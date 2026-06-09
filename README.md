# Lavoisier

A modular, **token-efficient** CLI coding agent in Rust with a provider-agnostic core
(Anthropic + xAI, native). Designed so the same agent brain can drive the CLI today and a
multi-gateway "Hermes" agent later.

> Status: early. Milestones **M0–M5** of the [build blueprint](RECIPE.md) are implemented and
> tested (provider streaming, the agent loop, fs/shell tools, and the token-efficiency
> engine). See [`RECIPE.md`](RECIPE.md) for the full design and milestone plan.

## Why

LLM coding workloads are I/O- and token-bound. Lavoisier treats **token efficiency as a
first-class design goal** at every layer — prompt caching on stable prefixes, tree-sitter
file skeletons (send signatures, elide bodies), hash-anchored edits and minimal diffs (don't
resend whole files), and a budget-fixture CI loop that gates skeleton-size regressions.

## Architecture

A Cargo workspace, trait-segmented so the agent core never depends on a wire protocol or a
frontend (the keystone is `lvz-protocol`; everything points inward to it).

| Crate | Role |
|---|---|
| `lvz-protocol` | Normalised contracts: `Event` stream, `Provider`, `Tool`, `Gateway`, `Tuner`. Zero provider/gateway deps. |
| `lvz-xai` | xAI provider (OpenAI-compat streaming + tool calling; gRPC path planned). |
| `lvz-anthropic` | Anthropic provider: native Messages API over SSE, prompt caching, extended thinking. |
| `lvz-context` | Token engine: tree-sitter skeletons, symbol-dependency graph (radius knob `N`), hash-anchored edits, diffs, budget-fixture loop. |
| `lvz-tools` | Tool registry + built-ins: `read_file`, `write_file`, `list_dir`, `shell`, `outline_file`, `read_anchored`, `edit_anchored`. |
| `lvz-agent` | The plan→act→observe loop: tool dispatch, capability-gated caching, per-task token budget. |
| `lvz-cli` | The `lavoisier` binary — the first gateway. |

## Quickstart

Requires a recent Rust toolchain (edition 2021, MSRV 1.82).

```sh
cargo build

# One streaming turn (no tools):
XAI_API_KEY=…       cargo run -p lvz-cli -- "explain a monad in one sentence"
ANTHROPIC_API_KEY=… cargo run -p lvz-cli -- --provider anthropic "…"

# The multi-step agent with filesystem + shell + context tools:
XAI_API_KEY=… cargo run -p lvz-cli -- --agent "add a doc comment to the add() function in src/lib.rs"
```

Useful flags: `--agent`, `--provider xai|anthropic`, `--model`, `--max-tokens`, `--budget`
(total-task token ceiling), `--system`. Env: `XAI_API_KEY`/`XAI_BASE_URL`,
`ANTHROPIC_API_KEY`/`ANTHROPIC_BASE_URL`, `LVZ_PROVIDER`, `LVZ_MODEL`.

## Development

```sh
cargo test                                            # all tests
cargo clippy --all-targets                            # lints (kept zero-warning)
cargo test -p lvz-context --test budget -- --nocapture   # token-budget trend line (§6.5)
```

## License

MIT — see [`LICENSE`](LICENSE).
