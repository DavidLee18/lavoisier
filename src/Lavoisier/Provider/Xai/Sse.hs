{- | Incremental decoder for xAI's OpenAI-compatible @chat/completions@ SSE stream. Ported from Rust
@lvz-xai@ @http.rs@ as a pure state machine (feed with 'ssePush', end with 'sseEof').

Each @data:@ line carries a chunk: @choices[0].delta.content@ → 'TextDelta'; streamed
@delta.tool_calls@ are reassembled by their @index@ into 'ToolUseStart'\/'ToolUseDelta', closed as
'ToolUseEnd' when @finish_reason@ arrives (in index order); @usage@ → 'Usage'; @finish_reason@ →
'StopReason'. A terminal @[DONE]@ (or EOF) emits exactly one 'Done'.
-}
module Lavoisier.Provider.Xai.Sse (
    SseState,
    initSse,
    ssePush,
    sseEof,
    mapStop,
)
where

import Data.Aeson (Value (..), decodeStrict)
import Data.ByteString (ByteString)
import Data.Map.Strict (Map)
import Data.Maybe (fromMaybe, listToMaybe)
import Data.Scientific (toBoundedInteger)
import Data.Text (Text)
import Data.Text.Encoding (decodeUtf8Lenient, encodeUtf8)
import Data.Word (Word64)

import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Vector qualified as V

import Lavoisier.Protocol.Event (Event (..), StopReason (..), Usage (..), emptyUsage)
import Lavoisier.Protocol.Provider (ProviderError (..))

data SseState = SseState
    { xsBuf ∷ ByteString
    , xsToolIds ∷ Map Int Text
    -- ^ tool-call index → emitted tool id, for correlating argument deltas and closing in order.
    , xsStop ∷ Maybe StopReason
    , xsDone ∷ Bool
    }

initSse ∷ SseState
initSse = SseState BS.empty Map.empty Nothing False

-- | Feed a chunk of bytes; returns the advanced state and any events completed lines yielded.
ssePush ∷ SseState → ByteString → (SseState, [Either ProviderError Event])
ssePush st bytes = drainLines st {xsBuf = xsBuf st <> bytes} []
    where
        drainLines s acc = case BS.elemIndex 10 (xsBuf s) of
            Nothing → (s, acc)
            Just i →
                let (lineBs, rest) = BS.splitAt i (xsBuf s)
                    (s', evs) = handleLine s {xsBuf = BS.drop 1 rest} (T.strip (decodeUtf8Lenient lineBs))
                 in drainLines s' (acc <> evs)

-- | End the stream: flush any trailing partial line, then guarantee exactly one 'Done'.
sseEof ∷ SseState → [Either ProviderError Event]
sseEof st =
    let (st1, evs1) =
            if BS.null (xsBuf st)
                then (st, [])
                else handleLine st {xsBuf = BS.empty} (T.strip (decodeUtf8Lenient (xsBuf st)))
        (_, evs2) = emitDone st1
     in evs1 <> evs2

handleLine ∷ SseState → Text → (SseState, [Either ProviderError Event])
handleLine st line = case T.stripPrefix "data:" line of
    Nothing → (st, [])
    Just rest →
        let payload = T.strip rest
         in if T.null payload
                then (st, [])
                else
                    if payload == "[DONE]"
                        then emitDone st
                        else case decodeStrict (encodeUtf8 payload) ∷ Maybe Value of
                            Nothing → (st, [Left (PDecode ("xai sse: bad json: " <> payload))])
                            Just chunk → processChunk st chunk

processChunk ∷ SseState → Value → (SseState, [Either ProviderError Event])
processChunk st chunk =
    let usageEvs = case objGet "usage" chunk of
            Just u → [Right (Usage (parseUsage u))]
            Nothing → []
     in case listToMaybe (arrGet "choices" chunk) of
            Nothing → (st, usageEvs)
            Just choice →
                let delta = fromMaybe Null (objGet "delta" choice)
                    contentEvs = case objStr "content" delta of
                        Just c | not (T.null c) → [Right (TextDelta c)]
                        _ → []
                    (st1, tcEvs) = foldl stepTc (st, []) (arrGet "tool_calls" delta)
                    (st2, finishEvs) = case objStr "finish_reason" choice of
                        Just r → closeTools st1 {xsStop = Just (mapStop r)}
                        Nothing → (st1, [])
                 in (st2, usageEvs <> contentEvs <> tcEvs <> finishEvs)
    where
        stepTc (s, acc) tc = let (s', e) = handleToolCallDelta s tc in (s', acc <> e)

{- | Fold one streamed @tool_calls@ delta: the first delta for an index carries the id (and usually
the name) → 'ToolUseStart'; later deltas carry @arguments@ → 'ToolUseDelta'.
-}
handleToolCallDelta ∷ SseState → Value → (SseState, [Either ProviderError Event])
handleToolCallDelta s tc =
    let idx = fromMaybe 0 (objInt "index" tc)
        mfunc = objGet "function" tc
        (s1, startEvs) = case objStr "id" tc of
            Just tid →
                ( s {xsToolIds = Map.insert idx tid (xsToolIds s)}
                , [Right (ToolUseStart tid (fromMaybe "" (mfunc >>= objStr "name")))]
                )
            Nothing → (s, [])
        argEvs = case mfunc >>= objStr "arguments" of
            Just args
                | not (T.null args) → case Map.lookup idx (xsToolIds s1) of
                    Just tid → [Right (ToolUseDelta tid args)]
                    Nothing → []
            _ → []
     in (s1, startEvs <> argEvs)

-- | Emit a 'ToolUseEnd' for every open tool call, in index order, and clear the map.
closeTools ∷ SseState → (SseState, [Either ProviderError Event])
closeTools s = (s {xsToolIds = Map.empty}, [Right (ToolUseEnd tid) | tid ← Map.elems (xsToolIds s)])

emitDone ∷ SseState → (SseState, [Either ProviderError Event])
emitDone s
    | xsDone s = (s, [])
    | otherwise =
        let (s1, closeEvs) = closeTools s -- safety net if no finish_reason was seen
         in (s1 {xsDone = True}, closeEvs <> [Right (Done (fromMaybe EndTurn (xsStop s1)))])

-- | Map an OpenAI @finish_reason@ onto a 'StopReason'.
mapStop ∷ Text → StopReason
mapStop "stop" = EndTurn
mapStop "length" = MaxTokens
mapStop "tool_calls" = ToolUse
mapStop other = Other other

parseUsage ∷ Value → Usage
parseUsage u = emptyUsage {inputTokens = num "prompt_tokens", outputTokens = num "completion_tokens"}
    where
        num k = fromMaybe 0 (objWord k u)

-- --- tiny JSON helpers -----------------------------------------------------------------------------

objGet ∷ Text → Value → Maybe Value
objGet k (Object o) = KM.lookup (K.fromText k) o
objGet _ _ = Nothing

objStr ∷ Text → Value → Maybe Text
objStr k v = case objGet k v of
    Just (String s) → Just s
    _ → Nothing

objInt ∷ Text → Value → Maybe Int
objInt k v = case objGet k v of
    Just (Number n) → toBoundedInteger n
    _ → Nothing

objWord ∷ Text → Value → Maybe Word64
objWord k v = case objGet k v of
    Just (Number n) → Just (truncate n)
    _ → Nothing

arrGet ∷ Text → Value → [Value]
arrGet k v = case objGet k v of
    Just (Array a) → V.toList a
    _ → []
