//! `lvz-agent` — the reasoning loop (`RECIPE.md` §4).
//!
//! The agent runs a **plan → act → observe** cycle: ask the provider for a turn, and if the
//! model called tools, execute them, append the results to history, and ask again — until
//! the model answers without calling a tool (or a safety/budget limit trips). It consumes
//! only the [`Provider`] and [`Tool`] contracts plus a [`ToolRegistry`], so it is unaware of
//! any wire protocol or gateway.
//!
//! Caching is **capability-gated** (§6.2): the stable prefix (system prompt + tool
//! definitions) is marked cacheable only when the provider advertises
//! [`prompt_caching`](lvz_protocol::Capabilities::prompt_caching). Token usage is summed
//! across every round-trip — the metric that matters (§6.4) — and enforced against an
//! optional budget.

use std::collections::HashMap;
use std::sync::Arc;

use async_trait::async_trait;
use futures::channel::mpsc;
use futures::stream::{BoxStream, StreamExt};
use lvz_protocol::{
    AgentError, AgentHandle, Capabilities, ChatRequest, ContentBlock, Event, Message, Provider,
    Role, StopReason, SystemPrompt, ToolDef, TurnRequest, Usage,
};
use lvz_tools::ToolRegistry;
use serde_json::{json, Value};

const DEFAULT_SYSTEM: &str = "You are Lavoisier, a terse, token-efficient coding agent. \
Use the provided tools to inspect and modify the repository. To save tokens, prefer \
outline_file over read_file to learn a file's structure, and prefer read_anchored + \
edit_anchored over rewriting whole files with write_file. Take minimal, targeted actions; \
do not narrate. When the task is complete, give a one-line summary.";

/// Tunable settings for an agent run.
#[derive(Clone, Debug)]
pub struct AgentConfig {
    /// Model id passed to the provider each turn.
    pub model: String,
    /// Per-turn generation ceiling.
    pub max_tokens: u32,
    /// System prompt (the stable prefix; cached when the provider supports it).
    pub system: String,
    /// Safety cap on tool round-trips before forcing a stop.
    pub max_steps: usize,
    /// Optional ceiling on total task tokens across all round-trips (§6.4).
    pub token_budget: Option<u64>,
    /// Tool results larger than this are head/tail truncated before re-sending (§6.3).
    pub truncate_bytes: usize,
}

impl Default for AgentConfig {
    fn default() -> Self {
        Self {
            model: "grok-4".to_string(),
            max_tokens: 4096,
            system: DEFAULT_SYSTEM.to_string(),
            max_steps: 12,
            token_budget: None,
            truncate_bytes: 8 * 1024,
        }
    }
}

impl AgentConfig {
    /// Set the model id (builder style).
    pub fn with_model(mut self, model: impl Into<String>) -> Self {
        self.model = model.into();
        self
    }

    /// Set the total-task token budget.
    pub fn with_budget(mut self, budget: u64) -> Self {
        self.token_budget = Some(budget);
        self
    }
}

/// The reasoning loop bound to a concrete provider and tool set.
pub struct Agent {
    provider: Arc<dyn Provider>,
    tools: ToolRegistry,
    config: AgentConfig,
}

impl Agent {
    pub fn new(provider: Arc<dyn Provider>, tools: ToolRegistry, config: AgentConfig) -> Self {
        Self {
            provider,
            tools,
            config,
        }
    }

    /// Run one task to completion, streaming normalised events as they are produced.
    ///
    /// Per-round-trip `Usage`/`Done` events are suppressed; the caller sees exactly one
    /// terminal `Usage` (the task total) followed by one `Done`.
    pub fn run(&self, input: impl Into<String>) -> BoxStream<'static, Result<Event, AgentError>> {
        let (tx, rx) = mpsc::unbounded();
        let provider = self.provider.clone();
        let tools = self.tools.clone();
        let config = self.config.clone();
        let input = input.into();

        tokio::spawn(async move {
            run_loop(provider, tools, config, input, &tx).await;
            // tx drops here, closing the stream.
        });

        rx.boxed()
    }
}

#[async_trait]
impl AgentHandle for Agent {
    async fn submit(
        &self,
        turn: TurnRequest,
    ) -> Result<BoxStream<'static, Result<Event, AgentError>>, AgentError> {
        Ok(self.run(turn.input))
    }
}

type Sink = mpsc::UnboundedSender<Result<Event, AgentError>>;

async fn run_loop(
    provider: Arc<dyn Provider>,
    tools: ToolRegistry,
    config: AgentConfig,
    input: String,
    tx: &Sink,
) {
    let tool_defs = tools.defs();
    let caps = provider.capabilities();
    let mut history: Vec<Message> = vec![Message::user(input)];
    let mut total = Usage::default();

    for _step in 0..config.max_steps {
        let req = build_request(&config, &tool_defs, &caps, &history);
        let mut stream = match provider.stream(req).await {
            Ok(s) => s,
            Err(e) => {
                let _ = tx.unbounded_send(Err(AgentError::Provider(e.to_string())));
                return;
            }
        };

        let mut turn = TurnAccumulator::default();
        while let Some(event) = stream.next().await {
            match event {
                Ok(event) => {
                    if let Some(forward) = turn.observe(event) {
                        let _ = tx.unbounded_send(Ok(forward));
                    }
                }
                Err(e) => {
                    let _ = tx.unbounded_send(Err(AgentError::Provider(e.to_string())));
                    return;
                }
            }
        }

        total.accumulate(&turn.usage);

        if let Some(budget) = config.token_budget {
            if total.total() > budget {
                let _ = tx.unbounded_send(Err(AgentError::BudgetExceeded));
                return;
            }
        }

        if turn.tool_calls.is_empty() {
            let stop = turn.stop.unwrap_or(StopReason::EndTurn);
            let _ = tx.unbounded_send(Ok(Event::Usage(total)));
            let _ = tx.unbounded_send(Ok(Event::Done(stop)));
            return;
        }

        // Echo the assistant's text + tool calls into history, then run the tools.
        history.push(turn.to_assistant_message());

        let mut results = Vec::with_capacity(turn.tool_calls.len());
        for call in &turn.tool_calls {
            let block = match tools.invoke(&call.name, call.parsed_args()).await {
                Ok(out) => ContentBlock::ToolResult {
                    tool_use_id: call.id.clone(),
                    content: truncate(&out.content, config.truncate_bytes),
                    is_error: out.is_error,
                },
                Err(e) => ContentBlock::ToolResult {
                    tool_use_id: call.id.clone(),
                    content: format!("tool error: {e}"),
                    is_error: true,
                },
            };
            results.push(block);
        }
        history.push(Message {
            role: Role::User,
            content: results,
        });
    }

    // Ran out of steps without a final answer.
    let _ = tx.unbounded_send(Ok(Event::Usage(total)));
    let _ = tx.unbounded_send(Ok(Event::Done(StopReason::Other("max_steps".into()))));
}

/// Assemble a request, marking the stable prefix cacheable iff the provider supports caching.
fn build_request(
    config: &AgentConfig,
    tool_defs: &[ToolDef],
    caps: &Capabilities,
    history: &[Message],
) -> ChatRequest {
    let mut req = ChatRequest::new(config.model.clone()).max_tokens(config.max_tokens);
    req.system = Some(SystemPrompt {
        text: config.system.clone(),
        cache: caps.prompt_caching,
    });
    let mut defs = tool_defs.to_vec();
    if caps.prompt_caching {
        if let Some(last) = defs.last_mut() {
            last.cache = true; // breakpoint at the end of the stable tool-def prefix
        }
    }
    req.tools = defs;
    req.messages = history.to_vec();
    req
}

/// One in-flight tool call being reassembled from streamed argument deltas.
struct ToolCall {
    id: String,
    name: String,
    args_json: String,
}

impl ToolCall {
    /// Parse accumulated argument JSON, defaulting to `{}` when empty or malformed.
    fn parsed_args(&self) -> Value {
        if self.args_json.trim().is_empty() {
            json!({})
        } else {
            serde_json::from_str(&self.args_json).unwrap_or_else(|_| json!({}))
        }
    }
}

/// Folds a provider's event stream into a structured turn while deciding which events to
/// forward to the caller. Text/thinking/tool events pass through; usage/done are captured.
#[derive(Default)]
struct TurnAccumulator {
    text: String,
    tool_calls: Vec<ToolCall>,
    by_id: HashMap<String, usize>,
    usage: Usage,
    stop: Option<StopReason>,
}

impl TurnAccumulator {
    fn observe(&mut self, event: Event) -> Option<Event> {
        match event {
            Event::TextDelta(ref t) => {
                self.text.push_str(t);
                Some(event)
            }
            Event::Thinking(_) => Some(event),
            Event::ToolUseStart { ref id, ref name } => {
                self.by_id.insert(id.clone(), self.tool_calls.len());
                self.tool_calls.push(ToolCall {
                    id: id.clone(),
                    name: name.clone(),
                    args_json: String::new(),
                });
                Some(event)
            }
            Event::ToolUseDelta { ref id, ref json } => {
                if let Some(&pos) = self.by_id.get(id) {
                    self.tool_calls[pos].args_json.push_str(json);
                }
                Some(event)
            }
            Event::ToolUseEnd { .. } => Some(event),
            Event::Usage(u) => {
                self.usage = u; // providers emit one usage per turn; last wins
                None
            }
            Event::Done(s) => {
                self.stop = Some(s);
                None
            }
        }
    }

    fn to_assistant_message(&self) -> Message {
        let mut content = Vec::new();
        if !self.text.is_empty() {
            content.push(ContentBlock::text(self.text.clone()));
        }
        for call in &self.tool_calls {
            content.push(ContentBlock::ToolUse {
                id: call.id.clone(),
                name: call.name.clone(),
                input: call.parsed_args(),
            });
        }
        Message {
            role: Role::Assistant,
            content,
        }
    }
}

/// Head/tail truncation for oversized tool output, preserving both ends with a byte count.
fn truncate(s: &str, max_bytes: usize) -> String {
    if s.len() <= max_bytes {
        return s.to_string();
    }
    let keep_head = max_bytes * 2 / 3;
    let keep_tail = max_bytes / 3;
    let head: String = s.chars().take(keep_head).collect();
    let chars: Vec<char> = s.chars().collect();
    let tail_start = chars.len().saturating_sub(keep_tail);
    let tail: String = chars[tail_start..].iter().collect();
    let omitted = s.len().saturating_sub(head.len() + tail.len());
    format!("{head}\n... [{omitted} bytes truncated] ...\n{tail}")
}

#[cfg(test)]
mod tests {
    use super::*;
    use futures::stream;
    use std::sync::atomic::{AtomicUsize, Ordering};

    /// A provider that replays a fixed script of event lists, one per successive call.
    struct ScriptedProvider {
        calls: AtomicUsize,
        scripts: Vec<Vec<Event>>,
    }

    impl ScriptedProvider {
        fn new(scripts: Vec<Vec<Event>>) -> Arc<Self> {
            Arc::new(Self {
                calls: AtomicUsize::new(0),
                scripts,
            })
        }
    }

    #[async_trait]
    impl Provider for ScriptedProvider {
        async fn stream(
            &self,
            _req: ChatRequest,
        ) -> Result<
            BoxStream<'static, Result<Event, lvz_protocol::ProviderError>>,
            lvz_protocol::ProviderError,
        > {
            let n = self.calls.fetch_add(1, Ordering::SeqCst);
            let events = self.scripts.get(n).cloned().unwrap_or_default();
            Ok(stream::iter(events.into_iter().map(Ok)).boxed())
        }

        fn capabilities(&self) -> Capabilities {
            Capabilities::default()
        }
    }

    async fn collect(mut s: BoxStream<'static, Result<Event, AgentError>>) -> Vec<Event> {
        let mut out = Vec::new();
        while let Some(e) = s.next().await {
            out.push(e.expect("no agent error"));
        }
        out
    }

    #[tokio::test]
    async fn executes_a_tool_then_answers() {
        // Turn 1: call shell `echo lavoisier`. Turn 2: final text.
        let scripts = vec![
            vec![
                Event::ToolUseStart {
                    id: "t1".into(),
                    name: "shell".into(),
                },
                Event::ToolUseDelta {
                    id: "t1".into(),
                    json: "{\"command\":\"echo lavoisier\"}".into(),
                },
                Event::ToolUseEnd { id: "t1".into() },
                Event::Usage(Usage {
                    input_tokens: 50,
                    output_tokens: 10,
                    ..Default::default()
                }),
                Event::Done(StopReason::ToolUse),
            ],
            vec![
                Event::TextDelta("done".into()),
                Event::Usage(Usage {
                    input_tokens: 70,
                    output_tokens: 5,
                    ..Default::default()
                }),
                Event::Done(StopReason::EndTurn),
            ],
        ];
        let provider = ScriptedProvider::new(scripts);
        let agent = Agent::new(
            provider.clone(),
            ToolRegistry::with_builtins(),
            AgentConfig::default(),
        );

        let events = collect(agent.run("do it")).await;

        // The tool call streamed through.
        assert!(events
            .iter()
            .any(|e| matches!(e, Event::ToolUseStart { name, .. } if name == "shell")));
        // Final text present.
        assert!(events
            .iter()
            .any(|e| matches!(e, Event::TextDelta(t) if t == "done")));
        // Exactly one terminal Done, and it's the second turn's EndTurn.
        let dones: Vec<_> = events
            .iter()
            .filter(|e| matches!(e, Event::Done(_)))
            .collect();
        assert_eq!(dones.len(), 1);
        assert_eq!(dones[0], &Event::Done(StopReason::EndTurn));
        // Aggregate usage sums both round-trips: in 50+70=120, out 10+5=15.
        let usage = events
            .iter()
            .find_map(|e| match e {
                Event::Usage(u) => Some(*u),
                _ => None,
            })
            .expect("usage emitted");
        assert_eq!(usage.input_tokens, 120);
        assert_eq!(usage.output_tokens, 15);
        // Provider was called exactly twice.
        assert_eq!(provider.calls.load(Ordering::SeqCst), 2);
    }

    #[tokio::test]
    async fn enforces_token_budget() {
        let scripts = vec![vec![
            Event::TextDelta("hi".into()),
            Event::Usage(Usage {
                input_tokens: 1000,
                output_tokens: 1000,
                ..Default::default()
            }),
            Event::Done(StopReason::EndTurn),
        ]];
        let provider = ScriptedProvider::new(scripts);
        let agent = Agent::new(
            provider,
            ToolRegistry::new(),
            AgentConfig::default().with_budget(100),
        );

        let mut s = agent.run("hi");
        let mut saw_budget_error = false;
        while let Some(e) = s.next().await {
            if matches!(e, Err(AgentError::BudgetExceeded)) {
                saw_budget_error = true;
            }
        }
        assert!(saw_budget_error, "expected BudgetExceeded");
    }

    #[test]
    fn truncate_preserves_head_and_tail() {
        let s = "a".repeat(100);
        let out = truncate(&s, 30);
        assert!(out.starts_with('a'));
        assert!(out.contains("truncated"));
        assert!(out.len() < s.len() + 40);
    }
}
