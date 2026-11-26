//! Chat-origin confirm gate. Empty rules leave every call unchanged.
//!
//! A matching call is stored and not executed. `Origin::Schedule` never matches.
//! A missing live probe, or [`Liveness::Unknown`], counts as live.

use std::collections::{HashMap, VecDeque};
use std::fs::File;
use std::io::Read;
use std::sync::{LazyLock, Mutex};
use std::time::Duration;

use lvz_protocol::{live_probe, origin, ConfirmedCall, Event, Liveness, Origin};
use serde_json::Value;
use sha2::Digest;

/// One `[confirm.rule]`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ConfirmRule {
    /// Tool name.
    pub tool: String,
    /// When set, only these `action` values are gated. `None` gates every call.
    pub actions: Option<Vec<String>>,
    /// Gate only while the probe says live. Unknown counts as live.
    pub when_live: bool,
}

/// A stored call waiting for a second member.
#[derive(Debug, Clone)]
pub struct PendingConfirm {
    /// Audit code.
    pub code: String,
    /// Room id.
    pub room: String,
    /// Tool name.
    pub tool: String,
    /// Arguments that will be executed.
    pub args: Value,
    /// The member who asked.
    pub requester: String,
    /// Session the asking turn ran in.
    pub session: String,
    /// Sequence of the asking event.
    pub request_seq: u64,
    /// When the row was stored.
    pub created: tokio::time::Instant,
    /// When the row stops being acceptable.
    pub expires: tokio::time::Instant,
}

/// What `POST /v1/confirm` decided.
#[derive(Debug, Clone)]
pub enum ConfirmDecision {
    /// Run `pending`.
    Ready(PendingConfirm),
    /// Nothing runs. `notice` is the refusal.
    Refuse(&'static str),
}

struct Table {
    rows: HashMap<(String, String), PendingConfirm>,
    superseded: HashMap<String, ()>,
    seen: VecDeque<String>,
}

static TABLE: LazyLock<Mutex<Table>> = LazyLock::new(|| {
    Mutex::new(Table {
        rows: HashMap::new(),
        superseded: HashMap::new(),
        seen: VecDeque::new(),
    })
});

static RULES: Mutex<Vec<ConfirmRule>> = Mutex::new(Vec::new());
static EXPIRY: Mutex<Duration> = Mutex::new(Duration::from_secs(300));

/// Replace the rule list. Empty turns the gate off.
pub fn configure(rules: Vec<ConfirmRule>, expiry: Duration) {
    *RULES.lock().unwrap_or_else(|err| err.into_inner()) = rules;
    *EXPIRY.lock().unwrap_or_else(|err| err.into_inner()) = expiry;
}

/// Hold `name` when a rule matches this chat call.
///
/// `None` means the caller should invoke the tool.
pub async fn intercept(session: &str, name: &str, args: &Value) -> Option<(String, Event)> {
    let rules = RULES.lock().unwrap_or_else(|err| err.into_inner()).clone();
    if rules.is_empty() {
        return None;
    }
    let here = origin();
    if matches!(here, Origin::Schedule { .. }) {
        return None;
    }
    let Origin::Chat {
        sender, room, seq, ..
    } = here
    else {
        return None;
    };
    let rule = rules.iter().find(|rule| rule.tool == name)?;
    if let Some(actions) = &rule.actions {
        let action = args.get("action").and_then(Value::as_str).unwrap_or("");
        if !actions.iter().any(|item| item == action) {
            return None;
        }
    }
    if rule.when_live {
        let live = match live_probe() {
            Some(probe) => probe.live(name, args).await,
            None => Liveness::Live,
        };
        if live == Liveness::NotLive {
            return None;
        }
    }
    let Some(code) = fresh_code() else {
        return Some((
            "confirmation unavailable".to_string(),
            Event::Notice("confirmation unavailable".to_string()),
        ));
    };
    let expiry = *EXPIRY.lock().unwrap_or_else(|err| err.into_inner());
    let created = tokio::time::Instant::now();
    let pending = PendingConfirm {
        code: code.clone(),
        room: room.clone(),
        tool: name.to_string(),
        args: args.clone(),
        requester: sender,
        session: session.to_string(),
        request_seq: seq,
        created,
        expires: created + expiry,
    };
    store_row(pending);
    let event = Event::ConfirmRequired {
        code: code.clone(),
        room,
        tool: name.to_string(),
        expires_s: expiry.as_secs(),
    };
    Some((
        format!("confirmation required from another member (code {code})"),
        event,
    ))
}

/// Validate one confirm. On success the row is gone.
pub fn take_if(
    code: &str,
    room: &str,
    sender: &str,
    seq: u64,
    event_id: &str,
    permitted: impl Fn(&str) -> bool,
) -> ConfirmDecision {
    let mut table = TABLE.lock().unwrap_or_else(|err| err.into_inner());
    if table.seen.contains(&event_id.to_string()) {
        return ConfirmDecision::Refuse("이미 처리됨");
    }
    if table.superseded.contains_key(code) {
        return ConfirmDecision::Refuse("새 요청으로 대체됨");
    }
    let Some(key) = table
        .rows
        .iter()
        .find(|(_, row)| row.code == code)
        .map(|(key, _)| key.clone())
    else {
        return ConfirmDecision::Refuse("이미 처리됨");
    };
    let Some(row) = table.rows.get(&key) else {
        return ConfirmDecision::Refuse("이미 처리됨");
    };
    if tokio::time::Instant::now() >= row.expires {
        table.rows.remove(&key);
        return ConfirmDecision::Refuse("만료됨");
    }
    if row.room != room || seq <= row.request_seq || !permitted(&row.tool) {
        return ConfirmDecision::Refuse("권한 없음");
    }
    if row.requester == sender {
        return ConfirmDecision::Refuse("요청자 본인은 확인할 수 없음");
    }
    let Some(row) = table.rows.remove(&key) else {
        return ConfirmDecision::Refuse("이미 처리됨");
    };
    table.seen.push_back(event_id.to_string());
    while table.seen.len() > 1024 {
        table.seen.pop_front();
    }
    ConfirmDecision::Ready(row)
}

/// Canonical hash of `args`, for [`ConfirmedCall`].
pub fn args_hash(args: &Value) -> String {
    let text = canonical(args);
    let digest = sha2::Sha256::digest(text.as_bytes());
    digest.iter().take(8).fold(String::new(), |mut acc, byte| {
        acc.push_str(&format!("{byte:02x}"));
        acc
    })
}

/// The marker for a stored execution.
pub fn marker(tool: &str, args: &Value) -> lvz_protocol::ConfirmedCall {
    ConfirmedCall {
        tool: tool.to_string(),
        args_hash: args_hash(args),
    }
}

fn store_row(pending: PendingConfirm) {
    let mut table = TABLE.lock().unwrap_or_else(|err| err.into_inner());
    let key = (pending.room.clone(), pending.tool.clone());
    if let Some(old) = table.rows.insert(key, pending) {
        table.superseded.insert(old.code, ());
    }
}

fn fresh_code() -> Option<String> {
    let mut buf = [0u8; 4];
    let mut file = File::open("/dev/urandom").ok()?;
    file.read_exact(&mut buf).ok()?;
    const ALPHA: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
    let mut n = u32::from_le_bytes(buf);
    let mut out = String::new();
    for _ in 0..6 {
        let index = (n & 31) as usize;
        out.push(ALPHA[index] as char);
        n >>= 5;
    }
    Some(out)
}

fn canonical(value: &Value) -> String {
    match value {
        Value::Object(map) => {
            let mut keys: Vec<&String> = map.keys().collect();
            keys.sort();
            let mut out = String::from("{");
            for (i, key) in keys.iter().enumerate() {
                if i > 0 {
                    out.push(',');
                }
                out.push_str(&serde_json::to_string(key).unwrap_or_else(|_| "\"\"".into()));
                out.push(':');
                out.push_str(&canonical(&map[*key]));
            }
            out.push('}');
            out
        }
        Value::Array(items) => {
            let mut out = String::from("[");
            for (i, item) in items.iter().enumerate() {
                if i > 0 {
                    out.push(',');
                }
                out.push_str(&canonical(item));
            }
            out.push(']');
            out
        }
        other => other.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use lvz_protocol::enter_turn;
    use serde_json::json;

    fn rule(tool: &str, actions: Option<Vec<&str>>, when_live: bool) -> ConfirmRule {
        ConfirmRule {
            tool: tool.to_string(),
            actions: actions.map(|items| items.into_iter().map(str::to_string).collect()),
            when_live,
        }
    }

    #[tokio::test]
    async fn a_schedule_call_is_not_held_and_a_chat_stop_is() {
        configure(
            vec![rule("server_broadcast", Some(vec!["stop"]), false)],
            Duration::from_secs(300),
        );
        let schedule = enter_turn(
            None,
            Origin::Schedule {
                job: "broadcast".into(),
            },
            intercept("s", "server_broadcast", &json!({"action": "stop"})),
        )
        .await;
        assert!(schedule.is_none());
        let held = enter_turn(
            None,
            Origin::Chat {
                sender: "@a:ex".into(),
                room: "!r:ex".into(),
                event_id: "$e".into(),
                seq: 3,
            },
            intercept("s", "server_broadcast", &json!({"action": "stop"})),
        )
        .await;
        assert!(held.is_some());
        let start = enter_turn(
            None,
            Origin::Chat {
                sender: "@a:ex".into(),
                room: "!r:ex".into(),
                event_id: "$e".into(),
                seq: 4,
            },
            intercept("s", "server_broadcast", &json!({"action": "start"})),
        )
        .await;
        assert!(start.is_none());
        configure(
            vec![rule("obs_macro", None, false)],
            Duration::from_secs(300),
        );
        let held = enter_turn(
            None,
            Origin::Chat {
                sender: "@a:ex".into(),
                room: "!r:ex".into(),
                event_id: "$e".into(),
                seq: 1,
            },
            intercept("s", "obs_macro", &json!({})),
        )
        .await;
        let code = match held.unwrap().1 {
            Event::ConfirmRequired { code, .. } => code,
            other => panic!("unexpected {other:?}"),
        };
        assert!(matches!(
            take_if(&code, "!r:ex", "@a:ex", 2, "$c1", |_| true),
            ConfirmDecision::Refuse("요청자 본인은 확인할 수 없음")
        ));
        assert!(matches!(
            take_if(&code, "!r:ex", "@b:ex", 2, "$c1", |_| false),
            ConfirmDecision::Refuse("권한 없음")
        ));
        assert!(matches!(
            take_if(&code, "!r:ex", "@b:ex", 2, "$c1", |_| true),
            ConfirmDecision::Ready(_)
        ));
        configure(Vec::new(), Duration::from_secs(300));
    }
}
