//! Token-efficient diffs (§6.1): emit minimal unified hunks, never full-file
//! rewrites. Small context radii keep the token cost proportional to what actually changed.

use similar::TextDiff;

/// A compact unified diff between `old` and `new`, with `context` unchanged lines around each
/// hunk. Returns an empty string when the inputs are identical.
pub fn unified_diff(old: &str, new: &str, context: usize) -> String {
    if old == new {
        return String::new();
    }
    TextDiff::from_lines(old, new)
        .unified_diff()
        .context_radius(context)
        .header("a", "b")
        .to_string()
}

/// The number of changed (inserted or deleted) lines between `old` and `new` — a cheap
/// proxy for edit size, useful for budgeting and for choosing whole-file vs diff transport.
pub fn changed_lines(old: &str, new: &str) -> usize {
    TextDiff::from_lines(old, new)
        .iter_all_changes()
        .filter(|c| c.tag() != similar::ChangeTag::Equal)
        .count()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn identical_inputs_produce_no_diff() {
        assert_eq!(unified_diff("a\nb\n", "a\nb\n", 1), "");
        assert_eq!(changed_lines("a\nb\n", "a\nb\n"), 0);
    }

    #[test]
    fn diff_shows_only_changed_hunk_with_context() {
        let old = "one\ntwo\nthree\nfour\nfive\n";
        let new = "one\ntwo\nTHREE\nfour\nfive\n";
        let d = unified_diff(old, new, 1);
        assert!(d.contains("-three"));
        assert!(d.contains("+THREE"));
        // With radius 1, distant unchanged lines ("one", "five") are excluded.
        assert!(!d.contains("one"));
        assert!(!d.contains("five"));
    }

    #[test]
    fn changed_lines_counts_inserts_and_deletes() {
        // one line replaced => one delete + one insert.
        assert_eq!(changed_lines("a\nb\nc\n", "a\nB\nc\n"), 2);
    }
}
