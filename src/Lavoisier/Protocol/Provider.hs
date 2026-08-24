{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds #-}

-- | The 'Provider' contract: stream a chat turn as normalised 'Event's, declare 'Capabilities', and
-- optionally count tokens. Ported from Rust @lvz-protocol@ @provider.rs@.
--
-- Rust's @Arc<dyn Provider>@ becomes a **record of functions** ('Provider') held as a first-class
-- value — the idiomatic Haskell equivalent of a trait object. Each adapter (Anthropic, xAI, Google,
-- claude-cli) constructs one.
module Lavoisier.Protocol.Provider
  ( Capability (..),
    Capabilities,
    Declares,
    declare,
    capabilitySet,
    supports,
    allCapabilities,
    noCapabilities,
    promptCaching,
    extendedThinking,
    parallelToolUse,
    serverSideTools,
    vision,
    ProviderError (..),
    EventStream,
    Provider (..),
  )
where

import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Word (Word64)
import Lavoisier.Protocol.Event (Event)
import Lavoisier.Protocol.Message (ChatRequest)
import Lavoisier.Protocol.Stream (Producer)

-- | An optional feature a provider may support. The agent conditions behaviour on these — e.g. it
-- only attaches cache markers when 'promptCaching' holds.
data Capability
  = PromptCaching
  | ExtendedThinking
  | ParallelToolUse
  | ServerSideTools
  | Vision
  deriving stock (Eq, Ord, Show, Enum, Bounded)

-- | What a provider supports. A /set/ of 'Capability', not a record of 'Bool': the record version
-- was built positionally at every adapter (@Capabilities True True True True True@), so inserting
-- or reordering a field silently re-labelled every provider\'s advertised features, and nothing in
-- the type could catch it. The constructor is hidden — build one with 'declare' or 'capabilitySet'.
newtype Capabilities = Capabilities (Set Capability)
  deriving stock (Eq, Show)

-- | Declare capabilities at the __type level__, so the list is part of the adapter\'s signature and
-- the value can only be derived from it:
--
-- > providerCapabilities = declare @'[ 'PromptCaching, 'ExtendedThinking, 'Vision]
--
-- There is no positional argument left to get wrong, and an unknown name is a type error naming
-- the 'Capability' promoted constructor.
class Declares (cs :: [Capability]) where
  -- | The value-level set for the declared type-level list.
  declare :: Capabilities

instance Declares '[] where
  declare = Capabilities Set.empty

instance (KnownCapability c, Declares cs) => Declares (c ': cs) where
  declare = insertCap (capabilityVal @c) (declare @cs)

-- | Reflect one promoted 'Capability' constructor down to its value.
class KnownCapability (c :: Capability) where
  capabilityVal :: Capability

instance KnownCapability 'PromptCaching where capabilityVal = PromptCaching

instance KnownCapability 'ExtendedThinking where capabilityVal = ExtendedThinking

instance KnownCapability 'ParallelToolUse where capabilityVal = ParallelToolUse

instance KnownCapability 'ServerSideTools where capabilityVal = ServerSideTools

instance KnownCapability 'Vision where capabilityVal = Vision

insertCap :: Capability -> Capabilities -> Capabilities
insertCap c (Capabilities s) = Capabilities (Set.insert c s)

-- | Build capabilities from a value-level list (for tests and dynamic sources).
capabilitySet :: [Capability] -> Capabilities
capabilitySet = Capabilities . Set.fromList

-- | Does the provider support this feature?
supports :: Capability -> Capabilities -> Bool
supports c (Capabilities s) = Set.member c s

-- | No optional features (Rust @Capabilities::default()@).
noCapabilities :: Capabilities
noCapabilities = Capabilities Set.empty

-- | Every feature — derived from 'Bounded', so a new 'Capability' joins it automatically.
allCapabilities :: Capabilities
allCapabilities = Capabilities (Set.fromList [minBound .. maxBound])

-- | Named predicates, kept so call sites read as before.
promptCaching, extendedThinking, parallelToolUse, serverSideTools, vision :: Capabilities -> Bool
promptCaching = supports PromptCaching
extendedThinking = supports ExtendedThinking
parallelToolUse = supports ParallelToolUse
serverSideTools = supports ServerSideTools
vision = supports Vision

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
