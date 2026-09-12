//! Codegen for the xAI gRPC client (§8): compile the vendored `xai-org/xai-proto` chat service
//! (and its transitive imports) with `tonic-prost-build`.
//!
//! **The generated bindings are committed** at `src/generated/xai_api.rs` and included directly by
//! `src/grpc.rs`, so an ordinary build — including docs.rs and `cargo install` — needs **no
//! `protoc`**. This build script only regenerates that file when `LVZ_XAI_REGEN=1` is set (a
//! maintainer step, e.g. after bumping the vendored proto); that path requires `protoc`
//! (`brew install protobuf`). The vendored protos live in this crate's own `proto/` directory (so
//! they ship in the published crate) — see `proto/VENDOR.md` for the pinned upstream commit and the
//! update procedure.

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let proto_root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("proto");
    let generated = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("src/generated");

    // Rebuild only when the inputs or the regen switch change — the default build is otherwise a
    // no-op that compiles the committed bindings.
    println!("cargo:rerun-if-env-changed=LVZ_XAI_REGEN");
    println!("cargo:rerun-if-changed={}", proto_root.display());
    println!("cargo:rerun-if-changed={}", generated.display());

    if std::env::var_os("LVZ_XAI_REGEN").is_none() {
        return Ok(());
    }

    let mut includes = vec![proto_root.clone()];

    // The protos import the well-known `google/protobuf/timestamp.proto`. Homebrew's protoc
    // resolves the well-known types built-in, but a packaged protoc (e.g. Debian's, used in the
    // M10 Fargate image build) needs them on the include path — add the first system include
    // dir that actually carries them (Debian: `libprotobuf-dev` → /usr/include).
    for candidate in [
        "/usr/include",
        "/usr/local/include",
        "/opt/homebrew/include",
    ] {
        let dir = std::path::Path::new(candidate);
        if dir.join("google/protobuf/timestamp.proto").exists() {
            includes.push(dir.to_path_buf());
            break;
        }
    }

    // Write the generated `xai_api.rs` straight into the source tree so it can be committed.
    std::fs::create_dir_all(&generated)?;
    tonic_prost_build::configure()
        .build_server(false)
        .out_dir(&generated)
        .compile_protos(&[proto_root.join("xai/api/v1/chat.proto")], &includes)?;
    Ok(())
}
