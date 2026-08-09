//! `lvz-mcp` — a **Model Context Protocol** client that adapts an external MCP server's tools into
//! Lavoisier [`Tool`]s.
//!
//! Lavoisier is the MCP **client**: it connects to one or more MCP *servers* (each a separate
//! process over stdio, or an HTTP endpoint), discovers the tools they expose (`tools/list`), and
//! wraps each as an [`McpTool`] implementing the core [`Tool`] contract. Because the adaptation
//! lands at that contract, the remote tools flow through the *same* registry every Lavoisier
//! frontend already uses — CLI, Matrix, Slack, cron, and the HTTP/A2A/ACP gateways all gain them
//! for free, with no change to the agent or any gateway.
//!
//! This is a **leaf crate**: it depends only on `lvz-protocol` (plus the async/runtime/serde/http
//! deps). The CLI composition root is the one place that turns a `--mcp-server` spec into live
//! tools (via [`connect_tools`]) and registers them.
//!
//! Transports (behind the [`Transport`] trait, so the JSON-RPC logic is transport-agnostic):
//! - **stdio** — spawn the server as a child process, frame newline-delimited JSON-RPC 2.0 over its
//!   stdin/stdout. This is how most MCP servers ship (e.g. `npx -y @modelcontextprotocol/server-…`).
//! - **HTTP** — POST JSON-RPC 2.0 to a URL, accepting either a JSON body or a Streamable-HTTP SSE
//!   reply, carrying any `Mcp-Session-Id` the server assigns on `initialize`.
//!
//! The protocol itself (JSON-RPC 2.0 + the MCP method set) is **hand-rolled** over `tokio`/`reqwest`
//! — no MCP SDK — matching the workspace's minimal-dependency rule.

#![warn(missing_docs)]

use std::collections::HashMap;
use std::process::Stdio;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex as StdMutex};
use std::time::Duration;

use async_trait::async_trait;
use lvz_protocol::{Tool, ToolError, ToolOutput};
use serde::Deserialize;
use serde_json::{json, Value};
use tokio::io::{AsyncBufReadExt, AsyncRead, AsyncWrite, AsyncWriteExt, BufReader};
use tokio::process::Child;
use tokio::sync::{oneshot, Mutex as AsyncMutex};

/// The MCP protocol version this client advertises on `initialize`. Servers negotiate down if they
/// speak an older revision; the field is informational for our tools-only use.
const PROTOCOL_VERSION: &str = "2025-06-18";

/// Ceiling on any single JSON-RPC round-trip. A hung server must not wedge the turn forever; on
/// timeout the pending slot is dropped and the caller sees [`McpError::Timeout`].
const REQUEST_TIMEOUT: Duration = Duration::from_secs(120);

/// A failure talking to an MCP server.
#[derive(Debug, thiserror::Error)]
pub enum McpError {
    /// A `--mcp-server` spec could not be parsed.
    #[error("bad MCP server spec: {0}")]
    BadSpec(String),
    /// The server process could not be spawned.
    #[error("spawn failed: {0}")]
    Spawn(String),
    /// A transport-level I/O failure (broken pipe, socket error).
    #[error("io error: {0}")]
    Io(String),
    /// An HTTP transport failure.
    #[error("http error: {0}")]
    Http(String),
    /// The server returned a JSON-RPC `error` object.
    #[error("server error: {0}")]
    Rpc(String),
    /// A reply did not match the expected shape.
    #[error("protocol error: {0}")]
    Protocol(String),
    /// The round-trip exceeded [`REQUEST_TIMEOUT`].
    #[error("request timed out")]
    Timeout,
    /// The transport closed before the reply arrived (server exited / pipe closed).
    #[error("connection closed")]
    Closed,
}

/// Which transport a server spec selects.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TransportSpec {
    /// Spawn a child process and speak JSON-RPC over its stdio. The vec is the command + args.
    Stdio(Vec<String>),
    /// POST JSON-RPC to this URL.
    Http(String),
}

/// One MCP server to connect to: a short `label` (used to namespace its tools) and a transport.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct McpServerSpec {
    /// Short identifier prefixed onto each of this server's tool names.
    pub label: String,
    /// How to reach the server.
    pub transport: TransportSpec,
}

impl McpServerSpec {
    /// Parse a `label: target` spec.
    ///
    /// The target is an HTTP(S) URL ⇒ [`TransportSpec::Http`], otherwise a command line split on
    /// whitespace ⇒ [`TransportSpec::Stdio`]. Splitting on the **first** `:` keeps a `://` URL
    /// intact. Examples:
    /// - `fs: npx -y @modelcontextprotocol/server-filesystem .`
    /// - `remote: https://mcp.example.com/`
    pub fn parse(spec: &str) -> Result<Self, McpError> {
        let (label, target) = spec
            .split_once(':')
            .ok_or_else(|| McpError::BadSpec(format!("{spec:?}: expected `label: target`")))?;
        let label = label.trim();
        let target = target.trim();
        if label.is_empty() {
            return Err(McpError::BadSpec(format!("{spec:?}: empty label")));
        }
        if target.is_empty() {
            return Err(McpError::BadSpec(format!("{spec:?}: empty target")));
        }
        let transport = if target.starts_with("http://") || target.starts_with("https://") {
            TransportSpec::Http(target.to_string())
        } else {
            let argv: Vec<String> = target.split_whitespace().map(str::to_string).collect();
            if argv.is_empty() {
                return Err(McpError::BadSpec(format!("{spec:?}: empty command")));
            }
            TransportSpec::Stdio(argv)
        };
        Ok(Self {
            label: label.to_string(),
            transport,
        })
    }
}

/// Connect to the server described by `spec`, run the MCP handshake, and return one [`Tool`] per
/// advertised remote tool. The returned tools keep the underlying connection (child process or HTTP
/// client) alive for as long as they exist, so hold them for the program's lifetime.
pub async fn connect_tools(spec: &McpServerSpec) -> Result<Vec<Arc<dyn Tool>>, McpError> {
    let transport: Box<dyn Transport> = match &spec.transport {
        TransportSpec::Stdio(argv) => Box::new(StdioTransport::spawn(argv)?),
        TransportSpec::Http(url) => Box::new(HttpTransport::new(url)?),
    };
    let client = Arc::new(McpClient::new(spec.label.clone(), transport));
    client.initialize().await?;
    let remote = client.list_tools().await?;
    let tools = remote
        .into_iter()
        .map(|t| {
            let advertised = advertised_name(&spec.label, &t.name);
            Arc::new(McpTool {
                client: client.clone(),
                remote_name: t.name,
                advertised,
                description: t.description.unwrap_or_default(),
                schema: t.input_schema.unwrap_or_else(|| json!({"type": "object"})),
            }) as Arc<dyn Tool>
        })
        .collect();
    Ok(tools)
}

/// Namespace a remote tool name under its server label so MCP tools never silently shadow builtins
/// (the registry is last-registration-wins), and coerce it into the provider tool-name charset
/// `^[A-Za-z0-9_-]{1,64}$`.
fn advertised_name(label: &str, name: &str) -> String {
    let raw = format!("{label}_{name}");
    let mut out: String = raw
        .chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || c == '_' || c == '-' {
                c
            } else {
                '_'
            }
        })
        .collect();
    if out.len() > 64 {
        out.truncate(64);
    }
    out
}

// ---------------------------------------------------------------------------------------------
// The MCP client: JSON-RPC method calls over any transport.
// ---------------------------------------------------------------------------------------------

/// A live connection to one MCP server. Wraps a [`Transport`] and issues the MCP method set.
struct McpClient {
    label: String,
    transport: Box<dyn Transport>,
}

impl McpClient {
    fn new(label: String, transport: Box<dyn Transport>) -> Self {
        Self { label, transport }
    }

    /// The `initialize` handshake, followed by the `notifications/initialized` acknowledgement the
    /// spec requires before other requests.
    async fn initialize(&self) -> Result<(), McpError> {
        let params = json!({
            "protocolVersion": PROTOCOL_VERSION,
            "capabilities": {},
            "clientInfo": { "name": "lavoisier", "version": env!("CARGO_PKG_VERSION") },
        });
        self.transport.request("initialize", params).await?;
        self.transport
            .notify("notifications/initialized", json!({}))
            .await?;
        tracing::info!(server = %self.label, "mcp server initialized");
        Ok(())
    }

    /// Discover the server's tools, following `nextCursor` pagination to completion.
    async fn list_tools(&self) -> Result<Vec<RemoteTool>, McpError> {
        let mut all = Vec::new();
        let mut cursor: Option<String> = None;
        loop {
            let params = match &cursor {
                Some(c) => json!({ "cursor": c }),
                None => json!({}),
            };
            let result = self.transport.request("tools/list", params).await?;
            let page: ToolsListResult = serde_json::from_value(result)
                .map_err(|e| McpError::Protocol(format!("tools/list: {e}")))?;
            all.extend(page.tools);
            match page.next_cursor {
                Some(c) if !c.is_empty() => cursor = Some(c),
                _ => break,
            }
        }
        tracing::info!(server = %self.label, tools = all.len(), "mcp tools discovered");
        Ok(all)
    }

    /// Invoke a tool by its **remote** name and return the parsed result.
    async fn call_tool(&self, name: &str, args: Value) -> Result<CallResult, McpError> {
        // MCP wants an object for `arguments`; a tool with no args may arrive as JSON `null`.
        let arguments = if args.is_null() { json!({}) } else { args };
        let result = self
            .transport
            .request(
                "tools/call",
                json!({ "name": name, "arguments": arguments }),
            )
            .await?;
        serde_json::from_value(result).map_err(|e| McpError::Protocol(format!("tools/call: {e}")))
    }
}

/// A tool advertised by an MCP server, in the shape `tools/list` returns.
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RemoteTool {
    name: String,
    #[serde(default)]
    description: Option<String>,
    #[serde(default)]
    input_schema: Option<Value>,
}

/// The `tools/list` result envelope.
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ToolsListResult {
    #[serde(default)]
    tools: Vec<RemoteTool>,
    #[serde(default)]
    next_cursor: Option<String>,
}

/// The `tools/call` result: a list of content blocks plus an error flag.
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct CallResult {
    #[serde(default)]
    content: Vec<Value>,
    #[serde(default)]
    is_error: bool,
}

impl CallResult {
    /// Flatten the content blocks into a single string for the model: text blocks contribute their
    /// `text`; any other block contributes its JSON, so nothing is silently dropped.
    fn render(&self) -> String {
        let parts: Vec<String> = self
            .content
            .iter()
            .map(|block| match block.get("type").and_then(Value::as_str) {
                Some("text") => block
                    .get("text")
                    .and_then(Value::as_str)
                    .unwrap_or_default()
                    .to_string(),
                _ => block.to_string(),
            })
            .collect();
        parts.join("\n")
    }
}

// ---------------------------------------------------------------------------------------------
// The Tool adapter.
// ---------------------------------------------------------------------------------------------

/// A single remote MCP tool, adapted to the Lavoisier [`Tool`] contract.
struct McpTool {
    client: Arc<McpClient>,
    /// The name as the server knows it (sent back in `tools/call`).
    remote_name: String,
    /// The namespaced name advertised to the model (`<label>_<tool>`).
    advertised: String,
    description: String,
    schema: Value,
}

#[async_trait]
impl Tool for McpTool {
    fn name(&self) -> &str {
        &self.advertised
    }

    fn description(&self) -> &str {
        &self.description
    }

    fn schema(&self) -> Value {
        self.schema.clone()
    }

    async fn invoke(&self, args: Value) -> Result<ToolOutput, ToolError> {
        let result = self
            .client
            .call_tool(&self.remote_name, args)
            .await
            .map_err(|e| ToolError::Execution(format!("mcp `{}`: {e}", self.advertised)))?;
        let content = result.render();
        // A tool-level `isError` is model-visible and recoverable — mirror it onto ToolOutput
        // rather than aborting the turn, exactly as the built-in tools do.
        Ok(if result.is_error {
            ToolOutput::error(content)
        } else {
            ToolOutput::ok(content)
        })
    }
}

// ---------------------------------------------------------------------------------------------
// Transport abstraction.
// ---------------------------------------------------------------------------------------------

/// A JSON-RPC 2.0 transport to an MCP server. Implementors own framing and (for bidirectional
/// transports) response demultiplexing; the [`McpClient`] above is transport-agnostic.
#[async_trait]
trait Transport: Send + Sync {
    /// Issue a request and await its matching response `result` (or map its `error`).
    async fn request(&self, method: &str, params: Value) -> Result<Value, McpError>;
    /// Fire a notification (no id, no response).
    async fn notify(&self, method: &str, params: Value) -> Result<(), McpError>;
}

type Pending = Arc<StdMutex<HashMap<u64, oneshot::Sender<Result<Value, McpError>>>>>;

/// A newline-delimited JSON-RPC transport over a byte reader + writer. Backs the stdio transport
/// (over a child's stdin/stdout) and is generic over the pipe so tests can drive it with an
/// in-memory duplex instead of a real process.
struct PipeTransport {
    writer: AsyncMutex<Box<dyn AsyncWrite + Unpin + Send>>,
    pending: Pending,
    next_id: AtomicU64,
    /// The child process, kept alive (and killed on drop) for the stdio transport; `None` in tests.
    _child: Option<Child>,
    /// The background reader task; aborted on drop.
    reader: tokio::task::JoinHandle<()>,
}

impl Drop for PipeTransport {
    fn drop(&mut self) {
        self.reader.abort();
    }
}

impl PipeTransport {
    /// Build a transport over an arbitrary reader/writer, spawning the demux reader task. `child`
    /// keeps a spawned process alive; pass `None` when the pipe is not process-backed.
    fn new(
        reader: Box<dyn AsyncRead + Unpin + Send>,
        writer: Box<dyn AsyncWrite + Unpin + Send>,
        child: Option<Child>,
    ) -> Self {
        let pending: Pending = Arc::new(StdMutex::new(HashMap::new()));
        let reader_pending = pending.clone();
        let handle = tokio::spawn(async move {
            let mut lines = BufReader::new(reader).lines();
            // Exit on EOF (`Ok(None)`) or any read error; both mean the pipe is gone.
            while let Ok(Some(line)) = lines.next_line().await {
                dispatch_line(&line, &reader_pending);
            }
            // The pipe closed: fail every outstanding request rather than let it hang to timeout.
            let mut map = reader_pending.lock().expect("mcp pending poisoned");
            for (_, tx) in map.drain() {
                let _ = tx.send(Err(McpError::Closed));
            }
        });
        Self {
            writer: AsyncMutex::new(writer),
            pending,
            next_id: AtomicU64::new(1),
            _child: child,
            reader: handle,
        }
    }

    async fn write_message(&self, msg: &Value) -> Result<(), McpError> {
        let mut line = serde_json::to_string(msg).expect("json-rpc message serializes");
        line.push('\n');
        let mut w = self.writer.lock().await;
        w.write_all(line.as_bytes())
            .await
            .map_err(|e| McpError::Io(e.to_string()))?;
        w.flush().await.map_err(|e| McpError::Io(e.to_string()))
    }
}

/// Route one inbound line to the waiting requester by id. Server-initiated requests/notifications
/// (no id we know) are ignored — this client exposes no roots/sampling.
fn dispatch_line(line: &str, pending: &Pending) {
    let line = line.trim();
    if line.is_empty() {
        return;
    }
    let msg: Value = match serde_json::from_str(line) {
        Ok(v) => v,
        Err(e) => {
            tracing::debug!(error = %e, "mcp: unparseable line");
            return;
        }
    };
    let Some(id) = msg.get("id").and_then(Value::as_u64) else {
        return;
    };
    let Some(tx) = pending.lock().expect("mcp pending poisoned").remove(&id) else {
        return;
    };
    let _ = tx.send(rpc_result(&msg));
}

/// Extract a JSON-RPC `result` (or map its `error`) from a response object.
fn rpc_result(msg: &Value) -> Result<Value, McpError> {
    if let Some(err) = msg.get("error") {
        let text = err
            .get("message")
            .and_then(Value::as_str)
            .map(str::to_string)
            .unwrap_or_else(|| err.to_string());
        return Err(McpError::Rpc(text));
    }
    Ok(msg.get("result").cloned().unwrap_or(Value::Null))
}

#[async_trait]
impl Transport for PipeTransport {
    async fn request(&self, method: &str, params: Value) -> Result<Value, McpError> {
        let id = self.next_id.fetch_add(1, Ordering::Relaxed);
        let (tx, rx) = oneshot::channel();
        self.pending
            .lock()
            .expect("mcp pending poisoned")
            .insert(id, tx);
        let msg = json!({ "jsonrpc": "2.0", "id": id, "method": method, "params": params });
        if let Err(e) = self.write_message(&msg).await {
            self.pending
                .lock()
                .expect("mcp pending poisoned")
                .remove(&id);
            return Err(e);
        }
        match tokio::time::timeout(REQUEST_TIMEOUT, rx).await {
            Ok(Ok(res)) => res,
            Ok(Err(_)) => Err(McpError::Closed),
            Err(_) => {
                self.pending
                    .lock()
                    .expect("mcp pending poisoned")
                    .remove(&id);
                Err(McpError::Timeout)
            }
        }
    }

    async fn notify(&self, method: &str, params: Value) -> Result<(), McpError> {
        let msg = json!({ "jsonrpc": "2.0", "method": method, "params": params });
        self.write_message(&msg).await
    }
}

/// The stdio transport: a child process wrapped in a [`PipeTransport`] over its stdin/stdout.
struct StdioTransport(PipeTransport);

impl StdioTransport {
    fn spawn(argv: &[String]) -> Result<Self, McpError> {
        let (cmd, args) = argv
            .split_first()
            .ok_or_else(|| McpError::BadSpec("empty command".into()))?;
        let mut child = tokio::process::Command::new(cmd)
            .args(args)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit())
            .kill_on_drop(true)
            .spawn()
            .map_err(|e| McpError::Spawn(format!("`{cmd}`: {e}")))?;
        let stdin = child
            .stdin
            .take()
            .ok_or_else(|| McpError::Spawn("no stdin pipe".into()))?;
        let stdout = child
            .stdout
            .take()
            .ok_or_else(|| McpError::Spawn("no stdout pipe".into()))?;
        Ok(Self(PipeTransport::new(
            Box::new(stdout),
            Box::new(stdin),
            Some(child),
        )))
    }
}

#[async_trait]
impl Transport for StdioTransport {
    async fn request(&self, method: &str, params: Value) -> Result<Value, McpError> {
        self.0.request(method, params).await
    }
    async fn notify(&self, method: &str, params: Value) -> Result<(), McpError> {
        self.0.notify(method, params).await
    }
}

/// The HTTP transport: POST each JSON-RPC message to a URL, accepting a JSON or SSE reply. Carries
/// any `Mcp-Session-Id` the server assigns on `initialize` (Streamable HTTP).
struct HttpTransport {
    client: reqwest::Client,
    url: String,
    next_id: AtomicU64,
    session_id: StdMutex<Option<String>>,
}

impl HttpTransport {
    fn new(url: &str) -> Result<Self, McpError> {
        let client = reqwest::Client::builder()
            .build()
            .map_err(|e| McpError::Http(e.to_string()))?;
        Ok(Self {
            client,
            url: url.to_string(),
            next_id: AtomicU64::new(1),
            session_id: StdMutex::new(None),
        })
    }

    async fn post(&self, msg: &Value, expect_reply: bool) -> Result<Value, McpError> {
        let mut req = self
            .client
            .post(&self.url)
            .header("content-type", "application/json")
            .header("accept", "application/json, text/event-stream");
        if let Some(sid) = self
            .session_id
            .lock()
            .expect("mcp session poisoned")
            .clone()
        {
            req = req.header("mcp-session-id", sid);
        }
        let resp = req
            .json(msg)
            .send()
            .await
            .map_err(|e| McpError::Http(e.to_string()))?;
        // A server may assign a session id on the initialize response; remember it for later posts.
        if let Some(sid) = resp.headers().get("mcp-session-id") {
            if let Ok(s) = sid.to_str() {
                *self.session_id.lock().expect("mcp session poisoned") = Some(s.to_string());
            }
        }
        let status = resp.status();
        let ctype = resp
            .headers()
            .get("content-type")
            .and_then(|v| v.to_str().ok())
            .unwrap_or("")
            .to_string();
        let body = resp
            .text()
            .await
            .map_err(|e| McpError::Http(e.to_string()))?;
        if !status.is_success() {
            return Err(McpError::Http(format!("HTTP {status}: {body}")));
        }
        if !expect_reply {
            return Ok(Value::Null);
        }
        let id = msg.get("id").and_then(Value::as_u64);
        parse_http_reply(&body, &ctype, id)
    }
}

/// Parse an HTTP JSON-RPC reply, whether a bare JSON object or a Streamable-HTTP SSE body. In an SSE
/// body the response rides a `data:` line; scan for the one whose `id` matches the request.
fn parse_http_reply(body: &str, content_type: &str, id: Option<u64>) -> Result<Value, McpError> {
    if content_type.contains("text/event-stream") {
        for line in body.lines() {
            let line = line.trim_start();
            let Some(data) = line.strip_prefix("data:") else {
                continue;
            };
            let Ok(msg) = serde_json::from_str::<Value>(data.trim()) else {
                continue;
            };
            if id.is_none() || msg.get("id").and_then(Value::as_u64) == id {
                return rpc_result(&msg);
            }
        }
        return Err(McpError::Protocol(
            "no JSON-RPC response in SSE body".into(),
        ));
    }
    let msg: Value =
        serde_json::from_str(body).map_err(|e| McpError::Protocol(format!("{e}: {body}")))?;
    rpc_result(&msg)
}

#[async_trait]
impl Transport for HttpTransport {
    async fn request(&self, method: &str, params: Value) -> Result<Value, McpError> {
        let id = self.next_id.fetch_add(1, Ordering::Relaxed);
        let msg = json!({ "jsonrpc": "2.0", "id": id, "method": method, "params": params });
        self.post(&msg, true).await
    }
    async fn notify(&self, method: &str, params: Value) -> Result<(), McpError> {
        let msg = json!({ "jsonrpc": "2.0", "method": method, "params": params });
        self.post(&msg, false).await.map(|_| ())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::io::split;

    #[test]
    fn parses_stdio_and_http_specs() {
        let s = McpServerSpec::parse("fs: npx -y server-filesystem .").unwrap();
        assert_eq!(s.label, "fs");
        assert_eq!(
            s.transport,
            TransportSpec::Stdio(vec![
                "npx".into(),
                "-y".into(),
                "server-filesystem".into(),
                ".".into()
            ])
        );

        let h = McpServerSpec::parse("remote: https://mcp.example.com/rpc").unwrap();
        assert_eq!(h.label, "remote");
        assert_eq!(
            h.transport,
            TransportSpec::Http("https://mcp.example.com/rpc".into())
        );
    }

    #[test]
    fn rejects_malformed_specs() {
        assert!(McpServerSpec::parse("no-colon").is_err());
        assert!(McpServerSpec::parse(": missing label").is_err());
        assert!(McpServerSpec::parse("empty:").is_err());
    }

    #[test]
    fn advertised_names_are_namespaced_and_sanitized() {
        assert_eq!(advertised_name("fs", "read_file"), "fs_read_file");
        // Illegal chars for the provider tool-name charset become underscores.
        assert_eq!(advertised_name("gh", "list/issues"), "gh_list_issues");
        // Over-long names are truncated to 64.
        assert!(advertised_name("x", &"a".repeat(200)).len() <= 64);
    }

    #[test]
    fn renders_content_blocks_and_falls_back_to_json() {
        let r = CallResult {
            content: vec![
                json!({"type": "text", "text": "hello"}),
                json!({"type": "text", "text": "world"}),
                json!({"type": "image", "data": "…"}),
            ],
            is_error: false,
        };
        let out = r.render();
        assert!(out.contains("hello"));
        assert!(out.contains("world"));
        // Non-text block is preserved as JSON rather than dropped.
        assert!(out.contains("image"));
    }

    #[test]
    fn parses_http_json_and_sse_replies() {
        // Bare JSON reply.
        let v = parse_http_reply(
            r#"{"jsonrpc":"2.0","id":1,"result":{"ok":true}}"#,
            "application/json",
            Some(1),
        )
        .unwrap();
        assert_eq!(v, json!({"ok": true}));
        // SSE reply: the response rides a `data:` line.
        let sse = "event: message\ndata: {\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"n\":5}}\n\n";
        let v = parse_http_reply(sse, "text/event-stream", Some(2)).unwrap();
        assert_eq!(v, json!({"n": 5}));
        // A JSON-RPC error object maps to McpError::Rpc.
        let err = parse_http_reply(
            r#"{"jsonrpc":"2.0","id":1,"error":{"code":-32601,"message":"nope"}}"#,
            "application/json",
            Some(1),
        );
        assert!(matches!(err, Err(McpError::Rpc(m)) if m == "nope"));
    }

    /// A minimal in-process MCP server driven over a duplex pipe: it answers `initialize`,
    /// `tools/list`, and `tools/call`, and swallows the `notifications/initialized` notification.
    /// This exercises the *real* stdio framing/demux path offline (no child process).
    async fn mock_server(
        reader: impl AsyncRead + Unpin + Send,
        mut writer: impl AsyncWrite + Unpin + Send,
    ) {
        let mut lines = BufReader::new(reader).lines();
        while let Ok(Some(line)) = lines.next_line().await {
            if line.trim().is_empty() {
                continue;
            }
            let msg: Value = serde_json::from_str(&line).unwrap();
            let id = msg.get("id").and_then(Value::as_u64);
            let method = msg.get("method").and_then(Value::as_str).unwrap_or("");
            // Notifications carry no id and expect no reply.
            let Some(id) = id else { continue };
            let result = match method {
                "initialize" => json!({"protocolVersion": PROTOCOL_VERSION, "capabilities": {}}),
                "tools/list" => json!({"tools": [
                    {"name": "echo", "description": "echo back", "inputSchema": {"type": "object"}}
                ]}),
                "tools/call" => {
                    let args = &msg["params"]["arguments"];
                    let text = args.get("text").and_then(Value::as_str).unwrap_or("");
                    json!({"content": [{"type": "text", "text": text}], "isError": false})
                }
                _ => json!(null),
            };
            let mut out =
                serde_json::to_string(&json!({"jsonrpc": "2.0", "id": id, "result": result}))
                    .unwrap();
            out.push('\n');
            writer.write_all(out.as_bytes()).await.unwrap();
            writer.flush().await.unwrap();
        }
    }

    fn pipe_client(label: &str) -> Arc<McpClient> {
        let (client_end, server_end) = tokio::io::duplex(8192);
        let (sr, sw) = split(server_end);
        tokio::spawn(async move { mock_server(sr, sw).await });
        let (cr, cw) = split(client_end);
        let transport = PipeTransport::new(Box::new(cr), Box::new(cw), None);
        Arc::new(McpClient::new(label.to_string(), Box::new(transport)))
    }

    #[tokio::test]
    async fn discovers_and_invokes_tools_over_a_real_pipe() {
        let client = pipe_client("fs");
        client.initialize().await.unwrap();
        let tools = client.list_tools().await.unwrap();
        assert_eq!(tools.len(), 1);
        assert_eq!(tools[0].name, "echo");

        let result = client
            .call_tool("echo", json!({"text": "hi there"}))
            .await
            .unwrap();
        assert!(!result.is_error);
        assert_eq!(result.render(), "hi there");
    }

    #[tokio::test]
    async fn adapter_maps_a_call_into_a_tooloutput() {
        // Build the McpTool adapter the way `connect_tools` does and invoke through the Tool trait.
        let client = pipe_client("fs");
        client.initialize().await.unwrap();
        let tool = McpTool {
            client,
            remote_name: "echo".into(),
            advertised: advertised_name("fs", "echo"),
            description: "echo".into(),
            schema: json!({"type": "object"}),
        };
        assert_eq!(tool.name(), "fs_echo");
        let out = tool.invoke(json!({"text": "pong"})).await.unwrap();
        assert!(!out.is_error);
        assert_eq!(out.content, "pong");
    }

    #[tokio::test]
    async fn a_closed_pipe_fails_pending_requests() {
        // A server that answers nothing and drops immediately: the request must resolve to Closed,
        // not hang until the timeout.
        let (client_end, server_end) = tokio::io::duplex(64);
        drop(server_end);
        let (cr, cw) = split(client_end);
        let transport = PipeTransport::new(Box::new(cr), Box::new(cw), None);
        let client = McpClient::new("dead".into(), Box::new(transport));
        // Either the reader drains pending (Closed) or the write hits a broken pipe (Io) — the
        // point is it fails fast rather than hanging until REQUEST_TIMEOUT.
        assert!(matches!(
            client.initialize().await,
            Err(McpError::Closed) | Err(McpError::Io(_))
        ));
    }
}
