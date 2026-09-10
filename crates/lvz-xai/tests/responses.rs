//! Fixture-driven tests for the xAI Responses transport.
//!
//! `tests/fixtures/xai-responses-*.sse` are **recorded live streams**. xAI documents the Responses
//! request body but not its streaming events, so these recordings — not the docs — are the
//! decoder's specification. If the wire moves, re-record rather than guess.

use lvz_protocol::{Event, StopReason};
use lvz_xai::ResponsesTransport;

/// Drive the real provider `stream()` against a local server replaying a recorded fixture, so the
/// test exercises the same path a live call takes (negotiation, HTTP, decoder) rather than poking
/// at the decoder directly.
async fn events_from_fixture(fixture: &str) -> Vec<Event> {
    use std::net::SocketAddr;
    use tokio::io::AsyncWriteExt;
    use tokio::net::TcpListener;

    let body = std::fs::read_to_string(format!(
        "{}/tests/fixtures/{fixture}",
        env!("CARGO_MANIFEST_DIR")
    ))
    .expect("fixture must exist");

    let listener = TcpListener::bind::<SocketAddr>("127.0.0.1:0".parse().unwrap())
        .await
        .unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        let (mut sock, _) = listener.accept().await.unwrap();
        // Read the request headers so the client's write completes, then reply with the recording.
        let mut buf = [0u8; 8192];
        let _ = tokio::io::AsyncReadExt::read(&mut sock, &mut buf).await;
        let head = format!(
            "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nContent-Length: {}\r\n\r\n",
            body.len()
        );
        sock.write_all(head.as_bytes()).await.unwrap();
        sock.write_all(body.as_bytes()).await.unwrap();
        sock.flush().await.unwrap();
    });

    let provider = ResponsesTransport::with_base_url("test-key", format!("http://{addr}/v1"));
    let mut req = lvz_protocol::ChatRequest::new("grok-4.6");
    req.messages = vec![lvz_protocol::Message::user("hi")];
    let mut stream = <ResponsesTransport as lvz_protocol::Provider>::stream(&provider, req)
        .await
        .expect("stream must open");
    let mut out = Vec::new();
    use futures::StreamExt;
    while let Some(ev) = stream.next().await {
        out.push(ev.expect("no decode errors in a recorded stream"));
    }
    out
}

#[tokio::test]
async fn tool_call_echoes_the_call_id_not_the_item_id() {
    // THE trap this transport carries: the stream reports two ids per tool call. `id` (`fc_…`)
    // correlates the argument deltas; `call_id` (`call-…`) is what must be echoed back on the
    // result. They are different strings, and emitting the item id yields a tool result the
    // provider cannot match — the loop then stalls with no error to explain why.
    let events = events_from_fixture("xai-responses-toolcall.sse").await;

    let call_id = "call-055b61a7-eb60-4674-a42a-e910871fd1c3-0";
    let item_id = "fc_16d1dacd-2732-9d47-a131-d6e1e83b4981_0";

    let starts: Vec<_> = events
        .iter()
        .filter_map(|e| match e {
            Event::ToolUseStart { id, name } => Some((id.as_str(), name.as_str())),
            _ => None,
        })
        .collect();
    assert_eq!(starts, vec![(call_id, "read_file")], "{events:?}");

    // The delta frame is keyed by item_id on the wire; it must come out under the call id.
    let deltas: Vec<_> = events
        .iter()
        .filter_map(|e| match e {
            Event::ToolUseDelta { id, json } => Some((id.as_str(), json.as_str())),
            _ => None,
        })
        .collect();
    assert_eq!(
        deltas,
        vec![(call_id, r#"{"path":"notes.txt"}"#)],
        "{events:?}"
    );

    let ends: Vec<_> = events
        .iter()
        .filter_map(|e| match e {
            Event::ToolUseEnd { id } => Some(id.as_str()),
            _ => None,
        })
        .collect();
    assert_eq!(ends, vec![call_id], "{events:?}");

    // And the item id must appear nowhere in the emitted stream.
    let rendered = format!("{events:?}");
    assert!(
        !rendered.contains(item_id),
        "the fc_ item id leaked into the event stream: {rendered}"
    );
}

#[tokio::test]
async fn a_turn_that_called_a_tool_ends_as_tool_use() {
    let events = events_from_fixture("xai-responses-toolcall.sse").await;
    match events.last() {
        Some(Event::Done(StopReason::ToolUse)) => {}
        other => panic!("expected Done(ToolUse), got {other:?}"),
    }
}

#[tokio::test]
async fn usage_is_read_from_the_response_envelope() {
    let events = events_from_fixture("xai-responses-toolcall.sse").await;
    let usage = events
        .iter()
        .find_map(|e| match e {
            Event::Usage(u) => Some(u),
            _ => None,
        })
        .expect("a completed response carries usage");
    assert_eq!(usage.input_tokens, 716);
    assert_eq!(usage.output_tokens, 44);
    // input_tokens_details.cached_tokens is the cache READ; xAI has no cache-creation counter,
    // which is also why this transport declares no PromptCaching.
    assert_eq!(usage.cache_read_tokens, 512);
    assert_eq!(usage.cache_creation_tokens, 0);
}

#[tokio::test]
async fn text_thinking_citations_and_server_tools_decode() {
    let events = events_from_fixture("xai-responses-stream.sse").await;

    let text: String = events
        .iter()
        .filter_map(|e| match e {
            Event::TextDelta(t) => Some(t.as_str()),
            _ => None,
        })
        .collect();
    assert!(!text.is_empty(), "expected answer text: {events:?}");

    let thinking: String = events
        .iter()
        .filter_map(|e| match e {
            Event::Thinking(t) => Some(t.as_str()),
            _ => None,
        })
        .collect();
    assert!(!thinking.is_empty(), "expected a reasoning summary");

    let citations: Vec<_> = events
        .iter()
        .filter_map(|e| match e {
            Event::Citation { source, .. } => Some(source.as_str()),
            _ => None,
        })
        .collect();
    assert!(
        citations.iter().any(|s| s.starts_with("https://")),
        "expected url citations, got {citations:?}"
    );

    // The provider-run web search must surface as a ServerToolUse/ServerToolResult pair sharing an
    // id, so a frontend can show that a search happened.
    let uses: Vec<_> = events
        .iter()
        .filter_map(|e| match e {
            Event::ServerToolUse { id, name } => Some((id.as_str(), name.as_str())),
            _ => None,
        })
        .collect();
    assert!(
        uses.iter().any(|(_, n)| *n == "web_search"),
        "expected a web_search ServerToolUse, got {uses:?}"
    );
    let results: Vec<_> = events
        .iter()
        .filter_map(|e| match e {
            Event::ServerToolResult { id, .. } => Some(id.as_str()),
            _ => None,
        })
        .collect();
    for (id, _) in &uses {
        assert!(
            results.contains(id),
            "server tool {id} was opened but never closed: {results:?}"
        );
    }

    match events.last() {
        Some(Event::Done(StopReason::EndTurn)) => {}
        other => panic!("a turn with no function call ends as EndTurn, got {other:?}"),
    }
}
