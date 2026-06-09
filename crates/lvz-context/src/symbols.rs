//! Recursive symbol-dependency tracking (`RECIPE.md` §6.1) — the graph that makes the
//! skeleton-radius knob `N` real: "include full bodies for symbols within `N` dependency
//! hops of the edit target."
//!
//! Edges are a deliberately cheap, language-agnostic heuristic: a symbol *references* another
//! when the other symbol's name appears as a whole word in its definition text. This is a
//! name-based approximation, not full name resolution (same-named symbols across files merge,
//! shadowing is ignored), but it is enough to drive skeleton expansion and is fully
//! deterministic — exactly what the §6.5 budget-fixture loop needs.

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
        let mut graph = SymbolGraph::default();
        graph.add_source(source, lang);
        graph
    }

    /// Build a graph spanning several files (e.g. a cross-file refactor fixture). Symbols are
    /// keyed by name across the whole set, so a call from one file to a definition in another
    /// produces an edge.
    pub fn from_sources<'a>(sources: impl IntoIterator<Item = (Lang, &'a str)>) -> Self {
        // First pass: collect every symbol's name + text across all files. Second pass: link.
        let mut defs: Vec<(String, String)> = Vec::new();
        for (lang, source) in sources {
            collect_symbols(source, lang, &mut defs);
        }
        SymbolGraph::link(defs)
    }

    fn add_source(&mut self, source: &str, lang: Lang) {
        let mut defs = Vec::new();
        collect_symbols(source, lang, &mut defs);
        let linked = SymbolGraph::link(defs);
        for (name, refs) in linked.edges {
            self.edges.entry(name).or_default().extend(refs);
        }
    }

    fn link(defs: Vec<(String, String)>) -> Self {
        let names: Vec<&String> = defs.iter().map(|(n, _)| n).collect();
        let mut edges: HashMap<String, HashSet<String>> = HashMap::new();
        for (name, text) in &defs {
            let entry = edges.entry(name.clone()).or_default();
            for other in &names {
                if other.as_str() != name.as_str() && contains_word(text, other) {
                    entry.insert((*other).clone());
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

/// Skeletonise `source`, keeping full bodies for symbols within `radius` hops of `target`.
/// Everything else is elided. This is the knob-`N` entry point used by the budget loop and
/// the `outline_file` tool's focus mode.
pub fn skeleton_with_radius(source: &str, lang: Lang, target: &str, radius: u8) -> String {
    let keep = SymbolGraph::from_source(source, lang).neighbors_within(target, radius);
    skeleton::skeletonize(source, lang, &keep)
}

/// Walk the tree collecting `(name, definition_text)` for every symbol-kind node.
fn collect_symbols(source: &str, lang: Lang, out: &mut Vec<(String, String)>) {
    let Some(tree) = parse(source, lang) else {
        return;
    };
    let kinds = lang.spec().symbol_kinds;
    walk(tree.root_node(), source, kinds, out);
}

fn walk(node: Node, source: &str, kinds: &[&str], out: &mut Vec<(String, String)>) {
    if kinds.contains(&node.kind()) {
        if let Some(name) = node
            .child_by_field_name("name")
            .map(|n| source[n.start_byte()..n.end_byte()].to_string())
        {
            let text = source[node.start_byte()..node.end_byte()].to_string();
            out.push((name, text));
        }
    }
    let mut cursor = node.walk();
    for child in node.children(&mut cursor) {
        walk(child, source, kinds, out);
    }
}

/// True if `word` occurs in `hay` bounded by non-identifier characters (whole-word match).
fn contains_word(hay: &str, word: &str) -> bool {
    if word.is_empty() {
        return false;
    }
    let bytes = hay.as_bytes();
    let mut from = 0;
    while let Some(rel) = hay[from..].find(word) {
        let i = from + rel;
        let before_ok = i == 0 || !is_ident_byte(bytes[i - 1]);
        let after = i + word.len();
        let after_ok = after >= bytes.len() || !is_ident_byte(bytes[after]);
        if before_ok && after_ok {
            return true;
        }
        from = i + 1;
        if from >= hay.len() {
            break;
        }
    }
    false
}

fn is_ident_byte(b: u8) -> bool {
    b.is_ascii_alphanumeric() || b == b'_'
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
    fn whole_word_matching_excludes_substrings() {
        assert!(contains_word("call add(x)", "add"));
        assert!(!contains_word("address book", "add"));
        assert!(!contains_word("readd", "add"));
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
    fn multi_file_graph_links_across_sources() {
        let a = "fn caller() -> i32 { shared() }";
        let b = "fn shared() -> i32 { 5 }";
        let g = SymbolGraph::from_sources([(Lang::Rust, a), (Lang::Rust, b)]);
        assert!(g.neighbors_within("caller", 1).contains("shared"));
    }
}
