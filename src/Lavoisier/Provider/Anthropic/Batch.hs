{- | Anthropic __Message Batches__ API (ports Rust @lvz-anthropic::batch@): a 'Batch' backed by
@/v1/messages/batches@ — submit → poll → fetch, at ~50% token cost. Powers the @batch_edit@ tool.
The request-body builder and JSONL result parser are pure (offline-tested); only the submit/poll/
fetch round-trips are live.
-}
module Lavoisier.Provider.Anthropic.Batch (
    anthropicBatch,
    batchRequestsBody,
    parseResults,
    parseResultLine,
)
where

import Control.Concurrent (threadDelay)
import Control.Exception (SomeException, try)
import Data.Aeson (Value (..), decode, decodeStrict, encode, object, (.=))
import Data.Map.Strict (Map)
import Data.Maybe (mapMaybe)
import Data.Scientific (toBoundedInteger)
import Data.Text (Text)
import Data.Text.Encoding (decodeUtf8Lenient, encodeUtf8)
import Data.Word (Word64)
import Network.HTTP.Client
import Network.HTTP.Types (RequestHeaders)
import Network.HTTP.Types.Status (statusCode, statusIsSuccessful)

import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Vector qualified as V

import Lavoisier.Protocol.Batch
import Lavoisier.Protocol.Event (Usage (..), emptyUsage)
import Lavoisier.Protocol.Provider (negotiate, providerErrorText)
import Lavoisier.Provider.Anthropic (AnthropicCaps, AnthropicConfig (..), buildBody)

anthropicVersion ∷ BS.ByteString
anthropicVersion = "2023-06-01"

-- | Poll every 5 s, up to ~30 min, for the batch to end.
pollIntervalMicros ∷ Int
pollIntervalMicros = 5000000

maxPolls ∷ Int
maxPolls = 360

-- | The 'Batch' backed by the Anthropic Message Batches API.
anthropicBatch ∷ AnthropicConfig → Batch
anthropicBatch cfg = Batch (runAnthropicBatch cfg)

runAnthropicBatch ∷ AnthropicConfig → [BatchTask] → IO (Either BatchError [BatchItem])
runAnthropicBatch cfg tasks = case batchRequestsBody (acExtendedTtl cfg) tasks of
    Left e → pure (Left e)
    Right reqBody → do
        created ← batchPost cfg "" reqBody
        case created >>= idOf of
            Left e → pure (Left e)
            Right bid → fmap (fmap (attachNotices (batchNotices tasks))) (poll bid maxPolls)
    where
        poll _ 0 = pure (Left (BatchError "batch did not finish within the poll window"))
        poll bid n = do
            st ← batchGet cfg ("/" <> bid)
            case st of
                Left e → pure (Left e)
                Right v
                    | statusOf v == Just "ended" → fmap parseResults <$> batchResults cfg bid
                    | otherwise → threadDelay pollIntervalMicros >> poll bid (n - 1)
        idOf v = maybe (Left (BatchError "batch response had no id")) Right (lookStr "id" v)
        statusOf v = lookStr "processing_status" v

-- --- pure body + result parsing --------------------------------------------------------------------

{- | The @{"requests":[{"custom_id":…,"params":…}]}@ body. Each request's @params@ is the normal
(non-streaming) message body with @stream@ stripped (the batch endpoint rejects it).

Every task is negotiated against 'AnthropicCaps' first, exactly as the streaming path is: a batch
is still a request to this provider, and a whole batch that would be rejected mid-flight is worth
refusing at submit time.
-}
batchRequestsBody ∷ Bool → [BatchTask] → Either BatchError Value
batchRequestsBody ttl tasks = do
    params ← traverse negotiated tasks
    pure (object ["requests" .= [object ["custom_id" .= btId t, "params" .= p] | (t, p) ← zip tasks params]])
    where
        negotiated t = case negotiate @AnthropicCaps (btRequest t) of
            (_, Left e) → Left (BatchError ("batch task \"" <> btId t <> "\": " <> providerErrorText e))
            (_, Right nreq) → Right (stripStream (buildBody ttl nreq))
        stripStream (Object o) = Object (KM.delete "stream" o)
        stripStream v = v

{- | The per-task capability notices raised at submit time, keyed by @custom_id@. Computed from the
same 'negotiate' call the body builder makes; recomputing is cheaper than threading it through the
poll loop, and 'negotiate' is pure.
-}
batchNotices ∷ [BatchTask] → Map Text [Text]
batchNotices tasks = Map.fromList [(btId t, fst (negotiate @AnthropicCaps (btRequest t))) | t ← tasks]

-- | Parse the JSONL results stream (one result object per line) into 'BatchItem's.
parseResults ∷ Text → [BatchItem]
parseResults = map parseResultLine . mapMaybe (decodeStrict . encodeUtf8) . filter (not . T.null . T.strip) . T.lines

-- | One result line → 'BatchItem' (succeeded → text + usage; errored\/canceled\/expired → error).
parseResultLine ∷ Value → BatchItem
parseResultLine v =
    let cid = maybe "" id (lookStr "custom_id" v)
        result = maybe Null id (lookKey "result" v)
     in case lookStr "type" result of
            Just "succeeded" →
                let msg = maybe Null id (lookKey "message" result)
                 in batchItem cid (textOf msg) (usageOf msg) Nothing
            Just "errored" → batchItem cid "" emptyUsage (Just (maybe "unknown" id (lookKey "error" result >>= lookStr "type")))
            Just "canceled" → batchItem cid "" emptyUsage (Just "canceled")
            _ → batchItem cid "" emptyUsage (Just "expired")
    where
        textOf msg = case lookKey "content" msg of
            Just (Array a) → T.concat [t | b ← V.toList a, lookStr "type" b == Just "text", Just t ← [lookStr "text" b]]
            _ → ""
        usageOf msg = case lookKey "usage" msg of
            Just u → MkUsage (num "input_tokens" u) (num "output_tokens" u) (num "cache_creation_input_tokens" u) (num "cache_read_input_tokens" u)
            Nothing → emptyUsage
        num k u = maybe 0 id (lookKey k u >>= toWord)
        toWord (Number n) = toBoundedInteger n ∷ Maybe Word64
        toWord _ = Nothing

-- --- HTTP round-trips ------------------------------------------------------------------------------

batchPost ∷ AnthropicConfig → Text → Value → IO (Either BatchError Value)
batchPost cfg suffix body =
    batchSend cfg suffix (\r → r {method = "POST", requestBody = RequestBodyLBS (encode body), requestHeaders = ("content-type", "application/json") : baseHeaders cfg})

batchGet ∷ AnthropicConfig → Text → IO (Either BatchError Value)
batchGet cfg suffix = batchSend cfg suffix (\r → r {method = "GET", requestHeaders = baseHeaders cfg})

-- | Send a JSON round-trip against @/v1/messages/batches<suffix>@.
batchSend ∷ AnthropicConfig → Text → (Request → Request) → IO (Either BatchError Value)
batchSend cfg suffix adjust = do
    er ← try (parseRequest (batchUrl cfg suffix)) ∷ IO (Either SomeException Request)
    case er of
        Left e → pure (Left (BatchError (T.pack (show e))))
        Right req0 → do
            eresp ← try (httpLbs (adjust req0) (acManager cfg)) ∷ IO (Either HttpException (Response BL.ByteString))
            pure $ case eresp of
                Left e → Left (BatchError (T.pack (show e)))
                Right resp
                    | statusIsSuccessful (responseStatus resp) → maybe (Left (BatchError "batch response was not JSON")) Right (decode (responseBody resp))
                    | otherwise → Left (BatchError ("batch API status " <> T.pack (show (statusCode (responseStatus resp)))))

-- | Fetch a finished batch's JSONL results as text.
batchResults ∷ AnthropicConfig → Text → IO (Either BatchError Text)
batchResults cfg bid = do
    er ← try (parseRequest (batchUrl cfg ("/" <> bid <> "/results"))) ∷ IO (Either SomeException Request)
    case er of
        Left e → pure (Left (BatchError (T.pack (show e))))
        Right req0 → do
            eresp ← try (httpLbs (req0 {method = "GET", requestHeaders = baseHeaders cfg}) (acManager cfg)) ∷ IO (Either HttpException (Response BL.ByteString))
            pure $ case eresp of
                Left e → Left (BatchError (T.pack (show e)))
                Right resp
                    | statusIsSuccessful (responseStatus resp) → Right (decodeLenient (responseBody resp))
                    | otherwise → Left (BatchError ("batch results status " <> T.pack (show (statusCode (responseStatus resp)))))

batchUrl ∷ AnthropicConfig → Text → String
batchUrl cfg suffix = T.unpack (T.dropWhileEnd (== '/') (acBaseUrl cfg) <> "/v1/messages/batches" <> suffix)

baseHeaders ∷ AnthropicConfig → RequestHeaders
baseHeaders cfg = [("x-api-key", encodeUtf8 (acApiKey cfg)), ("anthropic-version", anthropicVersion)]

decodeLenient ∷ BL.ByteString → Text
decodeLenient = decodeUtf8Lenient . BL.toStrict

-- --- JSON helpers ----------------------------------------------------------------------------------

lookKey ∷ Text → Value → Maybe Value
lookKey k (Object o) = KM.lookup (K.fromText k) o
lookKey _ _ = Nothing

lookStr ∷ Text → Value → Maybe Text
lookStr k v = case lookKey k v of Just (String s) → Just s; _ → Nothing
