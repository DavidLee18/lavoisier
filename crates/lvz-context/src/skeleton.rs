//! File-skeleton extraction (`RECIPE.md` §6.1, the largest token lever): keep signatures,
//! type definitions, and surrounding doc comments; replace function/method **bodies** with a
//! placeholder. Bodies named in `keep_bodies` are retained — the building block for the
//! skeleton-radius knob `N` ("include full bodies for symbols within N hops of the target").

use std::collections::HashSet;

use tree_sitter::{Node, Parser, Tree};

use crate::lang::Lang;

/// Parse `source` as `lang`, returning `None` if the grammar can't be loaded.
pub(crate) fn parse(source: &str, lang: Lang) -> Option<Tree> {
    let mut parser = Parser::new();
    parser.set_language(&lang.ts_language()).ok()?;
    parser.parse(source, None)
}

/// Produce a skeleton of `source`: signatures kept, un-kept bodies elided.
///
/// If the source cannot be parsed, the original is returned unchanged (skeletoning is an
/// optimisation, never a correctness requirement).
pub fn skeletonize(source: &str, lang: Lang, keep_bodies: &HashSet<String>) -> String {
    let Some(tree) = parse(source, lang) else {
        return source.to_string();
    };
    let spec = lang.spec();
    let mut elisions: Vec<(usize, usize)> = Vec::new();
    collect_body_elisions(
        tree.root_node(),
        source,
        spec.def_kinds,
        keep_bodies,
        &mut elisions,
    );

    // Apply right-to-left so earlier byte offsets stay valid.
    elisions.sort_by_key(|&(start, _)| std::cmp::Reverse(start));
    let mut out = source.to_string();
    for (start, end) in elisions {
        out.replace_range(start..end, spec.elision);
    }
    out
}

/// Convenience: skeletonise with no preserved bodies (radius 0).
pub fn skeleton(source: &str, lang: Lang) -> String {
    skeletonize(source, lang, &HashSet::new())
}

/// Detect the language from `path` and skeletonise; `None` for unsupported extensions.
pub fn skeletonize_path(path: &str, source: &str) -> Option<String> {
    Lang::from_path(path).map(|lang| skeleton(source, lang))
}

fn node_name<'a>(node: Node, source: &'a str) -> Option<&'a str> {
    node.child_by_field_name("name")
        .map(|n| &source[n.start_byte()..n.end_byte()])
}

fn collect_body_elisions(
    node: Node,
    source: &str,
    def_kinds: &[&str],
    keep: &HashSet<String>,
    out: &mut Vec<(usize, usize)>,
) {
    if def_kinds.contains(&node.kind()) {
        let keep_this = node_name(node, source).is_some_and(|n| keep.contains(n));
        if !keep_this {
            if let Some(body) = node.child_by_field_name("body") {
                out.push((body.start_byte(), body.end_byte()));
                // The whole body is gone; nested defs inside it go with it.
                return;
            }
        }
    }
    let mut cursor = node.walk();
    for child in node.children(&mut cursor) {
        collect_body_elisions(child, source, def_kinds, keep, out);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn keep(names: &[&str]) -> HashSet<String> {
        names.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn rust_bodies_are_elided_signatures_and_docs_kept() {
        let src = "\
/// Adds two numbers.
pub fn add(a: i32, b: i32) -> i32 {
    let sum = a + b;
    sum
}

struct Point { x: i32, y: i32 }
";
        let out = skeleton(src, Lang::Rust);
        assert!(out.contains("/// Adds two numbers."));
        assert!(out.contains("pub fn add(a: i32, b: i32) -> i32"));
        assert!(out.contains("{ … }"));
        assert!(!out.contains("let sum = a + b;"));
        // Struct fields are signatures and are preserved.
        assert!(out.contains("struct Point { x: i32, y: i32 }"));
    }

    #[test]
    fn keep_bodies_preserves_named_function() {
        let src = "\
fn keep_me() { let a = 1; }
fn drop_me() { let b = 2; }
";
        let out = skeletonize(src, Lang::Rust, &keep(&["keep_me"]));
        assert!(out.contains("let a = 1;"), "kept body should remain: {out}");
        assert!(
            !out.contains("let b = 2;"),
            "other body should be elided: {out}"
        );
    }

    #[test]
    fn methods_in_impl_blocks_are_skeletonised() {
        let src = "\
impl Foo {
    fn method(&self) -> u8 {
        let secret = 42;
        secret
    }
}
";
        let out = skeleton(src, Lang::Rust);
        assert!(out.contains("fn method(&self) -> u8"));
        assert!(!out.contains("let secret = 42;"));
    }

    #[test]
    fn python_bodies_are_elided() {
        let src = "\
def greet(name):
    msg = 'hi ' + name
    return msg
";
        let out = skeleton(src, Lang::Python);
        assert!(out.contains("def greet(name):"));
        assert!(out.contains("..."));
        assert!(!out.contains("msg = 'hi ' + name"));
    }

    #[test]
    fn typescript_bodies_are_elided() {
        let src = "\
function add(a: number, b: number): number {
    const s = a + b;
    return s;
}
";
        let out = skeleton(src, Lang::TypeScript);
        assert!(out.contains("function add(a: number, b: number): number"));
        assert!(!out.contains("const s = a + b;"));
    }

    #[test]
    fn unparseable_or_unknown_returns_input() {
        // Detection miss → None.
        assert!(skeletonize_path("notes.md", "# hi").is_none());
    }
}
