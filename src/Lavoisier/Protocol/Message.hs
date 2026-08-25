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

import Data.Aeson
  ( FromJSON (..),
    ToJSON (..),
    Value,
    object,
    withObject,
    withText,
    (.!=),
    (.:),
    (.:?),
    (.=),
  )
import Data.Aeson.Types (Parser)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Word (Word32)
import Lavoisier.Domain (ModelId (..))

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
  | -- | Let the provider fetch and read URLs named in the prompt (Gemini @url_context@).
    STUrlContext
  deriving stock (Eq, Show)

-- | A full chat-completion request in provider-agnostic form.
data ChatRequest = ChatRequest
  { crModel :: ModelId,
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
chatRequest :: ModelId -> ChatRequest
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

-- --- JSON for the transcript types (Role, MediaSource, ContentBlock, Message) --------------------
--
-- Used to persist a session transcript (see "Lavoisier.Memory"). The tags reproduce the Rust
-- @lvz-protocol@ serde shapes: @Role@ snake_case; @ContentBlock@ tagged @type@; @MediaSource@ tagged
-- @kind@. The boolean flags are always emitted here (Rust skips them when false, but reads them
-- either way; our decoder defaults a missing flag to @False@).

instance ToJSON ThinkingLevel where
  toJSON = \case
    ThinkOff -> "off"
    ThinkLow -> "low"
    ThinkMedium -> "medium"
    ThinkHigh -> "high"

instance FromJSON ThinkingLevel where
  parseJSON = withText "ThinkingLevel" $ \case
    "off" -> pure ThinkOff
    "low" -> pure ThinkLow
    "medium" -> pure ThinkMedium
    "high" -> pure ThinkHigh
    t -> fail ("unknown thinking level: " <> show t)

instance ToJSON Role where
  toJSON User = "user"
  toJSON Assistant = "assistant"

instance FromJSON Role where
  parseJSON = withText "Role" $ \case
    "user" -> pure User
    "assistant" -> pure Assistant
    t -> fail ("unknown role: " <> show t)

instance ToJSON MediaSource where
  toJSON = \case
    SrcBase64 mt d -> object ["kind" .= t "base64", "media_type" .= mt, "data" .= d]
    SrcUrl u -> object ["kind" .= t "url", "url" .= u]
    SrcFile f -> object ["kind" .= t "file", "file_id" .= f]
    SrcPlainText txt -> object ["kind" .= t "plain_text", "text" .= txt]
    where
      t = id :: Text -> Text

instance FromJSON MediaSource where
  parseJSON = withObject "MediaSource" $ \o -> do
    kind <- o .: "kind" :: Parser Text
    case kind of
      "base64" -> SrcBase64 <$> o .: "media_type" <*> o .: "data"
      "url" -> SrcUrl <$> o .: "url"
      "file" -> SrcFile <$> o .: "file_id"
      "plain_text" -> SrcPlainText <$> o .: "text"
      _ -> fail ("unknown media kind: " <> show kind)

instance ToJSON ContentBlock where
  toJSON = \case
    TextBlock txt c -> object ["type" .= t "text", "text" .= txt, "cache" .= c]
    ThinkingBlock txt -> object ["type" .= t "thinking", "text" .= txt]
    ImageBlock src -> object ["type" .= t "image", "source" .= src]
    DocumentBlock src cit -> object ["type" .= t "document", "source" .= src, "citations" .= cit]
    ToolUseBlock i n inp -> object ["type" .= t "tool_use", "id" .= i, "name" .= n, "input" .= inp]
    ToolResultBlock tuid c e ->
      object ["type" .= t "tool_result", "tool_use_id" .= tuid, "content" .= c, "is_error" .= e]
    where
      t = id :: Text -> Text

instance FromJSON ContentBlock where
  parseJSON = withObject "ContentBlock" $ \o -> do
    ty <- o .: "type" :: Parser Text
    case ty of
      "text" -> TextBlock <$> o .: "text" <*> o .:? "cache" .!= False
      "thinking" -> ThinkingBlock <$> o .: "text"
      "image" -> ImageBlock <$> o .: "source"
      "document" -> DocumentBlock <$> o .: "source" <*> o .:? "citations" .!= False
      "tool_use" -> ToolUseBlock <$> o .: "id" <*> o .: "name" <*> o .: "input"
      "tool_result" ->
        ToolResultBlock <$> o .: "tool_use_id" <*> o .: "content" <*> o .:? "is_error" .!= False
      _ -> fail ("unknown content type: " <> show ty)

instance ToJSON Message where
  toJSON (Message r c) = object ["role" .= r, "content" .= c]

instance FromJSON Message where
  parseJSON = withObject "Message" $ \o -> Message <$> o .: "role" <*> o .: "content"
