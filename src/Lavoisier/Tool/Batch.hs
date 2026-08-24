-- | The @batch_edit@ tool (ports Rust @lvz-tools::batch@): apply many INDEPENDENT, mechanical
-- per-file edits in one discounted asynchronous batch job (~50% of the normal token cost). Each
-- file + instruction becomes an editor request; the model replies with SEARCH\/REPLACE blocks (a
-- cheap diff) or a full-file rewrite, applied here. Decoupled from the concrete batch API via the
-- 'Batch' hook, so it drives a real provider batch from the CLI and a mock in tests.
module Lavoisier.Tool.Batch
  ( batchEditTool,
    applyResponse,
    parseSearchReplace,
    stripCodeFence,
  )
where

import Control.Exception (IOException, try)
import Control.Monad (forM)
import Data.Aeson (Value (..), object, (.=))
import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding (encodeUtf8)
import Data.Text.IO qualified as TIO
import Data.Vector qualified as V
import Data.Word (Word32)
import Lavoisier.Domain (ModelId (..))
import Lavoisier.Protocol.Batch
import Lavoisier.Protocol.Event (Usage (..), accumulateUsage, emptyUsage)
import Lavoisier.Protocol.Message
import Lavoisier.Protocol.Tool

-- | Generation ceiling per editor request.
batchMaxTokens :: Word32
batchMaxTokens = 8192

searchMark, dividerMark, replaceMark :: Text
searchMark = "<<<<<<< SEARCH"
dividerMark = "======="
replaceMark = ">>>>>>> REPLACE"

editorSystem :: Text
editorSystem =
  "You are a precise code editor. You are given one file and one instruction. Express your edit as "
    <> "one or more SEARCH/REPLACE blocks in exactly this format:\n"
    <> "<<<<<<< SEARCH\n(the exact existing lines to find, copied verbatim)\n=======\n(the "
    <> "replacement lines)\n>>>>>>> REPLACE\n"
    <> "Each SEARCH section must match the current file content exactly (including indentation) and "
    <> "be unique enough to locate. Use a separate block per disjoint change. Output ONLY the blocks "
    <> "— no prose, no code fences. If the change rewrites most of the file, instead output the "
    <> "COMPLETE new file contents with no SEARCH/REPLACE markers at all. If the instruction does not "
    <> "apply, output the file unchanged with no markers."

editorUserPrompt :: Text -> Text -> Text -> Text
editorUserPrompt path content instruction =
  "File `" <> path <> "`:\n```\n" <> content <> "\n```\n\nApply this change to the file above:\n" <> instruction

-- | @batch_edit@, bound to a default model + a 'Batch' runner.
batchEditTool :: ModelId -> Batch -> Tool
batchEditTool defaultModel batch =
  Tool
    { toolName = "batch_edit",
      toolDescription =
        "Apply many INDEPENDENT, mechanical per-file edits in one discounted asynchronous batch job "
          <> "(~50% of the normal token cost). Use this — not repeated str_replace/edit calls — when a "
          <> "task fans out into the same kind of self-contained change across many files (e.g. rename "
          <> "a symbol across modules, apply one migration to each file). Each `instruction` must be "
          <> "fully self-contained: it is sent with only its own file, no shared context. Do NOT use "
          <> "for exploratory work, edits that depend on each other, or a single file.",
      toolSchema =
        object
          [ "type" .= String "object",
            "properties"
              .= object
                [ "edits"
                    .= object
                      [ "type" .= String "array",
                        "description" .= String "The independent per-file edits to run as one batch.",
                        "items"
                          .= object
                            [ "type" .= String "object",
                              "properties"
                                .= object
                                  [ "path" .= prop "File to edit",
                                    "instruction" .= prop "Self-contained change to apply (sent with only this file)"
                                  ],
                              "required" .= [String "path", String "instruction"]
                            ]
                      ],
                  "model" .= prop "Optional model id for the editor requests (defaults to the agent model)"
                ],
            "required" .= [String "edits"]
          ],
      toolInvoke = batchEdit defaultModel batch
    }

-- | One file to edit: its index (the batch @custom_id@), path, and instruction.
data Edit = Edit !Int !Text !Text

batchEdit :: ModelId -> Batch -> Value -> IO (Either ToolError ToolOutput)
batchEdit defaultModel batch args = case parseEdits args of
  Left e -> pure (Left e)
  Right edits -> do
    let model = maybe defaultModel ModelId (strArg "model" args)
    prepared <- forM edits $ \(Edit i path instruction) -> do
      r <- tryText path
      pure (i, path, instruction, r)
    let tasks = [BatchTask (tshow i) (editorReq model path content instruction) | (i, path, instruction, Right content) <- prepared]
        prefailed = [path <> ": could not read (" <> e <> ")" | (_, path, _, Left e) <- prepared]
    if null tasks
      then pure (Right (toolErr ("batch_edit: no readable files to edit:\n" <> T.intercalate "\n" prefailed)))
      else do
        r <- runBatch batch tasks
        case r of
          Left (BatchError e) -> pure (Left (TEExecution ("batch_edit: batch run failed: " <> e)))
          Right items -> do
            let byId = Map.fromList [(biId it, it) | it <- items]
                readable = [(i, path, content) | (i, path, _, Right content) <- prepared]
            outcomes <- forM readable $ \(i, path, orig) -> applyItem byId i path orig
            let applied = length [() | ((_, True), _) <- outcomes]
                usage = foldr (accumulateUsage . snd) emptyUsage outcomes
                lns = map (fst . fst) outcomes <> prefailed
                summary =
                  "batch_edit: applied "
                    <> tshow applied
                    <> "/"
                    <> tshow (length edits)
                    <> " edits via discounted batch (~50% token cost; tokens: in="
                    <> tshow (inputTokens usage)
                    <> " out="
                    <> tshow (outputTokens usage)
                    <> ").\n"
                    <> T.intercalate "\n" lns
            pure (Right (setChanged (applied > 0) (toolOk summary)))

-- | Apply one batch item to its file; returns @(report line, changed?, item usage)@ flattened.
applyItem :: Map.Map Text BatchItem -> Int -> Text -> Text -> IO ((Text, Bool), Usage)
applyItem byId i path orig = case Map.lookup (tshow i) byId of
  Nothing -> pure ((path <> ": no result returned for this file", False), emptyUsage)
  Just item -> case biError item of
    Just err -> pure ((path <> ": batch error (" <> err <> ")", False), biUsage item)
    Nothing
      | T.null (T.strip (biText item)) -> pure ((path <> ": skipped (model returned empty output)", False), biUsage item)
      | otherwise -> case applyResponse orig (biText item) of
          Left why -> pure ((path <> ": skipped (" <> why <> ")", False), biUsage item)
          Right new
            | new == orig -> pure ((path <> ": unchanged", False), biUsage item)
            | otherwise -> do
                w <- tryWrite path new
                pure $ case w of
                  Left e -> ((path <> ": write failed (" <> e <> ")", False), biUsage item)
                  Right () -> ((path <> ": edited (" <> tshow (nbytes orig) <> " -> " <> tshow (nbytes new) <> " bytes)", True), biUsage item)

editorReq :: ModelId -> Text -> Text -> Text -> ChatRequest
editorReq model path content instruction =
  (chatRequest model)
    { crSystem = Just (SystemPrompt editorSystem True),
      crMessages = [userMessage (editorUserPrompt path content instruction)],
      crMaxTokens = batchMaxTokens
    }

-- --- response application (SEARCH/REPLACE blocks, else full-file rewrite) --------------------------

-- | Apply an editor response to @original@: SEARCH\/REPLACE blocks when present (a cheap diff), else
-- the whole response as a full-file rewrite (a stray code fence is unwrapped). @Left@ when a SEARCH
-- block does not match.
applyResponse :: Text -> Text -> Either Text Text
applyResponse original response = case parseSearchReplace response of
  [] -> Right (stripCodeFence response)
  blocks -> go original (zip [1 :: Int ..] blocks)
  where
    go content [] = Right content
    go content ((n, (search, replace)) : rest)
      | search `T.isInfixOf` content = go (replaceFirst search replace content) rest
      | otherwise = Left ("SEARCH block " <> tshow n <> " did not match the file (it must copy the existing lines verbatim)")

-- | Parse @<<<<<<< SEARCH … ======= … >>>>>>> REPLACE@ blocks into @(search, replace)@ pairs.
parseSearchReplace :: Text -> [(Text, Text)]
parseSearchReplace response = go (T.lines response)
  where
    go [] = []
    go (l : ls)
      | T.stripEnd l == searchMark =
          let (search, afterDiv) = break' dividerMark ls
           in case afterDiv of
                Nothing -> []
                Just rest ->
                  let (replace, afterClose) = break' replaceMark rest
                   in case afterClose of
                        Nothing -> []
                        Just rest' -> (T.intercalate "\n" search, T.intercalate "\n" replace) : go rest'
      | otherwise = go ls
    -- Split lines at the first line == mark (trimmed), returning (before, Just after) or (all, Nothing).
    break' mark = collect []
      where
        collect acc [] = (reverse acc, Nothing)
        collect acc (x : xs)
          | T.stripEnd x == mark = (reverse acc, Just xs)
          | otherwise = collect (x : acc) xs

-- | Unwrap a response that is a single whole @```…```@ fenced block; leave anything else untouched.
stripCodeFence :: Text -> Text
stripCodeFence text
  | not ("```" `T.isPrefixOf` trimmed) = text
  | otherwise = case T.breakOn "\n" trimmed of
      (_, "") -> text
      (_, nlRest) ->
        let afterOpen = T.drop 1 nlRest
            (before, _) = T.breakOnEnd "```" afterOpen -- @before@ ends with the last ```, empty if absent
         in if T.null before then text else T.dropWhileEnd (== '\n') (T.dropEnd 3 before) <> "\n"
  where
    trimmed = T.strip text

-- --- arg parsing + small helpers -------------------------------------------------------------------

parseEdits :: Value -> Either ToolError [Edit]
parseEdits v = case lookupKey "edits" v of
  Just (Array a) -> traverse toEdit (zip [0 ..] (V.toList a))
  _ -> Left (TEInvalidArgs "batch_edit: missing array `edits`")
  where
    toEdit (i, o) = case (strArg "path" o, strArg "instruction" o) of
      (Just p, Just ins) -> Right (Edit i p ins)
      _ -> Left (TEInvalidArgs "batch_edit: each edit needs `path` and `instruction`")

lookupKey :: Text -> Value -> Maybe Value
lookupKey k (Object o) = KM.lookup (K.fromText k) o
lookupKey _ _ = Nothing

strArg :: Text -> Value -> Maybe Text
strArg k v = case lookupKey k v of Just (String s) -> Just s; _ -> Nothing

replaceFirst :: Text -> Text -> Text -> Text
replaceFirst old new t =
  let (before, rest) = T.breakOn old t
   in if T.null rest then t else before <> new <> T.drop (T.length old) rest

nbytes :: Text -> Int
nbytes = BS.length . encodeUtf8

tryText :: Text -> IO (Either Text Text)
tryText p = either (Left . tshow) Right <$> tryIO (TIO.readFile (T.unpack p))

tryWrite :: Text -> Text -> IO (Either Text ())
tryWrite p c = either (Left . tshow) Right <$> tryIO (TIO.writeFile (T.unpack p) c)

tryIO :: IO a -> IO (Either IOException a)
tryIO = try

prop :: Text -> Value
prop d = object ["type" .= String "string", "description" .= String d]

tshow :: (Show a) => a -> Text
tshow = T.pack . show
