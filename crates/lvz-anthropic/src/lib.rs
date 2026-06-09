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
    body
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
            let content: Vec<Value> = m.content.iter().map(build_content_block).collect();
            json!({ "role": role, "content": content })
        })
        .collect::<Vec<_>>();
    Value::Array(arr)
}

fn build_content_block(block: &ContentBlock) -> Value {
    match block {
        ContentBlock::Text { text, cache } => {
            let mut v = json!({ "type": "text", "text": text });
            if *cache {
                v["cache_control"] = cache_control();
            }
            v
        }
        // Re-sending thinking verbatim requires a signature we don't yet track; until M4
        // wires that through, echo it as plain text. Outbound thinking is rare pre-agent.
        ContentBlock::Thinking { text } => json!({ "type": "text", "text": text }),
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
    }
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
}
