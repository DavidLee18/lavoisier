-- | The command-line entry point, ported (core subset) from Rust @lvz-cli@. Two modes over the same
-- plumbing: a one-shot @ask@ (no tools) and the @--agent@ tool loop. Providers: Anthropic + Google + xAI + claude-cli
-- (@--provider@); other providers reject with a clear message.
--
-- Rendering mirrors the Rust CLI: answer text on stdout; thinking\/tool activity, usage, and the
-- stop reason on stderr.
module Lavoisier.CLI
  ( runCli,
    mainWith,
    Options (..),
    optionsParser,
    applyConfig,
    layerPersona,

    -- * Custom-tool extension point (re-exported for downstream @mainWith@ crates)
    Tool (..),
    ToolOutput,
    ToolError (..),
    toolOk,
    toolErr,
    setChanged,

    -- * Operator logging (re-exported so downstream tools instrument themselves)
    LogLevel (..),
    logError,
    logWarn,
    logInfo,
    logDebug,
  )
where

import Control.Concurrent.Async (mapConcurrently)
import Control.Exception (SomeException, try)
import Control.Monad (when)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Time.Clock.POSIX (getPOSIXTime)
import Data.Version (showVersion)
import Data.Word (Word32, Word64)
import Lavoisier.Agent
import Lavoisier.Config (FileConfig (..), loadConfig)
import Lavoisier.Gateway.A2A (a2aGateway, defaultA2aConfig)
import Lavoisier.Gateway.Acp (acpGateway)
import Lavoisier.Gateway.Cron (CronJob, cronGateway, loadFileJobs, parseCliJob)
import Lavoisier.Gateway.Http (GatewayConfig (..), httpGateway)
import Lavoisier.Gateway.Matrix (matrixFromEnv, matrixGateway)
import Lavoisier.Gateway.Matrix qualified as MX
import Lavoisier.Gateway.Slack (slackFromEnv, slackGateway)
import Lavoisier.Gateway.Tui (TuiConfig (..), defaultTuiConfig, tuiGateway)
import Lavoisier.Gateway.Tui.Gate (newChannelGate)
import Lavoisier.Legion (Debater, languageFromLocale, mkDebater, newPanel, panelDeliberator, renderLegionError, withLanguage)
import Lavoisier.Log (LogLevel (..), fileLogSink, logDebug, logError, logInfo, logWarn, nullLogSink, parseLogLevel, setLogLevel, setLogSink)
import Lavoisier.Mcp (connectTools, mssLabel, parseServerSpec, renderMcpError)
import Lavoisier.Memory (newFileStore, newInMemoryStore, sessionAgentHandle)
import Lavoisier.Protocol.Agent (turnRequest)
import Lavoisier.Protocol.Deliberate (Deliberator)
import Lavoisier.Protocol.Event
import Lavoisier.Protocol.Gateway (Gateway (..))
import Lavoisier.Protocol.Message
import Lavoisier.Protocol.Provider (Provider (..), ProviderError)
import Lavoisier.Protocol.Stream (Producer (..))
import Lavoisier.Protocol.Tool (Tool (..), ToolError (..), ToolOutput, setChanged, toolErr, toolOk)
import Lavoisier.Protocol.Tune (Tuner, noopTuner)
import Lavoisier.Provider.Anthropic (anthropicFromEnv, newAnthropicConfig)
import Lavoisier.Provider.Anthropic.Batch (anthropicBatch)
import Lavoisier.Provider.ClaudeCli (claudeCliFromEnv)
import Lavoisier.Provider.Google (googleFromEnv, newGoogleConfig)
import Lavoisier.Provider.Google.Batch (googleBatch)
import Lavoisier.Provider.Xai (xaiFromEnv)
import Lavoisier.Provider.Xai.Grpc (defaultXaiGrpcEndpoint, xaiGrpcProvider)
import Lavoisier.Schedule (ScheduleRegistry, loadScheduleFile, newRegistry, scheduleTools)
import Lavoisier.Tool.Batch (batchEditTool)
import Lavoisier.Tool.Registry (ToolRegistry, invokeTool, registerTools, withBuiltins)
import Lavoisier.Tune (LearningTuner, asTuner, defaultTuneConfig, learningTuner, loadTuner, saveTuner)
import Lavoisier.Tune.Bayes (BayesTuner, asBayesTuner, bayesTuner, loadBayes, saveBayes)
import Options.Applicative
import Paths_lavoisier (version)
import System.Directory (doesFileExist)
import System.Environment (lookupEnv)
import System.Exit (exitFailure)
import System.IO (hFlush, hSetEncoding, stderr, stdout, utf8)

-- | Parsed command-line options.
data Options = Options
  { optAgent :: Bool,
    optProvider :: Maybe String,
    optModel :: Maybe Text,
    optThinking :: Maybe ThinkingLevel,
    optMaxTokens :: Maybe Word32,
    optMaxSteps :: Maybe Int,
    optContextLimit :: Maybe Int,
    optCheapModel :: Maybe Text,
    optEscalateAfter :: Maybe Int,
    optAdvisorModel :: Maybe Text,
    optBudget :: Maybe Word64,
    optNoProgressLimit :: Maybe Int,
    optVerifyCmd :: Maybe Text,
    optRequireEdit :: Bool,
    optVerifyAndFix :: Bool,
    optInLoopVerify :: Bool,
    optSummaryModel :: Maybe Text,
    optPersona :: Maybe FilePath,
    optNoPersona :: Bool,
    optSystem :: Maybe Text,
    optBudgetAwareness :: Bool,
    optClassifyWithModel :: Bool,
    optNoBatchEdit :: Bool,
    optApiKey :: [Text],
    optRateLimit :: Maybe Int,
    optServe :: Maybe Int,
    optServeA2a :: Maybe Int,
    optAcp :: Bool,
    optTui :: Bool,
    optTuiAutoApprove :: Bool,
    optServeSlack :: Bool,
    optServeMatrix :: Bool,
    -- | Per-room\/per-member Matrix tool permissions. Config-file only (they are nested maps);
    -- empty ⇒ unconstrained, which is why the file has to be able to set them.
    optMatrixRoomTools :: Map Text [Text],
    optMatrixUserTools :: Map Text [Text],
    optSessionDir :: Maybe FilePath,
    optConfig :: Maybe FilePath,
    optMcpServers :: [String],
    optTune :: Bool,
    optTuneBayes :: Bool,
    optTuneState :: Maybe FilePath,
    optLegionDebaters :: [String],
    optLegionJudge :: Maybe String,
    optLegionRounds :: Maybe Int,
    optLang :: Maybe String,
    optCron :: [String],
    optCronFile :: Maybe FilePath,
    optCronRetryMax :: Maybe Int,
    optCronRetryWait :: Maybe Int,
    optScheduleFile :: Maybe FilePath,
    optScheduleRetryMax :: Maybe Int,
    optScheduleRetryWait :: Maybe Int,
    optFallback :: [String],
    optFallbackCooldown :: Maybe Int,
    optLogLevel :: Maybe String,
    optWords :: [String]
  }

optionsParser :: Parser Options
optionsParser =
  Options
    <$> switch (long "agent" <> help "Run the plan->act->observe tool loop instead of a single ask")
    <*> optional (strOption (long "provider" <> metavar "PROVIDER" <> help "Model provider (anthropic|google|xai|xai-grpc|claude-cli; default anthropic)"))
    <*> optional (strOption (long "model" <> metavar "MODEL" <> help "Model id"))
    <*> optional (option thinkingReader (long "thinking" <> metavar "LEVEL" <> help "off|low|medium|high"))
    <*> optional (option auto (long "max-tokens" <> metavar "N" <> help "Generated-token ceiling"))
    <*> optional (option auto (long "max-steps" <> metavar "N" <> help "Agent tool-loop step budget"))
    <*> optional (option auto (long "context-limit" <> metavar "N" <> help "Per-request token ceiling; evict oldest tool output when exceeded after compaction"))
    <*> optional (strOption (long "cheap-model" <> metavar "MODEL" <> help "Cheaper model for the first --escalate-after round-trips, then escalate to --model"))
    <*> optional (option auto (long "escalate-after" <> metavar "N" <> help "Round-trips on --cheap-model before escalating (default 2)"))
    <*> optional (strOption (long "advisor-model" <> metavar "MODEL" <> help "Smarter model for a one-shot planning pre-pass that seeds the executor"))
    <*> optional (option auto (long "budget" <> metavar "N" <> help "Whole-task cost-weighted token budget; the turn stops when exceeded"))
    <*> optional (option auto (long "no-progress-limit" <> metavar "N" <> help "Hard-stop after 2N edit-free round-trips (nudge at N)"))
    <*> optional (strOption (long "verify-cmd" <> metavar "CMD" <> help "Shell command that verifies the task (exit 0 = pass); drives the ATO success signal and verify levers"))
    <*> switch (long "require-edit" <> help "Nudge a finish that edited nothing to actually edit (bounded)")
    <*> switch (long "verify-and-fix" <> help "On a would-be finish, if --verify-cmd fails, feed the output back and keep working (bounded)")
    <*> switch (long "in-loop-verify" <> help "Stop as soon as an edit turn makes --verify-cmd pass")
    <*> optional (strOption (long "summary-model" <> metavar "MODEL" <> help "Cheaper model for history-compaction summaries (defaults to --model)"))
    <*> optional (strOption (long "persona" <> metavar "PATH" <> help "Persona/standing-instructions file layered above the operating instructions (default ./PERSONA.md if present)"))
    <*> switch (long "no-persona" <> help "Don't auto-load ./PERSONA.md (an explicit --persona still loads)")
    <*> optional (strOption (long "system" <> metavar "PROMPT" <> help "Replace the built-in operating instructions (the persona still layers above whatever this leaves)"))
    <*> switch (long "budget-awareness" <> help "Append a progress/token note to each turn so the model sees the ceilings")
    <*> switch (long "classify-with-model" <> help "Classify the task archetype with a model call instead of the keyword heuristic")
    <*> switch (long "no-batch-edit" <> help "Don't offer the batch_edit fan-out tool (only offered with a batch-capable provider)")
    <*> many (strOption (long "api-key" <> metavar "KEY" <> help "Bearer API key gating the HTTP gateway's /v1/turns (repeatable); empty = open"))
    <*> optional (option auto (long "rate-limit" <> metavar "N" <> help "HTTP gateway per-key request cap over a 60s window"))
    <*> optional (option auto (long "serve" <> metavar "PORT" <> help "Serve the agent as an HTTP gateway on this port instead of a one-shot turn"))
    <*> optional (option auto (long "serve-a2a" <> metavar "PORT" <> help "Serve the agent as an A2A (Agent-to-Agent) gateway on this port"))
    <*> switch (long "acp" <> help "Run as a Zed Agent Client Protocol (ACP) agent over stdio (JSON-RPC 2.0), so an ACP-capable editor can launch `lav --acp` as a subprocess and drive the full tool loop from its agent panel. Takes over stdin/stdout; no bind address. For agent-to-agent interop use --serve-a2a instead.")
    <*> switch (long "tui" <> help "Launch the interactive inline terminal UI - a scrollback-native REPL that drives the agent with streaming output, tool-call cards, and Claude-Code-style tool-approval prompts. Takes over the terminal (logs go to $LVZ_LOG_FILE, or are suppressed, so they cannot corrupt the display).")
    <*> switch (long "tui-auto-approve" <> help "With --tui, skip the tool-approval prompts and run every tool unattended (the default is Claude-Code-style: read-only tools run, mutating tools and shells ask first).")
    <*> switch (long "serve-slack" <> help "Serve the agent as a Slack gateway over Socket Mode (needs SLACK_APP_TOKEN + SLACK_BOT_TOKEN)")
    <*> switch (long "serve-matrix" <> help "Serve the agent as a Matrix gateway (needs MATRIX_HOMESERVER + MATRIX_USER + token/password)")
    -- matrixRoomTools / matrixUserTools: config-file only (nested maps), so no flag — see applyConfig.
    <*> pure Map.empty
    <*> pure Map.empty
    <*> optional (strOption (long "session-dir" <> metavar "DIR" <> help "Persist gateway session transcripts under DIR (durable file store; default in-memory)"))
    <*> optional (strOption (long "config" <> metavar "PATH" <> help "Dhall config file (default ./lavoisier.dhall if present)"))
    <*> many (strOption (long "mcp-server" <> metavar "LABEL:TARGET" <> help "Connect to an MCP server and expose its tools (stdio command or http(s):// URL); repeatable"))
    <*> switch (long "tune" <> help "Enable the ATO learner (ε-greedy knob tuning); off ⇒ static baseline knobs")
    <*> switch (long "tune-bayes" <> help "Use the Bayesian (Thompson-sampling) ATO learner instead of ε-greedy")
    <*> optional (strOption (long "tune-state" <> metavar "PATH" <> help "Load/persist learned ATO profiles at PATH (implies --tune; saved after an --agent turn)"))
    <*> many (strOption (long "legion-debater" <> metavar "PROVIDER:MODEL" <> help "Add a legion council debater (repeatable; ≥2 enables the council pre-pass)"))
    <*> optional (strOption (long "legion-judge" <> metavar "PROVIDER:MODEL" <> help "The legion judge that synthesises the verdict (default: the first debater)"))
    <*> optional (option auto (long "legion-rounds" <> metavar "N" <> help "Number of critique rounds after the draft (default 1)"))
    <*> optional (strOption (long "lang" <> metavar "LOCALE" <> help "Locale for council progress notices (only ko_KR selects Korean; default English/LANG)"))
    <*> many (strOption (long "cron" <> metavar "SPEC" <> help "A cron job: 5 schedule fields then a prompt (repeatable), e.g. '*/30 9-17 * * 1-5 check CI'"))
    <*> optional (strOption (long "cron-file" <> metavar "PATH" <> help "A Dhall file of cron jobs: a list of {schedule,session,prompt,retryMax,retryWait}"))
    <*> optional (option auto (long "cron-retry-max" <> metavar "N" <> help "Global default retries after a failed cron fire (default 0)"))
    <*> optional (option auto (long "cron-retry-wait" <> metavar "SECS" <> help "Global default seconds between cron retries (default 0)"))
    <*> optional (strOption (long "schedule-file" <> metavar "PATH" <> help "A Dhall file of Matrix schedule jobs: jobs fire inside --serve-matrix and report to a room"))
    <*> optional (option auto (long "schedule-retry-max" <> metavar "N" <> help "Global default retries after a failed schedule fire (default 0)"))
    <*> optional (option auto (long "schedule-retry-wait" <> metavar "SECS" <> help "Global default seconds between schedule retries (default 0)"))
    <*> many (strOption (long "fallback" <> metavar "PROVIDER:MODEL" <> help "A fallback model (repeatable, ordered): rerouted to when the primary is unresponsive/errors before streaming any output"))
    <*> optional (option auto (long "fallback-cooldown" <> metavar "SECS" <> help "Seconds a failed fallback-chain model stays demoted before it's re-probed (circuit breaker; default 60)"))
    <*> optional (strOption (long "log-level" <> metavar "FILTER" <> help "Operator-log threshold: error|warn|info|debug (also LVZ_LOG_LEVEL; default info)"))
    <*> many (argument str (metavar "PROMPT..."))

thinkingReader :: ReadM ThinkingLevel
thinkingReader = maybeReader $ \s -> case s of
  "off" -> Just ThinkOff
  "low" -> Just ThinkLow
  "medium" -> Just ThinkMedium
  "high" -> Just ThinkHigh
  _ -> Nothing

-- | Parse arguments and run the requested mode with no extra tools ('mainWith' @[]@).
runCli :: IO ()
runCli = mainWith []

-- | The custom-tool extension point (the Haskell analogue of Rust @lavoisier::main_with@): the whole
-- CLI\/gateway stack, but with @extra@ tools registered alongside the built-ins wherever tools are
-- used (every gateway, and @--agent@). A downstream crate depends on @lavoisier@, implements 'Tool',
-- and calls @mainWith [myTool, …]@ from its @main@. Extra tools do not apply to a one-shot @ask@
-- (which uses no tools), matching the Rust behaviour.
mainWith :: [Tool] -> IO ()
mainWith extra = do
  -- Force UTF-8 on the product streams so non-ASCII output (the ε in the --tune help, the 🔧/👀
  -- gateway markers, Korean notices) never hits `commitBuffer: invalid argument` under a C locale.
  hSetEncoding stdout utf8
  hSetEncoding stderr utf8
  opts0 <- execParser pinfo
  opts <- mergeConfig opts0
  -- Operator-log threshold: --log-level > LVZ_LOG_LEVEL > default info.
  levelRaw <- maybe (lookupEnv "LVZ_LOG_LEVEL") (pure . Just) (optLogLevel opts)
  maybe (pure ()) (setLogLevel . parseLogLevel . T.pack) levelRaw
  -- The inline TUI owns the terminal: stderr writes would corrupt its viewport, so route logs to
  -- \$LVZ_LOG_FILE when set, else drop them. Every other frontend keeps stderr as usual.
  when (optTui opts) $ do
    mpath <- lookupEnv "LVZ_LOG_FILE"
    msink <- maybe (pure Nothing) fileLogSink mpath
    setLogSink (fromMaybe nullLogSink msink)
  eprov <- selectProvider (fromMaybe "anthropic" (optProvider opts))
  case eprov of
    Left e -> errExit e
    Right (prov, defModel) -> do
      let model = fromMaybe defModel (optModel opts)
      -- Build the in-gateway schedule (if --schedule-file) first: its schedule_* tools go into the
      -- same registry the executor gets, so "how's the disk job?" works in every frontend.
      msched <- buildScheduleReg opts
      withRegistryExtra opts model (extra <> maybe [] scheduleTools msched) $ \registry -> do
        gws <- buildGateways opts msched registry
        if null gws
          then do
            prompt <- resolvePrompt (optWords opts)
            if T.null prompt
              then errExit "empty prompt (pass it as arguments or on stdin)"
              else
                if optAgent opts
                  then runAgentMode prov opts model prompt registry
                  else runAskMode prov opts model prompt
          else serveGateways gws prov opts model registry
  where
    -- `--version` is an infoOption, not an Options field: the parser is positional-applicative, so
    -- adding a field here would mean threading it through the record and every call site for a flag
    -- that only prints and exits.
    versionOption =
      infoOption
        ("lav " <> showVersion version)
        (long "version" <> help "Show the version and exit")

    pinfo =
      info
        (optionsParser <**> versionOption <**> helper)
        ( fullDesc
            <> progDesc "Token-efficient CLI coding agent (Haskell port): ask, --agent, or --serve*; Anthropic + Google + xAI + claude-cli."
            <> header "lav - lavoisier"
        )

-- | Resolve the config file (explicit @--config@, else @./lavoisier.dhall@ if present), load it,
-- and fill any option the user left unset (CLI/env wins over the file, which wins over defaults).
mergeConfig :: Options -> IO Options
mergeConfig opts = do
  path <- case optConfig opts of
    Just p -> pure (Just p)
    Nothing -> do
      here <- doesFileExist "lavoisier.dhall"
      pure (if here then Just "lavoisier.dhall" else Nothing)
  case path of
    Nothing -> pure opts
    Just p -> do
      r <- try (loadConfig p) :: IO (Either SomeException FileConfig)
      case r of
        Left e -> errExit ("config " <> T.pack p <> ": " <> T.pack (show e))
        Right fc -> pure (applyConfig fc opts)

-- | Fill each unset 'Options' field from the config (CLI value wins via '<|>').
applyConfig :: FileConfig -> Options -> Options
applyConfig fc o =
  o
    { optProvider = optProvider o <|> fmap T.unpack (provider fc),
      optModel = optModel o <|> model fc,
      optThinking = optThinking o <|> (thinking fc >>= parseThinking),
      optMaxTokens = optMaxTokens o <|> fmap fromIntegral (maxTokens fc),
      optMaxSteps = optMaxSteps o <|> fmap fromIntegral (maxSteps fc),
      optContextLimit = optContextLimit o <|> fmap fromIntegral (contextLimit fc),
      optCheapModel = optCheapModel o <|> cheapModel fc,
      optEscalateAfter = optEscalateAfter o <|> fmap fromIntegral (escalateAfter fc),
      optAdvisorModel = optAdvisorModel o <|> advisorModel fc,
      optBudget = optBudget o <|> fmap fromIntegral (budget fc),
      optNoProgressLimit = optNoProgressLimit o <|> fmap fromIntegral (noProgressLimit fc),
      optVerifyCmd = optVerifyCmd o <|> verifyCmd fc,
      optRequireEdit = optRequireEdit o || fromMaybe False (requireEdit fc),
      optVerifyAndFix = optVerifyAndFix o || fromMaybe False (verifyAndFix fc),
      optInLoopVerify = optInLoopVerify o || fromMaybe False (inLoopVerify fc),
      optSummaryModel = optSummaryModel o <|> summaryModel fc,
      optPersona = optPersona o <|> fmap T.unpack (persona fc),
      optSystem = optSystem o <|> system fc,
      optBudgetAwareness = optBudgetAwareness o || fromMaybe False (budgetAwareness fc),
      optServe = optServe o <|> fmap fromIntegral (serve fc),
      optServeA2a = optServeA2a o <|> fmap fromIntegral (serveA2a fc),
      optAcp = optAcp o || fromMaybe False (acp fc),
      optTui = optTui o || fromMaybe False (tui fc),
      optTuiAutoApprove = optTuiAutoApprove o || fromMaybe False (tuiAutoApprove fc),
      optServeSlack = optServeSlack o || fromMaybe False (serveSlack fc),
      optServeMatrix = optServeMatrix o || fromMaybe False (serveMatrix fc),
      -- No flag sets these, so the file is the only source: take it as-is.
      optMatrixRoomTools = fromMaybe Map.empty (matrixRoomTools fc),
      optMatrixUserTools = fromMaybe Map.empty (matrixUserTools fc),
      optSessionDir = optSessionDir o <|> fmap T.unpack (sessionDir fc),
      -- A CLI --mcp-server (non-empty) wins wholesale; otherwise take the file's list.
      optMcpServers = case optMcpServers o of
        [] -> maybe [] (map T.unpack) (mcpServers fc)
        given -> given,
      -- --tune is a flag (default False); the file can turn it on when the flag was absent.
      optTune = optTune o || fromMaybe False (tune fc),
      optTuneBayes = optTuneBayes o || fromMaybe False (tuneBayes fc),
      optTuneState = optTuneState o <|> fmap T.unpack (tuneState fc),
      optLegionDebaters = case optLegionDebaters o of
        [] -> maybe [] (map T.unpack) (legionDebaters fc)
        given -> given,
      optLegionJudge = optLegionJudge o <|> fmap T.unpack (legionJudge fc),
      optLegionRounds = optLegionRounds o <|> fmap fromIntegral (legionRounds fc),
      optLang = optLang o <|> fmap T.unpack (lang fc),
      optCron = case optCron o of
        [] -> maybe [] (map T.unpack) (cron fc)
        given -> given,
      optCronFile = optCronFile o <|> fmap T.unpack (cronFile fc),
      optCronRetryMax = optCronRetryMax o <|> fmap fromIntegral (cronRetryMax fc),
      optCronRetryWait = optCronRetryWait o <|> fmap fromIntegral (cronRetryWait fc),
      optScheduleRetryMax = optScheduleRetryMax o <|> fmap fromIntegral (scheduleRetryMax fc),
      optScheduleRetryWait = optScheduleRetryWait o <|> fmap fromIntegral (scheduleRetryWait fc),
      optFallback = case optFallback o of
        [] -> maybe [] (map T.unpack) (fallback fc)
        given -> given,
      optFallbackCooldown = optFallbackCooldown o <|> fmap fromIntegral (fallbackCooldown fc)
    }

parseThinking :: Text -> Maybe ThinkingLevel
parseThinking = \case
  "off" -> Just ThinkOff
  "low" -> Just ThinkLow
  "medium" -> Just ThinkMedium
  "high" -> Just ThinkHigh
  _ -> Nothing

-- | Build the requested provider and its default model, or an error message.
selectProvider :: String -> IO (Either Text (Provider, Text))
selectProvider name = case name of
  "anthropic" -> tag "claude-sonnet-4-5" <$> anthropicFromEnv
  "google" -> tag "gemini-2.5-flash" <$> googleFromEnv
  "xai" -> tag "grok-4" <$> xaiFromEnv
  "xai-grpc" -> do
    mkey <- lookupEnv "XAI_API_KEY"
    pure $ case mkey of
      Just k | not (null k) -> Right (xaiGrpcProvider (T.pack k) defaultXaiGrpcEndpoint, "grok-4")
      _ -> Left "XAI_API_KEY is not set"
  "claude-cli" -> tag "sonnet" <$> claudeCliFromEnv
  other -> pure (Left ("unsupported provider: " <> T.pack other <> " (anthropic|google|xai|xai-grpc|claude-cli)"))
  where
    tag def = either (Left . tshow) (\p -> Right (p, def))

resolvePrompt :: [String] -> IO Text
resolvePrompt [] = T.strip <$> TIO.getContents
resolvePrompt ws = pure (T.strip (T.pack (unwords ws)))

runAskMode :: Provider -> Options -> Text -> Text -> IO ()
runAskMode prov opts model prompt = do
  let req =
        (chatRequest model)
          { crMessages = [userMessage prompt],
            crMaxTokens = fromMaybe 2048 (optMaxTokens opts),
            crThinking = optThinking opts
          }
  estream <- providerStream prov req
  case estream of
    Left e -> errExit (tshow e)
    Right stream -> renderStream stream

-- | Build the tool registry the agent will use: the built-ins plus any @--mcp-server@'s tools
-- (namespaced @\<label\>_\<tool\>@), then hand it to the continuation. Connecting only happens for
-- tool-using modes (@--agent@ or a gateway) — a plain @ask@ spawns nothing. A bad spec or a dead
-- server fails fast with the offending label.
-- | Build the tool registry (MCP + batch_edit + built-ins) plus any @extra@ tools registered after
-- the built-ins (the caller's 'mainWith' tools, and\/or the @schedule_*@ tools), and run the
-- continuation with it.
withRegistryExtra :: Options -> Text -> [Tool] -> (ToolRegistry -> IO ()) -> IO ()
withRegistryExtra opts model extra k = do
  toolss <- mapM connectOne (optMcpServers opts)
  batch <- batchEditTools opts model
  k (registerTools (concat toolss <> batch <> extra) withBuiltins)

-- | Build the Matrix in-gateway schedule registry from @--schedule-file@ (a Dhall job list), arming
-- each job's first cron slot; 'Nothing' when no schedule file is set. A bad file fails fast.
buildScheduleReg :: Options -> IO (Maybe ScheduleRegistry)
buildScheduleReg opts = case optScheduleFile opts of
  Nothing -> pure Nothing
  Just path -> do
    let rmax = fromMaybe 0 (optScheduleRetryMax opts)
        rwait = fromMaybe 0 (optScheduleRetryWait opts)
    ejobs <- loadScheduleFile path rmax (fromIntegral rwait)
    case ejobs of
      Left e -> errExit ("schedule: " <> tshow e)
      Right jobs -> do
        now <- round <$> getPOSIXTime
        Just <$> newRegistry now jobs

-- | Offer @batch_edit@ when the provider has a discounted batch API (Anthropic today) and it wasn't
-- disabled. A missing key just omits the tool.
batchEditTools :: Options -> Text -> IO [Tool]
batchEditTools opts model
  | optNoBatchEdit opts = pure []
  | provider == "anthropic" = do
      mkey <- lookupEnv "ANTHROPIC_API_KEY"
      case mkey of
        Just key -> do
          base <- maybe "https://api.anthropic.com" T.pack <$> lookupEnv "ANTHROPIC_BASE_URL"
          cfg <- newAnthropicConfig (T.pack key) base
          pure [batchEditTool model (anthropicBatch cfg)]
        Nothing -> pure []
  | provider == "google" = do
      mkey <- lookupEnv "GOOGLE_API_KEY"
      case mkey of
        Just key -> do
          base <- maybe "https://generativelanguage.googleapis.com" T.pack <$> lookupEnv "GOOGLE_BASE_URL"
          cfg <- newGoogleConfig (T.pack key) base
          pure [batchEditTool model (googleBatch cfg)]
        Nothing -> pure []
  | otherwise = pure []
  where
    provider = fromMaybe "anthropic" (optProvider opts)

-- | Connect one @label:target@ MCP server, failing fast with the offending label.
connectOne :: String -> IO [Tool]
connectOne raw = case parseServerSpec (T.pack raw) of
  Left e -> errExit ("mcp: " <> renderMcpError e)
  Right spec -> do
    r <- connectTools spec
    case r of
      Left e -> errExit ("mcp '" <> mssLabel spec <> "': " <> renderMcpError e)
      Right ts -> pure ts

-- | Build the ATO tuner: 'noopTuner' unless @--tune@\/@--tune-bayes@, else a learner — Bayesian
-- (Thompson) when @--tune-bayes@, else ε-greedy — loaded from @--tune-state@ when present (a missing
-- file loads cold). Returns the tuner plus a persist action (a no-op without @--tune-state@) the
-- caller runs when a turn completes.
buildTuner :: Options -> IO (Tuner, IO ())
buildTuner opts
  | optTuneBayes opts = case optTuneState opts of
      Nothing -> do t <- bayesTuner defaultTuneConfig; pure (t, pure ())
      Just path -> do
        r <- loadBayes path defaultTuneConfig
        case r of
          Left e -> errExit ("tune-state " <> T.pack path <> ": " <> T.pack e)
          Right (bt :: BayesTuner) -> pure (asBayesTuner bt, saveBayes bt path)
  | not (optTune opts) = pure (noopTuner, pure ())
  | otherwise = case optTuneState opts of
      Nothing -> do t <- learningTuner defaultTuneConfig; pure (t, pure ())
      Just path -> do
        r <- loadTuner path defaultTuneConfig
        case r of
          Left e -> errExit ("tune-state " <> T.pack path <> ": " <> T.pack e)
          Right (lt :: LearningTuner) -> pure (asTuner lt, saveTuner lt path)

-- | Build the legion council: 'Nothing' unless ≥2 @--legion-debater@s are given (a one-model council
-- is just the advisor pre-pass), else a 'Deliberator' 'Panel'. Each debater\/judge spec is
-- @provider:model@, its provider built from env via 'selectProvider'; a bad spec\/too-few debaters
-- fails fast. The judge defaults to the first debater. Progress notices localize via @--lang@\/@LANG@.
buildLegion :: Options -> IO (Maybe Deliberator)
buildLegion opts
  | null (optLegionDebaters opts) = pure Nothing
  | otherwise = do
      debs <- mapM buildDebater (optLegionDebaters opts)
      judge <- case (optLegionJudge opts, debs) of
        (Just js, _) -> buildDebater js
        (Nothing, d : _) -> pure d
        (Nothing, []) -> errExit "legion: no debaters configured"
      langRaw <- maybe (fmap (fromMaybe "") (lookupEnv "LANG")) pure (optLang opts)
      let lg = languageFromLocale (T.pack langRaw)
      case newPanel debs judge (fromMaybe 1 (optLegionRounds opts)) of
        Left e -> errExit ("legion: " <> renderLegionError e)
        Right panel -> pure (Just (panelDeliberator (withLanguage lg panel)))

-- | True when any @--cron@\/@--cron-file@ jobs are configured (selects the cron serve mode).
cronActive :: Options -> Bool
cronActive opts = not (null (optCron opts)) || isJust (optCronFile opts)

-- | Build the cron jobs from @--cron@ specs and a @--cron-file@, applying the global retry defaults;
-- a bad spec\/schedule\/file fails fast.
buildCronJobs :: Options -> IO [CronJob]
buildCronJobs opts = do
  let rmax = fromMaybe 0 (optCronRetryMax opts)
      rwait = fromMaybe 0 (optCronRetryWait opts)
  cliJobs <-
    mapM
      (\(i, spec) -> either (errExit . cronErr) pure (parseCliJob (T.pack spec) i rmax rwait))
      (zip [0 ..] (optCron opts))
  fileJobs <- case optCronFile opts of
    Nothing -> pure []
    Just path -> loadFileJobs path rmax rwait >>= either (errExit . cronErr) pure
  pure (cliJobs <> fileJobs)
  where
    cronErr e = "cron: " <> tshow e

-- | Build one council debater from a @provider:model@ spec, its provider from env.
buildDebater :: String -> IO Debater
buildDebater spec = case break (== ':') spec of
  (_, "") -> errExit ("legion: bad debater spec (want provider:model): " <> T.pack spec)
  (provName, _ : modelPart)
    | null modelPart -> errExit ("legion: empty model in spec: " <> T.pack spec)
    | otherwise -> do
        ep <- selectProvider provName
        case ep of
          Left e -> errExit ("legion: " <> e)
          Right (p, _def) -> pure (mkDebater (T.pack spec) p (T.pack modelPart) Nothing)

-- | Build the ordered @--fallback provider:model@ chain, each provider built fresh from env via
-- 'selectProvider'; a bad spec or missing key fails fast with the offending spec.
buildFallbacks :: Options -> IO [(Provider, Text)]
buildFallbacks opts = mapM one (optFallback opts)
  where
    one spec = case break (== ':') spec of
      (_, "") -> errExit ("fallback: bad spec (want provider:model): " <> T.pack spec)
      (provName, _ : modelPart)
        | null modelPart -> errExit ("fallback: empty model in spec: " <> T.pack spec)
        | otherwise -> do
            ep <- selectProvider provName
            case ep of
              Left e -> errExit ("fallback " <> T.pack spec <> ": " <> e)
              Right (p, _def) -> pure (p, T.pack modelPart)

-- | Assemble the shared 'Agent': base config + tuner + legion council, then install the fallback
-- chain (and its cross-turn circuit breaker) if @--fallback@ was given.
assembleAgent :: Provider -> Options -> Text -> Tuner -> Maybe Deliberator -> ToolRegistry -> IO Agent
assembleAgent prov opts model tuner delib registry = do
  sys <- systemPromptFor opts
  let base = defaultAgentConfig model
      cfg =
        base
          { acSystem = sys,
            acThinking = optThinking opts,
            acMaxTokens = fromMaybe (acMaxTokens base) (optMaxTokens opts),
            acMaxSteps = fromMaybe (acMaxSteps base) (optMaxSteps opts),
            acContextLimit = optContextLimit opts,
            acCheapModel = optCheapModel opts,
            acEscalateAfter = fromMaybe (acEscalateAfter base) (optEscalateAfter opts),
            acAdvisorModel = optAdvisorModel opts,
            acTokenBudget = optBudget opts,
            acNoProgressLimit = optNoProgressLimit opts,
            acVerifyCommand = optVerifyCmd opts,
            acRequireEdit = optRequireEdit opts,
            acVerifyAndFix = optVerifyAndFix opts,
            acInLoopVerify = optInLoopVerify opts,
            acSummaryModel = optSummaryModel opts,
            acBudgetAwareness = optBudgetAwareness opts,
            acClassifyWithModel = optClassifyWithModel opts
          }
  agent0 <- mkAgent prov registry cfg tuner delib
  fallbacks <- buildFallbacks opts
  if null fallbacks
    then pure agent0
    else withFallbacks fallbacks (fromIntegral (fromMaybe 60 (optFallbackCooldown opts))) agent0

-- | The agent's system prompt: the operating instructions (@--system@, else the built-in default)
-- with the persona layered __above__ them, mirroring the Rust @lvz-cli@ composition. The persona
-- sits in the cached prefix, so carrying it costs almost nothing per turn.
systemPromptFor :: Options -> IO (Maybe Text)
systemPromptFor opts = do
  mpersona <- loadPersona opts
  pure (layerPersona mpersona (optSystem opts))

-- | Layer a persona /above/ the operating instructions: 'Nothing' persona leaves the prompt alone,
-- otherwise the persona is prepended to @--system@ (or to 'defaultSystemPrompt' when unset). Note it
-- __appends to__ rather than replaces the operating instructions, which the tool loop depends on.
layerPersona :: Maybe Text -> Maybe Text -> Maybe Text
layerPersona Nothing msystem = msystem
layerPersona (Just p) msystem =
  Just (p <> "\n\n--- (operating instructions follow) ---\n\n" <> fromMaybe defaultSystemPrompt msystem)

-- | Read the persona file: an explicit @--persona PATH@, else @.\/PERSONA.md@ when present (unless
-- @--no-persona@). An unreadable\/empty file yields 'Nothing'; only an explicitly requested one warns,
-- so the default path stays silent when absent.
loadPersona :: Options -> IO (Maybe Text)
loadPersona opts = case (optPersona opts, optNoPersona opts) of
  (Just p, _) -> readIt True p
  (Nothing, True) -> pure Nothing
  (Nothing, False) -> do
    here <- doesFileExist "PERSONA.md"
    if here then readIt False "PERSONA.md" else pure Nothing
  where
    readIt explicit path = do
      r <- try (TIO.readFile path) :: IO (Either SomeException Text)
      case r of
        Right raw | not (T.null (T.strip raw)) -> do
          logInfo "persona" ("loaded persona from " <> T.pack path)
          pure (Just (T.strip raw))
        Right _ -> pure Nothing
        Left e -> do
          when explicit $ logWarn "persona" ("could not read --persona " <> T.pack path <> ": " <> tshow e)
          pure Nothing

-- | Every gateway the flags asked for. An empty list means no serving mode was requested, so the CLI
-- falls back to a one-shot @ask@\/@--agent@ turn. They all run concurrently over one shared agent
-- (see 'serveGateways'), so @--serve-matrix --serve --cron-file …@ composes rather than picking one.
buildGateways :: Options -> Maybe ScheduleRegistry -> ToolRegistry -> IO [Gateway]
buildGateways opts msched registry = do
  cron <- if cronActive opts then (\jobs -> [cronGateway jobs]) <$> buildCronJobs opts else pure []
  matrix <- if optServeMatrix opts then pure <$> matrixGw else pure []
  slack <- if optServeSlack opts then pure <$> fromEnv slackFromEnv slackGateway else pure []
  pure $
    concat
      [ cron,
        matrix,
        slack,
        [acpGateway | optAcp opts],
        -- The TUI is built here for ordering, but its approval gate must reach the *agent*, so
        -- 'serveGateways' rebuilds it with the gate's receiver once the agent exists.
        [tuiGateway defaultTuiConfig | optTui opts],
        maybe [] (\p -> [a2aGateway p defaultA2aConfig]) (optServeA2a opts),
        maybe [] (\p -> [httpGateway p (GatewayConfig (optApiKey opts) (fmap (\n -> (fromIntegral n, 60)) (optRateLimit opts)))]) (optServe opts)
      ]
  where
    fromEnv build wrap = build >>= either (errExit . tshow) (pure . wrap)
    matrixGw = do
      -- Localise the gateway-authored shutdown notice via --lang/LANG (only ko_KR ⇒ Korean).
      langRaw <- maybe (fmap (fromMaybe "") (lookupEnv "LANG")) pure (optLang opts)
      let lg = MX.languageFromLocale (T.pack langRaw)
      ecfg <- matrixFromEnv
      case ecfg of
        Left e -> errExit (tshow e)
        Right cfg0 -> do
          let cfg =
                (MX.withLanguage lg cfg0)
                  { MX.mcRoomTools = optMatrixRoomTools opts,
                    MX.mcUserTools = optMatrixUserTools opts
                  }
              -- Hand the gateway a direct invoker into the registry the executor also uses, so a
              -- scheduled tool action fires deterministically with no model round-trip.
              mctx = fmap (\reg -> MX.ScheduleCtx reg (\n a -> invokeTool n a registry)) msched
          pure (maybe (matrixGateway cfg) (MX.matrixScheduleGateway cfg) mctx)

-- | Serve every requested 'Gateway' __concurrently over one shared agent__, wrapped with a session
-- store (durable if @--session-dir@). The first to fail takes the process down with its error; a
-- clean return from all of them ends the run.
--
-- The interactive TUI is the one gateway that needs something installed on the agent — its
-- tool-approval 'ToolGate' — so the gate is built here (unless @--tui-auto-approve@ waives it) and
-- its receiver handed to the TUI's config.
serveGateways :: [Gateway] -> Provider -> Options -> Text -> ToolRegistry -> IO ()
serveGateways gws prov opts model registry = do
  (tuner, _persist) <- buildTuner opts
  delib <- buildLegion opts
  agent0 <- assembleAgent prov opts model tuner delib registry
  (agent, permits) <-
    if optTui opts && not (optTuiAutoApprove opts)
      then do
        (gate, ps) <- newChannelGate
        pure (withToolGate gate agent0, Just ps)
      else pure (agent0, Nothing)
  store <- maybe (newInMemoryStore (Just 200)) (`newFileStore` Just 200) (optSessionDir opts)
  let handle = sessionAgentHandle store agent
      wired gw
        | gatewayName gw == "tui" = tuiGateway defaultTuiConfig {tuiSession = "tui", tuiModel = model, tuiPermits = permits}
        | otherwise = gw
  mapM_ (\gw -> logInfo "gateway" (gatewayName gw <> " starting")) gws
  results <- mapConcurrently (\gw -> gatewayServe (wired gw) handle) gws
  case [e | Left e <- results] of
    (e : _) -> errExit (tshow e)
    [] -> pure ()

runAgentMode :: Provider -> Options -> Text -> Text -> ToolRegistry -> IO ()
runAgentMode prov opts model prompt registry = do
  (tuner, persist) <- buildTuner opts
  delib <- buildLegion opts
  agent <- assembleAgent prov opts model tuner delib registry
  res <- runAgent agent (turnRequest "cli" prompt) renderEvent
  persist -- snapshot learned ATO profiles when --tune-state is set (a no-op otherwise)
  case res of
    Left e -> errExit (tshow e)
    Right () -> TIO.putStrLn ""

renderStream :: Producer (Either ProviderError Event) -> IO ()
renderStream p = loop
  where
    loop =
      nextItem p >>= \case
        Nothing -> pure ()
        Just (Left e) -> errExit (tshow e)
        Just (Right ev) -> renderEvent ev >> loop

-- | The streamed interface (product output, not logging): answer on stdout, everything else stderr.
renderEvent :: Event -> IO ()
renderEvent = \case
  TextDelta t -> TIO.putStr t >> hFlush stdout
  Thinking _ -> pure ()
  ToolUseStart _ name -> herr ("[tool] " <> name)
  ToolUseDelta {} -> pure ()
  ToolUseEnd _ -> pure ()
  ServerToolUse _ name -> herr ("[server tool] " <> name)
  ServerToolResult {} -> pure ()
  Citation _ src -> herr ("[citation] " <> src)
  Usage u ->
    herr $
      "[usage] in="
        <> tshow (inputTokens u)
        <> " out="
        <> tshow (outputTokens u)
        <> " cache_read="
        <> tshow (cacheReadTokens u)
  Notice t -> herr ("[notice] " <> t)
  Done sr -> TIO.putStrLn "" >> herr ("[done] " <> tshow sr)

herr :: Text -> IO ()
herr = TIO.hPutStrLn stderr

errExit :: Text -> IO a
errExit msg = TIO.hPutStrLn stderr ("error: " <> msg) >> exitFailure

tshow :: (Show a) => a -> Text
tshow = T.pack . show
