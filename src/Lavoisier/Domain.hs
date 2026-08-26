{- | The shared domain vocabulary: the small types that name what the rest of the program talks
about — which provider, which port, which model, which tool.

This module exists because those values used to travel as 'Text' and 'String', which meant every
consumer re-parsed them and no two consumers were checked against each other. The canonical
example was provider selection: @selectProvider@ matched string literals in one place and
@batchEditTools@ compared @provider == "anthropic"@ in another, with nothing tying the two
together — adding a provider silently did the wrong thing in the second. With 'ProviderId' both
are exhaustive @case@s and the compiler enforces the connection.

It sits at the protocol layer and depends on nothing above it (architecture invariant 1), so
gateways, providers and the CLI can all share it without depending on each other.
-}
module Lavoisier.Domain (
    -- * Providers
    ProviderId (..),
    allProviders,
    renderProviderId,
    parseProviderId,
    providerIdList,
    defaultModelFor,

    -- * Network
    Port,
    unPort,
    mkPort,
    parsePort,
    renderPort,
    Url,
    unUrl,
    mkUrl,

    -- * Models and tools
    ModelId (..),
    ToolName (..),
    builtinToolNames,
    SessionId (..),

    -- * Matrix identifiers
    RoomId,
    unRoomId,
    mkRoomId,
    MatrixUserId,
    unMatrixUserId,
    mkMatrixUserId,

    -- * Localisation
    Language (..),
    Locale (..),
    languageFromLocale,

    -- * Composite specs that used to be packed strings
    ModelRef (..),
    renderModelRef,
    parseModelRef,
    McpLabel (..),
    McpTarget (..),
    McpSpec (..),
    parseMcpSpec,

    -- * Cron
    CronFieldKind (..),
    cronFieldName,
    cronFieldBounds,
    CronBase (..),
    CronTerm (..),
    CronField (cfKind, cfTerms),
    mkCronField,
    CronExpr (ceMinute, ceHour, ceDayOfMonth, ceMonth, ceDayOfWeek),
    mkCronExpr,
    everyMinute,
    cronFields,
    renderCronExpr,
    renderCronField,
    CronJobSpec (..),

    -- * Schedules
    ScheduleAction (..),
    ScheduleJobSpec (..),

    -- * Dates
    Date (dYear, dMonth, dDay),
    mkDate,
    renderDate,

    -- * Co-dependent knob groups
    Routing (..),
    VerifySpec (..),
    TuneStrategy (..),
    Tuning (..),
    TuiSpec (..),
    LegionSpec (lgDebaters, lgJudge, lgRounds),
    mkLegionSpec,

    -- * Permissions
    ToolGrant (..),

    -- * Bounded scalars
    Seconds (..),
    RetryCount (..),
)
where

import Data.Char (isDigit)
import Data.List (intercalate)
import Data.List.NonEmpty (NonEmpty (..))
import Data.String (IsString)
import Data.Text (Text)
import Data.Word (Word16, Word32)
import GHC.Generics (Generic)

import Data.List.NonEmpty qualified as NE
import Data.Text qualified as T

-- ---------------------------------------------------------------------------
-- Providers
-- ---------------------------------------------------------------------------

{- | Which provider backend to drive. 'Bounded' and 'Enum' are derived so that 'allProviders' —
and therefore every user-facing list of the valid values — is generated from the type rather
than hand-maintained alongside it.
-}
data ProviderId
    = Anthropic
    | Google
    | Xai
    | XaiGrpc
    | XaiResponses
    | ClaudeCli
    deriving stock (Bounded, Enum, Eq, Generic, Ord, Show)

-- | Every provider, in declaration order.
allProviders ∷ [ProviderId]
allProviders = [minBound .. maxBound]

-- | The wire\/CLI spelling of a provider.
renderProviderId ∷ ProviderId → Text
renderProviderId = \case
    Anthropic → "anthropic"
    Google → "google"
    Xai → "xai"
    XaiGrpc → "xai-grpc"
    XaiResponses → "xai-responses"
    ClaudeCli → "claude-cli"

-- | Parse a provider name. Total: an unrecognised name is 'Nothing', never a silent default.
parseProviderId ∷ Text → Maybe ProviderId
parseProviderId raw =
    lookup (T.toLower (T.strip raw)) [(renderProviderId p, p) | p ← allProviders]

{- | @anthropic|google|xai|xai-grpc|claude-cli@ — the help\/error string, derived from the type so
it cannot drift out of sync with 'parseProviderId'.
-}
providerIdList ∷ String
providerIdList = intercalate "|" [T.unpack (renderProviderId p) | p ← allProviders]

{- | The model a provider is driven with when nothing names one — neither @--model@, nor the config,
nor a 'ModelRef'. An exhaustive @case@ on 'ProviderId': adding a provider is a compile error here
until it has a default, which is the property the old string dispatch could not give.

It lives beside 'ProviderId' rather than in the CLI because the config schema names it too: a
'ModelRef' can say "this provider, its default model" instead of pinning an id that goes stale.
-}
defaultModelFor ∷ ProviderId → ModelId
defaultModelFor = \case
    Anthropic → "claude-sonnet-4-5"
    Google → "gemini-2.5-flash"
    Xai → "grok-4"
    XaiGrpc → "grok-4"
    XaiResponses → "grok-4.6"
    ClaudeCli → "sonnet"

-- ---------------------------------------------------------------------------
-- Network
-- ---------------------------------------------------------------------------

{- | A TCP port. The constructor is not exported: build one with 'mkPort' or 'parsePort', which is
what keeps @0@ and anything above @65535@ out of the type. Ports used to be @Maybe Int@, where
both were representable and neither was checked.
-}
newtype Port = Port Word16
    deriving stock (Eq, Ord, Show)

-- | The underlying port number.
unPort ∷ Port → Word16
unPort (Port p) = p

-- | Build a port from an integer, rejecting @0@ and out-of-range values.
mkPort ∷ Integer → Maybe Port
mkPort n
    | n > 0 && n <= 65535 = Just (Port (fromInteger n))
    | otherwise = Nothing

-- | Parse a port from text.
parsePort ∷ Text → Maybe Port
parsePort raw
    | not (T.null digits) && T.all isDigit digits = mkPort (read (T.unpack digits))
    | otherwise = Nothing
    where
        digits = T.strip raw

-- | Render a port for display.
renderPort ∷ Port → Text
renderPort = T.pack . show . unPort

{- | A non-empty URL. Not a full RFC 3986 parse — it rejects the empty string and anything without
a scheme, which is the mistake that actually reaches this program (an unset env var).
-}
newtype Url = Url Text
    deriving stock (Eq, Ord, Show)

-- | The underlying URL text.
unUrl ∷ Url → Text
unUrl (Url u) = u

-- | Build a URL, requiring a scheme.
mkUrl ∷ Text → Maybe Url
mkUrl raw
    | any (`T.isPrefixOf` t) ["http://", "https://", "ws://", "wss://"] = Just (Url t)
    | otherwise = Nothing
    where
        t = T.strip raw

-- ---------------------------------------------------------------------------
-- Models, tools, sessions
-- ---------------------------------------------------------------------------

{- | A model identifier (@claude-sonnet-4-5@, @gemini-2.5-flash@, …). Deliberately /not/ an
enumeration: model names are provider-side data that change without us, so an open newtype is
honest where a closed sum would force a release for every new model. The newtype still stops it
being confused with the many other 'Text's nearby.
-}
newtype ModelId = ModelId {unModelId ∷ Text}
    deriving stock (Eq, Ord, Show)
    deriving newtype IsString

-- | A tool's registry name. Distinct from 'ModelId' so the two cannot be swapped at a call site.
newtype ToolName = ToolName {unToolName ∷ Text}
    deriving stock (Eq, Ord, Show)
    deriving newtype IsString

{- | Every tool name @lav@ itself ships, alphabetically — the vocabulary a config file can name
without inventing one.

Tool names used to be bare 'Text' wherever a config mentioned them (the Matrix grants, a scheduled
tool action), so a typo granted or invoked nothing and said nothing: an unmatched name is not an
error, it is simply a permission that never applies. The config schema turns this list into a
union with a @Custom@ escape for MCP and @mainWith@ tools, so the typo is a load error and the
escape is a deliberate act.

A tasty test asserts this list is exactly the set of names the tool modules register, so the
schema cannot fall behind the tools.
-}
builtinToolNames ∷ [ToolName]
builtinToolNames =
    [ "batch_edit"
    , "edit_anchored"
    , "edit_files"
    , "find_references"
    , "list_dir"
    , "outline_file"
    , "outline_files"
    , "read_anchored"
    , "read_file"
    , "read_files"
    , "schedule_list"
    , "schedule_run"
    , "schedule_status"
    , "shell"
    , "str_replace"
    , "write_file"
    ]

-- | A conversation\/session key.
newtype SessionId = SessionId {unSessionId ∷ Text}
    deriving stock (Eq, Ord, Show)
    deriving newtype IsString

-- ---------------------------------------------------------------------------
-- Matrix identifiers
-- ---------------------------------------------------------------------------

{- | A Matrix room id or alias (@!room:hs@ \/ @#alias:hs@). Constructor hidden so the sigil is
checked once, here, rather than assumed at each of the places that index tool permissions by it.
-}
newtype RoomId = RoomId Text
    deriving stock (Eq, Ord, Show)

-- | The underlying room identifier.
unRoomId ∷ RoomId → Text
unRoomId (RoomId r) = r

-- | Build a room id, requiring a @!@ or @#@ sigil.
mkRoomId ∷ Text → Maybe RoomId
mkRoomId raw
    | T.length t > 1 && (T.head t == '!' || T.head t == '#') = Just (RoomId t)
    | otherwise = Nothing
    where
        t = T.strip raw

-- | A Matrix user id (@\@bob:hs@).
newtype MatrixUserId = MatrixUserId Text
    deriving stock (Eq, Ord, Show)

-- | The underlying user identifier.
unMatrixUserId ∷ MatrixUserId → Text
unMatrixUserId (MatrixUserId u) = u

-- | Build a user id, requiring the @\@@ sigil.
mkMatrixUserId ∷ Text → Maybe MatrixUserId
mkMatrixUserId raw
    | T.length t > 1 && T.head t == '@' = Just (MatrixUserId t)
    | otherwise = Nothing
    where
        t = T.strip raw

-- ---------------------------------------------------------------------------
-- Localisation
-- ---------------------------------------------------------------------------

{- | The language gateway- and council-authored notices render in. This type was previously
declared twice — once in "Lavoisier.Gateway.Matrix" and once in "Lavoisier.Legion" — each with
its own copy of 'languageFromLocale'. One definition, one resolver.
-}
data Language = English | Korean
    deriving stock (Bounded, Enum, Eq, Generic, Ord, Show)

-- | A POSIX locale string, e.g. @ko_KR.UTF-8@.
newtype Locale = Locale {unLocale ∷ Text}
    deriving stock (Eq, Ord, Show)
    deriving newtype IsString

{- | Resolve a locale to a 'Language'. Only @ko_KR@ (case-insensitive, any @.encoding@ suffix
ignored) selects Korean; everything else is English.
-}
languageFromLocale ∷ Locale → Language
languageFromLocale (Locale raw) =
    if T.toUpper (T.takeWhile (/= '.') raw) == "KO_KR" then Korean else English

-- ---------------------------------------------------------------------------
-- Composite specs
-- ---------------------------------------------------------------------------

{- | A provider-qualified model reference. Was the packed string @"provider:model"@, re-parsed
independently by the legion council, the judge, and the @--fallback@ chain.
-}
data ModelRef = ModelRef
    { mrProvider ∷ ProviderId
    , mrModel ∷ ModelId
    }
    deriving stock (Eq, Generic, Show)

-- | Render back to the @provider:model@ spelling (for logs and the CLI).
renderModelRef ∷ ModelRef → Text
renderModelRef (ModelRef p (ModelId m)) = renderProviderId p <> ":" <> m

-- | Parse @provider:model@. A missing or unknown provider is an error message, not a default.
parseModelRef ∷ Text → Either Text ModelRef
parseModelRef raw =
    case T.breakOn ":" (T.strip raw) of
        (_, rest) | T.null rest → Left ("expected provider:model, got " <> raw)
        (pText, rest) →
            let mText = T.strip (T.drop 1 rest)
             in case (parseProviderId pText, T.null mText) of
                    (Nothing, _) →
                        Left ("unknown provider " <> pText <> " (" <> T.pack providerIdList <> ")")
                    (_, True) → Left ("missing model in " <> raw)
                    (Just p, False) → Right (ModelRef p (ModelId mText))

-- | The namespace an MCP server's tools are exposed under (@\<label\>_\<tool\>@).
newtype McpLabel = McpLabel {unMcpLabel ∷ Text}
    deriving stock (Eq, Ord, Show)
    deriving newtype IsString

{- | How to reach an MCP server. The stdio\/HTTP distinction used to be recovered by sniffing the
target string for an @http@ prefix at connect time; here it is decided once, at parse time.
-}
data McpTarget
    = McpStdio Text
    | McpHttp Url
    deriving stock (Eq, Show)

-- | An MCP server: a namespace label plus how to reach it. Was @"label: target"@.
data McpSpec = McpSpec
    { msLabel ∷ McpLabel
    , msTarget ∷ McpTarget
    }
    deriving stock (Eq, Show)

-- | Parse @label: target@, where target is a stdio command line or an @http(s)://@ URL.
parseMcpSpec ∷ Text → Either Text McpSpec
parseMcpSpec raw =
    case T.breakOn ":" (T.strip raw) of
        (_, rest) | T.null rest → Left ("expected label: target, got " <> raw)
        (lText, rest) →
            let label = T.strip lText
                target = T.strip (T.drop 1 rest)
             in if T.null label
                    then Left ("missing label in " <> raw)
                    else
                        if T.null target
                            then Left ("missing target in " <> raw)
                            else Right (McpSpec (McpLabel label) (classify target))
    where
        classify t = maybe (McpStdio t) McpHttp (mkUrl t)

-- ---------------------------------------------------------------------------
-- Bounded scalars
-- ---------------------------------------------------------------------------

-- | A duration in whole seconds. 'Word32' rather than 'Int' so a negative wait is unrepresentable.
newtype Seconds = Seconds {unSeconds ∷ Word32}
    deriving stock (Eq, Ord, Show)

-- | A retry budget. Likewise non-negative by construction.
newtype RetryCount = RetryCount {unRetryCount ∷ Word32}
    deriving stock (Eq, Ord, Show)

-- ---------------------------------------------------------------------------
-- Cron
-- ---------------------------------------------------------------------------

{- | Which of the five cron fields a term belongs to. It fixes the field's permitted range and
names the field in load errors, and it travels /with/ the field so a field can never be built
against the wrong bounds.
-}
data CronFieldKind
    = Minute
    | Hour
    | DayOfMonth
    | Month
    | DayOfWeek
    deriving stock (Bounded, Enum, Eq, Generic, Ord, Show)

-- | The field's name as the config spells it, for load errors.
cronFieldName ∷ CronFieldKind → Text
cronFieldName = \case
    Minute → "minute"
    Hour → "hour"
    DayOfMonth → "dayOfMonth"
    Month → "month"
    DayOfWeek → "dayOfWeek"

{- | The inclusive range a field's values must fall in. Day-of-week admits @7@ as an alias for
Sunday (@0@); the fold to @0@ happens when the expression is compiled, so a config that writes @7@
still renders back as @7@.
-}
cronFieldBounds ∷ CronFieldKind → (Int, Int)
cronFieldBounds = \case
    Minute → (0, 59)
    Hour → (0, 23)
    DayOfMonth → (1, 31)
    Month → (1, 12)
    DayOfWeek → (0, 7)

{- | The base of one term, before any step is applied.

'Exactly' means two different things depending on whether a step follows it, which is crontab's
convention rather than a wart of this encoding: @5@ is the single value 5, while @5\/10@ is 5
through the field maximum in steps of ten.
-}
data CronBase
    = -- | @*@
      EveryValue
    | -- | @N@ — or, under a step, @N@ through the field maximum.
      Exactly Int
    | -- | @A-B@
      Between Int Int
    deriving stock (Eq, Generic, Ord, Show)

{- | One comma-separated term: a base, optionally stepped. The step hangs off the base rather than
wrapping another term, so @*\/2\/3@ is unrepresentable.
-}
data CronTerm = CronTerm
    { ctBase ∷ CronBase
    , ctStep ∷ Maybe Int
    }
    deriving stock (Eq, Generic, Ord, Show)

{- | One whole cron field: its kind, and a non-empty list of terms whose every value has been
checked against that kind's range.

The constructor is hidden and 'mkCronExpr' is the only thing that calls it, so a 'CronField' is
evidence that its contents are in range — which is what lets
'Lavoisier.Schedule.Cron.compileCron' be total.
-}
data CronField = CronField
    { cfKind ∷ CronFieldKind
    , cfTerms ∷ NonEmpty CronTerm
    }
    deriving stock (Eq, Generic, Show)

{- | Check a list of terms against a kind's range. 'Left' names the field and the offending value,
ready to be reported as a config load error.
-}
mkCronField ∷ CronFieldKind → NonEmpty CronTerm → Either Text CronField
mkCronField kind terms = CronField kind <$> traverse checkTerm terms
    where
        (lo, hi) = cronFieldBounds kind
        label = cronFieldName kind

        inRange v
            | v < lo || v > hi =
                Left (label <> ": " <> tshow v <> " is out of range " <> tshow lo <> "-" <> tshow hi)
            | otherwise = Right v

        checkTerm t = do
            base ← case ctBase t of
                EveryValue → Right EveryValue
                Exactly n → Exactly <$> inRange n
                Between a b → do
                    a' ← inRange a
                    b' ← inRange b
                    if a' > b'
                        then Left (label <> ": range start " <> tshow a' <> " is greater than its end " <> tshow b')
                        else Right (Between a' b')
            step ← case ctStep t of
                Nothing → Right Nothing
                Just s
                    | s < 1 → Left (label <> ": a step must be at least 1, not " <> tshow s)
                    | otherwise → Right (Just s)
            Right (CronTerm base step)

{- | The five cron fields, named and range-checked.

They used to share a single string with the prompt (@"*\/30 9-17 * * 1-5 check CI"@), so loading a
job meant splitting on whitespace and /guessing/ where the schedule stopped and the prose began — a
prompt beginning with a digit was enough to shift the boundary. Naming the fields removed that
guess; typing them removes what was left, which was that each field was still an unchecked 'Text'
whose errors surfaced when the /gateway started/ rather than when the config loaded.

The constructor is hidden: 'mkCronExpr' takes the terms slot by slot and applies the right
'CronFieldKind' to each, so a field cannot be built against the wrong bounds in the first place.
-}
data CronExpr = CronExpr
    { ceMinute ∷ CronField
    , ceHour ∷ CronField
    , ceDayOfMonth ∷ CronField
    , ceMonth ∷ CronField
    , ceDayOfWeek ∷ CronField
    }
    deriving stock (Eq, Generic, Show)

{- | Build an expression from the terms of each field, in cron's own order. Every field is checked
against its own bounds and the __first__ failure is returned, naming that field.
-}
mkCronExpr ∷
    NonEmpty CronTerm →
    NonEmpty CronTerm →
    NonEmpty CronTerm →
    NonEmpty CronTerm →
    NonEmpty CronTerm →
    Either Text CronExpr
mkCronExpr mi ho dom mo dow =
    CronExpr
        <$> mkCronField Minute mi
        <*> mkCronField Hour ho
        <*> mkCronField DayOfMonth dom
        <*> mkCronField Month mo
        <*> mkCronField DayOfWeek dow

-- | @* * * * *@ — every minute; the base the other fields are overridden onto.
everyMinute ∷ CronExpr
everyMinute = CronExpr (star Minute) (star Hour) (star DayOfMonth) (star Month) (star DayOfWeek)
    where
        star k = CronField k (CronTerm EveryValue Nothing :| [])

-- | The five fields in cron's order.
cronFields ∷ CronExpr → [CronField]
cronFields e = [ceMinute e, ceHour e, ceDayOfMonth e, ceMonth e, ceDayOfWeek e]

-- | Render back to the space-separated five-field crontab form, which round-trips.
renderCronExpr ∷ CronExpr → Text
renderCronExpr = T.unwords . map renderCronField . cronFields

-- | Render one field: its terms, comma-separated.
renderCronField ∷ CronField → Text
renderCronField = T.intercalate "," . map term . NE.toList . cfTerms
    where
        term t = base (ctBase t) <> maybe "" (\s → "/" <> tshow s) (ctStep t)
        base = \case
            EveryValue → "*"
            Exactly n → tshow n
            Between a b → tshow a <> "-" <> tshow b

-- | A cron job: when, what, and the optional per-job session and retry overrides.
data CronJobSpec = CronJobSpec
    { csSchedule ∷ CronExpr
    , csPrompt ∷ Text
    , csSession ∷ Maybe SessionId
    , csRetryMax ∷ Maybe RetryCount
    , csRetryWait ∷ Maybe Seconds
    }
    deriving stock (Eq, Generic, Show)

-- ---------------------------------------------------------------------------
-- Schedules
-- ---------------------------------------------------------------------------

{- | What a scheduled job does when it fires. Was a pair of @Optional Text@ fields (@tool@ and
@prompt@) with a runtime check that exactly one was set; as a union, "both" and "neither" are
unrepresentable.

The tool arguments stay a JSON object /string/ deliberately. Cron has a fixed grammar worth
typing; tool arguments have no schema but the invoked tool's own, so a union here would be
inventing one.
-}
data ScheduleAction
    = -- | Fire a prompt and let the agent choose its tools.
      SAPrompt Text
    | -- | Invoke one tool directly, with its arguments as a JSON object string.
      SATool ToolName (Maybe Text)
    deriving stock (Eq, Generic, Show)

-- | One entry of a @--schedule-file@: when, what, where to report, and the retry overrides.
data ScheduleJobSpec = ScheduleJobSpec
    { sjsId ∷ Text
    , sjsSchedule ∷ CronExpr
    , sjsAction ∷ ScheduleAction
    , sjsRoom ∷ Maybe RoomId
    , sjsSession ∷ Maybe SessionId
    , sjsSummarize ∷ Maybe Text
    , sjsRetryMax ∷ Maybe RetryCount
    , sjsRetryWait ∷ Maybe Seconds
    }
    deriving stock (Eq, Generic, Show)

-- ---------------------------------------------------------------------------
-- Dates
-- ---------------------------------------------------------------------------

{- | A calendar date, for the server-tool search windows that used to be free 'Text' in
@YYYY-MM-DD@ form.

The constructor is hidden so 'mkDate' is the only way in: it range-checks the month and the day
against that month in that year, leap years included. A date is the last thing in the config with
a grammar the type did not state — @"2026-13-40"@, @"26/08/01"@ and @"yesterday"@ all
type-checked as @Text@ and reached the provider, which answered with an unhelpful 400 or, worse,
an empty result set that looked like "nothing matched".
-}
data Date = Date
    { dYear ∷ Int
    , dMonth ∷ Int
    , dDay ∷ Int
    }
    deriving stock (Eq, Generic, Ord, Show)

-- | Build a date, naming which component is out of range.
mkDate ∷ Int → Int → Int → Either Text Date
mkDate y m d
    | y < 1 || y > 9999 = Left ("year: " <> tshow y <> " is out of range 1-9999")
    | m < 1 || m > 12 = Left ("month: " <> tshow m <> " is out of range 1-12")
    | d < 1 || d > daysInMonth y m =
        Left ("day: " <> tshow d <> " is out of range 1-" <> tshow (daysInMonth y m) <> " for month " <> tshow m)
    | otherwise = Right (Date y m d)

-- | Days in a month, Gregorian leap years included.
daysInMonth ∷ Int → Int → Int
daysInMonth y = \case
    2 | leap → 29
    2 → 28
    m | m `elem` [4, 6, 9, 11] → 30
    _ → 31
    where
        leap = (y `mod` 4 == 0 && y `mod` 100 /= 0) || y `mod` 400 == 0

-- | Render as @YYYY-MM-DD@, the form every provider that takes a date window wants.
renderDate ∷ Date → Text
renderDate (Date y m d) = pad 4 y <> "-" <> pad 2 m <> "-" <> pad 2 d
    where
        pad n v = T.justifyRight n '0' (tshow v)

-- ---------------------------------------------------------------------------
-- Co-dependent knob groups
-- ---------------------------------------------------------------------------

{- | Cheap-model-first routing: run the first 'rtEscalateAfter' round-trips on 'rtCheapModel',
then escalate to the primary model.

The threshold used to be a sibling of the model — two independent @Optional@ fields — so
@escalateAfter = Some 5@ with no cheap model type-checked, loaded, and did nothing at all; the
agent loop's own haddock said the knob was "ignored when the cheap model is Nothing". Grouping
them makes that dead combination unrepresentable: there is no escalation threshold without a
model to escalate /from/.
-}
data Routing = Routing
    { rtCheapModel ∷ ModelId
    , rtEscalateAfter ∷ Maybe Int
    -- ^ 'Nothing' keeps the built-in default.
    }
    deriving stock (Eq, Generic, Show)

{- | The verify lever: a command whose exit status decides whether the task is done, plus the two
switches that say what to do with the answer.

@verifyAndFix@ and @inLoopVerify@ were independent 'Bool's beside an @Optional Text@ command, and
both are inert without one — 'Lavoisier.Agent.runVerify' cases on the command first and returns
immediately when it is absent. Two switches that silently do nothing is exactly the shape this
group removes.
-}
data VerifySpec = VerifySpec
    { vsCommand ∷ Text
    -- ^ Shell command; exit 0 means the task verifies.
    , vsAndFix ∷ Bool
    -- ^ On a would-be finish, feed a failure's output back and keep working (bounded).
    , vsInLoop ∷ Bool
    -- ^ Stop as soon as an edit turn makes the command pass, without waiting for the model.
    }
    deriving stock (Eq, Generic, Show)

-- | Which ATO learner to run. There is no @Off@: absence of a 'Tuning' is what off means.
data TuneStrategy
    = -- | ε-greedy ("Lavoisier.Tune").
      Greedy
    | -- | Thompson sampling ("Lavoisier.Tune.Bayes").
      Bayes
    deriving stock (Bounded, Enum, Eq, Generic, Ord, Show)

{- | The ATO tuner: which learner, and where its learned profiles live.

This replaced three independent fields — @tune : Bool@, @tuneBayes : Bool@, @tuneState : Text@ —
whose combinations disagreed with the code that read them. @tuneBayes = True@ with
@tune = False@ ran the Bayesian learner anyway (the builder tested the Bayes flag first), and
@tuneState@ without @tune@ was documented as implying it and did not. As one group both are
gone: the strategy is a choice, not two booleans, and a state path cannot exist without a learner
to persist.
-}
data Tuning = Tuning
    { tuStrategy ∷ TuneStrategy
    , tuState ∷ Maybe FilePath
    -- ^ Load\/persist learned profiles here; 'Nothing' learns for the session only.
    }
    deriving stock (Eq, Generic, Show)

{- | The interactive TUI. Auto-approval was a second top-level 'Bool' that only the TUI reads, so
setting it without the TUI was silently nothing; here it is a field of the thing that reads it.
-}
newtype TuiSpec = TuiSpec
    { tsAutoApprove ∷ Bool
    -- ^ Skip the tool-approval prompts and run every tool unattended.
    }
    deriving stock (Eq, Generic, Show)

{- | A legion council: the debaters, the judge that synthesises their verdict, and how many
critique rounds follow the draft.

The judge and the round count used to sit beside an independent debater list, and the council was
built only when that list was non-empty — so a config that named a judge and a round count but no
debaters was dropped in full, without a word. The constructor is hidden so 'mkLegionSpec' is the
only way in, and it enforces the two-debater floor that "Lavoisier.Legion" needs; a one-model
council is just the advisor pre-pass.
-}
data LegionSpec = LegionSpec
    { lgDebaters ∷ [ModelRef]
    , lgJudge ∷ Maybe ModelRef
    -- ^ 'Nothing' judges with the first debater.
    , lgRounds ∷ Maybe Int
    -- ^ 'Nothing' keeps the built-in default.
    }
    deriving stock (Eq, Generic, Show)

-- | Build a council, rejecting a panel too small to deliberate.
mkLegionSpec ∷ [ModelRef] → Maybe ModelRef → Maybe Int → Either Text LegionSpec
mkLegionSpec debaters judge rounds
    | length debaters < 2 =
        Left ("legion: a council needs at least 2 debaters, got " <> tshow (length debaters))
    | otherwise = Right (LegionSpec debaters judge rounds)

-- ---------------------------------------------------------------------------
-- Permissions
-- ---------------------------------------------------------------------------

{- | A grant of tool names to a subject (a Matrix room or member). Was a bare
@Map Text [Text]@, in which nothing distinguished a room id from a user id from a tool name.
-}
data ToolGrant subject = ToolGrant
    { tgSubject ∷ subject
    , tgTools ∷ [ToolName]
    }
    deriving stock (Eq, Generic, Show)

-- | @show@ into 'Text', for the error messages above.
tshow ∷ Show a ⇒ a → Text
tshow = T.pack . show
