//! Anthropic provider for Lavoisier.
//!
//! Implements [`Provider`] over the **native** Messages API (`POST /v1/messages`,
//! `stream: true`). The native path is required to keep prompt caching and extended thinking
//! (`RECIPE.md` §1, §6.2, §8) — Anthropic's OpenAI-compat shim drops both, which is exactly
//! why this crate hand-rolls a thin `reqwest` adapter rather than depending on a stale
//! community crate.
//!
//! Caching: a [`cache_control: ephemeral`] marker is attached to any system prompt, tool
//! definition, or content block whose protocol-level `cache` flag is set, placing a cache
//! breakpoint at the end of the stable prefix. The agent (not this crate) decides where that
//! boundary is by setting the flags.

mod sse;

use std::collections::VecDeque;

use async_trait::async_trait;
use bytes::Bytes;
use futures::stream::{self, BoxStream, StreamExt};
use lvz_protocol::{
    Capabilities, ChatRequest, ContentBlock, Event, Message, Provider, ProviderError, Role,
    SystemPrompt, ToolDef,
};
use serde_json::{json, Value};

use crate::sse::AnthropicSseDecoder;

const DEFAULT_BASE_URL: &str = "https://api.anthropic.com";
const ANTHROPIC_VERSION: &str = "2023-06-01";

/// A [`Provider`] backed by the native Anthropic Messages API.
pub struct AnthropicProvider {
    api_key: String,
    base_url: String,
    http: reqwest::Client,
}

impl AnthropicProvider {
    /// Construct against the default base URL (`https://api.anthropic.com`).
    pub fn new(api_key: impl Into<String>) -> Self {
        Self::with_base_url(api_key, DEFAULT_BASE_URL)
    }

    /// Construct against an explicit base URL (e.g. a proxy or a mock server in tests).
    pub fn with_base_url(api_key: impl Into<String>, base_url: impl Into<String>) -> Self {
        Self {
            api_key: api_key.into(),
            base_url: base_url.into(),
            http: reqwest::Client::new(),
        }
    }

    /// Construct from `ANTHROPIC_API_KEY` (required) and `ANTHROPIC_BASE_URL` (optional).
    pub fn from_env() -> Result<Self, ProviderError> {
        let api_key = std::env::var("ANTHROPIC_API_KEY")
            .map_err(|_| ProviderError::Config("ANTHROPIC_API_KEY is not set".into()))?;
        let base_url =
            std::env::var("ANTHROPIC_BASE_URL").unwrap_or_else(|_| DEFAULT_BASE_URL.into());
        Ok(Self::with_base_url(api_key, base_url))
    }
}

#[async_trait]
impl Provider for AnthropicProvider {
    async fn stream(
        &self,
        req: ChatRequest,
    ) -> Result<BoxStream<'static, Result<Event, ProviderError>>, ProviderError> {
        let body = build_body(&req);
        let url = format!("{}/v1/messages", self.base_url.trim_end_matches('/'));

        let resp = self
            .http
            .post(url)
            .header("x-api-key", &self.api_key)
            .header("anthropic-version", ANTHROPIC_VERSION)
            .json(&body)
            .send()
            .await
            .map_err(|e| ProviderError::Transport(e.to_string()))?;

        let status = resp.status();
        if !status.is_success() {
            let message = resp.text().await.unwrap_or_default();
            return Err(ProviderError::Api {
                status: status.as_u16(),
                message,
            });
        }

        let state = SseState {
            body: resp.bytes_stream().boxed(),
            decoder: AnthropicSseDecoder::default(),
            pending: VecDeque::new(),
            drained: false,
        };

        let events = stream::unfold(state, |mut st| async move {
            loop {
                if let Some(event) = st.pending.pop_front() {
                    return Some((event, st));
                }
                if st.drained {
                    return None;
                }
                match st.body.next().await {
                    Some(Ok(chunk)) => st.decoder.push(&chunk, &mut st.pending),
                    Some(Err(e)) => {
                        st.pending
                            .push_back(Err(ProviderError::Transport(e.to_string())));
                        st.drained = true;
                    }
                    None => {
                        st.decoder.eof(&mut st.pending);
                        st.drained = true;
                    }
                }
            }
        });

        Ok(events.boxed())
    }

    fn capabilities(&self) -> Capabilities {
        Capabilities {
            prompt_caching: true,
            extended_thinking: true,
            parallel_tool_use: true,
            server_side_tools: false,
        }
    }
}

struct SseState {
    body: BoxStream<'static, reqwest::Result<Bytes>>,
    decoder: AnthropicSseDecoder,
    pending: VecDeque<Result<Event, ProviderError>>,
    drained: bool,
}

/// The ephemeral cache-control marker placed at a stable-prefix breakpoint.
fn cache_control() -> Value {
    json!({ "type": "ephemeral" })
}

/// Build the Messages API request body from a normalised [`ChatRequest`].
fn build_body(req: &ChatRequest) -> Value {
    let mut body = json!({
        "model": req.model,
        "max_tokens": req.max_tokens,
        "messages": build_messages(&req.messages),
        "stream": true,
    });
    if let Some(system) = req.system.as_ref().map(build_system) {
        body["system"] = system;
    }
    if !req.tools.is_empty() {
        body["tools"] = build_tools(&req.tools);
    }
    if let Some(t) = req.temperature {
        body["temperature"] = json!(t);
    }
    mark_conversation_tail(&mut body);
    body
}

/// Anthropic caps a request at **4** `cache_control` breakpoints. The static prefix (system +
/// last tool def + repo-skeleton block) uses up to 3; this spends the spare one on the **tail of
/// the conversation** — the last content block of the last message — so the whole transcript prefix
/// bills as `cache_read` on the next round-trip instead of full-price fresh input (the rolling-cache
/// pattern). It pays a one-time cache *write* on this turn to save the (larger) *read* next turn.
/// No-op when the breakpoint budget is already spent or there is no message content to mark.
fn mark_conversation_tail(body: &mut Value) {
    const MAX_BREAKPOINTS: usize = 4;
    if count_cache_breakpoints(body) >= MAX_BREAKPOINTS {
        return;
    }
    if let Some(last_msg) = body["messages"].as_array_mut().and_then(|m| m.last_mut()) {
        if let Some(last_block) = last_msg["content"]
            .as_array_mut()
            .and_then(|c| c.last_mut())
        {
            if last_block.get("cache_control").is_none() {
                last_block["cache_control"] = cache_control();
            }
        }
    }
}

/// Count `cache_control` markers already present across system, tools, and message content.
fn count_cache_breakpoints(body: &Value) -> usize {
    fn count(v: &Value) -> usize {
        match v {
            Value::Object(map) => {
                let here = map.contains_key("cache_control") as usize;
                here + map
                    .iter()
                    .filter(|(k, _)| *k != "cache_control")
                    .map(|(_, val)| count(val))
                    .sum::<usize>()
            }
            Value::Array(arr) => arr.iter().map(count).sum(),
            _ => 0,
        }
    }
    ["system", "tools", "messages"]
        .iter()
        .map(|k| count(&body[*k]))
        .sum()
}

/// System prompt as a one-element text-block array, so a cache breakpoint can attach to it.
fn build_system(system: &SystemPrompt) -> Value {
    let mut block = json!({ "type": "text", "text": system.text });
    if system.cache {
        block["cache_control"] = cache_control();
    }
    json!([block])
}

fn build_messages(messages: &[Message]) -> Value {
    let arr = messages
        .iter()
        .map(|m| {
            let role = match m.role {
                Role::User => "user",
                Role::Assistant => "assistant",
            };
            let content: Vec<Value> = m.content.iter().filter_map(build_content_block).collect();
            json!({ "role": role, "content": content })
        })
        .collect::<Vec<_>>();
    Value::Array(arr)
}

/// Map one normalised block to its Messages-API JSON, or `None` to omit it.
///
/// Prior-turn **thinking is dropped**, not re-sent. Echoing it back (verbatim or as text) would
/// re-bill those tokens every round-trip; the cheaper *and* correct choice is to omit it (the
/// Messages API does not require past thinking blocks once a turn's tool loop has closed). Caching
/// thinking would still cost cache-read tokens, so dropping it is strictly the most token-efficient
/// option.
fn build_content_block(block: &ContentBlock) -> Option<Value> {
    Some(match block {
        ContentBlock::Text { text, cache } => {
            let mut v = json!({ "type": "text", "text": text });
            if *cache {
                v["cache_control"] = cache_control();
            }
            v
        }
        ContentBlock::Thinking { .. } => return None,
        ContentBlock::ToolUse { id, name, input } => {
            json!({ "type": "tool_use", "id": id, "name": name, "input": input })
        }
        ContentBlock::ToolResult {
            tool_use_id,
            content,
            is_error,
        } => {
            let mut v = json!({
                "type": "tool_result",
                "tool_use_id": tool_use_id,
                "content": content,
            });
            if *is_error {
                v["is_error"] = json!(true);
            }
            v
        }
    })
}

fn build_tools(tools: &[ToolDef]) -> Value {
    let arr = tools
        .iter()
        .map(|t| {
            let mut v = json!({
                "name": t.name,
                "description": t.description,
                "input_schema": t.schema,
            });
            if t.cache {
                v["cache_control"] = cache_control();
            }
            v
        })
        .collect::<Vec<_>>();
    Value::Array(arr)
}

#[cfg(test)]
mod tests {
    use super::*;
    use lvz_protocol::ContentBlock;

    #[test]
    fn system_and_tools_carry_cache_control_when_flagged() {
        let mut req = ChatRequest::new("claude-sonnet-4-6").push(Message::user("hi"));
        req.system = Some(SystemPrompt {
            text: "stable rules".into(),
            cache: true,
        });
        req.tools.push(ToolDef {
            name: "read_file".into(),
            description: "read a file".into(),
            schema: json!({"type": "object"}),
            cache: true,
        });

        let body = build_body(&req);
        assert_eq!(body["system"][0]["cache_control"]["type"], "ephemeral");
        assert_eq!(body["tools"][0]["cache_control"]["type"], "ephemeral");
        assert_eq!(body["tools"][0]["input_schema"]["type"], "object");
        assert_eq!(body["stream"], true);
    }

    #[test]
    fn uncached_blocks_omit_cache_control() {
        let req = ChatRequest::new("claude-sonnet-4-6")
            .system("volatile")
            .push(Message::user("hi"));
        let body = build_body(&req);
        assert!(body["system"][0]["cache_control"].is_null());
    }

    #[test]
    fn tool_result_blocks_round_trip_into_anthropic_shape() {
        let msg = Message {
            role: Role::User,
            content: vec![ContentBlock::ToolResult {
                tool_use_id: "toolu_9".into(),
                content: "ok".into(),
                is_error: false,
            }],
        };
        let body = build_body(&ChatRequest::new("claude-sonnet-4-6").push(msg));
        let block = &body["messages"][0]["content"][0];
        assert_eq!(block["type"], "tool_result");
        assert_eq!(block["tool_use_id"], "toolu_9");
        assert!(block["is_error"].is_null()); // omitted when false
    }

    #[test]
    fn conversation_tail_gets_rolling_cache_breakpoint() {
        // A multi-turn transcript: the last block of the last message should carry the rolling
        // breakpoint so the whole prefix bills as cache_read next round-trip.
        let req = ChatRequest::new("claude-sonnet-4-6")
            .push(Message::user("do the task"))
            .push(Message::assistant("on it"))
            .push(Message::user("more context here"));
        let body = build_body(&req);
        let msgs = body["messages"].as_array().unwrap();
        let last = msgs.last().unwrap();
        let last_block = last["content"].as_array().unwrap().last().unwrap();
        assert_eq!(
            last_block["cache_control"]["type"], "ephemeral",
            "the conversation tail must carry the rolling cache breakpoint"
        );
        // Earlier messages stay uncached (the breakpoint is only on the tail).
        assert!(msgs[0]["content"][0]["cache_control"].is_null());
    }

    #[test]
    fn thinking_blocks_are_dropped_from_resent_history() {
        let msg = Message {
            role: Role::Assistant,
            content: vec![
                ContentBlock::Thinking {
                    text: "lots of reasoning we must not re-bill".into(),
                },
                ContentBlock::text("the answer"),
            ],
        };
        let body = build_body(&ChatRequest::new("claude-sonnet-4-6").push(msg));
        let content = body["messages"][0]["content"].as_array().unwrap();
        assert_eq!(content.len(), 1, "thinking block must be omitted");
        assert_eq!(content[0]["type"], "text");
        assert_eq!(content[0]["text"], "the answer");
        let serialized = body.to_string();
        assert!(
            !serialized.contains("re-bill"),
            "thinking text must not be re-sent in any form"
        );
    }

    #[test]
    fn cache_breakpoints_never_exceed_four() {
        // Saturate the static prefix with breakpoints (system + tool + two cached text blocks),
        // then assert the rolling-tail logic refuses to add a 5th.
        let mut req = ChatRequest::new("claude-sonnet-4-6").push(Message {
            role: Role::User,
            content: vec![
                ContentBlock::Text {
                    text: "skeleton".into(),
                    cache: true,
                },
                ContentBlock::Text {
                    text: "task".into(),
                    cache: true,
                },
                ContentBlock::text("uncached tail"),
            ],
        });
        req.system = Some(SystemPrompt {
            text: "rules".into(),
            cache: true,
        });
        req.tools.push(ToolDef {
            name: "t".into(),
            description: "d".into(),
            schema: json!({"type": "object"}),
            cache: true,
        });
        let body = build_body(&req);
        assert_eq!(
            count_cache_breakpoints(&body),
            4,
            "must cap at 4 breakpoints"
        );
        // The uncached tail block stays uncached because the budget was already spent.
        assert!(body["messages"][0]["content"][2]["cache_control"].is_null());
    }
}
