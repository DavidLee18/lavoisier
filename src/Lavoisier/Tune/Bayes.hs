-- | @Lavoisier.Tune.Bayes@ — a Thompson-sampling alternative to the ε-greedy 'Lavoisier.Tune'
-- learner. Ported from Rust @lvz-tune@ @bayes.rs@.
--
-- Same 'Tuner' contract, same discrete knob grid and baseline floor, but selection is __Bayesian__:
-- each candidate carries a Beta posterior over its success probability and a Gaussian posterior over
-- its cost, and 'tunerSelect' /samples/ from those posteriors and picks the cheapest sample that
-- meets the success target. Posterior uncertainty drives exploration automatically — no explicit ε.
--
-- Like the hill-climb it keeps the candidate set small (the baseline plus the one-step grid
-- neighbours of the baseline and of the current empirical best), so it stays tractable. The samplers
-- are hand-rolled (Box–Muller normal, Marsaglia–Tsang gamma → beta) over the same dependency-free
-- xorshift PRNG, so a run is reproducible. Persistence ('saveBayes'\/'loadBayes') snapshots the
-- posteriors + PRNG cursor as JSON, so @--tune-bayes --tune-state \<path\>@ carries learning across
-- restarts. Still experimental — opt in with @--tune-bayes@.
module Lavoisier.Tune.Bayes
  ( BayesTuner,
    newBayesTuner,
    bayesTuner,
    asBayesTuner,
    saveBayes,
    loadBayes,
    -- exposed for testing
    sampleBeta,
    nextGaussian,
  )
where

import Control.Exception (SomeException, try)
import Data.Aeson (FromJSON, ToJSON, eitherDecodeStrict, encode)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.IORef
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Word (Word64)
import GHC.Generics (Generic)
import Lavoisier.Protocol.Tune
import Lavoisier.Tune (ContextKey (..), TuneConfig (..), allNeighbours, contextFootprint, keyOf, nextDouble)
import System.Directory (doesFileExist)

-- | Beta(successes+1, failures+1) over success probability, and a Welford mean\/variance over the
-- token cost of __successful__ runs (cost-when-it-works), per knob vector under one context.
data BayesStats = BayesStats
  { successes :: Double,
    failures :: Double,
    costN :: Double,
    costMean :: Double,
    costM2 :: Double
  }
  deriving stock (Eq, Show, Generic)

instance ToJSON BayesStats

instance FromJSON BayesStats

emptyBayes :: BayesStats
emptyBayes = BayesStats 0 0 0 0 0

-- | Fold one outcome into a posterior: a Welford update of the success-cost mean\/variance on
-- success, else a failure tally.
recordBayes :: Outcome -> BayesStats -> BayesStats
recordBayes out s
  | otSuccess out =
      let tokens = fromIntegral (otTotalTokens out)
          n = costN s + 1
          delta = tokens - costMean s
          mean' = costMean s + delta / n
          m2' = costM2 s + delta * (tokens - mean')
       in s {successes = successes s + 1, costN = n, costMean = mean', costM2 = m2'}
  | otherwise = s {failures = failures s + 1}

-- | Standard error of the cost mean (0 until ≥2 successes).
costStderr :: BayesStats -> Double
costStderr s
  | costN s < 2 = 0
  | otherwise = sqrt (costM2 s / (costN s - 1)) / sqrt (costN s)

-- | The Thompson-sampling learner's mutable state: per-context posteriors + the PRNG cursor.
data BayesState = BayesState
  { bsProfiles :: Map ContextKey (Map Knobs BayesStats),
    bsRng :: Word64
  }

-- | A Thompson-sampling 'Tuner'. Share it freely; its state is behind an 'IORef'.
data BayesTuner = BayesTuner
  { btConfig :: TuneConfig,
    btState :: IORef BayesState
  }

-- Distinct fixed seed from the ε-greedy learner (reproducible sampling).
bayesSeed :: Word64
bayesSeed = 0x2545F4914F6CDD1D

-- | A cold tuner — flat posteriors, so it returns the baseline until it has evidence.
newBayesTuner :: TuneConfig -> IO BayesTuner
newBayesTuner cfg = BayesTuner cfg <$> newIORef (BayesState Map.empty bayesSeed)

-- | Adapt a 'BayesTuner' to the 'Tuner' record.
asBayesTuner :: BayesTuner -> Tuner
asBayesTuner bt =
  Tuner
    { tunerSelect = selectBayes bt,
      tunerObserve = observeBayes bt
    }

-- | Build a cold Thompson learner already wrapped as a 'Tuner' (the common case for the CLI).
bayesTuner :: TuneConfig -> IO Tuner
bayesTuner cfg = asBayesTuner <$> newBayesTuner cfg

-- --- select / observe ------------------------------------------------------------------------------

selectBayes :: BayesTuner -> TaskContext -> IO Knobs
selectBayes bt ctx = atomicModifyIORef' (btState bt) (pickBayes (btConfig bt) (keyOf ctx))

pickBayes :: TuneConfig -> ContextKey -> BayesState -> (BayesState, Knobs)
pickBayes cfg key st0 =
  let cands0 = Map.findWithDefault Map.empty key (bsProfiles st0)
      target = successTarget cfg
      best = empiricalBest target cands0
      -- Frontier: the baseline (the floor) is always present, plus the one-step neighbours of the
      -- baseline and of the current empirical best, so the search can still climb.
      frontier = defaultKnobs : allNeighbours defaultKnobs <> allNeighbours best
      cands1 = foldl' (\m k -> Map.insertWith (\_ old -> old) k emptyBayes m) cands0 frontier
      -- Optimistic cost prior for never-succeeded candidates: the cheapest mean seen so far (or 0
      -- when nothing has succeeded yet), so unexplored vectors are worth a sample.
      optimistic = case [costMean s | s <- Map.elems cands1, costN s > 0] of
        [] -> 0
        xs -> minimum xs
      (chosen, rng') = thompson target optimistic (Map.toList cands1) (bsRng st0)
      st1 = st0 {bsProfiles = Map.insert key cands1 (bsProfiles st0), bsRng = rng'}
   in (st1, chosen)

-- | Thompson draw per candidate: sample success prob from its Beta, sample cost from its Gaussian
-- (optimistic prior when unseen). Pick the cheapest draw clearing the target; if none do, move
-- toward feasibility (highest sampled success prob). Threads the PRNG through every draw.
thompson :: Double -> Double -> [(Knobs, BayesStats)] -> Word64 -> (Knobs, Word64)
thompson target optimistic cands rng0 =
  let (feasible, fallback, rngN) = foldl' draw (Nothing, Nothing, rng0) cands
      chosen = case feasible of
        Just (k, _) -> k
        Nothing -> maybe defaultKnobs fst fallback
   in (chosen, rngN)
  where
    draw (feas, fb, r) (knobs, s) =
      let (p, r1) = sampleBeta (successes s + 1) (failures s + 1) r
          (cost, r2) =
            if costN s == 0
              then (optimistic, r1)
              else let (g, rr) = nextGaussian r1 in (costMean s + costStderr s * g, rr)
       in if p >= target
            then (if betterCost feas knobs cost then Just (knobs, cost) else feas, fb, r2)
            else (feas, if maybe True (\(_, bp) -> p > bp) fb then Just (knobs, p) else fb, r2)

-- | True when @(knobs, cost)@ should replace the incumbent feasible pick: strictly cheaper, or equal
-- cost but carrying less context (the same least-context tie-break as the hill-climb).
betterCost :: Maybe (Knobs, Double) -> Knobs -> Double -> Bool
betterCost Nothing _ _ = True
betterCost (Just (bk, bc)) knobs cost =
  cost < bc || (cost == bc && contextFootprint knobs < contextFootprint bk)

-- | The cheapest candidate (by mean success-cost) whose observed success rate clears the target, or
-- the baseline when none qualifies yet — the centre the frontier expands around.
empiricalBest :: Double -> Map Knobs BayesStats -> Knobs
empiricalBest target cands =
  case [ (k, costMean s)
       | (k, s) <- Map.toList cands,
         let t = successes s + failures s,
         costN s > 0 && t > 0 && successes s / t >= target
       ] of
    [] -> defaultKnobs
    xs -> fst (minimumByCost xs)
  where
    minimumByCost = foldr1 (\a b -> if snd a <= snd b then a else b)

observeBayes :: BayesTuner -> TaskContext -> Knobs -> Outcome -> IO ()
observeBayes bt ctx used out =
  atomicModifyIORef' (btState bt) $ \st ->
    let key = keyOf ctx
        bump = Map.insertWith (\_ old -> recordBayes out old) used (recordBayes out emptyBayes)
        profs = Map.insertWith (\_ old -> bump old) key (bump Map.empty) (bsProfiles st)
     in (st {bsProfiles = profs}, ())

-- --- persistence -----------------------------------------------------------------------------------

data Row = Row
  { rowKey :: ContextKey,
    rowKnobs :: Knobs,
    rowStats :: BayesStats
  }
  deriving stock (Generic)

instance ToJSON Row

instance FromJSON Row

data Snapshot = Snapshot
  { snapRows :: [Row],
    snapRng :: Word64
  }
  deriving stock (Generic)

instance ToJSON Snapshot

instance FromJSON Snapshot

-- | Serialise the learned posteriors (and PRNG cursor) to @path@ as JSON.
saveBayes :: BayesTuner -> FilePath -> IO ()
saveBayes bt path = do
  st <- readIORef (btState bt)
  let rows =
        [ Row key knobs stats
        | (key, cands) <- Map.toList (bsProfiles st),
          (knobs, stats) <- Map.toList cands
        ]
  BL.writeFile path (encode (Snapshot rows (bsRng st)))

-- | Build a tuner pre-loaded from a 'saveBayes'd snapshot. A missing file yields a cold tuner (first
-- run). A corrupt file is an error.
loadBayes :: FilePath -> TuneConfig -> IO (Either String BayesTuner)
loadBayes path cfg = do
  exists <- doesFileExist path
  if not exists
    then Right <$> newBayesTuner cfg
    else do
      eb <- try (BS.readFile path) :: IO (Either SomeException BS.ByteString)
      case eb of
        Left e -> pure (Left (show e))
        Right bytes -> case eitherDecodeStrict bytes of
          Left e -> pure (Left e)
          Right snap -> do
            let profs = foldl' insertRow Map.empty (snapRows snap)
                seed = if snapRng snap /= 0 then snapRng snap else bayesSeed
            ref <- newIORef (BayesState profs seed)
            pure (Right (BayesTuner cfg ref))
  where
    insertRow m (Row key knobs stats) =
      Map.insertWith (\_ old -> Map.insert knobs stats old) key (Map.singleton knobs stats) m

-- --- hand-rolled samplers (no `random`/`statistics`), driven by the shared xorshift PRNG ----------

-- | A standard normal draw via Box–Muller, plus the advanced PRNG state.
nextGaussian :: Word64 -> (Double, Word64)
nextGaussian r0 =
  let (u1', r1) = nextDouble r0
      u1 = max 1e-12 u1'
      (u2, r2) = nextDouble r1
   in (sqrt (-2 * log u1) * cos (2 * pi * u2), r2)

-- | A Gamma(shape, 1) draw via Marsaglia–Tsang (valid for @shape >= 1@, which always holds here —
-- the Beta parameters are @1 + count@), plus the advanced PRNG state.
sampleGamma :: Double -> Word64 -> (Double, Word64)
sampleGamma shape = go
  where
    d = shape - 1 / 3
    c = 1 / sqrt (9 * d)
    go r0 =
      let (x, r1) = nextGaussian r0
          v = (1 + c * x) ^ (3 :: Int)
       in if v <= 0
            then go r1
            else
              let (u, r2) = nextDouble r1
               in if u < 1 - 0.0331 * x ^ (4 :: Int) || log u < 0.5 * x * x + d * (1 - v + log v)
                    then (d * v, r2)
                    else go r2

-- | A Beta(a, b) draw as @G(a) \/ (G(a) + G(b))@ from two Gamma draws, plus the advanced PRNG state.
sampleBeta :: Double -> Double -> Word64 -> (Double, Word64)
sampleBeta a b r0 =
  let (x, r1) = sampleGamma a r0
      (y, r2) = sampleGamma b r1
   in if x + y == 0 then (0.5, r2) else (x / (x + y), r2)
