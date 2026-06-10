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
use lvz_protocol::{ChatRequest, Event, Knobs, Message, Provider};
use lvz_tools::ToolRegistry;
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
}

#[derive(Copy, Clone, PartialEq, Eq, ValueEnum)]
enum ProviderKind {
    Xai,
    Anthropic,
}

impl ProviderKind {
    fn default_model(self) -> &'static str {
        match self {
            ProviderKind::Xai => "grok-4",
            ProviderKind::Anthropic => "claude-sonnet-4-6",
        }
    }

    fn build(self) -> Result<Arc<dyn Provider>, lvz_protocol::ProviderError> {
        Ok(match self {
            ProviderKind::Xai => Arc::new(XaiProvider::from_env()?),
            ProviderKind::Anthropic => Arc::new(AnthropicProvider::from_env()?),
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

    let provider = cli.provider.build()?;
    let model = cli
        .model
        .clone()
        .unwrap_or_else(|| cli.provider.default_model().to_string());
    let mut renderer = Renderer::new();

    if cli.agent {
        let mut config = AgentConfig::default().with_model(model);
        config.max_tokens = cli.max_tokens;
        if let Some(budget) = cli.budget {
            config = config.with_budget(budget);
        }
        if let Some(system) = cli.system {
            config.system = system;
        }
        if let Some(summary_model) = cli.summary_model {
            config = config.with_summary_model(summary_model);
        }
        let mut agent = Agent::new(provider, ToolRegistry::with_builtins(), config);
        if let Some(compact_after) = cli.compact_after {
            // A fixed-knob tuner overriding only the compaction trigger (§6.3).
            agent = agent.with_tuner(Arc::new(FixedTuner(Knobs {
                compact_after,
                ..Knobs::default()
            })));
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
