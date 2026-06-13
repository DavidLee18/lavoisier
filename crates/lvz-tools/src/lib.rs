//! Tool registry and built-in tools for the Lavoisier agent (`RECIPE.md` §4).
//!
//! The [`Tool`] trait itself lives in `lvz-protocol`; this crate provides the dispatch
//! [`ToolRegistry`] and the built-ins the agent uses to act on a repo: filesystem reads,
//! writes, directory listing, and a shell. Each built-in is just another `Tool`, so adding
//! capabilities (web search, memory, …) means registering more — nothing in the agent
//! changes.

mod builtins;
mod context;
mod search;

use std::sync::Arc;

use lvz_protocol::{Tool, ToolDef, ToolError, ToolOutput};

pub use builtins::{ListDirTool, ReadFileTool, ReadFilesTool, ShellTool, WriteFileTool};
pub use context::{
    EditAnchoredTool, EditFilesTool, OutlineFileTool, OutlineFilesTool, ReadAnchoredTool,
};
pub use search::FindReferencesTool;

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
        registry.register(Arc::new(ReadFilesTool));
        registry.register(Arc::new(WriteFileTool));
        registry.register(Arc::new(ListDirTool));
        registry.register(Arc::new(ShellTool));
        // Context engine (lvz-context): cheaper structural reads and anchored edits.
        registry.register(Arc::new(OutlineFileTool));
        registry.register(Arc::new(OutlineFilesTool));
        registry.register(Arc::new(ReadAnchoredTool));
        registry.register(Arc::new(EditAnchoredTool));
        registry.register(Arc::new(EditFilesTool));
        // Repo-wide reference search — the structured replacement for ad-hoc `grep -r`.
        registry.register(Arc::new(FindReferencesTool));
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
                strict: false,
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
            "read_files",
            "write_file",
            "list_dir",
            "shell",
            "outline_file",
            "outline_files",
            "read_anchored",
            "edit_anchored",
            "edit_files",
            "find_references",
        ] {
            assert!(names.contains(&expected), "missing tool: {expected}");
        }
        assert_eq!(defs.len(), 11);
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

    #[tokio::test]
    async fn read_files_batches_with_headers_and_inlines_errors() {
        let dir = std::env::temp_dir().join(format!("lvz-tools-batch-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let a = dir.join("a.txt");
        let b = dir.join("b.txt");
        std::fs::write(&a, "alpha").unwrap();
        std::fs::write(&b, "beta").unwrap();
        let missing = dir.join("missing.txt");

        let registry = ToolRegistry::with_builtins();
        let out = registry
            .invoke(
                "read_files",
                serde_json::json!({ "paths": [a.to_str().unwrap(), missing.to_str().unwrap(), b.to_str().unwrap()] }),
            )
            .await
            .unwrap();
        assert!(!out.is_error);
        // Both files present under headers, in order; the missing one is an inline error.
        assert!(out.content.contains("===== "));
        assert!(out.content.contains("alpha"));
        assert!(out.content.contains("beta"));
        assert!(out.content.contains("[error:"));
        let alpha_at = out.content.find("alpha").unwrap();
        let beta_at = out.content.find("beta").unwrap();
        assert!(alpha_at < beta_at, "sections preserve input order");

        std::fs::remove_dir_all(&dir).ok();
    }

    #[tokio::test]
    async fn outline_files_skeletonises_each_file() {
        let dir = std::env::temp_dir().join(format!("lvz-tools-outline-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let f = dir.join("m.rs");
        std::fs::write(&f, "fn keep_sig() -> u32 { let x = 41; x + 1 }\n").unwrap();

        let registry = ToolRegistry::with_builtins();
        let out = registry
            .invoke(
                "outline_files",
                serde_json::json!({ "paths": [f.to_str().unwrap()] }),
            )
            .await
            .unwrap();
        // Signature kept, body elided. (Check a body token that can't appear in the path header,
        // not a bare "41" — the temp dir embeds the PID, which may itself contain "41".)
        assert!(out.content.contains("fn keep_sig"));
        assert!(!out.content.contains("let x = 41"));
        assert!(out.content.contains("===== "));

        std::fs::remove_dir_all(&dir).ok();
    }
}
