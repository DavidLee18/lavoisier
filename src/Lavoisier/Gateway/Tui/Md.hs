-- | Lightweight terminal markdown for the TUI: an inline styler (@**bold**@, @*italic*@\/@_italic_@,
-- @\`code\`@, @~~strike~~@), a width-aware wrapper for styled segments, and an aligned table
-- renderer. Hand-rolled — it only needs the inline subset, applied per line, so block structure
-- (headings, fenced code) is handled by the caller's line classifier.
--
-- Ported from Rust @lvz-gw-tui@ @md.rs@. Where the Rust leans on @ratatui@'s 'Style' and the
-- @unicode-width@ crate, the port carries its own minimal 'Style' (rendered to SGR escapes by 'sgr')
-- and its own 'charWidth' — no TUI framework, in keeping with the tree's hand-rolled adapters.
module Lavoisier.Gateway.Tui.Md
  ( -- * Styling
    Color (..),
    Style (..),
    defaultStyle,
    fg,
    bold,
    italic,
    crossedOut,
    sgr,
    resetSgr,

    -- * Widths
    charWidth,
    displayWidth,

    -- * Inline markdown
    Segment,
    inline,
    wrap,

    -- * Tables
    isTableRow,
    isSeparatorRow,
    renderTable,
  )
where

import Data.Char (ord)
import Data.Text (Text)
import Data.Text qualified as T

-- --- style ----------------------------------------------------------------------------------------

-- | The eight-colour subset the TUI uses (plus a dim grey), as ANSI SGR foreground codes.
data Color = Cyan | Green | Yellow | Red | DarkGray
  deriving stock (Eq, Show)

-- | A resolved text style: an optional foreground colour plus the three inline modifiers.
data Style = Style
  { stFg :: Maybe Color,
    stBold :: Bool,
    stItalic :: Bool,
    stCrossedOut :: Bool
  }
  deriving stock (Eq, Show)

-- | Unstyled.
defaultStyle :: Style
defaultStyle = Style Nothing False False False

fg :: Color -> Style -> Style
fg c s = s {stFg = Just c}

bold, italic, crossedOut :: Style -> Style
bold s = s {stBold = True}
italic s = s {stItalic = True}
crossedOut s = s {stCrossedOut = True}

-- | The SGR escape sequence that turns @style@ on. Always paired with 'resetSgr'.
sgr :: Style -> Text
sgr s
  | null codes = ""
  | otherwise = "\ESC[" <> T.intercalate ";" codes <> "m"
  where
    codes =
      concat
        [ ["1" | stBold s],
          ["3" | stItalic s],
          ["9" | stCrossedOut s],
          maybe [] (pure . colorCode) (stFg s)
        ]
    colorCode = \case
      Cyan -> "36"
      Green -> "32"
      Yellow -> "33"
      Red -> "31"
      -- Bright black reads as grey on every common palette; plain 30 is invisible on dark themes.
      DarkGray -> "90"

-- | Turn every attribute back off.
resetSgr :: Text
resetSgr = "\ESC[0m"

-- --- widths ---------------------------------------------------------------------------------------

-- | Terminal columns one character occupies: 0 for combining marks, 2 for the East-Asian wide and
-- fullwidth ranges (CJK, Hangul, kana, fullwidth forms, most emoji), 1 otherwise. A deliberately
-- small stand-in for the @unicode-width@ crate — enough for the text this UI actually renders.
charWidth :: Char -> Int
charWidth c
  | n == 0 = 0
  | inAny combining = 0
  | inAny wide = 2
  | otherwise = 1
  where
    n = ord c
    inAny = any (\(lo, hi) -> n >= lo && n <= hi)
    combining = [(0x0300, 0x036F), (0x1AB0, 0x1AFF), (0x1DC0, 0x1DFF), (0x20D0, 0x20F0), (0xFE00, 0xFE0F), (0xFE20, 0xFE2F)]
    wide =
      [ (0x1100, 0x115F), -- Hangul Jamo
        (0x2E80, 0x303E), -- CJK radicals, Kangxi, CJK symbols
        (0x3041, 0x33FF), -- kana, Hangul compat jamo, CJK compat
        (0x3400, 0x4DBF), -- CJK ext A
        (0x4E00, 0x9FFF), -- CJK unified
        (0xA000, 0xA4CF), -- Yi
        (0xAC00, 0xD7A3), -- Hangul syllables
        (0xF900, 0xFAFF), -- CJK compat ideographs
        (0xFE30, 0xFE6F), -- CJK compat forms
        (0xFF00, 0xFF60), -- fullwidth forms
        (0xFFE0, 0xFFE6),
        (0x1F300, 0x1F64F), -- emoji
        (0x1F900, 0x1F9FF),
        (0x20000, 0x3FFFD) -- CJK ext B+
      ]

-- | Display width of a string in terminal columns.
displayWidth :: Text -> Int
displayWidth = T.foldl' (\acc c -> acc + charWidth c) 0

-- --- inline markdown ------------------------------------------------------------------------------

-- | A run of text with a resolved style.
type Segment = (Text, Style)

-- | Parse one line's inline markdown into styled segments. An unterminated marker is treated as
-- literal text (so a stray @*@ or backtick never eats the rest of the line).
inline :: Text -> [Segment]
inline line = case go (T.unpack line) "" of
  [] -> [("", defaultStyle)]
  segs -> segs
  where
    base = defaultStyle

    flush plain rest = [(T.pack (reverse plain), base) | not (null plain)] <> rest

    go [] plain = flush plain []
    go cs@(c : rest) plain
      -- `code`
      | c == '`',
        Just (body, after) <- untilChar '`' rest =
          flush plain ((T.pack body, fg Cyan base) : go after "")
      -- \**bold**
      | c == '*',
        take 1 rest == "*",
        Just (body, after) <- untilPair '*' '*' (drop 1 rest) =
          flush plain ((T.pack body, bold base) : go after "")
      -- ~~strike~~
      | c == '~',
        take 1 rest == "~",
        Just (body, after) <- untilPair '~' '~' (drop 1 rest) =
          flush plain ((T.pack body, crossedOut base) : go after "")
      -- \*italic* or _italic_
      | c == '*' || c == '_',
        (r0 : _) <- rest,
        not (isSpace' r0),
        Just (body, after) <- untilChar c rest =
          flush plain ((T.pack body, italic base) : go after "")
      | otherwise = go rest (c : plain)
      where
        _unused = cs

    isSpace' ch = ch == ' ' || ch == '\t'

    -- Split at the next occurrence of `needle`, returning (body, remainder-after-needle).
    untilChar needle s = case break (== needle) s of
      (_, []) -> Nothing
      (body, _ : after) -> Just (body, after)

    -- Split at the next `a b` pair, returning (body, remainder-after-pair).
    untilPair a b = search ""
      where
        search _ [] = Nothing
        search acc (x : y : ys)
          | x == a && y == b = Just (reverse acc, ys)
          | otherwise = search (x : acc) (y : ys)
        search _ [_] = Nothing

-- | Greedily wrap styled segments to @width@ display columns, splitting a run mid-way when needed
-- and coalescing consecutive same-style characters into one span per row.
wrap :: [Segment] -> Int -> [[Segment]]
wrap segments width0 =
  let (rows, cur, _) = foldl' step ([], [], 0) [(ch, st) | (t, st) <- segments, ch <- T.unpack t]
   in map (map (\(t, st) -> (T.pack (reverse t), st)) . reverse) (reverse (cur : rows))
  where
    width = max 1 width0
    step (rows, cur, col) (ch, st)
      | cw <- charWidth ch,
        col + max 1 cw > width && col > 0 =
          (cur : rows, [([ch], st)], max 1 (charWidth ch))
      | otherwise = (rows, push ch st cur, col + max 1 (charWidth ch))
    push ch st ((t, s) : more) | s == st = ((ch : t, s) : more)
    push ch st cur = (([ch], st) : cur)

-- --- tables ---------------------------------------------------------------------------------------

-- | Column alignment from a table's separator row.
data Align = AlignLeft | AlignCenter | AlignRight
  deriving stock (Eq, Show)

-- | Whether a line looks like a table row (trimmed, starts with @|@ and has more after it).
isTableRow :: Text -> Bool
isTableRow line = "|" `T.isPrefixOf` t && T.length t > 1
  where
    t = T.stripStart line

-- | Split a @| a | b |@ row into trimmed cells, preserving internal empty cells.
parseRow :: Text -> [Text]
parseRow line = map T.strip (T.splitOn "|" stripped)
  where
    t = T.strip line
    stripped = dropSuffix "|" (dropPrefix "|" t)
    dropPrefix p s = maybe s id (T.stripPrefix p s)
    dropSuffix p s = maybe s id (T.stripSuffix p s)

-- | Whether a line is a table __separator__ row (@|---|:--:|@): every cell is dashes with optional
-- leading\/trailing colons.
isSeparatorRow :: Text -> Bool
isSeparatorRow line =
  not (null cells) && all ok cells
  where
    cells = parseRow line
    ok c = T.any (== '-') c' && T.all (\ch -> ch == '-' || ch == ':') c'
      where
        c' = T.strip c

-- | Per-column alignment parsed from the separator row's colons.
parseAligns :: Text -> [Align]
parseAligns = map alignOf . parseRow
  where
    alignOf cell = case (":" `T.isPrefixOf` c, ":" `T.isSuffixOf` c) of
      (True, True) -> AlignCenter
      (False, True) -> AlignRight
      _ -> AlignLeft
      where
        c = T.strip cell

-- | Truncate to @w@ display columns, appending @…@ when it doesn't fit.
truncateToWidth :: Text -> Int -> Text
truncateToWidth s w
  | displayWidth s <= w = s
  | w == 0 = ""
  | otherwise = go (T.unpack s) "" 0
  where
    go [] acc _ = T.pack (reverse acc) <> "…"
    go (c : cs) acc used
      | used + max 1 (charWidth c) > w - 1 = T.pack (reverse acc) <> "…"
      | otherwise = go cs (c : acc) (used + max 1 (charWidth c))

-- | Pad to @w@ display columns per @align@ (assumes the text already fits).
padToWidth :: Text -> Int -> Align -> Text
padToWidth s w align
  | d >= w = s
  | otherwise = case align of
      AlignRight -> spaces pad <> s
      AlignLeft -> s <> spaces pad
      AlignCenter -> spaces l <> s <> spaces (pad - l)
  where
    d = displayWidth s
    pad = w - d
    l = pad `div` 2
    spaces n = T.replicate n " "

-- | Shrink column widths (widest first) until a row fits @avail@, so a wide table truncates cells
-- rather than overflowing the terminal.
fitWidths :: [Int] -> Int -> [Int]
fitWidths widths avail = go widths
  where
    seps = 3 * max 0 (length widths - 1)
    budget = max (length widths) (max 0 (avail - seps))
    go ws
      | sum ws <= budget = ws
      | mx <= 3 = ws
      | otherwise = go (take i ws <> [mx - 1] <> drop (i + 1) ws)
      where
        mx = maximum ws
        i = length (takeWhile (/= mx) ws)

-- | The @i@th cell of a row, or @\"\"@ when the row is short.
nthCell :: [Text] -> Int -> Text
nthCell row i = case drop i row of
  (c : _) -> c
  [] -> ""

-- | Render buffered table lines into aligned, styled visual rows (header bold, a @─┼─@ rule, then
-- data), fitted to @width@. Returns 'Nothing' when the lines aren't a valid table (no separator
-- row), so the caller can fall back to plain rendering.
renderTable :: [Text] -> Int -> Maybe [[Segment]]
renderTable lines_ width = case lines_ of
  (hdr : sepLine : rest) | isSeparatorRow sepLine -> Just (table hdr sepLine rest)
  _ -> Nothing
  where
    table hdr sepLine rest = build header (bold defaultStyle) : rule : map (`build` defaultStyle) dataRows
      where
        header = parseRow hdr
        aligns = parseAligns sepLine
        dataRows = map parseRow rest
        ncols = max 1 (maximum (length header : map length dataRows))
        natural = [max 1 (maximum (displayWidth (nthCell header i) : map (\r -> displayWidth (nthCell r i)) dataRows)) | i <- [0 .. ncols - 1]]
        widths = fitWidths natural width
        sep = fg DarkGray defaultStyle
        alignAt i = case drop i aligns of (a : _) -> a; [] -> AlignLeft
        build row style =
          concat
            [ [(" │ ", sep) | i > 0] <> [(padToWidth (truncateToWidth (nthCell row i) w) w (alignAt i), style)]
            | (i, w) <- zip [0 ..] widths
            ]
        rule =
          concat
            [ [("─┼─", sep) | i > 0] <> [(T.replicate w "─", sep)]
            | (i, w) <- zip [(0 :: Int) ..] widths
            ]
