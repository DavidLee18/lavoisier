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

{-| A provider-qualified model. Used for legion debaters, the legion judge, and the
    `--fallback` chain — all three used to be the packed string "provider:model".
-}
let ModelRef/Type
    : Type
    = { provider : Provider, model : Text }

let ModelRef =
      { Type = ModelRef/Type, default = { provider = Provider.Anthropic } }

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

-- | A whole cron field: one or more terms. `lav` range-checks each against the field it is in.
let CronField
    : Type
    = List CronTerm/Type

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
      Schedule::{ minute = [ everyN 30 ], hour = [ between 9 17 ], dayOfWeek = [ between 1 5 ] }
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
      { minute = [ every ]
      , hour = [ every ]
      , dayOfMonth = [ every ]
      , month = [ every ]
      , dayOfWeek = [ every ]
      }

let Schedule = { Type = Schedule/Type, default = Schedule/default }

let everyMinutes = \(n : Natural) -> Schedule/default // { minute = [ everyN n ] }

let dailyAt =
      \(h : Natural) -> Schedule/default // { minute = [ at 0 ], hour = [ at h ] }

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
          , fromDate : Optional Text
          , toDate : Optional Text
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
        , fromDate = None Text
        , toDate = None Text
        }

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
    = < Prompt : Text | Tool : { name : Text, args : Optional Text } >

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
    = { subject : Text, tools : List Text }

let ToolGrant = { Type = ToolGrant/Type, default = { tools = [] : List Text } }

let Config =
      { Type =
          { provider : Optional Provider
          , model : Optional Text
          , thinking : Optional Thinking
          , maxTokens : Optional Natural
          , maxSteps : Optional Natural
          , contextLimit : Optional Natural
          , cheapModel : Optional Text
          , escalateAfter : Optional Natural
          , advisorModel : Optional Text
          , budget : Optional Natural
          , noProgressLimit : Optional Natural
          , verifyCmd : Optional Text
          , requireEdit : Optional Bool
          , verifyAndFix : Optional Bool
          , inLoopVerify : Optional Bool
          , summaryModel : Optional Text
          , budgetAwareness : Optional Bool
          , persona : Optional Text
          , system : Optional Text
          , logLevel : Optional LogLevel
          , serverTools : Optional (List ServerTool)
          , serve : Optional Port
          , serveA2a : Optional Port
          , acp : Optional Bool
          , tui : Optional Bool
          , tuiAutoApprove : Optional Bool
          , serveSlack : Optional Bool
          , serveMatrix : Optional Bool
          , matrixRoomTools : Optional (List ToolGrant/Type)
          , matrixUserTools : Optional (List ToolGrant/Type)
          , sessionDir : Optional Text
          , mcpServers : Optional (List Mcp/Type)
          , tune : Optional Bool
          , tuneBayes : Optional Bool
          , tuneState : Optional Text
          , legionDebaters : Optional (List ModelRef/Type)
          , legionJudge : Optional ModelRef/Type
          , legionRounds : Optional Natural
          , lang : Optional Language
          , cron : Optional (List CronJob/Type)
          , cronFile : Optional Text
          , cronRetryMax : Optional Natural
          , cronRetryWait : Optional Natural
          , scheduleFile : Optional Text
          , scheduleRetryMax : Optional Natural
          , scheduleRetryWait : Optional Natural
          , fallback : Optional (List ModelRef/Type)
          , fallbackCooldown : Optional Natural
          }
      , default =
          { provider = None Provider
          , model = None Text
          , thinking = None Thinking
          , maxTokens = None Natural
          , maxSteps = None Natural
          , contextLimit = None Natural
          , cheapModel = None Text
          , escalateAfter = None Natural
          , advisorModel = None Text
          , budget = None Natural
          , noProgressLimit = None Natural
          , verifyCmd = None Text
          , requireEdit = None Bool
          , verifyAndFix = None Bool
          , inLoopVerify = None Bool
          , summaryModel = None Text
          , budgetAwareness = None Bool
          , persona = None Text
          , system = None Text
          , logLevel = None LogLevel
          , serverTools = None (List ServerTool)
          , serve = None Port
          , serveA2a = None Port
          , acp = None Bool
          , tui = None Bool
          , tuiAutoApprove = None Bool
          , serveSlack = None Bool
          , serveMatrix = None Bool
          , matrixRoomTools = None (List ToolGrant/Type)
          , matrixUserTools = None (List ToolGrant/Type)
          , sessionDir = None Text
          , mcpServers = None (List Mcp/Type)
          , tune = None Bool
          , tuneBayes = None Bool
          , tuneState = None Text
          , legionDebaters = None (List ModelRef/Type)
          , legionJudge = None ModelRef/Type
          , legionRounds = None Natural
          , lang = None Language
          , cron = None (List CronJob/Type)
          , cronFile = None Text
          , cronRetryMax = None Natural
          , cronRetryWait = None Natural
          , scheduleFile = None Text
          , scheduleRetryMax = None Natural
          , scheduleRetryWait = None Natural
          , fallback = None (List ModelRef/Type)
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
    , ModelRef
    , ModelRef/Type
    , McpTarget
    , Mcp
    , Mcp/Type
    , CronBase
    , CronTerm
    , CronTerm/Type
    , CronField
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
    , ToolGrant
    , ToolGrant/Type
    , Config
    }
