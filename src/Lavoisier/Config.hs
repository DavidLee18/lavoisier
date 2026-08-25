-- | Dhall configuration file for @lav@.
--
-- The config is a Dhall record built from @schema.dhall@, which is shipped beside this package and
-- imported by the user's file:
--
-- > let L = ./schema.dhall
-- > in  L.Config::{ provider = Some L.Provider.Anthropic, serve = Some 8080 }
--
-- Every enumerable field is a Dhall **union**, so @L.Provider.Anthropi@ is a type error at load
-- naming the missing constructor, and a bare @"anthropic"@ is a type error naming the expected
-- union. Previously these were @Text@ with the alternatives written in a comment: Dhall checked
-- that the value was /a/ Text and nothing checked that it was a /valid/ one, so a typo travelled
-- all the way to the provider factory before failing.
--
-- The one check Dhall cannot express is the port range — its @assert@ type-checks a lambda body
-- with the argument still abstract, so a @Natural -> Port@ smart constructor is not writable. That
-- bound is enforced here, in 'portDecoder', and reported as a load error naming the field.
--
-- Precedence — explicit CLI flag > config file > built-in default — is applied by the CLI.
module Lavoisier.Config
  ( FileConfig (..),
    defaultConfig,
    loadConfig,
  )
where

import Data.Either.Validation (Validation (..))
import Data.Text (Text)
import Data.Text qualified as T
import Data.Word (Word32)
import Dhall (Decoder, FromDhall (..), Natural)
import Dhall qualified
import Lavoisier.Domain
import Lavoisier.Log (LogLevel (..))
import Lavoisier.Protocol.Message (ServerTool (..), ThinkingLevel (..))

-- ---------------------------------------------------------------------------
-- Decoders for the schema's unions
-- ---------------------------------------------------------------------------

-- | Decode a Dhall enum union (all alternatives empty) from a table of constructor names.
enumDecoder :: [(Text, a)] -> Decoder a
enumDecoder table =
  Dhall.union (mconcat [c <$ Dhall.constructor n Dhall.unit | (n, c) <- table])

-- | @< Anthropic | Google | Xai | XaiGrpc | ClaudeCli >@. The alternative table is generated from
-- 'allProviders', so adding a constructor to 'ProviderId' extends the decoder automatically and
-- cannot leave it behind. Declared as a plain 'Decoder' rather than a 'FromDhall' instance to keep
-- "Lavoisier.Domain" free of a Dhall dependency — the vocabulary must not know the config format.
providerDecoder :: Decoder ProviderId
providerDecoder = enumDecoder [(T.pack (show p), p) | p <- allProviders]

-- | @< English | Korean >@.
languageDecoder :: Decoder Language
languageDecoder = enumDecoder [(T.pack (show l), l) | l <- [English, Korean]]

-- | @< Off | Low | Medium | High >@. The Haskell constructors carry a @Think@ prefix that would be
-- noise in a config file, so the mapping is spelled out rather than derived.
thinkingDecoder :: Decoder ThinkingLevel
thinkingDecoder =
  enumDecoder
    [ ("Off", ThinkOff),
      ("Low", ThinkLow),
      ("Medium", ThinkMedium),
      ("High", ThinkHigh)
    ]

-- | @< Error | Warn | Info | Debug >@, likewise unprefixed on the Dhall side.
-- | @< WebSearch : … | WebFetch : … | CodeExecution | XSearch : … | CollectionsSearch : … |
-- UrlContext >@. Written out rather than derived because the payload field names are the config's
-- vocabulary (@allowedDomains@), not the ADT's positional shape.
serverToolDecoder :: Decoder ServerTool
serverToolDecoder =
  Dhall.union
    ( Dhall.constructor "WebSearch" webSearchRec
        <> Dhall.constructor "WebFetch" webFetchRec
        <> (STCodeExecution <$ Dhall.constructor "CodeExecution" Dhall.unit)
        <> Dhall.constructor "XSearch" xSearchRec
        <> Dhall.constructor "CollectionsSearch" collectionsRec
        <> (STUrlContext <$ Dhall.constructor "UrlContext" Dhall.unit)
    )
  where
    webSearchRec =
      Dhall.record
        ( STWebSearch
            <$> Dhall.field "maxUses" (Dhall.maybe word32)
            <*> Dhall.field "allowedDomains" Dhall.auto
            <*> Dhall.field "blockedDomains" Dhall.auto
        )
    webFetchRec = Dhall.record (STWebFetch <$> Dhall.field "maxUses" (Dhall.maybe word32))
    xSearchRec =
      Dhall.record
        ( STXSearch
            <$> Dhall.field "allowedHandles" Dhall.auto
            <*> Dhall.field "blockedHandles" Dhall.auto
            <*> Dhall.field "fromDate" Dhall.auto
            <*> Dhall.field "toDate" Dhall.auto
        )
    collectionsRec =
      Dhall.record
        ( STCollectionsSearch
            <$> Dhall.field "collectionIds" Dhall.auto
            <*> Dhall.field "limit" (Dhall.maybe word32)
        )
    word32 =
      refine (Dhall.auto @Natural) $ \n ->
        if n > fromIntegral (maxBound :: Word32)
          then Left ("serverTools: value out of range: " <> T.pack (show n))
          else Right (fromIntegral n :: Word32)

logLevelDecoder :: Decoder LogLevel
logLevelDecoder =
  enumDecoder
    [ ("Error", LogError),
      ("Warn", LogWarn),
      ("Info", LogInfo),
      ("Debug", LogDebug)
    ]

-- | Post-process a decoder with a check that can fail. This is where every constraint that
-- Dhall's type system cannot state gets enforced — always as a load-time error naming the field,
-- never as a silent coercion or a default.
refine :: Decoder a -> (a -> Either Text b) -> Decoder b
refine d f = Dhall.Decoder ex (Dhall.expected d)
  where
    ex expr = case Dhall.extract d expr of
      Success a -> either Dhall.extractError pure (f a)
      Failure e -> Failure e

-- | A port, range-checked here because Dhall cannot express the bound (see the module header).
portDecoder :: Text -> Decoder Port
portDecoder field = refine (Dhall.auto @Natural) check
  where
    check n =
      maybe
        (Left (field <> ": " <> T.pack (show n) <> " is not a port (want 1..65535)"))
        Right
        (mkPort (toInteger n))

-- | @{ provider, model }@ — the record that replaced the packed @"provider:model"@ string.
modelRefDecoder :: Decoder ModelRef
modelRefDecoder =
  Dhall.record
    ( ModelRef
        <$> Dhall.field "provider" providerDecoder
        <*> Dhall.field "model" (ModelId <$> Dhall.auto)
    )

-- | @< Stdio : Text | Http : Text >@. The HTTP arm is validated as a URL here, so the
-- stdio-vs-HTTP decision is made once at load instead of being re-sniffed at connect time.
mcpTargetDecoder :: Decoder McpTarget
mcpTargetDecoder =
  Dhall.union
    ( (McpStdio <$> Dhall.constructor "Stdio" Dhall.auto)
        <> (Dhall.constructor "Http" httpUrl)
    )
  where
    httpUrl =
      refine (Dhall.auto @Text) $ \t ->
        maybe (Left ("mcpServers: not an http(s)/ws(s) URL: " <> t)) (Right . McpHttp) (mkUrl t)

mcpSpecDecoder :: Decoder McpSpec
mcpSpecDecoder =
  Dhall.record
    ( McpSpec
        <$> Dhall.field "label" (McpLabel <$> Dhall.auto)
        <*> Dhall.field "target" mcpTargetDecoder
    )

cronExprDecoder :: Decoder CronExpr
cronExprDecoder =
  Dhall.record
    ( CronExpr
        <$> Dhall.field "minute" Dhall.auto
        <*> Dhall.field "hour" Dhall.auto
        <*> Dhall.field "dayOfMonth" Dhall.auto
        <*> Dhall.field "month" Dhall.auto
        <*> Dhall.field "dayOfWeek" Dhall.auto
    )

cronJobDecoder :: Decoder CronJobSpec
cronJobDecoder =
  Dhall.record
    ( CronJobSpec
        <$> Dhall.field "schedule" cronExprDecoder
        <*> Dhall.field "prompt" Dhall.auto
        <*> Dhall.field "session" (fmap SessionId <$> Dhall.auto)
        <*> Dhall.field "retryMax" (fmap (RetryCount . fromIntegral @Natural) <$> Dhall.auto)
        <*> Dhall.field "retryWait" (fmap (Seconds . fromIntegral @Natural) <$> Dhall.auto)
    )

-- | @{ subject, tools }@, with the subject parsed by the caller-supplied sigil check so a room id
-- cannot be written where a user id belongs.
toolGrantDecoder :: Text -> (Text -> Maybe s) -> Decoder (ToolGrant s)
toolGrantDecoder field parseSubject =
  Dhall.record
    ( ToolGrant
        <$> Dhall.field "subject" subjectDecoder
        <*> Dhall.field "tools" (map ToolName <$> Dhall.auto)
    )
  where
    subjectDecoder =
      refine (Dhall.auto @Text) $ \t ->
        maybe (Left (field <> ": malformed subject: " <> t)) Right (parseSubject t)

-- ---------------------------------------------------------------------------
-- The config record
-- ---------------------------------------------------------------------------

-- | The parsed config. Field names match the Dhall record keys exactly.
data FileConfig = FileConfig
  { provider :: Maybe ProviderId,
    model :: Maybe ModelId,
    thinking :: Maybe ThinkingLevel,
    maxTokens :: Maybe Natural,
    maxSteps :: Maybe Natural,
    contextLimit :: Maybe Natural,
    cheapModel :: Maybe ModelId,
    escalateAfter :: Maybe Natural,
    advisorModel :: Maybe ModelId,
    budget :: Maybe Natural,
    noProgressLimit :: Maybe Natural,
    verifyCmd :: Maybe Text,
    requireEdit :: Maybe Bool,
    verifyAndFix :: Maybe Bool,
    inLoopVerify :: Maybe Bool,
    summaryModel :: Maybe ModelId,
    budgetAwareness :: Maybe Bool,
    -- | Path to a persona file layered /above/ the operational system prompt.
    persona :: Maybe FilePath,
    -- | Replaces the operational system prompt outright (the persona still layers above it).
    system :: Maybe Text,
    logLevel :: Maybe LogLevel,
    -- | Provider-run tools to offer. Which ones a given provider can actually run differs, and a
    -- request for one it cannot is refused by name rather than dropped.
    serverTools :: Maybe [ServerTool],
    serve :: Maybe Port,
    serveA2a :: Maybe Port,
    acp :: Maybe Bool,
    tui :: Maybe Bool,
    tuiAutoApprove :: Maybe Bool,
    serveSlack :: Maybe Bool,
    serveMatrix :: Maybe Bool,
    -- | Per-room Matrix tool permissions (a room absent from the list is unconstrained).
    matrixRoomTools :: Maybe [ToolGrant RoomId],
    -- | Per-member Matrix tool permissions (intersected with the room's when both apply).
    matrixUserTools :: Maybe [ToolGrant MatrixUserId],
    sessionDir :: Maybe FilePath,
    mcpServers :: Maybe [McpSpec],
    tune :: Maybe Bool,
    tuneBayes :: Maybe Bool,
    tuneState :: Maybe FilePath,
    legionDebaters :: Maybe [ModelRef],
    legionJudge :: Maybe ModelRef,
    legionRounds :: Maybe Natural,
    lang :: Maybe Language,
    cron :: Maybe [CronJobSpec],
    cronFile :: Maybe FilePath,
    cronRetryMax :: Maybe RetryCount,
    cronRetryWait :: Maybe Seconds,
    scheduleFile :: Maybe FilePath,
    scheduleRetryMax :: Maybe RetryCount,
    scheduleRetryWait :: Maybe Seconds,
    fallback :: Maybe [ModelRef],
    fallbackCooldown :: Maybe Seconds
  }
  deriving stock (Show, Eq)

-- | The decoder for 'FileConfig', written out rather than derived because most fields need one of
-- the checked decoders above.
fileConfigDecoder :: Decoder FileConfig
fileConfigDecoder =
  Dhall.record
    ( FileConfig
        <$> Dhall.field "provider" (Dhall.maybe providerDecoder)
        <*> Dhall.field "model" (fmap ModelId <$> Dhall.auto)
        <*> Dhall.field "thinking" (Dhall.maybe thinkingDecoder)
        <*> Dhall.field "maxTokens" Dhall.auto
        <*> Dhall.field "maxSteps" Dhall.auto
        <*> Dhall.field "contextLimit" Dhall.auto
        <*> Dhall.field "cheapModel" (fmap ModelId <$> Dhall.auto)
        <*> Dhall.field "escalateAfter" Dhall.auto
        <*> Dhall.field "advisorModel" (fmap ModelId <$> Dhall.auto)
        <*> Dhall.field "budget" Dhall.auto
        <*> Dhall.field "noProgressLimit" Dhall.auto
        <*> Dhall.field "verifyCmd" Dhall.auto
        <*> Dhall.field "requireEdit" Dhall.auto
        <*> Dhall.field "verifyAndFix" Dhall.auto
        <*> Dhall.field "inLoopVerify" Dhall.auto
        <*> Dhall.field "summaryModel" (fmap ModelId <$> Dhall.auto)
        <*> Dhall.field "budgetAwareness" Dhall.auto
        <*> Dhall.field "persona" (fmap T.unpack <$> Dhall.auto)
        <*> Dhall.field "system" Dhall.auto
        <*> Dhall.field "logLevel" (Dhall.maybe logLevelDecoder)
        <*> Dhall.field "serverTools" (Dhall.maybe (Dhall.list serverToolDecoder))
        <*> Dhall.field "serve" (Dhall.maybe (portDecoder "serve"))
        <*> Dhall.field "serveA2a" (Dhall.maybe (portDecoder "serveA2a"))
        <*> Dhall.field "acp" Dhall.auto
        <*> Dhall.field "tui" Dhall.auto
        <*> Dhall.field "tuiAutoApprove" Dhall.auto
        <*> Dhall.field "serveSlack" Dhall.auto
        <*> Dhall.field "serveMatrix" Dhall.auto
        <*> Dhall.field
          "matrixRoomTools"
          (Dhall.maybe (Dhall.list (toolGrantDecoder "matrixRoomTools" mkRoomId)))
        <*> Dhall.field
          "matrixUserTools"
          (Dhall.maybe (Dhall.list (toolGrantDecoder "matrixUserTools" mkMatrixUserId)))
        <*> Dhall.field "sessionDir" (fmap T.unpack <$> Dhall.auto)
        <*> Dhall.field "mcpServers" (Dhall.maybe (Dhall.list mcpSpecDecoder))
        <*> Dhall.field "tune" Dhall.auto
        <*> Dhall.field "tuneBayes" Dhall.auto
        <*> Dhall.field "tuneState" (fmap T.unpack <$> Dhall.auto)
        <*> Dhall.field "legionDebaters" (Dhall.maybe (Dhall.list modelRefDecoder))
        <*> Dhall.field "legionJudge" (Dhall.maybe modelRefDecoder)
        <*> Dhall.field "legionRounds" Dhall.auto
        <*> Dhall.field "lang" (Dhall.maybe languageDecoder)
        <*> Dhall.field "cron" (Dhall.maybe (Dhall.list cronJobDecoder))
        <*> Dhall.field "cronFile" (fmap T.unpack <$> Dhall.auto)
        <*> Dhall.field "cronRetryMax" (fmap (RetryCount . fromIntegral @Natural) <$> Dhall.auto)
        <*> Dhall.field "cronRetryWait" (fmap (Seconds . fromIntegral @Natural) <$> Dhall.auto)
        <*> Dhall.field "scheduleFile" (fmap T.unpack <$> Dhall.auto)
        <*> Dhall.field "scheduleRetryMax" (fmap (RetryCount . fromIntegral @Natural) <$> Dhall.auto)
        <*> Dhall.field "scheduleRetryWait" (fmap (Seconds . fromIntegral @Natural) <$> Dhall.auto)
        <*> Dhall.field "fallback" (Dhall.maybe (Dhall.list modelRefDecoder))
        <*> Dhall.field "fallbackCooldown" (fmap (Seconds . fromIntegral @Natural) <$> Dhall.auto)
    )

instance FromDhall FileConfig where
  autoWith _ = fileConfigDecoder

-- | The all-unset config.
defaultConfig :: FileConfig
defaultConfig =
  FileConfig
    n
    n
    n
    n
    n
    n
    n
    n
    n
    n
    n
    n
    n
    n
    n
    n
    n
    n
    n
    n
    n
    n
    n
    n
    n
    n
    n
    n
    n
    n
    n
    n
    n
    n
    n
    n
    n
    n
    n
    n
    n
    n
    n
    n
    n
    n
    n
    n
  where
    n :: Maybe a
    n = Nothing

-- | Load a Dhall config file. Uses 'Dhall.inputFile' so that a relative import in the config —
-- notably @./schema.dhall@ — resolves against the config file's own directory rather than the
-- process working directory. Throws a @Dhall@ exception on a parse, type, or range error.
loadConfig :: FilePath -> IO FileConfig
loadConfig = Dhall.inputFile Dhall.auto
