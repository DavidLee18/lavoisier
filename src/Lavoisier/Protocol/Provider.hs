{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds #-}

{- | The 'Provider' contract: stream a chat turn as normalised 'Event's, declare 'Capabilities', and
optionally count tokens. Ported from Rust @lvz-protocol@ @provider.rs@.

Rust's @Arc<dyn Provider>@ becomes a **record of functions** ('Provider') held as a first-class
value — the idiomatic Haskell equivalent of a trait object. Each adapter (Anthropic, xAI, Google,
claude-cli) constructs one.
-}
module Lavoisier.Protocol.Provider (
    Capability (..),
    Capabilities,
    Declares,
    declare,
    capabilitySet,
    supports,
    allCapabilities,
    noCapabilities,
    promptCaching,
    extendedThinking,
    vision,
    serverToolCapability,
    builtinToolCapability,
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

import Data.Maybe (isJust, listToMaybe)
import Data.Set (Set)
import Data.Text (Text)
import Data.Word (Word64)

import Data.Set qualified as Set
import Data.Text qualified as T

import Lavoisier.Protocol.Event (Event (..))
import Lavoisier.Protocol.Message (
    BuiltinTool (..),
    ChatRequest (..),
    ContentBlock (..),
    Message (..),
    ServerTool (..),
    ThinkingLevel (..),
 )
import Lavoisier.Protocol.Stream (Producer, prepend)

{- | An optional feature a provider may support.

Server-side tools are enumerated __one capability per tool__, not as a single @ServerSideTools@
category. The category flag was wrong: the providers' tool sets are genuinely disjoint (Anthropic
web search\/fetch\/code execution + its own client builtins + remote MCP; Gemini search + code
execution; xAI search + X search + collections), so one flag let a tool the adapter cannot map
pass the check and be dropped in silence — the failure 'negotiate' exists to remove. Each adapter
declares exactly the tools it maps.
-}
data Capability
    = PromptCaching
    | ExtendedThinking
    | Vision
    | -- | Provider-run web search ('STWebSearch'; Gemini\'s Google Search grounding).
      WebSearch
    | -- | Provider-run fetch of a named URL ('STWebFetch').
      WebFetch
    | -- | Provider-hosted code sandbox ('STCodeExecution').
      CodeExecution
    | -- | Search of X posts ('STXSearch', xAI only).
      XSearch
    | -- | RAG over provider-hosted document collections ('STCollectionsSearch', xAI only).
      CollectionsSearch
    | -- | Provider-side fetch of URLs named in the prompt ('STUrlContext', Gemini only).
      UrlContext
    | -- | Anthropic-defined client tools declared by versioned type ('BuiltinTool').
      ClientBuiltinTools
    | -- | Remote MCP servers the provider connects to on the model\'s behalf ('crMcpServers').
      RemoteMcp
    | -- | @temperature@ and @top_p@ are honoured ('crTemperature', 'crTopP').
      Sampling
    | {- | @top_k@ is honoured ('crTopK'). Separate from 'Sampling' because xAI takes the other two
      and not this one.
      -}
      TopK
    | -- | Caller-supplied stop sequences are honoured ('crStopSequences').
      StopSequences
    | -- | A response JSON schema is honoured ('crOutputFormat').
      StructuredOutput
    | -- | The caller can steer tool selection ('crToolChoice').
      ToolChoiceControl
    deriving stock (Bounded, Enum, Eq, Ord, Show)

{- | What a provider supports. A /set/ of 'Capability', not a record of 'Bool': the record version
was built positionally at every adapter (@Capabilities True True True True True@), so inserting
or reordering a field silently re-labelled every provider\'s advertised features, and nothing in
the type could catch it. The constructor is hidden — build one with 'declare' or 'capabilitySet'.
-}
newtype Capabilities = Capabilities (Set Capability)
    deriving stock (Eq, Show)

{- | Declare capabilities at the __type level__, so the list is part of the adapter\'s signature and
the value can only be derived from it:

> providerCapabilities = declare @'[ 'PromptCaching, 'ExtendedThinking, 'Vision]

There is no positional argument left to get wrong, and an unknown name is a type error naming
the 'Capability' promoted constructor.
-}
class Declares (cs ∷ [Capability]) where
    -- | The value-level set for the declared type-level list.
    declare ∷ Capabilities

instance Declares '[] where
    declare = Capabilities Set.empty

instance (Declares cs, KnownCapability c) ⇒ Declares (c ': cs) where
    declare = insertCap (capabilityVal @c) (declare @cs)

-- | Reflect one promoted 'Capability' constructor down to its value.
class KnownCapability (c ∷ Capability) where
    capabilityVal ∷ Capability

instance KnownCapability 'PromptCaching where capabilityVal = PromptCaching

instance KnownCapability 'ExtendedThinking where capabilityVal = ExtendedThinking

instance KnownCapability 'Vision where capabilityVal = Vision

instance KnownCapability 'WebSearch where capabilityVal = WebSearch

instance KnownCapability 'WebFetch where capabilityVal = WebFetch

instance KnownCapability 'CodeExecution where capabilityVal = CodeExecution

instance KnownCapability 'XSearch where capabilityVal = XSearch

instance KnownCapability 'CollectionsSearch where capabilityVal = CollectionsSearch

instance KnownCapability 'ClientBuiltinTools where capabilityVal = ClientBuiltinTools

instance KnownCapability 'RemoteMcp where capabilityVal = RemoteMcp

instance KnownCapability 'UrlContext where capabilityVal = UrlContext

instance KnownCapability 'Sampling where capabilityVal = Sampling

instance KnownCapability 'TopK where capabilityVal = TopK

instance KnownCapability 'StopSequences where capabilityVal = StopSequences

instance KnownCapability 'StructuredOutput where capabilityVal = StructuredOutput

instance KnownCapability 'ToolChoiceControl where capabilityVal = ToolChoiceControl

insertCap ∷ Capability → Capabilities → Capabilities
insertCap c (Capabilities s) = Capabilities (Set.insert c s)

-- | Build capabilities from a value-level list (for tests and dynamic sources).
capabilitySet ∷ [Capability] → Capabilities
capabilitySet = Capabilities . Set.fromList

-- | Does the provider support this feature?
supports ∷ Capability → Capabilities → Bool
supports c (Capabilities s) = Set.member c s

-- | No optional features (Rust @Capabilities::default()@).
noCapabilities ∷ Capabilities
noCapabilities = Capabilities Set.empty

-- | Every feature — derived from 'Bounded', so a new 'Capability' joins it automatically.
allCapabilities ∷ Capabilities
allCapabilities = Capabilities (Set.fromList [minBound .. maxBound])

-- | Named predicates, kept so call sites read as before.
promptCaching, extendedThinking, vision ∷ Capabilities → Bool
promptCaching = supports PromptCaching
extendedThinking = supports ExtendedThinking
vision = supports Vision

-- | The capability a given server-side tool requires.
serverToolCapability ∷ ServerTool → Capability
serverToolCapability = \case
    STWebSearch {} → WebSearch
    STWebFetch {} → WebFetch
    STCodeExecution → CodeExecution
    STXSearch {} → XSearch
    STCollectionsSearch {} → CollectionsSearch
    STUrlContext → UrlContext

{- | The capability a given client builtin tool requires. All three are Anthropic-defined, so they
share one capability rather than getting three of their own.
-}
builtinToolCapability ∷ BuiltinTool → Capability
builtinToolCapability _ = ClientBuiltinTools

-- --- capability negotiation -----------------------------------------------------------------------

{- | A 'ChatRequest' that has been checked against a provider declaring exactly @caps@, and adjusted
where it could be. The constructor is __hidden__: 'negotiate' is the only way to obtain one, so a
value of this type /is/ the evidence that the check ran. An adapter whose builders take
@'Negotiated' caps@ cannot skip it.

The index is the provider\'s declared capability list — the same promoted list passed to
'declare'. Adapters should name it once as a type synonym and use it for both, so the declaration
and the check cannot drift apart.
-}
newtype Negotiated (caps ∷ [Capability]) = Negotiated ChatRequest

-- | Unwrap a negotiated request. Deliberately the only accessor.
negotiatedRequest ∷ Negotiated caps → ChatRequest
negotiatedRequest (Negotiated req) = req

{- | Check a request against the capabilities @caps@ and return any notices alongside either a
refusal or the adjusted request.

The two kinds of capability fail in __opposite__ directions, deliberately:

  * __Caller knobs__ — the user asked for something optional ('ExtendedThinking'). These
    __degrade__ and emit a notice. Killing the turn would be worse than not thinking, and the
    fallback chain applies one request across several providers. Staying silent is what the tree
    did before, and it billed the user for a feature they did not get.

  * __Transcript content and requested tools__ — the messages already carry bytes the provider
    must accept ('Vision'), or the caller asked for a specific provider-run tool. These
    __refuse__ with 'PUnsupported'. Dropping an image silently makes the model answer about
    something it never saw; dropping a tool leaves the model unable to do what it was set up to
    do. Both look like success.

Notices are returned even alongside a refusal; the caller may drop them in that case, since a
refused turn has no event stream to carry them.
-}
negotiate ∷
    ∀ caps.
    Declares caps ⇒
    ChatRequest →
    ([Text], Either ProviderError (Negotiated caps))
negotiate req = (notices, outcome)
    where
        caps = declare @caps

        -- Caller knobs: degrade, one notice each. Each entry is (was it asked for, which capability,
        -- what to say, how to clear it) — adding a knob means adding a row, not a new code path.
        wantsThinking = case crThinking req of
            Just lvl | lvl /= ThinkOff → True
            _ → False

        knobs ∷ [(Bool, Capability, Text, ChatRequest → ChatRequest)]
        knobs =
            [
                ( wantsThinking
                , ExtendedThinking
                , "extended thinking"
                , \r → r {crThinking = Nothing}
                )
            ,
                ( isJust (crTemperature req) || isJust (crTopP req)
                , Sampling
                , "temperature/top_p"
                , \r → r {crTemperature = Nothing, crTopP = Nothing}
                )
            ,
                ( isJust (crTopK req)
                , TopK
                , "top_k"
                , \r → r {crTopK = Nothing}
                )
            ,
                ( not (null (crStopSequences req))
                , StopSequences
                , "stop sequences"
                , \r → r {crStopSequences = []}
                )
            ,
                ( isJust (crOutputFormat req)
                , StructuredOutput
                , "a structured-output schema"
                , \r → r {crOutputFormat = Nothing}
                )
            ,
                ( isJust (crToolChoice req)
                , ToolChoiceControl
                , "tool choice"
                , \r → r {crToolChoice = Nothing}
                )
            ]

        dropped = [(what, clear) | (asked, c, what, clear) ← knobs, asked, not (supports c caps)]

        notices =
            [ what <> " was requested but this provider does not support it; continuing without it"
            | (what, _) ← dropped
            ]

        adjusted = foldl' (\r (_, clear) → clear r) req dropped

        -- Transcript content: refuse.
        hasImage = any (any isImage . msgContent) (crMessages req)
        isImage = \case
            ImageBlock _ → True
            _ → False

        -- Each tool is checked against its __own__ capability, because the providers' tool sets are
        -- disjoint. A single category flag would let e.g. an xAI-only tool through to Anthropic, whose
        -- mapper then silently drops it.
        unsupportedTool =
            listToMaybe $
                [ (serverToolName t, c)
                | t ← crServerTools req
                , let c = serverToolCapability t
                , not (supports c caps)
                ]
                    <> [ (builtinToolName b, c)
                       | b ← crBuiltinTools req
                       , let c = builtinToolCapability b
                       , not (supports c caps)
                       ]

        outcome
            | hasImage && not (vision caps) =
                Left (PUnsupported "the request contains an image block but this provider does not support vision")
            | Just (name, c) ← unsupportedTool =
                Left (PUnsupported ("tool `" <> name <> "` was offered but this provider does not support it (" <> tshowCap c <> ")"))
            | not (null (crMcpServers req))
            , not (supports RemoteMcp caps) =
                Left (PUnsupported "remote MCP servers were offered but this provider does not connect to them")
            | otherwise = Right (Negotiated adjusted)

        tshowCap = T.pack . show

{- | The adapter-facing wrapper: negotiate, then run the send with the checked request, prefixing any
notices onto the front of the returned stream as 'Notice' events. An adapter\'s @providerStream@ is
this call and nothing else, so the check cannot be forgotten and the notices cannot be dropped.
-}
withNegotiated ∷
    ∀ caps.
    Declares caps ⇒
    ChatRequest →
    (Negotiated caps → IO (Either ProviderError EventStream)) →
    IO (Either ProviderError EventStream)
withNegotiated req send = case negotiate @caps req of
    (_, Left e) → pure (Left e)
    (notices, Right nreq) →
        send nreq >>= \case
            Left e → pure (Left e)
            Right st → Right <$> prepend [Right (Notice n) | n ← notices] st

-- | Name a 'ServerTool' for use in a refusal message.
serverToolName ∷ ServerTool → Text
serverToolName = \case
    STWebSearch {} → "web_search"
    STWebFetch {} → "web_fetch"
    STCodeExecution → "code_execution"
    STXSearch {} → "x_search"
    STCollectionsSearch {} → "collections_search"
    STUrlContext → "url_context"

-- | Name a 'BuiltinTool' for use in a refusal message.
builtinToolName ∷ BuiltinTool → Text
builtinToolName = \case
    BTBash → "bash"
    BTTextEditor → "text_editor"
    BTMemory → "memory"

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

{- | Render a 'ProviderError' as a one-line human message, for gateways and batch paths that carry
their own error type and only have a 'Text' to put it in.
-}
providerErrorText ∷ ProviderError → Text
providerErrorText = \case
    PTransport t → "transport error: " <> t
    PApi code t → "api error " <> tshow code <> ": " <> t
    PDecode t → "decode error: " <> t
    PCancelled → "cancelled"
    PUnsupported t → t
    PConfig t → "configuration error: " <> t
    where
        tshow ∷ Show a ⇒ a → Text
        tshow = T.pack . show

-- | A streamed turn: a pull stream of events, each of which may be an error.
type EventStream = Producer (Either ProviderError Event)

-- | A provider, as a record of functions (the @Arc\<dyn Provider\>@ analogue).
data Provider = Provider
    { providerStream ∷ ChatRequest → IO (Either ProviderError EventStream)
    -- ^ Stream a chat turn as normalised events.
    , providerCapabilities ∷ Capabilities
    -- ^ Declare optional features so the agent can negotiate\/degrade gracefully.
    , providerCountTokens ∷ ChatRequest → IO (Either ProviderError (Maybe Word64))
    -- ^ Count input tokens using the provider's native counter, or 'Nothing' if it has none.
    }
