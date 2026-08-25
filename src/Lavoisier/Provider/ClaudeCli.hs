{-# LANGUAGE DataKinds #-}

-- | @Lavoisier.Provider.ClaudeCli@ — an __optional__ 'Provider' that rides Claude Code's
-- @claude -p@ (subscription OAuth) instead of the Anthropic API. Ported from Rust @lvz-claude-cli@.
--
-- It spawns @claude -p --output-format stream-json@, feeds the rendered conversation on stdin, and
-- normalises the newline-delimited JSON event stream into 'Event's. @claude -p@ is itself a full
-- agent (it runs its own tools), so this adapter treats it as an opaque completion: it surfaces
-- assistant __text__ and __thinking__ and the final __usage__, and ignores the internal tool traffic.
--
-- Caveats, all reflected in 'Capabilities' (which advertises none): no prompt caching (subscription
-- tokens can't use @cache_control@); capped by the monthly Agent SDK credit then API rates;
-- policy-fragile. __Personal \/ low-volume convenience only__ — off by default, built only when
-- @--provider claude-cli@ is chosen explicitly.
--
-- Not live-verified here (needs a @claude@ install + a subscription); the stream-json → 'Event'
-- mapping is unit-tested via the pure 'Decoder'.
module Lavoisier.Provider.ClaudeCli
  ( claudeCliFromEnv,
    claudeCliProvider,
    ClaudeCliConfig (..),
    -- exposed for testing
    renderPrompt,
    Decoder,
    initDecoder,
    pushLine,
    eofDecoder,
  )
where

import Control.Exception (IOException, SomeException, try)
import Data.Aeson (Value (..), decodeStrict)
import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BS8
import Data.ByteString.Lazy qualified as BL
import Data.IORef
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding (decodeUtf8Lenient, encodeUtf8)
import Data.Vector qualified as V
import Data.Word (Word64)
import Lavoisier.Domain (ModelId (..))
import Lavoisier.Protocol.Event (Event (..), StopReason (..), Usage (..))
import Lavoisier.Protocol.Message (ChatRequest (..), Role (..), SystemPrompt (..), messageText, msgRole)
import Lavoisier.Protocol.Provider (EventStream, Provider (..), ProviderError (..), declare, negotiatedRequest, withNegotiated)
import Lavoisier.Protocol.Stream (Producer (..))
import System.Environment (lookupEnv)
import System.IO (Handle)
import System.IO.Error (isEOFError)
import System.Process.Typed
  ( Process,
    byteStringInput,
    createPipe,
    getStdout,
    nullStream,
    proc,
    setStderr,
    setStdin,
    setStdout,
    startProcess,
    stopProcess,
  )

defaultBin :: Text
defaultBin = "claude"

-- | Runtime configuration: which @claude@ binary to spawn.
newtype ClaudeCliConfig = ClaudeCliConfig {ccBin :: Text}

-- | Construct the provider, taking the binary from @CLAUDE_CLI_BIN@ (default @claude@ on @PATH@).
-- Infallible today; mirrors the other providers' @fromEnv@ for the CLI's uniform build path.
claudeCliFromEnv :: IO (Either ProviderError Provider)
claudeCliFromEnv = do
  bin <- maybe defaultBin T.pack <$> lookupEnv "CLAUDE_CLI_BIN"
  pure (Right (claudeCliProvider (ClaudeCliConfig bin)))

-- | The 'Provider' record backed by @claude -p@. Advertises no optional 'Capabilities' (the
-- subscription path has no caching, and @claude -p@ runs its own tools opaquely), and offers no
-- native token counting.
-- | @claude -p@ advertises nothing optional: the subscription path has no caching, it runs its own
-- tools opaquely, it has no image input, and its thinking is not caller-controllable. Note the last
-- one means \"cannot be /asked/ to think\" — the subprocess reasons on its own schedule and this
-- adapter does emit the resulting 'Lavoisier.Protocol.Event.Thinking' events.
type ClaudeCliCaps = '[]

claudeCliProvider :: ClaudeCliConfig -> Provider
claudeCliProvider cfg =
  Provider
    { providerStream = claudeCliStream cfg,
      providerCapabilities = declare @ClaudeCliCaps,
      providerCountTokens = \_ -> pure (Right Nothing)
    }

-- --- streaming -------------------------------------------------------------------------------------

claudeCliStream :: ClaudeCliConfig -> ChatRequest -> IO (Either ProviderError EventStream)
claudeCliStream cfg chatReq = withNegotiated @ClaudeCliCaps chatReq $ \nreq -> do
  let req = negotiatedRequest nreq
      prompt = renderPrompt req
      sysArgs = maybe [] (\sp -> ["--append-system-prompt", T.unpack (spText sp)]) (crSystem req)
      args =
        [ "-p",
          "--output-format",
          "stream-json",
          "--verbose",
          "--include-partial-messages",
          "--model",
          T.unpack (unModelId (crModel req))
        ]
          <> sysArgs
      pc =
        setStdin (byteStringInput (BL.fromStrict (encodeUtf8 prompt)))
          . setStdout createPipe
          . setStderr nullStream
          $ proc (T.unpack (ccBin cfg)) args
  r <- try (startProcess pc) :: IO (Either SomeException (Process () Handle ()))
  case r of
    Left e ->
      pure (Left (PConfig ("failed to spawn `" <> ccBin cfg <> "` (is Claude Code installed?): " <> tshow e)))
    Right p -> Right <$> makeStream p

-- | Wrap the child's stdout in a pull 'Producer': read a line, feed the 'Decoder', buffer the events
-- it yields, and hand them out one at a time. Stops the process at end-of-stream.
makeStream :: Process () Handle () -> IO EventStream
makeStream p = do
  stateRef <- newIORef initDecoder
  pendRef <- newIORef []
  doneRef <- newIORef False
  let out = getStdout p
      feed [] = pull
      feed (x : xs) = writeIORef pendRef xs >> pure (Just x)
      pull =
        readIORef pendRef >>= \case
          (x : xs) -> writeIORef pendRef xs >> pure (Just x)
          [] ->
            readIORef doneRef >>= \case
              True -> pure Nothing
              False -> do
                er <- try (BS8.hGetLine out) :: IO (Either IOException BS.ByteString)
                case er of
                  Left e
                    | isEOFError e -> do
                        st <- readIORef stateRef
                        stopProcess p
                        writeIORef doneRef True
                        let (st', evs) = eofDecoder st
                        writeIORef stateRef st'
                        feed evs
                    | otherwise -> do
                        stopProcess p
                        writeIORef doneRef True
                        feed [Left (PTransport (tshow e))]
                  Right line -> do
                    st <- readIORef stateRef
                    let (st', evs) = pushLine st (decodeUtf8Lenient line)
                    writeIORef stateRef st'
                    feed evs
  pure (Producer pull)

-- --- prompt rendering ------------------------------------------------------------------------------

-- | Render the conversation as a plain-text prompt for @claude -p@. Empty messages are skipped and
-- tool blocks contribute nothing (@claude -p@ has its own tools); the system prompt is passed
-- separately via @--append-system-prompt@.
renderPrompt :: ChatRequest -> Text
renderPrompt req = T.concat (concatMap one (crMessages req))
  where
    one m =
      let t = messageText m
       in if T.null t then [] else [label (msgRole m) <> ": " <> t <> "\n\n"]
    label User = "User"
    label Assistant = "Assistant"

-- --- the stream-json decoder (pure state machine, mirrors the SSE decoders) ------------------------

-- | Incremental decoder for @claude -p@'s newline-delimited stream-json. Prefers partial
-- @stream_event@ deltas; falls back to whole @assistant@ messages when partials are absent; takes the
-- final usage + stop from the @result@ event. Emits exactly one @Done@.
data Decoder = Decoder
  { sawPartial :: Bool,
    doneEmitted :: Bool
  }

-- | A fresh decoder.
initDecoder :: Decoder
initDecoder = Decoder False False

type Emit = [Either ProviderError Event]

-- | Feed one line; returns the advanced decoder and any events it yielded. Unknown\/unparseable
-- lines (e.g. the @system@ init) are ignored.
pushLine :: Decoder -> Text -> (Decoder, Emit)
pushLine d line
  | T.null (T.strip line) = (d, [])
  | otherwise = case decodeStrict (encodeUtf8 line) :: Maybe Value of
      Nothing -> (d, [])
      Just v -> case lookText "type" v of
        Just "stream_event" -> handleStreamEvent d v
        Just "assistant" -> handleAssistant d v
        Just "result" -> handleResult d v
        _ -> (d, [])

handleStreamEvent :: Decoder -> Value -> (Decoder, Emit)
handleStreamEvent d v = case lookKey "event" v of
  Just inner
    | lookText "type" inner == Just "content_block_delta",
      Just delta <- lookKey "delta" inner ->
        let evs =
              [TextDelta t | Just t <- [neText (lookText "text" delta)]]
                <> [Thinking t | Just t <- [neText (lookText "thinking" delta)]]
            d' = if null evs then d else d {sawPartial = True}
         in (d', map Right evs)
  _ -> (d, [])

handleAssistant :: Decoder -> Value -> (Decoder, Emit)
handleAssistant d v
  -- Already streamed token deltas → don't re-emit the assembled message.
  | sawPartial d = (d, [])
  | otherwise = case lookKey "message" v of
      Just msg -> (d, map Right (concatMap blockEv (lookArr "content" msg)))
      Nothing -> (d, [])
  where
    blockEv b = case lookText "type" b of
      Just "text" -> [TextDelta t | Just t <- [neText (lookText "text" b)]]
      Just "thinking" -> [Thinking t | Just t <- [neText (lookText "thinking" b)]]
      _ -> []

handleResult :: Decoder -> Value -> (Decoder, Emit)
handleResult d v =
  let usageEvs = case lookKey "usage" v of
        Just u -> [Usage (mkUsage (lookNum "input_tokens" u) (lookNum "output_tokens" u))]
        Nothing -> []
      stop = if lookBool "is_error" v == Just True then Other "claude_cli_error" else EndTurn
   in (d {doneEmitted = True}, map Right (usageEvs <> [Done stop]))

-- | On EOF: guarantee exactly one 'Done' even if the stream was truncated before a @result@.
eofDecoder :: Decoder -> (Decoder, Emit)
eofDecoder d
  | doneEmitted d = (d, [])
  | otherwise = (d {doneEmitted = True}, [Right (Done EndTurn)])

-- --- tiny JSON helpers -----------------------------------------------------------------------------

-- (The subscription path reports no cache hits, so cache classes are always zero.)
mkUsage :: Word64 -> Word64 -> Usage
mkUsage i o = MkUsage i o 0 0

lookKey :: Text -> Value -> Maybe Value
lookKey k (Object o) = KM.lookup (K.fromText k) o
lookKey _ _ = Nothing

lookText :: Text -> Value -> Maybe Text
lookText k v = case lookKey k v of
  Just (String s) -> Just s
  _ -> Nothing

lookBool :: Text -> Value -> Maybe Bool
lookBool k v = case lookKey k v of
  Just (Bool b) -> Just b
  _ -> Nothing

lookNum :: Text -> Value -> Word64
lookNum k v = case lookKey k v of
  Just (Number n) -> truncate n
  _ -> 0

lookArr :: Text -> Value -> [Value]
lookArr k v = case lookKey k v of
  Just (Array a) -> V.toList a
  _ -> []

neText :: Maybe Text -> Maybe Text
neText (Just t) | not (T.null t) = Just t
neText _ = Nothing

tshow :: (Show a) => a -> Text
tshow = T.pack . show
