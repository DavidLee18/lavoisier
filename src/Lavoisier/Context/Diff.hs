{- | Token-efficient diffs (ports Rust @lvz-context::diff@): emit minimal unified hunks, never
full-file rewrites. Small context radii keep the token cost proportional to what actually changed.

Built over the pure @Diff@ package (the @similar@ analogue): a line-level LCS diff, grouped into
unified hunks with a configurable context radius.
-}
module Lavoisier.Context.Diff (
    unifiedDiff,
    changedLines,
)
where

import Data.Algorithm.Diff (Diff, PolyDiff (..), getDiff)
import Data.Text (Text)

import Data.Set qualified as Set
import Data.Text qualified as T

{- | A compact unified diff between @old@ and @new@, with @context@ unchanged lines around each hunk.
Returns an empty string when the inputs are identical.
-}
unifiedDiff ∷ Text → Text → Int → Text
unifiedDiff old new context
    | old == new = ""
    | otherwise =
        let entries = annotate (getDiff (T.lines old) (T.lines new))
            hunks = groupHunks context entries
         in if null hunks
                then ""
                else T.intercalate "\n" ("--- a" : "+++ b" : concatMap renderHunk hunks)

{- | The number of changed (inserted or deleted) lines between @old@ and @new@ — a cheap proxy for
edit size, useful for budgeting and for choosing whole-file vs diff transport.
-}
changedLines ∷ Text → Text → Int
changedLines old new = length (filter isChange (getDiff (T.lines old) (T.lines new)))

-- --- internals ------------------------------------------------------------------------------------

-- One diff entry with the 1-based old\/new line numbers it sits at.
type Entry = (Diff Text, Int, Int)

isChange ∷ Diff Text → Bool
isChange (Both _ _) = False
isChange _ = True

-- Pair each diff element with its position in the old and new files. A deletion advances only the
-- old counter, an insertion only the new counter, a kept line both.
annotate ∷ [Diff Text] → [Entry]
annotate = go 1 1
    where
        go _ _ [] = []
        go o n (d : ds) = case d of
            Both _ _ → (d, o, n) : go (o + 1) (n + 1) ds
            First _ → (d, o, n) : go (o + 1) n ds
            Second _ → (d, o, n) : go o (n + 1) ds

-- Group entries into hunks: each changed entry pulls in @ctx@ neighbours on each side; overlapping
-- windows merge into one hunk. Unchanged entries outside every window are dropped.
groupHunks ∷ Int → [Entry] → [[Entry]]
groupHunks ctx entries =
    let n = length entries
        changed = [i | (i, (d, _, _)) ← zip [0 ..] entries, isChange d]
        included =
            Set.fromList
                (concat [[max 0 (i - ctx) .. min (n - 1) (i + ctx)] | i ← changed])
        runs = groupConsecutive (Set.toAscList included)
     in [[entries !! j | j ← run] | run ← runs]

-- Split an ascending index list into maximal consecutive runs.
groupConsecutive ∷ [Int] → [[Int]]
groupConsecutive [] = []
groupConsecutive (x : xs) = go [x] xs
    where
        go acc [] = [reverse acc]
        go acc@(a : _) (y : ys)
            | y == a + 1 = go (y : acc) ys
            | otherwise = reverse acc : go [y] ys
        go [] (y : ys) = go [y] ys

renderHunk ∷ [Entry] → [Text]
renderHunk [] = []
renderHunk hunk@((_, os, ns) : _) = header : map renderLine hunk
    where
        oc = length [() | (d, _, _) ← hunk, keepOld d]
        nc = length [() | (d, _, _) ← hunk, keepNew d]
        header = "@@ -" <> range os oc <> " +" <> range ns nc <> " @@"
        range s c = tshow s <> "," <> tshow c
        keepOld (Second _) = False
        keepOld _ = True
        keepNew (First _) = False
        keepNew _ = True
        renderLine (d, _, _) = case d of
            Both a _ → " " <> a
            First a → "-" <> a
            Second b → "+" <> b

tshow ∷ Show a ⇒ a → Text
tshow = T.pack . show
