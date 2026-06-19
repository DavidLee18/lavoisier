//! TOML configuration file for long-running deployments.
//!
//! A `lavoisier.toml` (or `--config <PATH>`) sets defaults for most flags, so a `--serve` /
//! `--serve-matrix` / `--cron` process can be configured from a file instead of a long command
//! line. **Precedence: an explicit CLI flag (or env var) always wins over the file, which wins
//! over the built-in default.** The file is split into `[provider]`, `[agent]`, `[memory]`, and
//! `[gateway]` sections; unknown keys are rejected so typos surface immediately.
//!
//! Memory in particular is configured here: the in-memory store is unbounded by default, but
//! `[memory]` can cap it (`max_messages`, `max_sessions`) or switch to a durable file store.

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
}

/// `[provider]` — which model/provider to drive.
#[derive(Debug, Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct ProviderSection {
    /// `xai` | `anthropic` | `google` | `claude-cli`.
    pub provider: Option<String>,
    pub model: Option<String>,
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
    /// Only answer these Slack user ids; empty/unset ⇒ answer everyone. The `SLACK_ALLOWED_USERS`
    /// env var (comma-separated) takes precedence.
    pub slack_allowed_users: Option<Vec<String>>,
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
        let config: Config =
            toml::from_str(&text).map_err(|e| format!("parsing config {}: {e}", path.display()))?;
        eprintln!("lavoisier: loaded config from {}", path.display());
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
        merge_copy(&mut cli.rate_limit, self.gateway.rate_limit);
        if cli.api_key.is_empty() {
            if let Some(keys) = &self.gateway.api_keys {
                cli.api_key = keys.clone();
            }
        }
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
    fn parses_gateway_matrix_and_slack_knobs() {
        let cfg: Config = toml::from_str(
            r#"
            [gateway]
            serve_matrix = true
            serve_slack = true
            matrix_state_dir = "/var/lib/lav/matrix"
            matrix_allowed_users = ["@a:hs", "@b:hs"]
            slack_allowed_users = ["U_A"]
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
            cfg.gateway.slack_allowed_users.as_deref(),
            Some(&["U_A".to_string()][..])
        );
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
