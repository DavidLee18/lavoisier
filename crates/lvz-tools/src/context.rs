//! Token-efficient context tools built on `lvz-context` (§6.1): read a file's
//! structure cheaply (skeleton), read it with edit anchors, and edit it by anchor without
//! resending the whole file. These let the agent spend far fewer tokens than naive
//! read_file/write_file round-trips.

use async_trait::async_trait;
use lvz_context::anchor::{apply_edits, render_anchored, Edit, EditOp};
use lvz_context::diff::unified_diff;
use lvz_context::symbols::skeleton_with_radius;
use lvz_context::{skeleton, Lang};
use lvz_protocol::{Tool, ToolError, ToolOutput};
use serde::Deserialize;
use serde_json::{json, Value};

fn parse_args<T: for<'de> Deserialize<'de>>(args: Value) -> Result<T, ToolError> {
    serde_json::from_value(args).map_err(|e| ToolError::InvalidArgs(e.to_string()))
}

/// `outline_file` — a file's skeleton (signatures kept, bodies elided). Cheap structural read.
pub struct OutlineFileTool;

#[derive(Deserialize)]
struct PathArg {
    path: String,
}

#[derive(Deserialize)]
struct OutlineArgs {
    path: String,
    /// Symbol to expand around: its body and those of its dependencies (within `radius` hops)
    /// are kept in full while everything else is elided.
    #[serde(default)]
    focus: Option<String>,
    /// Dependency-hop radius for `focus` (default 1).
    #[serde(default)]
    radius: Option<u8>,
}

#[async_trait]
impl Tool for OutlineFileTool {
    fn name(&self) -> &str {
        "outline_file"
    }

    fn description(&self) -> &str {
        "Return a token-efficient skeleton of a source file: function/method signatures, \
         types, and doc comments are kept while bodies are elided. Prefer this over read_file \
         to understand a file's structure before reading specific parts. Optionally pass \
         `focus` (a symbol name) to keep that symbol's body and its dependencies' bodies \
         (within `radius` hops, default 1) in full while eliding the rest. Supports Rust, \
         Python, JavaScript, TypeScript; falls back to the raw file for other languages."
    }

    fn schema(&self) -> Value {
        json!({
            "type": "object",
            "properties": {
                "path": { "type": "string", "description": "Path to the source file" },
                "focus": { "type": "string", "description": "Symbol to expand around (keep its body + dependencies)" },
                "radius": { "type": "integer", "minimum": 0, "description": "Dependency-hop radius for focus (default 1)" }
            },
            "required": ["path"]
        })
    }

    async fn invoke(&self, args: Value) -> Result<ToolOutput, ToolError> {
        let OutlineArgs {
            path,
            focus,
            radius,
        } = parse_args(args)?;
        let source = match tokio::fs::read_to_string(&path).await {
            Ok(s) => s,
            Err(e) => return Ok(ToolOutput::error(format!("outline_file {path}: {e}"))),
        };
        let outline = outline_source(&path, &source, focus.as_deref(), radius.unwrap_or(1));
        Ok(ToolOutput::ok(outline))
    }
}

/// Skeletonise one file's source (the shared core of `outline_file`/`outline_files`): apply
/// `focus`+`radius` when supported, fall back to a plain skeleton, or the raw file for an
/// unsupported language. Read errors are surfaced by the caller.
fn outline_source(path: &str, source: &str, focus: Option<&str>, radius: u8) -> String {
    match Lang::from_path(path) {
        Some(lang) => match focus {
            Some(target) => skeleton_with_radius(source, lang, target, radius),
            None => skeleton::skeleton(source, lang),
        },
        None => source.to_string(),
    }
}

/// `outline_files` — skeletons of several files in one round-trip (§6.1 batching).
pub struct OutlineFilesTool;

#[derive(Deserialize)]
struct OutlineFilesArgs {
    paths: Vec<String>,
    #[serde(default)]
    focus: Option<String>,
    #[serde(default)]
    radius: Option<u8>,
}

#[async_trait]
impl Tool for OutlineFilesTool {
    fn name(&self) -> &str {
        "outline_files"
    }

    fn description(&self) -> &str {
        "Return token-efficient skeletons of several source files at once, concatenated under \
         per-file headers. Prefer this over multiple outline_file calls when surveying more than \
         one file — one round-trip instead of several. Optional `focus`/`radius` apply to each \
         file. A failure to read one file is reported inline; the rest still return."
    }

    fn schema(&self) -> Value {
        json!({
            "type": "object",
            "properties": {
                "paths": {
                    "type": "array",
                    "items": { "type": "string" },
                    "description": "Paths to the source files"
                },
                "focus": { "type": "string", "description": "Symbol to expand around in each file (keep its body + dependencies)" },
                "radius": { "type": "integer", "minimum": 0, "description": "Dependency-hop radius for focus (default 1)" }
            },
            "required": ["paths"]
        })
    }

    async fn invoke(&self, args: Value) -> Result<ToolOutput, ToolError> {
        let OutlineFilesArgs {
            paths,
            focus,
            radius,
        } = parse_args(args)?;
        let mut sections = Vec::with_capacity(paths.len());
        for path in paths {
            let body = match tokio::fs::read_to_string(&path).await {
                Ok(source) => outline_source(&path, &source, focus.as_deref(), radius.unwrap_or(1)),
                Err(e) => format!("[error: {e}]"),
            };
            sections.push(format!("===== {path} =====\n{body}"));
        }
        Ok(ToolOutput::ok(sections.join("\n\n")))
    }
}

/// `read_anchored` — a file rendered with a per-line `anchor│ ` gutter for use with
/// `edit_anchored`.
pub struct ReadAnchoredTool;

#[async_trait]
impl Tool for ReadAnchoredTool {
    fn name(&self) -> &str {
        "read_anchored"
    }

    fn description(&self) -> &str {
        "Return a file with a stable per-line anchor in the left gutter (format `ANCHOR│ \
         text`). Use the anchors with edit_anchored to change specific lines without \
         resending the whole file."
    }

    fn schema(&self) -> Value {
        json!({
            "type": "object",
            "properties": { "path": { "type": "string", "description": "Path to the file" } },
            "required": ["path"]
        })
    }

    async fn invoke(&self, args: Value) -> Result<ToolOutput, ToolError> {
        let PathArg { path } = parse_args(args)?;
        match tokio::fs::read_to_string(&path).await {
            Ok(s) => Ok(ToolOutput::ok(render_anchored(&s))),
            Err(e) => Ok(ToolOutput::error(format!("read_anchored {path}: {e}"))),
        }
    }
}

/// `edit_anchored` — apply hash-anchored edits to a file and write it back.
pub struct EditAnchoredTool;

#[derive(Deserialize)]
struct EditArgs {
    path: String,
    edits: Vec<EditSpec>,
}

#[derive(Deserialize)]
struct EditSpec {
    anchor: String,
    op: String,
    #[serde(default)]
    text: Option<String>,
}

impl EditSpec {
    fn into_edit(self) -> Result<Edit, ToolError> {
        let text = || {
            self.text
                .clone()
                .ok_or_else(|| ToolError::InvalidArgs(format!("op '{}' requires `text`", self.op)))
        };
        let op = match self.op.as_str() {
            "replace" => EditOp::Replace(text()?),
            "insert_after" => EditOp::InsertAfter(text()?),
            "insert_before" => EditOp::InsertBefore(text()?),
            "delete" => EditOp::Delete,
            other => {
                return Err(ToolError::InvalidArgs(format!(
                    "unknown op '{other}' (expected replace|insert_after|insert_before|delete)"
                )))
            }
        };
        Ok(Edit {
            anchor: self.anchor,
            op,
        })
    }
}

#[async_trait]
impl Tool for EditAnchoredTool {
    fn name(&self) -> &str {
        "edit_anchored"
    }

    fn description(&self) -> &str {
        "Apply one or more anchored edits to a file (see read_anchored for anchors) and write \
         it back. Each edit targets a line by its anchor with op replace|insert_after|\
         insert_before|delete (replace/insert require `text`). The batch is atomic: if any \
         anchor is missing or ambiguous, nothing is written. Returns a unified diff of the \
         change."
    }

    fn schema(&self) -> Value {
        json!({
            "type": "object",
            "properties": {
                "path": { "type": "string", "description": "Path to the file to edit" },
                "edits": {
                    "type": "array",
                    "description": "Edits to apply, each targeting a line by anchor",
                    "items": {
                        "type": "object",
                        "properties": {
                            "anchor": { "type": "string", "description": "Line anchor from read_anchored" },
                            "op": {
                                "type": "string",
                                "enum": ["replace", "insert_after", "insert_before", "delete"]
                            },
                            "text": { "type": "string", "description": "Replacement/inserted text (omit for delete)" }
                        },
                        "required": ["anchor", "op"]
                    }
                }
            },
            "required": ["path", "edits"]
        })
    }

    async fn invoke(&self, args: Value) -> Result<ToolOutput, ToolError> {
        let EditArgs { path, edits } = parse_args(args)?;
        let edits: Vec<Edit> = edits
            .into_iter()
            .map(EditSpec::into_edit)
            .collect::<Result<_, _>>()?;

        let original = match tokio::fs::read_to_string(&path).await {
            Ok(s) => s,
            Err(e) => return Ok(ToolOutput::error(format!("edit_anchored {path}: {e}"))),
        };

        let updated = match apply_edits(&original, &edits) {
            Ok(s) => s,
            Err(e) => return Ok(ToolOutput::error(format!("edit_anchored {path}: {e}"))),
        };

        if let Err(e) = tokio::fs::write(&path, &updated).await {
            return Ok(ToolOutput::error(format!("edit_anchored {path}: {e}")));
        }

        let diff = unified_diff(&original, &updated, 2);
        Ok(
            ToolOutput::ok(format!("applied {} edit(s) to {path}\n{diff}", edits.len()))
                .changed(updated != original),
        )
    }
}

/// Apply anchored edits to one file (read → apply → write), returning `(summary + diff, changed)`
/// on success or an error string on failure. `changed` is whether the write actually altered the
/// file. The whole-file apply is atomic: if any anchor is missing or ambiguous, nothing is written.
/// Shared by the `edit_files` batch tool.
async fn apply_anchored_to_file(
    path: &str,
    specs: Vec<EditSpec>,
) -> Result<(String, bool), String> {
    let edits: Vec<Edit> = specs
        .into_iter()
        .map(EditSpec::into_edit)
        .collect::<Result<_, ToolError>>()
        .map_err(|e| format!("{path}: {e}"))?;
    let original = tokio::fs::read_to_string(path)
        .await
        .map_err(|e| format!("{path}: {e}"))?;
    let updated = apply_edits(&original, &edits).map_err(|e| format!("{path}: {e}"))?;
    tokio::fs::write(path, &updated)
        .await
        .map_err(|e| format!("{path}: {e}"))?;
    let diff = unified_diff(&original, &updated, 2);
    let changed = updated != original;
    Ok((
        format!("applied {} edit(s) to {path}\n{diff}", edits.len()),
        changed,
    ))
}

/// `edit_files` — apply anchored edits across several files in one round-trip (the write-side
/// counterpart to `read_files`/`outline_files`). The natural follow-up to `find_references`: edit
/// every call site in a single call instead of one `edit_anchored` round-trip per file.
pub struct EditFilesTool;

#[derive(Deserialize)]
struct EditFilesArgs {
    files: Vec<FileEdits>,
}

#[derive(Deserialize)]
struct FileEdits {
    path: String,
    edits: Vec<EditSpec>,
}

#[async_trait]
impl Tool for EditFilesTool {
    fn name(&self) -> &str {
        "edit_files"
    }

    fn description(&self) -> &str {
        "Apply anchored edits to SEVERAL files in one call — the multi-file form of edit_anchored. \
         Pass `files`, each `{ path, edits }` where `edits` are anchored ops (see read_anchored / \
         edit_anchored). Prefer this over many edit_anchored calls when a change spans multiple \
         files (e.g. updating every call site after find_references): one round-trip instead of one \
         per file. Each file is applied atomically; a file whose anchor is missing/ambiguous is \
         reported inline and skipped while the others still apply. Returns a per-file diff/summary."
    }

    fn schema(&self) -> Value {
        json!({
            "type": "object",
            "properties": {
                "files": {
                    "type": "array",
                    "description": "Per-file edit batches",
                    "items": {
                        "type": "object",
                        "properties": {
                            "path": { "type": "string", "description": "Path to the file to edit" },
                            "edits": {
                                "type": "array",
                                "description": "Anchored edits to apply to this file",
                                "items": {
                                    "type": "object",
                                    "properties": {
                                        "anchor": { "type": "string", "description": "Line anchor from read_anchored" },
                                        "op": { "type": "string", "enum": ["replace", "insert_after", "insert_before", "delete"] },
                                        "text": { "type": "string", "description": "Replacement/inserted text (omit for delete)" }
                                    },
                                    "required": ["anchor", "op"]
                                }
                            }
                        },
                        "required": ["path", "edits"]
                    }
                }
            },
            "required": ["files"]
        })
    }

    async fn invoke(&self, args: Value) -> Result<ToolOutput, ToolError> {
        let EditFilesArgs { files } = parse_args(args)?;
        let mut sections = Vec::with_capacity(files.len());
        let mut applied = 0usize;
        let mut failed = 0usize;
        let mut any_changed = false;
        for FileEdits { path, edits } in files {
            let body = match apply_anchored_to_file(&path, edits).await {
                Ok((summary, changed)) => {
                    applied += 1;
                    any_changed |= changed;
                    summary
                }
                Err(e) => {
                    failed += 1;
                    format!("[error: {e}]")
                }
            };
            sections.push(format!("===== {path} =====\n{body}"));
        }
        let header = format!("edit_files: applied {applied} file(s), {failed} failed.\n");
        let content = format!("{header}\n{}", sections.join("\n\n"));
        // Surface a batch with any failure as an error so the model retries just those files;
        // `changed` reflects whether at least one file was actually modified (drives convergence).
        Ok(ToolOutput {
            content,
            is_error: failed > 0,
            changed: any_changed,
        })
    }
}

/// `str_replace` — the primary edit tool: find an **exact string** and replace it. Unlike the
/// hash-anchored tools, there are no opaque anchors — you pass the literal text — which is the most
/// reliable edit primitive for models. **Accuracy first:** by default `old` must occur *exactly
/// once* in the file; a zero or non-unique match is a hard error (it never guesses or edits the wrong
/// occurrence), so the model must add surrounding context to disambiguate or pass `replace_all`.
/// `replace_all` replaces every occurrence (a rename), and `paths` applies the same edit to several
/// files in one call — so a project-wide rename is a single round-trip.
pub struct StrReplaceTool;

#[derive(Deserialize)]
struct StrReplaceArgs {
    /// One file to edit. Use this or `paths`.
    #[serde(default)]
    path: Option<String>,
    /// Several files to apply the same replacement to (e.g. a project-wide rename). Use this or `path`.
    #[serde(default)]
    paths: Option<Vec<String>>,
    /// The exact text to find (verbatim, including indentation/newlines).
    old: String,
    /// The replacement text.
    new: String,
    /// Replace every occurrence instead of requiring a unique match.
    #[serde(default)]
    replace_all: bool,
}

#[async_trait]
impl Tool for StrReplaceTool {
    fn name(&self) -> &str {
        "str_replace"
    }

    fn description(&self) -> &str {
        "Edit a file by exact-string replacement — the preferred edit tool. Pass `old` (verbatim text \
         to find, including indentation) and `new`. By default `old` must match exactly once (a \
         missing or non-unique match is an error — add surrounding context to disambiguate). Pass \
         `replace_all: true` to replace every occurrence (e.g. a rename), and `paths` (instead of \
         `path`) to apply the same replacement across several files in one call — ideal for a \
         project-wide rename after find_references. Returns a per-file count."
    }

    fn schema(&self) -> Value {
        json!({
            "type": "object",
            "properties": {
                "path": { "type": "string", "description": "File to edit (use this or paths)" },
                "paths": { "type": "array", "items": { "type": "string" }, "description": "Files to apply the same edit to (use this or path)" },
                "old": { "type": "string", "description": "Exact text to find (verbatim)" },
                "new": { "type": "string", "description": "Replacement text" },
                "replace_all": { "type": "boolean", "description": "Replace every occurrence (default false: require a unique match)" }
            },
            "required": ["old", "new"]
        })
    }

    async fn invoke(&self, args: Value) -> Result<ToolOutput, ToolError> {
        let StrReplaceArgs {
            path,
            paths,
            old,
            new,
            replace_all,
        } = parse_args(args)?;
        if old.is_empty() {
            return Ok(ToolOutput::error("str_replace: `old` must not be empty"));
        }
        let targets: Vec<String> = match (path, paths) {
            (Some(p), None) => vec![p],
            (None, Some(ps)) => ps,
            (Some(p), Some(mut ps)) => {
                ps.push(p);
                ps
            }
            (None, None) => return Ok(ToolOutput::error("str_replace: provide `path` or `paths`")),
        };

        let mut lines = Vec::with_capacity(targets.len());
        let mut any_changed = false;
        let mut any_error = false;
        for p in &targets {
            let original = match tokio::fs::read_to_string(p).await {
                Ok(s) => s,
                Err(e) => {
                    any_error = true;
                    lines.push(format!("{p}: read error ({e})"));
                    continue;
                }
            };
            let count = original.matches(&old).count();
            if count == 0 {
                any_error = true;
                lines.push(format!("{p}: `old` not found"));
                continue;
            }
            if count > 1 && !replace_all {
                any_error = true;
                lines.push(format!(
                    "{p}: `old` occurs {count}× — pass replace_all, or include more context to make it unique"
                ));
                continue;
            }
            let updated = if replace_all {
                original.replace(&old, &new)
            } else {
                original.replacen(&old, &new, 1)
            };
            if updated == original {
                lines.push(format!("{p}: no change (replacement equals original)"));
                continue;
            }
            if let Err(e) = tokio::fs::write(p, &updated).await {
                any_error = true;
                lines.push(format!("{p}: write error ({e})"));
                continue;
            }
            any_changed = true;
            lines.push(format!("{p}: replaced {count} occurrence(s)"));
        }
        Ok(ToolOutput {
            content: format!("str_replace:\n{}", lines.join("\n")),
            is_error: any_error,
            changed: any_changed,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn outline_elides_bodies() {
        let dir = std::env::temp_dir().join(format!("lvz_ctx_{}", std::process::id()));
        let _ = tokio::fs::create_dir_all(&dir).await;
        let path = dir.join("f.rs");
        let p = path.to_string_lossy().to_string();
        tokio::fs::write(&path, "fn f() {\n    let secret = 9;\n}\n")
            .await
            .unwrap();

        let out = OutlineFileTool.invoke(json!({ "path": p })).await.unwrap();
        assert!(out.content.contains("fn f()"));
        assert!(!out.content.contains("secret"));
        let _ = tokio::fs::remove_dir_all(&dir).await;
    }

    #[tokio::test]
    async fn outline_focus_keeps_target_and_dependency_bodies() {
        let dir = std::env::temp_dir().join(format!("lvz_ctx_focus_{}", std::process::id()));
        let _ = tokio::fs::create_dir_all(&dir).await;
        let path = dir.join("m.rs");
        let p = path.to_string_lossy().to_string();
        tokio::fs::write(
            &path,
            "fn helper() -> i32 { 11 }\nfn target() -> i32 { helper() }\nfn other() -> i32 { 99 }\n",
        )
        .await
        .unwrap();

        let out = OutlineFileTool
            .invoke(json!({ "path": p, "focus": "target", "radius": 1 }))
            .await
            .unwrap();
        // target + helper bodies kept; other elided.
        assert!(out.content.contains("helper()"));
        assert!(out.content.contains("11"));
        assert!(!out.content.contains("99"));
        let _ = tokio::fs::remove_dir_all(&dir).await;
    }

    #[tokio::test]
    async fn edit_anchored_applies_and_reports_diff() {
        let dir = std::env::temp_dir().join(format!("lvz_ctx_edit_{}", std::process::id()));
        let _ = tokio::fs::create_dir_all(&dir).await;
        let path = dir.join("g.txt");
        let p = path.to_string_lossy().to_string();
        tokio::fs::write(&path, "alpha\nbeta\ngamma\n")
            .await
            .unwrap();

        let anchor = lvz_context::anchor::anchor_of("beta");
        let out = EditAnchoredTool
            .invoke(json!({
                "path": p,
                "edits": [{ "anchor": anchor, "op": "replace", "text": "BETA" }]
            }))
            .await
            .unwrap();
        assert!(!out.is_error, "{}", out.content);
        assert!(out.content.contains("+BETA"));

        let after = tokio::fs::read_to_string(&path).await.unwrap();
        assert_eq!(after, "alpha\nBETA\ngamma\n");
        let _ = tokio::fs::remove_dir_all(&dir).await;
    }

    #[tokio::test]
    async fn edit_files_applies_across_multiple_files_in_one_call() {
        let dir = std::env::temp_dir().join(format!("lvz_ctx_editfiles_{}", std::process::id()));
        let _ = tokio::fs::create_dir_all(&dir).await;
        let a = dir.join("a.txt");
        let b = dir.join("b.txt");
        let (pa, pb) = (
            a.to_string_lossy().to_string(),
            b.to_string_lossy().to_string(),
        );
        tokio::fs::write(&a, "alpha\nkeep\n").await.unwrap();
        tokio::fs::write(&b, "beta\nkeep\n").await.unwrap();

        let out = EditFilesTool
            .invoke(json!({
                "files": [
                    { "path": pa, "edits": [{ "anchor": lvz_context::anchor::anchor_of("alpha"), "op": "replace", "text": "ALPHA" }] },
                    { "path": pb, "edits": [{ "anchor": lvz_context::anchor::anchor_of("beta"), "op": "replace", "text": "BETA" }] }
                ]
            }))
            .await
            .unwrap();
        assert!(!out.is_error, "{}", out.content);
        assert!(out.content.contains("applied 2 file(s), 0 failed"));
        assert_eq!(
            tokio::fs::read_to_string(&a).await.unwrap(),
            "ALPHA\nkeep\n"
        );
        assert_eq!(tokio::fs::read_to_string(&b).await.unwrap(), "BETA\nkeep\n");
        let _ = tokio::fs::remove_dir_all(&dir).await;
    }

    #[tokio::test]
    async fn edit_files_reports_one_bad_file_inline_and_still_applies_the_rest() {
        let dir =
            std::env::temp_dir().join(format!("lvz_ctx_editfiles_mix_{}", std::process::id()));
        let _ = tokio::fs::create_dir_all(&dir).await;
        let a = dir.join("a.txt");
        let (pa, pb) = (
            a.to_string_lossy().to_string(),
            "/nonexistent/lvz/missing.txt",
        );
        tokio::fs::write(&a, "one\ntwo\n").await.unwrap();

        let out = EditFilesTool
            .invoke(json!({
                "files": [
                    { "path": pa, "edits": [{ "anchor": lvz_context::anchor::anchor_of("one"), "op": "replace", "text": "ONE" }] },
                    { "path": pb, "edits": [{ "anchor": "deadbeef", "op": "delete" }] }
                ]
            }))
            .await
            .unwrap();
        // One succeeded, one failed → batch is flagged as error but the good file is written.
        assert!(out.is_error);
        assert!(
            out.content.contains("applied 1 file(s), 1 failed"),
            "{}",
            out.content
        );
        assert!(out.content.contains("[error:"));
        assert_eq!(tokio::fs::read_to_string(&a).await.unwrap(), "ONE\ntwo\n");
        let _ = tokio::fs::remove_dir_all(&dir).await;
    }

    #[tokio::test]
    async fn edit_anchored_missing_anchor_is_soft_error_and_no_write() {
        let dir = std::env::temp_dir().join(format!("lvz_ctx_miss_{}", std::process::id()));
        let _ = tokio::fs::create_dir_all(&dir).await;
        let path = dir.join("h.txt");
        let p = path.to_string_lossy().to_string();
        tokio::fs::write(&path, "one\ntwo\n").await.unwrap();

        let out = EditAnchoredTool
            .invoke(json!({
                "path": p,
                "edits": [{ "anchor": "deadbeef", "op": "delete" }]
            }))
            .await
            .unwrap();
        assert!(out.is_error);
        // File is untouched.
        assert_eq!(
            tokio::fs::read_to_string(&path).await.unwrap(),
            "one\ntwo\n"
        );
        let _ = tokio::fs::remove_dir_all(&dir).await;
    }

    #[tokio::test]
    async fn str_replace_unique_match_edits_and_reports_changed() {
        let dir = std::env::temp_dir().join(format!("lvz_sr_uniq_{}", std::process::id()));
        let _ = tokio::fs::create_dir_all(&dir).await;
        let p = dir.join("f.rs").to_string_lossy().to_string();
        tokio::fs::write(&p, "fn a() {}\nfn b() {}\n")
            .await
            .unwrap();
        let out = StrReplaceTool
            .invoke(json!({ "path": p, "old": "fn b()", "new": "fn c()" }))
            .await
            .unwrap();
        assert!(!out.is_error && out.changed, "{}", out.content);
        assert_eq!(
            tokio::fs::read_to_string(&p).await.unwrap(),
            "fn a() {}\nfn c() {}\n"
        );
        let _ = tokio::fs::remove_dir_all(&dir).await;
    }

    #[tokio::test]
    async fn str_replace_non_unique_is_an_error_and_no_write() {
        // Accuracy first: an ambiguous match must NOT edit (it could change the wrong site).
        let dir = std::env::temp_dir().join(format!("lvz_sr_amb_{}", std::process::id()));
        let _ = tokio::fs::create_dir_all(&dir).await;
        let p = dir.join("f.py").to_string_lossy().to_string();
        tokio::fs::write(&p, "x = 1\nx = 1\n").await.unwrap();
        let out = StrReplaceTool
            .invoke(json!({ "path": p, "old": "x = 1", "new": "x = 2" }))
            .await
            .unwrap();
        assert!(out.is_error && !out.changed);
        assert!(out.content.contains("occurs 2"));
        assert_eq!(
            tokio::fs::read_to_string(&p).await.unwrap(),
            "x = 1\nx = 1\n"
        ); // untouched
        let _ = tokio::fs::remove_dir_all(&dir).await;
    }

    #[tokio::test]
    async fn str_replace_not_found_is_an_error() {
        let dir = std::env::temp_dir().join(format!("lvz_sr_nf_{}", std::process::id()));
        let _ = tokio::fs::create_dir_all(&dir).await;
        let p = dir.join("f.txt").to_string_lossy().to_string();
        tokio::fs::write(&p, "hello\n").await.unwrap();
        let out = StrReplaceTool
            .invoke(json!({ "path": p, "old": "absent", "new": "x" }))
            .await
            .unwrap();
        assert!(out.is_error && !out.changed);
        assert!(out.content.contains("not found"));
        let _ = tokio::fs::remove_dir_all(&dir).await;
    }

    #[tokio::test]
    async fn str_replace_all_across_paths_renames_in_one_call() {
        // The repeated-symbol rename the hash-anchored tools can't do: one call, every file.
        let dir = std::env::temp_dir().join(format!("lvz_sr_all_{}", std::process::id()));
        let _ = tokio::fs::create_dir_all(&dir).await;
        let a = dir.join("a.py").to_string_lossy().to_string();
        let b = dir.join("b.py").to_string_lossy().to_string();
        tokio::fs::write(&a, "def old(): pass\nold()\nold()\n")
            .await
            .unwrap();
        tokio::fs::write(&b, "old()\n").await.unwrap();
        let out = StrReplaceTool
            .invoke(json!({ "paths": [a.clone(), b.clone()], "old": "old", "new": "new", "replace_all": true }))
            .await
            .unwrap();
        assert!(!out.is_error && out.changed, "{}", out.content);
        assert!(!tokio::fs::read_to_string(&a).await.unwrap().contains("old"));
        assert_eq!(tokio::fs::read_to_string(&b).await.unwrap(), "new()\n");
        let _ = tokio::fs::remove_dir_all(&dir).await;
    }
}
