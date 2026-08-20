-- | The 'Provider' contract: stream a chat turn as normalised 'Event's, declare 'Capabilities', and
-- optionally count tokens. Ported from Rust @lvz-protocol@ @provider.rs@.
--
-- Rust's @Arc<dyn Provider>@ becomes a **record of functions** ('Provider') held as a first-class
-- value — the idiomatic Haskell equivalent of a trait object. Each adapter (Anthropic, xAI, Google,
-- claude-cli) constructs one.
module Lavoisier.Protocol.Provider
  ( Capabilities (..),
    noCapabilities,
    ProviderError (..),
    EventStream,
    Provider (..),
  )
where

import Data.Text (Text)
import Data.Word (Word64)
import Lavoisier.Protocol.Event (Event)
import Lavoisier.Protocol.Message (ChatRequest)
import Lavoisier.Protocol.Stream (Producer)

-- | Optional features a provider may support. The agent conditions behaviour on these — e.g. it
-- only attaches cache markers when 'promptCaching' is true.
data Capabilities = Capabilities
  { promptCaching :: Bool,
    extendedThinking :: Bool,
    parallelToolUse :: Bool,
    serverSideTools :: Bool,
    vision :: Bool
  }
  deriving stock (Eq, Show)

-- | No optional features (Rust @Capabilities::default()@).
noCapabilities :: Capabilities
noCapabilities = Capabilities False False False False False

-- | Errors surfaced by a provider. Adapters map their transport\/API failures onto these.
data ProviderError
  = -- | Network \/ transport-level failure (connection, TLS, timeout).
    PTransport Text
  | -- | The API returned a non-success status with a message (status, message).
    PApi Int Text
  | -- | A response\/frame could not be decoded into the expected shape.
    PDecode Text
  | -- | The caller cancelled mid-stream.
    PCancelled
  | -- | The request used a feature the provider does not advertise.
    PUnsupported Text
  | -- | Configuration problem (missing API key, bad base URL).
    PConfig Text
  deriving stock (Eq, Show)

-- | A streamed turn: a pull stream of events, each of which may be an error.
type EventStream = Producer (Either ProviderError Event)

-- | A provider, as a record of functions (the @Arc\<dyn Provider\>@ analogue).
data Provider = Provider
  { -- | Stream a chat turn as normalised events.
    providerStream :: ChatRequest -> IO (Either ProviderError EventStream),
    -- | Declare optional features so the agent can negotiate\/degrade gracefully.
    providerCapabilities :: Capabilities,
    -- | Count input tokens using the provider's native counter, or 'Nothing' if it has none.
    providerCountTokens :: ChatRequest -> IO (Either ProviderError (Maybe Word64))
  }
