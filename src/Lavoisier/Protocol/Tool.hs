{- | The 'Tool' contract. Built-in tools live in @Lavoisier.Tool.Builtins@; the agent dispatches
calls through this record without knowing their concrete implementation. Ported from Rust
@lvz-protocol@ @tool.rs@ (@Arc\<dyn Tool\>@ → a record of functions).
-}
module Lavoisier.Protocol.Tool (
    ToolOutput (..),
    toolOk,
    toolErr,
    setChanged,
    ToolError (..),
    Tool (..),
)
where

import Data.Aeson (Value)
import Data.Text (Text)

import Lavoisier.Domain (ToolName)

{- | The successful result of a tool invocation. 'toIsError' lets a tool report a recoverable,
model-visible failure without aborting the turn; 'toChanged' records whether the workspace was
actually mutated (the agent's convergence signal).
-}
data ToolOutput = ToolOutput
    { toContent ∷ Text
    , toIsError ∷ Bool
    , toChanged ∷ Bool
    }
    deriving stock (Eq, Show)

-- | A successful result (no workspace mutation by default).
toolOk ∷ Text → ToolOutput
toolOk c = ToolOutput c False False

-- | A model-visible error result (the turn continues; the model sees the message).
toolErr ∷ Text → ToolOutput
toolErr c = ToolOutput c True False

-- | Mark whether this invocation actually changed a file (builder).
setChanged ∷ Bool → ToolOutput → ToolOutput
setChanged b o = o {toChanged = b}

-- | A hard tool failure (the dispatcher could not run the tool at all).
data ToolError
    = -- | No tool registered under the requested name.
      TEUnknown Text
    | -- | Arguments did not match the tool's schema.
      TEInvalidArgs Text
    | -- | The tool ran but failed irrecoverably.
      TEExecution Text
    deriving stock (Eq, Show)

-- | A capability the model can invoke, as a record of functions.
data Tool = Tool
    { toolName ∷ ToolName
    , toolDescription ∷ Text
    , toolSchema ∷ Value
    , toolInvoke ∷ Value → IO (Either ToolError ToolOutput)
    }
