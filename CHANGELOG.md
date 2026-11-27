# Changelog

Notable changes to Lavoisier. Older release notes are in the git history and in
[`PUBLISHING.md`](PUBLISHING.md).

## [Unreleased]

### Truncated rounds with no tool call (HOLD APPLY)

- The error for a round that ends `incomplete` or at `max_tokens` with no tool call now names
  the stop, the output budget sent, and the output tokens the provider reported. The old prefix
  `response incomplete (hit max_output_tokens) with no tool call` is kept, so existing matchers
  still match. With no usage reported it adds `the stream may have ended early`. On
  `xai-responses` / grok-4.3, `max_output_tokens` caps visible output only (reasoning and
  function-call tokens do not count), and `Usage.output_tokens` is the provider total including
  reasoning, so tokens used can exceed the budget without the cap being spent.
  `response.incomplete` can also come from `max_time_limit` or `max_prompt_tokens`.
- New, off by default: `--truncation-retry` / `[agent] truncation_retry = true`. Such a round is
  asked again with its output budget doubled, at most twice per turn and never above 16384. The
  truncated prose is dropped. A re-asked round still counts as the first live-ops round, so it
  keeps `tool_choice = required`. Engines before this release refuse the key
  (`deny_unknown_fields`): set it only with an image built from this change.
- No change when the flag is off apart from the error text. CLI default `max_tokens` stays 2048.

### Crate version bumps for crates.io

- `lvz-tools` 0.1.2 → 0.1.3 picks up the `ToolOutput.accepted` field added in `lvz-protocol` 0.1.10, so a publish no longer verifies against the old 0.1.2 sources.
- `lvz-memory` 0.3.2 → 0.3.3 picks up the switch to `Agent::run_in_session`.

The root workspace pins are `lvz-tools` 0.1.3 and `lvz-memory` 0.3.3, the same versions crates.io already serves. This stack starts from that reconcile.

### Cancel

- A job row holds the cancel token the worker is given. `POST /v1/jobs/{id}` installs that token for the attempt and cancels it when the attempt times out. Direct schedule tool calls and prompt turns are `Origin::Schedule`.
- `[jobs] user_tools` (default false) registers `jobs_list` and `job_cancel`. Cancel is limited to the caller's session. A scheduled job answers `예약 작업은 취소할 수 없습니다`. An unknown id is `JobError::Unknown`.
- `[jobs] cancel_command` (default false) handles `<job> 취소해줘` before the model, on a chat-origin turn. `<job>` is an exact id, then a Korean alias (`빌드`, `켜기`, `부팅`, `끄기`, `종료`, `방송 시작`, `방송 중지`, `방송 종료`). A tool name does not match. Zero or several matches list the running jobs and cancel nothing. A short model turn phrases the result; if that call fails, the raw notice is the reply.

### Durable jobs

- The job file is version 2 and still reads version 1. A write goes to a unique temp file, is fsynced, renamed, and the parent directory is fsynced, off the job-table lock. Object mounts write the final path instead. A terminal row stays until `drain_ready` delivers it. A tool that cannot survive a restart becomes `JobError::Interrupted` with the last progress step (`unknown` when none was stored). A recovered `run_build` keeps the timeout it was accepted with.
- `[jobs] recover_on_signal` defaults false, which keeps today's boot recovery. When it is true, `POST /v1/admin/recover` with `{lease_generation}` adopts the rows. The same generation returns `already_recovered`. A different generation returns 409 `stale_lease`. `[memory] fs` defaults to `local`.

### Turn context and work errors

- `TurnRequest.context` carries the gateway's trusted sender, room, event id, sequence, and raw text. `Origin` is `Chat`, `Schedule`, or `Cli`, installed as a task-local for the turn. `POST /v1/turns` accepts an optional `context` object and ignores unknown fields.
- `JobError::Interrupted` and `JobError::Lost`, plus `WorkError` / `WorkLease`, are the typed contract for cancellable background work. Nothing calls them yet.

### HTTP tool policy

- `tools_for` / `effective_tools` live in `lvz-protocol` and are re-exported by `lvz-tools`. The Matrix gateway and `POST /v1/turns` call that one function. The HTTP gateway does not depend on `lvz-tools`, so it does not pull the context engine in.
- When `[gateway.matrix_room_tools]` or `matrix_user_tools` is non-empty, `/v1/turns` always applies them. A turn with `context` gets that grant. A turn without `context` gets no tools. Empty maps leave the full registry. `POST /v1/jobs/{id}` is unchanged.

`lvz-tools` 0.1.2 → 0.1.3. `lvz-memory` 0.3.2 → 0.3.3.

## [0.18.16] — 2026-11-25

### Background jobs on the chat path

- A long tool returns a [`JobId`] immediately. The chat loop posts one placeholder
  `tool_result` (`accepted, id=…`) and keeps the turn open. The terminal payload is a
  later user message, in finish order, not a second result for the same id. `EndTurn`
  with a job still open waits until that job finishes, times out, or the turn is
  cancelled. Dropping the event stream, including ACP `session/cancel`, cancels the job.
- At most 4 running jobs per session. The next accept is `ToolError::Execution` and the
  placeholder is `is_error`. A chat timeout does not call the tool again. The schedule
  path and `POST /v1/jobs/{id}` still poll inline, and a schedule timeout still retries.
- A legacy `ToolOutput::pending` on the chat path is polled by the host. The model is
  not required to call `poll_build`, `server_poll_wake`, or `server_poll_shutdown`.
- Running rows are stored beside the file session transcript as `{hex}.jobs.json`
  (`id`, `tool`, `session`, `started`). After a restart, power and OBS jobs fail with
  `process restarted` and are not sent again. `run_build` reattaches when
  `$BUILD_ID.code` is already in the artifact directory.
- The table is one `Mutex`. It is not held across `.await`. The cap check and the insert
  share that critical section. A row is removed once its terminal value has been copied
  into the user message, so a finished id does not stay in the map.

`lavoisier` 0.18.15 → 0.18.16. `lvz-protocol` 0.1.9 → 0.1.10. `lvz-agent` 0.1.14 → 0.1.15.
Not tagged in this change. HOLD APPLY.

## [0.18.15] — 2026-11-25

### Live-ops summary after the round cap

- After `MAX_LIVE_OPS_ROUNDS` (3) tool-capable provider calls, a live OBS/PiKVM/schedule ask makes one more call. That call sends `tool_choice=none`, an empty tool list, and no server tools, and asks the model to summarise. The prose is the answer.
- A tool call on that summary round is not run and is not forwarded. The turn ends. A fifth provider call does not happen.
- An incomplete or max-token summary is still an error. A prose answer before the cap is unchanged: it is accepted, and the summary round is not added.

`lavoisier` 0.18.14 → 0.18.15. `lvz-agent` 0.1.13 → 0.1.14. Not tagged in this change.

## [0.18.14] — 2026-11-24

### Live-ops tool choice

- A live OBS/PiKVM/schedule ask sends `tool_choice=required` on the first provider round only. Later rounds with tools send `tool_choice=auto`. An empty tool list still omits the field.
- A prose answer on that first round is accepted. The turn does not re-call the primary with `required`, and it does not start the fallback model for that miss.
- The live-ops loop stops after `MAX_LIVE_OPS_ROUNDS` (3) provider calls. An incomplete or max-token message with no tool call is still an error.
- Expected, from the loop counts rather than a live clock: a miss that used to be two primary calls plus two fallback calls is now one primary call and zero fallback calls. A tool loop that ran about four rounds plus a fallback (~13 s on grok-4.3) stops at three provider calls. Connect and pre-token stream fallback is unchanged.

`lavoisier` 0.18.13 → 0.18.14. `lvz-agent` 0.1.12 → 0.1.13.

## [0.18.13] — 2026-11-12

### Jobs route for an external clock

- `lav --serve --serve-jobs --schedule-file …` (env `LVZ_SERVE_JOBS`, `[gateway] serve_jobs`)
  serves `POST /v1/jobs/{id}` behind the same API-key guard: one attempt of a schedule job
  per call, for a caller that owns the clock, the lease and the retry chain (lvz-matrix-infra
  phase5-endpoint, S1). Body `{"scheduled_minute","idempotency_key","attempt"}`; SSE answer
  with at most one `waiting` event and one terminal `report` (or `error`). Refusals: 404
  `unknown_job`, 409 `in_progress`, 422 `bad_body`/`bad_key`/`not_a_slot`/`stale`/`bad_attempt`.
- The attempt is the Matrix scheduler's fire: direct tool call or prompt turn, pending work
  polled inline, `summarize`, the same `report_body` and retry decision (`retry_in_s`,
  `gave_up`). Hard cap `--jobs-timeout` (default 1800 s). Finished keys replay for 24 h
  (in memory). No timer runs and `schedule_run` is not registered in this mode;
  `--serve-jobs` is refused with `--serve-matrix`, and needs `--serve` and `--schedule-file`.
- New API: `lvz_gw_http::jobs::{JobRunner, JobRequest, JobReport, JobRejection}`,
  `GatewayConfig::with_jobs`, `ScheduleRegistry::run_attempt`, `CronSchedule::matches_at`.

`lavoisier` 0.18.12 → 0.18.13. `lvz-gw-http` 0.1.1 → 0.1.2. `lvz-schedule` 0.4.2 → 0.4.3.

## [0.18.12] — 2026-11-10

### Matrix crypto store

- `lvz-gw-matrix` can keep the bot's Olm/Megolm state in Postgres (`CryptoStore` on
  `matrix-sdk-crypto` 0.18) when `MATRIX_CRYPTO_STORE_SECRET` is set. SQLite remains
  the store when that variable is unset. Pickle bytes are AES-256-GCM. The key is
  HKDF-SHA256 from `MATRIX_CRYPTO_STORE_KEY`, info `lavoisier-crypto-store-v1`.
  Lookup columns (user, device, room, session, Curve25519 sender key) stay plaintext.
- Every mutating transaction updates `crypto.crypto_fence` in the same transaction
  and increases `commit_seq` by one. A predicate miss rolls back as a stale fence.
  A lost commit reply is reconciled from `(epoch, commit_seq, last_op_id)` and is
  not applied again on the machine that already advanced.
- `Crypto::receive_sync` brackets `receive_sync_changes` so the session write and
  the account write share one Postgres transaction. `since` advances only when that
  pair is known committed. An aborted pair may be re-fed once after reload. A
  committed pair is not re-fed.
- The CLI acquires the fence once before Slack, the schedule, or the memory store.
  `Crypto` uses that lease and does not run the incrementing acquire again. A null
  `migration_marker` copies `<MATRIX_STATE_DIR>/crypto` through the 0.18 read API
  from a `/tmp` copy, inside the marker transaction. `SqliteCryptoStore::open` is
  not pointed at the EFS path. If the marker does not commit, startup does not call
  `OlmMachine::with_store`.
- A Slack `Ok` after a requested handoff does not end the process before the release
  `UPDATE`. Any other Slack completion does. A parked holder does not re-acquire.
  A refreshed waiter claim, and the first lapsed foreign lease inside the load
  grace, keep `/tmp/e2ee-ready`.

### Lattice Phase 4 Port

- The Matrix gateway can dial the in-cluster wasmCloud homeserver
  `http://matrix-cs.wasmcloud.svc.cluster.local:80` with HTTP `Host`
  `matrix-cs.wasmcloud.svc` and server name `davidlee18.dev`. See
  [`docs/PHASE4-PORT.md`](docs/PHASE4-PORT.md).
- Gate G4 is `lav --matrix-probe` (send, then `/sync` read-back). Lattice
  `MATRIX_REGISTER` requires `MATRIX_REGISTRATION_TOKEN`
  (`m.login.registration_token`) and is refused without it.
- `lav --matrix-probe` creates a room when `MATRIX_PROBE_ROOM` is unset or the send
  is refused with `M_FORBIDDEN` / `not in room`, then reads that event back from
  `/sync`. A room that accepts the send is not recreated (`createRoom` is not
  idempotent). The image digest the lattice job runs is rolled separately.
- The ECS spider42 path is unchanged when the lattice variables are unset.

`lavoisier` 0.18.11 → 0.18.12. `lvz-gw-matrix` 0.7.5 → 0.7.6.

## [0.18.11] — 2026-10-22

### Security

- Matrix `MatrixGateway::tools_for` fails closed when `[gateway.matrix_user_tools]` is non-empty
  and the sender is not listed. The turn allowlist is `Some([])`, so no tools are advertised or
  callable — including in a room with no `[gateway.matrix_room_tools]` entry. An unlisted sender
  previously received that room's tool set, or an unconstrained set when the room had no entry.
- An empty or absent member map is unchanged: the room set applies, and a room with no entry stays
  unconstrained. A listed member is still the intersection of the room and member sets when both
  apply, and that member's own set when the room has no entry.
- Scheduled jobs still bypass the member map. A tool job dispatches through the shared registry,
  and a prompt job is submitted with no sender.

`lavoisier` 0.18.10 → 0.18.11. `lvz-gw-matrix` 0.7.4 → 0.7.5. No tag.
