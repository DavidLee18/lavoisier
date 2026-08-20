-- | The normalised event stream — the semantic layer every provider maps onto.
--
-- Each provider adapter is the /only/ place that translates its wire format into these
-- constructors; nothing downstream of a provider sees a wire protocol. Ported from the Rust
-- @lvz-protocol@ @event.rs@; the JSON encodings below reproduce that crate's serde shapes exactly
-- (this is the on-the-wire form the gateways stream), so a Rust client and a Haskell gateway agree.
module Lavoisier.Protocol.Event
  ( Event (..),
    Usage (..),
    StopReason (..),
    CostWeights (..),
    emptyUsage,
    usageTotal,
    usageCost,
    accumulateUsage,
    cacheHitRate,
    defaultCostWeights,
    anthropicWeights,
    xaiWeights,
    googleWeights,
    flatWeights,
  )
where

import Data.Aeson
import Data.Aeson.Types (Parser, typeMismatch)
import Data.Text (Text)
import Data.Word (Word64)

-- | A single normalised event in a streamed model turn.
--
-- Adjacently tagged on the wire (@{"kind": …, "data": …}@, snake_case), matching Rust's
-- @#[serde(tag = "kind", content = "data", rename_all = "snake_case")]@.
data Event
  = -- | Incremental assistant text.
    TextDelta Text
  | -- | Incremental extended-thinking text (Anthropic).
    Thinking Text
  | -- | A tool call has begun: @id@ correlates the following deltas and end, then @name@.
    ToolUseStart Text Text
  | -- | Incremental tool-argument JSON (@id@, then a @json@ fragment) for the call.
    ToolUseDelta Text Text
  | -- | The tool call identified by @id@ is complete.
    ToolUseEnd Text
  | -- | A provider-executed (server-side) tool was invoked (@id@, @name@). Informational.
    ServerToolUse Text Text
  | -- | The result of a provider-executed tool (@id@, then @content@ as a JSON string).
    ServerToolResult Text Text
  | -- | A citation the model attached to the preceding output span (@cited_text@, @source@).
    Citation Text Text
  | -- | Token accounting, including cache hits. May arrive mid-stream and/or at the end.
    Usage Usage
  | -- | A human-readable progress notice about the turn (injected by the agent, not the provider).
    Notice Text
  | -- | Terminal event: the turn finished for the given reason.
    Done StopReason
  deriving stock (Eq, Show)

-- | Token accounting for a turn. Cache fields are zero on providers without prompt caching.
data Usage = MkUsage
  { inputTokens :: Word64,
    outputTokens :: Word64,
    cacheCreationTokens :: Word64,
    cacheReadTokens :: Word64
  }
  deriving stock (Eq, Show)

-- | The all-zero usage (Rust @Usage::default()@).
emptyUsage :: Usage
emptyUsage = MkUsage 0 0 0 0

-- | Raw billable input + output tokens (excludes the cache classes) — for display/diagnostics.
usageTotal :: Usage -> Word64
usageTotal u = inputTokens u + outputTokens u

-- | Cost-weighted total in fresh-input-token-equivalent units (rounded) — the budget/ATO objective.
usageCost :: Usage -> CostWeights -> Word64
usageCost u w =
  round $
    fromIntegral (inputTokens u) * cwInput w
      + fromIntegral (outputTokens u) * cwOutput w
      + fromIntegral (cacheCreationTokens u) * cwCacheCreation w
      + fromIntegral (cacheReadTokens u) * cwCacheRead w

-- | Add another turn's usage into this one — the running total across round-trips.
accumulateUsage :: Usage -> Usage -> Usage
accumulateUsage a b =
  MkUsage
    (inputTokens a + inputTokens b)
    (outputTokens a + outputTokens b)
    (cacheCreationTokens a + cacheCreationTokens b)
    (cacheReadTokens a + cacheReadTokens b)

-- | Fraction of input tokens served from cache, in @[0, 1]@. Zero when no input tokens.
cacheHitRate :: Usage -> Double
cacheHitRate u =
  let billed = inputTokens u + cacheReadTokens u
   in if billed == 0 then 0 else fromIntegral (cacheReadTokens u) / fromIntegral billed

-- | Per-token-class cost multipliers, relative to a fresh input token (= 1.0).
data CostWeights = CostWeights
  { cwInput :: Double,
    cwOutput :: Double,
    cwCacheCreation :: Double,
    cwCacheRead :: Double
  }
  deriving stock (Eq, Show)

-- | Anthropic/xAI ratios: output ≈ 5×, cache write ≈ 1.25×, cache read ≈ 0.1×.
defaultCostWeights :: CostWeights
defaultCostWeights = CostWeights 1.0 5.0 1.25 0.1

anthropicWeights :: CostWeights
anthropicWeights = defaultCostWeights

xaiWeights :: CostWeights
xaiWeights = defaultCostWeights

-- | Gemini ratios: wider output:input spread and a pricier cache read than Anthropic.
googleWeights :: CostWeights
googleWeights = CostWeights 1.0 8.0 1.0 0.25

-- | Flat weights — every token class counts the same (the legacy raw-token objective).
flatWeights :: CostWeights
flatWeights = CostWeights 1.0 1.0 1.0 1.0

-- | Why a turn stopped. Externally tagged snake_case on the wire, matching Rust.
data StopReason
  = EndTurn
  | MaxTokens
  | ToolUse
  | StopSequence
  | Refusal
  | PauseTurn
  | -- | Anything provider-specific not captured above.
    Other Text
  deriving stock (Eq, Show)

-- --- JSON: reproduce the Rust serde shapes exactly -------------------------------------------------

instance ToJSON Usage where
  toJSON u =
    object
      [ "input_tokens" .= inputTokens u,
        "output_tokens" .= outputTokens u,
        "cache_creation_tokens" .= cacheCreationTokens u,
        "cache_read_tokens" .= cacheReadTokens u
      ]

instance FromJSON Usage where
  parseJSON = withObject "Usage" $ \o ->
    MkUsage
      <$> o .: "input_tokens"
      <*> o .: "output_tokens"
      <*> o .: "cache_creation_tokens"
      <*> o .: "cache_read_tokens"

instance ToJSON StopReason where
  toJSON = \case
    EndTurn -> "end_turn"
    MaxTokens -> "max_tokens"
    ToolUse -> "tool_use"
    StopSequence -> "stop_sequence"
    Refusal -> "refusal"
    PauseTurn -> "pause_turn"
    Other t -> object ["other" .= t]

instance FromJSON StopReason where
  parseJSON v = case v of
    String s -> case s of
      "end_turn" -> pure EndTurn
      "max_tokens" -> pure MaxTokens
      "tool_use" -> pure ToolUse
      "stop_sequence" -> pure StopSequence
      "refusal" -> pure Refusal
      "pause_turn" -> pure PauseTurn
      _ -> fail ("unknown stop reason: " <> show s)
    Object o -> Other <$> o .: "other"
    _ -> typeMismatch "StopReason" v

instance ToJSON Event where
  toJSON = \case
    TextDelta t -> tagged "text_delta" (toJSON t)
    Thinking t -> tagged "thinking" (toJSON t)
    ToolUseStart i n -> tagged "tool_use_start" (object ["id" .= i, "name" .= n])
    ToolUseDelta i j -> tagged "tool_use_delta" (object ["id" .= i, "json" .= j])
    ToolUseEnd i -> tagged "tool_use_end" (object ["id" .= i])
    ServerToolUse i n -> tagged "server_tool_use" (object ["id" .= i, "name" .= n])
    ServerToolResult i c -> tagged "server_tool_result" (object ["id" .= i, "content" .= c])
    Citation ct s -> tagged "citation" (object ["cited_text" .= ct, "source" .= s])
    Usage u -> tagged "usage" (toJSON u)
    Notice t -> tagged "notice" (toJSON t)
    Done sr -> tagged "done" (toJSON sr)
    where
      tagged :: Text -> Value -> Value
      tagged k d = object ["kind" .= k, "data" .= d]

instance FromJSON Event where
  parseJSON = withObject "Event" $ \o -> do
    kind <- o .: "kind" :: Parser Text
    let dat :: (FromJSON a) => Parser a
        dat = o .: "data"
        obj :: Parser Object
        obj = o .: "data"
    case kind of
      "text_delta" -> TextDelta <$> dat
      "thinking" -> Thinking <$> dat
      "tool_use_start" -> obj >>= \d -> ToolUseStart <$> d .: "id" <*> d .: "name"
      "tool_use_delta" -> obj >>= \d -> ToolUseDelta <$> d .: "id" <*> d .: "json"
      "tool_use_end" -> obj >>= \d -> ToolUseEnd <$> d .: "id"
      "server_tool_use" -> obj >>= \d -> ServerToolUse <$> d .: "id" <*> d .: "name"
      "server_tool_result" -> obj >>= \d -> ServerToolResult <$> d .: "id" <*> d .: "content"
      "citation" -> obj >>= \d -> Citation <$> d .: "cited_text" <*> d .: "source"
      "usage" -> Usage <$> dat
      "notice" -> Notice <$> dat
      "done" -> Done <$> dat
      _ -> fail ("unknown event kind: " <> show kind)
