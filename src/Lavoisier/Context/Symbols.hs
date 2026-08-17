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
-- exists, falling back to a cross-file definition (by name) only when the name is not defined
-- locally. Name-keyed on the source side (no @use@\/@import@ path resolution) — all the radius knob
-- needs, and fully deterministic.
module Lavoisier.Context.Symbols
  ( SymbolGraph,
    fromSource,
    fromSources,
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
    sgFileCount :: !Int
  }
  deriving stock (Show, Eq)

-- | Build a graph from a single source file.
fromSource :: Lang -> ByteString -> IO SymbolGraph
fromSource lang source = do
  defs <- collectDefs lang source
  pure (link [defs])

-- | Build a graph spanning several files. A reference resolves to a same-file definition first; a
-- cross-file edge (by name) forms only when the name is not defined in the referencing file.
fromSources :: [(Lang, ByteString)] -> IO SymbolGraph
fromSources srcs = link <$> mapM (uncurry collectDefs) srcs

-- | Parse a file and collect @(name, referenced names)@ for every symbol-kind node ([] if unparsed).
collectDefs :: Lang -> ByteString -> IO [(Text, Set Text)]
collectDefs lang source = do
  mtree <- parse lang source
  pure $ case mtree of
    Nothing -> []
    Just root -> collectSymbolRefs (langSpec lang) source root

-- | Resolve each symbol's referenced names to file-scoped target symbols, preferring the same file.
-- A name defined nowhere is dropped. Every definition gets an edge entry (possibly empty), so a
-- symbol with no out-edges is still a known node.
link :: [[(Text, Set Text)]] -> SymbolGraph
link perFile = SymbolGraph edges (length perFile)
  where
    indexed = zip [0 :: Int ..] perFile
    -- name → the files that define it, for cross-file fallback resolution.
    definedIn :: Map Text [Int]
    definedIn = Map.fromListWith (++) [(name, [fi]) | (fi, defs) <- indexed, (name, _) <- defs]
    edges =
      Map.fromListWith
        Set.union
        [ ((fi, name), targets)
        | (fi, defs) <- indexed,
          let local = Set.fromList (map fst defs),
          (name, refs) <- defs,
          let targets =
                Set.fromList
                  [ tgt
                  | r <- Set.toList refs,
                    r /= name,
                    tgt <-
                      if Set.member r local
                        then [(fi, r)]
                        else maybe [] (map (\tf -> (tf, r))) (Map.lookup r definedIn)
                  ]
        ]

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
