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

#![warn(missing_docs)]

use std::collections::HashMap;
use std::io::{IsTerminal, Read, Stdout, Write};
use std::process::ExitCode;
use std::sync::Arc;

use clap::{Parser, ValueEnum};
use futures::StreamExt;
use lvz_agent::{Agent, AgentConfig, FixedTuner};
use lvz_anthropic::AnthropicProvider;
use lvz_claude_cli::ClaudeCliProvider;
use lvz_google::GoogleProvider;
use lvz_gw_a2a::A2aGateway;
use lvz_gw_acp::AcpGateway;
use lvz_gw_cron::{CronGateway, CronJob};
use lvz_gw_http::{GatewayConfig, HttpGateway};
use lvz_gw_matrix::MatrixGateway;
use lvz_gw_slack::SlackGateway;
use lvz_gw_tui::{ChannelGate, TuiGateway};
use lvz_legion::{Debater, Language, Panel};
use lvz_mcp::McpServerSpec;
use lvz_memory::SessionAgent;
use lvz_protocol::{
    AgentHandle, BatchProvider, ChatRequest, CostWeights, Deliberator, Event, Gateway, Knobs,
    Message, Outcome, Provider, ServerTool, TaskContext, TaskTelemetry, TelemetrySink,
    ThinkingLevel, Tuner,
};
use lvz_schedule::{
    ScheduleJob, ScheduleListTool, ScheduleRegistry, ScheduleRunTool, ScheduleStatusTool,
};
use lvz_tools::{BatchEditTool, ToolRegistry};
use lvz_tune::{BayesTuner, LearningTuner, PersistableTuner, TuneConfig};
use lvz_xai::{ResponsesTransport, XaiProvider};

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
    /// `[gateway]`/`[legion]`/`[log]` sections.
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
    /// (HTTP/Matrix/Slack/cron) a stable identity and rules.
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

    /// A **legion** council debater, `provider:model` (repeatable). Pass two or more: the models
    /// draft, critique each other, and a judge synthesises one agreed plan that seeds the agent
    /// before it acts (--agent/--serve). Supersedes --advisor-model. Each named provider needs its
    /// API key in the env. E.g. `--legion-debater anthropic:claude-opus-4-8 --legion-debater xai:grok-4`.
    #[arg(long = "legion-debater", value_name = "PROVIDER:MODEL")]
    legion_debater: Vec<ModelRef>,

    /// The legion judge, `provider:model`. Defaults to the first --legion-debater.
    #[arg(long = "legion-judge", value_name = "PROVIDER:MODEL")]
    legion_judge: Option<ModelRef>,

    /// A **fallback model**, `provider:model` (repeatable, ordered). If the primary model is
    /// unresponsive or errors *before streaming any output* for a round-trip (a connect timeout,
    /// an open error, or a stall/error before the first token), the agent transparently retries on
    /// the next fallback — so a slow or down provider doesn't hang the turn. Cross-provider is
    /// first-class; each named provider needs its API key in the env. Once a model fails it is
    /// skipped for the rest of the turn. E.g. `--fallback anthropic:claude-sonnet-4-6 --fallback google:gemini-3-flash-preview`.
    #[arg(long = "fallback", value_name = "PROVIDER:MODEL")]
    fallback: Vec<ModelRef>,

    /// Seconds a failed fallback-chain model stays demoted before it's re-probed (circuit breaker;
    /// default 60). A model that is unresponsive/errors is skipped from the start of subsequent
    /// turns for this long, so a persistently-down provider isn't re-tried every turn; after the
    /// cooldown it's tried again. `0` ⇒ re-probe every turn (demotion lasts only the current turn).
    #[arg(
        long = "fallback-cooldown",
        value_name = "SECONDS",
        env = "LVZ_FALLBACK_COOLDOWN"
    )]
    fallback_cooldown: Option<u64>,

    /// Critique rounds the legion runs after the initial draft (default 1; 0 = draft then judge).
    #[arg(long = "legion-rounds", value_name = "N", env = "LVZ_LEGION_ROUNDS")]
    legion_rounds: Option<usize>,

    /// Connect to an external **MCP** (Model Context Protocol) server and expose its tools as
    /// Lavoisier tools (repeatable). Each spec is `label: target`, where `target` is either a
    /// command to spawn (stdio transport) or an `http(s)://` URL. The tools are namespaced
    /// `<label>_<tool>` so they never shadow built-ins, and every frontend (CLI, gateways) gets
    /// them. E.g. `--mcp-server 'fs: npx -y @modelcontextprotocol/server-filesystem .'`. Also
    /// `[mcp] servers`.
    #[arg(long = "mcp-server", value_name = "LABEL:TARGET")]
    mcp_server: Vec<String>,

    /// Provider-run (server-side) tools to offer, comma-separated and repeatable:
    /// `web_search`, `web_fetch`, `code_execution`, `x_search`, `collections_search`,
    /// `url_context`. The *provider* runs these and returns results inline, so they cost no
    /// tool-loop round-trip — but they bill extra and each is provider-specific, so none are on by
    /// default. Names only: every parameterised tool takes its defaults here; the config file's
    /// `[[provider.server_tools]]` is where domain/handle/date filters go. Asking for a tool the
    /// chosen provider does not support fails the turn rather than being ignored.
    /// E.g. `--server-tools web_search,code_execution`.
    #[arg(long = "server-tools", value_name = "NAMES", value_delimiter = ',')]
    server_tools: Vec<ServerToolArg>,

    /// Refuse to start the Matrix gateway if E2EE cannot be initialised, instead of silently
    /// continuing in plaintext. Use in a deployment whose rooms are all encrypted: without it a bad
    /// `MATRIX_CRYPTO_STORE_KEY`, a crypto store at the wrong path, or a corrupt database leaves the
    /// bot running and apparently healthy while unable to read or write anything. Also
    /// `[gateway] matrix_require_e2ee`.
    #[arg(long = "require-e2ee", env = "LVZ_REQUIRE_E2EE")]
    require_e2ee: bool,

    /// Resolved provider-run tools: the `--server-tools` names expanded to their defaults when the
    /// flag was given, else the config file's `[[provider.server_tools]]` verbatim. Filled by
    /// `Config::apply_to`; not a flag itself, which is why the precedence rule lives in exactly one
    /// place.
    #[arg(skip)]
    resolved_server_tools: Vec<ServerTool>,

    /// Locale for the legion council's progress notices (POSIX form, e.g. `ko_KR.UTF-8`). Only
    /// `KO_KR` selects Korean; anything else — including unset — keeps them English. Falls back to
    /// the `LANG` env var.
    #[arg(long = "lang", value_name = "LOCALE", env = "LANG")]
    lang: Option<String>,

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
    /// `MATRIX_HOMESERVER` plus either `MATRIX_ACCESS_TOKEN` or (`MATRIX_USER` + `MATRIX_PASSWORD`).
    /// Optional: `MATRIX_DEVICE_ID`, `MATRIX_STATE_DIR` (stable identity + E2EE crypto store across
    /// restarts), `MATRIX_CRYPTO_STORE_KEY`, `MATRIX_ALLOWED_USERS`.
    #[arg(long)]
    serve_matrix: bool,

    /// Don't auto-accept Matrix room invites (the gateway joins invited rooms by default). Can
    /// also be set via `[gateway] matrix_auto_join = false`.
    #[arg(long)]
    matrix_no_auto_join: bool,

    /// Directory to download inbound Matrix media (images/files) into. Setting it **enables** media
    /// ingest: an engaged image/file message is fetched here and its local path handed to the agent
    /// so a tool can act on it. Unset ⇒ media messages are ignored. Env `MATRIX_MEDIA_DIR` or
    /// `[gateway] matrix_media_dir` also set it.
    #[arg(long, value_name = "DIR", env = "MATRIX_MEDIA_DIR")]
    matrix_media_dir: Option<PathBuf>,

    /// Serve as a Slack gateway (Socket Mode; one session per channel/thread) instead of a one-shot
    /// turn. Reads `SLACK_APP_TOKEN` (`xapp-…`) and `SLACK_BOT_TOKEN` (`xoxb-…`); optional
    /// `SLACK_ALLOWED_USERS` (comma-separated user ids). Runs alongside `--serve`/`--serve-matrix`.
    #[arg(long)]
    serve_slack: bool,

    /// Serve as an **A2A (Agent-to-Agent) server** on this `host:port` — an Agent Card at
    /// `/.well-known/agent-card.json` plus a JSON-RPC endpoint (`message/send`, `message/stream`,
    /// `tasks/get`) so other agents can delegate tasks to Lavoisier. Reuses `--api-key` for auth.
    /// Runs alongside the other gateways. Also `[gateway] serve_a2a`.
    #[arg(long = "serve-a2a", value_name = "ADDR", env = "LVZ_SERVE_A2A")]
    serve_a2a: Option<String>,

    /// Run as a **Zed Agent Client Protocol (ACP) agent** over **stdio** (JSON-RPC 2.0), so an
    /// ACP-capable editor (Zed, or Neovim via a bridge) can launch Lavoisier as a subprocess and
    /// drive the full tool loop from its agent panel. This takes over stdin/stdout (no bind address).
    /// Configure your editor to run `lav --acp`. Also `[gateway] acp`. (For agent-to-agent interop,
    /// use `--serve-a2a`.)
    #[arg(long = "acp")]
    acp: bool,

    /// Launch the interactive **inline terminal UI** — a scrollback-native REPL that drives the agent
    /// with streaming output, tool-call cards, and Claude-Code-style tool-approval prompts. Takes over
    /// the terminal (logs are redirected to `$LVZ_LOG_FILE` or suppressed so they don't corrupt the
    /// display). Intended standalone. Also `[gateway] tui`.
    #[arg(long = "tui")]
    tui: bool,

    /// With `--tui`, skip the tool-approval prompts and run every tool unattended (the default is
    /// Claude-Code-style: read-only tools run, mutating tools and shells ask first). Also
    /// `[gateway] tui_auto_approve`.
    #[arg(long = "tui-auto-approve")]
    tui_auto_approve: bool,

    /// Schedule a recurring agent turn (in-process cron, UTC). The first **five** whitespace
    /// tokens are a standard cron schedule (`min hour dom month dow`); the rest is the prompt.
    /// Repeatable; each gets its own session (`cron-<n>`). Runs alongside `--serve`/`--serve-matrix`
    /// or standalone. Example: `--cron "*/30 9-17 * * 1-5 summarise new CI failures"`.
    #[arg(long = "cron", value_name = "SPEC")]
    cron: Vec<String>,

    /// Schedule recurring turns from a JSON file: an array of
    /// `{"schedule","session"?,"prompt","retry_max"?,"retry_wait"?}` objects (UTC cron). Merged
    /// with any `--cron` flags. Per-job `retry_max`/`retry_wait` override the global defaults below.
    #[arg(long = "cron-file", value_name = "PATH")]
    cron_file: Option<PathBuf>,

    /// Default max retries after a *failed* cron fire (a rejected submit or a mid-turn stream
    /// error) before giving up and waiting for the next scheduled slot. `0` (default) ⇒ no retry.
    /// A per-job `retry_max` in `--cron-file` overrides this. Also `[gateway] cron_retry_max`.
    #[arg(long = "cron-retry-max", value_name = "N", env = "LVZ_CRON_RETRY_MAX")]
    cron_retry_max: Option<u32>,

    /// Seconds to wait between cron retries (fixed delay). A per-job `retry_wait` in `--cron-file`
    /// overrides this. Also settable via `[gateway] cron_retry_wait`.
    #[arg(
        long = "cron-retry-wait",
        value_name = "SECS",
        env = "LVZ_CRON_RETRY_WAIT"
    )]
    cron_retry_wait: Option<u64>,

    /// Run scheduled jobs **inside the Matrix gateway** from a JSON file: an array of
    /// `{"id","schedule","room"?,"session"?,"tool"+"args"|"prompt","retry_max"?,"retry_wait"?}`
    /// objects (UTC cron). A `tool` job invokes that tool directly — it runs unconditionally, with
    /// no model round-trip; a `prompt` job fires an agent turn. Every fire is reported to the room,
    /// and `schedule_list`/`schedule_status`/`schedule_run` let chat query and re-run jobs.
    /// Requires `--serve-matrix`. Also `[gateway] schedule_file`.
    #[arg(long = "schedule-file", value_name = "PATH")]
    schedule_file: Option<PathBuf>,

    /// Default Matrix room for schedule reports, for jobs that set no `room` of their own. Falls
    /// back to the home room (`MATRIX_HOME_ROOM`). Also `[gateway] schedule_room`.
    #[arg(long = "schedule-room", value_name = "ROOM", env = "LVZ_SCHEDULE_ROOM")]
    schedule_room: Option<String>,

    /// Default max retries after a *failed* scheduled fire before giving up and waiting for the
    /// next slot. `0` (default) ⇒ no retry. A per-job `retry_max` overrides this. Also
    /// `[gateway] schedule_retry_max`.
    #[arg(
        long = "schedule-retry-max",
        value_name = "N",
        env = "LVZ_SCHEDULE_RETRY_MAX"
    )]
    schedule_retry_max: Option<u32>,

    /// Seconds to wait between scheduled-job retries (fixed delay). A per-job `retry_wait`
    /// overrides this. Also settable via `[gateway] schedule_retry_wait`.
    #[arg(
        long = "schedule-retry-wait",
        value_name = "SECS",
        env = "LVZ_SCHEDULE_RETRY_WAIT"
    )]
    schedule_retry_wait: Option<u64>,

    /// Fallback polling budget (seconds) for a schedule tool that accepts long-running work and
    /// reports completion via a poll tool, but gives no estimate of its own. The scheduler gives up
    /// and reports a TIMEOUT at twice this, rather than holding the job's slot indefinitely. A
    /// tool's own `estimated_seconds` wins over it. Also `[gateway] schedule_pending_timeout`.
    #[arg(
        long = "schedule-pending-timeout",
        value_name = "SECS",
        env = "LVZ_SCHEDULE_PENDING_TIMEOUT"
    )]
    schedule_pending_timeout: Option<u64>,

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

    /// Filter for the structured `tracing` logs written to **stderr**. Accepts `RUST_LOG`-style
    /// directives, so it takes either a bare level (`info`, `debug`) or per-target rules
    /// (`lvz_gw_matrix=debug,warn`). Unset ⇒ our own crates log at `info` and everything else at
    /// `warn`, which keeps the operator output printing as it always has without dragging in
    /// dependency chatter (tonic/hyper emit through the same facade). Use this to go quieter
    /// (`--log-level warn`), louder (`debug`), or to target one subsystem. A malformed filter is
    /// reported and the default is used. Also settable via `[log] level`.
    #[arg(long = "log-level", value_name = "FILTER", env = "LVZ_LOG_LEVEL")]
    log_level: Option<String>,

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

/// Which model backend to drive. Public because [`ModelRef`] names one.
#[derive(Copy, Clone, PartialEq, Eq, Debug, ValueEnum)]
pub enum ProviderKind {
    /// xAI over `/chat/completions` (or native gRPC via `XAI_TRANSPORT=grpc`).
    Xai,
    /// xAI's **Responses API** (`/v1/responses`) — the Agent-Tools transport, and the *only* xAI
    /// route to provider-run tools: Live Search on `chat/completions` has been 410 Gone since
    /// 2026-01-12. Pair it with `--server-tools web_search,x_search,code_execution`.
    #[value(name = "xai-responses")]
    XaiResponses,
    /// Anthropic's native Messages API — the only transport with prompt caching.
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

/// Reject knobs set without the thing they configure.
///
/// `--tune-state`/`--tune-decay` are read *only* inside the `--tune`/`--tune-bayes` branches, and
/// `--legion-judge`/`--legion-rounds` only when there are debaters, so on their own they loaded
/// fine and were dropped in silence — no learning, no persisted file, no council, no explanation.
/// A flag the program ignores is worse than one it rejects.
///
/// Runs in the early validation pass, *before* any provider is constructed, so the user sees the
/// real problem rather than whichever API key happens to be missing.
fn validate_orphaned_flags(cli: &Cli) -> Result<(), String> {
    if !cli.tune && !cli.tune_bayes {
        let orphans: Vec<&str> = [
            cli.tune_state.is_some().then_some("--tune-state"),
            cli.tune_decay.is_some().then_some("--tune-decay"),
        ]
        .into_iter()
        .flatten()
        .collect();
        if !orphans.is_empty() {
            return Err(format!(
                "{} set without --tune or --tune-bayes: there is no learner to persist or decay",
                orphans.join(" and ")
            ));
        }
    }
    if cli.legion_debater.is_empty() {
        // A judge or a round count with nobody to judge configures nothing.
        let orphans: Vec<&str> = [
            cli.legion_judge.is_some().then_some("--legion-judge"),
            cli.legion_rounds.is_some().then_some("--legion-rounds"),
        ]
        .into_iter()
        .flatten()
        .collect();
        if !orphans.is_empty() {
            return Err(format!(
                "{} set without any --legion-debater: a council needs at least 2 debaters",
                orphans.join(" and ")
            ));
        }
    }
    Ok(())
}

/// Reject a resolved provider-run tool that cannot do anything.
///
/// `--server-tools` carries names only, so `collections_search` arrives with an empty
/// `collection_ids` — a search over no collections. Rather than offer the model a tool that can
/// only fail, say so and point at the surface that can express it. Same principle as negotiation:
/// refuse loudly instead of shipping something inert.
fn validate_resolved_server_tools(tools: &[ServerTool]) -> Result<(), String> {
    for t in tools {
        if let ServerTool::CollectionsSearch { collection_ids, .. } = t {
            if collection_ids.is_empty() {
                return Err(
                    "--server-tools collections_search needs collection ids, which the \
                     flag cannot express; set it in the config file instead:\n\n  \
                     [[provider.server_tools]]\n  kind = \"collections_search\"\n  \
                     collection_ids = [\"...\"]"
                        .into(),
                );
            }
        }
    }
    Ok(())
}

/// CLI spelling of [`ServerTool`] for `--server-tools`: the tool **names** only.
///
/// A `ValueEnum` rather than a free string, so `--server-tools web_serach` is rejected by clap with
/// the valid names listed, instead of parsing into a tool nothing maps and being dropped. Every
/// parameterised tool takes its defaults here; the filters live in the config file, which is why
/// this is a name list and not a mini-language.
#[derive(Clone, Copy, Debug, PartialEq, Eq, ValueEnum)]
pub(crate) enum ServerToolArg {
    // Spelled snake_case explicitly: clap would derive kebab-case (`web-search`), which would
    // disagree with the config file's `kind = "web_search"` and with every doc string naming them.
    // One spelling for one concept.
    #[value(name = "web_search")]
    WebSearch,
    #[value(name = "web_fetch")]
    WebFetch,
    #[value(name = "code_execution")]
    CodeExecution,
    #[value(name = "x_search")]
    XSearch,
    #[value(name = "collections_search")]
    CollectionsSearch,
    #[value(name = "url_context")]
    UrlContext,
}

impl From<ServerToolArg> for ServerTool {
    fn from(a: ServerToolArg) -> Self {
        match a {
            ServerToolArg::WebSearch => ServerTool::WebSearch {
                max_uses: None,
                allowed_domains: Vec::new(),
                blocked_domains: Vec::new(),
            },
            ServerToolArg::WebFetch => ServerTool::WebFetch { max_uses: None },
            ServerToolArg::CodeExecution => ServerTool::CodeExecution,
            ServerToolArg::XSearch => ServerTool::XSearch {
                allowed_handles: Vec::new(),
                blocked_handles: Vec::new(),
                from_date: None,
                to_date: None,
            },
            ServerToolArg::CollectionsSearch => ServerTool::CollectionsSearch {
                collection_ids: Vec::new(),
                limit: None,
            },
            ServerToolArg::UrlContext => ServerTool::UrlContext,
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
            ProviderKind::XaiResponses => "grok-4.6",
            ProviderKind::Anthropic => "claude-sonnet-4-6",
            ProviderKind::Google => "gemini-3-flash-preview",
            ProviderKind::ClaudeCli => "sonnet",
        }
    }

    /// Provider-appropriate [`CostWeights`] for the cost-weighted budget/ATO objective. The
    /// non-caching claude-cli path uses flat weights (no cache classes to value).
    fn cost_weights(self) -> CostWeights {
        match self {
            ProviderKind::Xai | ProviderKind::XaiResponses => CostWeights::xai(),
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
            // No batch provider: the Responses API has no batch endpoint.
            ProviderKind::XaiResponses => (Arc::new(ResponsesTransport::from_env()?), None),
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
pub use lvz_protocol::{Pending, Tool, ToolError, ToolOutput};

/// The [`tracing`] facade, re-exported so a private downstream crate can instrument its own tools
/// (`lavoisier::tracing::info!(…)`) without taking a direct `tracing` dependency or having to match
/// this crate's version. A downstream tool's events surface under its own crate name, so reach them
/// with a directive like `--log-level 'my_tools=debug'` (the default filter only raises *our*
/// crates to `info`, leaving everything else at `warn`).
pub use tracing;

/// The filter used when the operator sets none.
///
/// Our own crates log at `info`, so the operator diagnostics that predate structured logging keep
/// printing as before; everything else sits at `warn`. The scoping is the point: `tracing` is a
/// facade shared with our dependencies (tonic, hyper, h2, axum, tower all emit through it), so a
/// bare `info` default would drag their chatter into view. `EnvFilter` has no glob for `lvz_*`,
/// hence the explicit roll-call — a crate missing from this list falls back to `warn`, silently
/// hiding its `info` milestones, so add new crates here.
const DEFAULT_LOG_FILTER: &str = "warn,\
    lavoisier=info,\
    lvz_agent=info,\
    lvz_anthropic=info,\
    lvz_claude_cli=info,\
    lvz_context=info,\
    lvz_google=info,\
    lvz_gw_a2a=info,\
    lvz_gw_acp=info,\
    lvz_gw_cron=info,\
    lvz_gw_http=info,\
    lvz_gw_matrix=info,\
    lvz_gw_slack=info,\
    lvz_gw_tui=info,\
    lvz_legion=info,\
    lvz_mcp=info,\
    lvz_memory=info,\
    lvz_protocol=info,\
    lvz_schedule=info,\
    lvz_tools=info,\
    lvz_tune=info,\
    lvz_xai=info";

/// Install the stderr logging collector.
///
/// Always installs: the operator diagnostics these events replace used to print unconditionally, so
/// going quiet by default would be a silent regression for a long-running gateway. `--log-level`
/// only *retunes* the filter; [`DEFAULT_LOG_FILTER`] applies when it is unset.
///
/// This is the only place in the workspace that installs a collector: library crates emit through
/// the facade and never decide where events go, so embedding `lavoisier` as a library leaves the
/// host application's own collector untouched. Returns whether a collector was actually installed
/// (`false` if one was already set — e.g. by an embedding host).
fn init_logging(filter: Option<&str>, tui: bool) -> bool {
    let directives = filter.unwrap_or(DEFAULT_LOG_FILTER);
    // A bad filter is reported, then we fall back to the default rather than losing all output —
    // a typo in `--log-level` should not silence a running daemon.
    let env_filter = match build_log_filter(directives) {
        Some(f) => f,
        None => match build_log_filter(DEFAULT_LOG_FILTER) {
            Some(f) => f,
            None => return false,
        },
    };
    // The inline TUI owns the terminal: stderr writes would corrupt its viewport, so route logs to
    // `$LVZ_LOG_FILE` when set, else drop them. Elsewhere, stderr as usual (ANSI only on a tty).
    if tui {
        match std::env::var_os("LVZ_LOG_FILE").and_then(|p| {
            std::fs::OpenOptions::new()
                .create(true)
                .append(true)
                .open(p)
                .ok()
        }) {
            Some(file) => tracing_subscriber::fmt()
                .with_env_filter(env_filter)
                .with_ansi(false)
                .with_writer(move || file.try_clone().expect("clone log file handle"))
                .try_init()
                .is_ok(),
            None => tracing_subscriber::fmt()
                .with_env_filter(env_filter)
                .with_ansi(false)
                .with_writer(std::io::sink)
                .try_init()
                .is_ok(),
        }
    } else {
        let ansi = std::io::stderr().is_terminal();
        tracing_subscriber::fmt()
            .with_env_filter(env_filter)
            .with_writer(std::io::stderr)
            .with_ansi(ansi)
            .try_init()
            .is_ok()
    }
}

/// Parse a `RUST_LOG`-style filter, reporting a bad one on stderr. Split out from [`init_logging`]
/// so the validation is testable without touching the process-global collector.
fn build_log_filter(directives: &str) -> Option<tracing_subscriber::EnvFilter> {
    match tracing_subscriber::EnvFilter::try_new(directives) {
        Ok(f) => Some(f),
        Err(e) => {
            eprintln!("lavoisier: invalid --log-level {directives:?}: {e}");
            None
        }
    }
}

/// Run the full Lavoisier CLI, registering `extra_tools` into the agent alongside the built-ins.
/// This is the entry point for a private downstream binary that wants the entire CLI — flags,
/// config, gateways (HTTP/Matrix/Slack/cron), E2EE, persona — but with its own tools. The stock `lav`
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
    validate_resolved_server_tools(&cli.resolved_server_tools)?;
    validate_orphaned_flags(&cli)?;

    // Install the logging collector as early as possible — right after precedence is resolved, so
    // `[log] level` counts, and before any work worth logging happens.
    init_logging(cli.log_level.as_deref(), cli.tui);
    // Deferred from `Config::load`: the file carries `[log] level`, so it is necessarily read
    // before the collector exists and an event emitted there would be dropped.
    if let Some(path) = &config.source {
        tracing::info!(path = %path.display(), "loaded config");
    }

    let provider_kind = cli.provider.unwrap_or(ProviderKind::Xai);
    tracing::debug!(
        provider = ?provider_kind,
        model = cli.model.as_deref().unwrap_or("(default)"),
        agent = cli.agent,
        "lavoisier starting"
    );

    // Cron jobs (in-process scheduler) can run standalone or alongside HTTP/Matrix.
    let cron_jobs = build_cron_jobs(&cli)?;
    // Matrix schedules, parsed up front (and *before* the `serving` check) so a misconfigured
    // `--schedule-file` — bad JSON, or no `--serve-matrix` to host it — fails immediately instead
    // of being silently ignored on the one-shot path.
    let schedule_jobs = build_schedule(&cli)?;

    // Long-running gateways (HTTP/Matrix/Slack/cron) get the 1-hour cache TTL on the immutable
    // prefix.
    let serving = cli.serve.is_some()
        || cli.serve_matrix
        || cli.serve_slack
        || cli.serve_a2a.is_some()
        || cli.acp
        || cli.tui
        || !cron_jobs.is_empty();
    let (provider, batch_provider) = provider_kind.build(cli.thinking.as_deref(), serving)?;
    let model = cli
        .model
        .clone()
        .unwrap_or_else(|| provider_kind.default_model().to_string());

    // The legion council (if `--legion-debater`/`[legion]` is set): a panel of provider+model
    // debaters that argue the task out before the loop. Built once here at the composition root so
    // both the serving and one-shot paths share it. Fails fast on a bad spec or a missing key.
    let legion = build_legion(&cli, cli.thinking.as_deref(), serving)?;

    // The fallback chain (if `--fallback`/`[provider] fallback` is set): built once here so both the
    // serving and one-shot paths share it, and a bad spec / missing key fails fast rather than
    // mid-turn.
    let fallbacks = build_fallbacks(&cli, cli.thinking.as_deref(), serving)?;

    // External MCP servers (`--mcp-server` / `[mcp] servers`): connect and adapt their tools. Only
    // when the tools can actually be used (a gateway, or the `--agent` loop) — a plain one-shot ask
    // runs no tools, so there is no point spawning server processes. Merged ahead of the caller's
    // `extra_tools` so both reach the registry through the identical path (and a downstream tool can
    // still shadow an MCP tool, last-registration-wins).
    let mcp_tools = if serving || cli.agent {
        build_mcp_tools(&cli).await?
    } else {
        Vec::new()
    };
    let extra_tools: Vec<Arc<dyn Tool>> = mcp_tools.into_iter().chain(extra_tools).collect();

    // Gateway mode: build the shared agent once — wrapped in process-local session memory so each
    // `session` continues across turns (§7.3) — then run every active gateway (HTTP, Matrix, cron)
    // concurrently until shutdown. No prompt is consumed.
    if serving {
        let store = config.build_session_store()?;
        // Schedules run inside the Matrix gateway, but the registry is built here: the agent needs
        // the `schedule_*` tools, and the gateway needs the same registry to fire jobs against.
        let schedule = schedule_jobs.map(|jobs| {
            let mut reg = ScheduleRegistry::new(jobs);
            if let Some(secs) = cli.schedule_pending_timeout {
                reg = reg.with_pending_timeout(secs);
            }
            Arc::new(reg)
        });
        let tools = build_tool_registry(
            &cli,
            batch_provider,
            model.clone(),
            &extra_tools,
            schedule.as_ref(),
        );
        // Captured before `build_agent` consumes `model` — the TUI footer shows this label.
        let model_label = model.clone();
        let agent_core = build_agent(provider, model, &cli, tools.clone(), legion, fallbacks);
        // Interactive tool-approval gate for the TUI (Claude-Code default: read-only tools run
        // unattended, mutating tools / shells ask). Built only when the TUI is active and approval
        // isn't waived; its receiver is handed to the TUI gateway below so prompts reach the user.
        let (agent_core, mut tui_permits) = if cli.tui && !cli.tui_auto_approve {
            let (gate, permits) = ChannelGate::new();
            (agent_core.with_tool_gate(gate), Some(permits))
        } else {
            (agent_core, None)
        };
        let inner = Arc::new(agent_core);
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
            tracing::info!(
                %addr,
                %auth,
                "HTTP gateway listening on http://{addr} (POST /v1/turns, GET /v1/ws)"
            );
            gateways.push(Arc::new(HttpGateway::bind(&addr)?.with_config(gw_config)));
        }

        if cli.serve_matrix {
            // Auto-join invites by default; disabled by `--matrix-no-auto-join` or the config key.
            let auto_join =
                !cli.matrix_no_auto_join && config.gateway.matrix_auto_join.unwrap_or(true);
            // `from_env` already applied any MATRIX_* env vars (incl. state dir / allowlist);
            // fall back to the config file only where the corresponding env var is absent so the
            // documented precedence (env > file) holds.
            let mut matrix = MatrixGateway::from_env()?.with_auto_join(auto_join);
            if std::env::var_os("MATRIX_STATE_DIR").is_none() {
                if let Some(dir) = &config.gateway.matrix_state_dir {
                    matrix = matrix.with_state_dir(dir.clone());
                }
            }
            // Mandatory E2EE: the flag (which also reads LVZ_REQUIRE_E2EE via clap) wins, else the
            // config file. Off by default — degrading is right for a mixed-modality gateway and
            // wrong for an all-encrypted one, so it is the deployment that must say which it is.
            if cli.require_e2ee || config.gateway.matrix_require_e2ee.unwrap_or(false) {
                matrix = matrix.with_require_e2ee(true);
            }
            if std::env::var_os("MATRIX_ALLOWED_USERS").is_none() {
                if let Some(users) = &config.gateway.matrix_allowed_users {
                    matrix = matrix.with_allowed_users(users.clone());
                }
            }
            if std::env::var_os("MATRIX_ALLOWED_ROOMS").is_none() {
                if let Some(rooms) = &config.gateway.matrix_allowed_rooms {
                    matrix = matrix.with_allowed_rooms(rooms.clone());
                }
            }
            if std::env::var_os("MATRIX_HOME_ROOM").is_none() {
                if let Some(home) = &config.gateway.matrix_home_room {
                    matrix = matrix.with_home_room(home.clone());
                }
            }
            // Media ingest dir: the CLI flag (which also reads `MATRIX_MEDIA_DIR` via clap) wins;
            // fall back to the config file only when neither is set (env > file).
            if let Some(dir) = &cli.matrix_media_dir {
                matrix = matrix.with_media_dir(dir.clone());
            } else if let Some(dir) = &config.gateway.matrix_media_dir {
                matrix = matrix.with_media_dir(dir.clone());
            }
            // Localise the gateway's shutdown notice off the same `--lang`/`LANG` locale the council
            // notices use (one locale rule, `Language::from_locale`; only KO_KR ⇒ Korean).
            let matrix_lang = match cli
                .lang
                .as_deref()
                .map(Language::from_locale)
                .unwrap_or_default()
            {
                Language::Korean => lvz_gw_matrix::Language::Korean,
                Language::English => lvz_gw_matrix::Language::English,
            };
            matrix = matrix.with_language(matrix_lang);
            // Per-room/per-member tool permissions are config-file-only (too structured for env).
            if let Some(room_tools) = &config.gateway.matrix_room_tools {
                matrix = matrix.with_room_tools(room_tools.clone());
            }
            if let Some(user_tools) = &config.gateway.matrix_user_tools {
                matrix = matrix.with_user_tools(user_tools.clone());
            }
            // Scheduled jobs live inside this gateway: it owns the timer, fires the action, and
            // reports the outcome to a room.
            if let Some(schedule) = &schedule {
                tracing::info!(jobs = schedule.len(), "matrix schedule armed");
                matrix = matrix.with_schedule(schedule.clone(), tools.clone());
                if let Some(room) = &cli.schedule_room {
                    matrix = matrix.with_schedule_room(room.clone());
                }
            }
            gateways.push(Arc::new(matrix));
        }

        if cli.serve_slack {
            // `from_env` already applied SLACK_ALLOWED_USERS; fall back to the config file only
            // when that env var is absent (env > file).
            let mut slack = SlackGateway::from_env()?;
            if std::env::var_os("SLACK_ALLOWED_USERS").is_none() {
                if let Some(users) = &config.gateway.slack_allowed_users {
                    slack = slack.with_allowed_users(users.clone());
                }
            }
            tracing::info!("Slack gateway (Socket Mode)");
            gateways.push(Arc::new(slack));
        }

        if let Some(addr) = cli.serve_a2a.clone() {
            // Reuse the same API-key policy as the HTTP gateway for the JSON-RPC endpoint.
            let mut a2a = A2aGateway::bind(&addr)?;
            if !cli.api_key.is_empty() {
                a2a = a2a.with_api_keys(cli.api_key.clone());
            }
            let auth = if cli.api_key.is_empty() {
                "open"
            } else {
                "API-key required"
            };
            tracing::info!(%addr, %auth, "A2A gateway listening on http://{addr}");
            gateways.push(Arc::new(a2a));
        }

        if cli.acp {
            // Zed Agent Client Protocol over stdio: the editor spawns us and speaks JSON-RPC on
            // stdin/stdout. It owns those streams, so keep product/log output on stderr (already the
            // case — answer text and diagnostics never touch stdout in serving mode).
            tracing::info!("Zed ACP agent (stdio)");
            gateways.push(Arc::new(AcpGateway::new()));
        }

        if cli.tui {
            // Interactive inline terminal UI. Logs were already routed off stderr in `init_logging`.
            tracing::info!("inline TUI");
            let mut tui = TuiGateway::new()
                .with_session("tui")
                .with_model(model_label.clone());
            if let Some(permits) = tui_permits.take() {
                tui = tui.with_permits(permits);
            }
            gateways.push(Arc::new(tui));
        }

        if !cron_jobs.is_empty() {
            tracing::info!(jobs = cron_jobs.len(), "cron gateway armed");
            gateways.push(Arc::new(CronGateway::new(cron_jobs)));
        }

        // Run them together; the process lives until the first serve loop exits or errors. Using
        // `select_all` (rather than `join_all`) means a graceful shutdown — the Matrix gateway
        // returning `Ok` after catching SIGTERM / Ctrl-C and posting its home-room notice — ends the
        // whole process promptly, and any gateway error surfaces immediately instead of being
        // swallowed behind the other (endless) loops.
        let runs = gateways
            .into_iter()
            .map(|gw| Box::pin(gw.serve(agent.clone())));
        let (res, _idx, _rest) = futures::future::select_all(runs).await;
        res?;
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
        let tools = build_tool_registry(&cli, batch_provider, model.clone(), &extra_tools, None);
        let mut agent = build_agent(provider, model, &cli, tools, legion, fallbacks);
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
        // Provider-run tools apply to the one-shot path too — a plain `lav "..." --server-tools
        // web_search` is the cheapest way to use them, since there is no tool loop at all.
        req.server_tools = cli.resolved_server_tools.clone();
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
    let retry_max = cli.cron_retry_max.unwrap_or(0);
    let retry_wait = cli.cron_retry_wait.unwrap_or(0);
    let mut jobs = Vec::new();
    if let Some(path) = &cli.cron_file {
        let text = std::fs::read_to_string(path)
            .map_err(|e| format!("reading {}: {e}", path.display()))?;
        jobs.extend(CronJob::parse_file(&text, retry_max, retry_wait)?);
    }
    let base = jobs.len();
    for (i, spec) in cli.cron.iter().enumerate() {
        jobs.push(CronJob::parse_cli(spec, base + i, retry_max, retry_wait)?);
    }
    Ok(jobs)
}

/// Load the Matrix schedule from `--schedule-file`, applying the global retry defaults. `None`
/// when no file is configured (⇒ no schedule, and the `schedule_*` tools stay unregistered).
///
/// A schedule without `--serve-matrix` is a configuration mistake — the jobs would have nowhere to
/// report — so it fails loudly rather than running them silently into stderr.
fn build_schedule(cli: &Cli) -> Result<Option<Vec<ScheduleJob>>, Box<dyn std::error::Error>> {
    let Some(path) = &cli.schedule_file else {
        return Ok(None);
    };
    if !cli.serve_matrix {
        return Err(
            "--schedule-file requires --serve-matrix (schedules run inside the Matrix \
                    gateway; use --cron/--cron-file for a standalone scheduler)"
                .into(),
        );
    }
    let text =
        std::fs::read_to_string(path).map_err(|e| format!("reading {}: {e}", path.display()))?;
    let jobs = ScheduleJob::parse_file(
        &text,
        cli.schedule_retry_max.unwrap_or(0),
        cli.schedule_retry_wait.unwrap_or(0),
    )?;
    Ok((!jobs.is_empty()).then_some(jobs))
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
            tracing::info!(path = %path.display(), "loaded persona");
            Some(s.trim().to_string())
        }
        Ok(_) => None,
        Err(e) => {
            // Only surface an error for an explicitly requested file.
            if cli.persona.is_some() {
                tracing::warn!(
                    path = %path.display(),
                    error = %e,
                    "could not read --persona"
                );
            }
            None
        }
    }
}

/// Assemble the agent's tool set: built-ins, the optional `batch_edit` fan-out tool, the
/// `schedule_*` tools when a schedule is configured, then any caller-provided tools.
///
/// Parse a `provider:model` spec (e.g. `anthropic:claude-opus-4-8`) into its [`ProviderKind`] and
/// model id. Shared by legion debater/judge specs and `--fallback` specs; the provider names match
/// the `--provider` value set.
/// A provider paired with one of its models — the parsed form of a `provider:model` spec.
///
/// A **type, not a packed string**, because the string form let the pair be wrong in ways nothing
/// checked until the value was used: `--legion-judge anthropic:typo` or a `[provider] fallback`
/// entry naming a provider that does not exist used to parse at the moment the council convened or
/// the primary model failed — i.e. mid-run, on the rare path, long after the config was read.
/// Parsing at the boundary means a bad spec is a *startup* error naming the offending entry.
///
/// It also cannot disagree with itself the way the old `{provider, model}` pair could: there is one
/// constructor and it validates both halves together.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ModelRef {
    /// Which provider serves this model.
    pub provider: ProviderKind,
    /// The provider-specific model id.
    pub model: String,
}

impl ModelRef {
    /// The provider's canonical CLI spelling (`xai-responses`, `claude-cli`, …).
    fn provider_name(&self) -> &'static str {
        <ProviderKind as ValueEnum>::to_possible_value(&self.provider)
            .map(|v| v.get_name().to_string().leak() as &'static str)
            .unwrap_or("")
    }
}

impl std::fmt::Display for ModelRef {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}:{}", self.provider_name(), self.model)
    }
}

impl std::str::FromStr for ModelRef {
    type Err = String;

    fn from_str(spec: &str) -> Result<Self, Self::Err> {
        let (prov, model) = spec.split_once(':').ok_or_else(|| {
            format!(
                "bad spec {spec:?}: expected `provider:model` (e.g. `anthropic:claude-opus-4-8`)"
            )
        })?;
        if model.is_empty() {
            return Err(format!("bad spec {spec:?}: empty model after `:`"));
        }
        let provider = <ProviderKind as ValueEnum>::from_str(prov, true).map_err(|_| {
            // Derived from the enum rather than hard-coded, so adding a provider updates the
            // message. A stale list here is how `xai-responses` would have gone unmentioned.
            let names: Vec<String> = ProviderKind::value_variants()
                .iter()
                .filter_map(<ProviderKind as ValueEnum>::to_possible_value)
                .map(|v| v.get_name().to_string())
                .collect();
            format!(
                "bad spec {spec:?}: unknown provider {prov:?} (expected {})",
                names.join("|")
            )
        })?;
        Ok(ModelRef {
            provider,
            model: model.to_string(),
        })
    }
}

/// Compare against the canonical `provider:model` spelling. Keeps assertions and log matching
/// readable now that the field is a type rather than the string it came from.
impl PartialEq<&str> for ModelRef {
    fn eq(&self, other: &&str) -> bool {
        match other.split_once(':') {
            Some((p, m)) => self.model == m && self.provider_name() == p,
            None => false,
        }
    }
}

impl<'de> serde::Deserialize<'de> for ModelRef {
    fn deserialize<D: serde::Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        let s = String::deserialize(d)?;
        s.parse().map_err(serde::de::Error::custom)
    }
}

/// An ordered fallback chain: `(provider, model)` pairs the agent reroutes to when the primary is
/// unresponsive before streaming output. Built once at the composition root, handed to the agent.
type FallbackChain = Vec<(Arc<dyn Provider>, String)>;

/// Build the ordered **fallback chain** (`--fallback` / `[provider] fallback`): a `(provider, model)`
/// pair per spec, each provider built fresh from the env so a cross-provider chain picks up each
/// provider's own API key. A missing key surfaces here as a clear error rather than a mid-turn
/// failure. Empty when no fallback is configured (no behaviour change).
fn build_fallbacks(
    cli: &Cli,
    thinking: Option<&str>,
    serving: bool,
) -> Result<FallbackChain, Box<dyn std::error::Error>> {
    let mut chain = Vec::with_capacity(cli.fallback.len());
    for spec in &cli.fallback {
        let (provider, _batch) = spec
            .provider
            .build(thinking, serving)
            .map_err(|e| format!("fallback {spec}: {e}"))?;
        chain.push((provider, spec.model.clone()));
    }
    if !chain.is_empty() {
        tracing::info!(fallbacks = chain.len(), "fallback chain configured");
    }
    Ok(chain)
}

/// Connect to every configured **MCP server** (`--mcp-server` / `[mcp] servers`) and return their
/// tools, adapted to the [`Tool`] contract. Built once at the composition root and merged into the
/// `extra_tools` set, so the remote tools reach the agent through the same registry as the built-ins
/// and every frontend gets them. A bad spec or a server that fails to start surfaces here as a clear
/// error (with the offending label) rather than a mid-turn failure. Empty when none are configured.
async fn build_mcp_tools(cli: &Cli) -> Result<Vec<Arc<dyn Tool>>, Box<dyn std::error::Error>> {
    let mut tools: Vec<Arc<dyn Tool>> = Vec::new();
    for spec in &cli.mcp_server {
        let parsed = McpServerSpec::parse(spec)?;
        let label = parsed.label.clone();
        let connected = lvz_mcp::connect_tools(&parsed)
            .await
            .map_err(|e| format!("MCP server {label:?}: {e}"))?;
        tracing::info!(server = %label, tools = connected.len(), "mcp server connected");
        tools.extend(connected);
    }
    Ok(tools)
}

/// Build the **legion** council (`lvz-legion`) from the `--legion-*` flags / `[legion]` config, or
/// `None` when no debaters were configured. Each debater's provider is built fresh from the env so
/// a cross-provider panel picks up each provider's own API key; a missing key surfaces as a clear
/// error here rather than a mid-turn failure. Requires at least two debaters — a one-model council
/// is just `--advisor-model`.
fn build_legion(
    cli: &Cli,
    thinking: Option<&str>,
    serving: bool,
) -> Result<Option<Arc<dyn Deliberator>>, Box<dyn std::error::Error>> {
    if cli.legion_debater.is_empty() {
        // Orphaned --legion-judge/--legion-rounds are rejected earlier, by
        // `validate_orphaned_flags`, so that the user sees the real problem rather than whichever
        // API key happens to be missing.
        return Ok(None);
    }
    if cli.legion_debater.len() < 2 {
        return Err(
            "legion needs at least 2 --legion-debater specs (a one-model council is just --advisor-model)"
                .into(),
        );
    }
    let build_one = |spec: &ModelRef| -> Result<Debater, Box<dyn std::error::Error>> {
        let (provider, _batch) = spec
            .provider
            .build(thinking, serving)
            .map_err(|e| format!("legion debater {spec}: {e}"))?;
        Ok(Debater::new(
            spec.to_string(),
            provider,
            spec.model.clone(),
            None,
        ))
    };
    let mut debaters = Vec::with_capacity(cli.legion_debater.len());
    for spec in &cli.legion_debater {
        debaters.push(build_one(spec)?);
    }
    let judge = match &cli.legion_judge {
        Some(spec) => build_one(spec)?,
        None => debaters[0].clone(),
    };
    let rounds = cli.legion_rounds.unwrap_or(1);
    // Locale for the progress notices: --lang (or the LANG env var, via clap). Only KO_KR ⇒ Korean.
    let lang = cli
        .lang
        .as_deref()
        .map(Language::from_locale)
        .unwrap_or_default();
    let panel = Panel::new(debaters, judge, rounds)
        .map_err(|e| e.to_string())?
        .with_language(lang);
    tracing::info!(
        debaters = panel.debaters().len(),
        rounds = panel.rounds(),
        ?lang,
        "legion configured"
    );
    Ok(Some(Arc::new(panel)))
}

/// Built at the composition root (rather than inside [`build_agent`]) so the *same* registry can
/// also be handed to the Matrix gateway's scheduler — a scheduled `tool` job then dispatches
/// through the identical tool instances the model uses, with no second construction to drift.
/// [`ToolRegistry`] is a vector of `Arc`s, so the clone is cheap.
fn build_tool_registry(
    cli: &Cli,
    batch_provider: Option<Arc<dyn BatchProvider>>,
    editor_model: String,
    extra_tools: &[Arc<dyn Tool>],
    schedule: Option<&Arc<ScheduleRegistry>>,
) -> ToolRegistry {
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
    // Schedule introspection/control, so chat can ask "how's the backup job?" and "run it again"
    // in natural language. Only registered when there are jobs — otherwise they are dead weight in
    // the cached prefix of every request.
    if let Some(schedule) = schedule {
        registry.register(Arc::new(ScheduleListTool::new(schedule.clone())));
        registry.register(Arc::new(ScheduleStatusTool::new(schedule.clone())));
        registry.register(Arc::new(ScheduleRunTool::new(schedule.clone())));
    }
    // Caller-provided tools (e.g. a private downstream binary via `run_with`/`main_with`). Last, so
    // a downstream tool can deliberately shadow a built-in (last registration wins).
    for tool in extra_tools {
        registry.register(tool.clone());
    }
    registry
}

/// Build the tool-using [`Agent`] from the CLI config. Shared by `--agent` (one-shot) and
/// `--serve` (gateway) so both drive an identically-configured agent core. The tool set comes
/// from [`build_tool_registry`].
fn build_agent(
    provider: Arc<dyn Provider>,
    model: String,
    cli: &Cli,
    registry: ToolRegistry,
    legion: Option<Arc<dyn Deliberator>>,
    fallbacks: FallbackChain,
) -> Agent {
    let mut config = AgentConfig::default()
        .with_model(model)
        .with_cost_weights(cli.provider.unwrap_or(ProviderKind::Xai).cost_weights());
    config.max_tokens = cli.max_tokens.unwrap_or(2048);
    // Provider-run tools, already resolved (flag over file) by `Config::apply_to`.
    config.server_tools = cli.resolved_server_tools.clone();
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
    let mut agent = Agent::new(provider, registry, config);
    // Install the legion council (if configured), so its agreed plan seeds the loop; supersedes
    // the single advisor pre-pass inside the agent.
    if let Some(legion) = legion {
        agent = agent.with_legion(legion);
    }
    // Install the fallback chain (if configured): the loop transparently reroutes to the next model
    // when the primary is unresponsive before streaming any output, and a circuit breaker demotes a
    // failed model across turns for `--fallback-cooldown` seconds. No-op when empty.
    if !fallbacks.is_empty() {
        let cooldown = std::time::Duration::from_secs(cli.fallback_cooldown.unwrap_or(60));
        agent = agent.with_fallbacks(fallbacks, cooldown);
    }
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
                    tracing::warn!(%path, error = %e, "tune-state: could not load; starting cold");
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
                    tracing::warn!(%path, error = %e, "tune-state: could not load; starting cold");
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
            tracing::warn!(path = %self.path.display(), error = %e, "tune-state: could not save");
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
            Event::Notice(text) => eprintln!("\n[notice] {text}"),
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_default_filter_is_valid_and_scopes_to_our_crates() {
        // A typo here would silently downgrade every crate to `warn`, hiding the operator output
        // that used to print unconditionally — so parse it and check the shape explicitly.
        assert!(build_log_filter(DEFAULT_LOG_FILTER).is_some());
        assert!(
            DEFAULT_LOG_FILTER.starts_with("warn,"),
            "dependencies must default to warn, not info"
        );
        // Every workspace library that logs must be listed, or its info events vanish.
        for krate in [
            "lavoisier",
            "lvz_gw_matrix",
            "lvz_gw_slack",
            "lvz_gw_tui",
            "lvz_gw_a2a",
            "lvz_gw_acp",
            "lvz_gw_cron",
            "lvz_gw_http",
            "lvz_legion",
            "lvz_mcp",
            "lvz_schedule",
            "lvz_memory",
            "lvz_tools",
        ] {
            assert!(
                DEFAULT_LOG_FILTER.contains(&format!("{krate}=info")),
                "{krate} missing from the default filter"
            );
        }
    }

    #[test]
    fn a_malformed_filter_falls_back_to_the_default_rather_than_going_silent() {
        // `init_logging` installs a process-global collector, so this can only be asserted through
        // the fallback path it uses: the default must still parse when the operator's does not.
        assert!(build_log_filter("lvz_gw_matrix=nonsense").is_none());
        assert!(build_log_filter(DEFAULT_LOG_FILTER).is_some());
    }

    #[test]
    fn accepts_bare_levels_and_per_target_directives() {
        for ok in [
            "info",
            "debug",
            "off",
            "lvz_gw_matrix=debug",
            "lvz_gw_matrix=debug,warn",
            "lavoisier=trace,lvz_schedule=debug,error",
        ] {
            assert!(build_log_filter(ok).is_some(), "expected {ok:?} to parse");
        }
    }

    #[test]
    fn rejects_a_malformed_filter() {
        // A bad directive must be reported, not silently swallowed into "logs nothing".
        assert!(build_log_filter("=====").is_none());
        assert!(build_log_filter("lvz_gw_matrix=nonsense").is_none());
    }

    #[test]
    fn model_ref_parses_provider_and_model() {
        for (spec, provider, model) in [
            (
                "anthropic:claude-opus-4-8",
                ProviderKind::Anthropic,
                "claude-opus-4-8",
            ),
            ("xai:grok-4", ProviderKind::Xai, "grok-4"),
            ("google:gemini-3", ProviderKind::Google, "gemini-3"),
            (
                "xai-responses:grok-4.6",
                ProviderKind::XaiResponses,
                "grok-4.6",
            ),
        ] {
            let r: ModelRef = spec.parse().unwrap_or_else(|e| panic!("{spec}: {e}"));
            assert_eq!(r.provider, provider);
            assert_eq!(r.model, model);
            // Round-trips through the canonical spelling, which is what the comparison and every
            // error message use.
            assert_eq!(r.to_string(), spec);
            assert_eq!(r, spec);
        }
    }

    #[test]
    fn model_ref_rejects_bad_forms() {
        for bad in ["no-colon", "bogus:model", "anthropic:"] {
            assert!(bad.parse::<ModelRef>().is_err(), "{bad} should not parse");
        }
        // The unknown-provider message lists the real set, derived from the enum rather than
        // hard-coded, so adding a provider cannot leave it stale.
        let err = "bogus:model".parse::<ModelRef>().unwrap_err();
        assert!(err.contains("xai-responses"), "{err}");
    }

    #[test]
    fn build_legion_is_none_without_debaters_and_needs_two() {
        use clap::Parser;

        // No `--legion-debater` ⇒ no council.
        let cli = Cli::parse_from(["lav"]);
        assert!(build_legion(&cli, None, false).unwrap().is_none());

        // A single debater is refused before any provider is built (a one-model council is just
        // the advisor pre-pass), so this needs no API keys in the env.
        let cli = Cli::parse_from(["lav", "--legion-debater", "anthropic:opus"]);
        assert!(build_legion(&cli, None, false).is_err());
    }

    /// A writer that appends into a shared buffer, so a scoped subscriber's output is inspectable.
    struct SharedBuf(std::sync::Arc<std::sync::Mutex<Vec<u8>>>);
    impl std::io::Write for SharedBuf {
        fn write(&mut self, data: &[u8]) -> std::io::Result<usize> {
            self.0.lock().unwrap().extend_from_slice(data);
            Ok(data.len())
        }
        fn flush(&mut self) -> std::io::Result<()> {
            Ok(())
        }
    }

    /// The default filter's correctness rests on `EnvFilter` matching a directive target as a
    /// **prefix** of the event's target: `lvz_gw_matrix=info` has to cover events emitted from
    /// `lvz_gw_matrix::e2ee` too, or half a crate's logs go missing. Verified against a scoped
    /// subscriber so no process-global state is touched.
    #[test]
    fn a_crate_directive_covers_that_crate_s_submodules() {
        let buf = std::sync::Arc::new(std::sync::Mutex::new(Vec::<u8>::new()));
        let sink = buf.clone();
        let subscriber = tracing_subscriber::fmt()
            .with_env_filter(build_log_filter("warn,lvz_gw_matrix=info").unwrap())
            .with_writer(move || SharedBuf(sink.clone()))
            .with_ansi(false)
            .finish();

        tracing::subscriber::with_default(subscriber, || {
            tracing::info!(target: "lvz_gw_matrix", "crate root event");
            tracing::info!(target: "lvz_gw_matrix::e2ee", "submodule event");
            tracing::info!(target: "tonic::transport", "dependency info");
            tracing::warn!(target: "tonic::transport", "dependency warn");
        });

        let out = String::from_utf8(buf.lock().unwrap().clone()).unwrap();
        assert!(out.contains("crate root event"), "root target must match");
        assert!(
            out.contains("submodule event"),
            "a crate directive must cover its submodules (prefix match)"
        );
        assert!(
            !out.contains("dependency info"),
            "dependency info must stay below the warn floor"
        );
        assert!(out.contains("dependency warn"), "dependency warn must pass");
    }
}
