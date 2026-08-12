//! `lvz-gw-tui` — an **inline terminal-UI** frontend for Lavoisier.
//!
//! An interactive, scrollback-native REPL: it drives the shared agent via [`AgentHandle`] and
//! renders the normalised [`Event`] stream as a chat. Unlike a fullscreen (alt-screen) TUI, it uses
//! ratatui's **inline viewport** — finalized output flows into the terminal's own scrollback (so
//! natural scrolling, copy/paste, and `Ctrl-L` all work), while a small live region at the bottom
//! holds the input box, a status/spinner line, and a token/cost footer.
//!
//! It is a **leaf frontend**: it depends only on `lvz-protocol` (the [`Gateway`]/[`AgentHandle`]
//! contracts + the [`Event`] stream), never on a provider or on `lvz-agent`'s internals, so the same
//! shared agent drives the CLI, every network gateway, and this TUI unchanged.
//!
//! Concurrency: the render loop `select!`s over crossterm's async event stream and an mpsc channel
//! fed by the **current turn's** agent stream, which runs on a **spawned task** (never inline in the
//! loop) — that separation is what lets a future tool-approval prompt be answered while a turn is
//! mid-flight without deadlocking the stream that is waiting on the answer.

#![warn(missing_docs)]

use std::io::{self, Stdout};
use std::sync::Arc;

use async_trait::async_trait;
use crossterm::event::{Event as CtEvent, EventStream, KeyCode, KeyEventKind, KeyModifiers};
use crossterm::terminal::{disable_raw_mode, enable_raw_mode};
use futures::StreamExt;
use lvz_protocol::{
    AgentHandle, CostWeights, Event, Gateway, GatewayError, StopReason, TurnRequest, Usage,
};
use ratatui::backend::CrosstermBackend;
use ratatui::layout::{Constraint, Layout, Rect};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span, Text};
use ratatui::widgets::{Block, Borders, Paragraph, Widget};
use ratatui::{Terminal, TerminalOptions, Viewport};
use tokio::sync::mpsc;
use tokio::task::JoinHandle;
use tui_textarea::TextArea;
use unicode_width::UnicodeWidthStr;

mod gate;
use gate::PermitReply;
pub use gate::{ChannelGate, PermitRequest};

/// The inline viewport height: one status line + a 3-row bordered input + one footer line.
const VIEWPORT_HEIGHT: u16 = 5;

/// A live terminal over stdout with an inline viewport.
type Term = Terminal<CrosstermBackend<Stdout>>;

/// A message from the current turn's spawned task to the render loop, tagged with the turn
/// generation so events from a cancelled/superseded turn are ignored.
enum TurnMsg {
    /// One normalised event from the agent stream.
    Event(Event),
    /// The turn's stream errored (submit failure or mid-stream error).
    Error(String),
    /// The turn's stream ended (clean finish or drop).
    Finished,
}

/// The inline-TUI gateway. Construct with [`TuiGateway::new`] (optionally naming the model/session
/// for the footer), then [`Gateway::serve`] it with an [`AgentHandle`]. It takes over the terminal
/// for the duration.
pub struct TuiGateway {
    session: String,
    model: String,
    /// The approval-prompt receiver, present when a [`ChannelGate`] is installed on the agent. Held
    /// in a `Mutex<Option<…>>` because [`Gateway::serve`] takes `Arc<Self>` (shared), yet the render
    /// loop must *own* the receiver — it is `take`n out on the single serve call.
    permits: std::sync::Mutex<Option<mpsc::Receiver<PermitRequest>>>,
}

impl Default for TuiGateway {
    fn default() -> Self {
        Self {
            session: "tui".into(),
            model: "agent".into(),
            permits: std::sync::Mutex::new(None),
        }
    }
}

impl TuiGateway {
    /// A new gateway with the default session (`tui`) and a generic model label.
    pub fn new() -> Self {
        Self::default()
    }

    /// Set the session id conversations run under (so memory accrues across turns).
    pub fn with_session(mut self, session: impl Into<String>) -> Self {
        self.session = session.into();
        self
    }

    /// Set the model label shown in the footer (cosmetic).
    pub fn with_model(mut self, model: impl Into<String>) -> Self {
        self.model = model.into();
        self
    }

    /// Attach the approval-prompt receiver paired with a [`ChannelGate`] installed on the agent, so
    /// the render loop can drive interactive tool-approval prompts. Without it, no prompts appear.
    pub fn with_permits(self, permits: mpsc::Receiver<PermitRequest>) -> Self {
        *self.permits.lock().expect("permits lock poisoned") = Some(permits);
        self
    }
}

#[async_trait]
impl Gateway for TuiGateway {
    fn name(&self) -> &str {
        "tui"
    }

    async fn serve(self: Arc<Self>, agent: Arc<dyn AgentHandle>) -> Result<(), GatewayError> {
        run(&self, agent)
            .await
            .map_err(|e| GatewayError::Io(e.to_string()))
    }
}

/// Enter raw mode, install a panic hook that restores the terminal, and return a ready inline
/// terminal. The returned [`TermGuard`] restores cooked mode on drop.
fn setup() -> io::Result<(Term, TermGuard)> {
    // Restore the terminal even if a later panic unwinds through the render loop.
    let prev = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        let _ = disable_raw_mode();
        prev(info);
    }));
    enable_raw_mode()?;
    let backend = CrosstermBackend::new(io::stdout());
    let terminal = Terminal::with_options(
        backend,
        TerminalOptions {
            viewport: Viewport::Inline(VIEWPORT_HEIGHT),
        },
    )?;
    Ok((terminal, TermGuard))
}

/// Restores cooked mode on drop, so any early return or `?` leaves the terminal usable.
struct TermGuard;
impl Drop for TermGuard {
    fn drop(&mut self) {
        let _ = disable_raw_mode();
    }
}

/// The interactive session: set up the terminal, then loop rendering the viewport and folding
/// terminal input + agent events until the user quits (Ctrl-C / Ctrl-D on an empty prompt).
async fn run(gw: &TuiGateway, agent: Arc<dyn AgentHandle>) -> io::Result<()> {
    let (mut term, _guard) = setup()?;
    let mut app = App::new(gw.session.clone(), gw.model.clone());
    let mut keys = EventStream::new();
    let (turn_tx, mut turn_rx) = mpsc::channel::<(u64, TurnMsg)>(256);
    // Present only when a ChannelGate is installed; else approval prompts never fire.
    let mut permits = gw.permits.lock().expect("permits lock poisoned").take();

    scrollback::emit_welcome(&mut term)?;
    term.draw(|f| app.draw(f))?;

    loop {
        tokio::select! {
            maybe_key = keys.next() => {
                match maybe_key {
                    Some(Ok(ev)) => {
                        if handle_terminal_event(&mut term, &mut app, &agent, &turn_tx, ev)? {
                            break; // quit requested
                        }
                    }
                    Some(Err(e)) => return Err(e),
                    None => break, // stdin closed
                }
            }
            Some((gen, msg)) = turn_rx.recv() => {
                if gen == app.turn_gen {
                    handle_turn_msg(&mut term, &mut app, msg)?;
                }
            }
            // A tool wants approval. `pending()` parks this arm forever when no gate is installed.
            maybe_permit = recv_permit(&mut permits) => {
                if let Some(req) = maybe_permit {
                    app.pending_permit = Some(req);
                }
            }
        }
        term.draw(|f| app.draw(f))?;
    }

    // Leave the cursor on a fresh line below the (now-final) viewport.
    let _ = term.clear();
    println!();
    Ok(())
}

/// Handle one terminal event. Returns `Ok(true)` when the user asked to quit.
fn handle_terminal_event(
    term: &mut Term,
    app: &mut App,
    agent: &Arc<dyn AgentHandle>,
    turn_tx: &mpsc::Sender<(u64, TurnMsg)>,
    ev: CtEvent,
) -> io::Result<bool> {
    if let CtEvent::Key(key) = ev {
        if key.kind == KeyEventKind::Release {
            return Ok(false); // only act on press/repeat
        }
        let ctrl = key.modifiers.contains(KeyModifiers::CONTROL);
        // Ctrl-C always wins — even mid-approval — so the user is never trapped.
        if ctrl && matches!(key.code, KeyCode::Char('c')) {
            if app.running {
                app.cancel_turn();
                scrollback::emit_notice(term, "cancelled")?;
            } else {
                return Ok(true);
            }
            return Ok(false);
        }
        // An open approval prompt swallows keys until answered.
        if app.pending_permit.is_some() {
            handle_permit_key(app, key.code);
            return Ok(false);
        }
        match key.code {
            KeyCode::Char('d') if ctrl && app.input.is_empty() => return Ok(true),
            KeyCode::Enter if !key.modifiers.contains(KeyModifiers::SHIFT) => {
                let prompt = app.take_input();
                let trimmed = prompt.trim();
                if trimmed.is_empty() || app.running {
                    return Ok(false);
                }
                // A leading `/` is a slash command, handled locally (never sent to the agent).
                if let Some(cmd) = trimmed.strip_prefix('/') {
                    return dispatch_command(term, app, cmd);
                }
                submit(term, app, agent, turn_tx, prompt)?;
                return Ok(false);
            }
            _ => {}
        }
    }
    // Everything else (typing, paste, arrows, resize) goes to the input widget.
    app.input.input(ev);
    Ok(false)
}

/// Answer an open approval prompt: `y`/Enter allow once, `a` allow-always, `n`/Esc deny.
fn handle_permit_key(app: &mut App, code: KeyCode) {
    let reply = match code {
        KeyCode::Char('y' | 'Y') | KeyCode::Enter => PermitReply::AllowOnce,
        KeyCode::Char('a' | 'A') => PermitReply::AllowAlways,
        KeyCode::Char('n' | 'N') | KeyCode::Esc => PermitReply::Deny,
        _ => return,
    };
    if let Some(req) = app.pending_permit.take() {
        let _ = req.reply.send(reply);
    }
}

/// Await the next approval prompt; parks forever when no gate is installed so the `select!` arm stays
/// inert rather than spinning on `None`.
async fn recv_permit(permits: &mut Option<mpsc::Receiver<PermitRequest>>) -> Option<PermitRequest> {
    match permits {
        Some(rx) => rx.recv().await,
        None => std::future::pending().await,
    }
}

/// A parsed slash command.
#[derive(Debug, PartialEq, Eq)]
enum Command<'a> {
    /// List the available commands.
    Help,
    /// Quit the TUI.
    Quit,
    /// Reset the running token/cost totals.
    Clear,
    /// Start a fresh conversation session.
    New,
    /// Switch to (or, when empty, report) the named session.
    Session(&'a str),
    /// An unrecognised command.
    Unknown(&'a str),
}

/// Parse the text after a leading `/` into a [`Command`].
fn parse_command(cmd: &str) -> Command<'_> {
    let mut it = cmd.split_whitespace();
    match it.next().unwrap_or("") {
        "help" | "h" | "?" => Command::Help,
        "quit" | "exit" | "q" => Command::Quit,
        "clear" | "cls" => Command::Clear,
        "new" => Command::New,
        "session" | "s" => Command::Session(it.next().unwrap_or("")),
        other => Command::Unknown(other),
    }
}

const HELP: &str = "commands: /help · /clear (reset counters) · /new (fresh session) · /session <id> · /quit  —  Ctrl-L clears the screen";

/// Run a slash command against the app. Returns `Ok(true)` to quit.
fn dispatch_command(term: &mut Term, app: &mut App, cmd: &str) -> io::Result<bool> {
    match parse_command(cmd) {
        Command::Help => scrollback::emit_notice(term, HELP)?,
        Command::Quit => return Ok(true),
        Command::Clear => {
            app.usage = Usage::default();
            scrollback::emit_notice(term, "counters reset (Ctrl-L clears the screen)")?;
        }
        Command::New => {
            app.session_seq += 1;
            app.session = format!("tui-{}", app.session_seq);
            scrollback::emit_notice(term, &format!("new session: {}", app.session))?;
        }
        Command::Session("") => {
            scrollback::emit_notice(term, &format!("session: {}", app.session))?
        }
        Command::Session(id) => {
            app.session = id.to_string();
            scrollback::emit_notice(term, &format!("switched to session: {id}"))?;
        }
        Command::Unknown(c) => {
            scrollback::emit_notice(term, &format!("unknown command: /{c} (try /help)"))?
        }
    }
    Ok(false)
}

/// Emit the user's line to scrollback and spawn the turn task that streams the agent's reply back
/// over `turn_tx`, tagged with a fresh generation.
fn submit(
    term: &mut Term,
    app: &mut App,
    agent: &Arc<dyn AgentHandle>,
    turn_tx: &mpsc::Sender<(u64, TurnMsg)>,
    prompt: String,
) -> io::Result<()> {
    scrollback::emit_user(term, &prompt)?;
    app.turn_gen += 1;
    app.running = true;
    app.status.clear();
    let gen = app.turn_gen;
    let agent = agent.clone();
    let tx = turn_tx.clone();
    let session = app.session.clone();
    let handle = tokio::spawn(async move {
        match agent.submit(TurnRequest::new(session, prompt)).await {
            Ok(mut stream) => {
                while let Some(item) = stream.next().await {
                    let msg = match item {
                        Ok(ev) => TurnMsg::Event(ev),
                        Err(e) => TurnMsg::Error(e.to_string()),
                    };
                    if tx.send((gen, msg)).await.is_err() {
                        return;
                    }
                }
            }
            Err(e) => {
                let _ = tx.send((gen, TurnMsg::Error(e.to_string()))).await;
            }
        }
        let _ = tx.send((gen, TurnMsg::Finished)).await;
    });
    app.turn_handle = Some(handle);
    Ok(())
}

/// Fold one turn message into the conversation: stream text/tool activity into scrollback and update
/// the live status/footer.
fn handle_turn_msg(term: &mut Term, app: &mut App, msg: TurnMsg) -> io::Result<()> {
    match msg {
        TurnMsg::Event(ev) => on_event(term, app, ev)?,
        TurnMsg::Error(e) => {
            app.flush_pending(term)?;
            scrollback::emit_error(term, &e)?;
            app.finish();
        }
        TurnMsg::Finished => {
            app.flush_pending(term)?;
            app.finish();
        }
    }
    Ok(())
}

/// Map a single [`Event`] onto scrollback + live state.
fn on_event(term: &mut Term, app: &mut App, ev: Event) -> io::Result<()> {
    match ev {
        Event::TextDelta(t) => app.push_text(term, &t)?,
        Event::Thinking(_) => app.status = "thinking…".into(),
        Event::ToolUseStart { id, name } => {
            app.flush_pending(term)?;
            app.status = format!("running {name}…");
            app.tool_names.insert(id, name);
        }
        Event::ToolUseDelta { id, json } => {
            app.tool_args.entry(id).or_default().push_str(&json);
        }
        Event::ToolUseEnd { id } => {
            let name = app.tool_names.remove(&id).unwrap_or_else(|| "tool".into());
            let hint = app
                .tool_args
                .remove(&id)
                .map(|a| tool_hint(&a))
                .unwrap_or_default();
            scrollback::emit_tool(term, &name, &hint)?;
            app.status.clear();
        }
        Event::Notice(t) => {
            app.flush_pending(term)?;
            scrollback::emit_notice(term, &t)?;
        }
        Event::Citation { source, cited_text } => {
            scrollback::emit_notice(term, &format!("[{source}] {cited_text}"))?;
        }
        Event::Usage(u) => app.usage.accumulate(&u),
        Event::Done(reason) => {
            app.flush_pending(term)?;
            if matches!(reason, StopReason::Refusal) {
                scrollback::emit_notice(term, "(refused)")?;
            }
        }
        Event::ServerToolUse { name, .. } => app.status = format!("running {name}… (server)"),
        Event::ServerToolResult { .. } => app.status.clear(),
    }
    Ok(())
}

/// A one-line hint from a tool call's accumulated argument JSON (the first string-ish value).
fn tool_hint(args_json: &str) -> String {
    let Ok(serde_json::Value::Object(map)) = serde_json::from_str::<serde_json::Value>(args_json)
    else {
        return String::new();
    };
    for key in ["path", "file", "cmd", "command", "query", "pattern"] {
        if let Some(v) = map.get(key).and_then(serde_json::Value::as_str) {
            return v.chars().take(60).collect();
        }
    }
    String::new()
}

/// The interactive state: the input widget, the current turn, streaming buffers, and running totals.
struct App {
    session: String,
    model: String,
    input: TextArea<'static>,
    running: bool,
    turn_gen: u64,
    turn_handle: Option<JoinHandle<()>>,
    /// The unfinished tail of the current assistant line (shown live on the status row; committed to
    /// scrollback on newline / turn end).
    pending: String,
    /// A transient status line (`thinking…`, `running shell…`).
    status: String,
    /// In-flight tool calls: id → name, and id → accumulated argument JSON.
    tool_names: std::collections::HashMap<String, String>,
    tool_args: std::collections::HashMap<String, String>,
    usage: Usage,
    /// An open tool-approval prompt awaiting a keypress; while set, the viewport shows the prompt and
    /// keys answer it instead of editing the input.
    pending_permit: Option<PermitRequest>,
    /// Whether the assistant stream is currently inside a ```` ``` ```` fenced code block (so those
    /// lines are styled as code). Reset at each turn's end.
    in_code_fence: bool,
    /// Monotonic counter backing `/new` fresh-session ids (no clock/rng needed).
    session_seq: u64,
}

impl App {
    fn new(session: String, model: String) -> Self {
        let mut input = TextArea::default();
        input.set_block(Block::default().borders(Borders::ALL).title(" ask "));
        input.set_cursor_line_style(Style::default());
        Self {
            session,
            model,
            input,
            running: false,
            turn_gen: 0,
            turn_handle: None,
            pending: String::new(),
            status: String::new(),
            tool_names: std::collections::HashMap::new(),
            tool_args: std::collections::HashMap::new(),
            usage: Usage::default(),
            pending_permit: None,
            in_code_fence: false,
            session_seq: 0,
        }
    }

    /// Take the current input as a prompt and clear the box.
    fn take_input(&mut self) -> String {
        let text = self.input.lines().join("\n");
        self.input.select_all();
        self.input.cut();
        text
    }

    /// Append streamed assistant text, committing whole lines to scrollback and keeping the partial
    /// tail live in `pending`. Each line is styled by its lightweight markdown context (headings,
    /// fenced code).
    fn push_text(&mut self, term: &mut Term, delta: &str) -> io::Result<()> {
        self.pending.push_str(delta);
        while let Some(nl) = self.pending.find('\n') {
            let line: String = self.pending.drain(..=nl).collect();
            let line = line.trim_end_matches('\n');
            let style = self.md_line_style(line);
            scrollback::emit_assistant(term, line, style)?;
        }
        Ok(())
    }

    /// Flush any partial assistant line to scrollback (end of turn / before an interruption).
    fn flush_pending(&mut self, term: &mut Term) -> io::Result<()> {
        if !self.pending.is_empty() {
            let line = std::mem::take(&mut self.pending);
            let style = self.md_line_style(&line);
            scrollback::emit_assistant(term, &line, style)?;
        }
        Ok(())
    }

    /// Pick a style for one assistant line from its lightweight markdown context, toggling the fenced
    /// code state as it goes: a ```` ``` ```` fence line flips the state (and renders dim); lines
    /// inside a fence render as code; a `#`-heading renders bold cyan; everything else is plain.
    fn md_line_style(&mut self, line: &str) -> Style {
        let t = line.trim_start();
        if t.starts_with("```") {
            self.in_code_fence = !self.in_code_fence;
            return Style::default().fg(Color::DarkGray);
        }
        if self.in_code_fence {
            return Style::default().fg(Color::Green);
        }
        if t.starts_with('#') {
            return Style::default()
                .fg(Color::Cyan)
                .add_modifier(Modifier::BOLD);
        }
        Style::default()
    }

    /// Mark the turn finished and clear transient state.
    fn finish(&mut self) {
        self.running = false;
        self.status.clear();
        self.turn_handle = None;
        self.tool_names.clear();
        self.tool_args.clear();
        self.in_code_fence = false;
    }

    /// Cancel the in-flight turn: aborting the task drops the agent stream, which cancels the
    /// provider request. Bumping the generation makes any buffered events from it be ignored.
    fn cancel_turn(&mut self) {
        if let Some(h) = self.turn_handle.take() {
            h.abort();
        }
        self.turn_gen += 1;
        self.pending.clear();
        // Dropping any open prompt lets its one-shot resolve to a deny on the agent side.
        self.pending_permit = None;
        self.finish();
    }

    /// Draw the inline viewport: either an open approval prompt, or the status/input/footer.
    fn draw(&self, f: &mut ratatui::Frame) {
        let rows = Layout::vertical([
            Constraint::Length(1), // status / question
            Constraint::Length(3), // input (bordered) / args preview
            Constraint::Length(1), // footer / keys
        ])
        .split(f.area());

        if let Some(req) = &self.pending_permit {
            f.render_widget(
                Paragraph::new(Line::from(Span::styled(
                    format!("⚠ allow tool `{}`?", req.name),
                    Style::default()
                        .fg(Color::Yellow)
                        .add_modifier(Modifier::BOLD),
                ))),
                rows[0],
            );
            f.render_widget(
                Paragraph::new(req.args.as_str()).block(
                    Block::default()
                        .borders(Borders::ALL)
                        .title(" arguments ")
                        .border_style(Style::default().fg(Color::Yellow)),
                ),
                rows[1],
            );
            f.render_widget(
                Paragraph::new(Line::from(Span::styled(
                    "y allow once · a always allow this tool · n deny",
                    Style::default().fg(Color::DarkGray),
                ))),
                rows[2],
            );
            return;
        }

        let status = if self.running {
            let tail: String = self.pending.chars().rev().take(80).collect();
            let tail: String = tail.chars().rev().collect();
            if self.status.is_empty() {
                format!("◐ {tail}")
            } else {
                format!("◐ {}  {tail}", self.status)
            }
        } else {
            "ready · Enter to send · Shift+Enter newline · Ctrl-C quit".into()
        };
        f.render_widget(
            Paragraph::new(Line::from(Span::styled(
                status,
                Style::default().fg(Color::DarkGray),
            ))),
            rows[0],
        );

        f.render_widget(&self.input, rows[1]);

        let footer = format!(
            "{} · {} · {} tok-eq · {} in / {} out",
            self.session,
            self.model,
            self.usage.cost(&CostWeights::default()),
            self.usage.input_tokens,
            self.usage.output_tokens,
        );
        f.render_widget(
            Paragraph::new(Line::from(Span::styled(
                footer,
                Style::default().fg(Color::DarkGray),
            ))),
            rows[2],
        );
    }
}

/// Emitters that push finalized blocks into the terminal's own scrollback (above the inline
/// viewport) via `Terminal::insert_before`, wrapping to the current width.
mod scrollback {
    use super::*;

    /// Terminal width, defaulting to 80 if it can't be read.
    fn width(term: &Term) -> u16 {
        term.size().map(|s| s.width).unwrap_or(80).max(8)
    }

    /// Hard-wrap `line` to `width` display columns (greedy by unicode width; a single wide token is
    /// broken mid-run rather than overflowing).
    pub(super) fn wrap(line: &str, width: usize) -> Vec<String> {
        if line.is_empty() {
            return vec![String::new()];
        }
        let mut rows = Vec::new();
        let mut cur = String::new();
        let mut w = 0usize;
        for ch in line.chars() {
            let cw = UnicodeWidthStr::width(ch.to_string().as_str()).max(1);
            if w + cw > width && !cur.is_empty() {
                rows.push(std::mem::take(&mut cur));
                w = 0;
            }
            cur.push(ch);
            w += cw;
        }
        rows.push(cur);
        rows
    }

    /// Insert a styled multi-line block into scrollback, computing the wrapped height so nothing is
    /// clipped.
    fn emit(term: &mut Term, prefix: Span<'static>, body: &str, style: Style) -> io::Result<()> {
        let w = width(term) as usize;
        let indent = prefix.width();
        let avail = w.saturating_sub(indent).max(4);
        let mut lines: Vec<Line<'static>> = Vec::new();
        for (i, logical) in body.split('\n').enumerate() {
            for (j, row) in wrap(logical, avail).into_iter().enumerate() {
                let lead = if i == 0 && j == 0 {
                    prefix.clone()
                } else {
                    Span::raw(" ".repeat(indent))
                };
                lines.push(Line::from(vec![lead, Span::styled(row, style)]));
            }
        }
        let height = lines.len() as u16;
        let full_w = width(term);
        let text = Text::from(lines);
        term.insert_before(height, |buf| {
            Paragraph::new(text).render(Rect::new(0, 0, full_w, height), buf);
        })
    }

    pub(super) fn emit_welcome(term: &mut Term) -> io::Result<()> {
        emit(
            term,
            Span::styled(
                "lavoisier",
                Style::default()
                    .fg(Color::Cyan)
                    .add_modifier(Modifier::BOLD),
            ),
            " — inline agent shell. Type a task and press Enter.",
            Style::default().fg(Color::DarkGray),
        )
    }

    pub(super) fn emit_user(term: &mut Term, text: &str) -> io::Result<()> {
        emit(
            term,
            Span::styled(
                "› ",
                Style::default()
                    .fg(Color::Cyan)
                    .add_modifier(Modifier::BOLD),
            ),
            text,
            Style::default().fg(Color::Cyan),
        )
    }

    pub(super) fn emit_assistant(term: &mut Term, text: &str, style: Style) -> io::Result<()> {
        emit(term, Span::raw(""), text, style)
    }

    pub(super) fn emit_tool(term: &mut Term, name: &str, hint: &str) -> io::Result<()> {
        let body = if hint.is_empty() {
            name.to_string()
        } else {
            format!("{name} · {hint}")
        };
        emit(
            term,
            Span::styled("🔧 ", Style::default().fg(Color::Yellow)),
            &body,
            Style::default().fg(Color::Yellow),
        )
    }

    pub(super) fn emit_notice(term: &mut Term, text: &str) -> io::Result<()> {
        emit(
            term,
            Span::styled("• ", Style::default().fg(Color::DarkGray)),
            text,
            Style::default()
                .fg(Color::DarkGray)
                .add_modifier(Modifier::ITALIC),
        )
    }

    pub(super) fn emit_error(term: &mut Term, text: &str) -> io::Result<()> {
        emit(
            term,
            Span::styled(
                "error: ",
                Style::default().fg(Color::Red).add_modifier(Modifier::BOLD),
            ),
            text,
            Style::default().fg(Color::Red),
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tool_hint_pulls_the_salient_arg() {
        assert_eq!(tool_hint(r#"{"path":"src/main.rs"}"#), "src/main.rs");
        assert_eq!(tool_hint(r#"{"command":"cargo test"}"#), "cargo test");
        assert_eq!(tool_hint(r#"{"unknown":1}"#), "");
        assert_eq!(tool_hint("not json"), "");
    }

    #[test]
    fn wrap_breaks_at_width_without_clipping() {
        let rows = scrollback::wrap("abcdef", 3);
        assert_eq!(rows, vec!["abc", "def"]);
        assert_eq!(scrollback::wrap("", 5), vec![String::new()]);
    }

    #[test]
    fn take_input_clears_the_box() {
        let mut app = App::new("s".into(), "m".into());
        app.input.insert_str("hello world");
        assert_eq!(app.take_input(), "hello world");
        assert!(app.input.is_empty());
    }

    #[test]
    fn text_buffering_commits_whole_lines_and_keeps_the_tail() {
        // Drive the line-buffering logic without a real terminal by exercising the pending buffer
        // directly (emit is a no-op sink here since we don't push to scrollback).
        let mut app = App::new("s".into(), "m".into());
        app.pending.push_str("one\ntw");
        // The first newline-terminated line is drained; the tail remains pending.
        assert!(app.pending.contains("one\n"));
        // Simulate the drain the same way push_text does.
        while let Some(nl) = app.pending.find('\n') {
            let _line: String = app.pending.drain(..=nl).collect();
        }
        assert_eq!(app.pending, "tw");
    }

    #[test]
    fn slash_commands_parse() {
        assert_eq!(parse_command("help"), Command::Help);
        assert_eq!(parse_command("q"), Command::Quit);
        assert_eq!(parse_command("clear"), Command::Clear);
        assert_eq!(parse_command("new"), Command::New);
        assert_eq!(parse_command("session work"), Command::Session("work"));
        assert_eq!(parse_command("session"), Command::Session(""));
        assert_eq!(parse_command("frob"), Command::Unknown("frob"));
    }

    #[test]
    fn markdown_line_style_tracks_fences_and_headings() {
        let mut app = App::new("s".into(), "m".into());
        // A heading outside a fence is styled; the plain line is not.
        assert_eq!(app.md_line_style("# Title").add_modifier, Modifier::BOLD);
        assert_eq!(app.md_line_style("plain"), Style::default());
        // Entering a fence styles subsequent lines as code until the closing fence.
        let _ = app.md_line_style("```rust");
        assert!(app.in_code_fence);
        assert_eq!(app.md_line_style("let x = 1;").fg, Some(Color::Green));
        let _ = app.md_line_style("```");
        assert!(!app.in_code_fence);
    }

    #[test]
    fn new_session_command_bumps_the_session() {
        let mut app = App::new("tui".into(), "m".into());
        // Emulate `/new` twice: sessions are distinct and monotonic (no clock/rng).
        app.session_seq += 1;
        app.session = format!("tui-{}", app.session_seq);
        assert_eq!(app.session, "tui-1");
        app.session_seq += 1;
        app.session = format!("tui-{}", app.session_seq);
        assert_eq!(app.session, "tui-2");
    }
}
