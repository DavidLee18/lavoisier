//! `lavoisier` — the CLI gateway (`RECIPE.md` §4, §9 M1–M4).
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
use lvz_gw_http::{GatewayConfig, HttpGateway};
use lvz_gw_matrix::MatrixGateway;
use lvz_memory::{InMemoryStore, SessionAgent};
use lvz_protocol::{
    AgentHandle, ChatRequest, Event, Gateway, Knobs, Message, Outcome, Provider, TaskContext,
    TaskTelemetry, TelemetrySink, Tuner,
};
use lvz_tools::ToolRegistry;
use lvz_tune::{BayesTuner, LearningTuner, PersistableTuner, TuneConfig};
use lvz_xai::XaiProvider;
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

    /// Which provider to use.
    #[arg(long, value_enum, env = "LVZ_PROVIDER", default_value_t = ProviderKind::Xai)]
    provider: ProviderKind,

    /// Model id. Defaults to a provider-appropriate model when unset.
    #[arg(long, env = "LVZ_MODEL")]
    model: Option<String>,

    /// Maximum tokens to generate per turn.
    #[arg(long, default_value_t = 2048)]
    max_tokens: u32,

    /// Optional system prompt (overrides the agent's default in --agent mode).
    #[arg(long)]
    system: Option<String>,

    /// Sampling temperature (provider default if unset). Ignored in --agent mode.
    #[arg(long)]
    temperature: Option<f32>,

    /// Thinking effort for the Google provider (`--provider google`): a level keyword
    /// (`low`/`high`/`dynamic`, Gemini 3) or a numeric token budget (Gemini 2.5). E.g. `--thinking
    /// high` to match the public Dirac refactor suite. Ignored by other providers.
    #[arg(long, value_name = "LEVEL", env = "GOOGLE_THINKING")]
    thinking: Option<String>,

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

    /// Enable adaptive token optimisation (ATO, experimental): an online tuner that learns
    /// per-archetype knob settings from realised outcomes (most useful in a long-running
    /// `--serve` process). Pair with `--verify-cmd` for a real quality-gated success signal,
    /// and `--tune-state` to persist what it learns across restarts (§6.6, `docs/ATO.md`).
    #[arg(long)]
    tune: bool,

    /// Use the experimental **Bayesian** (Thompson-sampling) ATO tuner instead of the ε-greedy
    /// hill-climb (`docs/ATO.md` §10). Each knob vector carries a Beta posterior over success and
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

    /// Enable the experimental, **unsound** skeleton-radius counterfactual (`docs/ATO.md` §6):
    /// after each task, estimate what smaller --tune skeleton radii would have cost and credit
    /// them with the realised success bit (optimistically — it can't prove less context wouldn't
    /// have failed). Off by default; only meaningful with `--tune`. The truncate counterfactual
    /// (exact, sound) is always on and needs no flag.
    #[arg(long)]
    radius_counterfactual: bool,

    /// Print a per-task telemetry line to stderr after an `--agent` run (tokens, cache-hit rate,
    /// round-trips, success, latency, chosen knobs) — the one-shot equivalent of the gateway's
    /// `/metrics` (`RECIPE.md` §6.4).
    #[arg(long)]
    telemetry: bool,

    /// Classify the task archetype with a model call instead of the free keyword heuristic
    /// (`RECIPE.md` §6.3). Costs one extra tool-less round-trip (routed to --summary-model when
    /// set); falls back to the heuristic on failure. Mainly useful paired with `--tune`.
    #[arg(long)]
    classify_with_model: bool,

    /// Inject a cache-aware repo-skeleton prefix (`RECIPE.md` §6.1) bounded to this many estimated
    /// tokens (--agent/--serve): a tree-sitter outline of every source file in the working dir,
    /// built once and placed in the cached prompt prefix so the model sees whole-repo structure
    /// without per-task reads. Most valuable on a caching provider (Anthropic) and a long-running
    /// `--serve`; on a non-caching provider it still adds the skeleton but without amortisation.
    #[arg(long, value_name = "TOKENS")]
    repo_skeleton: Option<usize>,
}

#[derive(Copy, Clone, PartialEq, Eq, ValueEnum)]
enum ProviderKind {
    Xai,
    Anthropic,
    /// Google Gemini (native Generative Language API). Enables same-model benchmarking vs. agents
    /// that run on `gemini-3-flash-preview` (see `docs/BENCHMARKS.md`).
    Google,
    /// Rides Claude Code `claude -p` (subscription, no caching) — personal/low-volume only (§8).
    ClaudeCli,
}

impl ProviderKind {
    fn default_model(self) -> &'static str {
        match self {
            ProviderKind::Xai => "grok-4",
            ProviderKind::Anthropic => "claude-sonnet-4-6",
            ProviderKind::Google => "gemini-3-flash-preview",
            ProviderKind::ClaudeCli => "sonnet",
        }
    }

    fn build(
        self,
        thinking: Option<&str>,
    ) -> Result<Arc<dyn Provider>, lvz_protocol::ProviderError> {
        Ok(match self {
            ProviderKind::Xai => Arc::new(XaiProvider::from_env()?),
            ProviderKind::Anthropic => Arc::new(AnthropicProvider::from_env()?),
            ProviderKind::Google => {
                let mut p = GoogleProvider::from_env()?;
                if let Some(t) = thinking {
                    p = p.with_thinking(t);
                }
                Arc::new(p)
            }
            ProviderKind::ClaudeCli => Arc::new(ClaudeCliProvider::from_env()?),
        })
    }
}

#[tokio::main]
async fn main() -> ExitCode {
    match run().await {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("lavoisier: error: {e}");
            ExitCode::FAILURE
        }
    }
}

async fn run() -> Result<(), Box<dyn std::error::Error>> {
    let cli = Cli::parse();

    let provider = cli.provider.build(cli.thinking.as_deref())?;
    let model = cli
        .model
        .clone()
        .unwrap_or_else(|| cli.provider.default_model().to_string());

    // Gateway mode: run the HTTP/WebSocket server over the shared agent and never return until
    // shutdown. No prompt is consumed.
    if let Some(addr) = cli.serve.clone() {
        // Wrap the agent in process-local session memory so each `session` continues its own
        // conversation across turns (RECIPE §7.3).
        let inner = Arc::new(build_agent(provider, model, &cli));
        let agent: Arc<dyn AgentHandle> =
            Arc::new(SessionAgent::new(inner, Arc::new(InMemoryStore::new())));

        let mut gw_config = GatewayConfig::default();
        if !cli.api_key.is_empty() {
            gw_config = gw_config.with_api_keys(cli.api_key.clone());
        }
        if let Some(n) = cli.rate_limit {
            gw_config = gw_config.with_rate_limit(n, std::time::Duration::from_secs(60));
        }
        let gateway = Arc::new(HttpGateway::bind(&addr)?.with_config(gw_config));

        let auth = if cli.api_key.is_empty() {
            "open"
        } else {
            "API-key required"
        };
        eprintln!(
            "lavoisier: HTTP gateway listening on http://{addr} ({auth}; POST /v1/turns, GET /v1/ws)"
        );
        gateway.serve(agent).await?;
        return Ok(());
    }

    // Matrix gateway mode: drive the shared agent from a homeserver, one room per session.
    if cli.serve_matrix {
        let inner = Arc::new(build_agent(provider, model, &cli));
        let agent: Arc<dyn AgentHandle> =
            Arc::new(SessionAgent::new(inner, Arc::new(InMemoryStore::new())));
        let gateway = Arc::new(MatrixGateway::from_env()?);
        gateway.serve(agent).await?;
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
        let mut agent = build_agent(provider, model, &cli);
        if cli.telemetry {
            agent = agent.with_telemetry(Arc::new(StderrTelemetry));
        }
        let mut stream = agent.run(prompt);
        while let Some(event) = stream.next().await {
            renderer.handle(event?)?;
        }
    } else {
        let mut req = ChatRequest::new(model)
            .max_tokens(cli.max_tokens)
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

/// Build the tool-using [`Agent`] from the CLI config. Shared by `--agent` (one-shot) and
/// `--serve` (gateway) so both drive an identically-configured agent core.
fn build_agent(provider: Arc<dyn Provider>, model: String, cli: &Cli) -> Agent {
    let mut config = AgentConfig::default().with_model(model);
    config.max_tokens = cli.max_tokens;
    if let Some(budget) = cli.budget {
        config = config.with_budget(budget);
    }
    if let Some(system) = &cli.system {
        config.system = system.clone();
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
    let mut agent = Agent::new(provider, ToolRegistry::with_builtins(), config);
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
/// process restarts (`docs/ATO.md` §10 profile persistence). Selected by `--tune-state <path>`.
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
            "[telemetry] archetype={:?} model={} tokens={} (in={} out={} cache_read={} cache_creation={}) \
cache_hit={:.0}% round_trips={} success={} elapsed={}ms radius={} truncate={} compact_after={} batch={}",
            t.archetype,
            t.model,
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
