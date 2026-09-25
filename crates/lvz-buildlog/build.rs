//! Regenerates `src/generated/buildlog.rs` only when `LVZ_BUILDLOG_REGEN=1`.
//! Ordinary builds compile the committed bindings and do not need `protoc`.

fn main() -> Result<(), Box<dyn std::error::Error>> {
    println!("cargo:rerun-if-env-changed=LVZ_BUILDLOG_REGEN");
    println!("cargo:rerun-if-changed=proto/buildlog.proto");
    if std::env::var_os("LVZ_BUILDLOG_REGEN").is_none() {
        return Ok(());
    }
    let out = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("src/generated");
    std::fs::create_dir_all(&out)?;
    tonic_prost_build::configure()
        .build_server(true)
        .build_client(true)
        .out_dir(&out)
        .compile_protos(&["proto/buildlog.proto"], &["proto"])?;
    Ok(())
}
