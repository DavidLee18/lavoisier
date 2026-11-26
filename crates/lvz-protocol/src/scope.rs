//! The cancel token and session a background job is reserved under.
//!
//! Chat installs this around `Tool::invoke`. A scheduled attempt installs it around the
//! attempt, so a timeout cancels the same token the job row holds. Spawned tasks do not
//! inherit it; the worker keeps the [`tokio_util::sync::CancellationToken`] it was given.

use std::future::Future;

use tokio_util::sync::CancellationToken;

/// Session and parent token for jobs accepted on this task.
#[derive(Clone)]
pub struct WorkScope {
    /// Session the row is stored under.
    pub session: String,
    /// Parent of the row's token. Cancelling this cancels the work.
    pub cancel: CancellationToken,
}

tokio::task_local! {
    static WORK_SCOPE: WorkScope;
}

/// The scope installed on this task, if any.
pub fn work_scope() -> Option<WorkScope> {
    WORK_SCOPE
        .try_with(|scope| WorkScope {
            session: scope.session.clone(),
            cancel: scope.cancel.clone(),
        })
        .ok()
}

/// Run `fut` with `session` and `cancel` installed as the work scope.
pub async fn enter_work_scope<F>(session: &str, cancel: CancellationToken, fut: F) -> F::Output
where
    F: Future,
{
    WORK_SCOPE
        .scope(
            WorkScope {
                session: session.to_string(),
                cancel,
            },
            fut,
        )
        .await
}

/// Which tools this turn may call. `All` is an unconstrained turn.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ToolGrant {
    /// Every tool.
    All,
    /// Exactly these names. Empty means none.
    Only(Vec<String>),
}

tokio::task_local! {
    static TOOL_GRANT: ToolGrant;
}

/// The grant installed for this task. Outside a turn this is [`ToolGrant::All`].
pub fn tool_grant() -> ToolGrant {
    TOOL_GRANT
        .try_with(|grant| grant.clone())
        .unwrap_or(ToolGrant::All)
}

/// A slice view of [`tool_grant`] for [`crate::tool_permitted`].
pub fn tool_grant_slice() -> Option<Vec<String>> {
    match tool_grant() {
        ToolGrant::All => None,
        ToolGrant::Only(names) => Some(names),
    }
}

/// Run `fut` with `grant` installed.
pub async fn enter_tool_grant<F>(grant: ToolGrant, fut: F) -> F::Output
where
    F: Future,
{
    TOOL_GRANT.scope(grant, fut).await
}
