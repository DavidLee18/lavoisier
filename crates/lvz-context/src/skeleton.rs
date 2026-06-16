//! File-skeleton extraction (§6.1, the largest token lever): keep signatures,
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
    let mut elisions: Vec<Elision> = Vec::new();
    collect_body_elisions(tree.root_node(), source, &spec, keep_bodies, &mut elisions);

    // Apply right-to-left so earlier byte offsets stay valid.
    elisions.sort_by_key(|e| std::cmp::Reverse(e.start));
    let mut out = source.to_string();
    for e in elisions {
        out.replace_range(e.start..e.end, &e.replacement);
    }
    out
}

/// One body region to elide: the byte range `[start, end)` and the text it is replaced with.
/// The replacement is usually the language's bare placeholder, but the docstring-preserving path
/// elides only the *post-docstring* range and carries a re-indented placeholder.
struct Elision {
    start: usize,
    end: usize,
    replacement: String,
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
    spec: &crate::lang::LangSpec,
    keep: &HashSet<String>,
    out: &mut Vec<Elision>,
) {
    if spec.def_kinds.contains(&node.kind()) {
        let keep_this = node_name(node, source).is_some_and(|n| keep.contains(n));
        if !keep_this {
            if let Some(body) = node.child_by_field_name("body") {
                // Docstring fidelity (§6.1): keep a leading docstring statement, eliding only the
                // body that follows it. The placeholder is re-indented onto its own line so the
                // kept docstring reads cleanly.
                if spec.keeps_docstring {
                    if let Some(doc_end) = leading_docstring_end(body, source) {
                        if doc_end < body.end_byte() {
                            let indent = line_indent(source, body.start_byte());
                            out.push(Elision {
                                start: doc_end,
                                end: body.end_byte(),
                                replacement: format!("\n{indent}{}", spec.elision),
                            });
                        }
                        // A docstring-only body keeps everything (nothing left to elide).
                        return;
                    }
                }
                out.push(Elision {
                    start: body.start_byte(),
                    end: body.end_byte(),
                    replacement: spec.elision.to_string(),
                });
                // The whole body is gone; nested defs inside it go with it.
                return;
            }
        }
    }
    let mut cursor = node.walk();
    for child in node.children(&mut cursor) {
        collect_body_elisions(child, source, spec, keep, out);
    }
}

/// If `body`'s first statement is a bare string expression (a docstring), the byte offset just
/// past it; otherwise `None`. Handles the Python shape `block → expression_statement → string`.
fn leading_docstring_end(body: Node, _source: &str) -> Option<usize> {
    let mut cursor = body.walk();
    let first = body.named_children(&mut cursor).next()?;
    if first.kind() != "expression_statement" {
        return None;
    }
    let mut inner = first.walk();
    let is_string = first
        .named_children(&mut inner)
        .next()
        .is_some_and(|n| n.kind() == "string");
    is_string.then(|| first.end_byte())
}

/// The whitespace indentation of the line containing byte offset `at` (the run between the
/// preceding newline and `at`). Used to re-indent the placeholder under a kept docstring.
fn line_indent(source: &str, at: usize) -> &str {
    let line_start = source[..at].rfind('\n').map(|i| i + 1).unwrap_or(0);
    &source[line_start..at]
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
    fn python_docstring_is_kept_when_body_is_elided() {
        let src = "\
def greet(name):
    \"\"\"Return a friendly greeting for name.\"\"\"
    msg = 'hi ' + name
    return msg
";
        let out = skeleton(src, Lang::Python);
        assert!(out.contains("def greet(name):"));
        // The docstring survives; the executable body does not.
        assert!(
            out.contains("\"\"\"Return a friendly greeting for name.\"\"\""),
            "docstring kept: {out}"
        );
        assert!(!out.contains("msg = 'hi ' + name"), "body elided: {out}");
        assert!(out.contains("..."), "placeholder present: {out}");
        // The placeholder lands on its own indented line after the docstring.
        assert!(
            out.contains("\"\"\"\n    ..."),
            "re-indented placeholder: {out}"
        );
    }

    #[test]
    fn python_docstring_only_body_is_kept_whole() {
        let src = "\
def stub():
    \"\"\"Not implemented yet.\"\"\"
";
        let out = skeleton(src, Lang::Python);
        assert!(out.contains("\"\"\"Not implemented yet.\"\"\""));
        // Nothing to elide beyond the docstring → no stray placeholder added.
        assert!(
            !out.contains("..."),
            "no placeholder for docstring-only body: {out}"
        );
    }

    #[test]
    fn python_method_docstring_kept_with_class_indent() {
        let src = "\
class C:
    def m(self):
        \"\"\"Do the thing.\"\"\"
        x = 1
        return x
";
        let out = skeleton(src, Lang::Python);
        assert!(
            out.contains("\"\"\"Do the thing.\"\"\""),
            "method docstring kept: {out}"
        );
        assert!(!out.contains("x = 1"), "method body elided: {out}");
        // Placeholder re-indented to the method-body level (8 spaces).
        assert!(
            out.contains("\"\"\"\n        ..."),
            "deep indent preserved: {out}"
        );
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
