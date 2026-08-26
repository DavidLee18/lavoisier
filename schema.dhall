{-
   Lavoisier config schema.

   Import this from your `lavoisier.dhall` and build the record from the constructors below:

       let L = ./schema.dhall
       in  L.Config::{ provider = Some L.Provider.Anthropic }

   Everything enumerable is a **union**, so a typo is a Dhall type error at load with the valid
   alternatives listed, not a runtime failure three layers down. `Port` is a smart constructor that
   rejects 0 and anything above 65535 *during type-checking*, via an `assert`.
-}

let Provider
    : Type
    = < Anthropic | Google | Xai | XaiGrpc | XaiResponses | ClaudeCli >

let Thinking
    : Type
    = < Off | Low | Medium | High >

let Language
    : Type
    = < English | Korean >

let LogLevel
    : Type
    = < Error | Warn | Info | Debug >

let Port
    : Type
    = Natural

{-  NOTE: a port is a bare `Natural` here on purpose. Dhall's `assert` type-checks a lambda body
    with its argument still abstract, so a `mkPort : Natural -> Port` that rejects 0 and >65535
    cannot be written — the assertion fails at *definition* time, not on a bad call. The range
    check therefore lives in the Haskell decoder, which reports it as a config load error naming
    the field and the offending value. Dhall still guarantees it is a Natural, so a negative or a
    quoted "8080" is a type error here.
-}

{-| Which model, for a provider that has one. `Default` is that provider's built-in default,
    which is the honest way to say "the current one" — model ids go stale and a config that
    pinned one silently keeps using it.
-}
let Model
    : Type
    = < Default | Named : Text >

{-| A provider-qualified model. Used for legion debaters, the legion judge, and the `--fallback`
    chain — all three used to be the packed string "provider:model", then a two-field record.

    The record was the problem this union fixes: `provider` and `model` were independent fields
    with a relationship nothing stated, so `{ provider = Anthropic, model = "grok-4" }`
    type-checked, loaded, and failed at the API. Here a model cannot be named without saying
    whose it is, and the provider defaulted to Anthropic when omitted — a silent default on the
    one field that decides which API key is used.

    Note the limit: `Named` is free text, so the pairing is structural, not a check that the id
    belongs to that provider. Nothing in Dhall can do the latter, and a curated list of ids would
    ship stale.
-}
let ModelRef
    : Type
    = < Anthropic : Model
      | Google : Model
      | Xai : Model
      | XaiGrpc : Model
      | XaiResponses : Model
      | ClaudeCli : Model
      >

let anthropic = \(m : Text) -> ModelRef.Anthropic (Model.Named m)

let google = \(m : Text) -> ModelRef.Google (Model.Named m)

let xai = \(m : Text) -> ModelRef.Xai (Model.Named m)

let xaiGrpc = \(m : Text) -> ModelRef.XaiGrpc (Model.Named m)

let xaiResponses = \(m : Text) -> ModelRef.XaiResponses (Model.Named m)

let claudeCli = \(m : Text) -> ModelRef.ClaudeCli (Model.Named m)

{-| How to reach an MCP server. The stdio-vs-HTTP choice used to be recovered by sniffing the
    target string for an `http` prefix at connect time; here it is stated.
-}
let McpTarget
    : Type
    = < Stdio : Text | Http : Text >

let Mcp/Type
    : Type
    = { label : Text, target : McpTarget }

let Mcp = { Type = Mcp/Type, default = {=} }

{-| Cheap-model-first routing: run the first `escalateAfter` round-trips on `cheapModel`, then
    escalate to `model`.

    `escalateAfter` used to be a sibling field, independently optional, so setting it without a
    cheap model type-checked, loaded, and did nothing — the agent loop ignores the threshold when
    there is no model to escalate from. Here there is no threshold without one.
-}
let Routing/Type
    : Type
    = { cheapModel : Text, escalateAfter : Optional Natural }

let Routing =
      { Type = Routing/Type, default = { escalateAfter = None Natural } }

{-| The verify lever: a command whose exit status decides whether the task is done (0 = pass),
    plus what to do with the answer.

    `andFix` and `inLoop` were top-level `Bool`s beside an optional command, and both are inert
    without one: the agent returns immediately when the command is absent. Two switches that
    silently did nothing.
-}
let Verify/Type
    : Type
    = { command : Text, andFix : Bool, inLoop : Bool }

let Verify =
      { Type = Verify/Type, default = { andFix = False, inLoop = False } }

-- | Which ATO learner to run. There is no `Off`: leaving `tune` unset is what off means.
let TuneStrategy
    : Type
    = < Greedy | Bayes >

{-| The ATO tuner. This replaced `tune : Bool`, `tuneBayes : Bool` and `tuneState : Text`, three
    independent fields whose combinations disagreed with the code reading them:
    `tuneBayes = True` with `tune = False` ran the Bayesian learner anyway, and `tuneState`
    without `tune` was documented as implying it and did not. A strategy is a choice, not two
    booleans, and a state path cannot outlive the learner that writes it.
-}
let Tune/Type
    : Type
    = { strategy : TuneStrategy, state : Optional Text }

let Tune =
      { Type = Tune/Type
      , default = { strategy = TuneStrategy.Greedy, state = None Text }
      }

{-| The interactive TUI. `autoApprove` was a second top-level `Bool` that only the TUI reads, so
    setting it alone was silently nothing; here it belongs to the thing that reads it.
-}
let Tui/Type
    : Type
    = { autoApprove : Bool }

let Tui = { Type = Tui/Type, default = { autoApprove = False } }

{-| A legion council: the debaters, the judge that synthesises their verdict, and the number of
    critique rounds after the draft.

    The judge and the round count used to sit beside an independent debater list, and the council
    was built only when that list was non-empty — so naming a judge and rounds but no debaters
    dropped all three without a word. `lav` also requires at least two debaters (a one-model
    council is just the advisor pre-pass) and says so at load.
-}
let Legion/Type
    : Type
    = { debaters : List ModelRef
      , judge : Optional ModelRef
      , rounds : Optional Natural
      }

let Legion =
      { Type = Legion/Type
      , default = { judge = None ModelRef, rounds = None Natural }
      }

{-| One term of a cron field, before any step: `*`, a single value, or a range.

    `Exactly` means two things depending on whether a step follows it, which is crontab's own
    convention: `5` is the value 5, while `5/10` is 5 through the field's maximum in tens.
-}
let CronBase
    : Type
    = < Every | Exactly : Natural | Between : { from : Natural, to : Natural } >

{-| One comma-separated term of a cron field. The step hangs off the base rather than wrapping
    another term, so `*/2/3` cannot be written.
-}
let CronTerm/Type
    : Type
    = { base : CronBase, step : Optional Natural }

let CronTerm =
      { Type = CronTerm/Type
      , default = { base = CronBase.Every, step = None Natural }
      }

{-| A whole cron field: one or more terms, stated as a record because Dhall has no non-empty
    list. It was `List CronTerm`, so `minute = []` type-checked and became a load error; now it is
    not writable. Build one with `one` or `terms`, never by hand.

    `lav` range-checks each term against the field it lands in.
-}
let CronField
    : Type
    = { head : CronTerm/Type, tail : List CronTerm/Type }

-- | The one-term field, which is nearly every field.
let one =
      \(t : CronTerm/Type) -> { head = t, tail = [] : List CronTerm/Type }

-- | A field of two or more terms: `terms (at 0) [ at 30 ]` is `0,30`.
let terms =
      \(t : CronTerm/Type) -> \(ts : List CronTerm/Type) -> { head = t, tail = ts }

let every = CronTerm::{=}

let everyN = \(n : Natural) -> CronTerm::{ step = Some n }

let at = \(n : Natural) -> CronTerm::{ base = CronBase.Exactly n }

let between =
      \(a : Natural) ->
      \(b : Natural) ->
        CronTerm::{ base = CronBase.Between { from = a, to = b } }

let from =
      \(n : Natural) ->
      \(step : Natural) ->
        CronTerm::{ base = CronBase.Exactly n, step = Some step }

{-| The five cron fields, named and typed. They used to share one string with the prompt, so
    "*/30 9-17 * * 1-5 check CI" had to be split on whitespace and the split had to guess where
    the schedule stopped and the prompt began. Naming the fields removed that guess; typing them
    removes what was left, which was that each field was an unchecked string whose errors only
    surfaced once a gateway started.

    `*/30 9-17 * * 1-5` reads:
      Schedule::{ minute = one (everyN 30)
                , hour = one (between 9 17)
                , dayOfWeek = one (between 1 5)
                }
-}
let Schedule/Type
    : Type
    = { minute : CronField
      , hour : CronField
      , dayOfMonth : CronField
      , month : CronField
      , dayOfWeek : CronField
      }

let Schedule/default =
      { minute = one every
      , hour = one every
      , dayOfMonth = one every
      , month = one every
      , dayOfWeek = one every
      }

let Schedule = { Type = Schedule/Type, default = Schedule/default }

let everyMinutes = \(n : Natural) -> Schedule/default // { minute = one (everyN n) }

let dailyAt =
      \(h : Natural) ->
        Schedule/default // { minute = one (at 0), hour = one (at h) }

let CronJob/Type
    : Type
    = { schedule : Schedule/Type
      , prompt : Text
      , session : Optional Text
      , retryMax : Optional Natural
      , retryWait : Optional Natural
      }

let CronJob =
      { Type = CronJob/Type
      , default =
        { schedule = Schedule/default
        , session = None Text
        , retryMax = None Natural
        , retryWait = None Natural
        }
      }

{-| Provider-run ("server-side") tools: the provider executes them itself, mid-turn, and streams
    back what it found — no client round-trip per call. Which ones a provider can actually run
    differs, and the sets are disjoint: `XSearch` and `CollectionsSearch` are xAI's, `WebFetch` and
    the client builtins are Anthropic's, `UrlContext` is Gemini's. Asking a provider for one it
    cannot run is refused by name at load-to-send time, not dropped.

    The `XSearch` window uses Dhall's own `Date` — a bare `2026-08-26` literal, whose grammar and
    ranges the language checks. It was `Optional Text`, so `"2026-13-40"`, `"26/08/01"` and
    `"yesterday"` all type-checked and reached the provider, which answers with a 400 or with an
    empty result set that reads like "nothing matched".
-}
let ServerTool
    : Type
    = < WebSearch :
          { maxUses : Optional Natural
          , allowedDomains : List Text
          , blockedDomains : List Text
          }
      | WebFetch : { maxUses : Optional Natural }
      | CodeExecution
      | XSearch :
          { allowedHandles : List Text
          , blockedHandles : List Text
          , fromDate : Optional Date
          , toDate : Optional Date
          }
      | CollectionsSearch : { collectionIds : List Text, limit : Optional Natural }
      | UrlContext
      >

{-| `ServerTool.WebSearch` with everything defaulted — the common case. -}
let webSearch =
      ServerTool.WebSearch
        { maxUses = None Natural
        , allowedDomains = [] : List Text
        , blockedDomains = [] : List Text
        }

{-| `ServerTool.XSearch` with everything defaulted. -}
let xSearch =
      ServerTool.XSearch
        { allowedHandles = [] : List Text
        , blockedHandles = [] : List Text
        , fromDate = None Date
        , toDate = None Date
        }

{-| A tool by name: the ones `lav` ships, plus `Custom` for the ones it does not — MCP servers
    namespace theirs as `<label>_<tool>`, and `mainWith` callers add their own.

    These were bare `Text`, where a misspelling was not an error at all: a grant that matches no
    tool simply never applies, and a scheduled action that names no tool fails only when it fires,
    in a gateway, hours later. The alternatives here are the tool names themselves, so there is no
    mapping to get wrong, and a tasty test pins the list to the tools actually registered.
-}
let ToolName
    : Type
    = < batch_edit
      | edit_anchored
      | edit_files
      | find_references
      | list_dir
      | outline_file
      | outline_files
      | read_anchored
      | read_file
      | read_files
      | schedule_list
      | schedule_run
      | schedule_status
      | shell
      | str_replace
      | write_file
      | Custom : Text
      >

{-| Per-room / per-member Matrix tool permissions. A room or user absent from the list is
    unconstrained; when both apply the effective set is their INTERSECTION.
-}
{-| What a scheduled job does when it fires. Was `tool` and `prompt` as two `Optional Text`
    fields with a runtime check that exactly one was set; as a union, "both" and "neither" are
    unrepresentable.

    `args` stays a JSON object *string* deliberately: cron has a fixed grammar worth typing, but
    tool arguments have no schema except the invoked tool's own.
-}
let Action
    : Type
    = < Prompt : Text | Tool : { name : ToolName, args : Optional Text } >

-- | One entry of a `--schedule-file`: when, what, where to report, and the retry overrides.
let ScheduleJob/Type
    : Type
    = { jobId : Text
      , schedule : Schedule/Type
      , action : Action
      , room : Optional Text
      , session : Optional Text
      , summarize : Optional Text
      , retryMax : Optional Natural
      , retryWait : Optional Natural
      }

let ScheduleJob =
      { Type = ScheduleJob/Type
      , default =
        { schedule = Schedule/default
        , room = None Text
        , session = None Text
        , summarize = None Text
        , retryMax = None Natural
        , retryWait = None Natural
        }
      }

let ToolGrant/Type
    : Type
    = { subject : Text, tools : List ToolName }

let ToolGrant =
      { Type = ToolGrant/Type, default = { tools = [] : List ToolName } }

let Config =
      { Type =
          { provider : Optional Provider
          , model : Optional Text
          , thinking : Optional Thinking
          , maxTokens : Optional Natural
          , maxSteps : Optional Natural
          , contextLimit : Optional Natural
          , routing : Optional Routing/Type
          , advisorModel : Optional Text
          , budget : Optional Natural
          , noProgressLimit : Optional Natural
          , verify : Optional Verify/Type
          , requireEdit : Optional Bool
          , summaryModel : Optional Text
          , budgetAwareness : Optional Bool
          , persona : Optional Text
          , system : Optional Text
          , logLevel : Optional LogLevel
          , serverTools : Optional (List ServerTool)
          , serve : Optional Port
          , serveA2a : Optional Port
          , acp : Optional Bool
          , tui : Optional Tui/Type
          , serveSlack : Optional Bool
          , serveMatrix : Optional Bool
          , matrixRoomTools : Optional (List ToolGrant/Type)
          , matrixUserTools : Optional (List ToolGrant/Type)
          , sessionDir : Optional Text
          , mcpServers : Optional (List Mcp/Type)
          , tune : Optional Tune/Type
          , legion : Optional Legion/Type
          , lang : Optional Language
          , cron : Optional (List CronJob/Type)
          , cronFile : Optional Text
          , cronRetryMax : Optional Natural
          , cronRetryWait : Optional Natural
          , scheduleFile : Optional Text
          , scheduleRetryMax : Optional Natural
          , scheduleRetryWait : Optional Natural
          , fallback : Optional (List ModelRef)
          , fallbackCooldown : Optional Natural
          }
      , default =
          { provider = None Provider
          , model = None Text
          , thinking = None Thinking
          , maxTokens = None Natural
          , maxSteps = None Natural
          , contextLimit = None Natural
          , routing = None Routing/Type
          , advisorModel = None Text
          , budget = None Natural
          , noProgressLimit = None Natural
          , verify = None Verify/Type
          , requireEdit = None Bool
          , summaryModel = None Text
          , budgetAwareness = None Bool
          , persona = None Text
          , system = None Text
          , logLevel = None LogLevel
          , serverTools = None (List ServerTool)
          , serve = None Port
          , serveA2a = None Port
          , acp = None Bool
          , tui = None Tui/Type
          , serveSlack = None Bool
          , serveMatrix = None Bool
          , matrixRoomTools = None (List ToolGrant/Type)
          , matrixUserTools = None (List ToolGrant/Type)
          , sessionDir = None Text
          , mcpServers = None (List Mcp/Type)
          , tune = None Tune/Type
          , legion = None Legion/Type
          , lang = None Language
          , cron = None (List CronJob/Type)
          , cronFile = None Text
          , cronRetryMax = None Natural
          , cronRetryWait = None Natural
          , scheduleFile = None Text
          , scheduleRetryMax = None Natural
          , scheduleRetryWait = None Natural
          , fallback = None (List ModelRef)
          , fallbackCooldown = None Natural
          }
      }

in  { Provider
    , Thinking
    , Language
    , LogLevel
    , ServerTool
    , webSearch
    , xSearch
    , Port
    , Model
    , ModelRef
    , anthropic
    , google
    , xai
    , xaiGrpc
    , xaiResponses
    , claudeCli
    , McpTarget
    , Routing
    , Routing/Type
    , Verify
    , Verify/Type
    , TuneStrategy
    , Tune
    , Tune/Type
    , Tui
    , Tui/Type
    , Legion
    , Legion/Type
    , Mcp
    , Mcp/Type
    , CronBase
    , CronTerm
    , CronTerm/Type
    , CronField
    , one
    , terms
    , every
    , everyN
    , at
    , between
    , from
    , Schedule
    , Schedule/Type
    , Schedule/default
    , everyMinutes
    , dailyAt
    , CronJob
    , CronJob/Type
    , Action
    , ScheduleJob
    , ScheduleJob/Type
    , ToolName
    , ToolGrant
    , ToolGrant/Type
    , Config
    }
