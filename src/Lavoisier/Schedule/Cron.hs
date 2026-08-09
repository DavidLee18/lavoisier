-- | A small, dependency-free cron-expression engine: parse a standard 5-field expression
-- (@minute hour day-of-month month day-of-week@) and compute the next fire time after a given
-- instant. Ported from Rust @lvz-schedule@ @cron.rs@.
--
-- Hand-rolled (no @cron@\/@chrono@ dep). Time is __UTC__. Fields support @*@, @*\/step@, @a-b@,
-- @a-b\/step@, @a\/step@, single values, and comma-separated lists. Day-of-week is @0-6@ with Sunday
-- @0@ (and @7@ also accepted). When __both__ day-of-month and day-of-week are restricted, a minute
-- matches if __either__ matches (the Vixie-cron convention).
module Lavoisier.Schedule.Cron
  ( CronSchedule,
    CronError (..),
    parseCron,
    nextAfter,
    nextAfterNow,
    -- exposed for testing
    Civil (..),
    civilFromUnix,
  )
where

import Data.Bits (bit, testBit, (.|.))
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time.Clock.POSIX (getPOSIXTime)
import Data.Word (Word64)
import Text.Read (readMaybe)

-- | A parsed cron schedule: five fields, each a bitset of permitted values plus a @star@ flag
-- recording whether the field was an unrestricted @*@ (needed for the dom\/dow OR rule).
data CronSchedule = CronSchedule
  { csMinute :: Field,
    csHour :: Field,
    csDom :: Field,
    csMonth :: Field,
    csDow :: Field
  }
  deriving stock (Eq, Show)

data Field = Field
  { fMask :: Word64,
    fStar :: Bool
  }
  deriving stock (Eq, Show)

fMatches :: Field -> Int -> Bool
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
  { cvMinute :: Int,
    cvHour :: Int,
    cvDom :: Int,
    cvMonth :: Int,
    -- | Day of week, Sunday = 0.
    cvDow :: Int
  }
  deriving stock (Eq, Show)

-- | Parse a standard 5-field cron expression.
parseCron :: Text -> Either CronError CronSchedule
parseCron expr =
  case T.words expr of
    [mi, ho, dm, mo, dw] ->
      CronSchedule
        <$> parseField mi 0 59 False
        <*> parseField ho 0 23 False
        <*> parseField dm 1 31 False
        <*> parseField mo 1 12 False
        <*> parseField dw 0 6 True
    fields -> Left (CronFieldCount (length fields))

-- | The next fire time (Unix seconds, aligned to a minute boundary) strictly __after__ @after@.
-- 'Nothing' if the schedule has no fire within ~4 years (e.g. Feb 30), so the caller can disable the
-- job rather than spin.
nextAfter :: CronSchedule -> Integer -> Maybe Integer
nextAfter sched after = go t0
  where
    t0 = (after `div` 60 + 1) * 60
    cap = t0 + 4 * 366 * 24 * 60 * 60
    go t
      | t > cap = Nothing
      | matchesSched sched (civilFromUnix t) = Just t
      | otherwise = go (t + 60)

-- | Next fire time after /now/ (UTC).
nextAfterNow :: CronSchedule -> IO (Maybe Integer)
nextAfterNow sched = do
  now <- (round :: Double -> Integer) . realToFrac <$> getPOSIXTime
  pure (nextAfter sched now)

matchesSched :: CronSchedule -> Civil -> Bool
matchesSched s c =
  fMatches (csMinute s) (cvMinute c)
    && fMatches (csHour s) (cvHour c)
    && fMatches (csMonth s) (cvMonth c)
    && dayOk
  where
    dayOk = case (fStar (csDom s), fStar (csDow s)) of
      (True, True) -> True
      (False, True) -> fMatches (csDom s) (cvDom c)
      (True, False) -> fMatches (csDow s) (cvDow c)
      -- Both restricted ⇒ OR (Vixie convention).
      (False, False) -> fMatches (csDom s) (cvDom c) || fMatches (csDow s) (cvDow c)

-- | Parse one cron field into a bitset over @[lo0, hi0]@. @dow@ enables the @7 == Sunday@ alias.
parseField :: Text -> Int -> Int -> Bool -> Either CronError Field
parseField field lo0 hi0 dow = do
  masks <- traverse parsePart (T.splitOn "," field)
  pure (Field (foldr (.|.) 0 masks) (T.strip field == "*"))
  where
    bad reason = Left (CronFieldError field reason)
    num s reason = maybe (bad reason) Right (readMaybe (T.unpack s))

    parsePart part = do
      (range, step, hasSlash) <- case T.splitOn "/" part of
        [r] -> Right (r, 1, False)
        [r, s] -> do
          st <- num s "step is not a number"
          if st <= 0 then bad "step must be >= 1" else Right (r, st, True)
        _ -> bad "malformed step"
      (lo, hi) <-
        if range == "*"
          then Right (lo0, hi0)
          else case T.splitOn "-" range of
            [a, b] -> (,) <$> num a "range start is not a number" <*> num b "range end is not a number"
            [v] -> do
              n <- num v "value is not a number"
              -- `N/step` means N through max; a bare `N` is just N.
              Right (if hasSlash then (n, hi0) else (n, n))
            _ -> bad "malformed range"
      if lo > hi
        then bad "range start is greater than range end"
        else buildMask lo hi step

    buildMask lo hi step = go lo 0
      where
        go v acc
          | v > hi = Right acc
          | otherwise =
              -- dow allows 7 as an alias for Sunday (0); folding it makes 7 in-range.
              let val = if dow && v == 7 then 0 else v
               in if val < lo0 || val > hi0
                    then bad "value out of range"
                    else go (v + step) (acc .|. bit val)

-- | Decompose a Unix-second instant into UTC wall-clock components (Howard Hinnant's days→civil
-- algorithm — exact, no external date library). Valid for non-negative instants.
civilFromUnix :: Integer -> Civil
civilFromUnix secs =
  Civil
    { cvMinute = fromInteger ((sod `mod` 3600) `div` 60),
      cvHour = fromInteger (sod `div` 3600),
      cvDom = fromInteger d,
      cvMonth = fromInteger m,
      cvDow = fromInteger dow
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
