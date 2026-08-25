# Migrating to 0.17.0

0.17.0 makes the config **typed**. Before, every enumerable field was a `Text` that Dhall checked
only for being *a* string — `provider = Some "anthropik"` type-checked fine and failed three layers
down at the provider factory. Now each is a union, so a typo is a load error that names the valid
alternatives. Packed strings (`"anthropic:claude-sonnet-4-5"`, `"fs: npx …"`, `"*/30 9-17 * * 1-5 do
the thing"`) are records, so the parser that used to guess where one field ended and the next began
is gone.

**Every existing `lavoisier.dhall` needs editing.** This page is the mechanical list.

There are also runtime behaviour changes (§3) and, if you use `mainWith`, library API changes (§4).

---

## 1. Two things every config needs

**Import the schema and use the completion operator.** Wrap the whole record:

```dhall
-- before
{ provider = Some "anthropic", maxSteps = Some 12 }

-- after
let L = ./schema.dhall

in  L.Config::{ provider = Some L.Provider.Anthropic, maxSteps = Some 12 }
```

`::` fills in every field you did not write, so you still only list what you set.

**Ship `schema.dhall` next to your config.** This is the one that breaks deployments rather than
builds. `loadConfig` uses `Dhall.inputFile`, so the relative `./schema.dhall` resolves against **the
config file's own directory**, not the process working directory. If `/etc/lavoisier/lavoisier.dhall`
imports `./schema.dhall`, then `/etc/lavoisier/schema.dhall` must exist. Copy it from the release, or
import it by URL with an integrity hash if you would rather not vendor it.

## 2. Field-by-field

Anything not listed is unchanged.

| Field | Before | After |
|---|---|---|
| `provider` | `Some "anthropic"` | `Some L.Provider.Anthropic` |
| `thinking` | `Some "high"` | `Some L.Thinking.High` |
| `lang` | `Some "ko_KR"` | `Some L.Language.Korean` |
| `legionJudge` | `Some "google:gemini-2.5-flash"` | `Some L.ModelRef::{ provider = L.Provider.Google, model = "gemini-2.5-flash" }` |
| `legionDebaters` | `Some [ "anthropic:claude-sonnet-4-5" ]` | `Some [ L.ModelRef::{ provider = L.Provider.Anthropic, model = "claude-sonnet-4-5" } ]` |
| `mcpServers` | `Some [ "fs: npx -y … ." ]` | `Some [ L.Mcp::{ label = "fs", target = L.McpTarget.Stdio "npx -y … ." } ]` |
| `cron` | `Some [ "*/30 9-17 * * 1-5 check CI" ]` | `Some [ L.CronJob::{ schedule = L.Schedule::{ minute = [ L.everyN 30 ], hour = [ L.between 9 17 ], dayOfWeek = [ L.between 1 5 ] }, prompt = "check CI" } ]` |
| `matrixRoomTools` | ``Some (toMap { `!ops:hs` = [ "shell" ] })`` | `Some [ L.ToolGrant::{ subject = "!ops:hs", tools = [ "shell" ] } ]` |
| `matrixUserTools` | ``Some (toMap { `@bob:hs` = [ "read_file" ] })`` | `Some [ L.ToolGrant::{ subject = "@bob:hs", tools = [ "read_file" ] } ]` |

Notes on the less obvious ones:

- **An HTTP MCP target is stated, not sniffed.** `L.McpTarget.Http "https://…/sse"` for a URL,
  `L.McpTarget.Stdio "cmd …"` for a subprocess. Previously the string was inspected for an `http`
  prefix at connect time; now the choice is made at load, and the HTTP arm is checked for a scheme.
- **Cron schedules name *and type* their fields.** A field is a list of terms, each built with
  `L.every` (`*`), `L.everyN 30` (`*/30`), `L.at 9` (`9`), `L.between 9 17` (`9-17`) or
  `L.from 5 10` (`5/10`); commas become list elements, so `0,15,30` is `[ L.at 0, L.at 15, L.at 30 ]`.
  `L.Schedule` defaults every field to `[ L.every ]`, so write only what you constrain, and
  `L.everyMinutes 30` / `L.dailyAt 9` remain as shorthands. Each value is range-checked against its
  own field at load — an `hour` of `24` is an error naming `hour`, not a job that never fires.
- **Matrix tool grants are a list, not a `toMap`.** Same semantics: a room or user absent from the
  list is unconstrained, and when both a room and a user grant apply the effective set is their
  **intersection**.
- **Ports are range-checked.** Still `Natural`, but `serve = Some 0` or `Some 70000` is now a load
  error naming the field. Dhall cannot express this (its `assert` cannot refine a function argument),
  so the check lives in the decoder.

### `--cron-file` and `--schedule-file` are typed too

These two files kept their old flat shape through 0.17.0 and are converted here, so a cron file
written for any earlier release needs editing.

**`--cron-file`** is now a `List L.CronJob/Type` — the *same* type the config's `cron` field uses,
which means one shape for a cron job instead of two:

```dhall
-- before: a bare record list, every Optional spelled out, the schedule a packed string
[ { schedule = "0 9 * * *", session = Some "digest", prompt = "morning digest"
  , retryMax = None Natural, retryWait = None Natural } ]

-- after
let L = ./schema.dhall
in  [ L.CronJob::{ schedule = L.dailyAt 9, session = Some "digest", prompt = "morning digest" } ]
```

**`--schedule-file`** is a `List L.ScheduleJob/Type`, and its `tool`/`toolArgs`/`prompt` trio has
become one `action` union:

```dhall
-- before
[ { jobId = "disk", schedule = "0 * * * *", tool = Some "shell"
  , toolArgs = Some "{\"command\":\"df\"}", prompt = None Text, room = None Text
  , session = None Text, summarize = None Text, retryMax = None Natural, retryWait = None Natural } ]

-- after
let L = ./schema.dhall
in  [ L.ScheduleJob::{ jobId = "disk"
                     , schedule = L.Schedule::{ minute = [ L.at 0 ] }
                     , action = L.Action.Tool { name = "shell", args = Some "{\"command\":\"df\"}" }
                     } ]
```

Setting both `tool` and `prompt`, or neither, used to be a runtime error; the union makes both
states unrepresentable. `args` stays a JSON object string on purpose — cron has a fixed grammar
worth typing, tool arguments have no schema but the invoked tool's own.

Both files import `./schema.dhall` relative to **their own** directory, the same rule as the config.

### New fields, all optional

```dhall
, logLevel    = Some L.LogLevel.Info
, scheduleFile = Some "/etc/lavoisier/schedule.dhall"
, serverTools = Some [ L.webSearch, L.ServerTool.CodeExecution ]
```

`serverTools` offers **provider-run** tools — the provider executes them mid-turn with no client
round-trip. See the README; the sets differ per provider and asking the wrong one is refused by name.

## 3. Runtime behaviour that changed

These need no config edit, but you will see them.

- **Unsupported optional knobs now say so.** `--thinking high` against a provider without extended
  thinking (today `claude-cli`) prints `[notice] extended thinking was requested but this provider
  does not support it; continuing without it` and runs the turn anyway. Previously the flag was
  silently ignored — you were billed for a feature you did not get. The same holds for sampling,
  `top_k`, stop sequences, structured output and tool choice.
- **Unsupported content is now refused, not dropped.** A request carrying an image, or offering a
  provider-run tool the provider cannot run, fails with a message naming what was unsupported.
  Previously it was quietly discarded, which made the model answer about something it never saw.
  **This can turn a previously "working" (but wrong) call into a visible error.** That is the intent.
- **Gemini `--thinking medium` now sends `medium`.** It used to send `high`, quietly buying more
  reasoning tokens than you asked for.
- **Batch submissions are checked too**, at submit time rather than after the batch is accepted, and
  `batch_edit` prints any degraded knob once at the top of its report.
- **A bad cron schedule is a load error, not a start-up error.** Every field value is checked
  against its own range when the file is read, naming the field. Nothing is left to fail when the
  cron or schedule gateway starts.

## 4. If you use `mainWith`

Library API changes, in rough order of how likely they are to hit you.

- **`Capabilities` is no longer five positional `Bool`s.** `Capabilities True True True True True`
  becomes `declare @'[ 'PromptCaching, 'ExtendedThinking, … ]`. Note the space in `@'[ '` — `@'['` is
  a lex error.
- **`ParallelToolUse` is gone** and **`ServerSideTools` is split per tool** into `WebSearch`,
  `WebFetch`, `CodeExecution`, `XSearch`, `CollectionsSearch`, `UrlContext`, `ClientBuiltinTools` and
  `RemoteMcp`. Added: `Sampling`, `TopK`, `StopSequences`, `StructuredOutput`, `ToolChoiceControl`.
  The `serverSideTools` and `parallelToolUse` accessors are removed.
- **`ProviderId` gained `XaiResponses`.** Exhaustive matches over it will fail to compile — which is
  the point; each site is a real decision.
- **`BatchItem` gained `biNotices`.** Build one with the `batchItem` smart constructor rather than
  the positional constructor.
- **Request body builders take `Negotiated caps`, not `ChatRequest`.** If you wrote your own adapter,
  its `providerStream` should be `withNegotiated @YourCaps req $ \nreq -> …` and nothing else.
- **`UnicodeSyntax` is now in `default-extensions`.** Only matters if you copied the cabal settings.
- **New and optional:** `Lavoisier.Protocol.Typed` gives a compile-time front door — `Req needs`
  accumulates the capabilities a request requires in its type, and `streamTyped` rejects a provider
  that does not declare them. See `CUSTOM_TOOL_INSTRUCTIONS.md`.

## 5. Checking you got it right

Two different checks, because they catch different things:

```sh
dhall type --file lavoisier.dhall               # Dhall's type errors: bad constructor, wrong shape
lav --config lavoisier.dhall --agent "say ok"   # decoder errors: bad port range, bad room sigil
```

The first catches everything Dhall's type system can state. The second catches what it cannot — port
ranges, `!`/`#` on room ids, `@` on user ids — reported as a load error naming the field and the
offending value.

`lav --config … --version` is **not** a config check: `--version` short-circuits before the file is
read, so it prints happily on a config that would fail to load. It has to be a real invocation.

[`lavoisier.dhall.example`](lavoisier.dhall.example) is a full annotated config in the new format,
and [`schema.dhall`](schema.dhall) is the source of truth for every type.
