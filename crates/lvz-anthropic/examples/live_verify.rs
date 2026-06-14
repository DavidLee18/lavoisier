//! Small live verification of the A-list Anthropic features against the real Messages API.
//!
//! Run with a real key (a few cents on Haiku + Sonnet):
//! ```sh
//! ANTHROPIC_API_KEY=… cargo run -p lvz-anthropic --example live_verify
//! ```
//! Verifies: A3 response-side document citations, A4 builtin tools (bash/text_editor/memory
//! declarations accepted + a bash tool_use), and A5 batch list/create/get/cancel.

use futures::StreamExt;
use lvz_anthropic::batch::BatchRequest;
use lvz_anthropic::AnthropicProvider;
use lvz_protocol::{BuiltinTool, ChatRequest, ContentBlock, Event, MediaSource, Message, Provider};

#[tokio::main]
async fn main() {
    let provider = AnthropicProvider::from_env().expect("ANTHROPIC_API_KEY");

    a3_citations(&provider).await;
    a4_builtin_tools(&provider).await;
    a5_batch(&provider).await;

    println!("\n== live verify complete ==");
}

/// A3 — attach a plain-text document with `citations: true`; expect `Event::Citation` deltas.
/// Uses the `MediaSource::PlainText` source (no PDF needed).
async fn a3_citations(provider: &AnthropicProvider) {
    println!("\n--- A3: response-side citations, plain-text doc (haiku) ---");
    let doc = ContentBlock::Document {
        source: MediaSource::PlainText {
            text: "The Lavoisier mascot is a blue otter named Pascal, adopted in 2026.".into(),
        },
        citations: true,
    };
    let msg = Message {
        role: lvz_protocol::Role::User,
        content: vec![
            doc,
            ContentBlock::text(
                "What is the name of the mascot? Answer briefly and cite the document.",
            ),
        ],
    };
    let mut req = ChatRequest::new("claude-haiku-4-5").push(msg);
    req.max_tokens = 300;

    let mut stream = provider.stream(req).await.expect("stream");
    let (mut text, mut citations) = (String::new(), 0u32);
    while let Some(ev) = stream.next().await {
        match ev.expect("event") {
            Event::TextDelta(t) => text.push_str(&t),
            Event::Citation { cited_text, source } => {
                citations += 1;
                println!("  citation[{source}]: {cited_text:?}");
            }
            Event::Usage(u) => println!("  usage: in={} out={}", u.input_tokens, u.output_tokens),
            Event::Done(s) => println!("  done: {s:?}"),
            _ => {}
        }
    }
    println!("  answer: {}", text.trim());
    println!(
        "  => {} citation event(s) — A3 {}",
        citations,
        if citations > 0 {
            "VERIFIED"
        } else {
            "NO CITATIONS"
        }
    );
}

/// A4 — declare bash + text_editor + memory; expect a `bash` tool_use and a 200 (beta accepted).
async fn a4_builtin_tools(provider: &AnthropicProvider) {
    println!("\n--- A4: builtin tools (sonnet) ---");
    let mut req = ChatRequest::new("claude-sonnet-4-6").push(Message::user(
        "Use the bash tool to run `echo hello`. Do not explain.",
    ));
    req.max_tokens = 300;
    req.builtin_tools = vec![
        BuiltinTool::Bash,
        BuiltinTool::TextEditor,
        BuiltinTool::Memory,
    ];

    let mut stream = provider
        .stream(req)
        .await
        .expect("stream (builtin tools accepted = 200)");
    let mut tool_names = Vec::new();
    while let Some(ev) = stream.next().await {
        match ev.expect("event") {
            Event::ToolUseStart { name, .. } => {
                println!("  tool_use: {name}");
                tool_names.push(name);
            }
            Event::Done(s) => println!("  done: {s:?}"),
            _ => {}
        }
    }
    let bash = tool_names.iter().any(|n| n == "bash");
    println!(
        "  => request accepted (beta ok); bash tool_use seen={bash} — A4 {}",
        if bash {
            "VERIFIED"
        } else {
            "declared+accepted (no bash call)"
        }
    );
}

/// A5 — exercise the batch list/create/get/cancel endpoints (one tiny Haiku request).
async fn a5_batch(provider: &AnthropicProvider) {
    println!("\n--- A5: batch list / create / get / cancel (haiku) ---");
    let page = provider
        .list_batches(Some(5), None)
        .await
        .expect("list_batches");
    println!(
        "  list: {} batch(es), has_more={}, cursor={:?}",
        page.batches.len(),
        page.has_more,
        page.last_id
    );

    let mut req = ChatRequest::new("claude-haiku-4-5").push(Message::user("Reply with: ok"));
    req.max_tokens = 16;
    let batch = provider
        .create_batch(&[BatchRequest {
            custom_id: "verify-1".into(),
            request: req,
        }])
        .await
        .expect("create_batch");
    println!(
        "  created: id={} status={}",
        batch.id, batch.processing_status
    );

    let got = provider.get_batch(&batch.id).await.expect("get_batch");
    println!("  get: status={}", got.processing_status);

    let canceled = provider
        .cancel_batch(&batch.id)
        .await
        .expect("cancel_batch");
    println!("  cancel: status={}", canceled.processing_status);
    println!("  => A5 VERIFIED (list/create/get/cancel all responded)");
}
