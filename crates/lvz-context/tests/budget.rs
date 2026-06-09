//! Budget-fixture CI loop (`RECIPE.md` §6.5).
//!
//! Each fixture is `(repo snapshot + edit target)` with a **committed token ceiling** at a
//! chosen skeleton radius. The ceilings are the baseline: a change that makes skeletons fatter
//! (or breaks elision) blows the budget and fails CI. Fixtures span the §6.5 archetypes
//! (single-file edit, cross-file refactor, rename, new feature).
//!
//! Run/inspect the trend line with: `cargo test -p lvz-context --test budget -- --nocapture`.

use lvz_context::budget::{Archetype, Fixture};
use lvz_context::Lang;

fn rs(src: &str) -> (Lang, String) {
    (Lang::Rust, src.to_string())
}

/// A fixture, the radius the agent would use for it, and the asserted token ceiling.
struct Case {
    fixture: Fixture,
    radius: u8,
    ceiling: usize,
}

fn cases() -> Vec<Case> {
    vec![
        // Single-file edit: change `render`, which calls `format_row` -> `escape`.
        Case {
            fixture: Fixture {
                name: "single_file_edit",
                archetype: Archetype::SingleFileEdit,
                files: vec![rs("\
fn escape(s: &str) -> String { s.replace('<', \"&lt;\") }
fn format_row(cells: &[String]) -> String { cells.join(\" | \") }
fn render(rows: &[Vec<String>]) -> String {
    let mut out = String::new();
    for row in rows {
        let cells: Vec<String> = row.iter().map(|c| escape(c)).collect();
        out.push_str(&format_row(&cells));
    }
    out
}
fn helpers_unrelated() -> u32 { 12345 }
")],
                target: "render".to_string(),
            },
            radius: 1,
            ceiling: 160,
        },
        // Cross-file refactor: `service` (file A) depends on `repo` (file B).
        Case {
            fixture: Fixture {
                name: "cross_file_refactor",
                archetype: Archetype::Refactor,
                files: vec![
                    rs("\
fn service(id: u32) -> u32 { repo(id) + 1 }
fn unrelated_a() -> u32 { 0 }
"),
                    rs("\
fn repo(id: u32) -> u32 { id * 2 }
fn unrelated_b() -> u32 { 1 }
"),
                ],
                target: "service".to_string(),
            },
            radius: 1,
            ceiling: 66,
        },
        // Rename: a narrow edit; radius 0 keeps only the target body.
        Case {
            fixture: Fixture {
                name: "symbol_rename",
                archetype: Archetype::Rename,
                files: vec![rs("\
fn old_name() -> i32 { 1 }
fn caller_one() -> i32 { old_name() }
fn caller_two() -> i32 { old_name() + 1 }
")],
                target: "old_name".to_string(),
            },
            radius: 0,
            ceiling: 40,
        },
    ]
}

#[test]
fn fixtures_stay_within_committed_token_budgets() {
    let mut failures = Vec::new();
    for case in cases() {
        let report = case.fixture.measure(case.radius);
        eprintln!(
            "[budget] {:22} archetype={:?} radius={} tokens={} kept={} (ceiling {})",
            case.fixture.name,
            case.fixture.archetype,
            report.radius,
            report.est_tokens,
            report.kept_symbols,
            case.ceiling,
        );
        if report.est_tokens > case.ceiling {
            failures.push(format!(
                "{}: {} tokens > ceiling {}",
                case.fixture.name, report.est_tokens, case.ceiling
            ));
        }
    }
    assert!(
        failures.is_empty(),
        "budget regressions:\n{}",
        failures.join("\n")
    );
}

#[test]
fn skeleton_radius_expands_the_kept_set() {
    // The deterministic §6.5 invariant: the kept-symbol set grows (never shrinks) with radius,
    // and fixtures whose target has dependencies actually expand. (Token count itself is not
    // monotonic — eliding a trivial body can cost more than keeping it — so we assert on the
    // kept set, which the radius knob directly controls.)
    for case in cases() {
        let sweep = case.fixture.sweep(3);
        for pair in sweep.windows(2) {
            assert!(
                pair[1].kept_symbols >= pair[0].kept_symbols,
                "{}: kept set shrank from radius {} to {}",
                case.fixture.name,
                pair[0].radius,
                pair[1].radius,
            );
        }
    }
    // The dependency fixtures must demonstrably pull more in at radius 1 than at radius 0.
    let by_name = |n: &str| cases().into_iter().find(|c| c.fixture.name == n).unwrap();
    let edit = by_name("single_file_edit").fixture;
    assert!(edit.measure(1).kept_symbols > edit.measure(0).kept_symbols);
    let refac = by_name("cross_file_refactor").fixture;
    assert!(refac.measure(1).kept_symbols > refac.measure(0).kept_symbols);
}
