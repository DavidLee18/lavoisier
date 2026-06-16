//! Language detection and per-language tree-sitter configuration.
//!
//! Each supported [`Lang`] knows its tree-sitter grammar and which definition nodes carry
//! an elidable `body` field — the knobs the skeletoniser (`super::skeleton`) needs to keep
//! signatures while dropping bodies.

use tree_sitter::Language as TsLanguage;

/// A source language Lavoisier can parse for skeletons and symbols.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Lang {
    Rust,
    Python,
    JavaScript,
    TypeScript,
}

/// How to elide bodies for a language.
pub(crate) struct LangSpec {
    /// Definition node kinds whose `body` field should be replaced by [`elision`](Self::elision).
    pub def_kinds: &'static [&'static str],
    /// Placeholder text the body is replaced with (kept syntactically suggestive, not valid).
    pub elision: &'static str,
    /// Named-definition node kinds that become nodes in the symbol-dependency graph.
    pub symbol_kinds: &'static [&'static str],
    /// Keep a leading docstring (a bare string statement as the body's first item) when eliding
    /// the rest of the body — §6.1 wants docstrings retained as high-signal context.
    /// True only for Python, whose `def` bodies conventionally open with a `"""…"""` docstring.
    pub keeps_docstring: bool,
    /// Leaf node kinds that count as a *reference* to a name when resolving symbol-dependency
    /// edges (`super::symbols`). Restricting to real identifier nodes (vs. raw substring search)
    /// is what makes a name in a string or comment stop creating a spurious edge.
    pub ref_ident_kinds: &'static [&'static str],
    /// Node kinds that introduce **local bindings** (parameters, `let`/variable declarations).
    /// The identifiers in their binding position (`pattern`/`name` field, else direct children)
    /// are locals, so they are excluded from references — this is the scope/shadowing fix: a local
    /// variable that happens to share a top-level symbol's name no longer links to that symbol.
    pub binder_kinds: &'static [&'static str],
}

impl Lang {
    /// Best-effort detection from a file path's extension.
    pub fn from_path(path: &str) -> Option<Lang> {
        let ext = path.rsplit('.').next()?.to_ascii_lowercase();
        Some(match ext.as_str() {
            "rs" => Lang::Rust,
            "py" | "pyi" => Lang::Python,
            "js" | "jsx" | "mjs" | "cjs" => Lang::JavaScript,
            "ts" | "tsx" | "mts" | "cts" => Lang::TypeScript,
            _ => return None,
        })
    }

    /// The tree-sitter grammar for this language.
    pub(crate) fn ts_language(self) -> TsLanguage {
        match self {
            Lang::Rust => tree_sitter_rust::LANGUAGE.into(),
            Lang::Python => tree_sitter_python::LANGUAGE.into(),
            Lang::JavaScript => tree_sitter_javascript::LANGUAGE.into(),
            Lang::TypeScript => tree_sitter_typescript::LANGUAGE_TYPESCRIPT.into(),
        }
    }

    pub(crate) fn spec(self) -> LangSpec {
        match self {
            Lang::Rust => LangSpec {
                def_kinds: &["function_item"],
                elision: "{ … }",
                symbol_kinds: &[
                    "function_item",
                    "struct_item",
                    "enum_item",
                    "trait_item",
                    "type_item",
                    "const_item",
                    "static_item",
                ],
                keeps_docstring: false,
                ref_ident_kinds: &["identifier", "type_identifier"],
                binder_kinds: &["parameter", "let_declaration", "closure_parameters"],
            },
            Lang::Python => LangSpec {
                def_kinds: &["function_definition"],
                elision: "...",
                symbol_kinds: &["function_definition", "class_definition"],
                keeps_docstring: true,
                ref_ident_kinds: &["identifier"],
                binder_kinds: &["parameters", "lambda_parameters"],
            },
            Lang::JavaScript => LangSpec {
                def_kinds: &[
                    "function_declaration",
                    "method_definition",
                    "function_expression",
                ],
                elision: "{ … }",
                symbol_kinds: &[
                    "function_declaration",
                    "method_definition",
                    "class_declaration",
                ],
                keeps_docstring: false,
                ref_ident_kinds: &["identifier"],
                binder_kinds: &["formal_parameters", "variable_declarator"],
            },
            Lang::TypeScript => LangSpec {
                def_kinds: &[
                    "function_declaration",
                    "method_definition",
                    "function_expression",
                ],
                elision: "{ … }",
                symbol_kinds: &[
                    "function_declaration",
                    "method_definition",
                    "class_declaration",
                    "interface_declaration",
                    "type_alias_declaration",
                ],
                keeps_docstring: false,
                ref_ident_kinds: &["identifier", "type_identifier"],
                binder_kinds: &[
                    "formal_parameters",
                    "variable_declarator",
                    "required_parameter",
                    "optional_parameter",
                ],
            },
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detects_languages_by_extension() {
        assert_eq!(Lang::from_path("src/main.rs"), Some(Lang::Rust));
        assert_eq!(Lang::from_path("a/b/c.py"), Some(Lang::Python));
        assert_eq!(Lang::from_path("x.JSX"), Some(Lang::JavaScript));
        assert_eq!(Lang::from_path("x.tsx"), Some(Lang::TypeScript));
        assert_eq!(Lang::from_path("README.md"), None);
        assert_eq!(Lang::from_path("noext"), None);
    }
}
