-- | Dhall configuration file for @lav@ (the Haskell port uses **Dhall**, not the Rust side's TOML).
--
-- A config file is a Dhall record; every field is optional and merged over an all-@None@ defaults
-- record, so a file may set only the fields it cares about (e.g. @{ provider = Some "google", serve
-- = Some 8080 }@). Precedence — an explicit CLI flag always wins over the file, which wins over the
-- built-in default — is applied by the CLI (@applyConfig@ there fills only the options the user left
-- unset). Type-checked by Dhall at load, so a typo or wrong type is a clear error, not silent.
module Lavoisier.Config
  ( FileConfig (..),
    defaultConfig,
    loadConfig,
  )
where

import Data.Map.Strict (Map)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Dhall qualified
import GHC.Generics (Generic)
import Numeric.Natural (Natural)

-- | The parsed config. Field names match the Dhall record keys exactly.
data FileConfig = FileConfig
  { provider :: Maybe Text,
    model :: Maybe Text,
    thinking :: Maybe Text,
    maxTokens :: Maybe Natural,
    maxSteps :: Maybe Natural,
    contextLimit :: Maybe Natural,
    cheapModel :: Maybe Text,
    escalateAfter :: Maybe Natural,
    advisorModel :: Maybe Text,
    budget :: Maybe Natural,
    noProgressLimit :: Maybe Natural,
    verifyCmd :: Maybe Text,
    requireEdit :: Maybe Bool,
    verifyAndFix :: Maybe Bool,
    inLoopVerify :: Maybe Bool,
    summaryModel :: Maybe Text,
    budgetAwareness :: Maybe Bool,
    -- | Path to a persona file layered /above/ the operational system prompt.
    persona :: Maybe Text,
    -- | Replaces the operational system prompt outright (the persona still layers above it).
    system :: Maybe Text,
    serve :: Maybe Natural,
    serveA2a :: Maybe Natural,
    -- | Run as a Zed Agent Client Protocol agent over stdio (see @--acp@). The flag takes precedence.
    acp :: Maybe Bool,
    -- | Launch the interactive inline terminal UI (see @--tui@). The flag takes precedence.
    tui :: Maybe Bool,
    -- | Skip TUI tool-approval prompts (see @--tui-auto-approve@). The flag takes precedence.
    tuiAutoApprove :: Maybe Bool,
    serveSlack :: Maybe Bool,
    serveMatrix :: Maybe Bool,
    -- | Per-room Matrix tool permissions (a room absent from the map is unconstrained).
    matrixRoomTools :: Maybe (Map Text [Text]),
    -- | Per-member Matrix tool permissions (intersected with the room's when both apply).
    matrixUserTools :: Maybe (Map Text [Text]),
    sessionDir :: Maybe Text,
    mcpServers :: Maybe [Text],
    tune :: Maybe Bool,
    tuneBayes :: Maybe Bool,
    tuneState :: Maybe Text,
    legionDebaters :: Maybe [Text],
    legionJudge :: Maybe Text,
    legionRounds :: Maybe Natural,
    lang :: Maybe Text,
    cron :: Maybe [Text],
    cronFile :: Maybe Text,
    cronRetryMax :: Maybe Natural,
    cronRetryWait :: Maybe Natural,
    scheduleRetryMax :: Maybe Natural,
    scheduleRetryWait :: Maybe Natural,
    fallback :: Maybe [Text],
    fallbackCooldown :: Maybe Natural
  }
  deriving stock (Generic, Show, Eq)

instance Dhall.FromDhall FileConfig

-- | The all-unset config (one 'Nothing' per 'FileConfig' field).
defaultConfig :: FileConfig
defaultConfig = FileConfig n n n n n n n n n n n n n n n n n n n n n n n n n n n n n n n n n n n n n n n n n n n n n
  where
    n :: Maybe a
    n = Nothing

-- | Load a Dhall config file, merged over an all-@None@ defaults record so the file may set only the
-- fields it cares about. Throws (a @Dhall@ exception) on a parse or type error.
loadConfig :: FilePath -> IO FileConfig
loadConfig path = do
  userText <- TIO.readFile path
  Dhall.input Dhall.auto (defaultsDhall <> " // (" <> T.strip userText <> ")")

-- | An all-@None@ record of the full schema; the user file is merged over it with @//@.
defaultsDhall :: Text
defaultsDhall =
  T.concat
    [ "{ provider = None Text",
      ", model = None Text",
      ", thinking = None Text",
      ", maxTokens = None Natural",
      ", maxSteps = None Natural",
      ", contextLimit = None Natural",
      ", cheapModel = None Text",
      ", escalateAfter = None Natural",
      ", advisorModel = None Text",
      ", budget = None Natural",
      ", noProgressLimit = None Natural",
      ", verifyCmd = None Text",
      ", requireEdit = None Bool",
      ", verifyAndFix = None Bool",
      ", inLoopVerify = None Bool",
      ", summaryModel = None Text",
      ", budgetAwareness = None Bool",
      ", persona = None Text",
      ", system = None Text",
      ", serve = None Natural",
      ", serveA2a = None Natural",
      ", acp = None Bool",
      ", tui = None Bool",
      ", tuiAutoApprove = None Bool",
      ", serveSlack = None Bool",
      ", serveMatrix = None Bool",
      ", matrixRoomTools = None (List { mapKey : Text, mapValue : List Text })",
      ", matrixUserTools = None (List { mapKey : Text, mapValue : List Text })",
      ", sessionDir = None Text",
      ", mcpServers = None (List Text)",
      ", tune = None Bool",
      ", tuneBayes = None Bool",
      ", tuneState = None Text",
      ", legionDebaters = None (List Text)",
      ", legionJudge = None Text",
      ", legionRounds = None Natural",
      ", lang = None Text",
      ", cron = None (List Text)",
      ", cronFile = None Text",
      ", cronRetryMax = None Natural",
      ", cronRetryWait = None Natural",
      ", scheduleRetryMax = None Natural",
      ", scheduleRetryWait = None Natural",
      ", fallback = None (List Text)",
      ", fallbackCooldown = None Natural }"
    ]
