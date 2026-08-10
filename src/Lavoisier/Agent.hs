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
    mkAgent,
    withFallbacks,
    CircuitBreaker,
    newCircuitBreaker,
    defaultFallbackCooldown,
    runAgent,
    runLoopSeeded,
    agentHandle,
    defaultSystemPrompt,
  )
where

import Control.Concurrent (forkIO)
import Control.Concurrent.Chan
import Control.Monad (replicateM)
import Data.Aeson (Value (..), decodeStrict, object)
import Data.IORef
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding (encodeUtf8)
import Data.Word (Word32)
import GHC.Clock (getMonotonicTime)
import Lavoisier.Protocol.Agent
import Lavoisier.Protocol.Deliberate
  ( Deliberation (..),
    DeliberationContext (..),
    Deliberator (..),
  )
import Lavoisier.Protocol.Event
  ( Event (..),
    StopReason (EndTurn, ToolUse),
    Usage,
    accumulateUsage,
    cacheHitRate,
    defaultCostWeights,
    emptyUsage,
    usageCost,
  )
import Lavoisier.Protocol.Message
import Lavoisier.Protocol.Provider (Provider (..), ProviderError)
import Lavoisier.Protocol.Stream (Producer (..))
import Lavoisier.Protocol.Tool (ToolOutput (..))
import Lavoisier.Protocol.Tune
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

-- | A per-position __circuit breaker__ for the fallback chain, shared across turns so a dead model
-- isn't re-probed every turn. Position @0@ is the primary; position @i>0@ is @fallbacks !! (i-1)@.
-- A position that fails (unresponsive\/errors before the first token) is __demoted__ for a cooldown;
-- while demoted it is skipped at turn start, so its timeout isn't re-paid each turn. Once the
-- cooldown elapses it is re-probed (half-open): a probe success clears it, a probe failure re-trips
-- it. Each position holds an 'IORef' deadline on the monotonic clock (@0@ = healthy), written
-- atomically so concurrent turns (spawned gateway tasks) share it without a lock.
data CircuitBreaker = CircuitBreaker
  { cbDeadlines :: [IORef Double],
    cbCooldown :: Double
  }

-- | Default fallback cooldown, in seconds (mirrors the Rust @--fallback-cooldown@ default).
defaultFallbackCooldown :: Double
defaultFallbackCooldown = 60

-- | A breaker for @positions@ chain slots (@1 + length fallbacks@), all initially healthy, demoting
-- a tripped position for @cooldown@ seconds.
newCircuitBreaker :: Int -> Double -> IO CircuitBreaker
newCircuitBreaker positions cooldown = do
  refs <- replicateM (max 1 positions) (newIORef 0)
  pure (CircuitBreaker refs cooldown)

cbAt :: CircuitBreaker -> Int -> Maybe (IORef Double)
cbAt cb i = case drop i (cbDeadlines cb) of
  (r : _) -> Just r
  [] -> Nothing

-- | Whether position @i@ is currently demoted (its cooldown has not yet elapsed).
cbIsOpen :: CircuitBreaker -> Int -> IO Bool
cbIsOpen cb i = case cbAt cb i of
  Nothing -> pure False
  Just r -> do
    d <- readIORef r
    now <- getMonotonicTime
    pure (d > now)

-- | Demote position @i@ for one cooldown (last write wins under concurrency).
cbTrip :: CircuitBreaker -> Int -> IO ()
cbTrip cb i = case cbAt cb i of
  Nothing -> pure ()
  Just r -> do
    now <- getMonotonicTime
    atomicWriteIORef r (now + cbCooldown cb)

-- | Mark position @i@ healthy again (a successful use clears any prior demotion).
cbReset :: CircuitBreaker -> Int -> IO ()
cbReset cb i = maybe (pure ()) (`atomicWriteIORef` 0) (cbAt cb i)

-- | The first chain position (@0..fallbacksLen@) not currently demoted — where a turn starts. If
-- every position is demoted we still must try something, so fall back to the primary (@0@).
cbFirstAvailable :: CircuitBreaker -> Int -> IO Int
cbFirstAvailable cb fallbacksLen = probe 0
  where
    probe i
      | i > fallbacksLen = pure 0
      | otherwise = do
          open <- cbIsOpen cb i
          if open then probe (i + 1) else pure i

-- | The tool-using agent: a provider, a tool registry, the loop config, an ATO 'Tuner', an optional
-- legion 'Deliberator', an ordered fallback chain, and its cross-turn 'CircuitBreaker'. 'noopTuner'
-- (the default) makes ATO a no-op; @Lavoisier.Tune@'s learner swaps in to tune knobs. 'Nothing' for
-- the deliberator skips the council pre-pass; @Lavoisier.Legion@'s panel swaps in to argue the task
-- out before the loop (deliberate-then-act). An empty 'agFallbacks' ⇒ no fallback (today's default
-- behaviour); build via 'mkAgent' then 'withFallbacks'.
data Agent = Agent
  { agProvider :: Provider,
    agTools :: ToolRegistry,
    agConfig :: AgentConfig,
    agTuner :: Tuner,
    agDeliberator :: Maybe Deliberator,
    -- | Ordered @(provider, model)@ fallback chain for an unresponsive\/erroring primary. Empty by
    -- default. Within a turn the cursor only advances (a failed model is skipped for the rest of the
    -- turn); across turns 'agBreaker' demotes a failed position for a cooldown.
    agFallbacks :: [(Provider, Text)],
    -- | Cross-turn circuit breaker over the chain, sized @1 + length agFallbacks@.
    agBreaker :: CircuitBreaker
  }

-- | Build an 'Agent' with no fallback chain (a healthy 1-slot breaker) — the default wiring.
mkAgent :: Provider -> ToolRegistry -> AgentConfig -> Tuner -> Maybe Deliberator -> IO Agent
mkAgent prov tools cfg tuner delib = do
  breaker <- newCircuitBreaker 1 defaultFallbackCooldown
  pure (Agent prov tools cfg tuner delib [] breaker)

-- | Install an ordered fallback chain of @(provider, model)@ pairs with the given cooldown (seconds).
-- Sizes a fresh 'CircuitBreaker' to @1 + length chain@. An empty chain leaves the agent unchanged in
-- effect (the breaker's extra slots are simply unused).
withFallbacks :: [(Provider, Text)] -> Double -> Agent -> IO Agent
withFallbacks chain cooldown agent = do
  breaker <- newCircuitBreaker (1 + length chain) cooldown
  pure agent {agFallbacks = chain, agBreaker = breaker}

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

-- | The result of draining one provider round-trip. 'RoundFail' carries whether any *content* event
-- was forwarded before the failure — the pre-token fallback gate: a failure with nothing forwarded
-- may cleanly retry on another model, one after output has streamed must surface as an error.
data RoundOutcome
  = RoundOk Text [PendingCall] StopReason Usage
  | RoundFail Bool ProviderError

-- | Whether an event carries user-visible content (so forwarding it commits us to this model). Usage,
-- 'Done', and 'Notice' are bookkeeping\/progress, not content, so they don't block a pre-token retry.
isContentEvent :: Event -> Bool
isContentEvent = \case
  TextDelta _ -> True
  Thinking _ -> True
  ToolUseStart _ _ -> True
  ToolUseDelta _ _ -> True
  ToolUseEnd _ -> True
  ServerToolUse _ _ -> True
  ServerToolResult _ _ -> True
  Citation _ _ -> True
  _ -> False

-- | Run the loop, streaming every 'Event' to @emit@. Returns '()' on a clean finish, or an
-- 'AgentError' if a round-trip failed before completing.
runAgent :: Agent -> TurnRequest -> (Event -> IO ()) -> IO (Either AgentError ())
runAgent agent turn emit =
  fmap (const ())
    <$> runLoopSeeded agent (trAllowedTools turn) [userMessage (trInput turn)] emit

-- | The loop, seeded with an initial transcript (@initial@ already includes this turn's user
-- message). Streams events to @emit@ and returns the **full transcript** — @initial@ plus every
-- assistant\/tool-result message produced — so a session store can persist it (see
-- "Lavoisier.Memory").
runLoopSeeded ::
  Agent ->
  Maybe [Text] ->
  [Message] ->
  (Event -> IO ()) ->
  IO (Either AgentError [Message])
runLoopSeeded agent allowed initial emit = do
  -- ATO: pick knobs for this task, honour the tuned thinking dial (the one knob the loop can act on
  -- today — the skeleton/truncate/compact/batch dials await the context engine), then observe the
  -- realised cost-weighted outcome so the learner improves. With 'noopTuner' this is inert.
  let ctx = taskContextFor agent
  knobs <- tunerSelect (agTuner agent) ctx
  usageRef <- newIORef emptyUsage
  stepRef <- newIORef (0 :: Int)
  -- Legion pre-pass (best-effort, deliberate-then-act): if a council is configured, ask it to argue
  -- the task out — grounded in the executor's system prompt + this turn's tools, with progress
  -- streamed as Event.Notice — and seed the transcript with the agreed plan as an assistant opening
  -- move. A failed deliberation is swallowed and the turn proceeds unseeded. Its token cost is folded
  -- into the turn's usage so it flows into the tuner's outcome.
  seeded <- case agDeliberator agent of
    Nothing -> pure initial
    Just delib -> do
      let dctx = DeliberationContext systemText defs (Just (emit . Notice))
      r <- runDeliberation delib (lastUserText initial) dctx
      case r of
        Left _ -> pure initial
        Right del -> do
          modifyIORef' usageRef (accumulateUsage (delUsage del))
          pure (initial <> [Message Assistant [TextBlock (delPlan del) False]])
  let effThinking = maybe (acThinking cfg) Just (knobThinking knobs)
  -- Fallback cursor start: the first chain position the cross-turn breaker isn't currently demoting,
  -- so a persistently-down primary isn't re-timed every turn. Sticky within the turn (only advances).
  startCursor <- cbFirstAvailable (agBreaker agent) (length (agFallbacks agent))
  result <- go effThinking usageRef stepRef startCursor seeded 0
  finalUsage <- readIORef usageRef
  steps <- readIORef stepRef
  let out =
        defaultOutcome
          { otTotalTokens = usageCost finalUsage defaultCostWeights,
            otRoundTrips = fromIntegral steps,
            otCacheHitRate = cacheHitRate finalUsage,
            otSuccess = either (const False) (const True) result
          }
  tunerObserve (agTuner agent) ctx knobs out
  pure result
  where
    cfg = agConfig agent
    defs = filterDefs allowed (registryDefs (agTools agent))
    systemText = fromMaybe defaultSystemPrompt (acSystem cfg)
    system = SystemPrompt systemText True

    candidates :: [(Provider, Text)]
    candidates = (agProvider agent, acModel cfg) : agFallbacks agent

    fallbacksLen :: Int
    fallbacksLen = length (agFallbacks agent)

    go :: Maybe ThinkingLevel -> IORef Usage -> IORef Int -> Int -> [Message] -> Int -> IO (Either AgentError [Message])
    go effThinking usageRef stepRef cursor msgs step
      | step >= acMaxSteps cfg = pure (Right msgs)
      | otherwise = do
          let buildReq model =
                (chatRequest model)
                  { crSystem = Just system,
                    crMessages = msgs,
                    crTools = defs,
                    crMaxTokens = acMaxTokens cfg,
                    crThinking = effThinking
                  }
          res <- attempt buildReq cursor
          case res of
            Left e -> pure (Left e)
            Right (txt, calls, stop, roundUsage, cursor') -> do
              modifyIORef' usageRef (accumulateUsage roundUsage)
              writeIORef stepRef (step + 1)
              if stop == ToolUse && not (null calls)
                then do
                  results <- mapM runCall calls
                  let assistantMsg = Message Assistant (textPart txt <> map callBlock calls)
                      userMsg = Message User (map resultBlock results)
                  go effThinking usageRef stepRef cursor' (msgs <> [assistantMsg, userMsg]) (step + 1)
                else pure (Right (msgs <> [Message Assistant blocks | let blocks = textPart txt, not (null blocks)]))

    -- Fallback-aware send: try the model at `cursor`, then each remaining fallback in order. We only
    -- switch models *before any output has been forwarded* this round-trip — a stream-open error, or
    -- a stream error before the first content token. Once bytes are streaming a restart would double
    -- the user-visible text, so a later failure surfaces as an error like before. Within the turn the
    -- cursor only advances (a dead model is skipped for the rest of the turn); across turns each
    -- pre-token failure trips the breaker (demote for a cooldown) and a success resets it. Returns the
    -- (settled) cursor so it stays sticky across the turn's round-trips.
    attempt ::
      (Text -> ChatRequest) ->
      Int ->
      IO (Either AgentError (Text, [PendingCall], StopReason, Usage, Int))
    attempt buildReq = tryCursor
      where
        tryCursor c = do
          let (prov, model) = candidates !! c
              hasNext = c < fallbacksLen
          estream <- providerStream prov (buildReq model)
          case estream of
            -- Stream failed to open ⇒ before any output; trip and fall through to the next candidate.
            Left e -> do
              cbTrip (agBreaker agent) c
              if hasNext then tryCursor (c + 1) else pure (Left (AEProvider (tshow e)))
            Right stream -> do
              outcome <- consume stream
              case outcome of
                RoundOk txt calls stop usg -> do
                  cbReset (agBreaker agent) c
                  pure (Right (txt, calls, stop, usg, c))
                RoundFail forwarded e -> do
                  if forwarded then pure () else cbTrip (agBreaker agent) c
                  if not forwarded && hasNext
                    then tryCursor (c + 1)
                    else pure (Left (AEProvider (tshow e)))

    -- Drain one round-trip: forward each event, accumulate text + tool calls + stop reason + usage,
    -- and track whether any *content* event has been forwarded (drives the pre-token fallback gate).
    consume :: Producer (Either ProviderError Event) -> IO RoundOutcome
    consume stream = loop "" [] Nothing emptyUsage False
      where
        loop txt calls stop usg fwd =
          nextItem stream >>= \case
            Nothing -> pure (RoundOk txt calls (fromMaybe EndTurn stop) usg)
            Just (Left e) -> pure (RoundFail fwd e)
            Just (Right ev) -> do
              emit ev
              let fwd' = fwd || isContentEvent ev
              case ev of
                TextDelta t -> loop (txt <> t) calls stop usg fwd'
                ToolUseStart i n -> loop txt (calls <> [(i, n, "")]) stop usg fwd'
                ToolUseDelta i j -> loop txt (appendJson i j calls) stop usg fwd'
                ToolUseEnd _ -> loop txt calls stop usg fwd'
                Usage u -> loop txt calls stop (accumulateUsage u usg) fwd'
                Done sr -> loop txt calls (Just sr) usg fwd'
                _ -> loop txt calls stop usg fwd'

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

-- | The ATO 'TaskContext' for this turn. Archetype classification and repo profiling are deferred
-- (no context engine yet), so it reports 'Other' over an empty repo; the model tier is a coarse
-- name heuristic, and the concrete model id keys the learner's profiles apart across upgrades.
taskContextFor :: Agent -> TaskContext
taskContextFor agent =
  TaskContext
    { tcArchetype = Other,
      tcRepo = defaultRepoProfile,
      tcCaps = providerCapabilities (agProvider agent),
      tcModel = tierOf (acModel (agConfig agent)),
      tcModelId = acModel (agConfig agent),
      tcRepoId = ""
    }

-- | The task the council deliberates: the text of the latest user message in the seed transcript.
lastUserText :: [Message] -> Text
lastUserText msgs = case [messageText m | m <- msgs, msgRole m == User] of
  [] -> ""
  xs -> last xs

-- | Coarse capability tier from the model name.
tierOf :: Text -> ModelTier
tierOf m
  | any (`T.isInfixOf` m) ["haiku", "flash", "fast", "lite"] = Fast
  | any (`T.isInfixOf` m) ["opus", "heavy", "ultra"] = Deep
  | otherwise = Balanced

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
