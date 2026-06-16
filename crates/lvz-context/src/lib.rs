//! `lvz-context` — the token-efficiency engine (§6.1).
//!
//! This crate holds the largest token levers, all usable offline and independent of any
//! provider:
//!
//! - [`skeleton`] — tree-sitter file-skeleton extraction: keep signatures + types + docs,
//!   elide bodies (multi-language: Rust, Python, JavaScript, TypeScript).
//! - [`symbols`] — recursive symbol-dependency graph; drives the skeleton-radius knob `N`
//!   via [`symbols::skeleton_with_radius`].
//! - [`anchor`] — hash-anchored edits: address lines by a short content hash so edits don't
//!   require resending the file, and stale edits are rejected rather than misapplied.
//! - [`diff`] — token-efficient unified diffs: emit only changed hunks, never full rewrites.
//! - [`tokens`] / [`budget`] — deterministic token estimate + the §6.5 budget-fixture loop
//!   that gates skeleton-radius regressions in CI.
//!
//! These are the primitives the agent uses to read less and write less; the skeleton-radius
//! knob `N` (§6.5) drives [`skeleton::skeletonize`]'s `keep_bodies` set.

pub mod anchor;
pub mod budget;
pub mod diff;
mod lang;
pub mod skeleton;
pub mod symbols;
pub mod tokens;

pub use lang::Lang;

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashSet;

    /// End-to-end: skeleton a file to read it cheaply, then edit it by anchor, then diff.
    #[test]
    fn skeleton_then_anchored_edit_then_diff() {
        let src = "\
/// Doubles n.
fn double(n: i32) -> i32 {
    n * 2
}
";
        // 1. Skeleton keeps the signature, drops the body.
        let skel = skeleton::skeletonize(src, Lang::Rust, &HashSet::new());
        assert!(skel.contains("fn double(n: i32) -> i32"));
        assert!(!skel.contains("n * 2"));

        // 2. Anchored edit changes the body line without resending the file.
        let anchor = anchor::anchor_of("    n * 2");
        let edited =
            anchor::apply_edits(src, &[anchor::Edit::replace(anchor, "    n * 3")]).unwrap();
        assert!(edited.contains("n * 3"));

        // 3. A minimal diff captures exactly the change.
        let d = diff::unified_diff(src, &edited, 0);
        assert!(d.contains("-    n * 2"));
        assert!(d.contains("+    n * 3"));
    }
}
