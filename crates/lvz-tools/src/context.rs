//! Token-efficient context tools built on `lvz-context` (`RECIPE.md` §6.1): read a file's
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

/// `outline_files` — skeletons of several files in one round-trip (`RECIPE.md` §6.1 batching).
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
        Ok(ToolOutput::ok(format!(
            "applied {} edit(s) to {path}\n{diff}",
            edits.len()
        )))
    }
}

/// Apply anchored edits to one file (read → apply → write), returning a one-line summary + diff on
/// success, or an error string on failure. The whole-file apply is atomic: if any anchor is missing
/// or ambiguous, nothing is written. Shared by the `edit_files` batch tool.
async fn apply_anchored_to_file(path: &str, specs: Vec<EditSpec>) -> Result<String, String> {
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
    Ok(format!("applied {} edit(s) to {path}\n{diff}", edits.len()))
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
        for FileEdits { path, edits } in files {
            let body = match apply_anchored_to_file(&path, edits).await {
                Ok(summary) => {
                    applied += 1;
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
        // Surface a batch with any failure as an error so the model retries just those files.
        Ok(ToolOutput {
            content,
            is_error: failed > 0,
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
}
