# Releasing

Lavoisier ships as **prebuilt binaries attached to a GitHub release**, built by
`.github/workflows/release.yml`. There is no package-registry step: the project is not on Hackage,
and the crates.io packages are frozen (see the last section).

## Cutting a release

1. Everything green on `main`: `cabal build` (`-Wall -Werror`), `cabal test`, `ormolu --mode check`.
   CI gates all three, including the budget-ceiling step.
2. Bump `version:` in `lavoisier.cabal`. Commit it.
3. **Check the sdist actually carries what the build needs** before tagging — this has bitten a
   release before (`hs-v0.13.1`, missing `cbits` headers):

   ```sh
   cabal sdist all          # NOT `cabal sdist lavoisier` — that errors on the library component
   tar tzf dist-newstyle/sdist/lavoisier-*.tar.gz | grep -E '\.h$|tests/budget'
   ```

   Anything a build reads at compile time must be in `extra-source-files`: the `cbits/**/*.h`
   shims and the `tests/budget/**` fixtures.
4. Tag and push:

   ```sh
   git tag v0.16.2 && git push origin v0.16.2
   ```

5. The workflow builds three targets — `aarch64-apple-darwin`, `x86_64-unknown-linux-gnu`,
   `aarch64-unknown-linux-gnu` — packages each with `scripts/package-haskell.sh`, uploads them as
   run artifacts, and then a **single `publish` job** attaches all three at once.

   > **Do not make the build jobs attach their own asset.** This repo has GitHub's *immutable
   > releases* enabled: the first attach publishes the release and every later one is refused
   > (`Cannot upload asset … to an immutable release`). The tag name is then **burned permanently** —
   > deleting the half-published release does not free it, and the version number is spent. `v0.16.0`
   > was lost this way; `v0.16.1` is the first release under the corrected workflow.
6. **Verify the published artifact, not just the green run.** Download the tarball and run it:

   ```sh
   gh release download v0.16.2 -R DavidLee18/lavoisier -p 'lavoisier-aarch64-apple-darwin.tar.gz'
   tar xzf lavoisier-aarch64-apple-darwin.tar.gz && ./lav --version
   ```

   `--version` reads Cabal's generated `Paths_lavoisier`, so it is the tag you just built, not a
   hand-maintained string — a mismatch here means the wrong commit was tagged.

## Why packaging is not just "copy the binary"

`lav` links `libtree-sitter` and `libsnappy` **dynamically**, so a bare binary depends on the build
machine's Homebrew or `/usr/local` copies. `scripts/package-haskell.sh` copies each non-system
library next to the binary and rewrites the load paths to `@executable_path` (macOS) or `$ORIGIN`
(Linux).

On Apple Silicon, `install_name_tool` **invalidates the code signature**, so the script re-signs ad
hoc (`codesign -f -s -`). Skip that and the binary is killed on launch.

## Tag namespaces

| Tags | What they are |
|---|---|
| `v0.7.1` .. `v0.15.0` | The retired **Rust** implementation. Preserved on the `rust` branch. |
| `hs-v0.13.0` .. `hs-v0.15.0` | The Haskell tree while it was a port on its own branch. |
| `v0.16.0` onwards | Haskell, from `main`. The version line continues; the `hs-` prefix is dropped. |

## crates.io: frozen, deliberately

The Rust implementation published `lavoisier` plus 15 `lvz-*` library crates to crates.io. Those
versions are **left exactly as they are** — a published version can be yanked but never deleted, and
nothing is served from this tree.

The consequence worth stating plainly: **`cargo install lavoisier` and `cargo binstall lavoisier`
still install Rust v0.15.0**, not the current Haskell build. Anyone who wants the current binary
takes a release tarball. If that divergence stops being acceptable, the options are to yank the
published versions (reversible) or to publish a final version whose README points here; neither has
been done.

The old crates.io procedure — publish order, the new-crate rate limit, the `protoc`-free vendored
gRPC bindings — is preserved in this file's history: `git show v0.15.0:PUBLISHING.md`.
