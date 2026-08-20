-- | Structured operator logging (the Haskell analogue of the Rust engine's @tracing@ facade). Haskell
-- has no equivalent of @tracing@'s zero-cost facade, so this is a small hand-rolled logger: a single
-- process-wide level threshold (set once at the CLI from @--log-level@\/@LVZ_LOG_LEVEL@) and level
-- helpers that library crates — and downstream @mainWith@ tool crates — call to emit a timestamped
-- @LEVEL target: message@ line to __stderr__ when the level passes.
--
-- This is __diagnostics__, not product output: the streamed CLI interface (@[tool]@, @[usage]@, the
-- answer text, the fatal @error:@ lines) stays plain and unsuppressible, exactly as the Rust CLI keeps
-- those out of the log filter. A message is emitted iff its level is at least as severe as the
-- threshold (@Debug@ is shown only under a @debug@ threshold).
module Lavoisier.Log
  ( LogLevel (..),
    parseLogLevel,
    setLogLevel,
    getLogLevel,
    setLogSink,
    fileLogSink,
    nullLogSink,
    logAt,
    logError,
    logWarn,
    logInfo,
    logDebug,
  )
where

import Control.Exception (SomeException, try)
import Control.Monad (when)
import Data.IORef
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Time.Clock (getCurrentTime)
import Data.Time.Format (defaultTimeLocale, formatTime)
import System.IO (BufferMode (LineBuffering), Handle, IOMode (AppendMode), hSetBuffering, openFile, stderr)
import System.IO.Unsafe (unsafePerformIO)

-- | Severity, most-severe first (so a threshold admits everything up to and including itself).
data LogLevel = LogError | LogWarn | LogInfo | LogDebug
  deriving stock (Eq, Ord, Show)

-- | Parse a level from @--log-level@\/@LVZ_LOG_LEVEL@. A bare @error@\/@warn@\/@info@\/@debug@ selects
-- that threshold; a @RUST_LOG@-style directive set (e.g. @lvz_gw_matrix=debug,info@) is reduced to its
-- last bare-level token (the global default), so the engine tolerates the deployment's existing filter
-- strings. Anything unrecognised falls back to 'LogInfo'.
parseLogLevel :: Text -> LogLevel
parseLogLevel raw =
  let bare = [t | t <- map T.strip (T.splitOn "," raw), not (T.isInfixOf "=" t), not (T.null t)]
      pick t = case T.toLower t of
        "error" -> Just LogError
        "warn" -> Just LogWarn
        "warning" -> Just LogWarn
        "info" -> Just LogInfo
        "debug" -> Just LogDebug
        "trace" -> Just LogDebug
        _ -> Nothing
   in case reverse (foldr (\t acc -> maybe acc (: acc) (pick t)) [] bare) of
        (l : _) -> l
        [] -> LogInfo

-- | The process-wide threshold (the Rust global subscriber's analogue). Defaults to 'LogInfo'.
{-# NOINLINE levelRef #-}
levelRef :: IORef LogLevel
levelRef = unsafePerformIO (newIORef LogInfo)

-- | Where log lines go. Defaults to stderr; the inline TUI owns the terminal, so it redirects (see
-- 'fileLogSink' \/ 'nullLogSink') rather than letting stderr writes corrupt its viewport.
{-# NOINLINE sinkRef #-}
sinkRef :: IORef (Text -> IO ())
sinkRef = unsafePerformIO (newIORef (TIO.hPutStrLn stderr))

-- | Redirect log output (call once at startup, before anything worth logging happens).
setLogSink :: (Text -> IO ()) -> IO ()
setLogSink = writeIORef sinkRef

-- | A sink appending to @path@, or 'Nothing' when it cannot be opened.
fileLogSink :: FilePath -> IO (Maybe (Text -> IO ()))
fileLogSink path = do
  r <- try (openFile path AppendMode) :: IO (Either SomeException Handle)
  case r of
    Left _ -> pure Nothing
    Right h -> hSetBuffering h LineBuffering >> pure (Just (TIO.hPutStrLn h))

-- | A sink that drops every line.
nullLogSink :: Text -> IO ()
nullLogSink _ = pure ()

-- | Set the threshold (call once at startup).
setLogLevel :: LogLevel -> IO ()
setLogLevel = writeIORef levelRef

-- | The current threshold.
getLogLevel :: IO LogLevel
getLogLevel = readIORef levelRef

-- | Emit @<utc> <LEVEL> <target>: <message>@ to stderr when @level@ passes the threshold.
logAt :: LogLevel -> Text -> Text -> IO ()
logAt level target message = do
  threshold <- readIORef levelRef
  when (level <= threshold) $ do
    now <- getCurrentTime
    let ts = T.pack (formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ" now)
    sink <- readIORef sinkRef
    sink (ts <> " " <> levelName level <> " " <> target <> ": " <> message)

-- | @logAt LogError@ etc.
logError, logWarn, logInfo, logDebug :: Text -> Text -> IO ()
logError = logAt LogError
logWarn = logAt LogWarn
logInfo = logAt LogInfo
logDebug = logAt LogDebug

levelName :: LogLevel -> Text
levelName LogError = "ERROR"
levelName LogWarn = "WARN"
levelName LogInfo = "INFO"
levelName LogDebug = "DEBUG"
