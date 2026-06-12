//! Google **Gemini** provider for Lavoisier.
//!
//! Implements [`Provider`] over the native Generative Language API
//! (`POST /v1beta/models/{model}:streamGenerateContent?alt=sse`). Added so Lavoisier can run the
//! *same* model other agents benchmark on (`gemini-3-flash-preview`) with the *same* thinking
//! effort — see `bench/README.md`. This widens the original "Anthropic + xAI native only" scope
//! at the project owner's explicit request (recorded in `RECIPE.md` §1 / `CLAUDE.md`).
//!
//! Like the other adapters this is a thin hand-rolled `reqwest` client — no `google-*` SDK — and it
//! is the only place Gemini's wire format is mapped to the normalised [`Event`] stream. Gemini does
//! its own (implicit) prompt caching server-side, so we advertise `prompt_caching = false` (we emit
//! no request-side cache markers) while still surfacing `cachedContentTokenCount` as `cache_read`.
//!
//! **Thinking effort** is configurable (`thinkingConfig`): a keyword level (`low`/`high`/`dynamic`,
//! Gemini 3) or a numeric token budget (Gemini 2.5) — set via [`GoogleProvider::with_thinking`] or
//! `GOOGLE_THINKING` / the CLI `--thinking` flag. "High" matches the public Dirac refactor suite.

mod sse;

use std::collections::{HashMap, VecDeque};

use async_trait::async_trait;
use bytes::Bytes;
use futures::stream::{self, BoxStream, StreamExt};
use lvz_protocol::{
    Capabilities, ChatRequest, ContentBlock, Event, Message, Provider, ProviderError, Role,
};
use serde_json::{json, Value};

use crate::sse::GeminiSseDecoder;

const DEFAULT_BASE_URL: &str = "https://generativelanguage.googleapis.com";

/// A [`Provider`] backed by the native Gemini Generative Language API.
pub struct GoogleProvider {
    api_key: String,
    base_url: String,
    /// Optional thinking effort: a keyword level (`low`/`high`/`dynamic`) or a numeric budget.
    thinking: Option<String>,
    http: reqwest::Client,
}

impl GoogleProvider {
    /// Construct against the default base URL.
    pub fn new(api_key: impl Into<String>) -> Self {
        Self::with_base_url(api_key, DEFAULT_BASE_URL)
    }

    /// Construct against an explicit base URL (e.g. a proxy or a mock server in tests).
    pub fn with_base_url(api_key: impl Into<String>, base_url: impl Into<String>) -> Self {
        Self {
            api_key: api_key.into(),
            base_url: base_url.into(),
            thinking: None,
            http: reqwest::Client::new(),
        }
    }

    /// Set the thinking effort — a level keyword (`low`/`high`/`dynamic`) or a numeric token budget.
    pub fn with_thinking(mut self, thinking: impl Into<String>) -> Self {
        let t = thinking.into();
        self.thinking = (!t.is_empty()).then_some(t);
        self
    }

    /// Construct from `GOOGLE_API_KEY` (or `GEMINI_API_KEY`), `GOOGLE_BASE_URL` (optional), and
    /// `GOOGLE_THINKING` (optional thinking level/budget).
    pub fn from_env() -> Result<Self, ProviderError> {
        let api_key = std::env::var("GOOGLE_API_KEY")
            .or_else(|_| std::env::var("GEMINI_API_KEY"))
            .map_err(|_| {
                ProviderError::Config("GOOGLE_API_KEY (or GEMINI_API_KEY) is not set".into())
            })?;
        let base_url = std::env::var("GOOGLE_BASE_URL").unwrap_or_else(|_| DEFAULT_BASE_URL.into());
        let mut provider = Self::with_base_url(api_key, base_url);
        if let Ok(thinking) = std::env::var("GOOGLE_THINKING") {
            provider = provider.with_thinking(thinking);
        }
        Ok(provider)
    }
}

#[async_trait]
impl Provider for GoogleProvider {
    async fn stream(
        &self,
        req: ChatRequest,
    ) -> Result<BoxStream<'static, Result<Event, ProviderError>>, ProviderError> {
        let body = build_body(&req, self.thinking.as_deref());
        let url = format!(
            "{}/v1beta/models/{}:streamGenerateContent?alt=sse",
            self.base_url.trim_end_matches('/'),
            req.model,
        );

        let resp = self
            .http
            .post(url)
            .header("x-goog-api-key", &self.api_key)
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
            decoder: GeminiSseDecoder::default(),
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
            // Gemini caches implicitly server-side; we emit no request-side cache markers (cache
            // hits still surface as `cache_read` in usage), so we don't advertise prompt_caching.
            prompt_caching: false,
            extended_thinking: true,
            parallel_tool_use: true,
            server_side_tools: false,
        }
    }
}

struct SseState {
    body: BoxStream<'static, reqwest::Result<Bytes>>,
    decoder: GeminiSseDecoder,
    pending: VecDeque<Result<Event, ProviderError>>,
    drained: bool,
}

/// Build the `generateContent` request body from a normalised [`ChatRequest`]. The model id lives
/// in the URL path, not the body.
fn build_body(req: &ChatRequest, thinking: Option<&str>) -> Value {
    let mut body = json!({ "contents": build_contents(&req.messages) });

    if let Some(system) = &req.system {
        body["systemInstruction"] = json!({ "parts": [ { "text": system.text } ] });
    }
    if !req.tools.is_empty() {
        let decls: Vec<Value> = req
            .tools
            .iter()
            .map(|t| {
                json!({
                    "name": t.name,
                    "description": t.description,
                    "parameters": t.schema,
                })
            })
            .collect();
        body["tools"] = json!([ { "functionDeclarations": decls } ]);
    }

    let mut generation = json!({ "maxOutputTokens": req.max_tokens });
    if let Some(t) = req.temperature {
        generation["temperature"] = json!(t);
    }
    if let Some(thinking) = thinking {
        // A bare integer is a token budget (Gemini 2.5); anything else is a level (Gemini 3).
        generation["thinkingConfig"] = match thinking.parse::<i64>() {
            Ok(budget) => json!({ "thinkingBudget": budget }),
            Err(_) => json!({ "thinkingLevel": thinking }),
        };
    }
    body["generationConfig"] = generation;

    body
}

/// Map the conversation to Gemini `contents`. Tool results carry only a `tool_use_id`, but Gemini
/// keys `functionResponse` by name, so we first index every assistant tool call's id → name.
fn build_contents(messages: &[Message]) -> Value {
    let mut id_to_name: HashMap<&str, &str> = HashMap::new();
    for m in messages {
        for block in &m.content {
            if let ContentBlock::ToolUse { id, name, .. } = block {
                id_to_name.insert(id, name);
            }
        }
    }

    let contents: Vec<Value> = messages
        .iter()
        .map(|m| {
            let role = match m.role {
                Role::User => "user",
                Role::Assistant => "model",
            };
            let parts: Vec<Value> = m
                .content
                .iter()
                .map(|b| content_part(b, &id_to_name))
                .collect();
            json!({ "role": role, "parts": parts })
        })
        .collect();
    Value::Array(contents)
}

fn content_part(block: &ContentBlock, id_to_name: &HashMap<&str, &str>) -> Value {
    match block {
        ContentBlock::Text { text, .. } => json!({ "text": text }),
        // Gemini has no inbound "thinking" part; echo it as text (rare on the outbound path).
        ContentBlock::Thinking { text } => json!({ "text": text }),
        ContentBlock::ToolUse { id, name, input } => {
            let mut part = json!({ "functionCall": { "name": name, "args": input } });
            // Restore the `thoughtSignature` the decoder smuggled into the id (`call_{n}#{sig}`),
            // required by Gemini 3 thinking when a call is resent. Absent for non-thinking turns.
            if let Some((_, sig)) = id.split_once('#') {
                part["thoughtSignature"] = json!(sig);
            }
            part
        }
        ContentBlock::ToolResult {
            tool_use_id,
            content,
            is_error,
        } => {
            let name = id_to_name.get(tool_use_id.as_str()).copied().unwrap_or("");
            let response = if *is_error {
                json!({ "error": content })
            } else {
                json!({ "result": content })
            };
            json!({ "functionResponse": { "name": name, "response": response } })
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use lvz_protocol::{SystemPrompt, ToolDef};

    fn req() -> ChatRequest {
        let mut r = ChatRequest::new("gemini-3-flash-preview")
            .max_tokens(256)
            .push(Message::user("hi"));
        r.system = Some(SystemPrompt {
            text: "be terse".into(),
            cache: false,
        });
        r.tools.push(ToolDef {
            name: "read_file".into(),
            description: "read a file".into(),
            schema: json!({ "type": "object", "properties": { "path": { "type": "string" } } }),
            cache: false,
        });
        r
    }

    #[test]
    fn maps_system_tools_and_generation_config() {
        let body = build_body(&req(), Some("high"));
        assert_eq!(body["systemInstruction"]["parts"][0]["text"], "be terse");
        assert_eq!(
            body["tools"][0]["functionDeclarations"][0]["name"],
            "read_file"
        );
        assert_eq!(body["generationConfig"]["maxOutputTokens"], 256);
        assert_eq!(
            body["generationConfig"]["thinkingConfig"]["thinkingLevel"],
            "high"
        );
        assert_eq!(body["contents"][0]["role"], "user");
        assert_eq!(body["contents"][0]["parts"][0]["text"], "hi");
    }

    #[test]
    fn numeric_thinking_is_a_budget_not_a_level() {
        let body = build_body(&req(), Some("2048"));
        assert_eq!(
            body["generationConfig"]["thinkingConfig"]["thinkingBudget"],
            2048
        );
        assert!(body["generationConfig"]["thinkingConfig"]["thinkingLevel"].is_null());
    }

    #[test]
    fn tool_use_and_result_round_trip_to_function_call_and_response() {
        let messages = vec![
            Message::user("read it"),
            Message {
                role: Role::Assistant,
                content: vec![ContentBlock::ToolUse {
                    id: "call_0".into(),
                    name: "read_file".into(),
                    input: json!({ "path": "a.rs" }),
                }],
            },
            Message {
                role: Role::User,
                content: vec![ContentBlock::ToolResult {
                    tool_use_id: "call_0".into(),
                    content: "fn main() {}".into(),
                    is_error: false,
                }],
            },
        ];
        let contents = build_contents(&messages);
        assert_eq!(contents[1]["role"], "model");
        assert_eq!(contents[1]["parts"][0]["functionCall"]["name"], "read_file");
        assert_eq!(
            contents[1]["parts"][0]["functionCall"]["args"]["path"],
            "a.rs"
        );
        // The response is keyed back to the tool's *name*, resolved from the call id.
        assert_eq!(
            contents[2]["parts"][0]["functionResponse"]["name"],
            "read_file"
        );
        assert_eq!(
            contents[2]["parts"][0]["functionResponse"]["response"]["result"],
            "fn main() {}"
        );
    }

    #[test]
    fn thought_signature_smuggled_in_id_is_echoed_back_on_the_function_call() {
        let messages = vec![Message {
            role: Role::Assistant,
            content: vec![ContentBlock::ToolUse {
                id: "call_0#SIG123".into(),
                name: "shell".into(),
                input: json!({ "command": "ls" }),
            }],
        }];
        let contents = build_contents(&messages);
        let part = &contents[0]["parts"][0];
        assert_eq!(part["functionCall"]["name"], "shell");
        // The signature is restored to the part (Gemini 3 thinking requires it on resend); the
        // synthetic `#SIG` suffix never leaks into the functionCall itself.
        assert_eq!(part["thoughtSignature"], "SIG123");
        assert!(part["functionCall"]["name"].as_str() == Some("shell"));
    }
}
