//! Rough USD cost estimation for the footer, so the TUI can show real spend instead of an abstract
//! token-equivalent.
//!
//! Prices are **approximate list prices in USD per 1M tokens**, matched by model-name substring.
//! They drift — treat the footer's `$` as an estimate (it's prefixed `~`), and update the table here
//! when list prices change. An unrecognised model yields `None`, and the footer falls back to a raw
//! token count.

use lvz_protocol::Usage;

/// USD per 1M tokens for one model's four token classes.
struct Price {
    input: f64,
    output: f64,
    cache_read: f64,
    cache_write: f64,
}

/// Look up a model's price by name substring (case-insensitive). Ordered most-specific first.
fn lookup(model: &str) -> Option<Price> {
    let m = model.to_lowercase();
    let p = |input, output, cache_read, cache_write| Price {
        input,
        output,
        cache_read,
        cache_write,
    };
    Some(match () {
        // Anthropic
        _ if m.contains("opus") => p(15.0, 75.0, 1.5, 18.75),
        _ if m.contains("sonnet") => p(3.0, 15.0, 0.30, 3.75),
        _ if m.contains("haiku") => p(0.80, 4.0, 0.08, 1.0),
        // xAI
        _ if m.contains("grok") && m.contains("mini") => p(0.30, 0.50, 0.075, 0.30),
        _ if m.contains("grok") => p(3.0, 15.0, 0.75, 3.75),
        // Google
        _ if m.contains("gemini") && m.contains("flash") => p(0.30, 2.5, 0.075, 0.30),
        _ if m.contains("gemini") => p(1.25, 10.0, 0.31, 1.625),
        _ => return None,
    })
}

/// Estimate the USD spent for `usage` on `model`, or `None` if the model isn't in the table.
pub fn estimate_usd(model: &str, usage: &Usage) -> Option<f64> {
    let p = lookup(model)?;
    Some(
        (usage.input_tokens as f64 * p.input
            + usage.output_tokens as f64 * p.output
            + usage.cache_read_tokens as f64 * p.cache_read
            + usage.cache_creation_tokens as f64 * p.cache_write)
            / 1_000_000.0,
    )
}

/// A compact token count for the footer (`1234` → `1.2k`).
pub fn fmt_tokens(n: u64) -> String {
    if n >= 1000 {
        format!("{:.1}k", n as f64 / 1000.0)
    } else {
        n.to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn known_models_price_out() {
        let usage = Usage {
            input_tokens: 1_000_000,
            output_tokens: 1_000_000,
            ..Default::default()
        };
        // Sonnet: $3 in + $15 out per 1M = $18.
        let cost = estimate_usd("claude-sonnet-4", &usage).unwrap();
        assert!((cost - 18.0).abs() < 1e-9, "got {cost}");
        // Opus is pricier than Sonnet for identical usage.
        assert!(estimate_usd("claude-opus-4", &usage).unwrap() > cost);
    }

    #[test]
    fn unknown_model_has_no_estimate() {
        assert!(estimate_usd("some-random-model", &Usage::default()).is_none());
    }

    #[test]
    fn token_formatting() {
        assert_eq!(fmt_tokens(950), "950");
        assert_eq!(fmt_tokens(1500), "1.5k");
    }
}
