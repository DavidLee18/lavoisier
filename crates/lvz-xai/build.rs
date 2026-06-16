//! Codegen for the xAI gRPC client (§8): compile the vendored
//! `xai-org/xai-proto` chat service (and its transitive imports) with `tonic-prost-build`.
//!
//! Requires `protoc` on the build machine (e.g. `brew install protobuf`). The vendored
//! protos live at the repo-root `proto/` directory — see `proto/VENDOR.md` for the pinned
//! upstream commit and the update procedure.

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let proto_root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../proto");
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

    tonic_prost_build::configure()
        .build_server(false)
        .compile_protos(&[proto_root.join("xai/api/v1/chat.proto")], &includes)?;
    Ok(())
}
