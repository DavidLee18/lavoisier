# CLAUDE.md

**Lavoisier** (binary `lav`) is a token-efficient, provider-agnostic CLI coding agent. One agent core
drives the CLI and every gateway (HTTP/WS, Matrix, Slack, cron, A2A, ACP).

**This branch (`haskell-port`) is the Haskell port**: Cabal package at the repo root (`src/`, `app/`,
`test/`, `lavoisier.cabal`). `main` is the Rust implementation, at the root, and is the parity
reference — read it (`git show v0.15.0:crates/…`, `git log main`) when porting or when behaviour is
ambiguous. There is no in-tree Rust copy; the tags on `main` are the record.

Read before working in that area: [`ARCHITECTURE.md`](ARCHITECTURE.md) (crate/module map, dependency
invariants, design decisions) · [`ATO.md`](ATO.md) (the adaptive-token-optimisation tuner) ·
[`README.md`](README.md) (the full feature and flag surface) · [`bench/README.md`](bench/README.md)
(head-to-head vs. Dirac) · [`CUSTOM_TOOL_INSTRUCTIONS.md`](CUSTOM_TOOL_INSTRUCTIONS.md) (the
`mainWith` extension point) · [`PUBLISHING.md`](PUBLISHING.md) · [`infra/README.md`](infra/README.md).

## Architecture invariants (do not violate)

1. **The protocol layer is the keystone** — it defines the `Event` stream plus the
   `Provider`/`Tool`/`Gateway`/`Tuner`/`Deliberator`/`Capabilities` contracts and depends on no
   provider or gateway.
2. **Dependencies point inward only.** Each adapter is the *only* place its wire format maps to
   `Event`; gateways and providers never depend on each other.
3. **Abstract at the semantic layer.** gRPC vs. SSE vs. REST is contained behind `Event` +
   `Capabilities`. gRPC is never an architectural assumption — Anthropic has none.

In Haskell the "dyn trait" objects are **records of functions** (`Provider`, `Tool`, `Gateway`, …)
held as ordinary values; `EventStream` is a hand-rolled pull stream (`IO (Maybe (Either ...))`),
the `BoxStream` analogue. Plain `IO`, no effect framework.

## The central design lever

The optimisation metric is **cost-weighted total task tokens across all round-trips**
(input·1 + output·~5 + cache-write·1.25 + cache-read·0.1) — never per-call input. Both the `--budget`
ceiling and the ATO objective use it, so caching and output length actually register. Every
efficiency mechanism (prompt-cache breakpoints, repo skeletons, the symbol-graph radius knob,
batching, compaction, model routing) exists to serve that metric; the details are in `README.md` and
`ATO.md`. **Accuracy levers are opt-in** (`--require-edit`, `--verify-and-fix`) because the default
posture is efficiency-first.

## Conventions

- **Haskell**: GHC 9.10 / Cabal, `GHC2021`, `-Wall -Werror` kept clean, **ormolu** before every
  commit. Correctness via ADTs + exhaustive `case`. Tests are `tasty` — prefer QuickCheck properties.
- **Rust** (`main`): edition 2021, MSRV 1.88; `cargo clippy --all-targets` and `cargo fmt --check`
  kept green.
- **Config is Dhall** in the port (`lavoisier.dhall.example`), TOML in Rust. `--cron-file` and
  `--schedule-file` are Dhall record lists here, JSON/TOML there.
- Keep dependencies minimal: **no agent frameworks, no vendor SDKs** — hand-roll thin HTTP adapters
  so prompt caching and thinking blocks stay reachable. (The stale Rust `anthropic*`/`clust`/
  `misanthropy` crates are specifically not to be used.)
- **Providers in scope: Anthropic, xAI, Google Gemini — native.** OpenAI and others are out of scope.
  A **Discord gateway is out of scope** — do not build it.
- Scripts are **zsh**; local containers run on **colima + nerdctl** (not Docker, and no longer Podman).
- Secrets come from env / AWS Secrets Manager at runtime; never commit keys.
- **GitHub Actions are pinned to a full commit SHA**, never a tag (`uses: owner/repo@<sha> # vX.Y.Z`).
  Resolve with `gh api repos/<owner>/<repo>/commits/<tag> --jq .sha` and keep the version comment
  accurate. `dtolnay/rust-toolchain` additionally needs an explicit `toolchain:` input, since pinning
  discards the `@stable` ref-name signal.
- License MIT. Release tags: `hs-v*` for the Haskell binaries, `v*` for the Rust crates.

## Gotchas

**Haskell port**
- `runCli` forces UTF-8 on stdout/stderr. Without it the binary dies with `commitBuffer: invalid
  argument` under a C locale, because help text and notices contain ε and emoji.
- **Use a fresh `MATRIX_DEVICE_ID` for every live E2EE run.** Reusing one leaves stale one-time keys
  on the homeserver and peers fail with `BAD_MESSAGE_KEY_ID`. libolm exceptions are caught and
  converted to `Left` rather than escaping — keep it that way; an uncaught one kills the serve loop.
- **An Olm/Megolm decryption failure must never be discarded.** To-device events are consumed from
  `/sync` and never redelivered, so a swallowed failure loses a room key permanently and every later
  event from that peer is undecryptable — and `extractMessages` then drops it, which is a gateway that
  reads a room and answers nothing, silently. Since 0.13.4 both failures log at `warn` and drive
  recovery (`m.dummy` unwedge, `m.room_key_request`). The two are **not** interchangeable: repairing
  the Olm channel does not make a peer re-share the key for the session it believes it delivered.
  (Clients forward keys only to their *own* other devices, so the request is a bonus — the unwedge is
  what actually recovers a cross-user peer.)
- **The Matrix txn counter must be seeded from process-start nanos**, not 0 — Matrix dedupes by
  `(device, txn id)` and answers a repeat with the *previous* response, so a counter restarting at 0
  makes the first sends after every restart vanish silently. The Rust `process_seed` says so in a
  comment; the port had dropped it, and it swallowed room-key shares and the unwedge until 0.13.4.
- Dhall record fields become top-level selectors, so they collide with same-named function
  parameters and lambdas. Hence `jobId`/`toolArgs` rather than `id`/`args`.
- On Apple Silicon, `install_name_tool` invalidates the signature — re-sign ad hoc (`codesign -f -s -`)
  or the binary is killed on launch. `scripts/package-haskell.sh` does this.
- CI builds native deps from source (tree-sitter 0.26.12 for grammar ABI 15, libolm 3.2.16) and needs
  `protoc` at build time for `proto-lens-protobuf-types`. Clone libolm somewhere other than `./olm` —
  that path is the repo's own Haskell FFI package.
- Generated xAI proto-lens bindings are **committed** under `gen/` (isolated in the `xai-proto`
  library with warnings off), so an ordinary build needs no `protoc`.

**Both trees**
- Gemini 3 attaches a `thoughtSignature` to each `functionCall` that must be echoed on resend, or the
  API 400s. It round-trips through the opaque tool-call id, contained to the Google adapter.
- The tree-sitter grammar and core ABI versions are pinned together — bump them together.
- The budget-fixture ceilings (`tests/budget/ceilings.txt`, gated by its own `haskell-ci` step) are
  the committed context-token baseline, measured with no headroom. The fixtures are real snapshots
  (`tests/budget/<name>/TARGET` + `src/`), and their **paths are part of the measurement** — that is
  what the cross-file import ranking scores against. Update a number deliberately when skeleton
  output legitimately changes and say why in the commit; never edit one to make a test pass.

**Rust tree**
- `lvz-xai`'s tonic bindings are committed for the same protoc-free reason; `build.rs` regenerates
  only under `LVZ_XAI_REGEN=1`. Procedure in `crates/lvz-xai/proto/VENDOR.md`.
- Inside a `tracing` macro, fully qualify `serde_json::Value` — the expansion brings the
  `tracing::field::Value` *trait* into scope, so a bare `Value::as_str` path fails to compile with
  "expected a type, found a trait" even though the same expression compiles elsewhere in the file.
- `EnvFilter` has no glob, so `DEFAULT_LOG_FILTER` is an explicit per-crate roll-call. **A new crate
  must be added to it** or its `info!` events silently vanish. A unit test guards the list.

## Status and parity

The Rust implementation is complete and live-verified against real API keys across all providers and
gateways. The Haskell port covers the same surface — providers, context engine, ATO, tools, all
gateways including Matrix E2EE — and is live-verified on 7 surfaces (Slack is offline-tested only).

**Parity is against the deployed Rust v0.15.0.** The v0.13.1→v0.15.0 lineage — the atomic/corruption-
surfacing `FileStore`, the structural schedule report body, the `ToolGate` + per-turn model override,
the ACP rework (BeeAI REST → Zed stdio), and the inline TUI — is ported and offline-tested. The Rust
lineage was diffed straight from `main` in this repo, which carries every tag; `reference-rust/` was
only ever a v0.13.0 snapshot and has been removed. Read `git show v0.15.0:crates/…` (or any tag) when
behaviour is ambiguous.

The TUI is the one place the port deliberately diverges in **means**, not surface: the Rust builds on
ratatui's inline viewport, which has no Haskell equivalent (brick/vty are alt-screen shaped), so
`Lavoisier.Gateway.Tui` drives the terminal with ANSI escapes directly.

**The port is ahead of Rust in two places**, both former deferrals, both closed here only — port them
back before claiming parity in the other direction:
- **Repeated edit targets are addressable.** `edit_anchored`/`edit_files` take an `after` landmark
  anchor and `str_replace` takes `after`/`before` snippets; the landmark must itself occur exactly
  once and the first match past it is edited. Deliberately *not* a line range or an occurrence index
  — those fail silently against a shifted file, and the whole edit path's value is that it refuses
  rather than guesses.
- **Cross-file symbol edges are import-ranked.** `Symbols.fromFiles` scores candidate definers of a
  name by how much of their path the referencing file's imports mention, keeping only the best tier.
  It ranks, it does not resolve: with no evidence it degrades to linking every definer (exactly the
  old behaviour), because a wrong resolver drops a true edge and a missing edge is invisible.
  `narrowedCount` says whether evidence did anything. `outline_files --focus` now builds one graph
  across the given paths, which is where this pays.

Still deferred in both trees: Matrix token streaming.

## Commands

```sh
# Haskell (this branch)
cabal build && cabal test              # -Wall -Werror; tasty
cabal build -fe2ee && cabal test lavoisier-e2ee-test
ormolu --mode inplace $(git ls-files '*.hs')
cabal run lav -- --agent "edit task"

# Rust (on `main`; `git worktree add ../lavoisier-rust main` for a build tree)
cargo test && cargo clippy --all-targets && cargo fmt --check
cargo run -p lavoisier -- --agent "edit task"
```

Providers are selected with `--provider anthropic|xai|google|claude-cli` and keyed from
`ANTHROPIC_API_KEY` / `XAI_API_KEY` / `GOOGLE_API_KEY`. Gateways (`--serve`, `--serve-matrix`,
`--serve-slack`, `--serve-a2a`, `--acp`, `--tui`, `--cron-file`, `--schedule-file`) compose — they all
run concurrently over one shared agent. Full flag list in `README.md`.

## Working here

- **Never make live API calls without asking first** — they cost real money on the user's keys.
- Develop on `haskell-port`, not `main`. Stage explicitly (`git add <paths>`); `git add -A` sweeps a
  stray gitlink into the index.
- Ask before publishing, tagging, or pushing a release.
- Commit with a `Co-Authored-By: Claude <model> <noreply@anthropic.com>` trailer naming the model in
  use (past commits read `Claude Opus 4.8 (1M context)`).
