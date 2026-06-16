# Publishing to crates.io + cargo-binstall

`lavoisier` is a Cargo workspace, so the binary crate (`lavoisier`) and its 12 library crates
(`lvz-*`) are published to crates.io **in dependency order**. End users then install a prebuilt
binary with `cargo binstall lavoisier` (no Rust toolchain or `protoc` needed) or build from source
with `cargo install lavoisier` (needs `protoc`).

## Prerequisites (one-time)

- A crates.io account + token: `cargo login`.
- **Confirm the crate names are available** on crates.io: `lavoisier` and every `lvz-*` below. If one
  is taken, rename it (in its `Cargo.toml` and in `[workspace.dependencies]` in the root `Cargo.toml`).
- `protoc` installed (`brew install protobuf`) — `cargo publish` verifies each crate by building it,
  and `lvz-xai` compiles the vendored protos.
- A clean, committed tree on `main`; everything green (`cargo test`, `clippy`, `fmt`).

## 1. Publish the crates (in this order)

Each crate must already be on crates.io before the crates that depend on it. Dry-run first:

```sh
for c in lvz-protocol lvz-context lvz-anthropic lvz-google lvz-xai lvz-claude-cli \
         lvz-tune lvz-gw-http lvz-gw-matrix lvz-tools lvz-agent lvz-memory lavoisier; do
  cargo publish -p "$c" --dry-run || break
done
```

Then publish for real, waiting for each to index before the next (crates.io is usually ready within
a few seconds; `cargo publish` will retry/resolve):

```sh
for c in lvz-protocol lvz-context lvz-anthropic lvz-google lvz-xai lvz-claude-cli \
         lvz-tune lvz-gw-http lvz-gw-matrix lvz-tools lvz-agent lvz-memory lavoisier; do
  cargo publish -p "$c" || { echo "stopped at $c"; break; }
  sleep 20
done
```

Note: publishing is **public and effectively permanent** (a version can be yanked but not deleted).
Bump the version (all crates share `0.1.0`; keep them in lockstep) before re-publishing.

## 2. Cut a release → prebuilt binaries → `cargo binstall`

`cargo binstall lavoisier` downloads a prebuilt binary from the GitHub release matching the crate
version. Tag the version to trigger `.github/workflows/release.yml`, which builds and uploads
`lavoisier-<target>.tar.gz` for macOS (arm64/x64) and Linux (x64/arm64):

```sh
git tag v0.1.0
git push origin v0.1.0
```

Once the release assets are up, verify:

```sh
cargo binstall lavoisier      # fetches the prebuilt binary
lavoisier --help
```

## Notes

- **docs.rs**: `lvz-xai` needs `protoc` at build time; docs.rs has no `protoc`, so its docs build may
  fail. The other crates document fine. (Fix later if needed: vendor `protoc` via a `protobuf-src`
  build-dependency, or pre-generate the proto bindings.)
- **Version bumps**: keep all crates at the same version. Bump together, re-run §1, then a new tag for §2.
- The vendored xAI protos (Apache-2.0) ship inside `lvz-xai` (`crates/lvz-xai/proto/`, see its
  `VENDOR.md`); the rest of the workspace is MIT.
