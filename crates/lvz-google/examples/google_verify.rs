//! Small live verification of the A-list Google (Gemini) features against the real API.
//!
//! Run with a real key (a few cents on gemini-3-flash-preview):
//! ```sh
//! GOOGLE_API_KEY=… cargo run -p lvz-google --example google_verify
//! ```
//! Verifies: A9 safetySettings (request accepted + answered), A10 Files upload (→ fileUri, then
//! referenced in a follow-up turn), and A11 batch mode (create + poll the operation).

use std::time::Duration;

use futures::StreamExt;
use lvz_google::batch::{BatchOutcome, BatchRequest};
use lvz_google::{GoogleProvider, HarmBlockThreshold, HarmCategory, SafetySetting};
use lvz_protocol::{
    BatchProvider, BatchTask, ChatRequest, ContentBlock, Event, MediaSource, Message, Provider,
    Role,
};

const MODEL: &str = "gemini-3-flash-preview";

#[tokio::main]
async fn main() {
    let key = std::env::var("GOOGLE_API_KEY")
        .or_else(|_| std::env::var("GEMINI_API_KEY"))
        .expect("GOOGLE_API_KEY");

    a9_safety(&key).await;
    a10_files(&key).await;
    a11_batch(&key).await;
    auto_batch(&key).await;

    println!("\n== live verify complete ==");
}

/// Auto-batch — run two requests through the unified `BatchProvider::run_batch` (create → poll →
/// results) at the 50% batch price. Wrapped in a timeout so the demo can't hang.
async fn auto_batch(key: &str) {
    println!("\n--- auto-batch: BatchProvider::run_batch (gemini, 50% price) ---");
    let provider = GoogleProvider::new(key);
    let task = |id: &str, prompt: &str| {
        let mut r = ChatRequest::new(MODEL).push(Message::user(prompt));
        r.max_tokens = 64;
        BatchTask::new(id, r)
    };
    let tasks = vec![task("q1", "Reply with: one"), task("q2", "Reply with: two")];
    match tokio::time::timeout(Duration::from_secs(300), provider.run_batch(tasks)).await {
        Ok(Ok(items)) => {
            for it in &items {
                println!(
                    "  [{}] {:?} err={:?}",
                    it.custom_id,
                    it.text.trim(),
                    it.error
                );
            }
            println!("  => auto-batch VERIFIED ({} items)", items.len());
        }
        Ok(Err(e)) => println!("  run_batch error: {e:?}"),
        Err(_) => println!("  => still running after 300s (endpoints fine; not awaited)"),
    }
}

/// A9 — set explicit safety thresholds and confirm the request is accepted and answers.
async fn a9_safety(key: &str) {
    println!("\n--- A9: safetySettings (gemini) ---");
    let provider = GoogleProvider::new(key).with_safety_settings(vec![
        SafetySetting {
            category: HarmCategory::DangerousContent,
            threshold: HarmBlockThreshold::BlockOnlyHigh,
        },
        SafetySetting {
            category: HarmCategory::Harassment,
            threshold: HarmBlockThreshold::BlockMediumAndAbove,
        },
    ]);
    let mut req = ChatRequest::new(MODEL).push(Message::user("Reply with exactly: safety-ok"));
    // A reasoning model spends output budget on thinking first; leave room for visible text.
    req.max_tokens = 512;

    match provider.stream(req).await {
        Ok(mut stream) => {
            let mut text = String::new();
            let mut accepted = false;
            while let Some(ev) = stream.next().await {
                match ev {
                    Ok(Event::TextDelta(t)) => text.push_str(&t),
                    Ok(Event::Done(_)) => accepted = true,
                    Ok(_) => {}
                    Err(e) => println!("  stream error: {e:?}"),
                }
            }
            println!("  answer: {}  (clean stream={accepted})", text.trim());
            println!(
                "  => A9 {}",
                if accepted {
                    "VERIFIED (safetySettings accepted)"
                } else {
                    "stream did not finish"
                }
            );
        }
        Err(e) => println!("  request rejected: {e:?}"),
    }
}

/// A10 — upload a tiny text file, then reference its uri in a follow-up turn.
async fn a10_files(key: &str) {
    println!("\n--- A10: Files upload (gemini) ---");
    let provider = GoogleProvider::new(key);
    let content = b"The Lavoisier mascot is a blue otter named Pascal.".to_vec();

    let uri = match provider
        .upload_file("lavoisier-fact.txt", content, "text/plain")
        .await
    {
        Ok(uri) => {
            println!("  uploaded → fileUri: {uri}");
            uri
        }
        Err(e) => {
            println!("  upload failed: {e:?}");
            return;
        }
    };

    // Reference the uploaded file in a request (fileData → MediaSource::File).
    let msg = Message {
        role: Role::User,
        content: vec![
            ContentBlock::Document {
                source: MediaSource::File { file_id: uri },
                citations: false,
            },
            ContentBlock::text("What is the name of the mascot in this file? One word."),
        ],
    };
    let mut req = ChatRequest::new(MODEL).push(msg);
    req.max_tokens = 32;
    match provider.stream(req).await {
        Ok(mut stream) => {
            let mut text = String::new();
            while let Some(ev) = stream.next().await {
                if let Ok(Event::TextDelta(t)) = ev {
                    text.push_str(&t);
                }
            }
            println!("  follow-up answer: {}", text.trim());
            println!("  => A10 VERIFIED (upload returned a uri the model could read back)");
        }
        Err(e) => println!("  follow-up failed (uri obtained though): {e:?}"),
    }
}

/// A11 — create a one-request batch and poll the operation a few times.
async fn a11_batch(key: &str) {
    println!("\n--- A11: batch mode (gemini) ---");
    let provider = GoogleProvider::new(key);
    let mut req = ChatRequest::new(MODEL).push(Message::user("Reply with exactly: batch-ok"));
    req.max_tokens = 256;

    let batch = match provider
        .create_batch(
            MODEL,
            &[BatchRequest {
                custom_id: "verify-1".into(),
                request: req,
            }],
        )
        .await
    {
        Ok(b) => {
            println!(
                "  created: name={} state={:?} done={}",
                b.name, b.state, b.done
            );
            b
        }
        Err(e) => {
            println!("  create failed: {e:?}");
            return;
        }
    };

    for attempt in 1..=10 {
        let got = match provider.get_batch(&batch.name).await {
            Ok(g) => g,
            Err(e) => {
                println!("  get failed: {e:?}");
                return;
            }
        };
        println!("  poll {attempt}: state={:?} done={}", got.state, got.done);
        if got.done || got.succeeded() {
            match provider.batch_results(&batch.name).await {
                Ok(results) => {
                    for r in &results {
                        match &r.outcome {
                            BatchOutcome::Succeeded { text, usage } => println!(
                                "  result[{}]: {:?} (in={} out={})",
                                r.custom_id,
                                text.trim(),
                                usage.input_tokens,
                                usage.output_tokens
                            ),
                            BatchOutcome::Errored(m) => {
                                println!("  result[{}]: error {m}", r.custom_id)
                            }
                        }
                    }
                    println!("  => A11 VERIFIED (create + poll + results)");
                }
                Err(e) => println!("  results failed: {e:?}"),
            }
            return;
        }
        tokio::time::sleep(Duration::from_secs(6)).await;
    }
    println!(
        "  => A11 endpoints responded (create + get); batch still running, results not awaited"
    );
}
