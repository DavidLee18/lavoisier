//! `lvz-legion` — a multi-model **council** ("legion") that argues out a task before the agent
//! acts.
//!
//! A [`Panel`] holds a list of [`Debater`]s (each a `provider` + `model`) and a judge. Given a
//! task it runs three phases — **draft**, **critique**, **judge** — and returns one agreed
//! [`Deliberation`] (a plan-of-action plus the total token cost). The agent injects that plan as
//! the executor's opening move (*deliberate-then-act*), so the models argue about *what to do and
//! how to reply*, then the normal tool-using loop carries the agreed plan out.
//!
//! This crate implements the [`Deliberator`] contract from `lvz-protocol` and depends only on that
//! keystone — it knows nothing of the agent, the CLI, or any gateway (dependencies point inward).
//! The arguing is **internal**: the round-by-round transcript goes to `tracing`, and only the
//! judge's synthesis leaves the council.

#![warn(missing_docs)]

use std::fmt::Write as _;
use std::sync::Arc;

use futures::StreamExt;

use lvz_protocol::{
    ChatRequest, DeliberateError, Deliberation, Deliberator, Event, Message, Provider,
    ThinkingLevel, Usage,
};

/// Token ceiling for a single debater's draft/critique call. Positions are meant to be concise
/// argument, not essays, so this is modest.
const DEBATER_MAX_TOKENS: u32 = 1024;
/// Token ceiling for the judge's synthesis — a little larger, since it folds the whole panel into
/// one agreed plan.
const JUDGE_MAX_TOKENS: u32 = 2048;

/// System prompt for the opening **draft** round: each debater proposes independently.
const LEGION_DRAFT_SYSTEM: &str = "\
You are one member of a council of AI models deliberating on how to handle a task before any \
action is taken. Propose, concretely: (1) what should actually be done — the plan of action, \
including any tools/steps — and (2) what the reply to the user should say. Be specific and \
opinionated; state assumptions and call out risks. This is a first draft other members will \
critique, so make your reasoning legible. Keep it tight.";

/// System prompt for a **critique** round: each debater sees the panel and revises.
const LEGION_CRITIQUE_SYSTEM: &str = "\
You are one member of a deliberating council of AI models. You are shown the whole panel's current \
positions. Critique the others where they are wrong, risky, or incomplete, concede points that are \
better than yours, and then produce your own REVISED position — the plan of action and the reply \
you now stand behind. Argue for the strongest overall outcome, not merely your original take. Keep \
it tight.";

/// System prompt for the **judge**: synthesise the argument into one agreed plan.
const LEGION_JUDGE_SYSTEM: &str = "\
You are the judge of a council of AI models that has deliberated a task. You are shown every \
member's final position. Synthesise them into a SINGLE agreed plan of action for an executor agent \
to carry out, plus the key points the final reply to the user should make. Resolve disagreements \
on the merits, keep what is strongest, and drop what the debate showed to be wrong. Output only the \
agreed plan and reply points — no meta-commentary about the debate itself.";

/// Errors constructing a [`Panel`]. (Runtime deliberation failures use
/// [`DeliberateError`](lvz_protocol::DeliberateError).)
#[derive(Debug, thiserror::Error)]
pub enum LegionError {
    /// A council needs at least two debaters — a single model is just the advisor pre-pass.
    #[error("a legion panel needs at least 2 debaters, got {0}")]
    TooFewDebaters(usize),
}

/// One member of the council: a provider handle paired with the model id it should argue under.
///
/// The panel holds real [`Arc<dyn Provider>`](lvz_protocol::Provider)s, so a council can mix
/// providers freely (e.g. Anthropic vs. xAI vs. Google) — cross-provider panels are first-class.
#[derive(Clone)]
pub struct Debater {
    /// Human-readable label used in the debate transcript and logs (e.g. `"anthropic:opus"`).
    pub name: String,
    /// The backend this debater speaks through.
    pub provider: Arc<dyn Provider>,
    /// The model id passed in each [`ChatRequest`](lvz_protocol::ChatRequest).
    pub model: String,
    /// Optional extended-thinking effort for this debater. `None` defers to the provider default.
    pub thinking: Option<ThinkingLevel>,
}

impl Debater {
    /// Construct a debater from its parts.
    pub fn new(
        name: impl Into<String>,
        provider: Arc<dyn Provider>,
        model: impl Into<String>,
        thinking: Option<ThinkingLevel>,
    ) -> Self {
        Self {
            name: name.into(),
            provider,
            model: model.into(),
            thinking,
        }
    }
}

impl std::fmt::Debug for Debater {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        // `Arc<dyn Provider>` isn't Debug; show the identifying fields only.
        f.debug_struct("Debater")
            .field("name", &self.name)
            .field("model", &self.model)
            .field("thinking", &self.thinking)
            .finish_non_exhaustive()
    }
}

/// A council of debaters plus a judge. Implements [`Deliberator`].
#[derive(Clone, Debug)]
pub struct Panel {
    debaters: Vec<Debater>,
    judge: Debater,
    rounds: usize,
}

impl Panel {
    /// Build a panel from its debaters, a judge, and the number of **critique** rounds to run
    /// after the initial draft (`0` = draft then judge, no back-and-forth).
    ///
    /// Fails with [`LegionError::TooFewDebaters`] if fewer than two debaters are given — a
    /// one-model "council" is just the advisor pre-pass, and legion is about the argument between
    /// models.
    pub fn new(debaters: Vec<Debater>, judge: Debater, rounds: usize) -> Result<Self, LegionError> {
        if debaters.len() < 2 {
            return Err(LegionError::TooFewDebaters(debaters.len()));
        }
        Ok(Self {
            debaters,
            judge,
            rounds,
        })
    }

    /// The debaters on this panel.
    pub fn debaters(&self) -> &[Debater] {
        &self.debaters
    }

    /// The number of critique rounds this panel runs after the draft.
    pub fn rounds(&self) -> usize {
        self.rounds
    }
}

/// Ask one debater for a position: one tool-less streamed call, drained to `(text, usage)`.
/// Returns `None` if the call errors or produces empty output (best-effort — a dropped debater
/// just doesn't contribute to this run).
async fn ask(
    debater: &Debater,
    system: &str,
    user: String,
    max_tokens: u32,
) -> Option<(String, Usage)> {
    let mut req = ChatRequest::new(debater.model.clone())
        .max_tokens(max_tokens)
        .system(system)
        .push(Message::user(user));
    if let Some(level) = debater.thinking {
        req = req.thinking(level);
    }

    let mut stream = debater.provider.stream(req).await.ok()?;
    let mut text = String::new();
    let mut usage = Usage::default();
    while let Some(event) = stream.next().await {
        match event {
            Ok(Event::TextDelta(t)) => text.push_str(&t),
            Ok(Event::Usage(u)) => usage = u,
            Ok(_) => {}
            Err(_) => return None,
        }
    }
    (!text.trim().is_empty()).then_some((text, usage))
}

/// Render the surviving positions into a labelled board the panel and judge read.
fn render_positions(debaters: &[Debater], positions: &[Option<String>]) -> String {
    let mut out = String::new();
    for (d, p) in debaters.iter().zip(positions) {
        if let Some(text) = p {
            let _ = write!(out, "### {} ({})\n{}\n\n", d.name, d.model, text.trim());
        }
    }
    out
}

#[async_trait::async_trait]
impl Deliberator for Panel {
    async fn deliberate(&self, task: &str) -> Result<Deliberation, DeliberateError> {
        tracing::info!(
            debaters = self.debaters.len(),
            rounds = self.rounds,
            judge = %self.judge.name,
            "legion convened"
        );

        let mut positions: Vec<Option<String>> = vec![None; self.debaters.len()];
        let mut usage = Usage::default();

        // Phase 1 — draft round: every debater proposes independently, concurrently.
        let draft_futs = self.debaters.iter().enumerate().map(|(i, d)| {
            let user = task.to_string();
            async move {
                (
                    i,
                    ask(d, LEGION_DRAFT_SYSTEM, user, DEBATER_MAX_TOKENS).await,
                )
            }
        });
        for (i, res) in futures::future::join_all(draft_futs).await {
            match res {
                Some((text, u)) => {
                    usage.accumulate(&u);
                    tracing::debug!(debater = %self.debaters[i].name, bytes = text.len(), "legion draft");
                    positions[i] = Some(text);
                }
                None => {
                    tracing::warn!(debater = %self.debaters[i].name, "legion draft failed; debater dropped this run")
                }
            }
        }
        if positions.iter().all(Option::is_none) {
            return Err(DeliberateError::NoPositions);
        }

        // Phase 2 — critique rounds: each debater sees the board and revises, concurrently.
        for round in 0..self.rounds {
            let board = render_positions(&self.debaters, &positions);
            let crit_futs = self.debaters.iter().enumerate().map(|(i, d)| {
                let user = format!(
                    "TASK:\n{task}\n\nTHE PANEL'S CURRENT POSITIONS:\n{board}\nYou are \"{name}\". \
                     Critique the others and give your revised position.",
                    name = d.name
                );
                async move {
                    (
                        i,
                        ask(d, LEGION_CRITIQUE_SYSTEM, user, DEBATER_MAX_TOKENS).await,
                    )
                }
            });
            for (i, res) in futures::future::join_all(crit_futs).await {
                if let Some((text, u)) = res {
                    usage.accumulate(&u);
                    positions[i] = Some(text);
                }
            }
            tracing::debug!(round = round + 1, "legion critique round complete");
        }

        // Phase 3 — judge synthesis.
        let board = render_positions(&self.debaters, &positions);
        let judge_user = format!("TASK:\n{task}\n\nFINAL PANEL POSITIONS:\n{board}");
        match ask(
            &self.judge,
            LEGION_JUDGE_SYSTEM,
            judge_user,
            JUDGE_MAX_TOKENS,
        )
        .await
        {
            Some((plan, u)) => {
                usage.accumulate(&u);
                tracing::info!(
                    plan_bytes = plan.len(),
                    tokens = usage.total(),
                    "legion reached a verdict"
                );
                Ok(Deliberation { plan, usage })
            }
            None => Err(DeliberateError::Judge("judge returned no synthesis".into())),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use futures::stream::{self, BoxStream};
    use lvz_protocol::{Capabilities, ProviderError, StopReason};

    /// A provider that replies with one fixed text (and usage), or always errors.
    struct Scripted {
        reply: String,
        usage: Usage,
        fail: bool,
    }

    #[async_trait::async_trait]
    impl Provider for Scripted {
        async fn stream(
            &self,
            _req: ChatRequest,
        ) -> Result<BoxStream<'static, Result<Event, ProviderError>>, ProviderError> {
            if self.fail {
                return Err(ProviderError::Transport("scripted failure".into()));
            }
            let events = vec![
                Ok(Event::TextDelta(self.reply.clone())),
                Ok(Event::Usage(self.usage)),
                Ok(Event::Done(StopReason::EndTurn)),
            ];
            Ok(stream::iter(events).boxed())
        }
        fn capabilities(&self) -> Capabilities {
            Capabilities::default()
        }
    }

    /// A debater whose every call yields `reply` and 10 output tokens.
    fn debater(name: &str, reply: &str) -> Debater {
        Debater::new(
            name,
            Arc::new(Scripted {
                reply: reply.into(),
                usage: Usage {
                    output_tokens: 10,
                    ..Default::default()
                },
                fail: false,
            }),
            format!("{name}-model"),
            None,
        )
    }

    /// A debater whose every call errors.
    fn failing(name: &str) -> Debater {
        Debater::new(
            name,
            Arc::new(Scripted {
                reply: String::new(),
                usage: Usage::default(),
                fail: true,
            }),
            format!("{name}-model"),
            None,
        )
    }

    #[test]
    fn panel_rejects_fewer_than_two_debaters() {
        let err = Panel::new(vec![debater("solo", "x")], debater("judge", "v"), 1).unwrap_err();
        assert!(matches!(err, LegionError::TooFewDebaters(1)));
    }

    #[tokio::test]
    async fn deliberate_drafts_critiques_and_judges() {
        let panel = Panel::new(
            vec![debater("a", "position A"), debater("b", "position B")],
            debater("judge", "AGREED PLAN"),
            1,
        )
        .unwrap();

        let out = panel.deliberate("do the thing").await.unwrap();
        assert_eq!(out.plan, "AGREED PLAN");
        // 2 drafts + 2 critiques (1 round) + 1 judge = 5 calls × 10 output tokens.
        assert_eq!(out.usage.output_tokens, 50);
    }

    #[tokio::test]
    async fn rounds_knob_changes_the_call_count() {
        let panel = Panel::new(
            vec![debater("a", "A"), debater("b", "B")],
            debater("judge", "PLAN"),
            0, // draft then judge, no critique
        )
        .unwrap();

        let out = panel.deliberate("task").await.unwrap();
        // 2 drafts + 0 critiques + 1 judge = 3 calls × 10.
        assert_eq!(out.usage.output_tokens, 30);
    }

    #[tokio::test]
    async fn a_failing_debater_is_tolerated() {
        let panel = Panel::new(
            vec![failing("a"), debater("b", "position B")],
            debater("judge", "PLAN"),
            1,
        )
        .unwrap();

        let out = panel.deliberate("task").await.unwrap();
        assert_eq!(out.plan, "PLAN");
        // Only debater b contributes: 1 draft + 1 critique + 1 judge = 3 × 10.
        assert_eq!(out.usage.output_tokens, 30);
    }

    #[tokio::test]
    async fn all_debaters_failing_yields_no_positions() {
        let panel = Panel::new(
            vec![failing("a"), failing("b")],
            debater("judge", "PLAN"),
            1,
        )
        .unwrap();
        let err = panel.deliberate("task").await.unwrap_err();
        assert!(matches!(err, DeliberateError::NoPositions));
    }
}
