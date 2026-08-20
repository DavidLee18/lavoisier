-- | Incremental decoder for the Anthropic Messages SSE stream. Ported from Rust
-- @lvz-anthropic@ @sse.rs@ as a pure state machine: feed bytes with 'ssePush' and signal
-- end-of-stream with 'sseEof'; both return the events decoded so far.
--
-- Anthropic emits an @event:@ line plus a @data:@ JSON line per event, but the JSON itself carries
-- a @type@ field identical to the event name, so we dispatch purely on the @data@ payload and
-- ignore @event:@ lines. Byte chunks may split a line, so we buffer until a line is @\\n@-complete.
module Lavoisier.Provider.Anthropic.Sse
  ( SseState,
    initSse,
    ssePush,
    sseEof,
    -- exposed for testing
    mapStop,
    citationSource,
  )
where

import Data.Aeson (Value (..), decodeStrict, encode)
import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.IntMap.Strict (IntMap)
import Data.IntMap.Strict qualified as IntMap
import Data.Maybe (fromMaybe)
import Data.Scientific (toBoundedInteger)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding (decodeUtf8Lenient, encodeUtf8)
import Data.Word (Word64)
import Lavoisier.Protocol.Event
  ( Event (..),
    StopReason (..),
    Usage (..),
    emptyUsage,
  )
import Lavoisier.Protocol.Provider (ProviderError (..))

-- | The decoder's state: a partial-line buffer, the content-block-index → tool-use-id map (to
-- correlate @input_json_delta@s and the block stop), the accumulating usage, the stop reason, and
-- whether the terminal usage/done pair has been emitted.
data SseState = SseState
  { ssBuf :: ByteString,
    ssToolBlocks :: IntMap Text,
    ssUsage :: Usage,
    ssStop :: Maybe StopReason,
    ssDone :: Bool
  }

initSse :: SseState
initSse = SseState BS.empty IntMap.empty emptyUsage Nothing False

-- | Feed a byte chunk; returns the updated state and any events completed by it.
ssePush :: SseState -> ByteString -> (SseState, [Either ProviderError Event])
ssePush st bytes = drainLines st {ssBuf = ssBuf st <> bytes} []
  where
    drainLines s acc =
      case BS.elemIndex 10 (ssBuf s) of -- 10 = '\n'
        Nothing -> (s, acc)
        Just i ->
          let (lineBs, rest) = BS.splitAt i (ssBuf s)
              line = T.strip (decodeUtf8Lenient lineBs)
              (s', evs) = handleLine s {ssBuf = BS.drop 1 rest} line
           in drainLines s' (acc <> evs)

-- | Signal end-of-stream: flush any trailing partial line, then emit the terminal usage/done pair
-- if a @message_stop@ has not already done so.
sseEof :: SseState -> [Either ProviderError Event]
sseEof st =
  let (st1, evs1) =
        if BS.null (ssBuf st)
          then (st, [])
          else handleLine st {ssBuf = BS.empty} (T.strip (decodeUtf8Lenient (ssBuf st)))
      (_, evs2) = emitFinal st1
   in evs1 <> evs2

handleLine :: SseState -> Text -> (SseState, [Either ProviderError Event])
handleLine s line =
  case T.stripPrefix "data:" line of
    Nothing -> (s, []) -- event: lines, comments, blank separators
    Just rest ->
      let payload = T.strip rest
       in if T.null payload
            then (s, [])
            else case decodeStrict (encodeUtf8 payload) :: Maybe Value of
              Nothing -> (s, [Left (PDecode "invalid SSE JSON")])
              Just v -> handleEvent s v

handleEvent :: SseState -> Value -> (SseState, [Either ProviderError Event])
handleEvent s v = case path ["type"] v >>= asText of
  Just "message_start" ->
    let u = ssUsage s
        u' =
          u
            { inputTokens = inputTokens u + numAt ["message", "usage", "input_tokens"] v,
              cacheCreationTokens =
                cacheCreationTokens u + numAt ["message", "usage", "cache_creation_input_tokens"] v,
              cacheReadTokens =
                cacheReadTokens u + numAt ["message", "usage", "cache_read_input_tokens"] v
            }
     in (s {ssUsage = u'}, [])
  Just "content_block_start" -> blockStart s v
  Just "content_block_delta" -> blockDelta s v
  Just "content_block_stop" ->
    let idx = intAt ["index"] v
     in case IntMap.lookup idx (ssToolBlocks s) of
          Just tid -> (s {ssToolBlocks = IntMap.delete idx (ssToolBlocks s)}, [Right (ToolUseEnd tid)])
          Nothing -> (s, [])
  Just "message_delta" ->
    let s1 = case path ["delta", "stop_reason"] v >>= asText of
          Just r -> s {ssStop = Just (mapStop r)}
          Nothing -> s
        s2 = case path ["usage", "output_tokens"] v >>= asW64 of
          Just o -> s1 {ssUsage = (ssUsage s1) {outputTokens = o}}
          Nothing -> s1
     in (s2, [])
  Just "message_stop" -> emitFinal s
  Just "error" ->
    let msg = fromMaybe "unknown stream error" (path ["error", "message"] v >>= asText)
        (s', evs) = emitFinal s
     in (s', Left (PTransport ("anthropic stream error: " <> msg)) : evs)
  _ -> (s, []) -- ping and anything unrecognised

blockStart :: SseState -> Value -> (SseState, [Either ProviderError Event])
blockStart s v =
  let cb = path ["content_block"] v
   in case cb >>= objLook "type" >>= asText of
        Just "tool_use" ->
          let idx = intAt ["index"] v
              tid = strOr "" (cb >>= objLook "id")
              nm = strOr "" (cb >>= objLook "name")
           in (s {ssToolBlocks = IntMap.insert idx tid (ssToolBlocks s)}, [Right (ToolUseStart tid nm)])
        Just "server_tool_use" ->
          (s, [Right (ServerToolUse (strOr "" (cb >>= objLook "id")) (strOr "" (cb >>= objLook "name")))])
        Just t
          | "_tool_result" `T.isSuffixOf` t ->
              let tid = strOr "" (cb >>= objLook "tool_use_id")
                  content = maybe "" jsonText (cb >>= objLook "content")
               in (s, [Right (ServerToolResult tid content)])
        _ -> (s, [])

blockDelta :: SseState -> Value -> (SseState, [Either ProviderError Event])
blockDelta s v =
  let idx = intAt ["index"] v
      delta = path ["delta"] v
   in case delta >>= objLook "type" >>= asText of
        Just "text_delta" ->
          maybe (s, []) (\t -> (s, [Right (TextDelta t)])) (delta >>= objLook "text" >>= asText)
        Just "thinking_delta" ->
          maybe (s, []) (\t -> (s, [Right (Thinking t)])) (delta >>= objLook "thinking" >>= asText)
        Just "input_json_delta" ->
          case (IntMap.lookup idx (ssToolBlocks s), delta >>= objLook "partial_json" >>= asText) of
            (Just tid, Just j) -> (s, [Right (ToolUseDelta tid j)])
            _ -> (s, [])
        Just "citations_delta" ->
          let c = delta >>= objLook "citation"
              ct = strOr "" (c >>= objLook "cited_text")
              src = maybe "" citationSource c
           in (s, [Right (Citation ct src)])
        _ -> (s, [])

emitFinal :: SseState -> (SseState, [Either ProviderError Event])
emitFinal s
  | ssDone s = (s, [])
  | otherwise =
      ( s {ssDone = True},
        [Right (Usage (ssUsage s)), Right (Done (fromMaybe EndTurn (ssStop s)))]
      )

-- | Derive a human-readable source label from an Anthropic citation object.
citationSource :: Value -> Text
citationSource c =
  case [t | key <- ["document_title", "title", "url"], Just t <- [objLook key c >>= asText], not (T.null t)] of
    (t : _) -> t
    [] -> case objLook "document_index" c >>= asW64 of
      Just idx -> "document " <> T.pack (show idx)
      Nothing -> ""

mapStop :: Text -> StopReason
mapStop = \case
  "end_turn" -> EndTurn
  "max_tokens" -> MaxTokens
  "tool_use" -> ToolUse
  "stop_sequence" -> StopSequence
  "refusal" -> Refusal
  "pause_turn" -> PauseTurn
  other -> Other other

-- --- tiny JSON accessors ---------------------------------------------------------------------------

objLook :: Text -> Value -> Maybe Value
objLook k (Object o) = KM.lookup (K.fromText k) o
objLook _ _ = Nothing

path :: [Text] -> Value -> Maybe Value
path ks v0 = foldl (\mv k -> mv >>= objLook k) (Just v0) ks

asText :: Value -> Maybe Text
asText (String s) = Just s
asText _ = Nothing

asW64 :: Value -> Maybe Word64
asW64 (Number n) = toBoundedInteger n
asW64 _ = Nothing

asInt :: Value -> Maybe Int
asInt (Number n) = toBoundedInteger n
asInt _ = Nothing

numAt :: [Text] -> Value -> Word64
numAt ks v = fromMaybe 0 (path ks v >>= asW64)

intAt :: [Text] -> Value -> Int
intAt ks v = fromMaybe 0 (path ks v >>= asInt)

strOr :: Text -> Maybe Value -> Text
strOr d mv = fromMaybe d (mv >>= asText)

jsonText :: Value -> Text
jsonText = decodeUtf8Lenient . BL.toStrict . encode
