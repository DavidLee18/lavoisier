{- | Incremental decoder for xAI's __Responses API__ (@POST \/v1\/responses@) SSE stream — the
Agent-Tools transport. A pure state machine, same shape as "Lavoisier.Provider.Xai.Sse" (feed with
'ssePush', end with 'sseEof').

Unlike @chat\/completions@, every frame carries a named event whose @type@ field repeats the @event:@
line, so the decoder switches on @type@ alone and ignores @event:@ lines. The vocabulary was
captured from a live stream (the docs cover only @chat\/completions@):

* @response.output_text.delta@ → 'TextDelta' (field @delta@)
* @response.reasoning_summary_text.delta@ → 'Thinking'. Note this is the reasoning /summary/, not
  raw reasoning — xAI streams no raw chain of thought.
* @response.output_item.added@ with @item.type == "web_search_call"@ → 'ServerToolUse', and the
  matching @response.\<tool\>_call.completed@ → 'ServerToolResult'. The item id correlates them.
* @response.output_text.annotation.added@ → 'Citation' (@annotation.url@).
* @response.completed@ → 'Usage' then 'Done'. Usage lives on @response.usage@ and names its fields
  @input_tokens@\/@output_tokens@, with @input_tokens_details.cached_tokens@ for the cache read.
  There is no cache-/creation/ counter: xAI caches server-side with no request markers, which is
  also why the transport declares no 'Lavoisier.Protocol.Provider.PromptCaching'.
* @response.incomplete@ and @response.failed@ are terminal too, and must not be mistaken for a
  normal end — an incomplete response that emitted a 'Done' 'EndTurn' would look like success.

Lifecycle frames (@response.created@, @response.in_progress@, @*.part.added@\/@.done@,
@*_call.in_progress@\/@.searching@) carry nothing the 'Event' stream models and are dropped.
-}
module Lavoisier.Provider.Xai.ResponsesSse (
    RespState,
    initResp,
    respPush,
    respEof,
    decodeRespEvent,
    parseRespUsage,
    serverToolItemName,
)
where

import Data.Aeson (Value (..), decodeStrict)
import Data.ByteString (ByteString)
import Data.Map.Strict (Map)
import Data.Scientific (toBoundedInteger)
import Data.Text (Text)
import Data.Text.Encoding (decodeUtf8Lenient, encodeUtf8)
import Data.Word (Word64)

import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Text qualified as T

import Lavoisier.Protocol.Event (Event (..), StopReason (..), Usage (..), emptyUsage)
import Lavoisier.Protocol.Provider (ProviderError (..))

{- | Decoder state: the line buffer, the open server-tool calls (item id → tool name, so the
completion can be labelled), and whether a terminal 'Done' has been emitted.
-}
data RespState = RespState
    { rsBuf ∷ ByteString
    , rsOpenTools ∷ Map Text Text
    , rsDone ∷ Bool
    }

initResp ∷ RespState
initResp = RespState BS.empty Map.empty False

-- | Feed a chunk of bytes; returns the advanced state and the events completed lines yielded.
respPush ∷ RespState → ByteString → (RespState, [Either ProviderError Event])
respPush st bytes = drainLines st {rsBuf = rsBuf st <> bytes} []
    where
        drainLines s acc = case BS.elemIndex 10 (rsBuf s) of
            Nothing → (s, acc)
            Just i →
                let (lineBs, rest) = BS.splitAt i (rsBuf s)
                    (s', evs) = handleLine s {rsBuf = BS.drop 1 rest} (T.strip (decodeUtf8Lenient lineBs))
                 in drainLines s' (acc <> evs)

{- | End the stream: flush any trailing partial line, then guarantee exactly one 'Done'. A stream
that ends without @response.completed@ (a dropped connection) still terminates, but as
@Other "incomplete"@ rather than 'EndTurn' — the turn did not finish, and saying it did would let
the agent loop treat a truncated answer as a final one.
-}
respEof ∷ RespState → [Either ProviderError Event]
respEof st =
    let (st1, evs1) =
            if BS.null (rsBuf st)
                then (st, [])
                else handleLine st {rsBuf = BS.empty} (T.strip (decodeUtf8Lenient (rsBuf st)))
        evs2 = [Right (Done (Other "incomplete")) | not (rsDone st1)]
     in evs1 <> evs2

handleLine ∷ RespState → Text → (RespState, [Either ProviderError Event])
handleLine st line = case T.stripPrefix "data:" line of
    -- `event:` lines duplicate the payload's own `type`, and blank lines separate frames.
    Nothing → (st, [])
    Just rest →
        let payload = T.strip rest
         in if T.null payload
                then (st, [])
                else case decodeStrict (encodeUtf8 payload) ∷ Maybe Value of
                    Nothing → (st, [Left (PDecode ("xai responses sse: bad json: " <> payload))])
                    Just v → decodeRespEvent st v

-- | Decode one frame. Exposed for tests, which feed frames directly rather than through the buffer.
decodeRespEvent ∷ RespState → Value → (RespState, [Either ProviderError Event])
decodeRespEvent st v = case objStr "type" v of
    Nothing → (st, [Left (PDecode "xai responses sse: frame has no type")])
    Just ty → case ty of
        "response.output_text.delta" → (st, delta TextDelta)
        "response.reasoning_summary_text.delta" → (st, delta Thinking)
        "response.output_item.added" → itemAdded
        "response.output_text.annotation.added" → (st, annotation)
        "response.completed" → terminal EndTurn
        "response.incomplete" → terminal (Other "incomplete")
        "response.failed" → failed
        _
            -- @response.<tool>_call.completed@. Matched by shape rather than a fixed tool list, so a
            -- tool xAI adds later still closes its open call instead of leaking one.
            | Just itemType ← completedToolItemType ty
            , Just name ← serverToolItemName itemType
            , Just itemId ← objStr "item_id" v →
                (st {rsOpenTools = Map.delete itemId (rsOpenTools st)}, [Right (ServerToolResult itemId name)])
            | otherwise → (st, [])
    where
        delta ctor = [Right (ctor d) | Just d ← [objStr "delta" v], not (T.null d)]

        annotation =
            [ Right (Citation title url)
            | Just a ← [objGet "annotation" v]
            , Just url ← [objStr "url" a]
            , let title = maybe "" id (objStr "title" a)
            ]

        itemAdded = case objGet "item" v of
            Just item
                | Just name ← serverToolItemName =<< objStr "type" item
                , Just itemId ← objStr "id" item →
                    (st {rsOpenTools = Map.insert itemId name (rsOpenTools st)}, [Right (ServerToolUse itemId name)])
            _ → (st, [])

        terminal stop
            | rsDone st = (st, [])
            | otherwise =
                let u = maybe emptyUsage parseRespUsage (objGet "response" v >>= objGet "usage")
                 in (st {rsDone = True}, [Right (Usage u), Right (Done stop)])

        failed
            | rsDone st = (st, [])
            | otherwise =
                let msg =
                        maybe
                            "xai responses: the provider reported a failed response"
                            id
                            (objGet "response" v >>= objGet "error" >>= objStr "message")
                 in (st {rsDone = True}, [Left (PApi 200 msg), Right (Done (Other "failed"))])

{- | The @item.type@ of a provider-run tool call, mapped to the name reported on the event stream.
'Nothing' for item types that are not tool calls (@reasoning@, @message@).
-}
serverToolItemName ∷ Text → Maybe Text
serverToolItemName = \case
    "web_search_call" → Just "web_search"
    "x_search_call" → Just "x_search"
    "code_interpreter_call" → Just "code_interpreter"
    "collections_search_call" → Just "collections_search"
    "document_search_call" → Just "document_search"
    "file_search_call" → Just "file_search"
    "image_generation_call" → Just "image_generation"
    "mcp_call" → Just "mcp"
    _ → Nothing

-- | @response.web_search_call.completed@ → @Just "web_search_call"@; anything else → 'Nothing'.
completedToolItemType ∷ Text → Maybe Text
completedToolItemType ty = do
    inner ← T.stripPrefix "response." ty
    T.stripSuffix ".completed" inner

{- | @response.usage@ → 'Usage'. @input_tokens@ is the full prompt including the cached part, and
@input_tokens_details.cached_tokens@ is the cache read; there is no cache-creation counter.
-}
parseRespUsage ∷ Value → Usage
parseRespUsage v =
    MkUsage
        { inputTokens = word "input_tokens" v
        , outputTokens = word "output_tokens" v
        , cacheCreationTokens = 0
        , cacheReadTokens = maybe 0 (word "cached_tokens") (objGet "input_tokens_details" v)
        }
    where
        word k o = maybe 0 id (objWord k o)

objGet ∷ Text → Value → Maybe Value
objGet k (Object o) = KM.lookup (K.fromText k) o
objGet _ _ = Nothing

objStr ∷ Text → Value → Maybe Text
objStr k v = case objGet k v of
    Just (String s) → Just s
    _ → Nothing

objWord ∷ Text → Value → Maybe Word64
objWord k v = case objGet k v of
    Just (Number n) → toBoundedInteger n
    _ → Nothing
