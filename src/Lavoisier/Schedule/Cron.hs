{- | A small, dependency-free cron-expression engine: parse a standard 5-field expression
(@minute hour day-of-month month day-of-week@) and compute the next fire time after a given
instant. Ported from Rust @lvz-schedule@ @cron.rs@.

Hand-rolled (no @cron@\/@chrono@ dep). Time is __UTC__. Fields support @*@, @*\/step@, @a-b@,
@a-b\/step@, @a\/step@, single values, and comma-separated lists. Day-of-week is @0-6@ with Sunday
@0@ (and @7@ also accepted). When __both__ day-of-month and day-of-week are restricted, a minute
matches if __either__ matches (the Vixie-cron convention).
-}
module Lavoisier.Schedule.Cron (
    CronSchedule,
    CronError (..),
    cronErrorText,
    compileCron,
    parseCronExpr,
    parseCron,
    nextAfter,
    nextAfterNow,
    -- exposed for testing
    Civil (..),
    civilFromUnix,
)
where

import Data.Bits (bit, testBit, (.|.))
import Data.List.NonEmpty (NonEmpty (..))
import Data.Text (Text)
import Data.Time.Clock.POSIX (getPOSIXTime)
import Data.Word (Word64)
import Text.Read (readMaybe)

import Data.List.NonEmpty qualified as NE
import Data.Text qualified as T

import Lavoisier.Domain (
    CronBase (..),
    CronExpr,
    CronFieldKind (..),
    CronTerm (..),
    cfKind,
    cfTerms,
    cronFieldBounds,
    cronFields,
    mkCronExpr,
 )

{- | A parsed cron schedule: five fields, each a bitset of permitted values plus a @star@ flag
recording whether the field was an unrestricted @*@ (needed for the dom\/dow OR rule).
-}
data CronSchedule = CronSchedule
    { csMinute ∷ Field
    , csHour ∷ Field
    , csDom ∷ Field
    , csMonth ∷ Field
    , csDow ∷ Field
    }
    deriving stock (Eq, Show)

data Field = Field
    { fMask ∷ Word64
    , fStar ∷ Bool
    }
    deriving stock (Eq, Show)

fMatches ∷ Field → Int → Bool
fMatches f v = testBit (fMask f) v

-- | A failure parsing a cron expression.
data CronError
    = -- | The expression did not have exactly five whitespace-separated fields.
      CronFieldCount Int
    | -- | A field was malformed or out of range (the offending text + why).
      CronFieldError Text Text
    deriving stock (Eq, Show)

-- | Broken-down UTC wall-clock components used for matching.
data Civil = Civil
    { cvMinute ∷ Int
    , cvHour ∷ Int
    , cvDom ∷ Int
    , cvMonth ∷ Int
    , cvDow ∷ Int
    -- ^ Day of week, Sunday = 0.
    }
    deriving stock (Eq, Show)

-- | A 'CronError' as the message a user sees, rather than its 'Show' output.
cronErrorText ∷ CronError → Text
cronErrorText = \case
    CronFieldCount n →
        "expected 5 whitespace-separated schedule fields, got " <> T.pack (show n)
    CronFieldError field reason → field <> ": " <> reason

{- | Compile a checked 'CronExpr' into the matching bitsets.

__Total.__ Every value in a 'Lavoisier.Domain.CronField' was range-checked when the field was
built, so there is nothing left here that can fail. That is the point of the ADT: a bad schedule
is now a /config load/ error naming its field, and by the time a gateway starts there is no
deferred failure left to report.
-}
compileCron ∷ CronExpr → CronSchedule
compileCron e = case map field (cronFields e) of
    [mi, ho, dm, mo, dw] → CronSchedule mi ho dm mo dw
    -- 'cronFields' returns exactly five; this arm exists only to keep the match exhaustive.
    _ → CronSchedule (star Minute) (star Hour) (star DayOfMonth) (star Month) (star DayOfWeek)
    where
        star k = compileField k [CronTerm EveryValue Nothing]
        field f = compileField (cfKind f) (NE.toList (cfTerms f))

-- | One field's terms → a bitset, plus the @*@ flag the dom\/dow OR rule needs.
compileField ∷ CronFieldKind → [CronTerm] → Field
compileField kind terms = Field (foldr ((.|.) . termMask) 0 terms) isStar
    where
        (lo0, hi0) = cronFieldBounds kind
        isStar = case terms of
            [CronTerm EveryValue Nothing] → True
            _ → False

        termMask t =
            let step = maybe 1 id (ctStep t)
                (lo, hi) = case ctBase t of
                    EveryValue → (lo0, hi0)
                    -- `N/step` means N through the maximum; a bare `N` is just N.
                    Exactly n → (n, if ctStep t == Nothing then n else hi0)
                    Between a b → (a, b)
             in foldr ((.|.) . bit . fold) 0 [lo, lo + step .. hi]

        -- Day-of-week accepts 7 for Sunday; fold it so the bitset stays 0-6.
        fold v = if kind == DayOfWeek && v == 7 then 0 else v

{- | Parse a standard 5-field cron string into a checked 'CronExpr'. This is the __string__ surface
— the @--cron@ flag, and the crontab spelling people paste in from an existing crontab. The config
file builds a 'CronExpr' directly from its named fields and never comes through here.
-}
parseCronExpr ∷ Text → Either CronError CronExpr
parseCronExpr expr =
    case T.words expr of
        [mi, ho, dm, mo, dw] → do
            terms ← traverse parseTerms [mi, ho, dm, mo, dw]
            case terms of
                [a, b, c, d, e] →
                    either (Left . CronFieldError expr) Right (mkCronExpr a b c d e)
                _ → Left (CronFieldCount (length terms))
        fields → Left (CronFieldCount (length fields))

-- | Parse one field's text into terms. Range checking is 'mkCronExpr'\'s job, not this one\'s.
parseTerms ∷ Text → Either CronError (NonEmpty CronTerm)
parseTerms field = case T.splitOn "," field of
    -- 'T.splitOn' never returns an empty list, so the second arm is unreachable; it is here
    -- because the type of 'T.splitOn' cannot say so, and a field with no terms is exactly what
    -- the 'NonEmpty' upstream of here exists to rule out.
    (p : ps) → traverse parsePart (p :| ps)
    [] → bad "a cron field needs at least one term"
    where
        bad reason = Left (CronFieldError field reason)
        num s reason = maybe (bad reason) Right (readMaybe (T.unpack s))

        parsePart part = do
            (range, step) ← case T.splitOn "/" part of
                [r] → Right (r, Nothing)
                [r, st] → (\n → (r, Just n)) <$> num st "step is not a number"
                _ → bad "malformed step"
            base ←
                if range == "*"
                    then Right EveryValue
                    else case T.splitOn "-" range of
                        [a, b] → Between <$> num a "range start is not a number" <*> num b "range end is not a number"
                        [v] → Exactly <$> num v "value is not a number"
                        _ → bad "malformed range"
            Right (CronTerm base step)

-- | Parse a cron string straight to a schedule — 'parseCronExpr' then 'compileCron'.
parseCron ∷ Text → Either CronError CronSchedule
parseCron = fmap compileCron . parseCronExpr

{- | The next fire time (Unix seconds, aligned to a minute boundary) strictly __after__ @after@.
'Nothing' if the schedule has no fire within ~4 years (e.g. Feb 30), so the caller can disable the
job rather than spin.
-}
nextAfter ∷ CronSchedule → Integer → Maybe Integer
nextAfter sched after = go t0
    where
        t0 = (after `div` 60 + 1) * 60
        cap = t0 + 4 * 366 * 24 * 60 * 60
        go t
            | t > cap = Nothing
            | matchesSched sched (civilFromUnix t) = Just t
            | otherwise = go (t + 60)

-- | Next fire time after /now/ (UTC).
nextAfterNow ∷ CronSchedule → IO (Maybe Integer)
nextAfterNow sched = do
    now ← (round ∷ Double → Integer) . realToFrac <$> getPOSIXTime
    pure (nextAfter sched now)

matchesSched ∷ CronSchedule → Civil → Bool
matchesSched s c =
    fMatches (csMinute s) (cvMinute c)
        && fMatches (csHour s) (cvHour c)
        && fMatches (csMonth s) (cvMonth c)
        && dayOk
    where
        dayOk = case (fStar (csDom s), fStar (csDow s)) of
            (True, True) → True
            (False, True) → fMatches (csDom s) (cvDom c)
            (True, False) → fMatches (csDow s) (cvDow c)
            -- Both restricted ⇒ OR (Vixie convention).
            (False, False) → fMatches (csDom s) (cvDom c) || fMatches (csDow s) (cvDow c)

{- | Decompose a Unix-second instant into UTC wall-clock components (Howard Hinnant's days→civil
algorithm — exact, no external date library). Valid for non-negative instants.
-}
civilFromUnix ∷ Integer → Civil
civilFromUnix secs =
    Civil
        { cvMinute = fromInteger ((sod `mod` 3600) `div` 60)
        , cvHour = fromInteger (sod `div` 3600)
        , cvDom = fromInteger d
        , cvMonth = fromInteger m
        , cvDow = fromInteger dow
        }
    where
        days = secs `div` 86400
        sod = secs `mod` 86400
        -- 1970-01-01 was a Thursday; Sunday = 0.
        dow = (days `mod` 7 + 4) `mod` 7
        -- days-from-civil inverse (Hinnant). `z` shifts the epoch to 0000-03-01.
        z = days + 719468
        era = (if z >= 0 then z else z - 146096) `div` 146097
        doe = z - era * 146097 -- [0, 146096]
        yoe = (doe - doe `div` 1460 + doe `div` 36524 - doe `div` 146096) `div` 365 -- [0, 399]
        doy = doe - (365 * yoe + yoe `div` 4 - yoe `div` 100) -- [0, 365]
        mp = (5 * doy + 2) `div` 153 -- [0, 11]
        d = doy - (153 * mp + 2) `div` 5 + 1 -- [1, 31]
        m = if mp < 10 then mp + 3 else mp - 9 -- [1, 12]
