//! A cheap, deterministic token estimator for the budget-fixture loop (§6.4–§6.5).
//!
//! This is **not** a provider tokenizer — it is a stable proxy used to compare context sizes
//! across skeleton radii and to gate regressions. Because the budget loop only needs relative,
//! reproducible numbers (baseline vs candidate, radius N vs N+1), a heuristic is sufficient and
//! avoids pulling a model-specific BPE table into CI. Real per-call accounting comes from the
//! providers' `Usage` events at runtime.

/// Estimate the token count of `text`.
///
/// Heuristic: a token boundary occurs between an identifier/number run and any other
/// character, and every non-space punctuation character counts as its own token. This tracks
/// real BPE counts for source code far better than a flat chars/4, while staying deterministic.
pub fn estimate_tokens(text: &str) -> usize {
    let mut tokens = 0usize;
    let mut in_word = false;
    for ch in text.chars() {
        if ch.is_alphanumeric() || ch == '_' {
            if !in_word {
                tokens += 1; // start of a new identifier/number run
                in_word = true;
            }
        } else {
            in_word = false;
            if !ch.is_whitespace() {
                tokens += 1; // each punctuation char is roughly its own token
            }
        }
    }
    tokens
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_and_whitespace_are_zero() {
        assert_eq!(estimate_tokens(""), 0);
        assert_eq!(estimate_tokens("   \n\t "), 0);
    }

    #[test]
    fn counts_words_and_punctuation() {
        // `fn` `add` `(` `a` `,` `b` `)` => 7
        assert_eq!(estimate_tokens("fn add(a, b)"), 7);
    }

    #[test]
    fn elided_body_is_cheaper_than_full_body() {
        let full = "fn f() {\n    let x = compute(1, 2, 3);\n    x\n}";
        let skel = "fn f() { … }";
        assert!(estimate_tokens(skel) < estimate_tokens(full));
    }
}
