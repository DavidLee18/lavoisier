//! Codegen for the xAI gRPC client (`RECIPE.md` §8): compile the vendored
//! `xai-org/xai-proto` chat service (and its transitive imports) with `tonic-prost-build`.
//!
//! Requires `protoc` on the build machine (e.g. `brew install protobuf`). The vendored
//! protos live at the repo-root `proto/` directory — see `proto/VENDOR.md` for the pinned
//! upstream commit and the update procedure.

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let proto_root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../proto");
    tonic_prost_build::configure()
        .build_server(false)
        .compile_protos(&[proto_root.join("xai/api/v1/chat.proto")], &[proto_root])?;
    Ok(())
}
