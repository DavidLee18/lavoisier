# Containerfile for the `lavoisier` gateway — multi-stage, linux/arm64 (RECIPE §9 M10, §10).
#
#   podman build --platform linux/arm64 -f Containerfile -t lavoisier:dev .
#
# Conventions: arm64 (Fargate target), Podman not Docker. `protoc` is required only in the
# builder stage (lvz-xai/build.rs compiles the vendored protos); the runtime image has none.

# --- builder ---------------------------------------------------------------
FROM --platform=linux/arm64 docker.io/library/rust:1.88-bookworm AS builder

# protobuf-compiler = protoc; libprotobuf-dev ships the well-known .proto sources
# (/usr/include/google/protobuf/*.proto) that this protoc needs on the include path.
RUN apt-get update \
    && apt-get install -y --no-install-recommends protobuf-compiler libprotobuf-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
# The whole workspace is needed (build.rs + path deps); .containerignore drops target/, etc.
COPY Cargo.toml Cargo.lock ./
COPY crates ./crates
RUN cargo build --release -p lavoisier

# --- runtime ---------------------------------------------------------------
# distroless/cc: glibc + libgcc (for `ring`) + CA certs, no shell. TLS is rustls/webpki, so
# no OpenSSL is needed. Runs as the nonroot uid; port 8080 is unprivileged.
FROM --platform=linux/arm64 gcr.io/distroless/cc-debian12:nonroot AS runtime

COPY --from=builder /build/target/release/lavoisier /usr/local/bin/lavoisier
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/lavoisier"]
CMD ["--serve", "0.0.0.0:8080"]
