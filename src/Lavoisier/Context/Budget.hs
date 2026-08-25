{- | The budget-fixture loop (ports Rust @lvz-context::budget@ — §6.5): token-efficiency CI for the
skeleton-radius knob @N@. A 'Fixture' is @(repo snapshot + edit target)@; 'measure' builds the
context the agent would send at a given radius and reports its estimated tokens plus the kept-symbol
count. It measures the deterministic input-construction lever; the round-trip\/cache half of the
U-curve belongs to runtime ATO.
-}
module Lavoisier.Context.Budget (
    Archetype (..),
    Fixture (..),
    BudgetReport (..),
    contextAt,
    measure,
    sweep,
)
where

import Control.Monad (zipWithM)
import Data.ByteString (ByteString)
import Data.Set (Set)
import Data.Text (Text)
import Data.Text.Encoding (decodeUtf8Lenient)

import Data.ByteString qualified as BS
import Data.Set qualified as Set

import Lavoisier.Context.Tokens (estimateTokens)

import Lavoisier.Context.Skeleton qualified as Skel
import Lavoisier.Context.Symbols qualified as Sym

{- | Coarse task shape; knob optima differ per archetype. Kept local so the context engine stays
protocol-independent (mirrors @lvz_protocol::Archetype@).
-}
data Archetype
    = SingleFileEdit
    | Refactor
    | Rename
    | Feature
    deriving stock (Eq, Show)

{- | A repo snapshot plus the symbol at the centre of the intended edit. The files carry their paths,
so cross-file resolution sees the same import evidence it would at runtime — a fixture measured
without paths understates the skeleton the ranking actually produces.
-}
data Fixture = Fixture
    { fxName ∷ !Text
    , fxArchetype ∷ !Archetype
    , fxFiles ∷ ![Sym.SourceFile]
    , fxTarget ∷ !Text
    }

-- | The deterministic measurement of a fixture at one radius.
data BudgetReport = BudgetReport
    { brRadius ∷ !Int
    , brEstTokens ∷ !Int
    , brKeptSymbols ∷ !Int
    }
    deriving stock (Eq, Show)

{- | Build the context the agent would send at @radius@ (every file skeletonised, full bodies kept for
symbols within @radius@ hops of the target across the snapshot) together with the per-file keep sets.
-}
buildContext ∷ Fixture → Int → IO (ByteString, [Set Text])
buildContext fx radius = do
    graph ← Sym.fromFiles (fxFiles fx)
    let keep = Sym.neighborsWithinByFile (fxTarget fx) radius graph
    parts ← zipWithM (\sf k → Skel.skeletonize (Sym.sfLang sf) k (Sym.sfSource sf)) (fxFiles fx) keep
    pure (BS.intercalate "\n" parts, keep)

-- | The constructed context at @radius@.
contextAt ∷ Fixture → Int → IO ByteString
contextAt fx radius = fst <$> buildContext fx radius

-- | Measure estimated context tokens and kept-symbol count at @radius@.
measure ∷ Fixture → Int → IO BudgetReport
measure fx radius = do
    (context, keep) ← buildContext fx radius
    pure
        BudgetReport
            { brRadius = radius
            , brEstTokens = estimateTokens (decodeUtf8Lenient context)
            , brKeptSymbols = sum (map Set.size keep)
            }

-- | Sweep radii @0..maxRadius@, one report each — the trend line §6.5 tracks.
sweep ∷ Fixture → Int → IO [BudgetReport]
sweep fx maxRadius = mapM (measure fx) [0 .. maxRadius]
