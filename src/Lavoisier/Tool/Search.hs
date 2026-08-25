{- | Repository search tools (ports Rust @lvz-tools::search@). @find_references@ enumerates ALL
references to an identifier across a directory tree in one call — AST-precise for source files (a
name only in a string\/comment is not a match), a word-boundary text scan otherwise — grouped by
file with a total count, so the model gets the "that's all of them" signal instead of grepping N
times. Bounded so a monorepo can't stall a turn.
-}
module Lavoisier.Tool.Search (
    searchTools,
    findReferencesTool,
)
where

import Control.Exception (IOException, try)
import Control.Monad (foldM)
import Data.Aeson (Value (..), object, (.=))
import Data.Char (isAlphaNum)
import Data.List (sort)
import Data.Text (Text)
import Data.Text.Encoding (decodeUtf8Lenient, encodeUtf8)
import System.Directory (doesDirectoryExist, getFileSize, listDirectory)
import System.FilePath (makeRelative, (</>))

import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString qualified as BS
import Data.Text qualified as T

import Lavoisier.Context.Lang (langFromPath)
import Lavoisier.Context.Symbols (findIdentifierLines)
import Lavoisier.Protocol.Tool

-- | Bound the walk so a huge monorepo can't stall a turn.
maxFiles ∷ Int
maxFiles = 20000

-- | Cap reported matches so a pathological name can't blow the token budget (noted when hit).
maxMatches ∷ Int
maxMatches = 1000

-- | Don't scan files larger than this (likely generated\/minified\/data).
maxFileBytes ∷ Integer
maxFileBytes = 2000000

-- | The default search tool set.
searchTools ∷ [Tool]
searchTools = [findReferencesTool]

findReferencesTool ∷ Tool
findReferencesTool =
    Tool
        { toolName = "find_references"
        , toolDescription =
            "Find ALL references to an identifier/symbol across the repository in one call, grouped by "
                <> "file with a total count. Use this — not `grep`/`sed` via shell — to enumerate call sites "
                <> "before a rename or signature change: it returns the complete set in a single round-trip, "
                <> "and for source files it matches real code identifiers, ignoring mentions inside strings "
                <> "and comments. Falls back to a word-boundary text match for non-source files."
        , toolSchema =
            object
                [ "type" .= String "object"
                , "properties"
                    .= object
                        [ "name" .= prop "Identifier/symbol name to find references to"
                        , "path" .= prop "Directory to search (default '.')"
                        ]
                , "required" .= [String "name"]
                ]
        , toolInvoke = \args → case argStr "name" args of
            Nothing → pure (Right (toolErr "find_references: `name` must not be empty"))
            Just name
                | T.null name → pure (Right (toolErr "find_references: `name` must not be empty"))
                | otherwise → do
                    let path = maybe "." T.unpack (argStr "path" args)
                    files ← sort <$> collectFiles path
                    (groups, total, capped) ← scanFiles path name files
                    pure (Right (toolOk (render name (T.pack path) groups total capped)))
        }

-- | A per-file group of matches: @(relative path, [(line, snippet)])@.
type Group = (Text, [(Int, Text)])

-- | Scan candidate files, grouping matches per file, until the match cap is reached.
scanFiles ∷ FilePath → Text → [FilePath] → IO ([Group], Int, Bool)
scanFiles root name = go [] 0
    where
        go acc total [] = pure (reverse acc, total, False)
        go acc total (f : fs)
            | total >= maxMatches = pure (reverse acc, total, True)
            | otherwise = do
                er ← tryIO (readFileText f)
                case er of
                    Left _ → go acc total fs -- binary / non-UTF-8
                    Right text
                        | not (name `T.isInfixOf` text) → go acc total fs -- cheap reject before parsing
                        | otherwise → do
                            hits ← matchesIn f text name
                            if null hits
                                then go acc total fs
                                else go ((T.pack (makeRelative root f), hits) : acc) (total + length hits) fs

{- | Per-file match scan: AST-aware for known languages (a clean parse with the name only in a
comment\/string yields no hits), word-boundary text otherwise.
-}
matchesIn ∷ FilePath → Text → Text → IO [(Int, Text)]
matchesIn path text name = case langFromPath path of
    Just lang →
        findIdentifierLines lang name (encodeUtf8' text) >>= \case
            Just hits → pure hits -- parsed cleanly — trust the AST, even if empty
            Nothing → pure (textMatchLines text name) -- parse failure → text scan
    Nothing → pure (textMatchLines text name)

{- | Word-boundary occurrences of @name@ (one hit per line), for files we can't parse. A match must
not be flanked by identifier characters.
-}
textMatchLines ∷ Text → Text → [(Int, Text)]
textMatchLines src name =
    [(i, T.strip line) | (i, line) ← zip [1 ..] (T.lines src), lineHasWord line]
    where
        lineHasWord = scan Nothing
        scan prev s = case T.breakOn name s of
            (_, "") → False
            (before, rest) →
                let beforeChar = if T.null before then prev else Just (T.last before)
                    after = T.drop (T.length name) rest
                    afterChar = if T.null after then Nothing else Just (T.head after)
                    ok = notIdent beforeChar && notIdent afterChar
                 in ok || scan (Just (T.last name)) after
        notIdent = maybe True (not . isIdent)
        isIdent c = isAlphaNum c || c == '_'

{- | Recursively collect candidate files under @root@ (bounded; VCS\/build\/dep dirs and large files
skipped).
-}
collectFiles ∷ FilePath → IO [FilePath]
collectFiles root = snd <$> loop [root] (0, [])
    where
        loop [] acc = pure acc
        loop (d : ds) acc@(n, _)
            | n >= maxFiles = pure acc
            | otherwise = do
                names ← either (const []) id <$> tryIO (listDirectory d)
                (subdirs, acc') ← foldM (classify d) ([], acc) names
                loop (subdirs <> ds) acc'
        classify d (subdirs, (n, files)) name = do
            let p = d </> name
            isDir ← doesDirectoryExist p
            if isDir
                then pure (if skipDir name then subdirs else p : subdirs, (n, files))
                else do
                    sz ← either (const (maxFileBytes + 1)) id <$> tryIO (getFileSize p)
                    pure (subdirs, if sz <= maxFileBytes then (n + 1, p : files) else (n, files))

skipDir ∷ FilePath → Bool
skipDir name =
    take 1 name == "."
        || name `elem` ["target", "node_modules", "dist", "build", "vendor", "__pycache__"]

render ∷ Text → Text → [Group] → Int → Bool → Text
render name path groups total capped
    | null groups = "No references to `" <> name <> "` found under " <> path <> "."
    | otherwise =
        T.stripEnd $
            header <> "\n\n" <> T.intercalate "\n" (map groupBlock groups)
    where
        note = if capped then " (capped at " <> tshow maxMatches <> "; narrow with `path`)" else ""
        header = "Found " <> tshow total <> " reference(s) to `" <> name <> "` in " <> tshow (length groups) <> " file(s)" <> note <> ":"
        groupBlock (rel, hits) =
            rel <> " (" <> tshow (length hits) <> "):\n" <> T.intercalate "\n" ["  " <> tshow line <> ": " <> T.take 160 snippet | (line, snippet) ← hits]

-- --- small helpers ---------------------------------------------------------------------------------

argStr ∷ Text → Value → Maybe Text
argStr key (Object o) = case KM.lookup (K.fromText key) o of
    Just (String s) → Just s
    _ → Nothing
argStr _ _ = Nothing

-- Read a file's raw bytes and decode leniently (binary\/non-UTF-8 files still decode, not throw).
readFileText ∷ FilePath → IO Text
readFileText p = decodeUtf8Lenient <$> BS.readFile p

encodeUtf8' ∷ Text → BS.ByteString
encodeUtf8' = encodeUtf8

tryIO ∷ IO a → IO (Either IOException a)
tryIO = try

prop ∷ Text → Value
prop d = object ["type" .= String "string", "description" .= String d]

tshow ∷ Show a ⇒ a → Text
tshow = T.pack . show
