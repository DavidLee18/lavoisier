//! The stock `lav` binary: the full Lavoisier CLI with no extra tools.
//!
//! A private downstream binary that wants its own tools depends on this crate as a library and
//! calls [`lavoisier::main_with`] with its own `Vec<Arc<dyn Tool>>` instead — see the crate docs
//! and `examples/private-tools/`.

fn main() -> std::process::ExitCode {
    lavoisier::main_with(Vec::new())
}
