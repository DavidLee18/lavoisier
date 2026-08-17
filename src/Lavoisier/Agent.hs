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
    applyKnobsToArgs,
    dedupToolResults,
    markStaleReads,
    evictToFit,
    historyTokens,
  )
where

import Control.Concurrent (forkIO)
import Control.Concurrent.Chan
import Control.Monad (replicateM)
import Data.Aeson (Value (..), decodeStrict, encode, object, toJSON)
import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.IORef
import Data.List (mapAccumL)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding (decodeUtf8Lenient, encodeUtf8)
import Data.Vector qualified as V
import Data.Word (Word32)
import GHC.Clock (getMonotonicTime)
import Lavoisier.Context.Tokens (estimateTokens)
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
    acSystem :: Maybe Text,
    -- | Per-request token ceiling for the context-budget manager (§6.3). When set and still
    -- exceeded after compaction, the oldest tool-result content is evicted. 'Nothing' ⇒ no eviction.
    acContextLimit :: Maybe Int,
    -- | Cheaper model for the first 'acEscalateAfter' round-trips before escalating to 'acModel'
    -- (§8 cheap-model-first). 'Nothing' ⇒ every round-trip runs on 'acModel'. Primary only.
    acCheapModel :: Maybe Text,
    -- | Round-trips to run on 'acCheapModel' before escalating (ignored when it is 'Nothing').
    acEscalateAfter :: Int,
    -- | Smarter model for a one-shot tool-less planning pre-pass that seeds the executor (§8).
    -- 'Nothing' ⇒ no advisor. Superseded by a legion council when one is installed.
    acAdvisorModel :: Maybe Text
  }

-- | Sensible defaults: 12 steps, 4096 max tokens, no forced thinking, the default system prompt, no
-- context-eviction ceiling, no cheap\/advisor model (escalate-after 2).
defaultAgentConfig :: Text -> AgentConfig
defaultAgentConfig model = AgentConfig model 12 4096 Nothing Nothing Nothing Nothing 2 Nothing

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
  -- Pre-pass (best-effort, deliberate/advise-then-act): a legion council (if installed) argues the
  -- task out grounded in the executor's system + tools, streaming Event.Notice progress; otherwise an
  -- advisor model (if set) drafts a plan in one tool-less call. Either seeds the transcript with an
  -- assistant opening move; a failure is swallowed (turn proceeds unseeded) and the plan's tokens fold
  -- into the turn usage so they flow into the tuner's outcome.
  let seedPlan u plan =
        modifyIORef' usageRef (accumulateUsage u) >> pure (initial <> [Message Assistant [TextBlock plan False]])
  seeded <- case agDeliberator agent of
    Just delib ->
      runDeliberation delib (lastUserText initial) (DeliberationContext systemText defs (Just (emit . Notice))) >>= \case
        Left _ -> pure initial
        Right del -> seedPlan (delUsage del) (delPlan del)
    Nothing ->
      advise cfg (agProvider agent) (lastUserText initial) >>= \case
        Just (plan, u) -> seedPlan u ("Plan:\n" <> plan)
        Nothing -> pure initial
  let effThinking = maybe (acThinking cfg) Just (knobThinking knobs)
  -- ATO truncate dial: cap each tool result at the tuned byte budget before it re-enters the
  -- transcript (a large result billed every subsequent round-trip is a pure token sink). We also
  -- record the largest *pre-truncation* result so the tuner's Outcome carries the counterfactual
  -- (`otMaxToolResultBytes`) — "how big was the thing we clipped", the signal it uses to decide
  -- whether a wider budget would have helped.
  maxToolBytesRef <- newIORef (0 :: Int)
  -- Fallback cursor start: the first chain position the cross-turn breaker isn't currently demoting,
  -- so a persistently-down primary isn't re-timed every turn. Sticky within the turn (only advances).
  startCursor <- cbFirstAvailable (agBreaker agent) (length (agFallbacks agent))
  result <- go effThinking usageRef stepRef knobs maxToolBytesRef startCursor seeded 0
  finalUsage <- readIORef usageRef
  steps <- readIORef stepRef
  maxToolBytes <- readIORef maxToolBytesRef
  let out =
        defaultOutcome
          { otTotalTokens = usageCost finalUsage defaultCostWeights,
            otRoundTrips = fromIntegral steps,
            otCacheHitRate = cacheHitRate finalUsage,
            otSuccess = either (const False) (const True) result,
            otMaxToolResultBytes = if maxToolBytes > 0 then Just maxToolBytes else Nothing
          }
  tunerObserve (agTuner agent) ctx knobs out
  pure result
  where
    cfg = agConfig agent
    defs = filterDefs allowed (registryDefs (agTools agent))
    systemText = fromMaybe defaultSystemPrompt (acSystem cfg)
    system = SystemPrompt systemText True

    -- Cheap-model-first (§8) applies to the primary only: run 'acCheapModel' for the first
    -- 'acEscalateAfter' round-trips, then escalate to 'acModel'. Fallbacks name their model.
    candidatesAt :: Int -> [(Provider, Text)]
    candidatesAt step = (agProvider agent, primary) : agFallbacks agent
      where
        primary = case acCheapModel cfg of
          Just c | step < acEscalateAfter cfg -> c
          _ -> acModel cfg

    fallbacksLen :: Int
    fallbacksLen = length (agFallbacks agent)

    go :: Maybe ThinkingLevel -> IORef Usage -> IORef Int -> Knobs -> IORef Int -> Int -> [Message] -> Int -> IO (Either AgentError [Message])
    go effThinking usageRef stepRef knobs maxRef cursor msgs step
      | step >= acMaxSteps cfg = pure (Right msgs)
      | otherwise = do
          -- History shaping before the send (§6.3), in the Rust pipeline order: mark stale reads →
          -- dedup byte-identical results (both lossless) → compact the middle once over the
          -- compactAfter knob (tokens fold into the turn usage) → evict oldest results if a
          -- context-limit ceiling is still exceeded. The shrunk history carries into the recursion.
          msgs' <- shapeHistory knobs usageRef msgs
          let buildReq model =
                (chatRequest model)
                  { crSystem = Just system,
                    crMessages = msgs',
                    crTools = defs,
                    crMaxTokens = acMaxTokens cfg,
                    crThinking = effThinking
                  }
          res <- attempt (candidatesAt step) buildReq cursor
          case res of
            Left e -> pure (Left e)
            Right (txt, calls, stop, roundUsage, cursor') -> do
              modifyIORef' usageRef (accumulateUsage roundUsage)
              writeIORef stepRef (step + 1)
              if stop == ToolUse && not (null calls)
                then do
                  results <- mapM (runCall knobs maxRef) calls
                  let assistantMsg = Message Assistant (textPart txt <> map callBlock calls)
                      userMsg = Message User (map resultBlock results)
                  go effThinking usageRef stepRef knobs maxRef cursor' (msgs' <> [assistantMsg, userMsg]) (step + 1)
                else pure (Right (msgs' <> [Message Assistant blocks | let blocks = textPart txt, not (null blocks)]))

    -- The §6.3 pipeline: stale-reads → dedup (both lossless) → compact (best-effort) → evict-to-fit
    -- (only when a context limit is configured).
    shapeHistory :: Knobs -> IORef Usage -> [Message] -> IO [Message]
    shapeHistory knobs usageRef msgs = do
      let shrunk = dedupToolResults (markStaleReads msgs)
      compacted <-
        if historyTokens shrunk > compactAfter knobs
          then do
            mc <- compactHistory (agProvider agent) cfg shrunk
            case mc of
              Just (h, u) -> modifyIORef' usageRef (accumulateUsage u) >> pure h
              Nothing -> pure shrunk
          else pure shrunk
      pure $ maybe compacted (`evictToFit` compacted) (acContextLimit cfg)

    -- Fallback-aware send: try the model at `cursor`, then each remaining fallback in order. We only
    -- switch models *before any output has been forwarded* this round-trip — a stream-open error, or
    -- a stream error before the first content token. Once bytes are streaming a restart would double
    -- the user-visible text, so a later failure surfaces as an error like before. Within the turn the
    -- cursor only advances (a dead model is skipped for the rest of the turn); across turns each
    -- pre-token failure trips the breaker (demote for a cooldown) and a success resets it. Returns the
    -- (settled) cursor so it stays sticky across the turn's round-trips.
    attempt ::
      [(Provider, Text)] ->
      (Text -> ChatRequest) ->
      Int ->
      IO (Either AgentError (Text, [PendingCall], StopReason, Usage, Int))
    attempt cands buildReq = tryCursor
      where
        tryCursor c = do
          let (prov, model) = cands !! c
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

    runCall :: Knobs -> IORef Int -> PendingCall -> IO (Text, Text, Bool)
    runCall knobs maxRef (i, name, jsonT)
      | not (isAllowed allowed name) =
          pure (i, "tool `" <> name <> "` is not permitted this turn", True)
      | otherwise = do
          -- Apply the agent-enforced knobs to the call's args (skeleton-radius injection, batch-width
          -- cap), then truncate the result to the tuned byte budget and record the counterfactual.
          let args = applyKnobsToArgs knobs name (parseArgs jsonT)
          r <- invokeTool name args (agTools agent)
          case r of
            Left err -> pure (i, "tool error: " <> tshow err, True)
            Right out -> do
              let (content, origBytes) = truncateToBytes (truncateBytes knobs) (toContent out)
              modifyIORef' maxRef (max origBytes)
              pure (i, content, toIsError out)

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

-- --- history compaction (§6.3) --------------------------------------------------------------------

-- | Trailing (assistant, tool-result) turn-pairs kept verbatim when compacting.
keepRecentTurns :: Int
keepRecentTurns = 2

-- | Generation ceiling for a compaction summary (summaries are meant to be short).
summaryMaxTokens :: Word32
summaryMaxTokens = 512

-- | Tool results at or below this byte size are never deduplicated — the saving isn't worth churn.
dedupMinBytes :: Int
dedupMinBytes = 200

-- | System prompt for the compaction summariser: terse, structured, fact-preserving.
compactionSystem :: Text
compactionSystem =
  "You compress a coding agent's transcript so it can keep working with fewer tokens. Produce a "
    <> "terse note that preserves: files inspected or edited (with their paths), key findings, "
    <> "decisions made, and any steps still pending. Use short bullet lines. Omit pleasantries and "
    <> "reasoning narration. Output only the note."

-- | Media blocks aren't text; approximate their prompt footprint with this placeholder.
mediaProxy :: Text
mediaProxy = "[media block ~1500 tokens placeholder]"

-- | System prompt for the advisor pre-pass (§8): a terse plan, no code.
advisorSystem :: Text
advisorSystem =
  "You are a planning advisor for a coding agent. Given the task, output a short, concrete plan: "
    <> "which files or areas to inspect, the edits likely required, and the order of steps. Terse "
    <> "bullet lines only — no prose, no code, no narration."

-- | Generation ceiling for the advisor plan (plans are meant to be short).
advisorMaxTokens :: Word32
advisorMaxTokens = 512

-- | Advisor pre-pass (§8): one tool-less call to 'acAdvisorModel' drafting a plan for @task@; the
-- plan seeds the executor. 'Nothing' when the advisor is disabled, the call fails, or the plan is
-- empty. Reuses 'toollessCall'; superseded by a legion council when one is installed.
advise :: AgentConfig -> Provider -> Text -> IO (Maybe (Text, Usage))
advise cfg prov task = case acAdvisorModel cfg of
  Nothing -> pure Nothing
  Just m -> (>>= nonEmpty) <$> toollessCall prov (req m)
  where
    req m =
      (chatRequest m)
        { crSystem = Just (SystemPrompt advisorSystem True),
          crMessages = [userMessage task],
          crMaxTokens = advisorMaxTokens
        }
    nonEmpty r@(plan, _) = if T.null (T.strip plan) then Nothing else Just r

-- | Estimate the token footprint of the whole transcript (tool-call args + tool results dominate) —
-- the trigger for compaction.
historyTokens :: [Message] -> Int
historyTokens = sum . map (estimateTokens . proxyText)

-- | A message flattened to a text proxy for token estimation.
proxyText :: Message -> Text
proxyText (Message _ blocks) = T.unwords (map blockProxy blocks)
  where
    blockProxy = \case
      TextBlock t _ -> t
      ThinkingBlock t -> t
      ToolUseBlock _ n inp -> n <> renderJson inp
      ToolResultBlock _ c _ -> c
      ImageBlock _ -> mediaProxy
      DocumentBlock _ _ -> mediaProxy

-- | Render messages to a plain-text transcript for the summariser (tool blocks flattened to text,
-- since the summary request advertises no tools).
renderTranscript :: [Message] -> Text
renderTranscript = T.concat . map renderMsg
  where
    renderMsg (Message role blocks) = T.concat (map (renderBlock (roleLabel role)) blocks)
    roleLabel User = "user"
    roleLabel Assistant = "assistant"
    renderBlock role = \case
      TextBlock t _ -> role <> ": " <> t <> "\n"
      ThinkingBlock t -> role <> ": " <> t <> "\n"
      ToolUseBlock _ n inp -> role <> " called " <> n <> "(" <> renderJson inp <> ")\n"
      ToolResultBlock _ c err -> "tool result" <> (if err then " (error)" else "") <> ": " <> c <> "\n"
      ImageBlock _ -> role <> ": [image]\n"
      DocumentBlock _ _ -> role <> ": [document]\n"

-- | Collapse byte-identical tool-result content that appears more than once (e.g. the same file
-- read\/outlined twice unchanged). Walking newest→oldest, the most recent copy is kept verbatim and
-- earlier identical copies become a short pointer. Small results and existing placeholders are left
-- alone; @tool_use@\/@tool_result@ structure is preserved.
dedupToolResults :: [Message] -> [Message]
dedupToolResults msgs = reverse (go' Set.empty (reverse msgs))
  where
    go' _ [] = []
    go' seen (Message role blocks : rest) =
      let (seen', blocks') = mapAccumL dedupBlock seen blocks
       in Message role blocks' : go' seen' rest
    dedupBlock seen b@(ToolResultBlock i content err)
      | nbytes content < dedupMinBytes
          || "[evicted" `T.isPrefixOf` content
          || "[duplicate" `T.isPrefixOf` content =
          (seen, b)
      | Set.member content seen =
          (seen, ToolResultBlock i ("[duplicate of a more recent identical result, " <> tshow (nbytes content) <> " bytes]") err)
      | otherwise = (Set.insert content seen, b)
    dedupBlock seen b = (seen, b)
    nbytes = BS.length . encodeUtf8

-- | Tools whose result is file content that goes stale once the file is edited.
readTools :: [Text]
readTools = ["read_file", "read_files", "read_anchored", "outline_file", "outline_files"]

-- | Tools that edit a file (their success supersedes earlier reads of the same path).
editTools :: [Text]
editTools = ["str_replace", "edit_anchored", "edit_files", "write_file", "batch_edit"]

-- | Every file path referenced in a tool call's args — @path@ (string) and @paths@ (array) at any
-- nesting depth (so a nested @edits[].path@ is captured too).
collectPaths :: Value -> [Text]
collectPaths (Object m) = concatMap fromKey (KM.toList m)
  where
    fromKey (k, val) = case K.toText k of
      "path" -> case val of String s -> [s]; _ -> []
      "paths" -> case val of Array a -> [s | String s <- V.toList a]; _ -> []
      _ -> collectPaths val
collectPaths (Array a) = concatMap collectPaths (V.toList a)
collectPaths _ = []

-- | Staleness-aware eviction (§6.3): once a file has been successfully edited, replace each earlier
-- read\/outline of that same path with a short "[stale: …]" pointer (the carried bytes are now
-- wrong). The most recent read of a path (with no later edit), non-read results, small results,
-- errored results, and already-elided placeholders are left intact.
markStaleReads :: [Message] -> [Message]
markStaleReads history
  | Map.null lastEdit = history
  | otherwise = map reviseMsg history
  where
    -- Pass 1: linear index of read/edit calls (id → (position, isRead, isEdit, paths)) + errored ids.
    -- A position is assigned to every tool-use block in transcript order (as in Rust).
    (calls, errored) = indexCalls 0 Map.empty Set.empty (concatMap (\(Message _ bs) -> bs) history)
    indexCalls _ cs es [] = (cs, es)
    indexCalls pos cs es (b : bs) = case b of
      ToolUseBlock i n inp ->
        let isRead = n `elem` readTools
            isEdit = n `elem` editTools
            cs' =
              if isRead || isEdit
                then Map.insert i (pos, isRead, isEdit, collectPaths inp) cs
                else cs
         in indexCalls (pos + 1) cs' es bs
      ToolResultBlock tid _ err -> indexCalls pos cs (if err then Set.insert tid es else es) bs
      _ -> indexCalls pos cs es bs
    -- Latest position at which each path was *successfully* edited.
    lastEdit :: Map.Map Text Int
    lastEdit =
      Map.fromListWith
        max
        [ (p, pos)
        | (i, (pos, _, isEdit, paths)) <- Map.toList calls,
          isEdit,
          not (Set.member i errored),
          p <- paths
        ]
    reviseMsg (Message role bs) = Message role (map reviseBlock bs)
    reviseBlock b@(ToolResultBlock tid content err)
      | err || nbytes content < dedupMinBytes || "[" `T.isPrefixOf` content = b
      | otherwise = case Map.lookup tid calls of
          Just (pos, True, _, paths) ->
            case [p | p <- paths, maybe False (> pos) (Map.lookup p lastEdit)] of
              (stalePath : _) ->
                ToolResultBlock
                  tid
                  ("[stale: " <> stalePath <> " was edited after this read; " <> tshow (nbytes content) <> " bytes elided — re-read it if you need the current contents]")
                  err
              [] -> b
          _ -> b
    reviseBlock b = b
    nbytes = BS.length . encodeUtf8

-- | Context-budget eviction (§6.3): when the transcript still exceeds @limit@ tokens (e.g. one huge
-- recent result compaction can't touch), replace the /content/ of the oldest tool results (skipping
-- the task message and the protected recent window) with a placeholder, oldest-first, until it fits
-- or nothing more is evictable.
evictToFit :: Int -> [Message] -> [Message]
evictToFit limit history
  | historyTokens history <= limit = history
  | otherwise = evictFrom 1 history
  where
    evictableEnd = max 0 (length history - 2 * keepRecentTurns)
    evictFrom i hist
      | i >= evictableEnd = hist
      | otherwise =
          let (hist', changed) = evictAt i hist
           in if changed && historyTokens hist' <= limit
                then hist'
                else evictFrom (i + 1) hist'
    evictAt i hist = case splitAt i hist of
      (before, m : after) -> let (m', changed) = evictMsg m in (before ++ m' : after, changed)
      (_, []) -> (hist, False)
    evictMsg (Message role bs) =
      let (bs', anyChanged) = foldr step ([], False) bs
       in (Message role bs', anyChanged)
      where
        step b (acc, ch) = case b of
          ToolResultBlock tid content err
            | not ("[evicted" `T.isPrefixOf` content) ->
                (ToolResultBlock tid ("[evicted: " <> tshow (BS.length (encodeUtf8 content)) <> " bytes of older tool output]") err : acc, True)
          _ -> (b : acc, ch)

-- | Summarise the middle of @history@ into one note via a tool-less provider call. Returns 'Nothing'
-- (leaving history untouched) if there is too little to compact or the summary is empty\/failed. The
-- task message and the last @2*keepRecentTurns@ messages are kept verbatim; the slice between them is
-- replaced by a single user note. The cut lands on a turn boundary so an assistant @tool_use@ is
-- never split from its @tool_result@.
compactHistory :: Provider -> AgentConfig -> [Message] -> IO (Maybe ([Message], Usage))
compactHistory prov cfg history = case history of
  (h0 : _)
    | length history >= keep + 3 -> do
        let cutEnd = length history - keep
            prefix = take (cutEnd - 1) (drop 1 history)
            req =
              (chatRequest (acModel cfg))
                { crSystem = Just (SystemPrompt compactionSystem True),
                  crMessages = [userMessage (renderTranscript prefix)],
                  crMaxTokens = summaryMaxTokens
                }
        r <- toollessCall prov req
        pure $ case r of
          Just (summary, usage)
            | not (T.null (T.strip summary)) ->
                let note = userMessage ("[Earlier conversation compacted to save tokens]\n" <> summary)
                 in Just (h0 : note : drop cutEnd history, usage)
          _ -> Nothing
  _ -> pure Nothing
  where
    keep = 2 * keepRecentTurns

-- | Run one tool-less provider request, collecting streamed text and the (last) usage. 'Nothing' on
-- a stream-open error or any mid-stream error (mirrors the Rust compaction\/advisor drain).
toollessCall :: Provider -> ChatRequest -> IO (Maybe (Text, Usage))
toollessCall prov req = do
  est <- providerStream prov req
  case est of
    Left _ -> pure Nothing
    Right stream -> drainSummary stream "" emptyUsage
  where
    drainSummary stream acc usg =
      nextItem stream >>= \case
        Nothing -> pure (Just (acc, usg))
        Just (Left _) -> pure Nothing
        Just (Right (TextDelta t)) -> drainSummary stream (acc <> t) usg
        Just (Right (Usage u)) -> drainSummary stream acc u
        Just (Right _) -> drainSummary stream acc usg

-- | A JSON value rendered to compact text (for token-proxy\/transcript rendering).
renderJson :: Value -> Text
renderJson = decodeUtf8Lenient . BL.toStrict . encode

-- | Apply the knobs the agent enforces directly on a tool call's arguments (§6.6\/§6.1): inject the
-- tuned skeleton radius into an @outline_*@ call that focuses a symbol but left @radius@ unset, and
-- cap a batch tool's @paths@ array to the batch-width knob. Other tools\/already-pinned args pass
-- through untouched. Ports the Rust @apply_knobs_to_args@.
applyKnobsToArgs :: Knobs -> Text -> Value -> Value
applyKnobsToArgs knobs tool (Object o) = Object (capPaths (injectRadius o))
  where
    injectRadius m
      | tool `elem` ["outline_file", "outline_files"],
        KM.member "focus" m,
        not (KM.member "radius" m) =
          KM.insert "radius" (toJSON (fromIntegral (skeletonRadius knobs) :: Int)) m
      | otherwise = m
    capPaths m
      | tool `elem` ["read_files", "outline_files"] =
          case KM.lookup "paths" m of
            Just (Array a) -> KM.insert "paths" (Array (V.take (fromIntegral (batchWidth knobs)) a)) m
            _ -> m
      | otherwise = m
applyKnobsToArgs _ _ v = v

-- | Truncate @content@ to about @maxBytes@, keeping the head (⅔) and tail (⅓) around an elision
-- marker, and return it with the ORIGINAL byte size (so the caller records the pre-truncation
-- counterfactual). Preserving the tail keeps trailing errors\/summaries visible. Ports the Rust
-- @truncate@ (byte-length threshold, char-count head\/tail). A non-positive limit disables it.
truncateToBytes :: Int -> Text -> (Text, Int)
truncateToBytes maxBytes content
  | maxBytes <= 0 || origBytes <= maxBytes = (content, origBytes)
  | otherwise = (headT <> "\n... [" <> tshow omitted <> " bytes truncated] ...\n" <> tailT, origBytes)
  where
    origBytes = BS.length (encodeUtf8 content)
    headT = T.take (maxBytes * 2 `div` 3) content
    tailT = T.takeEnd (maxBytes `div` 3) content
    omitted = origBytes - (BS.length (encodeUtf8 headT) + BS.length (encodeUtf8 tailT))

tshow :: (Show a) => a -> Text
tshow = T.pack . show
