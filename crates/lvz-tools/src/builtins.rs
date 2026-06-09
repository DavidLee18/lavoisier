//! Built-in tools: `read_file`, `write_file`, `list_dir`, and `shell`.
//!
//! These act on the process's working directory. Blast-radius constraints (sandboxing,
//! path allow-lists) are a deliberately later concern (`RECIPE.md` §7.3); for now the tools
//! are thin wrappers over `tokio::fs` / `tokio::process` that report failures back to the
//! model as error results rather than aborting the turn.

use async_trait::async_trait;
use lvz_protocol::{Tool, ToolError, ToolOutput};
use serde::Deserialize;
use serde_json::{json, Value};

/// Parse a tool's argument object into a typed struct, mapping failure to [`ToolError::InvalidArgs`].
fn parse_args<T: for<'de> Deserialize<'de>>(args: Value) -> Result<T, ToolError> {
    serde_json::from_value(args).map_err(|e| ToolError::InvalidArgs(e.to_string()))
}

/// `read_file` — return the UTF-8 contents of a file.
pub struct ReadFileTool;

#[derive(Deserialize)]
struct ReadArgs {
    path: String,
}

#[async_trait]
impl Tool for ReadFileTool {
    fn name(&self) -> &str {
        "read_file"
    }

    fn description(&self) -> &str {
        "Read the UTF-8 contents of a file at the given path (relative to the working directory)."
    }

    fn schema(&self) -> Value {
        json!({
            "type": "object",
            "properties": { "path": { "type": "string", "description": "Path to the file" } },
            "required": ["path"]
        })
    }

    async fn invoke(&self, args: Value) -> Result<ToolOutput, ToolError> {
        let ReadArgs { path } = parse_args(args)?;
        match tokio::fs::read_to_string(&path).await {
            Ok(content) => Ok(ToolOutput::ok(content)),
            Err(e) => Ok(ToolOutput::error(format!("read_file {path}: {e}"))),
        }
    }
}

/// `write_file` — create or overwrite a file with the given contents.
pub struct WriteFileTool;

#[derive(Deserialize)]
struct WriteArgs {
    path: String,
    content: String,
}

#[async_trait]
impl Tool for WriteFileTool {
    fn name(&self) -> &str {
        "write_file"
    }

    fn description(&self) -> &str {
        "Create or overwrite a file at the given path with the provided UTF-8 content."
    }

    fn schema(&self) -> Value {
        json!({
            "type": "object",
            "properties": {
                "path": { "type": "string", "description": "Path to the file" },
                "content": { "type": "string", "description": "Full file contents to write" }
            },
            "required": ["path", "content"]
        })
    }

    async fn invoke(&self, args: Value) -> Result<ToolOutput, ToolError> {
        let WriteArgs { path, content } = parse_args(args)?;
        if let Some(parent) = std::path::Path::new(&path).parent() {
            if !parent.as_os_str().is_empty() {
                let _ = tokio::fs::create_dir_all(parent).await;
            }
        }
        let bytes = content.len();
        match tokio::fs::write(&path, content).await {
            Ok(()) => Ok(ToolOutput::ok(format!("wrote {bytes} bytes to {path}"))),
            Err(e) => Ok(ToolOutput::error(format!("write_file {path}: {e}"))),
        }
    }
}

/// `list_dir` — list the entries of a directory.
pub struct ListDirTool;

#[derive(Deserialize)]
struct ListArgs {
    #[serde(default = "dot")]
    path: String,
}

fn dot() -> String {
    ".".to_string()
}

#[async_trait]
impl Tool for ListDirTool {
    fn name(&self) -> &str {
        "list_dir"
    }

    fn description(&self) -> &str {
        "List the names of entries in a directory (defaults to the working directory). \
         Directory entries are suffixed with '/'."
    }

    fn schema(&self) -> Value {
        json!({
            "type": "object",
            "properties": { "path": { "type": "string", "description": "Directory path (default '.')" } }
        })
    }

    async fn invoke(&self, args: Value) -> Result<ToolOutput, ToolError> {
        let ListArgs { path } = parse_args(args)?;
        let mut entries = match tokio::fs::read_dir(&path).await {
            Ok(rd) => rd,
            Err(e) => return Ok(ToolOutput::error(format!("list_dir {path}: {e}"))),
        };
        let mut names = Vec::new();
        loop {
            match entries.next_entry().await {
                Ok(Some(entry)) => {
                    let name = entry.file_name().to_string_lossy().into_owned();
                    let is_dir = entry.file_type().await.map(|t| t.is_dir()).unwrap_or(false);
                    names.push(if is_dir { format!("{name}/") } else { name });
                }
                Ok(None) => break,
                Err(e) => return Ok(ToolOutput::error(format!("list_dir {path}: {e}"))),
            }
        }
        names.sort();
        Ok(ToolOutput::ok(names.join("\n")))
    }
}

/// `shell` — run a command line via `sh -c` and return combined output + exit status.
pub struct ShellTool;

#[derive(Deserialize)]
struct ShellArgs {
    command: String,
}

#[async_trait]
impl Tool for ShellTool {
    fn name(&self) -> &str {
        "shell"
    }

    fn description(&self) -> &str {
        "Run a shell command via `sh -c` in the working directory and return its stdout, \
         stderr, and exit code."
    }

    fn schema(&self) -> Value {
        json!({
            "type": "object",
            "properties": { "command": { "type": "string", "description": "Command line to execute" } },
            "required": ["command"]
        })
    }

    async fn invoke(&self, args: Value) -> Result<ToolOutput, ToolError> {
        let ShellArgs { command } = parse_args(args)?;
        let output = tokio::process::Command::new("sh")
            .arg("-c")
            .arg(&command)
            .output()
            .await
            .map_err(|e| ToolError::Execution(format!("spawning `{command}`: {e}")))?;

        let code = output.status.code().unwrap_or(-1);
        let stdout = String::from_utf8_lossy(&output.stdout);
        let stderr = String::from_utf8_lossy(&output.stderr);
        let rendered = format!("exit={code}\n--- stdout ---\n{stdout}\n--- stderr ---\n{stderr}");
        // A non-zero exit is reported as an error result so the model can react, but it is
        // not a hard ToolError — the tool itself ran fine.
        Ok(ToolOutput {
            content: rendered,
            is_error: !output.status.success(),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn read_missing_file_is_a_soft_error() {
        let out = ReadFileTool
            .invoke(json!({ "path": "/nonexistent/lvz/xyz" }))
            .await
            .unwrap();
        assert!(out.is_error);
    }

    #[tokio::test]
    async fn write_then_read_round_trips() {
        let dir = std::env::temp_dir().join(format!("lvz_tools_{}", std::process::id()));
        let path = dir.join("hello.txt");
        let path_str = path.to_string_lossy().to_string();

        let w = WriteFileTool
            .invoke(json!({ "path": path_str, "content": "hi there" }))
            .await
            .unwrap();
        assert!(!w.is_error, "write failed: {}", w.content);

        let r = ReadFileTool
            .invoke(json!({ "path": path_str }))
            .await
            .unwrap();
        assert_eq!(r.content, "hi there");

        let _ = tokio::fs::remove_dir_all(&dir).await;
    }

    #[tokio::test]
    async fn shell_reports_exit_code_and_output() {
        let ok = ShellTool
            .invoke(json!({ "command": "echo lavoisier" }))
            .await
            .unwrap();
        assert!(!ok.is_error);
        assert!(ok.content.contains("lavoisier"));
        assert!(ok.content.contains("exit=0"));

        let bad = ShellTool
            .invoke(json!({ "command": "exit 3" }))
            .await
            .unwrap();
        assert!(bad.is_error);
        assert!(bad.content.contains("exit=3"));
    }

    #[tokio::test]
    async fn invalid_args_are_rejected() {
        let err = ReadFileTool.invoke(json!({})).await.unwrap_err();
        assert!(matches!(err, ToolError::InvalidArgs(_)));
    }
}
