//! Hash-anchored edits (`RECIPE.md` §6.1): address a line by a short stable hash of its
//! content instead of resending the whole file. The model reads anchored lines once, then
//! targets edits by anchor — no full-file round-trips, and an edit that no longer matches is
//! rejected rather than silently misapplied.

use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};

/// Compute the anchor for a single line: 8 hex chars over the line's trimmed content.
///
/// Trimming makes the anchor insensitive to surrounding indentation churn; identical content
/// yields identical anchors (and is therefore ambiguous to target — by design).
pub fn anchor_of(line: &str) -> String {
    let mut hasher = DefaultHasher::new();
    line.trim().hash(&mut hasher);
    format!("{:08x}", hasher.finish() as u32)
}

/// A line paired with its anchor, as presented to the model.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AnchoredLine {
    pub anchor: String,
    pub text: String,
}

/// Annotate every line of `source` with its anchor.
pub fn anchored_lines(source: &str) -> Vec<AnchoredLine> {
    source
        .lines()
        .map(|text| AnchoredLine {
            anchor: anchor_of(text),
            text: text.to_string(),
        })
        .collect()
}

/// Render `source` with a leading `anchor│ ` gutter on each line — the form the model reads
/// before issuing [`Edit`]s.
pub fn render_anchored(source: &str) -> String {
    anchored_lines(source)
        .iter()
        .map(|l| format!("{}\u{2502} {}", l.anchor, l.text))
        .collect::<Vec<_>>()
        .join("\n")
}

/// What to do at a matched anchor.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum EditOp {
    /// Replace the matched line with these lines.
    Replace(String),
    /// Insert these lines immediately after the matched line.
    InsertAfter(String),
    /// Insert these lines immediately before the matched line.
    InsertBefore(String),
    /// Delete the matched line.
    Delete,
}

/// A single anchored edit.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Edit {
    pub anchor: String,
    pub op: EditOp,
}

impl Edit {
    pub fn replace(anchor: impl Into<String>, text: impl Into<String>) -> Self {
        Edit {
            anchor: anchor.into(),
            op: EditOp::Replace(text.into()),
        }
    }
    pub fn insert_after(anchor: impl Into<String>, text: impl Into<String>) -> Self {
        Edit {
            anchor: anchor.into(),
            op: EditOp::InsertAfter(text.into()),
        }
    }
    pub fn insert_before(anchor: impl Into<String>, text: impl Into<String>) -> Self {
        Edit {
            anchor: anchor.into(),
            op: EditOp::InsertBefore(text.into()),
        }
    }
    pub fn delete(anchor: impl Into<String>) -> Self {
        Edit {
            anchor: anchor.into(),
            op: EditOp::Delete,
        }
    }
}

/// Why an anchored edit could not be applied.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AnchorError {
    /// No line matched the anchor — the file changed under the edit.
    NotFound(String),
    /// More than one line matched the anchor — the target is ambiguous.
    Ambiguous { anchor: String, count: usize },
}

impl std::fmt::Display for AnchorError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            AnchorError::NotFound(a) => write!(f, "no line matches anchor {a}"),
            AnchorError::Ambiguous { anchor, count } => {
                write!(f, "anchor {anchor} matches {count} lines (ambiguous)")
            }
        }
    }
}

impl std::error::Error for AnchorError {}

/// Apply a batch of anchored edits to `source`, preserving a trailing newline if present.
///
/// All anchors are resolved against the **original** line set, so edits don't interfere with
/// each other's targeting. Any unmatched or ambiguous anchor fails the whole batch (atomic),
/// so a stale edit never corrupts the file.
pub fn apply_edits(source: &str, edits: &[Edit]) -> Result<String, AnchorError> {
    let lines: Vec<&str> = source.lines().collect();

    // Resolve every anchor to a unique line index first.
    let mut resolved: Vec<(usize, &EditOp)> = Vec::with_capacity(edits.len());
    for edit in edits {
        let matches: Vec<usize> = lines
            .iter()
            .enumerate()
            .filter(|(_, l)| anchor_of(l) == edit.anchor)
            .map(|(i, _)| i)
            .collect();
        match matches.as_slice() {
            [] => return Err(AnchorError::NotFound(edit.anchor.clone())),
            [i] => resolved.push((*i, &edit.op)),
            many => {
                return Err(AnchorError::Ambiguous {
                    anchor: edit.anchor.clone(),
                    count: many.len(),
                })
            }
        }
    }

    // Build the output line list, consulting edits keyed by original index.
    let mut by_index: std::collections::HashMap<usize, Vec<&EditOp>> =
        std::collections::HashMap::new();
    for (i, op) in resolved {
        by_index.entry(i).or_default().push(op);
    }

    let mut out: Vec<String> = Vec::with_capacity(lines.len());
    for (i, line) in lines.iter().enumerate() {
        let ops = by_index.get(&i);
        // Inserts-before first.
        if let Some(ops) = ops {
            for op in ops {
                if let EditOp::InsertBefore(text) = op {
                    out.extend(text.lines().map(String::from));
                }
            }
        }
        // The line itself: replaced, deleted, or kept.
        let mut emitted = false;
        if let Some(ops) = ops {
            for op in ops {
                match op {
                    EditOp::Replace(text) => {
                        out.extend(text.lines().map(String::from));
                        emitted = true;
                    }
                    EditOp::Delete => emitted = true,
                    _ => {}
                }
            }
        }
        if !emitted {
            out.push((*line).to_string());
        }
        // Inserts-after last.
        if let Some(ops) = ops {
            for op in ops {
                if let EditOp::InsertAfter(text) = op {
                    out.extend(text.lines().map(String::from));
                }
            }
        }
    }

    let mut result = out.join("\n");
    if source.ends_with('\n') {
        result.push('\n');
    }
    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;

    const SRC: &str = "fn main() {\n    let x = 1;\n    println!(\"{x}\");\n}\n";

    #[test]
    fn anchor_is_indentation_insensitive_and_stable() {
        assert_eq!(anchor_of("    let x = 1;"), anchor_of("let x = 1;"));
        assert_eq!(anchor_of("let x = 1;").len(), 8);
    }

    #[test]
    fn replace_targets_the_anchored_line() {
        let anchor = anchor_of("    let x = 1;");
        let out = apply_edits(SRC, &[Edit::replace(anchor, "    let x = 42;")]).unwrap();
        assert!(out.contains("let x = 42;"));
        assert!(!out.contains("let x = 1;"));
        assert!(out.ends_with('\n'));
    }

    #[test]
    fn insert_after_and_before() {
        let anchor = anchor_of("    let x = 1;");
        let out = apply_edits(SRC, &[Edit::insert_after(&anchor, "    let y = 2;")]).unwrap();
        let lines: Vec<&str> = out.lines().collect();
        let xi = lines.iter().position(|l| l.contains("let x = 1;")).unwrap();
        assert!(lines[xi + 1].contains("let y = 2;"));
    }

    #[test]
    fn delete_removes_the_line() {
        let anchor = anchor_of("    println!(\"{x}\");");
        let out = apply_edits(SRC, &[Edit::delete(anchor)]).unwrap();
        assert!(!out.contains("println!"));
    }

    #[test]
    fn unmatched_anchor_fails_the_batch() {
        let err = apply_edits(SRC, &[Edit::replace("deadbeef", "x")]).unwrap_err();
        assert!(matches!(err, AnchorError::NotFound(_)));
    }

    #[test]
    fn ambiguous_anchor_is_rejected() {
        let src = "dup\ndup\n";
        let err = apply_edits(src, &[Edit::replace(anchor_of("dup"), "x")]).unwrap_err();
        assert!(matches!(err, AnchorError::Ambiguous { count: 2, .. }));
    }

    #[test]
    fn render_anchored_has_gutter() {
        let rendered = render_anchored("hello");
        assert!(rendered.starts_with(&anchor_of("hello")));
        assert!(rendered.contains('\u{2502}'));
    }
}
