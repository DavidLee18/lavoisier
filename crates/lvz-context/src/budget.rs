//! The budget-fixture loop (`RECIPE.md` §6.5): token-efficiency CI for the skeleton-radius
//! knob `N`.
//!
//! A [`Fixture`] is `(repo snapshot + edit target)`; [`Fixture::measure`] builds the context
//! the agent would send at a given radius and reports its estimated tokens plus the two §6.5
//! diagnostics' deterministic half (kept-symbol count). The integration test
//! `tests/budget.rs` pins per-fixture token **ceilings** as the committed baseline and fails
//! CI when a change blows the budget.
//!
//! Scope: this harness measures the **input-construction** lever, which is deterministic and
//! gateable offline. The round-trip / cache-hit half of the U-curve depends on live model
//! behaviour and belongs to runtime ATO (§6.6); the fixtures here set its safe priors and the
//! regression floor.

use std::collections::HashSet;

use crate::symbols::SymbolGraph;
use crate::tokens::estimate_tokens;
use crate::{skeleton, Lang};

/// Coarse task shape; knob optima differ per archetype (`RECIPE.md` §6.5). Mirrors
/// `lvz_protocol::Archetype` but kept local so `lvz-context` stays protocol-independent.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Archetype {
    SingleFileEdit,
    Refactor,
    Rename,
    Feature,
}

/// A repo snapshot plus the symbol at the centre of the intended edit.
pub struct Fixture {
    pub name: &'static str,
    pub archetype: Archetype,
    /// The files of the snapshot, as `(language, source)`.
    pub files: Vec<(Lang, String)>,
    /// The symbol the task edits; skeleton radius expands outward from here.
    pub target: String,
}

/// The deterministic measurement of a fixture at one radius.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BudgetReport {
    pub radius: u8,
    pub est_tokens: usize,
    pub kept_symbols: usize,
}

impl Fixture {
    /// Build the context the agent would send at `radius`: every file skeletonised, with full
    /// bodies kept for symbols within `radius` hops of [`target`](Self::target) across the
    /// whole snapshot.
    pub fn context_at(&self, radius: u8) -> String {
        let graph = SymbolGraph::from_sources(self.files.iter().map(|(l, s)| (*l, s.as_str())));
        // Keep bodies per file (scope-aware), so a same-named symbol's body is kept only in the
        // file that actually owns the reached definition.
        let keep = graph.neighbors_within_by_file(&self.target, radius);
        self.files
            .iter()
            .enumerate()
            .map(|(i, (lang, source))| skeleton::skeletonize(source, *lang, &keep[i]))
            .collect::<Vec<_>>()
            .join("\n")
    }

    /// Measure estimated context tokens and kept-symbol count at `radius`.
    pub fn measure(&self, radius: u8) -> BudgetReport {
        let graph = SymbolGraph::from_sources(self.files.iter().map(|(l, s)| (*l, s.as_str())));
        let keep = graph.neighbors_within_by_file(&self.target, radius);
        let context = self
            .files
            .iter()
            .enumerate()
            .map(|(i, (lang, source))| skeleton::skeletonize(source, *lang, &keep[i]))
            .collect::<Vec<_>>()
            .join("\n");
        BudgetReport {
            radius,
            est_tokens: estimate_tokens(&context),
            kept_symbols: keep.iter().map(HashSet::len).sum(),
        }
    }

    /// Sweep radii `0..=max_radius`, returning one report each — the trend line §6.5 tracks.
    pub fn sweep(&self, max_radius: u8) -> Vec<BudgetReport> {
        (0..=max_radius).map(|r| self.measure(r)).collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture() -> Fixture {
        Fixture {
            name: "demo",
            archetype: Archetype::SingleFileEdit,
            files: vec![(
                Lang::Rust,
                "\
fn a() -> i32 { b() + 1 }
fn b() -> i32 { c() + 1 }
fn c() -> i32 { 1 }
fn unrelated() -> i32 { 99 }
"
                .to_string(),
            )],
            target: "a".to_string(),
        }
    }

    #[test]
    fn kept_set_never_shrinks_with_radius() {
        // The reachable set only grows with radius. (Token count is *not* monotonic — eliding
        // a trivial body can cost more than keeping it; §6.5's curve is U-shaped — so the kept
        // set, not tokens, is the invariant.)
        let reports = fixture().sweep(3);
        for pair in reports.windows(2) {
            assert!(
                pair[1].kept_symbols >= pair[0].kept_symbols,
                "kept set shrank from radius {} ({}) to {} ({})",
                pair[0].radius,
                pair[0].kept_symbols,
                pair[1].radius,
                pair[1].kept_symbols,
            );
        }
    }

    #[test]
    fn radius_is_a_real_lever_for_substantial_bodies() {
        // When a dependency has a non-trivial body, expanding to include it really does cost
        // more tokens than the radius-0 skeleton.
        let f = Fixture {
            name: "big_dep",
            archetype: Archetype::SingleFileEdit,
            files: vec![(
                Lang::Rust,
                "\
fn target() -> i32 { big() }
fn big() -> i32 {
    let mut total = 0;
    for i in 0..100 { total += i * i - 3 * i + 7; }
    total
}
"
                .to_string(),
            )],
            target: "target".to_string(),
        };
        assert!(f.measure(1).est_tokens > f.measure(0).est_tokens);
    }

    #[test]
    fn radius_expands_the_kept_set_along_the_dependency_chain() {
        let f = fixture();
        // a -> b -> c; unrelated is never pulled in.
        assert_eq!(f.measure(0).kept_symbols, 1); // {a}
        assert_eq!(f.measure(1).kept_symbols, 2); // {a, b}
        assert_eq!(f.measure(2).kept_symbols, 3); // {a, b, c}
        assert_eq!(f.measure(3).kept_symbols, 3); // saturated; unrelated excluded
    }
}
