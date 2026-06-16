//! The normalised event stream — the semantic layer every provider maps onto.
//!
//! Each provider adapter is the *only* place that translates its wire format into these
//! variants (§5.2): Anthropic SSE `content_block_delta`, xAI gRPC v6 outputs,
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
    /// A **provider-executed** (server-side) tool was invoked by the model — e.g. web search or
    /// code execution. Informational: the agent does not execute these (the provider does).
    ServerToolUse { id: String, name: String },
    /// The result of a provider-executed tool, as a serialized JSON string (search hits, code
    /// stdout/stderr, fetched page, …), correlated by `id`.
    ServerToolResult { id: String, content: String },
    /// A citation the model attached to the preceding span of output (Anthropic document /
    /// web-search citations, emitted as the text is produced). Informational — the agent
    /// forwards it; gateways/CLIs surface it.
    Citation {
        /// The exact text from the source that supports the cited output span.
        cited_text: String,
        /// Human-readable source reference (document title, URL, or `document N`).
        source: String,
    },
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

/// Per-token-class cost multipliers, expressed relative to a fresh input token (= 1.0).
///
/// Turns a raw [`Usage`] into a single **cost-weighted** objective ([`Usage::cost`]) so the
/// agent's budget and the ATO tuner optimise *actual spend*, not a flat token count. This is
/// what makes prompt caching — the project's biggest cost lever (§6) — visible to
/// optimisation: a fresh input token, an output token, a cache *write*, and a cache *read* all
/// cost different amounts, and a flat sum (or one that ignores cache classes outright) hides
/// that. The defaults match Anthropic/xAI list-price ratios, which are also a sensible
/// cross-provider baseline.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct CostWeights {
    pub input: f64,
    pub output: f64,
    pub cache_creation: f64,
    pub cache_read: f64,
}

impl Default for CostWeights {
    /// Anthropic/xAI ratios: output ≈ 5× input, a cache write ≈ 1.25× input, a cache read ≈
    /// 0.1× input. A reasonable default for any caching provider.
    fn default() -> Self {
        Self {
            input: 1.0,
            output: 5.0,
            cache_creation: 1.25,
            cache_read: 0.1,
        }
    }
}

impl CostWeights {
    /// Anthropic list-price ratios (Sonnet/Haiku/Opus all share 1 / 5 / 1.25 / 0.1).
    pub fn anthropic() -> Self {
        Self::default()
    }

    /// xAI (grok) ratios — same input/output 1:5 shape; xAI caches automatically and bills the
    /// cached read cheaply, with no separate request-side cache-write line.
    pub fn xai() -> Self {
        Self::default()
    }

    /// Gemini ratios: a wider output:input spread and a pricier cache read than Anthropic.
    pub fn google() -> Self {
        Self {
            input: 1.0,
            output: 8.0,
            cache_creation: 1.0,
            cache_read: 0.25,
        }
    }

    /// Flat weights — every token class counts the same. Restores the legacy raw-token
    /// objective (and is what providers without real caching effectively use).
    pub fn flat() -> Self {
        Self {
            input: 1.0,
            output: 1.0,
            cache_creation: 1.0,
            cache_read: 1.0,
        }
    }
}

impl Usage {
    /// Raw billable input + output tokens. A flat count for display/diagnostics; the budget and
    /// the ATO objective use the cost-weighted [`cost`](Self::cost) instead. Note this does
    /// **not** include the cache classes (which a caching provider reports separately).
    pub fn total(&self) -> u64 {
        self.input_tokens + self.output_tokens
    }

    /// Cost-weighted total in *fresh-input-token-equivalent* units (rounded). This — not the
    /// flat [`total`](Self::total) — is the objective the agent budget enforces and the ATO
    /// tuner minimises, so caching (cheap reads, pricier writes) and output cost all register.
    pub fn cost(&self, w: &CostWeights) -> u64 {
        (self.input_tokens as f64 * w.input
            + self.output_tokens as f64 * w.output
            + self.cache_creation_tokens as f64 * w.cache_creation
            + self.cache_read_tokens as f64 * w.cache_read)
            .round() as u64
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
            Event::Citation {
                cited_text: "the sky is blue".into(),
                source: "doc.txt".into(),
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
    fn cost_weights_make_caching_visible() {
        let w = CostWeights::default();
        // 100 fresh input + 20 output + 1000 cache write + 5000 cache read.
        let usage = Usage {
            input_tokens: 100,
            output_tokens: 20,
            cache_creation_tokens: 1000,
            cache_read_tokens: 5000,
        };
        // Flat total ignores both cache classes entirely.
        assert_eq!(usage.total(), 120);
        // Cost: 100*1 + 20*5 + 1000*1.25 + 5000*0.1 = 100 + 100 + 1250 + 500 = 1950.
        assert_eq!(usage.cost(&w), 1950);
        // Flat weights reduce cost() to summing every class equally.
        assert_eq!(usage.cost(&CostWeights::flat()), 100 + 20 + 1000 + 5000);
        // A cache-churning run (re-writing instead of reading) is now strictly more expensive,
        // which the flat total() could never show.
        let churn = Usage {
            cache_creation_tokens: 6000,
            cache_read_tokens: 0,
            ..usage
        };
        assert!(churn.cost(&w) > usage.cost(&w));
    }

    #[test]
    fn text_delta_has_the_adjacently_tagged_wire_shape() {
        let json = serde_json::to_value(Event::TextDelta("hi".into())).unwrap();
        assert_eq!(json["kind"], "text_delta");
        assert_eq!(json["data"], "hi");
    }
}
