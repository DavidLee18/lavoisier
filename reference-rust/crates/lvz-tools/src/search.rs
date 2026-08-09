//! `find_references` — an authoritative, repo-wide "where is this name used?" tool.
//!
//! This exists to replace the ad-hoc `grep -r … | sed -n …` loop the model otherwise falls into
//! when a task says "update all call sites" (`bench/README.md` Findings #2): a single call walks the
//! repo once and returns the **complete** set of references, grouped by file with a total count — so
//! the model gets the "that's all of them" signal it needs to stop, instead of grepping N times and
//! never being sure it is done.
//!
//! For source files of a known language it matches **identifier nodes** via `lvz-context`
//! (`find_identifier_lines`), so a mention inside a string or comment does not count — strictly more
//! precise than substring grep. For other text files it falls back to a word-boundary scan.

use async_trait::async_trait;
use std::fmt::Write as _;
use std::path::{Path, PathBuf};

use lvz_context::symbols::find_identifier_lines;
use lvz_context::Lang;
use lvz_protocol::{Tool, ToolError, ToolOutput};
use serde::Deserialize;
use serde_json::{json, Value};

/// `find_references` — list every reference to a symbol/name across the repo, in one round-trip.
pub struct FindReferencesTool;

#[derive(Deserialize)]
struct FindArgs {
    /// The identifier/symbol name to find references to.
    name: String,
    /// Directory to search (default: the working directory).
    #[serde(default = "dot")]
    path: String,
}

fn dot() -> String {
    ".".to_string()
}

/// Bound the walk so a huge monorepo can't stall a turn.
const MAX_FILES: usize = 20_000;
/// Cap reported matches so a pathological name can't blow the token budget (noted when hit).
const MAX_MATCHES: usize = 1_000;
/// Don't scan files larger than this (likely generated/minified/data).
const MAX_FILE_BYTES: u64 = 2_000_000;

fn skip_dir(name: &str) -> bool {
    name.starts_with('.')
        || matches!(
            name,
            "target" | "node_modules" | "dist" | "build" | "vendor" | "__pycache__"
        )
}

/// Word-boundary occurrences of `name` for files we can't parse: a match must not be flanked by
/// identifier characters (so `value_from_datadict` does not match inside `xvalue_from_datadicty`).
fn text_match_lines(source: &str, name: &str) -> Vec<(usize, String)> {
    let is_ident = |c: char| c.is_alphanumeric() || c == '_';
    let mut hits = Vec::new();
    for (i, line) in source.lines().enumerate() {
        let mut from = 0;
        while let Some(rel) = line[from..].find(name) {
            let start = from + rel;
            let end = start + name.len();
            let before_ok = start == 0 || !line[..start].chars().next_back().is_some_and(is_ident);
            let after_ok = end >= line.len() || !line[end..].chars().next().is_some_and(is_ident);
            if before_ok && after_ok {
                hits.push((i + 1, line.trim().to_string()));
                break; // one hit per line is enough
            }
            from = end;
        }
    }
    hits
}

/// Per-file match scan: AST-aware for known languages (so a successful parse with the name only in
/// a comment/string yields no hits — not a substring false positive), word-boundary text only when
/// the language is unknown or the file fails to parse.
fn matches_in(path: &str, source: &str, name: &str) -> Vec<(usize, String)> {
    match Lang::from_path(path).and_then(|lang| find_identifier_lines(source, lang, name)) {
        Some(hits) => hits, // parsed cleanly — trust the AST, even if empty
        None => text_match_lines(source, name), // unknown language or parse failure → text scan
    }
}

#[async_trait]
impl Tool for FindReferencesTool {
    fn name(&self) -> &str {
        "find_references"
    }

    fn description(&self) -> &str {
        "Find ALL references to an identifier/symbol across the repository in one call, grouped by \
         file with a total count. Use this — not `grep`/`sed` via shell — to enumerate call sites \
         before a rename or signature change: it returns the complete set in a single round-trip \
         (so you know when you've covered everything), and for source files it matches real code \
         identifiers, ignoring mentions inside strings and comments. Falls back to a word-boundary \
         text match for non-source files."
    }

    fn schema(&self) -> Value {
        json!({
            "type": "object",
            "properties": {
                "name": { "type": "string", "description": "Identifier/symbol name to find references to" },
                "path": { "type": "string", "description": "Directory to search (default '.')" }
            },
            "required": ["name"]
        })
    }

    async fn invoke(&self, args: Value) -> Result<ToolOutput, ToolError> {
        let FindArgs { name, path } = parse_args(args)?;
        if name.is_empty() {
            return Ok(ToolOutput::error(
                "find_references: `name` must not be empty",
            ));
        }
        let root = PathBuf::from(&path);

        // Collect candidate files (bounded, skipping VCS/build/dep dirs), sorted for stable output.
        let mut files: Vec<PathBuf> = Vec::new();
        let mut stack = vec![root.clone()];
        while let Some(dir) = stack.pop() {
            if files.len() >= MAX_FILES {
                break;
            }
            let Ok(entries) = std::fs::read_dir(&dir) else {
                continue;
            };
            for entry in entries.flatten() {
                let Ok(ft) = entry.file_type() else { continue };
                if ft.is_dir() {
                    if !skip_dir(&entry.file_name().to_string_lossy()) {
                        stack.push(entry.path());
                    }
                } else if ft.is_file() {
                    if let Ok(meta) = entry.metadata() {
                        if meta.len() <= MAX_FILE_BYTES {
                            files.push(entry.path());
                        }
                    }
                }
            }
        }
        files.sort();

        // Scan each file; group matches per (relative) path.
        let mut groups: Vec<(String, Vec<(usize, String)>)> = Vec::new();
        let mut total = 0usize;
        let mut capped = false;
        for file in &files {
            let Ok(source) = std::fs::read_to_string(file) else {
                continue; // binary / non-UTF-8 — skip
            };
            if !source.contains(&name) {
                continue; // cheap reject before parsing
            }
            let rel = file
                .strip_prefix(&root)
                .ok()
                .and_then(Path::to_str)
                .unwrap_or_else(|| file.to_str().unwrap_or("?"))
                .to_string();
            let hits = matches_in(file.to_str().unwrap_or(&rel), &source, &name);
            if hits.is_empty() {
                continue;
            }
            total += hits.len();
            groups.push((rel, hits));
            if total >= MAX_MATCHES {
                capped = true;
                break;
            }
        }

        if groups.is_empty() {
            return Ok(ToolOutput::ok(format!(
                "No references to `{name}` found under {path}."
            )));
        }

        let mut out = String::new();
        let note = if capped {
            format!(" (capped at {MAX_MATCHES}; narrow with `path`)")
        } else {
            String::new()
        };
        let _ = writeln!(
            out,
            "Found {total} reference(s) to `{name}` in {} file(s){note}:\n",
            groups.len()
        );
        for (rel, hits) in &groups {
            let _ = writeln!(out, "{rel} ({}):", hits.len());
            for (line, text) in hits {
                // Keep each line short — the location is the signal, not the full line.
                let snippet: String = text.chars().take(160).collect();
                let _ = writeln!(out, "  {line}: {snippet}");
            }
        }
        Ok(ToolOutput::ok(out.trim_end().to_string()))
    }
}

fn parse_args<T: for<'de> Deserialize<'de>>(args: Value) -> Result<T, ToolError> {
    serde_json::from_value(args).map_err(|e| ToolError::InvalidArgs(e.to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[tokio::test]
    async fn finds_references_grouped_and_counted_skipping_comments() {
        let dir = std::env::temp_dir().join(format!("lvz-find-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(dir.join("sub")).unwrap();
        std::fs::create_dir_all(dir.join("node_modules")).unwrap();
        // Real reference (call) + a definition; a comment mention must NOT count.
        std::fs::write(
            dir.join("a.rs"),
            "fn widget() -> i32 { 0 }\nfn use_it() -> i32 { widget() } // widget in comment\n",
        )
        .unwrap();
        std::fs::write(dir.join("sub/b.rs"), "fn other() -> i32 { widget() }\n").unwrap();
        // A skipped dependency dir must be ignored even though it mentions the name.
        std::fs::write(dir.join("node_modules/c.rs"), "fn z() { widget() }\n").unwrap();

        let out = FindReferencesTool
            .invoke(json!({ "name": "widget", "path": dir.to_str().unwrap() }))
            .await
            .unwrap();
        assert!(!out.is_error, "{}", out.content);
        // a.rs: definition + 1 call (comment excluded) = 2; sub/b.rs: 1. Total 3 across 2 files.
        assert!(
            out.content
                .contains("3 reference(s) to `widget` in 2 file(s)"),
            "got:\n{}",
            out.content
        );
        assert!(out.content.contains("a.rs (2):"));
        assert!(out.content.contains("b.rs (1):"));
        assert!(!out.content.contains("node_modules"));
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[tokio::test]
    async fn no_matches_reports_cleanly() {
        let dir = std::env::temp_dir().join(format!("lvz-find-none-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("a.rs"), "fn f() {}\n").unwrap();
        let out = FindReferencesTool
            .invoke(json!({ "name": "nonexistent", "path": dir.to_str().unwrap() }))
            .await
            .unwrap();
        assert!(!out.is_error);
        assert!(out.content.contains("No references to `nonexistent`"));
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// Manual scale check against a real checkout: `LVZ_SMOKE_DIR=… LVZ_SMOKE_NAME=… \
    /// cargo test -p lvz-tools find_references_scale -- --ignored --nocapture`. Confirms the tool
    /// completes on a large tree and prints the complete grouped reference set.
    #[tokio::test]
    #[ignore = "needs a real repo via LVZ_SMOKE_DIR/LVZ_SMOKE_NAME"]
    async fn find_references_scale_smoke() {
        let dir = std::env::var("LVZ_SMOKE_DIR").expect("set LVZ_SMOKE_DIR");
        let name = std::env::var("LVZ_SMOKE_NAME").expect("set LVZ_SMOKE_NAME");
        let out = FindReferencesTool
            .invoke(json!({ "name": name, "path": dir }))
            .await
            .unwrap();
        eprintln!("{}", out.content);
        assert!(!out.is_error);
    }
}
