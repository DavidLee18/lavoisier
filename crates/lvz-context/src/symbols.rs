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
//! Resolution is **scope-aware across files**: a reference is linked to a *same-file* definition
//! whenever one exists, and only falls back to a cross-file definition (by name) when the name is
//! not defined locally. So when two files each define a symbol of the same name, a caller links to
//! *its own* file's definition instead of silently merging with the unrelated far one — the common
//! same-name collision. (The budget loop relies on name-based cross-file linking for genuinely
//! cross-file edges — e.g. a refactor where the callee lives in another file with no `use` — so that
//! fallback is preserved.)
//!
//! It is still name-keyed on the *source* side, not a full module-qualified semantic index — two
//! same-named definitions still share one out-edge key, and there is no `use`/`import` path
//! resolution — but that is all the radius knob needs, and it stays fully deterministic, exactly
//! what the §6.5 budget-fixture loop requires.

use std::collections::{HashMap, HashSet};

use tree_sitter::Node;

use crate::lang::Lang;
use crate::skeleton::{self, parse};

/// A defined symbol's identity: the file it lives in plus its name. Same-named symbols in
/// different files are **distinct** nodes (so a caller links to its own file's definition, not an
/// unrelated far one) — the scope-awareness a flat name-keyed graph lacked.
type Sym = (usize, String);

/// A directed reference graph over file-scoped symbols: `(file, name) → the symbols it references`.
#[derive(Debug, Default, Clone)]
pub struct SymbolGraph {
    edges: HashMap<Sym, HashSet<Sym>>,
    file_count: usize,
}

impl SymbolGraph {
    /// Build a graph from a single source file.
    pub fn from_source(source: &str, lang: Lang) -> Self {
        let mut defs = Vec::new();
        collect_symbol_refs(source, lang, &mut defs);
        SymbolGraph::link(vec![defs])
    }

    /// Build a graph spanning several files (e.g. a cross-file refactor fixture). A reference is
    /// resolved to a *same-file* definition first; a cross-file edge (by name) forms only when the
    /// name is not defined in the referencing file — so a call to a same-named local symbol no
    /// longer merges with an unrelated definition elsewhere, while genuinely cross-file edges (the
    /// budget loop's refactor case) still link.
    pub fn from_sources<'a>(sources: impl IntoIterator<Item = (Lang, &'a str)>) -> Self {
        // First pass: per file, per symbol, its name + the names it *references* (resolved from
        // identifier nodes, minus its own locals). Second pass ([`link`]) resolves those names to
        // file-scoped symbols, preferring the same file.
        let per_file: Vec<Vec<(String, HashSet<String>)>> = sources
            .into_iter()
            .map(|(lang, source)| {
                let mut defs = Vec::new();
                collect_symbol_refs(source, lang, &mut defs);
                defs
            })
            .collect();
        SymbolGraph::link(per_file)
    }

    /// Resolve each symbol's referenced names to file-scoped target symbols. A name defined in the
    /// **same file** resolves there (the precise, scope-aware case); otherwise it resolves to every
    /// other file that defines it (the cross-file fallback — kept because the budget loop links
    /// across files that share no `use`/`import`). A name defined nowhere is dropped.
    fn link(per_file: Vec<Vec<(String, HashSet<String>)>>) -> Self {
        let file_count = per_file.len();
        // name → the files that define it, for cross-file fallback resolution.
        let mut defined_in: HashMap<&str, Vec<usize>> = HashMap::new();
        for (fi, defs) in per_file.iter().enumerate() {
            for (name, _) in defs {
                defined_in.entry(name.as_str()).or_default().push(fi);
            }
        }
        let mut edges: HashMap<Sym, HashSet<Sym>> = HashMap::new();
        for (fi, defs) in per_file.iter().enumerate() {
            let local: HashSet<&str> = defs.iter().map(|(n, _)| n.as_str()).collect();
            for (name, refs) in defs {
                let entry = edges.entry((fi, name.clone())).or_default();
                for r in refs {
                    if r == name {
                        continue; // not a reference to itself
                    }
                    if local.contains(r.as_str()) {
                        entry.insert((fi, r.clone())); // same-file definition wins
                    } else if let Some(files) = defined_in.get(r.as_str()) {
                        for &tf in files {
                            entry.insert((tf, r.clone())); // cross-file fallback (by name)
                        }
                    }
                }
            }
        }
        SymbolGraph { edges, file_count }
    }

    /// The set of symbol **names** within `radius` reference-hops of `target` (inclusive of
    /// `target` itself), across all files. `radius` 0 yields just the target. Names are collapsed at
    /// the end, so this matches the prior name-based API for single-file callers and the
    /// skeletoniser; traversal itself is file-scoped, so same-named symbols no longer over-link.
    pub fn neighbors_within(&self, target: &str, radius: u8) -> HashSet<String> {
        self.reach(target, radius)
            .into_iter()
            .map(|(_, name)| name)
            .collect()
    }

    /// Like [`neighbors_within`](Self::neighbors_within), but the names to keep are returned **per
    /// file** (index → names defined in that file within radius). Lets a multi-file skeletoniser keep
    /// a body only in the file that actually owns the reached symbol, instead of keeping every
    /// same-named body. `vec[i]` is the keep set for the `i`-th source passed to
    /// [`from_sources`](Self::from_sources).
    pub fn neighbors_within_by_file(&self, target: &str, radius: u8) -> Vec<HashSet<String>> {
        let mut per_file = vec![HashSet::new(); self.file_count.max(1)];
        for (fi, name) in self.reach(target, radius) {
            if let Some(set) = per_file.get_mut(fi) {
                set.insert(name);
            }
        }
        per_file
    }

    /// BFS over the file-scoped edges from every symbol named `target`, returning the reached
    /// `(file, name)` set (inclusive of the seeds).
    fn reach(&self, target: &str, radius: u8) -> HashSet<Sym> {
        let mut visited: HashSet<Sym> = HashSet::new();
        let mut frontier: Vec<Sym> = Vec::new();
        // Seed with every file that defines a symbol of this name (usually one).
        for fi in 0..self.file_count.max(1) {
            let sym = (fi, target.to_string());
            if self.edges.contains_key(&sym) && visited.insert(sym.clone()) {
                frontier.push(sym);
            }
        }
        // A target with no out-edges (e.g. radius queried on an unknown name) still returns itself.
        if visited.is_empty() {
            visited.insert((0, target.to_string()));
        }
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

    /// All symbol names known to the graph (deduplicated across files).
    pub fn names(&self) -> impl Iterator<Item = &str> {
        self.edges
            .keys()
            .map(|(_, name)| name.as_str())
            .collect::<HashSet<_>>()
            .into_iter()
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

    #[test]
    fn same_name_across_files_resolves_to_the_local_definition() {
        // Both files define `helper`. File A's `target` calls the local `helper` (a no-op body);
        // file B's `helper` pulls in a dependency `dep`. A name-keyed graph would merge both
        // `helper`s, so `target`'s radius-1 set would wrongly include B's `dep`. Scope-aware
        // resolution links `target` → A's `helper` only.
        let a = "\
fn helper() -> i32 { 0 }
fn target() -> i32 { helper() }
";
        let b = "\
fn helper() -> i32 { dep() }
fn dep() -> i32 { 9 }
";
        let g = SymbolGraph::from_sources([(Lang::Rust, a), (Lang::Rust, b)]);
        let within2 = g.neighbors_within("target", 2);
        assert!(
            within2.contains("helper"),
            "local helper linked: {within2:?}"
        );
        assert!(
            !within2.contains("dep"),
            "must not reach the OTHER file's helper dependency: {within2:?}"
        );
    }

    #[test]
    fn neighbors_by_file_keeps_a_body_only_in_its_owning_file() {
        // `target` (file 0) → `repo` (file 1). The per-file keep sets must place `repo` in file 1,
        // not file 0, so a skeletoniser keeps the body where it actually lives.
        let a = "fn target() -> i32 { repo() }\nfn noise_a() -> i32 { 0 }";
        let b = "fn repo() -> i32 { 5 }\nfn noise_b() -> i32 { 1 }";
        let g = SymbolGraph::from_sources([(Lang::Rust, a), (Lang::Rust, b)]);
        let per_file = g.neighbors_within_by_file("target", 1);
        assert_eq!(per_file.len(), 2);
        assert!(per_file[0].contains("target") && !per_file[0].contains("repo"));
        assert!(per_file[1].contains("repo") && !per_file[1].contains("target"));
    }
}
