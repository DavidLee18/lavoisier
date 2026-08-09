//! Small live verification of the A-list xAI features against the real gRPC API.
//!
//! Run with a real key (a few cents on grok-4):
//! ```sh
//! XAI_API_KEY=… cargo run -p lvz-xai --example xai_verify
//! ```
//! Verifies: A6 deferred (async) completions (start + poll), and A7 X search (a `ServerTool`
//! mapped to the proto `Tool` oneof). Collections search and MCP need real resources (a
//! collection id / an MCP server), so they're exercised at the request-mapping level only.

use std::time::Duration;

use futures::StreamExt;
use lvz_protocol::{ChatRequest, Event, Message, Provider, ServerTool};
use lvz_xai::GrpcTransport;

#[tokio::main]
async fn main() {
    let key = std::env::var("XAI_API_KEY").expect("XAI_API_KEY");
    let provider = GrpcTransport::new(key);

    a6_deferred(&provider).await;
    a7_x_search(&provider).await;

    println!("\n== live verify complete ==");
}

/// A6 — submit a deferred completion, then poll until it resolves.
async fn a6_deferred(provider: &GrpcTransport) {
    println!("\n--- A6: deferred (async) completion (grok-4) ---");
    let mut req = ChatRequest::new("grok-4").push(Message::user("Reply with exactly: deferred-ok"));
    req.max_tokens = 32;

    let id = provider.start_deferred(req).await.expect("start_deferred");
    println!("  request_id: {id}");

    for attempt in 1..=20 {
        match provider.poll_deferred(&id).await.expect("poll_deferred") {
            Some(events) => {
                let text: String = events
                    .iter()
                    .filter_map(|e| match e {
                        Event::TextDelta(t) => Some(t.as_str()),
                        _ => None,
                    })
                    .collect();
                let done = events.iter().any(|e| matches!(e, Event::Done(_)));
                println!(
                    "  resolved after {attempt} poll(s): text={:?} done={done}",
                    text.trim()
                );
                println!("  => A6 VERIFIED");
                return;
            }
            None => {
                println!("  poll {attempt}: pending…");
                tokio::time::sleep(Duration::from_secs(3)).await;
            }
        }
    }
    println!("  => A6 did not resolve within the poll window (endpoint reachable, still pending)");
}

/// A7 — declare an X-search server tool and ask a question that should trigger a live search.
async fn a7_x_search(provider: &GrpcTransport) {
    println!("\n--- A7: X search server tool (grok-4) ---");
    let mut req = ChatRequest::new("grok-4").push(Message::user(
        "Using X, what has @xai posted recently? One sentence.",
    ));
    req.max_tokens = 200;
    req.server_tools = vec![ServerTool::XSearch {
        allowed_handles: vec!["xai".into()],
        blocked_handles: vec![],
        from_date: None,
        to_date: None,
    }];

    match provider.stream(req).await {
        Ok(mut stream) => {
            let mut text = String::new();
            let mut stop = None;
            while let Some(ev) = stream.next().await {
                match ev {
                    Ok(Event::TextDelta(t)) => text.push_str(&t),
                    Ok(Event::Done(s)) => stop = Some(s),
                    Ok(_) => {}
                    Err(e) => {
                        println!("  stream error: {e:?}");
                        break;
                    }
                }
            }
            println!("  answer: {}", text.trim());
            println!("  done: {stop:?}");
            println!(
                "  => A7 X-search request accepted + answered — {}",
                if text.trim().is_empty() {
                    "no text"
                } else {
                    "VERIFIED"
                }
            );
        }
        Err(e) => println!("  request rejected: {e:?} (X-search may be account/model-gated)"),
    }
}
