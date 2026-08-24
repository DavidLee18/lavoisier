-- | @Lavoisier.Gateway.Cron@ — a cron-scheduled gateway for the shared agent. Ports the Rust
-- @lvz-gw-cron@ (the cron engine itself lives in "Lavoisier.Schedule.Cron").
--
-- A 'Gateway' whose "channel" is /time/: it holds a set of 'CronJob's and, for each, sleeps until the
-- job's next fire (UTC), submits a 'TurnRequest' to the shared 'AgentHandle', drains the resulting
-- 'Event' stream, and (on failure) retries. Jobs run __concurrently__ (@async@'s 'mapConcurrently_').
-- Each job keeps a fixed session, so the session store gives it continuity across fires.
--
-- A __failed fire__ is retryable — a rejected @submit@ or a mid-turn stream error — while a
-- /completed/ turn is a success even if its answer is weak (that's semantic, not knowable here). The
-- next scheduled slot is recomputed from "now" __after__ any retries finish, so a retry's wait never
-- double-fires the next slot.
module Lavoisier.Gateway.Cron
  ( CronJob (..),
    CronConfigError (..),
    parseCliJob,
    jobFromSpec,
    loadFileJobs,
    cronGateway,
  )
where

import Control.Concurrent (threadDelay)
import Control.Concurrent.Async (mapConcurrently_)
import Control.Exception (SomeException, try)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time.Clock.POSIX (getPOSIXTime)
import Dhall qualified
import GHC.Generics (Generic)
import Lavoisier.Domain qualified as D
import Lavoisier.Protocol.Agent (AgentHandle (..), turnRequest)
import Lavoisier.Protocol.Gateway (Gateway (..), GatewayError)
import Lavoisier.Protocol.Stream (Producer (..))
import Lavoisier.Schedule.Cron (CronError, CronSchedule, nextAfter, parseCron)
import Numeric.Natural (Natural)

-- | One scheduled task: when to fire, which session to run it under, the prompt to submit, and the
-- retry policy after a failed fire.
data CronJob = CronJob
  { cjSchedule :: CronSchedule,
    -- | Session id — fixed across fires so the job accrues continuity.
    cjSession :: Text,
    cjPrompt :: Text,
    -- | Max retries after a failed fire before waiting for the next slot (@0@ ⇒ single-shot).
    cjRetryMax :: Int,
    -- | Seconds between retries (ignored when 'cjRetryMax' is 0).
    cjRetryWait :: Int
  }
  deriving stock (Eq, Show)

-- | A failure building cron jobs from CLI\/file input.
data CronConfigError
  = -- | A cron expression failed to parse.
    CCECron CronError
  | -- | A @--cron@ quick spec lacked a prompt after its 5 schedule fields.
    CCEMissingPrompt Text
  | -- | The @--cron-file@ Dhall failed to parse or type-check.
    CCEFile Text
  deriving stock (Eq, Show)

-- | Parse a quick CLI spec: the first __five__ whitespace-separated tokens are the cron schedule, the
-- remainder is the prompt. @index@ seeds the default session id (@cron-\<index\>@). @retryMax@\/
-- @retryWait@ are the global retry defaults (a quick spec carries no inline retry policy).
-- | Build a job from an already-structured 'D.CronJobSpec'. The schedule fields and the prompt
-- arrive separately, so there is no whitespace split to get wrong — the flag reader and the Dhall
-- config both produce this shape.
jobFromSpec :: D.CronJobSpec -> Int -> D.RetryCount -> D.Seconds -> Either CronConfigError CronJob
jobFromSpec spec index rmax rwait =
  case parseCron (D.renderCronExpr (D.csSchedule spec)) of
    Left e -> Left (CCECron e)
    Right sched ->
      Right
        CronJob
          { cjSchedule = sched,
            cjSession = maybe ("cron-" <> tshow index) D.unSessionId (D.csSession spec),
            cjPrompt = D.csPrompt spec,
            cjRetryMax = fromIntegral (D.unRetryCount (fromMaybe rmax (D.csRetryMax spec))),
            cjRetryWait = fromIntegral (D.unSeconds (fromMaybe rwait (D.csRetryWait spec)))
          }

parseCliJob :: Text -> Int -> Int -> Int -> Either CronConfigError CronJob
parseCliJob spec index retryMax retryWait =
  case T.words spec of
    toks
      | length toks < 6 -> Left (CCEMissingPrompt spec)
      | otherwise -> case parseCron (T.unwords (take 5 toks)) of
          Left e -> Left (CCECron e)
          Right sched ->
            Right (CronJob sched ("cron-" <> tshow index) (T.unwords (drop 5 toks)) retryMax retryWait)

-- | Dhall shape for a @--cron-file@ job: a list of records
-- @{ schedule : Text, session : Optional Text, prompt : Text, retryMax : Optional Natural,
-- retryWait : Optional Natural }@. A per-job @retryMax@\/@retryWait@ overrides the global default.
-- The field names are the Dhall record keys (Dhall is camelCase by convention).
data CronSpec = CronSpec
  { schedule :: Text,
    session :: Maybe Text,
    prompt :: Text,
    retryMax :: Maybe Natural,
    retryWait :: Maybe Natural
  }
  deriving stock (Generic)

instance Dhall.FromDhall CronSpec

-- | Load a @--cron-file@ Dhall document (a list of job specs), type-checked by Dhall at load. A
-- missing @session@ defaults to @cron-\<index\>@; a missing @retryMax@\/@retryWait@ falls back to the
-- global default. A parse\/type error surfaces as 'CCEFile'.
loadFileJobs :: FilePath -> Int -> Int -> IO (Either CronConfigError [CronJob])
loadFileJobs path defRetryMax defRetryWait = do
  r <- try (Dhall.inputFile Dhall.auto path :: IO [CronSpec]) :: IO (Either SomeException [CronSpec])
  pure $ case r of
    Left e -> Left (CCEFile (T.pack (show e)))
    Right specs -> traverse toJob (zip [0 ..] specs)
  where
    toJob (i, s) = case parseCron (schedule s) of
      Left e -> Left (CCECron e)
      Right sched ->
        Right
          CronJob
            { cjSchedule = sched,
              cjSession = fromMaybe ("cron-" <> tshow (i :: Int)) (session s),
              cjPrompt = prompt s,
              cjRetryMax = maybe defRetryMax fromIntegral (retryMax s),
              cjRetryWait = maybe defRetryWait fromIntegral (retryWait s)
            }

-- | The 'Gateway' record: drives the shared agent from a set of 'CronJob's. An empty set returns
-- immediately.
cronGateway :: [CronJob] -> Gateway
cronGateway jobs =
  Gateway
    { gatewayName = "cron",
      gatewayServe = serveCron jobs
    }

serveCron :: [CronJob] -> AgentHandle -> IO (Either GatewayError ())
serveCron [] _ = pure (Right ())
serveCron jobs agent = do
  -- Drive every job concurrently; each loops forever, so this only returns if every job has
  -- self-disabled (its schedule has no future fire).
  mapConcurrently_ (runJob agent) jobs
  pure (Right ())

-- | Loop a single job: wait for its next fire, run a turn (with retries on failure), repeat. Returns
-- when the schedule has no further fire (so an impossible schedule disables just that job).
runJob :: AgentHandle -> CronJob -> IO ()
runJob agent job = loop
  where
    loop = do
      now <- nowUnix
      case nextAfter (cjSchedule job) now of
        Nothing -> pure () -- impossible schedule: disable this job
        Just next -> do
          sleepSecs (max 0 (next - now))
          fireWithRetries 0
          loop

    fireWithRetries attempt = do
      ok <- fire agent job
      if ok
        then pure ()
        else
          if attempt >= cjRetryMax job
            then pure ()
            else do
              sleepSecs (fromIntegral (cjRetryWait job))
              fireWithRetries (attempt + 1)

-- | Run one turn for @job@. Returns 'True' on a completed turn (a success even if the answer is
-- weak), 'False' on a failure worth retrying (submit rejected, or the event stream errored mid-turn).
fire :: AgentHandle -> CronJob -> IO Bool
fire agent job = do
  est <- submit agent (turnRequest (cjSession job) (cjPrompt job))
  case est of
    Left _ -> pure False
    Right stream -> drain stream
  where
    drain stream =
      nextItem stream >>= \case
        Nothing -> pure True
        Just (Left _) -> pure False
        Just (Right _) -> drain stream

nowUnix :: IO Integer
nowUnix = (round :: Double -> Integer) . realToFrac <$> getPOSIXTime

sleepSecs :: Integer -> IO ()
sleepSecs s
  | s <= 0 = pure ()
  | otherwise = threadDelay (fromInteger (min s maxSleep * 1000000))
  where
    maxSleep = 100000000 -- clamp a single sleep to avoid Int overflow on absurd waits

tshow :: (Show a) => a -> Text
tshow = T.pack . show
