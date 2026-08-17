-- | A minimal, safe Haskell binding to the tree-sitter runtime (ports the parsing substrate of
-- Rust @lvz-context@). tree-sitter's node API passes\/returns @TSNode@ by value, which the Haskell
-- FFI cannot do, so a small C shim (@cbits/lvz_ts_shim.c@) exposes pointer-based entry points.
--
-- This module hides all of that: 'parse' turns a source buffer into an immutable, pure 'Syntax'
-- tree (byte-offset spans + per-child field names), freeing every C node and the tree before it
-- returns. Callers ("Lavoisier.Context.Skeleton", ".Symbols") then work purely over 'Syntax'.
module Lavoisier.Context.TreeSitter
  ( Syntax (..),
    Child (..),
    parse,
    supported,
    namedChildren,
    childByField,
    nodeText,
    descendants,
  )
where

import Control.Monad (forM)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Unsafe qualified as BU
import Data.List (find)
import Data.Text (Text)
import Data.Text qualified as T
import Foreign.C.String (CString, peekCString)
import Foreign.C.Types (CInt (..), CUInt (..))
import Foreign.Ptr (Ptr, nullPtr)
import Lavoisier.Context.Lang (Lang (..))

-- Opaque C types (never dereferenced on the Haskell side).
data LvzLanguage

data LvzTree

data LvzNode

foreign import ccall unsafe "lvz_ts_lang_rust"
  c_lang_rust :: IO (Ptr LvzLanguage)

foreign import ccall unsafe "lvz_ts_lang_python"
  c_lang_python :: IO (Ptr LvzLanguage)

foreign import ccall unsafe "lvz_ts_lang_javascript"
  c_lang_javascript :: IO (Ptr LvzLanguage)

foreign import ccall unsafe "lvz_ts_lang_typescript"
  c_lang_typescript :: IO (Ptr LvzLanguage)

foreign import ccall unsafe "lvz_ts_parse"
  c_parse :: Ptr LvzLanguage -> CString -> CUInt -> IO (Ptr LvzTree)

foreign import ccall unsafe "lvz_tree_delete"
  c_tree_delete :: Ptr LvzTree -> IO ()

foreign import ccall unsafe "lvz_tree_root"
  c_tree_root :: Ptr LvzTree -> IO (Ptr LvzNode)

foreign import ccall unsafe "lvz_node_type"
  c_node_type :: Ptr LvzNode -> IO CString

foreign import ccall unsafe "lvz_node_start_byte"
  c_start :: Ptr LvzNode -> IO CUInt

foreign import ccall unsafe "lvz_node_end_byte"
  c_end :: Ptr LvzNode -> IO CUInt

foreign import ccall unsafe "lvz_node_is_named"
  c_is_named :: Ptr LvzNode -> IO CInt

foreign import ccall unsafe "lvz_node_child_count"
  c_child_count :: Ptr LvzNode -> IO CUInt

foreign import ccall unsafe "lvz_node_child"
  c_child :: Ptr LvzNode -> CUInt -> IO (Ptr LvzNode)

foreign import ccall unsafe "lvz_node_field_name_for_child"
  c_field_name :: Ptr LvzNode -> CUInt -> IO CString

foreign import ccall unsafe "lvz_node_free"
  c_node_free :: Ptr LvzNode -> IO ()

-- | An immutable parsed node: its grammar kind, whether it is a /named/ node, its byte span in the
-- source, and its children (each tagged with its field name, if any).
data Syntax = Syntax
  { synType :: !Text,
    synNamed :: !Bool,
    synStart :: !Int,
    synEnd :: !Int,
    synChildren :: [Child]
  }
  deriving stock (Show, Eq)

-- | A child edge: the field name the parent gives this child (e.g. @body@, @name@), if any.
data Child = Child
  { childField :: !(Maybe Text),
    childNode :: !Syntax
  }
  deriving stock (Show, Eq)

-- | The grammar pointer for a language, or 'Nothing' if its grammar is not yet vendored\/wired.
grammar :: Lang -> Maybe (IO (Ptr LvzLanguage))
grammar = \case
  Rust -> Just c_lang_rust
  Python -> Just c_lang_python
  JavaScript -> Just c_lang_javascript
  TypeScript -> Just c_lang_typescript

-- | Whether 'parse' can handle a language (its tree-sitter grammar is linked in).
supported :: Lang -> Bool
supported l = case grammar l of
  Just _ -> True
  Nothing -> False

-- | Parse a UTF-8 source buffer into a pure 'Syntax' tree. Returns 'Nothing' if the language's
-- grammar is unavailable or the parser produced no tree. All C resources are freed before return.
parse :: Lang -> ByteString -> IO (Maybe Syntax)
parse lang src = case grammar lang of
  Nothing -> pure Nothing
  Just getLang -> do
    langP <- getLang
    BU.unsafeUseAsCStringLen src $ \(ptr, len) -> do
      tree <- c_parse langP ptr (fromIntegral len)
      if tree == nullPtr
        then pure Nothing
        else do
          root <- c_tree_root tree
          result <-
            if root == nullPtr
              then pure Nothing
              else Just <$> convert root
          c_tree_delete tree
          pure result

-- | Convert a live C node into pure 'Syntax', freeing it (and each child) as it goes.
convert :: Ptr LvzNode -> IO Syntax
convert node = do
  ty <- c_node_type node >>= peekCString
  named <- (/= 0) <$> c_is_named node
  start <- fromIntegral <$> c_start node
  end <- fromIntegral <$> c_end node
  count <- c_child_count node
  children <- forM [0 .. fromIntegral count - 1 :: Int] $ \i -> do
    fnamePtr <- c_field_name node (fromIntegral i)
    fname <-
      if fnamePtr == nullPtr
        then pure Nothing
        else Just . T.pack <$> peekCString fnamePtr
    childPtr <- c_child node (fromIntegral i)
    childSyn <- convert childPtr
    pure (Child fname childSyn)
  c_node_free node
  pure (Syntax (T.pack ty) named start end children)

-- | The named children of a node (drops anonymous tokens like punctuation\/keywords).
namedChildren :: Syntax -> [Syntax]
namedChildren = map childNode . filter (synNamed . childNode) . synChildren

-- | The child a node exposes under a given field name (e.g. @"body"@, @"name"@), if present.
childByField :: Text -> Syntax -> Maybe Syntax
childByField name = fmap childNode . find ((== Just name) . childField) . synChildren

-- | The source bytes a node spans.
nodeText :: ByteString -> Syntax -> ByteString
nodeText src s = BS.take (synEnd s - synStart s) (BS.drop (synStart s) src)

-- | A node and all of its descendants, pre-order.
descendants :: Syntax -> [Syntax]
descendants s = s : concatMap (descendants . childNode) (synChildren s)
