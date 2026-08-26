{- | The command-line entry point, ported (core subset) from Rust @lvz-cli@. Two modes over the same
plumbing: a one-shot @ask@ (no tools) and the @--agent@ tool loop. Providers: Anthropic + Google + xAI + claude-cli
(@--provider@); other providers reject with a clear message.

Rendering mirrors the Rust CLI: answer text on stdout; thinking\/tool activity, usage, and the
stop reason on stderr.
-}
module Lavoisier.CLI (
    runCli,
    mainWith,
    Options (..),
    optionsParser,
    applyConfig,
    Groups (grRouting, grVerify, grTuning, grTui, grLegion),
    resolveGroups,
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
import Data.Maybe (fromMaybe, isJust, isNothing)
import Data.Text (Text)
import Data.Time.Clock.POSIX (getPOSIXTime)
import Data.Version (showVersion)
import Data.Word (Word32, Word64)
import Options.Applicative
import System.Directory (doesFileExist)
import System.Environment (lookupEnv)
import System.Exit (exitFailure)
import System.IO (hFlush, hSetEncoding, stderr, stdout, utf8)

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.IO qualified as TIO

import Lavoisier.Agent
import Lavoisier.Config (FileConfig (..), loadConfig, loadCronFile, loadScheduleFile)
import Lavoisier.Domain
import Lavoisier.Gateway.A2A (a2aGateway, defaultA2aConfig)
import Lavoisier.Gateway.Acp (acpGateway)
import Lavoisier.Gateway.Cron (CronJob, cronGateway, jobFromSpec)
import Lavoisier.Gateway.Http (GatewayConfig (..), httpGateway)
import Lavoisier.Gateway.Matrix (matrixFromEnv, matrixGateway)
import Lavoisier.Gateway.Slack (slackFromEnv, slackGateway)
import Lavoisier.Gateway.Tui (TuiConfig (..), defaultTuiConfig, tuiGateway)
import Lavoisier.Gateway.Tui.Gate (newChannelGate)
import Lavoisier.Legion (Debater, mkDebater, newPanel, panelDeliberator, renderLegionError, withLanguage)
import Lavoisier.Log (LogLevel (..), fileLogSink, logDebug, logError, logInfo, logWarn, nullLogSink, parseLogLevel, setLogLevel, setLogSink)
import Lavoisier.Mcp (connectTools, mssLabel, renderMcpError, serverSpecOf)
import Lavoisier.Memory (newFileStore, newInMemoryStore, sessionAgentHandle)
import Lavoisier.Protocol.Agent (turnRequest)
import Lavoisier.Protocol.Deliberate (Deliberator)
import Lavoisier.Protocol.Event
import Lavoisier.Protocol.Gateway (Gateway (..))
import Lavoisier.Protocol.Message
import Lavoisier.Protocol.Provider (Provider (..), ProviderError, providerErrorText)
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
import Lavoisier.Provider.Xai.Responses (xaiResponsesFromEnv)
import Lavoisier.Schedule (ScheduleRegistry, jobsFromSpecs, newRegistry, scheduleTools)
import Lavoisier.Schedule.Cron (cronErrorText, parseCronExpr)
import Lavoisier.Tool.Batch (batchEditTool)
import Lavoisier.Tool.Registry (ToolRegistry, invokeTool, registerTools, withBuiltins)
import Lavoisier.Tune (LearningTuner, asTuner, defaultTuneConfig, learningTuner, loadTuner, saveTuner)
import Lavoisier.Tune.Bayes (BayesTuner, asBayesTuner, bayesTuner, loadBayes, saveBayes)
import Paths_lavoisier (version)

import Lavoisier.Gateway.Matrix qualified as MX

-- | Parsed command-line options.
data Options = Options
    { optAgent ∷ Bool
    , optProvider ∷ Maybe ProviderId
    , optModel ∷ Maybe ModelId
    , optThinking ∷ Maybe ThinkingLevel
    , optServerTools ∷ [ServerTool]
    {- ^ Provider-run tools to offer. Empty means none; a tool the chosen provider cannot run is
    refused by name before the request is sent.
    -}
    , optMaxTokens ∷ Maybe Word32
    , optMaxSteps ∷ Maybe Int
    , optContextLimit ∷ Maybe Int
    , optCheapModel ∷ Maybe ModelId
    , optEscalateAfter ∷ Maybe Int
    , optAdvisorModel ∷ Maybe ModelId
    , optBudget ∷ Maybe Word64
    , optNoProgressLimit ∷ Maybe Int
    , optVerifyCmd ∷ Maybe Text
    , optRequireEdit ∷ Bool
    , optVerifyAndFix ∷ Bool
    , optInLoopVerify ∷ Bool
    , optSummaryModel ∷ Maybe ModelId
    , optPersona ∷ Maybe FilePath
    , optNoPersona ∷ Bool
    , optSystem ∷ Maybe Text
    , optBudgetAwareness ∷ Bool
    , optClassifyWithModel ∷ Bool
    , optNoBatchEdit ∷ Bool
    , optApiKey ∷ [Text]
    , optRateLimit ∷ Maybe Int
    , optServe ∷ Maybe Port
    , optServeA2a ∷ Maybe Port
    , optAcp ∷ Bool
    , optTui ∷ Bool
    , optTuiAutoApprove ∷ Bool
    , optServeSlack ∷ Bool
    , optServeMatrix ∷ Bool
    , optMatrixRoomTools ∷ [ToolGrant RoomId]
    {- ^ Per-room\/per-member Matrix tool permissions. Config-file only (they are nested maps);
    empty ⇒ unconstrained, which is why the file has to be able to set them.
    -}
    , optMatrixUserTools ∷ [ToolGrant MatrixUserId]
    , optSessionDir ∷ Maybe FilePath
    , optConfig ∷ Maybe FilePath
    , optMcpServers ∷ [McpSpec]
    , optTune ∷ Bool
    , optTuneBayes ∷ Bool
    , optTuneState ∷ Maybe FilePath
    , optLegionDebaters ∷ [ModelRef]
    , optLegionJudge ∷ Maybe ModelRef
    , optLegionRounds ∷ Maybe Int
    , optLang ∷ Maybe Locale
    , optCron ∷ [CronJobSpec]
    , optCronFile ∷ Maybe FilePath
    , optCronRetryMax ∷ Maybe RetryCount
    , optCronRetryWait ∷ Maybe Seconds
    , optScheduleFile ∷ Maybe FilePath
    , optScheduleRetryMax ∷ Maybe RetryCount
    , optScheduleRetryWait ∷ Maybe Seconds
    , optFallback ∷ [ModelRef]
    , optFallbackCooldown ∷ Maybe Seconds
    , optLogLevel ∷ Maybe LogLevel
    , optWords ∷ [String]
    }

{- | The co-dependent flag groups, resolved once from the command line and the config file.

'Options' is the __surface__: a command line is flat, so its flags are, and the config file fills
each one individually — which is what lets a knob come from the file while its sibling comes from
the flag. This is the __result__: every group is either absent or complete. The combinations that
used to be accepted and then quietly dropped (a Bayesian learner with tuning "off", a judge with
no debaters, auto-approval without the TUI) are reported here instead.

The constructor is hidden so 'resolveGroups' is the only way to obtain one — the same
unforgeable-evidence idiom as the provider layer's @Negotiated@, for the same reason: a new
consumer cannot read a half-set group without going through the check.
-}
data Groups = Groups
    { grRouting ∷ Maybe Routing
    , grVerify ∷ Maybe VerifySpec
    , grTuning ∷ Maybe Tuning
    , grTui ∷ Maybe TuiSpec
    , grLegion ∷ Maybe LegionSpec
    }
    deriving stock (Eq, Show)

{- | Group the flat options, failing on a dependent knob whose parent is absent on __both__
surfaces. Two of them can be completed instead of refused, and are: a tune-state path implies the
learner that writes it (the flag's help always said so and the code never did), and
@--tui-auto-approve@ implies the TUI it approves for.
-}
resolveGroups ∷ Options → Either Text Groups
resolveGroups o = Groups <$> routing <*> verify <*> pure tuning <*> pure tui <*> legion
    where
        routing = case (optCheapModel o, optEscalateAfter o) of
            (Just m, esc) → Right (Just (Routing m esc))
            (Nothing, Just _) →
                Left "escalate-after: does nothing without a cheap model to escalate from (--cheap-model, or routing.cheapModel)"
            (Nothing, Nothing) → Right Nothing
        verify = case optVerifyCmd o of
            Just cmd → Right (Just (VerifySpec cmd (optVerifyAndFix o) (optInLoopVerify o)))
            Nothing
                | optVerifyAndFix o || optInLoopVerify o →
                    Left "verify-and-fix/in-loop-verify: do nothing without a verify command (--verify-cmd, or verify.command)"
                | otherwise → Right Nothing
        tuning
            | optTuneBayes o = Just (Tuning Bayes (optTuneState o))
            | optTune o || isJust (optTuneState o) = Just (Tuning Greedy (optTuneState o))
            | otherwise = Nothing
        tui
            | optTui o || optTuiAutoApprove o = Just (TuiSpec (optTuiAutoApprove o))
            | otherwise = Nothing
        legion
            | null (optLegionDebaters o) && isNothing (optLegionJudge o) && isNothing (optLegionRounds o) =
                Right Nothing
            | otherwise = Just <$> mkLegionSpec (optLegionDebaters o) (optLegionJudge o) (optLegionRounds o)

optionsParser ∷ Parser Options
optionsParser =
    Options
        <$> switch (long "agent" <> help "Run the plan->act->observe tool loop instead of a single ask")
        <*> optional (option providerReader (long "provider" <> metavar "PROVIDER" <> help ("Model provider (" <> providerIdList <> "; default anthropic)")))
        <*> optional (ModelId <$> strOption (long "model" <> metavar "MODEL" <> help "Model id"))
        <*> optional (option thinkingReader (long "thinking" <> metavar "LEVEL" <> help "off|low|medium|high"))
        <*> (concat <$> many (option serverToolsReader (long "server-tools" <> metavar "NAMES" <> help "Provider-run tools, comma-separated: web_search|web_fetch|code_execution|x_search|collections_search|url_context; repeatable")))
        <*> optional (option auto (long "max-tokens" <> metavar "N" <> help "Generated-token ceiling"))
        <*> optional (option auto (long "max-steps" <> metavar "N" <> help "Agent tool-loop step budget"))
        <*> optional (option auto (long "context-limit" <> metavar "N" <> help "Per-request token ceiling; evict oldest tool output when exceeded after compaction"))
        <*> optional (ModelId <$> strOption (long "cheap-model" <> metavar "MODEL" <> help "Cheaper model for the first --escalate-after round-trips, then escalate to --model"))
        <*> optional (option auto (long "escalate-after" <> metavar "N" <> help "Round-trips on --cheap-model before escalating (default 2); requires --cheap-model"))
        <*> optional (ModelId <$> strOption (long "advisor-model" <> metavar "MODEL" <> help "Smarter model for a one-shot planning pre-pass that seeds the executor"))
        <*> optional (option auto (long "budget" <> metavar "N" <> help "Whole-task cost-weighted token budget; the turn stops when exceeded"))
        <*> optional (option auto (long "no-progress-limit" <> metavar "N" <> help "Hard-stop after 2N edit-free round-trips (nudge at N)"))
        <*> optional (strOption (long "verify-cmd" <> metavar "CMD" <> help "Shell command that verifies the task (exit 0 = pass); drives the ATO success signal and verify levers"))
        <*> switch (long "require-edit" <> help "Nudge a finish that edited nothing to actually edit (bounded)")
        <*> switch (long "verify-and-fix" <> help "On a would-be finish, if --verify-cmd fails, feed the output back and keep working (bounded); requires --verify-cmd")
        <*> switch (long "in-loop-verify" <> help "Stop as soon as an edit turn makes --verify-cmd pass; requires --verify-cmd")
        <*> optional (ModelId <$> strOption (long "summary-model" <> metavar "MODEL" <> help "Cheaper model for history-compaction summaries (defaults to --model)"))
        <*> optional (strOption (long "persona" <> metavar "PATH" <> help "Persona/standing-instructions file layered above the operating instructions (default ./PERSONA.md if present)"))
        <*> switch (long "no-persona" <> help "Don't auto-load ./PERSONA.md (an explicit --persona still loads)")
        <*> optional (strOption (long "system" <> metavar "PROMPT" <> help "Replace the built-in operating instructions (the persona still layers above whatever this leaves)"))
        <*> switch (long "budget-awareness" <> help "Append a progress/token note to each turn so the model sees the ceilings")
        <*> switch (long "classify-with-model" <> help "Classify the task archetype with a model call instead of the keyword heuristic")
        <*> switch (long "no-batch-edit" <> help "Don't offer the batch_edit fan-out tool (only offered with a batch-capable provider)")
        <*> many (strOption (long "api-key" <> metavar "KEY" <> help "Bearer API key gating the HTTP gateway's /v1/turns (repeatable); empty = open"))
        <*> optional (option auto (long "rate-limit" <> metavar "N" <> help "HTTP gateway per-key request cap over a 60s window"))
        <*> optional (option portReader (long "serve" <> metavar "PORT" <> help "Serve the agent as an HTTP gateway on this port instead of a one-shot turn"))
        <*> optional (option portReader (long "serve-a2a" <> metavar "PORT" <> help "Serve the agent as an A2A (Agent-to-Agent) gateway on this port"))
        <*> switch (long "acp" <> help "Run as a Zed Agent Client Protocol (ACP) agent over stdio (JSON-RPC 2.0), so an ACP-capable editor can launch `lav --acp` as a subprocess and drive the full tool loop from its agent panel. Takes over stdin/stdout; no bind address. For agent-to-agent interop use --serve-a2a instead.")
        <*> switch (long "tui" <> help "Launch the interactive inline terminal UI - a scrollback-native REPL that drives the agent with streaming output, tool-call cards, and Claude-Code-style tool-approval prompts. Takes over the terminal (logs go to $LVZ_LOG_FILE, or are suppressed, so they cannot corrupt the display).")
        <*> switch (long "tui-auto-approve" <> help "Skip the tool-approval prompts (implies --tui) and run every tool unattended (the default is Claude-Code-style: read-only tools run, mutating tools and shells ask first).")
        <*> switch (long "serve-slack" <> help "Serve the agent as a Slack gateway over Socket Mode (needs SLACK_APP_TOKEN + SLACK_BOT_TOKEN)")
        <*> switch (long "serve-matrix" <> help "Serve the agent as a Matrix gateway (needs MATRIX_HOMESERVER + MATRIX_USER + token/password)")
        -- matrixRoomTools / matrixUserTools: config-file only (nested maps), so no flag — see applyConfig.
        <*> pure []
        <*> pure []
        <*> optional (strOption (long "session-dir" <> metavar "DIR" <> help "Persist gateway session transcripts under DIR (durable file store; default in-memory)"))
        <*> optional (strOption (long "config" <> metavar "PATH" <> help "Dhall config file (default ./lavoisier.dhall if present)"))
        <*> many (option mcpReader (long "mcp-server" <> metavar "LABEL:TARGET" <> help "Connect to an MCP server and expose its tools (stdio command or http(s):// URL); repeatable"))
        <*> switch (long "tune" <> help "Enable the ATO learner (ε-greedy knob tuning); off ⇒ static baseline knobs")
        <*> switch (long "tune-bayes" <> help "Use the Bayesian (Thompson-sampling) ATO learner instead of ε-greedy")
        <*> optional (strOption (long "tune-state" <> metavar "PATH" <> help "Load/persist learned ATO profiles at PATH (implies --tune; saved after an --agent turn)"))
        <*> many (option modelRefReader (long "legion-debater" <> metavar "PROVIDER:MODEL" <> help "Add a legion council debater (repeatable; ≥2 enables the council pre-pass)"))
        <*> optional (option modelRefReader (long "legion-judge" <> metavar "PROVIDER:MODEL" <> help "The legion judge that synthesises the verdict (default: the first debater)"))
        <*> optional (option auto (long "legion-rounds" <> metavar "N" <> help "Number of critique rounds after the draft (default 1)"))
        <*> optional (Locale <$> strOption (long "lang" <> metavar "LOCALE" <> help "Locale for council progress notices (only ko_KR selects Korean; default English/LANG)"))
        <*> many (option cronReader (long "cron" <> metavar "SPEC" <> help "A cron job: 5 schedule fields then a prompt (repeatable), e.g. '*/30 9-17 * * 1-5 check CI'"))
        <*> optional (strOption (long "cron-file" <> metavar "PATH" <> help "A Dhall file of cron jobs: a list of {schedule,session,prompt,retryMax,retryWait}"))
        <*> optional (option retryReader (long "cron-retry-max" <> metavar "N" <> help "Global default retries after a failed cron fire (default 0)"))
        <*> optional (option secondsReader (long "cron-retry-wait" <> metavar "SECS" <> help "Global default seconds between cron retries (default 0)"))
        <*> optional (strOption (long "schedule-file" <> metavar "PATH" <> help "A Dhall file of Matrix schedule jobs: jobs fire inside --serve-matrix and report to a room"))
        <*> optional (option retryReader (long "schedule-retry-max" <> metavar "N" <> help "Global default retries after a failed schedule fire (default 0)"))
        <*> optional (option secondsReader (long "schedule-retry-wait" <> metavar "SECS" <> help "Global default seconds between schedule retries (default 0)"))
        <*> many (option modelRefReader (long "fallback" <> metavar "PROVIDER:MODEL" <> help "A fallback model (repeatable, ordered): rerouted to when the primary is unresponsive/errors before streaming any output"))
        <*> optional (option secondsReader (long "fallback-cooldown" <> metavar "SECS" <> help "Seconds a failed fallback-chain model stays demoted before it's re-probed (circuit breaker; default 60)"))
        <*> optional (option logLevelReader (long "log-level" <> metavar "FILTER" <> help "Operator-log threshold: error|warn|info|debug (also LVZ_LOG_LEVEL; default info)"))
        <*> many (argument str (metavar "PROMPT..."))

{- | Every @option@ reader below turns a command-line string into a domain value at the edge, so
the rest of the program never sees the string form. A rejected value is an optparse error naming
the flag, which is the same failure mode the Dhall config now has.
-}
providerReader ∷ ReadM ProviderId
providerReader = maybeReader (parseProviderId . T.pack)

portReader ∷ ReadM Port
portReader = maybeReader (parsePort . T.pack)

logLevelReader ∷ ReadM LogLevel
logLevelReader = maybeReader $ \s → case s of
    "error" → Just LogError
    "warn" → Just LogWarn
    "info" → Just LogInfo
    "debug" → Just LogDebug
    _ → Nothing

modelRefReader ∷ ReadM ModelRef
modelRefReader = eitherReader (either (Left . T.unpack) Right . parseModelRef . T.pack)

mcpReader ∷ ReadM McpSpec
mcpReader = eitherReader (either (Left . T.unpack) Right . parseMcpSpec . T.pack)

retryReader ∷ ReadM RetryCount
retryReader = RetryCount <$> auto

secondsReader ∷ ReadM Seconds
secondsReader = Seconds <$> auto

{- | @--cron \'*/30 9-17 * * 1-5 check CI\'@: the five schedule fields, then the prompt. The config
file no longer packs these together ('CronExpr' names each field), but the flag keeps the
familiar crontab spelling, so the split happens here — once, at the edge.
-}
cronReader ∷ ReadM CronJobSpec
cronReader = eitherReader $ \raw →
    case T.words (T.pack raw) of
        (mi : h : dom : mo : dow : rest)
            | not (null rest) → do
                sched ←
                    either
                        (Left . T.unpack . cronErrorText)
                        Right
                        (parseCronExpr (T.unwords [mi, h, dom, mo, dow]))
                Right
                    CronJobSpec
                        { csSchedule = sched
                        , csPrompt = T.unwords rest
                        , csSession = Nothing
                        , csRetryMax = Nothing
                        , csRetryWait = Nothing
                        }
        _ → Left "expected 5 schedule fields then a prompt, e.g. '*/30 9-17 * * 1-5 check CI'"

{- | @--server-tools web_search,code_execution@. Names only: every parameterised tool takes its
defaults here, and the Dhall @serverTools@ list is where domain\/handle\/date filters are set.
Which names a given provider accepts differs; that is checked against the provider, not here, so
the error can name both the tool and the provider.
-}
serverToolsReader ∷ ReadM [ServerTool]
serverToolsReader = eitherReader $ \raw →
    traverse one [T.strip w | w ← T.splitOn "," (T.pack raw), not (T.null (T.strip w))]
    where
        one = \case
            "web_search" → Right (STWebSearch Nothing [] [])
            "web_fetch" → Right (STWebFetch Nothing)
            "code_execution" → Right STCodeExecution
            "x_search" → Right (STXSearch [] [] Nothing Nothing)
            "collections_search" → Right (STCollectionsSearch [] Nothing)
            "url_context" → Right STUrlContext
            other → Left ("unknown server tool: " <> T.unpack other <> " (expected web_search|web_fetch|code_execution|x_search|collections_search|url_context)")

thinkingReader ∷ ReadM ThinkingLevel
thinkingReader = maybeReader $ \s → case s of
    "off" → Just ThinkOff
    "low" → Just ThinkLow
    "medium" → Just ThinkMedium
    "high" → Just ThinkHigh
    _ → Nothing

-- | Parse arguments and run the requested mode with no extra tools ('mainWith' @[]@).
runCli ∷ IO ()
runCli = mainWith []

{- | The custom-tool extension point (the Haskell analogue of Rust @lavoisier::main_with@): the whole
CLI\/gateway stack, but with @extra@ tools registered alongside the built-ins wherever tools are
used (every gateway, and @--agent@). A downstream crate depends on @lavoisier@, implements 'Tool',
and calls @mainWith [myTool, …]@ from its @main@. Extra tools do not apply to a one-shot @ask@
(which uses no tools), matching the Rust behaviour.
-}
mainWith ∷ [Tool] → IO ()
mainWith extra = do
    -- Force UTF-8 on the product streams so non-ASCII output (the ε in the --tune help, the 🔧/👀
    -- gateway markers, Korean notices) never hits `commitBuffer: invalid argument` under a C locale.
    hSetEncoding stdout utf8
    hSetEncoding stderr utf8
    opts0 ← execParser pinfo
    opts ← mergeConfig opts0
    -- One place turns the flat flag surface into complete groups, and the only place that can
    -- report a knob whose parent is missing on both surfaces.
    groups ← either errExit pure (resolveGroups opts)
    -- Operator-log threshold: --log-level > LVZ_LOG_LEVEL > default info.
    -- --log-level is already a LogLevel (the reader rejected anything else); only the env var is
    -- still text, and parseLogLevel keeps its RUST_LOG-style tolerance for deployment filter strings.
    envLevel ← fmap (parseLogLevel . T.pack) <$> lookupEnv "LVZ_LOG_LEVEL"
    mapM_ setLogLevel (optLogLevel opts <|> envLevel)
    -- The inline TUI owns the terminal: stderr writes would corrupt its viewport, so route logs to
    -- \$LVZ_LOG_FILE when set, else drop them. Every other frontend keeps stderr as usual.
    when (isJust (grTui groups)) $ do
        mpath ← lookupEnv "LVZ_LOG_FILE"
        msink ← maybe (pure Nothing) fileLogSink mpath
        setLogSink (fromMaybe nullLogSink msink)
    eprov ← selectProvider (providerOf opts)
    case eprov of
        Left e → errExit e
        Right (prov, defModel) → do
            let model = fromMaybe defModel (optModel opts)
            -- Build the in-gateway schedule (if --schedule-file) first: its schedule_* tools go into the
            -- same registry the executor gets, so "how's the disk job?" works in every frontend.
            msched ← buildScheduleReg opts
            withRegistryExtra opts model (extra <> maybe [] scheduleTools msched) $ \registry → do
                gws ← buildGateways opts groups msched registry
                if null gws
                    then do
                        prompt ← resolvePrompt (optWords opts)
                        if T.null prompt
                            then errExit "empty prompt (pass it as arguments or on stdin)"
                            else
                                if optAgent opts
                                    then runAgentMode prov opts groups model prompt registry
                                    else runAskMode prov opts model prompt
                    else serveGateways gws prov opts groups model registry
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

{- | Resolve the config file (explicit @--config@, else @./lavoisier.dhall@ if present), load it,
and fill any option the user left unset (CLI/env wins over the file, which wins over defaults).
-}
mergeConfig ∷ Options → IO Options
mergeConfig opts = do
    path ← case optConfig opts of
        Just p → pure (Just p)
        Nothing → do
            here ← doesFileExist "lavoisier.dhall"
            pure (if here then Just "lavoisier.dhall" else Nothing)
    case path of
        Nothing → pure opts
        Just p → do
            r ← try (loadConfig p) ∷ IO (Either SomeException FileConfig)
            case r of
                Left e → errExit ("config " <> T.pack p <> ": " <> T.pack (show e))
                Right fc → pure (applyConfig fc opts)

-- | Fill each unset 'Options' field from the config (CLI value wins via '<|>').
applyConfig ∷ FileConfig → Options → Options
applyConfig fc o =
    o
        { optProvider = optProvider o <|> provider fc
        , optModel = optModel o <|> model fc
        , optThinking = optThinking o <|> thinking fc
        , -- A non-empty --server-tools wins wholesale; otherwise take the file's list.
          optServerTools = if null (optServerTools o) then fromMaybe [] (serverTools fc) else optServerTools o
        , optMaxTokens = optMaxTokens o <|> fmap fromIntegral (maxTokens fc)
        , optMaxSteps = optMaxSteps o <|> fmap fromIntegral (maxSteps fc)
        , optContextLimit = optContextLimit o <|> fmap fromIntegral (contextLimit fc)
        , -- The file states each group whole; the flags state its parts. Exploding the group
          -- here keeps the merge field-by-field, so --escalate-after still composes with a
          -- routing.cheapModel from the file. 'resolveGroups' regroups what survives.
          optCheapModel = optCheapModel o <|> (rtCheapModel <$> routing fc)
        , optEscalateAfter = optEscalateAfter o <|> (routing fc >>= rtEscalateAfter)
        , optAdvisorModel = optAdvisorModel o <|> advisorModel fc
        , optBudget = optBudget o <|> fmap fromIntegral (budget fc)
        , optNoProgressLimit = optNoProgressLimit o <|> fmap fromIntegral (noProgressLimit fc)
        , optVerifyCmd = optVerifyCmd o <|> (vsCommand <$> verify fc)
        , optRequireEdit = optRequireEdit o || fromMaybe False (requireEdit fc)
        , optVerifyAndFix = optVerifyAndFix o || maybe False vsAndFix (verify fc)
        , optInLoopVerify = optInLoopVerify o || maybe False vsInLoop (verify fc)
        , optSummaryModel = optSummaryModel o <|> summaryModel fc
        , optPersona = optPersona o <|> persona fc
        , optSystem = optSystem o <|> system fc
        , optBudgetAwareness = optBudgetAwareness o || fromMaybe False (budgetAwareness fc)
        , optServe = optServe o <|> serve fc
        , optServeA2a = optServeA2a o <|> serveA2a fc
        , optAcp = optAcp o || fromMaybe False (acp fc)
        , optTui = optTui o || isJust (tui fc)
        , optTuiAutoApprove = optTuiAutoApprove o || maybe False tsAutoApprove (tui fc)
        , optServeSlack = optServeSlack o || fromMaybe False (serveSlack fc)
        , optServeMatrix = optServeMatrix o || fromMaybe False (serveMatrix fc)
        , -- No flag sets these, so the file is the only source: take it as-is.
          optMatrixRoomTools = fromMaybe [] (matrixRoomTools fc)
        , optMatrixUserTools = fromMaybe [] (matrixUserTools fc)
        , optSessionDir = optSessionDir o <|> sessionDir fc
        , -- A CLI --mcp-server (non-empty) wins wholesale; otherwise take the file's list.
          optMcpServers = case optMcpServers o of
            [] → fromMaybe [] (mcpServers fc)
            given → given
        , -- --tune is a flag (default False); the file can turn it on when the flag was absent.
          optTune = optTune o || isJust (tune fc)
        , optTuneBayes = optTuneBayes o || ((tuStrategy <$> tune fc) == Just Bayes)
        , optTuneState = optTuneState o <|> (tune fc >>= tuState)
        , optLegionDebaters = case optLegionDebaters o of
            [] → maybe [] lgDebaters (legion fc)
            given → given
        , optLegionJudge = optLegionJudge o <|> (legion fc >>= lgJudge)
        , optLegionRounds = optLegionRounds o <|> (legion fc >>= lgRounds)
        , optLang = optLang o <|> fmap localeOfLanguage (lang fc)
        , optCron = case optCron o of
            [] → fromMaybe [] (cron fc)
            given → given
        , optCronFile = optCronFile o <|> cronFile fc
        , optCronRetryMax = optCronRetryMax o <|> cronRetryMax fc
        , optCronRetryWait = optCronRetryWait o <|> cronRetryWait fc
        , optScheduleRetryMax = optScheduleRetryMax o <|> scheduleRetryMax fc
        , optScheduleRetryWait = optScheduleRetryWait o <|> scheduleRetryWait fc
        , optFallback = case optFallback o of
            [] → fromMaybe [] (fallback fc)
            given → given
        , optFallbackCooldown = optFallbackCooldown o <|> fallbackCooldown fc
        , optScheduleFile = optScheduleFile o <|> scheduleFile fc
        , optLogLevel = optLogLevel o <|> logLevel fc
        }

{- | The config states a 'Language' directly; @--lang@ takes a POSIX locale. Round-trip the former
into the latter so the single downstream resolver ('languageFromLocale') stays the only place
that decides what a locale means.
-}
localeOfLanguage ∷ Language → Locale
localeOfLanguage = \case
    English → Locale "en_US"
    Korean → Locale "ko_KR"

{- | Collapse a grant list into the lookup map the Matrix gateway indexes by. A repeated subject
keeps the last grant, matching the config file reading top-to-bottom.
-}
grantMap ∷ Ord s ⇒ [ToolGrant s] → Map s [ToolName]
grantMap gs = Map.fromList [(tgSubject g, tgTools g) | g ← gs]

{- | The effective provider: the flag, else the config, else Anthropic. One definition, so no call
site can disagree about what the default is.
-}
providerOf ∷ Options → ProviderId
providerOf = fromMaybe Anthropic . optProvider

{- | Build the requested provider and its default model, or an error message.

This used to take a 'String' and match literals, with a second, independent literal match in
'batchEditTools' deciding which providers had a batch API. Nothing connected the two, so adding
a provider silently skipped the batch question. Both are now exhaustive 'ProviderId' cases.
-}
selectProvider ∷ ProviderId → IO (Either Text (Provider, ModelId))
selectProvider pid = case pid of
    Anthropic → tag <$> anthropicFromEnv
    Google → tag <$> googleFromEnv
    Xai → tag <$> xaiFromEnv
    XaiGrpc → do
        mkey ← lookupEnv "XAI_API_KEY"
        pure $ case mkey of
            Just k
                | not (null k) →
                    Right (xaiGrpcProvider (T.pack k) defaultXaiGrpcEndpoint, defaultModelFor pid)
            _ → Left "XAI_API_KEY is not set"
    XaiResponses → tag <$> xaiResponsesFromEnv
    ClaudeCli → tag <$> claudeCliFromEnv
    where
        tag = either (Left . tshow) (\p → Right (p, defaultModelFor pid))

resolvePrompt ∷ [String] → IO Text
resolvePrompt [] = T.strip <$> TIO.getContents
resolvePrompt ws = pure (T.strip (T.pack (unwords ws)))

runAskMode ∷ Provider → Options → ModelId → Text → IO ()
runAskMode prov opts model prompt = do
    let req =
            (chatRequest model)
                { crMessages = [userMessage prompt]
                , crMaxTokens = fromMaybe 2048 (optMaxTokens opts)
                , crThinking = optThinking opts
                , crServerTools = optServerTools opts
                }
    estream ← providerStream prov req
    case estream of
        Left e → errExit (providerErrorText e)
        Right stream → renderStream stream

{- | Build the tool registry the agent will use: the built-ins plus any @--mcp-server@'s tools
(namespaced @\<label\>_\<tool\>@), then hand it to the continuation. Connecting only happens for
tool-using modes (@--agent@ or a gateway) — a plain @ask@ spawns nothing. A bad spec or a dead
server fails fast with the offending label.
| Build the tool registry (MCP + batch_edit + built-ins) plus any @extra@ tools registered after
the built-ins (the caller's 'mainWith' tools, and\/or the @schedule_*@ tools), and run the
continuation with it.
-}
withRegistryExtra ∷ Options → ModelId → [Tool] → (ToolRegistry → IO ()) → IO ()
withRegistryExtra opts model extra k = do
    toolss ← mapM connectOne (optMcpServers opts)
    batch ← batchEditTools opts model
    k (registerTools (concat toolss <> batch <> extra) withBuiltins)

{- | Build the Matrix in-gateway schedule registry from @--schedule-file@ (a Dhall job list), arming
each job's first cron slot; 'Nothing' when no schedule file is set. A bad file fails fast.
-}
buildScheduleReg ∷ Options → IO (Maybe ScheduleRegistry)
buildScheduleReg opts = case optScheduleFile opts of
    Nothing → pure Nothing
    Just path → do
        let rmax = fromIntegral (unRetryCount (fromMaybe (RetryCount 0) (optScheduleRetryMax opts)))
            rwait = fromIntegral (unSeconds (fromMaybe (Seconds 0) (optScheduleRetryWait opts)))
        especs ← loadScheduleFile path
        specs ← either (errExit . ("schedule-file: " <>)) pure especs
        case jobsFromSpecs specs rmax rwait of
            Left e → errExit ("schedule: " <> tshow e)
            Right jobs → do
                now ← round <$> getPOSIXTime
                Just <$> newRegistry now jobs

{- | Offer @batch_edit@ when the provider has a discounted batch API (Anthropic today) and it wasn't
disabled. A missing key just omits the tool.
-}
batchEditTools ∷ Options → ModelId → IO [Tool]
batchEditTools opts model
    | optNoBatchEdit opts = pure []
    | otherwise = case providerOf opts of
        Anthropic → withKey "ANTHROPIC_API_KEY" "ANTHROPIC_BASE_URL" "https://api.anthropic.com" $
            \key base → do
                cfg ← newAnthropicConfig key base
                pure [batchEditTool model (anthropicBatch cfg)]
        Google →
            withKey "GOOGLE_API_KEY" "GOOGLE_BASE_URL" "https://generativelanguage.googleapis.com" $
                \key base → do
                    cfg ← newGoogleConfig key base
                    pure [batchEditTool model (googleBatch cfg)]
        -- Neither has a discounted batch API; a missing arm here is a compile error, not a silent no.
        Xai → pure []
        XaiGrpc → pure []
        XaiResponses → pure []
        ClaudeCli → pure []
    where
        withKey keyVar baseVar defBase k = do
            mkey ← lookupEnv keyVar
            case mkey of
                Nothing → pure []
                Just key → do
                    base ← maybe defBase T.pack <$> lookupEnv baseVar
                    k (T.pack key) base

-- | Connect one @label:target@ MCP server, failing fast with the offending label.
connectOne ∷ McpSpec → IO [Tool]
connectOne dspec = case serverSpecOf dspec of
    Left e → errExit ("mcp: " <> renderMcpError e)
    Right spec → do
        r ← connectTools spec
        case r of
            Left e → errExit ("mcp '" <> mssLabel spec <> "': " <> renderMcpError e)
            Right ts → pure ts

{- | Build the ATO tuner: 'noopTuner' when no 'Tuning' was configured, else the learner it names,
loaded from its state path when it has one (a missing file loads cold). Returns the tuner plus a
persist action (a no-op without a state path) the caller runs when a turn completes.

This used to test three independent flags in an order that decided the answer: @--tune-bayes@ was
checked before @--tune@, so tuning "off" still ran the Bayesian learner. A 'Tuning' cannot say
that, so the ordering stopped mattering.
-}
buildTuner ∷ Maybe Tuning → IO (Tuner, IO ())
buildTuner Nothing = pure (noopTuner, pure ())
buildTuner (Just (Tuning strategy mstate)) = case (strategy, mstate) of
    (Bayes, Nothing) → do t ← bayesTuner defaultTuneConfig; pure (t, pure ())
    (Bayes, Just path) → do
        r ← loadBayes path defaultTuneConfig
        case r of
            Left e → errExit ("tune-state " <> T.pack path <> ": " <> T.pack e)
            Right (bt ∷ BayesTuner) → pure (asBayesTuner bt, saveBayes bt path)
    (Greedy, Nothing) → do t ← learningTuner defaultTuneConfig; pure (t, pure ())
    (Greedy, Just path) → do
        r ← loadTuner path defaultTuneConfig
        case r of
            Left e → errExit ("tune-state " <> T.pack path <> ": " <> T.pack e)
            Right (lt ∷ LearningTuner) → pure (asTuner lt, saveTuner lt path)

{- | Build the legion council: 'Nothing' when none was configured, else a 'Deliberator' 'Panel'.
Each debater\/judge is a 'ModelRef' whose provider is built from env via 'selectProvider'; a
missing key fails fast. The judge defaults to the first debater. Progress notices localize via
@--lang@\/@LANG@.

The two-debater floor is 'mkLegionSpec'\'s, checked when the config loads, so 'newPanel' cannot
fail here — a 'LegionSpec' is already a council big enough to deliberate. The 'errExit' stays for
@mainWith@ callers who build a 'Lavoisier.Legion.Panel' by hand.
-}
buildLegion ∷ Options → Maybe LegionSpec → IO (Maybe Deliberator)
buildLegion _ Nothing = pure Nothing
buildLegion opts (Just spec) = do
    debs ← mapM buildDebater (lgDebaters spec)
    judge ← case (lgJudge spec, debs) of
        (Just js, _) → buildDebater js
        (Nothing, d : _) → pure d
        (Nothing, []) → errExit "legion: no debaters configured"
    lc ← maybe (Locale . maybe "" T.pack <$> lookupEnv "LANG") pure (optLang opts)
    let lg = languageFromLocale lc
    case newPanel debs judge (fromMaybe 1 (lgRounds spec)) of
        Left e → errExit ("legion: " <> renderLegionError e)
        Right panel → pure (Just (panelDeliberator (withLanguage lg panel)))

-- | True when any @--cron@\/@--cron-file@ jobs are configured (selects the cron serve mode).
cronActive ∷ Options → Bool
cronActive opts = not (null (optCron opts)) || isJust (optCronFile opts)

{- | Build the cron jobs from @--cron@ specs and a @--cron-file@, applying the global retry defaults;
a bad spec\/schedule\/file fails fast.
-}
buildCronJobs ∷ Options → IO [CronJob]
buildCronJobs opts = do
    let rmax = fromMaybe (RetryCount 0) (optCronRetryMax opts)
        rwait = fromMaybe (Seconds 0) (optCronRetryWait opts)
    let cliJobs = [jobFromSpec spec i rmax rwait | (i, spec) ← zip [0 ..] (optCron opts)]
    fileJobs ← case optCronFile opts of
        Nothing → pure []
        Just path →
            loadCronFile path
                >>= either
                    (errExit . ("cron-file: " <>))
                    (pure . map (\(i, spec) → jobFromSpec spec i rmax rwait) . zip [length (optCron opts) ..])
    pure (cliJobs <> fileJobs)

{- | Build one council debater from a @provider:model@ spec, its provider from env.
The @provider:model@ split is the option reader's job now; this had its own third copy of it.
-}
buildDebater ∷ ModelRef → IO Debater
buildDebater ref = do
    ep ← selectProvider (mrProvider ref)
    case ep of
        Left e → errExit ("legion: " <> e)
        Right (p, _def) → pure (mkDebater (renderModelRef ref) p (mrModel ref) Nothing)

{- | Build the ordered @--fallback provider:model@ chain, each provider built fresh from env via
'selectProvider'; a bad spec or missing key fails fast with the offending spec.
The @provider:model@ split happened in the option reader, so what is left is building each
provider from env. The old version re-implemented the split here, differently from the legion
council's copy of the same parse.
-}
buildFallbacks ∷ Options → IO [(Provider, ModelId)]
buildFallbacks opts = mapM one (optFallback opts)
    where
        one ref = do
            ep ← selectProvider (mrProvider ref)
            case ep of
                Left e → errExit ("fallback " <> renderModelRef ref <> ": " <> e)
                Right (p, _def) → pure (p, mrModel ref)

{- | Assemble the shared 'Agent': base config + tuner + legion council, then install the fallback
chain (and its cross-turn circuit breaker) if @--fallback@ was given.
-}
assembleAgent ∷ Provider → Options → Groups → ModelId → Tuner → Maybe Deliberator → ToolRegistry → IO Agent
assembleAgent prov opts groups model tuner delib registry = do
    sys ← systemPromptFor opts
    let base = defaultAgentConfig model
        cfg =
            base
                { acSystem = sys
                , acThinking = optThinking opts
                , acServerTools = optServerTools opts
                , acMaxTokens = fromMaybe (acMaxTokens base) (optMaxTokens opts)
                , acMaxSteps = fromMaybe (acMaxSteps base) (optMaxSteps opts)
                , acContextLimit = optContextLimit opts
                , acRouting = grRouting groups
                , acAdvisorModel = optAdvisorModel opts
                , acTokenBudget = optBudget opts
                , acNoProgressLimit = optNoProgressLimit opts
                , acVerify = grVerify groups
                , acRequireEdit = optRequireEdit opts
                , acSummaryModel = optSummaryModel opts
                , acBudgetAwareness = optBudgetAwareness opts
                , acClassifyWithModel = optClassifyWithModel opts
                }
    agent0 ← mkAgent prov registry cfg tuner delib
    fallbacks ← buildFallbacks opts
    if null fallbacks
        then pure agent0
        else withFallbacks fallbacks (fromIntegral (unSeconds (fromMaybe (Seconds 60) (optFallbackCooldown opts)))) agent0

{- | The agent's system prompt: the operating instructions (@--system@, else the built-in default)
with the persona layered __above__ them, mirroring the Rust @lvz-cli@ composition. The persona
sits in the cached prefix, so carrying it costs almost nothing per turn.
-}
systemPromptFor ∷ Options → IO (Maybe Text)
systemPromptFor opts = do
    mpersona ← loadPersona opts
    pure (layerPersona mpersona (optSystem opts))

{- | Layer a persona /above/ the operating instructions: 'Nothing' persona leaves the prompt alone,
otherwise the persona is prepended to @--system@ (or to 'defaultSystemPrompt' when unset). Note it
__appends to__ rather than replaces the operating instructions, which the tool loop depends on.
-}
layerPersona ∷ Maybe Text → Maybe Text → Maybe Text
layerPersona Nothing msystem = msystem
layerPersona (Just p) msystem =
    Just (p <> "\n\n--- (operating instructions follow) ---\n\n" <> fromMaybe defaultSystemPrompt msystem)

{- | Read the persona file: an explicit @--persona PATH@, else @.\/PERSONA.md@ when present (unless
@--no-persona@). An unreadable\/empty file yields 'Nothing'; only an explicitly requested one warns,
so the default path stays silent when absent.
-}
loadPersona ∷ Options → IO (Maybe Text)
loadPersona opts = case (optPersona opts, optNoPersona opts) of
    (Just p, _) → readIt True p
    (Nothing, True) → pure Nothing
    (Nothing, False) → do
        here ← doesFileExist "PERSONA.md"
        if here then readIt False "PERSONA.md" else pure Nothing
    where
        readIt explicit path = do
            r ← try (TIO.readFile path) ∷ IO (Either SomeException Text)
            case r of
                Right raw | not (T.null (T.strip raw)) → do
                    logInfo "persona" ("loaded persona from " <> T.pack path)
                    pure (Just (T.strip raw))
                Right _ → pure Nothing
                Left e → do
                    when explicit $ logWarn "persona" ("could not read --persona " <> T.pack path <> ": " <> tshow e)
                    pure Nothing

{- | Every gateway the flags asked for. An empty list means no serving mode was requested, so the CLI
falls back to a one-shot @ask@\/@--agent@ turn. They all run concurrently over one shared agent
(see 'serveGateways'), so @--serve-matrix --serve --cron-file …@ composes rather than picking one.
-}
buildGateways ∷ Options → Groups → Maybe ScheduleRegistry → ToolRegistry → IO [Gateway]
buildGateways opts groups msched registry = do
    cron ← if cronActive opts then (\jobs → [cronGateway jobs]) <$> buildCronJobs opts else pure []
    matrix ← if optServeMatrix opts then pure <$> matrixGw else pure []
    slack ← if optServeSlack opts then pure <$> fromEnv slackFromEnv slackGateway else pure []
    pure $
        concat
            [ cron
            , matrix
            , slack
            , [acpGateway | optAcp opts]
            , -- The TUI is built here for ordering, but its approval gate must reach the *agent*, so
              -- 'serveGateways' rebuilds it with the gate's receiver once the agent exists.
              [tuiGateway defaultTuiConfig | isJust (grTui groups)]
            , maybe [] (\p → [a2aGateway p defaultA2aConfig]) (optServeA2a opts)
            , maybe [] (\p → [httpGateway p (GatewayConfig (optApiKey opts) (fmap (\n → (fromIntegral n, 60)) (optRateLimit opts)))]) (optServe opts)
            ]
    where
        fromEnv build wrap = build >>= either (errExit . tshow) (pure . wrap)
        matrixGw = do
            -- Localise the gateway-authored shutdown notice via --lang/LANG (only ko_KR ⇒ Korean).
            lc ← maybe (Locale . maybe "" T.pack <$> lookupEnv "LANG") pure (optLang opts)
            let lg = languageFromLocale lc
            ecfg ← matrixFromEnv
            case ecfg of
                Left e → errExit (tshow e)
                Right cfg0 → do
                    let cfg =
                            (MX.withLanguage lg cfg0)
                                { MX.mcRoomTools = grantMap (optMatrixRoomTools opts)
                                , MX.mcUserTools = grantMap (optMatrixUserTools opts)
                                }
                        -- Hand the gateway a direct invoker into the registry the executor also uses, so a
                        -- scheduled tool action fires deterministically with no model round-trip.
                        mctx = fmap (\reg → MX.ScheduleCtx reg (\n a → invokeTool n a registry)) msched
                    pure (maybe (matrixGateway cfg) (MX.matrixScheduleGateway cfg) mctx)

{- | Serve every requested 'Gateway' __concurrently over one shared agent__, wrapped with a session
store (durable if @--session-dir@). The first to fail takes the process down with its error; a
clean return from all of them ends the run.

The interactive TUI is the one gateway that needs something installed on the agent — its
tool-approval 'ToolGate' — so the gate is built here (unless @--tui-auto-approve@ waives it) and
its receiver handed to the TUI's config.
-}
serveGateways ∷ [Gateway] → Provider → Options → Groups → ModelId → ToolRegistry → IO ()
serveGateways gws prov opts groups model registry = do
    (tuner, _persist) ← buildTuner (grTuning groups)
    delib ← buildLegion opts (grLegion groups)
    agent0 ← assembleAgent prov opts groups model tuner delib registry
    (agent, permits) ←
        if maybe False (not . tsAutoApprove) (grTui groups)
            then do
                (gate, ps) ← newChannelGate
                pure (withToolGate gate agent0, Just ps)
            else pure (agent0, Nothing)
    store ← maybe (newInMemoryStore (Just 200)) (`newFileStore` Just 200) (optSessionDir opts)
    let handle = sessionAgentHandle store agent
        wired gw
            | gatewayName gw == "tui" = tuiGateway defaultTuiConfig {tuiSession = "tui", tuiModel = model, tuiPermits = permits}
            | otherwise = gw
    mapM_ (\gw → logInfo "gateway" (gatewayName gw <> " starting")) gws
    results ← mapConcurrently (\gw → gatewayServe (wired gw) handle) gws
    case [e | Left e ← results] of
        (e : _) → errExit (tshow e)
        [] → pure ()

runAgentMode ∷ Provider → Options → Groups → ModelId → Text → ToolRegistry → IO ()
runAgentMode prov opts groups model prompt registry = do
    (tuner, persist) ← buildTuner (grTuning groups)
    delib ← buildLegion opts (grLegion groups)
    agent ← assembleAgent prov opts groups model tuner delib registry
    res ← runAgent agent (turnRequest "cli" prompt) renderEvent
    persist -- snapshot learned ATO profiles when a tune-state path is set (a no-op otherwise)
    case res of
        Left e → errExit (tshow e)
        Right () → TIO.putStrLn ""

renderStream ∷ Producer (Either ProviderError Event) → IO ()
renderStream p = loop
    where
        loop =
            nextItem p >>= \case
                Nothing → pure ()
                Just (Left e) → errExit (providerErrorText e)
                Just (Right ev) → renderEvent ev >> loop

-- | The streamed interface (product output, not logging): answer on stdout, everything else stderr.
renderEvent ∷ Event → IO ()
renderEvent = \case
    TextDelta t → TIO.putStr t >> hFlush stdout
    Thinking _ → pure ()
    ToolUseStart _ name → herr ("[tool] " <> name)
    ToolUseDelta {} → pure ()
    ToolUseEnd _ → pure ()
    ServerToolUse _ name → herr ("[server tool] " <> name)
    ServerToolResult {} → pure ()
    Citation _ src → herr ("[citation] " <> src)
    Usage u →
        herr $
            "[usage] in="
                <> tshow (inputTokens u)
                <> " out="
                <> tshow (outputTokens u)
                <> " cache_read="
                <> tshow (cacheReadTokens u)
    Notice t → herr ("[notice] " <> t)
    Done sr → TIO.putStrLn "" >> herr ("[done] " <> tshow sr)

herr ∷ Text → IO ()
herr = TIO.hPutStrLn stderr

errExit ∷ Text → IO a
errExit msg = TIO.hPutStrLn stderr ("error: " <> msg) >> exitFailure

tshow ∷ Show a ⇒ a → Text
tshow = T.pack . show
