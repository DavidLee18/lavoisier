# Vendored: xai-org/xai-proto

- Source: https://github.com/xai-org/xai-proto
- Pinned commit: `543b901d69762b8e96f72450ac3619332eba698a` (2026-05-29 18:27:37 -0700)
- License: Apache-2.0 (see `LICENSE` in this directory)

Only the `proto/xai/` tree is vendored (plus this file and the license).
`lvz-xai` compiles `xai/api/v1/chat.proto` and its transitive imports via
`tonic-build` in its `build.rs`; the include root is this directory.

To update: clone the source repo, copy `proto/xai` over this tree, and record
the new pinned commit here. Then `cargo build -p lvz-xai` to regenerate and
re-run the tests.
