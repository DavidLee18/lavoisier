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
            },
            Lang::Python => LangSpec {
                def_kinds: &["function_definition"],
                elision: "...",
                symbol_kinds: &["function_definition", "class_definition"],
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
