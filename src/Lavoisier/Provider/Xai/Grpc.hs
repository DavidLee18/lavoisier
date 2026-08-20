{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedLabels #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
-- grapesy requires per-service metadata @type instance@s to be declared where the RPC is used, so
-- these (and the ChatMetadata BuildMetadata/Default instances) are unavoidably orphan.
{-# OPTIONS_GHC -Wno-orphans #-}

-- | The xAI native __gRPC__ transport (ports Rust @lvz-xai::grpc@). Opens a TLS connection to
-- @api.x.ai@, calls the server-streaming @Chat.GetCompletionChunk@ via grapesy, and normalises each
-- streamed @GetChatCompletionChunk@ into the shared 'Event' stream. The proto-lens generated bindings
-- live in the internal @xai-proto@ library; grapesy is the gRPC client. Alternative to the
-- OpenAI-compatible HTTP transport in "Lavoisier.Provider.Xai".
module Lavoisier.Provider.Xai.Grpc
  ( xaiGrpcProvider,
    defaultXaiGrpcEndpoint,

    -- * Exposed for offline testing (pure request build + chunk decode)
    buildRequest,
    buildMessages,
    decodeChunk,
    emptyDecoder,
    mapFinish,
    usageFrom,
  )
where

import Control.Concurrent (forkIO)
import Control.Concurrent.Chan (Chan, newChan, readChan, writeChan)
import Control.Exception (SomeException, try)
import Data.Aeson (Value, encode)
import Data.ByteString.Lazy qualified as BL
import Data.Int (Int32)
import Data.Maybe (fromMaybe)
import Data.ProtoLens (defMessage)
import Data.ProtoLens.Labels ()
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding (decodeUtf8, encodeUtf8)
import Data.Word (Word64)
import Lavoisier.Protocol.Event
import Lavoisier.Protocol.Message
import Lavoisier.Protocol.Provider
import Lavoisier.Protocol.Stream (Producer (..))
import Lens.Family2 ((&), (.~), (^.))
import Network.GRPC.Client
import Network.GRPC.Common
import Network.GRPC.Common.Protobuf (Proto (..), Protobuf)
import Proto.Xai.Api.V1.Chat qualified as P
import Proto.Xai.Api.V1.Sample qualified as S
import Proto.Xai.Api.V1.Usage qualified as U

-- grapesy requires per-service metadata declarations. We send an @authorization@ header (wrapped in
-- 'ChatMetadata' — grapesy has no @BuildMetadata@ for a bare @[CustomMetadata]@) and read none back.
newtype ChatMetadata = ChatMetadata [CustomMetadata]
  deriving stock (Show)

instance BuildMetadata ChatMetadata where
  buildMetadata (ChatMetadata m) = m

instance Default ChatMetadata where
  def = ChatMetadata []

type instance RequestMetadata (Protobuf P.Chat meth) = ChatMetadata

type instance ResponseInitialMetadata (Protobuf P.Chat meth) = NoMetadata

type instance ResponseTrailingMetadata (Protobuf P.Chat meth) = NoMetadata

-- | The server-streaming completion RPC.
type ChunkRPC = Protobuf P.Chat "getCompletionChunk"

-- | The default xAI gRPC endpoint host.
defaultXaiGrpcEndpoint :: Text
defaultXaiGrpcEndpoint = "api.x.ai"

-- | Build a 'Provider' that streams over the xAI gRPC chat service. @host@ is the gRPC endpoint
-- (usually 'defaultXaiGrpcEndpoint'); the connection is TLS on port 443.
xaiGrpcProvider :: Text -> Text -> Provider
xaiGrpcProvider apiKey host =
  Provider
    { providerStream = grpcStream apiKey host,
      -- xAI caches server-side (no request markers); it exposes provider-side tools + vision, and
      -- supports parallel tool use.
      providerCapabilities = Capabilities False False True True True,
      providerCountTokens = \_ -> pure (Right Nothing)
    }

-- | Run the streaming call on a background thread, funnelling normalised events (and a terminal
-- 'Nothing') through a 'Chan' that backs the pull 'Producer' — grapesy's @withRPC@ is scoped, the
-- 'Producer' is pull-based, so the thread owns the call's lifetime.
grpcStream :: Text -> Text -> ChatRequest -> IO (Either ProviderError EventStream)
grpcStream apiKey host req = do
  chan <- newChan
  _ <- forkIO $ do
    r <- try (runCall apiKey host (buildRequest req) chan)
    case r of
      Left (e :: SomeException) -> do
        writeChan chan (Just (Left (PTransport (T.pack (show e)))))
        writeChan chan Nothing
      Right () -> pure ()
  pure (Right (Producer (readChan chan)))

runCall :: Text -> Text -> P.GetCompletionsRequest -> Chan (Maybe (Either ProviderError Event)) -> IO ()
runCall apiKey host preq chan =
  withConnection def server $ \conn ->
    withRPC conn params (Proxy @ChunkRPC) $ \call -> do
      sendFinalInput call (Proto preq)
      loop call emptyDecoder
  where
    server = ServerSecure (ValidateServer certStoreFromSystem) SslKeyLogNone (Address (T.unpack host) 443 Nothing)
    params = def {callRequestMetadata = ChatMetadata [CustomMetadata (AsciiHeader "authorization") ("Bearer " <> encodeUtf8 apiKey)]}
    emit = writeChan chan . Just . Right
    loop call st = do
      el <- recvNextOutputElem call
      case el of
        NextElem (Proto chunk) -> do
          let (evs, st') = decodeChunk st chunk
          mapM_ emit evs
          loop call st'
        NoNextElem -> do
          mapM_ emit (map ToolUseEnd (dsSeen st) <> [Done (fromMaybe EndTurn (dsStop st))])
          writeChan chan Nothing

-- --- streamed chunk → events (mirrors the Rust Decoder) --------------------------------------------

-- | Accumulated decode state: tool-call ids seen (first-seen order, closed at end), the last id (to
-- attribute argument-only chunks), and the pending stop reason.
data Decoder = Decoder
  { dsSeen :: [Text],
    dsLast :: Maybe Text,
    dsStop :: Maybe StopReason
  }

emptyDecoder :: Decoder
emptyDecoder = Decoder [] Nothing Nothing

decodeChunk :: Decoder -> P.GetChatCompletionChunk -> ([Event], Decoder)
decodeChunk st0 chunk =
  let usageEvs = maybe [] (\u -> [Usage (usageFrom u)]) (chunk ^. #maybe'usage)
      (outEvs, st') = foldl step ([], st0) (chunk ^. #outputs)
   in (usageEvs <> outEvs, st')
  where
    step (acc, st) output =
      let (delEvs, st') = maybe ([], st) (handleDelta st) (output ^. #maybe'delta)
          reason = output ^. #finishReason
          st'' = if reason == S.REASON_INVALID then st' else st' {dsStop = Just (mapFinish reason)}
       in (acc <> delEvs, st'')

-- | Text\/reasoning\/tool-call events from one output delta.
handleDelta :: Decoder -> P.Delta -> ([Event], Decoder)
handleDelta st delta =
  let textEvs = [TextDelta t | let t = delta ^. #content, not (T.null t)]
      thinkEvs = [Thinking t | let t = delta ^. #reasoningContent, not (T.null t)]
      (tcEvs, st') = foldl (\(acc, s) tc -> let (e, s') = handleToolCall s tc in (acc <> e, s')) ([], st) (delta ^. #toolCalls)
   in (textEvs <> thinkEvs <> tcEvs, st')

-- | A streamed tool call: open it on first sight (ToolUseStart), then stream its argument JSON.
handleToolCall :: Decoder -> P.ToolCall -> ([Event], Decoder)
handleToolCall st tc
  | T.null cid = ([], st)
  | otherwise =
      let (name, args) = maybe ("", "") (\f -> (f ^. #name, f ^. #arguments)) (tc ^. #maybe'function)
          (startEv, seen') =
            if cid `elem` dsSeen st
              then ([], dsSeen st)
              else ([ToolUseStart cid name], dsSeen st <> [cid])
          argEv = [ToolUseDelta cid args | not (T.null args)]
       in (startEv <> argEv, st {dsSeen = seen', dsLast = Just cid})
  where
    rawId = tc ^. #id
    cid = if T.null rawId then fromMaybe "" (dsLast st) else rawId

mapFinish :: S.FinishReason -> StopReason
mapFinish r = case r of
  S.REASON_STOP -> EndTurn
  S.REASON_MAX_LEN -> MaxTokens
  S.REASON_MAX_CONTEXT -> MaxTokens
  S.REASON_TOOL_CALLS -> ToolUse
  S.REASON_TIME_LIMIT -> Other "time_limit"
  _ -> EndTurn

-- | xAI's cumulative usage → 'Usage'. @prompt_tokens@ includes cached text tokens, so uncached input
-- is @prompt - cached@; xAI reports no cache /creation/.
usageFrom :: U.SamplingUsage -> Usage
usageFrom u =
  let cached = nn (u ^. #cachedPromptTextTokens)
      prompt = nn (u ^. #promptTokens)
   in MkUsage (prompt - min prompt cached) (nn (u ^. #completionTokens)) 0 cached
  where
    nn :: Int32 -> Word64
    nn n = fromIntegral (max 0 n)

-- --- normalised ChatRequest → GetCompletionsRequest ------------------------------------------------

buildRequest :: ChatRequest -> P.GetCompletionsRequest
buildRequest req =
  foldr
    (.)
    id
    ( concat
        [ [#reasoningEffort .~ effortOf l | Just l <- [crThinking req]],
          [#tools .~ map buildTool (crTools req) | not (null (crTools req))],
          [#toolChoice .~ buildToolChoice tc | Just tc <- [crToolChoice req]],
          [#temperature .~ realToFrac t | Just t <- [crTemperature req]],
          [#topP .~ realToFrac t | Just t <- [crTopP req]],
          [#stop .~ crStopSequences req | not (null (crStopSequences req))]
        ]
    )
    ( defMessage
        & #model .~ crModel req
        & #messages .~ buildMessages req
        & #maxTokens .~ fromIntegral (crMaxTokens req)
    )

buildMessages :: ChatRequest -> [P.Message]
buildMessages req =
  [msgOf P.ROLE_SYSTEM [textContent t] | Just (SystemPrompt t _) <- [crSystem req]]
    <> concatMap conv (crMessages req)
  where
    conv (Message User blocks) = buildUser blocks
    conv (Message Assistant blocks) = [buildAssistant blocks]

buildUser :: [ContentBlock] -> [P.Message]
buildUser blocks =
  [toolMsg tuid content | ToolResultBlock tuid content _ <- blocks]
    <> [msgOf P.ROLE_USER [textContent text] | let text = T.concat (concatMap userText blocks), not (T.null text)]
  where
    userText (TextBlock t _) = [t]
    userText (ThinkingBlock t) = [t]
    userText _ = []
    toolMsg tuid content =
      defMessage & #content .~ [textContent content] & #role .~ P.ROLE_TOOL & #toolCallId .~ tuid

buildAssistant :: [ContentBlock] -> P.Message
buildAssistant blocks =
  defMessage
    & #content .~ [textContent text | not (T.null text)]
    & #role .~ P.ROLE_ASSISTANT
    & #toolCalls .~ [funCall i n inp | ToolUseBlock i n inp <- blocks]
  where
    text = T.concat [t | TextBlock t _ <- blocks]
    funCall i n inp =
      defMessage & #id .~ i & #function .~ (defMessage & #name .~ n & #arguments .~ jsonText inp)

buildTool :: ToolDef -> P.Tool
buildTool td =
  defMessage
    & #function .~ (defMessage & #name .~ tdName td & #description .~ tdDescription td & #parameters .~ jsonText (tdSchema td))

buildToolChoice :: ToolChoice -> P.ToolChoice
buildToolChoice ChoiceAuto = defMessage & #mode .~ P.TOOL_MODE_AUTO
buildToolChoice ChoiceRequired = defMessage & #mode .~ P.TOOL_MODE_REQUIRED
buildToolChoice ChoiceNone = defMessage & #mode .~ P.TOOL_MODE_NONE
buildToolChoice (ChoiceTool n) = defMessage & #functionName .~ n

effortOf :: ThinkingLevel -> P.ReasoningEffort
effortOf ThinkOff = P.EFFORT_NONE
effortOf ThinkLow = P.EFFORT_LOW
effortOf ThinkMedium = P.EFFORT_MEDIUM
effortOf ThinkHigh = P.EFFORT_HIGH

textContent :: Text -> P.Content
textContent t = defMessage & #text .~ t

msgOf :: P.MessageRole -> [P.Content] -> P.Message
msgOf role cs = defMessage & #content .~ cs & #role .~ role

jsonText :: Value -> Text
jsonText = decodeUtf8 . BL.toStrict . encode
