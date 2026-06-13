//! The normalised event stream — the semantic layer every provider maps onto.
//!
//! Each provider adapter is the *only* place that translates its wire format into these
//! variants (`RECIPE.md` §5.2): Anthropic SSE `content_block_delta`, xAI gRPC v6 outputs,
//! and the OpenAI-compat fallback all converge here. Nothing downstream of a provider sees
//! a wire protocol.

use serde::{Deserialize, Serialize};

/// A single normalised event in a streamed model turn.
///
/// Adjacently tagged (`{"kind": …, "data": …}`) so every variant — including the newtype
/// variants wrapping a primitive ([`TextDelta`](Event::TextDelta), [`Done`](Event::Done)) —
/// round-trips through JSON. This is the on-the-wire shape gateways stream to their channels.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "data", rename_all = "snake_case")]
pub enum Event {
    /// Incremental assistant text.
    TextDelta(String),
    /// Incremental extended-thinking text (Anthropic). Providers without thinking never emit this.
    Thinking(String),
    /// A tool call has begun; `id` correlates the following deltas and end.
    ToolUseStart { id: String, name: String },
    /// Incremental tool-argument JSON for the call identified by `id`.
    ToolUseDelta { id: String, json: String },
    /// The tool call identified by `id` is complete; its argument JSON is now whole.
    ToolUseEnd { id: String },
    /// Token accounting, including cache hits. May arrive mid-stream and/or at the end.
    Usage(Usage),
    /// Terminal event: the turn finished for the given reason.
    Done(StopReason),
}

/// Token accounting for a turn. Cache fields are zero on providers without prompt caching.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Usage {
    pub input_tokens: u64,
    pub output_tokens: u64,
    /// Tokens written to the cache this turn (Anthropic `cache_creation_input_tokens`).
    pub cache_creation_tokens: u64,
    /// Tokens served from the cache this turn (Anthropic `cache_read_input_tokens`).
    pub cache_read_tokens: u64,
}

impl Usage {
    /// Total billable input + output tokens (cache-creation counted as input).
    pub fn total(&self) -> u64 {
        self.input_tokens + self.output_tokens
    }

    /// Add another turn's usage into this one — the running total across round-trips (§6.4).
    pub fn accumulate(&mut self, other: &Usage) {
        self.input_tokens += other.input_tokens;
        self.output_tokens += other.output_tokens;
        self.cache_creation_tokens += other.cache_creation_tokens;
        self.cache_read_tokens += other.cache_read_tokens;
    }

    /// Fraction of input tokens served from cache, in `[0, 1]`. Zero when no input tokens.
    pub fn cache_hit_rate(&self) -> f32 {
        let billed_input = self.input_tokens + self.cache_read_tokens;
        if billed_input == 0 {
            0.0
        } else {
            self.cache_read_tokens as f32 / billed_input as f32
        }
    }
}

/// Why a turn stopped.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum StopReason {
    /// Model finished its turn naturally.
    EndTurn,
    /// Hit the `max_tokens` ceiling.
    MaxTokens,
    /// Stopped to hand control back for tool execution.
    ToolUse,
    /// Matched a caller-supplied stop sequence.
    StopSequence,
    /// The model declined the request for safety reasons (Anthropic `refusal`). Terminal.
    Refusal,
    /// The provider paused a server-side tool loop; resend the turn to continue (Anthropic
    /// `pause_turn`). Not terminal — the caller re-submits to let the model carry on.
    PauseTurn,
    /// Anything provider-specific not captured above.
    Other(String),
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_event_variant_roundtrips_through_json() {
        let events = vec![
            Event::TextDelta("hello".into()),
            Event::Thinking("hmm".into()),
            Event::ToolUseStart {
                id: "call_1".into(),
                name: "shell".into(),
            },
            Event::ToolUseDelta {
                id: "call_1".into(),
                json: "{\"cmd\":\"ls\"}".into(),
            },
            Event::ToolUseEnd {
                id: "call_1".into(),
            },
            Event::Usage(Usage {
                input_tokens: 1,
                output_tokens: 2,
                cache_creation_tokens: 3,
                cache_read_tokens: 4,
            }),
            Event::Done(StopReason::EndTurn),
            Event::Done(StopReason::Other("time_limit".into())),
        ];
        for ev in events {
            let json = serde_json::to_string(&ev).expect("serialize");
            let back: Event = serde_json::from_str(&json).expect("deserialize");
            assert_eq!(ev, back, "roundtrip mismatch for {json}");
        }
    }

    #[test]
    fn text_delta_has_the_adjacently_tagged_wire_shape() {
        let json = serde_json::to_value(Event::TextDelta("hi".into())).unwrap();
        assert_eq!(json["kind"], "text_delta");
        assert_eq!(json["data"], "hi");
    }
}
