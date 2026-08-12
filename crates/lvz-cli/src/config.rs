//! TOML configuration file for long-running deployments.
//!
//! A `lavoisier.toml` (or `--config <PATH>`) sets defaults for most flags, so a `--serve` /
//! `--serve-matrix` / `--cron` process can be configured from a file instead of a long command
//! line. **Precedence: an explicit CLI flag (or env var) always wins over the file, which wins
//! over the built-in default.** The file is split into `[provider]`, `[agent]`, `[memory]`,
//! `[gateway]`, `[legion]`, and `[log]` sections; unknown keys are rejected so typos surface
//! immediately.
//!
//! Memory in particular is configured here: the in-memory store is unbounded by default, but
//! `[memory]` can cap it (`max_messages`, `max_sessions`) or switch to a durable file store.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Arc;

use lvz_memory::{FileStore, InMemoryStore, SessionStore};
use serde::Deserialize;

use crate::{Cli, ProviderKind};

/// The parsed `lavoisier.toml`. Every field is optional; a missing file yields all-default.
#[derive(Debug, Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct Config {
    pub provider: ProviderSection,
    pub agent: AgentSection,
    pub memory: MemorySection,
    pub gateway: GatewaySection,
    pub legion: LegionSection,
    pub mcp: McpSection,
    pub log: LogSection,
    /// Where this config was read from, or `None` if no file was found.
    ///
    /// Recorded rather than logged at load time on purpose: `[log] level` lives *in* this file, so
    /// loading necessarily happens before the collector is installed and an event emitted here
    /// would be dropped. The caller logs it once logging is up.
    #[serde(skip)]
    pub source: Option<PathBuf>,
}

/// `[log]` — structured logging to stderr. Absent ⇒ no collector is installed.
#[derive(Debug, Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct LogSection {
    /// `RUST_LOG`-style filter: a bare level (`info`) or per-target directives
    /// (`lvz_gw_matrix=debug,warn`). `--log-level` / `LVZ_LOG_LEVEL` take precedence.
    pub level: Option<String>,
}

/// `[legion]` — a multi-model council that argues the task out before the agent acts. Absent ⇒
/// no council (the single `--advisor-model` pre-pass, if any, applies instead).
#[derive(Debug, Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct LegionSection {
    /// Debater specs, each `provider:model` (e.g. `anthropic:claude-opus-4-8`, `xai:grok-4`). Two
    /// or more required to convene. `--legion-debater` (repeatable) takes precedence.
    pub debaters: Option<Vec<String>>,
    /// The judge spec, `provider:model`; defaults to the first debater. `--legion-judge` takes
    /// precedence.
    pub judge: Option<String>,
    /// Critique rounds after the draft (default 1; 0 = draft then judge). `--legion-rounds` /
    /// `LVZ_LEGION_ROUNDS` take precedence.
    pub rounds: Option<usize>,
}

/// `[mcp]` — external Model Context Protocol servers whose tools Lavoisier connects to and exposes.
/// Absent ⇒ no MCP servers.
#[derive(Debug, Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct McpSection {
    /// Server specs, each `label: target` (a spawn command for stdio, or an `http(s)://` URL) —
    /// the same grammar as `--mcp-server`, which takes precedence.
    pub servers: Option<Vec<String>>,
}

/// `[provider]` — which model/provider to drive.
#[derive(Debug, Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct ProviderSection {
    /// `xai` | `anthropic` | `google` | `claude-cli`.
    pub provider: Option<String>,
    pub model: Option<String>,
    /// Ordered fallback chain, each `provider:model`. If the primary is unresponsive or errors
    /// before streaming output, the agent retries on the next. `--fallback` (repeatable) wins.
    pub fallback: Option<Vec<String>>,
    /// Seconds a failed fallback model stays demoted before re-probe (circuit breaker; default 60).
    /// `--fallback-cooldown` / `LVZ_FALLBACK_COOLDOWN` take precedence.
    pub fallback_cooldown: Option<u64>,
}

/// `[agent]` — the tool loop, compaction, routing, and accuracy levers.
#[derive(Debug, Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct AgentSection {
    pub summary_model: Option<String>,
    pub compact_after: Option<usize>,
    pub context_limit: Option<usize>,
    pub max_steps: Option<usize>,
    pub max_tokens: Option<u32>,
    pub budget: Option<u64>,
    pub cheap_model: Option<String>,
    pub escalate_after: Option<usize>,
    pub advisor_model: Option<String>,
    pub repo_skeleton: Option<usize>,
    pub thinking: Option<String>,
    pub persona: Option<PathBuf>,
    pub system: Option<String>,
    pub require_edit: Option<bool>,
    pub verify_and_fix: Option<bool>,
    pub verify_cmd: Option<String>,
}

/// `[memory]` — session-store kind and bounds.
#[derive(Debug, Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct MemorySection {
    /// `memory` (default, process-local) or `file` (durable; needs `path`).
    pub store: Option<String>,
    /// Directory for the `file` store.
    pub path: Option<PathBuf>,
    /// Cap each session to its most recent N messages.
    pub max_messages: Option<usize>,
    /// Keep at most N sessions (LRU eviction); in-memory store only.
    pub max_sessions: Option<usize>,
}

/// `[gateway]` — serve addresses, auth, and rate limit.
#[derive(Debug, Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct GatewaySection {
    pub serve: Option<String>,
    pub serve_matrix: Option<bool>,
    pub serve_slack: Option<bool>,
    /// A2A server bind address (`host:port`). `--serve-a2a` / `LVZ_SERVE_A2A` take precedence.
    pub serve_a2a: Option<String>,
    /// Run as a Zed Agent Client Protocol agent over stdio (see `--acp`). `--acp` takes precedence.
    pub acp: Option<bool>,
    pub api_keys: Option<Vec<String>>,
    pub rate_limit: Option<u32>,
    /// Auto-accept Matrix room invites (default `true`).
    pub matrix_auto_join: Option<bool>,
    /// Only answer these Matrix senders (`@user:server`); empty/unset ⇒ answer everyone. The
    /// `MATRIX_ALLOWED_USERS` env var (comma-separated) takes precedence.
    pub matrix_allowed_users: Option<Vec<String>>,
    /// Directory persisting the Matrix session (token + device id) and the E2EE crypto store, for
    /// a stable identity across restarts. `MATRIX_STATE_DIR` takes precedence.
    pub matrix_state_dir: Option<PathBuf>,
    /// Only act in these Matrix rooms (room ids); empty/unset ⇒ any room the bot is in. Combined
    /// with `matrix_allowed_users` as a conjunction. The `MATRIX_ALLOWED_ROOMS` env var
    /// (comma-separated) takes precedence.
    pub matrix_allowed_rooms: Option<Vec<String>>,
    /// Per-room tool permissions: `room_id` → the tool names permitted in that room. A room absent
    /// from the map is unconstrained. Intersected with `matrix_user_tools`.
    pub matrix_room_tools: Option<HashMap<String, Vec<String>>>,
    /// Per-member tool permissions: `user_id` → the tool names permitted to that member. A user
    /// absent from the map is unconstrained. Intersected with `matrix_room_tools`.
    pub matrix_user_tools: Option<HashMap<String, Vec<String>>>,
    /// The Matrix "home" room that receives the shutdown notice on SIGTERM / Ctrl-C. The
    /// `MATRIX_HOME_ROOM` env var takes precedence.
    pub matrix_home_room: Option<String>,
    /// Directory inbound Matrix media (images/files) is downloaded to. Setting it **enables** media
    /// ingest — an engaged image/file message is fetched here and its local path handed to the agent
    /// so a tool can act on it. Unset ⇒ media messages are ignored. `MATRIX_MEDIA_DIR` takes
    /// precedence.
    pub matrix_media_dir: Option<PathBuf>,
    /// Only answer these Slack user ids; empty/unset ⇒ answer everyone. The `SLACK_ALLOWED_USERS`
    /// env var (comma-separated) takes precedence.
    pub slack_allowed_users: Option<Vec<String>>,
    /// Default max retries after a failed cron fire before waiting for the next slot (`0` ⇒ no
    /// retry). A per-job `retry_max` in `--cron-file` overrides this. `--cron-retry-max` /
    /// `LVZ_CRON_RETRY_MAX` take precedence.
    pub cron_retry_max: Option<u32>,
    /// Seconds to wait between cron retries. A per-job `retry_wait` in `--cron-file` overrides this.
    /// `--cron-retry-wait` / `LVZ_CRON_RETRY_WAIT` take precedence.
    pub cron_retry_wait: Option<u64>,
    /// Path to the Matrix schedule file (see `--schedule-file`). Requires `serve_matrix`.
    pub schedule_file: Option<PathBuf>,
    /// Default room for schedule reports, for jobs that name none. Falls back to `matrix_home_room`.
    pub schedule_room: Option<String>,
    /// Default max retries after a failed scheduled fire. A per-job `retry_max` overrides this.
    pub schedule_retry_max: Option<u32>,
    /// Seconds between scheduled-job retries. A per-job `retry_wait` overrides this.
    pub schedule_retry_wait: Option<u64>,
}

impl Config {
    /// Load from an explicit `--config` path (a missing file is an error), else auto-discover
    /// `./lavoisier.toml` (absent ⇒ all-default, silently).
    pub fn load(explicit: Option<&Path>) -> Result<Self, String> {
        let path = match explicit {
            Some(p) => p.to_path_buf(),
            None => {
                let default = PathBuf::from("lavoisier.toml");
                if !default.is_file() {
                    return Ok(Self::default());
                }
                default
            }
        };
        let text = std::fs::read_to_string(&path)
            .map_err(|e| format!("reading config {}: {e}", path.display()))?;
        let mut config: Config =
            toml::from_str(&text).map_err(|e| format!("parsing config {}: {e}", path.display()))?;
        config.source = Some(path);
        Ok(config)
    }

    /// Fill any CLI field the user did not set from the config file (CLI/env wins over the file).
    pub fn apply_to(&self, cli: &mut Cli) {
        // [provider]
        if cli.provider.is_none() {
            if let Some(p) = self.provider.provider.as_deref().and_then(parse_provider) {
                cli.provider = Some(p);
            }
        }
        merge(&mut cli.model, &self.provider.model);
        // A Vec flag: the file supplies it only when the CLI passed none (CLI wins wholesale).
        if cli.fallback.is_empty() {
            if let Some(fallback) = &self.provider.fallback {
                cli.fallback = fallback.clone();
            }
        }
        merge_copy(&mut cli.fallback_cooldown, self.provider.fallback_cooldown);

        // [agent]
        merge(&mut cli.summary_model, &self.agent.summary_model);
        merge_copy(&mut cli.compact_after, self.agent.compact_after);
        merge_copy(&mut cli.context_limit, self.agent.context_limit);
        merge_copy(&mut cli.max_steps, self.agent.max_steps);
        merge_copy(&mut cli.max_tokens, self.agent.max_tokens);
        merge_copy(&mut cli.budget, self.agent.budget);
        merge(&mut cli.cheap_model, &self.agent.cheap_model);
        merge_copy(&mut cli.escalate_after, self.agent.escalate_after);
        merge(&mut cli.advisor_model, &self.agent.advisor_model);
        merge_copy(&mut cli.repo_skeleton, self.agent.repo_skeleton);
        merge(&mut cli.thinking, &self.agent.thinking);
        merge(&mut cli.persona, &self.agent.persona);
        merge(&mut cli.system, &self.agent.system);
        merge(&mut cli.verify_cmd, &self.agent.verify_cmd);
        // Boolean accuracy levers: the file can turn them on; an explicit `--flag` also turns
        // them on, so OR is the correct merge (neither can force-disable the other).
        cli.require_edit |= self.agent.require_edit.unwrap_or(false);
        cli.verify_and_fix |= self.agent.verify_and_fix.unwrap_or(false);

        // [gateway]
        merge(&mut cli.serve, &self.gateway.serve);
        cli.serve_matrix |= self.gateway.serve_matrix.unwrap_or(false);
        cli.serve_slack |= self.gateway.serve_slack.unwrap_or(false);
        merge(&mut cli.serve_a2a, &self.gateway.serve_a2a);
        cli.acp |= self.gateway.acp.unwrap_or(false);
        merge_copy(&mut cli.rate_limit, self.gateway.rate_limit);
        merge_copy(&mut cli.cron_retry_max, self.gateway.cron_retry_max);
        merge_copy(&mut cli.cron_retry_wait, self.gateway.cron_retry_wait);
        merge(&mut cli.schedule_file, &self.gateway.schedule_file);
        merge(&mut cli.schedule_room, &self.gateway.schedule_room);
        merge_copy(&mut cli.schedule_retry_max, self.gateway.schedule_retry_max);
        merge_copy(
            &mut cli.schedule_retry_wait,
            self.gateway.schedule_retry_wait,
        );
        if cli.api_key.is_empty() {
            if let Some(keys) = &self.gateway.api_keys {
                cli.api_key = keys.clone();
            }
        }

        // [legion]
        if cli.legion_debater.is_empty() {
            if let Some(debaters) = &self.legion.debaters {
                cli.legion_debater = debaters.clone();
            }
        }
        merge(&mut cli.legion_judge, &self.legion.judge);
        merge_copy(&mut cli.legion_rounds, self.legion.rounds);

        // [mcp] — a Vec flag: the file supplies it only when the CLI passed none (CLI wins wholesale).
        if cli.mcp_server.is_empty() {
            if let Some(servers) = &self.mcp.servers {
                cli.mcp_server = servers.clone();
            }
        }

        // [log]
        merge(&mut cli.log_level, &self.log.level);
    }

    /// Build the session store described by `[memory]` (`memory` store unless `store = "file"`).
    pub fn build_session_store(&self) -> Result<Arc<dyn SessionStore>, String> {
        match self.memory.store.as_deref() {
            None | Some("memory") => Ok(Arc::new(InMemoryStore::with_limits(
                self.memory.max_messages,
                self.memory.max_sessions,
            ))),
            Some("file") => {
                let dir =
                    self.memory.path.clone().ok_or_else(|| {
                        "memory.store = \"file\" requires memory.path".to_string()
                    })?;
                Ok(Arc::new(
                    FileStore::new(dir).with_max_messages(self.memory.max_messages),
                ))
            }
            Some(other) => Err(format!(
                "unknown memory.store {other:?} (expected \"memory\" or \"file\")"
            )),
        }
    }
}

/// Fill `target` from `from` only if the user left it unset.
fn merge<T: Clone>(target: &mut Option<T>, from: &Option<T>) {
    if target.is_none() {
        target.clone_from(from);
    }
}

/// `merge` for `Copy` values passed by value.
fn merge_copy<T>(target: &mut Option<T>, from: Option<T>) {
    if target.is_none() {
        *target = from;
    }
}

/// Parse a `[provider] provider` string into a [`ProviderKind`] (matching the CLI value names).
fn parse_provider(s: &str) -> Option<ProviderKind> {
    match s.to_ascii_lowercase().as_str() {
        "xai" => Some(ProviderKind::Xai),
        "anthropic" => Some(ProviderKind::Anthropic),
        "google" => Some(ProviderKind::Google),
        "claude-cli" | "claude_cli" | "claudecli" => Some(ProviderKind::ClaudeCli),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_sections_and_rejects_unknown_keys() {
        let cfg: Config = toml::from_str(
            r#"
            [provider]
            provider = "anthropic"
            model = "claude-x"

            [agent]
            compact_after = 50000
            require_edit = true

            [memory]
            store = "file"
            path = "/var/lib/lav/sessions"
            max_messages = 200

            [gateway]
            serve = "0.0.0.0:8080"
            api_keys = ["k1", "k2"]
            "#,
        )
        .unwrap();
        assert_eq!(cfg.provider.provider.as_deref(), Some("anthropic"));
        assert_eq!(cfg.agent.compact_after, Some(50000));
        assert_eq!(cfg.agent.require_edit, Some(true));
        assert_eq!(cfg.memory.store.as_deref(), Some("file"));
        assert_eq!(
            cfg.gateway.api_keys.as_deref(),
            Some(&["k1".to_string(), "k2".to_string()][..])
        );

        assert!(toml::from_str::<Config>("[agent]\nnonsense = 1\n").is_err());
    }

    #[test]
    fn load_records_its_source_instead_of_logging_it() {
        // Regression guard: `[log] level` lives in this file, so loading happens *before* the
        // collector is installed. An event emitted inside `load` would be silently dropped — the
        // path must be recorded for the caller to log once logging is up.
        let dir = std::env::temp_dir().join(format!("lvz-cfg-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("lavoisier.toml");
        std::fs::write(&path, "[log]\nlevel = \"warn\"\n").unwrap();

        let cfg = Config::load(Some(&path)).unwrap();
        assert_eq!(cfg.source.as_deref(), Some(path.as_path()));
        assert_eq!(cfg.log.level.as_deref(), Some("warn"));

        // No file discovered ⇒ nothing to report.
        assert_eq!(Config::default().source, None);
        // `source` is not a TOML key — it's derived, and must not be settable from the file.
        assert!(toml::from_str::<Config>("source = \"x\"\n").is_err());

        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn parses_log_section_and_rejects_unknown_keys() {
        let cfg: Config = toml::from_str("[log]\nlevel = \"lvz_gw_matrix=debug,warn\"\n").unwrap();
        assert_eq!(cfg.log.level.as_deref(), Some("lvz_gw_matrix=debug,warn"));

        // Absent `[log]` ⇒ no level ⇒ no collector installed (the no-op default).
        let empty: Config = toml::from_str("").unwrap();
        assert_eq!(empty.log.level, None);

        assert!(toml::from_str::<Config>("[log]\nlevl = \"info\"\n").is_err());
    }

    #[test]
    fn cli_log_level_wins_over_the_file() {
        use clap::Parser;
        let cfg: Config = toml::from_str("[log]\nlevel = \"warn\"\n").unwrap();

        // Unset on the CLI ⇒ the file fills it in.
        let mut cli = Cli::parse_from(["lav"]);
        cli.log_level = None; // ignore any ambient LVZ_LOG_LEVEL in the test environment
        cfg.apply_to(&mut cli);
        assert_eq!(cli.log_level.as_deref(), Some("warn"));

        // Explicit on the CLI ⇒ the file must not override it.
        let mut cli = Cli::parse_from(["lav", "--log-level", "trace"]);
        cfg.apply_to(&mut cli);
        assert_eq!(cli.log_level.as_deref(), Some("trace"));
    }

    #[test]
    fn parses_gateway_matrix_and_slack_knobs() {
        let cfg: Config = toml::from_str(
            r#"
            [gateway]
            serve_matrix = true
            serve_slack = true
            matrix_state_dir = "/var/lib/lav/matrix"
            matrix_allowed_users = ["@a:hs", "@b:hs"]
            matrix_allowed_rooms = ["!ops:hs", "!general:hs"]
            matrix_home_room = "!ops:hs"
            matrix_media_dir = "/var/lib/lav/media"
            slack_allowed_users = ["U_A"]

            [gateway.matrix_room_tools]
            "!ops:hs" = ["shell", "read_file"]

            [gateway.matrix_user_tools]
            "@a:hs" = ["read_file"]
            "#,
        )
        .unwrap();
        assert_eq!(cfg.gateway.serve_matrix, Some(true));
        assert_eq!(cfg.gateway.serve_slack, Some(true));
        assert_eq!(
            cfg.gateway.matrix_state_dir.as_deref(),
            Some(Path::new("/var/lib/lav/matrix"))
        );
        assert_eq!(
            cfg.gateway.matrix_allowed_users.as_deref(),
            Some(&["@a:hs".to_string(), "@b:hs".to_string()][..])
        );
        assert_eq!(
            cfg.gateway.matrix_allowed_rooms.as_deref(),
            Some(&["!ops:hs".to_string(), "!general:hs".to_string()][..])
        );
        assert_eq!(cfg.gateway.matrix_home_room.as_deref(), Some("!ops:hs"));
        assert_eq!(
            cfg.gateway.matrix_media_dir.as_deref(),
            Some(Path::new("/var/lib/lav/media"))
        );
        assert_eq!(
            cfg.gateway.matrix_room_tools.as_ref().unwrap()["!ops:hs"],
            vec!["shell".to_string(), "read_file".to_string()]
        );
        assert_eq!(
            cfg.gateway.matrix_user_tools.as_ref().unwrap()["@a:hs"],
            vec!["read_file".to_string()]
        );
        assert_eq!(
            cfg.gateway.slack_allowed_users.as_deref(),
            Some(&["U_A".to_string()][..])
        );
    }

    #[test]
    fn parses_legion_section_and_rejects_unknown_keys() {
        let cfg: Config = toml::from_str(
            r#"
            [legion]
            debaters = ["anthropic:claude-opus-4-8", "xai:grok-4"]
            judge = "anthropic:claude-opus-4-8"
            rounds = 2
            "#,
        )
        .unwrap();
        assert_eq!(
            cfg.legion.debaters.as_deref(),
            Some(
                &[
                    "anthropic:claude-opus-4-8".to_string(),
                    "xai:grok-4".to_string()
                ][..]
            )
        );
        assert_eq!(
            cfg.legion.judge.as_deref(),
            Some("anthropic:claude-opus-4-8")
        );
        assert_eq!(cfg.legion.rounds, Some(2));

        // Absent `[legion]` ⇒ no council.
        let empty: Config = toml::from_str("").unwrap();
        assert_eq!(empty.legion.debaters, None);

        assert!(toml::from_str::<Config>("[legion]\ndebators = []\n").is_err());
    }

    #[test]
    fn cli_legion_flags_win_over_the_file() {
        use clap::Parser;
        let cfg: Config = toml::from_str(
            "[legion]\ndebaters = [\"anthropic:opus\", \"xai:grok-4\"]\nrounds = 3\n",
        )
        .unwrap();

        // Unset on the CLI ⇒ the file fills them in.
        let mut cli = Cli::parse_from(["lav"]);
        cli.legion_rounds = None; // ignore any ambient LVZ_LEGION_ROUNDS
        cfg.apply_to(&mut cli);
        assert_eq!(cli.legion_debater, vec!["anthropic:opus", "xai:grok-4"]);
        assert_eq!(cli.legion_rounds, Some(3));

        // Explicit on the CLI ⇒ the file must not override.
        let mut cli = Cli::parse_from(["lav", "--legion-debater", "google:gemini-3"]);
        cli.legion_rounds = None;
        cfg.apply_to(&mut cli);
        assert_eq!(cli.legion_debater, vec!["google:gemini-3"]);
    }

    #[test]
    fn cli_fallback_flags_win_over_the_file() {
        use clap::Parser;
        let cfg: Config = toml::from_str(
            "[provider]\nfallback = [\"anthropic:claude-sonnet-4-6\", \"google:gemini-3-flash-preview\"]\nfallback_cooldown = 120\n",
        )
        .unwrap();

        // Unset on the CLI ⇒ the file supplies the whole chain (and the cooldown).
        let mut cli = Cli::parse_from(["lav"]);
        cli.fallback_cooldown = None; // ignore any ambient LVZ_FALLBACK_COOLDOWN
        cfg.apply_to(&mut cli);
        assert_eq!(
            cli.fallback,
            vec![
                "anthropic:claude-sonnet-4-6",
                "google:gemini-3-flash-preview"
            ]
        );
        assert_eq!(cli.fallback_cooldown, Some(120));

        // Explicit on the CLI ⇒ the file must not override.
        let mut cli = Cli::parse_from(["lav", "--fallback", "xai:grok-4"]);
        cfg.apply_to(&mut cli);
        assert_eq!(cli.fallback, vec!["xai:grok-4"]);

        // Unknown key still rejected.
        assert!(toml::from_str::<Config>("[provider]\nfalback = []\n").is_err());
    }

    #[test]
    fn file_store_requires_path() {
        let cfg: Config = toml::from_str("[memory]\nstore = \"file\"\n").unwrap();
        assert!(cfg.build_session_store().is_err());
        let cfg: Config = toml::from_str("[memory]\nstore = \"memory\"\n").unwrap();
        assert!(cfg.build_session_store().is_ok());
    }

    #[test]
    fn provider_parsing() {
        assert_eq!(parse_provider("Anthropic"), Some(ProviderKind::Anthropic));
        assert_eq!(parse_provider("claude-cli"), Some(ProviderKind::ClaudeCli));
        assert_eq!(parse_provider("bogus"), None);
    }
}
