-- | The tool registry: an ordered set of 'Tool's, the 'ToolDef's advertised to the model, and
-- name-based dispatch. Ported from Rust @lvz-tools@ @lib.rs@ (@ToolRegistry@). Last registration
-- wins on a duplicate name, so a caller-provided tool can deliberately shadow a built-in.
module Lavoisier.Tool.Registry
  ( ToolRegistry,
    emptyRegistry,
    withBuiltins,
    registerTool,
    registerTools,
    registryTools,
    registryDefs,
    invokeTool,
  )
where

import Data.Aeson (Value)
import Data.List (find)
import Data.Text (Text)
import Lavoisier.Protocol.Message (ToolDef (..))
import Lavoisier.Protocol.Tool
import Lavoisier.Tool.Builtins (builtinTools)
import Lavoisier.Tool.Edit (editToolset)

-- | An ordered collection of tools.
newtype ToolRegistry = ToolRegistry [Tool]

-- | An empty registry.
emptyRegistry :: ToolRegistry
emptyRegistry = ToolRegistry []

-- | A registry pre-loaded with the built-in tools (filesystem\/shell\/context + the edit suite).
withBuiltins :: ToolRegistry
withBuiltins = ToolRegistry (builtinTools <> editToolset)

-- | Append a tool (last registration wins on dispatch).
registerTool :: Tool -> ToolRegistry -> ToolRegistry
registerTool t (ToolRegistry ts) = ToolRegistry (ts <> [t])

-- | Append several tools, in order.
registerTools :: [Tool] -> ToolRegistry -> ToolRegistry
registerTools extra (ToolRegistry ts) = ToolRegistry (ts <> extra)

-- | The tools, in registration order.
registryTools :: ToolRegistry -> [Tool]
registryTools (ToolRegistry ts) = ts

-- | The tool definitions advertised to the model, in registration order.
registryDefs :: ToolRegistry -> [ToolDef]
registryDefs (ToolRegistry ts) =
  [ToolDef (toolName t) (toolDescription t) (toolSchema t) False False | t <- ts]

-- | Dispatch a call by name (last-registered wins); an unknown name is a hard 'TEUnknown'.
invokeTool :: Text -> Value -> ToolRegistry -> IO (Either ToolError ToolOutput)
invokeTool name args (ToolRegistry ts) =
  case find ((== name) . toolName) (reverse ts) of
    Just t -> toolInvoke t args
    Nothing -> pure (Left (TEUnknown name))
