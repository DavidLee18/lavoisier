-- | The provider-agnostic request model: the chat request, its messages/content blocks, tool
-- definitions, and the sampling/thinking/tool-choice knobs. Ported from Rust @lvz-protocol@
-- @message.rs@.
--
-- These are /internal/ types: each provider adapter is the only place that maps them onto its wire
-- format (Anthropic blocks, Gemini parts, xAI protobufs), so — unlike 'Lavoisier.Protocol.Event' —
-- they carry no shared JSON encoding here. Sum types with field clashes (content blocks, media
-- sources, server tools) use positional constructors; flat structs use records.
module Lavoisier.Protocol.Message
  ( ThinkingLevel (..),
    ToolChoice (..),
    OutputFormat (..),
    Role (..),
    MediaSource (..),
    ContentBlock (..),
    textBlock,
    imageBase64,
    imageUrl,
    SystemPrompt (..),
    Message (..),
    userMessage,
    assistantMessage,
    messageText,
    ToolDef (..),
    BuiltinTool (..),
    McpServer (..),
    ServerTool (..),
    ChatRequest (..),
    chatRequest,
  )
where

import Data.Aeson (Value)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Word (Word32)

-- | Normalised extended-thinking effort, mapped per-provider by each adapter. A cost dial:
-- 'ThinkOff'\/'ThinkLow' cheapest, 'ThinkHigh' the most. 'Ord' matters (the agent dials it down for
-- mechanical archetypes).
data ThinkingLevel = ThinkOff | ThinkLow | ThinkMedium | ThinkHigh
  deriving stock (Eq, Ord, Show, Enum, Bounded)

-- | How the model should choose among the offered tools.
data ToolChoice
  = ChoiceAuto
  | ChoiceRequired
  | ChoiceNone
  | ChoiceTool Text
  deriving stock (Eq, Show)

-- | Constrain the model's output to JSON matching a schema (structured outputs).
newtype OutputFormat = JsonSchema Value
  deriving stock (Eq, Show)

-- | Who authored a message.
data Role = User | Assistant
  deriving stock (Eq, Show)

-- | Where the bytes of an image or document come from.
data MediaSource
  = -- | Inline base64 bytes: media_type, then base64 data.
    SrcBase64 Text Text
  | -- | A URL the provider fetches itself.
    SrcUrl Text
  | -- | A previously-uploaded file referenced by id (provider Files API).
    SrcFile Text
  | -- | Inline plain text (raw, not base64) — for text documents.
    SrcPlainText Text
  deriving stock (Eq, Show)

-- | A unit of message content.
data ContentBlock
  = -- | Plain text, with a cache-breakpoint flag.
    TextBlock Text Bool
  | -- | Extended-thinking text echoed back into history.
    ThinkingBlock Text
  | -- | An image input (vision).
    ImageBlock MediaSource
  | -- | A document input (e.g. PDF): source, then a request-citations flag.
    DocumentBlock MediaSource Bool
  | -- | An assistant tool call: id, name, parsed argument JSON.
    ToolUseBlock Text Text Value
  | -- | The result of a tool call: tool_use_id, content, is_error.
    ToolResultBlock Text Text Bool
  deriving stock (Eq, Show)

-- | An un-cached text block.
textBlock :: Text -> ContentBlock
textBlock t = TextBlock t False

-- | An inline (base64) image block.
imageBase64 :: Text -> Text -> ContentBlock
imageBase64 mediaType dat = ImageBlock (SrcBase64 mediaType dat)

-- | An image block referencing a URL the provider fetches.
imageUrl :: Text -> ContentBlock
imageUrl url = ImageBlock (SrcUrl url)

-- | System prompt with a cache marker (honoured only by caching providers).
data SystemPrompt = SystemPrompt
  { spText :: Text,
    spCache :: Bool
  }
  deriving stock (Eq, Show)

-- | One message: a role plus an ordered list of content blocks.
data Message = Message
  { msgRole :: Role,
    msgContent :: [ContentBlock]
  }
  deriving stock (Eq, Show)

-- | A user message containing a single text block.
userMessage :: Text -> Message
userMessage t = Message User [textBlock t]

-- | An assistant message containing a single text block.
assistantMessage :: Text -> Message
assistantMessage t = Message Assistant [textBlock t]

-- | Concatenate all text\/thinking blocks (ignoring tool blocks) into one string.
messageText :: Message -> Text
messageText m =
  T.concat
    [ t
      | block <- msgContent m,
        t <- case block of
          TextBlock t _ -> [t]
          ThinkingBlock t -> [t]
          _ -> []
    ]

-- | A tool advertised to the model: name, description, JSON-Schema argument shape, and the
-- cache\/strict flags.
data ToolDef = ToolDef
  { tdName :: Text,
    tdDescription :: Text,
    tdSchema :: Value,
    tdCache :: Bool,
    tdStrict :: Bool
  }
  deriving stock (Eq, Show)

-- | Anthropic-defined client tools declared by versioned type (executed client-side).
data BuiltinTool = BTBash | BTTextEditor | BTMemory
  deriving stock (Eq, Show)

-- | A remote MCP server the provider connects to on the model's behalf.
data McpServer = McpServer
  { mcpName :: Text,
    mcpUrl :: Text,
    mcpAuthToken :: Maybe Text
  }
  deriving stock (Eq, Show)

-- | Provider-executed (server-side) tools to offer.
data ServerTool
  = -- | Web search: max_uses, allowed_domains, blocked_domains.
    STWebSearch (Maybe Word32) [Text] [Text]
  | -- | Fetch a specific URL: max_uses.
    STWebFetch (Maybe Word32)
  | -- | Run code in a provider-hosted sandbox.
    STCodeExecution
  | -- | Search X posts (xAI): allowed_handles, blocked_handles, from_date, to_date.
    STXSearch [Text] [Text] (Maybe Text) (Maybe Text)
  | -- | RAG over xAI document collections: collection_ids, limit.
    STCollectionsSearch [Text] (Maybe Word32)
  deriving stock (Eq, Show)

-- | A full chat-completion request in provider-agnostic form.
data ChatRequest = ChatRequest
  { crModel :: Text,
    crSystem :: Maybe SystemPrompt,
    crMessages :: [Message],
    crTools :: [ToolDef],
    crMaxTokens :: Word32,
    crTemperature :: Maybe Double,
    crThinking :: Maybe ThinkingLevel,
    crToolChoice :: Maybe ToolChoice,
    crDisableParallelToolUse :: Bool,
    crTopP :: Maybe Double,
    crTopK :: Maybe Word32,
    crStopSequences :: [Text],
    crOutputFormat :: Maybe OutputFormat,
    crServerTools :: [ServerTool],
    crMcpServers :: [McpServer],
    crBuiltinTools :: [BuiltinTool]
  }
  deriving stock (Eq, Show)

-- | A request with sane defaults: no system prompt, no tools, @max_tokens = 1024@.
chatRequest :: Text -> ChatRequest
chatRequest model =
  ChatRequest
    { crModel = model,
      crSystem = Nothing,
      crMessages = [],
      crTools = [],
      crMaxTokens = 1024,
      crTemperature = Nothing,
      crThinking = Nothing,
      crToolChoice = Nothing,
      crDisableParallelToolUse = False,
      crTopP = Nothing,
      crTopK = Nothing,
      crStopSequences = [],
      crOutputFormat = Nothing,
      crServerTools = [],
      crMcpServers = [],
      crBuiltinTools = []
    }
