#!/usr/bin/env bash
# Bundle the Haskell `lav` binary with its non-system shared libraries (libtree-sitter, libsnappy)
# into a self-contained directory, rewriting load paths so the binary runs without the build
# machine's Homebrew / /usr/local copies. Unlike the Rust binary, `lav` links these C libraries
# dynamically, so a portable tarball must carry them.
#
# Usage: scripts/package-haskell.sh <lav-binary> <staging-dir>
set -euo pipefail

BIN="${1:?usage: package-haskell.sh <lav-binary> <staging-dir>}"
OUT="${2:?usage: package-haskell.sh <lav-binary> <staging-dir>}"

mkdir -p "$OUT"
cp "$BIN" "$OUT/lav"
chmod u+w "$OUT/lav"

case "$(uname -s)" in
  Darwin)
    # Copy each non-system dylib next to the binary and repoint both the binary's reference and the
    # dylib's own id to @executable_path.
    otool -L "$OUT/lav" | awk 'NR>1{print $1}' | grep -vE '^/usr/lib/|^/System/' | while read -r lib; do
      [ -f "$lib" ] || continue
      base="$(basename "$lib")"
      cp "$lib" "$OUT/$base"
      chmod u+w "$OUT/$base"
      install_name_tool -id "@executable_path/$base" "$OUT/$base"
      install_name_tool -change "$lib" "@executable_path/$base" "$OUT/lav"
    done
    # install_name_tool invalidates the code signature on Apple Silicon — the loader then kills the
    # binary — so re-sign everything ad-hoc.
    codesign -f -s - "$OUT"/*.dylib "$OUT/lav"
    ;;
  Linux)
    # Copy the non-system .so deps next to the binary and set the rpath to $ORIGIN so the dynamic
    # loader finds them by SONAME beside the executable.
    ldd "$OUT/lav" | awk '{print $3}' | grep -E 'libtree-sitter|libsnappy' | while read -r lib; do
      [ -f "$lib" ] || continue
      cp -L "$lib" "$OUT/$(basename "$lib")"
    done
    patchelf --set-rpath '$ORIGIN' "$OUT/lav"
    ;;
  *)
    echo "unsupported OS: $(uname -s)" >&2
    exit 1
    ;;
esac

# Smoke-test: the bundle must run with no library-path hints in the environment.
( cd "$OUT" && env -i HOME="${HOME:-/tmp}" PATH=/usr/bin:/bin ./lav --help >/dev/null )
echo "bundle OK: $(ls "$OUT" | tr '\n' ' ')"
