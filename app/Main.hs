module Main (main) where

import Data.Maybe (fromMaybe)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Lavoisier.Protocol.Event (Event (..))
import Lavoisier.Protocol.Message (ChatRequest (..), chatRequest, userMessage)
import Lavoisier.Protocol.Provider (Provider (..), ProviderError)
import Lavoisier.Protocol.Stream (Producer (..))
import Lavoisier.Provider.Anthropic (anthropicFromEnv)
import System.Environment (getArgs, lookupEnv)
import System.Exit (exitFailure)
import System.IO (hFlush, hPutStrLn, stderr, stdout)

-- | Phase 2/5 stopgap CLI: a one-shot @ask@ against Anthropic. The full optparse-driven CLI
-- (ask + --agent, provider selection, streaming renderer) lands in Phase 5.
main :: IO ()
main = do
  args <- getArgs
  let prompt = T.strip (T.pack (unwords args))
  if T.null prompt
    then hPutStrLn stderr "usage: lav <prompt>" >> exitFailure
    else do
      eprov <- anthropicFromEnv
      case eprov of
        Left err -> die err
        Right prov -> do
          model <- T.pack . fromMaybe "claude-sonnet-4-5" <$> lookupEnv "LAV_MODEL"
          let req = (chatRequest model) {crMessages = [userMessage prompt], crMaxTokens = 1024}
          estream <- providerStream prov req
          case estream of
            Left err -> die err
            Right stream -> render stream
  where
    die :: ProviderError -> IO ()
    die err = hPutStrLn stderr ("error: " <> show err) >> exitFailure

render :: Producer (Either ProviderError Event) -> IO ()
render p = loop
  where
    loop =
      nextItem p >>= \case
        Nothing -> putStrLn ""
        Just (Left err) -> hPutStrLn stderr ("\nerror: " <> show err)
        Just (Right ev) -> handle ev >> loop
    handle = \case
      TextDelta t -> TIO.putStr t >> hFlush stdout
      _ -> pure ()
