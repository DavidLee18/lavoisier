//! Anthropic **Message Batches** API (`/v1/messages/batches`) — asynchronous bulk completion at
//! **50% of standard pricing**. Distinct from the streaming [`Provider`](lvz_protocol::Provider)
//! path: you submit many requests, poll until the batch ends, then fetch the JSONL results. Best
//! for non-interactive workloads (offline evals, the benchmark suite, bulk classification).

use std::time::Duration;

use async_trait::async_trait;
use lvz_protocol::{BatchItem, BatchProvider, BatchTask, ChatRequest, ProviderError, Usage};
use serde_json::{json, Value};

use crate::{build_body, AnthropicProvider, ANTHROPIC_VERSION};

/// How often [`BatchProvider::run_batch`] polls for completion.
const POLL_INTERVAL: Duration = Duration::from_secs(5);
/// Safety cap on poll attempts (≈30 min at [`POLL_INTERVAL`]) before giving up.
const MAX_POLLS: u32 = 360;

/// One entry in a batch: a caller-chosen `custom_id` correlating the result, plus the request.
pub struct BatchRequest {
    pub custom_id: String,
    pub request: ChatRequest,
}

/// A submitted/queried batch.
#[derive(Debug, Clone)]
pub struct Batch {
    pub id: String,
    /// `in_progress`, `canceling`, or `ended`.
    pub processing_status: String,
}

impl Batch {
    /// True once the batch has finished and results are available.
    pub fn ended(&self) -> bool {
        self.processing_status == "ended"
    }
}

/// One page of the batch list (`GET /v1/messages/batches`).
#[derive(Debug, Clone)]
pub struct BatchList {
    pub batches: Vec<Batch>,
    /// True if more pages follow; pass [`last_id`](Self::last_id) as `after_id` to fetch them.
    pub has_more: bool,
    /// The id of the last batch on this page (the pagination cursor), if any.
    pub last_id: Option<String>,
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
    /// The request errored (validation or server); carries the error type.
    Errored(String),
    /// Cancelled before completion.
    Canceled,
    /// Expired (not processed within the 24h window).
    Expired,
}

impl AnthropicProvider {
    /// Submit a batch of completion requests. Returns the batch id + initial status; poll
    /// [`get_batch`](Self::get_batch) until [`Batch::ended`], then read [`batch_results`](Self::batch_results).
    pub async fn create_batch(&self, requests: &[BatchRequest]) -> Result<Batch, ProviderError> {
        let reqs: Vec<Value> = requests
            .iter()
            .map(|r| {
                // Batch params are a *non-streaming* completion request: reuse the normal body
                // builder and strip `stream` (the batch endpoint rejects streaming params).
                let mut params = build_body(&r.request, false);
                if let Some(obj) = params.as_object_mut() {
                    obj.remove("stream");
                }
                json!({ "custom_id": r.custom_id, "params": params })
            })
            .collect();
        let v = self.batch_post("", json!({ "requests": reqs })).await?;
        Ok(parse_batch(&v))
    }

    /// Fetch a batch's current status.
    pub async fn get_batch(&self, batch_id: &str) -> Result<Batch, ProviderError> {
        let v = self.batch_get(&format!("/{batch_id}")).await?;
        Ok(parse_batch(&v))
    }

    /// Request cancellation of an in-progress batch. Returns the batch with its updated status
    /// (`canceling`, then eventually `ended`); requests already in flight may still complete.
    pub async fn cancel_batch(&self, batch_id: &str) -> Result<Batch, ProviderError> {
        let v = self
            .batch_post(&format!("/{batch_id}/cancel"), json!({}))
            .await?;
        Ok(parse_batch(&v))
    }

    /// List batches, most recent first. `limit` caps the page size (Anthropic default 20, max
    /// 100); `after_id` is the pagination cursor (pass a prior page's [`BatchList::last_id`]).
    pub async fn list_batches(
        &self,
        limit: Option<u32>,
        after_id: Option<&str>,
    ) -> Result<BatchList, ProviderError> {
        let mut query = Vec::new();
        if let Some(n) = limit {
            query.push(format!("limit={n}"));
        }
        if let Some(id) = after_id {
            query.push(format!("after_id={id}"));
        }
        let suffix = if query.is_empty() {
            String::new()
        } else {
            format!("?{}", query.join("&"))
        };
        let v = self.batch_get(&suffix).await?;
        Ok(parse_batch_list(&v))
    }

    /// Read a finished batch's per-request results (the JSONL results stream, one object per line).
    pub async fn batch_results(&self, batch_id: &str) -> Result<Vec<BatchResult>, ProviderError> {
        let url = format!(
            "{}/v1/messages/batches/{batch_id}/results",
            self.base_url.trim_end_matches('/')
        );
        let text = self
            .http
            .get(url)
            .header("x-api-key", &self.api_key)
            .header("anthropic-version", ANTHROPIC_VERSION)
            .send()
            .await
            .map_err(|e| ProviderError::Transport(e.to_string()))?
            .error_for_status()
            .map_err(|e| ProviderError::Api {
                status: e.status().map(|s| s.as_u16()).unwrap_or(0),
                message: e.to_string(),
            })?
            .text()
            .await
            .map_err(|e| ProviderError::Transport(e.to_string()))?;
        Ok(text
            .lines()
            .filter(|l| !l.trim().is_empty())
            .filter_map(|line| serde_json::from_str::<Value>(line).ok())
            .map(|v| parse_result(&v))
            .collect())
    }

    /// POST `/v1/messages/batches{suffix}` with a JSON body.
    async fn batch_post(&self, suffix: &str, body: Value) -> Result<Value, ProviderError> {
        let url = format!(
            "{}/v1/messages/batches{suffix}",
            self.base_url.trim_end_matches('/')
        );
        self.batch_send(self.http.post(url).json(&body)).await
    }

    /// GET `/v1/messages/batches{suffix}`.
    async fn batch_get(&self, suffix: &str) -> Result<Value, ProviderError> {
        let url = format!(
            "{}/v1/messages/batches{suffix}",
            self.base_url.trim_end_matches('/')
        );
        self.batch_send(self.http.get(url)).await
    }

    async fn batch_send(&self, builder: reqwest::RequestBuilder) -> Result<Value, ProviderError> {
        let resp = builder
            .header("x-api-key", &self.api_key)
            .header("anthropic-version", ANTHROPIC_VERSION)
            .send()
            .await
            .map_err(|e| ProviderError::Transport(e.to_string()))?;
        let status = resp.status();
        if !status.is_success() {
            let message = resp.text().await.unwrap_or_default();
            return Err(ProviderError::Api {
                status: status.as_u16(),
                message,
            });
        }
        resp.json()
            .await
            .map_err(|e| ProviderError::Decode(e.to_string()))
    }
}

#[async_trait]
impl BatchProvider for AnthropicProvider {
    async fn run_batch(&self, tasks: Vec<BatchTask>) -> Result<Vec<BatchItem>, ProviderError> {
        let reqs: Vec<BatchRequest> = tasks
            .into_iter()
            .map(|t| BatchRequest {
                custom_id: t.custom_id,
                request: t.request,
            })
            .collect();
        let batch = self.create_batch(&reqs).await?;
        for _ in 0..MAX_POLLS {
            if self.get_batch(&batch.id).await?.ended() {
                let results = self.batch_results(&batch.id).await?;
                return Ok(results.into_iter().map(item_from_result).collect());
            }
            tokio::time::sleep(POLL_INTERVAL).await;
        }
        Err(ProviderError::Transport(
            "batch did not finish within the poll window".into(),
        ))
    }
}

/// Flatten a per-request [`BatchResult`] into the unified [`BatchItem`].
fn item_from_result(r: BatchResult) -> BatchItem {
    let (text, usage, error) = match r.outcome {
        BatchOutcome::Succeeded { text, usage } => (text, usage, None),
        BatchOutcome::Errored(e) => (String::new(), Usage::default(), Some(e)),
        BatchOutcome::Canceled => (String::new(), Usage::default(), Some("canceled".into())),
        BatchOutcome::Expired => (String::new(), Usage::default(), Some("expired".into())),
    };
    BatchItem {
        custom_id: r.custom_id,
        text,
        usage,
        error,
    }
}

fn parse_batch(v: &Value) -> Batch {
    Batch {
        id: v["id"].as_str().unwrap_or_default().to_string(),
        processing_status: v["processing_status"]
            .as_str()
            .unwrap_or_default()
            .to_string(),
    }
}

fn parse_batch_list(v: &Value) -> BatchList {
    let batches = v["data"]
        .as_array()
        .map(|arr| arr.iter().map(parse_batch).collect())
        .unwrap_or_default();
    BatchList {
        batches,
        has_more: v["has_more"].as_bool().unwrap_or(false),
        last_id: v["last_id"].as_str().map(str::to_string),
    }
}

fn parse_result(v: &Value) -> BatchResult {
    let custom_id = v["custom_id"].as_str().unwrap_or_default().to_string();
    let result = &v["result"];
    let outcome = match result["type"].as_str() {
        Some("succeeded") => {
            let msg = &result["message"];
            let text = msg["content"]
                .as_array()
                .map(|blocks| {
                    blocks
                        .iter()
                        .filter(|b| b["type"] == "text")
                        .filter_map(|b| b["text"].as_str())
                        .collect::<String>()
                })
                .unwrap_or_default();
            let u = &msg["usage"];
            let usage = Usage {
                input_tokens: u["input_tokens"].as_u64().unwrap_or(0),
                output_tokens: u["output_tokens"].as_u64().unwrap_or(0),
                cache_creation_tokens: u["cache_creation_input_tokens"].as_u64().unwrap_or(0),
                cache_read_tokens: u["cache_read_input_tokens"].as_u64().unwrap_or(0),
            };
            BatchOutcome::Succeeded { text, usage }
        }
        Some("errored") => BatchOutcome::Errored(
            result["error"]["type"]
                .as_str()
                .unwrap_or("unknown")
                .to_string(),
        ),
        Some("canceled") => BatchOutcome::Canceled,
        _ => BatchOutcome::Expired,
    };
    BatchResult { custom_id, outcome }
}

#[cfg(test)]
mod tests {
    use super::*;
    use lvz_protocol::Message;

    #[test]
    fn batch_result_parses_a_succeeded_line() {
        let line = json!({
            "custom_id": "task-1",
            "result": {
                "type": "succeeded",
                "message": {
                    "content": [{ "type": "text", "text": "hello" }],
                    "usage": { "input_tokens": 10, "output_tokens": 3,
                               "cache_read_input_tokens": 4, "cache_creation_input_tokens": 0 }
                }
            }
        });
        let r = parse_result(&line);
        assert_eq!(r.custom_id, "task-1");
        match r.outcome {
            BatchOutcome::Succeeded { text, usage } => {
                assert_eq!(text, "hello");
                assert_eq!(usage.input_tokens, 10);
                assert_eq!(usage.cache_read_tokens, 4);
            }
            _ => panic!("expected succeeded"),
        }
    }

    #[test]
    fn item_from_result_flattens_outcomes() {
        let ok = item_from_result(BatchResult {
            custom_id: "a".into(),
            outcome: BatchOutcome::Succeeded {
                text: "hi".into(),
                usage: Usage {
                    input_tokens: 5,
                    ..Default::default()
                },
            },
        });
        assert_eq!(ok.text, "hi");
        assert_eq!(ok.usage.input_tokens, 5);
        assert!(ok.error.is_none());

        let err = item_from_result(BatchResult {
            custom_id: "b".into(),
            outcome: BatchOutcome::Expired,
        });
        assert_eq!(err.text, "");
        assert_eq!(err.error.as_deref(), Some("expired"));
    }

    #[test]
    fn batch_list_parses_page_and_cursor() {
        let page = json!({
            "data": [
                { "id": "batch_a", "processing_status": "ended" },
                { "id": "batch_b", "processing_status": "in_progress" }
            ],
            "has_more": true,
            "first_id": "batch_a",
            "last_id": "batch_b"
        });
        let list = parse_batch_list(&page);
        assert_eq!(list.batches.len(), 2);
        assert_eq!(list.batches[0].id, "batch_a");
        assert!(list.batches[0].ended());
        assert!(list.has_more);
        assert_eq!(list.last_id.as_deref(), Some("batch_b"));
    }

    #[test]
    fn create_batch_params_drop_stream_and_keep_custom_id() {
        // We can't hit the network in a unit test, but we can check the per-request shape the
        // builder produces by reconstructing it the same way create_batch does.
        let req = BatchRequest {
            custom_id: "abc".into(),
            request: ChatRequest::new("claude-sonnet-4-6").push(Message::user("hi")),
        };
        let mut params = build_body(&req.request, false);
        params.as_object_mut().unwrap().remove("stream");
        let entry = json!({ "custom_id": req.custom_id, "params": params });
        assert_eq!(entry["custom_id"], "abc");
        assert!(entry["params"]["stream"].is_null());
        assert_eq!(entry["params"]["model"], "claude-sonnet-4-6");
    }
}
