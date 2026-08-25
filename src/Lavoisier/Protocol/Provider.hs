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
    serverSideTools,
    vision,
    Negotiated,
    negotiatedRequest,
    negotiate,
    withNegotiated,
    ProviderError (..),
    providerErrorText,
    EventStream,
    Provider (..),
  )
where

import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Word (Word64)
import Lavoisier.Protocol.Event (Event (..))
import Lavoisier.Protocol.Message
  ( BuiltinTool (..),
    ChatRequest (..),
    ContentBlock (..),
    Message (..),
    ServerTool (..),
    ThinkingLevel (..),
  )
import Lavoisier.Protocol.Stream (Producer, prepend)

-- | An optional feature a provider may support. The agent conditions behaviour on these — e.g. it
-- only attaches cache markers when 'promptCaching' holds.
data Capability
  = PromptCaching
  | ExtendedThinking
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
promptCaching, extendedThinking, serverSideTools, vision :: Capabilities -> Bool
promptCaching = supports PromptCaching
extendedThinking = supports ExtendedThinking
serverSideTools = supports ServerSideTools
vision = supports Vision

-- --- capability negotiation -----------------------------------------------------------------------

-- | A 'ChatRequest' that has been checked against a provider declaring exactly @caps@, and adjusted
-- where it could be. The constructor is __hidden__: 'negotiate' is the only way to obtain one, so a
-- value of this type /is/ the evidence that the check ran. An adapter whose builders take
-- @'Negotiated' caps@ cannot skip it.
--
-- The index is the provider\'s declared capability list — the same promoted list passed to
-- 'declare'. Adapters should name it once as a type synonym and use it for both, so the declaration
-- and the check cannot drift apart.
newtype Negotiated (caps :: [Capability]) = Negotiated ChatRequest

-- | Unwrap a negotiated request. Deliberately the only accessor.
negotiatedRequest :: Negotiated caps -> ChatRequest
negotiatedRequest (Negotiated req) = req

-- | Check a request against the capabilities @caps@ and return any notices alongside either a
-- refusal or the adjusted request.
--
-- The two kinds of capability fail in __opposite__ directions, deliberately:
--
--   * __Caller knobs__ — the user asked for something optional ('ExtendedThinking'). These
--     __degrade__ and emit a notice. Killing the turn would be worse than not thinking, and the
--     fallback chain applies one request across several providers. Staying silent is what the tree
--     did before, and it billed the user for a feature they did not get.
--
--   * __Transcript content__ — the messages already carry bytes the provider must accept
--     ('Vision', 'ServerSideTools'). These __refuse__ with 'PUnsupported'. Dropping an image
--     silently makes the model answer about something it never saw, which looks like success.
--
-- Notices are returned even alongside a refusal; the caller may drop them in that case, since a
-- refused turn has no event stream to carry them.
negotiate ::
  forall caps.
  (Declares caps) =>
  ChatRequest ->
  ([Text], Either ProviderError (Negotiated caps))
negotiate req = (notices, outcome)
  where
    caps = declare @caps

    -- Caller knobs: degrade.
    wantsThinking = case crThinking req of
      Just lvl | lvl /= ThinkOff -> True
      _ -> False
    dropThinking = wantsThinking && not (extendedThinking caps)

    notices =
      [ "extended thinking was requested but this provider does not support it; continuing without it"
      | dropThinking
      ]

    adjusted
      | dropThinking = req {crThinking = Nothing}
      | otherwise = req

    -- Transcript content: refuse.
    hasImage = any (any isImage . msgContent) (crMessages req)
    isImage = \case
      ImageBlock _ -> True
      _ -> False

    offeredServerTools =
      map serverToolName (crServerTools req) <> map builtinToolName (crBuiltinTools req)

    outcome
      | hasImage && not (vision caps) =
          Left (PUnsupported "the request contains an image block but this provider does not support vision")
      | (t : _) <- offeredServerTools,
        not (serverSideTools caps) =
          Left (PUnsupported ("server-side tool `" <> t <> "` was offered but this provider does not support server-side tools"))
      | otherwise = Right (Negotiated adjusted)

-- | The adapter-facing wrapper: negotiate, then run the send with the checked request, prefixing any
-- notices onto the front of the returned stream as 'Notice' events. An adapter\'s @providerStream@ is
-- this call and nothing else, so the check cannot be forgotten and the notices cannot be dropped.
withNegotiated ::
  forall caps.
  (Declares caps) =>
  ChatRequest ->
  (Negotiated caps -> IO (Either ProviderError EventStream)) ->
  IO (Either ProviderError EventStream)
withNegotiated req send = case negotiate @caps req of
  (_, Left e) -> pure (Left e)
  (notices, Right nreq) ->
    send nreq >>= \case
      Left e -> pure (Left e)
      Right st -> Right <$> prepend [Right (Notice n) | n <- notices] st

-- | Name a 'ServerTool' for use in a refusal message.
serverToolName :: ServerTool -> Text
serverToolName = \case
  STWebSearch {} -> "web_search"
  STWebFetch {} -> "web_fetch"
  STCodeExecution -> "code_execution"
  STXSearch {} -> "x_search"
  STCollectionsSearch {} -> "collections_search"

-- | Name a 'BuiltinTool' for use in a refusal message.
builtinToolName :: BuiltinTool -> Text
builtinToolName = \case
  BTBash -> "bash"
  BTTextEditor -> "text_editor"
  BTMemory -> "memory"

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

-- | Render a 'ProviderError' as a one-line human message, for gateways and batch paths that carry
-- their own error type and only have a 'Text' to put it in.
providerErrorText :: ProviderError -> Text
providerErrorText = \case
  PTransport t -> "transport error: " <> t
  PApi code t -> "api error " <> tshow code <> ": " <> t
  PDecode t -> "decode error: " <> t
  PCancelled -> "cancelled"
  PUnsupported t -> t
  PConfig t -> "configuration error: " <> t
  where
    tshow :: (Show a) => a -> Text
    tshow = T.pack . show

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
