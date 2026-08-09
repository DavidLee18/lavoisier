//! Your private tools. Implement [`lavoisier::Tool`] and they're registered alongside the
//! built-ins. This example reverses a string; replace it with your own (DB queries, deploys, …).

use async_trait::async_trait;
use lavoisier::{Tool, ToolError, ToolOutput};
use serde_json::{json, Value};

/// A trivial example tool. The model calls it by `name` with arguments matching `schema`.
pub struct ReverseTool;

#[async_trait]
impl Tool for ReverseTool {
    fn name(&self) -> &str {
        "reverse"
    }

    fn description(&self) -> &str {
        "Reverse the characters of a string."
    }

    fn schema(&self) -> Value {
        json!({
            "type": "object",
            "properties": { "text": { "type": "string", "description": "the text to reverse" } },
            "required": ["text"]
        })
    }

    async fn invoke(&self, args: Value) -> Result<ToolOutput, ToolError> {
        let text = args["text"]
            .as_str()
            .ok_or_else(|| ToolError::InvalidArgs("`text` must be a string".into()))?;
        // Read-only, so leave `changed` false. Set `.changed(true)` if a tool mutates the workspace.
        Ok(ToolOutput::ok(text.chars().rev().collect::<String>()))
    }
}
