-- | Language detection and per-language tree-sitter configuration (ports Rust
-- @lvz-context::lang@). Each supported 'Lang' knows which definition nodes carry an elidable
-- @body@ (for the skeletoniser) and which node kinds are symbols\/references\/binders (for the
-- symbol-dependency graph). The grammar pointer itself lives in "Lavoisier.Context.TreeSitter"
-- (it is FFI, not pure data); everything here is pure.
module Lavoisier.Context.Lang
  ( Lang (..),
    langFromPath,
    LangSpec (..),
    langSpec,
  )
where

import Data.Char (toLower)
import Data.Text (Text)

-- | A source language Lavoisier can parse for skeletons and symbols.
data Lang
  = Rust
  | Python
  | JavaScript
  | TypeScript
  deriving stock (Show, Eq, Ord, Enum, Bounded)

-- | Best-effort detection from a file path's extension (case-insensitive).
langFromPath :: String -> Maybe Lang
langFromPath path = case map toLower ext of
  "rs" -> Just Rust
  "py" -> Just Python
  "pyi" -> Just Python
  "js" -> Just JavaScript
  "jsx" -> Just JavaScript
  "mjs" -> Just JavaScript
  "cjs" -> Just JavaScript
  "ts" -> Just TypeScript
  "tsx" -> Just TypeScript
  "mts" -> Just TypeScript
  "cts" -> Just TypeScript
  _ -> Nothing
  where
    ext = reverse (takeWhile (/= '.') (reverse path))

-- | How to elide bodies and classify nodes for a language.
data LangSpec = LangSpec
  { -- | Definition node kinds whose @body@ field is replaced by 'elision'.
    defKinds :: [Text],
    -- | Placeholder text a body is replaced with (syntactically suggestive, not valid).
    elision :: Text,
    -- | Named-definition node kinds that become nodes in the symbol-dependency graph.
    symbolKinds :: [Text],
    -- | Keep a leading docstring when eliding the rest of a body (Python only).
    keepsDocstring :: Bool,
    -- | Leaf node kinds that count as a /reference/ to a name (real identifiers only, so a
    -- name in a string or comment creates no spurious edge).
    refIdentKinds :: [Text],
    -- | Node kinds that introduce local bindings (parameters, @let@\/variable declarations);
    -- identifiers in their binding position are locals, excluded from references.
    binderKinds :: [Text]
  }
  deriving stock (Show, Eq)

-- | The elision\/symbol\/reference configuration for a language.
langSpec :: Lang -> LangSpec
langSpec = \case
  Rust ->
    LangSpec
      { defKinds = ["function_item"],
        elision = "{ … }",
        symbolKinds =
          [ "function_item",
            "struct_item",
            "enum_item",
            "trait_item",
            "type_item",
            "const_item",
            "static_item"
          ],
        keepsDocstring = False,
        refIdentKinds = ["identifier", "type_identifier"],
        binderKinds = ["parameter", "let_declaration", "closure_parameters"]
      }
  Python ->
    LangSpec
      { defKinds = ["function_definition"],
        elision = "...",
        symbolKinds = ["function_definition", "class_definition"],
        keepsDocstring = True,
        refIdentKinds = ["identifier"],
        binderKinds = ["parameters", "lambda_parameters"]
      }
  JavaScript ->
    LangSpec
      { defKinds = ["function_declaration", "method_definition", "function_expression"],
        elision = "{ … }",
        symbolKinds = ["function_declaration", "method_definition", "class_declaration"],
        keepsDocstring = False,
        refIdentKinds = ["identifier"],
        binderKinds = ["formal_parameters", "variable_declarator"]
      }
  TypeScript ->
    LangSpec
      { defKinds = ["function_declaration", "method_definition", "function_expression"],
        elision = "{ … }",
        symbolKinds =
          [ "function_declaration",
            "method_definition",
            "class_declaration",
            "interface_declaration",
            "type_alias_declaration"
          ],
        keepsDocstring = False,
        refIdentKinds = ["identifier", "type_identifier"],
        binderKinds =
          [ "formal_parameters",
            "variable_declarator",
            "required_parameter",
            "optional_parameter"
          ]
      }
