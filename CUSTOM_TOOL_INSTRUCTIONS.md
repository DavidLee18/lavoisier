# Building private custom tools for Lavoisier

How to give the agent your own tools **without forking Lavoisier or putting your code in this
repo**. Your tools live in a separate, private crate that depends on the published `lavoisier`
crate and injects them at startup. Your binary then behaves exactly like `lav` — same flags,
config, and gateways (HTTP/Matrix/cron, E2EE, persona) — with your tools additionally available to
the agent.

> Tools are **compiled-in Rust** — there is no dynamic/plugin loading. "Private" means the Rust
> code stays in your own repo; it never touches the public `lavoisier` source.

A ready-to-copy version of everything below lives in this repo at
[`examples/private-tools/`](examples/private-tools).

---

## 1. Create the project

Make a **standalone crate in its own (private) git repo, outside the `lavoisier` checkout** — not a
member of this workspace, not a fork.

```sh
cd ~/source                 # anywhere EXCEPT inside ~/source/lavoisier
cargo new my-lav --bin      # package + binary "my-lav" (rename freely)
cd my-lav
git init                    # your own private repo
```

## 2. `Cargo.toml`

```toml
[package]
name = "my-lav"
version = "0.1.0"
edition = "2021"
publish = false             # private — never goes to crates.io

[dependencies]
lavoisier   = "0.4"         # the published engine
async-trait = "0.1"
serde_json  = "1"
# ...plus whatever your tools need (reqwest, sqlx, ...)
```

For opt-in Matrix end-to-end encryption, enable the feature (needs Rust ≥ 1.93):

```toml
lavoisier = { version = "0.4", features = ["e2ee"] }
```

## 3. `src/main.rs`

```rust
use std::sync::Arc;
mod tools;

fn main() -> std::process::ExitCode {
    lavoisier::main_with(vec![
        Arc::new(tools::QueryDb::new()),
        // Arc::new(tools::Deploy::new()), ...
    ])
}
```

- `main_with(extra_tools)` builds the tokio runtime, runs the full CLI, and returns an exit code.
- If you manage your own runtime, call `lavoisier::run_with(extra_tools).await` instead (async).

## 4. `src/tools.rs` — your tools

Implement `lavoisier::Tool` for each tool. They're registered alongside the built-ins
(`read_file`, `str_replace`, `shell`, …); the model picks them by `name` using `schema`.

```rust
use async_trait::async_trait;
use lavoisier::{Tool, ToolError, ToolOutput};   // re-exported — no lvz-protocol dependency needed
use serde_json::{json, Value};

pub struct QueryDb {
    // hold whatever state the tool needs: a DB pool, an HTTP client, config, ...
}

impl QueryDb {
    pub fn new() -> Self {
        Self { /* ... */ }
    }
}

#[async_trait]
impl Tool for QueryDb {
    /// Stable identifier the model calls. Must be unique across all tools.
    fn name(&self) -> &str {
        "query_db"
    }

    /// Shown to the model — be precise; this is how it learns when/how to call the tool.
    fn description(&self) -> &str {
        "Run a read-only SQL query against the prod replica and return the rows."
    }

    /// JSON Schema for the argument object the model must produce.
    fn schema(&self) -> Value {
        json!({
            "type": "object",
            "properties": {
                "sql": { "type": "string", "description": "a SELECT statement" }
            },
            "required": ["sql"]
        })
    }

    /// Execute against the parsed argument JSON.
    async fn invoke(&self, args: Value) -> Result<ToolOutput, ToolError> {
        let sql = args["sql"]
            .as_str()
            .ok_or_else(|| ToolError::InvalidArgs("`sql` must be a string".into()))?;

        // ... run the query ...
        let rows = 0;

        Ok(ToolOutput::ok(format!("{rows} rows")))
    }
}
```

### The `Tool` contract

| Method | Purpose |
| --- | --- |
| `name(&self) -> &str` | Unique id the model calls. |
| `description(&self) -> &str` | Human-readable; tells the model what it does (defaults to `""`). |
| `schema(&self) -> serde_json::Value` | JSON Schema of the argument object. |
| `async fn invoke(&self, args) -> Result<ToolOutput, ToolError>` | Run it. |

Return values:

- **`ToolOutput::ok(text)`** — success; `text` goes back to the model.
- **`.changed(true)`** — call this **only if the tool mutated the workspace** (wrote/edited a file).
  It feeds the agent's convergence/no-progress logic; leave it `false` for read-only tools.
  e.g. `Ok(ToolOutput::ok("wrote 3 files").changed(true))`.
- **`ToolOutput::error(msg)`** — a *recoverable* failure the model should see and can retry
  (bad input, command exited non-zero). The turn continues.
- **`Err(ToolError::InvalidArgs(..))` / `Err(ToolError::Execution(..))`** — a *hard* failure
  (couldn't run the tool at all).

## 5. Build, run, install

```sh
cargo run -- --help                                          # same flags as `lav`
ANTHROPIC_API_KEY=… cargo run -- --provider anthropic --agent "use query_db to count users"
cargo install --path .                                       # put `my-lav` on your PATH
my-lav --serve-matrix                                        # gateways/config/persona/cron all work
```

Your tools are available in every mode the agent runs in: `--agent`, `--serve` (HTTP), `--serve-matrix`, and `--cron`.

---

## Gotchas

- **`protoc` is required to build.** Your crate compiles `lavoisier` from source, which pulls in
  `lvz-xai` (vendored protobuf). Install it: `brew install protobuf` (macOS) /
  `apt-get install -y protobuf-compiler` (Debian). (This is why `cargo binstall lavoisier` — a
  prebuilt binary — needs no protoc, but a custom binary always builds from source.)
- **Keep the crate outside `~/source/lavoisier`.** If it sits inside that checkout it becomes part
  of this repo. It must be its own directory / repo with a `lavoisier = "0.4"` dependency.
- **Unique tool names.** A custom tool name must not collide with a built-in (`read_file`,
  `read_files`, `write_file`, `list_dir`, `shell`, `outline_file`, `outline_files`, `read_anchored`,
  `str_replace`, `edit_anchored`, `edit_files`, `find_references`, and `batch_edit` when enabled).
- **Schemas matter.** The model only calls a tool as well as its `schema` + `description` let it;
  be specific about required fields and types.
- **Set `.changed(true)` for mutating tools** so the agent's stop/progress logic stays accurate.
- **Pin the version** in `Cargo.toml` (`lavoisier = "0.4"`); bump it deliberately to pick up engine
  updates. Your `Cargo.lock` keeps builds reproducible.

## Updating

To pull in a newer engine, bump the dependency (e.g. `lavoisier = "0.5"`), `cargo update -p
lavoisier`, and rebuild. Your tools are unaffected unless the `Tool` trait changes (it's stable).
