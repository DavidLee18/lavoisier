//! Template: a private binary that reuses the **entire** Lavoisier CLI (flags, config, gateways,
//! E2EE, persona, cron) but registers its own tools with the agent.
//!
//! To make this your own: copy this crate out of the repo into a private repo, swap the
//! `lavoisier` path dependency in `Cargo.toml` for `lavoisier = "0.4"`, and add your tools in
//! `tools.rs`. Your binary then behaves exactly like `lav` — same flags — with your tools
//! additionally available to the agent. None of this code needs to live in the public repo.

use std::sync::Arc;

mod tools;

fn main() -> std::process::ExitCode {
    lavoisier::main_with(vec![Arc::new(tools::ReverseTool)])
}
