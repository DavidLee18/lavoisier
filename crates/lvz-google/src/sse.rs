//! Incremental decoder for the Gemini `streamGenerateContent?alt=sse` stream.
//!
//! Unlike Anthropic's typed events, each `data:` line is a whole `GenerateContentResponse` chunk:
//! a `candidates[0].content.parts[]` slice plus a cumulative `usageMetadata`. Byte chunks may split
//! a line, so we buffer until a line is `\n`-complete (mirrors the Anthropic/xAI decoders).
//!
//! Mapping (`RECIPE.md` §5.2):
//! - `part.thought == true` + `text`     → [`Event::Thinking`]
//! - `part.text`                         → [`Event::TextDelta`]
//! - `part.functionCall`                 → [`Event::ToolUseStart`] + whole-args [`Event::ToolUseDelta`] + [`Event::ToolUseEnd`]
//!   (Gemini gives no call id, so we synthesise `call_{n}`; args arrive whole, not streamed)
//! - `usageMetadata`                     → [`Event::Usage`] (cumulative → last-wins; `cachedContentTokenCount`
//!   → `cache_read`, `input = prompt − cached`, `output = candidates + thoughts`)
//! - `candidates[0].finishReason`        → [`StopReason`] (overridden to `ToolUse` when any call was emitted)

use std::collections::VecDeque;

use lvz_protocol::{Event, ProviderError, StopReason, Usage};
use serde_json::Value;

type Sink = VecDeque<Result<Event, ProviderError>>;

/// Stateful, push-based decoder. Feed bytes with [`push`](GeminiSseDecoder::push) and signal
/// end-of-stream with [`eof`](GeminiSseDecoder::eof).
#[derive(Default)]
pub(crate) struct GeminiSseDecoder {
    buf: Vec<u8>,
    usage: Usage,
    stop: Option<StopReason>,
    tool_calls: u64,
    done_emitted: bool,
}

impl GeminiSseDecoder {
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
            return; // comments / blank separators
        };
        let payload = payload.trim();
        if payload.is_empty() {
            return;
        }
        match serde_json::from_str::<Value>(payload) {
            Ok(v) => self.handle_chunk(&v, out),
            Err(e) => out.push_back(Err(ProviderError::Decode(e.to_string()))),
        }
    }

    fn handle_chunk(&mut self, v: &Value, out: &mut Sink) {
        if let Some(meta) = v.get("usageMetadata") {
            // Cumulative per chunk → overwrite (last-wins), don't accumulate.
            let prompt = meta["promptTokenCount"].as_u64().unwrap_or(0);
            let cached = meta["cachedContentTokenCount"].as_u64().unwrap_or(0);
            let candidates = meta["candidatesTokenCount"].as_u64().unwrap_or(0);
            let thoughts = meta["thoughtsTokenCount"].as_u64().unwrap_or(0);
            self.usage.cache_read_tokens = cached;
            self.usage.input_tokens = prompt.saturating_sub(cached);
            self.usage.output_tokens = candidates + thoughts;
        }

        let Some(candidate) = v["candidates"].get(0) else {
            return;
        };
        if let Some(parts) = candidate["content"]["parts"].as_array() {
            for part in parts {
                if let Some(call) = part.get("functionCall") {
                    let id = format!("call_{}", self.tool_calls);
                    self.tool_calls += 1;
                    let name = call["name"].as_str().unwrap_or_default().to_string();
                    let args = call
                        .get("args")
                        .cloned()
                        .unwrap_or_else(|| Value::Object(Default::default()));
                    out.push_back(Ok(Event::ToolUseStart {
                        id: id.clone(),
                        name,
                    }));
                    out.push_back(Ok(Event::ToolUseDelta {
                        id: id.clone(),
                        json: args.to_string(),
                    }));
                    out.push_back(Ok(Event::ToolUseEnd { id }));
                } else if let Some(text) = part["text"].as_str() {
                    if part["thought"].as_bool() == Some(true) {
                        out.push_back(Ok(Event::Thinking(text.to_string())));
                    } else {
                        out.push_back(Ok(Event::TextDelta(text.to_string())));
                    }
                }
            }
        }
        if let Some(reason) = candidate["finishReason"].as_str() {
            self.stop = Some(map_finish(reason));
        }
    }

    fn emit_final(&mut self, out: &mut Sink) {
        if self.done_emitted {
            return;
        }
        self.done_emitted = true;
        out.push_back(Ok(Event::Usage(self.usage)));
        // Gemini reports `STOP` even when it emitted function calls; the agent needs `ToolUse`
        // to run them, so a turn that produced any call ends as ToolUse.
        let stop = if self.tool_calls > 0 && matches!(self.stop, None | Some(StopReason::EndTurn)) {
            StopReason::ToolUse
        } else {
            self.stop.take().unwrap_or(StopReason::EndTurn)
        };
        out.push_back(Ok(Event::Done(stop)));
    }
}

fn map_finish(reason: &str) -> StopReason {
    match reason {
        "STOP" => StopReason::EndTurn,
        "MAX_TOKENS" => StopReason::MaxTokens,
        other => StopReason::Other(other.to_string()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn decode_all(input: &str) -> Vec<Event> {
        let mut decoder = GeminiSseDecoder::default();
        let mut out = VecDeque::new();
        decoder.push(input.as_bytes(), &mut out);
        decoder.eof(&mut out);
        out.into_iter().map(|e| e.unwrap()).collect()
    }

    const TEXT_STREAM: &str = concat!(
        "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"Hi\"}],\"role\":\"model\"}}],\"usageMetadata\":{\"promptTokenCount\":10,\"cachedContentTokenCount\":4,\"candidatesTokenCount\":1}}\n\n",
        "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\" there\"}],\"role\":\"model\"},\"finishReason\":\"STOP\"}],\"usageMetadata\":{\"promptTokenCount\":10,\"cachedContentTokenCount\":4,\"candidatesTokenCount\":5,\"thoughtsTokenCount\":7}}\n\n",
    );

    #[test]
    fn decodes_text_with_cache_and_thinking_aware_usage() {
        let events = decode_all(TEXT_STREAM);
        assert_eq!(events[0], Event::TextDelta("Hi".into()));
        assert_eq!(events[1], Event::TextDelta(" there".into()));
        match events[2] {
            Event::Usage(u) => {
                assert_eq!(u.input_tokens, 6); // 10 prompt − 4 cached
                assert_eq!(u.cache_read_tokens, 4);
                assert_eq!(u.output_tokens, 12); // 5 candidates + 7 thoughts
            }
            ref other => panic!("expected usage, got {other:?}"),
        }
        assert_eq!(events[3], Event::Done(StopReason::EndTurn));
        assert_eq!(events.len(), 4);
    }

    #[test]
    fn separates_thinking_parts_from_answer_text() {
        let input = "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"reasoning\",\"thought\":true},{\"text\":\"answer\"}]},\"finishReason\":\"STOP\"}]}\n\n";
        let events = decode_all(input);
        assert_eq!(events[0], Event::Thinking("reasoning".into()));
        assert_eq!(events[1], Event::TextDelta("answer".into()));
    }

    #[test]
    fn function_call_becomes_start_delta_end_and_tool_use_stop() {
        let input = "data: {\"candidates\":[{\"content\":{\"parts\":[{\"functionCall\":{\"name\":\"shell\",\"args\":{\"command\":\"ls\"}}}]},\"finishReason\":\"STOP\"}]}\n\n";
        let events = decode_all(input);
        assert_eq!(
            events[0],
            Event::ToolUseStart {
                id: "call_0".into(),
                name: "shell".into()
            }
        );
        assert_eq!(
            events[1],
            Event::ToolUseDelta {
                id: "call_0".into(),
                json: "{\"command\":\"ls\"}".into()
            }
        );
        assert_eq!(
            events[2],
            Event::ToolUseEnd {
                id: "call_0".into()
            }
        );
        // STOP + a function call ⇒ the turn ends as ToolUse so the agent runs it.
        assert_eq!(events.last().unwrap(), &Event::Done(StopReason::ToolUse));
    }

    #[test]
    fn byte_at_a_time_matches_whole_feed() {
        let mut decoder = GeminiSseDecoder::default();
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
}
