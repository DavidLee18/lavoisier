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
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Vector qualified as V
import Lavoisier.Context.Anchor
  ( Edit,
    applyEdits,
    deleteEdit,
    insertAfterEdit,
    insertBeforeEdit,
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
          <> "missing or non-unique match is an error — add surrounding context to disambiguate). Pass "
          <> "`replace_all: true` to replace every occurrence, and `paths` (instead of `path`) to apply "
          <> "the same replacement across several files. Returns a per-file count.",
      toolSchema =
        object
          [ "type" .= str "object",
            "properties"
              .= object
                [ "path" .= prop "File to edit (use this or paths)",
                  "paths" .= arrProp "Files to apply the same edit to (use this or path)",
                  "old" .= prop "Exact text to find (verbatim)",
                  "new" .= prop "Replacement text",
                  "replace_all" .= object ["type" .= str "boolean", "description" .= str "Replace every occurrence (default false)"]
                ],
            "required" .= [str "old", str "new"]
          ],
      toolInvoke = strReplace
    }

strReplace :: Value -> IO (Either ToolError ToolOutput)
strReplace args = case (,) <$> reqStr "old" args <*> reqStr "new" args of
  Left e -> pure (Left e)
  Right (old, new)
    | T.null old -> soft "str_replace: `old` must not be empty"
    | null targets -> soft "str_replace: provide `path` or `paths`"
    | otherwise -> do
        rows <- mapM (replaceOne old new (getBool "replace_all" args)) targets
        let (lns, changed, erred) = foldr step ([], False, False) rows
        pure (Right (setChanged changed (mark erred ("str_replace:\n" <> T.intercalate "\n" lns))))
  where
    targets = maybe [] pure (getStr "path" args) <> getStrs "paths" args
    step (l, c, e) (ls, cc, ee) = (l : ls, c || cc, e || ee)
    soft = pure . Right . toolErr

-- | Edit one file; returns @(report line, changed, errored)@.
replaceOne :: Text -> Text -> Bool -> Text -> IO (Text, Bool, Bool)
replaceOne old new replaceAll p =
  tryText p >>= \case
    Left e -> pure (p <> ": read error (" <> e <> ")", False, True)
    Right original -> case T.count old original of
      0 -> pure (p <> ": `old` not found", False, True)
      n
        | n > 1 && not replaceAll ->
            pure (p <> ": `old` occurs " <> tshow n <> "× — pass replace_all or add context to disambiguate", False, True)
        | updated == original -> pure (p <> ": no change (replacement equals original)", False, False)
        | otherwise ->
            tryWrite p updated >>= \case
              Left e -> pure (p <> ": write error (" <> e <> ")", False, True)
              Right () -> pure (p <> ": replaced " <> tshow n <> " occurrence(s)", True, False)
        where
          updated = if replaceAll then T.replace old new original else replaceFirst old new original

replaceFirst :: Text -> Text -> Text -> Text
replaceFirst old new t =
  let (before, rest) = T.breakOn old t
   in if T.null rest then t else before <> new <> T.drop (T.length old) rest

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
          <> "op is replace|insert_after|insert_before|delete (anchors come from read_anchored).",
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
      Left aerr -> pure (Left (tshow aerr))
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
  case op of
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
                  "op" .= object ["type" .= str "string", "enum" .= map str ["replace", "insert_after", "insert_before", "delete"]],
                  "text" .= prop "Replacement/inserted text (omit for delete)"
                ],
            "required" .= [str "anchor", str "op"]
          ]
    ]

tshow :: (Show a) => a -> Text
tshow = T.pack . show
