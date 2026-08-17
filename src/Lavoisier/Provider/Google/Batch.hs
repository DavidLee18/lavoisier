-- | Gemini __Batch Mode__ (@models/{model}:batchGenerateContent@, ports Rust @lvz-google::batch@):
-- a 'Batch' backed by asynchronous bulk generation at ~50% of interactive pricing. Submit many
-- requests inline → poll the returned long-running operation until done → read the per-request
-- inline responses. The request-body builder and result parsers are pure (offline-tested); only the
-- submit\/poll\/fetch round-trips are live.
module Lavoisier.Provider.Google.Batch
  ( googleBatch,
    batchBody,
    parseBatchOp,
    parseResults,
  )
where

import Control.Concurrent (threadDelay)
import Control.Exception (SomeException, try)
import Data.Aeson (Value (..), decode, encode, object, (.=))
import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString.Lazy qualified as BL
import Data.Maybe (fromMaybe)
import Data.Scientific (toBoundedInteger)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding (encodeUtf8)
import Data.Vector qualified as V
import Data.Word (Word64)
import Lavoisier.Protocol.Batch
import Lavoisier.Protocol.Event (Usage (..), emptyUsage)
import Lavoisier.Protocol.Message (crModel)
import Lavoisier.Provider.Google (GoogleConfig (..), buildBody)
import Network.HTTP.Client
import Network.HTTP.Types (RequestHeaders)
import Network.HTTP.Types.Status (statusCode, statusIsSuccessful)

-- | Poll every 5 s, up to ~30 min, for the batch operation to finish.
pollIntervalMicros :: Int
pollIntervalMicros = 5000000

maxPolls :: Int
maxPolls = 360

-- | The 'Batch' backed by the Gemini Batch Mode API.
googleBatch :: GoogleConfig -> Batch
googleBatch cfg = Batch (runGoogleBatch cfg)

runGoogleBatch :: GoogleConfig -> [BatchTask] -> IO (Either BatchError [BatchItem])
runGoogleBatch _ [] = pure (Left (BatchError "run_batch: no tasks"))
runGoogleBatch cfg tasks@(t0 : _) = do
  -- All tasks in a Gemini batch share the URL's model; take it from the first request.
  let model = crModel (btRequest t0)
  created <- batchPost cfg ("models/" <> T.unpack model <> ":batchGenerateContent") (batchBody cfg tasks)
  case created of
    Left e -> pure (Left e)
    Right v ->
      let (name, _, _) = parseBatchOp v
       in if T.null name
            then pure (Left (BatchError "batch response had no operation name"))
            else poll name maxPolls
  where
    poll _ 0 = pure (Left (BatchError "batch did not finish within the poll window"))
    poll name n = do
      st <- batchGet cfg (T.unpack name)
      case st of
        Left e -> pure (Left e)
        Right v ->
          let (_, state, done) = parseBatchOp v
           in if done || state == "BATCH_STATE_SUCCEEDED"
                then do
                  r <- batchGet cfg (T.unpack name)
                  pure (fmap parseResults r)
                else threadDelay pollIntervalMicros >> poll name (n - 1)

-- --- pure body + result parsing --------------------------------------------------------------------

-- | The @{"batch":{"display_name":…,"input_config":{"requests":{"requests":[…]}}}}@ body. Each entry
-- is the normal generation body under @request@ plus a @metadata.key@ carrying the @custom_id@.
batchBody :: GoogleConfig -> [BatchTask] -> Value
batchBody cfg tasks =
  object
    [ "batch"
        .= object
          [ "display_name" .= String "lavoisier-batch",
            "input_config" .= object ["requests" .= object ["requests" .= inlined]]
          ]
    ]
  where
    inlined =
      [ object
          [ "request" .= buildBody (gcReasoningFloor cfg) (btRequest t),
            "metadata" .= object ["key" .= btId t]
          ]
      | t <- tasks
      ]

-- | Parse a batch long-running-operation object into @(name, state, done)@.
parseBatchOp :: Value -> (Text, Text, Bool)
parseBatchOp v =
  ( fromMaybe "" (lookStr "name" v),
    fromMaybe "" (lookStr "state" meta `orElse` (lookKey "batchStats" meta >>= lookStr "state")),
    lookBool "done" v
  )
  where
    meta = fromMaybe Null (lookKey "metadata" v)
    orElse (Just x) _ = Just x
    orElse Nothing y = y

-- | Parse a finished batch operation's inline responses into 'BatchItem's, correlated by @metadata.key@.
parseResults :: Value -> [BatchItem]
parseResults v = map parseOne inlined
  where
    inlined = case lookKey "response" v >>= lookKey "inlinedResponses" >>= lookKey "inlinedResponses" of
      Just (Array a) -> V.toList a
      _ -> []

parseOne :: Value -> BatchItem
parseOne v =
  let cid = fromMaybe "" (lookKey "metadata" v >>= lookStr "key")
   in case lookKey "error" v of
        Just err@(Object _) -> BatchItem cid "" emptyUsage (Just (fromMaybe "unknown error" (lookStr "message" err)))
        _ ->
          let response = fromMaybe Null (lookKey "response" v)
           in BatchItem cid (textOf response) (usageOf response) Nothing
  where
    textOf response = case lookKey "candidates" response of
      Just (Array a) | not (V.null a) -> partsText (V.head a)
      _ -> ""
    partsText cand = case lookKey "content" cand >>= lookKey "parts" of
      Just (Array parts) -> T.concat [t | p <- V.toList parts, Just t <- [lookStr "text" p]]
      _ -> ""
    usageOf response = case lookKey "usageMetadata" response of
      Just meta ->
        let prompt = num "promptTokenCount" meta
            cached = num "cachedContentTokenCount" meta
            candidates = num "candidatesTokenCount" meta
            thoughts = num "thoughtsTokenCount" meta
         in MkUsage (prompt - min prompt cached) (candidates + thoughts) 0 cached
      Nothing -> emptyUsage
    num k meta = maybe 0 id (lookKey k meta >>= toWord)
    toWord (Number n) = toBoundedInteger n :: Maybe Word64
    toWord _ = Nothing

-- --- HTTP round-trips ------------------------------------------------------------------------------

batchPost :: GoogleConfig -> String -> Value -> IO (Either BatchError Value)
batchPost cfg suffix body =
  batchSend cfg suffix (\r -> r {method = "POST", requestBody = RequestBodyLBS (encode body), requestHeaders = ("content-type", "application/json") : baseHeaders cfg})

batchGet :: GoogleConfig -> String -> IO (Either BatchError Value)
batchGet cfg suffix = batchSend cfg suffix (\r -> r {method = "GET", requestHeaders = baseHeaders cfg})

-- | Send a JSON round-trip against @/v1beta/<suffix>@.
batchSend :: GoogleConfig -> String -> (Request -> Request) -> IO (Either BatchError Value)
batchSend cfg suffix adjust = do
  er <- try (parseRequest (batchUrl cfg suffix)) :: IO (Either SomeException Request)
  case er of
    Left e -> pure (Left (BatchError (T.pack (show e))))
    Right req0 -> do
      eresp <- try (httpLbs (adjust req0) (gcManager cfg)) :: IO (Either HttpException (Response BL.ByteString))
      pure $ case eresp of
        Left e -> Left (BatchError (T.pack (show e)))
        Right resp
          | statusIsSuccessful (responseStatus resp) -> maybe (Left (BatchError "batch response was not JSON")) Right (decode (responseBody resp))
          | otherwise -> Left (BatchError ("batch API status " <> T.pack (show (statusCode (responseStatus resp)))))

batchUrl :: GoogleConfig -> String -> String
batchUrl cfg suffix = T.unpack (T.dropWhileEnd (== '/') (gcBaseUrl cfg)) <> "/v1beta/" <> suffix

baseHeaders :: GoogleConfig -> RequestHeaders
baseHeaders cfg = [("x-goog-api-key", encodeUtf8 (gcApiKey cfg))]

-- --- JSON helpers ----------------------------------------------------------------------------------

lookKey :: Text -> Value -> Maybe Value
lookKey k (Object o) = KM.lookup (K.fromText k) o
lookKey _ _ = Nothing

lookStr :: Text -> Value -> Maybe Text
lookStr k v = case lookKey k v of Just (String s) -> Just s; _ -> Nothing

lookBool :: Text -> Value -> Bool
lookBool k v = case lookKey k v of Just (Bool b) -> b; _ -> False
