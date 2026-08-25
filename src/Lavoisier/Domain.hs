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
    CronExpr (..),
    everyMinute,
    renderCronExpr,
    CronJobSpec (..),

    -- * Permissions
    ToolGrant (..),

    -- * Bounded scalars
    Seconds (..),
    RetryCount (..),
)
where

import Data.Char (isDigit)
import Data.List (intercalate)
import Data.String (IsString)
import Data.Text (Text)
import Data.Word (Word16, Word32)
import GHC.Generics (Generic)

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

{- | The five cron fields, named. They used to share a single string with the prompt
(@"*\/30 9-17 * * 1-5 check CI"@), so loading a job meant splitting on whitespace and /guessing/
where the schedule stopped and the prose began — a prompt beginning with a digit was enough to
shift the boundary. Separating them removes the guess.
-}
data CronExpr = CronExpr
    { ceMinute ∷ Text
    , ceHour ∷ Text
    , ceDayOfMonth ∷ Text
    , ceMonth ∷ Text
    , ceDayOfWeek ∷ Text
    }
    deriving stock (Eq, Generic, Show)

-- | @* * * * *@ — every minute; the base the other fields are overridden onto.
everyMinute ∷ CronExpr
everyMinute = CronExpr "*" "*" "*" "*" "*"

-- | Render back to the space-separated five-field form the schedule engine parses.
renderCronExpr ∷ CronExpr → Text
renderCronExpr CronExpr {..} =
    T.unwords [ceMinute, ceHour, ceDayOfMonth, ceMonth, ceDayOfWeek]

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
