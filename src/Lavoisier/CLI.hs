-- | The command-line entry point, ported (core subset) from Rust @lvz-cli@. Two modes over the same
-- plumbing: a one-shot @ask@ (no tools) and the @--agent@ tool loop. Providers: Anthropic + Google
-- (@--provider@); other providers reject with a clear message.
--
-- Rendering mirrors the Rust CLI: answer text on stdout; thinking\/tool activity, usage, and the
-- stop reason on stderr.
module Lavoisier.CLI
  ( runCli,
    Options (..),
    optionsParser,
  )
where

import Control.Exception (SomeException, try)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Word (Word32)
import Lavoisier.Agent
import Lavoisier.Config (FileConfig (..), loadConfig)
import Lavoisier.Gateway.A2A (a2aGateway, defaultA2aConfig)
import Lavoisier.Gateway.Acp (acpGateway, defaultAcpConfig)
import Lavoisier.Gateway.Http (defaultGatewayConfig, httpGateway)
import Lavoisier.Mcp (connectTools, mssLabel, parseServerSpec, renderMcpError)
import Lavoisier.Memory (newFileStore, newInMemoryStore, sessionAgentHandle)
import Lavoisier.Protocol.Agent (turnRequest)
import Lavoisier.Protocol.Event
import Lavoisier.Protocol.Gateway (Gateway (..))
import Lavoisier.Protocol.Message
import Lavoisier.Protocol.Provider (Provider (..), ProviderError)
import Lavoisier.Protocol.Stream (Producer (..))
import Lavoisier.Protocol.Tune (Tuner, noopTuner)
import Lavoisier.Tune (LearningTuner, asTuner, defaultTuneConfig, learningTuner, loadTuner, saveTuner)
import Lavoisier.Provider.Anthropic (anthropicFromEnv)
import Lavoisier.Provider.Google (googleFromEnv)
import Lavoisier.Tool.Registry (ToolRegistry, registerTools, withBuiltins)
import Options.Applicative
import System.Directory (doesFileExist)
import System.Exit (exitFailure)
import System.IO (hFlush, stderr, stdout)

-- | Parsed command-line options.
data Options = Options
  { optAgent :: Bool,
    optProvider :: Maybe String,
    optModel :: Maybe Text,
    optThinking :: Maybe ThinkingLevel,
    optMaxTokens :: Maybe Word32,
    optMaxSteps :: Maybe Int,
    optServe :: Maybe Int,
    optServeA2a :: Maybe Int,
    optServeAcp :: Maybe Int,
    optSessionDir :: Maybe FilePath,
    optConfig :: Maybe FilePath,
    optMcpServers :: [String],
    optTune :: Bool,
    optTuneState :: Maybe FilePath,
    optWords :: [String]
  }

optionsParser :: Parser Options
optionsParser =
  Options
    <$> switch (long "agent" <> help "Run the plan->act->observe tool loop instead of a single ask")
    <*> optional (strOption (long "provider" <> metavar "PROVIDER" <> help "Model provider (anthropic|google; default anthropic)"))
    <*> optional (strOption (long "model" <> metavar "MODEL" <> help "Model id"))
    <*> optional (option thinkingReader (long "thinking" <> metavar "LEVEL" <> help "off|low|medium|high"))
    <*> optional (option auto (long "max-tokens" <> metavar "N" <> help "Generated-token ceiling"))
    <*> optional (option auto (long "max-steps" <> metavar "N" <> help "Agent tool-loop step budget"))
    <*> optional (option auto (long "serve" <> metavar "PORT" <> help "Serve the agent as an HTTP gateway on this port instead of a one-shot turn"))
    <*> optional (option auto (long "serve-a2a" <> metavar "PORT" <> help "Serve the agent as an A2A (Agent-to-Agent) gateway on this port"))
    <*> optional (option auto (long "serve-acp" <> metavar "PORT" <> help "Serve the agent as an ACP (Agent Communication Protocol) gateway on this port"))
    <*> optional (strOption (long "session-dir" <> metavar "DIR" <> help "Persist gateway session transcripts under DIR (durable file store; default in-memory)"))
    <*> optional (strOption (long "config" <> metavar "PATH" <> help "Dhall config file (default ./lavoisier.dhall if present)"))
    <*> many (strOption (long "mcp-server" <> metavar "LABEL:TARGET" <> help "Connect to an MCP server and expose its tools (stdio command or http(s):// URL); repeatable"))
    <*> switch (long "tune" <> help "Enable the ATO learner (ε-greedy knob tuning); off ⇒ static baseline knobs")
    <*> optional (strOption (long "tune-state" <> metavar "PATH" <> help "Load/persist learned ATO profiles at PATH (implies --tune; saved after an --agent turn)"))
    <*> many (argument str (metavar "PROMPT..."))

thinkingReader :: ReadM ThinkingLevel
thinkingReader = maybeReader $ \s -> case s of
  "off" -> Just ThinkOff
  "low" -> Just ThinkLow
  "medium" -> Just ThinkMedium
  "high" -> Just ThinkHigh
  _ -> Nothing

-- | Parse arguments and run the requested mode.
runCli :: IO ()
runCli = do
  opts0 <- execParser pinfo
  opts <- mergeConfig opts0
  eprov <- selectProvider (fromMaybe "anthropic" (optProvider opts))
  case eprov of
    Left e -> errExit e
    Right (prov, defModel) -> do
      let model = fromMaybe defModel (optModel opts)
      case (optServeAcp opts, optServeA2a opts, optServe opts) of
        (Just port, _, _) -> withRegistry opts $ serveGateway (acpGateway port defaultAcpConfig) prov opts model
        (_, Just port, _) -> withRegistry opts $ serveGateway (a2aGateway port defaultA2aConfig) prov opts model
        (_, _, Just port) -> withRegistry opts $ serveGateway (httpGateway port defaultGatewayConfig) prov opts model
        _ -> do
          prompt <- resolvePrompt (optWords opts)
          if T.null prompt
            then errExit "empty prompt (pass it as arguments or on stdin)"
            else
              if optAgent opts
                then withRegistry opts (runAgentMode prov opts model prompt)
                else runAskMode prov opts model prompt
  where
    pinfo =
      info
        (optionsParser <**> helper)
        ( fullDesc
            <> progDesc "Token-efficient CLI coding agent (Haskell port): ask, --agent, or --serve*; Anthropic + Google."
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
      optServe = optServe o <|> fmap fromIntegral (serve fc),
      optServeA2a = optServeA2a o <|> fmap fromIntegral (serveA2a fc),
      optServeAcp = optServeAcp o <|> fmap fromIntegral (serveAcp fc),
      optSessionDir = optSessionDir o <|> fmap T.unpack (sessionDir fc),
      -- A CLI --mcp-server (non-empty) wins wholesale; otherwise take the file's list.
      optMcpServers = case optMcpServers o of
        [] -> maybe [] (map T.unpack) (mcpServers fc)
        given -> given,
      -- --tune is a flag (default False); the file can turn it on when the flag was absent.
      optTune = optTune o || fromMaybe False (tune fc),
      optTuneState = optTuneState o <|> fmap T.unpack (tuneState fc)
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
  other -> pure (Left ("unsupported provider: " <> T.pack other <> " (anthropic|google)"))
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
withRegistry :: Options -> (ToolRegistry -> IO ()) -> IO ()
withRegistry opts k = do
  toolss <- mapM connectOne (optMcpServers opts)
  k (registerTools (concat toolss) withBuiltins)
  where
    connectOne raw = case parseServerSpec (T.pack raw) of
      Left e -> errExit ("mcp: " <> renderMcpError e)
      Right spec -> do
        r <- connectTools spec
        case r of
          Left e -> errExit ("mcp '" <> mssLabel spec <> "': " <> renderMcpError e)
          Right ts -> pure ts

-- | Build the ATO tuner: 'noopTuner' unless @--tune@ (or @--tune-state@), else a learner — loaded
-- from @--tune-state@ when present (a missing file loads cold). Returns the tuner plus a persist
-- action (a no-op without @--tune-state@) the caller runs when a turn completes.
buildTuner :: Options -> IO (Tuner, IO ())
buildTuner opts
  | not (optTune opts) = pure (noopTuner, pure ())
  | otherwise = case optTuneState opts of
      Nothing -> do t <- learningTuner defaultTuneConfig; pure (t, pure ())
      Just path -> do
        r <- loadTuner path defaultTuneConfig
        case r of
          Left e -> errExit ("tune-state " <> T.pack path <> ": " <> T.pack e)
          Right (lt :: LearningTuner) -> pure (asTuner lt, saveTuner lt path)

-- | Serve the agent through any 'Gateway', wrapped with a session store (durable if --session-dir).
serveGateway :: Gateway -> Provider -> Options -> Text -> ToolRegistry -> IO ()
serveGateway gw prov opts model registry = do
  (tuner, _persist) <- buildTuner opts
  let base = defaultAgentConfig model
      cfg = base {acThinking = optThinking opts, acMaxTokens = fromMaybe (acMaxTokens base) (optMaxTokens opts), acMaxSteps = fromMaybe (acMaxSteps base) (optMaxSteps opts)}
      agent = Agent prov registry cfg tuner
  store <- maybe (newInMemoryStore (Just 200)) (`newFileStore` Just 200) (optSessionDir opts)
  herr ("gateway '" <> gatewayName gw <> "' starting")
  res <- gatewayServe gw (sessionAgentHandle store agent)
  case res of
    Left e -> errExit (tshow e)
    Right () -> pure ()

runAgentMode :: Provider -> Options -> Text -> Text -> ToolRegistry -> IO ()
runAgentMode prov opts model prompt registry = do
  (tuner, persist) <- buildTuner opts
  let base = defaultAgentConfig model
      cfg =
        base
          { acThinking = optThinking opts,
            acMaxTokens = fromMaybe (acMaxTokens base) (optMaxTokens opts),
            acMaxSteps = fromMaybe (acMaxSteps base) (optMaxSteps opts)
          }
      agent = Agent prov registry cfg tuner
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
