-- | Recursive symbol-dependency tracking (ports Rust @lvz-context::symbols@ — §6.1): the graph that
-- makes the skeleton-radius knob @N@ real ("include full bodies for symbols within @N@ dependency
-- hops of the edit target").
--
-- Edges are resolved from the parse tree, not raw text. For each symbol we walk its subtree and
-- collect the reference identifiers it uses (real @identifier@\/@type_identifier@ nodes) minus the
-- identifiers it binds locally (parameters, @let@\/variable patterns); an edge @A → B@ exists when
-- one of @A@'s references names a defined symbol @B@. So a name appearing only in a string or comment
-- creates no edge, and a local that shadows a top-level symbol no longer links to it.
--
-- Resolution is scope-aware across files: a reference links to a same-file definition when one
-- exists, falling back to a cross-file definition only when the name is not defined locally.
--
-- The cross-file fallback is /ranked, not resolved/. Import and @use@ declarations are mined for
-- module-path segments, and a candidate definer scores by how many of them its own path matches;
-- only the best-scoring tier survives. This is deliberately not a name resolver: a real one drops a
-- true edge whenever it is wrong, and a missing edge is invisible — the model silently never sees the
-- body it needed. Ranking can only narrow where positive evidence exists and degrades exactly to the
-- old link-every-definer behaviour where it does not ('narrowedCount' says which happened). Fully
-- deterministic either way.
module Lavoisier.Context.Symbols
  ( SymbolGraph,
    SourceFile (..),
    fromSource,
    fromSources,
    fromFiles,
    narrowedCount,
    neighborsWithin,
    neighborsWithinByFile,
    symbolNames,
    findIdentifierLines,
    skeletonWithRadius,
  )
where

import Control.Applicative ((<|>))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Char (isAlphaNum)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding (decodeUtf8Lenient)
import Lavoisier.Context.Lang (Lang, LangSpec (..), langSpec)
import Lavoisier.Context.Skeleton qualified as Skel
import Lavoisier.Context.TreeSitter
  ( Child (..),
    Syntax (..),
    childByField,
    nodeText,
    parse,
  )

-- | A defined symbol's identity: the file it lives in plus its name. Same-named symbols in different
-- files are distinct nodes (a caller links to its own file's definition, not an unrelated far one).
type Sym = (Int, Text)

-- | A directed reference graph over file-scoped symbols: @(file, name)@ → the symbols it references.
data SymbolGraph = SymbolGraph
  { sgEdges :: !(Map Sym (Set Sym)),
    sgFileCount :: !Int,
    sgNarrowed :: !Int
  }
  deriving stock (Show, Eq)

-- | One file of a multi-file snapshot. The path is evidence, not identity — it is matched against
-- other files' import segments to rank cross-file candidates; @""@ simply means "no evidence".
data SourceFile = SourceFile
  { sfPath :: !Text,
    sfLang :: !Lang,
    sfSource :: !ByteString
  }

-- | How many cross-file references import evidence actually narrowed. Zero on a snapshot whose files
-- carry no paths or no imports — that is the honest reading of "the ranking did nothing here", and
-- the first thing to check when a body is unexpectedly missing from a focused skeleton.
narrowedCount :: SymbolGraph -> Int
narrowedCount = sgNarrowed

-- | Build a graph from a single source file.
fromSource :: Lang -> ByteString -> IO SymbolGraph
fromSource lang source = fromFiles [SourceFile "" lang source]

-- | Build a graph spanning several files, without path evidence (every cross-file definer of a name
-- is linked). Prefer 'fromFiles' when the paths are known.
fromSources :: [(Lang, ByteString)] -> IO SymbolGraph
fromSources = fromFiles . map (\(l, src) -> SourceFile "" l src)

-- | Build a graph spanning several paths-and-sources. A reference resolves to a same-file definition
-- first; otherwise to the cross-file definers whose paths best match this file's imports.
fromFiles :: [SourceFile] -> IO SymbolGraph
fromFiles files = link <$> mapM collectFile files

-- | Parse a file into the pieces 'link' needs ('emptyInfo' if it does not parse).
collectFile :: SourceFile -> IO FileInfo
collectFile sf = do
  mtree <- parse (sfLang sf) (sfSource sf)
  pure $ case mtree of
    Nothing -> emptyInfo
    Just root ->
      let spec = langSpec (sfLang sf)
       in FileInfo
            { fiPathTokens = pathTokens (sfPath sf),
              fiImports = collectImportSegments spec (sfSource sf) root,
              fiDefs = collectSymbolRefs spec (sfSource sf) root
            }

-- | A file's definitions plus the evidence used to rank it as a cross-file target.
data FileInfo = FileInfo
  { -- | Path components of this file (directories plus the basename stem).
    fiPathTokens :: Set Text,
    -- | Module-path segments mentioned by this file's imports.
    fiImports :: Set Text,
    -- | @(name, referenced names)@ for each symbol defined here.
    fiDefs :: [(Text, Set Text)]
  }

emptyInfo :: FileInfo
emptyInfo = FileInfo Set.empty Set.empty []

-- | Resolve each symbol's referenced names to file-scoped target symbols, preferring the same file.
-- A name defined nowhere is dropped. Every definition gets an edge entry (possibly empty), so a
-- symbol with no out-edges is still a known node.
link :: [FileInfo] -> SymbolGraph
link perFile = SymbolGraph edges (length perFile) narrowed
  where
    indexed = zip [0 :: Int ..] perFile
    infoAt = Map.fromList indexed
    -- name → the files that define it, for cross-file fallback resolution.
    definedIn :: Map Text [Int]
    definedIn = Map.fromListWith (++) [(name, [fi]) | (fi, info) <- indexed, (name, _) <- fiDefs info]
    -- One entry per resolved reference: source symbol, referenced name, whether it stayed in-file,
    -- and the target files it linked to.
    resolutions =
      [ ((fi, name), r, isLocal, cands)
      | (fi, info) <- indexed,
        let local = Set.fromList (map fst (fiDefs info)),
        (name, refs) <- fiDefs info,
        r <- Set.toList refs,
        r /= name,
        let isLocal = Set.member r local,
        let cands = if isLocal then [fi] else ranked info (Map.findWithDefault [] r definedIn)
      ]
    edges =
      Map.fromListWith
        Set.union
        ( [((fi, name), Set.empty) | (fi, info) <- indexed, (name, _) <- fiDefs info]
            <> [(src, Set.fromList [(tf, r) | tf <- cands]) | (src, r, _, cands) <- resolutions]
        )
    -- References whose candidate set import evidence actually shrank.
    narrowed =
      length
        [ ()
        | (_, r, False, cands) <- resolutions,
          length cands < length (Map.findWithDefault [] r definedIn)
        ]

    -- The best-scoring definers of a name, where a definer scores by how much of its path the
    -- referencing file's imports mention. With no evidence every candidate ties at zero, which is
    -- exactly the unranked behaviour.
    ranked info cands =
      let scored = [(score info c, c) | c <- cands]
          best = maximum (0 : map fst scored)
       in [c | (sc, c) <- scored, sc == best]
    score info c =
      Set.size (Set.intersection (fiImports info) (fiPathTokens (Map.findWithDefault emptyInfo c infoAt)))

-- | A path's identifying components: directory names plus the basename stem (@src\/parser.rs@ →
-- @{src, parser, rs}@). Extension noise is harmless — imports do not name it.
--
-- Hyphens are folded to underscores because the two sides spell the same module differently: a Rust
-- crate directory @lvz-context\/@ is imported as @lvz_context@, and a JS module @foo-bar.ts@ as
-- @\'.\/foo-bar\'@. Without the fold almost no real import matches anything — measured on the 60-file
-- Rust workspace, folding took the number of narrowed cross-file references from 33 to 316.
pathTokens :: Text -> Set Text
pathTokens =
  Set.fromList . filter (not . T.null) . map (T.replace "-" "_") . T.split (\c -> c == '/' || c == '.' || c == '\\')

-- | The module-path segments named by a file's imports: every identifier-ish run in an import
-- declaration's raw text, minus the keywords every language sprinkles through them.
collectImportSegments :: LangSpec -> ByteString -> Syntax -> Set Text
collectImportSegments spec source = go
  where
    go node
      | synType node `elem` importKinds spec = segmentsOf (textOf source node)
      | otherwise = foldMap go (kids node)
    segmentsOf =
      Set.fromList
        . filter (\w -> not (T.null w) && not (Set.member w importKeywords))
        . map (T.replace "-" "_")
        . T.split (\c -> not (isAlphaNum c) && c /= '_' && c /= '-')

-- | Import syntax that is never a module-path segment.
importKeywords :: Set Text
importKeywords =
  Set.fromList
    ["use", "pub", "crate", "self", "super", "as", "mod", "import", "from", "require", "type", "default"]

-- | The set of symbol names within @radius@ reference-hops of @target@ (inclusive), across all files.
neighborsWithin :: Text -> Int -> SymbolGraph -> Set Text
neighborsWithin target radius g = Set.map snd (reach g target radius)

-- | Like 'neighborsWithin', but names to keep are returned per file (index → names within radius),
-- so a multi-file skeletoniser keeps a body only in the file that owns the reached symbol.
neighborsWithinByFile :: Text -> Int -> SymbolGraph -> [Set Text]
neighborsWithinByFile target radius g =
  [Set.fromList [name | (fi, name) <- reached, fi == i] | i <- [0 .. max 1 (sgFileCount g) - 1]]
  where
    reached = Set.toList (reach g target radius)

-- | All symbol names known to the graph (deduplicated across files).
symbolNames :: SymbolGraph -> Set Text
symbolNames = Set.map snd . Map.keysSet . sgEdges

-- | BFS over the file-scoped edges from every symbol named @target@, returning the reached
-- @(file, name)@ set (inclusive of the seeds). An unknown name still returns itself.
reach :: SymbolGraph -> Text -> Int -> Set Sym
reach g target radius = bfs visited0 frontier0 radius
  where
    fc = max 1 (sgFileCount g)
    seeds = [(fi, target) | fi <- [0 .. fc - 1], Map.member (fi, target) (sgEdges g)]
    (visited0, frontier0)
      | null seeds = (Set.singleton (0, target), [])
      | otherwise = (Set.fromList seeds, seeds)
    bfs visited frontier n
      | n <= 0 = visited
      | null next = visited
      | otherwise = bfs (Set.union visited next) (Set.toList next) (n - 1)
      where
        next =
          Set.fromList
            [ r
            | node <- frontier,
              r <- Set.toList (Map.findWithDefault Set.empty node (sgEdges g)),
              Set.notMember r visited
            ]

-- | Walk the tree collecting @(name, referenced names)@ for every symbol-kind node.
collectSymbolRefs :: LangSpec -> ByteString -> Syntax -> [(Text, Set Text)]
collectSymbolRefs spec source = go
  where
    go node = here ++ concatMap go (kids node)
      where
        here
          | synType node `elem` symbolKinds spec,
            Just nameNode <- childByField "name" node =
              let name = textOf source nameNode
                  bound = collectBound spec source node
                  refs = Set.delete name (collectRefs spec source bound node)
               in [(name, refs)]
          | otherwise = []

-- | The identifiers bound locally inside @node@: for every binder, the identifiers in its binding
-- position only (@pattern@\/@name@ field, or its direct children when it has neither). The binder's
-- value and type are not treated as bindings (so @let x = helper()@ still references @helper@).
collectBound :: LangSpec -> ByteString -> Syntax -> Set Text
collectBound spec source = go
  where
    go node = self <> foldMap go (kids node)
      where
        self
          | synType node `elem` binderKinds spec =
              case childByField "pattern" node <|> childByField "name" node of
                Just target -> collectIdents spec source target
                Nothing -> foldMap (collectIdents spec source) (kids node)
          | otherwise = Set.empty

-- | Every reference-identifier name in @node@'s subtree that is not locally @bound@.
collectRefs :: LangSpec -> ByteString -> Set Text -> Syntax -> Set Text
collectRefs spec source bound = go
  where
    go node = self <> foldMap go (kids node)
      where
        self
          | synType node `elem` refIdentKinds spec,
            let t = textOf source node,
            not (Set.member t bound) =
              Set.singleton t
          | otherwise = Set.empty

-- | Every reference-identifier name in @node@'s subtree (binding-agnostic).
collectIdents :: LangSpec -> ByteString -> Syntax -> Set Text
collectIdents spec source = go
  where
    go node = self <> foldMap go (kids node)
      where
        self
          | synType node `elem` refIdentKinds spec = Set.singleton (textOf source node)
          | otherwise = Set.empty

-- | Every 1-based line on which @name@ occurs as a reference identifier (a real
-- @identifier@\/@type_identifier@ node), not inside a string or comment — the AST-aware core of the
-- @find_references@ tool. Each matching line is returned once, trimmed, in source order. 'Nothing'
-- only when the source fails to parse (distinguishing that from a clean parse with no matches).
findIdentifierLines :: Lang -> Text -> ByteString -> IO (Maybe [(Int, Text)])
findIdentifierLines lang name source = do
  mtree <- parse lang source
  pure $ flip fmap mtree $ \root ->
    let spec = langSpec lang
        rows = Set.toAscList (Set.fromList (map rowOf (collectNamedRefBytes spec source name root)))
        srcLines = T.lines (decodeUtf8Lenient source)
        lineAt r
          | r >= 0 && r < length srcLines = T.strip (srcLines !! r)
          | otherwise = ""
     in [(r + 1, lineAt r) | r <- rows]
  where
    rowOf b = BS.count 0x0a (BS.take b source)

-- | The start-byte offsets of every reference-identifier node whose text equals @name@.
collectNamedRefBytes :: LangSpec -> ByteString -> Text -> Syntax -> [Int]
collectNamedRefBytes spec source name = go
  where
    go node = here ++ concatMap go (kids node)
      where
        here
          | synType node `elem` refIdentKinds spec, textOf source node == name = [synStart node]
          | otherwise = []

-- | Skeletonise @source@, keeping full bodies for symbols within @radius@ hops of @target@; the
-- knob-@N@ entry point used by the budget loop and the @outline_file@ tool's focus mode.
skeletonWithRadius :: Lang -> Text -> Int -> ByteString -> IO ByteString
skeletonWithRadius lang target radius source = do
  g <- fromSource lang source
  Skel.skeletonize lang (neighborsWithin target radius g) source

-- | A node's source text, decoded UTF-8 (lenient).
textOf :: ByteString -> Syntax -> Text
textOf source = decodeUtf8Lenient . nodeText source

-- | A node's children (all of them, named or not).
kids :: Syntax -> [Syntax]
kids = map childNode . synChildren
