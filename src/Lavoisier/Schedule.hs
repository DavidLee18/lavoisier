-- | Scheduled jobs (ports the offline core of Rust @lvz-schedule@): the job model, the schedule-file
-- parser, the 'ScheduleRegistry' holding live per-job state, and the @schedule_list@\/@schedule_status@
-- \/@schedule_run@ chat tools. A job's 'Action' is either a __direct tool call__ (deterministic, no
-- model round-trip) or a __prompt turn__; a tool job may carry a @summarize@ instruction to rewrite a
-- successful result as prose for a room. The live serve-loop firing + Matrix room reports are the
-- gateway's concern (not here).
module Lavoisier.Schedule
  ( Action (..),
    actionSummary,
    ScheduleJob (..),
    Outcome (..),
    JobState (..),
    emptyJobState,
    ScheduleConfigError (..),
    parseScheduleFile,
    ScheduleRegistry,
    newRegistry,
    registryJobs,
    stateOf,
    indexOf,
    requestRun,
    takeRequested,
    recordOutcome,
    scheduleTools,
  )
where

import Data.Aeson (FromJSON (..), Value (..), decode, object, withObject, (.:), (.:?), (.=))
import Data.Aeson.Types (parseMaybe)
import Data.ByteString.Lazy qualified as BL
import Data.IORef
import Data.List (findIndex)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Lavoisier.Protocol.Tool
import Lavoisier.Schedule.Cron (CronError, CronSchedule, nextAfter, parseCron)

-- | Recent outcomes kept per job (for @schedule_status@).
historyCap :: Int
historyCap = 20

-- | Longest action-output snippet carried into a report / stored in state.
detailCap :: Int
detailCap = 600

-- | What a job does when it fires.
data Action
  = -- | Invoke a tool directly through the shared registry — deterministic, no model round-trip.
    ActTool Text Value
  | -- | Fire a prompt into the agent and let it decide which tools to call.
    ActPrompt Text
  deriving stock (Show, Eq)

-- | One-line description for listings and reports.
actionSummary :: Action -> Text
actionSummary (ActTool n _) = "tool `" <> n <> "`"
actionSummary (ActPrompt t) = "prompt " <> T.pack (show (T.take 60 t))

-- | A single scheduled job.
data ScheduleJob = ScheduleJob
  { sjId :: Text,
    sjExpr :: Text,
    sjSchedule :: CronSchedule,
    sjAction :: Action,
    sjRoom :: Maybe Text,
    sjSession :: Text,
    sjSummarize :: Maybe Text,
    sjRetryMax :: Int,
    sjRetryWait :: Integer
  }

-- | The JSON shape of one entry in a schedule file.
data JobSpec = JobSpec
  { specId :: Text,
    specSchedule :: Text,
    specRoom :: Maybe Text,
    specSession :: Maybe Text,
    specTool :: Maybe Text,
    specArgs :: Maybe Value,
    specPrompt :: Maybe Text,
    specSummarize :: Maybe Text,
    specRetryMax :: Maybe Int,
    specRetryWait :: Maybe Integer
  }

instance FromJSON JobSpec where
  parseJSON = withObject "JobSpec" $ \o ->
    JobSpec
      <$> o .: "id"
      <*> o .: "schedule"
      <*> o .:? "room"
      <*> o .:? "session"
      <*> o .:? "tool"
      <*> o .:? "args"
      <*> o .:? "prompt"
      <*> o .:? "summarize"
      <*> o .:? "retry_max"
      <*> o .:? "retry_wait"

-- | A failure building jobs from a schedule file.
data ScheduleConfigError
  = SceJson Text
  | SceCron Text CronError
  | SceAction Text
  | SceDuplicateId Text
  deriving stock (Show, Eq)

-- | Parse a JSON array of job specs, applying the global @retry_max@\/@retry_wait@ defaults to any
-- job that doesn't override them. @tool@ and @prompt@ are mutually exclusive and one is required;
-- ids must be unique.
parseScheduleFile :: BL.ByteString -> Int -> Integer -> Either ScheduleConfigError [ScheduleJob]
parseScheduleFile json retryMax retryWait =
  maybe (Left (SceJson "not a JSON array of job specs")) (go Set.empty) (decode json)
  where
    go _ [] = Right []
    go seen (s : ss)
      | Set.member (specId s) seen = Left (SceDuplicateId (specId s))
      | otherwise = do
          action <- case (specTool s, specPrompt s) of
            (Just n, Nothing) -> Right (ActTool n (fromMaybe (object []) (specArgs s)))
            (Nothing, Just t) -> Right (ActPrompt t)
            _ -> Left (SceAction (specId s))
          sched <- either (Left . SceCron (specId s)) Right (parseCron (specSchedule s))
          rest <- go (Set.insert (specId s) seen) ss
          pure (mkJob s action sched : rest)
    mkJob s action sched =
      ScheduleJob
        { sjId = specId s,
          sjExpr = specSchedule s,
          sjSchedule = sched,
          sjAction = action,
          sjRoom = specRoom s,
          sjSession = fromMaybe ("schedule-" <> specId s) (specSession s),
          sjSummarize = specSummarize s,
          sjRetryMax = fromMaybe retryMax (specRetryMax s),
          sjRetryWait = fromMaybe retryWait (specRetryWait s)
        }

-- | One recorded fire.
data Outcome = Outcome
  { ocAt :: Integer,
    ocOk :: Bool,
    ocDetail :: Text,
    ocAttempt :: Int
  }
  deriving stock (Show, Eq)

-- | Live per-job state, read by the @schedule_*@ tools.
data JobState = JobState
  { jsNextDue :: Maybe Integer,
    jsRetryAt :: Maybe Integer,
    jsAttempt :: Int,
    jsLastFired :: Maybe Integer,
    jsLastOk :: Maybe Bool,
    jsRuns :: Integer,
    jsFailures :: Integer,
    jsConsecutiveFailures :: Int,
    jsHistory :: [Outcome]
  }
  deriving stock (Show, Eq)

emptyJobState :: JobState
emptyJobState = JobState Nothing Nothing 0 Nothing Nothing 0 0 0 []

-- | A registry over a fixed job list plus its live state and a manual-run request queue.
data ScheduleRegistry = ScheduleRegistry
  { srJobs :: [ScheduleJob],
    srState :: IORef (Map Text JobState),
    srRequested :: IORef [Int]
  }

-- | Build a registry over @jobs@ and arm each one's first cron slot (relative to @now@ unix seconds).
newRegistry :: Integer -> [ScheduleJob] -> IO ScheduleRegistry
newRegistry now jobs = do
  st <- newIORef (Map.fromList [(sjId j, emptyJobState {jsNextDue = nextAfter (sjSchedule j) now}) | j <- jobs])
  req <- newIORef []
  pure (ScheduleRegistry jobs st req)

-- | The jobs, in registration order.
registryJobs :: ScheduleRegistry -> [ScheduleJob]
registryJobs = srJobs

-- | A snapshot of one job's state.
stateOf :: ScheduleRegistry -> Text -> IO (Maybe JobState)
stateOf reg jid = Map.lookup jid <$> readIORef (srState reg)

-- | Index of a job by id.
indexOf :: ScheduleRegistry -> Text -> Maybe Int
indexOf reg jid = findIndex ((== jid) . sjId) (srJobs reg)

-- | Queue an out-of-band run of @id@; 'False' if no such job.
requestRun :: ScheduleRegistry -> Text -> IO Bool
requestRun reg jid = case indexOf reg jid of
  Nothing -> pure False
  Just i -> modifyIORef' (srRequested reg) (<> [i]) >> pure True

-- | Drain and return the queued manual-run job indices.
takeRequested :: ScheduleRegistry -> IO [Int]
takeRequested reg = atomicModifyIORef' (srRequested reg) (\q -> ([], q))

-- | Record a fire's outcome against a job's state (mirrors the Rust @record@): bump counters + the
-- failure streak, cap history, and set the follow-up — a pending retry suppresses the cron slot
-- (@next_due = Nothing@) until the chain resolves, then the next slot is recomputed from @now@.
recordOutcome :: ScheduleRegistry -> Integer -> ScheduleJob -> Either Text Text -> IO ()
recordOutcome reg now job result = modifyIORef' (srState reg) (Map.alter (Just . upd) (sjId job))
  where
    ok = either (const False) (const True) result
    detail = T.take detailCap (either id id result)
    upd ms =
      let s0 = fromMaybe emptyJobState ms
          attempt = jsAttempt s0 + 1
          h = jsHistory s0 <> [Outcome now ok detail attempt]
          hist = drop (max 0 (length h - historyCap)) h
          retrying = not ok && attempt <= sjRetryMax job
       in s0
            { jsAttempt = if retrying then attempt else 0,
              jsRuns = jsRuns s0 + 1,
              jsLastFired = Just now,
              jsLastOk = Just ok,
              jsHistory = hist,
              jsFailures = if ok then jsFailures s0 else jsFailures s0 + 1,
              jsConsecutiveFailures = if ok then 0 else jsConsecutiveFailures s0 + 1,
              jsRetryAt = if retrying then Just (now + sjRetryWait job) else Nothing,
              jsNextDue = if retrying then Nothing else nextAfter (sjSchedule job) now
            }

-- --- the schedule_* chat tools ---------------------------------------------------------------------

-- | The three schedule tools bound to a registry (so "how's the disk job?" / "run it again" work in
-- natural language): @schedule_list@, @schedule_status@, @schedule_run@.
scheduleTools :: ScheduleRegistry -> [Tool]
scheduleTools reg = [scheduleListTool reg, scheduleStatusTool reg, scheduleRunTool reg]

scheduleListTool :: ScheduleRegistry -> Tool
scheduleListTool reg =
  Tool
    { toolName = "schedule_list",
      toolDescription = "List every scheduled job, its schedule, action, and current health.",
      toolSchema = object ["type" .= sv "object", "properties" .= object []],
      toolInvoke = \_ -> do
        st <- readIORef (srState reg)
        pure (Right (toolOk (T.intercalate "\n" (map (jobLine st) (srJobs reg)))))
    }
  where
    jobLine st j =
      let s = Map.findWithDefault emptyJobState (sjId j) st
       in "• "
            <> sjId j
            <> " ["
            <> sjExpr j
            <> "] "
            <> actionSummary (sjAction j)
            <> " — "
            <> health s

scheduleStatusTool :: ScheduleRegistry -> Tool
scheduleStatusTool reg =
  Tool
    { toolName = "schedule_status",
      toolDescription = "Show one scheduled job in detail, including recent run history. Needs `id`.",
      toolSchema = object ["type" .= sv "object", "properties" .= object ["id" .= prop "The job id, as shown by schedule_list"], "required" .= [sv "id"]],
      toolInvoke = \args -> case idArg args of
        Nothing -> pure (Right (toolErr "schedule_status: missing `id`"))
        Just jid -> do
          ms <- stateOf reg jid
          pure . Right $ case (lookupJob jid, ms) of
            (Just j, Just s) -> toolOk (statusReport j s)
            _ -> toolErr ("schedule_status: no job `" <> jid <> "`")
    }
  where
    lookupJob jid = case filter ((== jid) . sjId) (srJobs reg) of (j : _) -> Just j; [] -> Nothing

scheduleRunTool :: ScheduleRegistry -> Tool
scheduleRunTool reg =
  Tool
    { toolName = "schedule_run",
      toolDescription = "Fire a scheduled job now, out of band. Needs `id`.",
      toolSchema = object ["type" .= sv "object", "properties" .= object ["id" .= prop "The job id, as shown by schedule_list"], "required" .= [sv "id"]],
      toolInvoke = \args -> case idArg args of
        Nothing -> pure (Right (toolErr "schedule_run: missing `id`"))
        Just jid -> do
          queued <- requestRun reg jid
          pure . Right $
            if queued
              then toolOk ("queued an out-of-band run of `" <> jid <> "`")
              else toolErr ("schedule_run: no job `" <> jid <> "`")
    }

-- --- rendering + arg helpers -----------------------------------------------------------------------

health :: JobState -> Text
health s = case jsLastOk s of
  Nothing -> "never fired, " <> nextText s
  Just True -> "last ok, " <> runsText s <> ", " <> nextText s
  Just False -> "last FAILED (streak " <> tshow (jsConsecutiveFailures s) <> "), " <> runsText s <> ", " <> nextText s

statusReport :: ScheduleJob -> JobState -> Text
statusReport j s =
  T.intercalate
    "\n"
    ( [ "job: " <> sjId j <> " [" <> sjExpr j <> "]",
        "action: " <> actionSummary (sjAction j),
        "room: " <> fromMaybe "(default)" (sjRoom j),
        "health: " <> health s
      ]
        <> ["history:"]
        <> map histLine (reverse (jsHistory s))
    )
  where
    histLine o = "  " <> (if ocOk o then "ok " else "FAIL") <> " @" <> tshow (ocAt o) <> " (attempt " <> tshow (ocAttempt o) <> "): " <> ocDetail o

runsText :: JobState -> Text
runsText s = tshow (jsRuns s) <> " runs / " <> tshow (jsFailures s) <> " failed"

nextText :: JobState -> Text
nextText s = case (jsRetryAt s, jsNextDue s) of
  (Just r, _) -> "retry at " <> tshow r
  (Nothing, Just n) -> "next at " <> tshow n
  (Nothing, Nothing) -> "no further runs"

idArg :: Value -> Maybe Text
idArg = parseMaybe (withObject "args" (.: "id"))

sv :: Text -> Value
sv = String

prop :: Text -> Value
prop d = object ["type" .= sv "string", "description" .= sv d]

tshow :: (Show a) => a -> Text
tshow = T.pack . show
