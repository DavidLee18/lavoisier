{- | Incremental decoder for the Gemini @streamGenerateContent?alt=sse@ stream. Ported from Rust
@lvz-google@ @sse.rs@ as a pure state machine (feed with 'ssePush', end with 'sseEof').

Each chunk carries a @candidates[0].content.parts[]@ slice plus a cumulative @usageMetadata@:
text parts → 'TextDelta' (or 'Thinking' when @thought:true@); @functionCall@ → whole-args
'ToolUseStart'+'ToolUseDelta'+'ToolUseEnd' (the Gemini-3 @thoughtSignature@ is smuggled into the
call id as @call_N#sig@); @usageMetadata@ is last-wins; @finishReason@ → 'StopReason' (overridden
to 'ToolUse' when any call was emitted, since Gemini reports @STOP@ even then).
-}
module Lavoisier.Provider.Google.Sse (
    SseState,
    initSse,
    ssePush,
    sseEof,
    mapFinish,
)
where

import Data.Aeson (Value (..), decodeStrict, encode)
import Data.ByteString (ByteString)
import Data.Maybe (fromMaybe, listToMaybe)
import Data.Scientific (toBoundedInteger)
import Data.Text (Text)
import Data.Text.Encoding (decodeUtf8Lenient, encodeUtf8)
import Data.Word (Word64)

import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Text qualified as T

import Lavoisier.Protocol.Event (Event (..), StopReason (..), Usage (..), emptyUsage)
import Lavoisier.Protocol.Provider (ProviderError (..))

data SseState = SseState
    { gsBuf ∷ ByteString
    , gsUsage ∷ Usage
    , gsStop ∷ Maybe StopReason
    , gsToolCalls ∷ Word64
    , gsDone ∷ Bool
    }

initSse ∷ SseState
initSse = SseState BS.empty emptyUsage Nothing 0 False

ssePush ∷ SseState → ByteString → (SseState, [Either ProviderError Event])
ssePush st bytes = drainLines st {gsBuf = gsBuf st <> bytes} []
    where
        drainLines s acc = case BS.elemIndex 10 (gsBuf s) of
            Nothing → (s, acc)
            Just i →
                let (lineBs, rest) = BS.splitAt i (gsBuf s)
                    (s', evs) = handleLine s {gsBuf = BS.drop 1 rest} (T.strip (decodeUtf8Lenient lineBs))
                 in drainLines s' (acc <> evs)

sseEof ∷ SseState → [Either ProviderError Event]
sseEof st =
    let (st1, evs1) =
            if BS.null (gsBuf st)
                then (st, [])
                else handleLine st {gsBuf = BS.empty} (T.strip (decodeUtf8Lenient (gsBuf st)))
        (_, evs2) = emitFinal st1
     in evs1 <> evs2

handleLine ∷ SseState → Text → (SseState, [Either ProviderError Event])
handleLine s line = case T.stripPrefix "data:" line of
    Nothing → (s, [])
    Just rest →
        let payload = T.strip rest
         in if T.null payload
                then (s, [])
                else case decodeStrict (encodeUtf8 payload) ∷ Maybe Value of
                    Nothing → (s, [Left (PDecode "invalid SSE JSON")])
                    Just v → handleChunk s v

handleChunk ∷ SseState → Value → (SseState, [Either ProviderError Event])
handleChunk s0 v =
    let s1 = updateUsage s0 v
     in case look "candidates" v >>= asArray >>= listToMaybe of
            Nothing → (s1, [])
            Just cand →
                let parts = fromMaybe [] (look "content" cand >>= look "parts" >>= asArray)
                    (s2, evs) = foldl step (s1, []) parts
                    s3 = case look "finishReason" cand >>= asText of
                        Just r → s2 {gsStop = Just (mapFinish r)}
                        Nothing → s2
                 in (s3, evs)
    where
        step (st, acc) part = case look "functionCall" part of
            Just call →
                let n = gsToolCalls st
                    cid = case look "thoughtSignature" part >>= asText of
                        Just sig | not (T.null sig) → "call_" <> tshow n <> "#" <> sig
                        _ → "call_" <> tshow n
                    name = strOr "" (look "name" call)
                    args = fromMaybe (Object KM.empty) (look "args" call)
                 in ( st {gsToolCalls = n + 1}
                    , acc
                        <> [ Right (ToolUseStart cid name)
                           , Right (ToolUseDelta cid (jsonText args))
                           , Right (ToolUseEnd cid)
                           ]
                    )
            Nothing → case look "text" part >>= asText of
                Just txt →
                    let ev = if look "thought" part == Just (Bool True) then Thinking txt else TextDelta txt
                     in (st, acc <> [Right ev])
                Nothing → (st, acc)

updateUsage ∷ SseState → Value → SseState
updateUsage s v = case look "usageMetadata" v of
    Nothing → s
    Just _ →
        let prompt = numAt ["usageMetadata", "promptTokenCount"] v
            cached = numAt ["usageMetadata", "cachedContentTokenCount"] v
            candidates = numAt ["usageMetadata", "candidatesTokenCount"] v
            thoughts = numAt ["usageMetadata", "thoughtsTokenCount"] v
         in s {gsUsage = MkUsage (natSub prompt cached) (candidates + thoughts) 0 cached}

emitFinal ∷ SseState → (SseState, [Either ProviderError Event])
emitFinal s
    | gsDone s = (s, [])
    | otherwise =
        let stop
                | gsToolCalls s > 0 && (gsStop s == Nothing || gsStop s == Just EndTurn) = ToolUse
                | otherwise = fromMaybe EndTurn (gsStop s)
         in (s {gsDone = True}, [Right (Usage (gsUsage s)), Right (Done stop)])

mapFinish ∷ Text → StopReason
mapFinish = \case
    "STOP" → EndTurn
    "MAX_TOKENS" → MaxTokens
    other → Other other

-- --- helpers --------------------------------------------------------------------------------------

natSub ∷ Word64 → Word64 → Word64
natSub a b = if a >= b then a - b else 0

look ∷ Text → Value → Maybe Value
look k (Object o) = KM.lookup (K.fromText k) o
look _ _ = Nothing

asText ∷ Value → Maybe Text
asText (String s) = Just s
asText _ = Nothing

asW64 ∷ Value → Maybe Word64
asW64 (Number n) = toBoundedInteger n
asW64 _ = Nothing

asArray ∷ Value → Maybe [Value]
asArray (Array a) = Just (foldr (:) [] a)
asArray _ = Nothing

numAt ∷ [Text] → Value → Word64
numAt ks v = fromMaybe 0 (foldl (\mv k → mv >>= look k) (Just v) ks >>= asW64)

strOr ∷ Text → Maybe Value → Text
strOr d mv = fromMaybe d (mv >>= asText)

jsonText ∷ Value → Text
jsonText = decodeUtf8Lenient . BL.toStrict . encode

tshow ∷ Show a ⇒ a → Text
tshow = T.pack . show
