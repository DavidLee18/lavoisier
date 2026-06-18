# Publishing to crates.io + cargo-binstall

`lavoisier` is a Cargo workspace, so the binary crate (`lavoisier`) and its 13 library crates
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
         lvz-tune lvz-gw-http lvz-gw-matrix lvz-gw-cron lvz-tools lvz-agent lvz-memory lavoisier; do
  cargo publish -p "$c" --dry-run || break
done
```

Then publish for real, **in this order**. Two limits to know:
- `cargo publish` already waits for each version to index before returning, so deps resolve.
- crates.io rate-limits **brand-new crate names** to ~1 per 10 minutes (after a small burst). On a
  fresh workspace the first ~5 publish immediately, then you'll get `429 Too Many Requests` with a
  "try again after" time. The loop below **waits out the 429 and retries**, so the whole set
  (~14 new crates) completes hands-off in roughly 1.5 hours:

```sh
for c in lvz-protocol lvz-context lvz-anthropic lvz-google lvz-xai lvz-claude-cli \
         lvz-tune lvz-gw-http lvz-gw-matrix lvz-gw-cron lvz-tools lvz-agent lvz-memory lavoisier; do
  until out=$(cargo publish -p "$c" 2>&1); do
    echo "$out" | grep -qiE '429|Too Many Requests' || { echo "$out" | tail; echo "HARD FAIL: $c"; exit 1; }
    echo "rate-limited on $c — sleeping 11m…"; sleep 660
  done
done
```

(Once published, *version bumps* are not new-crate publishes, so they are not subject to this
limit — only the initial publish of each new name is. A higher limit can be requested from
help@crates.io.)

Note: publishing is **public and effectively permanent** (a version can be yanked but not deleted).
Bump only the crates whose source actually changed (and any crate that depends on a bumped crate, so its
version requirement still resolves); leave the rest at their published version. Latest changed set
(`v0.3.0`): `lvz-memory` (0.2.0) and `lavoisier` (0.3.0). Earlier, `v0.2.0` bumped `lvz-gw-cron` (new),
`lvz-gw-matrix`, and `lavoisier`. The remaining crates are still at `0.1.0`.

## 2. Cut a release → prebuilt binaries → `cargo binstall`

`cargo binstall lavoisier` downloads a prebuilt binary from the GitHub release matching the crate
version. Tag the version to trigger `.github/workflows/release.yml`, which builds and uploads
`lavoisier-<target>.tar.gz` for macOS (arm64/Apple Silicon) and Linux (x64/arm64):

```sh
git tag v0.3.0
git push origin v0.3.0
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
- **`e2ee` feature**: `lvz-gw-matrix` (and the `lavoisier` passthrough) gain an optional `e2ee` feature
  pulling `matrix-sdk-crypto`/`ruma`. It's **off by default**, so it doesn't affect the standard publish
  or the MSRV-1.88 default build — but a consumer enabling it needs Rust ≥ 1.93. Publishing is unaffected
  (optional deps publish fine); just don't bump the workspace MSRV on its account.
- The vendored xAI protos (Apache-2.0) ship inside `lvz-xai` (`crates/lvz-xai/proto/`, see its
  `VENDOR.md`); the rest of the workspace is MIT.
