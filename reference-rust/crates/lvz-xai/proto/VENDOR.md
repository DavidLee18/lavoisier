# Vendored: xai-org/xai-proto

- Source: https://github.com/xai-org/xai-proto
- Pinned commit: `543b901d69762b8e96f72450ac3619332eba698a` (2026-05-29 18:27:37 -0700)
- License: Apache-2.0 (see `LICENSE` in this directory)

Only the `proto/xai/` tree is vendored (plus this file and the license).
`lvz-xai` compiles `xai/api/v1/chat.proto` and its transitive imports via
`tonic-prost-build` in its `build.rs`; the include root is this directory.

The generated bindings are **committed** at `../src/generated/xai_api.rs` and
included directly by `src/grpc.rs`, so an ordinary build — including docs.rs and
`cargo install` — needs **no `protoc`**. Codegen runs only when `LVZ_XAI_REGEN=1`
is set (which does need `protoc`, e.g. `brew install protobuf`).

To update: clone the source repo, copy `proto/xai` over this tree, and record
the new pinned commit here. Then regenerate the committed bindings and re-run
the tests:

```sh
LVZ_XAI_REGEN=1 cargo build -p lvz-xai   # rewrites src/generated/xai_api.rs (needs protoc)
cargo test -p lvz-xai
git add crates/lvz-xai/src/generated/xai_api.rs   # commit the refreshed bindings
```
