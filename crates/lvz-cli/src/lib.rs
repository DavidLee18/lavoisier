//! `lavoisier` — the CLI gateway (§4, §9 M1–M4).
//!
//! Two modes over the same plumbing:
//! - **ask** (default): one streaming turn, no tools — the M1–M3 path.
//! - **agent** (`--agent`): the M4 plan→act→observe loop with the filesystem + shell
//!   built-ins, so the model can actually inspect and edit the repo.
//!
//! Either way the provider is selectable (xAI OpenAI-compat or Anthropic native) and the
//! normalised [`Event`] stream is rendered to the terminal: answer text on stdout; thinking,
//! tool activity, usage, and stop reason on stderr.

use std::collections::HashMap;
use std::io::{Read, Stdout, Write};
use std::process::ExitCode;
use std::sync::Arc;

use clap::{Parser, ValueEnum};
use futures::StreamExt;
use lvz_agent::{Agent, AgentConfig, FixedTuner};
use lvz_anthropic::AnthropicProvider;
use lvz_claude_cli::ClaudeCliProvider;
use lvz_google::GoogleProvider;
use lvz_gw_cron::{CronGateway, CronJob};
use lvz_gw_http::{GatewayConfig, HttpGateway};
use lvz_gw_matrix::MatrixGateway;
use lvz_memory::SessionAgent;
use lvz_protocol::{
    AgentHandle, BatchProvider, ChatRequest, CostWeights, Event, Gateway, Knobs, Message, Outcome,
    Provider, TaskContext, TaskTelemetry, TelemetrySink, ThinkingLevel, Tuner,
};
use lvz_tools::{BatchEditTool, ToolRegistry};
use lvz_tune::{BayesTuner, LearningTuner, PersistableTuner, TuneConfig};
use lvz_xai::XaiProvider;

mod config;
use config::Config;
use std::path::PathBuf;

#[derive(Parser)]
#[command(
    name = "lavoisier",
    bin_name = "lavoisier",
    version,
    about = "Token-efficient CLI coding agent (M4: ask or --agent, xAI or Anthropic)"
)]
struct Cli {
    /// The prompt / task. Joined with spaces if multiple words; read from stdin if omitted.
    prompt: Vec<String>,

    /// Run the multi-step agent loop with filesystem + shell tools.
    #[arg(long)]
    agent: bool,

    /// Path to a TOML config file (defaults for most flags; CLI/env still win). Without it,
    /// `./lavoisier.toml` is auto-loaded if present. See `[provider]`/`[agent]`/`[memory]`/
    /// `[gateway]` sections.
    #[arg(long, value_name = "PATH")]
    config: Option<PathBuf>,

    /// Which provider to use (default `xai`; overridable via `[provider]` in the config file).
    #[arg(long, value_enum, env = "LVZ_PROVIDER")]
    provider: Option<ProviderKind>,

    /// Model id. Defaults to a provider-appropriate model when unset.
    #[arg(long, env = "LVZ_MODEL")]
    model: Option<String>,

    /// Maximum tokens to generate per turn (default 2048; overridable via `[agent] max_tokens`).
    #[arg(long)]
    max_tokens: Option<u32>,

    /// Optional system prompt (overrides the agent's default in --agent mode).
    #[arg(long)]
    system: Option<String>,

    /// Path to a persistent persona file (persona, standing instructions, priorities) layered
    /// **above** the operational system prompt — the agent keeps it in mind on every turn, and
    /// it sits in the cached prefix so it costs almost nothing to carry. Defaults to `./PERSONA.md`
    /// if present; `--no-persona` disables auto-loading. Use this to give a long-running gateway
    /// (HTTP/Matrix/cron) a stable identity and rules.
    #[arg(long, value_name = "PATH")]
    persona: Option<PathBuf>,

    /// Do not auto-load `./PERSONA.md`. (An explicit `--persona <PATH>` still loads.)
    #[arg(long)]
    no_persona: bool,

    /// Sampling temperature (provider default if unset). Ignored in --agent mode.
    #[arg(long)]
    temperature: Option<f32>,

    /// Thinking effort for the Google provider (`--provider google`): a level keyword
    /// (`low`/`high`/`dynamic`, Gemini 3) or a numeric token budget (Gemini 2.5). E.g. `--thinking
    /// high` to match the public Dirac refactor suite. Ignored by other providers.
    #[arg(long, value_name = "LEVEL", env = "GOOGLE_THINKING")]
    thinking: Option<String>,

    /// Normalised, cross-provider extended-thinking budget (`--agent` mode): `off`/`low`/`medium`/
    /// `high`. Forces that level every turn, overriding the per-archetype default (mechanical tasks
    /// think less) and the ATO tuner. Maps to each provider's economical equivalent; unset ⇒ the
    /// per-archetype default applies and ATO may tune it.
    #[arg(long, value_name = "LEVEL", value_enum)]
    thinking_budget: Option<ThinkingBudgetArg>,

    /// Total-task token budget (--agent mode); the run aborts if exceeded.
    #[arg(long)]
    budget: Option<u64>,

    /// Route history-compaction summaries to a cheaper model (--agent mode). Defaults to --model.
    #[arg(long)]
    summary_model: Option<String>,

    /// Compact conversation history once it exceeds this many estimated tokens (--agent mode).
    #[arg(long)]
    compact_after: Option<usize>,

    /// Soft per-request context-token ceiling (--agent mode); evict oldest tool output to fit.
    #[arg(long)]
    context_limit: Option<usize>,

    /// Max agent round-trips before giving up (--agent mode; default 12). Raise for large
    /// multi-file refactors that need many explore→edit turns.
    #[arg(long, value_name = "N")]
    max_steps: Option<usize>,

    /// In-loop verify (--agent mode): stop as soon as --verify-cmd passes after an edit turn,
    /// instead of waiting for the model to decide it's done. On by default; inert without
    /// --verify-cmd. Disable all convergence levers with --no-converge.
    #[arg(long)]
    in_loop_verify: bool,

    /// No-progress circuit-breaker (--agent mode): nudge after N edit-free turns, hard-stop after
    /// 2N. Defaults to N=8 (on); --no-converge disables it.
    #[arg(long, value_name = "N")]
    no_progress_limit: Option<usize>,

    /// Budget awareness (--agent mode): tell the model its turn/token budget each turn so it can
    /// wrap up before the ceiling. On by default; --no-converge disables it.
    #[arg(long)]
    budget_awareness: bool,

    /// Turn OFF the default convergence levers (--in-loop-verify / --no-progress-limit 8 /
    /// --budget-awareness). They only lower cost by making the agent loop self-terminate; this
    /// restores the raw "run until the model stops or hits --max-steps" behaviour for A/B baselines.
    #[arg(long)]
    no_converge: bool,

    /// **Accuracy lever, opt-in** (--agent mode): no-edit completion guard — don't let an edit task
    /// finish having changed no files (nudge it to act, bounded). Trades efficiency for completion,
    /// so it is OFF by default.
    #[arg(long)]
    require_edit: bool,

    /// **Accuracy lever, opt-in** (--agent mode): verify-and-fix — when finishing, if --verify-cmd
    /// fails, feed the failure back and keep fixing (bounded) instead of shipping an incomplete
    /// change. Needs --verify-cmd; trades efficiency for completeness, so it is OFF by default.
    #[arg(long)]
    verify_and_fix: bool,

    /// Cheap model to run the first turns on, escalating to --model after --escalate-after
    /// round-trips (--agent/--serve; §8 cost reduction, e.g. claude-haiku-4-5 → claude-sonnet-4-6).
    #[arg(long, value_name = "MODEL")]
    cheap_model: Option<String>,

    /// Round-trips on --cheap-model before escalating to --model (default 2).
    #[arg(long, value_name = "N")]
    escalate_after: Option<usize>,

    /// Smarter, more expensive advisor model that drafts a plan before the loop; the cheaper
    /// --model executor then carries it out (--agent/--serve; §8 advisor+executor split). The
    /// expensive model is paid for once, e.g. an Opus advisor planning for a Sonnet executor.
    #[arg(long, value_name = "MODEL")]
    advisor_model: Option<String>,

    /// Serve the agent as an HTTP/WebSocket gateway on this `host:port` (e.g. `127.0.0.1:8080`)
    /// instead of running a one-shot turn. Implies the agent tool loop. No prompt is required.
    #[arg(long, value_name = "ADDR", env = "LVZ_SERVE_ADDR")]
    serve: Option<String>,

    /// Require this API key on the gateway's protected routes (--serve; repeatable). Sent by
    /// clients as `Authorization: Bearer <key>`. If unset, the gateway is open. The
    /// `LVZ_API_KEYS` env var accepts a comma-separated list (for Secrets Manager injection).
    #[arg(
        long = "api-key",
        value_name = "KEY",
        env = "LVZ_API_KEYS",
        value_delimiter = ','
    )]
    api_key: Vec<String>,

    /// Per-principal request quota for the gateway (--serve): max requests per 60s window.
    #[arg(long, value_name = "N", env = "LVZ_RATE_LIMIT")]
    rate_limit: Option<u32>,

    /// Serve as a Matrix gateway (one room per session) instead of a one-shot turn. Reads
    /// `MATRIX_HOMESERVER`, `MATRIX_USER`, `MATRIX_PASSWORD` from the environment.
    #[arg(long)]
    serve_matrix: bool,

    /// Don't auto-accept Matrix room invites (the gateway joins invited rooms by default). Can
    /// also be set via `[gateway] matrix_auto_join = false`.
    #[arg(long)]
    matrix_no_auto_join: bool,

    /// Schedule a recurring agent turn (in-process cron, UTC). The first **five** whitespace
    /// tokens are a standard cron schedule (`min hour dom month dow`); the rest is the prompt.
    /// Repeatable; each gets its own session (`cron-<n>`). Runs alongside `--serve`/`--serve-matrix`
    /// or standalone. Example: `--cron "*/30 9-17 * * 1-5 summarise new CI failures"`.
    #[arg(long = "cron", value_name = "SPEC")]
    cron: Vec<String>,

    /// Schedule recurring turns from a JSON file: an array of
    /// `{"schedule","session"?,"prompt"}` objects (UTC cron). Merged with any `--cron` flags.
    #[arg(long = "cron-file", value_name = "PATH")]
    cron_file: Option<PathBuf>,

    /// Enable adaptive token optimisation (ATO, experimental): an online tuner that learns
    /// per-archetype knob settings from realised outcomes (most useful in a long-running
    /// `--serve` process). Pair with `--verify-cmd` for a real quality-gated success signal,
    /// and `--tune-state` to persist what it learns across restarts (§6.6, `ATO.md`).
    #[arg(long)]
    tune: bool,

    /// Use the experimental **Bayesian** (Thompson-sampling) ATO tuner instead of the ε-greedy
    /// hill-climb (`ATO.md` §10). Each knob vector carries a Beta posterior over success and
    /// a Gaussian over cost; selection *samples* and picks the cheapest feasible draw, so posterior
    /// uncertainty drives exploration with no explicit ε. Implies `--tune`; takes precedence over it.
    /// Persists with `--tune-state` just like `--tune`.
    #[arg(long)]
    tune_bayes: bool,

    /// Shell command run after each task to gate ATO success (the real §6.6 signal): exit 0 ⇒
    /// the change is good, non-zero ⇒ failed. Runs in the working dir, e.g. `cargo test --quiet`.
    /// Without it, success falls back to the coarse "completed without error" flag.
    #[arg(long, value_name = "CMD")]
    verify_cmd: Option<String>,

    /// Persist the `--tune`/`--tune-bayes` learner's profiles to this JSON file: loaded at start
    /// (missing ⇒ cold), saved after each completed turn. Lets ATO keep what it learned across
    /// restarts.
    #[arg(long, value_name = "PATH")]
    tune_state: Option<String>,

    /// Per-observation decay in (0,1] for the `--tune` learner (non-stationarity): <1.0 makes
    /// recent outcomes weigh more so a stale optimum fades after a model/codebase shift. Default
    /// 1.0 (no decay). Keep it above 1−1/min_trials (≈0.67) so candidates can still become trusted.
    #[arg(long, value_name = "F")]
    tune_decay: Option<f64>,

    /// Enable the experimental, **unsound** skeleton-radius counterfactual (`ATO.md` §6):
    /// after each task, estimate what smaller --tune skeleton radii would have cost and credit
    /// them with the realised success bit (optimistically — it can't prove less context wouldn't
    /// have failed). Off by default; only meaningful with `--tune`. The truncate counterfactual
    /// (exact, sound) is always on and needs no flag.
    #[arg(long)]
    radius_counterfactual: bool,

    /// Radius-counterfactual **re-exploration risk** in `[0,1]` (`ATO.md` §10; default 0.5).
    /// Models the model's altered reasoning on a thinner skeleton: a smaller radius is credited with
    /// less of its raw input saving (a fraction is assumed clawed back re-acquiring stripped
    /// context), and a radius that strips most of the context isn't credited with success at all.
    /// `0` restores the old pure-saving estimate. Only used with `--radius-counterfactual`.
    #[arg(long)]
    radius_risk: Option<f64>,

    /// Print a per-task telemetry line to stderr after an `--agent` run (tokens, cache-hit rate,
    /// round-trips, success, latency, chosen knobs) — the one-shot equivalent of the gateway's
    /// `/metrics` (§6.4).
    #[arg(long)]
    telemetry: bool,

    /// Classify the task archetype with a model call instead of the free keyword heuristic
    /// (§6.3). Costs one extra tool-less round-trip (routed to --summary-model when
    /// set); falls back to the heuristic on failure. Mainly useful paired with `--tune`.
    #[arg(long)]
    classify_with_model: bool,

    /// Inject a cache-aware repo-skeleton prefix (§6.1) bounded to this many estimated
    /// tokens (--agent/--serve): a tree-sitter outline of every source file in the working dir,
    /// built once and placed in the cached prompt prefix so the model sees whole-repo structure
    /// without per-task reads. Most valuable on a caching provider (Anthropic) and a long-running
    /// `--serve`; on a non-caching provider it still adds the skeleton but without amortisation.
    #[arg(long, value_name = "TOKENS")]
    repo_skeleton: Option<usize>,

    /// Disable the `batch_edit` fan-out tool (--agent/--serve). By default the model is offered
    /// `batch_edit` whenever the provider has a discounted batch API (Anthropic / Google), letting
    /// it run a set of INDEPENDENT, mechanical per-file edits as one async batch (~50% token cost)
    /// instead of editing them one-by-one — Lavoisier is cost-first, so this is on by default. It
    /// trades latency for cost; pass `--no-batch-edit` to keep every edit in the interactive loop.
    /// (No effect on xAI / claude-cli, which have no batch API.)
    #[arg(long)]
    no_batch_edit: bool,
}

#[derive(Copy, Clone, PartialEq, Eq, Debug, ValueEnum)]
enum ProviderKind {
    Xai,
    Anthropic,
    /// Google Gemini (native Generative Language API). Enables same-model benchmarking vs. agents
    /// that run on `gemini-3-flash-preview` (see `bench/README.md`).
    Google,
    /// Rides Claude Code `claude -p` (subscription, no caching) — personal/low-volume only (§8).
    ClaudeCli,
}

/// CLI spelling of [`ThinkingLevel`] for `--thinking-budget`.
#[derive(Clone, Copy, Debug, ValueEnum)]
enum ThinkingBudgetArg {
    Off,
    Low,
    Medium,
    High,
}

impl From<ThinkingBudgetArg> for ThinkingLevel {
    fn from(a: ThinkingBudgetArg) -> Self {
        match a {
            ThinkingBudgetArg::Off => ThinkingLevel::Off,
            ThinkingBudgetArg::Low => ThinkingLevel::Low,
            ThinkingBudgetArg::Medium => ThinkingLevel::Medium,
            ThinkingBudgetArg::High => ThinkingLevel::High,
        }
    }
}

/// A built streaming provider, plus an optional handle to the same instance as a [`BatchProvider`]
/// (present only for providers with a discounted batch API: Anthropic / Google).
type BuiltProvider = (Arc<dyn Provider>, Option<Arc<dyn BatchProvider>>);

impl ProviderKind {
    fn default_model(self) -> &'static str {
        match self {
            ProviderKind::Xai => "grok-4",
            ProviderKind::Anthropic => "claude-sonnet-4-6",
            ProviderKind::Google => "gemini-3-flash-preview",
            ProviderKind::ClaudeCli => "sonnet",
        }
    }

    /// Provider-appropriate [`CostWeights`] for the cost-weighted budget/ATO objective. The
    /// non-caching claude-cli path uses flat weights (no cache classes to value).
    fn cost_weights(self) -> CostWeights {
        match self {
            ProviderKind::Xai => CostWeights::xai(),
            ProviderKind::Anthropic => CostWeights::anthropic(),
            ProviderKind::Google => CostWeights::google(),
            ProviderKind::ClaudeCli => CostWeights::flat(),
        }
    }

    /// Build the streaming [`Provider`] plus, when the provider offers a discounted batch API
    /// (Anthropic / Google), a [`BatchProvider`] handle to the *same* instance (used by the
    /// `batch_edit` fan-out tool). xAI / claude-cli have no batch API, so the handle is `None`.
    fn build(
        self,
        thinking: Option<&str>,
        extended_cache_ttl: bool,
    ) -> Result<BuiltProvider, lvz_protocol::ProviderError> {
        Ok(match self {
            ProviderKind::Xai => (Arc::new(XaiProvider::from_env()?), None),
            ProviderKind::Anthropic => {
                // A long-running gateway benefits from the 1-hour cache TTL on the immutable prefix
                // (it survives idle gaps between turns); one-shot runs keep the cheaper 5-min TTL.
                let p = Arc::new(
                    AnthropicProvider::from_env()?.with_extended_cache_ttl(extended_cache_ttl),
                );
                (p.clone(), Some(p))
            }
            ProviderKind::Google => {
                let mut p = GoogleProvider::from_env()?;
                if let Some(t) = thinking {
                    p = p.with_thinking(t);
                }
                let p = Arc::new(p);
                (p.clone(), Some(p))
            }
            ProviderKind::ClaudeCli => (Arc::new(ClaudeCliProvider::from_env()?), None),
        })
    }
}

/// Tool-authoring types, re-exported so a private downstream crate can implement [`Tool`] by
/// depending only on `lavoisier` (no direct `lvz-protocol` dependency needed).
pub use lvz_protocol::{Tool, ToolError, ToolOutput};

/// Run the full Lavoisier CLI, registering `extra_tools` into the agent alongside the built-ins.
/// This is the entry point for a private downstream binary that wants the entire CLI — flags,
/// config, gateways (HTTP/Matrix/cron), E2EE, persona — but with its own tools. The stock `lav`
/// binary calls this with an empty vec. Async; pair with your own runtime, or use [`main_with`].
pub async fn run_with(extra_tools: Vec<Arc<dyn Tool>>) -> Result<(), Box<dyn std::error::Error>> {
    run(extra_tools).await
}

/// Build a tokio runtime, run [`run_with`], and map the result to a process exit code (errors are
/// printed to stderr). Call this straight from `fn main` in a downstream binary:
///
/// ```no_run
/// use std::sync::Arc;
/// fn main() -> std::process::ExitCode {
///     lavoisier::main_with(vec![/* Arc::new(MyTool), ... */])
/// }
/// ```
pub fn main_with(extra_tools: Vec<Arc<dyn Tool>>) -> ExitCode {
    let runtime = match tokio::runtime::Runtime::new() {
        Ok(rt) => rt,
        Err(e) => {
            eprintln!("lavoisier: error: {e}");
            return ExitCode::FAILURE;
        }
    };
    match runtime.block_on(run_with(extra_tools)) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("lavoisier: error: {e}");
            ExitCode::FAILURE
        }
    }
}

async fn run(extra_tools: Vec<Arc<dyn Tool>>) -> Result<(), Box<dyn std::error::Error>> {
    let mut cli = Cli::parse();

    // Load the TOML config (explicit --config, else ./lavoisier.toml) and fill any flag the user
    // left unset — CLI/env always wins. Done before anything reads `cli`.
    let config = Config::load(cli.config.as_deref())?;
    config.apply_to(&mut cli);
    let provider_kind = cli.provider.unwrap_or(ProviderKind::Xai);

    // Cron jobs (in-process scheduler) can run standalone or alongside HTTP/Matrix.
    let cron_jobs = build_cron_jobs(&cli)?;

    // Long-running gateways (HTTP/Matrix/cron) get the 1-hour cache TTL on the immutable prefix.
    let serving = cli.serve.is_some() || cli.serve_matrix || !cron_jobs.is_empty();
    let (provider, batch_provider) = provider_kind.build(cli.thinking.as_deref(), serving)?;
    let model = cli
        .model
        .clone()
        .unwrap_or_else(|| provider_kind.default_model().to_string());

    // Gateway mode: build the shared agent once — wrapped in process-local session memory so each
    // `session` continues across turns (§7.3) — then run every active gateway (HTTP, Matrix, cron)
    // concurrently until shutdown. No prompt is consumed.
    if serving {
        let store = config.build_session_store()?;
        let inner = Arc::new(build_agent(
            provider,
            batch_provider,
            model,
            &cli,
            &extra_tools,
        ));
        let agent: Arc<dyn AgentHandle> = Arc::new(SessionAgent::new(inner, store));

        let mut gateways: Vec<Arc<dyn Gateway>> = Vec::new();

        if let Some(addr) = cli.serve.clone() {
            let mut gw_config = GatewayConfig::default();
            if !cli.api_key.is_empty() {
                gw_config = gw_config.with_api_keys(cli.api_key.clone());
            }
            if let Some(n) = cli.rate_limit {
                gw_config = gw_config.with_rate_limit(n, std::time::Duration::from_secs(60));
            }
            let auth = if cli.api_key.is_empty() {
                "open"
            } else {
                "API-key required"
            };
            eprintln!(
                "lavoisier: HTTP gateway listening on http://{addr} ({auth}; POST /v1/turns, GET /v1/ws)"
            );
            gateways.push(Arc::new(HttpGateway::bind(&addr)?.with_config(gw_config)));
        }

        if cli.serve_matrix {
            // Auto-join invites by default; disabled by `--matrix-no-auto-join` or the config key.
            let auto_join =
                !cli.matrix_no_auto_join && config.gateway.matrix_auto_join.unwrap_or(true);
            gateways.push(Arc::new(
                MatrixGateway::from_env()?.with_auto_join(auto_join),
            ));
        }

        if !cron_jobs.is_empty() {
            eprintln!("lavoisier: cron gateway with {} job(s)", cron_jobs.len());
            gateways.push(Arc::new(CronGateway::new(cron_jobs)));
        }

        // Run them together; the process lives until a serve loop exits or errors.
        let runs = gateways.into_iter().map(|gw| gw.serve(agent.clone()));
        for res in futures::future::join_all(runs).await {
            res?;
        }
        return Ok(());
    }

    let prompt = if cli.prompt.is_empty() {
        let mut buf = String::new();
        std::io::stdin().read_to_string(&mut buf)?;
        buf.trim().to_string()
    } else {
        cli.prompt.join(" ")
    };
    if prompt.is_empty() {
        return Err("empty prompt (pass it as an argument or on stdin)".into());
    }

    let mut renderer = Renderer::new();

    if cli.agent {
        let mut agent = build_agent(provider, batch_provider, model, &cli, &extra_tools);
        if cli.telemetry {
            agent = agent.with_telemetry(Arc::new(StderrTelemetry));
        }
        let mut stream = agent.run(prompt);
        while let Some(event) = stream.next().await {
            renderer.handle(event?)?;
        }
    } else {
        let mut req = ChatRequest::new(model)
            .max_tokens(cli.max_tokens.unwrap_or(2048))
            .push(Message::user(prompt));
        if let Some(system) = cli.system {
            req = req.system(system);
        }
        if let Some(t) = cli.temperature {
            req = req.temperature(t);
        }
        let mut stream = provider.stream(req).await?;
        while let Some(event) = stream.next().await {
            renderer.handle(event?)?;
        }
    }

    Ok(())
}

/// Collect cron jobs from `--cron-file` (parsed first) then any `--cron` quick specs. CLI
/// specs are indexed after the file jobs so their default `cron-<n>` sessions don't collide.
fn build_cron_jobs(cli: &Cli) -> Result<Vec<CronJob>, Box<dyn std::error::Error>> {
    let mut jobs = Vec::new();
    if let Some(path) = &cli.cron_file {
        let text = std::fs::read_to_string(path)
            .map_err(|e| format!("reading {}: {e}", path.display()))?;
        jobs.extend(CronJob::parse_file(&text)?);
    }
    let base = jobs.len();
    for (i, spec) in cli.cron.iter().enumerate() {
        jobs.push(CronJob::parse_cli(spec, base + i)?);
    }
    Ok(jobs)
}

/// Load the persistent persona prompt: an explicit `--persona <PATH>`, else `./PERSONA.md` if
/// present (unless `--no-persona`). A missing explicit path is a hard error; a missing default is
/// silent.
fn load_persona(cli: &Cli) -> Option<String> {
    let path = match (&cli.persona, cli.no_persona) {
        (Some(p), _) => p.clone(),
        (None, true) => return None,
        (None, false) => {
            let default = PathBuf::from("PERSONA.md");
            if !default.is_file() {
                return None;
            }
            default
        }
    };
    match std::fs::read_to_string(&path) {
        Ok(s) if !s.trim().is_empty() => {
            eprintln!("lavoisier: loaded persona from {}", path.display());
            Some(s.trim().to_string())
        }
        Ok(_) => None,
        Err(e) => {
            // Only surface an error for an explicitly requested file.
            if cli.persona.is_some() {
                eprintln!(
                    "lavoisier: WARNING could not read --persona {}: {e}",
                    path.display()
                );
            }
            None
        }
    }
}

/// Build the tool-using [`Agent`] from the CLI config. Shared by `--agent` (one-shot) and
/// `--serve` (gateway) so both drive an identically-configured agent core.
fn build_agent(
    provider: Arc<dyn Provider>,
    batch_provider: Option<Arc<dyn BatchProvider>>,
    model: String,
    cli: &Cli,
    extra_tools: &[Arc<dyn Tool>],
) -> Agent {
    let editor_model = model.clone();
    let mut config = AgentConfig::default()
        .with_model(model)
        .with_cost_weights(cli.provider.unwrap_or(ProviderKind::Xai).cost_weights());
    config.max_tokens = cli.max_tokens.unwrap_or(2048);
    if let Some(max_steps) = cli.max_steps {
        config.max_steps = max_steps;
    }
    // Convergence levers are ON by default (they only lower cost — they make the loop stop instead
    // of riding to the turn ceiling). `--no-converge` opts out; the explicit positive flags still
    // force-enable. `in_loop_verify` is inert without `--verify-cmd`, so defaulting it on is safe.
    let converge = !cli.no_converge;
    config = config.with_in_loop_verify(cli.in_loop_verify || converge);
    let no_progress = cli.no_progress_limit.or(converge.then_some(8));
    if let Some(n) = no_progress {
        config = config.with_no_progress_limit(n);
    }
    config = config.with_budget_awareness(cli.budget_awareness || converge);
    // Accuracy levers stay opt-in (efficiency-by-default): only on when explicitly requested.
    config = config.with_require_edit(cli.require_edit);
    config = config.with_verify_and_fix(cli.verify_and_fix);
    if let Some(tb) = cli.thinking_budget {
        config = config.with_forced_thinking(tb.into());
    }
    if let Some(budget) = cli.budget {
        config = config.with_budget(budget);
    }
    if let Some(system) = &cli.system {
        config.system = system.clone();
    }
    // Layer the persistent persona (persona/priorities) ABOVE the operational base prompt, so the
    // agent keeps standing instructions in mind while retaining the tool/efficiency steering.
    if let Some(persona) = load_persona(cli) {
        config.system = format!(
            "{persona}\n\n--- (operating instructions follow) ---\n\n{}",
            config.system
        );
    }
    if let Some(summary_model) = &cli.summary_model {
        config = config.with_summary_model(summary_model.clone());
    }
    if let Some(context_limit) = cli.context_limit {
        config = config.with_context_limit(context_limit);
    }
    if let Some(cheap_model) = &cli.cheap_model {
        config = config.with_cheap_model(cheap_model.clone());
    }
    if let Some(escalate_after) = cli.escalate_after {
        config = config.with_escalate_after(escalate_after);
    }
    if let Some(advisor_model) = &cli.advisor_model {
        config = config.with_advisor_model(advisor_model.clone());
    }
    if let Some(verify_cmd) = &cli.verify_cmd {
        config = config.with_verify_command(verify_cmd.clone());
    }
    if cli.radius_counterfactual {
        config = config.with_radius_counterfactual(true);
    }
    if let Some(risk) = cli.radius_risk {
        config = config.with_radius_risk(risk);
    }
    if cli.classify_with_model {
        config = config.with_model_classification(true);
    }
    if let Some(budget) = cli.repo_skeleton {
        config = config.with_repo_skeleton(budget);
    }
    // Profile the working directory so the tuner sees a real repo shape (§6.6).
    if let Ok(cwd) = std::env::current_dir() {
        config = config.with_repo_root(cwd);
    }
    let mut registry = ToolRegistry::with_builtins();
    // `batch_edit` fan-out tool: on by default (Lavoisier is cost-first), registered whenever the
    // provider has a batch API. Lets the model run independent mechanical edits as one discounted
    // async batch instead of looping over them. `--no-batch-edit` opts out; providers without a
    // batch API (xAI/claude-cli) simply never get it.
    if !cli.no_batch_edit {
        if let Some(batch) = batch_provider {
            registry.register(Arc::new(BatchEditTool::new(batch, editor_model)));
        }
    }
    // Caller-provided tools (e.g. a private downstream binary via `run_with`/`main_with`).
    for tool in extra_tools {
        registry.register(tool.clone());
    }
    let mut agent = Agent::new(provider, registry, config);
    if cli.tune_bayes {
        // The experimental Bayesian (Thompson-sampling) learner; takes precedence over the
        // ε-greedy `--tune` and a fixed `--compact-after`. Persists like `--tune` when a
        // `--tune-state` path is given (load prior posteriors, save after each turn).
        let mut tune_cfg = TuneConfig::default();
        if let Some(decay) = cli.tune_decay {
            tune_cfg.decay = decay;
        }
        let tuner: Arc<dyn Tuner> = match &cli.tune_state {
            Some(path) => {
                let inner = BayesTuner::load(path, tune_cfg).unwrap_or_else(|e| {
                    eprintln!("tune-state: could not load {path}: {e}; starting cold");
                    BayesTuner::with_config(tune_cfg)
                });
                PersistentTuner::new(Arc::new(inner), path).into_arc()
            }
            None => Arc::new(BayesTuner::with_config(tune_cfg)),
        };
        agent = agent.with_tuner(tuner);
    } else if cli.tune {
        // The online ATO learner (§6.6); takes precedence over a fixed --compact-after. When a
        // state path is given, load prior profiles (missing ⇒ cold) and persist on drop.
        let mut tune_cfg = TuneConfig::default();
        if let Some(decay) = cli.tune_decay {
            tune_cfg.decay = decay;
        }
        let tuner: Arc<dyn Tuner> = match &cli.tune_state {
            Some(path) => {
                let inner = LearningTuner::load(path, tune_cfg).unwrap_or_else(|e| {
                    eprintln!("tune-state: could not load {path}: {e}; starting cold");
                    LearningTuner::with_config(tune_cfg)
                });
                PersistentTuner::new(Arc::new(inner), path).into_arc()
            }
            None => Arc::new(LearningTuner::with_config(tune_cfg)),
        };
        agent = agent.with_tuner(tuner);
    } else if let Some(compact_after) = cli.compact_after {
        // A fixed-knob tuner overriding only the compaction trigger (§6.3).
        agent = agent.with_tuner(Arc::new(FixedTuner(Knobs {
            compact_after,
            ..Knobs::default()
        })));
    }
    agent
}

/// Wraps any [`PersistableTuner`] (the ε-greedy [`LearningTuner`] or the Bayesian [`BayesTuner`])
/// to snapshot its profiles to disk after every observation, so what ATO learns survives across
/// process restarts (`ATO.md` §10 profile persistence). Selected by `--tune-state <path>`.
struct PersistentTuner {
    inner: Arc<dyn PersistableTuner>,
    path: PathBuf,
}

impl PersistentTuner {
    fn new(inner: Arc<dyn PersistableTuner>, path: &str) -> Self {
        Self {
            inner,
            path: path.into(),
        }
    }

    fn into_arc(self) -> Arc<dyn Tuner> {
        Arc::new(self)
    }
}

impl Tuner for PersistentTuner {
    fn select(&self, ctx: &TaskContext) -> Knobs {
        self.inner.select(ctx)
    }

    fn observe(&self, ctx: &TaskContext, used: &Knobs, out: &Outcome) {
        self.inner.observe(ctx, used, out);
        if let Err(e) = self.inner.persist(&self.path) {
            eprintln!("tune-state: could not save {}: {e}", self.path.display());
        }
    }
}

/// A [`TelemetrySink`] that prints one per-task summary line to stderr (the one-shot equivalent
/// of the gateway's `/metrics`). Installed by `--telemetry` on the `--agent` path.
struct StderrTelemetry;

impl TelemetrySink for StderrTelemetry {
    fn record(&self, t: &TaskTelemetry) {
        eprintln!(
            "[telemetry] archetype={:?} model={} cost={} tokens={} (in={} out={} cache_read={} cache_creation={}) \
cache_hit={:.0}% round_trips={} success={} elapsed={}ms radius={} truncate={} compact_after={} batch={}",
            t.archetype,
            t.model,
            t.cost(),
            t.usage.total(),
            t.usage.input_tokens,
            t.usage.output_tokens,
            t.usage.cache_read_tokens,
            t.usage.cache_creation_tokens,
            t.cache_hit_rate() * 100.0,
            t.round_trips,
            t.success,
            t.elapsed.as_millis(),
            t.knobs.skeleton_radius,
            t.knobs.truncate_bytes,
            t.knobs.compact_after,
            t.knobs.batch_width,
        );
    }
}

/// Renders the normalised event stream to the terminal, keeping answer text (stdout) cleanly
/// separated from diagnostics (stderr).
struct Renderer {
    stdout: Stdout,
    wrote_text: bool,
    tool_args: HashMap<String, String>,
}

impl Renderer {
    fn new() -> Self {
        Self {
            stdout: std::io::stdout(),
            wrote_text: false,
            tool_args: HashMap::new(),
        }
    }

    fn handle(&mut self, event: Event) -> std::io::Result<()> {
        match event {
            Event::TextDelta(text) => {
                let mut lock = self.stdout.lock();
                write!(lock, "{text}")?;
                lock.flush()?;
                self.wrote_text = true;
            }
            Event::Thinking(text) => eprint!("{text}"),
            Event::ToolUseStart { id, name } => {
                eprintln!("\n[tool] {name}");
                self.tool_args.insert(id, String::new());
            }
            Event::ToolUseDelta { id, json } => {
                self.tool_args.entry(id).or_default().push_str(&json);
            }
            Event::ToolUseEnd { id } => {
                if let Some(args) = self.tool_args.remove(&id) {
                    if !args.trim().is_empty() {
                        eprintln!("[tool args] {args}");
                    }
                }
            }
            Event::ServerToolUse { name, .. } => eprintln!("\n[server tool] {name}"),
            Event::ServerToolResult { .. } => eprintln!("[server tool result]"),
            Event::Citation { cited_text, source } => {
                eprintln!("[citation: {source}] {cited_text}")
            }
            Event::Usage(usage) => {
                eprintln!(
                    "\n[usage] in={} out={} cache_read={} cache_creation={}",
                    usage.input_tokens,
                    usage.output_tokens,
                    usage.cache_read_tokens,
                    usage.cache_creation_tokens,
                );
            }
            Event::Done(reason) => {
                if self.wrote_text {
                    println!();
                    self.wrote_text = false;
                }
                eprintln!("[done] {reason:?}");
            }
        }
        Ok(())
    }
}
