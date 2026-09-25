//! gRPC build log.
//!
//! The agent listens. The builder pushes one line at a time, then a final chunk with `eof` set
//! and the process exit code. Subscribers (a `run_build` tool) follow a `build_id` and learn the
//! outcome from that last chunk, so there is no separate result tool to poll.
//!
//! Bindings are committed under `src/generated`. Regenerate with `LVZ_BUILDLOG_REGEN=1`.

use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::{Arc, Mutex, OnceLock};

use tokio::sync::mpsc::{UnboundedReceiver, UnboundedSender};
use tonic::transport::Server;

pub mod pb {
    include!("generated/buildlog.rs");
}

use pb::build_log_server::{BuildLog, BuildLogServer};
use pb::{LogChunk, PublishAck};

/// One update from a running build.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LogUpdate {
    /// A single stdout/stderr line, without the trailing newline.
    Line(String),
    /// The build process exited.
    End {
        /// Process exit code.
        exit_code: i32,
    },
}

/// Fan-out of build lines, keyed by `build_id`.
#[derive(Default)]
pub struct LogHub {
    subs: Mutex<HashMap<String, Vec<UnboundedSender<LogUpdate>>>>,
}

impl LogHub {
    /// Receive every later update for `build_id`. Subscribe before the builder connects.
    pub fn subscribe(&self, build_id: &str) -> UnboundedReceiver<LogUpdate> {
        let (tx, rx) = tokio::sync::mpsc::unbounded_channel();
        self.subs
            .lock()
            .expect("build log hub")
            .entry(build_id.to_string())
            .or_default()
            .push(tx);
        rx
    }

    fn fanout(&self, build_id: &str, update: LogUpdate) {
        let mut guard = self.subs.lock().expect("build log hub");
        if let Some(txs) = guard.get_mut(build_id) {
            txs.retain(|tx| tx.send(update.clone()).is_ok());
        }
    }
}

struct Svc(Arc<LogHub>);

#[tonic::async_trait]
impl BuildLog for Svc {
    async fn publish(
        &self,
        request: tonic::Request<tonic::Streaming<LogChunk>>,
    ) -> Result<tonic::Response<PublishAck>, tonic::Status> {
        let mut stream = request.into_inner();
        while let Some(chunk) = stream.message().await? {
            if chunk.eof {
                self.0.fanout(
                    &chunk.build_id,
                    LogUpdate::End {
                        exit_code: chunk.exit_code,
                    },
                );
            } else if !chunk.line.is_empty() {
                self.0
                    .fanout(&chunk.build_id, LogUpdate::Line(chunk.line));
            }
        }
        Ok(tonic::Response::new(PublishAck {}))
    }
}

static HUB: OnceLock<Arc<LogHub>> = OnceLock::new();

/// Install the process-wide hub. Later calls return the same hub.
pub fn install() -> Arc<LogHub> {
    HUB.get_or_init(|| Arc::new(LogHub::default())).clone()
}

/// The hub, if [`install`] has run (the CLI does this when `LVZ_BUILDLOG_BIND` is set).
pub fn hub() -> Option<Arc<LogHub>> {
    HUB.get().cloned()
}

/// Serve `hub` on `addr` until the task is dropped or the listener fails.
pub async fn serve(hub: Arc<LogHub>, addr: SocketAddr) -> Result<(), tonic::transport::Error> {
    let mut builder = Server::builder();
    builder
        .add_service(BuildLogServer::new(Svc(hub)))
        .serve(addr)
        .await
}

/// Push `lines` then an eof chunk. Used by the builder-side binary and by tests.
pub async fn publish(
    addr: SocketAddr,
    build_id: &str,
    lines: &[String],
    exit_code: i32,
) -> Result<(), tonic::Status> {
    use tokio_stream::wrappers::ReceiverStream;
    let endpoint = format!("http://{addr}");
    let mut client = pb::build_log_client::BuildLogClient::connect(endpoint)
        .await
        .map_err(|e| tonic::Status::unavailable(e.to_string()))?;
    let (tx, rx) = tokio::sync::mpsc::channel(lines.len().saturating_add(1).max(1));
    for line in lines {
        let _ = tx
            .send(LogChunk {
                build_id: build_id.to_string(),
                line: line.clone(),
                eof: false,
                exit_code: 0,
            })
            .await;
    }
    let _ = tx
        .send(LogChunk {
            build_id: build_id.to_string(),
            line: String::new(),
            eof: true,
            exit_code,
        })
        .await;
    drop(tx);
    client
        .publish(ReceiverStream::new(rx))
        .await
        .map(|_| ())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn a_subscriber_sees_lines_then_the_exit_code() {
        let hub = Arc::new(LogHub::default());
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let incoming = tokio_stream::wrappers::TcpListenerStream::new(listener);
        let served = hub.clone();
        tokio::spawn(async move {
            let mut builder = Server::builder();
            let _ = builder
                .add_service(BuildLogServer::new(Svc(served)))
                .serve_with_incoming(incoming)
                .await;
        });
        let mut rx = hub.subscribe("b1");
        // Give the listener a moment to accept.
        tokio::time::sleep(std::time::Duration::from_millis(50)).await;
        publish(addr, "b1", &["compiling crate".into(), "finished".into()], 0)
            .await
            .unwrap();
        assert_eq!(rx.recv().await, Some(LogUpdate::Line("compiling crate".into())));
        assert_eq!(rx.recv().await, Some(LogUpdate::Line("finished".into())));
        assert_eq!(rx.recv().await, Some(LogUpdate::End { exit_code: 0 }));
    }
}
