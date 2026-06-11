//! `lvz-claude-cli` — an **optional** [`Provider`] that rides Claude Code's `claude -p`
//! (subscription OAuth) instead of the Anthropic API (`RECIPE.md` §8).
//!
//! It spawns `claude -p --output-format stream-json`, feeds the rendered conversation on
//! stdin, and normalises the newline-delimited JSON event stream into [`Event`]s. `claude -p`
//! is itself a full agent (it runs its own tools), so this adapter treats it as an opaque
//! completion: it surfaces assistant **text** and **thinking** and the final **usage**, and
//! ignores the internal tool traffic.
//!
//! Caveats (RECIPE §8), all reflected in [`Capabilities`]:
//! - **No prompt caching** — subscription tokens can't use `cache_control`.
//! - Capped by the monthly Agent SDK credit (from 2026-06-15), then API rates; policy-fragile.
//! - **Personal / low-volume convenience only — never Hermes.** Off by default; the CLI only
//!   builds it when `--provider claude-cli` is chosen explicitly.
//!
//! Not live-verified here (needs a `claude` install + a subscription); the stream-json → Event
//! mapping is unit-tested.

use std::collections::VecDeque;
use std::process::Stdio;

use async_trait::async_trait;
use futures::stream::{self, BoxStream, StreamExt};
use lvz_protocol::{
    Capabilities, ChatRequest, Event, Provider, ProviderError, Role, StopReason, Usage,
};
use serde::Deserialize;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader, Lines};
use tokio::process::{Child, ChildStdout, Command};

const DEFAULT_BIN: &str = "claude";

/// A [`Provider`] backed by the `claude -p` CLI.
pub struct ClaudeCliProvider {
    bin: String,
}

impl ClaudeCliProvider {
    /// Use the `claude` binary on `PATH` (override with `CLAUDE_CLI_BIN`).
    pub fn new() -> Self {
        Self {
            bin: std::env::var("CLAUDE_CLI_BIN").unwrap_or_else(|_| DEFAULT_BIN.into()),
        }
    }

    /// Use an explicit binary path.
    pub fn with_bin(bin: impl Into<String>) -> Self {
        Self { bin: bin.into() }
    }

    /// Infallible today; mirrors the other providers' `from_env` for the CLI's `build()`.
    pub fn from_env() -> Result<Self, ProviderError> {
        Ok(Self::new())
    }
}

impl Default for ClaudeCliProvider {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait]
impl Provider for ClaudeCliProvider {
    async fn stream(
        &self,
        req: ChatRequest,
    ) -> Result<BoxStream<'static, Result<Event, ProviderError>>, ProviderError> {
        let prompt = render_prompt(&req);

        let mut cmd = Command::new(&self.bin);
        cmd.arg("-p")
            .arg("--output-format")
            .arg("stream-json")
            .arg("--verbose")
            .arg("--include-partial-messages")
            .arg("--model")
            .arg(&req.model)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null());
        if let Some(system) = &req.system {
            cmd.arg("--append-system-prompt").arg(&system.text);
        }

        let mut child = cmd.spawn().map_err(|e| {
            ProviderError::Config(format!(
                "failed to spawn `{}` (is Claude Code installed?): {e}",
                self.bin
            ))
        })?;

        // Feed the conversation on stdin, then drop the handle to signal EOF.
        if let Some(mut stdin) = child.stdin.take() {
            stdin
                .write_all(prompt.as_bytes())
                .await
                .map_err(|e| ProviderError::Transport(e.to_string()))?;
        }

        let stdout = child
            .stdout
            .take()
            .ok_or_else(|| ProviderError::Transport("claude -p produced no stdout".into()))?;

        let state = CliState {
            _child: child,
            lines: BufReader::new(stdout).lines(),
            decoder: Decoder::default(),
            pending: VecDeque::new(),
            drained: false,
        };

        let events = stream::unfold(state, |mut st| async move {
            loop {
                if let Some(ev) = st.pending.pop_front() {
                    return Some((ev, st));
                }
                if st.drained {
                    return None;
                }
                match st.lines.next_line().await {
                    Ok(Some(line)) => st.decoder.push_line(&line, &mut st.pending),
                    Ok(None) => {
                        st.decoder.eof(&mut st.pending);
                        st.drained = true;
                    }
                    Err(e) => {
                        st.pending
                            .push_back(Err(ProviderError::Transport(e.to_string())));
                        st.drained = true;
                    }
                }
            }
        });

        Ok(events.boxed())
    }

    fn capabilities(&self) -> Capabilities {
        // Subscription path: no caching, and `claude -p` runs its own tools opaquely, so we
        // advertise none of the optional features.
        Capabilities {
            prompt_caching: false,
            extended_thinking: false,
            parallel_tool_use: false,
            server_side_tools: false,
        }
    }
}

/// Keeps the child alive while its stdout is streamed (dropping `Child` would kill it).
struct CliState {
    _child: Child,
    lines: Lines<BufReader<ChildStdout>>,
    decoder: Decoder,
    pending: VecDeque<Result<Event, ProviderError>>,
    drained: bool,
}

type Sink = VecDeque<Result<Event, ProviderError>>;

/// Render the conversation as a plain-text prompt for `claude -p`. Tool blocks are dropped
/// (`claude -p` has its own tools); the system prompt is passed via `--append-system-prompt`.
fn render_prompt(req: &ChatRequest) -> String {
    let mut out = String::new();
    for m in &req.messages {
        let text = m.text();
        if text.is_empty() {
            continue;
        }
        let role = match m.role {
            Role::User => "User",
            Role::Assistant => "Assistant",
        };
        out.push_str(role);
        out.push_str(": ");
        out.push_str(&text);
        out.push_str("\n\n");
    }
    out
}

/// Incremental decoder for `claude -p`'s newline-delimited stream-json. Prefers partial
/// `stream_event` deltas; falls back to whole `assistant` messages when partials are absent;
/// takes the final usage + stop from the `result` event. Emits exactly one [`Event::Done`].
#[derive(Default)]
struct Decoder {
    saw_partial: bool,
    done_emitted: bool,
}

impl Decoder {
    fn push_line(&mut self, line: &str, out: &mut Sink) {
        let line = line.trim();
        if line.is_empty() {
            return;
        }
        // Unknown / unparseable lines (e.g. the `system` init) are simply ignored.
        let Ok(event) = serde_json::from_str::<CliEvent>(line) else {
            return;
        };
        match event.kind.as_str() {
            "stream_event" => {
                if let Some(inner) = event.event {
                    if inner.kind == "content_block_delta" {
                        if let Some(delta) = inner.delta {
                            if let Some(t) = delta.text.filter(|t| !t.is_empty()) {
                                self.saw_partial = true;
                                out.push_back(Ok(Event::TextDelta(t)));
                            }
                            if let Some(t) = delta.thinking.filter(|t| !t.is_empty()) {
                                self.saw_partial = true;
                                out.push_back(Ok(Event::Thinking(t)));
                            }
                        }
                    }
                }
            }
            "assistant" => {
                // Already streamed token deltas → don't re-emit the assembled message.
                if self.saw_partial {
                    return;
                }
                if let Some(message) = event.message {
                    for block in message.content {
                        match block.kind.as_str() {
                            "text" => {
                                if let Some(t) = block.text.filter(|t| !t.is_empty()) {
                                    out.push_back(Ok(Event::TextDelta(t)));
                                }
                            }
                            "thinking" => {
                                if let Some(t) = block.thinking.filter(|t| !t.is_empty()) {
                                    out.push_back(Ok(Event::Thinking(t)));
                                }
                            }
                            _ => {}
                        }
                    }
                }
            }
            "result" => {
                if let Some(usage) = event.usage {
                    out.push_back(Ok(Event::Usage(usage.into())));
                }
                let stop = if event.is_error.unwrap_or(false) {
                    StopReason::Other("claude_cli_error".into())
                } else {
                    StopReason::EndTurn
                };
                out.push_back(Ok(Event::Done(stop)));
                self.done_emitted = true;
            }
            _ => {}
        }
    }

    fn eof(&mut self, out: &mut Sink) {
        if !self.done_emitted {
            self.done_emitted = true;
            out.push_back(Ok(Event::Done(StopReason::EndTurn)));
        }
    }
}

// --- claude -p stream-json wire types (defensive: every field optional) ---

#[derive(Deserialize)]
struct CliEvent {
    #[serde(rename = "type")]
    kind: String,
    #[serde(default)]
    event: Option<StreamEvent>,
    #[serde(default)]
    message: Option<AssistantMessage>,
    #[serde(default)]
    usage: Option<CliUsage>,
    #[serde(default)]
    is_error: Option<bool>,
}

#[derive(Deserialize)]
struct StreamEvent {
    #[serde(rename = "type")]
    kind: String,
    #[serde(default)]
    delta: Option<BlockDelta>,
}

#[derive(Deserialize)]
struct BlockDelta {
    #[serde(default)]
    text: Option<String>,
    #[serde(default)]
    thinking: Option<String>,
}

#[derive(Deserialize)]
struct AssistantMessage {
    #[serde(default)]
    content: Vec<Block>,
}

#[derive(Deserialize)]
struct Block {
    #[serde(rename = "type")]
    kind: String,
    #[serde(default)]
    text: Option<String>,
    #[serde(default)]
    thinking: Option<String>,
}

#[derive(Deserialize)]
struct CliUsage {
    #[serde(default)]
    input_tokens: u64,
    #[serde(default)]
    output_tokens: u64,
}

impl From<CliUsage> for Usage {
    fn from(u: CliUsage) -> Self {
        // Subscription path reports no cache hits.
        Usage {
            input_tokens: u.input_tokens,
            output_tokens: u.output_tokens,
            cache_creation_tokens: 0,
            cache_read_tokens: 0,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use lvz_protocol::Message;

    fn decode_all(lines: &[&str]) -> Vec<Event> {
        let mut decoder = Decoder::default();
        let mut out = VecDeque::new();
        for line in lines {
            decoder.push_line(line, &mut out);
        }
        decoder.eof(&mut out);
        out.into_iter().map(|e| e.unwrap()).collect()
    }

    #[test]
    fn renders_conversation_with_role_labels() {
        let req = ChatRequest::new("sonnet")
            .push(Message::user("hello"))
            .push(Message::assistant("hi there"))
            .push(Message::user("more"));
        let p = render_prompt(&req);
        assert_eq!(p, "User: hello\n\nAssistant: hi there\n\nUser: more\n\n");
    }

    #[test]
    fn streams_partial_deltas_then_usage_and_done() {
        let events = decode_all(&[
            r#"{"type":"system","subtype":"init","model":"sonnet"}"#,
            r#"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"Hel"}}}"#,
            r#"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"lo"}}}"#,
            r#"{"type":"assistant","message":{"content":[{"type":"text","text":"Hello"}]}}"#,
            r#"{"type":"result","subtype":"success","is_error":false,"usage":{"input_tokens":12,"output_tokens":3}}"#,
        ]);
        // Partial deltas win; the assembled `assistant` message is suppressed (no dup).
        assert_eq!(events[0], Event::TextDelta("Hel".into()));
        assert_eq!(events[1], Event::TextDelta("lo".into()));
        assert!(
            matches!(events[2], Event::Usage(u) if u.input_tokens == 12 && u.output_tokens == 3)
        );
        assert_eq!(events[3], Event::Done(StopReason::EndTurn));
        assert_eq!(events.len(), 4);
    }

    #[test]
    fn falls_back_to_assistant_message_when_no_partials() {
        let events = decode_all(&[
            r#"{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"hmm"},{"type":"text","text":"answer"}]}}"#,
            r#"{"type":"result","subtype":"success","usage":{"input_tokens":5,"output_tokens":2}}"#,
        ]);
        assert_eq!(events[0], Event::Thinking("hmm".into()));
        assert_eq!(events[1], Event::TextDelta("answer".into()));
        assert!(matches!(events[2], Event::Usage(_)));
        assert_eq!(events[3], Event::Done(StopReason::EndTurn));
    }

    #[test]
    fn error_result_maps_to_other_stop_and_eof_guarantees_done() {
        let err = decode_all(&[
            r#"{"type":"result","subtype":"error_max_turns","is_error":true,"usage":{"input_tokens":1,"output_tokens":0}}"#,
        ]);
        assert_eq!(
            err.last().unwrap(),
            &Event::Done(StopReason::Other("claude_cli_error".into()))
        );

        // A truncated stream (no result) still terminates with exactly one Done.
        let truncated = decode_all(&[
            r#"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"hi"}}}"#,
        ]);
        assert_eq!(truncated[0], Event::TextDelta("hi".into()));
        assert_eq!(truncated[1], Event::Done(StopReason::EndTurn));
        assert_eq!(truncated.len(), 2);
    }
}
