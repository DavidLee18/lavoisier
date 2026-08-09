-- | @Lavoisier.Tune@ — adaptive token optimisation (ATO). Ported from Rust @lvz-tune@ @lib.rs@.
--
-- 'LearningTuner' is the online half of the knob-tuning loop: it fulfils the 'Tuner' contract so the
-- agent can swap it in for 'noopTuner' with no other change. Each @(archetype, caching, model-tier,
-- model-id, repo-id)@ context is its own contextual bandit, over which it __ε-greedily hill-climbs__
-- 'Knobs': mostly it exploits the cheapest knob vector that meets a success constraint, occasionally
-- it explores a one-step neighbour on a discrete grid seeded by the baseline.
--
-- Two guarantees keep it safe:
--
--   * __Constrained objective.__ It minimises cost-weighted task tokens only among candidates whose
--     observed success rate clears 'successTarget' — never the cheapest-but-failing vector.
--   * __Bounded by the baseline floor.__ Exploration moves only along a discrete grid centred on
--     'defaultKnobs' (the baseline), and until a candidate is __trusted__ it returns that baseline —
--     so it can never regress below it.
--
-- Caching on\/off, the concrete model id, and the repo id are all part of the profile key (major
-- confounders \/ non-stationarity). The controller is pure in-memory bookkeeping behind an
-- 'IORef'; 'select'\/'observe' are atomic read-modify-writes.
--
-- Wired here: the real success signal (reported by the agent), model-version + per-repo keying,
-- observation decay (an EWMA for non-stationarity), the exact byte-identical truncate counterfactual,
-- and profile persistence ('saveTuner'\/'loadTuner'). Deferred: Bayesian optimisation (@BayesTuner@).
module Lavoisier.Tune
  ( TuneConfig (..),
    defaultTuneConfig,
    LearningTuner,
    newLearningTuner,
    learningTuner,
    asTuner,
    saveTuner,
    loadTuner,
    -- exposed for testing
    allNeighbours,
    step,
    contextFootprint,
    nextWord64,
    nextDouble,
    dials,
  )
where

import Control.Exception (SomeException, try)
import Data.Aeson (FromJSON, ToJSON, eitherDecodeStrict, encode)
import Data.Bits (shiftL, shiftR, xor)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.IORef
import Data.List (minimumBy)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Ord (comparing)
import Data.Text (Text)
import Data.Word (Word64)
import GHC.Generics (Generic)
import Lavoisier.Protocol.Message (ThinkingLevel (..))
import Lavoisier.Protocol.Provider (Capabilities (..))
import Lavoisier.Protocol.Tune
import System.Directory (doesFileExist)

-- | Tuning hyper-parameters.
data TuneConfig = TuneConfig
  { -- | Probability of exploring a neighbour instead of exploiting the best known vector.
    epsilon :: Double,
    -- | Minimum observed success rate for a candidate to be eligible as "best".
    successTarget :: Double,
    -- | Minimum trials before a candidate is trusted (avoids chasing lucky one-offs).
    minTrials :: Double,
    -- | Per-observation decay in @(0, 1]@ for non-stationarity: before a candidate folds in a new
    -- sample its stats are multiplied by this factor, so recent outcomes weigh more. @1.0@ = no
    -- decay; @0.9@ ≈ a soft ~10-sample memory.
    decay :: Double
  }
  deriving stock (Eq, Show)

-- | Defaults: ε=0.1, success target 0.9, 3 trials, no decay.
defaultTuneConfig :: TuneConfig
defaultTuneConfig = TuneConfig 0.1 0.9 3 1.0

-- | Profile key: the context features knob optima depend on. Caching is carried explicitly (the
-- dominant confounder); the concrete model id is keyed alongside the coarse tier so a model upgrade
-- starts a fresh profile.
data ContextKey = ContextKey
  { ckArchetype :: Archetype,
    ckCaching :: Bool,
    ckModel :: ModelTier,
    ckModelId :: Text,
    ckRepoId :: Text
  }
  deriving stock (Eq, Ord, Show, Generic)

instance ToJSON ContextKey

instance FromJSON ContextKey

keyOf :: TaskContext -> ContextKey
keyOf ctx =
  ContextKey
    { ckArchetype = tcArchetype ctx,
      ckCaching = promptCaching (tcCaps ctx),
      ckModel = tcModel ctx,
      ckModelId = tcModelId ctx,
      ckRepoId = tcRepoId ctx
    }

-- | Running (optionally decayed) stats for one knob vector under one context. Fields are 'Double' so
-- a @< 1.0@ decay factor can down-weight old samples (an EWMA); at @1.0@ they are exact totals.
data Stats = Stats
  { trials :: Double,
    successes :: Double,
    -- | (Decay-weighted) summed tokens over __successful__ runs.
    successTokens :: Double
  }
  deriving stock (Eq, Show, Generic)

instance ToJSON Stats

instance FromJSON Stats

emptyStats :: Stats
emptyStats = Stats 0 0 0

successRate :: Stats -> Double
successRate s
  | trials s == 0 = 0
  | otherwise = successes s / trials s

meanTokens :: Stats -> Maybe Double
meanTokens s
  | successes s > 0 = Just (successTokens s / successes s)
  | otherwise = Nothing

trusted :: TuneConfig -> Stats -> Bool
trusted cfg s = trials s >= minTrials cfg && successRate s >= successTarget cfg

-- | The learner's mutable state: per-context candidate stats + the PRNG cursor.
data TuneState = TuneState
  { profiles :: Map ContextKey (Map Knobs Stats),
    rng :: Word64
  }

-- | The ε-greedy learning tuner. Share it freely; its state is behind an 'IORef'.
data LearningTuner = LearningTuner
  { ltConfig :: TuneConfig,
    ltState :: IORef TuneState
  }

-- Fixed non-zero seed: reproducible exploration; ε-greedy needs no crypto RNG.
initialSeed :: Word64
initialSeed = 0x9E3779B97F4A7C15

-- | A cold tuner — knows nothing yet, so it returns the baseline.
newLearningTuner :: TuneConfig -> IO LearningTuner
newLearningTuner cfg = LearningTuner cfg <$> newIORef (TuneState Map.empty initialSeed)

-- | Adapt a 'LearningTuner' to the 'Tuner' record so the agent can hold it uniformly.
asTuner :: LearningTuner -> Tuner
asTuner lt =
  Tuner
    { tunerSelect = selectKnobs lt,
      tunerObserve = observeOutcome lt
    }

-- | Build a cold learner already wrapped as a 'Tuner' (the common case for the CLI).
learningTuner :: TuneConfig -> IO Tuner
learningTuner cfg = asTuner <$> newLearningTuner cfg

-- --- select / observe ------------------------------------------------------------------------------

-- | Choose knobs for a task: register the baseline candidate, find the cheapest trusted vector, then
-- with probability ε explore a one-step neighbour (registered so it can accrue stats). Atomic.
selectKnobs :: LearningTuner -> TaskContext -> IO Knobs
selectKnobs lt ctx = atomicModifyIORef' (ltState lt) (pickKnobs (ltConfig lt) (keyOf ctx))

pickKnobs :: TuneConfig -> ContextKey -> TuneState -> (TuneState, Knobs)
pickKnobs cfg key st0 =
  let st1 = ensureCandidate key defaultKnobs st0
      candidates = Map.findWithDefault Map.empty key (profiles st1)
      best = fromMaybe defaultKnobs (bestCandidate cfg candidates)
      (r, rng1) = nextDouble (rng st1)
   in if r < epsilon cfg
        then
          let (whichW, rng2) = nextWord64 rng1
              which = fromIntegral (whichW `mod` fromIntegral dials)
              (upW, rng3) = nextWord64 rng2
              up = even upW
              explored = step best which up
              st2 = ensureCandidate key explored st1 {rng = rng3}
           in (st2, explored)
        else (st1 {rng = rng1}, best)

-- | Fold a realised outcome into the used vector's stats, plus any provably-equivalent cheaper
-- truncate values (the safe counterfactual). Atomic.
observeOutcome :: LearningTuner -> TaskContext -> Knobs -> Outcome -> IO ()
observeOutcome lt ctx used out =
  atomicModifyIORef' (ltState lt) $ \st ->
    (recordAll (ltConfig lt) (keyOf ctx) used out st, ())

recordAll :: TuneConfig -> ContextKey -> Knobs -> Outcome -> TuneState -> TuneState
recordAll cfg key used out st0 =
  let st1 = updateStats key used out (decay cfg) st0
   in -- Safe counterfactual: if nothing in the task exceeded the truncate limit actually used, then
      -- every cheaper grid value still ≥ the largest result would have produced a byte-identical
      -- transcript — identical tokens and success. Credit those provably-equivalent vectors so the
      -- learner discovers cheaper truncate settings without ever risking a starved live trial.
      case otMaxToolResultBytes out of
        Just maxBytes
          | maxBytes <= truncateBytes used ->
              foldl'
                ( \st b ->
                    if b >= maxBytes && b < truncateBytes used
                      then updateStats key (used {truncateBytes = b}) out (decay cfg) st
                      else st
                )
                st1
                truncateGrid
        _ -> st1

updateStats :: ContextKey -> Knobs -> Outcome -> Double -> TuneState -> TuneState
updateStats key knobs out d st =
  st {profiles = Map.alter (Just . bumpCandidate) key (profiles st)}
  where
    bumpCandidate = Map.alter (Just . record out d . fromMaybe emptyStats) knobs . fromMaybe Map.empty

-- | Fold one realised (or counterfactual) outcome into a candidate's stats, first decaying the prior
-- totals (an EWMA when @decay < 1@; plain accumulation at @1@).
record :: Outcome -> Double -> Stats -> Stats
record out d s
  | otSuccess out =
      Stats
        { trials = trials s * d + 1,
          successes = successes s * d + 1,
          successTokens = successTokens s * d + fromIntegral (otTotalTokens out)
        }
  | otherwise =
      -- Decay the success side too, so a run of failures fades past success evidence.
      Stats
        { trials = trials s * d + 1,
          successes = successes s * d,
          successTokens = successTokens s * d
        }

-- | Register a knob vector as a live candidate (cold stats) if not already present.
ensureCandidate :: ContextKey -> Knobs -> TuneState -> TuneState
ensureCandidate key knobs st =
  st {profiles = Map.alter (Just . addKnob) key (profiles st)}
  where
    addKnob = Map.alter (Just . fromMaybe emptyStats) knobs . fromMaybe Map.empty

-- | The cheapest trusted candidate (lowest mean tokens among those meeting the success constraint),
-- or 'Nothing' if nothing is trusted yet. Ties on mean tokens break toward the __least context
-- carried__ ('contextFootprint') — deterministic, and what makes the truncate counterfactual bite.
bestCandidate :: TuneConfig -> Map Knobs Stats -> Maybe Knobs
bestCandidate cfg candidates =
  case [(k, m) | (k, s) <- Map.toList candidates, trusted cfg s, Just m <- [meanTokens s]] of
    [] -> Nothing
    xs -> Just (fst (minimumBy (comparing (\(k, m) -> (m, contextFootprint k))) xs))

-- | Tie-break key: the context a knob vector carries (smaller = preferred), ordered by the dials
-- that grow the prompt — truncate ceiling, then skeleton radius, then compaction threshold.
contextFootprint :: Knobs -> (Int, Int, Int)
contextFootprint k = (truncateBytes k, skeletonRadius k, compactAfter k)

-- --- persistence -----------------------------------------------------------------------------------

-- | One learned @(context, knobs) → stats@ row in a snapshot. The nested maps flatten to a list
-- because their keys are records (which can't be JSON object keys).
data Row = Row
  { rowKey :: ContextKey,
    rowKnobs :: Knobs,
    rowStats :: Stats
  }
  deriving stock (Generic)

instance ToJSON Row

instance FromJSON Row

-- | The persisted learner state (profiles + PRNG cursor).
data Snapshot = Snapshot
  { snapRows :: [Row],
    snapRng :: Word64
  }
  deriving stock (Generic)

instance ToJSON Snapshot

instance FromJSON Snapshot

-- | Serialise the learned profiles (and PRNG cursor) to @path@ as JSON, so a long-running or
-- restarted gateway keeps what it learned.
saveTuner :: LearningTuner -> FilePath -> IO ()
saveTuner lt path = do
  st <- readIORef (ltState lt)
  let rows =
        [ Row key knobs stats
          | (key, cands) <- Map.toList (profiles st),
            (knobs, stats) <- Map.toList cands
        ]
  BL.writeFile path (encode (Snapshot rows (rng st)))

-- | Build a tuner pre-loaded from a 'saveTuner'd snapshot. A missing file yields a cold tuner (first
-- run), so callers can pass a path unconditionally. A corrupt file is an error.
loadTuner :: FilePath -> TuneConfig -> IO (Either String LearningTuner)
loadTuner path cfg = do
  exists <- doesFileExist path
  if not exists
    then Right <$> newLearningTuner cfg
    else do
      eb <- try (BS.readFile path) :: IO (Either SomeException BS.ByteString)
      case eb of
        Left e -> pure (Left (show e))
        Right bytes -> case eitherDecodeStrict bytes of
          Left e -> pure (Left e)
          Right snap -> do
            let profs = foldl' insertRow Map.empty (snapRows snap)
                seed = if snapRng snap /= 0 then snapRng snap else initialSeed
            ref <- newIORef (TuneState profs seed)
            pure (Right (LearningTuner cfg ref))
  where
    insertRow m (Row key knobs stats) =
      Map.alter (Just . Map.insert knobs stats . fromMaybe Map.empty) key m

-- --- discrete knob grids (centred on defaultKnobs), and one-step neighbour moves -------------------

radiusGrid :: [Int]
radiusGrid = [0, 1, 2, 3]

truncateGrid :: [Int]
truncateGrid = [2048, 4096, 8192, 16384, 32768]

compactGrid :: [Int]
compactGrid = [8000, 16000, 24000, 32000, 48000, 64000]

batchGrid :: [Int]
batchGrid = [1, 2, 4, 8]

-- | Thinking-effort dial, cheapest→most expensive. 'Nothing' (the floor) defers to the agent's
-- per-archetype default; the explicit levels let the learner push thinking down or up.
thinkingGrid :: [Maybe ThinkingLevel]
thinkingGrid = [Nothing, Just ThinkOff, Just ThinkLow, Just ThinkMedium, Just ThinkHigh]

-- | Number of tunable dials (radius, truncate, compact, batch, thinking).
dials :: Int
dials = 5

-- | Step one dial to an adjacent grid value (clamped). Dial index 0..4; index ≥4 is the thinking
-- dial.
step :: Knobs -> Int -> Bool -> Knobs
step k which up = case which of
  0 -> k {skeletonRadius = neighbour radiusGrid (skeletonRadius k) up}
  1 -> k {truncateBytes = neighbour truncateGrid (truncateBytes k) up}
  2 -> k {compactAfter = neighbour compactGrid (compactAfter k) up}
  3 -> k {batchWidth = neighbour batchGrid (batchWidth k) up}
  _ -> k {knobThinking = neighbour thinkingGrid (knobThinking k) up}

-- | All distinct one-step grid neighbours of @knobs@ (both directions on every dial, clamped; the
-- centre itself excluded).
allNeighbours :: Knobs -> [Knobs]
allNeighbours knobs =
  foldl'
    (\acc n -> if n /= knobs && n `notElem` acc then acc <> [n] else acc)
    []
    [step knobs which up | which <- [0 .. dials - 1], up <- [True, False]]

-- | Adjacent grid value (clamped at the ends). Off-grid inputs snap to the nearest cell first.
neighbour :: (Ord a) => [a] -> a -> Bool -> a
neighbour grid current up =
  let idx = case [i | (i, v) <- zip [0 ..] grid, v == current] of
        (i : _) -> i
        [] -> case [i | (i, v) <- zip [0 ..] grid, v >= current] of
          (i : _) -> i
          [] -> length grid - 1
      next = if up then min (idx + 1) (length grid - 1) else max (idx - 1) 0
   in grid !! next

-- --- xorshift64 PRNG (no `random` dependency) ------------------------------------------------------

-- | One xorshift64 step: returns the next value and the advanced state.
nextWord64 :: Word64 -> (Word64, Word64)
nextWord64 s0 =
  let x1 = s0 `xor` (s0 `shiftL` 13)
      x2 = x1 `xor` (x1 `shiftR` 7)
      x3 = x2 `xor` (x2 `shiftL` 17)
   in (x3, x3)

-- | A uniform double in @[0, 1)@ from the top 53 bits, plus the advanced state.
nextDouble :: Word64 -> (Double, Word64)
nextDouble s0 =
  let (x, s1) = nextWord64 s0
   in (fromIntegral (x `shiftR` 11) / fromIntegral ((1 :: Word64) `shiftL` 53), s1)
