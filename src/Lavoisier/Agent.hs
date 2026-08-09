-- | The plan→act→observe agent loop, ported (core subset) from Rust @lvz-agent@ @run_loop@.
--
-- Given a task it advertises the registry's 'ToolDef's (filtered by any @allowed_tools@), streams
-- the provider's 'Event's out through a callback, assembles streamed @tool_use@ calls, executes them
-- against the 'ToolRegistry', appends the assistant message + tool results, and iterates until the
-- model stops for a non-tool reason (or the step budget is hit).
--
-- 'runAgent' is the callback primitive (used by the CLI). 'agentHandle' adapts it to the
-- 'AgentHandle' record (the gateway contract) by streaming events through a 'Chan'-backed 'Producer'.
module Lavoisier.Agent
  ( AgentConfig (..),
    defaultAgentConfig,
    Agent (..),
    runAgent,
    agentHandle,
    defaultSystemPrompt,
  )
where

import Control.Concurrent (forkIO)
import Control.Concurrent.Chan
import Data.Aeson (Value (..), decodeStrict, object)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding (encodeUtf8)
import Data.Word (Word32)
import Lavoisier.Protocol.Agent
import Lavoisier.Protocol.Event (Event (..), StopReason (..))
import Lavoisier.Protocol.Message
import Lavoisier.Protocol.Provider (Provider (..), ProviderError)
import Lavoisier.Protocol.Stream (Producer (..))
import Lavoisier.Protocol.Tool (ToolOutput (..))
import Lavoisier.Tool.Registry

-- | The tool-loop configuration.
data AgentConfig = AgentConfig
  { acModel :: Text,
    acMaxSteps :: Int,
    acMaxTokens :: Word32,
    acThinking :: Maybe ThinkingLevel,
    -- | System prompt; 'Nothing' uses 'defaultSystemPrompt'.
    acSystem :: Maybe Text
  }

-- | Sensible defaults: 12 steps, 4096 max tokens, no forced thinking, the default system prompt.
defaultAgentConfig :: Text -> AgentConfig
defaultAgentConfig model = AgentConfig model 12 4096 Nothing Nothing

-- | The tool-using agent: a provider, a tool registry, and the loop config.
data Agent = Agent
  { agProvider :: Provider,
    agTools :: ToolRegistry,
    agConfig :: AgentConfig
  }

-- | The default operating instructions layered above the user's task.
defaultSystemPrompt :: Text
defaultSystemPrompt =
  T.unwords
    [ "You are Lavoisier, a token-efficient coding agent.",
      "You have tools to read, write, and list files and to run shell commands in the working directory.",
      "Use them to inspect and modify the workspace as needed to complete the task.",
      "Be concise. When the task is complete, stop and give a short final answer."
    ]

-- | One streamed, in-flight tool call: correlation id, tool name, and accumulated argument JSON.
type PendingCall = (Text, Text, Text)

-- | Run the loop, streaming every 'Event' to @emit@. Returns '()' on a clean finish, or an
-- 'AgentError' if a round-trip failed before completing.
runAgent :: Agent -> TurnRequest -> (Event -> IO ()) -> IO (Either AgentError ())
runAgent agent turn emit = go [userMessage (trInput turn)] 0
  where
    cfg = agConfig agent
    allowed = trAllowedTools turn
    defs = filterDefs allowed (registryDefs (agTools agent))
    system = SystemPrompt (fromMaybe defaultSystemPrompt (acSystem cfg)) True

    go :: [Message] -> Int -> IO (Either AgentError ())
    go msgs step
      | step >= acMaxSteps cfg = pure (Right ())
      | otherwise = do
          let req =
                (chatRequest (acModel cfg))
                  { crSystem = Just system,
                    crMessages = msgs,
                    crTools = defs,
                    crMaxTokens = acMaxTokens cfg,
                    crThinking = acThinking cfg
                  }
          estream <- providerStream (agProvider agent) req
          case estream of
            Left e -> pure (Left (AEProvider (tshow e)))
            Right stream -> do
              res <- consume stream
              case res of
                Left e -> pure (Left e)
                Right (txt, calls, stop) ->
                  if stop == ToolUse && not (null calls)
                    then do
                      results <- mapM runCall calls
                      let assistantMsg = Message Assistant (textPart txt <> map callBlock calls)
                          userMsg = Message User (map resultBlock results)
                      go (msgs <> [assistantMsg, userMsg]) (step + 1)
                    else pure (Right ())

    -- Drain one round-trip: forward each event, accumulate text + tool calls + the stop reason.
    consume :: Producer (Either ProviderError Event) -> IO (Either AgentError (Text, [PendingCall], StopReason))
    consume stream = loop "" [] Nothing
      where
        loop txt calls stop =
          nextItem stream >>= \case
            Nothing -> pure (Right (txt, calls, fromMaybe EndTurn stop))
            Just (Left e) -> pure (Left (AEProvider (tshow e)))
            Just (Right ev) -> do
              emit ev
              case ev of
                TextDelta t -> loop (txt <> t) calls stop
                ToolUseStart i n -> loop txt (calls <> [(i, n, "")]) stop
                ToolUseDelta i j -> loop txt (appendJson i j calls) stop
                ToolUseEnd _ -> loop txt calls stop
                Done sr -> loop txt calls (Just sr)
                _ -> loop txt calls stop

    runCall :: PendingCall -> IO (Text, Text, Bool)
    runCall (i, name, jsonT)
      | not (isAllowed allowed name) =
          pure (i, "tool `" <> name <> "` is not permitted this turn", True)
      | otherwise = do
          r <- invokeTool name (parseArgs jsonT) (agTools agent)
          pure $ case r of
            Right out -> (i, toContent out, toIsError out)
            Left err -> (i, "tool error: " <> tshow err, True)

    callBlock (i, name, jsonT) = ToolUseBlock i name (parseArgs jsonT)
    resultBlock (i, content, err) = ToolResultBlock i content err
    textPart txt = [TextBlock txt False | not (T.null txt)]

-- | Adapt 'runAgent' to the 'AgentHandle' record: spawn the loop, streaming its events (and any
-- terminal error) through a 'Chan'-backed pull 'Producer'.
agentHandle :: Agent -> AgentHandle
agentHandle agent = AgentHandle $ \turn -> do
  chan <- newChan
  _ <- forkIO $ do
    res <- runAgent agent turn (\ev -> writeChan chan (Just (Right ev)))
    case res of
      Left e -> writeChan chan (Just (Left e))
      Right () -> pure ()
    writeChan chan Nothing
  pure (Right (Producer (readChan chan)))

-- --- helpers --------------------------------------------------------------------------------------

filterDefs :: Maybe [Text] -> [ToolDef] -> [ToolDef]
filterDefs Nothing ds = ds
filterDefs (Just names) ds = [d | d <- ds, tdName d `elem` names]

isAllowed :: Maybe [Text] -> Text -> Bool
isAllowed Nothing _ = True
isAllowed (Just names) n = n `elem` names

appendJson :: Text -> Text -> [PendingCall] -> [PendingCall]
appendJson i j = map (\(ci, cn, cj) -> if ci == i then (ci, cn, cj <> j) else (ci, cn, cj))

parseArgs :: Text -> Value
parseArgs s =
  let s' = if T.null (T.strip s) then "{}" else s
   in fromMaybe (object []) (decodeStrict (encodeUtf8 s'))

tshow :: (Show a) => a -> Text
tshow = T.pack . show
