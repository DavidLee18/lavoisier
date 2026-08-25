{- | Scheduled jobs (ports the offline core of Rust @lvz-schedule@): the job model, the schedule-file
parser, the 'ScheduleRegistry' holding live per-job state, and the @schedule_list@\/@schedule_status@
\/@schedule_run@ chat tools. A job's 'Action' is either a __direct tool call__ (deterministic, no
model round-trip) or a __prompt turn__; a tool job may carry a @summarize@ instruction to rewrite a
successful result as prose for a room. The live serve-loop firing + Matrix room reports are the
gateway's concern (not here).
-}
module Lavoisier.Schedule (
    Action (..),
    actionSummary,
    ScheduleJob (..),
    Outcome (..),
    JobState (..),
    emptyJobState,
    ScheduleConfigError (..),
    jobsFromSpecs,
    ScheduleRegistry,
    newRegistry,
    registryJobs,
    stateOf,
    indexOf,
    requestRun,
    takeRequested,
    dueJobs,
    recordOutcome,
    FireRecord (..),
    reportBody,
    scheduleTools,
)
where

import Data.Aeson (Value (..), decode, object, withObject, (.:), (.=))
import Data.Aeson.Types (parseMaybe)
import Data.IORef
import Data.List (findIndex)
import Data.Map.Strict (Map)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text.Encoding (encodeUtf8)

import Data.ByteString.Lazy qualified as BL
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as T

import Lavoisier.Domain (ToolName (..))
import Lavoisier.Protocol.Tool
import Lavoisier.Schedule.Cron (CronSchedule, compileCron, nextAfter)

import Lavoisier.Domain qualified as D

-- | Recent outcomes kept per job (for @schedule_status@).
historyCap ∷ Int
historyCap = 20

-- | Longest action-output snippet carried into a report / stored in state.
detailCap ∷ Int
detailCap = 600

-- | What a job does when it fires.
data Action
    = -- | Invoke a tool directly through the shared registry — deterministic, no model round-trip.
      ActTool ToolName Value
    | -- | Fire a prompt into the agent and let it decide which tools to call.
      ActPrompt Text
    deriving stock (Eq, Show)

-- | One-line description for listings and reports.
actionSummary ∷ Action → Text
actionSummary (ActTool n _) = "tool `" <> unToolName n <> "`"
actionSummary (ActPrompt t) = "prompt " <> T.pack (show (T.take 60 t))

-- | A single scheduled job.
data ScheduleJob = ScheduleJob
    { sjId ∷ Text
    , sjExpr ∷ Text
    , sjSchedule ∷ CronSchedule
    , sjAction ∷ Action
    , sjRoom ∷ Maybe Text
    , sjSession ∷ Text
    , sjSummarize ∷ Maybe Text
    , sjRetryMax ∷ Int
    , sjRetryWait ∷ Integer
    }

-- | A failure building jobs from a schedule file.
data ScheduleConfigError
    = -- | Two jobs shared an id.
      SceDuplicateId Text
    deriving stock (Eq, Show)

{- | Build jobs from the specs a @--schedule-file@ decoded to, applying the global @retryMax@\/
@retryWait@ defaults to any job that does not override them. Ids must be unique.

__The only failure left is a duplicate id.__ The schedule is a checked 'D.CronExpr', so compiling
it is total, and the action is a union, so the old "exactly one of @tool@\/@prompt@" check has
nothing to check — both were runtime errors that the types now rule out.
-}
jobsFromSpecs ∷ [D.ScheduleJobSpec] → Int → Integer → Either ScheduleConfigError [ScheduleJob]
jobsFromSpecs specs defRetryMax defRetryWait = go Set.empty specs
    where
        go _ [] = Right []
        go seen (s : ss)
            | Set.member (D.sjsId s) seen = Left (SceDuplicateId (D.sjsId s))
            | otherwise = (mkJob s :) <$> go (Set.insert (D.sjsId s) seen) ss

        mkJob s =
            ScheduleJob
                { sjId = D.sjsId s
                , sjExpr = D.renderCronExpr (D.sjsSchedule s)
                , sjSchedule = compileCron (D.sjsSchedule s)
                , sjAction = action (D.sjsAction s)
                , sjRoom = D.unRoomId <$> D.sjsRoom s
                , sjSession = maybe ("schedule-" <> D.sjsId s) D.unSessionId (D.sjsSession s)
                , sjSummarize = D.sjsSummarize s
                , sjRetryMax = maybe defRetryMax (fromIntegral . D.unRetryCount) (D.sjsRetryMax s)
                , sjRetryWait = maybe defRetryWait (fromIntegral . D.unSeconds) (D.sjsRetryWait s)
                }

        action = \case
            D.SAPrompt t → ActPrompt t
            D.SATool n margs → ActTool n (argsValue margs)

        -- Tool arguments stay a JSON object string: their schema is the invoked tool's, not ours.
        argsValue Nothing = object []
        argsValue (Just t) = fromMaybe (object []) (decode (BL.fromStrict (encodeUtf8 t)))

-- | One recorded fire.
data Outcome = Outcome
    { ocAt ∷ Integer
    , ocOk ∷ Bool
    , ocDetail ∷ Text
    , ocAttempt ∷ Int
    }
    deriving stock (Eq, Show)

-- | Live per-job state, read by the @schedule_*@ tools.
data JobState = JobState
    { jsNextDue ∷ Maybe Integer
    , jsRetryAt ∷ Maybe Integer
    , jsAttempt ∷ Int
    , jsLastFired ∷ Maybe Integer
    , jsLastOk ∷ Maybe Bool
    , jsRuns ∷ Integer
    , jsFailures ∷ Integer
    , jsConsecutiveFailures ∷ Int
    , jsHistory ∷ [Outcome]
    }
    deriving stock (Eq, Show)

emptyJobState ∷ JobState
emptyJobState = JobState Nothing Nothing 0 Nothing Nothing 0 0 0 []

-- | A registry over a fixed job list plus its live state and a manual-run request queue.
data ScheduleRegistry = ScheduleRegistry
    { srJobs ∷ [ScheduleJob]
    , srState ∷ IORef (Map Text JobState)
    , srRequested ∷ IORef [Int]
    }

-- | Build a registry over @jobs@ and arm each one's first cron slot (relative to @now@ unix seconds).
newRegistry ∷ Integer → [ScheduleJob] → IO ScheduleRegistry
newRegistry now jobs = do
    st ← newIORef (Map.fromList [(sjId j, emptyJobState {jsNextDue = nextAfter (sjSchedule j) now}) | j ← jobs])
    req ← newIORef []
    pure (ScheduleRegistry jobs st req)

-- | The jobs, in registration order.
registryJobs ∷ ScheduleRegistry → [ScheduleJob]
registryJobs = srJobs

-- | A snapshot of one job's state.
stateOf ∷ ScheduleRegistry → Text → IO (Maybe JobState)
stateOf reg jid = Map.lookup jid <$> readIORef (srState reg)

-- | Index of a job by id.
indexOf ∷ ScheduleRegistry → Text → Maybe Int
indexOf reg jid = findIndex ((== jid) . sjId) (srJobs reg)

-- | Queue an out-of-band run of @id@; 'False' if no such job.
requestRun ∷ ScheduleRegistry → Text → IO Bool
requestRun reg jid = case indexOf reg jid of
    Nothing → pure False
    Just i → modifyIORef' (srRequested reg) (<> [i]) >> pure True

-- | Drain and return the queued manual-run job indices.
takeRequested ∷ ScheduleRegistry → IO [Int]
takeRequested reg = atomicModifyIORef' (srRequested reg) (\q → ([], q))

{- | Indices of jobs due to fire at @now@: a pending retry (@retry_at@) if its time has come, else the
next cron slot (@next_due@) if reached. A job in retry never fires on its cron slot until the chain
resolves.
-}
dueJobs ∷ ScheduleRegistry → Integer → IO [Int]
dueJobs reg now = do
    st ← readIORef (srState reg)
    pure [i | (i, j) ← zip [0 ..] (srJobs reg), due (Map.findWithDefault emptyJobState (sjId j) st)]
    where
        due s = case jsRetryAt s of
            Just r → r <= now
            Nothing → maybe False (<= now) (jsNextDue s)

{- | What one fire's bookkeeping decided, for composing its room report. The retry structure lives
here rather than in the posted prose so a @summarize@ paraphrase can never hide or soften it.
-}
data FireRecord = FireRecord
    { frAttempt ∷ Int
    -- ^ 1-based attempt number within the current retry chain.
    , frRetryIn ∷ Maybe Integer
    -- ^ Seconds until the queued retry, when this failure starts\/continues a chain.
    , frGaveUp ∷ Bool
    -- ^ Whether this failure exhausted a non-zero retry budget.
    }
    deriving stock (Eq, Show)

{- | Record a fire's outcome against a job's state (mirrors the Rust @record@): bump counters + the
failure streak, cap history, and set the follow-up — a pending retry suppresses the cron slot
(@next_due = Nothing@) until the chain resolves, then the next slot is recomputed from @now@.
Returns the retry bookkeeping so the report and the schedule agree on one decision.
-}
recordOutcome ∷ ScheduleRegistry → Integer → ScheduleJob → Either Text Text → IO FireRecord
recordOutcome reg now job result =
    atomicModifyIORef' (srState reg) $ \st →
        let s0 = Map.findWithDefault emptyJobState (sjId job) st
            attempt = jsAttempt s0 + 1
            h = jsHistory s0 <> [Outcome now ok detail attempt]
            hist = drop (max 0 (length h - historyCap)) h
            retrying = not ok && attempt <= sjRetryMax job
            s1 =
                s0
                    { jsAttempt = if retrying then attempt else 0
                    , jsRuns = jsRuns s0 + 1
                    , jsLastFired = Just now
                    , jsLastOk = Just ok
                    , jsHistory = hist
                    , jsFailures = if ok then jsFailures s0 else jsFailures s0 + 1
                    , jsConsecutiveFailures = if ok then 0 else jsConsecutiveFailures s0 + 1
                    , jsRetryAt = if retrying then Just (now + sjRetryWait job) else Nothing
                    , jsNextDue = if retrying then Nothing else nextAfter (sjSchedule job) now
                    }
            rec =
                FireRecord
                    { frAttempt = attempt
                    , frRetryIn = if retrying then Just (sjRetryWait job) else Nothing
                    , frGaveUp = not retrying && not ok && sjRetryMax job > 0
                    }
         in (Map.insert (sjId job) s1 st, rec)
    where
        ok = either (const False) (const True) result
        detail = T.take detailCap (either id id result)

{- | The body of a fire's room report (mirrors the Rust @report_body@). @shown@ is the detail slot —
the @summarize@ prose when a job has one, else the raw output. The verdict marker, the attempt
counter, and the retry\/gave-up line are composed __around__ it, so they survive a paraphrase.
-}
reportBody ∷ ScheduleJob → Bool → Text → FireRecord → Text
reportBody job ok shown FireRecord {..}
    | ok =
        let retried
                | frAttempt > 1 = " (after " <> tshow frAttempt <> " attempt" <> plural frAttempt <> ")"
                | otherwise = ""
            d = T.strip shown
         in "\9989 `" <> sjId job <> "`" <> retried <> (if T.null d then "" else " \183 " <> d)
    | otherwise =
        "\10060 `" <> sjId job <> "` failed (attempt " <> tshow frAttempt <> ")\n" <> T.strip shown <> retryLine
    where
        plural n = if n == (1 ∷ Int) then "" else "s"
        retryLine = case frRetryIn of
            Just wait → "\n\8635 retry " <> tshow frAttempt <> "/" <> tshow (sjRetryMax job) <> " in " <> tshow wait <> "s"
            Nothing
                | frGaveUp →
                    "\n\9940 gave up after "
                        <> tshow (sjRetryMax job)
                        <> (if sjRetryMax job == 1 then " retry" else " retries")
                | otherwise → ""

-- --- the schedule_* chat tools ---------------------------------------------------------------------

{- | The three schedule tools bound to a registry (so "how's the disk job?" / "run it again" work in
natural language): @schedule_list@, @schedule_status@, @schedule_run@.
-}
scheduleTools ∷ ScheduleRegistry → [Tool]
scheduleTools reg = [scheduleListTool reg, scheduleStatusTool reg, scheduleRunTool reg]

scheduleListTool ∷ ScheduleRegistry → Tool
scheduleListTool reg =
    Tool
        { toolName = "schedule_list"
        , toolDescription = "List every scheduled job, its schedule, action, and current health."
        , toolSchema = object ["type" .= sv "object", "properties" .= object []]
        , toolInvoke = \_ → do
            st ← readIORef (srState reg)
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

scheduleStatusTool ∷ ScheduleRegistry → Tool
scheduleStatusTool reg =
    Tool
        { toolName = "schedule_status"
        , toolDescription = "Show one scheduled job in detail, including recent run history. Needs `id`."
        , toolSchema = object ["type" .= sv "object", "properties" .= object ["id" .= prop "The job id, as shown by schedule_list"], "required" .= [sv "id"]]
        , toolInvoke = \args → case idArg args of
            Nothing → pure (Right (toolErr "schedule_status: missing `id`"))
            Just jid → do
                ms ← stateOf reg jid
                pure . Right $ case (lookupJob jid, ms) of
                    (Just j, Just s) → toolOk (statusReport j s)
                    _ → toolErr ("schedule_status: no job `" <> jid <> "`")
        }
    where
        lookupJob jid = case filter ((== jid) . sjId) (srJobs reg) of (j : _) → Just j; [] → Nothing

scheduleRunTool ∷ ScheduleRegistry → Tool
scheduleRunTool reg =
    Tool
        { toolName = "schedule_run"
        , toolDescription = "Fire a scheduled job now, out of band. Needs `id`."
        , toolSchema = object ["type" .= sv "object", "properties" .= object ["id" .= prop "The job id, as shown by schedule_list"], "required" .= [sv "id"]]
        , toolInvoke = \args → case idArg args of
            Nothing → pure (Right (toolErr "schedule_run: missing `id`"))
            Just jid → do
                queued ← requestRun reg jid
                pure . Right $
                    if queued
                        then toolOk ("queued an out-of-band run of `" <> jid <> "`")
                        else toolErr ("schedule_run: no job `" <> jid <> "`")
        }

-- --- rendering + arg helpers -----------------------------------------------------------------------

health ∷ JobState → Text
health s = case jsLastOk s of
    Nothing → "never fired, " <> nextText s
    Just True → "last ok, " <> runsText s <> ", " <> nextText s
    Just False → "last FAILED (streak " <> tshow (jsConsecutiveFailures s) <> "), " <> runsText s <> ", " <> nextText s

statusReport ∷ ScheduleJob → JobState → Text
statusReport j s =
    T.intercalate
        "\n"
        ( [ "job: " <> sjId j <> " [" <> sjExpr j <> "]"
          , "action: " <> actionSummary (sjAction j)
          , "room: " <> fromMaybe "(default)" (sjRoom j)
          , "health: " <> health s
          ]
            <> ["history:"]
            <> map histLine (reverse (jsHistory s))
        )
    where
        histLine o = "  " <> (if ocOk o then "ok " else "FAIL") <> " @" <> tshow (ocAt o) <> " (attempt " <> tshow (ocAttempt o) <> "): " <> ocDetail o

runsText ∷ JobState → Text
runsText s = tshow (jsRuns s) <> " runs / " <> tshow (jsFailures s) <> " failed"

nextText ∷ JobState → Text
nextText s = case (jsRetryAt s, jsNextDue s) of
    (Just r, _) → "retry at " <> tshow r
    (Nothing, Just n) → "next at " <> tshow n
    (Nothing, Nothing) → "no further runs"

idArg ∷ Value → Maybe Text
idArg = parseMaybe (withObject "args" (.: "id"))

sv ∷ Text → Value
sv = String

prop ∷ Text → Value
prop d = object ["type" .= sv "string", "description" .= sv d]

tshow ∷ Show a ⇒ a → Text
tshow = T.pack . show
