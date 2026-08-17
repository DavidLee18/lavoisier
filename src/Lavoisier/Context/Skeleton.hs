-- | File-skeleton extraction (ports Rust @lvz-context::skeleton@ — §6.1, the largest token lever):
-- keep signatures, type definitions and surrounding doc comments; replace function\/method /bodies/
-- with a placeholder. Bodies named in @keepBodies@ are retained — the building block for the
-- skeleton-radius knob @N@ ("include full bodies for symbols within N hops of the target").
--
-- Everything is byte-indexed 'ByteString': tree-sitter reports UTF-8 byte offsets, so slicing the
-- source by those offsets must be byte-, not char-, indexed. Skeletonising is an optimisation, never
-- a correctness requirement, so an unparseable source is returned unchanged.
module Lavoisier.Context.Skeleton
  ( skeletonize,
    skeleton,
    skeletonizePath,
  )
where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.List (sortBy)
import Data.Ord (Down (..), comparing)
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text.Encoding (decodeUtf8Lenient, encodeUtf8)
import Lavoisier.Context.Lang
  ( Lang,
    LangSpec (..),
    langFromPath,
    langSpec,
  )
import Lavoisier.Context.TreeSitter
  ( Child (..),
    Syntax (..),
    childByField,
    namedChildren,
    nodeText,
    parse,
  )

-- | One body region to elide: the byte range @[start, end)@ and the bytes it is replaced with.
-- Usually the language's bare placeholder, but the docstring-preserving path elides only the
-- /post-docstring/ range and carries a re-indented placeholder.
data Elision = Elision !Int !Int !ByteString

-- | Produce a skeleton of @source@: signatures kept, un-kept bodies elided. Bodies whose definition
-- name is in @keep@ are retained whole. Unparseable input is returned unchanged.
skeletonize :: Lang -> Set Text -> ByteString -> IO ByteString
skeletonize lang keep source = do
  mtree <- parse lang source
  pure $ case mtree of
    Nothing -> source
    Just root -> applyElisions source (collect (langSpec lang) keep source root)

-- | Skeletonise with no preserved bodies (radius 0).
skeleton :: Lang -> ByteString -> IO ByteString
skeleton lang = skeletonize lang Set.empty

-- | Detect the language from @path@ and skeletonise; 'Nothing' for unsupported extensions.
skeletonizePath :: String -> ByteString -> IO (Maybe ByteString)
skeletonizePath path source = case langFromPath path of
  Nothing -> pure Nothing
  Just lang -> Just <$> skeleton lang source

-- | Walk the tree collecting body elisions. A def whose body is elided stops the descent (nested
-- defs inside it go with it, matching the Rust @return@); anything else recurses into all children.
collect :: LangSpec -> Set Text -> ByteString -> Syntax -> [Elision]
collect spec keep source node =
  case tryElide of
    Just es -> es
    Nothing -> concatMap (collect spec keep source) (map childNode (synChildren node))
  where
    tryElide
      | synType node `elem` defKinds spec,
        not kept,
        Just body <- childByField "body" node =
          Just (elideBody spec source body)
      | otherwise = Nothing
    kept = maybe False (`Set.member` keep) (nodeName source node)

-- | The elisions for a single definition body (0 or 1). The docstring-preserving path keeps a
-- leading docstring statement, eliding only what follows it (re-indented placeholder on its own
-- line); a docstring-only body keeps everything, so it yields no elision.
elideBody :: LangSpec -> ByteString -> Syntax -> [Elision]
elideBody spec source body
  | keepsDocstring spec,
    Just docEnd <- leadingDocstringEnd body =
      [ Elision docEnd (synEnd body) (encodeUtf8 ("\n" <> indent <> elision spec))
      | docEnd < synEnd body
      ]
  | otherwise =
      [Elision (synStart body) (synEnd body) (encodeUtf8 (elision spec))]
  where
    indent = lineIndent source (synStart body)

-- | If @body@'s first statement is a bare string expression (a docstring), the byte offset just past
-- it; otherwise 'Nothing'. Handles the Python shape @block → expression_statement → string@.
leadingDocstringEnd :: Syntax -> Maybe Int
leadingDocstringEnd body = case namedChildren body of
  (first : _)
    | synType first == "expression_statement",
      (inner : _) <- namedChildren first,
      synType inner == "string" ->
        Just (synEnd first)
  _ -> Nothing

-- | The whitespace indentation of the line containing byte offset @at@ (the run between the
-- preceding newline and @at@), as text. Used to re-indent the placeholder under a kept docstring.
lineIndent :: ByteString -> Int -> Text
lineIndent source at =
  let before = BS.take at source
      lineStart = maybe 0 (+ 1) (BS.elemIndexEnd 0x0a before)
   in decodeUtf8Lenient (BS.drop lineStart before)

-- | The @name@ field of a definition node, as text (empty-name-safe, unicode-lenient).
nodeName :: ByteString -> Syntax -> Maybe Text
nodeName source node = decodeUtf8Lenient . nodeText source <$> childByField "name" node

-- | Apply elisions right-to-left (so earlier byte offsets stay valid) by splicing each range.
applyElisions :: ByteString -> [Elision] -> ByteString
applyElisions source es = foldl apply source (sortBy (comparing (\(Elision st _ _) -> Down st)) es)
  where
    apply s (Elision st en repl) = BS.take st s <> repl <> BS.drop en s
