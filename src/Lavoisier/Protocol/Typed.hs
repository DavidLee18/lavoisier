{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

-- | A __compile-time__ front door for building requests, for callers who compose a 'ChatRequest' in
-- Haskell source rather than from runtime input.
--
-- "Lavoisier.Protocol.Provider" checks capabilities at the adapter boundary with 'negotiate',
-- because the CLI, the Dhall config and the gateways all build requests from data that does not
-- exist until run time — no type can reject a string typed at a shell. But a @mainWith@ extension
-- (see @CUSTOM_TOOL_INSTRUCTIONS.md@) writes its request out, and there the mistake /is/ visible to
-- the compiler.
--
-- A 'Req' carries the set of capabilities it needs in its type. Every builder that adds a demanding
-- feature widens that set, and 'streamTyped' will not accept a provider whose declared list does not
-- cover it:
--
-- > let req = withImage (SrcUrl "https://…/x.png") (newReq "grok-4")
-- > streamTyped claudeCli req   -- rejected at compile time, naming 'Vision
--
-- This does not replace 'negotiate' and does not weaken it: 'streamTyped' still goes through
-- 'providerStream', which negotiates. The index moves the error earlier for the one population that
-- can benefit; the runtime check stays for everyone else.
module Lavoisier.Protocol.Typed
  ( -- * Requests indexed by what they need
    Req,
    unReq,
    newReq,
    liftReq,

    -- * Builders (each widens the index)
    withMessages,
    withSystem,
    withMaxTokens,
    withTools,
    withThinking,
    withImage,
    withSampling,
    withTopK,
    withStopSequences,
    withOutputFormat,
    withToolChoice,
    withWebSearch,
    withWebFetch,
    withCodeExecution,
    withXSearch,
    withCollectionsSearch,
    withUrlContext,
    withBuiltinTools,
    withMcpServers,

    -- * Providers indexed by what they declare
    TypedProvider,
    untyped,
    attestTyped,
    streamTyped,

    -- * The constraint
    Supports,
  )
where

import Data.Kind (Constraint)
import Data.Text (Text)
import Data.Word (Word32)
import GHC.TypeLits (ErrorMessage (..), TypeError)
import Lavoisier.Domain (ModelId)
import Lavoisier.Protocol.Message
import Lavoisier.Protocol.Provider
  ( Capabilities,
    Capability (..),
    Declares,
    EventStream,
    Provider (..),
    ProviderError,
    declare,
  )

-- --- the constraint ---------------------------------------------------------------------------------

-- | Is @c@ in @cs@?
type family Elem (c :: Capability) (cs :: [Capability]) :: Bool where
  Elem _ '[] = 'False
  Elem c (c ': _) = 'True
  Elem c (_ ': cs) = Elem c cs

-- | @Requires c cs found@ is satisfied when @found@ is 'True', and a readable type error otherwise.
-- Splitting the lookup out means the message can name the capability that is missing rather than
-- dumping the whole list.
type family Requires (c :: Capability) (cs :: [Capability]) (found :: Bool) :: Constraint where
  Requires _ _ 'True = ()
  Requires c cs 'False =
    TypeError
      ( 'Text "This request needs the capability "
          ':<>: 'ShowType c
          ':<>: 'Text ", which the provider does not declare."
          ':$$: 'Text "The provider declares: "
          ':<>: 'ShowType cs
          ':$$: 'Text "Either pick a provider that supports it, or drop the builder that added it."
      )

-- | Every capability in @needs@ is in @caps@. The error names the first one that is not.
type family Supports (needs :: [Capability]) (caps :: [Capability]) :: Constraint where
  Supports '[] _ = ()
  Supports (n ': ns) caps = (Requires n caps (Elem n caps), Supports ns caps)

-- --- requests ---------------------------------------------------------------------------------------

-- | A 'ChatRequest' that has accumulated the capabilities it needs in @needs@. The constructor is
-- hidden: the index can only grow through the builders below, so it cannot be understated.
newtype Req (needs :: [Capability]) = Req ChatRequest

-- | The underlying request. Sound in either direction — the index is a claim about what the request
-- needs, and dropping it only loses information.
unReq :: Req needs -> ChatRequest
unReq (Req r) = r

-- | A request that needs nothing: a model and the defaults.
newReq :: ModelId -> Req '[]
newReq = Req . chatRequest

-- | Adopt a hand-built 'ChatRequest' at a stated index. __Unchecked__ — the index is your claim, and
-- nothing verifies the request does not need more than it says. Prefer 'newReq' plus builders; this
-- exists for wrapping a request that arrived from elsewhere, where the runtime 'negotiate' at the
-- adapter is the real guard.
liftReq :: ChatRequest -> Req needs
liftReq = Req

-- Builders that need nothing --------------------------------------------------------------------

-- | Set the conversation.
withMessages :: [Message] -> Req ns -> Req ns
withMessages ms (Req r) = Req r {crMessages = ms}

-- | Set the system prompt.
withSystem :: SystemPrompt -> Req ns -> Req ns
withSystem sp (Req r) = Req r {crSystem = Just sp}

-- | Set the generated-token ceiling.
withMaxTokens :: Word32 -> Req ns -> Req ns
withMaxTokens n (Req r) = Req r {crMaxTokens = n}

-- | Advertise client-side tools. Needs nothing: every provider that takes tools at all takes these,
-- and @claude-cli@ ignores them by design.
withTools :: [ToolDef] -> Req ns -> Req ns
withTools ts (Req r) = Req r {crTools = ts}

-- Builders that widen the index -----------------------------------------------------------------

-- | Ask for extended thinking. Needs 'ExtendedThinking'.
withThinking :: ThinkingLevel -> Req ns -> Req ('ExtendedThinking ': ns)
withThinking l (Req r) = Req r {crThinking = Just l}

-- | Append an image block to the last message, or start one. Needs 'Vision'.
withImage :: MediaSource -> Req ns -> Req ('Vision ': ns)
withImage src (Req r) = Req r {crMessages = append (crMessages r)}
  where
    append [] = [Message User [ImageBlock src]]
    append ms = init ms <> [(last ms) {msgContent = msgContent (last ms) <> [ImageBlock src]}]

-- | Set @temperature@ and\/or @top_p@. Needs 'Sampling'.
withSampling :: Maybe Double -> Maybe Double -> Req ns -> Req ('Sampling ': ns)
withSampling t p (Req r) = Req r {crTemperature = t, crTopP = p}

-- | Set @top_k@. Needs 'TopK', which is separate from 'Sampling' because xAI has the other two and
-- not this one.
withTopK :: Word32 -> Req ns -> Req ('TopK ': ns)
withTopK k (Req r) = Req r {crTopK = Just k}

-- | Set stop sequences. Needs 'StopSequences'.
withStopSequences :: [Text] -> Req ns -> Req ('StopSequences ': ns)
withStopSequences ss (Req r) = Req r {crStopSequences = ss}

-- | Constrain the response to a JSON schema. Needs 'StructuredOutput'.
withOutputFormat :: OutputFormat -> Req ns -> Req ('StructuredOutput ': ns)
withOutputFormat f (Req r) = Req r {crOutputFormat = Just f}

-- | Steer tool selection. Needs 'ToolChoiceControl'.
withToolChoice :: ToolChoice -> Req ns -> Req ('ToolChoiceControl ': ns)
withToolChoice tc (Req r) = Req r {crToolChoice = Just tc}

-- | Offer provider-run web search. Needs 'WebSearch'.
withWebSearch :: Maybe Word32 -> [Text] -> [Text] -> Req ns -> Req ('WebSearch ': ns)
withWebSearch mu ad bd = addServerTool (STWebSearch mu ad bd)

-- | Offer provider-run URL fetch. Needs 'WebFetch'.
withWebFetch :: Maybe Word32 -> Req ns -> Req ('WebFetch ': ns)
withWebFetch mu = addServerTool (STWebFetch mu)

-- | Offer a provider-hosted code sandbox. Needs 'CodeExecution'.
withCodeExecution :: Req ns -> Req ('CodeExecution ': ns)
withCodeExecution = addServerTool STCodeExecution

-- | Offer X post search. Needs 'XSearch'.
withXSearch :: [Text] -> [Text] -> Maybe Text -> Maybe Text -> Req ns -> Req ('XSearch ': ns)
withXSearch ah bh from to = addServerTool (STXSearch ah bh from to)

-- | Offer RAG over provider-hosted collections. Needs 'CollectionsSearch'.
withCollectionsSearch :: [Text] -> Maybe Word32 -> Req ns -> Req ('CollectionsSearch ': ns)
withCollectionsSearch ids lim = addServerTool (STCollectionsSearch ids lim)

-- | Let the provider read URLs named in the prompt. Needs 'UrlContext'.
withUrlContext :: Req ns -> Req ('UrlContext ': ns)
withUrlContext = addServerTool STUrlContext

-- | Declare Anthropic-defined client builtins. Needs 'ClientBuiltinTools'.
withBuiltinTools :: [BuiltinTool] -> Req ns -> Req ('ClientBuiltinTools ': ns)
withBuiltinTools bs (Req r) = Req r {crBuiltinTools = crBuiltinTools r <> bs}

-- | Attach remote MCP servers. Needs 'RemoteMcp'.
withMcpServers :: [McpServer] -> Req ns -> Req ('RemoteMcp ': ns)
withMcpServers ss (Req r) = Req r {crMcpServers = crMcpServers r <> ss}

addServerTool :: ServerTool -> Req ns -> Req ns'
addServerTool t (Req r) = Req r {crServerTools = crServerTools r <> [t]}

-- --- providers --------------------------------------------------------------------------------------

-- | A 'Provider' whose declared capabilities are recorded in @caps@. The constructor is hidden;
-- 'attestTyped' is the only way in, and it checks the claim.
newtype TypedProvider (caps :: [Capability]) = TypedProvider Provider

-- | Forget the index and get the ordinary provider back.
untyped :: TypedProvider caps -> Provider
untyped (TypedProvider p) = p

-- | Attach a type-level capability list to a provider, __checking it against what the provider
-- actually declares__. 'Nothing' when they disagree, so a wrong claim fails once at construction
-- instead of licensing bad requests forever after.
--
-- > attestTyped @AnthropicCaps (anthropicProvider cfg)
attestTyped :: forall caps. (Declares caps) => Provider -> Maybe (TypedProvider caps)
attestTyped p
  | declared == providerCapabilities p = Just (TypedProvider p)
  | otherwise = Nothing
  where
    declared = declare @caps :: Capabilities

-- | Stream a typed request on a typed provider. The 'Supports' constraint is discharged at compile
-- time; the adapter still negotiates at run time, which is what catches anything 'liftReq' let
-- through.
streamTyped ::
  (Supports needs caps) =>
  TypedProvider caps ->
  Req needs ->
  IO (Either ProviderError EventStream)
streamTyped (TypedProvider p) (Req r) = providerStream p r
