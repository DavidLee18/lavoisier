{- | Hash-anchored edits (ports Rust @lvz-context::anchor@): address a line by a short stable hash of
its content instead of resending the whole file. The model reads anchored lines once, then targets
edits by anchor — no full-file round-trips, and an edit that no longer matches is rejected rather
than silently misapplied.

The anchor is an 8-hex FNV-1a hash of the line's trimmed content. It need not match the Rust
implementation's @DefaultHasher@ value — only be deterministic and self-consistent within a run —
so a dependency-free FNV-1a stands in for Rust's (unspecified, non-portable) SipHash.
-}
module Lavoisier.Context.Anchor (
    anchorOf,
    AnchoredLine (..),
    anchoredLines,
    renderAnchored,
    EditOp (..),
    Edit (..),
    replaceEdit,
    insertAfterEdit,
    insertBeforeEdit,
    deleteEdit,
    after,
    AnchorError (..),
    renderAnchorError,
    applyEdits,
)
where

import Data.Bits (shiftR, xor, (.&.))
import Data.Text (Text)
import Data.Text.Encoding (encodeUtf8)
import Data.Word (Word32)

import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Text qualified as T

{- | Compute the anchor for a single line: 8 hex chars over the line's trimmed content.

Trimming makes the anchor insensitive to surrounding indentation churn; identical content yields
identical anchors (and is therefore ambiguous to target — by design).
-}
anchorOf ∷ Text → Text
anchorOf = toHex8 . fnv1a . encodeUtf8 . T.strip

fnv1a ∷ BS.ByteString → Word32
fnv1a = BS.foldl' (\h b → (h `xor` fromIntegral b) * 0x01000193) 0x811c9dc5

-- | An unsigned 32-bit value as exactly 8 lowercase hex digits.
toHex8 ∷ Word32 → Text
toHex8 w = T.pack [hexDigit (fromIntegral ((w `shiftR` s) .&. 0xf)) | s ← [28, 24 .. 0]]
    where
        hexDigit d = "0123456789abcdef" !! d

-- | A line paired with its anchor, as presented to the model.
data AnchoredLine = AnchoredLine
    { alAnchor ∷ Text
    -- ^ The line's 8-hex content anchor.
    , alText ∷ Text
    -- ^ The line's raw text.
    }
    deriving stock (Eq, Show)

-- | Annotate every line of @source@ with its anchor.
anchoredLines ∷ Text → [AnchoredLine]
anchoredLines source = [AnchoredLine (anchorOf l) l | l ← T.lines source]

{- | Render @source@ with a leading @anchor│ @ gutter on each line — the form the model reads before
issuing 'Edit's.
-}
renderAnchored ∷ Text → Text
renderAnchored source =
    T.intercalate "\n" [alAnchor l <> "\9474 " <> alText l | l ← anchoredLines source]

-- | What to do at a matched anchor.
data EditOp
    = -- | Replace the matched line with these lines.
      Replace Text
    | -- | Insert these lines immediately after the matched line.
      InsertAfter Text
    | -- | Insert these lines immediately before the matched line.
      InsertBefore Text
    | -- | Delete the matched line.
      Delete
    deriving stock (Eq, Show)

{- | A single anchored edit: the anchor of the line to act on, an optional /landmark/ anchor that
disambiguates when several lines share that content, and what to do there.

'editAfter' is what makes a repeated line addressable without ever becoming positional: the target
stays content-addressed, and the landmark only says which side of a unique nearby line the meant
copy sits on — the __first__ matching line strictly after it. A line number would silently hit the
wrong line once the file shifts; this cannot. It matches @str_replace@'s @after@ argument, so one
rule covers both edit tools.
-}
data Edit = Edit
    { editAnchor ∷ Text
    , editAfter ∷ Maybe Text
    , editOp ∷ EditOp
    }
    deriving stock (Eq, Show)

-- | Replace the anchored line with @text@.
replaceEdit ∷ Text → Text → Edit
replaceEdit a t = Edit a Nothing (Replace t)

-- | Insert @text@ immediately after the anchored line.
insertAfterEdit ∷ Text → Text → Edit
insertAfterEdit a t = Edit a Nothing (InsertAfter t)

-- | Insert @text@ immediately before the anchored line.
insertBeforeEdit ∷ Text → Text → Edit
insertBeforeEdit a t = Edit a Nothing (InsertBefore t)

-- | Delete the anchored line.
deleteEdit ∷ Text → Edit
deleteEdit a = Edit a Nothing Delete

{- | Qualify an edit with the anchor of a unique landmark line: the target becomes the first matching
line after it. Disambiguates a repeated target without naming a position.
-}
after ∷ Text → Edit → Edit
after n e = e {editAfter = Just n}

{- | Why an anchored edit could not be applied. Every case is a refusal, never a guess: an edit that
cannot be pinned to exactly one line is rejected rather than applied somewhere plausible.
-}
data AnchorError
    = -- | No line matched the anchor — the file changed under the edit.
      NotFound Text
    | -- | More than one line matched the anchor (with the match count) and no @after@ was given.
      Ambiguous Text Int
    | -- | An @after@ landmark was given but matched no line.
      AfterNotFound Text
    | -- | An @after@ landmark is itself repeated (with the match count), so it pins nothing.
      AfterAmbiguous Text Int
    | -- | No line matched the anchor after the landmark (target anchor, landmark anchor).
      NoneAfter Text Text
    deriving stock (Eq, Show)

{- | A model-facing rendering of an 'AnchorError' that names the fix, not just the fault. The
@read_anchored@ gutter already shows every neighbouring anchor, so the suggested @after@ landmark
can be supplied without re-reading the file.
-}
renderAnchorError ∷ AnchorError → Text
renderAnchorError = \case
    NotFound a →
        "anchor \"" <> a <> "\" matched no line — the file changed since it was read; re-read it with read_anchored"
    Ambiguous a n →
        "anchor \""
            <> a
            <> "\" matches "
            <> tshow n
            <> " identical lines — add \"after\": the anchor of a unique line just above the one you mean"
    AfterNotFound a →
        "after-anchor \"" <> a <> "\" matched no line — re-read the file with read_anchored"
    AfterAmbiguous a n →
        "after-anchor \""
            <> a
            <> "\" is itself repeated ("
            <> tshow n
            <> " lines) — \"after\" must be unique; pick a distinctive line above the target"
    NoneAfter a n →
        "no line matching anchor \""
            <> a
            <> "\" follows after-anchor \""
            <> n
            <> "\" — \"after\" must name a line above the target"
    where
        tshow ∷ Int → Text
        tshow = T.pack . show

{- | Apply a batch of anchored edits to @source@, preserving a trailing newline if present.

All anchors are resolved against the __original__ line set, so edits don't interfere with each
other's targeting. Any unmatched or ambiguous anchor fails the whole batch (atomic), so a stale
edit never corrupts the file.
-}
applyEdits ∷ Text → [Edit] → Either AnchorError Text
applyEdits source edits = do
    let indexed = zip [0 ∷ Int ..] (T.lines source)
    -- Resolve every anchor to a unique line index first (short-circuits on the first bad anchor).
    resolved ← mapM (resolveOne indexed) edits
    let byIndex = Map.fromListWith (\new old → old <> new) [(i, [op]) | (i, op) ← resolved]
        out = concat [emit (Map.findWithDefault [] i byIndex) line | (i, line) ← indexed]
        result = T.intercalate "\n" out
    pure (if "\n" `T.isSuffixOf` source then result <> "\n" else result)
    where
        resolveOne indexed e =
            case [i | (i, l) ← indexed, anchorOf l == editAnchor e] of
                [i] → Right (i, editOp e)
                [] → Left (NotFound (editAnchor e))
                cands → case editAfter e of
                    Nothing → Left (Ambiguous (editAnchor e) (length cands))
                    Just n → case [i | (i, l) ← indexed, anchorOf l == n] of
                        [] → Left (AfterNotFound n)
                        [ni] → case [i | i ← cands, i > ni] of
                            (i : _) → Right (i, editOp e)
                            [] → Left (NoneAfter (editAnchor e) n)
                        ns → Left (AfterAmbiguous n (length ns))

        -- The output lines for one original line: inserts-before, then the line (replaced/deleted/kept),
        -- then inserts-after — mirroring the Rust ordering.
        emit ops line = pre <> middle <> post
            where
                pre = concat [T.lines t | InsertBefore t ← ops]
                post = concat [T.lines t | InsertAfter t ← ops]
                replaced = concat [T.lines t | Replace t ← ops]
                removedOrReplaced = any isReplaceOrDelete ops
                middle = if removedOrReplaced then replaced else [line]

        isReplaceOrDelete (Replace _) = True
        isReplaceOrDelete Delete = True
        isReplaceOrDelete _ = False
