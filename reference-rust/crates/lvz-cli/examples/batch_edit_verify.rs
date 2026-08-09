//! Live verification of the `batch_edit` fan-out tool against a real batch API.
//!
//! Gated on `ANTHROPIC_API_KEY` (skips cleanly when unset, so `cargo test`/CI never runs it).
//! Creates a few temp files, then invokes `batch_edit` with one INDEPENDENT mechanical instruction
//! per file, going through the real Anthropic Message Batches API (`run_batch`, ~50% pricing) and
//! writing the results back. Confirms the read -> batch -> write path end-to-end and that the edits
//! actually landed.
//!
//! Run: `ANTHROPIC_API_KEY=… cargo run -p lvz-cli --example batch_edit_verify`

use std::sync::Arc;

use lvz_anthropic::AnthropicProvider;
use lvz_protocol::{BatchProvider, Tool};
use lvz_tools::BatchEditTool;
use serde_json::json;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    if std::env::var("ANTHROPIC_API_KEY").is_err() {
        eprintln!("ANTHROPIC_API_KEY unset — skipping live batch_edit verification.");
        return Ok(());
    }

    // Temp workspace with three files, each needing the same kind of self-contained mechanical edit.
    let dir = std::env::temp_dir().join(format!("lvz-batch-edit-live-{}", std::process::id()));
    std::fs::create_dir_all(&dir)?;
    let files = [
        ("greet.py", "def greet():\n    print(\"hi\")\n"),
        ("bye.py", "def bye():\n    print(\"bye\")\n"),
        ("ping.py", "def ping():\n    print(\"ping\")\n"),
    ];
    for (name, body) in files {
        std::fs::write(dir.join(name), body)?;
    }

    // The same instance is both the streaming Provider and the BatchProvider (as in the CLI).
    let provider: Arc<dyn BatchProvider> = Arc::new(AnthropicProvider::from_env()?);
    let tool = BatchEditTool::new(provider, "claude-haiku-4-5");

    let edits: Vec<_> = files
        .iter()
        .map(|(name, _)| {
            json!({
                "path": dir.join(name).to_str().unwrap(),
                "instruction": "Add a one-line module docstring at the very top of the file describing what the function does. Change nothing else."
            })
        })
        .collect();

    println!(
        "Submitting {} independent edits as one batch (Anthropic, ~50% pricing)…",
        edits.len()
    );
    let out = tool.invoke(json!({ "edits": edits })).await?;
    println!("\n--- tool result ---\n{}", out.content);
    if out.is_error {
        return Err("batch_edit reported an error".into());
    }

    // Show the results and assert the docstring landed in each file.
    let mut all_ok = true;
    for (name, original) in files {
        let now = std::fs::read_to_string(dir.join(name))?;
        let changed = now != original;
        let has_docstring = now.trim_start().starts_with("\"\"\"") || now.contains("\"\"\"");
        println!("\n===== {name} (changed={changed}) =====\n{now}");
        all_ok &= changed && has_docstring;
    }

    std::fs::remove_dir_all(&dir).ok();
    if all_ok {
        println!("\nbatch_edit LIVE OK — all files edited via the real batch API.");
        Ok(())
    } else {
        Err("at least one file was not edited as expected".into())
    }
}
