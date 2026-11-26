//! The "<job> 취소해줘" hook.
//!
//! It runs before any model call, on the trusted [`TurnContext::raw_input`], and only for a
//! chat-origin turn. The gateway is what decides the message was addressed. A turn that was
//! not addressed never arrives here; [`interpret`] still takes `engaged` so a test can show
//! an un-addressed line is ignored.

use std::sync::Mutex;

use futures::StreamExt;
use lvz_protocol::{
    origin, tool_permitted, turn_context, ChatRequest, Event, JobId, Message, Origin, Provider,
    ToolChoice,
};

use crate::jobs::{self, UserCancel};

/// One Korean phrase and the tool it names. The phrase is not a tool name.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CancelAlias {
    /// What the person typed, such as `빌드`.
    pub phrase: String,
    /// Tool the phrase selects.
    pub tool: String,
}

/// A cancel the hook actually performed. The trace store reads these later.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CancelCommand {
    /// Sender from the trusted context.
    pub sender: String,
    /// Job id that was cancelled.
    pub job: String,
    /// `id` or `alias`.
    pub matched_by: String,
}

static RECORDS: Mutex<Vec<CancelCommand>> = Mutex::new(Vec::new());

/// The aliases named for the Korean cancel phrase. Config replaces this list when it sets one.
pub fn default_aliases() -> Vec<CancelAlias> {
    [
        ("빌드", "run_build"),
        ("켜기", "server_wake"),
        ("부팅", "server_wake"),
        ("끄기", "server_shutdown"),
        ("종료", "server_shutdown"),
        ("방송 시작", "server_broadcast"),
        ("방송 중지", "server_broadcast"),
        ("방송 종료", "server_broadcast"),
    ]
    .into_iter()
    .map(|(phrase, tool)| CancelAlias {
        phrase: phrase.to_string(),
        tool: tool.to_string(),
    })
    .collect()
}

/// Records taken since the last call. Tests and the trace store use this.
pub fn take_cancel_records() -> Vec<CancelCommand> {
    let mut guard = RECORDS.lock().unwrap_or_else(|err| err.into_inner());
    std::mem::take(&mut *guard)
}

const SCHEDULE_REFUSAL: &str = "예약 작업은 취소할 수 없습니다";

/// Decide what a chat line does.
///
/// `None` means the line is not a cancel command, so the normal turn runs.
/// `Some` is the raw notice. The caller phrases it, and posts this text if phrasing fails.
pub fn interpret(
    session: &str,
    grant: Option<&[String]>,
    aliases: &[CancelAlias],
    engaged: bool,
) -> Option<String> {
    if !engaged {
        return None;
    }
    if !matches!(origin(), Origin::Chat { .. }) {
        return None;
    }
    let raw = turn_context().map(|ctx| ctx.raw_input).unwrap_or_default();
    let job = parse_cancel(&raw)?;
    let sender = turn_context().map(|ctx| ctx.sender).unwrap_or_default();
    Some(resolve(session, grant, aliases, &job, &sender))
}

fn resolve(
    session: &str,
    grant: Option<&[String]>,
    aliases: &[CancelAlias],
    job: &str,
    sender: &str,
) -> String {
    if let Ok(id) = JobId::new(job) {
        match jobs::global().cancel_for_user(session, &id, grant) {
            UserCancel::Unknown => {}
            other => return finish_user(other, "id", sender),
        }
    }
    let tools: Vec<&str> = aliases
        .iter()
        .filter(|alias| alias.phrase == job)
        .map(|alias| alias.tool.as_str())
        .collect();
    if tools.is_empty() {
        return list_notice(session);
    }
    let hits: Vec<_> = jobs::global()
        .list_running(session)
        .into_iter()
        .filter(|row| tools.contains(&row.tool.as_str()))
        .collect();
    match hits.as_slice() {
        [] => list_notice(session),
        [one] if one.origin == "schedule" => SCHEDULE_REFUSAL.to_string(),
        [one] if !tool_permitted(grant, &one.tool) => "권한 없음".to_string(),
        [one] => {
            let id = match JobId::new(&one.id) {
                Ok(id) => id,
                Err(_) => return list_notice(session),
            };
            finish_user(
                jobs::global().cancel_for_user(session, &id, grant),
                "alias",
                sender,
            )
        }
        _ => list_notice(session),
    }
}

fn finish_user(outcome: UserCancel, matched_by: &str, sender: &str) -> String {
    match outcome {
        UserCancel::Cancelled { id, tool } => {
            let mut guard = RECORDS.lock().unwrap_or_else(|err| err.into_inner());
            guard.push(CancelCommand {
                sender: sender.to_string(),
                job: id.clone(),
                matched_by: matched_by.to_string(),
            });
            format!("cancelled {id} ({tool})")
        }
        UserCancel::Schedule => SCHEDULE_REFUSAL.to_string(),
        UserCancel::Denied => "권한 없음".to_string(),
        UserCancel::Finished { id, tool, text } => {
            format!("job {id} ({tool}) already finished: {text}")
        }
        UserCancel::Unknown => list_notice(""),
    }
}

fn list_notice(session: &str) -> String {
    let rows = if session.is_empty() {
        Vec::new()
    } else {
        jobs::global().list_running(session)
    };
    if rows.is_empty() {
        return "실행 중인 작업이 없습니다.".to_string();
    }
    let mut text = String::from("어떤 작업인지 모르겠습니다.");
    for row in rows {
        text.push('\n');
        text.push_str(&format!(
            "{} · {} · {}s · {}",
            row.id, row.tool, row.age_s, row.step
        ));
    }
    text
}

/// `Some(job)` when `raw` is `<job> 취소해줘` with an optional trailing `.` or `!`.
pub fn parse_cancel(raw: &str) -> Option<String> {
    let trimmed = raw.trim();
    let trimmed = trimmed
        .strip_suffix(['.', '!'])
        .map(str::trim_end)
        .unwrap_or(trimmed);
    let idx = trimmed.rfind("취소해")?;
    let (job, tail) = trimmed.split_at(idx);
    let tail = tail["취소해".len()..].trim_start();
    if tail != "줘" {
        return None;
    }
    let job = job.trim();
    if job.is_empty() {
        None
    } else {
        Some(job.to_string())
    }
}

/// One short tool-less rewrite of `raw`. `None` when the provider fails or returns nothing.
pub async fn phrase(
    provider: &std::sync::Arc<dyn Provider>,
    model: &str,
    raw: &str,
) -> Option<String> {
    let req = ChatRequest::new(model)
        .max_tokens(200)
        .system("Rewrite this notice in one short sentence. Do not add facts or call tools.")
        .tool_choice(ToolChoice::None)
        .push(Message::user(raw.to_string()));
    let mut stream = provider.stream(req).await.ok()?;
    let mut text = String::new();
    while let Some(event) = stream.next().await {
        match event {
            Ok(Event::TextDelta(delta)) => text.push_str(&delta),
            Ok(_) => {}
            Err(_) => return None,
        }
    }
    let text = text.trim().to_string();
    if text.is_empty() {
        None
    } else {
        Some(text)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use lvz_protocol::{enter_turn, Origin, ToolOutput, TurnContext};
    use tokio_util::sync::CancellationToken;
    fn ctx(raw: &str) -> TurnContext {
        TurnContext {
            sender: "@a:example".into(),
            room: "!r:example".into(),
            raw_input: raw.into(),
            ..TurnContext::default()
        }
    }

    fn reserve(session: &str, tool: &str, id: &str) {
        let parent = CancellationToken::new();
        jobs::global()
            .reserve(
                session,
                tool,
                JobId::new(id).expect("id"),
                Some(30),
                &parent,
            )
            .expect("reserve");
    }

    #[test]
    fn grammar_accepts_the_spaced_form_and_a_trailing_mark() {
        assert_eq!(parse_cancel("빌드 취소해줘").as_deref(), Some("빌드"));
        assert_eq!(parse_cancel("  빌드  취소해 줘. ").as_deref(), Some("빌드"));
        assert_eq!(parse_cancel("wake1 취소해 줘!").as_deref(), Some("wake1"));
        assert_eq!(parse_cancel("취소해줘"), None);
        assert_eq!(parse_cancel("빌드를 취소해 주세요"), None);
    }

    #[tokio::test]
    async fn exact_id_cancels_and_a_tool_name_does_not() {
        let _ = take_cancel_records();
        jobs::global().clear_session("c1");
        reserve("c1", "server_wake", "wake1");
        let aliases = default_aliases();
        let text = enter_turn(Some(ctx("wake1 취소해줘")), Origin::Cli, async {
            interpret("c1", None, &aliases, true)
        })
        .await;
        assert_eq!(text.as_deref(), None, "cli origin is not a chat command");

        let text = enter_turn(
            Some(ctx("wake1 취소해줘")),
            Origin::Chat {
                sender: "@a:example".into(),
                room: "!r:example".into(),
                event_id: "$e".into(),
                seq: 1,
            },
            async { interpret("c1", None, &aliases, true) },
        )
        .await
        .expect("handled");
        assert!(text.contains("cancelled wake1"), "{text}");
        let recs = take_cancel_records();
        assert_eq!(recs.len(), 1);
        assert_eq!(recs[0].matched_by, "id");
        assert!(!jobs::job_running(&JobId::new("wake1").expect("id")));

        reserve("c1", "server_wake", "wake2");
        let text = enter_turn(
            Some(ctx("server_wake 취소해줘")),
            Origin::Chat {
                sender: "@a:example".into(),
                room: "!r:example".into(),
                event_id: "$e".into(),
                seq: 2,
            },
            async { interpret("c1", None, &aliases, true) },
        )
        .await
        .expect("list");
        assert!(text.contains("wake2"), "{text}");
        assert!(jobs::job_running(&JobId::new("wake2").expect("id")));
        jobs::global().clear_session("c1");
    }

    #[tokio::test]
    async fn alias_cancels_one_match_and_lists_when_ambiguous() {
        let _ = take_cancel_records();
        jobs::global().clear_session("c2");
        reserve("c2", "run_build", "b1");
        reserve("c2", "run_build", "b2");
        let aliases = default_aliases();
        let chat = Origin::Chat {
            sender: "@a:example".into(),
            room: "!r:example".into(),
            event_id: "$e".into(),
            seq: 1,
        };
        let text = enter_turn(Some(ctx("빌드 취소해줘")), chat.clone(), async {
            interpret("c2", None, &aliases, true)
        })
        .await
        .expect("list");
        assert!(text.contains("b1") && text.contains("b2"), "{text}");
        assert!(take_cancel_records().is_empty());
        jobs::global().clear_session("c2");
        reserve("c2", "run_build", "b3");
        let text = enter_turn(Some(ctx("빌드 취소해줘")), chat, async {
            interpret("c2", None, &aliases, true)
        })
        .await
        .expect("cancel");
        assert!(text.contains("cancelled b3"), "{text}");
        assert_eq!(take_cancel_records()[0].matched_by, "alias");
        jobs::global().clear_session("c2");
    }

    #[tokio::test]
    async fn unaddressed_schedule_permission_and_finished() {
        let _ = take_cancel_records();
        jobs::global().clear_session("c3");
        reserve("c3", "server_wake", "wake3");
        let aliases = default_aliases();
        let chat = Origin::Chat {
            sender: "@a:example".into(),
            room: "!r:example".into(),
            event_id: "$e".into(),
            seq: 1,
        };
        let ignored = enter_turn(Some(ctx("wake3 취소해줘")), chat.clone(), async {
            interpret("c3", None, &aliases, false)
        })
        .await;
        assert_eq!(ignored, None);
        assert!(jobs::job_running(&JobId::new("wake3").expect("id")));

        let denied = enter_turn(Some(ctx("wake3 취소해줘")), chat.clone(), async {
            interpret("c3", Some(&["read".into()]), &aliases, true)
        })
        .await
        .expect("denied");
        assert_eq!(denied, "권한 없음");
        assert!(jobs::job_running(&JobId::new("wake3").expect("id")));

        jobs::global().finish(
            JobId::new("wake3").expect("id"),
            Ok(ToolOutput::ok("powered on")),
        );
        let finished = enter_turn(Some(ctx("wake3 취소해줘")), chat.clone(), async {
            interpret("c3", None, &aliases, true)
        })
        .await
        .expect("finished");
        assert!(finished.contains("already finished"), "{finished}");
        assert!(finished.contains("powered on"), "{finished}");
        jobs::global().clear_session("c3");

        enter_turn(
            None,
            Origin::Schedule {
                job: "nightly".into(),
            },
            async { reserve("c3", "server_wake", "sched1") },
        )
        .await;
        let refused = enter_turn(Some(ctx("sched1 취소해줘")), chat, async {
            interpret("c3", None, &aliases, true)
        })
        .await
        .expect("refused");
        assert_eq!(refused, SCHEDULE_REFUSAL);
        assert!(jobs::job_running(&JobId::new("sched1").expect("id")));
        jobs::global().clear_session("c3");
    }
}
