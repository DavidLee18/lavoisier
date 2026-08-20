-- | The editing tools (ports Rust @lvz-tools@ @context.rs@ edit surface): @str_replace@ (exact-string
-- replacement — the preferred edit) plus the anchored suite @read_anchored@\/@edit_anchored@\/
-- @edit_files@, thin wrappers over "Lavoisier.Context.Anchor". A bad argument shape is a hard
-- 'ToolError'; a missing file, an unmatched anchor, or a non-unique match is a soft 'toolErr' result.
module Lavoisier.Tool.Edit
  ( editToolset,
    strReplaceTool,
    readAnchoredTool,
    editAnchoredTool,
    editFilesTool,
  )
where

import Control.Exception (IOException, try)
import Data.Aeson (Value (..), object, (.=))
import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.Maybe (fromMaybe, isJust)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Vector qualified as V
import Lavoisier.Context.Anchor
  ( Edit,
    after,
    applyEdits,
    deleteEdit,
    insertAfterEdit,
    insertBeforeEdit,
    renderAnchorError,
    renderAnchored,
    replaceEdit,
  )
import Lavoisier.Protocol.Tool

-- | The default edit tools, in registration order.
editToolset :: [Tool]
editToolset = [strReplaceTool, readAnchoredTool, editAnchoredTool, editFilesTool]

-- --- str_replace ----------------------------------------------------------------------------------

strReplaceTool :: Tool
strReplaceTool =
  Tool
    { toolName = "str_replace",
      toolDescription =
        "Edit a file by exact-string replacement — the preferred edit tool. Pass `old` (verbatim text "
          <> "to find, including indentation) and `new`. By default `old` must match exactly once (a "
          <> "missing or non-unique match is an error). To pick one of several matches, narrow the "
          <> "search with `after` and/or `before`: each is a verbatim snippet that must itself occur "
          <> "exactly once, and only matches of `old` between them are considered. Pass "
          <> "`replace_all: true` to replace every occurrence (within that window, if given), and "
          <> "`paths` (instead of `path`) to apply the same replacement across several files. Returns "
          <> "a per-file count.",
      toolSchema =
        object
          [ "type" .= str "object",
            "properties"
              .= object
                [ "path" .= prop "File to edit (use this or paths)",
                  "paths" .= arrProp "Files to apply the same edit to (use this or path)",
                  "old" .= prop "Exact text to find (verbatim)",
                  "new" .= prop "Replacement text",
                  "after" .= prop "Only consider matches of `old` that start after this snippet (which must occur exactly once)",
                  "before" .= prop "Only consider matches of `old` that end before this snippet (which must occur exactly once)",
                  "replace_all" .= object ["type" .= str "boolean", "description" .= str "Replace every occurrence (default false)"]
                ],
            "required" .= [str "old", str "new"]
          ],
      toolInvoke = strReplace
    }

-- | One @str_replace@ request, resolved from the argument object.
data ReplaceSpec = ReplaceSpec
  { rsOld :: Text,
    rsNew :: Text,
    rsAll :: Bool,
    -- | Only match @old@ after this (unique) snippet.
    rsAfter :: Maybe Text,
    -- | Only match @old@ before this (unique) snippet.
    rsBefore :: Maybe Text
  }

strReplace :: Value -> IO (Either ToolError ToolOutput)
strReplace args = case (,) <$> reqStr "old" args <*> reqStr "new" args of
  Left e -> pure (Left e)
  Right (old, new)
    | T.null old -> soft "str_replace: `old` must not be empty"
    | null targets -> soft "str_replace: provide `path` or `paths`"
    | otherwise -> do
        rows <- mapM (replaceOne spec) targets
        let (lns, changed, erred) = foldr step ([], False, False) rows
        pure (Right (setChanged changed (mark erred ("str_replace:\n" <> T.intercalate "\n" lns))))
    where
      spec =
        ReplaceSpec
          { rsOld = old,
            rsNew = new,
            rsAll = getBool "replace_all" args,
            rsAfter = getStr "after" args,
            rsBefore = getStr "before" args
          }
  where
    targets = maybe [] pure (getStr "path" args) <> getStrs "paths" args
    step (l, c, e) (ls, cc, ee) = (l : ls, c || cc, e || ee)
    soft = pure . Right . toolErr

-- | Edit one file; returns @(report line, changed, errored)@.
replaceOne :: ReplaceSpec -> Text -> IO (Text, Bool, Bool)
replaceOne spec p =
  tryText p >>= \case
    Left e -> pure (p <> ": read error (" <> e <> ")", False, True)
    Right original -> case selectTargets spec original of
      Left msg -> pure (p <> ": " <> msg, False, True)
      Right offs
        | updated == original -> pure (p <> ": no change (replacement equals original)", False, False)
        | otherwise ->
            tryWrite p updated >>= \case
              Left e -> pure (p <> ": write error (" <> e <> ")", False, True)
              Right () -> pure (p <> ": replaced " <> tshow (length offs) <> " occurrence(s)", True, False)
        where
          updated = spliceAll (rsOld spec) (rsNew spec) offs original

-- | Which occurrences of @old@ to rewrite (as start offsets), or why the request is not unambiguous.
--
-- The window bounds are themselves content — a snippet that must occur exactly once — never a line
-- number or an occurrence index. That keeps the whole edit path content-addressed: a stale request
-- fails loudly here rather than landing on whatever now sits at some position.
selectTargets :: ReplaceSpec -> Text -> Either Text [Int]
selectTargets spec original = do
  lo <- case rsAfter spec of
    Nothing -> Right 0
    Just s -> (+ T.length s) <$> unique "after" s
  hi <- case rsBefore spec of
    Nothing -> Right (T.length original)
    Just s -> unique "before" s
  if lo > hi
    then Left "`after` occurs at or past `before` — the search window is empty"
    else case [i | i <- occurrences (rsOld spec) original, i >= lo, i + T.length (rsOld spec) <= hi] of
      [] -> Left (if windowed then "`old` not found between `after` and `before`" else "`old` not found")
      offs
        | rsAll spec -> Right offs
        | [i] <- offs -> Right [i]
        | otherwise -> Left (ambiguous (length offs))
  where
    windowed = isJust (rsAfter spec) || isJust (rsBefore spec)
    unique label s = case occurrences s original of
      [i] -> Right i
      [] -> Left ("`" <> label <> "` not found")
      xs -> Left ("`" <> label <> "` occurs " <> tshow (length xs) <> "× — it must match exactly once")
    ambiguous n
      | windowed =
          "`old` occurs " <> tshow n <> "× within the `after`/`before` window — narrow it, or pass replace_all"
      | otherwise =
          "`old` occurs "
            <> tshow n
            <> "× — pass `after`/`before` (a verbatim snippet that occurs exactly once) to pick one, or replace_all to change every occurrence"

-- | The start offsets of every non-overlapping occurrence of @needle@, in order.
occurrences :: Text -> Text -> [Int]
occurrences needle = go 0
  where
    n = T.length needle
    go off t =
      let (pre, rest) = T.breakOn needle t
       in if T.null rest
            then []
            else let i = off + T.length pre in i : go (i + n) (T.drop n rest)

-- | Replace @old@ with @new@ at each given start offset (applied right-to-left, so earlier offsets
-- stay valid).
spliceAll :: Text -> Text -> [Int] -> Text -> Text
spliceAll old new offs t = foldr splice t offs
  where
    splice i acc = T.take i acc <> new <> T.drop (i + T.length old) acc

-- --- anchored suite -------------------------------------------------------------------------------

readAnchoredTool :: Tool
readAnchoredTool =
  Tool
    { toolName = "read_anchored",
      toolDescription =
        "Read a file with a stable per-line anchor gutter. Address later edits (edit_anchored/"
          <> "edit_files) by anchor instead of resending the whole file.",
      toolSchema = object ["type" .= str "object", "properties" .= object ["path" .= prop "Path to the file"], "required" .= [str "path"]],
      toolInvoke = \args -> case reqStr "path" args of
        Left e -> pure (Left e)
        Right p ->
          tryText p >>= \r ->
            pure . Right $ either (\e -> toolErr ("read_anchored " <> p <> ": " <> e)) (toolOk . renderAnchored) r
    }

editAnchoredTool :: Tool
editAnchoredTool =
  Tool
    { toolName = "edit_anchored",
      toolDescription =
        "Apply anchored edits to one file. Pass `path` and `edits`, each `{anchor, op, text}` where "
          <> "op is replace|insert_after|insert_before|delete (anchors come from read_anchored). "
          <> "Identical lines share an anchor: add `after` (the anchor of a unique line above the one "
          <> "you mean) and the first match below it is edited.",
      toolSchema = object ["type" .= str "object", "properties" .= object ["path" .= prop "Path to the file", "edits" .= editsSchema], "required" .= [str "path", str "edits"]],
      toolInvoke = \args -> case (,) <$> reqStr "path" args <*> parseEdits args of
        Left e -> pure (Left e)
        Right (p, edits) ->
          applyToFile p edits >>= \r ->
            pure . Right $ either (\e -> toolErr ("edit_anchored " <> p <> ": " <> e)) (\(s, c) -> setChanged c (toolOk s)) r
    }

editFilesTool :: Tool
editFilesTool =
  Tool
    { toolName = "edit_files",
      toolDescription =
        "Apply anchored edits to SEVERAL files in one call — the multi-file form of edit_anchored. "
          <> "Pass `files`, each `{path, edits}`. A file whose anchor is missing/ambiguous is reported "
          <> "inline and skipped while the others still apply. Returns a per-file summary.",
      toolSchema =
        object
          [ "type" .= str "object",
            "properties" .= object ["files" .= object ["type" .= str "array", "description" .= str "Per-file edit batches", "items" .= object ["type" .= str "object", "properties" .= object ["path" .= prop "Path to the file", "edits" .= editsSchema], "required" .= [str "path", str "edits"]]]],
            "required" .= [str "files"]
          ],
      toolInvoke = editFiles
    }

editFiles :: Value -> IO (Either ToolError ToolOutput)
editFiles args = case parseFiles args of
  Left e -> pure (Left e)
  Right files -> do
    rs <- mapM (\(p, es) -> (,) p <$> applyToFile p es) files
    let failed = length [() | (_, Left _) <- rs]
        changed = or [c | (_, Right (_, c)) <- rs]
        header = "edit_files: applied " <> tshow (length rs - failed) <> " file(s), " <> tshow failed <> " failed.\n"
    pure (Right (setChanged changed (mark (failed > 0) (header <> "\n" <> T.intercalate "\n\n" (map section rs)))))
  where
    section (p, Right (s, _)) = "===== " <> p <> " =====\n" <> s
    section (p, Left e) = "===== " <> p <> " =====\n[error: " <> e <> "]"

-- | Read, apply anchored edits, write back if changed. @Left@ = read/anchor/write error message.
applyToFile :: Text -> [Edit] -> IO (Either Text (Text, Bool))
applyToFile p edits =
  tryText p >>= \case
    Left e -> pure (Left e)
    Right original -> case applyEdits original edits of
      Left aerr -> pure (Left (renderAnchorError aerr))
      Right updated
        | updated == original -> pure (Right ("no change", False))
        | otherwise ->
            tryWrite p updated >>= \case
              Left e -> pure (Left e)
              Right () -> pure (Right ("applied " <> tshow (length edits) <> " edit(s)", True))

-- --- argument + JSON helpers ----------------------------------------------------------------------

lookupKey :: Text -> Value -> Maybe Value
lookupKey k (Object o) = KM.lookup (K.fromText k) o
lookupKey _ _ = Nothing

getStr :: Text -> Value -> Maybe Text
getStr k v = case lookupKey k v of Just (String s) -> Just s; _ -> Nothing

getStrs :: Text -> Value -> [Text]
getStrs k v = case lookupKey k v of Just (Array a) -> [s | String s <- V.toList a]; _ -> []

getBool :: Text -> Value -> Bool
getBool k v = case lookupKey k v of Just (Bool b) -> b; _ -> False

reqStr :: Text -> Value -> Either ToolError Text
reqStr k = maybe (Left (TEInvalidArgs ("missing argument: " <> k))) Right . getStr k

parseEdits :: Value -> Either ToolError [Edit]
parseEdits v = case lookupKey "edits" v of
  Just (Array a) -> traverse parseEdit (V.toList a)
  _ -> Left (TEInvalidArgs "missing array: edits")

parseEdit :: Value -> Either ToolError Edit
parseEdit v = do
  anchor <- reqStr "anchor" v
  op <- reqStr "op" v
  let txt = fromMaybe "" (getStr "text" v)
      qualify = maybe id after (getStr "after" v)
  fmap qualify $ case op of
    "replace" -> Right (replaceEdit anchor txt)
    "insert_after" -> Right (insertAfterEdit anchor txt)
    "insert_before" -> Right (insertBeforeEdit anchor txt)
    "delete" -> Right (deleteEdit anchor)
    _ -> Left (TEInvalidArgs ("unknown edit op: " <> op))

parseFiles :: Value -> Either ToolError [(Text, [Edit])]
parseFiles v = case lookupKey "files" v of
  Just (Array a) -> traverse (\fv -> (,) <$> reqStr "path" fv <*> parseEdits fv) (V.toList a)
  _ -> Left (TEInvalidArgs "missing array: files")

-- --- small IO + schema helpers --------------------------------------------------------------------

tryText :: Text -> IO (Either Text Text)
tryText p = either (Left . tshow) Right <$> tryIO (TIO.readFile (T.unpack p))

tryWrite :: Text -> Text -> IO (Either Text ())
tryWrite p c = either (Left . tshow) Right <$> tryIO (TIO.writeFile (T.unpack p) c)

tryIO :: IO a -> IO (Either IOException a)
tryIO = try

mark :: Bool -> Text -> ToolOutput
mark err = if err then toolErr else toolOk

str :: Text -> Value
str = String

prop :: Text -> Value
prop d = object ["type" .= str "string", "description" .= str d]

arrProp :: Text -> Value
arrProp d = object ["type" .= str "array", "items" .= object ["type" .= str "string"], "description" .= str d]

editsSchema :: Value
editsSchema =
  object
    [ "type" .= str "array",
      "description" .= str "Anchored edits to apply",
      "items"
        .= object
          [ "type" .= str "object",
            "properties"
              .= object
                [ "anchor" .= prop "Line anchor from read_anchored",
                  "after" .= prop "Anchor of a unique line above the target, when several lines share the target's anchor (identical content). The first matching line after it is edited.",
                  "op" .= object ["type" .= str "string", "enum" .= map str ["replace", "insert_after", "insert_before", "delete"]],
                  "text" .= prop "Replacement/inserted text (omit for delete)"
                ],
            "required" .= [str "anchor", str "op"]
          ]
    ]

tshow :: (Show a) => a -> Text
tshow = T.pack . show
