//! The [`Provider`] contract: stream a chat turn as normalised [`Event`]s, regardless of
//! wire protocol, and declare what optional features the transport supports.
//!
//! Capabilities are a **set of [`Capability`]**, not a record of `bool`. The record version was
//! built positionally at every adapter (`Capabilities { prompt_caching: true, .. }`), so inserting
//! or reordering a field silently re-labelled every provider's advertised features and nothing in
//! the type could catch it. The set's field is private: build one through [`ProviderCaps::declare`]
//! or [`Capabilities::from_list`].

use std::collections::BTreeSet;
use std::marker::PhantomData;

use async_trait::async_trait;
use futures::stream::{self, BoxStream, StreamExt};

use crate::event::Event;
use crate::message::{BuiltinTool, ChatRequest, ContentBlock, ServerTool, ThinkingLevel};

/// A model backend. Implemented once per transport (`lvz-anthropic`, `lvz-xai`,
/// `lvz-claude-cli`). The agent core depends only on this trait, never on a concrete
/// transport (§5.1).
#[async_trait]
pub trait Provider: Send + Sync {
    /// Stream a chat turn as normalised events. The returned stream owns its state so it
    /// can outlive the borrow of `self`.
    async fn stream(
        &self,
        req: ChatRequest,
    ) -> Result<BoxStream<'static, Result<Event, ProviderError>>, ProviderError>;

    /// Declare optional features so the agent can negotiate / degrade gracefully.
    fn capabilities(&self) -> Capabilities;

    /// Count the input tokens this request would consume, using the provider's **native** counter
    /// when it has one. Returns `Ok(None)` when the provider exposes no count endpoint (the caller
    /// then falls back to its own estimate). The default is `Ok(None)`; adapters with a counter
    /// (e.g. Anthropic `/v1/messages/count_tokens`) override it.
    async fn count_tokens(&self, _req: &ChatRequest) -> Result<Option<u64>, ProviderError> {
        Ok(None)
    }
}

/// An optional feature a provider may support.
///
/// Server-side tools are enumerated **one capability per tool**, not as a single
/// `ServerSideTools` category. The category flag was wrong: the providers' tool sets are genuinely
/// disjoint (Anthropic web search/fetch/code execution + its own client builtins + remote MCP;
/// Gemini search + code execution + `url_context`; xAI search + X search + collections), so one
/// flag let a tool the adapter cannot map pass the check and be dropped in silence — the failure
/// [`negotiate`] exists to remove. Each adapter declares exactly the tools it maps.
///
/// There is deliberately **no `ParallelToolUse`**. It was mis-modelled:
/// [`ChatRequest::disable_parallel_tool_use`] is an *inverse* knob, so a provider lacking parallel
/// tool use already satisfies "disabled" and there is nothing to detect.
#[derive(
    Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, serde::Serialize, serde::Deserialize,
)]
#[serde(rename_all = "snake_case")]
pub enum Capability {
    /// Ephemeral prompt caching on stable prefixes. Anthropic: yes; claude-cli: no.
    PromptCaching,
    /// Extended-thinking blocks.
    ExtendedThinking,
    /// Image / document (multimodal) inputs.
    Vision,
    /// Provider-run web search ([`ServerTool::WebSearch`]; Gemini's Google Search grounding).
    WebSearch,
    /// Provider-run fetch of a named URL ([`ServerTool::WebFetch`]).
    WebFetch,
    /// Provider-hosted code sandbox ([`ServerTool::CodeExecution`]).
    CodeExecution,
    /// Search of X posts ([`ServerTool::XSearch`], xAI only).
    XSearch,
    /// RAG over provider-hosted document collections ([`ServerTool::CollectionsSearch`], xAI only).
    CollectionsSearch,
    /// Provider-side fetch of URLs named in the prompt ([`ServerTool::UrlContext`], Gemini only).
    UrlContext,
    /// Anthropic-defined client tools declared by versioned type ([`BuiltinTool`]).
    ClientBuiltinTools,
    /// Remote MCP servers the provider connects to on the model's behalf.
    RemoteMcp,
    /// `temperature` and `top_p` are honoured.
    Sampling,
    /// `top_k` is honoured. Separate from [`Capability::Sampling`] because xAI takes the other two
    /// and not this one.
    TopK,
    /// Caller-supplied stop sequences are honoured.
    StopSequences,
    /// A response JSON schema is honoured.
    StructuredOutput,
    /// The caller can steer tool selection.
    ToolChoiceControl,
}

impl Capability {
    /// Every capability. A new variant must be added here too; the exhaustive `match` in
    /// [`Capability::name`] is what forces the reminder.
    pub const ALL: &'static [Capability] = &[
        Capability::PromptCaching,
        Capability::ExtendedThinking,
        Capability::Vision,
        Capability::WebSearch,
        Capability::WebFetch,
        Capability::CodeExecution,
        Capability::XSearch,
        Capability::CollectionsSearch,
        Capability::UrlContext,
        Capability::ClientBuiltinTools,
        Capability::RemoteMcp,
        Capability::Sampling,
        Capability::TopK,
        Capability::StopSequences,
        Capability::StructuredOutput,
        Capability::ToolChoiceControl,
    ];

    /// The capability's name, for refusal and notice messages.
    pub fn name(self) -> &'static str {
        match self {
            Capability::PromptCaching => "prompt caching",
            Capability::ExtendedThinking => "extended thinking",
            Capability::Vision => "vision",
            Capability::WebSearch => "web search",
            Capability::WebFetch => "web fetch",
            Capability::CodeExecution => "code execution",
            Capability::XSearch => "x search",
            Capability::CollectionsSearch => "collections search",
            Capability::UrlContext => "url context",
            Capability::ClientBuiltinTools => "client builtin tools",
            Capability::RemoteMcp => "remote MCP",
            Capability::Sampling => "sampling",
            Capability::TopK => "top_k",
            Capability::StopSequences => "stop sequences",
            Capability::StructuredOutput => "structured output",
            Capability::ToolChoiceControl => "tool choice",
        }
    }
}

/// What a provider supports. The field is private — build one with [`ProviderCaps::declare`] or
/// [`Capabilities::from_list`].
#[derive(Debug, Clone, Default, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct Capabilities(BTreeSet<Capability>);

impl Capabilities {
    /// Build from a value-level list (for tests and dynamic sources).
    pub fn from_list(caps: &[Capability]) -> Self {
        Capabilities(caps.iter().copied().collect())
    }

    /// No optional features.
    pub fn none() -> Self {
        Capabilities(BTreeSet::new())
    }

    /// Every feature — derived from [`Capability::ALL`], so a new capability joins automatically.
    pub fn all() -> Self {
        Capabilities::from_list(Capability::ALL)
    }

    /// Does the provider support this feature?
    pub fn supports(&self, c: Capability) -> bool {
        self.0.contains(&c)
    }

    /// Ephemeral prompt caching on stable prefixes.
    pub fn prompt_caching(&self) -> bool {
        self.supports(Capability::PromptCaching)
    }

    /// Extended-thinking blocks.
    pub fn extended_thinking(&self) -> bool {
        self.supports(Capability::ExtendedThinking)
    }

    /// Image / document (multimodal) inputs.
    pub fn vision(&self) -> bool {
        self.supports(Capability::Vision)
    }
}

/// An adapter's capability list, named **once** as a type so the declaration and the check cannot
/// drift apart: the same `C` feeds both [`Provider::capabilities`] (via [`ProviderCaps::declare`])
/// and [`negotiate`].
///
/// ```ignore
/// pub struct AnthropicCaps;
/// impl ProviderCaps for AnthropicCaps {
///     const CAPS: &'static [Capability] = &[Capability::PromptCaching, Capability::Vision];
/// }
/// ```
pub trait ProviderCaps {
    /// The capabilities this provider advertises **and** enforces.
    const CAPS: &'static [Capability];

    /// The value-level set for [`Self::CAPS`].
    fn declare() -> Capabilities {
        Capabilities::from_list(Self::CAPS)
    }
}

/// A [`ChatRequest`] checked against a provider declaring exactly `C`, and adjusted where it could
/// be. The field is **private**: [`negotiate`] is the only way to obtain one, so a value of this
/// type *is* the evidence that the check ran. An adapter whose request builders take
/// `Negotiated<C>` cannot skip it — and a newly added send path fails to compile until it
/// negotiates too, which is the point.
pub struct Negotiated<C: ProviderCaps>(ChatRequest, PhantomData<C>);

/// Hand-written rather than derived: `C` is a marker type that is never constructed, so deriving
/// would demand a pointless `C: Debug` bound.
impl<C: ProviderCaps> std::fmt::Debug for Negotiated<C> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_tuple("Negotiated").field(&self.0).finish()
    }
}

impl<C: ProviderCaps> Negotiated<C> {
    /// Borrow the negotiated request.
    pub fn request(&self) -> &ChatRequest {
        &self.0
    }

    /// Consume the evidence and take the request.
    pub fn into_request(self) -> ChatRequest {
        self.0
    }
}

/// The capability a given server-side tool requires.
pub fn server_tool_capability(t: &ServerTool) -> Capability {
    match t {
        ServerTool::WebSearch { .. } => Capability::WebSearch,
        ServerTool::WebFetch { .. } => Capability::WebFetch,
        ServerTool::CodeExecution => Capability::CodeExecution,
        ServerTool::XSearch { .. } => Capability::XSearch,
        ServerTool::CollectionsSearch { .. } => Capability::CollectionsSearch,
        ServerTool::UrlContext => Capability::UrlContext,
    }
}

/// The capability a given client builtin tool requires. All three are Anthropic-defined, so they
/// share one capability rather than getting three of their own.
pub fn builtin_tool_capability(_b: &BuiltinTool) -> Capability {
    Capability::ClientBuiltinTools
}

/// Name a [`ServerTool`] for use in a refusal message.
fn server_tool_name(t: &ServerTool) -> &'static str {
    match t {
        ServerTool::WebSearch { .. } => "web_search",
        ServerTool::WebFetch { .. } => "web_fetch",
        ServerTool::CodeExecution => "code_execution",
        ServerTool::XSearch { .. } => "x_search",
        ServerTool::CollectionsSearch { .. } => "collections_search",
        ServerTool::UrlContext => "url_context",
    }
}

/// Name a [`BuiltinTool`] for use in a refusal message.
fn builtin_tool_name(b: &BuiltinTool) -> &'static str {
    match b {
        BuiltinTool::Bash => "bash",
        BuiltinTool::TextEditor => "text_editor",
        BuiltinTool::Memory => "memory",
    }
}

/// Check a request against the capabilities `C` and return any notices alongside either a refusal
/// or the adjusted request.
///
/// The two kinds of capability fail in **opposite** directions, deliberately:
///
/// * **Caller knobs** — the user asked for something optional ([`Capability::ExtendedThinking`]).
///   These **degrade** and emit a notice. Killing the turn would be worse than not thinking, and
///   the fallback chain applies one request across several providers. Staying silent bills the
///   user for a feature they did not get.
///
/// * **Transcript content and requested tools** — the messages already carry bytes the provider
///   must accept ([`Capability::Vision`]), or the caller asked for a specific provider-run tool.
///   These **refuse** with [`ProviderError::Unsupported`]. Dropping an image silently makes the
///   model answer about something it never saw; dropping a tool leaves the model unable to do what
///   it was set up to do. Both look like success.
///
/// Notices are returned even alongside a refusal; the caller may drop them in that case, since a
/// refused turn has no event stream to carry them.
pub fn negotiate<C: ProviderCaps>(
    req: ChatRequest,
) -> (Vec<String>, Result<Negotiated<C>, ProviderError>) {
    let caps = C::declare();
    let mut notices = Vec::new();
    let mut adjusted = req;

    // Caller knobs: degrade, one notice each. Each entry is (was it asked for, which capability,
    // what to say, how to clear it) — adding a knob means adding a row, not a new code path.
    type Clear = fn(&mut ChatRequest);
    let knobs: [(bool, Capability, &str, Clear); 6] = [
        (
            matches!(adjusted.thinking, Some(l) if l != ThinkingLevel::Off),
            Capability::ExtendedThinking,
            "extended thinking",
            |r| r.thinking = None,
        ),
        (
            adjusted.temperature.is_some() || adjusted.top_p.is_some(),
            Capability::Sampling,
            "temperature/top_p",
            |r| {
                r.temperature = None;
                r.top_p = None;
            },
        ),
        (adjusted.top_k.is_some(), Capability::TopK, "top_k", |r| {
            r.top_k = None
        }),
        (
            !adjusted.stop_sequences.is_empty(),
            Capability::StopSequences,
            "stop sequences",
            |r| r.stop_sequences.clear(),
        ),
        (
            adjusted.output_format.is_some(),
            Capability::StructuredOutput,
            "a structured-output schema",
            |r| r.output_format = None,
        ),
        (
            adjusted.tool_choice.is_some(),
            Capability::ToolChoiceControl,
            "tool choice",
            |r| r.tool_choice = None,
        ),
    ];

    for (asked, cap, what, clear) in knobs {
        if asked && !caps.supports(cap) {
            notices.push(format!(
                "{what} was requested but this provider does not support it; continuing without it"
            ));
            clear(&mut adjusted);
        }
    }

    // Transcript content: refuse.
    let has_image = adjusted.messages.iter().any(|m| {
        m.content
            .iter()
            .any(|b| matches!(b, ContentBlock::Image { .. }))
    });
    if has_image && !caps.vision() {
        return (
            notices,
            Err(ProviderError::Unsupported(
                "the request contains an image block but this provider does not support vision"
                    .into(),
            )),
        );
    }

    // Each tool is checked against its **own** capability, because the providers' tool sets are
    // disjoint. A single category flag would let e.g. an xAI-only tool through to Anthropic, whose
    // mapper then silently drops it.
    let unsupported_tool = adjusted
        .server_tools
        .iter()
        .map(|t| (server_tool_name(t), server_tool_capability(t)))
        .chain(
            adjusted
                .builtin_tools
                .iter()
                .map(|b| (builtin_tool_name(b), builtin_tool_capability(b))),
        )
        .find(|(_, c)| !caps.supports(*c));

    if let Some((name, c)) = unsupported_tool {
        return (
            notices,
            Err(ProviderError::Unsupported(format!(
                "tool `{name}` was offered but this provider does not support it ({})",
                c.name()
            ))),
        );
    }

    if !adjusted.mcp_servers.is_empty() && !caps.supports(Capability::RemoteMcp) {
        return (
            notices,
            Err(ProviderError::Unsupported(
                "remote MCP servers were offered but this provider does not connect to them".into(),
            )),
        );
    }

    (notices, Ok(Negotiated(adjusted, PhantomData)))
}

/// The adapter-facing wrapper: negotiate, then run the send with the checked request, prefixing any
/// notices onto the front of the returned stream as [`Event::Notice`]. An adapter's `stream` should
/// be this call and nothing else, so the check cannot be forgotten and the notices cannot be
/// dropped.
pub async fn with_negotiated<C, F, Fut>(
    req: ChatRequest,
    send: F,
) -> Result<BoxStream<'static, Result<Event, ProviderError>>, ProviderError>
where
    C: ProviderCaps,
    F: FnOnce(Negotiated<C>) -> Fut,
    Fut: std::future::Future<
        Output = Result<BoxStream<'static, Result<Event, ProviderError>>, ProviderError>,
    >,
{
    let (notices, outcome) = negotiate::<C>(req);
    let nreq = outcome?;
    let inner = send(nreq).await?;
    if notices.is_empty() {
        return Ok(inner);
    }
    let head = stream::iter(notices.into_iter().map(|n| Ok(Event::Notice(n))));
    Ok(head.chain(inner).boxed())
}

/// Errors surfaced by a provider. Adapters map their transport/API failures onto these.
#[derive(Debug, thiserror::Error)]
pub enum ProviderError {
    /// Network / transport-level failure (connection, TLS, timeout).
    #[error("transport error: {0}")]
    Transport(String),

    /// The API returned a non-success status with a message.
    #[error("api error {status}: {message}")]
    Api {
        /// The HTTP status code returned.
        status: u16,
        /// The error message from the API.
        message: String,
    },

    /// A response (or SSE/gRPC frame) could not be decoded into the expected shape.
    #[error("decode error: {0}")]
    Decode(String),

    /// The caller cancelled mid-stream. Tokens consumed before cancellation may still bill.
    #[error("request cancelled")]
    Cancelled,

    /// The request used a feature this provider's [`Capabilities`] does not advertise.
    #[error("unsupported capability: {0}")]
    Unsupported(String),

    /// Configuration problem (missing API key, bad base URL).
    #[error("configuration error: {0}")]
    Config(String),
}

#[cfg(test)]
mod negotiate_tests {
    use super::*;
    use crate::message::{MediaSource, Message, Role};

    /// A provider that supports nothing — the claude-cli shape.
    struct Bare;
    impl ProviderCaps for Bare {
        const CAPS: &'static [Capability] = &[];
    }

    /// Vision plus the two knobs, but no provider-run tools.
    struct Rich;
    impl ProviderCaps for Rich {
        const CAPS: &'static [Capability] = &[
            Capability::Vision,
            Capability::ExtendedThinking,
            Capability::Sampling,
            Capability::WebSearch,
        ];
    }

    fn req() -> ChatRequest {
        ChatRequest::new("m")
    }

    #[test]
    fn caller_knobs_degrade_with_a_notice_rather_than_failing() {
        let mut r = req();
        r.thinking = Some(ThinkingLevel::High);
        r.temperature = Some(0.5);
        r.top_p = Some(0.9);
        let (notices, out) = negotiate::<Bare>(r);
        let n = out
            .expect("a dropped knob must never kill the turn")
            .into_request();
        // Cleared, so the adapter cannot send a field the provider ignores...
        assert_eq!(n.thinking, None);
        assert_eq!(n.temperature, None);
        assert_eq!(n.top_p, None);
        // ...but the user is told, because they asked for something they did not get.
        assert_eq!(notices.len(), 2, "one notice per dropped knob: {notices:?}");
        assert!(notices.iter().any(|s| s.contains("extended thinking")));
        assert!(notices.iter().any(|s| s.contains("temperature/top_p")));
    }

    #[test]
    fn a_supported_knob_is_left_alone_and_says_nothing() {
        let mut r = req();
        r.thinking = Some(ThinkingLevel::High);
        r.temperature = Some(0.5);
        let (notices, out) = negotiate::<Rich>(r);
        let n = out.unwrap().into_request();
        assert_eq!(n.thinking, Some(ThinkingLevel::High));
        assert_eq!(n.temperature, Some(0.5));
        assert!(notices.is_empty(), "{notices:?}");
    }

    #[test]
    fn thinking_off_is_not_a_request_for_thinking() {
        let mut r = req();
        r.thinking = Some(ThinkingLevel::Off);
        let (notices, out) = negotiate::<Bare>(r);
        assert!(out.is_ok());
        assert!(notices.is_empty(), "Off asks for nothing: {notices:?}");
    }

    #[test]
    fn transcript_content_refuses_instead_of_being_dropped() {
        // A silently-dropped image makes the model answer about something it never saw, which
        // looks like success. That is why this direction refuses rather than degrading.
        let mut r = req();
        r.messages = vec![Message {
            role: Role::User,
            content: vec![ContentBlock::Image {
                source: MediaSource::Url {
                    url: "https://example.invalid/a.png".into(),
                },
            }],
        }];
        let (_, out) = negotiate::<Bare>(r);
        match out {
            Err(ProviderError::Unsupported(m)) => assert!(m.contains("vision"), "{m}"),
            other => panic!("expected a refusal, got {other:?}"),
        }
    }

    #[test]
    fn each_server_tool_is_checked_against_its_own_capability() {
        // Rich declares WebSearch but not XSearch. A single category flag would let XSearch
        // through to a mapper that drops it in silence — the failure this design removes.
        let mut r = req();
        r.server_tools = vec![ServerTool::WebSearch {
            max_uses: None,
            allowed_domains: vec![],
            blocked_domains: vec![],
        }];
        assert!(
            negotiate::<Rich>(r.clone()).1.is_ok(),
            "declared tool passes"
        );

        r.server_tools.push(ServerTool::XSearch {
            allowed_handles: vec![],
            blocked_handles: vec![],
            from_date: None,
            to_date: None,
        });
        match negotiate::<Rich>(r).1 {
            Err(ProviderError::Unsupported(m)) => {
                assert!(
                    m.contains("x_search"),
                    "the refusal must name the tool: {m}"
                );
            }
            other => panic!("expected a refusal, got {other:?}"),
        }
    }

    #[test]
    fn remote_mcp_refuses_when_undeclared() {
        let mut r = req();
        r.mcp_servers = vec![crate::message::McpServer {
            name: "s".into(),
            url: "https://example.invalid".into(),
            authorization_token: None,
        }];
        match negotiate::<Rich>(r).1 {
            Err(ProviderError::Unsupported(m)) => assert!(m.contains("MCP"), "{m}"),
            other => panic!("expected a refusal, got {other:?}"),
        }
    }

    #[test]
    fn notices_survive_alongside_a_refusal() {
        // The caller may drop them (a refused turn has no stream to carry them), but negotiate
        // must not swallow them just because it is also refusing.
        let mut r = req();
        r.thinking = Some(ThinkingLevel::High);
        r.messages = vec![Message {
            role: Role::User,
            content: vec![ContentBlock::Image {
                source: MediaSource::Url { url: "u".into() },
            }],
        }];
        let (notices, out) = negotiate::<Bare>(r);
        assert!(out.is_err());
        assert!(!notices.is_empty(), "notices were swallowed by the refusal");
    }
}
