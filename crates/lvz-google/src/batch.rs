//! Gemini **Batch Mode** (`models/{model}:batchGenerateContent`) — asynchronous bulk generation
//! at **50% of interactive pricing**. You submit many requests inline, poll the returned
//! long-running operation until it finishes, then read the per-request inline responses. Like the
//! Anthropic batch path, this is for non-interactive workloads (offline evals, bulk classification).

use lvz_protocol::{ChatRequest, ProviderError, Usage};
use serde_json::{json, Value};

use crate::{build_body, GoogleProvider};

/// One entry in a batch: a caller-chosen `custom_id` (echoed back to correlate the result) and the
/// request. All requests in a batch share the batch's `model` (passed to [`create_batch`]).
pub struct BatchRequest {
    pub custom_id: String,
    pub request: ChatRequest,
}

/// A submitted/queried batch (the underlying long-running operation).
#[derive(Debug, Clone)]
pub struct Batch {
    /// The operation/batch resource name (`batches/...`) used to poll and read results.
    pub name: String,
    /// The batch state, e.g. `BATCH_STATE_PENDING`/`BATCH_STATE_RUNNING`/`BATCH_STATE_SUCCEEDED`.
    pub state: String,
    /// True once the operation has finished (results available, or terminal failure).
    pub done: bool,
}

impl Batch {
    /// True once results can be read.
    pub fn succeeded(&self) -> bool {
        self.state == "BATCH_STATE_SUCCEEDED"
    }
}

/// The per-request outcome read from a finished batch.
#[derive(Debug, Clone)]
pub struct BatchResult {
    pub custom_id: String,
    pub outcome: BatchOutcome,
}

/// What happened to a single batched request.
#[derive(Debug, Clone)]
pub enum BatchOutcome {
    /// Completed: the concatenated answer text and the turn's usage.
    Succeeded { text: String, usage: Usage },
    /// The request errored; carries the error message.
    Errored(String),
}

impl GoogleProvider {
    /// Submit a batch of generation requests for `model`. Returns the batch resource name + state;
    /// poll [`get_batch`](Self::get_batch) until [`Batch::succeeded`], then read
    /// [`batch_results`](Self::batch_results).
    pub async fn create_batch(
        &self,
        model: &str,
        requests: &[BatchRequest],
    ) -> Result<Batch, ProviderError> {
        let inlined: Vec<Value> = requests
            .iter()
            .map(|r| {
                json!({
                    "request": build_body(
                        &r.request,
                        self.thinking.as_deref(),
                        self.cached_content.as_deref(),
                    ),
                    "metadata": { "key": r.custom_id },
                })
            })
            .collect();
        let body = json!({
            "batch": {
                "display_name": "lavoisier-batch",
                "input_config": { "requests": { "requests": inlined } },
            }
        });
        let url = format!(
            "{}/v1beta/models/{model}:batchGenerateContent",
            self.base_url.trim_end_matches('/')
        );
        let v = self.batch_send(self.http.post(url).json(&body)).await?;
        Ok(parse_batch(&v))
    }

    /// Fetch a batch's current state by its resource name (`batches/...`).
    pub async fn get_batch(&self, name: &str) -> Result<Batch, ProviderError> {
        let url = format!("{}/v1beta/{name}", self.base_url.trim_end_matches('/'));
        let v = self.batch_send(self.http.get(url)).await?;
        Ok(parse_batch(&v))
    }

    /// Read a finished batch's per-request results, correlated by the `custom_id` each carried.
    pub async fn batch_results(&self, name: &str) -> Result<Vec<BatchResult>, ProviderError> {
        let url = format!("{}/v1beta/{name}", self.base_url.trim_end_matches('/'));
        let v = self.batch_send(self.http.get(url)).await?;
        Ok(parse_results(&v))
    }

    async fn batch_send(&self, builder: reqwest::RequestBuilder) -> Result<Value, ProviderError> {
        let resp = builder
            .header("x-goog-api-key", &self.api_key)
            .send()
            .await
            .map_err(|e| ProviderError::Transport(e.to_string()))?;
        let status = resp.status();
        if !status.is_success() {
            return Err(ProviderError::Api {
                status: status.as_u16(),
                message: resp.text().await.unwrap_or_default(),
            });
        }
        resp.json()
            .await
            .map_err(|e| ProviderError::Decode(e.to_string()))
    }
}

fn parse_batch(v: &Value) -> Batch {
    Batch {
        name: v["name"].as_str().unwrap_or_default().to_string(),
        state: v["metadata"]["state"]
            .as_str()
            .or_else(|| v["metadata"]["batchStats"]["state"].as_str())
            .unwrap_or_default()
            .to_string(),
        done: v["done"].as_bool().unwrap_or(false),
    }
}

fn parse_results(v: &Value) -> Vec<BatchResult> {
    let inlined = v["response"]["inlinedResponses"]["inlinedResponses"]
        .as_array()
        .cloned()
        .unwrap_or_default();
    inlined.iter().map(parse_one_result).collect()
}

fn parse_one_result(v: &Value) -> BatchResult {
    let custom_id = v["metadata"]["key"]
        .as_str()
        .unwrap_or_default()
        .to_string();
    let outcome = if let Some(err) = v.get("error").filter(|e| !e.is_null()) {
        BatchOutcome::Errored(
            err["message"]
                .as_str()
                .unwrap_or("unknown error")
                .to_string(),
        )
    } else {
        let response = &v["response"];
        let text = response["candidates"][0]["content"]["parts"]
            .as_array()
            .map(|parts| {
                parts
                    .iter()
                    .filter_map(|p| p["text"].as_str())
                    .collect::<String>()
            })
            .unwrap_or_default();
        BatchOutcome::Succeeded {
            text,
            usage: usage_from_metadata(&response["usageMetadata"]),
        }
    };
    BatchResult { custom_id, outcome }
}

/// Map Gemini `usageMetadata` onto [`Usage`] (matching the streaming decoder's semantics).
fn usage_from_metadata(meta: &Value) -> Usage {
    let prompt = meta["promptTokenCount"].as_u64().unwrap_or(0);
    let cached = meta["cachedContentTokenCount"].as_u64().unwrap_or(0);
    let candidates = meta["candidatesTokenCount"].as_u64().unwrap_or(0);
    let thoughts = meta["thoughtsTokenCount"].as_u64().unwrap_or(0);
    Usage {
        input_tokens: prompt.saturating_sub(cached),
        output_tokens: candidates + thoughts,
        cache_creation_tokens: 0,
        cache_read_tokens: cached,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_batch_operation_state() {
        let op = json!({
            "name": "batches/abc",
            "metadata": { "state": "BATCH_STATE_SUCCEEDED" },
            "done": true
        });
        let b = parse_batch(&op);
        assert_eq!(b.name, "batches/abc");
        assert!(b.done);
        assert!(b.succeeded());
    }

    #[test]
    fn parses_inline_results_text_error_and_usage() {
        let op = json!({
            "response": { "inlinedResponses": { "inlinedResponses": [
                {
                    "metadata": { "key": "task-1" },
                    "response": {
                        "candidates": [{ "content": { "parts": [{ "text": "hello" }] } }],
                        "usageMetadata": { "promptTokenCount": 10, "cachedContentTokenCount": 4, "candidatesTokenCount": 3 }
                    }
                },
                {
                    "metadata": { "key": "task-2" },
                    "error": { "message": "boom" }
                }
            ] } }
        });
        let results = parse_results(&op);
        assert_eq!(results.len(), 2);
        assert_eq!(results[0].custom_id, "task-1");
        match &results[0].outcome {
            BatchOutcome::Succeeded { text, usage } => {
                assert_eq!(text, "hello");
                assert_eq!(usage.input_tokens, 6);
                assert_eq!(usage.cache_read_tokens, 4);
                assert_eq!(usage.output_tokens, 3);
            }
            other => panic!("expected succeeded, got {other:?}"),
        }
        match &results[1].outcome {
            BatchOutcome::Errored(msg) => assert_eq!(msg, "boom"),
            other => panic!("expected errored, got {other:?}"),
        }
    }
}
