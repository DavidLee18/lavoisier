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
mkCronField ∷ CronFieldKind → [CronTerm] → Either Text CronField
mkCronField kind terms = case NE.nonEmpty terms of
    Nothing → Left (label <> ": a cron field needs at least one term")
    Just ne → CronField kind <$> traverse checkTerm ne
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
mkCronExpr ∷ [CronTerm] → [CronTerm] → [CronTerm] → [CronTerm] → [CronTerm] → Either Text CronExpr
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
