//! Recursive symbol-dependency tracking (`RECIPE.md` §6.1) — the graph that makes the
//! skeleton-radius knob `N` real: "include full bodies for symbols within `N` dependency
//! hops of the edit target."
//!
//! Edges are **resolved from the parse tree**, not from raw text. For each symbol we walk its
//! subtree and collect the *reference identifiers* it uses (real `identifier`/`type_identifier`
//! nodes), minus the identifiers it binds locally (parameters, `let`/variable patterns); an edge
//! `A → B` exists when one of `A`'s references names a defined symbol `B`. Resolving through the
//! AST means a name that only appears in a **string or comment** no longer creates a spurious
//! edge, and a **local variable that shadows** a top-level symbol's name no longer links to it.
//!
//! It is still name-keyed, not a full semantic index — same-named symbols across files merge and
//! there is no import/visibility resolution — but that is all the radius knob needs, and it stays
//! fully deterministic, exactly what the §6.5 budget-fixture loop requires.

use std::collections::{HashMap, HashSet};

use tree_sitter::Node;

use crate::lang::Lang;
use crate::skeleton::{self, parse};

/// A directed reference graph over named symbols: `name → names it references`.
#[derive(Debug, Default, Clone)]
pub struct SymbolGraph {
    edges: HashMap<String, HashSet<String>>,
}

impl SymbolGraph {
    /// Build a graph from a single source file.
    pub fn from_source(source: &str, lang: Lang) -> Self {
        let mut defs = Vec::new();
        collect_symbol_refs(source, lang, &mut defs);
        SymbolGraph::link(defs)
    }

    /// Build a graph spanning several files (e.g. a cross-file refactor fixture). Symbols are
    /// keyed by name across the whole set, so a call from one file to a definition in another
    /// produces an edge.
    pub fn from_sources<'a>(sources: impl IntoIterator<Item = (Lang, &'a str)>) -> Self {
        // First pass: per symbol, its name + the names it *references* (resolved from identifier
        // nodes, minus its own locals). Second pass: keep only references that name a known symbol.
        let mut defs: Vec<(String, HashSet<String>)> = Vec::new();
        for (lang, source) in sources {
            collect_symbol_refs(source, lang, &mut defs);
        }
        SymbolGraph::link(defs)
    }

    /// Resolve references against the known symbol set: an edge `name → other` exists when `name`
    /// references `other`'s identifier and `other` is itself a defined symbol. Same-named symbols
    /// merge by union (a name-keyed graph is all the radius knob needs).
    fn link(defs: Vec<(String, HashSet<String>)>) -> Self {
        let names: HashSet<&str> = defs.iter().map(|(n, _)| n.as_str()).collect();
        let mut edges: HashMap<String, HashSet<String>> = HashMap::new();
        for (name, refs) in &defs {
            let entry = edges.entry(name.clone()).or_default();
            for r in refs {
                if r != name && names.contains(r.as_str()) {
                    entry.insert(r.clone());
                }
            }
        }
        SymbolGraph { edges }
    }

    /// The set of symbol names within `radius` reference-hops of `target` (inclusive of
    /// `target` itself). `radius` 0 yields just the target.
    pub fn neighbors_within(&self, target: &str, radius: u8) -> HashSet<String> {
        let mut visited = HashSet::new();
        visited.insert(target.to_string());
        let mut frontier = vec![target.to_string()];
        for _ in 0..radius {
            let mut next = Vec::new();
            for node in &frontier {
                if let Some(refs) = self.edges.get(node) {
                    for r in refs {
                        if visited.insert(r.clone()) {
                            next.push(r.clone());
                        }
                    }
                }
            }
            if next.is_empty() {
                break;
            }
            frontier = next;
        }
        visited
    }

    /// All symbol names known to the graph.
    pub fn names(&self) -> impl Iterator<Item = &str> {
        self.edges.keys().map(String::as_str)
    }
}

/// Every 1-based line on which `name` occurs as a **reference identifier** (a real
/// `identifier`/`type_identifier` node), not inside a string or comment. Each matching line is
/// returned once, with its trimmed text, in source order.
///
/// This is the AST-aware core of the `find_references` tool: unlike a substring `grep`, a mention
/// of `name` in a string literal or comment does **not** match, so the call-site set it returns is
/// the *real* code references. (It is name-keyed, like the rest of this module — it does not resolve
/// imports/visibility, so it matches every same-named identifier; that is exactly what "find all
/// usages of this name" wants.)
///
/// Returns `None` only when the source **fails to parse** — so a caller can distinguish that from a
/// successful parse with no identifier matches (e.g. the name appears only in a comment), and avoid
/// falling back to a substring scan that would re-introduce the comment/string false positives.
pub fn find_identifier_lines(source: &str, lang: Lang, name: &str) -> Option<Vec<(usize, String)>> {
    let tree = parse(source, lang)?;
    let spec = lang.spec();
    let mut rows: HashSet<usize> = HashSet::new();
    collect_named_ref_rows(tree.root_node(), source, &spec, name, &mut rows);
    let src_lines: Vec<&str> = source.lines().collect();
    let mut rows: Vec<usize> = rows.into_iter().collect();
    rows.sort_unstable();
    Some(
        rows.into_iter()
            .map(|row| {
                let text = src_lines
                    .get(row)
                    .map(|s| s.trim())
                    .unwrap_or("")
                    .to_string();
                (row + 1, text)
            })
            .collect(),
    )
}

/// Collect the (0-based) rows of every reference-identifier node whose text equals `name`.
fn collect_named_ref_rows(
    node: Node,
    source: &str,
    spec: &crate::lang::LangSpec,
    name: &str,
    out: &mut HashSet<usize>,
) {
    if spec.ref_ident_kinds.contains(&node.kind()) && text(node, source) == name {
        out.insert(node.start_position().row);
    }
    let mut cursor = node.walk();
    for child in node.children(&mut cursor) {
        collect_named_ref_rows(child, source, spec, name, out);
    }
}

/// Skeletonise `source`, keeping full bodies for symbols within `radius` hops of `target`.
/// Everything else is elided. This is the knob-`N` entry point used by the budget loop and
/// the `outline_file` tool's focus mode.
pub fn skeleton_with_radius(source: &str, lang: Lang, target: &str, radius: u8) -> String {
    let keep = SymbolGraph::from_source(source, lang).neighbors_within(target, radius);
    skeleton::skeletonize(source, lang, &keep)
}

/// Walk the tree collecting `(name, referenced names)` for every symbol-kind node. References are
/// resolved from the parse tree (identifier nodes), not raw text, and exclude the symbol's own
/// locals — so names appearing in strings/comments, and locals shadowing a top-level symbol, no
/// longer create spurious edges.
fn collect_symbol_refs(source: &str, lang: Lang, out: &mut Vec<(String, HashSet<String>)>) {
    let Some(tree) = parse(source, lang) else {
        return;
    };
    let spec = lang.spec();
    walk_symbols(tree.root_node(), source, &spec, out);
}

fn walk_symbols(
    node: Node,
    source: &str,
    spec: &crate::lang::LangSpec,
    out: &mut Vec<(String, HashSet<String>)>,
) {
    if spec.symbol_kinds.contains(&node.kind()) {
        if let Some(name) = node.child_by_field_name("name").map(|n| text(n, source)) {
            let mut bound = HashSet::new();
            collect_bound(node, source, spec, &mut bound);
            let mut refs = HashSet::new();
            collect_refs(node, source, spec, &bound, &mut refs);
            refs.remove(&name); // a symbol is not a reference to itself
            out.push((name, refs));
        }
    }
    let mut cursor = node.walk();
    for child in node.children(&mut cursor) {
        walk_symbols(child, source, spec, out);
    }
}

/// Collect the identifiers bound *locally* inside `node`: for every binder (parameter, `let`,
/// variable declarator) the identifiers in its binding position only (`pattern`/`name` field, or
/// — for parameter-list nodes that have neither — its direct children). The binder's *value* and
/// *type* are intentionally not treated as bindings, so a `let x = helper()` still references
/// `helper` while binding `x`.
fn collect_bound(
    node: Node,
    source: &str,
    spec: &crate::lang::LangSpec,
    out: &mut HashSet<String>,
) {
    if spec.binder_kinds.contains(&node.kind()) {
        match node
            .child_by_field_name("pattern")
            .or_else(|| node.child_by_field_name("name"))
        {
            Some(target) => collect_idents(target, source, spec, out),
            None => {
                let mut cursor = node.walk();
                for child in node.children(&mut cursor) {
                    collect_idents(child, source, spec, out);
                }
            }
        }
    }
    let mut cursor = node.walk();
    for child in node.children(&mut cursor) {
        collect_bound(child, source, spec, out);
    }
}

/// Every reference-identifier name in `node`'s subtree that is not locally `bound`.
fn collect_refs(
    node: Node,
    source: &str,
    spec: &crate::lang::LangSpec,
    bound: &HashSet<String>,
    out: &mut HashSet<String>,
) {
    if spec.ref_ident_kinds.contains(&node.kind()) {
        let t = text(node, source);
        if !bound.contains(&t) {
            out.insert(t);
        }
    }
    let mut cursor = node.walk();
    for child in node.children(&mut cursor) {
        collect_refs(child, source, spec, bound, out);
    }
}

/// Every reference-identifier name in `node`'s subtree (binding-agnostic — used to harvest the
/// names a binder introduces).
fn collect_idents(
    node: Node,
    source: &str,
    spec: &crate::lang::LangSpec,
    out: &mut HashSet<String>,
) {
    if spec.ref_ident_kinds.contains(&node.kind()) {
        out.insert(text(node, source));
    }
    let mut cursor = node.walk();
    for child in node.children(&mut cursor) {
        collect_idents(child, source, spec, out);
    }
}

fn text(node: Node, source: &str) -> String {
    source[node.start_byte()..node.end_byte()].to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    const SRC: &str = "\
fn helper(x: i32) -> i32 {
    x + 1
}

fn target() -> i32 {
    helper(41)
}

fn unrelated() -> i32 {
    7
}
";

    #[test]
    fn references_in_strings_and_comments_do_not_link() {
        // `helper` appears only in a string literal and a line comment — never as a real call —
        // so the name-based substring heuristic would wrongly link, but AST resolution does not.
        let src = "\
fn helper() -> i32 { 1 }
fn target() -> i32 {
    // call helper here later
    let s = \"remember to call helper\";
    2
}
";
        let g = SymbolGraph::from_source(src, Lang::Rust);
        assert!(
            !g.neighbors_within("target", 1).contains("helper"),
            "string/comment mention must not create an edge"
        );
    }

    #[test]
    fn a_local_shadowing_a_symbol_name_does_not_link() {
        // `target` binds a local named `helper`; the top-level `helper` fn is never called.
        let src = "\
fn helper() -> i32 { 1 }
fn target() -> i32 {
    let helper = 5;
    helper + 1
}
";
        let g = SymbolGraph::from_source(src, Lang::Rust);
        assert!(
            !g.neighbors_within("target", 1).contains("helper"),
            "a shadowing local must not link to the same-named symbol"
        );
    }

    #[test]
    fn graph_links_caller_to_callee() {
        let g = SymbolGraph::from_source(SRC, Lang::Rust);
        let within1 = g.neighbors_within("target", 1);
        assert!(within1.contains("target"));
        assert!(within1.contains("helper"));
        assert!(!within1.contains("unrelated"));
    }

    #[test]
    fn radius_zero_is_just_the_target() {
        let g = SymbolGraph::from_source(SRC, Lang::Rust);
        let within0 = g.neighbors_within("target", 0);
        assert_eq!(within0.len(), 1);
        assert!(within0.contains("target"));
    }

    #[test]
    fn skeleton_with_radius_keeps_only_dependencies() {
        // radius 1 keeps target + helper bodies, elides unrelated.
        let out = skeleton_with_radius(SRC, Lang::Rust, "target", 1);
        assert!(out.contains("helper(41)"), "target body kept: {out}");
        assert!(out.contains("x + 1"), "helper body kept: {out}");
        assert!(!out.contains("    7\n"), "unrelated body elided: {out}");
    }

    #[test]
    fn radius_zero_elides_dependencies_too() {
        let out = skeleton_with_radius(SRC, Lang::Rust, "target", 0);
        assert!(out.contains("helper(41)"), "target body kept: {out}");
        assert!(
            !out.contains("x + 1"),
            "helper body should be elided at radius 0: {out}"
        );
    }

    #[test]
    fn find_identifier_lines_matches_code_not_strings_or_comments() {
        let src = "\
fn helper() -> i32 { 1 }
fn target() -> i32 {
    // helper is mentioned in this comment
    let s = \"call helper here\";
    helper()
}
";
        let hits = find_identifier_lines(src, Lang::Rust, "helper").unwrap();
        let rows: Vec<usize> = hits.iter().map(|(r, _)| *r).collect();
        // Line 1 (definition) and line 5 (the real call) — NOT the comment (3) or string (4).
        assert_eq!(rows, vec![1, 5], "got {hits:?}");
        assert!(hits.iter().any(|(r, t)| *r == 5 && t.contains("helper()")));
    }

    #[test]
    fn find_identifier_lines_dedups_a_line_with_two_uses() {
        let src = "fn f() -> i32 { g() + g() }\nfn g() -> i32 { 1 }\n";
        let hits = find_identifier_lines(src, Lang::Rust, "g").unwrap();
        // The `g() + g()` line is reported once, plus the definition line.
        assert_eq!(hits.iter().map(|(r, _)| *r).collect::<Vec<_>>(), vec![1, 2]);
    }

    #[test]
    fn multi_file_graph_links_across_sources() {
        let a = "fn caller() -> i32 { shared() }";
        let b = "fn shared() -> i32 { 5 }";
        let g = SymbolGraph::from_sources([(Lang::Rust, a), (Lang::Rust, b)]);
        assert!(g.neighbors_within("caller", 1).contains("shared"));
    }
}
