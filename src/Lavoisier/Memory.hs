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
    atomicWriteFile,
    trimTo,
    sessionAgentHandle,
  )
where

import Control.Concurrent (forkIO)
import Control.Concurrent.Chan
import Control.Exception (IOException, onException, try)
import Data.Aeson (decode, encode)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.IORef
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding (encodeUtf8)
import Data.Word (Word64, Word8)
import Lavoisier.Agent (Agent, applyModelOverride, runLoopSeeded)
import Lavoisier.Log (logError)
import Lavoisier.Protocol.Agent (AgentHandle (..), TurnRequest (..))
import Lavoisier.Protocol.Message (Message, userMessage)
import Lavoisier.Protocol.Stream (Producer (..))
import System.Directory (createDirectoryIfMissing, doesFileExist, removeFile, renameFile)
import System.FilePath (takeDirectory, takeFileName, (</>))
import System.IO (IOMode (WriteMode), hFlush, openBinaryFile)
import System.IO.Unsafe (unsafePerformIO)
import System.Posix.IO (closeFd, handleToFd)
import System.Posix.Process (getProcessID)
import System.Posix.Unistd (fileSynchronise)

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
      { loadSession = loadFile dir,
        saveSession = \s h -> do
          let path = dir </> sessionFile s
          r <- try (atomicWriteFile path (encode (trimTo maxMsgs h))) :: IO (Either IOException ())
          case r of
            Right () -> pure ()
            Left e -> logError "memory" ("cannot write session " <> T.pack path <> ": " <> T.pack (show e))
      }

-- | Read one session file. A missing file is the normal "fresh session" case and is silent; any
-- other read error is logged rather than swallowed. A file that exists but will not parse means
-- __corruption__ — a partial write from before atomic saves, external tampering, or disk damage. It
-- is /not/ silently reset to empty (which would let the next save overwrite the evidence): it is set
-- aside as @.corrupt@ and logged loudly, so the transcript loss is visible and recoverable.
loadFile :: FilePath -> Text -> IO [Message]
loadFile dir s = do
  let path = dir </> sessionFile s
  present <- doesFileExist path
  if not present
    then pure []
    else do
      r <- try (BL.readFile path) :: IO (Either IOException BL.ByteString)
      case r of
        Left e -> do
          logError "memory" ("cannot read session file " <> T.pack path <> " (" <> T.pack (show e) <> "); starting empty")
          pure []
        Right bs -> case decode bs of
          Just history -> pure history
          Nothing -> do
            let corrupt = path <> ".corrupt"
            logError "memory" $
              "session file " <> T.pack path <> " is corrupt; preserving it as " <> T.pack corrupt <> " and starting empty"
            re <- try (renameFile path corrupt) :: IO (Either IOException ())
            case re of
              Right () -> pure ()
              Left e -> logError "memory" ("could not set aside corrupt session file " <> T.pack path <> ": " <> T.pack (show e))
            pure []

-- | Durably replace @path@'s contents with @bytes@: write a sibling temp file, flush it to disk, then
-- atomically rename it over the target.
--
-- @rename(2)@ is atomic on POSIX and on EFS\/NFS (within one filesystem — hence a temp file in the
-- /same/ directory), so a crash mid-write can never leave a torn file, and a concurrent reader sees
-- either the old contents or the new, never a partial mix. This is what stops a mid-write
-- SIGKILL\/OOM\/task-replacement from truncating a transcript into unparseable JSON that 'loadFile'
-- would then have to quarantine. The temp file is removed on any failure, so a transient error cannot
-- litter the directory.
atomicWriteFile :: FilePath -> BL.ByteString -> IO ()
atomicWriteFile path bytes = do
  -- Hidden, unique-per-write temp name in the same dir: pid + a monotonic counter, so concurrent
  -- writers (in this process or another sharing the dir) never collide on it.
  pid <- getProcessID
  n <- atomicModifyIORef' writeSeq (\k -> (k + 1, k))
  let dir = takeDirectory path
      tmp = dir </> ("." <> takeFileName path <> "." <> show pid <> "." <> show n <> ".tmp")
  flip onException (ignoring (removeFile tmp)) $ do
    hnd <- openBinaryFile tmp WriteMode
    BL.hPut hnd bytes
    hFlush hnd
    -- Durable before the rename makes it visible. 'handleToFd' flushes and closes the 'Handle',
    -- handing us the raw descriptor to fsync.
    fd <- handleToFd hnd
    fileSynchronise fd
    closeFd fd
    renameFile tmp path
  where
    ignoring act = (try act :: IO (Either IOException ())) >> pure ()

-- | Per-process write counter, so each 'atomicWriteFile' temp file has a unique name even under
-- concurrent writers (paired with the pid it is unique across processes on a shared dir too).
writeSeq :: IORef Word64
writeSeq = unsafePerformIO (newIORef 0)
{-# NOINLINE writeSeq #-}

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
    res <- runLoopSeeded (applyModelOverride (trModel turn) agent) (trAllowedTools turn) initial (\ev -> writeChan chan (Just (Right ev)))
    case res of
      Right full -> saveSession store (trSession turn) full
      Left e -> writeChan chan (Just (Left e))
    writeChan chan Nothing
  pure (Right (Producer (readChan chan)))
