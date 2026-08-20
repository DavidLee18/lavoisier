# Containerfile for the `lavoisier` gateway — multi-stage, linux/arm64.
#
#   nerdctl build --platform linux/arm64 -f Containerfile -t lavoisier:dev .
#
# Conventions: arm64 (Fargate target), colima + nerdctl (not Docker).
#
# This is the SIMPLE stack: `infra/`'s HTTP/WS gateway on Fargate — no Matrix, no EFS. So the
# `e2ee` flag stays OFF (its default) and **libolm is deliberately not built here**; only the Matrix
# gateway needs it, and it is EOL upstream and expensive to build. The deployment that does need it
# builds it explicitly (see the sibling lvz-matrix-infra Containerfile).
#
# NOTE: no Linux build of this tree existed when this was written — every green build so far is
# macOS/aarch64-darwin. The recipe below mirrors .github/workflows/haskell-ci.yml, which does build
# these native libraries on Linux, but treat the first run as unattempted work.

# --- builder ---------------------------------------------------------------
# GHC pinned to the version haskell-ci.yml uses.
FROM --platform=linux/arm64 docker.io/library/haskell:9.10.3-bookworm AS builder

# libtree-sitter must be >= 0.25 (the vendored grammars are ABI 15) — newer than any apt package, so
# it is built from source at the version CI pins. libsnappy comes from apt (snappy-c, pulled in
# transitively by grapesy -> grpc-spec).
ARG TREE_SITTER_VERSION=0.26.12
ARG PROTOC_VERSION=29.3

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential pkg-config git curl unzip ca-certificates \
        libsnappy-dev libgmp-dev zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# protoc is needed in the BUILDER ONLY: proto-lens-protobuf-types (via the xai-proto codec) runs it
# at build time even though the xAI bindings are committed. The runtime image has none. Same pinned,
# SHA-256-verified download as release-haskell.yml (linux-aarch_64 asset).
RUN set -eu; \
    url="https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOC_VERSION}/protoc-${PROTOC_VERSION}-linux-aarch_64.zip"; \
    sha=6427349140e01f06e049e707a58709a4f221ae73ab9a0425bc4a00c8d0e1ab32; \
    curl -fsSL -o /tmp/protoc.zip "$url"; \
    echo "${sha}  /tmp/protoc.zip" | sha256sum -c -; \
    unzip -q /tmp/protoc.zip -d /usr/local; \
    rm /tmp/protoc.zip; \
    protoc --version

RUN set -eu; \
    curl -fsSL -o /tmp/ts.tar.gz "https://github.com/tree-sitter/tree-sitter/archive/refs/tags/v${TREE_SITTER_VERSION}.tar.gz"; \
    tar xzf /tmp/ts.tar.gz -C /tmp; \
    make -C "/tmp/tree-sitter-${TREE_SITTER_VERSION}" -j"$(nproc)"; \
    make -C "/tmp/tree-sitter-${TREE_SITTER_VERSION}" install PREFIX=/usr/local; \
    ldconfig; \
    pkg-config --modversion tree-sitter; \
    rm -rf /tmp/ts.tar.gz "/tmp/tree-sitter-${TREE_SITTER_VERSION}"

WORKDIR /build

# Explicit COPYs rather than `COPY . .`: .containerignore does not exclude dist-newstyle/, which
# would bloat the build context enormously.
# cabal.project.dist is the packaging project file — no machine-specific paths, unlike the dev
# cabal.project which points at ~/.local and /opt/homebrew.
COPY cabal.project.dist lavoisier.cabal ./
COPY src ./src
COPY app ./app
COPY gen ./gen
COPY cbits ./cbits
COPY olm ./olm

# snappy-c's C-library detection needs the multiarch lib dir; release-haskell.yml writes exactly this
# file per runner. `gcc -print-multiarch` keeps it correct on both arm64 and x86_64.
RUN set -eu; \
    ma="$(gcc -print-multiarch)"; \
    printf 'package snappy-c\n  extra-lib-dirs: /usr/lib/%s\n  extra-include-dirs: /usr/include\n' "$ma" \
        > cabal.project.dist.local

# -j1 plus an RTS heap cap: GHC linking is memory-hungry and this is a large package.
RUN cabal update && cabal build --project-file=cabal.project.dist -j1 --ghc-options="+RTS -M6g -RTS" exe:lav \
    && cp "$(cabal list-bin --project-file=cabal.project.dist exe:lav)" /usr/local/bin/lav

# --- runtime ---------------------------------------------------------------
# NOT distroless/cc any more. A GHC binary is dynamically linked and additionally links
# libtree-sitter and libsnappy; distroless carries neither, and has no shell to diagnose it with.
# debian:bookworm-slim matches the builder's ABI and provides both.
FROM --platform=linux/arm64 docker.io/library/debian:bookworm-slim AS runtime

# libgmp10/libffi8/zlib1g/libtinfo6 — the GHC runtime's own dynamic dependencies.
# libsnappy1v5 — the runtime counterpart of libsnappy-dev. TLS is the pure-Haskell `tls` stack, so
# no OpenSSL is needed; ca-certificates supplies the trust roots.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates libgmp10 libffi8 zlib1g libtinfo6 libsnappy1v5 \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --uid 65532 nonroot

COPY --from=builder /usr/local/lib/libtree-sitter.so* /usr/local/lib/
RUN ldconfig

COPY --from=builder /usr/local/bin/lav /usr/local/bin/lav

# Fail the build, not the deploy, if the binary cannot load its shared libraries.
RUN lav --help > /dev/null

USER nonroot
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/lav"]
# `--serve` takes a PORT (an Int), not an address: the old ["--serve", "0.0.0.0:8080"] was rejected by
# the option parser and the container exited at startup. The server binds all interfaces regardless.
# `infra/terraform/ecs.tf` passes the same argument and needs the same one-line fix — it is outside
# this file's remit, so it is still wrong there.
CMD ["--serve", "8080"]
