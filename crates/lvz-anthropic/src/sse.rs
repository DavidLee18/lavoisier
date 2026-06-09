//! Incremental decoder for the Anthropic Messages SSE stream.
//!
//! Anthropic emits an `event:` line plus a `data:` JSON line per event, but the JSON itself
//! carries a `type` field identical to the event name, so we dispatch purely on the `data`
//! payload and ignore the `event:` lines. Byte chunks may split a line, so we buffer until a
//! line is `\n`-complete before decoding (mirrors the xAI decoder).
//!
//! Event mapping (`RECIPE.md` §5.2):
//! - `message_start.usage`            → input / cache-creation / cache-read tokens (accumulated)
//! - `content_block_start` (tool_use) → [`Event::ToolUseStart`]
//! - `content_block_delta.text_delta`        → [`Event::TextDelta`]
//! - `content_block_delta.thinking_delta`    → [`Event::Thinking`]
//! - `content_block_delta.input_json_delta`  → [`Event::ToolUseDelta`]
//! - `content_block_stop` (tool_use) → [`Event::ToolUseEnd`]
//! - `message_delta`                  → stop reason + output tokens
//! - `message_stop`                   → emit accumulated [`Event::Usage`] then [`Event::Done`]

use std::collections::{HashMap, VecDeque};

use lvz_protocol::{Event, ProviderError, StopReason, Usage};
use serde_json::Value;

type Sink = VecDeque<Result<Event, ProviderError>>;

/// Stateful, push-based decoder. Feed bytes with [`push`](AnthropicSseDecoder::push) and
/// signal end-of-stream with [`eof`](AnthropicSseDecoder::eof).
#[derive(Default)]
pub(crate) struct AnthropicSseDecoder {
    buf: Vec<u8>,
    /// content-block index → tool_use id, for correlating `input_json_delta`s and the stop.
    tool_blocks: HashMap<u64, String>,
    usage: Usage,
    stop: Option<StopReason>,
    done_emitted: bool,
}

impl AnthropicSseDecoder {
    pub(crate) fn push(&mut self, bytes: &[u8], out: &mut Sink) {
        self.buf.extend_from_slice(bytes);
        while let Some(pos) = self.buf.iter().position(|&b| b == b'\n') {
            let line: Vec<u8> = self.buf.drain(..=pos).collect();
            let line = String::from_utf8_lossy(&line);
            self.handle_line(line.trim(), out);
        }
    }

    pub(crate) fn eof(&mut self, out: &mut Sink) {
        if !self.buf.is_empty() {
            let line = String::from_utf8_lossy(&self.buf).trim().to_string();
            self.buf.clear();
            self.handle_line(&line, out);
        }
        self.emit_final(out);
    }

    fn handle_line(&mut self, line: &str, out: &mut Sink) {
        let Some(payload) = line.strip_prefix("data:") else {
            return; // `event:` lines, comments, and blank separators are ignored.
        };
        let payload = payload.trim();
        if payload.is_empty() {
            return;
        }
        match serde_json::from_str::<Value>(payload) {
            Ok(v) => self.handle_event(&v, out),
            Err(e) => out.push_back(Err(ProviderError::Decode(e.to_string()))),
        }
    }

    fn handle_event(&mut self, v: &Value, out: &mut Sink) {
        match v["type"].as_str() {
            Some("message_start") => {
                let u = &v["message"]["usage"];
                self.usage.input_tokens += u["input_tokens"].as_u64().unwrap_or(0);
                self.usage.cache_creation_tokens +=
                    u["cache_creation_input_tokens"].as_u64().unwrap_or(0);
                self.usage.cache_read_tokens += u["cache_read_input_tokens"].as_u64().unwrap_or(0);
            }
            Some("content_block_start") => {
                let cb = &v["content_block"];
                if cb["type"].as_str() == Some("tool_use") {
                    let idx = v["index"].as_u64().unwrap_or(0);
                    let id = cb["id"].as_str().unwrap_or_default().to_string();
                    let name = cb["name"].as_str().unwrap_or_default().to_string();
                    self.tool_blocks.insert(idx, id.clone());
                    out.push_back(Ok(Event::ToolUseStart { id, name }));
                }
            }
            Some("content_block_delta") => {
                let idx = v["index"].as_u64().unwrap_or(0);
                let delta = &v["delta"];
                match delta["type"].as_str() {
                    Some("text_delta") => {
                        if let Some(t) = delta["text"].as_str() {
                            out.push_back(Ok(Event::TextDelta(t.to_string())));
                        }
                    }
                    Some("thinking_delta") => {
                        if let Some(t) = delta["thinking"].as_str() {
                            out.push_back(Ok(Event::Thinking(t.to_string())));
                        }
                    }
                    Some("input_json_delta") => {
                        if let (Some(id), Some(json)) =
                            (self.tool_blocks.get(&idx), delta["partial_json"].as_str())
                        {
                            out.push_back(Ok(Event::ToolUseDelta {
                                id: id.clone(),
                                json: json.to_string(),
                            }));
                        }
                    }
                    _ => {}
                }
            }
            Some("content_block_stop") => {
                let idx = v["index"].as_u64().unwrap_or(0);
                if let Some(id) = self.tool_blocks.remove(&idx) {
                    out.push_back(Ok(Event::ToolUseEnd { id }));
                }
            }
            Some("message_delta") => {
                if let Some(reason) = v["delta"]["stop_reason"].as_str() {
                    self.stop = Some(map_stop(reason));
                }
                if let Some(o) = v["usage"]["output_tokens"].as_u64() {
                    self.usage.output_tokens = o;
                }
            }
            Some("message_stop") => self.emit_final(out),
            Some("error") => {
                let message = v["error"]["message"]
                    .as_str()
                    .unwrap_or("unknown stream error")
                    .to_string();
                out.push_back(Err(ProviderError::Transport(format!(
                    "anthropic stream error: {message}"
                ))));
                self.emit_final(out);
            }
            // "ping" and anything unrecognised are no-ops.
            _ => {}
        }
    }

    fn emit_final(&mut self, out: &mut Sink) {
        if self.done_emitted {
            return;
        }
        self.done_emitted = true;
        out.push_back(Ok(Event::Usage(self.usage)));
        let stop = self.stop.take().unwrap_or(StopReason::EndTurn);
        out.push_back(Ok(Event::Done(stop)));
    }
}

fn map_stop(reason: &str) -> StopReason {
    match reason {
        "end_turn" => StopReason::EndTurn,
        "max_tokens" => StopReason::MaxTokens,
        "tool_use" => StopReason::ToolUse,
        "stop_sequence" => StopReason::StopSequence,
        other => StopReason::Other(other.to_string()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn decode_all(input: &str) -> Vec<Event> {
        let mut decoder = AnthropicSseDecoder::default();
        let mut out = VecDeque::new();
        decoder.push(input.as_bytes(), &mut out);
        decoder.eof(&mut out);
        out.into_iter().map(|e| e.unwrap()).collect()
    }

    const TEXT_STREAM: &str = concat!(
        "event: message_start\n",
        "data: {\"type\":\"message_start\",\"message\":{\"usage\":{\"input_tokens\":10,\"cache_read_input_tokens\":4,\"cache_creation_input_tokens\":0,\"output_tokens\":1}}}\n\n",
        "event: content_block_start\n",
        "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}\n\n",
        "event: content_block_delta\n",
        "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hi\"}}\n\n",
        "event: content_block_delta\n",
        "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\" there\"}}\n\n",
        "event: content_block_stop\n",
        "data: {\"type\":\"content_block_stop\",\"index\":0}\n\n",
        "event: message_delta\n",
        "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"},\"usage\":{\"output_tokens\":5}}\n\n",
        "event: message_stop\n",
        "data: {\"type\":\"message_stop\"}\n\n",
    );

    #[test]
    fn decodes_text_with_cache_aware_usage() {
        let events = decode_all(TEXT_STREAM);
        assert_eq!(events[0], Event::TextDelta("Hi".into()));
        assert_eq!(events[1], Event::TextDelta(" there".into()));
        match events[2] {
            Event::Usage(u) => {
                assert_eq!(u.input_tokens, 10);
                assert_eq!(u.output_tokens, 5);
                assert_eq!(u.cache_read_tokens, 4);
            }
            ref other => panic!("expected usage, got {other:?}"),
        }
        assert_eq!(events[3], Event::Done(StopReason::EndTurn));
        assert_eq!(events.len(), 4);
    }

    #[test]
    fn byte_at_a_time_matches_whole_feed() {
        let mut decoder = AnthropicSseDecoder::default();
        let mut out = VecDeque::new();
        for b in TEXT_STREAM.as_bytes() {
            decoder.push(&[*b], &mut out);
        }
        decoder.eof(&mut out);
        let events: Vec<Event> = out.into_iter().map(|e| e.unwrap()).collect();
        assert_eq!(events.len(), 4);
        assert_eq!(events[0], Event::TextDelta("Hi".into()));
        assert_eq!(events[3], Event::Done(StopReason::EndTurn));
    }

    #[test]
    fn streams_a_tool_call_start_delta_end() {
        let input = concat!(
            "data: {\"type\":\"content_block_start\",\"index\":1,\"content_block\":{\"type\":\"tool_use\",\"id\":\"toolu_1\",\"name\":\"read_file\",\"input\":{}}}\n\n",
            "data: {\"type\":\"content_block_delta\",\"index\":1,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"{\\\"path\\\":\"}}\n\n",
            "data: {\"type\":\"content_block_delta\",\"index\":1,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"\\\"a.rs\\\"}\"}}\n\n",
            "data: {\"type\":\"content_block_stop\",\"index\":1}\n\n",
            "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"tool_use\"},\"usage\":{\"output_tokens\":8}}\n\n",
            "data: {\"type\":\"message_stop\"}\n\n",
        );
        let events = decode_all(input);
        assert_eq!(
            events[0],
            Event::ToolUseStart {
                id: "toolu_1".into(),
                name: "read_file".into()
            }
        );
        assert_eq!(
            events[1],
            Event::ToolUseDelta {
                id: "toolu_1".into(),
                json: "{\"path\":".into()
            }
        );
        assert_eq!(
            events[2],
            Event::ToolUseDelta {
                id: "toolu_1".into(),
                json: "\"a.rs\"}".into()
            }
        );
        assert_eq!(
            events[3],
            Event::ToolUseEnd {
                id: "toolu_1".into()
            }
        );
        assert_eq!(events[5], Event::Done(StopReason::ToolUse));
    }
}
