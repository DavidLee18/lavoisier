//! Builder-side publisher. Run as the builder container's entrypoint.
//!
//! Reads `LVZ_BUILDLOG_ADDR` (`http://host:port`), `BUILD_ID`, `BUILD_COMMAND`, and optional
//! `BUILD_WORKDIR` (default `/root`). Runs the command, pushes each output line to the agent,
//! then one eof chunk with the exit code.

use std::process::Stdio;

use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Command;
use tokio_stream::wrappers::ReceiverStream;
use tonic::Request;

use lvz_buildlog::pb::build_log_client::BuildLogClient;
use lvz_buildlog::pb::LogChunk;

#[tokio::main]
async fn main() {
    let addr = std::env::var("LVZ_BUILDLOG_ADDR").expect("LVZ_BUILDLOG_ADDR is required");
    let build_id = std::env::var("BUILD_ID").expect("BUILD_ID is required");
    let command = std::env::var("BUILD_COMMAND").expect("BUILD_COMMAND is required");
    let workdir = std::env::var("BUILD_WORKDIR").unwrap_or_else(|_| "/root".into());

    let mut client = BuildLogClient::connect(addr).await.expect("connect to agent");
    let mut child = Command::new("sh")
        .arg("-c")
        .arg(&command)
        .current_dir(&workdir)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("spawn build command");

    let stdout = child.stdout.take().expect("stdout");
    let stderr = child.stderr.take().expect("stderr");
    let (tx, rx) = tokio::sync::mpsc::channel(64);
    let id_out = build_id.clone();
    let out_tx = tx.clone();
    let stdout_task = tokio::spawn(async move { forward_lines(stdout, &id_out, out_tx).await });
    let id_err = build_id.clone();
    let err_tx = tx.clone();
    let stderr_task = tokio::spawn(async move { forward_lines(stderr, &id_err, err_tx).await });

    let eof_id = build_id.clone();
    let eof_tx = tx.clone();
    tokio::spawn(async move {
        let status = child.wait().await.expect("wait for build command");
        let _ = stdout_task.await;
        let _ = stderr_task.await;
        let code = status.code().unwrap_or(1);
        let _ = eof_tx
            .send(LogChunk {
                build_id: eof_id,
                line: String::new(),
                eof: true,
                exit_code: code,
            })
            .await;
    });
    drop(tx);

    client
        .publish(Request::new(ReceiverStream::new(rx)))
        .await
        .expect("publish build log");
    std::process::exit(0);
}

async fn forward_lines<R>(reader: R, build_id: &str, tx: tokio::sync::mpsc::Sender<LogChunk>)
where
    R: tokio::io::AsyncRead + Unpin,
{
    let mut lines = BufReader::new(reader).lines();
    while let Ok(Some(line)) = lines.next_line().await {
        if tx
            .send(LogChunk {
                build_id: build_id.to_string(),
                line,
                eof: false,
                exit_code: 0,
            })
            .await
            .is_err()
        {
            break;
        }
    }
}
