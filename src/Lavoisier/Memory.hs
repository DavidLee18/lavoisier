-- | Per-session transcript memory, ported (core subset) from Rust @lvz-memory@.
--
-- 'sessionAgentHandle' wraps an 'Agent' as an 'AgentHandle' that loads the session's stored
-- transcript, seeds the turn with it, runs, and persists the result — so a gateway's @session@ field
-- becomes load-bearing and a conversation continues across turns. 'newInMemoryStore' is the
-- process-local store (a durable file store is a deferred follow-up).
module Lavoisier.Memory
  ( SessionStore (..),
    newInMemoryStore,
    newFileStore,
    trimTo,
    sessionAgentHandle,
  )
where

import Control.Concurrent (forkIO)
import Control.Concurrent.Chan
import Control.Exception (IOException, try)
import Data.Aeson (decode, encode)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.IORef
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text.Encoding (encodeUtf8)
import Data.Word (Word8)
import Lavoisier.Agent (Agent, runLoopSeeded)
import Lavoisier.Protocol.Agent (AgentHandle (..), TurnRequest (..))
import Lavoisier.Protocol.Message (Message, userMessage)
import Lavoisier.Protocol.Stream (Producer (..))
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))

-- | A per-session transcript store, as a record of functions. @save@ replaces the whole transcript
-- (the caller passes the full updated history), mirroring the Rust @SessionStore@.
data SessionStore = SessionStore
  { loadSession :: Text -> IO [Message],
    saveSession :: Text -> [Message] -> IO ()
  }

-- | Keep only the most recent @n@ messages (no-op when unbounded or already within bound).
trimTo :: Maybe Int -> [Message] -> [Message]
trimTo Nothing h = h
trimTo (Just n) h = let len = length h in if len > n then drop (len - n) h else h

-- | A process-local in-memory store, optionally capping each session to its most recent N messages.
-- (Rust's LRU @max_sessions@ eviction and the durable file store are deferred.)
newInMemoryStore :: Maybe Int -> IO SessionStore
newInMemoryStore maxMsgs = do
  ref <- newIORef Map.empty
  pure
    SessionStore
      { loadSession = \s -> Map.findWithDefault [] s <$> readIORef ref,
        saveSession = \s h -> modifyIORef' ref (Map.insert s (trimTo maxMsgs h))
      }

-- | A durable, file-backed store: one JSON file per session under @dir@ (the session name is
-- hex-encoded into the filename, so any session string is filesystem-safe). Survives restarts.
newFileStore :: FilePath -> Maybe Int -> IO SessionStore
newFileStore dir maxMsgs = do
  createDirectoryIfMissing True dir
  pure
    SessionStore
      { loadSession = \s -> do
          r <- try (BL.readFile (dir </> sessionFile s)) :: IO (Either IOException BL.ByteString)
          pure $ case r of
            Right bs -> maybe [] id (decode bs)
            Left _ -> [],
        saveSession = \s h -> BL.writeFile (dir </> sessionFile s) (encode (trimTo maxMsgs h))
      }

-- | Hex-encode a session name into a safe @.json@ filename.
sessionFile :: Text -> FilePath
sessionFile s = concatMap byteHex (BS.unpack (encodeUtf8 s)) <> ".json"
  where
    byteHex :: Word8 -> String
    byteHex w = [hexDigit (w `div` 16), hexDigit (w `mod` 16)]
    hexDigit n
      | n < 10 = toEnum (fromEnum '0' + fromIntegral n)
      | otherwise = toEnum (fromEnum 'a' + fromIntegral n - 10)

-- | Wrap an 'Agent' so each turn continues its session's transcript: load prior history, seed the
-- turn with it + the new user message, run, stream events through a 'Chan'-backed 'Producer', and
-- persist the full updated transcript on success.
sessionAgentHandle :: SessionStore -> Agent -> AgentHandle
sessionAgentHandle store agent = AgentHandle $ \turn -> do
  chan <- newChan
  _ <- forkIO $ do
    prior <- loadSession store (trSession turn)
    let initial = prior <> [userMessage (trInput turn)]
    res <- runLoopSeeded agent (trAllowedTools turn) initial (\ev -> writeChan chan (Just (Right ev)))
    case res of
      Right full -> saveSession store (trSession turn) full
      Left e -> writeChan chan (Just (Left e))
    writeChan chan Nothing
  pure (Right (Producer (readChan chan)))
