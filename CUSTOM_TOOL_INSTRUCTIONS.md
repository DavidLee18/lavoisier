# Building private custom tools for Lavoisier (Haskell)

How to give the agent your own tools **without forking Lavoisier or putting your code in this
repo**. Your tools live in a separate, private Cabal package that depends on the `lavoisier` library
and injects them at startup via `mainWith`. Your binary then behaves exactly like `lav` — same flags,
config, and gateways (HTTP/Matrix/Slack/cron/schedule/A2A/ACP/MCP, E2EE, persona) — with your tools
additionally available to the agent.

> Tools are **compiled-in Haskell** — there is no dynamic/plugin loading. "Private" means the Haskell
> code stays in your own repo; it never touches the public `lavoisier` source.

This is the Haskell port (branch `haskell-port`). It is the analogue of the Rust engine's
`main_with`; the entry point here is **`Lavoisier.CLI.mainWith :: [Tool] -> IO ()`**.

---

## 1. Create the project

Make a **standalone Cabal package in its own (private) git repo, outside the `lavoisier` checkout**.

```sh
cd ~/source                 # anywhere EXCEPT inside ~/source/lavoisier
mkdir my-lav && cd my-lav
git init
```

## 2. `cabal.project`

Pin the engine by git ref (it is not on Hackage — use an `hs-v*` release tag). The engine links
`libtree-sitter` + `libsnappy` (always) and `libolm` (only under the `e2ee` flag), so point cabal at
wherever those live on your build host — the same machine-specific `extra-lib-dirs` the engine's own
`cabal.project` uses.

`subdir` must list `olm` as well as `.`. The engine's `e2ee` flag pulls in the sibling `olm` package
from the same repo; with `subdir: .` alone, resolution fails with `unknown package: olm`.

Pin at least `hs-v0.13.2` — earlier tags omit the C headers from the packaged tarball and fail to
build as a git dependency (`fatal error: 'lvz_ts_shim.h' file not found`).

```cabal
packages: .

source-repository-package
  type: git
  location: https://github.com/DavidLee18/lavoisier
  tag: hs-v0.13.4            -- an hs-v* release tag (NOT the Rust v* tags)
  subdir: . olm              -- `olm` too: the engine's e2ee flag depends on it

-- Native libs (adjust paths for your host; Homebrew / ~/.local shown).
package lavoisier
  extra-lib-dirs: /opt/homebrew/lib /Users/you/.local/lib
  extra-include-dirs: /opt/homebrew/include /Users/you/.local/include
package snappy-c
  extra-lib-dirs: /opt/homebrew/lib
  extra-include-dirs: /opt/homebrew/include
```

## 3. `my-lav.cabal`

```cabal
cabal-version:      3.0
name:               my-lav
version:            0.1.0
build-type:         Simple

flag e2ee
  description: Matrix end-to-end encryption (forwards to lavoisier's e2ee/libolm).
  default:     False
  manual:      True

executable my-lav
  main-is:          Main.hs
  hs-source-dirs:   app
  default-language: GHC2021
  default-extensions: OverloadedStrings LambdaCase
  ghc-options:      -threaded -rtsopts -with-rtsopts=-N   -- warp needs the threaded RTS
  build-depends:    base, text, aeson, lavoisier
  if flag(e2ee)
    cpp-options: -DE2EE      -- your own code only; see below for the engine's flag
```

**A cabal flag never propagates to a dependency**, so `cabal build -f e2ee` sets *your* flag and
leaves the engine's off. Turn the engine's on in `cabal.project`:

```cabal
constraints: lavoisier +e2ee
```

## 4. `app/Main.hs` — implement `Tool` and call `mainWith`

Everything you need is re-exported from `Lavoisier.CLI`:
`Tool(..)`, `ToolOutput`, `ToolError(..)` (`TEUnknown` / `TEInvalidArgs` / `TEExecution`),
`toolOk`, `toolErr`, `setChanged`.

A `Tool` is a record of four fields:

```haskell
data Tool = Tool
  { toolName        :: Text
  , toolDescription :: Text
  , toolSchema      :: Value                                  -- JSON Schema (advisory; validate yourself)
  , toolInvoke      :: Value -> IO (Either ToolError ToolOutput)
  }
```

```haskell
{-# LANGUAGE OverloadedStrings #-}
module Main (main) where

import Data.Aeson (Value (..), object, (.=))
import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.Text (Text)
import Data.Text qualified as T
import Lavoisier.CLI (Tool (..), ToolError (..), mainWith, toolErr, toolOk)

-- A trivial tool: `greet {"name": "Ada"}` -> "Hello, Ada!".
greetTool :: Tool
greetTool =
  Tool
    { toolName = "greet",
      -- Descriptions steer the model's tool choice — write them the way you want it invoked
      -- (bilingual if your rooms are). Errors are values: return toolErr, never throw.
      toolDescription = "Return a friendly greeting for a given name. / 이름을 받아 인사말을 돌려줍니다.",
      toolSchema =
        object
          [ "type" .= String "object",
            "properties" .= object ["name" .= object ["type" .= String "string"]],
            "required" .= [String "name"]
          ],
      toolInvoke = \args -> case strArg "name" args of
        Nothing -> pure (Right (toolErr "greet: missing `name`"))   -- recoverable, model-visible
        Just n -> pure (Right (toolOk ("Hello, " <> n <> "!")))
    }

main :: IO ()
main = mainWith [greetTool]

strArg :: Text -> Value -> Maybe Text
strArg k (Object o) = case KM.lookup (K.fromText k) o of Just (String s) -> Just s; _ -> Nothing
strArg _ _ = Nothing
```

### Conventions (match these or the agent misbehaves)
- **Errors are values.** A recoverable failure (bad args, upstream 4xx) is
  `Right (toolErr "…")` — model-visible, the loop continues. Reserve
  `Left (TEExecution "…")` for a failure that should abort the turn. Never let `toolInvoke` throw.
- **Validate every argument yourself.** `toolSchema` is advertised to the model but not enforced;
  read args defensively.
- **Signal edits.** If your tool changed a file, wrap the output with `setChanged True` so the
  `--require-edit`/`--verify-and-fix` convergence levers see it.
- **Never log secrets** — lengths/counters only.

## 5. Build and run

```sh
cabal build                 # or:  cabal build -f e2ee
cabal run my-lav -- --agent "greet me as Ada"
cabal run my-lav -- --serve-matrix --schedule-file schedule.dhall   # all gateways, plus your tools
```

Your tools are registered **alongside the built-ins** wherever tools are used — every gateway and
`--agent`. A one-shot `ask` (no `--agent`, no `--serve*`) uses no tools, so your tools are not loaded
there (matching the engine). The `schedule_*` tools and any `--mcp-server` tools compose the same way.

## 6. Packaging for deployment

`mainWith` gives you the whole CLI, so your binary deploys exactly like `lav`: build a self-contained
tarball (bundle `libtree-sitter`/`libsnappy`, and `libolm` under e2ee; rewrite load paths — see the
engine's `scripts/package-haskell.sh`), or build in-container with `cabal install`. Config is **Dhall**
(`--config lavoisier.dhall`); the cron/schedule files are Dhall too.
