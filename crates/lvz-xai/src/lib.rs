//! xAI provider for Lavoisier.
//!
//! `RECIPE.md` (§1, §8) gives xAI two transports: a native **gRPC** path (codegen from the
//! vendored `xai-proto`, M7) and an in-crate **OpenAI-compatible** fallback against
//! `https://api.x.ai/v1`. Both implement the [`Provider`] contract and converge on the
//! normalised [`Event`] stream; each is the *only* place its wire format is known.
//!
//! [`XaiProvider`] is a thin dispatcher over the two. [`XaiProvider::from_env`] honours the
//! `XAI_TRANSPORT` switch (`grpc` | `http`), defaulting to `http` until the gRPC path is
//! live-verified.

mod grpc;
mod http;

pub use grpc::GrpcTransport;
pub use http::HttpTransport;

use async_trait::async_trait;
use futures::stream::BoxStream;
use lvz_protocol::{Capabilities, ChatRequest, Event, Provider, ProviderError};

/// A [`Provider`] for xAI that dispatches to one of two transports: the native gRPC path
/// or the OpenAI-compatible HTTP fallback.
pub enum XaiProvider {
    /// Native gRPC against `api.x.ai` (xAI proto; server-side tools).
    Grpc(GrpcTransport),
    /// OpenAI-compatible REST against `https://api.x.ai/v1`.
    Http(HttpTransport),
}

impl XaiProvider {
    /// Construct the OpenAI-compat HTTP transport against the default base URL.
    pub fn new(api_key: impl Into<String>) -> Self {
        XaiProvider::Http(HttpTransport::new(api_key))
    }

    /// Construct the OpenAI-compat HTTP transport against an explicit base URL (proxy/mock).
    pub fn with_base_url(api_key: impl Into<String>, base_url: impl Into<String>) -> Self {
        XaiProvider::Http(HttpTransport::with_base_url(api_key, base_url))
    }

    /// Construct from the environment. `XAI_API_KEY` is required. `XAI_TRANSPORT` selects the
    /// transport (`grpc` | `http`, default `http`). `XAI_BASE_URL` overrides the REST base
    /// (HTTP); `XAI_GRPC_ENDPOINT` overrides the gRPC endpoint.
    pub fn from_env() -> Result<Self, ProviderError> {
        let api_key = std::env::var("XAI_API_KEY")
            .map_err(|_| ProviderError::Config("XAI_API_KEY is not set".into()))?;
        let transport = std::env::var("XAI_TRANSPORT").unwrap_or_else(|_| "http".into());
        match transport.trim().to_ascii_lowercase().as_str() {
            "grpc" => {
                let endpoint = std::env::var("XAI_GRPC_ENDPOINT")
                    .unwrap_or_else(|_| grpc::DEFAULT_ENDPOINT.into());
                Ok(XaiProvider::Grpc(GrpcTransport::with_endpoint(
                    api_key, endpoint,
                )))
            }
            "http" => {
                let base_url =
                    std::env::var("XAI_BASE_URL").unwrap_or_else(|_| http::DEFAULT_BASE_URL.into());
                Ok(XaiProvider::Http(HttpTransport::with_base_url(
                    api_key, base_url,
                )))
            }
            other => Err(ProviderError::Config(format!(
                "unknown XAI_TRANSPORT '{other}' (expected 'grpc' or 'http')"
            ))),
        }
    }
}

#[async_trait]
impl Provider for XaiProvider {
    async fn stream(
        &self,
        req: ChatRequest,
    ) -> Result<BoxStream<'static, Result<Event, ProviderError>>, ProviderError> {
        match self {
            XaiProvider::Grpc(t) => t.stream(req).await,
            XaiProvider::Http(t) => t.stream(req).await,
        }
    }

    fn capabilities(&self) -> Capabilities {
        match self {
            XaiProvider::Grpc(t) => t.capabilities(),
            XaiProvider::Http(t) => t.capabilities(),
        }
    }
}
