-- | The built-in tools: filesystem reads/writes, directory listing, and shell. Ported from Rust
-- @lvz-tools@ @builtins.rs@. Each is a 'Tool' record (the @Arc\<dyn Tool\>@ analogue). Tool-visible
-- failures (missing file, non-zero exit) are 'toolErr' results (the turn continues); only a bad
-- argument shape is a hard 'ToolError'.
module Lavoisier.Tool.Builtins
  ( builtinTools,
    readFileTool,
    readFilesTool,
    writeFileTool,
    listDirTool,
    shellTool,
    outlineFileTool,
    outlineFilesTool,
  )
where

import Control.Exception (IOException, try)
import Data.Aeson (Value (..), object, (.=))
import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.List (sort)
import Data.Scientific (toBoundedInteger)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding (decodeUtf8Lenient, encodeUtf8)
import Data.Text.IO qualified as TIO
import Lavoisier.Context.Lang (langFromPath)
import Lavoisier.Context.Skeleton qualified as Skel
import Lavoisier.Context.Symbols qualified as Sym
import Lavoisier.Protocol.Tool
import System.Directory
  ( createDirectoryIfMissing,
    doesDirectoryExist,
    listDirectory,
  )
import System.Exit (ExitCode (..))
import System.FilePath (takeDirectory)
import System.Process.Typed (proc, readProcess)

-- | The default built-in tool set, in registration order.
builtinTools :: [Tool]
builtinTools =
  [ readFileTool,
    readFilesTool,
    writeFileTool,
    listDirTool,
    shellTool,
    outlineFileTool,
    outlineFilesTool
  ]

readFileTool :: Tool
readFileTool =
  Tool
    { toolName = "read_file",
      toolDescription =
        "Read the UTF-8 contents of a file at the given path (relative to the working directory).",
      toolSchema =
        object
          [ "type" .= sv "object",
            "properties" .= object ["path" .= prop "Path to the file"],
            "required" .= [sv "path"]
          ],
      toolInvoke = \args -> withArg (argStr "path" args) $ \path -> do
        r <- tryIO (TIO.readFile (T.unpack path))
        pure . Right $ case r of
          Right content -> toolOk content
          Left e -> toolErr ("read_file " <> path <> ": " <> tshow e)
    }

readFilesTool :: Tool
readFilesTool =
  Tool
    { toolName = "read_files",
      toolDescription =
        "Read several files at once and return them concatenated under per-file headers. Prefer "
          <> "this over multiple read_file calls when you need more than one file. A failure to read "
          <> "one file is reported inline; the rest still return.",
      toolSchema =
        object
          [ "type" .= sv "object",
            "properties"
              .= object
                [ "paths"
                    .= object
                      [ "type" .= sv "array",
                        "items" .= object ["type" .= sv "string"],
                        "description" .= sv "Paths to read, relative to the working directory"
                      ]
                ],
            "required" .= [sv "paths"]
          ],
      toolInvoke = \args -> withArg (argStrList "paths" args) $ \paths -> do
        sections <- mapM readOne paths
        pure (Right (toolOk (T.intercalate "\n\n" sections)))
    }
  where
    readOne path = do
      r <- tryIO (TIO.readFile (T.unpack path))
      let body = either (\e -> "[error: " <> tshow e <> "]") id r
      pure ("===== " <> path <> " =====\n" <> body)

writeFileTool :: Tool
writeFileTool =
  Tool
    { toolName = "write_file",
      toolDescription = "Create or overwrite a file at the given path with the provided UTF-8 content.",
      toolSchema =
        object
          [ "type" .= sv "object",
            "properties"
              .= object
                [ "path" .= prop "Path to the file",
                  "content" .= prop "Full file contents to write"
                ],
            "required" .= [sv "path", sv "content"]
          ],
      toolInvoke = \args -> withArg (both (argStr "path" args) (argStr "content" args)) $ \(path, content) -> do
        let dir = takeDirectory (T.unpack path)
        _ <- tryIO (createDirectoryIfMissing True dir)
        existing <- tryIO (TIO.readFile (T.unpack path))
        let changed = either (const True) (/= content) existing
            nbytes = BS.length (encodeUtf8 content)
        w <- tryIO (TIO.writeFile (T.unpack path) content)
        pure . Right $ case w of
          Right () -> setChanged changed (toolOk ("wrote " <> tshow nbytes <> " bytes to " <> path))
          Left e -> toolErr ("write_file " <> path <> ": " <> tshow e)
    }

listDirTool :: Tool
listDirTool =
  Tool
    { toolName = "list_dir",
      toolDescription =
        "List the names of entries in a directory (defaults to the working directory). "
          <> "Directory entries are suffixed with '/'.",
      toolSchema =
        object
          [ "type" .= sv "object",
            "properties" .= object ["path" .= prop "Directory path (default '.')"]
          ],
      toolInvoke = \args -> withArg (Right (argStrOr "path" "." args)) $ \path -> do
        r <- tryIO (listDirectory (T.unpack path))
        case r of
          Left e -> pure (Right (toolErr ("list_dir " <> path <> ": " <> tshow e)))
          Right names -> do
            decorated <- mapM (decorate path) names
            pure (Right (toolOk (T.intercalate "\n" (sort decorated))))
    }
  where
    decorate path name = do
      isDir <- doesDirectoryExist (T.unpack path <> "/" <> name)
      pure (T.pack (if isDir then name <> "/" else name))

shellTool :: Tool
shellTool =
  Tool
    { toolName = "shell",
      toolDescription =
        "Run a shell command via `sh -c` in the working directory and return its stdout, stderr, "
          <> "and exit code.",
      toolSchema =
        object
          [ "type" .= sv "object",
            "properties" .= object ["command" .= prop "Command line to execute"],
            "required" .= [sv "command"]
          ],
      toolInvoke = \args -> withArg (argStr "command" args) $ \command -> do
        r <- tryIO (readProcess (proc "sh" ["-c", T.unpack command]))
        pure . Right $ case r of
          Left e -> toolErr ("shell: " <> tshow e)
          Right (code, out, err) ->
            let n = case code of ExitSuccess -> 0 :: Int; ExitFailure k -> k
                rendered =
                  "exit="
                    <> tshow n
                    <> "\n--- stdout ---\n"
                    <> decodeUtf8Lenient (BL.toStrict out)
                    <> "\n--- stderr ---\n"
                    <> decodeUtf8Lenient (BL.toStrict err)
             in (if code == ExitSuccess then toolOk else toolErr) rendered
    }

-- --- context-engine tools (skeleton + symbol references over tree-sitter) -------------------------

-- | Skeletonise one source file (signatures kept, bodies elided), with an optional symbol focus.
outlineFileTool :: Tool
outlineFileTool =
  Tool
    { toolName = "outline_file",
      toolDescription =
        "Return a token-efficient skeleton of a source file: signatures, type definitions and doc "
          <> "comments kept, function/method bodies elided. Optionally focus on a symbol — pass "
          <> "`focus` (and `radius`, default 1) to keep full bodies for it and everything within "
          <> "`radius` dependency hops. Supported: Rust, Python, JavaScript, TypeScript; other files "
          <> "are returned unchanged. Prefer this over read_file when you only need a file's shape.",
      toolSchema =
        object
          [ "type" .= sv "object",
            "properties"
              .= object
                [ "path" .= prop "Path to the source file",
                  "focus" .= prop "Optional symbol to expand around (keep its body + dependencies)",
                  "radius"
                    .= object
                      [ "type" .= sv "integer",
                        "minimum" .= (0 :: Int),
                        "description" .= sv "Dependency-hop radius for focus (default 1)"
                      ]
                ],
            "required" .= [sv "path"]
          ],
      toolInvoke = \args -> withArg (argStr "path" args) $ \path -> do
        r <- tryIO (BS.readFile (T.unpack path))
        case r of
          Left e -> pure (Right (toolErr ("outline_file " <> path <> ": " <> tshow e)))
          Right bytes -> case langFromPath (T.unpack path) of
            Nothing -> pure (Right (toolOk (decodeUtf8Lenient bytes)))
            Just lang -> do
              out <- case argStr "focus" args of
                Right focus -> Sym.skeletonWithRadius lang focus (max 0 (argIntOr "radius" 1 args)) bytes
                Left _ -> Skel.skeleton lang bytes
              pure (Right (toolOk (decodeUtf8Lenient out)))
    }

-- | Skeletonise several source files at once, concatenated under per-file headers.
outlineFilesTool :: Tool
outlineFilesTool =
  Tool
    { toolName = "outline_files",
      toolDescription =
        "Skeletonise several source files at once (signatures kept, bodies elided), concatenated "
          <> "under per-file headers. Prefer this over multiple outline_file calls. Optional "
          <> "`focus`/`radius` apply to each file. Unsupported file types are returned unchanged.",
      toolSchema =
        object
          [ "type" .= sv "object",
            "properties"
              .= object
                [ "paths"
                    .= object
                      [ "type" .= sv "array",
                        "items" .= object ["type" .= sv "string"],
                        "description" .= sv "Paths to outline, relative to the working directory"
                      ],
                  "focus" .= prop "Optional symbol to expand around in each file",
                  "radius"
                    .= object
                      [ "type" .= sv "integer",
                        "minimum" .= (0 :: Int),
                        "description" .= sv "Dependency-hop radius for focus (default 1)"
                      ]
                ],
            "required" .= [sv "paths"]
          ],
      toolInvoke = \args -> withArg (argStrList "paths" args) $ \paths -> do
        let mfocus = either (const Nothing) Just (argStr "focus" args)
            radius = max 0 (argIntOr "radius" 1 args)
        sections <- mapM (outlineOne mfocus radius) paths
        pure (Right (toolOk (T.intercalate "\n\n" sections)))
    }
  where
    outlineOne mfocus radius path = do
      r <- tryIO (BS.readFile (T.unpack path))
      body <- case r of
        Left e -> pure ("[error: " <> tshow e <> "]")
        Right bytes -> case langFromPath (T.unpack path) of
          Nothing -> pure (decodeUtf8Lenient bytes)
          Just lang ->
            decodeUtf8Lenient <$> case mfocus of
              Just focus -> Sym.skeletonWithRadius lang focus radius bytes
              Nothing -> Skel.skeleton lang bytes
      pure ("===== " <> path <> " =====\n" <> body)

-- --- argument parsing + small helpers -------------------------------------------------------------

-- | Run an IO effect only when the arguments parsed; a parse failure short-circuits to 'ToolError'.
withArg :: Either ToolError a -> (a -> IO (Either ToolError ToolOutput)) -> IO (Either ToolError ToolOutput)
withArg (Left e) _ = pure (Left e)
withArg (Right a) k = k a

argStr :: Text -> Value -> Either ToolError Text
argStr key (Object o) = case KM.lookup (K.fromText key) o of
  Just (String s) -> Right s
  Just _ -> Left (TEInvalidArgs (key <> " must be a string"))
  Nothing -> Left (TEInvalidArgs ("missing argument: " <> key))
argStr _ _ = Left (TEInvalidArgs "expected a JSON object")

argStrOr :: Text -> Text -> Value -> Text
argStrOr key def v = either (const def) id (argStr key v)

-- | An integer argument with a default (a non-integer or absent value falls back to @def@).
argIntOr :: Text -> Int -> Value -> Int
argIntOr key def (Object o) = case KM.lookup (K.fromText key) o of
  Just (Number n) -> maybe def id (toBoundedInteger n)
  _ -> def
argIntOr _ def _ = def

argStrList :: Text -> Value -> Either ToolError [Text]
argStrList key (Object o) = case KM.lookup (K.fromText key) o of
  Just (Array a) -> traverse asStr (foldr (:) [] a)
  Just _ -> Left (TEInvalidArgs (key <> " must be an array"))
  Nothing -> Left (TEInvalidArgs ("missing argument: " <> key))
  where
    asStr (String s) = Right s
    asStr _ = Left (TEInvalidArgs (key <> " must be an array of strings"))
argStrList _ _ = Left (TEInvalidArgs "expected a JSON object")

both :: Either e a -> Either e b -> Either e (a, b)
both ea eb = (,) <$> ea <*> eb

tryIO :: IO a -> IO (Either IOException a)
tryIO = try

sv :: Text -> Value
sv = String

-- | A @{"type":"string","description":…}@ schema property.
prop :: Text -> Value
prop desc = object ["type" .= sv "string", "description" .= sv desc]

tshow :: (Show a) => a -> Text
tshow = T.pack . show
