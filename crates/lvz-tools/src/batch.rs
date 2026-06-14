//! `batch_edit` — fan out a set of **independent, mechanical** per-file edits to a provider's
//! discounted asynchronous **batch** API (~50% token cost) instead of editing them one-by-one in
//! the interactive loop.
//!
//! The interactive agent loop can't be batched — each edit turn depends on seeing the previous
//! tool result. But a *bulk-mechanical* task ("apply the same change to every file in this dir",
//! "rename this symbol across these modules") decomposes into many edits where **no edit depends on
//! another's outcome**. That fan-out is a perfect batch fit: each file becomes one single-shot
//! request, they all run in one async batch job, and the results are written back. The model owns
//! the decomposition (it knows which edits are independent); this tool owns the batch lifecycle.
//!
//! Requires a [`BatchProvider`] (Anthropic / Google). Providers without a batch API (xAI) don't get
//! the tool registered, so it is never advertised when it can't run.

use std::sync::Arc;

use async_trait::async_trait;
use lvz_protocol::{
    BatchProvider, BatchTask, ChatRequest, Message, Tool, ToolError, ToolOutput, Usage,
};
use serde::Deserialize;
use serde_json::{json, Value};

/// Default token ceiling per batched edit — generous, because each request returns the **complete**
/// rewritten file (full-file rewrite is the robust MVP; a diff/search-replace form is a later
/// refinement). Batch output is billed at the ~50% discount, so a roomy cap is cheap.
const DEFAULT_MAX_TOKENS: u32 = 8192;

/// System prompt for each single-shot editor request. Kept terse and identical across every task in
/// a batch so the cacheable prefix is stable.
const EDITOR_SYSTEM: &str = "You are a precise code editor. You are given one file and one \
instruction. Apply the instruction to the file and return the COMPLETE updated file contents and \
nothing else — no explanations, no markdown code fences, no commentary. If the instruction does not \
apply to this file, return the file unchanged.";

/// `batch_edit` — run many independent mechanical edits as one discounted batch job.
pub struct BatchEditTool {
    batch: Arc<dyn BatchProvider>,
    model: String,
    max_tokens: u32,
}

impl BatchEditTool {
    /// Build the tool over a batch-capable provider and the editor model id (typically the agent's
    /// main model).
    pub fn new(batch: Arc<dyn BatchProvider>, model: impl Into<String>) -> Self {
        Self {
            batch,
            model: model.into(),
            max_tokens: DEFAULT_MAX_TOKENS,
        }
    }

    /// Override the per-edit token ceiling (default [`DEFAULT_MAX_TOKENS`]).
    pub fn with_max_tokens(mut self, n: u32) -> Self {
        self.max_tokens = n;
        self
    }
}

#[derive(Deserialize)]
struct BatchEditArgs {
    edits: Vec<EditSpec>,
    /// Optional model override for the editor requests (defaults to the tool's configured model).
    #[serde(default)]
    model: Option<String>,
}

#[derive(Deserialize)]
struct EditSpec {
    path: String,
    instruction: String,
}

#[async_trait]
impl Tool for BatchEditTool {
    fn name(&self) -> &str {
        "batch_edit"
    }

    fn description(&self) -> &str {
        "Apply many INDEPENDENT, mechanical per-file edits in one discounted asynchronous batch \
job (~50% of the normal token cost). Use this — not repeated edit_anchored/write_file calls — \
when a task fans out into the same kind of self-contained change across many files (e.g. rename a \
symbol across modules, apply one migration to each file, add the same boilerplate everywhere) and \
no edit depends on another edit's result. Each `instruction` must be fully self-contained: it is \
sent with only its own file, with no shared conversation context. DO NOT use this for exploratory \
work, for edits that depend on each other's outcome, or for a single file (just edit it directly). \
Trades latency (the batch runs asynchronously) for the lower price, so prefer it only when there \
are several independent edits."
    }

    fn schema(&self) -> Value {
        json!({
            "type": "object",
            "properties": {
                "edits": {
                    "type": "array",
                    "description": "The independent per-file edits to run as one batch.",
                    "items": {
                        "type": "object",
                        "properties": {
                            "path": { "type": "string", "description": "File to edit." },
                            "instruction": {
                                "type": "string",
                                "description": "Self-contained change to apply to this file (sent with only this file, no shared context)."
                            }
                        },
                        "required": ["path", "instruction"]
                    }
                },
                "model": {
                    "type": "string",
                    "description": "Optional model id for the editor requests (defaults to the agent model)."
                }
            },
            "required": ["edits"]
        })
    }

    async fn invoke(&self, args: Value) -> Result<ToolOutput, ToolError> {
        let BatchEditArgs { edits, model } =
            serde_json::from_value(args).map_err(|e| ToolError::InvalidArgs(e.to_string()))?;
        if edits.is_empty() {
            return Ok(ToolOutput::error("batch_edit: `edits` is empty"));
        }
        let model = model.unwrap_or_else(|| self.model.clone());

        // Read every target up front. Unreadable files never enter the batch — they are reported
        // back so the model can react, while the readable ones still run.
        let mut tasks: Vec<BatchTask> = Vec::new();
        let mut originals: Vec<(String, String)> = Vec::new(); // (path, original content)
        let mut prefailed: Vec<String> = Vec::new();
        for (i, EditSpec { path, instruction }) in edits.into_iter().enumerate() {
            match tokio::fs::read_to_string(&path).await {
                Ok(content) => {
                    let req = ChatRequest::new(&model)
                        .max_tokens(self.max_tokens)
                        .system(EDITOR_SYSTEM)
                        .push(Message::user(editor_user_prompt(
                            &path,
                            &content,
                            &instruction,
                        )));
                    tasks.push(BatchTask::new(i.to_string(), req));
                    originals.push((path, content));
                }
                Err(e) => prefailed.push(format!("{path}: could not read ({e})")),
            }
        }

        if tasks.is_empty() {
            return Ok(ToolOutput::error(format!(
                "batch_edit: no readable files to edit:\n{}",
                prefailed.join("\n")
            )));
        }

        // The whole create -> poll -> fetch lifecycle is behind run_batch. A transport/API failure
        // here aborts the tool (no edits were applied yet).
        let items = self
            .batch
            .run_batch(tasks)
            .await
            .map_err(|e| ToolError::Execution(format!("batch_edit: batch run failed: {e}")))?;

        // Correlate results back to files by the index custom_id (order is not guaranteed).
        let mut by_id: std::collections::HashMap<String, lvz_protocol::BatchItem> = items
            .into_iter()
            .map(|it| (it.custom_id.clone(), it))
            .collect();

        let mut applied = 0usize;
        let mut lines: Vec<String> = Vec::new();
        let mut total = Usage::default();
        for (i, (path, original)) in originals.iter().enumerate() {
            match by_id.remove(&i.to_string()) {
                Some(item) => {
                    accumulate(&mut total, &item.usage);
                    if let Some(err) = item.error {
                        lines.push(format!("{path}: batch error ({err})"));
                        continue;
                    }
                    let new_content = strip_code_fence(&item.text);
                    if new_content.trim().is_empty() {
                        lines.push(format!("{path}: skipped (model returned empty output)"));
                        continue;
                    }
                    if new_content == *original {
                        lines.push(format!("{path}: unchanged"));
                        continue;
                    }
                    match tokio::fs::write(path, &new_content).await {
                        Ok(()) => {
                            applied += 1;
                            lines.push(format!(
                                "{path}: edited ({} -> {} bytes)",
                                original.len(),
                                new_content.len()
                            ));
                        }
                        Err(e) => lines.push(format!("{path}: write failed ({e})")),
                    }
                }
                None => lines.push(format!("{path}: no result returned for this file")),
            }
        }
        for f in &prefailed {
            lines.push(f.clone());
        }

        let summary = format!(
            "batch_edit: applied {applied}/{} edits via discounted batch (~50% token cost; tokens: \
in={} out={}).\n{}",
            originals.len(),
            total.input_tokens,
            total.output_tokens,
            lines.join("\n")
        );
        Ok(ToolOutput::ok(summary))
    }
}

/// The per-file user prompt: the file, then the instruction. Path is included for the model's
/// orientation only — the edit is applied to the content shown.
fn editor_user_prompt(path: &str, content: &str, instruction: &str) -> String {
    format!("File `{path}`:\n```\n{content}\n```\n\nApply this change to the file above:\n{instruction}")
}

/// Defensively unwrap a single fenced block if the model wrapped the whole file in ``` despite the
/// instruction. Only strips when the *entire* response is one fence; otherwise returns the text
/// unchanged. Preserves a trailing newline on the inner content.
fn strip_code_fence(text: &str) -> String {
    let trimmed = text.trim();
    if !trimmed.starts_with("```") {
        return text.to_string();
    }
    let Some(first_nl) = trimmed.find('\n') else {
        return text.to_string();
    };
    let after_open = &trimmed[first_nl + 1..];
    let Some(close) = after_open.rfind("```") else {
        return text.to_string();
    };
    after_open[..close].trim_end_matches('\n').to_string() + "\n"
}

fn accumulate(total: &mut Usage, u: &Usage) {
    total.input_tokens += u.input_tokens;
    total.output_tokens += u.output_tokens;
    total.cache_read_tokens += u.cache_read_tokens;
    total.cache_creation_tokens += u.cache_creation_tokens;
}

#[cfg(test)]
mod tests {
    use super::*;
    use lvz_protocol::{BatchItem, ProviderError};

    /// A stand-in batch provider: returns each request's text uppercased (a deterministic, visible
    /// "edit") so the tool's read -> batch -> write path can be exercised without a network call.
    struct UppercasingBatch;

    #[async_trait]
    impl BatchProvider for UppercasingBatch {
        async fn run_batch(&self, tasks: Vec<BatchTask>) -> Result<Vec<BatchItem>, ProviderError> {
            Ok(tasks
                .into_iter()
                .map(|t| {
                    // Echo the original file content (embedded in the user prompt) uppercased.
                    let user = t.request.messages[0].text();
                    let body = user
                        .split("```\n")
                        .nth(1)
                        .and_then(|s| s.split("\n```").next())
                        .unwrap_or_default()
                        .to_uppercase();
                    BatchItem {
                        custom_id: t.custom_id,
                        text: body,
                        usage: Usage {
                            output_tokens: 3,
                            ..Default::default()
                        },
                        error: None,
                    }
                })
                .collect())
        }
    }

    fn tmp() -> std::path::PathBuf {
        let d = std::env::temp_dir().join(format!(
            "lvz-batch-edit-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    #[tokio::test]
    async fn applies_independent_edits_and_reports_each() {
        let dir = tmp();
        let a = dir.join("a.txt");
        let b = dir.join("b.txt");
        std::fs::write(&a, "alpha").unwrap();
        std::fs::write(&b, "beta").unwrap();

        let tool = BatchEditTool::new(Arc::new(UppercasingBatch), "test-model");
        let out = tool
            .invoke(json!({
                "edits": [
                    { "path": a.to_str().unwrap(), "instruction": "uppercase it" },
                    { "path": b.to_str().unwrap(), "instruction": "uppercase it" }
                ]
            }))
            .await
            .unwrap();

        assert!(!out.is_error, "{}", out.content);
        assert!(out.content.contains("applied 2/2"));
        assert_eq!(std::fs::read_to_string(&a).unwrap(), "ALPHA\n");
        assert_eq!(std::fs::read_to_string(&b).unwrap(), "BETA\n");
        std::fs::remove_dir_all(&dir).ok();
    }

    #[tokio::test]
    async fn unreadable_files_are_reported_not_fatal() {
        let dir = tmp();
        let a = dir.join("a.txt");
        std::fs::write(&a, "alpha").unwrap();
        let missing = dir.join("nope.txt");

        let tool = BatchEditTool::new(Arc::new(UppercasingBatch), "test-model");
        let out = tool
            .invoke(json!({
                "edits": [
                    { "path": a.to_str().unwrap(), "instruction": "x" },
                    { "path": missing.to_str().unwrap(), "instruction": "x" }
                ]
            }))
            .await
            .unwrap();

        assert!(!out.is_error);
        assert!(out.content.contains("applied 1/1")); // one readable file batched + applied
        assert!(out.content.contains("could not read"));
        assert_eq!(std::fs::read_to_string(&a).unwrap(), "ALPHA\n");
        std::fs::remove_dir_all(&dir).ok();
    }

    #[tokio::test]
    async fn empty_edits_is_a_model_visible_error() {
        let tool = BatchEditTool::new(Arc::new(UppercasingBatch), "test-model");
        let out = tool.invoke(json!({ "edits": [] })).await.unwrap();
        assert!(out.is_error);
    }

    #[test]
    fn strip_code_fence_unwraps_only_whole_fenced_blocks() {
        assert_eq!(strip_code_fence("```rust\nlet x = 1;\n```"), "let x = 1;\n");
        assert_eq!(strip_code_fence("```\nplain\n```\n"), "plain\n");
        // Not a whole-block fence — left untouched.
        assert_eq!(strip_code_fence("no fences here"), "no fences here");
    }
}
