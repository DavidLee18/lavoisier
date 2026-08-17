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
    serve :: Maybe Natural,
    serveA2a :: Maybe Natural,
    serveAcp :: Maybe Natural,
    serveSlack :: Maybe Bool,
    serveMatrix :: Maybe Bool,
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
    fallback :: Maybe [Text],
    fallbackCooldown :: Maybe Natural
  }
  deriving stock (Generic, Show, Eq)

instance Dhall.FromDhall FileConfig

-- | The all-unset config (one 'Nothing' per 'FileConfig' field).
defaultConfig :: FileConfig
defaultConfig = FileConfig n n n n n n n n n n n n n n n n n n n n n n n n n n n n n
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
      ", serve = None Natural",
      ", serveA2a = None Natural",
      ", serveAcp = None Natural",
      ", serveSlack = None Bool",
      ", serveMatrix = None Bool",
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
      ", fallback = None (List Text)",
      ", fallbackCooldown = None Natural }"
    ]
