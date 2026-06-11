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
use lvz_gw_http::{GatewayConfig, HttpGateway};
use lvz_gw_matrix::MatrixGateway;
use lvz_memory::{InMemoryStore, SessionAgent};
use lvz_protocol::{AgentHandle, ChatRequest, Event, Gateway, Knobs, Message, Provider};
use lvz_tools::ToolRegistry;
use lvz_tune::LearningTuner;
use lvz_xai::XaiProvider;

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

    /// Cheap advisor model that drafts a plan before the loop to seed the executor (--agent/
    /// --serve; §8 advisor+executor split). Reduces the strong model's exploration turns.
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
    /// `--serve` process). The success signal is the agent's coarse "completed without error"
    /// flag, not a verified quality gate — keep opt-in until a real signal is wired (§6.6).
    #[arg(long)]
    tune: bool,
}

#[derive(Copy, Clone, PartialEq, Eq, ValueEnum)]
enum ProviderKind {
    Xai,
    Anthropic,
    /// Rides Claude Code `claude -p` (subscription, no caching) — personal/low-volume only (§8).
    ClaudeCli,
}

impl ProviderKind {
    fn default_model(self) -> &'static str {
        match self {
            ProviderKind::Xai => "grok-4",
            ProviderKind::Anthropic => "claude-sonnet-4-6",
            ProviderKind::ClaudeCli => "sonnet",
        }
    }

    fn build(self) -> Result<Arc<dyn Provider>, lvz_protocol::ProviderError> {
        Ok(match self {
            ProviderKind::Xai => Arc::new(XaiProvider::from_env()?),
            ProviderKind::Anthropic => Arc::new(AnthropicProvider::from_env()?),
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

    let provider = cli.provider.build()?;
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
        let agent = build_agent(provider, model, &cli);
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
    // Profile the working directory so the tuner sees a real repo shape (§6.6).
    if let Ok(cwd) = std::env::current_dir() {
        config = config.with_repo_root(cwd);
    }
    let mut agent = Agent::new(provider, ToolRegistry::with_builtins(), config);
    if cli.tune {
        // The online ATO learner (§6.6); takes precedence over a fixed --compact-after.
        agent = agent.with_tuner(Arc::new(LearningTuner::new()));
    } else if let Some(compact_after) = cli.compact_after {
        // A fixed-knob tuner overriding only the compaction trigger (§6.3).
        agent = agent.with_tuner(Arc::new(FixedTuner(Knobs {
            compact_after,
            ..Knobs::default()
        })));
    }
    agent
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
