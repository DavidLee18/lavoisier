{- | A cheap, deterministic token estimator for the budget-fixture loop (ports Rust
@lvz-context::tokens@).

This is __not__ a provider tokenizer — it is a stable proxy used to compare context sizes across
skeleton radii and to gate regressions. The budget loop only needs relative, reproducible numbers
(baseline vs candidate, radius @N@ vs @N+1@), so a heuristic suffices and avoids pulling a
model-specific BPE table into CI. Real per-call accounting comes from the providers' @Usage@ events.
-}
module Lavoisier.Context.Tokens (
    estimateTokens,
)
where

import Data.Char (isAlphaNum, isSpace)
import Data.Text (Text)

import Data.Text qualified as T

{- | Estimate the token count of @text@.

Heuristic: a token boundary occurs between an identifier\/number run and any other character, and
every non-space punctuation character counts as its own token. This tracks real BPE counts for
source code far better than a flat chars\/4, while staying deterministic.
-}
estimateTokens ∷ Text → Int
estimateTokens = snd . T.foldl' step (False, 0)
    where
        step ∷ (Bool, Int) → Char → (Bool, Int)
        step (inWord, n) ch
            | isAlphaNum ch || ch == '_' = if inWord then (True, n) else (True, n + 1)
            | otherwise = (False, if isSpace ch then n else n + 1)
