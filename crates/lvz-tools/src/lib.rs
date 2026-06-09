//! Tool registry and built-in tools for the Lavoisier agent (`RECIPE.md` §4).
//!
//! The [`Tool`] trait itself lives in `lvz-protocol`; this crate provides the dispatch
//! [`ToolRegistry`] and the built-ins the agent uses to act on a repo: filesystem reads,
//! writes, directory listing, and a shell. Each built-in is just another `Tool`, so adding
//! capabilities (web search, memory, …) means registering more — nothing in the agent
//! changes.

mod builtins;
mod context;

use std::sync::Arc;

use lvz_protocol::{Tool, ToolDef, ToolError, ToolOutput};

pub use builtins::{ListDirTool, ReadFileTool, ShellTool, WriteFileTool};
pub use context::{EditAnchoredTool, OutlineFileTool, ReadAnchoredTool};

/// A name-indexed set of tools. Exposes [`ToolDef`]s for the model and dispatches calls by
/// name. Cheap to clone (it is a vector of `Arc`s), so the agent can hand a copy to a
/// spawned turn loop.
#[derive(Clone, Default)]
pub struct ToolRegistry {
    tools: Vec<Arc<dyn Tool>>,
}

impl ToolRegistry {
    /// An empty registry.
    pub fn new() -> Self {
        Self::default()
    }

    /// A registry preloaded with the filesystem + shell + token-efficient context built-ins.
    pub fn with_builtins() -> Self {
        let mut registry = Self::new();
        registry.register(Arc::new(ReadFileTool));
        registry.register(Arc::new(WriteFileTool));
        registry.register(Arc::new(ListDirTool));
        registry.register(Arc::new(ShellTool));
        // Context engine (lvz-context): cheaper structural reads and anchored edits.
        registry.register(Arc::new(OutlineFileTool));
        registry.register(Arc::new(ReadAnchoredTool));
        registry.register(Arc::new(EditAnchoredTool));
        registry
    }

    /// Add a tool. A later registration under an existing name shadows the earlier one.
    pub fn register(&mut self, tool: Arc<dyn Tool>) {
        self.tools.push(tool);
    }

    /// True when no tools are registered.
    pub fn is_empty(&self) -> bool {
        self.tools.is_empty()
    }

    /// The tool definitions to advertise to the model, in registration order.
    pub fn defs(&self) -> Vec<ToolDef> {
        self.tools
            .iter()
            .map(|t| ToolDef {
                name: t.name().to_string(),
                description: t.description().to_string(),
                schema: t.schema(),
                cache: false,
            })
            .collect()
    }

    /// Dispatch a call to the named tool. Last registration wins on duplicate names.
    pub async fn invoke(
        &self,
        name: &str,
        args: serde_json::Value,
    ) -> Result<ToolOutput, ToolError> {
        let tool = self
            .tools
            .iter()
            .rev()
            .find(|t| t.name() == name)
            .ok_or_else(|| ToolError::Unknown(name.to_string()))?;
        tool.invoke(args).await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn builtins_registry_exposes_all_named_defs() {
        let defs = ToolRegistry::with_builtins().defs();
        let names: Vec<&str> = defs.iter().map(|d| d.name.as_str()).collect();
        for expected in [
            "read_file",
            "write_file",
            "list_dir",
            "shell",
            "outline_file",
            "read_anchored",
            "edit_anchored",
        ] {
            assert!(names.contains(&expected), "missing tool: {expected}");
        }
        assert_eq!(defs.len(), 7);
    }

    #[tokio::test]
    async fn unknown_tool_is_an_error() {
        let registry = ToolRegistry::with_builtins();
        let err = registry
            .invoke("does_not_exist", serde_json::json!({}))
            .await
            .unwrap_err();
        assert!(matches!(err, ToolError::Unknown(_)));
    }
}
