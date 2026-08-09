-- | The command-line entry point, ported (core subset) from Rust @lvz-cli@. Two modes over the same
-- plumbing: a one-shot @ask@ (no tools) and the @--agent@ tool loop. Only the Anthropic provider is
-- ported so far; @--provider@ rejects the rest with a clear message.
--
-- Rendering mirrors the Rust CLI: answer text on stdout; thinking\/tool activity, usage, and the
-- stop reason on stderr.
module Lavoisier.CLI
  ( runCli,
    Options (..),
    optionsParser,
  )
where

import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Word (Word32)
import Lavoisier.Agent
import Lavoisier.Gateway.A2A (a2aGateway, defaultA2aConfig)
import Lavoisier.Gateway.Http (defaultGatewayConfig, httpGateway)
import Lavoisier.Memory (newFileStore, newInMemoryStore, sessionAgentHandle)
import Lavoisier.Protocol.Agent (turnRequest)
import Lavoisier.Protocol.Event
import Lavoisier.Protocol.Gateway (Gateway (..))
import Lavoisier.Protocol.Message
import Lavoisier.Protocol.Provider (Provider (..), ProviderError)
import Lavoisier.Protocol.Stream (Producer (..))
import Lavoisier.Provider.Anthropic (anthropicFromEnv)
import Lavoisier.Tool.Registry (withBuiltins)
import Options.Applicative
import System.Exit (exitFailure)
import System.IO (hFlush, stderr, stdout)

-- | Parsed command-line options.
data Options = Options
  { optAgent :: Bool,
    optProvider :: String,
    optModel :: Maybe Text,
    optThinking :: Maybe ThinkingLevel,
    optMaxTokens :: Maybe Word32,
    optServe :: Maybe Int,
    optServeA2a :: Maybe Int,
    optSessionDir :: Maybe FilePath,
    optWords :: [String]
  }

optionsParser :: Parser Options
optionsParser =
  Options
    <$> switch (long "agent" <> help "Run the plan->act->observe tool loop instead of a single ask")
    <*> strOption
      ( long "provider"
          <> value "anthropic"
          <> showDefault
          <> metavar "PROVIDER"
          <> help "Model provider (only 'anthropic' is ported so far)"
      )
    <*> optional (strOption (long "model" <> metavar "MODEL" <> help "Model id"))
    <*> optional (option thinkingReader (long "thinking" <> metavar "LEVEL" <> help "off|low|medium|high"))
    <*> optional (option auto (long "max-tokens" <> metavar "N" <> help "Generated-token ceiling"))
    <*> optional (option auto (long "serve" <> metavar "PORT" <> help "Serve the agent as an HTTP gateway on this port instead of a one-shot turn"))
    <*> optional (option auto (long "serve-a2a" <> metavar "PORT" <> help "Serve the agent as an A2A (Agent-to-Agent) gateway on this port"))
    <*> optional (strOption (long "session-dir" <> metavar "DIR" <> help "Persist gateway session transcripts under DIR (durable file store; default in-memory)"))
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
  opts <- execParser pinfo
  if optProvider opts /= "anthropic"
    then errExit ("unsupported provider: " <> T.pack (optProvider opts) <> " (only 'anthropic' is ported so far)")
    else do
      eprov <- anthropicFromEnv
      case eprov of
        Left e -> errExit (tshow e)
        Right prov -> do
          let model = fromMaybe "claude-sonnet-4-5" (optModel opts)
          case (optServeA2a opts, optServe opts) of
            (Just port, _) -> serveGateway (a2aGateway port defaultA2aConfig) prov opts model
            (_, Just port) -> serveGateway (httpGateway port defaultGatewayConfig) prov opts model
            _ -> do
              prompt <- resolvePrompt (optWords opts)
              if T.null prompt
                then errExit "empty prompt (pass it as arguments or on stdin)"
                else
                  if optAgent opts
                    then runAgentMode prov opts model prompt
                    else runAskMode prov opts model prompt
  where
    pinfo =
      info
        (optionsParser <**> helper)
        ( fullDesc
            <> progDesc "Token-efficient CLI coding agent (Haskell port): ask or --agent, Anthropic."
            <> header "lav - lavoisier"
        )

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

-- | Serve the agent through any 'Gateway', wrapped with a session store (durable if --session-dir).
serveGateway :: Gateway -> Provider -> Options -> Text -> IO ()
serveGateway gw prov opts model = do
  let base = defaultAgentConfig model
      cfg = base {acThinking = optThinking opts, acMaxTokens = fromMaybe (acMaxTokens base) (optMaxTokens opts)}
      agent = Agent prov withBuiltins cfg
  store <- maybe (newInMemoryStore (Just 200)) (`newFileStore` Just 200) (optSessionDir opts)
  herr ("gateway '" <> gatewayName gw <> "' starting")
  res <- gatewayServe gw (sessionAgentHandle store agent)
  case res of
    Left e -> errExit (tshow e)
    Right () -> pure ()

runAgentMode :: Provider -> Options -> Text -> Text -> IO ()
runAgentMode prov opts model prompt = do
  let base = defaultAgentConfig model
      cfg =
        base
          { acThinking = optThinking opts,
            acMaxTokens = fromMaybe (acMaxTokens base) (optMaxTokens opts)
          }
      agent = Agent prov withBuiltins cfg
  res <- runAgent agent (turnRequest "cli" prompt) renderEvent
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
