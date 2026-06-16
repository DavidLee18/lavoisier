# lavoisier

A modular, **token-efficient** CLI coding agent in Rust, with a provider-agnostic core
(**Anthropic + xAI native, plus Google Gemini**).

Token efficiency is a first-class design goal: prompt caching on stable prefixes, a tree-sitter
context engine (file skeletons + an AST symbol-dependency graph driving how much context to send),
hash-anchored and exact-string edits, multi-file batching, history compaction, and an
adaptive-token-optimisation tuner. The same agent core runs the CLI and an HTTP/WebSocket or Matrix
gateway.

## Install

```sh
# Prebuilt binary (no Rust toolchain or protoc needed):
cargo binstall lavoisier

# From source (needs `protoc`, e.g. `brew install protobuf`):
cargo install lavoisier
```

## Use

```sh
XAI_API_KEY=…       lavoisier "explain a monad in one sentence"     # one streaming turn (xAI gRPC)
ANTHROPIC_API_KEY=… lavoisier --provider anthropic --agent "…"      # the tool-using agent loop
XAI_API_KEY=…       lavoisier --serve 127.0.0.1:8080                # HTTP/WebSocket gateway
```

**Two modes:** efficiency-first by default; opt into accuracy-mode with a real test gate
(`--verify-cmd <tests> --require-edit --verify-and-fix`) and the agent iterates until the tests pass.

Full flags, architecture, the measured head-to-head benchmark, and the tuner internals are in the
[repository](https://github.com/DavidLee18/lavoisier).

## License

MIT
