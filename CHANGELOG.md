# Changelog

Notable changes to Lavoisier. Older release notes are in the git history and in
[`PUBLISHING.md`](PUBLISHING.md).

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
