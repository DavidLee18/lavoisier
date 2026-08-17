{- This file was auto-generated from xai/api/v1/chat.proto by the proto-lens-protoc program. -}
{-# LANGUAGE ScopedTypeVariables, DataKinds, TypeFamilies, UndecidableInstances, GeneralizedNewtypeDeriving, MultiParamTypeClasses, FlexibleContexts, FlexibleInstances, PatternSynonyms, MagicHash, NoImplicitPrelude, DataKinds, BangPatterns, TypeApplications, OverloadedStrings, DerivingStrategies#-}
{-# OPTIONS_GHC -Wno-unused-imports#-}
{-# OPTIONS_GHC -Wno-duplicate-exports#-}
{-# OPTIONS_GHC -Wno-dodgy-exports#-}
module Proto.Xai.Api.V1.Chat (
        Chat(..), AgentCount(..), AgentCount(),
        AgentCount'UnrecognizedValue, AttachmentSearch(), CodeExecution(),
        CollectionsCitation(), CollectionsSearch(),
        CollectionsSearch'RetrievalMode(..),
        _CollectionsSearch'HybridRetrieval,
        _CollectionsSearch'SemanticRetrieval,
        _CollectionsSearch'KeywordRetrieval, CompactContextRequest(),
        CompactContextResponse(), CompletionMessage(), CompletionOutput(),
        CompletionOutputChunk(), Content(), Content'Content(..),
        _Content'Text, _Content'ImageUrl, _Content'File, DebugOutput(),
        DeleteStoredCompletionRequest(), DeleteStoredCompletionResponse(),
        Delta(), FileContent(), FormatType(..), FormatType(),
        FormatType'UnrecognizedValue, Function(), FunctionCall(),
        GetChatCompletionChunk(), GetChatCompletionResponse(),
        GetCompletionsRequest(), GetDeferredCompletionResponse(),
        GetStoredCompletionRequest(), IncludeOption(..), IncludeOption(),
        IncludeOption'UnrecognizedValue, InlineCitation(),
        InlineCitation'Citation(..), _InlineCitation'WebCitation,
        _InlineCitation'XCitation, _InlineCitation'CollectionsCitation,
        LogProb(), LogProbs(), MCP(), MCP'ExtraHeadersEntry(), Message(),
        MessageRole(..), MessageRole(), MessageRole'UnrecognizedValue,
        NewsSource(), ReasoningEffort(..), ReasoningEffort(),
        ReasoningEffort'UnrecognizedValue, RequestSettings(),
        ResponseFormat(), RssSource(), SearchMode(..), SearchMode(),
        SearchMode'UnrecognizedValue, SearchParameters(), Source(),
        Source'Source(..), _Source'Web, _Source'News, _Source'X,
        _Source'Rss, Tool(), Tool'Tool(..), _Tool'Function,
        _Tool'WebSearch, _Tool'XSearch, _Tool'CodeExecution,
        _Tool'CollectionsSearch, _Tool'Mcp, _Tool'AttachmentSearch,
        ToolCall(), ToolCall'Tool(..), _ToolCall'Function,
        ToolCallStatus(..), ToolCallStatus(),
        ToolCallStatus'UnrecognizedValue, ToolCallType(..), ToolCallType(),
        ToolCallType'UnrecognizedValue, ToolChoice(),
        ToolChoice'ToolChoice(..), _ToolChoice'Mode,
        _ToolChoice'FunctionName, ToolMode(..), ToolMode(),
        ToolMode'UnrecognizedValue, TopLogProb(), WebCitation(),
        WebSearch(), WebSearchUserLocation(), WebSource(), XCitation(),
        XSearch(), XSource()
    ) where
import qualified Data.ProtoLens.Runtime.Control.DeepSeq as Control.DeepSeq
import qualified Data.ProtoLens.Runtime.Data.ProtoLens.Prism as Data.ProtoLens.Prism
import qualified Data.ProtoLens.Runtime.Prelude as Prelude
import qualified Data.ProtoLens.Runtime.Data.Int as Data.Int
import qualified Data.ProtoLens.Runtime.Data.Monoid as Data.Monoid
import qualified Data.ProtoLens.Runtime.Data.Word as Data.Word
import qualified Data.ProtoLens.Runtime.Data.ProtoLens as Data.ProtoLens
import qualified Data.ProtoLens.Runtime.Data.ProtoLens.Encoding.Bytes as Data.ProtoLens.Encoding.Bytes
import qualified Data.ProtoLens.Runtime.Data.ProtoLens.Encoding.Growing as Data.ProtoLens.Encoding.Growing
import qualified Data.ProtoLens.Runtime.Data.ProtoLens.Encoding.Parser.Unsafe as Data.ProtoLens.Encoding.Parser.Unsafe
import qualified Data.ProtoLens.Runtime.Data.ProtoLens.Encoding.Wire as Data.ProtoLens.Encoding.Wire
import qualified Data.ProtoLens.Runtime.Data.ProtoLens.Field as Data.ProtoLens.Field
import qualified Data.ProtoLens.Runtime.Data.ProtoLens.Message.Enum as Data.ProtoLens.Message.Enum
import qualified Data.ProtoLens.Runtime.Data.ProtoLens.Service.Types as Data.ProtoLens.Service.Types
import qualified Data.ProtoLens.Runtime.Lens.Family2 as Lens.Family2
import qualified Data.ProtoLens.Runtime.Lens.Family2.Unchecked as Lens.Family2.Unchecked
import qualified Data.ProtoLens.Runtime.Data.Text as Data.Text
import qualified Data.ProtoLens.Runtime.Data.Map as Data.Map
import qualified Data.ProtoLens.Runtime.Data.ByteString as Data.ByteString
import qualified Data.ProtoLens.Runtime.Data.ByteString.Char8 as Data.ByteString.Char8
import qualified Data.ProtoLens.Runtime.Data.Text.Encoding as Data.Text.Encoding
import qualified Data.ProtoLens.Runtime.Data.Vector as Data.Vector
import qualified Data.ProtoLens.Runtime.Data.Vector.Generic as Data.Vector.Generic
import qualified Data.ProtoLens.Runtime.Data.Vector.Unboxed as Data.Vector.Unboxed
import qualified Data.ProtoLens.Runtime.Text.Read as Text.Read
import qualified Proto.Google.Protobuf.Timestamp
import qualified Proto.Xai.Api.V1.Deferred
import qualified Proto.Xai.Api.V1.Documents
import qualified Proto.Xai.Api.V1.Image
import qualified Proto.Xai.Api.V1.Sample
import qualified Proto.Xai.Api.V1.Usage
newtype AgentCount'UnrecognizedValue
  = AgentCount'UnrecognizedValue Data.Int.Int32
  deriving stock (Prelude.Eq, Prelude.Ord, Prelude.Show)
data AgentCount
  = AGENT_COUNT_UNSPECIFIED |
    AGENT_COUNT_4 |
    AGENT_COUNT_16 |
    AgentCount'Unrecognized !AgentCount'UnrecognizedValue
  deriving stock (Prelude.Show, Prelude.Eq, Prelude.Ord)
instance Data.ProtoLens.MessageEnum AgentCount where
  maybeToEnum 0 = Prelude.Just AGENT_COUNT_UNSPECIFIED
  maybeToEnum 1 = Prelude.Just AGENT_COUNT_4
  maybeToEnum 2 = Prelude.Just AGENT_COUNT_16
  maybeToEnum k
    = Prelude.Just
        (AgentCount'Unrecognized
           (AgentCount'UnrecognizedValue (Prelude.fromIntegral k)))
  showEnum AGENT_COUNT_UNSPECIFIED = "AGENT_COUNT_UNSPECIFIED"
  showEnum AGENT_COUNT_4 = "AGENT_COUNT_4"
  showEnum AGENT_COUNT_16 = "AGENT_COUNT_16"
  showEnum (AgentCount'Unrecognized (AgentCount'UnrecognizedValue k))
    = Prelude.show k
  readEnum k
    | (Prelude.==) k "AGENT_COUNT_UNSPECIFIED"
    = Prelude.Just AGENT_COUNT_UNSPECIFIED
    | (Prelude.==) k "AGENT_COUNT_4" = Prelude.Just AGENT_COUNT_4
    | (Prelude.==) k "AGENT_COUNT_16" = Prelude.Just AGENT_COUNT_16
    | Prelude.otherwise
    = (Prelude.>>=) (Text.Read.readMaybe k) Data.ProtoLens.maybeToEnum
instance Prelude.Bounded AgentCount where
  minBound = AGENT_COUNT_UNSPECIFIED
  maxBound = AGENT_COUNT_16
instance Prelude.Enum AgentCount where
  toEnum k__
    = Prelude.maybe
        (Prelude.error
           ((Prelude.++)
              "toEnum: unknown value for enum AgentCount: " (Prelude.show k__)))
        Prelude.id (Data.ProtoLens.maybeToEnum k__)
  fromEnum AGENT_COUNT_UNSPECIFIED = 0
  fromEnum AGENT_COUNT_4 = 1
  fromEnum AGENT_COUNT_16 = 2
  fromEnum (AgentCount'Unrecognized (AgentCount'UnrecognizedValue k))
    = Prelude.fromIntegral k
  succ AGENT_COUNT_16
    = Prelude.error
        "AgentCount.succ: bad argument AGENT_COUNT_16. This value would be out of bounds."
  succ AGENT_COUNT_UNSPECIFIED = AGENT_COUNT_4
  succ AGENT_COUNT_4 = AGENT_COUNT_16
  succ (AgentCount'Unrecognized _)
    = Prelude.error "AgentCount.succ: bad argument: unrecognized value"
  pred AGENT_COUNT_UNSPECIFIED
    = Prelude.error
        "AgentCount.pred: bad argument AGENT_COUNT_UNSPECIFIED. This value would be out of bounds."
  pred AGENT_COUNT_4 = AGENT_COUNT_UNSPECIFIED
  pred AGENT_COUNT_16 = AGENT_COUNT_4
  pred (AgentCount'Unrecognized _)
    = Prelude.error "AgentCount.pred: bad argument: unrecognized value"
  enumFrom = Data.ProtoLens.Message.Enum.messageEnumFrom
  enumFromTo = Data.ProtoLens.Message.Enum.messageEnumFromTo
  enumFromThen = Data.ProtoLens.Message.Enum.messageEnumFromThen
  enumFromThenTo = Data.ProtoLens.Message.Enum.messageEnumFromThenTo
instance Data.ProtoLens.FieldDefault AgentCount where
  fieldDefault = AGENT_COUNT_UNSPECIFIED
instance Control.DeepSeq.NFData AgentCount where
  rnf x__ = Prelude.seq x__ ()
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Chat_Fields.limit' @:: Lens' AttachmentSearch Data.Int.Int32@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'limit' @:: Lens' AttachmentSearch (Prelude.Maybe Data.Int.Int32)@ -}
data AttachmentSearch
  = AttachmentSearch'_constructor {_AttachmentSearch'limit :: !(Prelude.Maybe Data.Int.Int32),
                                   _AttachmentSearch'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show AttachmentSearch where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField AttachmentSearch "limit" Data.Int.Int32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _AttachmentSearch'limit
           (\ x__ y__ -> x__ {_AttachmentSearch'limit = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField AttachmentSearch "maybe'limit" (Prelude.Maybe Data.Int.Int32) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _AttachmentSearch'limit
           (\ x__ y__ -> x__ {_AttachmentSearch'limit = y__}))
        Prelude.id
instance Data.ProtoLens.Message AttachmentSearch where
  messageName _ = Data.Text.pack "xai_api.AttachmentSearch"
  packedMessageDescriptor _
    = "\n\
      \\DLEAttachmentSearch\DC2\EM\n\
      \\ENQlimit\CAN\STX \SOH(\ENQH\NULR\ENQlimit\136\SOH\SOHB\b\n\
      \\ACK_limit"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        limit__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "limit"
              (Data.ProtoLens.ScalarField Data.ProtoLens.Int32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Int.Int32)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'limit")) ::
              Data.ProtoLens.FieldDescriptor AttachmentSearch
      in
        Data.Map.fromList [(Data.ProtoLens.Tag 2, limit__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _AttachmentSearch'_unknownFields
        (\ x__ y__ -> x__ {_AttachmentSearch'_unknownFields = y__})
  defMessage
    = AttachmentSearch'_constructor
        {_AttachmentSearch'limit = Prelude.Nothing,
         _AttachmentSearch'_unknownFields = []}
  parseMessage
    = let
        loop ::
          AttachmentSearch
          -> Data.ProtoLens.Encoding.Bytes.Parser AttachmentSearch
        loop x
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t) x)
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        16
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "limit"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"limit") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "AttachmentSearch"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (case
                  Lens.Family2.view (Data.ProtoLens.Field.field @"maybe'limit") _x
              of
                Prelude.Nothing -> Data.Monoid.mempty
                (Prelude.Just _v)
                  -> (Data.Monoid.<>)
                       (Data.ProtoLens.Encoding.Bytes.putVarInt 16)
                       ((Prelude..)
                          Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral _v))
             (Data.ProtoLens.Encoding.Wire.buildFieldSet
                (Lens.Family2.view Data.ProtoLens.unknownFields _x))
instance Control.DeepSeq.NFData AttachmentSearch where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_AttachmentSearch'_unknownFields x__)
             (Control.DeepSeq.deepseq (_AttachmentSearch'limit x__) ())
{- | Fields :
      -}
data CodeExecution
  = CodeExecution'_constructor {_CodeExecution'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show CodeExecution where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Message CodeExecution where
  messageName _ = Data.Text.pack "xai_api.CodeExecution"
  packedMessageDescriptor _
    = "\n\
      \\rCodeExecution"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag = let in Data.Map.fromList []
  unknownFields
    = Lens.Family2.Unchecked.lens
        _CodeExecution'_unknownFields
        (\ x__ y__ -> x__ {_CodeExecution'_unknownFields = y__})
  defMessage
    = CodeExecution'_constructor {_CodeExecution'_unknownFields = []}
  parseMessage
    = let
        loop ::
          CodeExecution -> Data.ProtoLens.Encoding.Bytes.Parser CodeExecution
        loop x
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t) x)
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "CodeExecution"
  buildMessage
    = \ _x
        -> Data.ProtoLens.Encoding.Wire.buildFieldSet
             (Lens.Family2.view Data.ProtoLens.unknownFields _x)
instance Control.DeepSeq.NFData CodeExecution where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq (_CodeExecution'_unknownFields x__) ()
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Chat_Fields.fileId' @:: Lens' CollectionsCitation Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.chunkId' @:: Lens' CollectionsCitation Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.chunkContent' @:: Lens' CollectionsCitation Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.score' @:: Lens' CollectionsCitation Prelude.Float@
         * 'Proto.Xai.Api.V1.Chat_Fields.collectionIds' @:: Lens' CollectionsCitation [Data.Text.Text]@
         * 'Proto.Xai.Api.V1.Chat_Fields.vec'collectionIds' @:: Lens' CollectionsCitation (Data.Vector.Vector Data.Text.Text)@ -}
data CollectionsCitation
  = CollectionsCitation'_constructor {_CollectionsCitation'fileId :: !Data.Text.Text,
                                      _CollectionsCitation'chunkId :: !Data.Text.Text,
                                      _CollectionsCitation'chunkContent :: !Data.Text.Text,
                                      _CollectionsCitation'score :: !Prelude.Float,
                                      _CollectionsCitation'collectionIds :: !(Data.Vector.Vector Data.Text.Text),
                                      _CollectionsCitation'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show CollectionsCitation where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField CollectionsCitation "fileId" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CollectionsCitation'fileId
           (\ x__ y__ -> x__ {_CollectionsCitation'fileId = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField CollectionsCitation "chunkId" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CollectionsCitation'chunkId
           (\ x__ y__ -> x__ {_CollectionsCitation'chunkId = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField CollectionsCitation "chunkContent" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CollectionsCitation'chunkContent
           (\ x__ y__ -> x__ {_CollectionsCitation'chunkContent = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField CollectionsCitation "score" Prelude.Float where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CollectionsCitation'score
           (\ x__ y__ -> x__ {_CollectionsCitation'score = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField CollectionsCitation "collectionIds" [Data.Text.Text] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CollectionsCitation'collectionIds
           (\ x__ y__ -> x__ {_CollectionsCitation'collectionIds = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField CollectionsCitation "vec'collectionIds" (Data.Vector.Vector Data.Text.Text) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CollectionsCitation'collectionIds
           (\ x__ y__ -> x__ {_CollectionsCitation'collectionIds = y__}))
        Prelude.id
instance Data.ProtoLens.Message CollectionsCitation where
  messageName _ = Data.Text.pack "xai_api.CollectionsCitation"
  packedMessageDescriptor _
    = "\n\
      \\DC3CollectionsCitation\DC2\ETB\n\
      \\afile_id\CAN\SOH \SOH(\tR\ACKfileId\DC2\EM\n\
      \\bchunk_id\CAN\STX \SOH(\tR\achunkId\DC2#\n\
      \\rchunk_content\CAN\ETX \SOH(\tR\fchunkContent\DC2\DC4\n\
      \\ENQscore\CAN\EOT \SOH(\STXR\ENQscore\DC2%\n\
      \\SOcollection_ids\CAN\ENQ \ETX(\tR\rcollectionIds"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        fileId__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "file_id"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"fileId")) ::
              Data.ProtoLens.FieldDescriptor CollectionsCitation
        chunkId__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "chunk_id"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"chunkId")) ::
              Data.ProtoLens.FieldDescriptor CollectionsCitation
        chunkContent__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "chunk_content"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"chunkContent")) ::
              Data.ProtoLens.FieldDescriptor CollectionsCitation
        score__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "score"
              (Data.ProtoLens.ScalarField Data.ProtoLens.FloatField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Float)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"score")) ::
              Data.ProtoLens.FieldDescriptor CollectionsCitation
        collectionIds__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "collection_ids"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Unpacked
                 (Data.ProtoLens.Field.field @"collectionIds")) ::
              Data.ProtoLens.FieldDescriptor CollectionsCitation
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, fileId__field_descriptor),
           (Data.ProtoLens.Tag 2, chunkId__field_descriptor),
           (Data.ProtoLens.Tag 3, chunkContent__field_descriptor),
           (Data.ProtoLens.Tag 4, score__field_descriptor),
           (Data.ProtoLens.Tag 5, collectionIds__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _CollectionsCitation'_unknownFields
        (\ x__ y__ -> x__ {_CollectionsCitation'_unknownFields = y__})
  defMessage
    = CollectionsCitation'_constructor
        {_CollectionsCitation'fileId = Data.ProtoLens.fieldDefault,
         _CollectionsCitation'chunkId = Data.ProtoLens.fieldDefault,
         _CollectionsCitation'chunkContent = Data.ProtoLens.fieldDefault,
         _CollectionsCitation'score = Data.ProtoLens.fieldDefault,
         _CollectionsCitation'collectionIds = Data.Vector.Generic.empty,
         _CollectionsCitation'_unknownFields = []}
  parseMessage
    = let
        loop ::
          CollectionsCitation
          -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Vector Data.ProtoLens.Encoding.Growing.RealWorld Data.Text.Text
             -> Data.ProtoLens.Encoding.Bytes.Parser CollectionsCitation
        loop x mutable'collectionIds
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do frozen'collectionIds <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                                (Data.ProtoLens.Encoding.Growing.unsafeFreeze
                                                   mutable'collectionIds)
                      (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t)
                           (Lens.Family2.set
                              (Data.ProtoLens.Field.field @"vec'collectionIds")
                              frozen'collectionIds x))
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "file_id"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"fileId") y x)
                                  mutable'collectionIds
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "chunk_id"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"chunkId") y x)
                                  mutable'collectionIds
                        26
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "chunk_content"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"chunkContent") y x)
                                  mutable'collectionIds
                        37
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Data.ProtoLens.Encoding.Bytes.wordToFloat
                                          Data.ProtoLens.Encoding.Bytes.getFixed32)
                                       "score"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"score") y x)
                                  mutable'collectionIds
                        42
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                            Data.ProtoLens.Encoding.Bytes.getText
                                              (Prelude.fromIntegral len))
                                        "collection_ids"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append
                                          mutable'collectionIds y)
                                loop x v
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
                                  mutable'collectionIds
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do mutable'collectionIds <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                         Data.ProtoLens.Encoding.Growing.new
              loop Data.ProtoLens.defMessage mutable'collectionIds)
          "CollectionsCitation"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v = Lens.Family2.view (Data.ProtoLens.Field.field @"fileId") _x
              in
                if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                      ((Prelude..)
                         (\ bs
                            -> (Data.Monoid.<>)
                                 (Data.ProtoLens.Encoding.Bytes.putVarInt
                                    (Prelude.fromIntegral (Data.ByteString.length bs)))
                                 (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                         Data.Text.Encoding.encodeUtf8 _v))
             ((Data.Monoid.<>)
                (let
                   _v = Lens.Family2.view (Data.ProtoLens.Field.field @"chunkId") _x
                 in
                   if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                       Data.Monoid.mempty
                   else
                       (Data.Monoid.<>)
                         (Data.ProtoLens.Encoding.Bytes.putVarInt 18)
                         ((Prelude..)
                            (\ bs
                               -> (Data.Monoid.<>)
                                    (Data.ProtoLens.Encoding.Bytes.putVarInt
                                       (Prelude.fromIntegral (Data.ByteString.length bs)))
                                    (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                            Data.Text.Encoding.encodeUtf8 _v))
                ((Data.Monoid.<>)
                   (let
                      _v
                        = Lens.Family2.view (Data.ProtoLens.Field.field @"chunkContent") _x
                    in
                      if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                          Data.Monoid.mempty
                      else
                          (Data.Monoid.<>)
                            (Data.ProtoLens.Encoding.Bytes.putVarInt 26)
                            ((Prelude..)
                               (\ bs
                                  -> (Data.Monoid.<>)
                                       (Data.ProtoLens.Encoding.Bytes.putVarInt
                                          (Prelude.fromIntegral (Data.ByteString.length bs)))
                                       (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                               Data.Text.Encoding.encodeUtf8 _v))
                   ((Data.Monoid.<>)
                      (let
                         _v = Lens.Family2.view (Data.ProtoLens.Field.field @"score") _x
                       in
                         if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                             Data.Monoid.mempty
                         else
                             (Data.Monoid.<>)
                               (Data.ProtoLens.Encoding.Bytes.putVarInt 37)
                               ((Prelude..)
                                  Data.ProtoLens.Encoding.Bytes.putFixed32
                                  Data.ProtoLens.Encoding.Bytes.floatToWord _v))
                      ((Data.Monoid.<>)
                         (Data.ProtoLens.Encoding.Bytes.foldMapBuilder
                            (\ _v
                               -> (Data.Monoid.<>)
                                    (Data.ProtoLens.Encoding.Bytes.putVarInt 42)
                                    ((Prelude..)
                                       (\ bs
                                          -> (Data.Monoid.<>)
                                               (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                  (Prelude.fromIntegral
                                                     (Data.ByteString.length bs)))
                                               (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                       Data.Text.Encoding.encodeUtf8 _v))
                            (Lens.Family2.view
                               (Data.ProtoLens.Field.field @"vec'collectionIds") _x))
                         (Data.ProtoLens.Encoding.Wire.buildFieldSet
                            (Lens.Family2.view Data.ProtoLens.unknownFields _x))))))
instance Control.DeepSeq.NFData CollectionsCitation where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_CollectionsCitation'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_CollectionsCitation'fileId x__)
                (Control.DeepSeq.deepseq
                   (_CollectionsCitation'chunkId x__)
                   (Control.DeepSeq.deepseq
                      (_CollectionsCitation'chunkContent x__)
                      (Control.DeepSeq.deepseq
                         (_CollectionsCitation'score x__)
                         (Control.DeepSeq.deepseq
                            (_CollectionsCitation'collectionIds x__) ())))))
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Chat_Fields.collectionIds' @:: Lens' CollectionsSearch [Data.Text.Text]@
         * 'Proto.Xai.Api.V1.Chat_Fields.vec'collectionIds' @:: Lens' CollectionsSearch (Data.Vector.Vector Data.Text.Text)@
         * 'Proto.Xai.Api.V1.Chat_Fields.limit' @:: Lens' CollectionsSearch Data.Int.Int32@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'limit' @:: Lens' CollectionsSearch (Prelude.Maybe Data.Int.Int32)@
         * 'Proto.Xai.Api.V1.Chat_Fields.instructions' @:: Lens' CollectionsSearch Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'instructions' @:: Lens' CollectionsSearch (Prelude.Maybe Data.Text.Text)@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'retrievalMode' @:: Lens' CollectionsSearch (Prelude.Maybe CollectionsSearch'RetrievalMode)@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'hybridRetrieval' @:: Lens' CollectionsSearch (Prelude.Maybe Proto.Xai.Api.V1.Documents.HybridRetrieval)@
         * 'Proto.Xai.Api.V1.Chat_Fields.hybridRetrieval' @:: Lens' CollectionsSearch Proto.Xai.Api.V1.Documents.HybridRetrieval@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'semanticRetrieval' @:: Lens' CollectionsSearch (Prelude.Maybe Proto.Xai.Api.V1.Documents.SemanticRetrieval)@
         * 'Proto.Xai.Api.V1.Chat_Fields.semanticRetrieval' @:: Lens' CollectionsSearch Proto.Xai.Api.V1.Documents.SemanticRetrieval@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'keywordRetrieval' @:: Lens' CollectionsSearch (Prelude.Maybe Proto.Xai.Api.V1.Documents.KeywordRetrieval)@
         * 'Proto.Xai.Api.V1.Chat_Fields.keywordRetrieval' @:: Lens' CollectionsSearch Proto.Xai.Api.V1.Documents.KeywordRetrieval@ -}
data CollectionsSearch
  = CollectionsSearch'_constructor {_CollectionsSearch'collectionIds :: !(Data.Vector.Vector Data.Text.Text),
                                    _CollectionsSearch'limit :: !(Prelude.Maybe Data.Int.Int32),
                                    _CollectionsSearch'instructions :: !(Prelude.Maybe Data.Text.Text),
                                    _CollectionsSearch'retrievalMode :: !(Prelude.Maybe CollectionsSearch'RetrievalMode),
                                    _CollectionsSearch'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show CollectionsSearch where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
data CollectionsSearch'RetrievalMode
  = CollectionsSearch'HybridRetrieval !Proto.Xai.Api.V1.Documents.HybridRetrieval |
    CollectionsSearch'SemanticRetrieval !Proto.Xai.Api.V1.Documents.SemanticRetrieval |
    CollectionsSearch'KeywordRetrieval !Proto.Xai.Api.V1.Documents.KeywordRetrieval
  deriving stock (Prelude.Show, Prelude.Eq, Prelude.Ord)
instance Data.ProtoLens.Field.HasField CollectionsSearch "collectionIds" [Data.Text.Text] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CollectionsSearch'collectionIds
           (\ x__ y__ -> x__ {_CollectionsSearch'collectionIds = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField CollectionsSearch "vec'collectionIds" (Data.Vector.Vector Data.Text.Text) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CollectionsSearch'collectionIds
           (\ x__ y__ -> x__ {_CollectionsSearch'collectionIds = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField CollectionsSearch "limit" Data.Int.Int32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CollectionsSearch'limit
           (\ x__ y__ -> x__ {_CollectionsSearch'limit = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField CollectionsSearch "maybe'limit" (Prelude.Maybe Data.Int.Int32) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CollectionsSearch'limit
           (\ x__ y__ -> x__ {_CollectionsSearch'limit = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField CollectionsSearch "instructions" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CollectionsSearch'instructions
           (\ x__ y__ -> x__ {_CollectionsSearch'instructions = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField CollectionsSearch "maybe'instructions" (Prelude.Maybe Data.Text.Text) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CollectionsSearch'instructions
           (\ x__ y__ -> x__ {_CollectionsSearch'instructions = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField CollectionsSearch "maybe'retrievalMode" (Prelude.Maybe CollectionsSearch'RetrievalMode) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CollectionsSearch'retrievalMode
           (\ x__ y__ -> x__ {_CollectionsSearch'retrievalMode = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField CollectionsSearch "maybe'hybridRetrieval" (Prelude.Maybe Proto.Xai.Api.V1.Documents.HybridRetrieval) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CollectionsSearch'retrievalMode
           (\ x__ y__ -> x__ {_CollectionsSearch'retrievalMode = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (CollectionsSearch'HybridRetrieval x__val))
                     -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap CollectionsSearch'HybridRetrieval y__))
instance Data.ProtoLens.Field.HasField CollectionsSearch "hybridRetrieval" Proto.Xai.Api.V1.Documents.HybridRetrieval where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CollectionsSearch'retrievalMode
           (\ x__ y__ -> x__ {_CollectionsSearch'retrievalMode = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (CollectionsSearch'HybridRetrieval x__val))
                        -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap CollectionsSearch'HybridRetrieval y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Field.HasField CollectionsSearch "maybe'semanticRetrieval" (Prelude.Maybe Proto.Xai.Api.V1.Documents.SemanticRetrieval) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CollectionsSearch'retrievalMode
           (\ x__ y__ -> x__ {_CollectionsSearch'retrievalMode = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (CollectionsSearch'SemanticRetrieval x__val))
                     -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap CollectionsSearch'SemanticRetrieval y__))
instance Data.ProtoLens.Field.HasField CollectionsSearch "semanticRetrieval" Proto.Xai.Api.V1.Documents.SemanticRetrieval where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CollectionsSearch'retrievalMode
           (\ x__ y__ -> x__ {_CollectionsSearch'retrievalMode = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (CollectionsSearch'SemanticRetrieval x__val))
                        -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap CollectionsSearch'SemanticRetrieval y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Field.HasField CollectionsSearch "maybe'keywordRetrieval" (Prelude.Maybe Proto.Xai.Api.V1.Documents.KeywordRetrieval) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CollectionsSearch'retrievalMode
           (\ x__ y__ -> x__ {_CollectionsSearch'retrievalMode = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (CollectionsSearch'KeywordRetrieval x__val))
                     -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap CollectionsSearch'KeywordRetrieval y__))
instance Data.ProtoLens.Field.HasField CollectionsSearch "keywordRetrieval" Proto.Xai.Api.V1.Documents.KeywordRetrieval where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CollectionsSearch'retrievalMode
           (\ x__ y__ -> x__ {_CollectionsSearch'retrievalMode = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (CollectionsSearch'KeywordRetrieval x__val))
                        -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap CollectionsSearch'KeywordRetrieval y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Message CollectionsSearch where
  messageName _ = Data.Text.pack "xai_api.CollectionsSearch"
  packedMessageDescriptor _
    = "\n\
      \\DC1CollectionsSearch\DC2%\n\
      \\SOcollection_ids\CAN\SOH \ETX(\tR\rcollectionIds\DC2\EM\n\
      \\ENQlimit\CAN\STX \SOH(\ENQH\SOHR\ENQlimit\136\SOH\SOH\DC2'\n\
      \\finstructions\CAN\ETX \SOH(\tH\STXR\finstructions\136\SOH\SOH\DC2E\n\
      \\DLEhybrid_retrieval\CAN\EOT \SOH(\v2\CAN.xai_api.HybridRetrievalH\NULR\SIhybridRetrieval\DC2K\n\
      \\DC2semantic_retrieval\CAN\ENQ \SOH(\v2\SUB.xai_api.SemanticRetrievalH\NULR\DC1semanticRetrieval\DC2H\n\
      \\DC1keyword_retrieval\CAN\ACK \SOH(\v2\EM.xai_api.KeywordRetrievalH\NULR\DLEkeywordRetrievalB\DLE\n\
      \\SOretrieval_modeB\b\n\
      \\ACK_limitB\SI\n\
      \\r_instructions"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        collectionIds__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "collection_ids"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Unpacked
                 (Data.ProtoLens.Field.field @"collectionIds")) ::
              Data.ProtoLens.FieldDescriptor CollectionsSearch
        limit__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "limit"
              (Data.ProtoLens.ScalarField Data.ProtoLens.Int32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Int.Int32)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'limit")) ::
              Data.ProtoLens.FieldDescriptor CollectionsSearch
        instructions__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "instructions"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'instructions")) ::
              Data.ProtoLens.FieldDescriptor CollectionsSearch
        hybridRetrieval__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "hybrid_retrieval"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor Proto.Xai.Api.V1.Documents.HybridRetrieval)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'hybridRetrieval")) ::
              Data.ProtoLens.FieldDescriptor CollectionsSearch
        semanticRetrieval__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "semantic_retrieval"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor Proto.Xai.Api.V1.Documents.SemanticRetrieval)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'semanticRetrieval")) ::
              Data.ProtoLens.FieldDescriptor CollectionsSearch
        keywordRetrieval__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "keyword_retrieval"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor Proto.Xai.Api.V1.Documents.KeywordRetrieval)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'keywordRetrieval")) ::
              Data.ProtoLens.FieldDescriptor CollectionsSearch
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, collectionIds__field_descriptor),
           (Data.ProtoLens.Tag 2, limit__field_descriptor),
           (Data.ProtoLens.Tag 3, instructions__field_descriptor),
           (Data.ProtoLens.Tag 4, hybridRetrieval__field_descriptor),
           (Data.ProtoLens.Tag 5, semanticRetrieval__field_descriptor),
           (Data.ProtoLens.Tag 6, keywordRetrieval__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _CollectionsSearch'_unknownFields
        (\ x__ y__ -> x__ {_CollectionsSearch'_unknownFields = y__})
  defMessage
    = CollectionsSearch'_constructor
        {_CollectionsSearch'collectionIds = Data.Vector.Generic.empty,
         _CollectionsSearch'limit = Prelude.Nothing,
         _CollectionsSearch'instructions = Prelude.Nothing,
         _CollectionsSearch'retrievalMode = Prelude.Nothing,
         _CollectionsSearch'_unknownFields = []}
  parseMessage
    = let
        loop ::
          CollectionsSearch
          -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Vector Data.ProtoLens.Encoding.Growing.RealWorld Data.Text.Text
             -> Data.ProtoLens.Encoding.Bytes.Parser CollectionsSearch
        loop x mutable'collectionIds
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do frozen'collectionIds <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                                (Data.ProtoLens.Encoding.Growing.unsafeFreeze
                                                   mutable'collectionIds)
                      (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t)
                           (Lens.Family2.set
                              (Data.ProtoLens.Field.field @"vec'collectionIds")
                              frozen'collectionIds x))
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                            Data.ProtoLens.Encoding.Bytes.getText
                                              (Prelude.fromIntegral len))
                                        "collection_ids"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append
                                          mutable'collectionIds y)
                                loop x v
                        16
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "limit"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"limit") y x)
                                  mutable'collectionIds
                        26
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "instructions"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"instructions") y x)
                                  mutable'collectionIds
                        34
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "hybrid_retrieval"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"hybridRetrieval") y x)
                                  mutable'collectionIds
                        42
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "semantic_retrieval"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"semanticRetrieval") y x)
                                  mutable'collectionIds
                        50
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "keyword_retrieval"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"keywordRetrieval") y x)
                                  mutable'collectionIds
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
                                  mutable'collectionIds
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do mutable'collectionIds <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                         Data.ProtoLens.Encoding.Growing.new
              loop Data.ProtoLens.defMessage mutable'collectionIds)
          "CollectionsSearch"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (Data.ProtoLens.Encoding.Bytes.foldMapBuilder
                (\ _v
                   -> (Data.Monoid.<>)
                        (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                        ((Prelude..)
                           (\ bs
                              -> (Data.Monoid.<>)
                                   (Data.ProtoLens.Encoding.Bytes.putVarInt
                                      (Prelude.fromIntegral (Data.ByteString.length bs)))
                                   (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                           Data.Text.Encoding.encodeUtf8 _v))
                (Lens.Family2.view
                   (Data.ProtoLens.Field.field @"vec'collectionIds") _x))
             ((Data.Monoid.<>)
                (case
                     Lens.Family2.view (Data.ProtoLens.Field.field @"maybe'limit") _x
                 of
                   Prelude.Nothing -> Data.Monoid.mempty
                   (Prelude.Just _v)
                     -> (Data.Monoid.<>)
                          (Data.ProtoLens.Encoding.Bytes.putVarInt 16)
                          ((Prelude..)
                             Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral _v))
                ((Data.Monoid.<>)
                   (case
                        Lens.Family2.view
                          (Data.ProtoLens.Field.field @"maybe'instructions") _x
                    of
                      Prelude.Nothing -> Data.Monoid.mempty
                      (Prelude.Just _v)
                        -> (Data.Monoid.<>)
                             (Data.ProtoLens.Encoding.Bytes.putVarInt 26)
                             ((Prelude..)
                                (\ bs
                                   -> (Data.Monoid.<>)
                                        (Data.ProtoLens.Encoding.Bytes.putVarInt
                                           (Prelude.fromIntegral (Data.ByteString.length bs)))
                                        (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                Data.Text.Encoding.encodeUtf8 _v))
                   ((Data.Monoid.<>)
                      (case
                           Lens.Family2.view
                             (Data.ProtoLens.Field.field @"maybe'retrievalMode") _x
                       of
                         Prelude.Nothing -> Data.Monoid.mempty
                         (Prelude.Just (CollectionsSearch'HybridRetrieval v))
                           -> (Data.Monoid.<>)
                                (Data.ProtoLens.Encoding.Bytes.putVarInt 34)
                                ((Prelude..)
                                   (\ bs
                                      -> (Data.Monoid.<>)
                                           (Data.ProtoLens.Encoding.Bytes.putVarInt
                                              (Prelude.fromIntegral (Data.ByteString.length bs)))
                                           (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                   Data.ProtoLens.encodeMessage v)
                         (Prelude.Just (CollectionsSearch'SemanticRetrieval v))
                           -> (Data.Monoid.<>)
                                (Data.ProtoLens.Encoding.Bytes.putVarInt 42)
                                ((Prelude..)
                                   (\ bs
                                      -> (Data.Monoid.<>)
                                           (Data.ProtoLens.Encoding.Bytes.putVarInt
                                              (Prelude.fromIntegral (Data.ByteString.length bs)))
                                           (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                   Data.ProtoLens.encodeMessage v)
                         (Prelude.Just (CollectionsSearch'KeywordRetrieval v))
                           -> (Data.Monoid.<>)
                                (Data.ProtoLens.Encoding.Bytes.putVarInt 50)
                                ((Prelude..)
                                   (\ bs
                                      -> (Data.Monoid.<>)
                                           (Data.ProtoLens.Encoding.Bytes.putVarInt
                                              (Prelude.fromIntegral (Data.ByteString.length bs)))
                                           (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                   Data.ProtoLens.encodeMessage v))
                      (Data.ProtoLens.Encoding.Wire.buildFieldSet
                         (Lens.Family2.view Data.ProtoLens.unknownFields _x)))))
instance Control.DeepSeq.NFData CollectionsSearch where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_CollectionsSearch'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_CollectionsSearch'collectionIds x__)
                (Control.DeepSeq.deepseq
                   (_CollectionsSearch'limit x__)
                   (Control.DeepSeq.deepseq
                      (_CollectionsSearch'instructions x__)
                      (Control.DeepSeq.deepseq
                         (_CollectionsSearch'retrievalMode x__) ()))))
instance Control.DeepSeq.NFData CollectionsSearch'RetrievalMode where
  rnf (CollectionsSearch'HybridRetrieval x__)
    = Control.DeepSeq.rnf x__
  rnf (CollectionsSearch'SemanticRetrieval x__)
    = Control.DeepSeq.rnf x__
  rnf (CollectionsSearch'KeywordRetrieval x__)
    = Control.DeepSeq.rnf x__
_CollectionsSearch'HybridRetrieval ::
  Data.ProtoLens.Prism.Prism' CollectionsSearch'RetrievalMode Proto.Xai.Api.V1.Documents.HybridRetrieval
_CollectionsSearch'HybridRetrieval
  = Data.ProtoLens.Prism.prism'
      CollectionsSearch'HybridRetrieval
      (\ p__
         -> case p__ of
              (CollectionsSearch'HybridRetrieval p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
_CollectionsSearch'SemanticRetrieval ::
  Data.ProtoLens.Prism.Prism' CollectionsSearch'RetrievalMode Proto.Xai.Api.V1.Documents.SemanticRetrieval
_CollectionsSearch'SemanticRetrieval
  = Data.ProtoLens.Prism.prism'
      CollectionsSearch'SemanticRetrieval
      (\ p__
         -> case p__ of
              (CollectionsSearch'SemanticRetrieval p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
_CollectionsSearch'KeywordRetrieval ::
  Data.ProtoLens.Prism.Prism' CollectionsSearch'RetrievalMode Proto.Xai.Api.V1.Documents.KeywordRetrieval
_CollectionsSearch'KeywordRetrieval
  = Data.ProtoLens.Prism.prism'
      CollectionsSearch'KeywordRetrieval
      (\ p__
         -> case p__ of
              (CollectionsSearch'KeywordRetrieval p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Chat_Fields.model' @:: Lens' CompactContextRequest Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.input' @:: Lens' CompactContextRequest [Message]@
         * 'Proto.Xai.Api.V1.Chat_Fields.vec'input' @:: Lens' CompactContextRequest (Data.Vector.Vector Message)@ -}
data CompactContextRequest
  = CompactContextRequest'_constructor {_CompactContextRequest'model :: !Data.Text.Text,
                                        _CompactContextRequest'input :: !(Data.Vector.Vector Message),
                                        _CompactContextRequest'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show CompactContextRequest where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField CompactContextRequest "model" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CompactContextRequest'model
           (\ x__ y__ -> x__ {_CompactContextRequest'model = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField CompactContextRequest "input" [Message] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CompactContextRequest'input
           (\ x__ y__ -> x__ {_CompactContextRequest'input = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField CompactContextRequest "vec'input" (Data.Vector.Vector Message) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CompactContextRequest'input
           (\ x__ y__ -> x__ {_CompactContextRequest'input = y__}))
        Prelude.id
instance Data.ProtoLens.Message CompactContextRequest where
  messageName _ = Data.Text.pack "xai_api.CompactContextRequest"
  packedMessageDescriptor _
    = "\n\
      \\NAKCompactContextRequest\DC2\DC4\n\
      \\ENQmodel\CAN\SOH \SOH(\tR\ENQmodel\DC2&\n\
      \\ENQinput\CAN\STX \ETX(\v2\DLE.xai_api.MessageR\ENQinput"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        model__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "model"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"model")) ::
              Data.ProtoLens.FieldDescriptor CompactContextRequest
        input__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "input"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor Message)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Unpacked (Data.ProtoLens.Field.field @"input")) ::
              Data.ProtoLens.FieldDescriptor CompactContextRequest
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, model__field_descriptor),
           (Data.ProtoLens.Tag 2, input__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _CompactContextRequest'_unknownFields
        (\ x__ y__ -> x__ {_CompactContextRequest'_unknownFields = y__})
  defMessage
    = CompactContextRequest'_constructor
        {_CompactContextRequest'model = Data.ProtoLens.fieldDefault,
         _CompactContextRequest'input = Data.Vector.Generic.empty,
         _CompactContextRequest'_unknownFields = []}
  parseMessage
    = let
        loop ::
          CompactContextRequest
          -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Vector Data.ProtoLens.Encoding.Growing.RealWorld Message
             -> Data.ProtoLens.Encoding.Bytes.Parser CompactContextRequest
        loop x mutable'input
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do frozen'input <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                        (Data.ProtoLens.Encoding.Growing.unsafeFreeze mutable'input)
                      (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t)
                           (Lens.Family2.set
                              (Data.ProtoLens.Field.field @"vec'input") frozen'input x))
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "model"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"model") y x)
                                  mutable'input
                        18
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                            Data.ProtoLens.Encoding.Bytes.isolate
                                              (Prelude.fromIntegral len)
                                              Data.ProtoLens.parseMessage)
                                        "input"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append mutable'input y)
                                loop x v
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
                                  mutable'input
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do mutable'input <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                 Data.ProtoLens.Encoding.Growing.new
              loop Data.ProtoLens.defMessage mutable'input)
          "CompactContextRequest"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v = Lens.Family2.view (Data.ProtoLens.Field.field @"model") _x
              in
                if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                      ((Prelude..)
                         (\ bs
                            -> (Data.Monoid.<>)
                                 (Data.ProtoLens.Encoding.Bytes.putVarInt
                                    (Prelude.fromIntegral (Data.ByteString.length bs)))
                                 (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                         Data.Text.Encoding.encodeUtf8 _v))
             ((Data.Monoid.<>)
                (Data.ProtoLens.Encoding.Bytes.foldMapBuilder
                   (\ _v
                      -> (Data.Monoid.<>)
                           (Data.ProtoLens.Encoding.Bytes.putVarInt 18)
                           ((Prelude..)
                              (\ bs
                                 -> (Data.Monoid.<>)
                                      (Data.ProtoLens.Encoding.Bytes.putVarInt
                                         (Prelude.fromIntegral (Data.ByteString.length bs)))
                                      (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                              Data.ProtoLens.encodeMessage _v))
                   (Lens.Family2.view (Data.ProtoLens.Field.field @"vec'input") _x))
                (Data.ProtoLens.Encoding.Wire.buildFieldSet
                   (Lens.Family2.view Data.ProtoLens.unknownFields _x)))
instance Control.DeepSeq.NFData CompactContextRequest where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_CompactContextRequest'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_CompactContextRequest'model x__)
                (Control.DeepSeq.deepseq (_CompactContextRequest'input x__) ()))
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Chat_Fields.id' @:: Lens' CompactContextResponse Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.encryptedContent' @:: Lens' CompactContextResponse Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.droppedMessageCount' @:: Lens' CompactContextResponse Data.Word.Word32@
         * 'Proto.Xai.Api.V1.Chat_Fields.usage' @:: Lens' CompactContextResponse Proto.Xai.Api.V1.Usage.SamplingUsage@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'usage' @:: Lens' CompactContextResponse (Prelude.Maybe Proto.Xai.Api.V1.Usage.SamplingUsage)@ -}
data CompactContextResponse
  = CompactContextResponse'_constructor {_CompactContextResponse'id :: !Data.Text.Text,
                                         _CompactContextResponse'encryptedContent :: !Data.Text.Text,
                                         _CompactContextResponse'droppedMessageCount :: !Data.Word.Word32,
                                         _CompactContextResponse'usage :: !(Prelude.Maybe Proto.Xai.Api.V1.Usage.SamplingUsage),
                                         _CompactContextResponse'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show CompactContextResponse where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField CompactContextResponse "id" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CompactContextResponse'id
           (\ x__ y__ -> x__ {_CompactContextResponse'id = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField CompactContextResponse "encryptedContent" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CompactContextResponse'encryptedContent
           (\ x__ y__
              -> x__ {_CompactContextResponse'encryptedContent = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField CompactContextResponse "droppedMessageCount" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CompactContextResponse'droppedMessageCount
           (\ x__ y__
              -> x__ {_CompactContextResponse'droppedMessageCount = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField CompactContextResponse "usage" Proto.Xai.Api.V1.Usage.SamplingUsage where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CompactContextResponse'usage
           (\ x__ y__ -> x__ {_CompactContextResponse'usage = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage)
instance Data.ProtoLens.Field.HasField CompactContextResponse "maybe'usage" (Prelude.Maybe Proto.Xai.Api.V1.Usage.SamplingUsage) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CompactContextResponse'usage
           (\ x__ y__ -> x__ {_CompactContextResponse'usage = y__}))
        Prelude.id
instance Data.ProtoLens.Message CompactContextResponse where
  messageName _ = Data.Text.pack "xai_api.CompactContextResponse"
  packedMessageDescriptor _
    = "\n\
      \\SYNCompactContextResponse\DC2\SO\n\
      \\STXid\CAN\SOH \SOH(\tR\STXid\DC2+\n\
      \\DC1encrypted_content\CAN\STX \SOH(\tR\DLEencryptedContent\DC22\n\
      \\NAKdropped_message_count\CAN\ETX \SOH(\rR\DC3droppedMessageCount\DC2,\n\
      \\ENQusage\CAN\EOT \SOH(\v2\SYN.xai_api.SamplingUsageR\ENQusage"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        id__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "id"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"id")) ::
              Data.ProtoLens.FieldDescriptor CompactContextResponse
        encryptedContent__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "encrypted_content"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"encryptedContent")) ::
              Data.ProtoLens.FieldDescriptor CompactContextResponse
        droppedMessageCount__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "dropped_message_count"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"droppedMessageCount")) ::
              Data.ProtoLens.FieldDescriptor CompactContextResponse
        usage__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "usage"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor Proto.Xai.Api.V1.Usage.SamplingUsage)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'usage")) ::
              Data.ProtoLens.FieldDescriptor CompactContextResponse
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, id__field_descriptor),
           (Data.ProtoLens.Tag 2, encryptedContent__field_descriptor),
           (Data.ProtoLens.Tag 3, droppedMessageCount__field_descriptor),
           (Data.ProtoLens.Tag 4, usage__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _CompactContextResponse'_unknownFields
        (\ x__ y__ -> x__ {_CompactContextResponse'_unknownFields = y__})
  defMessage
    = CompactContextResponse'_constructor
        {_CompactContextResponse'id = Data.ProtoLens.fieldDefault,
         _CompactContextResponse'encryptedContent = Data.ProtoLens.fieldDefault,
         _CompactContextResponse'droppedMessageCount = Data.ProtoLens.fieldDefault,
         _CompactContextResponse'usage = Prelude.Nothing,
         _CompactContextResponse'_unknownFields = []}
  parseMessage
    = let
        loop ::
          CompactContextResponse
          -> Data.ProtoLens.Encoding.Bytes.Parser CompactContextResponse
        loop x
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t) x)
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "id"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"id") y x)
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "encrypted_content"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"encryptedContent") y x)
                        24
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "dropped_message_count"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"droppedMessageCount") y x)
                        34
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "usage"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"usage") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "CompactContextResponse"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let _v = Lens.Family2.view (Data.ProtoLens.Field.field @"id") _x
              in
                if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                      ((Prelude..)
                         (\ bs
                            -> (Data.Monoid.<>)
                                 (Data.ProtoLens.Encoding.Bytes.putVarInt
                                    (Prelude.fromIntegral (Data.ByteString.length bs)))
                                 (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                         Data.Text.Encoding.encodeUtf8 _v))
             ((Data.Monoid.<>)
                (let
                   _v
                     = Lens.Family2.view
                         (Data.ProtoLens.Field.field @"encryptedContent") _x
                 in
                   if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                       Data.Monoid.mempty
                   else
                       (Data.Monoid.<>)
                         (Data.ProtoLens.Encoding.Bytes.putVarInt 18)
                         ((Prelude..)
                            (\ bs
                               -> (Data.Monoid.<>)
                                    (Data.ProtoLens.Encoding.Bytes.putVarInt
                                       (Prelude.fromIntegral (Data.ByteString.length bs)))
                                    (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                            Data.Text.Encoding.encodeUtf8 _v))
                ((Data.Monoid.<>)
                   (let
                      _v
                        = Lens.Family2.view
                            (Data.ProtoLens.Field.field @"droppedMessageCount") _x
                    in
                      if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                          Data.Monoid.mempty
                      else
                          (Data.Monoid.<>)
                            (Data.ProtoLens.Encoding.Bytes.putVarInt 24)
                            ((Prelude..)
                               Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral _v))
                   ((Data.Monoid.<>)
                      (case
                           Lens.Family2.view (Data.ProtoLens.Field.field @"maybe'usage") _x
                       of
                         Prelude.Nothing -> Data.Monoid.mempty
                         (Prelude.Just _v)
                           -> (Data.Monoid.<>)
                                (Data.ProtoLens.Encoding.Bytes.putVarInt 34)
                                ((Prelude..)
                                   (\ bs
                                      -> (Data.Monoid.<>)
                                           (Data.ProtoLens.Encoding.Bytes.putVarInt
                                              (Prelude.fromIntegral (Data.ByteString.length bs)))
                                           (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                   Data.ProtoLens.encodeMessage _v))
                      (Data.ProtoLens.Encoding.Wire.buildFieldSet
                         (Lens.Family2.view Data.ProtoLens.unknownFields _x)))))
instance Control.DeepSeq.NFData CompactContextResponse where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_CompactContextResponse'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_CompactContextResponse'id x__)
                (Control.DeepSeq.deepseq
                   (_CompactContextResponse'encryptedContent x__)
                   (Control.DeepSeq.deepseq
                      (_CompactContextResponse'droppedMessageCount x__)
                      (Control.DeepSeq.deepseq (_CompactContextResponse'usage x__) ()))))
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Chat_Fields.content' @:: Lens' CompletionMessage Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.reasoningContent' @:: Lens' CompletionMessage Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.role' @:: Lens' CompletionMessage MessageRole@
         * 'Proto.Xai.Api.V1.Chat_Fields.toolCalls' @:: Lens' CompletionMessage [ToolCall]@
         * 'Proto.Xai.Api.V1.Chat_Fields.vec'toolCalls' @:: Lens' CompletionMessage (Data.Vector.Vector ToolCall)@
         * 'Proto.Xai.Api.V1.Chat_Fields.encryptedContent' @:: Lens' CompletionMessage Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.citations' @:: Lens' CompletionMessage [InlineCitation]@
         * 'Proto.Xai.Api.V1.Chat_Fields.vec'citations' @:: Lens' CompletionMessage (Data.Vector.Vector InlineCitation)@ -}
data CompletionMessage
  = CompletionMessage'_constructor {_CompletionMessage'content :: !Data.Text.Text,
                                    _CompletionMessage'reasoningContent :: !Data.Text.Text,
                                    _CompletionMessage'role :: !MessageRole,
                                    _CompletionMessage'toolCalls :: !(Data.Vector.Vector ToolCall),
                                    _CompletionMessage'encryptedContent :: !Data.Text.Text,
                                    _CompletionMessage'citations :: !(Data.Vector.Vector InlineCitation),
                                    _CompletionMessage'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show CompletionMessage where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField CompletionMessage "content" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CompletionMessage'content
           (\ x__ y__ -> x__ {_CompletionMessage'content = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField CompletionMessage "reasoningContent" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CompletionMessage'reasoningContent
           (\ x__ y__ -> x__ {_CompletionMessage'reasoningContent = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField CompletionMessage "role" MessageRole where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CompletionMessage'role
           (\ x__ y__ -> x__ {_CompletionMessage'role = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField CompletionMessage "toolCalls" [ToolCall] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CompletionMessage'toolCalls
           (\ x__ y__ -> x__ {_CompletionMessage'toolCalls = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField CompletionMessage "vec'toolCalls" (Data.Vector.Vector ToolCall) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CompletionMessage'toolCalls
           (\ x__ y__ -> x__ {_CompletionMessage'toolCalls = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField CompletionMessage "encryptedContent" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CompletionMessage'encryptedContent
           (\ x__ y__ -> x__ {_CompletionMessage'encryptedContent = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField CompletionMessage "citations" [InlineCitation] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CompletionMessage'citations
           (\ x__ y__ -> x__ {_CompletionMessage'citations = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField CompletionMessage "vec'citations" (Data.Vector.Vector InlineCitation) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CompletionMessage'citations
           (\ x__ y__ -> x__ {_CompletionMessage'citations = y__}))
        Prelude.id
instance Data.ProtoLens.Message CompletionMessage where
  messageName _ = Data.Text.pack "xai_api.CompletionMessage"
  packedMessageDescriptor _
    = "\n\
      \\DC1CompletionMessage\DC2\CAN\n\
      \\acontent\CAN\SOH \SOH(\tR\acontent\DC2+\n\
      \\DC1reasoning_content\CAN\EOT \SOH(\tR\DLEreasoningContent\DC2(\n\
      \\EOTrole\CAN\STX \SOH(\SO2\DC4.xai_api.MessageRoleR\EOTrole\DC20\n\
      \\n\
      \tool_calls\CAN\ETX \ETX(\v2\DC1.xai_api.ToolCallR\ttoolCalls\DC2+\n\
      \\DC1encrypted_content\CAN\ENQ \SOH(\tR\DLEencryptedContent\DC25\n\
      \\tcitations\CAN\ACK \ETX(\v2\ETB.xai_api.InlineCitationR\tcitations"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        content__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "content"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"content")) ::
              Data.ProtoLens.FieldDescriptor CompletionMessage
        reasoningContent__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "reasoning_content"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"reasoningContent")) ::
              Data.ProtoLens.FieldDescriptor CompletionMessage
        role__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "role"
              (Data.ProtoLens.ScalarField Data.ProtoLens.EnumField ::
                 Data.ProtoLens.FieldTypeDescriptor MessageRole)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"role")) ::
              Data.ProtoLens.FieldDescriptor CompletionMessage
        toolCalls__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "tool_calls"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor ToolCall)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Unpacked
                 (Data.ProtoLens.Field.field @"toolCalls")) ::
              Data.ProtoLens.FieldDescriptor CompletionMessage
        encryptedContent__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "encrypted_content"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"encryptedContent")) ::
              Data.ProtoLens.FieldDescriptor CompletionMessage
        citations__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "citations"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor InlineCitation)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Unpacked
                 (Data.ProtoLens.Field.field @"citations")) ::
              Data.ProtoLens.FieldDescriptor CompletionMessage
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, content__field_descriptor),
           (Data.ProtoLens.Tag 4, reasoningContent__field_descriptor),
           (Data.ProtoLens.Tag 2, role__field_descriptor),
           (Data.ProtoLens.Tag 3, toolCalls__field_descriptor),
           (Data.ProtoLens.Tag 5, encryptedContent__field_descriptor),
           (Data.ProtoLens.Tag 6, citations__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _CompletionMessage'_unknownFields
        (\ x__ y__ -> x__ {_CompletionMessage'_unknownFields = y__})
  defMessage
    = CompletionMessage'_constructor
        {_CompletionMessage'content = Data.ProtoLens.fieldDefault,
         _CompletionMessage'reasoningContent = Data.ProtoLens.fieldDefault,
         _CompletionMessage'role = Data.ProtoLens.fieldDefault,
         _CompletionMessage'toolCalls = Data.Vector.Generic.empty,
         _CompletionMessage'encryptedContent = Data.ProtoLens.fieldDefault,
         _CompletionMessage'citations = Data.Vector.Generic.empty,
         _CompletionMessage'_unknownFields = []}
  parseMessage
    = let
        loop ::
          CompletionMessage
          -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Vector Data.ProtoLens.Encoding.Growing.RealWorld InlineCitation
             -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Vector Data.ProtoLens.Encoding.Growing.RealWorld ToolCall
                -> Data.ProtoLens.Encoding.Bytes.Parser CompletionMessage
        loop x mutable'citations mutable'toolCalls
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do frozen'citations <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                            (Data.ProtoLens.Encoding.Growing.unsafeFreeze
                                               mutable'citations)
                      frozen'toolCalls <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                            (Data.ProtoLens.Encoding.Growing.unsafeFreeze
                                               mutable'toolCalls)
                      (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t)
                           (Lens.Family2.set
                              (Data.ProtoLens.Field.field @"vec'citations") frozen'citations
                              (Lens.Family2.set
                                 (Data.ProtoLens.Field.field @"vec'toolCalls") frozen'toolCalls x)))
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "content"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"content") y x)
                                  mutable'citations mutable'toolCalls
                        34
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "reasoning_content"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"reasoningContent") y x)
                                  mutable'citations mutable'toolCalls
                        16
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.toEnum
                                          (Prelude.fmap
                                             Prelude.fromIntegral
                                             Data.ProtoLens.Encoding.Bytes.getVarInt))
                                       "role"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"role") y x)
                                  mutable'citations mutable'toolCalls
                        26
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                            Data.ProtoLens.Encoding.Bytes.isolate
                                              (Prelude.fromIntegral len)
                                              Data.ProtoLens.parseMessage)
                                        "tool_calls"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append mutable'toolCalls y)
                                loop x mutable'citations v
                        42
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "encrypted_content"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"encryptedContent") y x)
                                  mutable'citations mutable'toolCalls
                        50
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                            Data.ProtoLens.Encoding.Bytes.isolate
                                              (Prelude.fromIntegral len)
                                              Data.ProtoLens.parseMessage)
                                        "citations"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append mutable'citations y)
                                loop x v mutable'toolCalls
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
                                  mutable'citations mutable'toolCalls
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do mutable'citations <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                     Data.ProtoLens.Encoding.Growing.new
              mutable'toolCalls <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                     Data.ProtoLens.Encoding.Growing.new
              loop Data.ProtoLens.defMessage mutable'citations mutable'toolCalls)
          "CompletionMessage"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v = Lens.Family2.view (Data.ProtoLens.Field.field @"content") _x
              in
                if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                      ((Prelude..)
                         (\ bs
                            -> (Data.Monoid.<>)
                                 (Data.ProtoLens.Encoding.Bytes.putVarInt
                                    (Prelude.fromIntegral (Data.ByteString.length bs)))
                                 (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                         Data.Text.Encoding.encodeUtf8 _v))
             ((Data.Monoid.<>)
                (let
                   _v
                     = Lens.Family2.view
                         (Data.ProtoLens.Field.field @"reasoningContent") _x
                 in
                   if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                       Data.Monoid.mempty
                   else
                       (Data.Monoid.<>)
                         (Data.ProtoLens.Encoding.Bytes.putVarInt 34)
                         ((Prelude..)
                            (\ bs
                               -> (Data.Monoid.<>)
                                    (Data.ProtoLens.Encoding.Bytes.putVarInt
                                       (Prelude.fromIntegral (Data.ByteString.length bs)))
                                    (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                            Data.Text.Encoding.encodeUtf8 _v))
                ((Data.Monoid.<>)
                   (let _v = Lens.Family2.view (Data.ProtoLens.Field.field @"role") _x
                    in
                      if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                          Data.Monoid.mempty
                      else
                          (Data.Monoid.<>)
                            (Data.ProtoLens.Encoding.Bytes.putVarInt 16)
                            ((Prelude..)
                               ((Prelude..)
                                  Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral)
                               Prelude.fromEnum _v))
                   ((Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.foldMapBuilder
                         (\ _v
                            -> (Data.Monoid.<>)
                                 (Data.ProtoLens.Encoding.Bytes.putVarInt 26)
                                 ((Prelude..)
                                    (\ bs
                                       -> (Data.Monoid.<>)
                                            (Data.ProtoLens.Encoding.Bytes.putVarInt
                                               (Prelude.fromIntegral (Data.ByteString.length bs)))
                                            (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                    Data.ProtoLens.encodeMessage _v))
                         (Lens.Family2.view
                            (Data.ProtoLens.Field.field @"vec'toolCalls") _x))
                      ((Data.Monoid.<>)
                         (let
                            _v
                              = Lens.Family2.view
                                  (Data.ProtoLens.Field.field @"encryptedContent") _x
                          in
                            if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                Data.Monoid.mempty
                            else
                                (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt 42)
                                  ((Prelude..)
                                     (\ bs
                                        -> (Data.Monoid.<>)
                                             (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                (Prelude.fromIntegral (Data.ByteString.length bs)))
                                             (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                     Data.Text.Encoding.encodeUtf8 _v))
                         ((Data.Monoid.<>)
                            (Data.ProtoLens.Encoding.Bytes.foldMapBuilder
                               (\ _v
                                  -> (Data.Monoid.<>)
                                       (Data.ProtoLens.Encoding.Bytes.putVarInt 50)
                                       ((Prelude..)
                                          (\ bs
                                             -> (Data.Monoid.<>)
                                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                     (Prelude.fromIntegral
                                                        (Data.ByteString.length bs)))
                                                  (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                          Data.ProtoLens.encodeMessage _v))
                               (Lens.Family2.view
                                  (Data.ProtoLens.Field.field @"vec'citations") _x))
                            (Data.ProtoLens.Encoding.Wire.buildFieldSet
                               (Lens.Family2.view Data.ProtoLens.unknownFields _x)))))))
instance Control.DeepSeq.NFData CompletionMessage where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_CompletionMessage'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_CompletionMessage'content x__)
                (Control.DeepSeq.deepseq
                   (_CompletionMessage'reasoningContent x__)
                   (Control.DeepSeq.deepseq
                      (_CompletionMessage'role x__)
                      (Control.DeepSeq.deepseq
                         (_CompletionMessage'toolCalls x__)
                         (Control.DeepSeq.deepseq
                            (_CompletionMessage'encryptedContent x__)
                            (Control.DeepSeq.deepseq
                               (_CompletionMessage'citations x__) ()))))))
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Chat_Fields.finishReason' @:: Lens' CompletionOutput Proto.Xai.Api.V1.Sample.FinishReason@
         * 'Proto.Xai.Api.V1.Chat_Fields.index' @:: Lens' CompletionOutput Data.Int.Int32@
         * 'Proto.Xai.Api.V1.Chat_Fields.message' @:: Lens' CompletionOutput CompletionMessage@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'message' @:: Lens' CompletionOutput (Prelude.Maybe CompletionMessage)@
         * 'Proto.Xai.Api.V1.Chat_Fields.logprobs' @:: Lens' CompletionOutput LogProbs@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'logprobs' @:: Lens' CompletionOutput (Prelude.Maybe LogProbs)@ -}
data CompletionOutput
  = CompletionOutput'_constructor {_CompletionOutput'finishReason :: !Proto.Xai.Api.V1.Sample.FinishReason,
                                   _CompletionOutput'index :: !Data.Int.Int32,
                                   _CompletionOutput'message :: !(Prelude.Maybe CompletionMessage),
                                   _CompletionOutput'logprobs :: !(Prelude.Maybe LogProbs),
                                   _CompletionOutput'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show CompletionOutput where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField CompletionOutput "finishReason" Proto.Xai.Api.V1.Sample.FinishReason where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CompletionOutput'finishReason
           (\ x__ y__ -> x__ {_CompletionOutput'finishReason = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField CompletionOutput "index" Data.Int.Int32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CompletionOutput'index
           (\ x__ y__ -> x__ {_CompletionOutput'index = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField CompletionOutput "message" CompletionMessage where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CompletionOutput'message
           (\ x__ y__ -> x__ {_CompletionOutput'message = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage)
instance Data.ProtoLens.Field.HasField CompletionOutput "maybe'message" (Prelude.Maybe CompletionMessage) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CompletionOutput'message
           (\ x__ y__ -> x__ {_CompletionOutput'message = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField CompletionOutput "logprobs" LogProbs where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CompletionOutput'logprobs
           (\ x__ y__ -> x__ {_CompletionOutput'logprobs = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage)
instance Data.ProtoLens.Field.HasField CompletionOutput "maybe'logprobs" (Prelude.Maybe LogProbs) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CompletionOutput'logprobs
           (\ x__ y__ -> x__ {_CompletionOutput'logprobs = y__}))
        Prelude.id
instance Data.ProtoLens.Message CompletionOutput where
  messageName _ = Data.Text.pack "xai_api.CompletionOutput"
  packedMessageDescriptor _
    = "\n\
      \\DLECompletionOutput\DC2:\n\
      \\rfinish_reason\CAN\SOH \SOH(\SO2\NAK.xai_api.FinishReasonR\ffinishReason\DC2\DC4\n\
      \\ENQindex\CAN\STX \SOH(\ENQR\ENQindex\DC24\n\
      \\amessage\CAN\ETX \SOH(\v2\SUB.xai_api.CompletionMessageR\amessage\DC2-\n\
      \\blogprobs\CAN\EOT \SOH(\v2\DC1.xai_api.LogProbsR\blogprobs"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        finishReason__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "finish_reason"
              (Data.ProtoLens.ScalarField Data.ProtoLens.EnumField ::
                 Data.ProtoLens.FieldTypeDescriptor Proto.Xai.Api.V1.Sample.FinishReason)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"finishReason")) ::
              Data.ProtoLens.FieldDescriptor CompletionOutput
        index__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "index"
              (Data.ProtoLens.ScalarField Data.ProtoLens.Int32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Int.Int32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"index")) ::
              Data.ProtoLens.FieldDescriptor CompletionOutput
        message__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "message"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor CompletionMessage)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'message")) ::
              Data.ProtoLens.FieldDescriptor CompletionOutput
        logprobs__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "logprobs"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor LogProbs)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'logprobs")) ::
              Data.ProtoLens.FieldDescriptor CompletionOutput
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, finishReason__field_descriptor),
           (Data.ProtoLens.Tag 2, index__field_descriptor),
           (Data.ProtoLens.Tag 3, message__field_descriptor),
           (Data.ProtoLens.Tag 4, logprobs__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _CompletionOutput'_unknownFields
        (\ x__ y__ -> x__ {_CompletionOutput'_unknownFields = y__})
  defMessage
    = CompletionOutput'_constructor
        {_CompletionOutput'finishReason = Data.ProtoLens.fieldDefault,
         _CompletionOutput'index = Data.ProtoLens.fieldDefault,
         _CompletionOutput'message = Prelude.Nothing,
         _CompletionOutput'logprobs = Prelude.Nothing,
         _CompletionOutput'_unknownFields = []}
  parseMessage
    = let
        loop ::
          CompletionOutput
          -> Data.ProtoLens.Encoding.Bytes.Parser CompletionOutput
        loop x
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t) x)
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        8 -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.toEnum
                                          (Prelude.fmap
                                             Prelude.fromIntegral
                                             Data.ProtoLens.Encoding.Bytes.getVarInt))
                                       "finish_reason"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"finishReason") y x)
                        16
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "index"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"index") y x)
                        26
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "message"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"message") y x)
                        34
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "logprobs"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"logprobs") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "CompletionOutput"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v
                  = Lens.Family2.view (Data.ProtoLens.Field.field @"finishReason") _x
              in
                if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 8)
                      ((Prelude..)
                         ((Prelude..)
                            Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral)
                         Prelude.fromEnum _v))
             ((Data.Monoid.<>)
                (let
                   _v = Lens.Family2.view (Data.ProtoLens.Field.field @"index") _x
                 in
                   if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                       Data.Monoid.mempty
                   else
                       (Data.Monoid.<>)
                         (Data.ProtoLens.Encoding.Bytes.putVarInt 16)
                         ((Prelude..)
                            Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral _v))
                ((Data.Monoid.<>)
                   (case
                        Lens.Family2.view (Data.ProtoLens.Field.field @"maybe'message") _x
                    of
                      Prelude.Nothing -> Data.Monoid.mempty
                      (Prelude.Just _v)
                        -> (Data.Monoid.<>)
                             (Data.ProtoLens.Encoding.Bytes.putVarInt 26)
                             ((Prelude..)
                                (\ bs
                                   -> (Data.Monoid.<>)
                                        (Data.ProtoLens.Encoding.Bytes.putVarInt
                                           (Prelude.fromIntegral (Data.ByteString.length bs)))
                                        (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                Data.ProtoLens.encodeMessage _v))
                   ((Data.Monoid.<>)
                      (case
                           Lens.Family2.view (Data.ProtoLens.Field.field @"maybe'logprobs") _x
                       of
                         Prelude.Nothing -> Data.Monoid.mempty
                         (Prelude.Just _v)
                           -> (Data.Monoid.<>)
                                (Data.ProtoLens.Encoding.Bytes.putVarInt 34)
                                ((Prelude..)
                                   (\ bs
                                      -> (Data.Monoid.<>)
                                           (Data.ProtoLens.Encoding.Bytes.putVarInt
                                              (Prelude.fromIntegral (Data.ByteString.length bs)))
                                           (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                   Data.ProtoLens.encodeMessage _v))
                      (Data.ProtoLens.Encoding.Wire.buildFieldSet
                         (Lens.Family2.view Data.ProtoLens.unknownFields _x)))))
instance Control.DeepSeq.NFData CompletionOutput where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_CompletionOutput'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_CompletionOutput'finishReason x__)
                (Control.DeepSeq.deepseq
                   (_CompletionOutput'index x__)
                   (Control.DeepSeq.deepseq
                      (_CompletionOutput'message x__)
                      (Control.DeepSeq.deepseq (_CompletionOutput'logprobs x__) ()))))
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Chat_Fields.delta' @:: Lens' CompletionOutputChunk Delta@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'delta' @:: Lens' CompletionOutputChunk (Prelude.Maybe Delta)@
         * 'Proto.Xai.Api.V1.Chat_Fields.logprobs' @:: Lens' CompletionOutputChunk LogProbs@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'logprobs' @:: Lens' CompletionOutputChunk (Prelude.Maybe LogProbs)@
         * 'Proto.Xai.Api.V1.Chat_Fields.finishReason' @:: Lens' CompletionOutputChunk Proto.Xai.Api.V1.Sample.FinishReason@
         * 'Proto.Xai.Api.V1.Chat_Fields.index' @:: Lens' CompletionOutputChunk Data.Int.Int32@ -}
data CompletionOutputChunk
  = CompletionOutputChunk'_constructor {_CompletionOutputChunk'delta :: !(Prelude.Maybe Delta),
                                        _CompletionOutputChunk'logprobs :: !(Prelude.Maybe LogProbs),
                                        _CompletionOutputChunk'finishReason :: !Proto.Xai.Api.V1.Sample.FinishReason,
                                        _CompletionOutputChunk'index :: !Data.Int.Int32,
                                        _CompletionOutputChunk'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show CompletionOutputChunk where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField CompletionOutputChunk "delta" Delta where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CompletionOutputChunk'delta
           (\ x__ y__ -> x__ {_CompletionOutputChunk'delta = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage)
instance Data.ProtoLens.Field.HasField CompletionOutputChunk "maybe'delta" (Prelude.Maybe Delta) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CompletionOutputChunk'delta
           (\ x__ y__ -> x__ {_CompletionOutputChunk'delta = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField CompletionOutputChunk "logprobs" LogProbs where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CompletionOutputChunk'logprobs
           (\ x__ y__ -> x__ {_CompletionOutputChunk'logprobs = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage)
instance Data.ProtoLens.Field.HasField CompletionOutputChunk "maybe'logprobs" (Prelude.Maybe LogProbs) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CompletionOutputChunk'logprobs
           (\ x__ y__ -> x__ {_CompletionOutputChunk'logprobs = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField CompletionOutputChunk "finishReason" Proto.Xai.Api.V1.Sample.FinishReason where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CompletionOutputChunk'finishReason
           (\ x__ y__ -> x__ {_CompletionOutputChunk'finishReason = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField CompletionOutputChunk "index" Data.Int.Int32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _CompletionOutputChunk'index
           (\ x__ y__ -> x__ {_CompletionOutputChunk'index = y__}))
        Prelude.id
instance Data.ProtoLens.Message CompletionOutputChunk where
  messageName _ = Data.Text.pack "xai_api.CompletionOutputChunk"
  packedMessageDescriptor _
    = "\n\
      \\NAKCompletionOutputChunk\DC2$\n\
      \\ENQdelta\CAN\SOH \SOH(\v2\SO.xai_api.DeltaR\ENQdelta\DC2-\n\
      \\blogprobs\CAN\STX \SOH(\v2\DC1.xai_api.LogProbsR\blogprobs\DC2:\n\
      \\rfinish_reason\CAN\ETX \SOH(\SO2\NAK.xai_api.FinishReasonR\ffinishReason\DC2\DC4\n\
      \\ENQindex\CAN\EOT \SOH(\ENQR\ENQindex"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        delta__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "delta"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor Delta)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'delta")) ::
              Data.ProtoLens.FieldDescriptor CompletionOutputChunk
        logprobs__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "logprobs"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor LogProbs)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'logprobs")) ::
              Data.ProtoLens.FieldDescriptor CompletionOutputChunk
        finishReason__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "finish_reason"
              (Data.ProtoLens.ScalarField Data.ProtoLens.EnumField ::
                 Data.ProtoLens.FieldTypeDescriptor Proto.Xai.Api.V1.Sample.FinishReason)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"finishReason")) ::
              Data.ProtoLens.FieldDescriptor CompletionOutputChunk
        index__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "index"
              (Data.ProtoLens.ScalarField Data.ProtoLens.Int32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Int.Int32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"index")) ::
              Data.ProtoLens.FieldDescriptor CompletionOutputChunk
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, delta__field_descriptor),
           (Data.ProtoLens.Tag 2, logprobs__field_descriptor),
           (Data.ProtoLens.Tag 3, finishReason__field_descriptor),
           (Data.ProtoLens.Tag 4, index__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _CompletionOutputChunk'_unknownFields
        (\ x__ y__ -> x__ {_CompletionOutputChunk'_unknownFields = y__})
  defMessage
    = CompletionOutputChunk'_constructor
        {_CompletionOutputChunk'delta = Prelude.Nothing,
         _CompletionOutputChunk'logprobs = Prelude.Nothing,
         _CompletionOutputChunk'finishReason = Data.ProtoLens.fieldDefault,
         _CompletionOutputChunk'index = Data.ProtoLens.fieldDefault,
         _CompletionOutputChunk'_unknownFields = []}
  parseMessage
    = let
        loop ::
          CompletionOutputChunk
          -> Data.ProtoLens.Encoding.Bytes.Parser CompletionOutputChunk
        loop x
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t) x)
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "delta"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"delta") y x)
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "logprobs"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"logprobs") y x)
                        24
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.toEnum
                                          (Prelude.fmap
                                             Prelude.fromIntegral
                                             Data.ProtoLens.Encoding.Bytes.getVarInt))
                                       "finish_reason"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"finishReason") y x)
                        32
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "index"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"index") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "CompletionOutputChunk"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (case
                  Lens.Family2.view (Data.ProtoLens.Field.field @"maybe'delta") _x
              of
                Prelude.Nothing -> Data.Monoid.mempty
                (Prelude.Just _v)
                  -> (Data.Monoid.<>)
                       (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                       ((Prelude..)
                          (\ bs
                             -> (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                     (Prelude.fromIntegral (Data.ByteString.length bs)))
                                  (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                          Data.ProtoLens.encodeMessage _v))
             ((Data.Monoid.<>)
                (case
                     Lens.Family2.view (Data.ProtoLens.Field.field @"maybe'logprobs") _x
                 of
                   Prelude.Nothing -> Data.Monoid.mempty
                   (Prelude.Just _v)
                     -> (Data.Monoid.<>)
                          (Data.ProtoLens.Encoding.Bytes.putVarInt 18)
                          ((Prelude..)
                             (\ bs
                                -> (Data.Monoid.<>)
                                     (Data.ProtoLens.Encoding.Bytes.putVarInt
                                        (Prelude.fromIntegral (Data.ByteString.length bs)))
                                     (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                             Data.ProtoLens.encodeMessage _v))
                ((Data.Monoid.<>)
                   (let
                      _v
                        = Lens.Family2.view (Data.ProtoLens.Field.field @"finishReason") _x
                    in
                      if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                          Data.Monoid.mempty
                      else
                          (Data.Monoid.<>)
                            (Data.ProtoLens.Encoding.Bytes.putVarInt 24)
                            ((Prelude..)
                               ((Prelude..)
                                  Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral)
                               Prelude.fromEnum _v))
                   ((Data.Monoid.<>)
                      (let
                         _v = Lens.Family2.view (Data.ProtoLens.Field.field @"index") _x
                       in
                         if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                             Data.Monoid.mempty
                         else
                             (Data.Monoid.<>)
                               (Data.ProtoLens.Encoding.Bytes.putVarInt 32)
                               ((Prelude..)
                                  Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral _v))
                      (Data.ProtoLens.Encoding.Wire.buildFieldSet
                         (Lens.Family2.view Data.ProtoLens.unknownFields _x)))))
instance Control.DeepSeq.NFData CompletionOutputChunk where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_CompletionOutputChunk'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_CompletionOutputChunk'delta x__)
                (Control.DeepSeq.deepseq
                   (_CompletionOutputChunk'logprobs x__)
                   (Control.DeepSeq.deepseq
                      (_CompletionOutputChunk'finishReason x__)
                      (Control.DeepSeq.deepseq (_CompletionOutputChunk'index x__) ()))))
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'content' @:: Lens' Content (Prelude.Maybe Content'Content)@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'text' @:: Lens' Content (Prelude.Maybe Data.Text.Text)@
         * 'Proto.Xai.Api.V1.Chat_Fields.text' @:: Lens' Content Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'imageUrl' @:: Lens' Content (Prelude.Maybe Proto.Xai.Api.V1.Image.ImageUrlContent)@
         * 'Proto.Xai.Api.V1.Chat_Fields.imageUrl' @:: Lens' Content Proto.Xai.Api.V1.Image.ImageUrlContent@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'file' @:: Lens' Content (Prelude.Maybe FileContent)@
         * 'Proto.Xai.Api.V1.Chat_Fields.file' @:: Lens' Content FileContent@ -}
data Content
  = Content'_constructor {_Content'content :: !(Prelude.Maybe Content'Content),
                          _Content'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show Content where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
data Content'Content
  = Content'Text !Data.Text.Text |
    Content'ImageUrl !Proto.Xai.Api.V1.Image.ImageUrlContent |
    Content'File !FileContent
  deriving stock (Prelude.Show, Prelude.Eq, Prelude.Ord)
instance Data.ProtoLens.Field.HasField Content "maybe'content" (Prelude.Maybe Content'Content) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Content'content (\ x__ y__ -> x__ {_Content'content = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField Content "maybe'text" (Prelude.Maybe Data.Text.Text) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Content'content (\ x__ y__ -> x__ {_Content'content = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (Content'Text x__val)) -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap Content'Text y__))
instance Data.ProtoLens.Field.HasField Content "text" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Content'content (\ x__ y__ -> x__ {_Content'content = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (Content'Text x__val)) -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap Content'Text y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault))
instance Data.ProtoLens.Field.HasField Content "maybe'imageUrl" (Prelude.Maybe Proto.Xai.Api.V1.Image.ImageUrlContent) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Content'content (\ x__ y__ -> x__ {_Content'content = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (Content'ImageUrl x__val)) -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap Content'ImageUrl y__))
instance Data.ProtoLens.Field.HasField Content "imageUrl" Proto.Xai.Api.V1.Image.ImageUrlContent where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Content'content (\ x__ y__ -> x__ {_Content'content = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (Content'ImageUrl x__val)) -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap Content'ImageUrl y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Field.HasField Content "maybe'file" (Prelude.Maybe FileContent) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Content'content (\ x__ y__ -> x__ {_Content'content = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (Content'File x__val)) -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap Content'File y__))
instance Data.ProtoLens.Field.HasField Content "file" FileContent where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Content'content (\ x__ y__ -> x__ {_Content'content = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (Content'File x__val)) -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap Content'File y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Message Content where
  messageName _ = Data.Text.pack "xai_api.Content"
  packedMessageDescriptor _
    = "\n\
      \\aContent\DC2\DC4\n\
      \\EOTtext\CAN\SOH \SOH(\tH\NULR\EOTtext\DC27\n\
      \\timage_url\CAN\STX \SOH(\v2\CAN.xai_api.ImageUrlContentH\NULR\bimageUrl\DC2*\n\
      \\EOTfile\CAN\ETX \SOH(\v2\DC4.xai_api.FileContentH\NULR\EOTfileB\t\n\
      \\acontent"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        text__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "text"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'text")) ::
              Data.ProtoLens.FieldDescriptor Content
        imageUrl__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "image_url"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor Proto.Xai.Api.V1.Image.ImageUrlContent)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'imageUrl")) ::
              Data.ProtoLens.FieldDescriptor Content
        file__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "file"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor FileContent)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'file")) ::
              Data.ProtoLens.FieldDescriptor Content
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, text__field_descriptor),
           (Data.ProtoLens.Tag 2, imageUrl__field_descriptor),
           (Data.ProtoLens.Tag 3, file__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _Content'_unknownFields
        (\ x__ y__ -> x__ {_Content'_unknownFields = y__})
  defMessage
    = Content'_constructor
        {_Content'content = Prelude.Nothing, _Content'_unknownFields = []}
  parseMessage
    = let
        loop :: Content -> Data.ProtoLens.Encoding.Bytes.Parser Content
        loop x
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t) x)
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "text"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"text") y x)
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "image_url"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"imageUrl") y x)
                        26
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "file"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"file") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "Content"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (case
                  Lens.Family2.view (Data.ProtoLens.Field.field @"maybe'content") _x
              of
                Prelude.Nothing -> Data.Monoid.mempty
                (Prelude.Just (Content'Text v))
                  -> (Data.Monoid.<>)
                       (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                       ((Prelude..)
                          (\ bs
                             -> (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                     (Prelude.fromIntegral (Data.ByteString.length bs)))
                                  (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                          Data.Text.Encoding.encodeUtf8 v)
                (Prelude.Just (Content'ImageUrl v))
                  -> (Data.Monoid.<>)
                       (Data.ProtoLens.Encoding.Bytes.putVarInt 18)
                       ((Prelude..)
                          (\ bs
                             -> (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                     (Prelude.fromIntegral (Data.ByteString.length bs)))
                                  (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                          Data.ProtoLens.encodeMessage v)
                (Prelude.Just (Content'File v))
                  -> (Data.Monoid.<>)
                       (Data.ProtoLens.Encoding.Bytes.putVarInt 26)
                       ((Prelude..)
                          (\ bs
                             -> (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                     (Prelude.fromIntegral (Data.ByteString.length bs)))
                                  (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                          Data.ProtoLens.encodeMessage v))
             (Data.ProtoLens.Encoding.Wire.buildFieldSet
                (Lens.Family2.view Data.ProtoLens.unknownFields _x))
instance Control.DeepSeq.NFData Content where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_Content'_unknownFields x__)
             (Control.DeepSeq.deepseq (_Content'content x__) ())
instance Control.DeepSeq.NFData Content'Content where
  rnf (Content'Text x__) = Control.DeepSeq.rnf x__
  rnf (Content'ImageUrl x__) = Control.DeepSeq.rnf x__
  rnf (Content'File x__) = Control.DeepSeq.rnf x__
_Content'Text ::
  Data.ProtoLens.Prism.Prism' Content'Content Data.Text.Text
_Content'Text
  = Data.ProtoLens.Prism.prism'
      Content'Text
      (\ p__
         -> case p__ of
              (Content'Text p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
_Content'ImageUrl ::
  Data.ProtoLens.Prism.Prism' Content'Content Proto.Xai.Api.V1.Image.ImageUrlContent
_Content'ImageUrl
  = Data.ProtoLens.Prism.prism'
      Content'ImageUrl
      (\ p__
         -> case p__ of
              (Content'ImageUrl p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
_Content'File ::
  Data.ProtoLens.Prism.Prism' Content'Content FileContent
_Content'File
  = Data.ProtoLens.Prism.prism'
      Content'File
      (\ p__
         -> case p__ of
              (Content'File p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Chat_Fields.attempts' @:: Lens' DebugOutput Data.Int.Int32@
         * 'Proto.Xai.Api.V1.Chat_Fields.request' @:: Lens' DebugOutput Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.prompt' @:: Lens' DebugOutput Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.engineRequest' @:: Lens' DebugOutput Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.responses' @:: Lens' DebugOutput [Data.Text.Text]@
         * 'Proto.Xai.Api.V1.Chat_Fields.vec'responses' @:: Lens' DebugOutput (Data.Vector.Vector Data.Text.Text)@
         * 'Proto.Xai.Api.V1.Chat_Fields.chunks' @:: Lens' DebugOutput [Data.Text.Text]@
         * 'Proto.Xai.Api.V1.Chat_Fields.vec'chunks' @:: Lens' DebugOutput (Data.Vector.Vector Data.Text.Text)@
         * 'Proto.Xai.Api.V1.Chat_Fields.cacheReadCount' @:: Lens' DebugOutput Data.Word.Word32@
         * 'Proto.Xai.Api.V1.Chat_Fields.cacheReadInputBytes' @:: Lens' DebugOutput Data.Word.Word64@
         * 'Proto.Xai.Api.V1.Chat_Fields.cacheWriteCount' @:: Lens' DebugOutput Data.Word.Word32@
         * 'Proto.Xai.Api.V1.Chat_Fields.cacheWriteInputBytes' @:: Lens' DebugOutput Data.Word.Word64@
         * 'Proto.Xai.Api.V1.Chat_Fields.lbAddress' @:: Lens' DebugOutput Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.samplerTag' @:: Lens' DebugOutput Data.Text.Text@ -}
data DebugOutput
  = DebugOutput'_constructor {_DebugOutput'attempts :: !Data.Int.Int32,
                              _DebugOutput'request :: !Data.Text.Text,
                              _DebugOutput'prompt :: !Data.Text.Text,
                              _DebugOutput'engineRequest :: !Data.Text.Text,
                              _DebugOutput'responses :: !(Data.Vector.Vector Data.Text.Text),
                              _DebugOutput'chunks :: !(Data.Vector.Vector Data.Text.Text),
                              _DebugOutput'cacheReadCount :: !Data.Word.Word32,
                              _DebugOutput'cacheReadInputBytes :: !Data.Word.Word64,
                              _DebugOutput'cacheWriteCount :: !Data.Word.Word32,
                              _DebugOutput'cacheWriteInputBytes :: !Data.Word.Word64,
                              _DebugOutput'lbAddress :: !Data.Text.Text,
                              _DebugOutput'samplerTag :: !Data.Text.Text,
                              _DebugOutput'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show DebugOutput where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField DebugOutput "attempts" Data.Int.Int32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _DebugOutput'attempts
           (\ x__ y__ -> x__ {_DebugOutput'attempts = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField DebugOutput "request" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _DebugOutput'request
           (\ x__ y__ -> x__ {_DebugOutput'request = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField DebugOutput "prompt" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _DebugOutput'prompt (\ x__ y__ -> x__ {_DebugOutput'prompt = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField DebugOutput "engineRequest" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _DebugOutput'engineRequest
           (\ x__ y__ -> x__ {_DebugOutput'engineRequest = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField DebugOutput "responses" [Data.Text.Text] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _DebugOutput'responses
           (\ x__ y__ -> x__ {_DebugOutput'responses = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField DebugOutput "vec'responses" (Data.Vector.Vector Data.Text.Text) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _DebugOutput'responses
           (\ x__ y__ -> x__ {_DebugOutput'responses = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField DebugOutput "chunks" [Data.Text.Text] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _DebugOutput'chunks (\ x__ y__ -> x__ {_DebugOutput'chunks = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField DebugOutput "vec'chunks" (Data.Vector.Vector Data.Text.Text) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _DebugOutput'chunks (\ x__ y__ -> x__ {_DebugOutput'chunks = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField DebugOutput "cacheReadCount" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _DebugOutput'cacheReadCount
           (\ x__ y__ -> x__ {_DebugOutput'cacheReadCount = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField DebugOutput "cacheReadInputBytes" Data.Word.Word64 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _DebugOutput'cacheReadInputBytes
           (\ x__ y__ -> x__ {_DebugOutput'cacheReadInputBytes = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField DebugOutput "cacheWriteCount" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _DebugOutput'cacheWriteCount
           (\ x__ y__ -> x__ {_DebugOutput'cacheWriteCount = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField DebugOutput "cacheWriteInputBytes" Data.Word.Word64 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _DebugOutput'cacheWriteInputBytes
           (\ x__ y__ -> x__ {_DebugOutput'cacheWriteInputBytes = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField DebugOutput "lbAddress" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _DebugOutput'lbAddress
           (\ x__ y__ -> x__ {_DebugOutput'lbAddress = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField DebugOutput "samplerTag" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _DebugOutput'samplerTag
           (\ x__ y__ -> x__ {_DebugOutput'samplerTag = y__}))
        Prelude.id
instance Data.ProtoLens.Message DebugOutput where
  messageName _ = Data.Text.pack "xai_api.DebugOutput"
  packedMessageDescriptor _
    = "\n\
      \\vDebugOutput\DC2\SUB\n\
      \\battempts\CAN\SOH \SOH(\ENQR\battempts\DC2\CAN\n\
      \\arequest\CAN\STX \SOH(\tR\arequest\DC2\SYN\n\
      \\ACKprompt\CAN\ETX \SOH(\tR\ACKprompt\DC2%\n\
      \\SOengine_request\CAN\t \SOH(\tR\rengineRequest\DC2\FS\n\
      \\tresponses\CAN\EOT \ETX(\tR\tresponses\DC2\SYN\n\
      \\ACKchunks\CAN\f \ETX(\tR\ACKchunks\DC2(\n\
      \\DLEcache_read_count\CAN\ENQ \SOH(\rR\SOcacheReadCount\DC23\n\
      \\SYNcache_read_input_bytes\CAN\ACK \SOH(\EOTR\DC3cacheReadInputBytes\DC2*\n\
      \\DC1cache_write_count\CAN\a \SOH(\rR\SIcacheWriteCount\DC25\n\
      \\ETBcache_write_input_bytes\CAN\b \SOH(\EOTR\DC4cacheWriteInputBytes\DC2\GS\n\
      \\n\
      \lb_address\CAN\n\
      \ \SOH(\tR\tlbAddress\DC2\US\n\
      \\vsampler_tag\CAN\v \SOH(\tR\n\
      \samplerTag"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        attempts__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "attempts"
              (Data.ProtoLens.ScalarField Data.ProtoLens.Int32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Int.Int32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"attempts")) ::
              Data.ProtoLens.FieldDescriptor DebugOutput
        request__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "request"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"request")) ::
              Data.ProtoLens.FieldDescriptor DebugOutput
        prompt__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "prompt"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"prompt")) ::
              Data.ProtoLens.FieldDescriptor DebugOutput
        engineRequest__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "engine_request"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"engineRequest")) ::
              Data.ProtoLens.FieldDescriptor DebugOutput
        responses__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "responses"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Unpacked
                 (Data.ProtoLens.Field.field @"responses")) ::
              Data.ProtoLens.FieldDescriptor DebugOutput
        chunks__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "chunks"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Unpacked (Data.ProtoLens.Field.field @"chunks")) ::
              Data.ProtoLens.FieldDescriptor DebugOutput
        cacheReadCount__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "cache_read_count"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"cacheReadCount")) ::
              Data.ProtoLens.FieldDescriptor DebugOutput
        cacheReadInputBytes__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "cache_read_input_bytes"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt64Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word64)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"cacheReadInputBytes")) ::
              Data.ProtoLens.FieldDescriptor DebugOutput
        cacheWriteCount__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "cache_write_count"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"cacheWriteCount")) ::
              Data.ProtoLens.FieldDescriptor DebugOutput
        cacheWriteInputBytes__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "cache_write_input_bytes"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt64Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word64)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"cacheWriteInputBytes")) ::
              Data.ProtoLens.FieldDescriptor DebugOutput
        lbAddress__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "lb_address"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"lbAddress")) ::
              Data.ProtoLens.FieldDescriptor DebugOutput
        samplerTag__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "sampler_tag"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"samplerTag")) ::
              Data.ProtoLens.FieldDescriptor DebugOutput
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, attempts__field_descriptor),
           (Data.ProtoLens.Tag 2, request__field_descriptor),
           (Data.ProtoLens.Tag 3, prompt__field_descriptor),
           (Data.ProtoLens.Tag 9, engineRequest__field_descriptor),
           (Data.ProtoLens.Tag 4, responses__field_descriptor),
           (Data.ProtoLens.Tag 12, chunks__field_descriptor),
           (Data.ProtoLens.Tag 5, cacheReadCount__field_descriptor),
           (Data.ProtoLens.Tag 6, cacheReadInputBytes__field_descriptor),
           (Data.ProtoLens.Tag 7, cacheWriteCount__field_descriptor),
           (Data.ProtoLens.Tag 8, cacheWriteInputBytes__field_descriptor),
           (Data.ProtoLens.Tag 10, lbAddress__field_descriptor),
           (Data.ProtoLens.Tag 11, samplerTag__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _DebugOutput'_unknownFields
        (\ x__ y__ -> x__ {_DebugOutput'_unknownFields = y__})
  defMessage
    = DebugOutput'_constructor
        {_DebugOutput'attempts = Data.ProtoLens.fieldDefault,
         _DebugOutput'request = Data.ProtoLens.fieldDefault,
         _DebugOutput'prompt = Data.ProtoLens.fieldDefault,
         _DebugOutput'engineRequest = Data.ProtoLens.fieldDefault,
         _DebugOutput'responses = Data.Vector.Generic.empty,
         _DebugOutput'chunks = Data.Vector.Generic.empty,
         _DebugOutput'cacheReadCount = Data.ProtoLens.fieldDefault,
         _DebugOutput'cacheReadInputBytes = Data.ProtoLens.fieldDefault,
         _DebugOutput'cacheWriteCount = Data.ProtoLens.fieldDefault,
         _DebugOutput'cacheWriteInputBytes = Data.ProtoLens.fieldDefault,
         _DebugOutput'lbAddress = Data.ProtoLens.fieldDefault,
         _DebugOutput'samplerTag = Data.ProtoLens.fieldDefault,
         _DebugOutput'_unknownFields = []}
  parseMessage
    = let
        loop ::
          DebugOutput
          -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Vector Data.ProtoLens.Encoding.Growing.RealWorld Data.Text.Text
             -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Vector Data.ProtoLens.Encoding.Growing.RealWorld Data.Text.Text
                -> Data.ProtoLens.Encoding.Bytes.Parser DebugOutput
        loop x mutable'chunks mutable'responses
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do frozen'chunks <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                         (Data.ProtoLens.Encoding.Growing.unsafeFreeze
                                            mutable'chunks)
                      frozen'responses <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                            (Data.ProtoLens.Encoding.Growing.unsafeFreeze
                                               mutable'responses)
                      (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t)
                           (Lens.Family2.set
                              (Data.ProtoLens.Field.field @"vec'chunks") frozen'chunks
                              (Lens.Family2.set
                                 (Data.ProtoLens.Field.field @"vec'responses") frozen'responses x)))
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        8 -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "attempts"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"attempts") y x)
                                  mutable'chunks mutable'responses
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "request"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"request") y x)
                                  mutable'chunks mutable'responses
                        26
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "prompt"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"prompt") y x)
                                  mutable'chunks mutable'responses
                        74
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "engine_request"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"engineRequest") y x)
                                  mutable'chunks mutable'responses
                        34
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                            Data.ProtoLens.Encoding.Bytes.getText
                                              (Prelude.fromIntegral len))
                                        "responses"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append mutable'responses y)
                                loop x mutable'chunks v
                        98
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                            Data.ProtoLens.Encoding.Bytes.getText
                                              (Prelude.fromIntegral len))
                                        "chunks"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append mutable'chunks y)
                                loop x v mutable'responses
                        40
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "cache_read_count"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"cacheReadCount") y x)
                                  mutable'chunks mutable'responses
                        48
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       Data.ProtoLens.Encoding.Bytes.getVarInt
                                       "cache_read_input_bytes"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"cacheReadInputBytes") y x)
                                  mutable'chunks mutable'responses
                        56
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "cache_write_count"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"cacheWriteCount") y x)
                                  mutable'chunks mutable'responses
                        64
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       Data.ProtoLens.Encoding.Bytes.getVarInt
                                       "cache_write_input_bytes"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"cacheWriteInputBytes") y x)
                                  mutable'chunks mutable'responses
                        82
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "lb_address"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"lbAddress") y x)
                                  mutable'chunks mutable'responses
                        90
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "sampler_tag"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"samplerTag") y x)
                                  mutable'chunks mutable'responses
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
                                  mutable'chunks mutable'responses
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do mutable'chunks <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                  Data.ProtoLens.Encoding.Growing.new
              mutable'responses <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                     Data.ProtoLens.Encoding.Growing.new
              loop Data.ProtoLens.defMessage mutable'chunks mutable'responses)
          "DebugOutput"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v = Lens.Family2.view (Data.ProtoLens.Field.field @"attempts") _x
              in
                if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 8)
                      ((Prelude..)
                         Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral _v))
             ((Data.Monoid.<>)
                (let
                   _v = Lens.Family2.view (Data.ProtoLens.Field.field @"request") _x
                 in
                   if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                       Data.Monoid.mempty
                   else
                       (Data.Monoid.<>)
                         (Data.ProtoLens.Encoding.Bytes.putVarInt 18)
                         ((Prelude..)
                            (\ bs
                               -> (Data.Monoid.<>)
                                    (Data.ProtoLens.Encoding.Bytes.putVarInt
                                       (Prelude.fromIntegral (Data.ByteString.length bs)))
                                    (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                            Data.Text.Encoding.encodeUtf8 _v))
                ((Data.Monoid.<>)
                   (let
                      _v = Lens.Family2.view (Data.ProtoLens.Field.field @"prompt") _x
                    in
                      if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                          Data.Monoid.mempty
                      else
                          (Data.Monoid.<>)
                            (Data.ProtoLens.Encoding.Bytes.putVarInt 26)
                            ((Prelude..)
                               (\ bs
                                  -> (Data.Monoid.<>)
                                       (Data.ProtoLens.Encoding.Bytes.putVarInt
                                          (Prelude.fromIntegral (Data.ByteString.length bs)))
                                       (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                               Data.Text.Encoding.encodeUtf8 _v))
                   ((Data.Monoid.<>)
                      (let
                         _v
                           = Lens.Family2.view
                               (Data.ProtoLens.Field.field @"engineRequest") _x
                       in
                         if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                             Data.Monoid.mempty
                         else
                             (Data.Monoid.<>)
                               (Data.ProtoLens.Encoding.Bytes.putVarInt 74)
                               ((Prelude..)
                                  (\ bs
                                     -> (Data.Monoid.<>)
                                          (Data.ProtoLens.Encoding.Bytes.putVarInt
                                             (Prelude.fromIntegral (Data.ByteString.length bs)))
                                          (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                  Data.Text.Encoding.encodeUtf8 _v))
                      ((Data.Monoid.<>)
                         (Data.ProtoLens.Encoding.Bytes.foldMapBuilder
                            (\ _v
                               -> (Data.Monoid.<>)
                                    (Data.ProtoLens.Encoding.Bytes.putVarInt 34)
                                    ((Prelude..)
                                       (\ bs
                                          -> (Data.Monoid.<>)
                                               (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                  (Prelude.fromIntegral
                                                     (Data.ByteString.length bs)))
                                               (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                       Data.Text.Encoding.encodeUtf8 _v))
                            (Lens.Family2.view
                               (Data.ProtoLens.Field.field @"vec'responses") _x))
                         ((Data.Monoid.<>)
                            (Data.ProtoLens.Encoding.Bytes.foldMapBuilder
                               (\ _v
                                  -> (Data.Monoid.<>)
                                       (Data.ProtoLens.Encoding.Bytes.putVarInt 98)
                                       ((Prelude..)
                                          (\ bs
                                             -> (Data.Monoid.<>)
                                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                     (Prelude.fromIntegral
                                                        (Data.ByteString.length bs)))
                                                  (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                          Data.Text.Encoding.encodeUtf8 _v))
                               (Lens.Family2.view (Data.ProtoLens.Field.field @"vec'chunks") _x))
                            ((Data.Monoid.<>)
                               (let
                                  _v
                                    = Lens.Family2.view
                                        (Data.ProtoLens.Field.field @"cacheReadCount") _x
                                in
                                  if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                      Data.Monoid.mempty
                                  else
                                      (Data.Monoid.<>)
                                        (Data.ProtoLens.Encoding.Bytes.putVarInt 40)
                                        ((Prelude..)
                                           Data.ProtoLens.Encoding.Bytes.putVarInt
                                           Prelude.fromIntegral _v))
                               ((Data.Monoid.<>)
                                  (let
                                     _v
                                       = Lens.Family2.view
                                           (Data.ProtoLens.Field.field @"cacheReadInputBytes") _x
                                   in
                                     if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                         Data.Monoid.mempty
                                     else
                                         (Data.Monoid.<>)
                                           (Data.ProtoLens.Encoding.Bytes.putVarInt 48)
                                           (Data.ProtoLens.Encoding.Bytes.putVarInt _v))
                                  ((Data.Monoid.<>)
                                     (let
                                        _v
                                          = Lens.Family2.view
                                              (Data.ProtoLens.Field.field @"cacheWriteCount") _x
                                      in
                                        if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                            Data.Monoid.mempty
                                        else
                                            (Data.Monoid.<>)
                                              (Data.ProtoLens.Encoding.Bytes.putVarInt 56)
                                              ((Prelude..)
                                                 Data.ProtoLens.Encoding.Bytes.putVarInt
                                                 Prelude.fromIntegral _v))
                                     ((Data.Monoid.<>)
                                        (let
                                           _v
                                             = Lens.Family2.view
                                                 (Data.ProtoLens.Field.field
                                                    @"cacheWriteInputBytes")
                                                 _x
                                         in
                                           if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                               Data.Monoid.mempty
                                           else
                                               (Data.Monoid.<>)
                                                 (Data.ProtoLens.Encoding.Bytes.putVarInt 64)
                                                 (Data.ProtoLens.Encoding.Bytes.putVarInt _v))
                                        ((Data.Monoid.<>)
                                           (let
                                              _v
                                                = Lens.Family2.view
                                                    (Data.ProtoLens.Field.field @"lbAddress") _x
                                            in
                                              if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                                  Data.Monoid.mempty
                                              else
                                                  (Data.Monoid.<>)
                                                    (Data.ProtoLens.Encoding.Bytes.putVarInt 82)
                                                    ((Prelude..)
                                                       (\ bs
                                                          -> (Data.Monoid.<>)
                                                               (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                  (Prelude.fromIntegral
                                                                     (Data.ByteString.length bs)))
                                                               (Data.ProtoLens.Encoding.Bytes.putBytes
                                                                  bs))
                                                       Data.Text.Encoding.encodeUtf8 _v))
                                           ((Data.Monoid.<>)
                                              (let
                                                 _v
                                                   = Lens.Family2.view
                                                       (Data.ProtoLens.Field.field @"samplerTag") _x
                                               in
                                                 if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                                     Data.Monoid.mempty
                                                 else
                                                     (Data.Monoid.<>)
                                                       (Data.ProtoLens.Encoding.Bytes.putVarInt 90)
                                                       ((Prelude..)
                                                          (\ bs
                                                             -> (Data.Monoid.<>)
                                                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                     (Prelude.fromIntegral
                                                                        (Data.ByteString.length
                                                                           bs)))
                                                                  (Data.ProtoLens.Encoding.Bytes.putBytes
                                                                     bs))
                                                          Data.Text.Encoding.encodeUtf8 _v))
                                              (Data.ProtoLens.Encoding.Wire.buildFieldSet
                                                 (Lens.Family2.view
                                                    Data.ProtoLens.unknownFields _x)))))))))))))
instance Control.DeepSeq.NFData DebugOutput where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_DebugOutput'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_DebugOutput'attempts x__)
                (Control.DeepSeq.deepseq
                   (_DebugOutput'request x__)
                   (Control.DeepSeq.deepseq
                      (_DebugOutput'prompt x__)
                      (Control.DeepSeq.deepseq
                         (_DebugOutput'engineRequest x__)
                         (Control.DeepSeq.deepseq
                            (_DebugOutput'responses x__)
                            (Control.DeepSeq.deepseq
                               (_DebugOutput'chunks x__)
                               (Control.DeepSeq.deepseq
                                  (_DebugOutput'cacheReadCount x__)
                                  (Control.DeepSeq.deepseq
                                     (_DebugOutput'cacheReadInputBytes x__)
                                     (Control.DeepSeq.deepseq
                                        (_DebugOutput'cacheWriteCount x__)
                                        (Control.DeepSeq.deepseq
                                           (_DebugOutput'cacheWriteInputBytes x__)
                                           (Control.DeepSeq.deepseq
                                              (_DebugOutput'lbAddress x__)
                                              (Control.DeepSeq.deepseq
                                                 (_DebugOutput'samplerTag x__) ()))))))))))))
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Chat_Fields.responseId' @:: Lens' DeleteStoredCompletionRequest Data.Text.Text@ -}
data DeleteStoredCompletionRequest
  = DeleteStoredCompletionRequest'_constructor {_DeleteStoredCompletionRequest'responseId :: !Data.Text.Text,
                                                _DeleteStoredCompletionRequest'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show DeleteStoredCompletionRequest where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField DeleteStoredCompletionRequest "responseId" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _DeleteStoredCompletionRequest'responseId
           (\ x__ y__
              -> x__ {_DeleteStoredCompletionRequest'responseId = y__}))
        Prelude.id
instance Data.ProtoLens.Message DeleteStoredCompletionRequest where
  messageName _
    = Data.Text.pack "xai_api.DeleteStoredCompletionRequest"
  packedMessageDescriptor _
    = "\n\
      \\GSDeleteStoredCompletionRequest\DC2\US\n\
      \\vresponse_id\CAN\SOH \SOH(\tR\n\
      \responseId"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        responseId__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "response_id"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"responseId")) ::
              Data.ProtoLens.FieldDescriptor DeleteStoredCompletionRequest
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, responseId__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _DeleteStoredCompletionRequest'_unknownFields
        (\ x__ y__
           -> x__ {_DeleteStoredCompletionRequest'_unknownFields = y__})
  defMessage
    = DeleteStoredCompletionRequest'_constructor
        {_DeleteStoredCompletionRequest'responseId = Data.ProtoLens.fieldDefault,
         _DeleteStoredCompletionRequest'_unknownFields = []}
  parseMessage
    = let
        loop ::
          DeleteStoredCompletionRequest
          -> Data.ProtoLens.Encoding.Bytes.Parser DeleteStoredCompletionRequest
        loop x
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t) x)
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "response_id"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"responseId") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "DeleteStoredCompletionRequest"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v
                  = Lens.Family2.view (Data.ProtoLens.Field.field @"responseId") _x
              in
                if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                      ((Prelude..)
                         (\ bs
                            -> (Data.Monoid.<>)
                                 (Data.ProtoLens.Encoding.Bytes.putVarInt
                                    (Prelude.fromIntegral (Data.ByteString.length bs)))
                                 (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                         Data.Text.Encoding.encodeUtf8 _v))
             (Data.ProtoLens.Encoding.Wire.buildFieldSet
                (Lens.Family2.view Data.ProtoLens.unknownFields _x))
instance Control.DeepSeq.NFData DeleteStoredCompletionRequest where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_DeleteStoredCompletionRequest'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_DeleteStoredCompletionRequest'responseId x__) ())
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Chat_Fields.responseId' @:: Lens' DeleteStoredCompletionResponse Data.Text.Text@ -}
data DeleteStoredCompletionResponse
  = DeleteStoredCompletionResponse'_constructor {_DeleteStoredCompletionResponse'responseId :: !Data.Text.Text,
                                                 _DeleteStoredCompletionResponse'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show DeleteStoredCompletionResponse where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField DeleteStoredCompletionResponse "responseId" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _DeleteStoredCompletionResponse'responseId
           (\ x__ y__
              -> x__ {_DeleteStoredCompletionResponse'responseId = y__}))
        Prelude.id
instance Data.ProtoLens.Message DeleteStoredCompletionResponse where
  messageName _
    = Data.Text.pack "xai_api.DeleteStoredCompletionResponse"
  packedMessageDescriptor _
    = "\n\
      \\RSDeleteStoredCompletionResponse\DC2\US\n\
      \\vresponse_id\CAN\SOH \SOH(\tR\n\
      \responseId"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        responseId__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "response_id"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"responseId")) ::
              Data.ProtoLens.FieldDescriptor DeleteStoredCompletionResponse
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, responseId__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _DeleteStoredCompletionResponse'_unknownFields
        (\ x__ y__
           -> x__ {_DeleteStoredCompletionResponse'_unknownFields = y__})
  defMessage
    = DeleteStoredCompletionResponse'_constructor
        {_DeleteStoredCompletionResponse'responseId = Data.ProtoLens.fieldDefault,
         _DeleteStoredCompletionResponse'_unknownFields = []}
  parseMessage
    = let
        loop ::
          DeleteStoredCompletionResponse
          -> Data.ProtoLens.Encoding.Bytes.Parser DeleteStoredCompletionResponse
        loop x
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t) x)
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "response_id"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"responseId") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage)
          "DeleteStoredCompletionResponse"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v
                  = Lens.Family2.view (Data.ProtoLens.Field.field @"responseId") _x
              in
                if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                      ((Prelude..)
                         (\ bs
                            -> (Data.Monoid.<>)
                                 (Data.ProtoLens.Encoding.Bytes.putVarInt
                                    (Prelude.fromIntegral (Data.ByteString.length bs)))
                                 (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                         Data.Text.Encoding.encodeUtf8 _v))
             (Data.ProtoLens.Encoding.Wire.buildFieldSet
                (Lens.Family2.view Data.ProtoLens.unknownFields _x))
instance Control.DeepSeq.NFData DeleteStoredCompletionResponse where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_DeleteStoredCompletionResponse'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_DeleteStoredCompletionResponse'responseId x__) ())
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Chat_Fields.content' @:: Lens' Delta Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.reasoningContent' @:: Lens' Delta Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.role' @:: Lens' Delta MessageRole@
         * 'Proto.Xai.Api.V1.Chat_Fields.toolCalls' @:: Lens' Delta [ToolCall]@
         * 'Proto.Xai.Api.V1.Chat_Fields.vec'toolCalls' @:: Lens' Delta (Data.Vector.Vector ToolCall)@
         * 'Proto.Xai.Api.V1.Chat_Fields.encryptedContent' @:: Lens' Delta Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.citations' @:: Lens' Delta [InlineCitation]@
         * 'Proto.Xai.Api.V1.Chat_Fields.vec'citations' @:: Lens' Delta (Data.Vector.Vector InlineCitation)@ -}
data Delta
  = Delta'_constructor {_Delta'content :: !Data.Text.Text,
                        _Delta'reasoningContent :: !Data.Text.Text,
                        _Delta'role :: !MessageRole,
                        _Delta'toolCalls :: !(Data.Vector.Vector ToolCall),
                        _Delta'encryptedContent :: !Data.Text.Text,
                        _Delta'citations :: !(Data.Vector.Vector InlineCitation),
                        _Delta'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show Delta where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField Delta "content" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Delta'content (\ x__ y__ -> x__ {_Delta'content = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField Delta "reasoningContent" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Delta'reasoningContent
           (\ x__ y__ -> x__ {_Delta'reasoningContent = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField Delta "role" MessageRole where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Delta'role (\ x__ y__ -> x__ {_Delta'role = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField Delta "toolCalls" [ToolCall] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Delta'toolCalls (\ x__ y__ -> x__ {_Delta'toolCalls = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField Delta "vec'toolCalls" (Data.Vector.Vector ToolCall) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Delta'toolCalls (\ x__ y__ -> x__ {_Delta'toolCalls = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField Delta "encryptedContent" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Delta'encryptedContent
           (\ x__ y__ -> x__ {_Delta'encryptedContent = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField Delta "citations" [InlineCitation] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Delta'citations (\ x__ y__ -> x__ {_Delta'citations = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField Delta "vec'citations" (Data.Vector.Vector InlineCitation) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Delta'citations (\ x__ y__ -> x__ {_Delta'citations = y__}))
        Prelude.id
instance Data.ProtoLens.Message Delta where
  messageName _ = Data.Text.pack "xai_api.Delta"
  packedMessageDescriptor _
    = "\n\
      \\ENQDelta\DC2\CAN\n\
      \\acontent\CAN\SOH \SOH(\tR\acontent\DC2+\n\
      \\DC1reasoning_content\CAN\EOT \SOH(\tR\DLEreasoningContent\DC2(\n\
      \\EOTrole\CAN\STX \SOH(\SO2\DC4.xai_api.MessageRoleR\EOTrole\DC20\n\
      \\n\
      \tool_calls\CAN\ETX \ETX(\v2\DC1.xai_api.ToolCallR\ttoolCalls\DC2+\n\
      \\DC1encrypted_content\CAN\ENQ \SOH(\tR\DLEencryptedContent\DC25\n\
      \\tcitations\CAN\ACK \ETX(\v2\ETB.xai_api.InlineCitationR\tcitations"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        content__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "content"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"content")) ::
              Data.ProtoLens.FieldDescriptor Delta
        reasoningContent__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "reasoning_content"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"reasoningContent")) ::
              Data.ProtoLens.FieldDescriptor Delta
        role__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "role"
              (Data.ProtoLens.ScalarField Data.ProtoLens.EnumField ::
                 Data.ProtoLens.FieldTypeDescriptor MessageRole)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"role")) ::
              Data.ProtoLens.FieldDescriptor Delta
        toolCalls__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "tool_calls"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor ToolCall)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Unpacked
                 (Data.ProtoLens.Field.field @"toolCalls")) ::
              Data.ProtoLens.FieldDescriptor Delta
        encryptedContent__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "encrypted_content"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"encryptedContent")) ::
              Data.ProtoLens.FieldDescriptor Delta
        citations__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "citations"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor InlineCitation)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Unpacked
                 (Data.ProtoLens.Field.field @"citations")) ::
              Data.ProtoLens.FieldDescriptor Delta
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, content__field_descriptor),
           (Data.ProtoLens.Tag 4, reasoningContent__field_descriptor),
           (Data.ProtoLens.Tag 2, role__field_descriptor),
           (Data.ProtoLens.Tag 3, toolCalls__field_descriptor),
           (Data.ProtoLens.Tag 5, encryptedContent__field_descriptor),
           (Data.ProtoLens.Tag 6, citations__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _Delta'_unknownFields
        (\ x__ y__ -> x__ {_Delta'_unknownFields = y__})
  defMessage
    = Delta'_constructor
        {_Delta'content = Data.ProtoLens.fieldDefault,
         _Delta'reasoningContent = Data.ProtoLens.fieldDefault,
         _Delta'role = Data.ProtoLens.fieldDefault,
         _Delta'toolCalls = Data.Vector.Generic.empty,
         _Delta'encryptedContent = Data.ProtoLens.fieldDefault,
         _Delta'citations = Data.Vector.Generic.empty,
         _Delta'_unknownFields = []}
  parseMessage
    = let
        loop ::
          Delta
          -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Vector Data.ProtoLens.Encoding.Growing.RealWorld InlineCitation
             -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Vector Data.ProtoLens.Encoding.Growing.RealWorld ToolCall
                -> Data.ProtoLens.Encoding.Bytes.Parser Delta
        loop x mutable'citations mutable'toolCalls
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do frozen'citations <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                            (Data.ProtoLens.Encoding.Growing.unsafeFreeze
                                               mutable'citations)
                      frozen'toolCalls <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                            (Data.ProtoLens.Encoding.Growing.unsafeFreeze
                                               mutable'toolCalls)
                      (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t)
                           (Lens.Family2.set
                              (Data.ProtoLens.Field.field @"vec'citations") frozen'citations
                              (Lens.Family2.set
                                 (Data.ProtoLens.Field.field @"vec'toolCalls") frozen'toolCalls x)))
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "content"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"content") y x)
                                  mutable'citations mutable'toolCalls
                        34
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "reasoning_content"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"reasoningContent") y x)
                                  mutable'citations mutable'toolCalls
                        16
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.toEnum
                                          (Prelude.fmap
                                             Prelude.fromIntegral
                                             Data.ProtoLens.Encoding.Bytes.getVarInt))
                                       "role"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"role") y x)
                                  mutable'citations mutable'toolCalls
                        26
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                            Data.ProtoLens.Encoding.Bytes.isolate
                                              (Prelude.fromIntegral len)
                                              Data.ProtoLens.parseMessage)
                                        "tool_calls"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append mutable'toolCalls y)
                                loop x mutable'citations v
                        42
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "encrypted_content"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"encryptedContent") y x)
                                  mutable'citations mutable'toolCalls
                        50
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                            Data.ProtoLens.Encoding.Bytes.isolate
                                              (Prelude.fromIntegral len)
                                              Data.ProtoLens.parseMessage)
                                        "citations"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append mutable'citations y)
                                loop x v mutable'toolCalls
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
                                  mutable'citations mutable'toolCalls
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do mutable'citations <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                     Data.ProtoLens.Encoding.Growing.new
              mutable'toolCalls <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                     Data.ProtoLens.Encoding.Growing.new
              loop Data.ProtoLens.defMessage mutable'citations mutable'toolCalls)
          "Delta"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v = Lens.Family2.view (Data.ProtoLens.Field.field @"content") _x
              in
                if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                      ((Prelude..)
                         (\ bs
                            -> (Data.Monoid.<>)
                                 (Data.ProtoLens.Encoding.Bytes.putVarInt
                                    (Prelude.fromIntegral (Data.ByteString.length bs)))
                                 (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                         Data.Text.Encoding.encodeUtf8 _v))
             ((Data.Monoid.<>)
                (let
                   _v
                     = Lens.Family2.view
                         (Data.ProtoLens.Field.field @"reasoningContent") _x
                 in
                   if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                       Data.Monoid.mempty
                   else
                       (Data.Monoid.<>)
                         (Data.ProtoLens.Encoding.Bytes.putVarInt 34)
                         ((Prelude..)
                            (\ bs
                               -> (Data.Monoid.<>)
                                    (Data.ProtoLens.Encoding.Bytes.putVarInt
                                       (Prelude.fromIntegral (Data.ByteString.length bs)))
                                    (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                            Data.Text.Encoding.encodeUtf8 _v))
                ((Data.Monoid.<>)
                   (let _v = Lens.Family2.view (Data.ProtoLens.Field.field @"role") _x
                    in
                      if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                          Data.Monoid.mempty
                      else
                          (Data.Monoid.<>)
                            (Data.ProtoLens.Encoding.Bytes.putVarInt 16)
                            ((Prelude..)
                               ((Prelude..)
                                  Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral)
                               Prelude.fromEnum _v))
                   ((Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.foldMapBuilder
                         (\ _v
                            -> (Data.Monoid.<>)
                                 (Data.ProtoLens.Encoding.Bytes.putVarInt 26)
                                 ((Prelude..)
                                    (\ bs
                                       -> (Data.Monoid.<>)
                                            (Data.ProtoLens.Encoding.Bytes.putVarInt
                                               (Prelude.fromIntegral (Data.ByteString.length bs)))
                                            (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                    Data.ProtoLens.encodeMessage _v))
                         (Lens.Family2.view
                            (Data.ProtoLens.Field.field @"vec'toolCalls") _x))
                      ((Data.Monoid.<>)
                         (let
                            _v
                              = Lens.Family2.view
                                  (Data.ProtoLens.Field.field @"encryptedContent") _x
                          in
                            if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                Data.Monoid.mempty
                            else
                                (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt 42)
                                  ((Prelude..)
                                     (\ bs
                                        -> (Data.Monoid.<>)
                                             (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                (Prelude.fromIntegral (Data.ByteString.length bs)))
                                             (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                     Data.Text.Encoding.encodeUtf8 _v))
                         ((Data.Monoid.<>)
                            (Data.ProtoLens.Encoding.Bytes.foldMapBuilder
                               (\ _v
                                  -> (Data.Monoid.<>)
                                       (Data.ProtoLens.Encoding.Bytes.putVarInt 50)
                                       ((Prelude..)
                                          (\ bs
                                             -> (Data.Monoid.<>)
                                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                     (Prelude.fromIntegral
                                                        (Data.ByteString.length bs)))
                                                  (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                          Data.ProtoLens.encodeMessage _v))
                               (Lens.Family2.view
                                  (Data.ProtoLens.Field.field @"vec'citations") _x))
                            (Data.ProtoLens.Encoding.Wire.buildFieldSet
                               (Lens.Family2.view Data.ProtoLens.unknownFields _x)))))))
instance Control.DeepSeq.NFData Delta where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_Delta'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_Delta'content x__)
                (Control.DeepSeq.deepseq
                   (_Delta'reasoningContent x__)
                   (Control.DeepSeq.deepseq
                      (_Delta'role x__)
                      (Control.DeepSeq.deepseq
                         (_Delta'toolCalls x__)
                         (Control.DeepSeq.deepseq
                            (_Delta'encryptedContent x__)
                            (Control.DeepSeq.deepseq (_Delta'citations x__) ()))))))
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Chat_Fields.fileId' @:: Lens' FileContent Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.data'' @:: Lens' FileContent Data.ByteString.ByteString@
         * 'Proto.Xai.Api.V1.Chat_Fields.filename' @:: Lens' FileContent Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.mimeType' @:: Lens' FileContent Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.url' @:: Lens' FileContent Data.Text.Text@ -}
data FileContent
  = FileContent'_constructor {_FileContent'fileId :: !Data.Text.Text,
                              _FileContent'data' :: !Data.ByteString.ByteString,
                              _FileContent'filename :: !Data.Text.Text,
                              _FileContent'mimeType :: !Data.Text.Text,
                              _FileContent'url :: !Data.Text.Text,
                              _FileContent'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show FileContent where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField FileContent "fileId" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _FileContent'fileId (\ x__ y__ -> x__ {_FileContent'fileId = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField FileContent "data'" Data.ByteString.ByteString where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _FileContent'data' (\ x__ y__ -> x__ {_FileContent'data' = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField FileContent "filename" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _FileContent'filename
           (\ x__ y__ -> x__ {_FileContent'filename = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField FileContent "mimeType" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _FileContent'mimeType
           (\ x__ y__ -> x__ {_FileContent'mimeType = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField FileContent "url" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _FileContent'url (\ x__ y__ -> x__ {_FileContent'url = y__}))
        Prelude.id
instance Data.ProtoLens.Message FileContent where
  messageName _ = Data.Text.pack "xai_api.FileContent"
  packedMessageDescriptor _
    = "\n\
      \\vFileContent\DC2\ETB\n\
      \\afile_id\CAN\SOH \SOH(\tR\ACKfileId\DC2\DC2\n\
      \\EOTdata\CAN\STX \SOH(\fR\EOTdata\DC2\SUB\n\
      \\bfilename\CAN\ETX \SOH(\tR\bfilename\DC2\ESC\n\
      \\tmime_type\CAN\EOT \SOH(\tR\bmimeType\DC2\DLE\n\
      \\ETXurl\CAN\ENQ \SOH(\tR\ETXurl"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        fileId__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "file_id"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"fileId")) ::
              Data.ProtoLens.FieldDescriptor FileContent
        data'__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "data"
              (Data.ProtoLens.ScalarField Data.ProtoLens.BytesField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.ByteString.ByteString)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"data'")) ::
              Data.ProtoLens.FieldDescriptor FileContent
        filename__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "filename"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"filename")) ::
              Data.ProtoLens.FieldDescriptor FileContent
        mimeType__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "mime_type"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"mimeType")) ::
              Data.ProtoLens.FieldDescriptor FileContent
        url__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "url"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"url")) ::
              Data.ProtoLens.FieldDescriptor FileContent
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, fileId__field_descriptor),
           (Data.ProtoLens.Tag 2, data'__field_descriptor),
           (Data.ProtoLens.Tag 3, filename__field_descriptor),
           (Data.ProtoLens.Tag 4, mimeType__field_descriptor),
           (Data.ProtoLens.Tag 5, url__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _FileContent'_unknownFields
        (\ x__ y__ -> x__ {_FileContent'_unknownFields = y__})
  defMessage
    = FileContent'_constructor
        {_FileContent'fileId = Data.ProtoLens.fieldDefault,
         _FileContent'data' = Data.ProtoLens.fieldDefault,
         _FileContent'filename = Data.ProtoLens.fieldDefault,
         _FileContent'mimeType = Data.ProtoLens.fieldDefault,
         _FileContent'url = Data.ProtoLens.fieldDefault,
         _FileContent'_unknownFields = []}
  parseMessage
    = let
        loop ::
          FileContent -> Data.ProtoLens.Encoding.Bytes.Parser FileContent
        loop x
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t) x)
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "file_id"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"fileId") y x)
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getBytes
                                             (Prelude.fromIntegral len))
                                       "data"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"data'") y x)
                        26
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "filename"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"filename") y x)
                        34
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "mime_type"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"mimeType") y x)
                        42
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "url"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"url") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "FileContent"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v = Lens.Family2.view (Data.ProtoLens.Field.field @"fileId") _x
              in
                if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                      ((Prelude..)
                         (\ bs
                            -> (Data.Monoid.<>)
                                 (Data.ProtoLens.Encoding.Bytes.putVarInt
                                    (Prelude.fromIntegral (Data.ByteString.length bs)))
                                 (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                         Data.Text.Encoding.encodeUtf8 _v))
             ((Data.Monoid.<>)
                (let
                   _v = Lens.Family2.view (Data.ProtoLens.Field.field @"data'") _x
                 in
                   if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                       Data.Monoid.mempty
                   else
                       (Data.Monoid.<>)
                         (Data.ProtoLens.Encoding.Bytes.putVarInt 18)
                         ((\ bs
                             -> (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                     (Prelude.fromIntegral (Data.ByteString.length bs)))
                                  (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                            _v))
                ((Data.Monoid.<>)
                   (let
                      _v = Lens.Family2.view (Data.ProtoLens.Field.field @"filename") _x
                    in
                      if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                          Data.Monoid.mempty
                      else
                          (Data.Monoid.<>)
                            (Data.ProtoLens.Encoding.Bytes.putVarInt 26)
                            ((Prelude..)
                               (\ bs
                                  -> (Data.Monoid.<>)
                                       (Data.ProtoLens.Encoding.Bytes.putVarInt
                                          (Prelude.fromIntegral (Data.ByteString.length bs)))
                                       (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                               Data.Text.Encoding.encodeUtf8 _v))
                   ((Data.Monoid.<>)
                      (let
                         _v = Lens.Family2.view (Data.ProtoLens.Field.field @"mimeType") _x
                       in
                         if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                             Data.Monoid.mempty
                         else
                             (Data.Monoid.<>)
                               (Data.ProtoLens.Encoding.Bytes.putVarInt 34)
                               ((Prelude..)
                                  (\ bs
                                     -> (Data.Monoid.<>)
                                          (Data.ProtoLens.Encoding.Bytes.putVarInt
                                             (Prelude.fromIntegral (Data.ByteString.length bs)))
                                          (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                  Data.Text.Encoding.encodeUtf8 _v))
                      ((Data.Monoid.<>)
                         (let _v = Lens.Family2.view (Data.ProtoLens.Field.field @"url") _x
                          in
                            if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                Data.Monoid.mempty
                            else
                                (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt 42)
                                  ((Prelude..)
                                     (\ bs
                                        -> (Data.Monoid.<>)
                                             (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                (Prelude.fromIntegral (Data.ByteString.length bs)))
                                             (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                     Data.Text.Encoding.encodeUtf8 _v))
                         (Data.ProtoLens.Encoding.Wire.buildFieldSet
                            (Lens.Family2.view Data.ProtoLens.unknownFields _x))))))
instance Control.DeepSeq.NFData FileContent where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_FileContent'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_FileContent'fileId x__)
                (Control.DeepSeq.deepseq
                   (_FileContent'data' x__)
                   (Control.DeepSeq.deepseq
                      (_FileContent'filename x__)
                      (Control.DeepSeq.deepseq
                         (_FileContent'mimeType x__)
                         (Control.DeepSeq.deepseq (_FileContent'url x__) ())))))
newtype FormatType'UnrecognizedValue
  = FormatType'UnrecognizedValue Data.Int.Int32
  deriving stock (Prelude.Eq, Prelude.Ord, Prelude.Show)
data FormatType
  = FORMAT_TYPE_INVALID |
    FORMAT_TYPE_TEXT |
    FORMAT_TYPE_JSON_OBJECT |
    FORMAT_TYPE_JSON_SCHEMA |
    FormatType'Unrecognized !FormatType'UnrecognizedValue
  deriving stock (Prelude.Show, Prelude.Eq, Prelude.Ord)
instance Data.ProtoLens.MessageEnum FormatType where
  maybeToEnum 0 = Prelude.Just FORMAT_TYPE_INVALID
  maybeToEnum 1 = Prelude.Just FORMAT_TYPE_TEXT
  maybeToEnum 2 = Prelude.Just FORMAT_TYPE_JSON_OBJECT
  maybeToEnum 3 = Prelude.Just FORMAT_TYPE_JSON_SCHEMA
  maybeToEnum k
    = Prelude.Just
        (FormatType'Unrecognized
           (FormatType'UnrecognizedValue (Prelude.fromIntegral k)))
  showEnum FORMAT_TYPE_INVALID = "FORMAT_TYPE_INVALID"
  showEnum FORMAT_TYPE_TEXT = "FORMAT_TYPE_TEXT"
  showEnum FORMAT_TYPE_JSON_OBJECT = "FORMAT_TYPE_JSON_OBJECT"
  showEnum FORMAT_TYPE_JSON_SCHEMA = "FORMAT_TYPE_JSON_SCHEMA"
  showEnum (FormatType'Unrecognized (FormatType'UnrecognizedValue k))
    = Prelude.show k
  readEnum k
    | (Prelude.==) k "FORMAT_TYPE_INVALID"
    = Prelude.Just FORMAT_TYPE_INVALID
    | (Prelude.==) k "FORMAT_TYPE_TEXT" = Prelude.Just FORMAT_TYPE_TEXT
    | (Prelude.==) k "FORMAT_TYPE_JSON_OBJECT"
    = Prelude.Just FORMAT_TYPE_JSON_OBJECT
    | (Prelude.==) k "FORMAT_TYPE_JSON_SCHEMA"
    = Prelude.Just FORMAT_TYPE_JSON_SCHEMA
    | Prelude.otherwise
    = (Prelude.>>=) (Text.Read.readMaybe k) Data.ProtoLens.maybeToEnum
instance Prelude.Bounded FormatType where
  minBound = FORMAT_TYPE_INVALID
  maxBound = FORMAT_TYPE_JSON_SCHEMA
instance Prelude.Enum FormatType where
  toEnum k__
    = Prelude.maybe
        (Prelude.error
           ((Prelude.++)
              "toEnum: unknown value for enum FormatType: " (Prelude.show k__)))
        Prelude.id (Data.ProtoLens.maybeToEnum k__)
  fromEnum FORMAT_TYPE_INVALID = 0
  fromEnum FORMAT_TYPE_TEXT = 1
  fromEnum FORMAT_TYPE_JSON_OBJECT = 2
  fromEnum FORMAT_TYPE_JSON_SCHEMA = 3
  fromEnum (FormatType'Unrecognized (FormatType'UnrecognizedValue k))
    = Prelude.fromIntegral k
  succ FORMAT_TYPE_JSON_SCHEMA
    = Prelude.error
        "FormatType.succ: bad argument FORMAT_TYPE_JSON_SCHEMA. This value would be out of bounds."
  succ FORMAT_TYPE_INVALID = FORMAT_TYPE_TEXT
  succ FORMAT_TYPE_TEXT = FORMAT_TYPE_JSON_OBJECT
  succ FORMAT_TYPE_JSON_OBJECT = FORMAT_TYPE_JSON_SCHEMA
  succ (FormatType'Unrecognized _)
    = Prelude.error "FormatType.succ: bad argument: unrecognized value"
  pred FORMAT_TYPE_INVALID
    = Prelude.error
        "FormatType.pred: bad argument FORMAT_TYPE_INVALID. This value would be out of bounds."
  pred FORMAT_TYPE_TEXT = FORMAT_TYPE_INVALID
  pred FORMAT_TYPE_JSON_OBJECT = FORMAT_TYPE_TEXT
  pred FORMAT_TYPE_JSON_SCHEMA = FORMAT_TYPE_JSON_OBJECT
  pred (FormatType'Unrecognized _)
    = Prelude.error "FormatType.pred: bad argument: unrecognized value"
  enumFrom = Data.ProtoLens.Message.Enum.messageEnumFrom
  enumFromTo = Data.ProtoLens.Message.Enum.messageEnumFromTo
  enumFromThen = Data.ProtoLens.Message.Enum.messageEnumFromThen
  enumFromThenTo = Data.ProtoLens.Message.Enum.messageEnumFromThenTo
instance Data.ProtoLens.FieldDefault FormatType where
  fieldDefault = FORMAT_TYPE_INVALID
instance Control.DeepSeq.NFData FormatType where
  rnf x__ = Prelude.seq x__ ()
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Chat_Fields.name' @:: Lens' Function Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.description' @:: Lens' Function Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.strict' @:: Lens' Function Prelude.Bool@
         * 'Proto.Xai.Api.V1.Chat_Fields.parameters' @:: Lens' Function Data.Text.Text@ -}
data Function
  = Function'_constructor {_Function'name :: !Data.Text.Text,
                           _Function'description :: !Data.Text.Text,
                           _Function'strict :: !Prelude.Bool,
                           _Function'parameters :: !Data.Text.Text,
                           _Function'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show Function where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField Function "name" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Function'name (\ x__ y__ -> x__ {_Function'name = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField Function "description" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Function'description
           (\ x__ y__ -> x__ {_Function'description = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField Function "strict" Prelude.Bool where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Function'strict (\ x__ y__ -> x__ {_Function'strict = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField Function "parameters" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Function'parameters
           (\ x__ y__ -> x__ {_Function'parameters = y__}))
        Prelude.id
instance Data.ProtoLens.Message Function where
  messageName _ = Data.Text.pack "xai_api.Function"
  packedMessageDescriptor _
    = "\n\
      \\bFunction\DC2\DC2\n\
      \\EOTname\CAN\SOH \SOH(\tR\EOTname\DC2 \n\
      \\vdescription\CAN\STX \SOH(\tR\vdescription\DC2\SYN\n\
      \\ACKstrict\CAN\ETX \SOH(\bR\ACKstrict\DC2\RS\n\
      \\n\
      \parameters\CAN\EOT \SOH(\tR\n\
      \parameters"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        name__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "name"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"name")) ::
              Data.ProtoLens.FieldDescriptor Function
        description__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "description"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"description")) ::
              Data.ProtoLens.FieldDescriptor Function
        strict__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "strict"
              (Data.ProtoLens.ScalarField Data.ProtoLens.BoolField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Bool)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"strict")) ::
              Data.ProtoLens.FieldDescriptor Function
        parameters__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "parameters"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"parameters")) ::
              Data.ProtoLens.FieldDescriptor Function
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, name__field_descriptor),
           (Data.ProtoLens.Tag 2, description__field_descriptor),
           (Data.ProtoLens.Tag 3, strict__field_descriptor),
           (Data.ProtoLens.Tag 4, parameters__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _Function'_unknownFields
        (\ x__ y__ -> x__ {_Function'_unknownFields = y__})
  defMessage
    = Function'_constructor
        {_Function'name = Data.ProtoLens.fieldDefault,
         _Function'description = Data.ProtoLens.fieldDefault,
         _Function'strict = Data.ProtoLens.fieldDefault,
         _Function'parameters = Data.ProtoLens.fieldDefault,
         _Function'_unknownFields = []}
  parseMessage
    = let
        loop :: Function -> Data.ProtoLens.Encoding.Bytes.Parser Function
        loop x
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t) x)
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "name"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"name") y x)
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "description"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"description") y x)
                        24
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          ((Prelude./=) 0) Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "strict"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"strict") y x)
                        34
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "parameters"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"parameters") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "Function"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let _v = Lens.Family2.view (Data.ProtoLens.Field.field @"name") _x
              in
                if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                      ((Prelude..)
                         (\ bs
                            -> (Data.Monoid.<>)
                                 (Data.ProtoLens.Encoding.Bytes.putVarInt
                                    (Prelude.fromIntegral (Data.ByteString.length bs)))
                                 (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                         Data.Text.Encoding.encodeUtf8 _v))
             ((Data.Monoid.<>)
                (let
                   _v
                     = Lens.Family2.view (Data.ProtoLens.Field.field @"description") _x
                 in
                   if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                       Data.Monoid.mempty
                   else
                       (Data.Monoid.<>)
                         (Data.ProtoLens.Encoding.Bytes.putVarInt 18)
                         ((Prelude..)
                            (\ bs
                               -> (Data.Monoid.<>)
                                    (Data.ProtoLens.Encoding.Bytes.putVarInt
                                       (Prelude.fromIntegral (Data.ByteString.length bs)))
                                    (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                            Data.Text.Encoding.encodeUtf8 _v))
                ((Data.Monoid.<>)
                   (let
                      _v = Lens.Family2.view (Data.ProtoLens.Field.field @"strict") _x
                    in
                      if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                          Data.Monoid.mempty
                      else
                          (Data.Monoid.<>)
                            (Data.ProtoLens.Encoding.Bytes.putVarInt 24)
                            ((Prelude..)
                               Data.ProtoLens.Encoding.Bytes.putVarInt (\ b -> if b then 1 else 0)
                               _v))
                   ((Data.Monoid.<>)
                      (let
                         _v
                           = Lens.Family2.view (Data.ProtoLens.Field.field @"parameters") _x
                       in
                         if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                             Data.Monoid.mempty
                         else
                             (Data.Monoid.<>)
                               (Data.ProtoLens.Encoding.Bytes.putVarInt 34)
                               ((Prelude..)
                                  (\ bs
                                     -> (Data.Monoid.<>)
                                          (Data.ProtoLens.Encoding.Bytes.putVarInt
                                             (Prelude.fromIntegral (Data.ByteString.length bs)))
                                          (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                  Data.Text.Encoding.encodeUtf8 _v))
                      (Data.ProtoLens.Encoding.Wire.buildFieldSet
                         (Lens.Family2.view Data.ProtoLens.unknownFields _x)))))
instance Control.DeepSeq.NFData Function where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_Function'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_Function'name x__)
                (Control.DeepSeq.deepseq
                   (_Function'description x__)
                   (Control.DeepSeq.deepseq
                      (_Function'strict x__)
                      (Control.DeepSeq.deepseq (_Function'parameters x__) ()))))
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Chat_Fields.name' @:: Lens' FunctionCall Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.arguments' @:: Lens' FunctionCall Data.Text.Text@ -}
data FunctionCall
  = FunctionCall'_constructor {_FunctionCall'name :: !Data.Text.Text,
                               _FunctionCall'arguments :: !Data.Text.Text,
                               _FunctionCall'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show FunctionCall where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField FunctionCall "name" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _FunctionCall'name (\ x__ y__ -> x__ {_FunctionCall'name = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField FunctionCall "arguments" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _FunctionCall'arguments
           (\ x__ y__ -> x__ {_FunctionCall'arguments = y__}))
        Prelude.id
instance Data.ProtoLens.Message FunctionCall where
  messageName _ = Data.Text.pack "xai_api.FunctionCall"
  packedMessageDescriptor _
    = "\n\
      \\fFunctionCall\DC2\DC2\n\
      \\EOTname\CAN\SOH \SOH(\tR\EOTname\DC2\FS\n\
      \\targuments\CAN\STX \SOH(\tR\targuments"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        name__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "name"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"name")) ::
              Data.ProtoLens.FieldDescriptor FunctionCall
        arguments__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "arguments"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"arguments")) ::
              Data.ProtoLens.FieldDescriptor FunctionCall
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, name__field_descriptor),
           (Data.ProtoLens.Tag 2, arguments__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _FunctionCall'_unknownFields
        (\ x__ y__ -> x__ {_FunctionCall'_unknownFields = y__})
  defMessage
    = FunctionCall'_constructor
        {_FunctionCall'name = Data.ProtoLens.fieldDefault,
         _FunctionCall'arguments = Data.ProtoLens.fieldDefault,
         _FunctionCall'_unknownFields = []}
  parseMessage
    = let
        loop ::
          FunctionCall -> Data.ProtoLens.Encoding.Bytes.Parser FunctionCall
        loop x
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t) x)
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "name"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"name") y x)
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "arguments"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"arguments") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "FunctionCall"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let _v = Lens.Family2.view (Data.ProtoLens.Field.field @"name") _x
              in
                if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                      ((Prelude..)
                         (\ bs
                            -> (Data.Monoid.<>)
                                 (Data.ProtoLens.Encoding.Bytes.putVarInt
                                    (Prelude.fromIntegral (Data.ByteString.length bs)))
                                 (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                         Data.Text.Encoding.encodeUtf8 _v))
             ((Data.Monoid.<>)
                (let
                   _v = Lens.Family2.view (Data.ProtoLens.Field.field @"arguments") _x
                 in
                   if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                       Data.Monoid.mempty
                   else
                       (Data.Monoid.<>)
                         (Data.ProtoLens.Encoding.Bytes.putVarInt 18)
                         ((Prelude..)
                            (\ bs
                               -> (Data.Monoid.<>)
                                    (Data.ProtoLens.Encoding.Bytes.putVarInt
                                       (Prelude.fromIntegral (Data.ByteString.length bs)))
                                    (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                            Data.Text.Encoding.encodeUtf8 _v))
                (Data.ProtoLens.Encoding.Wire.buildFieldSet
                   (Lens.Family2.view Data.ProtoLens.unknownFields _x)))
instance Control.DeepSeq.NFData FunctionCall where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_FunctionCall'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_FunctionCall'name x__)
                (Control.DeepSeq.deepseq (_FunctionCall'arguments x__) ()))
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Chat_Fields.id' @:: Lens' GetChatCompletionChunk Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.outputs' @:: Lens' GetChatCompletionChunk [CompletionOutputChunk]@
         * 'Proto.Xai.Api.V1.Chat_Fields.vec'outputs' @:: Lens' GetChatCompletionChunk (Data.Vector.Vector CompletionOutputChunk)@
         * 'Proto.Xai.Api.V1.Chat_Fields.created' @:: Lens' GetChatCompletionChunk Proto.Google.Protobuf.Timestamp.Timestamp@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'created' @:: Lens' GetChatCompletionChunk (Prelude.Maybe Proto.Google.Protobuf.Timestamp.Timestamp)@
         * 'Proto.Xai.Api.V1.Chat_Fields.model' @:: Lens' GetChatCompletionChunk Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.systemFingerprint' @:: Lens' GetChatCompletionChunk Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.usage' @:: Lens' GetChatCompletionChunk Proto.Xai.Api.V1.Usage.SamplingUsage@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'usage' @:: Lens' GetChatCompletionChunk (Prelude.Maybe Proto.Xai.Api.V1.Usage.SamplingUsage)@
         * 'Proto.Xai.Api.V1.Chat_Fields.citations' @:: Lens' GetChatCompletionChunk [Data.Text.Text]@
         * 'Proto.Xai.Api.V1.Chat_Fields.vec'citations' @:: Lens' GetChatCompletionChunk (Data.Vector.Vector Data.Text.Text)@
         * 'Proto.Xai.Api.V1.Chat_Fields.debugOutput' @:: Lens' GetChatCompletionChunk DebugOutput@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'debugOutput' @:: Lens' GetChatCompletionChunk (Prelude.Maybe DebugOutput)@ -}
data GetChatCompletionChunk
  = GetChatCompletionChunk'_constructor {_GetChatCompletionChunk'id :: !Data.Text.Text,
                                         _GetChatCompletionChunk'outputs :: !(Data.Vector.Vector CompletionOutputChunk),
                                         _GetChatCompletionChunk'created :: !(Prelude.Maybe Proto.Google.Protobuf.Timestamp.Timestamp),
                                         _GetChatCompletionChunk'model :: !Data.Text.Text,
                                         _GetChatCompletionChunk'systemFingerprint :: !Data.Text.Text,
                                         _GetChatCompletionChunk'usage :: !(Prelude.Maybe Proto.Xai.Api.V1.Usage.SamplingUsage),
                                         _GetChatCompletionChunk'citations :: !(Data.Vector.Vector Data.Text.Text),
                                         _GetChatCompletionChunk'debugOutput :: !(Prelude.Maybe DebugOutput),
                                         _GetChatCompletionChunk'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show GetChatCompletionChunk where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField GetChatCompletionChunk "id" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetChatCompletionChunk'id
           (\ x__ y__ -> x__ {_GetChatCompletionChunk'id = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GetChatCompletionChunk "outputs" [CompletionOutputChunk] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetChatCompletionChunk'outputs
           (\ x__ y__ -> x__ {_GetChatCompletionChunk'outputs = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField GetChatCompletionChunk "vec'outputs" (Data.Vector.Vector CompletionOutputChunk) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetChatCompletionChunk'outputs
           (\ x__ y__ -> x__ {_GetChatCompletionChunk'outputs = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GetChatCompletionChunk "created" Proto.Google.Protobuf.Timestamp.Timestamp where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetChatCompletionChunk'created
           (\ x__ y__ -> x__ {_GetChatCompletionChunk'created = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage)
instance Data.ProtoLens.Field.HasField GetChatCompletionChunk "maybe'created" (Prelude.Maybe Proto.Google.Protobuf.Timestamp.Timestamp) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetChatCompletionChunk'created
           (\ x__ y__ -> x__ {_GetChatCompletionChunk'created = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GetChatCompletionChunk "model" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetChatCompletionChunk'model
           (\ x__ y__ -> x__ {_GetChatCompletionChunk'model = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GetChatCompletionChunk "systemFingerprint" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetChatCompletionChunk'systemFingerprint
           (\ x__ y__
              -> x__ {_GetChatCompletionChunk'systemFingerprint = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GetChatCompletionChunk "usage" Proto.Xai.Api.V1.Usage.SamplingUsage where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetChatCompletionChunk'usage
           (\ x__ y__ -> x__ {_GetChatCompletionChunk'usage = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage)
instance Data.ProtoLens.Field.HasField GetChatCompletionChunk "maybe'usage" (Prelude.Maybe Proto.Xai.Api.V1.Usage.SamplingUsage) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetChatCompletionChunk'usage
           (\ x__ y__ -> x__ {_GetChatCompletionChunk'usage = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GetChatCompletionChunk "citations" [Data.Text.Text] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetChatCompletionChunk'citations
           (\ x__ y__ -> x__ {_GetChatCompletionChunk'citations = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField GetChatCompletionChunk "vec'citations" (Data.Vector.Vector Data.Text.Text) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetChatCompletionChunk'citations
           (\ x__ y__ -> x__ {_GetChatCompletionChunk'citations = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GetChatCompletionChunk "debugOutput" DebugOutput where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetChatCompletionChunk'debugOutput
           (\ x__ y__ -> x__ {_GetChatCompletionChunk'debugOutput = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage)
instance Data.ProtoLens.Field.HasField GetChatCompletionChunk "maybe'debugOutput" (Prelude.Maybe DebugOutput) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetChatCompletionChunk'debugOutput
           (\ x__ y__ -> x__ {_GetChatCompletionChunk'debugOutput = y__}))
        Prelude.id
instance Data.ProtoLens.Message GetChatCompletionChunk where
  messageName _ = Data.Text.pack "xai_api.GetChatCompletionChunk"
  packedMessageDescriptor _
    = "\n\
      \\SYNGetChatCompletionChunk\DC2\SO\n\
      \\STXid\CAN\SOH \SOH(\tR\STXid\DC28\n\
      \\aoutputs\CAN\STX \ETX(\v2\RS.xai_api.CompletionOutputChunkR\aoutputs\DC24\n\
      \\acreated\CAN\ETX \SOH(\v2\SUB.google.protobuf.TimestampR\acreated\DC2\DC4\n\
      \\ENQmodel\CAN\EOT \SOH(\tR\ENQmodel\DC2-\n\
      \\DC2system_fingerprint\CAN\ENQ \SOH(\tR\DC1systemFingerprint\DC2,\n\
      \\ENQusage\CAN\ACK \SOH(\v2\SYN.xai_api.SamplingUsageR\ENQusage\DC2\FS\n\
      \\tcitations\CAN\a \ETX(\tR\tcitations\DC27\n\
      \\fdebug_output\CAN\n\
      \ \SOH(\v2\DC4.xai_api.DebugOutputR\vdebugOutput"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        id__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "id"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"id")) ::
              Data.ProtoLens.FieldDescriptor GetChatCompletionChunk
        outputs__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "outputs"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor CompletionOutputChunk)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Unpacked (Data.ProtoLens.Field.field @"outputs")) ::
              Data.ProtoLens.FieldDescriptor GetChatCompletionChunk
        created__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "created"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor Proto.Google.Protobuf.Timestamp.Timestamp)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'created")) ::
              Data.ProtoLens.FieldDescriptor GetChatCompletionChunk
        model__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "model"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"model")) ::
              Data.ProtoLens.FieldDescriptor GetChatCompletionChunk
        systemFingerprint__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "system_fingerprint"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"systemFingerprint")) ::
              Data.ProtoLens.FieldDescriptor GetChatCompletionChunk
        usage__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "usage"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor Proto.Xai.Api.V1.Usage.SamplingUsage)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'usage")) ::
              Data.ProtoLens.FieldDescriptor GetChatCompletionChunk
        citations__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "citations"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Unpacked
                 (Data.ProtoLens.Field.field @"citations")) ::
              Data.ProtoLens.FieldDescriptor GetChatCompletionChunk
        debugOutput__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "debug_output"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor DebugOutput)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'debugOutput")) ::
              Data.ProtoLens.FieldDescriptor GetChatCompletionChunk
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, id__field_descriptor),
           (Data.ProtoLens.Tag 2, outputs__field_descriptor),
           (Data.ProtoLens.Tag 3, created__field_descriptor),
           (Data.ProtoLens.Tag 4, model__field_descriptor),
           (Data.ProtoLens.Tag 5, systemFingerprint__field_descriptor),
           (Data.ProtoLens.Tag 6, usage__field_descriptor),
           (Data.ProtoLens.Tag 7, citations__field_descriptor),
           (Data.ProtoLens.Tag 10, debugOutput__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _GetChatCompletionChunk'_unknownFields
        (\ x__ y__ -> x__ {_GetChatCompletionChunk'_unknownFields = y__})
  defMessage
    = GetChatCompletionChunk'_constructor
        {_GetChatCompletionChunk'id = Data.ProtoLens.fieldDefault,
         _GetChatCompletionChunk'outputs = Data.Vector.Generic.empty,
         _GetChatCompletionChunk'created = Prelude.Nothing,
         _GetChatCompletionChunk'model = Data.ProtoLens.fieldDefault,
         _GetChatCompletionChunk'systemFingerprint = Data.ProtoLens.fieldDefault,
         _GetChatCompletionChunk'usage = Prelude.Nothing,
         _GetChatCompletionChunk'citations = Data.Vector.Generic.empty,
         _GetChatCompletionChunk'debugOutput = Prelude.Nothing,
         _GetChatCompletionChunk'_unknownFields = []}
  parseMessage
    = let
        loop ::
          GetChatCompletionChunk
          -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Vector Data.ProtoLens.Encoding.Growing.RealWorld Data.Text.Text
             -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Vector Data.ProtoLens.Encoding.Growing.RealWorld CompletionOutputChunk
                -> Data.ProtoLens.Encoding.Bytes.Parser GetChatCompletionChunk
        loop x mutable'citations mutable'outputs
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do frozen'citations <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                            (Data.ProtoLens.Encoding.Growing.unsafeFreeze
                                               mutable'citations)
                      frozen'outputs <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                          (Data.ProtoLens.Encoding.Growing.unsafeFreeze
                                             mutable'outputs)
                      (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t)
                           (Lens.Family2.set
                              (Data.ProtoLens.Field.field @"vec'citations") frozen'citations
                              (Lens.Family2.set
                                 (Data.ProtoLens.Field.field @"vec'outputs") frozen'outputs x)))
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "id"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"id") y x)
                                  mutable'citations mutable'outputs
                        18
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                            Data.ProtoLens.Encoding.Bytes.isolate
                                              (Prelude.fromIntegral len)
                                              Data.ProtoLens.parseMessage)
                                        "outputs"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append mutable'outputs y)
                                loop x mutable'citations v
                        26
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "created"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"created") y x)
                                  mutable'citations mutable'outputs
                        34
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "model"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"model") y x)
                                  mutable'citations mutable'outputs
                        42
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "system_fingerprint"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"systemFingerprint") y x)
                                  mutable'citations mutable'outputs
                        50
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "usage"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"usage") y x)
                                  mutable'citations mutable'outputs
                        58
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                            Data.ProtoLens.Encoding.Bytes.getText
                                              (Prelude.fromIntegral len))
                                        "citations"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append mutable'citations y)
                                loop x v mutable'outputs
                        82
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "debug_output"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"debugOutput") y x)
                                  mutable'citations mutable'outputs
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
                                  mutable'citations mutable'outputs
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do mutable'citations <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                     Data.ProtoLens.Encoding.Growing.new
              mutable'outputs <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                   Data.ProtoLens.Encoding.Growing.new
              loop Data.ProtoLens.defMessage mutable'citations mutable'outputs)
          "GetChatCompletionChunk"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let _v = Lens.Family2.view (Data.ProtoLens.Field.field @"id") _x
              in
                if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                      ((Prelude..)
                         (\ bs
                            -> (Data.Monoid.<>)
                                 (Data.ProtoLens.Encoding.Bytes.putVarInt
                                    (Prelude.fromIntegral (Data.ByteString.length bs)))
                                 (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                         Data.Text.Encoding.encodeUtf8 _v))
             ((Data.Monoid.<>)
                (Data.ProtoLens.Encoding.Bytes.foldMapBuilder
                   (\ _v
                      -> (Data.Monoid.<>)
                           (Data.ProtoLens.Encoding.Bytes.putVarInt 18)
                           ((Prelude..)
                              (\ bs
                                 -> (Data.Monoid.<>)
                                      (Data.ProtoLens.Encoding.Bytes.putVarInt
                                         (Prelude.fromIntegral (Data.ByteString.length bs)))
                                      (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                              Data.ProtoLens.encodeMessage _v))
                   (Lens.Family2.view (Data.ProtoLens.Field.field @"vec'outputs") _x))
                ((Data.Monoid.<>)
                   (case
                        Lens.Family2.view (Data.ProtoLens.Field.field @"maybe'created") _x
                    of
                      Prelude.Nothing -> Data.Monoid.mempty
                      (Prelude.Just _v)
                        -> (Data.Monoid.<>)
                             (Data.ProtoLens.Encoding.Bytes.putVarInt 26)
                             ((Prelude..)
                                (\ bs
                                   -> (Data.Monoid.<>)
                                        (Data.ProtoLens.Encoding.Bytes.putVarInt
                                           (Prelude.fromIntegral (Data.ByteString.length bs)))
                                        (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                Data.ProtoLens.encodeMessage _v))
                   ((Data.Monoid.<>)
                      (let
                         _v = Lens.Family2.view (Data.ProtoLens.Field.field @"model") _x
                       in
                         if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                             Data.Monoid.mempty
                         else
                             (Data.Monoid.<>)
                               (Data.ProtoLens.Encoding.Bytes.putVarInt 34)
                               ((Prelude..)
                                  (\ bs
                                     -> (Data.Monoid.<>)
                                          (Data.ProtoLens.Encoding.Bytes.putVarInt
                                             (Prelude.fromIntegral (Data.ByteString.length bs)))
                                          (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                  Data.Text.Encoding.encodeUtf8 _v))
                      ((Data.Monoid.<>)
                         (let
                            _v
                              = Lens.Family2.view
                                  (Data.ProtoLens.Field.field @"systemFingerprint") _x
                          in
                            if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                Data.Monoid.mempty
                            else
                                (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt 42)
                                  ((Prelude..)
                                     (\ bs
                                        -> (Data.Monoid.<>)
                                             (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                (Prelude.fromIntegral (Data.ByteString.length bs)))
                                             (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                     Data.Text.Encoding.encodeUtf8 _v))
                         ((Data.Monoid.<>)
                            (case
                                 Lens.Family2.view (Data.ProtoLens.Field.field @"maybe'usage") _x
                             of
                               Prelude.Nothing -> Data.Monoid.mempty
                               (Prelude.Just _v)
                                 -> (Data.Monoid.<>)
                                      (Data.ProtoLens.Encoding.Bytes.putVarInt 50)
                                      ((Prelude..)
                                         (\ bs
                                            -> (Data.Monoid.<>)
                                                 (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                    (Prelude.fromIntegral
                                                       (Data.ByteString.length bs)))
                                                 (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                         Data.ProtoLens.encodeMessage _v))
                            ((Data.Monoid.<>)
                               (Data.ProtoLens.Encoding.Bytes.foldMapBuilder
                                  (\ _v
                                     -> (Data.Monoid.<>)
                                          (Data.ProtoLens.Encoding.Bytes.putVarInt 58)
                                          ((Prelude..)
                                             (\ bs
                                                -> (Data.Monoid.<>)
                                                     (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                        (Prelude.fromIntegral
                                                           (Data.ByteString.length bs)))
                                                     (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                             Data.Text.Encoding.encodeUtf8 _v))
                                  (Lens.Family2.view
                                     (Data.ProtoLens.Field.field @"vec'citations") _x))
                               ((Data.Monoid.<>)
                                  (case
                                       Lens.Family2.view
                                         (Data.ProtoLens.Field.field @"maybe'debugOutput") _x
                                   of
                                     Prelude.Nothing -> Data.Monoid.mempty
                                     (Prelude.Just _v)
                                       -> (Data.Monoid.<>)
                                            (Data.ProtoLens.Encoding.Bytes.putVarInt 82)
                                            ((Prelude..)
                                               (\ bs
                                                  -> (Data.Monoid.<>)
                                                       (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                          (Prelude.fromIntegral
                                                             (Data.ByteString.length bs)))
                                                       (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                               Data.ProtoLens.encodeMessage _v))
                                  (Data.ProtoLens.Encoding.Wire.buildFieldSet
                                     (Lens.Family2.view Data.ProtoLens.unknownFields _x)))))))))
instance Control.DeepSeq.NFData GetChatCompletionChunk where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_GetChatCompletionChunk'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_GetChatCompletionChunk'id x__)
                (Control.DeepSeq.deepseq
                   (_GetChatCompletionChunk'outputs x__)
                   (Control.DeepSeq.deepseq
                      (_GetChatCompletionChunk'created x__)
                      (Control.DeepSeq.deepseq
                         (_GetChatCompletionChunk'model x__)
                         (Control.DeepSeq.deepseq
                            (_GetChatCompletionChunk'systemFingerprint x__)
                            (Control.DeepSeq.deepseq
                               (_GetChatCompletionChunk'usage x__)
                               (Control.DeepSeq.deepseq
                                  (_GetChatCompletionChunk'citations x__)
                                  (Control.DeepSeq.deepseq
                                     (_GetChatCompletionChunk'debugOutput x__) ()))))))))
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Chat_Fields.id' @:: Lens' GetChatCompletionResponse Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.outputs' @:: Lens' GetChatCompletionResponse [CompletionOutput]@
         * 'Proto.Xai.Api.V1.Chat_Fields.vec'outputs' @:: Lens' GetChatCompletionResponse (Data.Vector.Vector CompletionOutput)@
         * 'Proto.Xai.Api.V1.Chat_Fields.created' @:: Lens' GetChatCompletionResponse Proto.Google.Protobuf.Timestamp.Timestamp@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'created' @:: Lens' GetChatCompletionResponse (Prelude.Maybe Proto.Google.Protobuf.Timestamp.Timestamp)@
         * 'Proto.Xai.Api.V1.Chat_Fields.model' @:: Lens' GetChatCompletionResponse Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.systemFingerprint' @:: Lens' GetChatCompletionResponse Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.usage' @:: Lens' GetChatCompletionResponse Proto.Xai.Api.V1.Usage.SamplingUsage@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'usage' @:: Lens' GetChatCompletionResponse (Prelude.Maybe Proto.Xai.Api.V1.Usage.SamplingUsage)@
         * 'Proto.Xai.Api.V1.Chat_Fields.citations' @:: Lens' GetChatCompletionResponse [Data.Text.Text]@
         * 'Proto.Xai.Api.V1.Chat_Fields.vec'citations' @:: Lens' GetChatCompletionResponse (Data.Vector.Vector Data.Text.Text)@
         * 'Proto.Xai.Api.V1.Chat_Fields.settings' @:: Lens' GetChatCompletionResponse RequestSettings@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'settings' @:: Lens' GetChatCompletionResponse (Prelude.Maybe RequestSettings)@
         * 'Proto.Xai.Api.V1.Chat_Fields.debugOutput' @:: Lens' GetChatCompletionResponse DebugOutput@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'debugOutput' @:: Lens' GetChatCompletionResponse (Prelude.Maybe DebugOutput)@ -}
data GetChatCompletionResponse
  = GetChatCompletionResponse'_constructor {_GetChatCompletionResponse'id :: !Data.Text.Text,
                                            _GetChatCompletionResponse'outputs :: !(Data.Vector.Vector CompletionOutput),
                                            _GetChatCompletionResponse'created :: !(Prelude.Maybe Proto.Google.Protobuf.Timestamp.Timestamp),
                                            _GetChatCompletionResponse'model :: !Data.Text.Text,
                                            _GetChatCompletionResponse'systemFingerprint :: !Data.Text.Text,
                                            _GetChatCompletionResponse'usage :: !(Prelude.Maybe Proto.Xai.Api.V1.Usage.SamplingUsage),
                                            _GetChatCompletionResponse'citations :: !(Data.Vector.Vector Data.Text.Text),
                                            _GetChatCompletionResponse'settings :: !(Prelude.Maybe RequestSettings),
                                            _GetChatCompletionResponse'debugOutput :: !(Prelude.Maybe DebugOutput),
                                            _GetChatCompletionResponse'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show GetChatCompletionResponse where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField GetChatCompletionResponse "id" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetChatCompletionResponse'id
           (\ x__ y__ -> x__ {_GetChatCompletionResponse'id = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GetChatCompletionResponse "outputs" [CompletionOutput] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetChatCompletionResponse'outputs
           (\ x__ y__ -> x__ {_GetChatCompletionResponse'outputs = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField GetChatCompletionResponse "vec'outputs" (Data.Vector.Vector CompletionOutput) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetChatCompletionResponse'outputs
           (\ x__ y__ -> x__ {_GetChatCompletionResponse'outputs = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GetChatCompletionResponse "created" Proto.Google.Protobuf.Timestamp.Timestamp where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetChatCompletionResponse'created
           (\ x__ y__ -> x__ {_GetChatCompletionResponse'created = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage)
instance Data.ProtoLens.Field.HasField GetChatCompletionResponse "maybe'created" (Prelude.Maybe Proto.Google.Protobuf.Timestamp.Timestamp) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetChatCompletionResponse'created
           (\ x__ y__ -> x__ {_GetChatCompletionResponse'created = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GetChatCompletionResponse "model" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetChatCompletionResponse'model
           (\ x__ y__ -> x__ {_GetChatCompletionResponse'model = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GetChatCompletionResponse "systemFingerprint" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetChatCompletionResponse'systemFingerprint
           (\ x__ y__
              -> x__ {_GetChatCompletionResponse'systemFingerprint = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GetChatCompletionResponse "usage" Proto.Xai.Api.V1.Usage.SamplingUsage where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetChatCompletionResponse'usage
           (\ x__ y__ -> x__ {_GetChatCompletionResponse'usage = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage)
instance Data.ProtoLens.Field.HasField GetChatCompletionResponse "maybe'usage" (Prelude.Maybe Proto.Xai.Api.V1.Usage.SamplingUsage) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetChatCompletionResponse'usage
           (\ x__ y__ -> x__ {_GetChatCompletionResponse'usage = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GetChatCompletionResponse "citations" [Data.Text.Text] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetChatCompletionResponse'citations
           (\ x__ y__ -> x__ {_GetChatCompletionResponse'citations = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField GetChatCompletionResponse "vec'citations" (Data.Vector.Vector Data.Text.Text) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetChatCompletionResponse'citations
           (\ x__ y__ -> x__ {_GetChatCompletionResponse'citations = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GetChatCompletionResponse "settings" RequestSettings where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetChatCompletionResponse'settings
           (\ x__ y__ -> x__ {_GetChatCompletionResponse'settings = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage)
instance Data.ProtoLens.Field.HasField GetChatCompletionResponse "maybe'settings" (Prelude.Maybe RequestSettings) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetChatCompletionResponse'settings
           (\ x__ y__ -> x__ {_GetChatCompletionResponse'settings = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GetChatCompletionResponse "debugOutput" DebugOutput where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetChatCompletionResponse'debugOutput
           (\ x__ y__ -> x__ {_GetChatCompletionResponse'debugOutput = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage)
instance Data.ProtoLens.Field.HasField GetChatCompletionResponse "maybe'debugOutput" (Prelude.Maybe DebugOutput) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetChatCompletionResponse'debugOutput
           (\ x__ y__ -> x__ {_GetChatCompletionResponse'debugOutput = y__}))
        Prelude.id
instance Data.ProtoLens.Message GetChatCompletionResponse where
  messageName _ = Data.Text.pack "xai_api.GetChatCompletionResponse"
  packedMessageDescriptor _
    = "\n\
      \\EMGetChatCompletionResponse\DC2\SO\n\
      \\STXid\CAN\SOH \SOH(\tR\STXid\DC23\n\
      \\aoutputs\CAN\STX \ETX(\v2\EM.xai_api.CompletionOutputR\aoutputs\DC24\n\
      \\acreated\CAN\ENQ \SOH(\v2\SUB.google.protobuf.TimestampR\acreated\DC2\DC4\n\
      \\ENQmodel\CAN\ACK \SOH(\tR\ENQmodel\DC2-\n\
      \\DC2system_fingerprint\CAN\a \SOH(\tR\DC1systemFingerprint\DC2,\n\
      \\ENQusage\CAN\t \SOH(\v2\SYN.xai_api.SamplingUsageR\ENQusage\DC2\FS\n\
      \\tcitations\CAN\n\
      \ \ETX(\tR\tcitations\DC24\n\
      \\bsettings\CAN\v \SOH(\v2\CAN.xai_api.RequestSettingsR\bsettings\DC27\n\
      \\fdebug_output\CAN\f \SOH(\v2\DC4.xai_api.DebugOutputR\vdebugOutput"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        id__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "id"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"id")) ::
              Data.ProtoLens.FieldDescriptor GetChatCompletionResponse
        outputs__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "outputs"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor CompletionOutput)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Unpacked (Data.ProtoLens.Field.field @"outputs")) ::
              Data.ProtoLens.FieldDescriptor GetChatCompletionResponse
        created__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "created"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor Proto.Google.Protobuf.Timestamp.Timestamp)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'created")) ::
              Data.ProtoLens.FieldDescriptor GetChatCompletionResponse
        model__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "model"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"model")) ::
              Data.ProtoLens.FieldDescriptor GetChatCompletionResponse
        systemFingerprint__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "system_fingerprint"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"systemFingerprint")) ::
              Data.ProtoLens.FieldDescriptor GetChatCompletionResponse
        usage__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "usage"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor Proto.Xai.Api.V1.Usage.SamplingUsage)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'usage")) ::
              Data.ProtoLens.FieldDescriptor GetChatCompletionResponse
        citations__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "citations"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Unpacked
                 (Data.ProtoLens.Field.field @"citations")) ::
              Data.ProtoLens.FieldDescriptor GetChatCompletionResponse
        settings__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "settings"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor RequestSettings)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'settings")) ::
              Data.ProtoLens.FieldDescriptor GetChatCompletionResponse
        debugOutput__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "debug_output"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor DebugOutput)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'debugOutput")) ::
              Data.ProtoLens.FieldDescriptor GetChatCompletionResponse
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, id__field_descriptor),
           (Data.ProtoLens.Tag 2, outputs__field_descriptor),
           (Data.ProtoLens.Tag 5, created__field_descriptor),
           (Data.ProtoLens.Tag 6, model__field_descriptor),
           (Data.ProtoLens.Tag 7, systemFingerprint__field_descriptor),
           (Data.ProtoLens.Tag 9, usage__field_descriptor),
           (Data.ProtoLens.Tag 10, citations__field_descriptor),
           (Data.ProtoLens.Tag 11, settings__field_descriptor),
           (Data.ProtoLens.Tag 12, debugOutput__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _GetChatCompletionResponse'_unknownFields
        (\ x__ y__
           -> x__ {_GetChatCompletionResponse'_unknownFields = y__})
  defMessage
    = GetChatCompletionResponse'_constructor
        {_GetChatCompletionResponse'id = Data.ProtoLens.fieldDefault,
         _GetChatCompletionResponse'outputs = Data.Vector.Generic.empty,
         _GetChatCompletionResponse'created = Prelude.Nothing,
         _GetChatCompletionResponse'model = Data.ProtoLens.fieldDefault,
         _GetChatCompletionResponse'systemFingerprint = Data.ProtoLens.fieldDefault,
         _GetChatCompletionResponse'usage = Prelude.Nothing,
         _GetChatCompletionResponse'citations = Data.Vector.Generic.empty,
         _GetChatCompletionResponse'settings = Prelude.Nothing,
         _GetChatCompletionResponse'debugOutput = Prelude.Nothing,
         _GetChatCompletionResponse'_unknownFields = []}
  parseMessage
    = let
        loop ::
          GetChatCompletionResponse
          -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Vector Data.ProtoLens.Encoding.Growing.RealWorld Data.Text.Text
             -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Vector Data.ProtoLens.Encoding.Growing.RealWorld CompletionOutput
                -> Data.ProtoLens.Encoding.Bytes.Parser GetChatCompletionResponse
        loop x mutable'citations mutable'outputs
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do frozen'citations <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                            (Data.ProtoLens.Encoding.Growing.unsafeFreeze
                                               mutable'citations)
                      frozen'outputs <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                          (Data.ProtoLens.Encoding.Growing.unsafeFreeze
                                             mutable'outputs)
                      (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t)
                           (Lens.Family2.set
                              (Data.ProtoLens.Field.field @"vec'citations") frozen'citations
                              (Lens.Family2.set
                                 (Data.ProtoLens.Field.field @"vec'outputs") frozen'outputs x)))
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "id"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"id") y x)
                                  mutable'citations mutable'outputs
                        18
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                            Data.ProtoLens.Encoding.Bytes.isolate
                                              (Prelude.fromIntegral len)
                                              Data.ProtoLens.parseMessage)
                                        "outputs"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append mutable'outputs y)
                                loop x mutable'citations v
                        42
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "created"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"created") y x)
                                  mutable'citations mutable'outputs
                        50
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "model"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"model") y x)
                                  mutable'citations mutable'outputs
                        58
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "system_fingerprint"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"systemFingerprint") y x)
                                  mutable'citations mutable'outputs
                        74
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "usage"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"usage") y x)
                                  mutable'citations mutable'outputs
                        82
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                            Data.ProtoLens.Encoding.Bytes.getText
                                              (Prelude.fromIntegral len))
                                        "citations"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append mutable'citations y)
                                loop x v mutable'outputs
                        90
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "settings"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"settings") y x)
                                  mutable'citations mutable'outputs
                        98
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "debug_output"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"debugOutput") y x)
                                  mutable'citations mutable'outputs
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
                                  mutable'citations mutable'outputs
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do mutable'citations <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                     Data.ProtoLens.Encoding.Growing.new
              mutable'outputs <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                   Data.ProtoLens.Encoding.Growing.new
              loop Data.ProtoLens.defMessage mutable'citations mutable'outputs)
          "GetChatCompletionResponse"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let _v = Lens.Family2.view (Data.ProtoLens.Field.field @"id") _x
              in
                if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                      ((Prelude..)
                         (\ bs
                            -> (Data.Monoid.<>)
                                 (Data.ProtoLens.Encoding.Bytes.putVarInt
                                    (Prelude.fromIntegral (Data.ByteString.length bs)))
                                 (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                         Data.Text.Encoding.encodeUtf8 _v))
             ((Data.Monoid.<>)
                (Data.ProtoLens.Encoding.Bytes.foldMapBuilder
                   (\ _v
                      -> (Data.Monoid.<>)
                           (Data.ProtoLens.Encoding.Bytes.putVarInt 18)
                           ((Prelude..)
                              (\ bs
                                 -> (Data.Monoid.<>)
                                      (Data.ProtoLens.Encoding.Bytes.putVarInt
                                         (Prelude.fromIntegral (Data.ByteString.length bs)))
                                      (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                              Data.ProtoLens.encodeMessage _v))
                   (Lens.Family2.view (Data.ProtoLens.Field.field @"vec'outputs") _x))
                ((Data.Monoid.<>)
                   (case
                        Lens.Family2.view (Data.ProtoLens.Field.field @"maybe'created") _x
                    of
                      Prelude.Nothing -> Data.Monoid.mempty
                      (Prelude.Just _v)
                        -> (Data.Monoid.<>)
                             (Data.ProtoLens.Encoding.Bytes.putVarInt 42)
                             ((Prelude..)
                                (\ bs
                                   -> (Data.Monoid.<>)
                                        (Data.ProtoLens.Encoding.Bytes.putVarInt
                                           (Prelude.fromIntegral (Data.ByteString.length bs)))
                                        (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                Data.ProtoLens.encodeMessage _v))
                   ((Data.Monoid.<>)
                      (let
                         _v = Lens.Family2.view (Data.ProtoLens.Field.field @"model") _x
                       in
                         if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                             Data.Monoid.mempty
                         else
                             (Data.Monoid.<>)
                               (Data.ProtoLens.Encoding.Bytes.putVarInt 50)
                               ((Prelude..)
                                  (\ bs
                                     -> (Data.Monoid.<>)
                                          (Data.ProtoLens.Encoding.Bytes.putVarInt
                                             (Prelude.fromIntegral (Data.ByteString.length bs)))
                                          (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                  Data.Text.Encoding.encodeUtf8 _v))
                      ((Data.Monoid.<>)
                         (let
                            _v
                              = Lens.Family2.view
                                  (Data.ProtoLens.Field.field @"systemFingerprint") _x
                          in
                            if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                Data.Monoid.mempty
                            else
                                (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt 58)
                                  ((Prelude..)
                                     (\ bs
                                        -> (Data.Monoid.<>)
                                             (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                (Prelude.fromIntegral (Data.ByteString.length bs)))
                                             (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                     Data.Text.Encoding.encodeUtf8 _v))
                         ((Data.Monoid.<>)
                            (case
                                 Lens.Family2.view (Data.ProtoLens.Field.field @"maybe'usage") _x
                             of
                               Prelude.Nothing -> Data.Monoid.mempty
                               (Prelude.Just _v)
                                 -> (Data.Monoid.<>)
                                      (Data.ProtoLens.Encoding.Bytes.putVarInt 74)
                                      ((Prelude..)
                                         (\ bs
                                            -> (Data.Monoid.<>)
                                                 (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                    (Prelude.fromIntegral
                                                       (Data.ByteString.length bs)))
                                                 (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                         Data.ProtoLens.encodeMessage _v))
                            ((Data.Monoid.<>)
                               (Data.ProtoLens.Encoding.Bytes.foldMapBuilder
                                  (\ _v
                                     -> (Data.Monoid.<>)
                                          (Data.ProtoLens.Encoding.Bytes.putVarInt 82)
                                          ((Prelude..)
                                             (\ bs
                                                -> (Data.Monoid.<>)
                                                     (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                        (Prelude.fromIntegral
                                                           (Data.ByteString.length bs)))
                                                     (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                             Data.Text.Encoding.encodeUtf8 _v))
                                  (Lens.Family2.view
                                     (Data.ProtoLens.Field.field @"vec'citations") _x))
                               ((Data.Monoid.<>)
                                  (case
                                       Lens.Family2.view
                                         (Data.ProtoLens.Field.field @"maybe'settings") _x
                                   of
                                     Prelude.Nothing -> Data.Monoid.mempty
                                     (Prelude.Just _v)
                                       -> (Data.Monoid.<>)
                                            (Data.ProtoLens.Encoding.Bytes.putVarInt 90)
                                            ((Prelude..)
                                               (\ bs
                                                  -> (Data.Monoid.<>)
                                                       (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                          (Prelude.fromIntegral
                                                             (Data.ByteString.length bs)))
                                                       (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                               Data.ProtoLens.encodeMessage _v))
                                  ((Data.Monoid.<>)
                                     (case
                                          Lens.Family2.view
                                            (Data.ProtoLens.Field.field @"maybe'debugOutput") _x
                                      of
                                        Prelude.Nothing -> Data.Monoid.mempty
                                        (Prelude.Just _v)
                                          -> (Data.Monoid.<>)
                                               (Data.ProtoLens.Encoding.Bytes.putVarInt 98)
                                               ((Prelude..)
                                                  (\ bs
                                                     -> (Data.Monoid.<>)
                                                          (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                             (Prelude.fromIntegral
                                                                (Data.ByteString.length bs)))
                                                          (Data.ProtoLens.Encoding.Bytes.putBytes
                                                             bs))
                                                  Data.ProtoLens.encodeMessage _v))
                                     (Data.ProtoLens.Encoding.Wire.buildFieldSet
                                        (Lens.Family2.view Data.ProtoLens.unknownFields _x))))))))))
instance Control.DeepSeq.NFData GetChatCompletionResponse where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_GetChatCompletionResponse'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_GetChatCompletionResponse'id x__)
                (Control.DeepSeq.deepseq
                   (_GetChatCompletionResponse'outputs x__)
                   (Control.DeepSeq.deepseq
                      (_GetChatCompletionResponse'created x__)
                      (Control.DeepSeq.deepseq
                         (_GetChatCompletionResponse'model x__)
                         (Control.DeepSeq.deepseq
                            (_GetChatCompletionResponse'systemFingerprint x__)
                            (Control.DeepSeq.deepseq
                               (_GetChatCompletionResponse'usage x__)
                               (Control.DeepSeq.deepseq
                                  (_GetChatCompletionResponse'citations x__)
                                  (Control.DeepSeq.deepseq
                                     (_GetChatCompletionResponse'settings x__)
                                     (Control.DeepSeq.deepseq
                                        (_GetChatCompletionResponse'debugOutput x__) ())))))))))
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Chat_Fields.messages' @:: Lens' GetCompletionsRequest [Message]@
         * 'Proto.Xai.Api.V1.Chat_Fields.vec'messages' @:: Lens' GetCompletionsRequest (Data.Vector.Vector Message)@
         * 'Proto.Xai.Api.V1.Chat_Fields.model' @:: Lens' GetCompletionsRequest Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.user' @:: Lens' GetCompletionsRequest Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.n' @:: Lens' GetCompletionsRequest Data.Int.Int32@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'n' @:: Lens' GetCompletionsRequest (Prelude.Maybe Data.Int.Int32)@
         * 'Proto.Xai.Api.V1.Chat_Fields.maxTokens' @:: Lens' GetCompletionsRequest Data.Int.Int32@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'maxTokens' @:: Lens' GetCompletionsRequest (Prelude.Maybe Data.Int.Int32)@
         * 'Proto.Xai.Api.V1.Chat_Fields.seed' @:: Lens' GetCompletionsRequest Data.Int.Int32@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'seed' @:: Lens' GetCompletionsRequest (Prelude.Maybe Data.Int.Int32)@
         * 'Proto.Xai.Api.V1.Chat_Fields.stop' @:: Lens' GetCompletionsRequest [Data.Text.Text]@
         * 'Proto.Xai.Api.V1.Chat_Fields.vec'stop' @:: Lens' GetCompletionsRequest (Data.Vector.Vector Data.Text.Text)@
         * 'Proto.Xai.Api.V1.Chat_Fields.temperature' @:: Lens' GetCompletionsRequest Prelude.Float@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'temperature' @:: Lens' GetCompletionsRequest (Prelude.Maybe Prelude.Float)@
         * 'Proto.Xai.Api.V1.Chat_Fields.topP' @:: Lens' GetCompletionsRequest Prelude.Float@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'topP' @:: Lens' GetCompletionsRequest (Prelude.Maybe Prelude.Float)@
         * 'Proto.Xai.Api.V1.Chat_Fields.logprobs' @:: Lens' GetCompletionsRequest Prelude.Bool@
         * 'Proto.Xai.Api.V1.Chat_Fields.topLogprobs' @:: Lens' GetCompletionsRequest Data.Int.Int32@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'topLogprobs' @:: Lens' GetCompletionsRequest (Prelude.Maybe Data.Int.Int32)@
         * 'Proto.Xai.Api.V1.Chat_Fields.tools' @:: Lens' GetCompletionsRequest [Tool]@
         * 'Proto.Xai.Api.V1.Chat_Fields.vec'tools' @:: Lens' GetCompletionsRequest (Data.Vector.Vector Tool)@
         * 'Proto.Xai.Api.V1.Chat_Fields.toolChoice' @:: Lens' GetCompletionsRequest ToolChoice@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'toolChoice' @:: Lens' GetCompletionsRequest (Prelude.Maybe ToolChoice)@
         * 'Proto.Xai.Api.V1.Chat_Fields.responseFormat' @:: Lens' GetCompletionsRequest ResponseFormat@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'responseFormat' @:: Lens' GetCompletionsRequest (Prelude.Maybe ResponseFormat)@
         * 'Proto.Xai.Api.V1.Chat_Fields.frequencyPenalty' @:: Lens' GetCompletionsRequest Prelude.Float@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'frequencyPenalty' @:: Lens' GetCompletionsRequest (Prelude.Maybe Prelude.Float)@
         * 'Proto.Xai.Api.V1.Chat_Fields.presencePenalty' @:: Lens' GetCompletionsRequest Prelude.Float@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'presencePenalty' @:: Lens' GetCompletionsRequest (Prelude.Maybe Prelude.Float)@
         * 'Proto.Xai.Api.V1.Chat_Fields.reasoningEffort' @:: Lens' GetCompletionsRequest ReasoningEffort@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'reasoningEffort' @:: Lens' GetCompletionsRequest (Prelude.Maybe ReasoningEffort)@
         * 'Proto.Xai.Api.V1.Chat_Fields.searchParameters' @:: Lens' GetCompletionsRequest SearchParameters@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'searchParameters' @:: Lens' GetCompletionsRequest (Prelude.Maybe SearchParameters)@
         * 'Proto.Xai.Api.V1.Chat_Fields.parallelToolCalls' @:: Lens' GetCompletionsRequest Prelude.Bool@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'parallelToolCalls' @:: Lens' GetCompletionsRequest (Prelude.Maybe Prelude.Bool)@
         * 'Proto.Xai.Api.V1.Chat_Fields.previousResponseId' @:: Lens' GetCompletionsRequest Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'previousResponseId' @:: Lens' GetCompletionsRequest (Prelude.Maybe Data.Text.Text)@
         * 'Proto.Xai.Api.V1.Chat_Fields.storeMessages' @:: Lens' GetCompletionsRequest Prelude.Bool@
         * 'Proto.Xai.Api.V1.Chat_Fields.useEncryptedContent' @:: Lens' GetCompletionsRequest Prelude.Bool@
         * 'Proto.Xai.Api.V1.Chat_Fields.maxTurns' @:: Lens' GetCompletionsRequest Data.Int.Int32@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'maxTurns' @:: Lens' GetCompletionsRequest (Prelude.Maybe Data.Int.Int32)@
         * 'Proto.Xai.Api.V1.Chat_Fields.include' @:: Lens' GetCompletionsRequest [IncludeOption]@
         * 'Proto.Xai.Api.V1.Chat_Fields.vec'include' @:: Lens' GetCompletionsRequest (Data.Vector.Vector IncludeOption)@
         * 'Proto.Xai.Api.V1.Chat_Fields.agentCount' @:: Lens' GetCompletionsRequest AgentCount@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'agentCount' @:: Lens' GetCompletionsRequest (Prelude.Maybe AgentCount)@ -}
data GetCompletionsRequest
  = GetCompletionsRequest'_constructor {_GetCompletionsRequest'messages :: !(Data.Vector.Vector Message),
                                        _GetCompletionsRequest'model :: !Data.Text.Text,
                                        _GetCompletionsRequest'user :: !Data.Text.Text,
                                        _GetCompletionsRequest'n :: !(Prelude.Maybe Data.Int.Int32),
                                        _GetCompletionsRequest'maxTokens :: !(Prelude.Maybe Data.Int.Int32),
                                        _GetCompletionsRequest'seed :: !(Prelude.Maybe Data.Int.Int32),
                                        _GetCompletionsRequest'stop :: !(Data.Vector.Vector Data.Text.Text),
                                        _GetCompletionsRequest'temperature :: !(Prelude.Maybe Prelude.Float),
                                        _GetCompletionsRequest'topP :: !(Prelude.Maybe Prelude.Float),
                                        _GetCompletionsRequest'logprobs :: !Prelude.Bool,
                                        _GetCompletionsRequest'topLogprobs :: !(Prelude.Maybe Data.Int.Int32),
                                        _GetCompletionsRequest'tools :: !(Data.Vector.Vector Tool),
                                        _GetCompletionsRequest'toolChoice :: !(Prelude.Maybe ToolChoice),
                                        _GetCompletionsRequest'responseFormat :: !(Prelude.Maybe ResponseFormat),
                                        _GetCompletionsRequest'frequencyPenalty :: !(Prelude.Maybe Prelude.Float),
                                        _GetCompletionsRequest'presencePenalty :: !(Prelude.Maybe Prelude.Float),
                                        _GetCompletionsRequest'reasoningEffort :: !(Prelude.Maybe ReasoningEffort),
                                        _GetCompletionsRequest'searchParameters :: !(Prelude.Maybe SearchParameters),
                                        _GetCompletionsRequest'parallelToolCalls :: !(Prelude.Maybe Prelude.Bool),
                                        _GetCompletionsRequest'previousResponseId :: !(Prelude.Maybe Data.Text.Text),
                                        _GetCompletionsRequest'storeMessages :: !Prelude.Bool,
                                        _GetCompletionsRequest'useEncryptedContent :: !Prelude.Bool,
                                        _GetCompletionsRequest'maxTurns :: !(Prelude.Maybe Data.Int.Int32),
                                        _GetCompletionsRequest'include :: !(Data.Vector.Vector IncludeOption),
                                        _GetCompletionsRequest'agentCount :: !(Prelude.Maybe AgentCount),
                                        _GetCompletionsRequest'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show GetCompletionsRequest where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField GetCompletionsRequest "messages" [Message] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetCompletionsRequest'messages
           (\ x__ y__ -> x__ {_GetCompletionsRequest'messages = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField GetCompletionsRequest "vec'messages" (Data.Vector.Vector Message) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetCompletionsRequest'messages
           (\ x__ y__ -> x__ {_GetCompletionsRequest'messages = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GetCompletionsRequest "model" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetCompletionsRequest'model
           (\ x__ y__ -> x__ {_GetCompletionsRequest'model = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GetCompletionsRequest "user" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetCompletionsRequest'user
           (\ x__ y__ -> x__ {_GetCompletionsRequest'user = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GetCompletionsRequest "n" Data.Int.Int32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetCompletionsRequest'n
           (\ x__ y__ -> x__ {_GetCompletionsRequest'n = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField GetCompletionsRequest "maybe'n" (Prelude.Maybe Data.Int.Int32) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetCompletionsRequest'n
           (\ x__ y__ -> x__ {_GetCompletionsRequest'n = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GetCompletionsRequest "maxTokens" Data.Int.Int32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetCompletionsRequest'maxTokens
           (\ x__ y__ -> x__ {_GetCompletionsRequest'maxTokens = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField GetCompletionsRequest "maybe'maxTokens" (Prelude.Maybe Data.Int.Int32) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetCompletionsRequest'maxTokens
           (\ x__ y__ -> x__ {_GetCompletionsRequest'maxTokens = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GetCompletionsRequest "seed" Data.Int.Int32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetCompletionsRequest'seed
           (\ x__ y__ -> x__ {_GetCompletionsRequest'seed = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField GetCompletionsRequest "maybe'seed" (Prelude.Maybe Data.Int.Int32) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetCompletionsRequest'seed
           (\ x__ y__ -> x__ {_GetCompletionsRequest'seed = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GetCompletionsRequest "stop" [Data.Text.Text] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetCompletionsRequest'stop
           (\ x__ y__ -> x__ {_GetCompletionsRequest'stop = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField GetCompletionsRequest "vec'stop" (Data.Vector.Vector Data.Text.Text) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetCompletionsRequest'stop
           (\ x__ y__ -> x__ {_GetCompletionsRequest'stop = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GetCompletionsRequest "temperature" Prelude.Float where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetCompletionsRequest'temperature
           (\ x__ y__ -> x__ {_GetCompletionsRequest'temperature = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField GetCompletionsRequest "maybe'temperature" (Prelude.Maybe Prelude.Float) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetCompletionsRequest'temperature
           (\ x__ y__ -> x__ {_GetCompletionsRequest'temperature = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GetCompletionsRequest "topP" Prelude.Float where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetCompletionsRequest'topP
           (\ x__ y__ -> x__ {_GetCompletionsRequest'topP = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField GetCompletionsRequest "maybe'topP" (Prelude.Maybe Prelude.Float) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetCompletionsRequest'topP
           (\ x__ y__ -> x__ {_GetCompletionsRequest'topP = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GetCompletionsRequest "logprobs" Prelude.Bool where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetCompletionsRequest'logprobs
           (\ x__ y__ -> x__ {_GetCompletionsRequest'logprobs = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GetCompletionsRequest "topLogprobs" Data.Int.Int32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetCompletionsRequest'topLogprobs
           (\ x__ y__ -> x__ {_GetCompletionsRequest'topLogprobs = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField GetCompletionsRequest "maybe'topLogprobs" (Prelude.Maybe Data.Int.Int32) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetCompletionsRequest'topLogprobs
           (\ x__ y__ -> x__ {_GetCompletionsRequest'topLogprobs = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GetCompletionsRequest "tools" [Tool] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetCompletionsRequest'tools
           (\ x__ y__ -> x__ {_GetCompletionsRequest'tools = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField GetCompletionsRequest "vec'tools" (Data.Vector.Vector Tool) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetCompletionsRequest'tools
           (\ x__ y__ -> x__ {_GetCompletionsRequest'tools = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GetCompletionsRequest "toolChoice" ToolChoice where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetCompletionsRequest'toolChoice
           (\ x__ y__ -> x__ {_GetCompletionsRequest'toolChoice = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage)
instance Data.ProtoLens.Field.HasField GetCompletionsRequest "maybe'toolChoice" (Prelude.Maybe ToolChoice) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetCompletionsRequest'toolChoice
           (\ x__ y__ -> x__ {_GetCompletionsRequest'toolChoice = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GetCompletionsRequest "responseFormat" ResponseFormat where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetCompletionsRequest'responseFormat
           (\ x__ y__ -> x__ {_GetCompletionsRequest'responseFormat = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage)
instance Data.ProtoLens.Field.HasField GetCompletionsRequest "maybe'responseFormat" (Prelude.Maybe ResponseFormat) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetCompletionsRequest'responseFormat
           (\ x__ y__ -> x__ {_GetCompletionsRequest'responseFormat = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GetCompletionsRequest "frequencyPenalty" Prelude.Float where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetCompletionsRequest'frequencyPenalty
           (\ x__ y__ -> x__ {_GetCompletionsRequest'frequencyPenalty = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField GetCompletionsRequest "maybe'frequencyPenalty" (Prelude.Maybe Prelude.Float) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetCompletionsRequest'frequencyPenalty
           (\ x__ y__ -> x__ {_GetCompletionsRequest'frequencyPenalty = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GetCompletionsRequest "presencePenalty" Prelude.Float where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetCompletionsRequest'presencePenalty
           (\ x__ y__ -> x__ {_GetCompletionsRequest'presencePenalty = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField GetCompletionsRequest "maybe'presencePenalty" (Prelude.Maybe Prelude.Float) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetCompletionsRequest'presencePenalty
           (\ x__ y__ -> x__ {_GetCompletionsRequest'presencePenalty = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GetCompletionsRequest "reasoningEffort" ReasoningEffort where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetCompletionsRequest'reasoningEffort
           (\ x__ y__ -> x__ {_GetCompletionsRequest'reasoningEffort = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField GetCompletionsRequest "maybe'reasoningEffort" (Prelude.Maybe ReasoningEffort) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetCompletionsRequest'reasoningEffort
           (\ x__ y__ -> x__ {_GetCompletionsRequest'reasoningEffort = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GetCompletionsRequest "searchParameters" SearchParameters where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetCompletionsRequest'searchParameters
           (\ x__ y__ -> x__ {_GetCompletionsRequest'searchParameters = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage)
instance Data.ProtoLens.Field.HasField GetCompletionsRequest "maybe'searchParameters" (Prelude.Maybe SearchParameters) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetCompletionsRequest'searchParameters
           (\ x__ y__ -> x__ {_GetCompletionsRequest'searchParameters = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GetCompletionsRequest "parallelToolCalls" Prelude.Bool where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetCompletionsRequest'parallelToolCalls
           (\ x__ y__
              -> x__ {_GetCompletionsRequest'parallelToolCalls = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField GetCompletionsRequest "maybe'parallelToolCalls" (Prelude.Maybe Prelude.Bool) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetCompletionsRequest'parallelToolCalls
           (\ x__ y__
              -> x__ {_GetCompletionsRequest'parallelToolCalls = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GetCompletionsRequest "previousResponseId" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetCompletionsRequest'previousResponseId
           (\ x__ y__
              -> x__ {_GetCompletionsRequest'previousResponseId = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField GetCompletionsRequest "maybe'previousResponseId" (Prelude.Maybe Data.Text.Text) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetCompletionsRequest'previousResponseId
           (\ x__ y__
              -> x__ {_GetCompletionsRequest'previousResponseId = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GetCompletionsRequest "storeMessages" Prelude.Bool where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetCompletionsRequest'storeMessages
           (\ x__ y__ -> x__ {_GetCompletionsRequest'storeMessages = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GetCompletionsRequest "useEncryptedContent" Prelude.Bool where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetCompletionsRequest'useEncryptedContent
           (\ x__ y__
              -> x__ {_GetCompletionsRequest'useEncryptedContent = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GetCompletionsRequest "maxTurns" Data.Int.Int32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetCompletionsRequest'maxTurns
           (\ x__ y__ -> x__ {_GetCompletionsRequest'maxTurns = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField GetCompletionsRequest "maybe'maxTurns" (Prelude.Maybe Data.Int.Int32) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetCompletionsRequest'maxTurns
           (\ x__ y__ -> x__ {_GetCompletionsRequest'maxTurns = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GetCompletionsRequest "include" [IncludeOption] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetCompletionsRequest'include
           (\ x__ y__ -> x__ {_GetCompletionsRequest'include = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField GetCompletionsRequest "vec'include" (Data.Vector.Vector IncludeOption) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetCompletionsRequest'include
           (\ x__ y__ -> x__ {_GetCompletionsRequest'include = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GetCompletionsRequest "agentCount" AgentCount where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetCompletionsRequest'agentCount
           (\ x__ y__ -> x__ {_GetCompletionsRequest'agentCount = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField GetCompletionsRequest "maybe'agentCount" (Prelude.Maybe AgentCount) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetCompletionsRequest'agentCount
           (\ x__ y__ -> x__ {_GetCompletionsRequest'agentCount = y__}))
        Prelude.id
instance Data.ProtoLens.Message GetCompletionsRequest where
  messageName _ = Data.Text.pack "xai_api.GetCompletionsRequest"
  packedMessageDescriptor _
    = "\n\
      \\NAKGetCompletionsRequest\DC2,\n\
      \\bmessages\CAN\SOH \ETX(\v2\DLE.xai_api.MessageR\bmessages\DC2\DC4\n\
      \\ENQmodel\CAN\STX \SOH(\tR\ENQmodel\DC2\DC2\n\
      \\EOTuser\CAN\DLE \SOH(\tR\EOTuser\DC2\DC1\n\
      \\SOHn\CAN\b \SOH(\ENQH\NULR\SOHn\136\SOH\SOH\DC2\"\n\
      \\n\
      \max_tokens\CAN\a \SOH(\ENQH\SOHR\tmaxTokens\136\SOH\SOH\DC2\ETB\n\
      \\EOTseed\CAN\v \SOH(\ENQH\STXR\EOTseed\136\SOH\SOH\DC2\DC2\n\
      \\EOTstop\CAN\f \ETX(\tR\EOTstop\DC2%\n\
      \\vtemperature\CAN\SO \SOH(\STXH\ETXR\vtemperature\136\SOH\SOH\DC2\CAN\n\
      \\ENQtop_p\CAN\SI \SOH(\STXH\EOTR\EOTtopP\136\SOH\SOH\DC2\SUB\n\
      \\blogprobs\CAN\ENQ \SOH(\bR\blogprobs\DC2&\n\
      \\ftop_logprobs\CAN\ACK \SOH(\ENQH\ENQR\vtopLogprobs\136\SOH\SOH\DC2#\n\
      \\ENQtools\CAN\DC1 \ETX(\v2\r.xai_api.ToolR\ENQtools\DC24\n\
      \\vtool_choice\CAN\DC2 \SOH(\v2\DC3.xai_api.ToolChoiceR\n\
      \toolChoice\DC2@\n\
      \\SIresponse_format\CAN\n\
      \ \SOH(\v2\ETB.xai_api.ResponseFormatR\SOresponseFormat\DC20\n\
      \\DC1frequency_penalty\CAN\ETX \SOH(\STXH\ACKR\DLEfrequencyPenalty\136\SOH\SOH\DC2.\n\
      \\DLEpresence_penalty\CAN\t \SOH(\STXH\aR\SIpresencePenalty\136\SOH\SOH\DC2H\n\
      \\DLEreasoning_effort\CAN\DC3 \SOH(\SO2\CAN.xai_api.ReasoningEffortH\bR\SIreasoningEffort\136\SOH\SOH\DC2K\n\
      \\DC1search_parameters\CAN\DC4 \SOH(\v2\EM.xai_api.SearchParametersH\tR\DLEsearchParameters\136\SOH\SOH\DC23\n\
      \\DC3parallel_tool_calls\CAN\NAK \SOH(\bH\n\
      \R\DC1parallelToolCalls\136\SOH\SOH\DC25\n\
      \\DC4previous_response_id\CAN\SYN \SOH(\tH\vR\DC2previousResponseId\136\SOH\SOH\DC2%\n\
      \\SOstore_messages\CAN\ETB \SOH(\bR\rstoreMessages\DC22\n\
      \\NAKuse_encrypted_content\CAN\CAN \SOH(\bR\DC3useEncryptedContent\DC2 \n\
      \\tmax_turns\CAN\EM \SOH(\ENQH\fR\bmaxTurns\136\SOH\SOH\DC20\n\
      \\ainclude\CAN\SUB \ETX(\SO2\SYN.xai_api.IncludeOptionR\ainclude\DC29\n\
      \\vagent_count\CAN\GS \SOH(\SO2\DC3.xai_api.AgentCountH\rR\n\
      \agentCount\136\SOH\SOHB\EOT\n\
      \\STX_nB\r\n\
      \\v_max_tokensB\a\n\
      \\ENQ_seedB\SO\n\
      \\f_temperatureB\b\n\
      \\ACK_top_pB\SI\n\
      \\r_top_logprobsB\DC4\n\
      \\DC2_frequency_penaltyB\DC3\n\
      \\DC1_presence_penaltyB\DC3\n\
      \\DC1_reasoning_effortB\DC4\n\
      \\DC2_search_parametersB\SYN\n\
      \\DC4_parallel_tool_callsB\ETB\n\
      \\NAK_previous_response_idB\f\n\
      \\n\
      \_max_turnsB\SO\n\
      \\f_agent_countJ\EOT\b\EOT\DLE\ENQ"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        messages__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "messages"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor Message)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Unpacked
                 (Data.ProtoLens.Field.field @"messages")) ::
              Data.ProtoLens.FieldDescriptor GetCompletionsRequest
        model__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "model"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"model")) ::
              Data.ProtoLens.FieldDescriptor GetCompletionsRequest
        user__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "user"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"user")) ::
              Data.ProtoLens.FieldDescriptor GetCompletionsRequest
        n__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "n"
              (Data.ProtoLens.ScalarField Data.ProtoLens.Int32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Int.Int32)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'n")) ::
              Data.ProtoLens.FieldDescriptor GetCompletionsRequest
        maxTokens__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "max_tokens"
              (Data.ProtoLens.ScalarField Data.ProtoLens.Int32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Int.Int32)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'maxTokens")) ::
              Data.ProtoLens.FieldDescriptor GetCompletionsRequest
        seed__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "seed"
              (Data.ProtoLens.ScalarField Data.ProtoLens.Int32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Int.Int32)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'seed")) ::
              Data.ProtoLens.FieldDescriptor GetCompletionsRequest
        stop__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "stop"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Unpacked (Data.ProtoLens.Field.field @"stop")) ::
              Data.ProtoLens.FieldDescriptor GetCompletionsRequest
        temperature__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "temperature"
              (Data.ProtoLens.ScalarField Data.ProtoLens.FloatField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Float)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'temperature")) ::
              Data.ProtoLens.FieldDescriptor GetCompletionsRequest
        topP__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "top_p"
              (Data.ProtoLens.ScalarField Data.ProtoLens.FloatField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Float)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'topP")) ::
              Data.ProtoLens.FieldDescriptor GetCompletionsRequest
        logprobs__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "logprobs"
              (Data.ProtoLens.ScalarField Data.ProtoLens.BoolField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Bool)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"logprobs")) ::
              Data.ProtoLens.FieldDescriptor GetCompletionsRequest
        topLogprobs__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "top_logprobs"
              (Data.ProtoLens.ScalarField Data.ProtoLens.Int32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Int.Int32)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'topLogprobs")) ::
              Data.ProtoLens.FieldDescriptor GetCompletionsRequest
        tools__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "tools"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor Tool)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Unpacked (Data.ProtoLens.Field.field @"tools")) ::
              Data.ProtoLens.FieldDescriptor GetCompletionsRequest
        toolChoice__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "tool_choice"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor ToolChoice)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'toolChoice")) ::
              Data.ProtoLens.FieldDescriptor GetCompletionsRequest
        responseFormat__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "response_format"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor ResponseFormat)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'responseFormat")) ::
              Data.ProtoLens.FieldDescriptor GetCompletionsRequest
        frequencyPenalty__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "frequency_penalty"
              (Data.ProtoLens.ScalarField Data.ProtoLens.FloatField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Float)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'frequencyPenalty")) ::
              Data.ProtoLens.FieldDescriptor GetCompletionsRequest
        presencePenalty__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "presence_penalty"
              (Data.ProtoLens.ScalarField Data.ProtoLens.FloatField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Float)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'presencePenalty")) ::
              Data.ProtoLens.FieldDescriptor GetCompletionsRequest
        reasoningEffort__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "reasoning_effort"
              (Data.ProtoLens.ScalarField Data.ProtoLens.EnumField ::
                 Data.ProtoLens.FieldTypeDescriptor ReasoningEffort)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'reasoningEffort")) ::
              Data.ProtoLens.FieldDescriptor GetCompletionsRequest
        searchParameters__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "search_parameters"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor SearchParameters)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'searchParameters")) ::
              Data.ProtoLens.FieldDescriptor GetCompletionsRequest
        parallelToolCalls__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "parallel_tool_calls"
              (Data.ProtoLens.ScalarField Data.ProtoLens.BoolField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Bool)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'parallelToolCalls")) ::
              Data.ProtoLens.FieldDescriptor GetCompletionsRequest
        previousResponseId__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "previous_response_id"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'previousResponseId")) ::
              Data.ProtoLens.FieldDescriptor GetCompletionsRequest
        storeMessages__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "store_messages"
              (Data.ProtoLens.ScalarField Data.ProtoLens.BoolField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Bool)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"storeMessages")) ::
              Data.ProtoLens.FieldDescriptor GetCompletionsRequest
        useEncryptedContent__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "use_encrypted_content"
              (Data.ProtoLens.ScalarField Data.ProtoLens.BoolField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Bool)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"useEncryptedContent")) ::
              Data.ProtoLens.FieldDescriptor GetCompletionsRequest
        maxTurns__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "max_turns"
              (Data.ProtoLens.ScalarField Data.ProtoLens.Int32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Int.Int32)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'maxTurns")) ::
              Data.ProtoLens.FieldDescriptor GetCompletionsRequest
        include__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "include"
              (Data.ProtoLens.ScalarField Data.ProtoLens.EnumField ::
                 Data.ProtoLens.FieldTypeDescriptor IncludeOption)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Packed (Data.ProtoLens.Field.field @"include")) ::
              Data.ProtoLens.FieldDescriptor GetCompletionsRequest
        agentCount__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "agent_count"
              (Data.ProtoLens.ScalarField Data.ProtoLens.EnumField ::
                 Data.ProtoLens.FieldTypeDescriptor AgentCount)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'agentCount")) ::
              Data.ProtoLens.FieldDescriptor GetCompletionsRequest
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, messages__field_descriptor),
           (Data.ProtoLens.Tag 2, model__field_descriptor),
           (Data.ProtoLens.Tag 16, user__field_descriptor),
           (Data.ProtoLens.Tag 8, n__field_descriptor),
           (Data.ProtoLens.Tag 7, maxTokens__field_descriptor),
           (Data.ProtoLens.Tag 11, seed__field_descriptor),
           (Data.ProtoLens.Tag 12, stop__field_descriptor),
           (Data.ProtoLens.Tag 14, temperature__field_descriptor),
           (Data.ProtoLens.Tag 15, topP__field_descriptor),
           (Data.ProtoLens.Tag 5, logprobs__field_descriptor),
           (Data.ProtoLens.Tag 6, topLogprobs__field_descriptor),
           (Data.ProtoLens.Tag 17, tools__field_descriptor),
           (Data.ProtoLens.Tag 18, toolChoice__field_descriptor),
           (Data.ProtoLens.Tag 10, responseFormat__field_descriptor),
           (Data.ProtoLens.Tag 3, frequencyPenalty__field_descriptor),
           (Data.ProtoLens.Tag 9, presencePenalty__field_descriptor),
           (Data.ProtoLens.Tag 19, reasoningEffort__field_descriptor),
           (Data.ProtoLens.Tag 20, searchParameters__field_descriptor),
           (Data.ProtoLens.Tag 21, parallelToolCalls__field_descriptor),
           (Data.ProtoLens.Tag 22, previousResponseId__field_descriptor),
           (Data.ProtoLens.Tag 23, storeMessages__field_descriptor),
           (Data.ProtoLens.Tag 24, useEncryptedContent__field_descriptor),
           (Data.ProtoLens.Tag 25, maxTurns__field_descriptor),
           (Data.ProtoLens.Tag 26, include__field_descriptor),
           (Data.ProtoLens.Tag 29, agentCount__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _GetCompletionsRequest'_unknownFields
        (\ x__ y__ -> x__ {_GetCompletionsRequest'_unknownFields = y__})
  defMessage
    = GetCompletionsRequest'_constructor
        {_GetCompletionsRequest'messages = Data.Vector.Generic.empty,
         _GetCompletionsRequest'model = Data.ProtoLens.fieldDefault,
         _GetCompletionsRequest'user = Data.ProtoLens.fieldDefault,
         _GetCompletionsRequest'n = Prelude.Nothing,
         _GetCompletionsRequest'maxTokens = Prelude.Nothing,
         _GetCompletionsRequest'seed = Prelude.Nothing,
         _GetCompletionsRequest'stop = Data.Vector.Generic.empty,
         _GetCompletionsRequest'temperature = Prelude.Nothing,
         _GetCompletionsRequest'topP = Prelude.Nothing,
         _GetCompletionsRequest'logprobs = Data.ProtoLens.fieldDefault,
         _GetCompletionsRequest'topLogprobs = Prelude.Nothing,
         _GetCompletionsRequest'tools = Data.Vector.Generic.empty,
         _GetCompletionsRequest'toolChoice = Prelude.Nothing,
         _GetCompletionsRequest'responseFormat = Prelude.Nothing,
         _GetCompletionsRequest'frequencyPenalty = Prelude.Nothing,
         _GetCompletionsRequest'presencePenalty = Prelude.Nothing,
         _GetCompletionsRequest'reasoningEffort = Prelude.Nothing,
         _GetCompletionsRequest'searchParameters = Prelude.Nothing,
         _GetCompletionsRequest'parallelToolCalls = Prelude.Nothing,
         _GetCompletionsRequest'previousResponseId = Prelude.Nothing,
         _GetCompletionsRequest'storeMessages = Data.ProtoLens.fieldDefault,
         _GetCompletionsRequest'useEncryptedContent = Data.ProtoLens.fieldDefault,
         _GetCompletionsRequest'maxTurns = Prelude.Nothing,
         _GetCompletionsRequest'include = Data.Vector.Generic.empty,
         _GetCompletionsRequest'agentCount = Prelude.Nothing,
         _GetCompletionsRequest'_unknownFields = []}
  parseMessage
    = let
        loop ::
          GetCompletionsRequest
          -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Vector Data.ProtoLens.Encoding.Growing.RealWorld IncludeOption
             -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Vector Data.ProtoLens.Encoding.Growing.RealWorld Message
                -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Vector Data.ProtoLens.Encoding.Growing.RealWorld Data.Text.Text
                   -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Vector Data.ProtoLens.Encoding.Growing.RealWorld Tool
                      -> Data.ProtoLens.Encoding.Bytes.Parser GetCompletionsRequest
        loop x mutable'include mutable'messages mutable'stop mutable'tools
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do frozen'include <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                          (Data.ProtoLens.Encoding.Growing.unsafeFreeze
                                             mutable'include)
                      frozen'messages <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                           (Data.ProtoLens.Encoding.Growing.unsafeFreeze
                                              mutable'messages)
                      frozen'stop <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.unsafeFreeze mutable'stop)
                      frozen'tools <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                        (Data.ProtoLens.Encoding.Growing.unsafeFreeze mutable'tools)
                      (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t)
                           (Lens.Family2.set
                              (Data.ProtoLens.Field.field @"vec'include") frozen'include
                              (Lens.Family2.set
                                 (Data.ProtoLens.Field.field @"vec'messages") frozen'messages
                                 (Lens.Family2.set
                                    (Data.ProtoLens.Field.field @"vec'stop") frozen'stop
                                    (Lens.Family2.set
                                       (Data.ProtoLens.Field.field @"vec'tools") frozen'tools x)))))
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                            Data.ProtoLens.Encoding.Bytes.isolate
                                              (Prelude.fromIntegral len)
                                              Data.ProtoLens.parseMessage)
                                        "messages"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append mutable'messages y)
                                loop x mutable'include v mutable'stop mutable'tools
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "model"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"model") y x)
                                  mutable'include mutable'messages mutable'stop mutable'tools
                        130
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "user"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"user") y x)
                                  mutable'include mutable'messages mutable'stop mutable'tools
                        64
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "n"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"n") y x)
                                  mutable'include mutable'messages mutable'stop mutable'tools
                        56
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "max_tokens"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"maxTokens") y x)
                                  mutable'include mutable'messages mutable'stop mutable'tools
                        88
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "seed"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"seed") y x)
                                  mutable'include mutable'messages mutable'stop mutable'tools
                        98
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                            Data.ProtoLens.Encoding.Bytes.getText
                                              (Prelude.fromIntegral len))
                                        "stop"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append mutable'stop y)
                                loop x mutable'include mutable'messages v mutable'tools
                        117
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Data.ProtoLens.Encoding.Bytes.wordToFloat
                                          Data.ProtoLens.Encoding.Bytes.getFixed32)
                                       "temperature"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"temperature") y x)
                                  mutable'include mutable'messages mutable'stop mutable'tools
                        125
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Data.ProtoLens.Encoding.Bytes.wordToFloat
                                          Data.ProtoLens.Encoding.Bytes.getFixed32)
                                       "top_p"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"topP") y x)
                                  mutable'include mutable'messages mutable'stop mutable'tools
                        40
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          ((Prelude./=) 0) Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "logprobs"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"logprobs") y x)
                                  mutable'include mutable'messages mutable'stop mutable'tools
                        48
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "top_logprobs"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"topLogprobs") y x)
                                  mutable'include mutable'messages mutable'stop mutable'tools
                        138
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                            Data.ProtoLens.Encoding.Bytes.isolate
                                              (Prelude.fromIntegral len)
                                              Data.ProtoLens.parseMessage)
                                        "tools"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append mutable'tools y)
                                loop x mutable'include mutable'messages mutable'stop v
                        146
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "tool_choice"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"toolChoice") y x)
                                  mutable'include mutable'messages mutable'stop mutable'tools
                        82
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "response_format"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"responseFormat") y x)
                                  mutable'include mutable'messages mutable'stop mutable'tools
                        29
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Data.ProtoLens.Encoding.Bytes.wordToFloat
                                          Data.ProtoLens.Encoding.Bytes.getFixed32)
                                       "frequency_penalty"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"frequencyPenalty") y x)
                                  mutable'include mutable'messages mutable'stop mutable'tools
                        77
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Data.ProtoLens.Encoding.Bytes.wordToFloat
                                          Data.ProtoLens.Encoding.Bytes.getFixed32)
                                       "presence_penalty"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"presencePenalty") y x)
                                  mutable'include mutable'messages mutable'stop mutable'tools
                        152
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.toEnum
                                          (Prelude.fmap
                                             Prelude.fromIntegral
                                             Data.ProtoLens.Encoding.Bytes.getVarInt))
                                       "reasoning_effort"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"reasoningEffort") y x)
                                  mutable'include mutable'messages mutable'stop mutable'tools
                        162
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "search_parameters"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"searchParameters") y x)
                                  mutable'include mutable'messages mutable'stop mutable'tools
                        168
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          ((Prelude./=) 0) Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "parallel_tool_calls"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"parallelToolCalls") y x)
                                  mutable'include mutable'messages mutable'stop mutable'tools
                        178
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "previous_response_id"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"previousResponseId") y x)
                                  mutable'include mutable'messages mutable'stop mutable'tools
                        184
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          ((Prelude./=) 0) Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "store_messages"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"storeMessages") y x)
                                  mutable'include mutable'messages mutable'stop mutable'tools
                        192
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          ((Prelude./=) 0) Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "use_encrypted_content"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"useEncryptedContent") y x)
                                  mutable'include mutable'messages mutable'stop mutable'tools
                        200
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "max_turns"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"maxTurns") y x)
                                  mutable'include mutable'messages mutable'stop mutable'tools
                        208
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (Prelude.fmap
                                           Prelude.toEnum
                                           (Prelude.fmap
                                              Prelude.fromIntegral
                                              Data.ProtoLens.Encoding.Bytes.getVarInt))
                                        "include"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append mutable'include y)
                                loop x v mutable'messages mutable'stop mutable'tools
                        210
                          -> do y <- do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                        Data.ProtoLens.Encoding.Bytes.isolate
                                          (Prelude.fromIntegral len)
                                          ((let
                                              ploop qs
                                                = do packedEnd <- Data.ProtoLens.Encoding.Bytes.atEnd
                                                     if packedEnd then
                                                         Prelude.return qs
                                                     else
                                                         do !q <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                                                    (Prelude.fmap
                                                                       Prelude.toEnum
                                                                       (Prelude.fmap
                                                                          Prelude.fromIntegral
                                                                          Data.ProtoLens.Encoding.Bytes.getVarInt))
                                                                    "include"
                                                            qs' <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                                                     (Data.ProtoLens.Encoding.Growing.append
                                                                        qs q)
                                                            ploop qs'
                                            in ploop)
                                             mutable'include)
                                loop x y mutable'messages mutable'stop mutable'tools
                        232
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.toEnum
                                          (Prelude.fmap
                                             Prelude.fromIntegral
                                             Data.ProtoLens.Encoding.Bytes.getVarInt))
                                       "agent_count"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"agentCount") y x)
                                  mutable'include mutable'messages mutable'stop mutable'tools
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
                                  mutable'include mutable'messages mutable'stop mutable'tools
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do mutable'include <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                   Data.ProtoLens.Encoding.Growing.new
              mutable'messages <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                    Data.ProtoLens.Encoding.Growing.new
              mutable'stop <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                Data.ProtoLens.Encoding.Growing.new
              mutable'tools <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                 Data.ProtoLens.Encoding.Growing.new
              loop
                Data.ProtoLens.defMessage mutable'include mutable'messages
                mutable'stop mutable'tools)
          "GetCompletionsRequest"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (Data.ProtoLens.Encoding.Bytes.foldMapBuilder
                (\ _v
                   -> (Data.Monoid.<>)
                        (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                        ((Prelude..)
                           (\ bs
                              -> (Data.Monoid.<>)
                                   (Data.ProtoLens.Encoding.Bytes.putVarInt
                                      (Prelude.fromIntegral (Data.ByteString.length bs)))
                                   (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                           Data.ProtoLens.encodeMessage _v))
                (Lens.Family2.view
                   (Data.ProtoLens.Field.field @"vec'messages") _x))
             ((Data.Monoid.<>)
                (let
                   _v = Lens.Family2.view (Data.ProtoLens.Field.field @"model") _x
                 in
                   if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                       Data.Monoid.mempty
                   else
                       (Data.Monoid.<>)
                         (Data.ProtoLens.Encoding.Bytes.putVarInt 18)
                         ((Prelude..)
                            (\ bs
                               -> (Data.Monoid.<>)
                                    (Data.ProtoLens.Encoding.Bytes.putVarInt
                                       (Prelude.fromIntegral (Data.ByteString.length bs)))
                                    (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                            Data.Text.Encoding.encodeUtf8 _v))
                ((Data.Monoid.<>)
                   (let _v = Lens.Family2.view (Data.ProtoLens.Field.field @"user") _x
                    in
                      if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                          Data.Monoid.mempty
                      else
                          (Data.Monoid.<>)
                            (Data.ProtoLens.Encoding.Bytes.putVarInt 130)
                            ((Prelude..)
                               (\ bs
                                  -> (Data.Monoid.<>)
                                       (Data.ProtoLens.Encoding.Bytes.putVarInt
                                          (Prelude.fromIntegral (Data.ByteString.length bs)))
                                       (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                               Data.Text.Encoding.encodeUtf8 _v))
                   ((Data.Monoid.<>)
                      (case
                           Lens.Family2.view (Data.ProtoLens.Field.field @"maybe'n") _x
                       of
                         Prelude.Nothing -> Data.Monoid.mempty
                         (Prelude.Just _v)
                           -> (Data.Monoid.<>)
                                (Data.ProtoLens.Encoding.Bytes.putVarInt 64)
                                ((Prelude..)
                                   Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral _v))
                      ((Data.Monoid.<>)
                         (case
                              Lens.Family2.view
                                (Data.ProtoLens.Field.field @"maybe'maxTokens") _x
                          of
                            Prelude.Nothing -> Data.Monoid.mempty
                            (Prelude.Just _v)
                              -> (Data.Monoid.<>)
                                   (Data.ProtoLens.Encoding.Bytes.putVarInt 56)
                                   ((Prelude..)
                                      Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral
                                      _v))
                         ((Data.Monoid.<>)
                            (case
                                 Lens.Family2.view (Data.ProtoLens.Field.field @"maybe'seed") _x
                             of
                               Prelude.Nothing -> Data.Monoid.mempty
                               (Prelude.Just _v)
                                 -> (Data.Monoid.<>)
                                      (Data.ProtoLens.Encoding.Bytes.putVarInt 88)
                                      ((Prelude..)
                                         Data.ProtoLens.Encoding.Bytes.putVarInt
                                         Prelude.fromIntegral _v))
                            ((Data.Monoid.<>)
                               (Data.ProtoLens.Encoding.Bytes.foldMapBuilder
                                  (\ _v
                                     -> (Data.Monoid.<>)
                                          (Data.ProtoLens.Encoding.Bytes.putVarInt 98)
                                          ((Prelude..)
                                             (\ bs
                                                -> (Data.Monoid.<>)
                                                     (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                        (Prelude.fromIntegral
                                                           (Data.ByteString.length bs)))
                                                     (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                             Data.Text.Encoding.encodeUtf8 _v))
                                  (Lens.Family2.view (Data.ProtoLens.Field.field @"vec'stop") _x))
                               ((Data.Monoid.<>)
                                  (case
                                       Lens.Family2.view
                                         (Data.ProtoLens.Field.field @"maybe'temperature") _x
                                   of
                                     Prelude.Nothing -> Data.Monoid.mempty
                                     (Prelude.Just _v)
                                       -> (Data.Monoid.<>)
                                            (Data.ProtoLens.Encoding.Bytes.putVarInt 117)
                                            ((Prelude..)
                                               Data.ProtoLens.Encoding.Bytes.putFixed32
                                               Data.ProtoLens.Encoding.Bytes.floatToWord _v))
                                  ((Data.Monoid.<>)
                                     (case
                                          Lens.Family2.view
                                            (Data.ProtoLens.Field.field @"maybe'topP") _x
                                      of
                                        Prelude.Nothing -> Data.Monoid.mempty
                                        (Prelude.Just _v)
                                          -> (Data.Monoid.<>)
                                               (Data.ProtoLens.Encoding.Bytes.putVarInt 125)
                                               ((Prelude..)
                                                  Data.ProtoLens.Encoding.Bytes.putFixed32
                                                  Data.ProtoLens.Encoding.Bytes.floatToWord _v))
                                     ((Data.Monoid.<>)
                                        (let
                                           _v
                                             = Lens.Family2.view
                                                 (Data.ProtoLens.Field.field @"logprobs") _x
                                         in
                                           if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                               Data.Monoid.mempty
                                           else
                                               (Data.Monoid.<>)
                                                 (Data.ProtoLens.Encoding.Bytes.putVarInt 40)
                                                 ((Prelude..)
                                                    Data.ProtoLens.Encoding.Bytes.putVarInt
                                                    (\ b -> if b then 1 else 0) _v))
                                        ((Data.Monoid.<>)
                                           (case
                                                Lens.Family2.view
                                                  (Data.ProtoLens.Field.field @"maybe'topLogprobs")
                                                  _x
                                            of
                                              Prelude.Nothing -> Data.Monoid.mempty
                                              (Prelude.Just _v)
                                                -> (Data.Monoid.<>)
                                                     (Data.ProtoLens.Encoding.Bytes.putVarInt 48)
                                                     ((Prelude..)
                                                        Data.ProtoLens.Encoding.Bytes.putVarInt
                                                        Prelude.fromIntegral _v))
                                           ((Data.Monoid.<>)
                                              (Data.ProtoLens.Encoding.Bytes.foldMapBuilder
                                                 (\ _v
                                                    -> (Data.Monoid.<>)
                                                         (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                            138)
                                                         ((Prelude..)
                                                            (\ bs
                                                               -> (Data.Monoid.<>)
                                                                    (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                       (Prelude.fromIntegral
                                                                          (Data.ByteString.length
                                                                             bs)))
                                                                    (Data.ProtoLens.Encoding.Bytes.putBytes
                                                                       bs))
                                                            Data.ProtoLens.encodeMessage _v))
                                                 (Lens.Family2.view
                                                    (Data.ProtoLens.Field.field @"vec'tools") _x))
                                              ((Data.Monoid.<>)
                                                 (case
                                                      Lens.Family2.view
                                                        (Data.ProtoLens.Field.field
                                                           @"maybe'toolChoice")
                                                        _x
                                                  of
                                                    Prelude.Nothing -> Data.Monoid.mempty
                                                    (Prelude.Just _v)
                                                      -> (Data.Monoid.<>)
                                                           (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                              146)
                                                           ((Prelude..)
                                                              (\ bs
                                                                 -> (Data.Monoid.<>)
                                                                      (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                         (Prelude.fromIntegral
                                                                            (Data.ByteString.length
                                                                               bs)))
                                                                      (Data.ProtoLens.Encoding.Bytes.putBytes
                                                                         bs))
                                                              Data.ProtoLens.encodeMessage _v))
                                                 ((Data.Monoid.<>)
                                                    (case
                                                         Lens.Family2.view
                                                           (Data.ProtoLens.Field.field
                                                              @"maybe'responseFormat")
                                                           _x
                                                     of
                                                       Prelude.Nothing -> Data.Monoid.mempty
                                                       (Prelude.Just _v)
                                                         -> (Data.Monoid.<>)
                                                              (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                 82)
                                                              ((Prelude..)
                                                                 (\ bs
                                                                    -> (Data.Monoid.<>)
                                                                         (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                            (Prelude.fromIntegral
                                                                               (Data.ByteString.length
                                                                                  bs)))
                                                                         (Data.ProtoLens.Encoding.Bytes.putBytes
                                                                            bs))
                                                                 Data.ProtoLens.encodeMessage _v))
                                                    ((Data.Monoid.<>)
                                                       (case
                                                            Lens.Family2.view
                                                              (Data.ProtoLens.Field.field
                                                                 @"maybe'frequencyPenalty")
                                                              _x
                                                        of
                                                          Prelude.Nothing -> Data.Monoid.mempty
                                                          (Prelude.Just _v)
                                                            -> (Data.Monoid.<>)
                                                                 (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                    29)
                                                                 ((Prelude..)
                                                                    Data.ProtoLens.Encoding.Bytes.putFixed32
                                                                    Data.ProtoLens.Encoding.Bytes.floatToWord
                                                                    _v))
                                                       ((Data.Monoid.<>)
                                                          (case
                                                               Lens.Family2.view
                                                                 (Data.ProtoLens.Field.field
                                                                    @"maybe'presencePenalty")
                                                                 _x
                                                           of
                                                             Prelude.Nothing -> Data.Monoid.mempty
                                                             (Prelude.Just _v)
                                                               -> (Data.Monoid.<>)
                                                                    (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                       77)
                                                                    ((Prelude..)
                                                                       Data.ProtoLens.Encoding.Bytes.putFixed32
                                                                       Data.ProtoLens.Encoding.Bytes.floatToWord
                                                                       _v))
                                                          ((Data.Monoid.<>)
                                                             (case
                                                                  Lens.Family2.view
                                                                    (Data.ProtoLens.Field.field
                                                                       @"maybe'reasoningEffort")
                                                                    _x
                                                              of
                                                                Prelude.Nothing
                                                                  -> Data.Monoid.mempty
                                                                (Prelude.Just _v)
                                                                  -> (Data.Monoid.<>)
                                                                       (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                          152)
                                                                       ((Prelude..)
                                                                          ((Prelude..)
                                                                             Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                             Prelude.fromIntegral)
                                                                          Prelude.fromEnum _v))
                                                             ((Data.Monoid.<>)
                                                                (case
                                                                     Lens.Family2.view
                                                                       (Data.ProtoLens.Field.field
                                                                          @"maybe'searchParameters")
                                                                       _x
                                                                 of
                                                                   Prelude.Nothing
                                                                     -> Data.Monoid.mempty
                                                                   (Prelude.Just _v)
                                                                     -> (Data.Monoid.<>)
                                                                          (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                             162)
                                                                          ((Prelude..)
                                                                             (\ bs
                                                                                -> (Data.Monoid.<>)
                                                                                     (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                                        (Prelude.fromIntegral
                                                                                           (Data.ByteString.length
                                                                                              bs)))
                                                                                     (Data.ProtoLens.Encoding.Bytes.putBytes
                                                                                        bs))
                                                                             Data.ProtoLens.encodeMessage
                                                                             _v))
                                                                ((Data.Monoid.<>)
                                                                   (case
                                                                        Lens.Family2.view
                                                                          (Data.ProtoLens.Field.field
                                                                             @"maybe'parallelToolCalls")
                                                                          _x
                                                                    of
                                                                      Prelude.Nothing
                                                                        -> Data.Monoid.mempty
                                                                      (Prelude.Just _v)
                                                                        -> (Data.Monoid.<>)
                                                                             (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                                168)
                                                                             ((Prelude..)
                                                                                Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                                (\ b
                                                                                   -> if b then
                                                                                          1
                                                                                      else
                                                                                          0)
                                                                                _v))
                                                                   ((Data.Monoid.<>)
                                                                      (case
                                                                           Lens.Family2.view
                                                                             (Data.ProtoLens.Field.field
                                                                                @"maybe'previousResponseId")
                                                                             _x
                                                                       of
                                                                         Prelude.Nothing
                                                                           -> Data.Monoid.mempty
                                                                         (Prelude.Just _v)
                                                                           -> (Data.Monoid.<>)
                                                                                (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                                   178)
                                                                                ((Prelude..)
                                                                                   (\ bs
                                                                                      -> (Data.Monoid.<>)
                                                                                           (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                                              (Prelude.fromIntegral
                                                                                                 (Data.ByteString.length
                                                                                                    bs)))
                                                                                           (Data.ProtoLens.Encoding.Bytes.putBytes
                                                                                              bs))
                                                                                   Data.Text.Encoding.encodeUtf8
                                                                                   _v))
                                                                      ((Data.Monoid.<>)
                                                                         (let
                                                                            _v
                                                                              = Lens.Family2.view
                                                                                  (Data.ProtoLens.Field.field
                                                                                     @"storeMessages")
                                                                                  _x
                                                                          in
                                                                            if (Prelude.==)
                                                                                 _v
                                                                                 Data.ProtoLens.fieldDefault then
                                                                                Data.Monoid.mempty
                                                                            else
                                                                                (Data.Monoid.<>)
                                                                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                                     184)
                                                                                  ((Prelude..)
                                                                                     Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                                     (\ b
                                                                                        -> if b then
                                                                                               1
                                                                                           else
                                                                                               0)
                                                                                     _v))
                                                                         ((Data.Monoid.<>)
                                                                            (let
                                                                               _v
                                                                                 = Lens.Family2.view
                                                                                     (Data.ProtoLens.Field.field
                                                                                        @"useEncryptedContent")
                                                                                     _x
                                                                             in
                                                                               if (Prelude.==)
                                                                                    _v
                                                                                    Data.ProtoLens.fieldDefault then
                                                                                   Data.Monoid.mempty
                                                                               else
                                                                                   (Data.Monoid.<>)
                                                                                     (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                                        192)
                                                                                     ((Prelude..)
                                                                                        Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                                        (\ b
                                                                                           -> if b then
                                                                                                  1
                                                                                              else
                                                                                                  0)
                                                                                        _v))
                                                                            ((Data.Monoid.<>)
                                                                               (case
                                                                                    Lens.Family2.view
                                                                                      (Data.ProtoLens.Field.field
                                                                                         @"maybe'maxTurns")
                                                                                      _x
                                                                                of
                                                                                  Prelude.Nothing
                                                                                    -> Data.Monoid.mempty
                                                                                  (Prelude.Just _v)
                                                                                    -> (Data.Monoid.<>)
                                                                                         (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                                            200)
                                                                                         ((Prelude..)
                                                                                            Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                                            Prelude.fromIntegral
                                                                                            _v))
                                                                               ((Data.Monoid.<>)
                                                                                  (let
                                                                                     p = Lens.Family2.view
                                                                                           (Data.ProtoLens.Field.field
                                                                                              @"vec'include")
                                                                                           _x
                                                                                   in
                                                                                     if Data.Vector.Generic.null
                                                                                          p then
                                                                                         Data.Monoid.mempty
                                                                                     else
                                                                                         (Data.Monoid.<>)
                                                                                           (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                                              210)
                                                                                           ((\ bs
                                                                                               -> (Data.Monoid.<>)
                                                                                                    (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                                                       (Prelude.fromIntegral
                                                                                                          (Data.ByteString.length
                                                                                                             bs)))
                                                                                                    (Data.ProtoLens.Encoding.Bytes.putBytes
                                                                                                       bs))
                                                                                              (Data.ProtoLens.Encoding.Bytes.runBuilder
                                                                                                 (Data.ProtoLens.Encoding.Bytes.foldMapBuilder
                                                                                                    ((Prelude..)
                                                                                                       ((Prelude..)
                                                                                                          Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                                                          Prelude.fromIntegral)
                                                                                                       Prelude.fromEnum)
                                                                                                    p))))
                                                                                  ((Data.Monoid.<>)
                                                                                     (case
                                                                                          Lens.Family2.view
                                                                                            (Data.ProtoLens.Field.field
                                                                                               @"maybe'agentCount")
                                                                                            _x
                                                                                      of
                                                                                        Prelude.Nothing
                                                                                          -> Data.Monoid.mempty
                                                                                        (Prelude.Just _v)
                                                                                          -> (Data.Monoid.<>)
                                                                                               (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                                                  232)
                                                                                               ((Prelude..)
                                                                                                  ((Prelude..)
                                                                                                     Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                                                     Prelude.fromIntegral)
                                                                                                  Prelude.fromEnum
                                                                                                  _v))
                                                                                     (Data.ProtoLens.Encoding.Wire.buildFieldSet
                                                                                        (Lens.Family2.view
                                                                                           Data.ProtoLens.unknownFields
                                                                                           _x))))))))))))))))))))))))))
instance Control.DeepSeq.NFData GetCompletionsRequest where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_GetCompletionsRequest'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_GetCompletionsRequest'messages x__)
                (Control.DeepSeq.deepseq
                   (_GetCompletionsRequest'model x__)
                   (Control.DeepSeq.deepseq
                      (_GetCompletionsRequest'user x__)
                      (Control.DeepSeq.deepseq
                         (_GetCompletionsRequest'n x__)
                         (Control.DeepSeq.deepseq
                            (_GetCompletionsRequest'maxTokens x__)
                            (Control.DeepSeq.deepseq
                               (_GetCompletionsRequest'seed x__)
                               (Control.DeepSeq.deepseq
                                  (_GetCompletionsRequest'stop x__)
                                  (Control.DeepSeq.deepseq
                                     (_GetCompletionsRequest'temperature x__)
                                     (Control.DeepSeq.deepseq
                                        (_GetCompletionsRequest'topP x__)
                                        (Control.DeepSeq.deepseq
                                           (_GetCompletionsRequest'logprobs x__)
                                           (Control.DeepSeq.deepseq
                                              (_GetCompletionsRequest'topLogprobs x__)
                                              (Control.DeepSeq.deepseq
                                                 (_GetCompletionsRequest'tools x__)
                                                 (Control.DeepSeq.deepseq
                                                    (_GetCompletionsRequest'toolChoice x__)
                                                    (Control.DeepSeq.deepseq
                                                       (_GetCompletionsRequest'responseFormat x__)
                                                       (Control.DeepSeq.deepseq
                                                          (_GetCompletionsRequest'frequencyPenalty
                                                             x__)
                                                          (Control.DeepSeq.deepseq
                                                             (_GetCompletionsRequest'presencePenalty
                                                                x__)
                                                             (Control.DeepSeq.deepseq
                                                                (_GetCompletionsRequest'reasoningEffort
                                                                   x__)
                                                                (Control.DeepSeq.deepseq
                                                                   (_GetCompletionsRequest'searchParameters
                                                                      x__)
                                                                   (Control.DeepSeq.deepseq
                                                                      (_GetCompletionsRequest'parallelToolCalls
                                                                         x__)
                                                                      (Control.DeepSeq.deepseq
                                                                         (_GetCompletionsRequest'previousResponseId
                                                                            x__)
                                                                         (Control.DeepSeq.deepseq
                                                                            (_GetCompletionsRequest'storeMessages
                                                                               x__)
                                                                            (Control.DeepSeq.deepseq
                                                                               (_GetCompletionsRequest'useEncryptedContent
                                                                                  x__)
                                                                               (Control.DeepSeq.deepseq
                                                                                  (_GetCompletionsRequest'maxTurns
                                                                                     x__)
                                                                                  (Control.DeepSeq.deepseq
                                                                                     (_GetCompletionsRequest'include
                                                                                        x__)
                                                                                     (Control.DeepSeq.deepseq
                                                                                        (_GetCompletionsRequest'agentCount
                                                                                           x__)
                                                                                        ())))))))))))))))))))))))))
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Chat_Fields.status' @:: Lens' GetDeferredCompletionResponse Proto.Xai.Api.V1.Deferred.DeferredStatus@
         * 'Proto.Xai.Api.V1.Chat_Fields.response' @:: Lens' GetDeferredCompletionResponse GetChatCompletionResponse@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'response' @:: Lens' GetDeferredCompletionResponse (Prelude.Maybe GetChatCompletionResponse)@ -}
data GetDeferredCompletionResponse
  = GetDeferredCompletionResponse'_constructor {_GetDeferredCompletionResponse'status :: !Proto.Xai.Api.V1.Deferred.DeferredStatus,
                                                _GetDeferredCompletionResponse'response :: !(Prelude.Maybe GetChatCompletionResponse),
                                                _GetDeferredCompletionResponse'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show GetDeferredCompletionResponse where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField GetDeferredCompletionResponse "status" Proto.Xai.Api.V1.Deferred.DeferredStatus where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetDeferredCompletionResponse'status
           (\ x__ y__ -> x__ {_GetDeferredCompletionResponse'status = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GetDeferredCompletionResponse "response" GetChatCompletionResponse where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetDeferredCompletionResponse'response
           (\ x__ y__ -> x__ {_GetDeferredCompletionResponse'response = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage)
instance Data.ProtoLens.Field.HasField GetDeferredCompletionResponse "maybe'response" (Prelude.Maybe GetChatCompletionResponse) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetDeferredCompletionResponse'response
           (\ x__ y__ -> x__ {_GetDeferredCompletionResponse'response = y__}))
        Prelude.id
instance Data.ProtoLens.Message GetDeferredCompletionResponse where
  messageName _
    = Data.Text.pack "xai_api.GetDeferredCompletionResponse"
  packedMessageDescriptor _
    = "\n\
      \\GSGetDeferredCompletionResponse\DC2/\n\
      \\ACKstatus\CAN\STX \SOH(\SO2\ETB.xai_api.DeferredStatusR\ACKstatus\DC2C\n\
      \\bresponse\CAN\SOH \SOH(\v2\".xai_api.GetChatCompletionResponseH\NULR\bresponse\136\SOH\SOHB\v\n\
      \\t_response"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        status__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "status"
              (Data.ProtoLens.ScalarField Data.ProtoLens.EnumField ::
                 Data.ProtoLens.FieldTypeDescriptor Proto.Xai.Api.V1.Deferred.DeferredStatus)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"status")) ::
              Data.ProtoLens.FieldDescriptor GetDeferredCompletionResponse
        response__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "response"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor GetChatCompletionResponse)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'response")) ::
              Data.ProtoLens.FieldDescriptor GetDeferredCompletionResponse
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 2, status__field_descriptor),
           (Data.ProtoLens.Tag 1, response__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _GetDeferredCompletionResponse'_unknownFields
        (\ x__ y__
           -> x__ {_GetDeferredCompletionResponse'_unknownFields = y__})
  defMessage
    = GetDeferredCompletionResponse'_constructor
        {_GetDeferredCompletionResponse'status = Data.ProtoLens.fieldDefault,
         _GetDeferredCompletionResponse'response = Prelude.Nothing,
         _GetDeferredCompletionResponse'_unknownFields = []}
  parseMessage
    = let
        loop ::
          GetDeferredCompletionResponse
          -> Data.ProtoLens.Encoding.Bytes.Parser GetDeferredCompletionResponse
        loop x
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t) x)
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        16
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.toEnum
                                          (Prelude.fmap
                                             Prelude.fromIntegral
                                             Data.ProtoLens.Encoding.Bytes.getVarInt))
                                       "status"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"status") y x)
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "response"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"response") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "GetDeferredCompletionResponse"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v = Lens.Family2.view (Data.ProtoLens.Field.field @"status") _x
              in
                if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 16)
                      ((Prelude..)
                         ((Prelude..)
                            Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral)
                         Prelude.fromEnum _v))
             ((Data.Monoid.<>)
                (case
                     Lens.Family2.view (Data.ProtoLens.Field.field @"maybe'response") _x
                 of
                   Prelude.Nothing -> Data.Monoid.mempty
                   (Prelude.Just _v)
                     -> (Data.Monoid.<>)
                          (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                          ((Prelude..)
                             (\ bs
                                -> (Data.Monoid.<>)
                                     (Data.ProtoLens.Encoding.Bytes.putVarInt
                                        (Prelude.fromIntegral (Data.ByteString.length bs)))
                                     (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                             Data.ProtoLens.encodeMessage _v))
                (Data.ProtoLens.Encoding.Wire.buildFieldSet
                   (Lens.Family2.view Data.ProtoLens.unknownFields _x)))
instance Control.DeepSeq.NFData GetDeferredCompletionResponse where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_GetDeferredCompletionResponse'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_GetDeferredCompletionResponse'status x__)
                (Control.DeepSeq.deepseq
                   (_GetDeferredCompletionResponse'response x__) ()))
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Chat_Fields.responseId' @:: Lens' GetStoredCompletionRequest Data.Text.Text@ -}
data GetStoredCompletionRequest
  = GetStoredCompletionRequest'_constructor {_GetStoredCompletionRequest'responseId :: !Data.Text.Text,
                                             _GetStoredCompletionRequest'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show GetStoredCompletionRequest where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField GetStoredCompletionRequest "responseId" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetStoredCompletionRequest'responseId
           (\ x__ y__ -> x__ {_GetStoredCompletionRequest'responseId = y__}))
        Prelude.id
instance Data.ProtoLens.Message GetStoredCompletionRequest where
  messageName _ = Data.Text.pack "xai_api.GetStoredCompletionRequest"
  packedMessageDescriptor _
    = "\n\
      \\SUBGetStoredCompletionRequest\DC2\US\n\
      \\vresponse_id\CAN\SOH \SOH(\tR\n\
      \responseId"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        responseId__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "response_id"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"responseId")) ::
              Data.ProtoLens.FieldDescriptor GetStoredCompletionRequest
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, responseId__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _GetStoredCompletionRequest'_unknownFields
        (\ x__ y__
           -> x__ {_GetStoredCompletionRequest'_unknownFields = y__})
  defMessage
    = GetStoredCompletionRequest'_constructor
        {_GetStoredCompletionRequest'responseId = Data.ProtoLens.fieldDefault,
         _GetStoredCompletionRequest'_unknownFields = []}
  parseMessage
    = let
        loop ::
          GetStoredCompletionRequest
          -> Data.ProtoLens.Encoding.Bytes.Parser GetStoredCompletionRequest
        loop x
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t) x)
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "response_id"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"responseId") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "GetStoredCompletionRequest"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v
                  = Lens.Family2.view (Data.ProtoLens.Field.field @"responseId") _x
              in
                if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                      ((Prelude..)
                         (\ bs
                            -> (Data.Monoid.<>)
                                 (Data.ProtoLens.Encoding.Bytes.putVarInt
                                    (Prelude.fromIntegral (Data.ByteString.length bs)))
                                 (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                         Data.Text.Encoding.encodeUtf8 _v))
             (Data.ProtoLens.Encoding.Wire.buildFieldSet
                (Lens.Family2.view Data.ProtoLens.unknownFields _x))
instance Control.DeepSeq.NFData GetStoredCompletionRequest where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_GetStoredCompletionRequest'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_GetStoredCompletionRequest'responseId x__) ())
newtype IncludeOption'UnrecognizedValue
  = IncludeOption'UnrecognizedValue Data.Int.Int32
  deriving stock (Prelude.Eq, Prelude.Ord, Prelude.Show)
data IncludeOption
  = INCLUDE_OPTION_INVALID |
    INCLUDE_OPTION_WEB_SEARCH_CALL_OUTPUT |
    INCLUDE_OPTION_X_SEARCH_CALL_OUTPUT |
    INCLUDE_OPTION_CODE_EXECUTION_CALL_OUTPUT |
    INCLUDE_OPTION_COLLECTIONS_SEARCH_CALL_OUTPUT |
    INCLUDE_OPTION_ATTACHMENT_SEARCH_CALL_OUTPUT |
    INCLUDE_OPTION_MCP_CALL_OUTPUT |
    INCLUDE_OPTION_INLINE_CITATIONS |
    INCLUDE_OPTION_VERBOSE_STREAMING |
    IncludeOption'Unrecognized !IncludeOption'UnrecognizedValue
  deriving stock (Prelude.Show, Prelude.Eq, Prelude.Ord)
instance Data.ProtoLens.MessageEnum IncludeOption where
  maybeToEnum 0 = Prelude.Just INCLUDE_OPTION_INVALID
  maybeToEnum 1 = Prelude.Just INCLUDE_OPTION_WEB_SEARCH_CALL_OUTPUT
  maybeToEnum 2 = Prelude.Just INCLUDE_OPTION_X_SEARCH_CALL_OUTPUT
  maybeToEnum 3
    = Prelude.Just INCLUDE_OPTION_CODE_EXECUTION_CALL_OUTPUT
  maybeToEnum 4
    = Prelude.Just INCLUDE_OPTION_COLLECTIONS_SEARCH_CALL_OUTPUT
  maybeToEnum 5
    = Prelude.Just INCLUDE_OPTION_ATTACHMENT_SEARCH_CALL_OUTPUT
  maybeToEnum 6 = Prelude.Just INCLUDE_OPTION_MCP_CALL_OUTPUT
  maybeToEnum 7 = Prelude.Just INCLUDE_OPTION_INLINE_CITATIONS
  maybeToEnum 8 = Prelude.Just INCLUDE_OPTION_VERBOSE_STREAMING
  maybeToEnum k
    = Prelude.Just
        (IncludeOption'Unrecognized
           (IncludeOption'UnrecognizedValue (Prelude.fromIntegral k)))
  showEnum INCLUDE_OPTION_INVALID = "INCLUDE_OPTION_INVALID"
  showEnum INCLUDE_OPTION_WEB_SEARCH_CALL_OUTPUT
    = "INCLUDE_OPTION_WEB_SEARCH_CALL_OUTPUT"
  showEnum INCLUDE_OPTION_X_SEARCH_CALL_OUTPUT
    = "INCLUDE_OPTION_X_SEARCH_CALL_OUTPUT"
  showEnum INCLUDE_OPTION_CODE_EXECUTION_CALL_OUTPUT
    = "INCLUDE_OPTION_CODE_EXECUTION_CALL_OUTPUT"
  showEnum INCLUDE_OPTION_COLLECTIONS_SEARCH_CALL_OUTPUT
    = "INCLUDE_OPTION_COLLECTIONS_SEARCH_CALL_OUTPUT"
  showEnum INCLUDE_OPTION_ATTACHMENT_SEARCH_CALL_OUTPUT
    = "INCLUDE_OPTION_ATTACHMENT_SEARCH_CALL_OUTPUT"
  showEnum INCLUDE_OPTION_MCP_CALL_OUTPUT
    = "INCLUDE_OPTION_MCP_CALL_OUTPUT"
  showEnum INCLUDE_OPTION_INLINE_CITATIONS
    = "INCLUDE_OPTION_INLINE_CITATIONS"
  showEnum INCLUDE_OPTION_VERBOSE_STREAMING
    = "INCLUDE_OPTION_VERBOSE_STREAMING"
  showEnum
    (IncludeOption'Unrecognized (IncludeOption'UnrecognizedValue k))
    = Prelude.show k
  readEnum k
    | (Prelude.==) k "INCLUDE_OPTION_INVALID"
    = Prelude.Just INCLUDE_OPTION_INVALID
    | (Prelude.==) k "INCLUDE_OPTION_WEB_SEARCH_CALL_OUTPUT"
    = Prelude.Just INCLUDE_OPTION_WEB_SEARCH_CALL_OUTPUT
    | (Prelude.==) k "INCLUDE_OPTION_X_SEARCH_CALL_OUTPUT"
    = Prelude.Just INCLUDE_OPTION_X_SEARCH_CALL_OUTPUT
    | (Prelude.==) k "INCLUDE_OPTION_CODE_EXECUTION_CALL_OUTPUT"
    = Prelude.Just INCLUDE_OPTION_CODE_EXECUTION_CALL_OUTPUT
    | (Prelude.==) k "INCLUDE_OPTION_COLLECTIONS_SEARCH_CALL_OUTPUT"
    = Prelude.Just INCLUDE_OPTION_COLLECTIONS_SEARCH_CALL_OUTPUT
    | (Prelude.==) k "INCLUDE_OPTION_ATTACHMENT_SEARCH_CALL_OUTPUT"
    = Prelude.Just INCLUDE_OPTION_ATTACHMENT_SEARCH_CALL_OUTPUT
    | (Prelude.==) k "INCLUDE_OPTION_MCP_CALL_OUTPUT"
    = Prelude.Just INCLUDE_OPTION_MCP_CALL_OUTPUT
    | (Prelude.==) k "INCLUDE_OPTION_INLINE_CITATIONS"
    = Prelude.Just INCLUDE_OPTION_INLINE_CITATIONS
    | (Prelude.==) k "INCLUDE_OPTION_VERBOSE_STREAMING"
    = Prelude.Just INCLUDE_OPTION_VERBOSE_STREAMING
    | Prelude.otherwise
    = (Prelude.>>=) (Text.Read.readMaybe k) Data.ProtoLens.maybeToEnum
instance Prelude.Bounded IncludeOption where
  minBound = INCLUDE_OPTION_INVALID
  maxBound = INCLUDE_OPTION_VERBOSE_STREAMING
instance Prelude.Enum IncludeOption where
  toEnum k__
    = Prelude.maybe
        (Prelude.error
           ((Prelude.++)
              "toEnum: unknown value for enum IncludeOption: "
              (Prelude.show k__)))
        Prelude.id (Data.ProtoLens.maybeToEnum k__)
  fromEnum INCLUDE_OPTION_INVALID = 0
  fromEnum INCLUDE_OPTION_WEB_SEARCH_CALL_OUTPUT = 1
  fromEnum INCLUDE_OPTION_X_SEARCH_CALL_OUTPUT = 2
  fromEnum INCLUDE_OPTION_CODE_EXECUTION_CALL_OUTPUT = 3
  fromEnum INCLUDE_OPTION_COLLECTIONS_SEARCH_CALL_OUTPUT = 4
  fromEnum INCLUDE_OPTION_ATTACHMENT_SEARCH_CALL_OUTPUT = 5
  fromEnum INCLUDE_OPTION_MCP_CALL_OUTPUT = 6
  fromEnum INCLUDE_OPTION_INLINE_CITATIONS = 7
  fromEnum INCLUDE_OPTION_VERBOSE_STREAMING = 8
  fromEnum
    (IncludeOption'Unrecognized (IncludeOption'UnrecognizedValue k))
    = Prelude.fromIntegral k
  succ INCLUDE_OPTION_VERBOSE_STREAMING
    = Prelude.error
        "IncludeOption.succ: bad argument INCLUDE_OPTION_VERBOSE_STREAMING. This value would be out of bounds."
  succ INCLUDE_OPTION_INVALID = INCLUDE_OPTION_WEB_SEARCH_CALL_OUTPUT
  succ INCLUDE_OPTION_WEB_SEARCH_CALL_OUTPUT
    = INCLUDE_OPTION_X_SEARCH_CALL_OUTPUT
  succ INCLUDE_OPTION_X_SEARCH_CALL_OUTPUT
    = INCLUDE_OPTION_CODE_EXECUTION_CALL_OUTPUT
  succ INCLUDE_OPTION_CODE_EXECUTION_CALL_OUTPUT
    = INCLUDE_OPTION_COLLECTIONS_SEARCH_CALL_OUTPUT
  succ INCLUDE_OPTION_COLLECTIONS_SEARCH_CALL_OUTPUT
    = INCLUDE_OPTION_ATTACHMENT_SEARCH_CALL_OUTPUT
  succ INCLUDE_OPTION_ATTACHMENT_SEARCH_CALL_OUTPUT
    = INCLUDE_OPTION_MCP_CALL_OUTPUT
  succ INCLUDE_OPTION_MCP_CALL_OUTPUT
    = INCLUDE_OPTION_INLINE_CITATIONS
  succ INCLUDE_OPTION_INLINE_CITATIONS
    = INCLUDE_OPTION_VERBOSE_STREAMING
  succ (IncludeOption'Unrecognized _)
    = Prelude.error
        "IncludeOption.succ: bad argument: unrecognized value"
  pred INCLUDE_OPTION_INVALID
    = Prelude.error
        "IncludeOption.pred: bad argument INCLUDE_OPTION_INVALID. This value would be out of bounds."
  pred INCLUDE_OPTION_WEB_SEARCH_CALL_OUTPUT = INCLUDE_OPTION_INVALID
  pred INCLUDE_OPTION_X_SEARCH_CALL_OUTPUT
    = INCLUDE_OPTION_WEB_SEARCH_CALL_OUTPUT
  pred INCLUDE_OPTION_CODE_EXECUTION_CALL_OUTPUT
    = INCLUDE_OPTION_X_SEARCH_CALL_OUTPUT
  pred INCLUDE_OPTION_COLLECTIONS_SEARCH_CALL_OUTPUT
    = INCLUDE_OPTION_CODE_EXECUTION_CALL_OUTPUT
  pred INCLUDE_OPTION_ATTACHMENT_SEARCH_CALL_OUTPUT
    = INCLUDE_OPTION_COLLECTIONS_SEARCH_CALL_OUTPUT
  pred INCLUDE_OPTION_MCP_CALL_OUTPUT
    = INCLUDE_OPTION_ATTACHMENT_SEARCH_CALL_OUTPUT
  pred INCLUDE_OPTION_INLINE_CITATIONS
    = INCLUDE_OPTION_MCP_CALL_OUTPUT
  pred INCLUDE_OPTION_VERBOSE_STREAMING
    = INCLUDE_OPTION_INLINE_CITATIONS
  pred (IncludeOption'Unrecognized _)
    = Prelude.error
        "IncludeOption.pred: bad argument: unrecognized value"
  enumFrom = Data.ProtoLens.Message.Enum.messageEnumFrom
  enumFromTo = Data.ProtoLens.Message.Enum.messageEnumFromTo
  enumFromThen = Data.ProtoLens.Message.Enum.messageEnumFromThen
  enumFromThenTo = Data.ProtoLens.Message.Enum.messageEnumFromThenTo
instance Data.ProtoLens.FieldDefault IncludeOption where
  fieldDefault = INCLUDE_OPTION_INVALID
instance Control.DeepSeq.NFData IncludeOption where
  rnf x__ = Prelude.seq x__ ()
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Chat_Fields.id' @:: Lens' InlineCitation Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.startIndex' @:: Lens' InlineCitation Data.Int.Int32@
         * 'Proto.Xai.Api.V1.Chat_Fields.endIndex' @:: Lens' InlineCitation Data.Int.Int32@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'citation' @:: Lens' InlineCitation (Prelude.Maybe InlineCitation'Citation)@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'webCitation' @:: Lens' InlineCitation (Prelude.Maybe WebCitation)@
         * 'Proto.Xai.Api.V1.Chat_Fields.webCitation' @:: Lens' InlineCitation WebCitation@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'xCitation' @:: Lens' InlineCitation (Prelude.Maybe XCitation)@
         * 'Proto.Xai.Api.V1.Chat_Fields.xCitation' @:: Lens' InlineCitation XCitation@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'collectionsCitation' @:: Lens' InlineCitation (Prelude.Maybe CollectionsCitation)@
         * 'Proto.Xai.Api.V1.Chat_Fields.collectionsCitation' @:: Lens' InlineCitation CollectionsCitation@ -}
data InlineCitation
  = InlineCitation'_constructor {_InlineCitation'id :: !Data.Text.Text,
                                 _InlineCitation'startIndex :: !Data.Int.Int32,
                                 _InlineCitation'endIndex :: !Data.Int.Int32,
                                 _InlineCitation'citation :: !(Prelude.Maybe InlineCitation'Citation),
                                 _InlineCitation'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show InlineCitation where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
data InlineCitation'Citation
  = InlineCitation'WebCitation !WebCitation |
    InlineCitation'XCitation !XCitation |
    InlineCitation'CollectionsCitation !CollectionsCitation
  deriving stock (Prelude.Show, Prelude.Eq, Prelude.Ord)
instance Data.ProtoLens.Field.HasField InlineCitation "id" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _InlineCitation'id (\ x__ y__ -> x__ {_InlineCitation'id = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField InlineCitation "startIndex" Data.Int.Int32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _InlineCitation'startIndex
           (\ x__ y__ -> x__ {_InlineCitation'startIndex = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField InlineCitation "endIndex" Data.Int.Int32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _InlineCitation'endIndex
           (\ x__ y__ -> x__ {_InlineCitation'endIndex = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField InlineCitation "maybe'citation" (Prelude.Maybe InlineCitation'Citation) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _InlineCitation'citation
           (\ x__ y__ -> x__ {_InlineCitation'citation = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField InlineCitation "maybe'webCitation" (Prelude.Maybe WebCitation) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _InlineCitation'citation
           (\ x__ y__ -> x__ {_InlineCitation'citation = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (InlineCitation'WebCitation x__val))
                     -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap InlineCitation'WebCitation y__))
instance Data.ProtoLens.Field.HasField InlineCitation "webCitation" WebCitation where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _InlineCitation'citation
           (\ x__ y__ -> x__ {_InlineCitation'citation = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (InlineCitation'WebCitation x__val))
                        -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap InlineCitation'WebCitation y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Field.HasField InlineCitation "maybe'xCitation" (Prelude.Maybe XCitation) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _InlineCitation'citation
           (\ x__ y__ -> x__ {_InlineCitation'citation = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (InlineCitation'XCitation x__val))
                     -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap InlineCitation'XCitation y__))
instance Data.ProtoLens.Field.HasField InlineCitation "xCitation" XCitation where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _InlineCitation'citation
           (\ x__ y__ -> x__ {_InlineCitation'citation = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (InlineCitation'XCitation x__val))
                        -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap InlineCitation'XCitation y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Field.HasField InlineCitation "maybe'collectionsCitation" (Prelude.Maybe CollectionsCitation) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _InlineCitation'citation
           (\ x__ y__ -> x__ {_InlineCitation'citation = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (InlineCitation'CollectionsCitation x__val))
                     -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap InlineCitation'CollectionsCitation y__))
instance Data.ProtoLens.Field.HasField InlineCitation "collectionsCitation" CollectionsCitation where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _InlineCitation'citation
           (\ x__ y__ -> x__ {_InlineCitation'citation = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (InlineCitation'CollectionsCitation x__val))
                        -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap InlineCitation'CollectionsCitation y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Message InlineCitation where
  messageName _ = Data.Text.pack "xai_api.InlineCitation"
  packedMessageDescriptor _
    = "\n\
      \\SOInlineCitation\DC2\SO\n\
      \\STXid\CAN\SOH \SOH(\tR\STXid\DC2\US\n\
      \\vstart_index\CAN\STX \SOH(\ENQR\n\
      \startIndex\DC2\ESC\n\
      \\tend_index\CAN\ACK \SOH(\ENQR\bendIndex\DC29\n\
      \\fweb_citation\CAN\ETX \SOH(\v2\DC4.xai_api.WebCitationH\NULR\vwebCitation\DC23\n\
      \\n\
      \x_citation\CAN\EOT \SOH(\v2\DC2.xai_api.XCitationH\NULR\txCitation\DC2Q\n\
      \\DC4collections_citation\CAN\ENQ \SOH(\v2\FS.xai_api.CollectionsCitationH\NULR\DC3collectionsCitationB\n\
      \\n\
      \\bcitation"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        id__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "id"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"id")) ::
              Data.ProtoLens.FieldDescriptor InlineCitation
        startIndex__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "start_index"
              (Data.ProtoLens.ScalarField Data.ProtoLens.Int32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Int.Int32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"startIndex")) ::
              Data.ProtoLens.FieldDescriptor InlineCitation
        endIndex__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "end_index"
              (Data.ProtoLens.ScalarField Data.ProtoLens.Int32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Int.Int32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"endIndex")) ::
              Data.ProtoLens.FieldDescriptor InlineCitation
        webCitation__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "web_citation"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor WebCitation)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'webCitation")) ::
              Data.ProtoLens.FieldDescriptor InlineCitation
        xCitation__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "x_citation"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor XCitation)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'xCitation")) ::
              Data.ProtoLens.FieldDescriptor InlineCitation
        collectionsCitation__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "collections_citation"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor CollectionsCitation)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'collectionsCitation")) ::
              Data.ProtoLens.FieldDescriptor InlineCitation
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, id__field_descriptor),
           (Data.ProtoLens.Tag 2, startIndex__field_descriptor),
           (Data.ProtoLens.Tag 6, endIndex__field_descriptor),
           (Data.ProtoLens.Tag 3, webCitation__field_descriptor),
           (Data.ProtoLens.Tag 4, xCitation__field_descriptor),
           (Data.ProtoLens.Tag 5, collectionsCitation__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _InlineCitation'_unknownFields
        (\ x__ y__ -> x__ {_InlineCitation'_unknownFields = y__})
  defMessage
    = InlineCitation'_constructor
        {_InlineCitation'id = Data.ProtoLens.fieldDefault,
         _InlineCitation'startIndex = Data.ProtoLens.fieldDefault,
         _InlineCitation'endIndex = Data.ProtoLens.fieldDefault,
         _InlineCitation'citation = Prelude.Nothing,
         _InlineCitation'_unknownFields = []}
  parseMessage
    = let
        loop ::
          InlineCitation
          -> Data.ProtoLens.Encoding.Bytes.Parser InlineCitation
        loop x
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t) x)
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "id"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"id") y x)
                        16
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "start_index"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"startIndex") y x)
                        48
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "end_index"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"endIndex") y x)
                        26
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "web_citation"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"webCitation") y x)
                        34
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "x_citation"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"xCitation") y x)
                        42
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "collections_citation"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"collectionsCitation") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "InlineCitation"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let _v = Lens.Family2.view (Data.ProtoLens.Field.field @"id") _x
              in
                if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                      ((Prelude..)
                         (\ bs
                            -> (Data.Monoid.<>)
                                 (Data.ProtoLens.Encoding.Bytes.putVarInt
                                    (Prelude.fromIntegral (Data.ByteString.length bs)))
                                 (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                         Data.Text.Encoding.encodeUtf8 _v))
             ((Data.Monoid.<>)
                (let
                   _v
                     = Lens.Family2.view (Data.ProtoLens.Field.field @"startIndex") _x
                 in
                   if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                       Data.Monoid.mempty
                   else
                       (Data.Monoid.<>)
                         (Data.ProtoLens.Encoding.Bytes.putVarInt 16)
                         ((Prelude..)
                            Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral _v))
                ((Data.Monoid.<>)
                   (let
                      _v = Lens.Family2.view (Data.ProtoLens.Field.field @"endIndex") _x
                    in
                      if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                          Data.Monoid.mempty
                      else
                          (Data.Monoid.<>)
                            (Data.ProtoLens.Encoding.Bytes.putVarInt 48)
                            ((Prelude..)
                               Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral _v))
                   ((Data.Monoid.<>)
                      (case
                           Lens.Family2.view (Data.ProtoLens.Field.field @"maybe'citation") _x
                       of
                         Prelude.Nothing -> Data.Monoid.mempty
                         (Prelude.Just (InlineCitation'WebCitation v))
                           -> (Data.Monoid.<>)
                                (Data.ProtoLens.Encoding.Bytes.putVarInt 26)
                                ((Prelude..)
                                   (\ bs
                                      -> (Data.Monoid.<>)
                                           (Data.ProtoLens.Encoding.Bytes.putVarInt
                                              (Prelude.fromIntegral (Data.ByteString.length bs)))
                                           (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                   Data.ProtoLens.encodeMessage v)
                         (Prelude.Just (InlineCitation'XCitation v))
                           -> (Data.Monoid.<>)
                                (Data.ProtoLens.Encoding.Bytes.putVarInt 34)
                                ((Prelude..)
                                   (\ bs
                                      -> (Data.Monoid.<>)
                                           (Data.ProtoLens.Encoding.Bytes.putVarInt
                                              (Prelude.fromIntegral (Data.ByteString.length bs)))
                                           (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                   Data.ProtoLens.encodeMessage v)
                         (Prelude.Just (InlineCitation'CollectionsCitation v))
                           -> (Data.Monoid.<>)
                                (Data.ProtoLens.Encoding.Bytes.putVarInt 42)
                                ((Prelude..)
                                   (\ bs
                                      -> (Data.Monoid.<>)
                                           (Data.ProtoLens.Encoding.Bytes.putVarInt
                                              (Prelude.fromIntegral (Data.ByteString.length bs)))
                                           (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                   Data.ProtoLens.encodeMessage v))
                      (Data.ProtoLens.Encoding.Wire.buildFieldSet
                         (Lens.Family2.view Data.ProtoLens.unknownFields _x)))))
instance Control.DeepSeq.NFData InlineCitation where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_InlineCitation'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_InlineCitation'id x__)
                (Control.DeepSeq.deepseq
                   (_InlineCitation'startIndex x__)
                   (Control.DeepSeq.deepseq
                      (_InlineCitation'endIndex x__)
                      (Control.DeepSeq.deepseq (_InlineCitation'citation x__) ()))))
instance Control.DeepSeq.NFData InlineCitation'Citation where
  rnf (InlineCitation'WebCitation x__) = Control.DeepSeq.rnf x__
  rnf (InlineCitation'XCitation x__) = Control.DeepSeq.rnf x__
  rnf (InlineCitation'CollectionsCitation x__)
    = Control.DeepSeq.rnf x__
_InlineCitation'WebCitation ::
  Data.ProtoLens.Prism.Prism' InlineCitation'Citation WebCitation
_InlineCitation'WebCitation
  = Data.ProtoLens.Prism.prism'
      InlineCitation'WebCitation
      (\ p__
         -> case p__ of
              (InlineCitation'WebCitation p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
_InlineCitation'XCitation ::
  Data.ProtoLens.Prism.Prism' InlineCitation'Citation XCitation
_InlineCitation'XCitation
  = Data.ProtoLens.Prism.prism'
      InlineCitation'XCitation
      (\ p__
         -> case p__ of
              (InlineCitation'XCitation p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
_InlineCitation'CollectionsCitation ::
  Data.ProtoLens.Prism.Prism' InlineCitation'Citation CollectionsCitation
_InlineCitation'CollectionsCitation
  = Data.ProtoLens.Prism.prism'
      InlineCitation'CollectionsCitation
      (\ p__
         -> case p__ of
              (InlineCitation'CollectionsCitation p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Chat_Fields.token' @:: Lens' LogProb Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.logprob' @:: Lens' LogProb Prelude.Float@
         * 'Proto.Xai.Api.V1.Chat_Fields.bytes' @:: Lens' LogProb Data.ByteString.ByteString@
         * 'Proto.Xai.Api.V1.Chat_Fields.topLogprobs' @:: Lens' LogProb [TopLogProb]@
         * 'Proto.Xai.Api.V1.Chat_Fields.vec'topLogprobs' @:: Lens' LogProb (Data.Vector.Vector TopLogProb)@ -}
data LogProb
  = LogProb'_constructor {_LogProb'token :: !Data.Text.Text,
                          _LogProb'logprob :: !Prelude.Float,
                          _LogProb'bytes :: !Data.ByteString.ByteString,
                          _LogProb'topLogprobs :: !(Data.Vector.Vector TopLogProb),
                          _LogProb'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show LogProb where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField LogProb "token" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _LogProb'token (\ x__ y__ -> x__ {_LogProb'token = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField LogProb "logprob" Prelude.Float where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _LogProb'logprob (\ x__ y__ -> x__ {_LogProb'logprob = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField LogProb "bytes" Data.ByteString.ByteString where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _LogProb'bytes (\ x__ y__ -> x__ {_LogProb'bytes = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField LogProb "topLogprobs" [TopLogProb] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _LogProb'topLogprobs
           (\ x__ y__ -> x__ {_LogProb'topLogprobs = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField LogProb "vec'topLogprobs" (Data.Vector.Vector TopLogProb) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _LogProb'topLogprobs
           (\ x__ y__ -> x__ {_LogProb'topLogprobs = y__}))
        Prelude.id
instance Data.ProtoLens.Message LogProb where
  messageName _ = Data.Text.pack "xai_api.LogProb"
  packedMessageDescriptor _
    = "\n\
      \\aLogProb\DC2\DC4\n\
      \\ENQtoken\CAN\SOH \SOH(\tR\ENQtoken\DC2\CAN\n\
      \\alogprob\CAN\STX \SOH(\STXR\alogprob\DC2\DC4\n\
      \\ENQbytes\CAN\ETX \SOH(\fR\ENQbytes\DC26\n\
      \\ftop_logprobs\CAN\EOT \ETX(\v2\DC3.xai_api.TopLogProbR\vtopLogprobs"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        token__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "token"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"token")) ::
              Data.ProtoLens.FieldDescriptor LogProb
        logprob__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "logprob"
              (Data.ProtoLens.ScalarField Data.ProtoLens.FloatField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Float)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"logprob")) ::
              Data.ProtoLens.FieldDescriptor LogProb
        bytes__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "bytes"
              (Data.ProtoLens.ScalarField Data.ProtoLens.BytesField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.ByteString.ByteString)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"bytes")) ::
              Data.ProtoLens.FieldDescriptor LogProb
        topLogprobs__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "top_logprobs"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor TopLogProb)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Unpacked
                 (Data.ProtoLens.Field.field @"topLogprobs")) ::
              Data.ProtoLens.FieldDescriptor LogProb
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, token__field_descriptor),
           (Data.ProtoLens.Tag 2, logprob__field_descriptor),
           (Data.ProtoLens.Tag 3, bytes__field_descriptor),
           (Data.ProtoLens.Tag 4, topLogprobs__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _LogProb'_unknownFields
        (\ x__ y__ -> x__ {_LogProb'_unknownFields = y__})
  defMessage
    = LogProb'_constructor
        {_LogProb'token = Data.ProtoLens.fieldDefault,
         _LogProb'logprob = Data.ProtoLens.fieldDefault,
         _LogProb'bytes = Data.ProtoLens.fieldDefault,
         _LogProb'topLogprobs = Data.Vector.Generic.empty,
         _LogProb'_unknownFields = []}
  parseMessage
    = let
        loop ::
          LogProb
          -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Vector Data.ProtoLens.Encoding.Growing.RealWorld TopLogProb
             -> Data.ProtoLens.Encoding.Bytes.Parser LogProb
        loop x mutable'topLogprobs
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do frozen'topLogprobs <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                              (Data.ProtoLens.Encoding.Growing.unsafeFreeze
                                                 mutable'topLogprobs)
                      (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t)
                           (Lens.Family2.set
                              (Data.ProtoLens.Field.field @"vec'topLogprobs") frozen'topLogprobs
                              x))
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "token"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"token") y x)
                                  mutable'topLogprobs
                        21
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Data.ProtoLens.Encoding.Bytes.wordToFloat
                                          Data.ProtoLens.Encoding.Bytes.getFixed32)
                                       "logprob"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"logprob") y x)
                                  mutable'topLogprobs
                        26
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getBytes
                                             (Prelude.fromIntegral len))
                                       "bytes"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"bytes") y x)
                                  mutable'topLogprobs
                        34
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                            Data.ProtoLens.Encoding.Bytes.isolate
                                              (Prelude.fromIntegral len)
                                              Data.ProtoLens.parseMessage)
                                        "top_logprobs"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append
                                          mutable'topLogprobs y)
                                loop x v
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
                                  mutable'topLogprobs
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do mutable'topLogprobs <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       Data.ProtoLens.Encoding.Growing.new
              loop Data.ProtoLens.defMessage mutable'topLogprobs)
          "LogProb"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v = Lens.Family2.view (Data.ProtoLens.Field.field @"token") _x
              in
                if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                      ((Prelude..)
                         (\ bs
                            -> (Data.Monoid.<>)
                                 (Data.ProtoLens.Encoding.Bytes.putVarInt
                                    (Prelude.fromIntegral (Data.ByteString.length bs)))
                                 (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                         Data.Text.Encoding.encodeUtf8 _v))
             ((Data.Monoid.<>)
                (let
                   _v = Lens.Family2.view (Data.ProtoLens.Field.field @"logprob") _x
                 in
                   if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                       Data.Monoid.mempty
                   else
                       (Data.Monoid.<>)
                         (Data.ProtoLens.Encoding.Bytes.putVarInt 21)
                         ((Prelude..)
                            Data.ProtoLens.Encoding.Bytes.putFixed32
                            Data.ProtoLens.Encoding.Bytes.floatToWord _v))
                ((Data.Monoid.<>)
                   (let
                      _v = Lens.Family2.view (Data.ProtoLens.Field.field @"bytes") _x
                    in
                      if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                          Data.Monoid.mempty
                      else
                          (Data.Monoid.<>)
                            (Data.ProtoLens.Encoding.Bytes.putVarInt 26)
                            ((\ bs
                                -> (Data.Monoid.<>)
                                     (Data.ProtoLens.Encoding.Bytes.putVarInt
                                        (Prelude.fromIntegral (Data.ByteString.length bs)))
                                     (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                               _v))
                   ((Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.foldMapBuilder
                         (\ _v
                            -> (Data.Monoid.<>)
                                 (Data.ProtoLens.Encoding.Bytes.putVarInt 34)
                                 ((Prelude..)
                                    (\ bs
                                       -> (Data.Monoid.<>)
                                            (Data.ProtoLens.Encoding.Bytes.putVarInt
                                               (Prelude.fromIntegral (Data.ByteString.length bs)))
                                            (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                    Data.ProtoLens.encodeMessage _v))
                         (Lens.Family2.view
                            (Data.ProtoLens.Field.field @"vec'topLogprobs") _x))
                      (Data.ProtoLens.Encoding.Wire.buildFieldSet
                         (Lens.Family2.view Data.ProtoLens.unknownFields _x)))))
instance Control.DeepSeq.NFData LogProb where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_LogProb'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_LogProb'token x__)
                (Control.DeepSeq.deepseq
                   (_LogProb'logprob x__)
                   (Control.DeepSeq.deepseq
                      (_LogProb'bytes x__)
                      (Control.DeepSeq.deepseq (_LogProb'topLogprobs x__) ()))))
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Chat_Fields.content' @:: Lens' LogProbs [LogProb]@
         * 'Proto.Xai.Api.V1.Chat_Fields.vec'content' @:: Lens' LogProbs (Data.Vector.Vector LogProb)@ -}
data LogProbs
  = LogProbs'_constructor {_LogProbs'content :: !(Data.Vector.Vector LogProb),
                           _LogProbs'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show LogProbs where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField LogProbs "content" [LogProb] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _LogProbs'content (\ x__ y__ -> x__ {_LogProbs'content = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField LogProbs "vec'content" (Data.Vector.Vector LogProb) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _LogProbs'content (\ x__ y__ -> x__ {_LogProbs'content = y__}))
        Prelude.id
instance Data.ProtoLens.Message LogProbs where
  messageName _ = Data.Text.pack "xai_api.LogProbs"
  packedMessageDescriptor _
    = "\n\
      \\bLogProbs\DC2*\n\
      \\acontent\CAN\SOH \ETX(\v2\DLE.xai_api.LogProbR\acontent"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        content__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "content"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor LogProb)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Unpacked (Data.ProtoLens.Field.field @"content")) ::
              Data.ProtoLens.FieldDescriptor LogProbs
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, content__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _LogProbs'_unknownFields
        (\ x__ y__ -> x__ {_LogProbs'_unknownFields = y__})
  defMessage
    = LogProbs'_constructor
        {_LogProbs'content = Data.Vector.Generic.empty,
         _LogProbs'_unknownFields = []}
  parseMessage
    = let
        loop ::
          LogProbs
          -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Vector Data.ProtoLens.Encoding.Growing.RealWorld LogProb
             -> Data.ProtoLens.Encoding.Bytes.Parser LogProbs
        loop x mutable'content
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do frozen'content <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                          (Data.ProtoLens.Encoding.Growing.unsafeFreeze
                                             mutable'content)
                      (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t)
                           (Lens.Family2.set
                              (Data.ProtoLens.Field.field @"vec'content") frozen'content x))
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                            Data.ProtoLens.Encoding.Bytes.isolate
                                              (Prelude.fromIntegral len)
                                              Data.ProtoLens.parseMessage)
                                        "content"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append mutable'content y)
                                loop x v
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
                                  mutable'content
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do mutable'content <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                   Data.ProtoLens.Encoding.Growing.new
              loop Data.ProtoLens.defMessage mutable'content)
          "LogProbs"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (Data.ProtoLens.Encoding.Bytes.foldMapBuilder
                (\ _v
                   -> (Data.Monoid.<>)
                        (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                        ((Prelude..)
                           (\ bs
                              -> (Data.Monoid.<>)
                                   (Data.ProtoLens.Encoding.Bytes.putVarInt
                                      (Prelude.fromIntegral (Data.ByteString.length bs)))
                                   (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                           Data.ProtoLens.encodeMessage _v))
                (Lens.Family2.view (Data.ProtoLens.Field.field @"vec'content") _x))
             (Data.ProtoLens.Encoding.Wire.buildFieldSet
                (Lens.Family2.view Data.ProtoLens.unknownFields _x))
instance Control.DeepSeq.NFData LogProbs where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_LogProbs'_unknownFields x__)
             (Control.DeepSeq.deepseq (_LogProbs'content x__) ())
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Chat_Fields.serverLabel' @:: Lens' MCP Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.serverDescription' @:: Lens' MCP Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.serverUrl' @:: Lens' MCP Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.allowedToolNames' @:: Lens' MCP [Data.Text.Text]@
         * 'Proto.Xai.Api.V1.Chat_Fields.vec'allowedToolNames' @:: Lens' MCP (Data.Vector.Vector Data.Text.Text)@
         * 'Proto.Xai.Api.V1.Chat_Fields.authorization' @:: Lens' MCP Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'authorization' @:: Lens' MCP (Prelude.Maybe Data.Text.Text)@
         * 'Proto.Xai.Api.V1.Chat_Fields.extraHeaders' @:: Lens' MCP (Data.Map.Map Data.Text.Text Data.Text.Text)@ -}
data MCP
  = MCP'_constructor {_MCP'serverLabel :: !Data.Text.Text,
                      _MCP'serverDescription :: !Data.Text.Text,
                      _MCP'serverUrl :: !Data.Text.Text,
                      _MCP'allowedToolNames :: !(Data.Vector.Vector Data.Text.Text),
                      _MCP'authorization :: !(Prelude.Maybe Data.Text.Text),
                      _MCP'extraHeaders :: !(Data.Map.Map Data.Text.Text Data.Text.Text),
                      _MCP'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show MCP where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField MCP "serverLabel" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _MCP'serverLabel (\ x__ y__ -> x__ {_MCP'serverLabel = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField MCP "serverDescription" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _MCP'serverDescription
           (\ x__ y__ -> x__ {_MCP'serverDescription = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField MCP "serverUrl" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _MCP'serverUrl (\ x__ y__ -> x__ {_MCP'serverUrl = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField MCP "allowedToolNames" [Data.Text.Text] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _MCP'allowedToolNames
           (\ x__ y__ -> x__ {_MCP'allowedToolNames = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField MCP "vec'allowedToolNames" (Data.Vector.Vector Data.Text.Text) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _MCP'allowedToolNames
           (\ x__ y__ -> x__ {_MCP'allowedToolNames = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField MCP "authorization" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _MCP'authorization (\ x__ y__ -> x__ {_MCP'authorization = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField MCP "maybe'authorization" (Prelude.Maybe Data.Text.Text) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _MCP'authorization (\ x__ y__ -> x__ {_MCP'authorization = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField MCP "extraHeaders" (Data.Map.Map Data.Text.Text Data.Text.Text) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _MCP'extraHeaders (\ x__ y__ -> x__ {_MCP'extraHeaders = y__}))
        Prelude.id
instance Data.ProtoLens.Message MCP where
  messageName _ = Data.Text.pack "xai_api.MCP"
  packedMessageDescriptor _
    = "\n\
      \\ETXMCP\DC2!\n\
      \\fserver_label\CAN\SOH \SOH(\tR\vserverLabel\DC2-\n\
      \\DC2server_description\CAN\STX \SOH(\tR\DC1serverDescription\DC2\GS\n\
      \\n\
      \server_url\CAN\ETX \SOH(\tR\tserverUrl\DC2,\n\
      \\DC2allowed_tool_names\CAN\EOT \ETX(\tR\DLEallowedToolNames\DC2)\n\
      \\rauthorization\CAN\ENQ \SOH(\tH\NULR\rauthorization\136\SOH\SOH\DC2C\n\
      \\rextra_headers\CAN\ACK \ETX(\v2\RS.xai_api.MCP.ExtraHeadersEntryR\fextraHeaders\SUB?\n\
      \\DC1ExtraHeadersEntry\DC2\DLE\n\
      \\ETXkey\CAN\SOH \SOH(\tR\ETXkey\DC2\DC4\n\
      \\ENQvalue\CAN\STX \SOH(\tR\ENQvalue:\STX8\SOHB\DLE\n\
      \\SO_authorization"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        serverLabel__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "server_label"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"serverLabel")) ::
              Data.ProtoLens.FieldDescriptor MCP
        serverDescription__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "server_description"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"serverDescription")) ::
              Data.ProtoLens.FieldDescriptor MCP
        serverUrl__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "server_url"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"serverUrl")) ::
              Data.ProtoLens.FieldDescriptor MCP
        allowedToolNames__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "allowed_tool_names"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Unpacked
                 (Data.ProtoLens.Field.field @"allowedToolNames")) ::
              Data.ProtoLens.FieldDescriptor MCP
        authorization__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "authorization"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'authorization")) ::
              Data.ProtoLens.FieldDescriptor MCP
        extraHeaders__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "extra_headers"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor MCP'ExtraHeadersEntry)
              (Data.ProtoLens.MapField
                 (Data.ProtoLens.Field.field @"key")
                 (Data.ProtoLens.Field.field @"value")
                 (Data.ProtoLens.Field.field @"extraHeaders")) ::
              Data.ProtoLens.FieldDescriptor MCP
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, serverLabel__field_descriptor),
           (Data.ProtoLens.Tag 2, serverDescription__field_descriptor),
           (Data.ProtoLens.Tag 3, serverUrl__field_descriptor),
           (Data.ProtoLens.Tag 4, allowedToolNames__field_descriptor),
           (Data.ProtoLens.Tag 5, authorization__field_descriptor),
           (Data.ProtoLens.Tag 6, extraHeaders__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _MCP'_unknownFields (\ x__ y__ -> x__ {_MCP'_unknownFields = y__})
  defMessage
    = MCP'_constructor
        {_MCP'serverLabel = Data.ProtoLens.fieldDefault,
         _MCP'serverDescription = Data.ProtoLens.fieldDefault,
         _MCP'serverUrl = Data.ProtoLens.fieldDefault,
         _MCP'allowedToolNames = Data.Vector.Generic.empty,
         _MCP'authorization = Prelude.Nothing,
         _MCP'extraHeaders = Data.Map.empty, _MCP'_unknownFields = []}
  parseMessage
    = let
        loop ::
          MCP
          -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Vector Data.ProtoLens.Encoding.Growing.RealWorld Data.Text.Text
             -> Data.ProtoLens.Encoding.Bytes.Parser MCP
        loop x mutable'allowedToolNames
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do frozen'allowedToolNames <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                                   (Data.ProtoLens.Encoding.Growing.unsafeFreeze
                                                      mutable'allowedToolNames)
                      (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t)
                           (Lens.Family2.set
                              (Data.ProtoLens.Field.field @"vec'allowedToolNames")
                              frozen'allowedToolNames x))
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "server_label"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"serverLabel") y x)
                                  mutable'allowedToolNames
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "server_description"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"serverDescription") y x)
                                  mutable'allowedToolNames
                        26
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "server_url"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"serverUrl") y x)
                                  mutable'allowedToolNames
                        34
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                            Data.ProtoLens.Encoding.Bytes.getText
                                              (Prelude.fromIntegral len))
                                        "allowed_tool_names"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append
                                          mutable'allowedToolNames y)
                                loop x v
                        42
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "authorization"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"authorization") y x)
                                  mutable'allowedToolNames
                        50
                          -> do !(entry :: MCP'ExtraHeadersEntry) <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                                                           Data.ProtoLens.Encoding.Bytes.isolate
                                                                             (Prelude.fromIntegral
                                                                                len)
                                                                             Data.ProtoLens.parseMessage)
                                                                       "extra_headers"
                                (let
                                   key = Lens.Family2.view (Data.ProtoLens.Field.field @"key") entry
                                   value
                                     = Lens.Family2.view (Data.ProtoLens.Field.field @"value") entry
                                 in
                                   loop
                                     (Lens.Family2.over
                                        (Data.ProtoLens.Field.field @"extraHeaders")
                                        (\ !t -> Data.Map.insert key value t) x)
                                     mutable'allowedToolNames)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
                                  mutable'allowedToolNames
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do mutable'allowedToolNames <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                            Data.ProtoLens.Encoding.Growing.new
              loop Data.ProtoLens.defMessage mutable'allowedToolNames)
          "MCP"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v
                  = Lens.Family2.view (Data.ProtoLens.Field.field @"serverLabel") _x
              in
                if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                      ((Prelude..)
                         (\ bs
                            -> (Data.Monoid.<>)
                                 (Data.ProtoLens.Encoding.Bytes.putVarInt
                                    (Prelude.fromIntegral (Data.ByteString.length bs)))
                                 (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                         Data.Text.Encoding.encodeUtf8 _v))
             ((Data.Monoid.<>)
                (let
                   _v
                     = Lens.Family2.view
                         (Data.ProtoLens.Field.field @"serverDescription") _x
                 in
                   if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                       Data.Monoid.mempty
                   else
                       (Data.Monoid.<>)
                         (Data.ProtoLens.Encoding.Bytes.putVarInt 18)
                         ((Prelude..)
                            (\ bs
                               -> (Data.Monoid.<>)
                                    (Data.ProtoLens.Encoding.Bytes.putVarInt
                                       (Prelude.fromIntegral (Data.ByteString.length bs)))
                                    (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                            Data.Text.Encoding.encodeUtf8 _v))
                ((Data.Monoid.<>)
                   (let
                      _v = Lens.Family2.view (Data.ProtoLens.Field.field @"serverUrl") _x
                    in
                      if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                          Data.Monoid.mempty
                      else
                          (Data.Monoid.<>)
                            (Data.ProtoLens.Encoding.Bytes.putVarInt 26)
                            ((Prelude..)
                               (\ bs
                                  -> (Data.Monoid.<>)
                                       (Data.ProtoLens.Encoding.Bytes.putVarInt
                                          (Prelude.fromIntegral (Data.ByteString.length bs)))
                                       (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                               Data.Text.Encoding.encodeUtf8 _v))
                   ((Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.foldMapBuilder
                         (\ _v
                            -> (Data.Monoid.<>)
                                 (Data.ProtoLens.Encoding.Bytes.putVarInt 34)
                                 ((Prelude..)
                                    (\ bs
                                       -> (Data.Monoid.<>)
                                            (Data.ProtoLens.Encoding.Bytes.putVarInt
                                               (Prelude.fromIntegral (Data.ByteString.length bs)))
                                            (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                    Data.Text.Encoding.encodeUtf8 _v))
                         (Lens.Family2.view
                            (Data.ProtoLens.Field.field @"vec'allowedToolNames") _x))
                      ((Data.Monoid.<>)
                         (case
                              Lens.Family2.view
                                (Data.ProtoLens.Field.field @"maybe'authorization") _x
                          of
                            Prelude.Nothing -> Data.Monoid.mempty
                            (Prelude.Just _v)
                              -> (Data.Monoid.<>)
                                   (Data.ProtoLens.Encoding.Bytes.putVarInt 42)
                                   ((Prelude..)
                                      (\ bs
                                         -> (Data.Monoid.<>)
                                              (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                 (Prelude.fromIntegral (Data.ByteString.length bs)))
                                              (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                      Data.Text.Encoding.encodeUtf8 _v))
                         ((Data.Monoid.<>)
                            (Data.Monoid.mconcat
                               (Prelude.map
                                  (\ _v
                                     -> (Data.Monoid.<>)
                                          (Data.ProtoLens.Encoding.Bytes.putVarInt 50)
                                          ((Prelude..)
                                             (\ bs
                                                -> (Data.Monoid.<>)
                                                     (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                        (Prelude.fromIntegral
                                                           (Data.ByteString.length bs)))
                                                     (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                             Data.ProtoLens.encodeMessage
                                             (Lens.Family2.set
                                                (Data.ProtoLens.Field.field @"key") (Prelude.fst _v)
                                                (Lens.Family2.set
                                                   (Data.ProtoLens.Field.field @"value")
                                                   (Prelude.snd _v)
                                                   (Data.ProtoLens.defMessage ::
                                                      MCP'ExtraHeadersEntry)))))
                                  (Data.Map.toList
                                     (Lens.Family2.view
                                        (Data.ProtoLens.Field.field @"extraHeaders") _x))))
                            (Data.ProtoLens.Encoding.Wire.buildFieldSet
                               (Lens.Family2.view Data.ProtoLens.unknownFields _x)))))))
instance Control.DeepSeq.NFData MCP where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_MCP'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_MCP'serverLabel x__)
                (Control.DeepSeq.deepseq
                   (_MCP'serverDescription x__)
                   (Control.DeepSeq.deepseq
                      (_MCP'serverUrl x__)
                      (Control.DeepSeq.deepseq
                         (_MCP'allowedToolNames x__)
                         (Control.DeepSeq.deepseq
                            (_MCP'authorization x__)
                            (Control.DeepSeq.deepseq (_MCP'extraHeaders x__) ()))))))
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Chat_Fields.key' @:: Lens' MCP'ExtraHeadersEntry Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.value' @:: Lens' MCP'ExtraHeadersEntry Data.Text.Text@ -}
data MCP'ExtraHeadersEntry
  = MCP'ExtraHeadersEntry'_constructor {_MCP'ExtraHeadersEntry'key :: !Data.Text.Text,
                                        _MCP'ExtraHeadersEntry'value :: !Data.Text.Text,
                                        _MCP'ExtraHeadersEntry'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show MCP'ExtraHeadersEntry where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField MCP'ExtraHeadersEntry "key" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _MCP'ExtraHeadersEntry'key
           (\ x__ y__ -> x__ {_MCP'ExtraHeadersEntry'key = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField MCP'ExtraHeadersEntry "value" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _MCP'ExtraHeadersEntry'value
           (\ x__ y__ -> x__ {_MCP'ExtraHeadersEntry'value = y__}))
        Prelude.id
instance Data.ProtoLens.Message MCP'ExtraHeadersEntry where
  messageName _ = Data.Text.pack "xai_api.MCP.ExtraHeadersEntry"
  packedMessageDescriptor _
    = "\n\
      \\DC1ExtraHeadersEntry\DC2\DLE\n\
      \\ETXkey\CAN\SOH \SOH(\tR\ETXkey\DC2\DC4\n\
      \\ENQvalue\CAN\STX \SOH(\tR\ENQvalue:\STX8\SOH"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        key__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "key"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"key")) ::
              Data.ProtoLens.FieldDescriptor MCP'ExtraHeadersEntry
        value__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "value"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"value")) ::
              Data.ProtoLens.FieldDescriptor MCP'ExtraHeadersEntry
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, key__field_descriptor),
           (Data.ProtoLens.Tag 2, value__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _MCP'ExtraHeadersEntry'_unknownFields
        (\ x__ y__ -> x__ {_MCP'ExtraHeadersEntry'_unknownFields = y__})
  defMessage
    = MCP'ExtraHeadersEntry'_constructor
        {_MCP'ExtraHeadersEntry'key = Data.ProtoLens.fieldDefault,
         _MCP'ExtraHeadersEntry'value = Data.ProtoLens.fieldDefault,
         _MCP'ExtraHeadersEntry'_unknownFields = []}
  parseMessage
    = let
        loop ::
          MCP'ExtraHeadersEntry
          -> Data.ProtoLens.Encoding.Bytes.Parser MCP'ExtraHeadersEntry
        loop x
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t) x)
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "key"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"key") y x)
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "value"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"value") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "ExtraHeadersEntry"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let _v = Lens.Family2.view (Data.ProtoLens.Field.field @"key") _x
              in
                if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                      ((Prelude..)
                         (\ bs
                            -> (Data.Monoid.<>)
                                 (Data.ProtoLens.Encoding.Bytes.putVarInt
                                    (Prelude.fromIntegral (Data.ByteString.length bs)))
                                 (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                         Data.Text.Encoding.encodeUtf8 _v))
             ((Data.Monoid.<>)
                (let
                   _v = Lens.Family2.view (Data.ProtoLens.Field.field @"value") _x
                 in
                   if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                       Data.Monoid.mempty
                   else
                       (Data.Monoid.<>)
                         (Data.ProtoLens.Encoding.Bytes.putVarInt 18)
                         ((Prelude..)
                            (\ bs
                               -> (Data.Monoid.<>)
                                    (Data.ProtoLens.Encoding.Bytes.putVarInt
                                       (Prelude.fromIntegral (Data.ByteString.length bs)))
                                    (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                            Data.Text.Encoding.encodeUtf8 _v))
                (Data.ProtoLens.Encoding.Wire.buildFieldSet
                   (Lens.Family2.view Data.ProtoLens.unknownFields _x)))
instance Control.DeepSeq.NFData MCP'ExtraHeadersEntry where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_MCP'ExtraHeadersEntry'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_MCP'ExtraHeadersEntry'key x__)
                (Control.DeepSeq.deepseq (_MCP'ExtraHeadersEntry'value x__) ()))
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Chat_Fields.content' @:: Lens' Message [Content]@
         * 'Proto.Xai.Api.V1.Chat_Fields.vec'content' @:: Lens' Message (Data.Vector.Vector Content)@
         * 'Proto.Xai.Api.V1.Chat_Fields.reasoningContent' @:: Lens' Message Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'reasoningContent' @:: Lens' Message (Prelude.Maybe Data.Text.Text)@
         * 'Proto.Xai.Api.V1.Chat_Fields.role' @:: Lens' Message MessageRole@
         * 'Proto.Xai.Api.V1.Chat_Fields.name' @:: Lens' Message Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.toolCalls' @:: Lens' Message [ToolCall]@
         * 'Proto.Xai.Api.V1.Chat_Fields.vec'toolCalls' @:: Lens' Message (Data.Vector.Vector ToolCall)@
         * 'Proto.Xai.Api.V1.Chat_Fields.encryptedContent' @:: Lens' Message Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.toolCallId' @:: Lens' Message Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'toolCallId' @:: Lens' Message (Prelude.Maybe Data.Text.Text)@ -}
data Message
  = Message'_constructor {_Message'content :: !(Data.Vector.Vector Content),
                          _Message'reasoningContent :: !(Prelude.Maybe Data.Text.Text),
                          _Message'role :: !MessageRole,
                          _Message'name :: !Data.Text.Text,
                          _Message'toolCalls :: !(Data.Vector.Vector ToolCall),
                          _Message'encryptedContent :: !Data.Text.Text,
                          _Message'toolCallId :: !(Prelude.Maybe Data.Text.Text),
                          _Message'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show Message where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField Message "content" [Content] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Message'content (\ x__ y__ -> x__ {_Message'content = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField Message "vec'content" (Data.Vector.Vector Content) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Message'content (\ x__ y__ -> x__ {_Message'content = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField Message "reasoningContent" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Message'reasoningContent
           (\ x__ y__ -> x__ {_Message'reasoningContent = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField Message "maybe'reasoningContent" (Prelude.Maybe Data.Text.Text) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Message'reasoningContent
           (\ x__ y__ -> x__ {_Message'reasoningContent = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField Message "role" MessageRole where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Message'role (\ x__ y__ -> x__ {_Message'role = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField Message "name" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Message'name (\ x__ y__ -> x__ {_Message'name = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField Message "toolCalls" [ToolCall] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Message'toolCalls (\ x__ y__ -> x__ {_Message'toolCalls = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField Message "vec'toolCalls" (Data.Vector.Vector ToolCall) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Message'toolCalls (\ x__ y__ -> x__ {_Message'toolCalls = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField Message "encryptedContent" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Message'encryptedContent
           (\ x__ y__ -> x__ {_Message'encryptedContent = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField Message "toolCallId" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Message'toolCallId (\ x__ y__ -> x__ {_Message'toolCallId = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField Message "maybe'toolCallId" (Prelude.Maybe Data.Text.Text) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Message'toolCallId (\ x__ y__ -> x__ {_Message'toolCallId = y__}))
        Prelude.id
instance Data.ProtoLens.Message Message where
  messageName _ = Data.Text.pack "xai_api.Message"
  packedMessageDescriptor _
    = "\n\
      \\aMessage\DC2*\n\
      \\acontent\CAN\SOH \ETX(\v2\DLE.xai_api.ContentR\acontent\DC20\n\
      \\DC1reasoning_content\CAN\ENQ \SOH(\tH\NULR\DLEreasoningContent\136\SOH\SOH\DC2(\n\
      \\EOTrole\CAN\STX \SOH(\SO2\DC4.xai_api.MessageRoleR\EOTrole\DC2\DC2\n\
      \\EOTname\CAN\ETX \SOH(\tR\EOTname\DC20\n\
      \\n\
      \tool_calls\CAN\EOT \ETX(\v2\DC1.xai_api.ToolCallR\ttoolCalls\DC2+\n\
      \\DC1encrypted_content\CAN\ACK \SOH(\tR\DLEencryptedContent\DC2%\n\
      \\ftool_call_id\CAN\a \SOH(\tH\SOHR\n\
      \toolCallId\136\SOH\SOHB\DC4\n\
      \\DC2_reasoning_contentB\SI\n\
      \\r_tool_call_id"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        content__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "content"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor Content)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Unpacked (Data.ProtoLens.Field.field @"content")) ::
              Data.ProtoLens.FieldDescriptor Message
        reasoningContent__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "reasoning_content"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'reasoningContent")) ::
              Data.ProtoLens.FieldDescriptor Message
        role__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "role"
              (Data.ProtoLens.ScalarField Data.ProtoLens.EnumField ::
                 Data.ProtoLens.FieldTypeDescriptor MessageRole)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"role")) ::
              Data.ProtoLens.FieldDescriptor Message
        name__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "name"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"name")) ::
              Data.ProtoLens.FieldDescriptor Message
        toolCalls__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "tool_calls"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor ToolCall)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Unpacked
                 (Data.ProtoLens.Field.field @"toolCalls")) ::
              Data.ProtoLens.FieldDescriptor Message
        encryptedContent__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "encrypted_content"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"encryptedContent")) ::
              Data.ProtoLens.FieldDescriptor Message
        toolCallId__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "tool_call_id"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'toolCallId")) ::
              Data.ProtoLens.FieldDescriptor Message
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, content__field_descriptor),
           (Data.ProtoLens.Tag 5, reasoningContent__field_descriptor),
           (Data.ProtoLens.Tag 2, role__field_descriptor),
           (Data.ProtoLens.Tag 3, name__field_descriptor),
           (Data.ProtoLens.Tag 4, toolCalls__field_descriptor),
           (Data.ProtoLens.Tag 6, encryptedContent__field_descriptor),
           (Data.ProtoLens.Tag 7, toolCallId__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _Message'_unknownFields
        (\ x__ y__ -> x__ {_Message'_unknownFields = y__})
  defMessage
    = Message'_constructor
        {_Message'content = Data.Vector.Generic.empty,
         _Message'reasoningContent = Prelude.Nothing,
         _Message'role = Data.ProtoLens.fieldDefault,
         _Message'name = Data.ProtoLens.fieldDefault,
         _Message'toolCalls = Data.Vector.Generic.empty,
         _Message'encryptedContent = Data.ProtoLens.fieldDefault,
         _Message'toolCallId = Prelude.Nothing,
         _Message'_unknownFields = []}
  parseMessage
    = let
        loop ::
          Message
          -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Vector Data.ProtoLens.Encoding.Growing.RealWorld Content
             -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Vector Data.ProtoLens.Encoding.Growing.RealWorld ToolCall
                -> Data.ProtoLens.Encoding.Bytes.Parser Message
        loop x mutable'content mutable'toolCalls
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do frozen'content <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                          (Data.ProtoLens.Encoding.Growing.unsafeFreeze
                                             mutable'content)
                      frozen'toolCalls <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                            (Data.ProtoLens.Encoding.Growing.unsafeFreeze
                                               mutable'toolCalls)
                      (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t)
                           (Lens.Family2.set
                              (Data.ProtoLens.Field.field @"vec'content") frozen'content
                              (Lens.Family2.set
                                 (Data.ProtoLens.Field.field @"vec'toolCalls") frozen'toolCalls x)))
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                            Data.ProtoLens.Encoding.Bytes.isolate
                                              (Prelude.fromIntegral len)
                                              Data.ProtoLens.parseMessage)
                                        "content"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append mutable'content y)
                                loop x v mutable'toolCalls
                        42
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "reasoning_content"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"reasoningContent") y x)
                                  mutable'content mutable'toolCalls
                        16
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.toEnum
                                          (Prelude.fmap
                                             Prelude.fromIntegral
                                             Data.ProtoLens.Encoding.Bytes.getVarInt))
                                       "role"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"role") y x)
                                  mutable'content mutable'toolCalls
                        26
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "name"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"name") y x)
                                  mutable'content mutable'toolCalls
                        34
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                            Data.ProtoLens.Encoding.Bytes.isolate
                                              (Prelude.fromIntegral len)
                                              Data.ProtoLens.parseMessage)
                                        "tool_calls"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append mutable'toolCalls y)
                                loop x mutable'content v
                        50
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "encrypted_content"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"encryptedContent") y x)
                                  mutable'content mutable'toolCalls
                        58
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "tool_call_id"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"toolCallId") y x)
                                  mutable'content mutable'toolCalls
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
                                  mutable'content mutable'toolCalls
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do mutable'content <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                   Data.ProtoLens.Encoding.Growing.new
              mutable'toolCalls <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                     Data.ProtoLens.Encoding.Growing.new
              loop Data.ProtoLens.defMessage mutable'content mutable'toolCalls)
          "Message"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (Data.ProtoLens.Encoding.Bytes.foldMapBuilder
                (\ _v
                   -> (Data.Monoid.<>)
                        (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                        ((Prelude..)
                           (\ bs
                              -> (Data.Monoid.<>)
                                   (Data.ProtoLens.Encoding.Bytes.putVarInt
                                      (Prelude.fromIntegral (Data.ByteString.length bs)))
                                   (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                           Data.ProtoLens.encodeMessage _v))
                (Lens.Family2.view (Data.ProtoLens.Field.field @"vec'content") _x))
             ((Data.Monoid.<>)
                (case
                     Lens.Family2.view
                       (Data.ProtoLens.Field.field @"maybe'reasoningContent") _x
                 of
                   Prelude.Nothing -> Data.Monoid.mempty
                   (Prelude.Just _v)
                     -> (Data.Monoid.<>)
                          (Data.ProtoLens.Encoding.Bytes.putVarInt 42)
                          ((Prelude..)
                             (\ bs
                                -> (Data.Monoid.<>)
                                     (Data.ProtoLens.Encoding.Bytes.putVarInt
                                        (Prelude.fromIntegral (Data.ByteString.length bs)))
                                     (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                             Data.Text.Encoding.encodeUtf8 _v))
                ((Data.Monoid.<>)
                   (let _v = Lens.Family2.view (Data.ProtoLens.Field.field @"role") _x
                    in
                      if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                          Data.Monoid.mempty
                      else
                          (Data.Monoid.<>)
                            (Data.ProtoLens.Encoding.Bytes.putVarInt 16)
                            ((Prelude..)
                               ((Prelude..)
                                  Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral)
                               Prelude.fromEnum _v))
                   ((Data.Monoid.<>)
                      (let _v = Lens.Family2.view (Data.ProtoLens.Field.field @"name") _x
                       in
                         if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                             Data.Monoid.mempty
                         else
                             (Data.Monoid.<>)
                               (Data.ProtoLens.Encoding.Bytes.putVarInt 26)
                               ((Prelude..)
                                  (\ bs
                                     -> (Data.Monoid.<>)
                                          (Data.ProtoLens.Encoding.Bytes.putVarInt
                                             (Prelude.fromIntegral (Data.ByteString.length bs)))
                                          (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                  Data.Text.Encoding.encodeUtf8 _v))
                      ((Data.Monoid.<>)
                         (Data.ProtoLens.Encoding.Bytes.foldMapBuilder
                            (\ _v
                               -> (Data.Monoid.<>)
                                    (Data.ProtoLens.Encoding.Bytes.putVarInt 34)
                                    ((Prelude..)
                                       (\ bs
                                          -> (Data.Monoid.<>)
                                               (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                  (Prelude.fromIntegral
                                                     (Data.ByteString.length bs)))
                                               (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                       Data.ProtoLens.encodeMessage _v))
                            (Lens.Family2.view
                               (Data.ProtoLens.Field.field @"vec'toolCalls") _x))
                         ((Data.Monoid.<>)
                            (let
                               _v
                                 = Lens.Family2.view
                                     (Data.ProtoLens.Field.field @"encryptedContent") _x
                             in
                               if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                   Data.Monoid.mempty
                               else
                                   (Data.Monoid.<>)
                                     (Data.ProtoLens.Encoding.Bytes.putVarInt 50)
                                     ((Prelude..)
                                        (\ bs
                                           -> (Data.Monoid.<>)
                                                (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                   (Prelude.fromIntegral
                                                      (Data.ByteString.length bs)))
                                                (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                        Data.Text.Encoding.encodeUtf8 _v))
                            ((Data.Monoid.<>)
                               (case
                                    Lens.Family2.view
                                      (Data.ProtoLens.Field.field @"maybe'toolCallId") _x
                                of
                                  Prelude.Nothing -> Data.Monoid.mempty
                                  (Prelude.Just _v)
                                    -> (Data.Monoid.<>)
                                         (Data.ProtoLens.Encoding.Bytes.putVarInt 58)
                                         ((Prelude..)
                                            (\ bs
                                               -> (Data.Monoid.<>)
                                                    (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                       (Prelude.fromIntegral
                                                          (Data.ByteString.length bs)))
                                                    (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                            Data.Text.Encoding.encodeUtf8 _v))
                               (Data.ProtoLens.Encoding.Wire.buildFieldSet
                                  (Lens.Family2.view Data.ProtoLens.unknownFields _x))))))))
instance Control.DeepSeq.NFData Message where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_Message'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_Message'content x__)
                (Control.DeepSeq.deepseq
                   (_Message'reasoningContent x__)
                   (Control.DeepSeq.deepseq
                      (_Message'role x__)
                      (Control.DeepSeq.deepseq
                         (_Message'name x__)
                         (Control.DeepSeq.deepseq
                            (_Message'toolCalls x__)
                            (Control.DeepSeq.deepseq
                               (_Message'encryptedContent x__)
                               (Control.DeepSeq.deepseq (_Message'toolCallId x__) ())))))))
newtype MessageRole'UnrecognizedValue
  = MessageRole'UnrecognizedValue Data.Int.Int32
  deriving stock (Prelude.Eq, Prelude.Ord, Prelude.Show)
data MessageRole
  = INVALID_ROLE |
    ROLE_USER |
    ROLE_ASSISTANT |
    ROLE_SYSTEM |
    ROLE_FUNCTION |
    ROLE_TOOL |
    ROLE_DEVELOPER |
    MessageRole'Unrecognized !MessageRole'UnrecognizedValue
  deriving stock (Prelude.Show, Prelude.Eq, Prelude.Ord)
instance Data.ProtoLens.MessageEnum MessageRole where
  maybeToEnum 0 = Prelude.Just INVALID_ROLE
  maybeToEnum 1 = Prelude.Just ROLE_USER
  maybeToEnum 2 = Prelude.Just ROLE_ASSISTANT
  maybeToEnum 3 = Prelude.Just ROLE_SYSTEM
  maybeToEnum 4 = Prelude.Just ROLE_FUNCTION
  maybeToEnum 5 = Prelude.Just ROLE_TOOL
  maybeToEnum 6 = Prelude.Just ROLE_DEVELOPER
  maybeToEnum k
    = Prelude.Just
        (MessageRole'Unrecognized
           (MessageRole'UnrecognizedValue (Prelude.fromIntegral k)))
  showEnum INVALID_ROLE = "INVALID_ROLE"
  showEnum ROLE_USER = "ROLE_USER"
  showEnum ROLE_ASSISTANT = "ROLE_ASSISTANT"
  showEnum ROLE_SYSTEM = "ROLE_SYSTEM"
  showEnum ROLE_FUNCTION = "ROLE_FUNCTION"
  showEnum ROLE_TOOL = "ROLE_TOOL"
  showEnum ROLE_DEVELOPER = "ROLE_DEVELOPER"
  showEnum
    (MessageRole'Unrecognized (MessageRole'UnrecognizedValue k))
    = Prelude.show k
  readEnum k
    | (Prelude.==) k "INVALID_ROLE" = Prelude.Just INVALID_ROLE
    | (Prelude.==) k "ROLE_USER" = Prelude.Just ROLE_USER
    | (Prelude.==) k "ROLE_ASSISTANT" = Prelude.Just ROLE_ASSISTANT
    | (Prelude.==) k "ROLE_SYSTEM" = Prelude.Just ROLE_SYSTEM
    | (Prelude.==) k "ROLE_FUNCTION" = Prelude.Just ROLE_FUNCTION
    | (Prelude.==) k "ROLE_TOOL" = Prelude.Just ROLE_TOOL
    | (Prelude.==) k "ROLE_DEVELOPER" = Prelude.Just ROLE_DEVELOPER
    | Prelude.otherwise
    = (Prelude.>>=) (Text.Read.readMaybe k) Data.ProtoLens.maybeToEnum
instance Prelude.Bounded MessageRole where
  minBound = INVALID_ROLE
  maxBound = ROLE_DEVELOPER
instance Prelude.Enum MessageRole where
  toEnum k__
    = Prelude.maybe
        (Prelude.error
           ((Prelude.++)
              "toEnum: unknown value for enum MessageRole: " (Prelude.show k__)))
        Prelude.id (Data.ProtoLens.maybeToEnum k__)
  fromEnum INVALID_ROLE = 0
  fromEnum ROLE_USER = 1
  fromEnum ROLE_ASSISTANT = 2
  fromEnum ROLE_SYSTEM = 3
  fromEnum ROLE_FUNCTION = 4
  fromEnum ROLE_TOOL = 5
  fromEnum ROLE_DEVELOPER = 6
  fromEnum
    (MessageRole'Unrecognized (MessageRole'UnrecognizedValue k))
    = Prelude.fromIntegral k
  succ ROLE_DEVELOPER
    = Prelude.error
        "MessageRole.succ: bad argument ROLE_DEVELOPER. This value would be out of bounds."
  succ INVALID_ROLE = ROLE_USER
  succ ROLE_USER = ROLE_ASSISTANT
  succ ROLE_ASSISTANT = ROLE_SYSTEM
  succ ROLE_SYSTEM = ROLE_FUNCTION
  succ ROLE_FUNCTION = ROLE_TOOL
  succ ROLE_TOOL = ROLE_DEVELOPER
  succ (MessageRole'Unrecognized _)
    = Prelude.error
        "MessageRole.succ: bad argument: unrecognized value"
  pred INVALID_ROLE
    = Prelude.error
        "MessageRole.pred: bad argument INVALID_ROLE. This value would be out of bounds."
  pred ROLE_USER = INVALID_ROLE
  pred ROLE_ASSISTANT = ROLE_USER
  pred ROLE_SYSTEM = ROLE_ASSISTANT
  pred ROLE_FUNCTION = ROLE_SYSTEM
  pred ROLE_TOOL = ROLE_FUNCTION
  pred ROLE_DEVELOPER = ROLE_TOOL
  pred (MessageRole'Unrecognized _)
    = Prelude.error
        "MessageRole.pred: bad argument: unrecognized value"
  enumFrom = Data.ProtoLens.Message.Enum.messageEnumFrom
  enumFromTo = Data.ProtoLens.Message.Enum.messageEnumFromTo
  enumFromThen = Data.ProtoLens.Message.Enum.messageEnumFromThen
  enumFromThenTo = Data.ProtoLens.Message.Enum.messageEnumFromThenTo
instance Data.ProtoLens.FieldDefault MessageRole where
  fieldDefault = INVALID_ROLE
instance Control.DeepSeq.NFData MessageRole where
  rnf x__ = Prelude.seq x__ ()
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Chat_Fields.excludedWebsites' @:: Lens' NewsSource [Data.Text.Text]@
         * 'Proto.Xai.Api.V1.Chat_Fields.vec'excludedWebsites' @:: Lens' NewsSource (Data.Vector.Vector Data.Text.Text)@
         * 'Proto.Xai.Api.V1.Chat_Fields.country' @:: Lens' NewsSource Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'country' @:: Lens' NewsSource (Prelude.Maybe Data.Text.Text)@
         * 'Proto.Xai.Api.V1.Chat_Fields.safeSearch' @:: Lens' NewsSource Prelude.Bool@ -}
data NewsSource
  = NewsSource'_constructor {_NewsSource'excludedWebsites :: !(Data.Vector.Vector Data.Text.Text),
                             _NewsSource'country :: !(Prelude.Maybe Data.Text.Text),
                             _NewsSource'safeSearch :: !Prelude.Bool,
                             _NewsSource'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show NewsSource where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField NewsSource "excludedWebsites" [Data.Text.Text] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _NewsSource'excludedWebsites
           (\ x__ y__ -> x__ {_NewsSource'excludedWebsites = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField NewsSource "vec'excludedWebsites" (Data.Vector.Vector Data.Text.Text) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _NewsSource'excludedWebsites
           (\ x__ y__ -> x__ {_NewsSource'excludedWebsites = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField NewsSource "country" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _NewsSource'country (\ x__ y__ -> x__ {_NewsSource'country = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField NewsSource "maybe'country" (Prelude.Maybe Data.Text.Text) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _NewsSource'country (\ x__ y__ -> x__ {_NewsSource'country = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField NewsSource "safeSearch" Prelude.Bool where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _NewsSource'safeSearch
           (\ x__ y__ -> x__ {_NewsSource'safeSearch = y__}))
        Prelude.id
instance Data.ProtoLens.Message NewsSource where
  messageName _ = Data.Text.pack "xai_api.NewsSource"
  packedMessageDescriptor _
    = "\n\
      \\n\
      \NewsSource\DC2+\n\
      \\DC1excluded_websites\CAN\STX \ETX(\tR\DLEexcludedWebsites\DC2\GS\n\
      \\acountry\CAN\ETX \SOH(\tH\NULR\acountry\136\SOH\SOH\DC2\US\n\
      \\vsafe_search\CAN\EOT \SOH(\bR\n\
      \safeSearchB\n\
      \\n\
      \\b_country"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        excludedWebsites__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "excluded_websites"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Unpacked
                 (Data.ProtoLens.Field.field @"excludedWebsites")) ::
              Data.ProtoLens.FieldDescriptor NewsSource
        country__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "country"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'country")) ::
              Data.ProtoLens.FieldDescriptor NewsSource
        safeSearch__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "safe_search"
              (Data.ProtoLens.ScalarField Data.ProtoLens.BoolField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Bool)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"safeSearch")) ::
              Data.ProtoLens.FieldDescriptor NewsSource
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 2, excludedWebsites__field_descriptor),
           (Data.ProtoLens.Tag 3, country__field_descriptor),
           (Data.ProtoLens.Tag 4, safeSearch__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _NewsSource'_unknownFields
        (\ x__ y__ -> x__ {_NewsSource'_unknownFields = y__})
  defMessage
    = NewsSource'_constructor
        {_NewsSource'excludedWebsites = Data.Vector.Generic.empty,
         _NewsSource'country = Prelude.Nothing,
         _NewsSource'safeSearch = Data.ProtoLens.fieldDefault,
         _NewsSource'_unknownFields = []}
  parseMessage
    = let
        loop ::
          NewsSource
          -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Vector Data.ProtoLens.Encoding.Growing.RealWorld Data.Text.Text
             -> Data.ProtoLens.Encoding.Bytes.Parser NewsSource
        loop x mutable'excludedWebsites
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do frozen'excludedWebsites <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                                   (Data.ProtoLens.Encoding.Growing.unsafeFreeze
                                                      mutable'excludedWebsites)
                      (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t)
                           (Lens.Family2.set
                              (Data.ProtoLens.Field.field @"vec'excludedWebsites")
                              frozen'excludedWebsites x))
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        18
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                            Data.ProtoLens.Encoding.Bytes.getText
                                              (Prelude.fromIntegral len))
                                        "excluded_websites"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append
                                          mutable'excludedWebsites y)
                                loop x v
                        26
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "country"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"country") y x)
                                  mutable'excludedWebsites
                        32
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          ((Prelude./=) 0) Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "safe_search"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"safeSearch") y x)
                                  mutable'excludedWebsites
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
                                  mutable'excludedWebsites
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do mutable'excludedWebsites <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                            Data.ProtoLens.Encoding.Growing.new
              loop Data.ProtoLens.defMessage mutable'excludedWebsites)
          "NewsSource"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (Data.ProtoLens.Encoding.Bytes.foldMapBuilder
                (\ _v
                   -> (Data.Monoid.<>)
                        (Data.ProtoLens.Encoding.Bytes.putVarInt 18)
                        ((Prelude..)
                           (\ bs
                              -> (Data.Monoid.<>)
                                   (Data.ProtoLens.Encoding.Bytes.putVarInt
                                      (Prelude.fromIntegral (Data.ByteString.length bs)))
                                   (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                           Data.Text.Encoding.encodeUtf8 _v))
                (Lens.Family2.view
                   (Data.ProtoLens.Field.field @"vec'excludedWebsites") _x))
             ((Data.Monoid.<>)
                (case
                     Lens.Family2.view (Data.ProtoLens.Field.field @"maybe'country") _x
                 of
                   Prelude.Nothing -> Data.Monoid.mempty
                   (Prelude.Just _v)
                     -> (Data.Monoid.<>)
                          (Data.ProtoLens.Encoding.Bytes.putVarInt 26)
                          ((Prelude..)
                             (\ bs
                                -> (Data.Monoid.<>)
                                     (Data.ProtoLens.Encoding.Bytes.putVarInt
                                        (Prelude.fromIntegral (Data.ByteString.length bs)))
                                     (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                             Data.Text.Encoding.encodeUtf8 _v))
                ((Data.Monoid.<>)
                   (let
                      _v
                        = Lens.Family2.view (Data.ProtoLens.Field.field @"safeSearch") _x
                    in
                      if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                          Data.Monoid.mempty
                      else
                          (Data.Monoid.<>)
                            (Data.ProtoLens.Encoding.Bytes.putVarInt 32)
                            ((Prelude..)
                               Data.ProtoLens.Encoding.Bytes.putVarInt (\ b -> if b then 1 else 0)
                               _v))
                   (Data.ProtoLens.Encoding.Wire.buildFieldSet
                      (Lens.Family2.view Data.ProtoLens.unknownFields _x))))
instance Control.DeepSeq.NFData NewsSource where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_NewsSource'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_NewsSource'excludedWebsites x__)
                (Control.DeepSeq.deepseq
                   (_NewsSource'country x__)
                   (Control.DeepSeq.deepseq (_NewsSource'safeSearch x__) ())))
newtype ReasoningEffort'UnrecognizedValue
  = ReasoningEffort'UnrecognizedValue Data.Int.Int32
  deriving stock (Prelude.Eq, Prelude.Ord, Prelude.Show)
data ReasoningEffort
  = INVALID_EFFORT |
    EFFORT_LOW |
    EFFORT_MEDIUM |
    EFFORT_HIGH |
    EFFORT_NONE |
    ReasoningEffort'Unrecognized !ReasoningEffort'UnrecognizedValue
  deriving stock (Prelude.Show, Prelude.Eq, Prelude.Ord)
instance Data.ProtoLens.MessageEnum ReasoningEffort where
  maybeToEnum 0 = Prelude.Just INVALID_EFFORT
  maybeToEnum 1 = Prelude.Just EFFORT_LOW
  maybeToEnum 2 = Prelude.Just EFFORT_MEDIUM
  maybeToEnum 3 = Prelude.Just EFFORT_HIGH
  maybeToEnum 4 = Prelude.Just EFFORT_NONE
  maybeToEnum k
    = Prelude.Just
        (ReasoningEffort'Unrecognized
           (ReasoningEffort'UnrecognizedValue (Prelude.fromIntegral k)))
  showEnum INVALID_EFFORT = "INVALID_EFFORT"
  showEnum EFFORT_LOW = "EFFORT_LOW"
  showEnum EFFORT_MEDIUM = "EFFORT_MEDIUM"
  showEnum EFFORT_HIGH = "EFFORT_HIGH"
  showEnum EFFORT_NONE = "EFFORT_NONE"
  showEnum
    (ReasoningEffort'Unrecognized (ReasoningEffort'UnrecognizedValue k))
    = Prelude.show k
  readEnum k
    | (Prelude.==) k "INVALID_EFFORT" = Prelude.Just INVALID_EFFORT
    | (Prelude.==) k "EFFORT_LOW" = Prelude.Just EFFORT_LOW
    | (Prelude.==) k "EFFORT_MEDIUM" = Prelude.Just EFFORT_MEDIUM
    | (Prelude.==) k "EFFORT_HIGH" = Prelude.Just EFFORT_HIGH
    | (Prelude.==) k "EFFORT_NONE" = Prelude.Just EFFORT_NONE
    | Prelude.otherwise
    = (Prelude.>>=) (Text.Read.readMaybe k) Data.ProtoLens.maybeToEnum
instance Prelude.Bounded ReasoningEffort where
  minBound = INVALID_EFFORT
  maxBound = EFFORT_NONE
instance Prelude.Enum ReasoningEffort where
  toEnum k__
    = Prelude.maybe
        (Prelude.error
           ((Prelude.++)
              "toEnum: unknown value for enum ReasoningEffort: "
              (Prelude.show k__)))
        Prelude.id (Data.ProtoLens.maybeToEnum k__)
  fromEnum INVALID_EFFORT = 0
  fromEnum EFFORT_LOW = 1
  fromEnum EFFORT_MEDIUM = 2
  fromEnum EFFORT_HIGH = 3
  fromEnum EFFORT_NONE = 4
  fromEnum
    (ReasoningEffort'Unrecognized (ReasoningEffort'UnrecognizedValue k))
    = Prelude.fromIntegral k
  succ EFFORT_NONE
    = Prelude.error
        "ReasoningEffort.succ: bad argument EFFORT_NONE. This value would be out of bounds."
  succ INVALID_EFFORT = EFFORT_LOW
  succ EFFORT_LOW = EFFORT_MEDIUM
  succ EFFORT_MEDIUM = EFFORT_HIGH
  succ EFFORT_HIGH = EFFORT_NONE
  succ (ReasoningEffort'Unrecognized _)
    = Prelude.error
        "ReasoningEffort.succ: bad argument: unrecognized value"
  pred INVALID_EFFORT
    = Prelude.error
        "ReasoningEffort.pred: bad argument INVALID_EFFORT. This value would be out of bounds."
  pred EFFORT_LOW = INVALID_EFFORT
  pred EFFORT_MEDIUM = EFFORT_LOW
  pred EFFORT_HIGH = EFFORT_MEDIUM
  pred EFFORT_NONE = EFFORT_HIGH
  pred (ReasoningEffort'Unrecognized _)
    = Prelude.error
        "ReasoningEffort.pred: bad argument: unrecognized value"
  enumFrom = Data.ProtoLens.Message.Enum.messageEnumFrom
  enumFromTo = Data.ProtoLens.Message.Enum.messageEnumFromTo
  enumFromThen = Data.ProtoLens.Message.Enum.messageEnumFromThen
  enumFromThenTo = Data.ProtoLens.Message.Enum.messageEnumFromThenTo
instance Data.ProtoLens.FieldDefault ReasoningEffort where
  fieldDefault = INVALID_EFFORT
instance Control.DeepSeq.NFData ReasoningEffort where
  rnf x__ = Prelude.seq x__ ()
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Chat_Fields.maxTokens' @:: Lens' RequestSettings Data.Int.Int32@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'maxTokens' @:: Lens' RequestSettings (Prelude.Maybe Data.Int.Int32)@
         * 'Proto.Xai.Api.V1.Chat_Fields.parallelToolCalls' @:: Lens' RequestSettings Prelude.Bool@
         * 'Proto.Xai.Api.V1.Chat_Fields.previousResponseId' @:: Lens' RequestSettings Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'previousResponseId' @:: Lens' RequestSettings (Prelude.Maybe Data.Text.Text)@
         * 'Proto.Xai.Api.V1.Chat_Fields.reasoningEffort' @:: Lens' RequestSettings ReasoningEffort@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'reasoningEffort' @:: Lens' RequestSettings (Prelude.Maybe ReasoningEffort)@
         * 'Proto.Xai.Api.V1.Chat_Fields.temperature' @:: Lens' RequestSettings Prelude.Float@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'temperature' @:: Lens' RequestSettings (Prelude.Maybe Prelude.Float)@
         * 'Proto.Xai.Api.V1.Chat_Fields.responseFormat' @:: Lens' RequestSettings ResponseFormat@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'responseFormat' @:: Lens' RequestSettings (Prelude.Maybe ResponseFormat)@
         * 'Proto.Xai.Api.V1.Chat_Fields.toolChoice' @:: Lens' RequestSettings ToolChoice@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'toolChoice' @:: Lens' RequestSettings (Prelude.Maybe ToolChoice)@
         * 'Proto.Xai.Api.V1.Chat_Fields.tools' @:: Lens' RequestSettings [Tool]@
         * 'Proto.Xai.Api.V1.Chat_Fields.vec'tools' @:: Lens' RequestSettings (Data.Vector.Vector Tool)@
         * 'Proto.Xai.Api.V1.Chat_Fields.topP' @:: Lens' RequestSettings Prelude.Float@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'topP' @:: Lens' RequestSettings (Prelude.Maybe Prelude.Float)@
         * 'Proto.Xai.Api.V1.Chat_Fields.user' @:: Lens' RequestSettings Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.searchParameters' @:: Lens' RequestSettings SearchParameters@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'searchParameters' @:: Lens' RequestSettings (Prelude.Maybe SearchParameters)@
         * 'Proto.Xai.Api.V1.Chat_Fields.storeMessages' @:: Lens' RequestSettings Prelude.Bool@
         * 'Proto.Xai.Api.V1.Chat_Fields.useEncryptedContent' @:: Lens' RequestSettings Prelude.Bool@
         * 'Proto.Xai.Api.V1.Chat_Fields.include' @:: Lens' RequestSettings [IncludeOption]@
         * 'Proto.Xai.Api.V1.Chat_Fields.vec'include' @:: Lens' RequestSettings (Data.Vector.Vector IncludeOption)@ -}
data RequestSettings
  = RequestSettings'_constructor {_RequestSettings'maxTokens :: !(Prelude.Maybe Data.Int.Int32),
                                  _RequestSettings'parallelToolCalls :: !Prelude.Bool,
                                  _RequestSettings'previousResponseId :: !(Prelude.Maybe Data.Text.Text),
                                  _RequestSettings'reasoningEffort :: !(Prelude.Maybe ReasoningEffort),
                                  _RequestSettings'temperature :: !(Prelude.Maybe Prelude.Float),
                                  _RequestSettings'responseFormat :: !(Prelude.Maybe ResponseFormat),
                                  _RequestSettings'toolChoice :: !(Prelude.Maybe ToolChoice),
                                  _RequestSettings'tools :: !(Data.Vector.Vector Tool),
                                  _RequestSettings'topP :: !(Prelude.Maybe Prelude.Float),
                                  _RequestSettings'user :: !Data.Text.Text,
                                  _RequestSettings'searchParameters :: !(Prelude.Maybe SearchParameters),
                                  _RequestSettings'storeMessages :: !Prelude.Bool,
                                  _RequestSettings'useEncryptedContent :: !Prelude.Bool,
                                  _RequestSettings'include :: !(Data.Vector.Vector IncludeOption),
                                  _RequestSettings'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show RequestSettings where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField RequestSettings "maxTokens" Data.Int.Int32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RequestSettings'maxTokens
           (\ x__ y__ -> x__ {_RequestSettings'maxTokens = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField RequestSettings "maybe'maxTokens" (Prelude.Maybe Data.Int.Int32) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RequestSettings'maxTokens
           (\ x__ y__ -> x__ {_RequestSettings'maxTokens = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField RequestSettings "parallelToolCalls" Prelude.Bool where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RequestSettings'parallelToolCalls
           (\ x__ y__ -> x__ {_RequestSettings'parallelToolCalls = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField RequestSettings "previousResponseId" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RequestSettings'previousResponseId
           (\ x__ y__ -> x__ {_RequestSettings'previousResponseId = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField RequestSettings "maybe'previousResponseId" (Prelude.Maybe Data.Text.Text) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RequestSettings'previousResponseId
           (\ x__ y__ -> x__ {_RequestSettings'previousResponseId = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField RequestSettings "reasoningEffort" ReasoningEffort where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RequestSettings'reasoningEffort
           (\ x__ y__ -> x__ {_RequestSettings'reasoningEffort = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField RequestSettings "maybe'reasoningEffort" (Prelude.Maybe ReasoningEffort) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RequestSettings'reasoningEffort
           (\ x__ y__ -> x__ {_RequestSettings'reasoningEffort = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField RequestSettings "temperature" Prelude.Float where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RequestSettings'temperature
           (\ x__ y__ -> x__ {_RequestSettings'temperature = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField RequestSettings "maybe'temperature" (Prelude.Maybe Prelude.Float) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RequestSettings'temperature
           (\ x__ y__ -> x__ {_RequestSettings'temperature = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField RequestSettings "responseFormat" ResponseFormat where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RequestSettings'responseFormat
           (\ x__ y__ -> x__ {_RequestSettings'responseFormat = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage)
instance Data.ProtoLens.Field.HasField RequestSettings "maybe'responseFormat" (Prelude.Maybe ResponseFormat) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RequestSettings'responseFormat
           (\ x__ y__ -> x__ {_RequestSettings'responseFormat = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField RequestSettings "toolChoice" ToolChoice where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RequestSettings'toolChoice
           (\ x__ y__ -> x__ {_RequestSettings'toolChoice = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage)
instance Data.ProtoLens.Field.HasField RequestSettings "maybe'toolChoice" (Prelude.Maybe ToolChoice) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RequestSettings'toolChoice
           (\ x__ y__ -> x__ {_RequestSettings'toolChoice = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField RequestSettings "tools" [Tool] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RequestSettings'tools
           (\ x__ y__ -> x__ {_RequestSettings'tools = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField RequestSettings "vec'tools" (Data.Vector.Vector Tool) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RequestSettings'tools
           (\ x__ y__ -> x__ {_RequestSettings'tools = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField RequestSettings "topP" Prelude.Float where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RequestSettings'topP
           (\ x__ y__ -> x__ {_RequestSettings'topP = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField RequestSettings "maybe'topP" (Prelude.Maybe Prelude.Float) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RequestSettings'topP
           (\ x__ y__ -> x__ {_RequestSettings'topP = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField RequestSettings "user" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RequestSettings'user
           (\ x__ y__ -> x__ {_RequestSettings'user = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField RequestSettings "searchParameters" SearchParameters where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RequestSettings'searchParameters
           (\ x__ y__ -> x__ {_RequestSettings'searchParameters = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage)
instance Data.ProtoLens.Field.HasField RequestSettings "maybe'searchParameters" (Prelude.Maybe SearchParameters) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RequestSettings'searchParameters
           (\ x__ y__ -> x__ {_RequestSettings'searchParameters = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField RequestSettings "storeMessages" Prelude.Bool where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RequestSettings'storeMessages
           (\ x__ y__ -> x__ {_RequestSettings'storeMessages = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField RequestSettings "useEncryptedContent" Prelude.Bool where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RequestSettings'useEncryptedContent
           (\ x__ y__ -> x__ {_RequestSettings'useEncryptedContent = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField RequestSettings "include" [IncludeOption] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RequestSettings'include
           (\ x__ y__ -> x__ {_RequestSettings'include = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField RequestSettings "vec'include" (Data.Vector.Vector IncludeOption) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RequestSettings'include
           (\ x__ y__ -> x__ {_RequestSettings'include = y__}))
        Prelude.id
instance Data.ProtoLens.Message RequestSettings where
  messageName _ = Data.Text.pack "xai_api.RequestSettings"
  packedMessageDescriptor _
    = "\n\
      \\SIRequestSettings\DC2\"\n\
      \\n\
      \max_tokens\CAN\SOH \SOH(\ENQH\NULR\tmaxTokens\136\SOH\SOH\DC2.\n\
      \\DC3parallel_tool_calls\CAN\STX \SOH(\bR\DC1parallelToolCalls\DC25\n\
      \\DC4previous_response_id\CAN\ETX \SOH(\tH\SOHR\DC2previousResponseId\136\SOH\SOH\DC2H\n\
      \\DLEreasoning_effort\CAN\EOT \SOH(\SO2\CAN.xai_api.ReasoningEffortH\STXR\SIreasoningEffort\136\SOH\SOH\DC2%\n\
      \\vtemperature\CAN\ENQ \SOH(\STXH\ETXR\vtemperature\136\SOH\SOH\DC2@\n\
      \\SIresponse_format\CAN\ACK \SOH(\v2\ETB.xai_api.ResponseFormatR\SOresponseFormat\DC24\n\
      \\vtool_choice\CAN\a \SOH(\v2\DC3.xai_api.ToolChoiceR\n\
      \toolChoice\DC2#\n\
      \\ENQtools\CAN\b \ETX(\v2\r.xai_api.ToolR\ENQtools\DC2\CAN\n\
      \\ENQtop_p\CAN\t \SOH(\STXH\EOTR\EOTtopP\136\SOH\SOH\DC2\DC2\n\
      \\EOTuser\CAN\n\
      \ \SOH(\tR\EOTuser\DC2K\n\
      \\DC1search_parameters\CAN\v \SOH(\v2\EM.xai_api.SearchParametersH\ENQR\DLEsearchParameters\136\SOH\SOH\DC2%\n\
      \\SOstore_messages\CAN\f \SOH(\bR\rstoreMessages\DC22\n\
      \\NAKuse_encrypted_content\CAN\r \SOH(\bR\DC3useEncryptedContent\DC20\n\
      \\ainclude\CAN\SO \ETX(\SO2\SYN.xai_api.IncludeOptionR\aincludeB\r\n\
      \\v_max_tokensB\ETB\n\
      \\NAK_previous_response_idB\DC3\n\
      \\DC1_reasoning_effortB\SO\n\
      \\f_temperatureB\b\n\
      \\ACK_top_pB\DC4\n\
      \\DC2_search_parameters"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        maxTokens__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "max_tokens"
              (Data.ProtoLens.ScalarField Data.ProtoLens.Int32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Int.Int32)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'maxTokens")) ::
              Data.ProtoLens.FieldDescriptor RequestSettings
        parallelToolCalls__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "parallel_tool_calls"
              (Data.ProtoLens.ScalarField Data.ProtoLens.BoolField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Bool)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"parallelToolCalls")) ::
              Data.ProtoLens.FieldDescriptor RequestSettings
        previousResponseId__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "previous_response_id"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'previousResponseId")) ::
              Data.ProtoLens.FieldDescriptor RequestSettings
        reasoningEffort__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "reasoning_effort"
              (Data.ProtoLens.ScalarField Data.ProtoLens.EnumField ::
                 Data.ProtoLens.FieldTypeDescriptor ReasoningEffort)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'reasoningEffort")) ::
              Data.ProtoLens.FieldDescriptor RequestSettings
        temperature__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "temperature"
              (Data.ProtoLens.ScalarField Data.ProtoLens.FloatField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Float)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'temperature")) ::
              Data.ProtoLens.FieldDescriptor RequestSettings
        responseFormat__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "response_format"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor ResponseFormat)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'responseFormat")) ::
              Data.ProtoLens.FieldDescriptor RequestSettings
        toolChoice__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "tool_choice"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor ToolChoice)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'toolChoice")) ::
              Data.ProtoLens.FieldDescriptor RequestSettings
        tools__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "tools"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor Tool)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Unpacked (Data.ProtoLens.Field.field @"tools")) ::
              Data.ProtoLens.FieldDescriptor RequestSettings
        topP__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "top_p"
              (Data.ProtoLens.ScalarField Data.ProtoLens.FloatField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Float)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'topP")) ::
              Data.ProtoLens.FieldDescriptor RequestSettings
        user__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "user"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"user")) ::
              Data.ProtoLens.FieldDescriptor RequestSettings
        searchParameters__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "search_parameters"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor SearchParameters)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'searchParameters")) ::
              Data.ProtoLens.FieldDescriptor RequestSettings
        storeMessages__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "store_messages"
              (Data.ProtoLens.ScalarField Data.ProtoLens.BoolField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Bool)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"storeMessages")) ::
              Data.ProtoLens.FieldDescriptor RequestSettings
        useEncryptedContent__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "use_encrypted_content"
              (Data.ProtoLens.ScalarField Data.ProtoLens.BoolField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Bool)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"useEncryptedContent")) ::
              Data.ProtoLens.FieldDescriptor RequestSettings
        include__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "include"
              (Data.ProtoLens.ScalarField Data.ProtoLens.EnumField ::
                 Data.ProtoLens.FieldTypeDescriptor IncludeOption)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Packed (Data.ProtoLens.Field.field @"include")) ::
              Data.ProtoLens.FieldDescriptor RequestSettings
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, maxTokens__field_descriptor),
           (Data.ProtoLens.Tag 2, parallelToolCalls__field_descriptor),
           (Data.ProtoLens.Tag 3, previousResponseId__field_descriptor),
           (Data.ProtoLens.Tag 4, reasoningEffort__field_descriptor),
           (Data.ProtoLens.Tag 5, temperature__field_descriptor),
           (Data.ProtoLens.Tag 6, responseFormat__field_descriptor),
           (Data.ProtoLens.Tag 7, toolChoice__field_descriptor),
           (Data.ProtoLens.Tag 8, tools__field_descriptor),
           (Data.ProtoLens.Tag 9, topP__field_descriptor),
           (Data.ProtoLens.Tag 10, user__field_descriptor),
           (Data.ProtoLens.Tag 11, searchParameters__field_descriptor),
           (Data.ProtoLens.Tag 12, storeMessages__field_descriptor),
           (Data.ProtoLens.Tag 13, useEncryptedContent__field_descriptor),
           (Data.ProtoLens.Tag 14, include__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _RequestSettings'_unknownFields
        (\ x__ y__ -> x__ {_RequestSettings'_unknownFields = y__})
  defMessage
    = RequestSettings'_constructor
        {_RequestSettings'maxTokens = Prelude.Nothing,
         _RequestSettings'parallelToolCalls = Data.ProtoLens.fieldDefault,
         _RequestSettings'previousResponseId = Prelude.Nothing,
         _RequestSettings'reasoningEffort = Prelude.Nothing,
         _RequestSettings'temperature = Prelude.Nothing,
         _RequestSettings'responseFormat = Prelude.Nothing,
         _RequestSettings'toolChoice = Prelude.Nothing,
         _RequestSettings'tools = Data.Vector.Generic.empty,
         _RequestSettings'topP = Prelude.Nothing,
         _RequestSettings'user = Data.ProtoLens.fieldDefault,
         _RequestSettings'searchParameters = Prelude.Nothing,
         _RequestSettings'storeMessages = Data.ProtoLens.fieldDefault,
         _RequestSettings'useEncryptedContent = Data.ProtoLens.fieldDefault,
         _RequestSettings'include = Data.Vector.Generic.empty,
         _RequestSettings'_unknownFields = []}
  parseMessage
    = let
        loop ::
          RequestSettings
          -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Vector Data.ProtoLens.Encoding.Growing.RealWorld IncludeOption
             -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Vector Data.ProtoLens.Encoding.Growing.RealWorld Tool
                -> Data.ProtoLens.Encoding.Bytes.Parser RequestSettings
        loop x mutable'include mutable'tools
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do frozen'include <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                          (Data.ProtoLens.Encoding.Growing.unsafeFreeze
                                             mutable'include)
                      frozen'tools <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                        (Data.ProtoLens.Encoding.Growing.unsafeFreeze mutable'tools)
                      (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t)
                           (Lens.Family2.set
                              (Data.ProtoLens.Field.field @"vec'include") frozen'include
                              (Lens.Family2.set
                                 (Data.ProtoLens.Field.field @"vec'tools") frozen'tools x)))
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        8 -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "max_tokens"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"maxTokens") y x)
                                  mutable'include mutable'tools
                        16
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          ((Prelude./=) 0) Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "parallel_tool_calls"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"parallelToolCalls") y x)
                                  mutable'include mutable'tools
                        26
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "previous_response_id"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"previousResponseId") y x)
                                  mutable'include mutable'tools
                        32
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.toEnum
                                          (Prelude.fmap
                                             Prelude.fromIntegral
                                             Data.ProtoLens.Encoding.Bytes.getVarInt))
                                       "reasoning_effort"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"reasoningEffort") y x)
                                  mutable'include mutable'tools
                        45
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Data.ProtoLens.Encoding.Bytes.wordToFloat
                                          Data.ProtoLens.Encoding.Bytes.getFixed32)
                                       "temperature"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"temperature") y x)
                                  mutable'include mutable'tools
                        50
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "response_format"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"responseFormat") y x)
                                  mutable'include mutable'tools
                        58
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "tool_choice"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"toolChoice") y x)
                                  mutable'include mutable'tools
                        66
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                            Data.ProtoLens.Encoding.Bytes.isolate
                                              (Prelude.fromIntegral len)
                                              Data.ProtoLens.parseMessage)
                                        "tools"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append mutable'tools y)
                                loop x mutable'include v
                        77
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Data.ProtoLens.Encoding.Bytes.wordToFloat
                                          Data.ProtoLens.Encoding.Bytes.getFixed32)
                                       "top_p"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"topP") y x)
                                  mutable'include mutable'tools
                        82
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "user"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"user") y x)
                                  mutable'include mutable'tools
                        90
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "search_parameters"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"searchParameters") y x)
                                  mutable'include mutable'tools
                        96
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          ((Prelude./=) 0) Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "store_messages"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"storeMessages") y x)
                                  mutable'include mutable'tools
                        104
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          ((Prelude./=) 0) Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "use_encrypted_content"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"useEncryptedContent") y x)
                                  mutable'include mutable'tools
                        112
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (Prelude.fmap
                                           Prelude.toEnum
                                           (Prelude.fmap
                                              Prelude.fromIntegral
                                              Data.ProtoLens.Encoding.Bytes.getVarInt))
                                        "include"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append mutable'include y)
                                loop x v mutable'tools
                        114
                          -> do y <- do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                        Data.ProtoLens.Encoding.Bytes.isolate
                                          (Prelude.fromIntegral len)
                                          ((let
                                              ploop qs
                                                = do packedEnd <- Data.ProtoLens.Encoding.Bytes.atEnd
                                                     if packedEnd then
                                                         Prelude.return qs
                                                     else
                                                         do !q <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                                                    (Prelude.fmap
                                                                       Prelude.toEnum
                                                                       (Prelude.fmap
                                                                          Prelude.fromIntegral
                                                                          Data.ProtoLens.Encoding.Bytes.getVarInt))
                                                                    "include"
                                                            qs' <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                                                     (Data.ProtoLens.Encoding.Growing.append
                                                                        qs q)
                                                            ploop qs'
                                            in ploop)
                                             mutable'include)
                                loop x y mutable'tools
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
                                  mutable'include mutable'tools
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do mutable'include <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                   Data.ProtoLens.Encoding.Growing.new
              mutable'tools <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                 Data.ProtoLens.Encoding.Growing.new
              loop Data.ProtoLens.defMessage mutable'include mutable'tools)
          "RequestSettings"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (case
                  Lens.Family2.view
                    (Data.ProtoLens.Field.field @"maybe'maxTokens") _x
              of
                Prelude.Nothing -> Data.Monoid.mempty
                (Prelude.Just _v)
                  -> (Data.Monoid.<>)
                       (Data.ProtoLens.Encoding.Bytes.putVarInt 8)
                       ((Prelude..)
                          Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral _v))
             ((Data.Monoid.<>)
                (let
                   _v
                     = Lens.Family2.view
                         (Data.ProtoLens.Field.field @"parallelToolCalls") _x
                 in
                   if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                       Data.Monoid.mempty
                   else
                       (Data.Monoid.<>)
                         (Data.ProtoLens.Encoding.Bytes.putVarInt 16)
                         ((Prelude..)
                            Data.ProtoLens.Encoding.Bytes.putVarInt (\ b -> if b then 1 else 0)
                            _v))
                ((Data.Monoid.<>)
                   (case
                        Lens.Family2.view
                          (Data.ProtoLens.Field.field @"maybe'previousResponseId") _x
                    of
                      Prelude.Nothing -> Data.Monoid.mempty
                      (Prelude.Just _v)
                        -> (Data.Monoid.<>)
                             (Data.ProtoLens.Encoding.Bytes.putVarInt 26)
                             ((Prelude..)
                                (\ bs
                                   -> (Data.Monoid.<>)
                                        (Data.ProtoLens.Encoding.Bytes.putVarInt
                                           (Prelude.fromIntegral (Data.ByteString.length bs)))
                                        (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                Data.Text.Encoding.encodeUtf8 _v))
                   ((Data.Monoid.<>)
                      (case
                           Lens.Family2.view
                             (Data.ProtoLens.Field.field @"maybe'reasoningEffort") _x
                       of
                         Prelude.Nothing -> Data.Monoid.mempty
                         (Prelude.Just _v)
                           -> (Data.Monoid.<>)
                                (Data.ProtoLens.Encoding.Bytes.putVarInt 32)
                                ((Prelude..)
                                   ((Prelude..)
                                      Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral)
                                   Prelude.fromEnum _v))
                      ((Data.Monoid.<>)
                         (case
                              Lens.Family2.view
                                (Data.ProtoLens.Field.field @"maybe'temperature") _x
                          of
                            Prelude.Nothing -> Data.Monoid.mempty
                            (Prelude.Just _v)
                              -> (Data.Monoid.<>)
                                   (Data.ProtoLens.Encoding.Bytes.putVarInt 45)
                                   ((Prelude..)
                                      Data.ProtoLens.Encoding.Bytes.putFixed32
                                      Data.ProtoLens.Encoding.Bytes.floatToWord _v))
                         ((Data.Monoid.<>)
                            (case
                                 Lens.Family2.view
                                   (Data.ProtoLens.Field.field @"maybe'responseFormat") _x
                             of
                               Prelude.Nothing -> Data.Monoid.mempty
                               (Prelude.Just _v)
                                 -> (Data.Monoid.<>)
                                      (Data.ProtoLens.Encoding.Bytes.putVarInt 50)
                                      ((Prelude..)
                                         (\ bs
                                            -> (Data.Monoid.<>)
                                                 (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                    (Prelude.fromIntegral
                                                       (Data.ByteString.length bs)))
                                                 (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                         Data.ProtoLens.encodeMessage _v))
                            ((Data.Monoid.<>)
                               (case
                                    Lens.Family2.view
                                      (Data.ProtoLens.Field.field @"maybe'toolChoice") _x
                                of
                                  Prelude.Nothing -> Data.Monoid.mempty
                                  (Prelude.Just _v)
                                    -> (Data.Monoid.<>)
                                         (Data.ProtoLens.Encoding.Bytes.putVarInt 58)
                                         ((Prelude..)
                                            (\ bs
                                               -> (Data.Monoid.<>)
                                                    (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                       (Prelude.fromIntegral
                                                          (Data.ByteString.length bs)))
                                                    (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                            Data.ProtoLens.encodeMessage _v))
                               ((Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.foldMapBuilder
                                     (\ _v
                                        -> (Data.Monoid.<>)
                                             (Data.ProtoLens.Encoding.Bytes.putVarInt 66)
                                             ((Prelude..)
                                                (\ bs
                                                   -> (Data.Monoid.<>)
                                                        (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                           (Prelude.fromIntegral
                                                              (Data.ByteString.length bs)))
                                                        (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                                Data.ProtoLens.encodeMessage _v))
                                     (Lens.Family2.view
                                        (Data.ProtoLens.Field.field @"vec'tools") _x))
                                  ((Data.Monoid.<>)
                                     (case
                                          Lens.Family2.view
                                            (Data.ProtoLens.Field.field @"maybe'topP") _x
                                      of
                                        Prelude.Nothing -> Data.Monoid.mempty
                                        (Prelude.Just _v)
                                          -> (Data.Monoid.<>)
                                               (Data.ProtoLens.Encoding.Bytes.putVarInt 77)
                                               ((Prelude..)
                                                  Data.ProtoLens.Encoding.Bytes.putFixed32
                                                  Data.ProtoLens.Encoding.Bytes.floatToWord _v))
                                     ((Data.Monoid.<>)
                                        (let
                                           _v
                                             = Lens.Family2.view
                                                 (Data.ProtoLens.Field.field @"user") _x
                                         in
                                           if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                               Data.Monoid.mempty
                                           else
                                               (Data.Monoid.<>)
                                                 (Data.ProtoLens.Encoding.Bytes.putVarInt 82)
                                                 ((Prelude..)
                                                    (\ bs
                                                       -> (Data.Monoid.<>)
                                                            (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                               (Prelude.fromIntegral
                                                                  (Data.ByteString.length bs)))
                                                            (Data.ProtoLens.Encoding.Bytes.putBytes
                                                               bs))
                                                    Data.Text.Encoding.encodeUtf8 _v))
                                        ((Data.Monoid.<>)
                                           (case
                                                Lens.Family2.view
                                                  (Data.ProtoLens.Field.field
                                                     @"maybe'searchParameters")
                                                  _x
                                            of
                                              Prelude.Nothing -> Data.Monoid.mempty
                                              (Prelude.Just _v)
                                                -> (Data.Monoid.<>)
                                                     (Data.ProtoLens.Encoding.Bytes.putVarInt 90)
                                                     ((Prelude..)
                                                        (\ bs
                                                           -> (Data.Monoid.<>)
                                                                (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                   (Prelude.fromIntegral
                                                                      (Data.ByteString.length bs)))
                                                                (Data.ProtoLens.Encoding.Bytes.putBytes
                                                                   bs))
                                                        Data.ProtoLens.encodeMessage _v))
                                           ((Data.Monoid.<>)
                                              (let
                                                 _v
                                                   = Lens.Family2.view
                                                       (Data.ProtoLens.Field.field @"storeMessages")
                                                       _x
                                               in
                                                 if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                                     Data.Monoid.mempty
                                                 else
                                                     (Data.Monoid.<>)
                                                       (Data.ProtoLens.Encoding.Bytes.putVarInt 96)
                                                       ((Prelude..)
                                                          Data.ProtoLens.Encoding.Bytes.putVarInt
                                                          (\ b -> if b then 1 else 0) _v))
                                              ((Data.Monoid.<>)
                                                 (let
                                                    _v
                                                      = Lens.Family2.view
                                                          (Data.ProtoLens.Field.field
                                                             @"useEncryptedContent")
                                                          _x
                                                  in
                                                    if (Prelude.==)
                                                         _v Data.ProtoLens.fieldDefault then
                                                        Data.Monoid.mempty
                                                    else
                                                        (Data.Monoid.<>)
                                                          (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                             104)
                                                          ((Prelude..)
                                                             Data.ProtoLens.Encoding.Bytes.putVarInt
                                                             (\ b -> if b then 1 else 0) _v))
                                                 ((Data.Monoid.<>)
                                                    (let
                                                       p = Lens.Family2.view
                                                             (Data.ProtoLens.Field.field
                                                                @"vec'include")
                                                             _x
                                                     in
                                                       if Data.Vector.Generic.null p then
                                                           Data.Monoid.mempty
                                                       else
                                                           (Data.Monoid.<>)
                                                             (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                114)
                                                             ((\ bs
                                                                 -> (Data.Monoid.<>)
                                                                      (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                         (Prelude.fromIntegral
                                                                            (Data.ByteString.length
                                                                               bs)))
                                                                      (Data.ProtoLens.Encoding.Bytes.putBytes
                                                                         bs))
                                                                (Data.ProtoLens.Encoding.Bytes.runBuilder
                                                                   (Data.ProtoLens.Encoding.Bytes.foldMapBuilder
                                                                      ((Prelude..)
                                                                         ((Prelude..)
                                                                            Data.ProtoLens.Encoding.Bytes.putVarInt
                                                                            Prelude.fromIntegral)
                                                                         Prelude.fromEnum)
                                                                      p))))
                                                    (Data.ProtoLens.Encoding.Wire.buildFieldSet
                                                       (Lens.Family2.view
                                                          Data.ProtoLens.unknownFields
                                                          _x)))))))))))))))
instance Control.DeepSeq.NFData RequestSettings where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_RequestSettings'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_RequestSettings'maxTokens x__)
                (Control.DeepSeq.deepseq
                   (_RequestSettings'parallelToolCalls x__)
                   (Control.DeepSeq.deepseq
                      (_RequestSettings'previousResponseId x__)
                      (Control.DeepSeq.deepseq
                         (_RequestSettings'reasoningEffort x__)
                         (Control.DeepSeq.deepseq
                            (_RequestSettings'temperature x__)
                            (Control.DeepSeq.deepseq
                               (_RequestSettings'responseFormat x__)
                               (Control.DeepSeq.deepseq
                                  (_RequestSettings'toolChoice x__)
                                  (Control.DeepSeq.deepseq
                                     (_RequestSettings'tools x__)
                                     (Control.DeepSeq.deepseq
                                        (_RequestSettings'topP x__)
                                        (Control.DeepSeq.deepseq
                                           (_RequestSettings'user x__)
                                           (Control.DeepSeq.deepseq
                                              (_RequestSettings'searchParameters x__)
                                              (Control.DeepSeq.deepseq
                                                 (_RequestSettings'storeMessages x__)
                                                 (Control.DeepSeq.deepseq
                                                    (_RequestSettings'useEncryptedContent x__)
                                                    (Control.DeepSeq.deepseq
                                                       (_RequestSettings'include x__)
                                                       ()))))))))))))))
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Chat_Fields.formatType' @:: Lens' ResponseFormat FormatType@
         * 'Proto.Xai.Api.V1.Chat_Fields.schema' @:: Lens' ResponseFormat Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'schema' @:: Lens' ResponseFormat (Prelude.Maybe Data.Text.Text)@ -}
data ResponseFormat
  = ResponseFormat'_constructor {_ResponseFormat'formatType :: !FormatType,
                                 _ResponseFormat'schema :: !(Prelude.Maybe Data.Text.Text),
                                 _ResponseFormat'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show ResponseFormat where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField ResponseFormat "formatType" FormatType where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ResponseFormat'formatType
           (\ x__ y__ -> x__ {_ResponseFormat'formatType = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField ResponseFormat "schema" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ResponseFormat'schema
           (\ x__ y__ -> x__ {_ResponseFormat'schema = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField ResponseFormat "maybe'schema" (Prelude.Maybe Data.Text.Text) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ResponseFormat'schema
           (\ x__ y__ -> x__ {_ResponseFormat'schema = y__}))
        Prelude.id
instance Data.ProtoLens.Message ResponseFormat where
  messageName _ = Data.Text.pack "xai_api.ResponseFormat"
  packedMessageDescriptor _
    = "\n\
      \\SOResponseFormat\DC24\n\
      \\vformat_type\CAN\SOH \SOH(\SO2\DC3.xai_api.FormatTypeR\n\
      \formatType\DC2\ESC\n\
      \\ACKschema\CAN\STX \SOH(\tH\NULR\ACKschema\136\SOH\SOHB\t\n\
      \\a_schema"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        formatType__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "format_type"
              (Data.ProtoLens.ScalarField Data.ProtoLens.EnumField ::
                 Data.ProtoLens.FieldTypeDescriptor FormatType)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"formatType")) ::
              Data.ProtoLens.FieldDescriptor ResponseFormat
        schema__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "schema"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'schema")) ::
              Data.ProtoLens.FieldDescriptor ResponseFormat
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, formatType__field_descriptor),
           (Data.ProtoLens.Tag 2, schema__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _ResponseFormat'_unknownFields
        (\ x__ y__ -> x__ {_ResponseFormat'_unknownFields = y__})
  defMessage
    = ResponseFormat'_constructor
        {_ResponseFormat'formatType = Data.ProtoLens.fieldDefault,
         _ResponseFormat'schema = Prelude.Nothing,
         _ResponseFormat'_unknownFields = []}
  parseMessage
    = let
        loop ::
          ResponseFormat
          -> Data.ProtoLens.Encoding.Bytes.Parser ResponseFormat
        loop x
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t) x)
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        8 -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.toEnum
                                          (Prelude.fmap
                                             Prelude.fromIntegral
                                             Data.ProtoLens.Encoding.Bytes.getVarInt))
                                       "format_type"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"formatType") y x)
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "schema"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"schema") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "ResponseFormat"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v
                  = Lens.Family2.view (Data.ProtoLens.Field.field @"formatType") _x
              in
                if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 8)
                      ((Prelude..)
                         ((Prelude..)
                            Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral)
                         Prelude.fromEnum _v))
             ((Data.Monoid.<>)
                (case
                     Lens.Family2.view (Data.ProtoLens.Field.field @"maybe'schema") _x
                 of
                   Prelude.Nothing -> Data.Monoid.mempty
                   (Prelude.Just _v)
                     -> (Data.Monoid.<>)
                          (Data.ProtoLens.Encoding.Bytes.putVarInt 18)
                          ((Prelude..)
                             (\ bs
                                -> (Data.Monoid.<>)
                                     (Data.ProtoLens.Encoding.Bytes.putVarInt
                                        (Prelude.fromIntegral (Data.ByteString.length bs)))
                                     (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                             Data.Text.Encoding.encodeUtf8 _v))
                (Data.ProtoLens.Encoding.Wire.buildFieldSet
                   (Lens.Family2.view Data.ProtoLens.unknownFields _x)))
instance Control.DeepSeq.NFData ResponseFormat where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_ResponseFormat'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_ResponseFormat'formatType x__)
                (Control.DeepSeq.deepseq (_ResponseFormat'schema x__) ()))
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Chat_Fields.links' @:: Lens' RssSource [Data.Text.Text]@
         * 'Proto.Xai.Api.V1.Chat_Fields.vec'links' @:: Lens' RssSource (Data.Vector.Vector Data.Text.Text)@ -}
data RssSource
  = RssSource'_constructor {_RssSource'links :: !(Data.Vector.Vector Data.Text.Text),
                            _RssSource'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show RssSource where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField RssSource "links" [Data.Text.Text] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RssSource'links (\ x__ y__ -> x__ {_RssSource'links = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField RssSource "vec'links" (Data.Vector.Vector Data.Text.Text) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RssSource'links (\ x__ y__ -> x__ {_RssSource'links = y__}))
        Prelude.id
instance Data.ProtoLens.Message RssSource where
  messageName _ = Data.Text.pack "xai_api.RssSource"
  packedMessageDescriptor _
    = "\n\
      \\tRssSource\DC2\DC4\n\
      \\ENQlinks\CAN\SOH \ETX(\tR\ENQlinks"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        links__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "links"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Unpacked (Data.ProtoLens.Field.field @"links")) ::
              Data.ProtoLens.FieldDescriptor RssSource
      in
        Data.Map.fromList [(Data.ProtoLens.Tag 1, links__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _RssSource'_unknownFields
        (\ x__ y__ -> x__ {_RssSource'_unknownFields = y__})
  defMessage
    = RssSource'_constructor
        {_RssSource'links = Data.Vector.Generic.empty,
         _RssSource'_unknownFields = []}
  parseMessage
    = let
        loop ::
          RssSource
          -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Vector Data.ProtoLens.Encoding.Growing.RealWorld Data.Text.Text
             -> Data.ProtoLens.Encoding.Bytes.Parser RssSource
        loop x mutable'links
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do frozen'links <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                        (Data.ProtoLens.Encoding.Growing.unsafeFreeze mutable'links)
                      (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t)
                           (Lens.Family2.set
                              (Data.ProtoLens.Field.field @"vec'links") frozen'links x))
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                            Data.ProtoLens.Encoding.Bytes.getText
                                              (Prelude.fromIntegral len))
                                        "links"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append mutable'links y)
                                loop x v
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
                                  mutable'links
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do mutable'links <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                 Data.ProtoLens.Encoding.Growing.new
              loop Data.ProtoLens.defMessage mutable'links)
          "RssSource"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (Data.ProtoLens.Encoding.Bytes.foldMapBuilder
                (\ _v
                   -> (Data.Monoid.<>)
                        (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                        ((Prelude..)
                           (\ bs
                              -> (Data.Monoid.<>)
                                   (Data.ProtoLens.Encoding.Bytes.putVarInt
                                      (Prelude.fromIntegral (Data.ByteString.length bs)))
                                   (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                           Data.Text.Encoding.encodeUtf8 _v))
                (Lens.Family2.view (Data.ProtoLens.Field.field @"vec'links") _x))
             (Data.ProtoLens.Encoding.Wire.buildFieldSet
                (Lens.Family2.view Data.ProtoLens.unknownFields _x))
instance Control.DeepSeq.NFData RssSource where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_RssSource'_unknownFields x__)
             (Control.DeepSeq.deepseq (_RssSource'links x__) ())
newtype SearchMode'UnrecognizedValue
  = SearchMode'UnrecognizedValue Data.Int.Int32
  deriving stock (Prelude.Eq, Prelude.Ord, Prelude.Show)
data SearchMode
  = INVALID_SEARCH_MODE |
    OFF_SEARCH_MODE |
    ON_SEARCH_MODE |
    AUTO_SEARCH_MODE |
    SearchMode'Unrecognized !SearchMode'UnrecognizedValue
  deriving stock (Prelude.Show, Prelude.Eq, Prelude.Ord)
instance Data.ProtoLens.MessageEnum SearchMode where
  maybeToEnum 0 = Prelude.Just INVALID_SEARCH_MODE
  maybeToEnum 1 = Prelude.Just OFF_SEARCH_MODE
  maybeToEnum 2 = Prelude.Just ON_SEARCH_MODE
  maybeToEnum 3 = Prelude.Just AUTO_SEARCH_MODE
  maybeToEnum k
    = Prelude.Just
        (SearchMode'Unrecognized
           (SearchMode'UnrecognizedValue (Prelude.fromIntegral k)))
  showEnum INVALID_SEARCH_MODE = "INVALID_SEARCH_MODE"
  showEnum OFF_SEARCH_MODE = "OFF_SEARCH_MODE"
  showEnum ON_SEARCH_MODE = "ON_SEARCH_MODE"
  showEnum AUTO_SEARCH_MODE = "AUTO_SEARCH_MODE"
  showEnum (SearchMode'Unrecognized (SearchMode'UnrecognizedValue k))
    = Prelude.show k
  readEnum k
    | (Prelude.==) k "INVALID_SEARCH_MODE"
    = Prelude.Just INVALID_SEARCH_MODE
    | (Prelude.==) k "OFF_SEARCH_MODE" = Prelude.Just OFF_SEARCH_MODE
    | (Prelude.==) k "ON_SEARCH_MODE" = Prelude.Just ON_SEARCH_MODE
    | (Prelude.==) k "AUTO_SEARCH_MODE" = Prelude.Just AUTO_SEARCH_MODE
    | Prelude.otherwise
    = (Prelude.>>=) (Text.Read.readMaybe k) Data.ProtoLens.maybeToEnum
instance Prelude.Bounded SearchMode where
  minBound = INVALID_SEARCH_MODE
  maxBound = AUTO_SEARCH_MODE
instance Prelude.Enum SearchMode where
  toEnum k__
    = Prelude.maybe
        (Prelude.error
           ((Prelude.++)
              "toEnum: unknown value for enum SearchMode: " (Prelude.show k__)))
        Prelude.id (Data.ProtoLens.maybeToEnum k__)
  fromEnum INVALID_SEARCH_MODE = 0
  fromEnum OFF_SEARCH_MODE = 1
  fromEnum ON_SEARCH_MODE = 2
  fromEnum AUTO_SEARCH_MODE = 3
  fromEnum (SearchMode'Unrecognized (SearchMode'UnrecognizedValue k))
    = Prelude.fromIntegral k
  succ AUTO_SEARCH_MODE
    = Prelude.error
        "SearchMode.succ: bad argument AUTO_SEARCH_MODE. This value would be out of bounds."
  succ INVALID_SEARCH_MODE = OFF_SEARCH_MODE
  succ OFF_SEARCH_MODE = ON_SEARCH_MODE
  succ ON_SEARCH_MODE = AUTO_SEARCH_MODE
  succ (SearchMode'Unrecognized _)
    = Prelude.error "SearchMode.succ: bad argument: unrecognized value"
  pred INVALID_SEARCH_MODE
    = Prelude.error
        "SearchMode.pred: bad argument INVALID_SEARCH_MODE. This value would be out of bounds."
  pred OFF_SEARCH_MODE = INVALID_SEARCH_MODE
  pred ON_SEARCH_MODE = OFF_SEARCH_MODE
  pred AUTO_SEARCH_MODE = ON_SEARCH_MODE
  pred (SearchMode'Unrecognized _)
    = Prelude.error "SearchMode.pred: bad argument: unrecognized value"
  enumFrom = Data.ProtoLens.Message.Enum.messageEnumFrom
  enumFromTo = Data.ProtoLens.Message.Enum.messageEnumFromTo
  enumFromThen = Data.ProtoLens.Message.Enum.messageEnumFromThen
  enumFromThenTo = Data.ProtoLens.Message.Enum.messageEnumFromThenTo
instance Data.ProtoLens.FieldDefault SearchMode where
  fieldDefault = INVALID_SEARCH_MODE
instance Control.DeepSeq.NFData SearchMode where
  rnf x__ = Prelude.seq x__ ()
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Chat_Fields.mode' @:: Lens' SearchParameters SearchMode@
         * 'Proto.Xai.Api.V1.Chat_Fields.sources' @:: Lens' SearchParameters [Source]@
         * 'Proto.Xai.Api.V1.Chat_Fields.vec'sources' @:: Lens' SearchParameters (Data.Vector.Vector Source)@
         * 'Proto.Xai.Api.V1.Chat_Fields.fromDate' @:: Lens' SearchParameters Proto.Google.Protobuf.Timestamp.Timestamp@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'fromDate' @:: Lens' SearchParameters (Prelude.Maybe Proto.Google.Protobuf.Timestamp.Timestamp)@
         * 'Proto.Xai.Api.V1.Chat_Fields.toDate' @:: Lens' SearchParameters Proto.Google.Protobuf.Timestamp.Timestamp@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'toDate' @:: Lens' SearchParameters (Prelude.Maybe Proto.Google.Protobuf.Timestamp.Timestamp)@
         * 'Proto.Xai.Api.V1.Chat_Fields.returnCitations' @:: Lens' SearchParameters Prelude.Bool@
         * 'Proto.Xai.Api.V1.Chat_Fields.maxSearchResults' @:: Lens' SearchParameters Data.Int.Int32@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'maxSearchResults' @:: Lens' SearchParameters (Prelude.Maybe Data.Int.Int32)@ -}
data SearchParameters
  = SearchParameters'_constructor {_SearchParameters'mode :: !SearchMode,
                                   _SearchParameters'sources :: !(Data.Vector.Vector Source),
                                   _SearchParameters'fromDate :: !(Prelude.Maybe Proto.Google.Protobuf.Timestamp.Timestamp),
                                   _SearchParameters'toDate :: !(Prelude.Maybe Proto.Google.Protobuf.Timestamp.Timestamp),
                                   _SearchParameters'returnCitations :: !Prelude.Bool,
                                   _SearchParameters'maxSearchResults :: !(Prelude.Maybe Data.Int.Int32),
                                   _SearchParameters'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show SearchParameters where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField SearchParameters "mode" SearchMode where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SearchParameters'mode
           (\ x__ y__ -> x__ {_SearchParameters'mode = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SearchParameters "sources" [Source] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SearchParameters'sources
           (\ x__ y__ -> x__ {_SearchParameters'sources = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField SearchParameters "vec'sources" (Data.Vector.Vector Source) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SearchParameters'sources
           (\ x__ y__ -> x__ {_SearchParameters'sources = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SearchParameters "fromDate" Proto.Google.Protobuf.Timestamp.Timestamp where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SearchParameters'fromDate
           (\ x__ y__ -> x__ {_SearchParameters'fromDate = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage)
instance Data.ProtoLens.Field.HasField SearchParameters "maybe'fromDate" (Prelude.Maybe Proto.Google.Protobuf.Timestamp.Timestamp) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SearchParameters'fromDate
           (\ x__ y__ -> x__ {_SearchParameters'fromDate = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SearchParameters "toDate" Proto.Google.Protobuf.Timestamp.Timestamp where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SearchParameters'toDate
           (\ x__ y__ -> x__ {_SearchParameters'toDate = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage)
instance Data.ProtoLens.Field.HasField SearchParameters "maybe'toDate" (Prelude.Maybe Proto.Google.Protobuf.Timestamp.Timestamp) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SearchParameters'toDate
           (\ x__ y__ -> x__ {_SearchParameters'toDate = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SearchParameters "returnCitations" Prelude.Bool where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SearchParameters'returnCitations
           (\ x__ y__ -> x__ {_SearchParameters'returnCitations = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SearchParameters "maxSearchResults" Data.Int.Int32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SearchParameters'maxSearchResults
           (\ x__ y__ -> x__ {_SearchParameters'maxSearchResults = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField SearchParameters "maybe'maxSearchResults" (Prelude.Maybe Data.Int.Int32) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SearchParameters'maxSearchResults
           (\ x__ y__ -> x__ {_SearchParameters'maxSearchResults = y__}))
        Prelude.id
instance Data.ProtoLens.Message SearchParameters where
  messageName _ = Data.Text.pack "xai_api.SearchParameters"
  packedMessageDescriptor _
    = "\n\
      \\DLESearchParameters\DC2'\n\
      \\EOTmode\CAN\SOH \SOH(\SO2\DC3.xai_api.SearchModeR\EOTmode\DC2)\n\
      \\asources\CAN\t \ETX(\v2\SI.xai_api.SourceR\asources\DC27\n\
      \\tfrom_date\CAN\EOT \SOH(\v2\SUB.google.protobuf.TimestampR\bfromDate\DC23\n\
      \\ato_date\CAN\ENQ \SOH(\v2\SUB.google.protobuf.TimestampR\ACKtoDate\DC2)\n\
      \\DLEreturn_citations\CAN\a \SOH(\bR\SIreturnCitations\DC21\n\
      \\DC2max_search_results\CAN\b \SOH(\ENQH\NULR\DLEmaxSearchResults\136\SOH\SOHB\NAK\n\
      \\DC3_max_search_results"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        mode__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "mode"
              (Data.ProtoLens.ScalarField Data.ProtoLens.EnumField ::
                 Data.ProtoLens.FieldTypeDescriptor SearchMode)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"mode")) ::
              Data.ProtoLens.FieldDescriptor SearchParameters
        sources__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "sources"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor Source)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Unpacked (Data.ProtoLens.Field.field @"sources")) ::
              Data.ProtoLens.FieldDescriptor SearchParameters
        fromDate__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "from_date"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor Proto.Google.Protobuf.Timestamp.Timestamp)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'fromDate")) ::
              Data.ProtoLens.FieldDescriptor SearchParameters
        toDate__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "to_date"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor Proto.Google.Protobuf.Timestamp.Timestamp)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'toDate")) ::
              Data.ProtoLens.FieldDescriptor SearchParameters
        returnCitations__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "return_citations"
              (Data.ProtoLens.ScalarField Data.ProtoLens.BoolField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Bool)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"returnCitations")) ::
              Data.ProtoLens.FieldDescriptor SearchParameters
        maxSearchResults__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "max_search_results"
              (Data.ProtoLens.ScalarField Data.ProtoLens.Int32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Int.Int32)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'maxSearchResults")) ::
              Data.ProtoLens.FieldDescriptor SearchParameters
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, mode__field_descriptor),
           (Data.ProtoLens.Tag 9, sources__field_descriptor),
           (Data.ProtoLens.Tag 4, fromDate__field_descriptor),
           (Data.ProtoLens.Tag 5, toDate__field_descriptor),
           (Data.ProtoLens.Tag 7, returnCitations__field_descriptor),
           (Data.ProtoLens.Tag 8, maxSearchResults__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _SearchParameters'_unknownFields
        (\ x__ y__ -> x__ {_SearchParameters'_unknownFields = y__})
  defMessage
    = SearchParameters'_constructor
        {_SearchParameters'mode = Data.ProtoLens.fieldDefault,
         _SearchParameters'sources = Data.Vector.Generic.empty,
         _SearchParameters'fromDate = Prelude.Nothing,
         _SearchParameters'toDate = Prelude.Nothing,
         _SearchParameters'returnCitations = Data.ProtoLens.fieldDefault,
         _SearchParameters'maxSearchResults = Prelude.Nothing,
         _SearchParameters'_unknownFields = []}
  parseMessage
    = let
        loop ::
          SearchParameters
          -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Vector Data.ProtoLens.Encoding.Growing.RealWorld Source
             -> Data.ProtoLens.Encoding.Bytes.Parser SearchParameters
        loop x mutable'sources
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do frozen'sources <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                          (Data.ProtoLens.Encoding.Growing.unsafeFreeze
                                             mutable'sources)
                      (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t)
                           (Lens.Family2.set
                              (Data.ProtoLens.Field.field @"vec'sources") frozen'sources x))
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        8 -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.toEnum
                                          (Prelude.fmap
                                             Prelude.fromIntegral
                                             Data.ProtoLens.Encoding.Bytes.getVarInt))
                                       "mode"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"mode") y x)
                                  mutable'sources
                        74
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                            Data.ProtoLens.Encoding.Bytes.isolate
                                              (Prelude.fromIntegral len)
                                              Data.ProtoLens.parseMessage)
                                        "sources"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append mutable'sources y)
                                loop x v
                        34
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "from_date"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"fromDate") y x)
                                  mutable'sources
                        42
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "to_date"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"toDate") y x)
                                  mutable'sources
                        56
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          ((Prelude./=) 0) Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "return_citations"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"returnCitations") y x)
                                  mutable'sources
                        64
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "max_search_results"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"maxSearchResults") y x)
                                  mutable'sources
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
                                  mutable'sources
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do mutable'sources <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                   Data.ProtoLens.Encoding.Growing.new
              loop Data.ProtoLens.defMessage mutable'sources)
          "SearchParameters"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let _v = Lens.Family2.view (Data.ProtoLens.Field.field @"mode") _x
              in
                if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 8)
                      ((Prelude..)
                         ((Prelude..)
                            Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral)
                         Prelude.fromEnum _v))
             ((Data.Monoid.<>)
                (Data.ProtoLens.Encoding.Bytes.foldMapBuilder
                   (\ _v
                      -> (Data.Monoid.<>)
                           (Data.ProtoLens.Encoding.Bytes.putVarInt 74)
                           ((Prelude..)
                              (\ bs
                                 -> (Data.Monoid.<>)
                                      (Data.ProtoLens.Encoding.Bytes.putVarInt
                                         (Prelude.fromIntegral (Data.ByteString.length bs)))
                                      (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                              Data.ProtoLens.encodeMessage _v))
                   (Lens.Family2.view (Data.ProtoLens.Field.field @"vec'sources") _x))
                ((Data.Monoid.<>)
                   (case
                        Lens.Family2.view (Data.ProtoLens.Field.field @"maybe'fromDate") _x
                    of
                      Prelude.Nothing -> Data.Monoid.mempty
                      (Prelude.Just _v)
                        -> (Data.Monoid.<>)
                             (Data.ProtoLens.Encoding.Bytes.putVarInt 34)
                             ((Prelude..)
                                (\ bs
                                   -> (Data.Monoid.<>)
                                        (Data.ProtoLens.Encoding.Bytes.putVarInt
                                           (Prelude.fromIntegral (Data.ByteString.length bs)))
                                        (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                Data.ProtoLens.encodeMessage _v))
                   ((Data.Monoid.<>)
                      (case
                           Lens.Family2.view (Data.ProtoLens.Field.field @"maybe'toDate") _x
                       of
                         Prelude.Nothing -> Data.Monoid.mempty
                         (Prelude.Just _v)
                           -> (Data.Monoid.<>)
                                (Data.ProtoLens.Encoding.Bytes.putVarInt 42)
                                ((Prelude..)
                                   (\ bs
                                      -> (Data.Monoid.<>)
                                           (Data.ProtoLens.Encoding.Bytes.putVarInt
                                              (Prelude.fromIntegral (Data.ByteString.length bs)))
                                           (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                   Data.ProtoLens.encodeMessage _v))
                      ((Data.Monoid.<>)
                         (let
                            _v
                              = Lens.Family2.view
                                  (Data.ProtoLens.Field.field @"returnCitations") _x
                          in
                            if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                Data.Monoid.mempty
                            else
                                (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt 56)
                                  ((Prelude..)
                                     Data.ProtoLens.Encoding.Bytes.putVarInt
                                     (\ b -> if b then 1 else 0) _v))
                         ((Data.Monoid.<>)
                            (case
                                 Lens.Family2.view
                                   (Data.ProtoLens.Field.field @"maybe'maxSearchResults") _x
                             of
                               Prelude.Nothing -> Data.Monoid.mempty
                               (Prelude.Just _v)
                                 -> (Data.Monoid.<>)
                                      (Data.ProtoLens.Encoding.Bytes.putVarInt 64)
                                      ((Prelude..)
                                         Data.ProtoLens.Encoding.Bytes.putVarInt
                                         Prelude.fromIntegral _v))
                            (Data.ProtoLens.Encoding.Wire.buildFieldSet
                               (Lens.Family2.view Data.ProtoLens.unknownFields _x)))))))
instance Control.DeepSeq.NFData SearchParameters where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_SearchParameters'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_SearchParameters'mode x__)
                (Control.DeepSeq.deepseq
                   (_SearchParameters'sources x__)
                   (Control.DeepSeq.deepseq
                      (_SearchParameters'fromDate x__)
                      (Control.DeepSeq.deepseq
                         (_SearchParameters'toDate x__)
                         (Control.DeepSeq.deepseq
                            (_SearchParameters'returnCitations x__)
                            (Control.DeepSeq.deepseq
                               (_SearchParameters'maxSearchResults x__) ()))))))
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'source' @:: Lens' Source (Prelude.Maybe Source'Source)@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'web' @:: Lens' Source (Prelude.Maybe WebSource)@
         * 'Proto.Xai.Api.V1.Chat_Fields.web' @:: Lens' Source WebSource@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'news' @:: Lens' Source (Prelude.Maybe NewsSource)@
         * 'Proto.Xai.Api.V1.Chat_Fields.news' @:: Lens' Source NewsSource@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'x' @:: Lens' Source (Prelude.Maybe XSource)@
         * 'Proto.Xai.Api.V1.Chat_Fields.x' @:: Lens' Source XSource@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'rss' @:: Lens' Source (Prelude.Maybe RssSource)@
         * 'Proto.Xai.Api.V1.Chat_Fields.rss' @:: Lens' Source RssSource@ -}
data Source
  = Source'_constructor {_Source'source :: !(Prelude.Maybe Source'Source),
                         _Source'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show Source where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
data Source'Source
  = Source'Web !WebSource |
    Source'News !NewsSource |
    Source'X !XSource |
    Source'Rss !RssSource
  deriving stock (Prelude.Show, Prelude.Eq, Prelude.Ord)
instance Data.ProtoLens.Field.HasField Source "maybe'source" (Prelude.Maybe Source'Source) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Source'source (\ x__ y__ -> x__ {_Source'source = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField Source "maybe'web" (Prelude.Maybe WebSource) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Source'source (\ x__ y__ -> x__ {_Source'source = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (Source'Web x__val)) -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap Source'Web y__))
instance Data.ProtoLens.Field.HasField Source "web" WebSource where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Source'source (\ x__ y__ -> x__ {_Source'source = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (Source'Web x__val)) -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap Source'Web y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Field.HasField Source "maybe'news" (Prelude.Maybe NewsSource) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Source'source (\ x__ y__ -> x__ {_Source'source = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (Source'News x__val)) -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap Source'News y__))
instance Data.ProtoLens.Field.HasField Source "news" NewsSource where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Source'source (\ x__ y__ -> x__ {_Source'source = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (Source'News x__val)) -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap Source'News y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Field.HasField Source "maybe'x" (Prelude.Maybe XSource) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Source'source (\ x__ y__ -> x__ {_Source'source = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (Source'X x__val)) -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap Source'X y__))
instance Data.ProtoLens.Field.HasField Source "x" XSource where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Source'source (\ x__ y__ -> x__ {_Source'source = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (Source'X x__val)) -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap Source'X y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Field.HasField Source "maybe'rss" (Prelude.Maybe RssSource) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Source'source (\ x__ y__ -> x__ {_Source'source = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (Source'Rss x__val)) -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap Source'Rss y__))
instance Data.ProtoLens.Field.HasField Source "rss" RssSource where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Source'source (\ x__ y__ -> x__ {_Source'source = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (Source'Rss x__val)) -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap Source'Rss y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Message Source where
  messageName _ = Data.Text.pack "xai_api.Source"
  packedMessageDescriptor _
    = "\n\
      \\ACKSource\DC2&\n\
      \\ETXweb\CAN\SOH \SOH(\v2\DC2.xai_api.WebSourceH\NULR\ETXweb\DC2)\n\
      \\EOTnews\CAN\STX \SOH(\v2\DC3.xai_api.NewsSourceH\NULR\EOTnews\DC2 \n\
      \\SOHx\CAN\ETX \SOH(\v2\DLE.xai_api.XSourceH\NULR\SOHx\DC2&\n\
      \\ETXrss\CAN\EOT \SOH(\v2\DC2.xai_api.RssSourceH\NULR\ETXrssB\b\n\
      \\ACKsource"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        web__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "web"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor WebSource)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'web")) ::
              Data.ProtoLens.FieldDescriptor Source
        news__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "news"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor NewsSource)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'news")) ::
              Data.ProtoLens.FieldDescriptor Source
        x__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "x"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor XSource)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'x")) ::
              Data.ProtoLens.FieldDescriptor Source
        rss__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "rss"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor RssSource)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'rss")) ::
              Data.ProtoLens.FieldDescriptor Source
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, web__field_descriptor),
           (Data.ProtoLens.Tag 2, news__field_descriptor),
           (Data.ProtoLens.Tag 3, x__field_descriptor),
           (Data.ProtoLens.Tag 4, rss__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _Source'_unknownFields
        (\ x__ y__ -> x__ {_Source'_unknownFields = y__})
  defMessage
    = Source'_constructor
        {_Source'source = Prelude.Nothing, _Source'_unknownFields = []}
  parseMessage
    = let
        loop :: Source -> Data.ProtoLens.Encoding.Bytes.Parser Source
        loop x
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t) x)
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "web"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"web") y x)
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "news"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"news") y x)
                        26
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "x"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"x") y x)
                        34
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "rss"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"rss") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "Source"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (case
                  Lens.Family2.view (Data.ProtoLens.Field.field @"maybe'source") _x
              of
                Prelude.Nothing -> Data.Monoid.mempty
                (Prelude.Just (Source'Web v))
                  -> (Data.Monoid.<>)
                       (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                       ((Prelude..)
                          (\ bs
                             -> (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                     (Prelude.fromIntegral (Data.ByteString.length bs)))
                                  (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                          Data.ProtoLens.encodeMessage v)
                (Prelude.Just (Source'News v))
                  -> (Data.Monoid.<>)
                       (Data.ProtoLens.Encoding.Bytes.putVarInt 18)
                       ((Prelude..)
                          (\ bs
                             -> (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                     (Prelude.fromIntegral (Data.ByteString.length bs)))
                                  (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                          Data.ProtoLens.encodeMessage v)
                (Prelude.Just (Source'X v))
                  -> (Data.Monoid.<>)
                       (Data.ProtoLens.Encoding.Bytes.putVarInt 26)
                       ((Prelude..)
                          (\ bs
                             -> (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                     (Prelude.fromIntegral (Data.ByteString.length bs)))
                                  (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                          Data.ProtoLens.encodeMessage v)
                (Prelude.Just (Source'Rss v))
                  -> (Data.Monoid.<>)
                       (Data.ProtoLens.Encoding.Bytes.putVarInt 34)
                       ((Prelude..)
                          (\ bs
                             -> (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                     (Prelude.fromIntegral (Data.ByteString.length bs)))
                                  (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                          Data.ProtoLens.encodeMessage v))
             (Data.ProtoLens.Encoding.Wire.buildFieldSet
                (Lens.Family2.view Data.ProtoLens.unknownFields _x))
instance Control.DeepSeq.NFData Source where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_Source'_unknownFields x__)
             (Control.DeepSeq.deepseq (_Source'source x__) ())
instance Control.DeepSeq.NFData Source'Source where
  rnf (Source'Web x__) = Control.DeepSeq.rnf x__
  rnf (Source'News x__) = Control.DeepSeq.rnf x__
  rnf (Source'X x__) = Control.DeepSeq.rnf x__
  rnf (Source'Rss x__) = Control.DeepSeq.rnf x__
_Source'Web :: Data.ProtoLens.Prism.Prism' Source'Source WebSource
_Source'Web
  = Data.ProtoLens.Prism.prism'
      Source'Web
      (\ p__
         -> case p__ of
              (Source'Web p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
_Source'News ::
  Data.ProtoLens.Prism.Prism' Source'Source NewsSource
_Source'News
  = Data.ProtoLens.Prism.prism'
      Source'News
      (\ p__
         -> case p__ of
              (Source'News p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
_Source'X :: Data.ProtoLens.Prism.Prism' Source'Source XSource
_Source'X
  = Data.ProtoLens.Prism.prism'
      Source'X
      (\ p__
         -> case p__ of
              (Source'X p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
_Source'Rss :: Data.ProtoLens.Prism.Prism' Source'Source RssSource
_Source'Rss
  = Data.ProtoLens.Prism.prism'
      Source'Rss
      (\ p__
         -> case p__ of
              (Source'Rss p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'tool' @:: Lens' Tool (Prelude.Maybe Tool'Tool)@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'function' @:: Lens' Tool (Prelude.Maybe Function)@
         * 'Proto.Xai.Api.V1.Chat_Fields.function' @:: Lens' Tool Function@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'webSearch' @:: Lens' Tool (Prelude.Maybe WebSearch)@
         * 'Proto.Xai.Api.V1.Chat_Fields.webSearch' @:: Lens' Tool WebSearch@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'xSearch' @:: Lens' Tool (Prelude.Maybe XSearch)@
         * 'Proto.Xai.Api.V1.Chat_Fields.xSearch' @:: Lens' Tool XSearch@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'codeExecution' @:: Lens' Tool (Prelude.Maybe CodeExecution)@
         * 'Proto.Xai.Api.V1.Chat_Fields.codeExecution' @:: Lens' Tool CodeExecution@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'collectionsSearch' @:: Lens' Tool (Prelude.Maybe CollectionsSearch)@
         * 'Proto.Xai.Api.V1.Chat_Fields.collectionsSearch' @:: Lens' Tool CollectionsSearch@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'mcp' @:: Lens' Tool (Prelude.Maybe MCP)@
         * 'Proto.Xai.Api.V1.Chat_Fields.mcp' @:: Lens' Tool MCP@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'attachmentSearch' @:: Lens' Tool (Prelude.Maybe AttachmentSearch)@
         * 'Proto.Xai.Api.V1.Chat_Fields.attachmentSearch' @:: Lens' Tool AttachmentSearch@ -}
data Tool
  = Tool'_constructor {_Tool'tool :: !(Prelude.Maybe Tool'Tool),
                       _Tool'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show Tool where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
data Tool'Tool
  = Tool'Function !Function |
    Tool'WebSearch !WebSearch |
    Tool'XSearch !XSearch |
    Tool'CodeExecution !CodeExecution |
    Tool'CollectionsSearch !CollectionsSearch |
    Tool'Mcp !MCP |
    Tool'AttachmentSearch !AttachmentSearch
  deriving stock (Prelude.Show, Prelude.Eq, Prelude.Ord)
instance Data.ProtoLens.Field.HasField Tool "maybe'tool" (Prelude.Maybe Tool'Tool) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Tool'tool (\ x__ y__ -> x__ {_Tool'tool = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField Tool "maybe'function" (Prelude.Maybe Function) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Tool'tool (\ x__ y__ -> x__ {_Tool'tool = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (Tool'Function x__val)) -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap Tool'Function y__))
instance Data.ProtoLens.Field.HasField Tool "function" Function where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Tool'tool (\ x__ y__ -> x__ {_Tool'tool = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (Tool'Function x__val)) -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap Tool'Function y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Field.HasField Tool "maybe'webSearch" (Prelude.Maybe WebSearch) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Tool'tool (\ x__ y__ -> x__ {_Tool'tool = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (Tool'WebSearch x__val)) -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap Tool'WebSearch y__))
instance Data.ProtoLens.Field.HasField Tool "webSearch" WebSearch where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Tool'tool (\ x__ y__ -> x__ {_Tool'tool = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (Tool'WebSearch x__val)) -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap Tool'WebSearch y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Field.HasField Tool "maybe'xSearch" (Prelude.Maybe XSearch) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Tool'tool (\ x__ y__ -> x__ {_Tool'tool = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (Tool'XSearch x__val)) -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap Tool'XSearch y__))
instance Data.ProtoLens.Field.HasField Tool "xSearch" XSearch where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Tool'tool (\ x__ y__ -> x__ {_Tool'tool = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (Tool'XSearch x__val)) -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap Tool'XSearch y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Field.HasField Tool "maybe'codeExecution" (Prelude.Maybe CodeExecution) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Tool'tool (\ x__ y__ -> x__ {_Tool'tool = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (Tool'CodeExecution x__val)) -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap Tool'CodeExecution y__))
instance Data.ProtoLens.Field.HasField Tool "codeExecution" CodeExecution where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Tool'tool (\ x__ y__ -> x__ {_Tool'tool = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (Tool'CodeExecution x__val)) -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap Tool'CodeExecution y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Field.HasField Tool "maybe'collectionsSearch" (Prelude.Maybe CollectionsSearch) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Tool'tool (\ x__ y__ -> x__ {_Tool'tool = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (Tool'CollectionsSearch x__val))
                     -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap Tool'CollectionsSearch y__))
instance Data.ProtoLens.Field.HasField Tool "collectionsSearch" CollectionsSearch where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Tool'tool (\ x__ y__ -> x__ {_Tool'tool = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (Tool'CollectionsSearch x__val))
                        -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap Tool'CollectionsSearch y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Field.HasField Tool "maybe'mcp" (Prelude.Maybe MCP) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Tool'tool (\ x__ y__ -> x__ {_Tool'tool = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (Tool'Mcp x__val)) -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap Tool'Mcp y__))
instance Data.ProtoLens.Field.HasField Tool "mcp" MCP where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Tool'tool (\ x__ y__ -> x__ {_Tool'tool = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (Tool'Mcp x__val)) -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap Tool'Mcp y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Field.HasField Tool "maybe'attachmentSearch" (Prelude.Maybe AttachmentSearch) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Tool'tool (\ x__ y__ -> x__ {_Tool'tool = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (Tool'AttachmentSearch x__val))
                     -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap Tool'AttachmentSearch y__))
instance Data.ProtoLens.Field.HasField Tool "attachmentSearch" AttachmentSearch where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _Tool'tool (\ x__ y__ -> x__ {_Tool'tool = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (Tool'AttachmentSearch x__val))
                        -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap Tool'AttachmentSearch y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Message Tool where
  messageName _ = Data.Text.pack "xai_api.Tool"
  packedMessageDescriptor _
    = "\n\
      \\EOTTool\DC2/\n\
      \\bfunction\CAN\SOH \SOH(\v2\DC1.xai_api.FunctionH\NULR\bfunction\DC23\n\
      \\n\
      \web_search\CAN\ETX \SOH(\v2\DC2.xai_api.WebSearchH\NULR\twebSearch\DC2-\n\
      \\bx_search\CAN\EOT \SOH(\v2\DLE.xai_api.XSearchH\NULR\axSearch\DC2?\n\
      \\SOcode_execution\CAN\ENQ \SOH(\v2\SYN.xai_api.CodeExecutionH\NULR\rcodeExecution\DC2K\n\
      \\DC2collections_search\CAN\ACK \SOH(\v2\SUB.xai_api.CollectionsSearchH\NULR\DC1collectionsSearch\DC2 \n\
      \\ETXmcp\CAN\a \SOH(\v2\f.xai_api.MCPH\NULR\ETXmcp\DC2H\n\
      \\DC1attachment_search\CAN\b \SOH(\v2\EM.xai_api.AttachmentSearchH\NULR\DLEattachmentSearchB\ACK\n\
      \\EOTtool"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        function__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "function"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor Function)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'function")) ::
              Data.ProtoLens.FieldDescriptor Tool
        webSearch__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "web_search"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor WebSearch)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'webSearch")) ::
              Data.ProtoLens.FieldDescriptor Tool
        xSearch__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "x_search"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor XSearch)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'xSearch")) ::
              Data.ProtoLens.FieldDescriptor Tool
        codeExecution__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "code_execution"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor CodeExecution)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'codeExecution")) ::
              Data.ProtoLens.FieldDescriptor Tool
        collectionsSearch__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "collections_search"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor CollectionsSearch)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'collectionsSearch")) ::
              Data.ProtoLens.FieldDescriptor Tool
        mcp__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "mcp"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor MCP)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'mcp")) ::
              Data.ProtoLens.FieldDescriptor Tool
        attachmentSearch__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "attachment_search"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor AttachmentSearch)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'attachmentSearch")) ::
              Data.ProtoLens.FieldDescriptor Tool
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, function__field_descriptor),
           (Data.ProtoLens.Tag 3, webSearch__field_descriptor),
           (Data.ProtoLens.Tag 4, xSearch__field_descriptor),
           (Data.ProtoLens.Tag 5, codeExecution__field_descriptor),
           (Data.ProtoLens.Tag 6, collectionsSearch__field_descriptor),
           (Data.ProtoLens.Tag 7, mcp__field_descriptor),
           (Data.ProtoLens.Tag 8, attachmentSearch__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _Tool'_unknownFields
        (\ x__ y__ -> x__ {_Tool'_unknownFields = y__})
  defMessage
    = Tool'_constructor
        {_Tool'tool = Prelude.Nothing, _Tool'_unknownFields = []}
  parseMessage
    = let
        loop :: Tool -> Data.ProtoLens.Encoding.Bytes.Parser Tool
        loop x
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t) x)
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "function"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"function") y x)
                        26
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "web_search"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"webSearch") y x)
                        34
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "x_search"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"xSearch") y x)
                        42
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "code_execution"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"codeExecution") y x)
                        50
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "collections_search"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"collectionsSearch") y x)
                        58
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "mcp"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"mcp") y x)
                        66
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "attachment_search"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"attachmentSearch") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "Tool"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (case
                  Lens.Family2.view (Data.ProtoLens.Field.field @"maybe'tool") _x
              of
                Prelude.Nothing -> Data.Monoid.mempty
                (Prelude.Just (Tool'Function v))
                  -> (Data.Monoid.<>)
                       (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                       ((Prelude..)
                          (\ bs
                             -> (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                     (Prelude.fromIntegral (Data.ByteString.length bs)))
                                  (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                          Data.ProtoLens.encodeMessage v)
                (Prelude.Just (Tool'WebSearch v))
                  -> (Data.Monoid.<>)
                       (Data.ProtoLens.Encoding.Bytes.putVarInt 26)
                       ((Prelude..)
                          (\ bs
                             -> (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                     (Prelude.fromIntegral (Data.ByteString.length bs)))
                                  (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                          Data.ProtoLens.encodeMessage v)
                (Prelude.Just (Tool'XSearch v))
                  -> (Data.Monoid.<>)
                       (Data.ProtoLens.Encoding.Bytes.putVarInt 34)
                       ((Prelude..)
                          (\ bs
                             -> (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                     (Prelude.fromIntegral (Data.ByteString.length bs)))
                                  (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                          Data.ProtoLens.encodeMessage v)
                (Prelude.Just (Tool'CodeExecution v))
                  -> (Data.Monoid.<>)
                       (Data.ProtoLens.Encoding.Bytes.putVarInt 42)
                       ((Prelude..)
                          (\ bs
                             -> (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                     (Prelude.fromIntegral (Data.ByteString.length bs)))
                                  (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                          Data.ProtoLens.encodeMessage v)
                (Prelude.Just (Tool'CollectionsSearch v))
                  -> (Data.Monoid.<>)
                       (Data.ProtoLens.Encoding.Bytes.putVarInt 50)
                       ((Prelude..)
                          (\ bs
                             -> (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                     (Prelude.fromIntegral (Data.ByteString.length bs)))
                                  (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                          Data.ProtoLens.encodeMessage v)
                (Prelude.Just (Tool'Mcp v))
                  -> (Data.Monoid.<>)
                       (Data.ProtoLens.Encoding.Bytes.putVarInt 58)
                       ((Prelude..)
                          (\ bs
                             -> (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                     (Prelude.fromIntegral (Data.ByteString.length bs)))
                                  (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                          Data.ProtoLens.encodeMessage v)
                (Prelude.Just (Tool'AttachmentSearch v))
                  -> (Data.Monoid.<>)
                       (Data.ProtoLens.Encoding.Bytes.putVarInt 66)
                       ((Prelude..)
                          (\ bs
                             -> (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                     (Prelude.fromIntegral (Data.ByteString.length bs)))
                                  (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                          Data.ProtoLens.encodeMessage v))
             (Data.ProtoLens.Encoding.Wire.buildFieldSet
                (Lens.Family2.view Data.ProtoLens.unknownFields _x))
instance Control.DeepSeq.NFData Tool where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_Tool'_unknownFields x__)
             (Control.DeepSeq.deepseq (_Tool'tool x__) ())
instance Control.DeepSeq.NFData Tool'Tool where
  rnf (Tool'Function x__) = Control.DeepSeq.rnf x__
  rnf (Tool'WebSearch x__) = Control.DeepSeq.rnf x__
  rnf (Tool'XSearch x__) = Control.DeepSeq.rnf x__
  rnf (Tool'CodeExecution x__) = Control.DeepSeq.rnf x__
  rnf (Tool'CollectionsSearch x__) = Control.DeepSeq.rnf x__
  rnf (Tool'Mcp x__) = Control.DeepSeq.rnf x__
  rnf (Tool'AttachmentSearch x__) = Control.DeepSeq.rnf x__
_Tool'Function :: Data.ProtoLens.Prism.Prism' Tool'Tool Function
_Tool'Function
  = Data.ProtoLens.Prism.prism'
      Tool'Function
      (\ p__
         -> case p__ of
              (Tool'Function p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
_Tool'WebSearch :: Data.ProtoLens.Prism.Prism' Tool'Tool WebSearch
_Tool'WebSearch
  = Data.ProtoLens.Prism.prism'
      Tool'WebSearch
      (\ p__
         -> case p__ of
              (Tool'WebSearch p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
_Tool'XSearch :: Data.ProtoLens.Prism.Prism' Tool'Tool XSearch
_Tool'XSearch
  = Data.ProtoLens.Prism.prism'
      Tool'XSearch
      (\ p__
         -> case p__ of
              (Tool'XSearch p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
_Tool'CodeExecution ::
  Data.ProtoLens.Prism.Prism' Tool'Tool CodeExecution
_Tool'CodeExecution
  = Data.ProtoLens.Prism.prism'
      Tool'CodeExecution
      (\ p__
         -> case p__ of
              (Tool'CodeExecution p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
_Tool'CollectionsSearch ::
  Data.ProtoLens.Prism.Prism' Tool'Tool CollectionsSearch
_Tool'CollectionsSearch
  = Data.ProtoLens.Prism.prism'
      Tool'CollectionsSearch
      (\ p__
         -> case p__ of
              (Tool'CollectionsSearch p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
_Tool'Mcp :: Data.ProtoLens.Prism.Prism' Tool'Tool MCP
_Tool'Mcp
  = Data.ProtoLens.Prism.prism'
      Tool'Mcp
      (\ p__
         -> case p__ of
              (Tool'Mcp p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
_Tool'AttachmentSearch ::
  Data.ProtoLens.Prism.Prism' Tool'Tool AttachmentSearch
_Tool'AttachmentSearch
  = Data.ProtoLens.Prism.prism'
      Tool'AttachmentSearch
      (\ p__
         -> case p__ of
              (Tool'AttachmentSearch p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Chat_Fields.id' @:: Lens' ToolCall Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.type'' @:: Lens' ToolCall ToolCallType@
         * 'Proto.Xai.Api.V1.Chat_Fields.status' @:: Lens' ToolCall ToolCallStatus@
         * 'Proto.Xai.Api.V1.Chat_Fields.errorMessage' @:: Lens' ToolCall Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'errorMessage' @:: Lens' ToolCall (Prelude.Maybe Data.Text.Text)@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'tool' @:: Lens' ToolCall (Prelude.Maybe ToolCall'Tool)@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'function' @:: Lens' ToolCall (Prelude.Maybe FunctionCall)@
         * 'Proto.Xai.Api.V1.Chat_Fields.function' @:: Lens' ToolCall FunctionCall@ -}
data ToolCall
  = ToolCall'_constructor {_ToolCall'id :: !Data.Text.Text,
                           _ToolCall'type' :: !ToolCallType,
                           _ToolCall'status :: !ToolCallStatus,
                           _ToolCall'errorMessage :: !(Prelude.Maybe Data.Text.Text),
                           _ToolCall'tool :: !(Prelude.Maybe ToolCall'Tool),
                           _ToolCall'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show ToolCall where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
data ToolCall'Tool
  = ToolCall'Function !FunctionCall
  deriving stock (Prelude.Show, Prelude.Eq, Prelude.Ord)
instance Data.ProtoLens.Field.HasField ToolCall "id" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ToolCall'id (\ x__ y__ -> x__ {_ToolCall'id = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField ToolCall "type'" ToolCallType where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ToolCall'type' (\ x__ y__ -> x__ {_ToolCall'type' = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField ToolCall "status" ToolCallStatus where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ToolCall'status (\ x__ y__ -> x__ {_ToolCall'status = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField ToolCall "errorMessage" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ToolCall'errorMessage
           (\ x__ y__ -> x__ {_ToolCall'errorMessage = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField ToolCall "maybe'errorMessage" (Prelude.Maybe Data.Text.Text) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ToolCall'errorMessage
           (\ x__ y__ -> x__ {_ToolCall'errorMessage = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField ToolCall "maybe'tool" (Prelude.Maybe ToolCall'Tool) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ToolCall'tool (\ x__ y__ -> x__ {_ToolCall'tool = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField ToolCall "maybe'function" (Prelude.Maybe FunctionCall) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ToolCall'tool (\ x__ y__ -> x__ {_ToolCall'tool = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (ToolCall'Function x__val)) -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap ToolCall'Function y__))
instance Data.ProtoLens.Field.HasField ToolCall "function" FunctionCall where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ToolCall'tool (\ x__ y__ -> x__ {_ToolCall'tool = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (ToolCall'Function x__val)) -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap ToolCall'Function y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Message ToolCall where
  messageName _ = Data.Text.pack "xai_api.ToolCall"
  packedMessageDescriptor _
    = "\n\
      \\bToolCall\DC2\SO\n\
      \\STXid\CAN\SOH \SOH(\tR\STXid\DC2)\n\
      \\EOTtype\CAN\STX \SOH(\SO2\NAK.xai_api.ToolCallTypeR\EOTtype\DC2/\n\
      \\ACKstatus\CAN\ETX \SOH(\SO2\ETB.xai_api.ToolCallStatusR\ACKstatus\DC2(\n\
      \\rerror_message\CAN\EOT \SOH(\tH\SOHR\ferrorMessage\136\SOH\SOH\DC23\n\
      \\bfunction\CAN\n\
      \ \SOH(\v2\NAK.xai_api.FunctionCallH\NULR\bfunctionB\ACK\n\
      \\EOTtoolB\DLE\n\
      \\SO_error_message"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        id__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "id"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"id")) ::
              Data.ProtoLens.FieldDescriptor ToolCall
        type'__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "type"
              (Data.ProtoLens.ScalarField Data.ProtoLens.EnumField ::
                 Data.ProtoLens.FieldTypeDescriptor ToolCallType)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"type'")) ::
              Data.ProtoLens.FieldDescriptor ToolCall
        status__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "status"
              (Data.ProtoLens.ScalarField Data.ProtoLens.EnumField ::
                 Data.ProtoLens.FieldTypeDescriptor ToolCallStatus)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"status")) ::
              Data.ProtoLens.FieldDescriptor ToolCall
        errorMessage__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "error_message"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'errorMessage")) ::
              Data.ProtoLens.FieldDescriptor ToolCall
        function__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "function"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor FunctionCall)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'function")) ::
              Data.ProtoLens.FieldDescriptor ToolCall
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, id__field_descriptor),
           (Data.ProtoLens.Tag 2, type'__field_descriptor),
           (Data.ProtoLens.Tag 3, status__field_descriptor),
           (Data.ProtoLens.Tag 4, errorMessage__field_descriptor),
           (Data.ProtoLens.Tag 10, function__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _ToolCall'_unknownFields
        (\ x__ y__ -> x__ {_ToolCall'_unknownFields = y__})
  defMessage
    = ToolCall'_constructor
        {_ToolCall'id = Data.ProtoLens.fieldDefault,
         _ToolCall'type' = Data.ProtoLens.fieldDefault,
         _ToolCall'status = Data.ProtoLens.fieldDefault,
         _ToolCall'errorMessage = Prelude.Nothing,
         _ToolCall'tool = Prelude.Nothing, _ToolCall'_unknownFields = []}
  parseMessage
    = let
        loop :: ToolCall -> Data.ProtoLens.Encoding.Bytes.Parser ToolCall
        loop x
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t) x)
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "id"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"id") y x)
                        16
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.toEnum
                                          (Prelude.fmap
                                             Prelude.fromIntegral
                                             Data.ProtoLens.Encoding.Bytes.getVarInt))
                                       "type"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"type'") y x)
                        24
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.toEnum
                                          (Prelude.fmap
                                             Prelude.fromIntegral
                                             Data.ProtoLens.Encoding.Bytes.getVarInt))
                                       "status"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"status") y x)
                        34
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "error_message"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"errorMessage") y x)
                        82
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "function"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"function") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "ToolCall"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let _v = Lens.Family2.view (Data.ProtoLens.Field.field @"id") _x
              in
                if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                      ((Prelude..)
                         (\ bs
                            -> (Data.Monoid.<>)
                                 (Data.ProtoLens.Encoding.Bytes.putVarInt
                                    (Prelude.fromIntegral (Data.ByteString.length bs)))
                                 (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                         Data.Text.Encoding.encodeUtf8 _v))
             ((Data.Monoid.<>)
                (let
                   _v = Lens.Family2.view (Data.ProtoLens.Field.field @"type'") _x
                 in
                   if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                       Data.Monoid.mempty
                   else
                       (Data.Monoid.<>)
                         (Data.ProtoLens.Encoding.Bytes.putVarInt 16)
                         ((Prelude..)
                            ((Prelude..)
                               Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral)
                            Prelude.fromEnum _v))
                ((Data.Monoid.<>)
                   (let
                      _v = Lens.Family2.view (Data.ProtoLens.Field.field @"status") _x
                    in
                      if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                          Data.Monoid.mempty
                      else
                          (Data.Monoid.<>)
                            (Data.ProtoLens.Encoding.Bytes.putVarInt 24)
                            ((Prelude..)
                               ((Prelude..)
                                  Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral)
                               Prelude.fromEnum _v))
                   ((Data.Monoid.<>)
                      (case
                           Lens.Family2.view
                             (Data.ProtoLens.Field.field @"maybe'errorMessage") _x
                       of
                         Prelude.Nothing -> Data.Monoid.mempty
                         (Prelude.Just _v)
                           -> (Data.Monoid.<>)
                                (Data.ProtoLens.Encoding.Bytes.putVarInt 34)
                                ((Prelude..)
                                   (\ bs
                                      -> (Data.Monoid.<>)
                                           (Data.ProtoLens.Encoding.Bytes.putVarInt
                                              (Prelude.fromIntegral (Data.ByteString.length bs)))
                                           (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                   Data.Text.Encoding.encodeUtf8 _v))
                      ((Data.Monoid.<>)
                         (case
                              Lens.Family2.view (Data.ProtoLens.Field.field @"maybe'tool") _x
                          of
                            Prelude.Nothing -> Data.Monoid.mempty
                            (Prelude.Just (ToolCall'Function v))
                              -> (Data.Monoid.<>)
                                   (Data.ProtoLens.Encoding.Bytes.putVarInt 82)
                                   ((Prelude..)
                                      (\ bs
                                         -> (Data.Monoid.<>)
                                              (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                 (Prelude.fromIntegral (Data.ByteString.length bs)))
                                              (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                      Data.ProtoLens.encodeMessage v))
                         (Data.ProtoLens.Encoding.Wire.buildFieldSet
                            (Lens.Family2.view Data.ProtoLens.unknownFields _x))))))
instance Control.DeepSeq.NFData ToolCall where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_ToolCall'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_ToolCall'id x__)
                (Control.DeepSeq.deepseq
                   (_ToolCall'type' x__)
                   (Control.DeepSeq.deepseq
                      (_ToolCall'status x__)
                      (Control.DeepSeq.deepseq
                         (_ToolCall'errorMessage x__)
                         (Control.DeepSeq.deepseq (_ToolCall'tool x__) ())))))
instance Control.DeepSeq.NFData ToolCall'Tool where
  rnf (ToolCall'Function x__) = Control.DeepSeq.rnf x__
_ToolCall'Function ::
  Data.ProtoLens.Prism.Prism' ToolCall'Tool FunctionCall
_ToolCall'Function
  = Data.ProtoLens.Prism.prism'
      ToolCall'Function
      (\ p__
         -> case p__ of (ToolCall'Function p__val) -> Prelude.Just p__val)
newtype ToolCallStatus'UnrecognizedValue
  = ToolCallStatus'UnrecognizedValue Data.Int.Int32
  deriving stock (Prelude.Eq, Prelude.Ord, Prelude.Show)
data ToolCallStatus
  = TOOL_CALL_STATUS_IN_PROGRESS |
    TOOL_CALL_STATUS_COMPLETED |
    TOOL_CALL_STATUS_INCOMPLETE |
    TOOL_CALL_STATUS_FAILED |
    ToolCallStatus'Unrecognized !ToolCallStatus'UnrecognizedValue
  deriving stock (Prelude.Show, Prelude.Eq, Prelude.Ord)
instance Data.ProtoLens.MessageEnum ToolCallStatus where
  maybeToEnum 0 = Prelude.Just TOOL_CALL_STATUS_IN_PROGRESS
  maybeToEnum 1 = Prelude.Just TOOL_CALL_STATUS_COMPLETED
  maybeToEnum 2 = Prelude.Just TOOL_CALL_STATUS_INCOMPLETE
  maybeToEnum 3 = Prelude.Just TOOL_CALL_STATUS_FAILED
  maybeToEnum k
    = Prelude.Just
        (ToolCallStatus'Unrecognized
           (ToolCallStatus'UnrecognizedValue (Prelude.fromIntegral k)))
  showEnum TOOL_CALL_STATUS_IN_PROGRESS
    = "TOOL_CALL_STATUS_IN_PROGRESS"
  showEnum TOOL_CALL_STATUS_COMPLETED = "TOOL_CALL_STATUS_COMPLETED"
  showEnum TOOL_CALL_STATUS_INCOMPLETE
    = "TOOL_CALL_STATUS_INCOMPLETE"
  showEnum TOOL_CALL_STATUS_FAILED = "TOOL_CALL_STATUS_FAILED"
  showEnum
    (ToolCallStatus'Unrecognized (ToolCallStatus'UnrecognizedValue k))
    = Prelude.show k
  readEnum k
    | (Prelude.==) k "TOOL_CALL_STATUS_IN_PROGRESS"
    = Prelude.Just TOOL_CALL_STATUS_IN_PROGRESS
    | (Prelude.==) k "TOOL_CALL_STATUS_COMPLETED"
    = Prelude.Just TOOL_CALL_STATUS_COMPLETED
    | (Prelude.==) k "TOOL_CALL_STATUS_INCOMPLETE"
    = Prelude.Just TOOL_CALL_STATUS_INCOMPLETE
    | (Prelude.==) k "TOOL_CALL_STATUS_FAILED"
    = Prelude.Just TOOL_CALL_STATUS_FAILED
    | Prelude.otherwise
    = (Prelude.>>=) (Text.Read.readMaybe k) Data.ProtoLens.maybeToEnum
instance Prelude.Bounded ToolCallStatus where
  minBound = TOOL_CALL_STATUS_IN_PROGRESS
  maxBound = TOOL_CALL_STATUS_FAILED
instance Prelude.Enum ToolCallStatus where
  toEnum k__
    = Prelude.maybe
        (Prelude.error
           ((Prelude.++)
              "toEnum: unknown value for enum ToolCallStatus: "
              (Prelude.show k__)))
        Prelude.id (Data.ProtoLens.maybeToEnum k__)
  fromEnum TOOL_CALL_STATUS_IN_PROGRESS = 0
  fromEnum TOOL_CALL_STATUS_COMPLETED = 1
  fromEnum TOOL_CALL_STATUS_INCOMPLETE = 2
  fromEnum TOOL_CALL_STATUS_FAILED = 3
  fromEnum
    (ToolCallStatus'Unrecognized (ToolCallStatus'UnrecognizedValue k))
    = Prelude.fromIntegral k
  succ TOOL_CALL_STATUS_FAILED
    = Prelude.error
        "ToolCallStatus.succ: bad argument TOOL_CALL_STATUS_FAILED. This value would be out of bounds."
  succ TOOL_CALL_STATUS_IN_PROGRESS = TOOL_CALL_STATUS_COMPLETED
  succ TOOL_CALL_STATUS_COMPLETED = TOOL_CALL_STATUS_INCOMPLETE
  succ TOOL_CALL_STATUS_INCOMPLETE = TOOL_CALL_STATUS_FAILED
  succ (ToolCallStatus'Unrecognized _)
    = Prelude.error
        "ToolCallStatus.succ: bad argument: unrecognized value"
  pred TOOL_CALL_STATUS_IN_PROGRESS
    = Prelude.error
        "ToolCallStatus.pred: bad argument TOOL_CALL_STATUS_IN_PROGRESS. This value would be out of bounds."
  pred TOOL_CALL_STATUS_COMPLETED = TOOL_CALL_STATUS_IN_PROGRESS
  pred TOOL_CALL_STATUS_INCOMPLETE = TOOL_CALL_STATUS_COMPLETED
  pred TOOL_CALL_STATUS_FAILED = TOOL_CALL_STATUS_INCOMPLETE
  pred (ToolCallStatus'Unrecognized _)
    = Prelude.error
        "ToolCallStatus.pred: bad argument: unrecognized value"
  enumFrom = Data.ProtoLens.Message.Enum.messageEnumFrom
  enumFromTo = Data.ProtoLens.Message.Enum.messageEnumFromTo
  enumFromThen = Data.ProtoLens.Message.Enum.messageEnumFromThen
  enumFromThenTo = Data.ProtoLens.Message.Enum.messageEnumFromThenTo
instance Data.ProtoLens.FieldDefault ToolCallStatus where
  fieldDefault = TOOL_CALL_STATUS_IN_PROGRESS
instance Control.DeepSeq.NFData ToolCallStatus where
  rnf x__ = Prelude.seq x__ ()
newtype ToolCallType'UnrecognizedValue
  = ToolCallType'UnrecognizedValue Data.Int.Int32
  deriving stock (Prelude.Eq, Prelude.Ord, Prelude.Show)
data ToolCallType
  = TOOL_CALL_TYPE_INVALID |
    TOOL_CALL_TYPE_CLIENT_SIDE_TOOL |
    TOOL_CALL_TYPE_WEB_SEARCH_TOOL |
    TOOL_CALL_TYPE_X_SEARCH_TOOL |
    TOOL_CALL_TYPE_CODE_EXECUTION_TOOL |
    TOOL_CALL_TYPE_COLLECTIONS_SEARCH_TOOL |
    TOOL_CALL_TYPE_MCP_TOOL |
    TOOL_CALL_TYPE_ATTACHMENT_SEARCH_TOOL |
    ToolCallType'Unrecognized !ToolCallType'UnrecognizedValue
  deriving stock (Prelude.Show, Prelude.Eq, Prelude.Ord)
instance Data.ProtoLens.MessageEnum ToolCallType where
  maybeToEnum 0 = Prelude.Just TOOL_CALL_TYPE_INVALID
  maybeToEnum 1 = Prelude.Just TOOL_CALL_TYPE_CLIENT_SIDE_TOOL
  maybeToEnum 2 = Prelude.Just TOOL_CALL_TYPE_WEB_SEARCH_TOOL
  maybeToEnum 3 = Prelude.Just TOOL_CALL_TYPE_X_SEARCH_TOOL
  maybeToEnum 4 = Prelude.Just TOOL_CALL_TYPE_CODE_EXECUTION_TOOL
  maybeToEnum 5 = Prelude.Just TOOL_CALL_TYPE_COLLECTIONS_SEARCH_TOOL
  maybeToEnum 6 = Prelude.Just TOOL_CALL_TYPE_MCP_TOOL
  maybeToEnum 7 = Prelude.Just TOOL_CALL_TYPE_ATTACHMENT_SEARCH_TOOL
  maybeToEnum k
    = Prelude.Just
        (ToolCallType'Unrecognized
           (ToolCallType'UnrecognizedValue (Prelude.fromIntegral k)))
  showEnum TOOL_CALL_TYPE_INVALID = "TOOL_CALL_TYPE_INVALID"
  showEnum TOOL_CALL_TYPE_CLIENT_SIDE_TOOL
    = "TOOL_CALL_TYPE_CLIENT_SIDE_TOOL"
  showEnum TOOL_CALL_TYPE_WEB_SEARCH_TOOL
    = "TOOL_CALL_TYPE_WEB_SEARCH_TOOL"
  showEnum TOOL_CALL_TYPE_X_SEARCH_TOOL
    = "TOOL_CALL_TYPE_X_SEARCH_TOOL"
  showEnum TOOL_CALL_TYPE_CODE_EXECUTION_TOOL
    = "TOOL_CALL_TYPE_CODE_EXECUTION_TOOL"
  showEnum TOOL_CALL_TYPE_COLLECTIONS_SEARCH_TOOL
    = "TOOL_CALL_TYPE_COLLECTIONS_SEARCH_TOOL"
  showEnum TOOL_CALL_TYPE_MCP_TOOL = "TOOL_CALL_TYPE_MCP_TOOL"
  showEnum TOOL_CALL_TYPE_ATTACHMENT_SEARCH_TOOL
    = "TOOL_CALL_TYPE_ATTACHMENT_SEARCH_TOOL"
  showEnum
    (ToolCallType'Unrecognized (ToolCallType'UnrecognizedValue k))
    = Prelude.show k
  readEnum k
    | (Prelude.==) k "TOOL_CALL_TYPE_INVALID"
    = Prelude.Just TOOL_CALL_TYPE_INVALID
    | (Prelude.==) k "TOOL_CALL_TYPE_CLIENT_SIDE_TOOL"
    = Prelude.Just TOOL_CALL_TYPE_CLIENT_SIDE_TOOL
    | (Prelude.==) k "TOOL_CALL_TYPE_WEB_SEARCH_TOOL"
    = Prelude.Just TOOL_CALL_TYPE_WEB_SEARCH_TOOL
    | (Prelude.==) k "TOOL_CALL_TYPE_X_SEARCH_TOOL"
    = Prelude.Just TOOL_CALL_TYPE_X_SEARCH_TOOL
    | (Prelude.==) k "TOOL_CALL_TYPE_CODE_EXECUTION_TOOL"
    = Prelude.Just TOOL_CALL_TYPE_CODE_EXECUTION_TOOL
    | (Prelude.==) k "TOOL_CALL_TYPE_COLLECTIONS_SEARCH_TOOL"
    = Prelude.Just TOOL_CALL_TYPE_COLLECTIONS_SEARCH_TOOL
    | (Prelude.==) k "TOOL_CALL_TYPE_MCP_TOOL"
    = Prelude.Just TOOL_CALL_TYPE_MCP_TOOL
    | (Prelude.==) k "TOOL_CALL_TYPE_ATTACHMENT_SEARCH_TOOL"
    = Prelude.Just TOOL_CALL_TYPE_ATTACHMENT_SEARCH_TOOL
    | Prelude.otherwise
    = (Prelude.>>=) (Text.Read.readMaybe k) Data.ProtoLens.maybeToEnum
instance Prelude.Bounded ToolCallType where
  minBound = TOOL_CALL_TYPE_INVALID
  maxBound = TOOL_CALL_TYPE_ATTACHMENT_SEARCH_TOOL
instance Prelude.Enum ToolCallType where
  toEnum k__
    = Prelude.maybe
        (Prelude.error
           ((Prelude.++)
              "toEnum: unknown value for enum ToolCallType: "
              (Prelude.show k__)))
        Prelude.id (Data.ProtoLens.maybeToEnum k__)
  fromEnum TOOL_CALL_TYPE_INVALID = 0
  fromEnum TOOL_CALL_TYPE_CLIENT_SIDE_TOOL = 1
  fromEnum TOOL_CALL_TYPE_WEB_SEARCH_TOOL = 2
  fromEnum TOOL_CALL_TYPE_X_SEARCH_TOOL = 3
  fromEnum TOOL_CALL_TYPE_CODE_EXECUTION_TOOL = 4
  fromEnum TOOL_CALL_TYPE_COLLECTIONS_SEARCH_TOOL = 5
  fromEnum TOOL_CALL_TYPE_MCP_TOOL = 6
  fromEnum TOOL_CALL_TYPE_ATTACHMENT_SEARCH_TOOL = 7
  fromEnum
    (ToolCallType'Unrecognized (ToolCallType'UnrecognizedValue k))
    = Prelude.fromIntegral k
  succ TOOL_CALL_TYPE_ATTACHMENT_SEARCH_TOOL
    = Prelude.error
        "ToolCallType.succ: bad argument TOOL_CALL_TYPE_ATTACHMENT_SEARCH_TOOL. This value would be out of bounds."
  succ TOOL_CALL_TYPE_INVALID = TOOL_CALL_TYPE_CLIENT_SIDE_TOOL
  succ TOOL_CALL_TYPE_CLIENT_SIDE_TOOL
    = TOOL_CALL_TYPE_WEB_SEARCH_TOOL
  succ TOOL_CALL_TYPE_WEB_SEARCH_TOOL = TOOL_CALL_TYPE_X_SEARCH_TOOL
  succ TOOL_CALL_TYPE_X_SEARCH_TOOL
    = TOOL_CALL_TYPE_CODE_EXECUTION_TOOL
  succ TOOL_CALL_TYPE_CODE_EXECUTION_TOOL
    = TOOL_CALL_TYPE_COLLECTIONS_SEARCH_TOOL
  succ TOOL_CALL_TYPE_COLLECTIONS_SEARCH_TOOL
    = TOOL_CALL_TYPE_MCP_TOOL
  succ TOOL_CALL_TYPE_MCP_TOOL
    = TOOL_CALL_TYPE_ATTACHMENT_SEARCH_TOOL
  succ (ToolCallType'Unrecognized _)
    = Prelude.error
        "ToolCallType.succ: bad argument: unrecognized value"
  pred TOOL_CALL_TYPE_INVALID
    = Prelude.error
        "ToolCallType.pred: bad argument TOOL_CALL_TYPE_INVALID. This value would be out of bounds."
  pred TOOL_CALL_TYPE_CLIENT_SIDE_TOOL = TOOL_CALL_TYPE_INVALID
  pred TOOL_CALL_TYPE_WEB_SEARCH_TOOL
    = TOOL_CALL_TYPE_CLIENT_SIDE_TOOL
  pred TOOL_CALL_TYPE_X_SEARCH_TOOL = TOOL_CALL_TYPE_WEB_SEARCH_TOOL
  pred TOOL_CALL_TYPE_CODE_EXECUTION_TOOL
    = TOOL_CALL_TYPE_X_SEARCH_TOOL
  pred TOOL_CALL_TYPE_COLLECTIONS_SEARCH_TOOL
    = TOOL_CALL_TYPE_CODE_EXECUTION_TOOL
  pred TOOL_CALL_TYPE_MCP_TOOL
    = TOOL_CALL_TYPE_COLLECTIONS_SEARCH_TOOL
  pred TOOL_CALL_TYPE_ATTACHMENT_SEARCH_TOOL
    = TOOL_CALL_TYPE_MCP_TOOL
  pred (ToolCallType'Unrecognized _)
    = Prelude.error
        "ToolCallType.pred: bad argument: unrecognized value"
  enumFrom = Data.ProtoLens.Message.Enum.messageEnumFrom
  enumFromTo = Data.ProtoLens.Message.Enum.messageEnumFromTo
  enumFromThen = Data.ProtoLens.Message.Enum.messageEnumFromThen
  enumFromThenTo = Data.ProtoLens.Message.Enum.messageEnumFromThenTo
instance Data.ProtoLens.FieldDefault ToolCallType where
  fieldDefault = TOOL_CALL_TYPE_INVALID
instance Control.DeepSeq.NFData ToolCallType where
  rnf x__ = Prelude.seq x__ ()
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'toolChoice' @:: Lens' ToolChoice (Prelude.Maybe ToolChoice'ToolChoice)@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'mode' @:: Lens' ToolChoice (Prelude.Maybe ToolMode)@
         * 'Proto.Xai.Api.V1.Chat_Fields.mode' @:: Lens' ToolChoice ToolMode@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'functionName' @:: Lens' ToolChoice (Prelude.Maybe Data.Text.Text)@
         * 'Proto.Xai.Api.V1.Chat_Fields.functionName' @:: Lens' ToolChoice Data.Text.Text@ -}
data ToolChoice
  = ToolChoice'_constructor {_ToolChoice'toolChoice :: !(Prelude.Maybe ToolChoice'ToolChoice),
                             _ToolChoice'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show ToolChoice where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
data ToolChoice'ToolChoice
  = ToolChoice'Mode !ToolMode |
    ToolChoice'FunctionName !Data.Text.Text
  deriving stock (Prelude.Show, Prelude.Eq, Prelude.Ord)
instance Data.ProtoLens.Field.HasField ToolChoice "maybe'toolChoice" (Prelude.Maybe ToolChoice'ToolChoice) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ToolChoice'toolChoice
           (\ x__ y__ -> x__ {_ToolChoice'toolChoice = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField ToolChoice "maybe'mode" (Prelude.Maybe ToolMode) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ToolChoice'toolChoice
           (\ x__ y__ -> x__ {_ToolChoice'toolChoice = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (ToolChoice'Mode x__val)) -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap ToolChoice'Mode y__))
instance Data.ProtoLens.Field.HasField ToolChoice "mode" ToolMode where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ToolChoice'toolChoice
           (\ x__ y__ -> x__ {_ToolChoice'toolChoice = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (ToolChoice'Mode x__val)) -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap ToolChoice'Mode y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault))
instance Data.ProtoLens.Field.HasField ToolChoice "maybe'functionName" (Prelude.Maybe Data.Text.Text) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ToolChoice'toolChoice
           (\ x__ y__ -> x__ {_ToolChoice'toolChoice = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (ToolChoice'FunctionName x__val))
                     -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap ToolChoice'FunctionName y__))
instance Data.ProtoLens.Field.HasField ToolChoice "functionName" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ToolChoice'toolChoice
           (\ x__ y__ -> x__ {_ToolChoice'toolChoice = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (ToolChoice'FunctionName x__val))
                        -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap ToolChoice'FunctionName y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault))
instance Data.ProtoLens.Message ToolChoice where
  messageName _ = Data.Text.pack "xai_api.ToolChoice"
  packedMessageDescriptor _
    = "\n\
      \\n\
      \ToolChoice\DC2'\n\
      \\EOTmode\CAN\SOH \SOH(\SO2\DC1.xai_api.ToolModeH\NULR\EOTmode\DC2%\n\
      \\rfunction_name\CAN\STX \SOH(\tH\NULR\ffunctionNameB\r\n\
      \\vtool_choice"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        mode__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "mode"
              (Data.ProtoLens.ScalarField Data.ProtoLens.EnumField ::
                 Data.ProtoLens.FieldTypeDescriptor ToolMode)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'mode")) ::
              Data.ProtoLens.FieldDescriptor ToolChoice
        functionName__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "function_name"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'functionName")) ::
              Data.ProtoLens.FieldDescriptor ToolChoice
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, mode__field_descriptor),
           (Data.ProtoLens.Tag 2, functionName__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _ToolChoice'_unknownFields
        (\ x__ y__ -> x__ {_ToolChoice'_unknownFields = y__})
  defMessage
    = ToolChoice'_constructor
        {_ToolChoice'toolChoice = Prelude.Nothing,
         _ToolChoice'_unknownFields = []}
  parseMessage
    = let
        loop ::
          ToolChoice -> Data.ProtoLens.Encoding.Bytes.Parser ToolChoice
        loop x
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t) x)
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        8 -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.toEnum
                                          (Prelude.fmap
                                             Prelude.fromIntegral
                                             Data.ProtoLens.Encoding.Bytes.getVarInt))
                                       "mode"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"mode") y x)
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "function_name"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"functionName") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "ToolChoice"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (case
                  Lens.Family2.view
                    (Data.ProtoLens.Field.field @"maybe'toolChoice") _x
              of
                Prelude.Nothing -> Data.Monoid.mempty
                (Prelude.Just (ToolChoice'Mode v))
                  -> (Data.Monoid.<>)
                       (Data.ProtoLens.Encoding.Bytes.putVarInt 8)
                       ((Prelude..)
                          ((Prelude..)
                             Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral)
                          Prelude.fromEnum v)
                (Prelude.Just (ToolChoice'FunctionName v))
                  -> (Data.Monoid.<>)
                       (Data.ProtoLens.Encoding.Bytes.putVarInt 18)
                       ((Prelude..)
                          (\ bs
                             -> (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                     (Prelude.fromIntegral (Data.ByteString.length bs)))
                                  (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                          Data.Text.Encoding.encodeUtf8 v))
             (Data.ProtoLens.Encoding.Wire.buildFieldSet
                (Lens.Family2.view Data.ProtoLens.unknownFields _x))
instance Control.DeepSeq.NFData ToolChoice where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_ToolChoice'_unknownFields x__)
             (Control.DeepSeq.deepseq (_ToolChoice'toolChoice x__) ())
instance Control.DeepSeq.NFData ToolChoice'ToolChoice where
  rnf (ToolChoice'Mode x__) = Control.DeepSeq.rnf x__
  rnf (ToolChoice'FunctionName x__) = Control.DeepSeq.rnf x__
_ToolChoice'Mode ::
  Data.ProtoLens.Prism.Prism' ToolChoice'ToolChoice ToolMode
_ToolChoice'Mode
  = Data.ProtoLens.Prism.prism'
      ToolChoice'Mode
      (\ p__
         -> case p__ of
              (ToolChoice'Mode p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
_ToolChoice'FunctionName ::
  Data.ProtoLens.Prism.Prism' ToolChoice'ToolChoice Data.Text.Text
_ToolChoice'FunctionName
  = Data.ProtoLens.Prism.prism'
      ToolChoice'FunctionName
      (\ p__
         -> case p__ of
              (ToolChoice'FunctionName p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
newtype ToolMode'UnrecognizedValue
  = ToolMode'UnrecognizedValue Data.Int.Int32
  deriving stock (Prelude.Eq, Prelude.Ord, Prelude.Show)
data ToolMode
  = TOOL_MODE_INVALID |
    TOOL_MODE_AUTO |
    TOOL_MODE_NONE |
    TOOL_MODE_REQUIRED |
    ToolMode'Unrecognized !ToolMode'UnrecognizedValue
  deriving stock (Prelude.Show, Prelude.Eq, Prelude.Ord)
instance Data.ProtoLens.MessageEnum ToolMode where
  maybeToEnum 0 = Prelude.Just TOOL_MODE_INVALID
  maybeToEnum 1 = Prelude.Just TOOL_MODE_AUTO
  maybeToEnum 2 = Prelude.Just TOOL_MODE_NONE
  maybeToEnum 3 = Prelude.Just TOOL_MODE_REQUIRED
  maybeToEnum k
    = Prelude.Just
        (ToolMode'Unrecognized
           (ToolMode'UnrecognizedValue (Prelude.fromIntegral k)))
  showEnum TOOL_MODE_INVALID = "TOOL_MODE_INVALID"
  showEnum TOOL_MODE_AUTO = "TOOL_MODE_AUTO"
  showEnum TOOL_MODE_NONE = "TOOL_MODE_NONE"
  showEnum TOOL_MODE_REQUIRED = "TOOL_MODE_REQUIRED"
  showEnum (ToolMode'Unrecognized (ToolMode'UnrecognizedValue k))
    = Prelude.show k
  readEnum k
    | (Prelude.==) k "TOOL_MODE_INVALID"
    = Prelude.Just TOOL_MODE_INVALID
    | (Prelude.==) k "TOOL_MODE_AUTO" = Prelude.Just TOOL_MODE_AUTO
    | (Prelude.==) k "TOOL_MODE_NONE" = Prelude.Just TOOL_MODE_NONE
    | (Prelude.==) k "TOOL_MODE_REQUIRED"
    = Prelude.Just TOOL_MODE_REQUIRED
    | Prelude.otherwise
    = (Prelude.>>=) (Text.Read.readMaybe k) Data.ProtoLens.maybeToEnum
instance Prelude.Bounded ToolMode where
  minBound = TOOL_MODE_INVALID
  maxBound = TOOL_MODE_REQUIRED
instance Prelude.Enum ToolMode where
  toEnum k__
    = Prelude.maybe
        (Prelude.error
           ((Prelude.++)
              "toEnum: unknown value for enum ToolMode: " (Prelude.show k__)))
        Prelude.id (Data.ProtoLens.maybeToEnum k__)
  fromEnum TOOL_MODE_INVALID = 0
  fromEnum TOOL_MODE_AUTO = 1
  fromEnum TOOL_MODE_NONE = 2
  fromEnum TOOL_MODE_REQUIRED = 3
  fromEnum (ToolMode'Unrecognized (ToolMode'UnrecognizedValue k))
    = Prelude.fromIntegral k
  succ TOOL_MODE_REQUIRED
    = Prelude.error
        "ToolMode.succ: bad argument TOOL_MODE_REQUIRED. This value would be out of bounds."
  succ TOOL_MODE_INVALID = TOOL_MODE_AUTO
  succ TOOL_MODE_AUTO = TOOL_MODE_NONE
  succ TOOL_MODE_NONE = TOOL_MODE_REQUIRED
  succ (ToolMode'Unrecognized _)
    = Prelude.error "ToolMode.succ: bad argument: unrecognized value"
  pred TOOL_MODE_INVALID
    = Prelude.error
        "ToolMode.pred: bad argument TOOL_MODE_INVALID. This value would be out of bounds."
  pred TOOL_MODE_AUTO = TOOL_MODE_INVALID
  pred TOOL_MODE_NONE = TOOL_MODE_AUTO
  pred TOOL_MODE_REQUIRED = TOOL_MODE_NONE
  pred (ToolMode'Unrecognized _)
    = Prelude.error "ToolMode.pred: bad argument: unrecognized value"
  enumFrom = Data.ProtoLens.Message.Enum.messageEnumFrom
  enumFromTo = Data.ProtoLens.Message.Enum.messageEnumFromTo
  enumFromThen = Data.ProtoLens.Message.Enum.messageEnumFromThen
  enumFromThenTo = Data.ProtoLens.Message.Enum.messageEnumFromThenTo
instance Data.ProtoLens.FieldDefault ToolMode where
  fieldDefault = TOOL_MODE_INVALID
instance Control.DeepSeq.NFData ToolMode where
  rnf x__ = Prelude.seq x__ ()
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Chat_Fields.token' @:: Lens' TopLogProb Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.logprob' @:: Lens' TopLogProb Prelude.Float@
         * 'Proto.Xai.Api.V1.Chat_Fields.bytes' @:: Lens' TopLogProb Data.ByteString.ByteString@ -}
data TopLogProb
  = TopLogProb'_constructor {_TopLogProb'token :: !Data.Text.Text,
                             _TopLogProb'logprob :: !Prelude.Float,
                             _TopLogProb'bytes :: !Data.ByteString.ByteString,
                             _TopLogProb'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show TopLogProb where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField TopLogProb "token" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _TopLogProb'token (\ x__ y__ -> x__ {_TopLogProb'token = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField TopLogProb "logprob" Prelude.Float where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _TopLogProb'logprob (\ x__ y__ -> x__ {_TopLogProb'logprob = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField TopLogProb "bytes" Data.ByteString.ByteString where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _TopLogProb'bytes (\ x__ y__ -> x__ {_TopLogProb'bytes = y__}))
        Prelude.id
instance Data.ProtoLens.Message TopLogProb where
  messageName _ = Data.Text.pack "xai_api.TopLogProb"
  packedMessageDescriptor _
    = "\n\
      \\n\
      \TopLogProb\DC2\DC4\n\
      \\ENQtoken\CAN\SOH \SOH(\tR\ENQtoken\DC2\CAN\n\
      \\alogprob\CAN\STX \SOH(\STXR\alogprob\DC2\DC4\n\
      \\ENQbytes\CAN\ETX \SOH(\fR\ENQbytes"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        token__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "token"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"token")) ::
              Data.ProtoLens.FieldDescriptor TopLogProb
        logprob__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "logprob"
              (Data.ProtoLens.ScalarField Data.ProtoLens.FloatField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Float)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"logprob")) ::
              Data.ProtoLens.FieldDescriptor TopLogProb
        bytes__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "bytes"
              (Data.ProtoLens.ScalarField Data.ProtoLens.BytesField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.ByteString.ByteString)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"bytes")) ::
              Data.ProtoLens.FieldDescriptor TopLogProb
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, token__field_descriptor),
           (Data.ProtoLens.Tag 2, logprob__field_descriptor),
           (Data.ProtoLens.Tag 3, bytes__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _TopLogProb'_unknownFields
        (\ x__ y__ -> x__ {_TopLogProb'_unknownFields = y__})
  defMessage
    = TopLogProb'_constructor
        {_TopLogProb'token = Data.ProtoLens.fieldDefault,
         _TopLogProb'logprob = Data.ProtoLens.fieldDefault,
         _TopLogProb'bytes = Data.ProtoLens.fieldDefault,
         _TopLogProb'_unknownFields = []}
  parseMessage
    = let
        loop ::
          TopLogProb -> Data.ProtoLens.Encoding.Bytes.Parser TopLogProb
        loop x
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t) x)
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "token"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"token") y x)
                        21
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Data.ProtoLens.Encoding.Bytes.wordToFloat
                                          Data.ProtoLens.Encoding.Bytes.getFixed32)
                                       "logprob"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"logprob") y x)
                        26
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getBytes
                                             (Prelude.fromIntegral len))
                                       "bytes"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"bytes") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "TopLogProb"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v = Lens.Family2.view (Data.ProtoLens.Field.field @"token") _x
              in
                if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                      ((Prelude..)
                         (\ bs
                            -> (Data.Monoid.<>)
                                 (Data.ProtoLens.Encoding.Bytes.putVarInt
                                    (Prelude.fromIntegral (Data.ByteString.length bs)))
                                 (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                         Data.Text.Encoding.encodeUtf8 _v))
             ((Data.Monoid.<>)
                (let
                   _v = Lens.Family2.view (Data.ProtoLens.Field.field @"logprob") _x
                 in
                   if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                       Data.Monoid.mempty
                   else
                       (Data.Monoid.<>)
                         (Data.ProtoLens.Encoding.Bytes.putVarInt 21)
                         ((Prelude..)
                            Data.ProtoLens.Encoding.Bytes.putFixed32
                            Data.ProtoLens.Encoding.Bytes.floatToWord _v))
                ((Data.Monoid.<>)
                   (let
                      _v = Lens.Family2.view (Data.ProtoLens.Field.field @"bytes") _x
                    in
                      if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                          Data.Monoid.mempty
                      else
                          (Data.Monoid.<>)
                            (Data.ProtoLens.Encoding.Bytes.putVarInt 26)
                            ((\ bs
                                -> (Data.Monoid.<>)
                                     (Data.ProtoLens.Encoding.Bytes.putVarInt
                                        (Prelude.fromIntegral (Data.ByteString.length bs)))
                                     (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                               _v))
                   (Data.ProtoLens.Encoding.Wire.buildFieldSet
                      (Lens.Family2.view Data.ProtoLens.unknownFields _x))))
instance Control.DeepSeq.NFData TopLogProb where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_TopLogProb'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_TopLogProb'token x__)
                (Control.DeepSeq.deepseq
                   (_TopLogProb'logprob x__)
                   (Control.DeepSeq.deepseq (_TopLogProb'bytes x__) ())))
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Chat_Fields.url' @:: Lens' WebCitation Data.Text.Text@ -}
data WebCitation
  = WebCitation'_constructor {_WebCitation'url :: !Data.Text.Text,
                              _WebCitation'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show WebCitation where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField WebCitation "url" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WebCitation'url (\ x__ y__ -> x__ {_WebCitation'url = y__}))
        Prelude.id
instance Data.ProtoLens.Message WebCitation where
  messageName _ = Data.Text.pack "xai_api.WebCitation"
  packedMessageDescriptor _
    = "\n\
      \\vWebCitation\DC2\DLE\n\
      \\ETXurl\CAN\SOH \SOH(\tR\ETXurl"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        url__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "url"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"url")) ::
              Data.ProtoLens.FieldDescriptor WebCitation
      in
        Data.Map.fromList [(Data.ProtoLens.Tag 1, url__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _WebCitation'_unknownFields
        (\ x__ y__ -> x__ {_WebCitation'_unknownFields = y__})
  defMessage
    = WebCitation'_constructor
        {_WebCitation'url = Data.ProtoLens.fieldDefault,
         _WebCitation'_unknownFields = []}
  parseMessage
    = let
        loop ::
          WebCitation -> Data.ProtoLens.Encoding.Bytes.Parser WebCitation
        loop x
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t) x)
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "url"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"url") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "WebCitation"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let _v = Lens.Family2.view (Data.ProtoLens.Field.field @"url") _x
              in
                if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                      ((Prelude..)
                         (\ bs
                            -> (Data.Monoid.<>)
                                 (Data.ProtoLens.Encoding.Bytes.putVarInt
                                    (Prelude.fromIntegral (Data.ByteString.length bs)))
                                 (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                         Data.Text.Encoding.encodeUtf8 _v))
             (Data.ProtoLens.Encoding.Wire.buildFieldSet
                (Lens.Family2.view Data.ProtoLens.unknownFields _x))
instance Control.DeepSeq.NFData WebCitation where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_WebCitation'_unknownFields x__)
             (Control.DeepSeq.deepseq (_WebCitation'url x__) ())
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Chat_Fields.excludedDomains' @:: Lens' WebSearch [Data.Text.Text]@
         * 'Proto.Xai.Api.V1.Chat_Fields.vec'excludedDomains' @:: Lens' WebSearch (Data.Vector.Vector Data.Text.Text)@
         * 'Proto.Xai.Api.V1.Chat_Fields.allowedDomains' @:: Lens' WebSearch [Data.Text.Text]@
         * 'Proto.Xai.Api.V1.Chat_Fields.vec'allowedDomains' @:: Lens' WebSearch (Data.Vector.Vector Data.Text.Text)@
         * 'Proto.Xai.Api.V1.Chat_Fields.enableImageUnderstanding' @:: Lens' WebSearch Prelude.Bool@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'enableImageUnderstanding' @:: Lens' WebSearch (Prelude.Maybe Prelude.Bool)@
         * 'Proto.Xai.Api.V1.Chat_Fields.userLocation' @:: Lens' WebSearch WebSearchUserLocation@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'userLocation' @:: Lens' WebSearch (Prelude.Maybe WebSearchUserLocation)@
         * 'Proto.Xai.Api.V1.Chat_Fields.enableImageSearch' @:: Lens' WebSearch Prelude.Bool@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'enableImageSearch' @:: Lens' WebSearch (Prelude.Maybe Prelude.Bool)@ -}
data WebSearch
  = WebSearch'_constructor {_WebSearch'excludedDomains :: !(Data.Vector.Vector Data.Text.Text),
                            _WebSearch'allowedDomains :: !(Data.Vector.Vector Data.Text.Text),
                            _WebSearch'enableImageUnderstanding :: !(Prelude.Maybe Prelude.Bool),
                            _WebSearch'userLocation :: !(Prelude.Maybe WebSearchUserLocation),
                            _WebSearch'enableImageSearch :: !(Prelude.Maybe Prelude.Bool),
                            _WebSearch'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show WebSearch where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField WebSearch "excludedDomains" [Data.Text.Text] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WebSearch'excludedDomains
           (\ x__ y__ -> x__ {_WebSearch'excludedDomains = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField WebSearch "vec'excludedDomains" (Data.Vector.Vector Data.Text.Text) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WebSearch'excludedDomains
           (\ x__ y__ -> x__ {_WebSearch'excludedDomains = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField WebSearch "allowedDomains" [Data.Text.Text] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WebSearch'allowedDomains
           (\ x__ y__ -> x__ {_WebSearch'allowedDomains = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField WebSearch "vec'allowedDomains" (Data.Vector.Vector Data.Text.Text) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WebSearch'allowedDomains
           (\ x__ y__ -> x__ {_WebSearch'allowedDomains = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField WebSearch "enableImageUnderstanding" Prelude.Bool where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WebSearch'enableImageUnderstanding
           (\ x__ y__ -> x__ {_WebSearch'enableImageUnderstanding = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField WebSearch "maybe'enableImageUnderstanding" (Prelude.Maybe Prelude.Bool) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WebSearch'enableImageUnderstanding
           (\ x__ y__ -> x__ {_WebSearch'enableImageUnderstanding = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField WebSearch "userLocation" WebSearchUserLocation where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WebSearch'userLocation
           (\ x__ y__ -> x__ {_WebSearch'userLocation = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage)
instance Data.ProtoLens.Field.HasField WebSearch "maybe'userLocation" (Prelude.Maybe WebSearchUserLocation) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WebSearch'userLocation
           (\ x__ y__ -> x__ {_WebSearch'userLocation = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField WebSearch "enableImageSearch" Prelude.Bool where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WebSearch'enableImageSearch
           (\ x__ y__ -> x__ {_WebSearch'enableImageSearch = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField WebSearch "maybe'enableImageSearch" (Prelude.Maybe Prelude.Bool) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WebSearch'enableImageSearch
           (\ x__ y__ -> x__ {_WebSearch'enableImageSearch = y__}))
        Prelude.id
instance Data.ProtoLens.Message WebSearch where
  messageName _ = Data.Text.pack "xai_api.WebSearch"
  packedMessageDescriptor _
    = "\n\
      \\tWebSearch\DC2)\n\
      \\DLEexcluded_domains\CAN\SOH \ETX(\tR\SIexcludedDomains\DC2'\n\
      \\SIallowed_domains\CAN\STX \ETX(\tR\SOallowedDomains\DC2A\n\
      \\SUBenable_image_understanding\CAN\ETX \SOH(\bH\NULR\CANenableImageUnderstanding\136\SOH\SOH\DC2H\n\
      \\ruser_location\CAN\EOT \SOH(\v2\RS.xai_api.WebSearchUserLocationH\SOHR\fuserLocation\136\SOH\SOH\DC23\n\
      \\DC3enable_image_search\CAN\ENQ \SOH(\bH\STXR\DC1enableImageSearch\136\SOH\SOHB\GS\n\
      \\ESC_enable_image_understandingB\DLE\n\
      \\SO_user_locationB\SYN\n\
      \\DC4_enable_image_search"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        excludedDomains__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "excluded_domains"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Unpacked
                 (Data.ProtoLens.Field.field @"excludedDomains")) ::
              Data.ProtoLens.FieldDescriptor WebSearch
        allowedDomains__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "allowed_domains"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Unpacked
                 (Data.ProtoLens.Field.field @"allowedDomains")) ::
              Data.ProtoLens.FieldDescriptor WebSearch
        enableImageUnderstanding__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "enable_image_understanding"
              (Data.ProtoLens.ScalarField Data.ProtoLens.BoolField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Bool)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'enableImageUnderstanding")) ::
              Data.ProtoLens.FieldDescriptor WebSearch
        userLocation__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "user_location"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor WebSearchUserLocation)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'userLocation")) ::
              Data.ProtoLens.FieldDescriptor WebSearch
        enableImageSearch__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "enable_image_search"
              (Data.ProtoLens.ScalarField Data.ProtoLens.BoolField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Bool)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'enableImageSearch")) ::
              Data.ProtoLens.FieldDescriptor WebSearch
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, excludedDomains__field_descriptor),
           (Data.ProtoLens.Tag 2, allowedDomains__field_descriptor),
           (Data.ProtoLens.Tag 3, enableImageUnderstanding__field_descriptor),
           (Data.ProtoLens.Tag 4, userLocation__field_descriptor),
           (Data.ProtoLens.Tag 5, enableImageSearch__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _WebSearch'_unknownFields
        (\ x__ y__ -> x__ {_WebSearch'_unknownFields = y__})
  defMessage
    = WebSearch'_constructor
        {_WebSearch'excludedDomains = Data.Vector.Generic.empty,
         _WebSearch'allowedDomains = Data.Vector.Generic.empty,
         _WebSearch'enableImageUnderstanding = Prelude.Nothing,
         _WebSearch'userLocation = Prelude.Nothing,
         _WebSearch'enableImageSearch = Prelude.Nothing,
         _WebSearch'_unknownFields = []}
  parseMessage
    = let
        loop ::
          WebSearch
          -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Vector Data.ProtoLens.Encoding.Growing.RealWorld Data.Text.Text
             -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Vector Data.ProtoLens.Encoding.Growing.RealWorld Data.Text.Text
                -> Data.ProtoLens.Encoding.Bytes.Parser WebSearch
        loop x mutable'allowedDomains mutable'excludedDomains
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do frozen'allowedDomains <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                                 (Data.ProtoLens.Encoding.Growing.unsafeFreeze
                                                    mutable'allowedDomains)
                      frozen'excludedDomains <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                                  (Data.ProtoLens.Encoding.Growing.unsafeFreeze
                                                     mutable'excludedDomains)
                      (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t)
                           (Lens.Family2.set
                              (Data.ProtoLens.Field.field @"vec'allowedDomains")
                              frozen'allowedDomains
                              (Lens.Family2.set
                                 (Data.ProtoLens.Field.field @"vec'excludedDomains")
                                 frozen'excludedDomains x)))
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                            Data.ProtoLens.Encoding.Bytes.getText
                                              (Prelude.fromIntegral len))
                                        "excluded_domains"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append
                                          mutable'excludedDomains y)
                                loop x mutable'allowedDomains v
                        18
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                            Data.ProtoLens.Encoding.Bytes.getText
                                              (Prelude.fromIntegral len))
                                        "allowed_domains"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append
                                          mutable'allowedDomains y)
                                loop x v mutable'excludedDomains
                        24
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          ((Prelude./=) 0) Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "enable_image_understanding"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"enableImageUnderstanding") y x)
                                  mutable'allowedDomains mutable'excludedDomains
                        34
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "user_location"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"userLocation") y x)
                                  mutable'allowedDomains mutable'excludedDomains
                        40
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          ((Prelude./=) 0) Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "enable_image_search"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"enableImageSearch") y x)
                                  mutable'allowedDomains mutable'excludedDomains
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
                                  mutable'allowedDomains mutable'excludedDomains
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do mutable'allowedDomains <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                          Data.ProtoLens.Encoding.Growing.new
              mutable'excludedDomains <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                           Data.ProtoLens.Encoding.Growing.new
              loop
                Data.ProtoLens.defMessage mutable'allowedDomains
                mutable'excludedDomains)
          "WebSearch"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (Data.ProtoLens.Encoding.Bytes.foldMapBuilder
                (\ _v
                   -> (Data.Monoid.<>)
                        (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                        ((Prelude..)
                           (\ bs
                              -> (Data.Monoid.<>)
                                   (Data.ProtoLens.Encoding.Bytes.putVarInt
                                      (Prelude.fromIntegral (Data.ByteString.length bs)))
                                   (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                           Data.Text.Encoding.encodeUtf8 _v))
                (Lens.Family2.view
                   (Data.ProtoLens.Field.field @"vec'excludedDomains") _x))
             ((Data.Monoid.<>)
                (Data.ProtoLens.Encoding.Bytes.foldMapBuilder
                   (\ _v
                      -> (Data.Monoid.<>)
                           (Data.ProtoLens.Encoding.Bytes.putVarInt 18)
                           ((Prelude..)
                              (\ bs
                                 -> (Data.Monoid.<>)
                                      (Data.ProtoLens.Encoding.Bytes.putVarInt
                                         (Prelude.fromIntegral (Data.ByteString.length bs)))
                                      (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                              Data.Text.Encoding.encodeUtf8 _v))
                   (Lens.Family2.view
                      (Data.ProtoLens.Field.field @"vec'allowedDomains") _x))
                ((Data.Monoid.<>)
                   (case
                        Lens.Family2.view
                          (Data.ProtoLens.Field.field @"maybe'enableImageUnderstanding") _x
                    of
                      Prelude.Nothing -> Data.Monoid.mempty
                      (Prelude.Just _v)
                        -> (Data.Monoid.<>)
                             (Data.ProtoLens.Encoding.Bytes.putVarInt 24)
                             ((Prelude..)
                                Data.ProtoLens.Encoding.Bytes.putVarInt (\ b -> if b then 1 else 0)
                                _v))
                   ((Data.Monoid.<>)
                      (case
                           Lens.Family2.view
                             (Data.ProtoLens.Field.field @"maybe'userLocation") _x
                       of
                         Prelude.Nothing -> Data.Monoid.mempty
                         (Prelude.Just _v)
                           -> (Data.Monoid.<>)
                                (Data.ProtoLens.Encoding.Bytes.putVarInt 34)
                                ((Prelude..)
                                   (\ bs
                                      -> (Data.Monoid.<>)
                                           (Data.ProtoLens.Encoding.Bytes.putVarInt
                                              (Prelude.fromIntegral (Data.ByteString.length bs)))
                                           (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                   Data.ProtoLens.encodeMessage _v))
                      ((Data.Monoid.<>)
                         (case
                              Lens.Family2.view
                                (Data.ProtoLens.Field.field @"maybe'enableImageSearch") _x
                          of
                            Prelude.Nothing -> Data.Monoid.mempty
                            (Prelude.Just _v)
                              -> (Data.Monoid.<>)
                                   (Data.ProtoLens.Encoding.Bytes.putVarInt 40)
                                   ((Prelude..)
                                      Data.ProtoLens.Encoding.Bytes.putVarInt
                                      (\ b -> if b then 1 else 0) _v))
                         (Data.ProtoLens.Encoding.Wire.buildFieldSet
                            (Lens.Family2.view Data.ProtoLens.unknownFields _x))))))
instance Control.DeepSeq.NFData WebSearch where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_WebSearch'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_WebSearch'excludedDomains x__)
                (Control.DeepSeq.deepseq
                   (_WebSearch'allowedDomains x__)
                   (Control.DeepSeq.deepseq
                      (_WebSearch'enableImageUnderstanding x__)
                      (Control.DeepSeq.deepseq
                         (_WebSearch'userLocation x__)
                         (Control.DeepSeq.deepseq (_WebSearch'enableImageSearch x__) ())))))
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Chat_Fields.country' @:: Lens' WebSearchUserLocation Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'country' @:: Lens' WebSearchUserLocation (Prelude.Maybe Data.Text.Text)@
         * 'Proto.Xai.Api.V1.Chat_Fields.city' @:: Lens' WebSearchUserLocation Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'city' @:: Lens' WebSearchUserLocation (Prelude.Maybe Data.Text.Text)@
         * 'Proto.Xai.Api.V1.Chat_Fields.region' @:: Lens' WebSearchUserLocation Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'region' @:: Lens' WebSearchUserLocation (Prelude.Maybe Data.Text.Text)@
         * 'Proto.Xai.Api.V1.Chat_Fields.timezone' @:: Lens' WebSearchUserLocation Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'timezone' @:: Lens' WebSearchUserLocation (Prelude.Maybe Data.Text.Text)@ -}
data WebSearchUserLocation
  = WebSearchUserLocation'_constructor {_WebSearchUserLocation'country :: !(Prelude.Maybe Data.Text.Text),
                                        _WebSearchUserLocation'city :: !(Prelude.Maybe Data.Text.Text),
                                        _WebSearchUserLocation'region :: !(Prelude.Maybe Data.Text.Text),
                                        _WebSearchUserLocation'timezone :: !(Prelude.Maybe Data.Text.Text),
                                        _WebSearchUserLocation'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show WebSearchUserLocation where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField WebSearchUserLocation "country" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WebSearchUserLocation'country
           (\ x__ y__ -> x__ {_WebSearchUserLocation'country = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField WebSearchUserLocation "maybe'country" (Prelude.Maybe Data.Text.Text) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WebSearchUserLocation'country
           (\ x__ y__ -> x__ {_WebSearchUserLocation'country = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField WebSearchUserLocation "city" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WebSearchUserLocation'city
           (\ x__ y__ -> x__ {_WebSearchUserLocation'city = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField WebSearchUserLocation "maybe'city" (Prelude.Maybe Data.Text.Text) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WebSearchUserLocation'city
           (\ x__ y__ -> x__ {_WebSearchUserLocation'city = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField WebSearchUserLocation "region" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WebSearchUserLocation'region
           (\ x__ y__ -> x__ {_WebSearchUserLocation'region = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField WebSearchUserLocation "maybe'region" (Prelude.Maybe Data.Text.Text) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WebSearchUserLocation'region
           (\ x__ y__ -> x__ {_WebSearchUserLocation'region = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField WebSearchUserLocation "timezone" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WebSearchUserLocation'timezone
           (\ x__ y__ -> x__ {_WebSearchUserLocation'timezone = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField WebSearchUserLocation "maybe'timezone" (Prelude.Maybe Data.Text.Text) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WebSearchUserLocation'timezone
           (\ x__ y__ -> x__ {_WebSearchUserLocation'timezone = y__}))
        Prelude.id
instance Data.ProtoLens.Message WebSearchUserLocation where
  messageName _ = Data.Text.pack "xai_api.WebSearchUserLocation"
  packedMessageDescriptor _
    = "\n\
      \\NAKWebSearchUserLocation\DC2\GS\n\
      \\acountry\CAN\SOH \SOH(\tH\NULR\acountry\136\SOH\SOH\DC2\ETB\n\
      \\EOTcity\CAN\STX \SOH(\tH\SOHR\EOTcity\136\SOH\SOH\DC2\ESC\n\
      \\ACKregion\CAN\ETX \SOH(\tH\STXR\ACKregion\136\SOH\SOH\DC2\US\n\
      \\btimezone\CAN\EOT \SOH(\tH\ETXR\btimezone\136\SOH\SOHB\n\
      \\n\
      \\b_countryB\a\n\
      \\ENQ_cityB\t\n\
      \\a_regionB\v\n\
      \\t_timezone"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        country__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "country"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'country")) ::
              Data.ProtoLens.FieldDescriptor WebSearchUserLocation
        city__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "city"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'city")) ::
              Data.ProtoLens.FieldDescriptor WebSearchUserLocation
        region__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "region"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'region")) ::
              Data.ProtoLens.FieldDescriptor WebSearchUserLocation
        timezone__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "timezone"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'timezone")) ::
              Data.ProtoLens.FieldDescriptor WebSearchUserLocation
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, country__field_descriptor),
           (Data.ProtoLens.Tag 2, city__field_descriptor),
           (Data.ProtoLens.Tag 3, region__field_descriptor),
           (Data.ProtoLens.Tag 4, timezone__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _WebSearchUserLocation'_unknownFields
        (\ x__ y__ -> x__ {_WebSearchUserLocation'_unknownFields = y__})
  defMessage
    = WebSearchUserLocation'_constructor
        {_WebSearchUserLocation'country = Prelude.Nothing,
         _WebSearchUserLocation'city = Prelude.Nothing,
         _WebSearchUserLocation'region = Prelude.Nothing,
         _WebSearchUserLocation'timezone = Prelude.Nothing,
         _WebSearchUserLocation'_unknownFields = []}
  parseMessage
    = let
        loop ::
          WebSearchUserLocation
          -> Data.ProtoLens.Encoding.Bytes.Parser WebSearchUserLocation
        loop x
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t) x)
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "country"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"country") y x)
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "city"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"city") y x)
                        26
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "region"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"region") y x)
                        34
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "timezone"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"timezone") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "WebSearchUserLocation"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (case
                  Lens.Family2.view (Data.ProtoLens.Field.field @"maybe'country") _x
              of
                Prelude.Nothing -> Data.Monoid.mempty
                (Prelude.Just _v)
                  -> (Data.Monoid.<>)
                       (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                       ((Prelude..)
                          (\ bs
                             -> (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                     (Prelude.fromIntegral (Data.ByteString.length bs)))
                                  (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                          Data.Text.Encoding.encodeUtf8 _v))
             ((Data.Monoid.<>)
                (case
                     Lens.Family2.view (Data.ProtoLens.Field.field @"maybe'city") _x
                 of
                   Prelude.Nothing -> Data.Monoid.mempty
                   (Prelude.Just _v)
                     -> (Data.Monoid.<>)
                          (Data.ProtoLens.Encoding.Bytes.putVarInt 18)
                          ((Prelude..)
                             (\ bs
                                -> (Data.Monoid.<>)
                                     (Data.ProtoLens.Encoding.Bytes.putVarInt
                                        (Prelude.fromIntegral (Data.ByteString.length bs)))
                                     (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                             Data.Text.Encoding.encodeUtf8 _v))
                ((Data.Monoid.<>)
                   (case
                        Lens.Family2.view (Data.ProtoLens.Field.field @"maybe'region") _x
                    of
                      Prelude.Nothing -> Data.Monoid.mempty
                      (Prelude.Just _v)
                        -> (Data.Monoid.<>)
                             (Data.ProtoLens.Encoding.Bytes.putVarInt 26)
                             ((Prelude..)
                                (\ bs
                                   -> (Data.Monoid.<>)
                                        (Data.ProtoLens.Encoding.Bytes.putVarInt
                                           (Prelude.fromIntegral (Data.ByteString.length bs)))
                                        (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                Data.Text.Encoding.encodeUtf8 _v))
                   ((Data.Monoid.<>)
                      (case
                           Lens.Family2.view (Data.ProtoLens.Field.field @"maybe'timezone") _x
                       of
                         Prelude.Nothing -> Data.Monoid.mempty
                         (Prelude.Just _v)
                           -> (Data.Monoid.<>)
                                (Data.ProtoLens.Encoding.Bytes.putVarInt 34)
                                ((Prelude..)
                                   (\ bs
                                      -> (Data.Monoid.<>)
                                           (Data.ProtoLens.Encoding.Bytes.putVarInt
                                              (Prelude.fromIntegral (Data.ByteString.length bs)))
                                           (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                   Data.Text.Encoding.encodeUtf8 _v))
                      (Data.ProtoLens.Encoding.Wire.buildFieldSet
                         (Lens.Family2.view Data.ProtoLens.unknownFields _x)))))
instance Control.DeepSeq.NFData WebSearchUserLocation where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_WebSearchUserLocation'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_WebSearchUserLocation'country x__)
                (Control.DeepSeq.deepseq
                   (_WebSearchUserLocation'city x__)
                   (Control.DeepSeq.deepseq
                      (_WebSearchUserLocation'region x__)
                      (Control.DeepSeq.deepseq
                         (_WebSearchUserLocation'timezone x__) ()))))
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Chat_Fields.excludedWebsites' @:: Lens' WebSource [Data.Text.Text]@
         * 'Proto.Xai.Api.V1.Chat_Fields.vec'excludedWebsites' @:: Lens' WebSource (Data.Vector.Vector Data.Text.Text)@
         * 'Proto.Xai.Api.V1.Chat_Fields.allowedWebsites' @:: Lens' WebSource [Data.Text.Text]@
         * 'Proto.Xai.Api.V1.Chat_Fields.vec'allowedWebsites' @:: Lens' WebSource (Data.Vector.Vector Data.Text.Text)@
         * 'Proto.Xai.Api.V1.Chat_Fields.country' @:: Lens' WebSource Data.Text.Text@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'country' @:: Lens' WebSource (Prelude.Maybe Data.Text.Text)@
         * 'Proto.Xai.Api.V1.Chat_Fields.safeSearch' @:: Lens' WebSource Prelude.Bool@ -}
data WebSource
  = WebSource'_constructor {_WebSource'excludedWebsites :: !(Data.Vector.Vector Data.Text.Text),
                            _WebSource'allowedWebsites :: !(Data.Vector.Vector Data.Text.Text),
                            _WebSource'country :: !(Prelude.Maybe Data.Text.Text),
                            _WebSource'safeSearch :: !Prelude.Bool,
                            _WebSource'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show WebSource where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField WebSource "excludedWebsites" [Data.Text.Text] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WebSource'excludedWebsites
           (\ x__ y__ -> x__ {_WebSource'excludedWebsites = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField WebSource "vec'excludedWebsites" (Data.Vector.Vector Data.Text.Text) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WebSource'excludedWebsites
           (\ x__ y__ -> x__ {_WebSource'excludedWebsites = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField WebSource "allowedWebsites" [Data.Text.Text] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WebSource'allowedWebsites
           (\ x__ y__ -> x__ {_WebSource'allowedWebsites = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField WebSource "vec'allowedWebsites" (Data.Vector.Vector Data.Text.Text) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WebSource'allowedWebsites
           (\ x__ y__ -> x__ {_WebSource'allowedWebsites = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField WebSource "country" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WebSource'country (\ x__ y__ -> x__ {_WebSource'country = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField WebSource "maybe'country" (Prelude.Maybe Data.Text.Text) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WebSource'country (\ x__ y__ -> x__ {_WebSource'country = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField WebSource "safeSearch" Prelude.Bool where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _WebSource'safeSearch
           (\ x__ y__ -> x__ {_WebSource'safeSearch = y__}))
        Prelude.id
instance Data.ProtoLens.Message WebSource where
  messageName _ = Data.Text.pack "xai_api.WebSource"
  packedMessageDescriptor _
    = "\n\
      \\tWebSource\DC2+\n\
      \\DC1excluded_websites\CAN\STX \ETX(\tR\DLEexcludedWebsites\DC2)\n\
      \\DLEallowed_websites\CAN\ENQ \ETX(\tR\SIallowedWebsites\DC2\GS\n\
      \\acountry\CAN\ETX \SOH(\tH\NULR\acountry\136\SOH\SOH\DC2\US\n\
      \\vsafe_search\CAN\EOT \SOH(\bR\n\
      \safeSearchB\n\
      \\n\
      \\b_country"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        excludedWebsites__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "excluded_websites"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Unpacked
                 (Data.ProtoLens.Field.field @"excludedWebsites")) ::
              Data.ProtoLens.FieldDescriptor WebSource
        allowedWebsites__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "allowed_websites"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Unpacked
                 (Data.ProtoLens.Field.field @"allowedWebsites")) ::
              Data.ProtoLens.FieldDescriptor WebSource
        country__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "country"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'country")) ::
              Data.ProtoLens.FieldDescriptor WebSource
        safeSearch__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "safe_search"
              (Data.ProtoLens.ScalarField Data.ProtoLens.BoolField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Bool)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"safeSearch")) ::
              Data.ProtoLens.FieldDescriptor WebSource
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 2, excludedWebsites__field_descriptor),
           (Data.ProtoLens.Tag 5, allowedWebsites__field_descriptor),
           (Data.ProtoLens.Tag 3, country__field_descriptor),
           (Data.ProtoLens.Tag 4, safeSearch__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _WebSource'_unknownFields
        (\ x__ y__ -> x__ {_WebSource'_unknownFields = y__})
  defMessage
    = WebSource'_constructor
        {_WebSource'excludedWebsites = Data.Vector.Generic.empty,
         _WebSource'allowedWebsites = Data.Vector.Generic.empty,
         _WebSource'country = Prelude.Nothing,
         _WebSource'safeSearch = Data.ProtoLens.fieldDefault,
         _WebSource'_unknownFields = []}
  parseMessage
    = let
        loop ::
          WebSource
          -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Vector Data.ProtoLens.Encoding.Growing.RealWorld Data.Text.Text
             -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Vector Data.ProtoLens.Encoding.Growing.RealWorld Data.Text.Text
                -> Data.ProtoLens.Encoding.Bytes.Parser WebSource
        loop x mutable'allowedWebsites mutable'excludedWebsites
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do frozen'allowedWebsites <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                                  (Data.ProtoLens.Encoding.Growing.unsafeFreeze
                                                     mutable'allowedWebsites)
                      frozen'excludedWebsites <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                                   (Data.ProtoLens.Encoding.Growing.unsafeFreeze
                                                      mutable'excludedWebsites)
                      (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t)
                           (Lens.Family2.set
                              (Data.ProtoLens.Field.field @"vec'allowedWebsites")
                              frozen'allowedWebsites
                              (Lens.Family2.set
                                 (Data.ProtoLens.Field.field @"vec'excludedWebsites")
                                 frozen'excludedWebsites x)))
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        18
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                            Data.ProtoLens.Encoding.Bytes.getText
                                              (Prelude.fromIntegral len))
                                        "excluded_websites"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append
                                          mutable'excludedWebsites y)
                                loop x mutable'allowedWebsites v
                        42
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                            Data.ProtoLens.Encoding.Bytes.getText
                                              (Prelude.fromIntegral len))
                                        "allowed_websites"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append
                                          mutable'allowedWebsites y)
                                loop x v mutable'excludedWebsites
                        26
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "country"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"country") y x)
                                  mutable'allowedWebsites mutable'excludedWebsites
                        32
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          ((Prelude./=) 0) Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "safe_search"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"safeSearch") y x)
                                  mutable'allowedWebsites mutable'excludedWebsites
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
                                  mutable'allowedWebsites mutable'excludedWebsites
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do mutable'allowedWebsites <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                           Data.ProtoLens.Encoding.Growing.new
              mutable'excludedWebsites <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                            Data.ProtoLens.Encoding.Growing.new
              loop
                Data.ProtoLens.defMessage mutable'allowedWebsites
                mutable'excludedWebsites)
          "WebSource"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (Data.ProtoLens.Encoding.Bytes.foldMapBuilder
                (\ _v
                   -> (Data.Monoid.<>)
                        (Data.ProtoLens.Encoding.Bytes.putVarInt 18)
                        ((Prelude..)
                           (\ bs
                              -> (Data.Monoid.<>)
                                   (Data.ProtoLens.Encoding.Bytes.putVarInt
                                      (Prelude.fromIntegral (Data.ByteString.length bs)))
                                   (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                           Data.Text.Encoding.encodeUtf8 _v))
                (Lens.Family2.view
                   (Data.ProtoLens.Field.field @"vec'excludedWebsites") _x))
             ((Data.Monoid.<>)
                (Data.ProtoLens.Encoding.Bytes.foldMapBuilder
                   (\ _v
                      -> (Data.Monoid.<>)
                           (Data.ProtoLens.Encoding.Bytes.putVarInt 42)
                           ((Prelude..)
                              (\ bs
                                 -> (Data.Monoid.<>)
                                      (Data.ProtoLens.Encoding.Bytes.putVarInt
                                         (Prelude.fromIntegral (Data.ByteString.length bs)))
                                      (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                              Data.Text.Encoding.encodeUtf8 _v))
                   (Lens.Family2.view
                      (Data.ProtoLens.Field.field @"vec'allowedWebsites") _x))
                ((Data.Monoid.<>)
                   (case
                        Lens.Family2.view (Data.ProtoLens.Field.field @"maybe'country") _x
                    of
                      Prelude.Nothing -> Data.Monoid.mempty
                      (Prelude.Just _v)
                        -> (Data.Monoid.<>)
                             (Data.ProtoLens.Encoding.Bytes.putVarInt 26)
                             ((Prelude..)
                                (\ bs
                                   -> (Data.Monoid.<>)
                                        (Data.ProtoLens.Encoding.Bytes.putVarInt
                                           (Prelude.fromIntegral (Data.ByteString.length bs)))
                                        (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                Data.Text.Encoding.encodeUtf8 _v))
                   ((Data.Monoid.<>)
                      (let
                         _v
                           = Lens.Family2.view (Data.ProtoLens.Field.field @"safeSearch") _x
                       in
                         if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                             Data.Monoid.mempty
                         else
                             (Data.Monoid.<>)
                               (Data.ProtoLens.Encoding.Bytes.putVarInt 32)
                               ((Prelude..)
                                  Data.ProtoLens.Encoding.Bytes.putVarInt
                                  (\ b -> if b then 1 else 0) _v))
                      (Data.ProtoLens.Encoding.Wire.buildFieldSet
                         (Lens.Family2.view Data.ProtoLens.unknownFields _x)))))
instance Control.DeepSeq.NFData WebSource where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_WebSource'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_WebSource'excludedWebsites x__)
                (Control.DeepSeq.deepseq
                   (_WebSource'allowedWebsites x__)
                   (Control.DeepSeq.deepseq
                      (_WebSource'country x__)
                      (Control.DeepSeq.deepseq (_WebSource'safeSearch x__) ()))))
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Chat_Fields.url' @:: Lens' XCitation Data.Text.Text@ -}
data XCitation
  = XCitation'_constructor {_XCitation'url :: !Data.Text.Text,
                            _XCitation'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show XCitation where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField XCitation "url" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _XCitation'url (\ x__ y__ -> x__ {_XCitation'url = y__}))
        Prelude.id
instance Data.ProtoLens.Message XCitation where
  messageName _ = Data.Text.pack "xai_api.XCitation"
  packedMessageDescriptor _
    = "\n\
      \\tXCitation\DC2\DLE\n\
      \\ETXurl\CAN\SOH \SOH(\tR\ETXurl"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        url__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "url"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"url")) ::
              Data.ProtoLens.FieldDescriptor XCitation
      in
        Data.Map.fromList [(Data.ProtoLens.Tag 1, url__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _XCitation'_unknownFields
        (\ x__ y__ -> x__ {_XCitation'_unknownFields = y__})
  defMessage
    = XCitation'_constructor
        {_XCitation'url = Data.ProtoLens.fieldDefault,
         _XCitation'_unknownFields = []}
  parseMessage
    = let
        loop :: XCitation -> Data.ProtoLens.Encoding.Bytes.Parser XCitation
        loop x
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t) x)
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "url"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"url") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "XCitation"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let _v = Lens.Family2.view (Data.ProtoLens.Field.field @"url") _x
              in
                if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                      ((Prelude..)
                         (\ bs
                            -> (Data.Monoid.<>)
                                 (Data.ProtoLens.Encoding.Bytes.putVarInt
                                    (Prelude.fromIntegral (Data.ByteString.length bs)))
                                 (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                         Data.Text.Encoding.encodeUtf8 _v))
             (Data.ProtoLens.Encoding.Wire.buildFieldSet
                (Lens.Family2.view Data.ProtoLens.unknownFields _x))
instance Control.DeepSeq.NFData XCitation where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_XCitation'_unknownFields x__)
             (Control.DeepSeq.deepseq (_XCitation'url x__) ())
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Chat_Fields.fromDate' @:: Lens' XSearch Proto.Google.Protobuf.Timestamp.Timestamp@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'fromDate' @:: Lens' XSearch (Prelude.Maybe Proto.Google.Protobuf.Timestamp.Timestamp)@
         * 'Proto.Xai.Api.V1.Chat_Fields.toDate' @:: Lens' XSearch Proto.Google.Protobuf.Timestamp.Timestamp@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'toDate' @:: Lens' XSearch (Prelude.Maybe Proto.Google.Protobuf.Timestamp.Timestamp)@
         * 'Proto.Xai.Api.V1.Chat_Fields.allowedXHandles' @:: Lens' XSearch [Data.Text.Text]@
         * 'Proto.Xai.Api.V1.Chat_Fields.vec'allowedXHandles' @:: Lens' XSearch (Data.Vector.Vector Data.Text.Text)@
         * 'Proto.Xai.Api.V1.Chat_Fields.excludedXHandles' @:: Lens' XSearch [Data.Text.Text]@
         * 'Proto.Xai.Api.V1.Chat_Fields.vec'excludedXHandles' @:: Lens' XSearch (Data.Vector.Vector Data.Text.Text)@
         * 'Proto.Xai.Api.V1.Chat_Fields.enableImageUnderstanding' @:: Lens' XSearch Prelude.Bool@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'enableImageUnderstanding' @:: Lens' XSearch (Prelude.Maybe Prelude.Bool)@
         * 'Proto.Xai.Api.V1.Chat_Fields.enableVideoUnderstanding' @:: Lens' XSearch Prelude.Bool@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'enableVideoUnderstanding' @:: Lens' XSearch (Prelude.Maybe Prelude.Bool)@ -}
data XSearch
  = XSearch'_constructor {_XSearch'fromDate :: !(Prelude.Maybe Proto.Google.Protobuf.Timestamp.Timestamp),
                          _XSearch'toDate :: !(Prelude.Maybe Proto.Google.Protobuf.Timestamp.Timestamp),
                          _XSearch'allowedXHandles :: !(Data.Vector.Vector Data.Text.Text),
                          _XSearch'excludedXHandles :: !(Data.Vector.Vector Data.Text.Text),
                          _XSearch'enableImageUnderstanding :: !(Prelude.Maybe Prelude.Bool),
                          _XSearch'enableVideoUnderstanding :: !(Prelude.Maybe Prelude.Bool),
                          _XSearch'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show XSearch where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField XSearch "fromDate" Proto.Google.Protobuf.Timestamp.Timestamp where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _XSearch'fromDate (\ x__ y__ -> x__ {_XSearch'fromDate = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage)
instance Data.ProtoLens.Field.HasField XSearch "maybe'fromDate" (Prelude.Maybe Proto.Google.Protobuf.Timestamp.Timestamp) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _XSearch'fromDate (\ x__ y__ -> x__ {_XSearch'fromDate = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField XSearch "toDate" Proto.Google.Protobuf.Timestamp.Timestamp where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _XSearch'toDate (\ x__ y__ -> x__ {_XSearch'toDate = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage)
instance Data.ProtoLens.Field.HasField XSearch "maybe'toDate" (Prelude.Maybe Proto.Google.Protobuf.Timestamp.Timestamp) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _XSearch'toDate (\ x__ y__ -> x__ {_XSearch'toDate = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField XSearch "allowedXHandles" [Data.Text.Text] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _XSearch'allowedXHandles
           (\ x__ y__ -> x__ {_XSearch'allowedXHandles = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField XSearch "vec'allowedXHandles" (Data.Vector.Vector Data.Text.Text) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _XSearch'allowedXHandles
           (\ x__ y__ -> x__ {_XSearch'allowedXHandles = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField XSearch "excludedXHandles" [Data.Text.Text] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _XSearch'excludedXHandles
           (\ x__ y__ -> x__ {_XSearch'excludedXHandles = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField XSearch "vec'excludedXHandles" (Data.Vector.Vector Data.Text.Text) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _XSearch'excludedXHandles
           (\ x__ y__ -> x__ {_XSearch'excludedXHandles = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField XSearch "enableImageUnderstanding" Prelude.Bool where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _XSearch'enableImageUnderstanding
           (\ x__ y__ -> x__ {_XSearch'enableImageUnderstanding = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField XSearch "maybe'enableImageUnderstanding" (Prelude.Maybe Prelude.Bool) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _XSearch'enableImageUnderstanding
           (\ x__ y__ -> x__ {_XSearch'enableImageUnderstanding = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField XSearch "enableVideoUnderstanding" Prelude.Bool where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _XSearch'enableVideoUnderstanding
           (\ x__ y__ -> x__ {_XSearch'enableVideoUnderstanding = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField XSearch "maybe'enableVideoUnderstanding" (Prelude.Maybe Prelude.Bool) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _XSearch'enableVideoUnderstanding
           (\ x__ y__ -> x__ {_XSearch'enableVideoUnderstanding = y__}))
        Prelude.id
instance Data.ProtoLens.Message XSearch where
  messageName _ = Data.Text.pack "xai_api.XSearch"
  packedMessageDescriptor _
    = "\n\
      \\aXSearch\DC2<\n\
      \\tfrom_date\CAN\SOH \SOH(\v2\SUB.google.protobuf.TimestampH\NULR\bfromDate\136\SOH\SOH\DC28\n\
      \\ato_date\CAN\STX \SOH(\v2\SUB.google.protobuf.TimestampH\SOHR\ACKtoDate\136\SOH\SOH\DC2*\n\
      \\DC1allowed_x_handles\CAN\ETX \ETX(\tR\SIallowedXHandles\DC2,\n\
      \\DC2excluded_x_handles\CAN\EOT \ETX(\tR\DLEexcludedXHandles\DC2A\n\
      \\SUBenable_image_understanding\CAN\ENQ \SOH(\bH\STXR\CANenableImageUnderstanding\136\SOH\SOH\DC2A\n\
      \\SUBenable_video_understanding\CAN\ACK \SOH(\bH\ETXR\CANenableVideoUnderstanding\136\SOH\SOHB\f\n\
      \\n\
      \_from_dateB\n\
      \\n\
      \\b_to_dateB\GS\n\
      \\ESC_enable_image_understandingB\GS\n\
      \\ESC_enable_video_understanding"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        fromDate__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "from_date"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor Proto.Google.Protobuf.Timestamp.Timestamp)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'fromDate")) ::
              Data.ProtoLens.FieldDescriptor XSearch
        toDate__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "to_date"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor Proto.Google.Protobuf.Timestamp.Timestamp)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'toDate")) ::
              Data.ProtoLens.FieldDescriptor XSearch
        allowedXHandles__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "allowed_x_handles"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Unpacked
                 (Data.ProtoLens.Field.field @"allowedXHandles")) ::
              Data.ProtoLens.FieldDescriptor XSearch
        excludedXHandles__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "excluded_x_handles"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Unpacked
                 (Data.ProtoLens.Field.field @"excludedXHandles")) ::
              Data.ProtoLens.FieldDescriptor XSearch
        enableImageUnderstanding__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "enable_image_understanding"
              (Data.ProtoLens.ScalarField Data.ProtoLens.BoolField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Bool)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'enableImageUnderstanding")) ::
              Data.ProtoLens.FieldDescriptor XSearch
        enableVideoUnderstanding__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "enable_video_understanding"
              (Data.ProtoLens.ScalarField Data.ProtoLens.BoolField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Bool)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'enableVideoUnderstanding")) ::
              Data.ProtoLens.FieldDescriptor XSearch
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, fromDate__field_descriptor),
           (Data.ProtoLens.Tag 2, toDate__field_descriptor),
           (Data.ProtoLens.Tag 3, allowedXHandles__field_descriptor),
           (Data.ProtoLens.Tag 4, excludedXHandles__field_descriptor),
           (Data.ProtoLens.Tag 5, enableImageUnderstanding__field_descriptor),
           (Data.ProtoLens.Tag 6, enableVideoUnderstanding__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _XSearch'_unknownFields
        (\ x__ y__ -> x__ {_XSearch'_unknownFields = y__})
  defMessage
    = XSearch'_constructor
        {_XSearch'fromDate = Prelude.Nothing,
         _XSearch'toDate = Prelude.Nothing,
         _XSearch'allowedXHandles = Data.Vector.Generic.empty,
         _XSearch'excludedXHandles = Data.Vector.Generic.empty,
         _XSearch'enableImageUnderstanding = Prelude.Nothing,
         _XSearch'enableVideoUnderstanding = Prelude.Nothing,
         _XSearch'_unknownFields = []}
  parseMessage
    = let
        loop ::
          XSearch
          -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Vector Data.ProtoLens.Encoding.Growing.RealWorld Data.Text.Text
             -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Vector Data.ProtoLens.Encoding.Growing.RealWorld Data.Text.Text
                -> Data.ProtoLens.Encoding.Bytes.Parser XSearch
        loop x mutable'allowedXHandles mutable'excludedXHandles
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do frozen'allowedXHandles <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                                  (Data.ProtoLens.Encoding.Growing.unsafeFreeze
                                                     mutable'allowedXHandles)
                      frozen'excludedXHandles <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                                   (Data.ProtoLens.Encoding.Growing.unsafeFreeze
                                                      mutable'excludedXHandles)
                      (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t)
                           (Lens.Family2.set
                              (Data.ProtoLens.Field.field @"vec'allowedXHandles")
                              frozen'allowedXHandles
                              (Lens.Family2.set
                                 (Data.ProtoLens.Field.field @"vec'excludedXHandles")
                                 frozen'excludedXHandles x)))
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "from_date"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"fromDate") y x)
                                  mutable'allowedXHandles mutable'excludedXHandles
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "to_date"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"toDate") y x)
                                  mutable'allowedXHandles mutable'excludedXHandles
                        26
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                            Data.ProtoLens.Encoding.Bytes.getText
                                              (Prelude.fromIntegral len))
                                        "allowed_x_handles"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append
                                          mutable'allowedXHandles y)
                                loop x v mutable'excludedXHandles
                        34
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                            Data.ProtoLens.Encoding.Bytes.getText
                                              (Prelude.fromIntegral len))
                                        "excluded_x_handles"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append
                                          mutable'excludedXHandles y)
                                loop x mutable'allowedXHandles v
                        40
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          ((Prelude./=) 0) Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "enable_image_understanding"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"enableImageUnderstanding") y x)
                                  mutable'allowedXHandles mutable'excludedXHandles
                        48
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          ((Prelude./=) 0) Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "enable_video_understanding"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"enableVideoUnderstanding") y x)
                                  mutable'allowedXHandles mutable'excludedXHandles
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
                                  mutable'allowedXHandles mutable'excludedXHandles
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do mutable'allowedXHandles <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                           Data.ProtoLens.Encoding.Growing.new
              mutable'excludedXHandles <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                            Data.ProtoLens.Encoding.Growing.new
              loop
                Data.ProtoLens.defMessage mutable'allowedXHandles
                mutable'excludedXHandles)
          "XSearch"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (case
                  Lens.Family2.view (Data.ProtoLens.Field.field @"maybe'fromDate") _x
              of
                Prelude.Nothing -> Data.Monoid.mempty
                (Prelude.Just _v)
                  -> (Data.Monoid.<>)
                       (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                       ((Prelude..)
                          (\ bs
                             -> (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt
                                     (Prelude.fromIntegral (Data.ByteString.length bs)))
                                  (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                          Data.ProtoLens.encodeMessage _v))
             ((Data.Monoid.<>)
                (case
                     Lens.Family2.view (Data.ProtoLens.Field.field @"maybe'toDate") _x
                 of
                   Prelude.Nothing -> Data.Monoid.mempty
                   (Prelude.Just _v)
                     -> (Data.Monoid.<>)
                          (Data.ProtoLens.Encoding.Bytes.putVarInt 18)
                          ((Prelude..)
                             (\ bs
                                -> (Data.Monoid.<>)
                                     (Data.ProtoLens.Encoding.Bytes.putVarInt
                                        (Prelude.fromIntegral (Data.ByteString.length bs)))
                                     (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                             Data.ProtoLens.encodeMessage _v))
                ((Data.Monoid.<>)
                   (Data.ProtoLens.Encoding.Bytes.foldMapBuilder
                      (\ _v
                         -> (Data.Monoid.<>)
                              (Data.ProtoLens.Encoding.Bytes.putVarInt 26)
                              ((Prelude..)
                                 (\ bs
                                    -> (Data.Monoid.<>)
                                         (Data.ProtoLens.Encoding.Bytes.putVarInt
                                            (Prelude.fromIntegral (Data.ByteString.length bs)))
                                         (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                 Data.Text.Encoding.encodeUtf8 _v))
                      (Lens.Family2.view
                         (Data.ProtoLens.Field.field @"vec'allowedXHandles") _x))
                   ((Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.foldMapBuilder
                         (\ _v
                            -> (Data.Monoid.<>)
                                 (Data.ProtoLens.Encoding.Bytes.putVarInt 34)
                                 ((Prelude..)
                                    (\ bs
                                       -> (Data.Monoid.<>)
                                            (Data.ProtoLens.Encoding.Bytes.putVarInt
                                               (Prelude.fromIntegral (Data.ByteString.length bs)))
                                            (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                    Data.Text.Encoding.encodeUtf8 _v))
                         (Lens.Family2.view
                            (Data.ProtoLens.Field.field @"vec'excludedXHandles") _x))
                      ((Data.Monoid.<>)
                         (case
                              Lens.Family2.view
                                (Data.ProtoLens.Field.field @"maybe'enableImageUnderstanding") _x
                          of
                            Prelude.Nothing -> Data.Monoid.mempty
                            (Prelude.Just _v)
                              -> (Data.Monoid.<>)
                                   (Data.ProtoLens.Encoding.Bytes.putVarInt 40)
                                   ((Prelude..)
                                      Data.ProtoLens.Encoding.Bytes.putVarInt
                                      (\ b -> if b then 1 else 0) _v))
                         ((Data.Monoid.<>)
                            (case
                                 Lens.Family2.view
                                   (Data.ProtoLens.Field.field @"maybe'enableVideoUnderstanding") _x
                             of
                               Prelude.Nothing -> Data.Monoid.mempty
                               (Prelude.Just _v)
                                 -> (Data.Monoid.<>)
                                      (Data.ProtoLens.Encoding.Bytes.putVarInt 48)
                                      ((Prelude..)
                                         Data.ProtoLens.Encoding.Bytes.putVarInt
                                         (\ b -> if b then 1 else 0) _v))
                            (Data.ProtoLens.Encoding.Wire.buildFieldSet
                               (Lens.Family2.view Data.ProtoLens.unknownFields _x)))))))
instance Control.DeepSeq.NFData XSearch where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_XSearch'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_XSearch'fromDate x__)
                (Control.DeepSeq.deepseq
                   (_XSearch'toDate x__)
                   (Control.DeepSeq.deepseq
                      (_XSearch'allowedXHandles x__)
                      (Control.DeepSeq.deepseq
                         (_XSearch'excludedXHandles x__)
                         (Control.DeepSeq.deepseq
                            (_XSearch'enableImageUnderstanding x__)
                            (Control.DeepSeq.deepseq
                               (_XSearch'enableVideoUnderstanding x__) ()))))))
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Chat_Fields.includedXHandles' @:: Lens' XSource [Data.Text.Text]@
         * 'Proto.Xai.Api.V1.Chat_Fields.vec'includedXHandles' @:: Lens' XSource (Data.Vector.Vector Data.Text.Text)@
         * 'Proto.Xai.Api.V1.Chat_Fields.excludedXHandles' @:: Lens' XSource [Data.Text.Text]@
         * 'Proto.Xai.Api.V1.Chat_Fields.vec'excludedXHandles' @:: Lens' XSource (Data.Vector.Vector Data.Text.Text)@
         * 'Proto.Xai.Api.V1.Chat_Fields.postFavoriteCount' @:: Lens' XSource Data.Int.Int32@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'postFavoriteCount' @:: Lens' XSource (Prelude.Maybe Data.Int.Int32)@
         * 'Proto.Xai.Api.V1.Chat_Fields.postViewCount' @:: Lens' XSource Data.Int.Int32@
         * 'Proto.Xai.Api.V1.Chat_Fields.maybe'postViewCount' @:: Lens' XSource (Prelude.Maybe Data.Int.Int32)@ -}
data XSource
  = XSource'_constructor {_XSource'includedXHandles :: !(Data.Vector.Vector Data.Text.Text),
                          _XSource'excludedXHandles :: !(Data.Vector.Vector Data.Text.Text),
                          _XSource'postFavoriteCount :: !(Prelude.Maybe Data.Int.Int32),
                          _XSource'postViewCount :: !(Prelude.Maybe Data.Int.Int32),
                          _XSource'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show XSource where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField XSource "includedXHandles" [Data.Text.Text] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _XSource'includedXHandles
           (\ x__ y__ -> x__ {_XSource'includedXHandles = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField XSource "vec'includedXHandles" (Data.Vector.Vector Data.Text.Text) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _XSource'includedXHandles
           (\ x__ y__ -> x__ {_XSource'includedXHandles = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField XSource "excludedXHandles" [Data.Text.Text] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _XSource'excludedXHandles
           (\ x__ y__ -> x__ {_XSource'excludedXHandles = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField XSource "vec'excludedXHandles" (Data.Vector.Vector Data.Text.Text) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _XSource'excludedXHandles
           (\ x__ y__ -> x__ {_XSource'excludedXHandles = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField XSource "postFavoriteCount" Data.Int.Int32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _XSource'postFavoriteCount
           (\ x__ y__ -> x__ {_XSource'postFavoriteCount = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField XSource "maybe'postFavoriteCount" (Prelude.Maybe Data.Int.Int32) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _XSource'postFavoriteCount
           (\ x__ y__ -> x__ {_XSource'postFavoriteCount = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField XSource "postViewCount" Data.Int.Int32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _XSource'postViewCount
           (\ x__ y__ -> x__ {_XSource'postViewCount = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField XSource "maybe'postViewCount" (Prelude.Maybe Data.Int.Int32) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _XSource'postViewCount
           (\ x__ y__ -> x__ {_XSource'postViewCount = y__}))
        Prelude.id
instance Data.ProtoLens.Message XSource where
  messageName _ = Data.Text.pack "xai_api.XSource"
  packedMessageDescriptor _
    = "\n\
      \\aXSource\DC2,\n\
      \\DC2included_x_handles\CAN\a \ETX(\tR\DLEincludedXHandles\DC2,\n\
      \\DC2excluded_x_handles\CAN\b \ETX(\tR\DLEexcludedXHandles\DC23\n\
      \\DC3post_favorite_count\CAN\t \SOH(\ENQH\NULR\DC1postFavoriteCount\136\SOH\SOH\DC2+\n\
      \\SIpost_view_count\CAN\n\
      \ \SOH(\ENQH\SOHR\rpostViewCount\136\SOH\SOHB\SYN\n\
      \\DC4_post_favorite_countB\DC2\n\
      \\DLE_post_view_countJ\EOT\b\ACK\DLE\a"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        includedXHandles__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "included_x_handles"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Unpacked
                 (Data.ProtoLens.Field.field @"includedXHandles")) ::
              Data.ProtoLens.FieldDescriptor XSource
        excludedXHandles__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "excluded_x_handles"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Unpacked
                 (Data.ProtoLens.Field.field @"excludedXHandles")) ::
              Data.ProtoLens.FieldDescriptor XSource
        postFavoriteCount__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "post_favorite_count"
              (Data.ProtoLens.ScalarField Data.ProtoLens.Int32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Int.Int32)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'postFavoriteCount")) ::
              Data.ProtoLens.FieldDescriptor XSource
        postViewCount__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "post_view_count"
              (Data.ProtoLens.ScalarField Data.ProtoLens.Int32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Int.Int32)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'postViewCount")) ::
              Data.ProtoLens.FieldDescriptor XSource
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 7, includedXHandles__field_descriptor),
           (Data.ProtoLens.Tag 8, excludedXHandles__field_descriptor),
           (Data.ProtoLens.Tag 9, postFavoriteCount__field_descriptor),
           (Data.ProtoLens.Tag 10, postViewCount__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _XSource'_unknownFields
        (\ x__ y__ -> x__ {_XSource'_unknownFields = y__})
  defMessage
    = XSource'_constructor
        {_XSource'includedXHandles = Data.Vector.Generic.empty,
         _XSource'excludedXHandles = Data.Vector.Generic.empty,
         _XSource'postFavoriteCount = Prelude.Nothing,
         _XSource'postViewCount = Prelude.Nothing,
         _XSource'_unknownFields = []}
  parseMessage
    = let
        loop ::
          XSource
          -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Vector Data.ProtoLens.Encoding.Growing.RealWorld Data.Text.Text
             -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Vector Data.ProtoLens.Encoding.Growing.RealWorld Data.Text.Text
                -> Data.ProtoLens.Encoding.Bytes.Parser XSource
        loop x mutable'excludedXHandles mutable'includedXHandles
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do frozen'excludedXHandles <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                                   (Data.ProtoLens.Encoding.Growing.unsafeFreeze
                                                      mutable'excludedXHandles)
                      frozen'includedXHandles <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                                   (Data.ProtoLens.Encoding.Growing.unsafeFreeze
                                                      mutable'includedXHandles)
                      (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t)
                           (Lens.Family2.set
                              (Data.ProtoLens.Field.field @"vec'excludedXHandles")
                              frozen'excludedXHandles
                              (Lens.Family2.set
                                 (Data.ProtoLens.Field.field @"vec'includedXHandles")
                                 frozen'includedXHandles x)))
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        58
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                            Data.ProtoLens.Encoding.Bytes.getText
                                              (Prelude.fromIntegral len))
                                        "included_x_handles"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append
                                          mutable'includedXHandles y)
                                loop x mutable'excludedXHandles v
                        66
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                            Data.ProtoLens.Encoding.Bytes.getText
                                              (Prelude.fromIntegral len))
                                        "excluded_x_handles"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append
                                          mutable'excludedXHandles y)
                                loop x v mutable'includedXHandles
                        72
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "post_favorite_count"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"postFavoriteCount") y x)
                                  mutable'excludedXHandles mutable'includedXHandles
                        80
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "post_view_count"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"postViewCount") y x)
                                  mutable'excludedXHandles mutable'includedXHandles
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
                                  mutable'excludedXHandles mutable'includedXHandles
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do mutable'excludedXHandles <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                            Data.ProtoLens.Encoding.Growing.new
              mutable'includedXHandles <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                            Data.ProtoLens.Encoding.Growing.new
              loop
                Data.ProtoLens.defMessage mutable'excludedXHandles
                mutable'includedXHandles)
          "XSource"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (Data.ProtoLens.Encoding.Bytes.foldMapBuilder
                (\ _v
                   -> (Data.Monoid.<>)
                        (Data.ProtoLens.Encoding.Bytes.putVarInt 58)
                        ((Prelude..)
                           (\ bs
                              -> (Data.Monoid.<>)
                                   (Data.ProtoLens.Encoding.Bytes.putVarInt
                                      (Prelude.fromIntegral (Data.ByteString.length bs)))
                                   (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                           Data.Text.Encoding.encodeUtf8 _v))
                (Lens.Family2.view
                   (Data.ProtoLens.Field.field @"vec'includedXHandles") _x))
             ((Data.Monoid.<>)
                (Data.ProtoLens.Encoding.Bytes.foldMapBuilder
                   (\ _v
                      -> (Data.Monoid.<>)
                           (Data.ProtoLens.Encoding.Bytes.putVarInt 66)
                           ((Prelude..)
                              (\ bs
                                 -> (Data.Monoid.<>)
                                      (Data.ProtoLens.Encoding.Bytes.putVarInt
                                         (Prelude.fromIntegral (Data.ByteString.length bs)))
                                      (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                              Data.Text.Encoding.encodeUtf8 _v))
                   (Lens.Family2.view
                      (Data.ProtoLens.Field.field @"vec'excludedXHandles") _x))
                ((Data.Monoid.<>)
                   (case
                        Lens.Family2.view
                          (Data.ProtoLens.Field.field @"maybe'postFavoriteCount") _x
                    of
                      Prelude.Nothing -> Data.Monoid.mempty
                      (Prelude.Just _v)
                        -> (Data.Monoid.<>)
                             (Data.ProtoLens.Encoding.Bytes.putVarInt 72)
                             ((Prelude..)
                                Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral _v))
                   ((Data.Monoid.<>)
                      (case
                           Lens.Family2.view
                             (Data.ProtoLens.Field.field @"maybe'postViewCount") _x
                       of
                         Prelude.Nothing -> Data.Monoid.mempty
                         (Prelude.Just _v)
                           -> (Data.Monoid.<>)
                                (Data.ProtoLens.Encoding.Bytes.putVarInt 80)
                                ((Prelude..)
                                   Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral _v))
                      (Data.ProtoLens.Encoding.Wire.buildFieldSet
                         (Lens.Family2.view Data.ProtoLens.unknownFields _x)))))
instance Control.DeepSeq.NFData XSource where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_XSource'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_XSource'includedXHandles x__)
                (Control.DeepSeq.deepseq
                   (_XSource'excludedXHandles x__)
                   (Control.DeepSeq.deepseq
                      (_XSource'postFavoriteCount x__)
                      (Control.DeepSeq.deepseq (_XSource'postViewCount x__) ()))))
data Chat = Chat {}
instance Data.ProtoLens.Service.Types.Service Chat where
  type ServiceName Chat = "Chat"
  type ServicePackage Chat = "xai_api"
  type ServiceMethods Chat = '["compactContext",
                               "deleteStoredCompletion",
                               "getCompletion",
                               "getCompletionChunk",
                               "getDeferredCompletion",
                               "getStoredCompletion",
                               "startDeferredCompletion"]
  packedServiceDescriptor _
    = "\n\
      \\EOTChat\DC2U\n\
      \\rGetCompletion\DC2\RS.xai_api.GetCompletionsRequest\SUB\".xai_api.GetChatCompletionResponse\"\NUL\DC2Y\n\
      \\DC2GetCompletionChunk\DC2\RS.xai_api.GetCompletionsRequest\SUB\US.xai_api.GetChatCompletionChunk\"\NUL0\SOH\DC2[\n\
      \\ETBStartDeferredCompletion\DC2\RS.xai_api.GetCompletionsRequest\SUB\RS.xai_api.StartDeferredResponse\"\NUL\DC2^\n\
      \\NAKGetDeferredCompletion\DC2\ESC.xai_api.GetDeferredRequest\SUB&.xai_api.GetDeferredCompletionResponse\"\NUL\DC2`\n\
      \\DC3GetStoredCompletion\DC2#.xai_api.GetStoredCompletionRequest\SUB\".xai_api.GetChatCompletionResponse\"\NUL\DC2k\n\
      \\SYNDeleteStoredCompletion\DC2&.xai_api.DeleteStoredCompletionRequest\SUB'.xai_api.DeleteStoredCompletionResponse\"\NUL\DC2S\n\
      \\SOCompactContext\DC2\RS.xai_api.CompactContextRequest\SUB\US.xai_api.CompactContextResponse\"\NUL"
instance Data.ProtoLens.Service.Types.HasMethodImpl Chat "getCompletion" where
  type MethodName Chat "getCompletion" = "GetCompletion"
  type MethodInput Chat "getCompletion" = GetCompletionsRequest
  type MethodOutput Chat "getCompletion" = GetChatCompletionResponse
  type MethodStreamingType Chat "getCompletion" = 'Data.ProtoLens.Service.Types.NonStreaming
instance Data.ProtoLens.Service.Types.HasMethodImpl Chat "getCompletionChunk" where
  type MethodName Chat "getCompletionChunk" = "GetCompletionChunk"
  type MethodInput Chat "getCompletionChunk" = GetCompletionsRequest
  type MethodOutput Chat "getCompletionChunk" = GetChatCompletionChunk
  type MethodStreamingType Chat "getCompletionChunk" = 'Data.ProtoLens.Service.Types.ServerStreaming
instance Data.ProtoLens.Service.Types.HasMethodImpl Chat "startDeferredCompletion" where
  type MethodName Chat "startDeferredCompletion" = "StartDeferredCompletion"
  type MethodInput Chat "startDeferredCompletion" = GetCompletionsRequest
  type MethodOutput Chat "startDeferredCompletion" = Proto.Xai.Api.V1.Deferred.StartDeferredResponse
  type MethodStreamingType Chat "startDeferredCompletion" = 'Data.ProtoLens.Service.Types.NonStreaming
instance Data.ProtoLens.Service.Types.HasMethodImpl Chat "getDeferredCompletion" where
  type MethodName Chat "getDeferredCompletion" = "GetDeferredCompletion"
  type MethodInput Chat "getDeferredCompletion" = Proto.Xai.Api.V1.Deferred.GetDeferredRequest
  type MethodOutput Chat "getDeferredCompletion" = GetDeferredCompletionResponse
  type MethodStreamingType Chat "getDeferredCompletion" = 'Data.ProtoLens.Service.Types.NonStreaming
instance Data.ProtoLens.Service.Types.HasMethodImpl Chat "getStoredCompletion" where
  type MethodName Chat "getStoredCompletion" = "GetStoredCompletion"
  type MethodInput Chat "getStoredCompletion" = GetStoredCompletionRequest
  type MethodOutput Chat "getStoredCompletion" = GetChatCompletionResponse
  type MethodStreamingType Chat "getStoredCompletion" = 'Data.ProtoLens.Service.Types.NonStreaming
instance Data.ProtoLens.Service.Types.HasMethodImpl Chat "deleteStoredCompletion" where
  type MethodName Chat "deleteStoredCompletion" = "DeleteStoredCompletion"
  type MethodInput Chat "deleteStoredCompletion" = DeleteStoredCompletionRequest
  type MethodOutput Chat "deleteStoredCompletion" = DeleteStoredCompletionResponse
  type MethodStreamingType Chat "deleteStoredCompletion" = 'Data.ProtoLens.Service.Types.NonStreaming
instance Data.ProtoLens.Service.Types.HasMethodImpl Chat "compactContext" where
  type MethodName Chat "compactContext" = "CompactContext"
  type MethodInput Chat "compactContext" = CompactContextRequest
  type MethodOutput Chat "compactContext" = CompactContextResponse
  type MethodStreamingType Chat "compactContext" = 'Data.ProtoLens.Service.Types.NonStreaming
packedFileDescriptor :: Data.ByteString.ByteString
packedFileDescriptor
  = "\n\
    \\NAKxai/api/v1/chat.proto\DC2\axai_api\SUB\USgoogle/protobuf/timestamp.proto\SUB\EMxai/api/v1/deferred.proto\SUB\SUBxai/api/v1/documents.proto\SUB\SYNxai/api/v1/image.proto\SUB\ETBxai/api/v1/sample.proto\SUB\SYNxai/api/v1/usage.proto\"\184\n\
    \\n\
    \\NAKGetCompletionsRequest\DC2,\n\
    \\bmessages\CAN\SOH \ETX(\v2\DLE.xai_api.MessageR\bmessages\DC2\DC4\n\
    \\ENQmodel\CAN\STX \SOH(\tR\ENQmodel\DC2\DC2\n\
    \\EOTuser\CAN\DLE \SOH(\tR\EOTuser\DC2\DC1\n\
    \\SOHn\CAN\b \SOH(\ENQH\NULR\SOHn\136\SOH\SOH\DC2\"\n\
    \\n\
    \max_tokens\CAN\a \SOH(\ENQH\SOHR\tmaxTokens\136\SOH\SOH\DC2\ETB\n\
    \\EOTseed\CAN\v \SOH(\ENQH\STXR\EOTseed\136\SOH\SOH\DC2\DC2\n\
    \\EOTstop\CAN\f \ETX(\tR\EOTstop\DC2%\n\
    \\vtemperature\CAN\SO \SOH(\STXH\ETXR\vtemperature\136\SOH\SOH\DC2\CAN\n\
    \\ENQtop_p\CAN\SI \SOH(\STXH\EOTR\EOTtopP\136\SOH\SOH\DC2\SUB\n\
    \\blogprobs\CAN\ENQ \SOH(\bR\blogprobs\DC2&\n\
    \\ftop_logprobs\CAN\ACK \SOH(\ENQH\ENQR\vtopLogprobs\136\SOH\SOH\DC2#\n\
    \\ENQtools\CAN\DC1 \ETX(\v2\r.xai_api.ToolR\ENQtools\DC24\n\
    \\vtool_choice\CAN\DC2 \SOH(\v2\DC3.xai_api.ToolChoiceR\n\
    \toolChoice\DC2@\n\
    \\SIresponse_format\CAN\n\
    \ \SOH(\v2\ETB.xai_api.ResponseFormatR\SOresponseFormat\DC20\n\
    \\DC1frequency_penalty\CAN\ETX \SOH(\STXH\ACKR\DLEfrequencyPenalty\136\SOH\SOH\DC2.\n\
    \\DLEpresence_penalty\CAN\t \SOH(\STXH\aR\SIpresencePenalty\136\SOH\SOH\DC2H\n\
    \\DLEreasoning_effort\CAN\DC3 \SOH(\SO2\CAN.xai_api.ReasoningEffortH\bR\SIreasoningEffort\136\SOH\SOH\DC2K\n\
    \\DC1search_parameters\CAN\DC4 \SOH(\v2\EM.xai_api.SearchParametersH\tR\DLEsearchParameters\136\SOH\SOH\DC23\n\
    \\DC3parallel_tool_calls\CAN\NAK \SOH(\bH\n\
    \R\DC1parallelToolCalls\136\SOH\SOH\DC25\n\
    \\DC4previous_response_id\CAN\SYN \SOH(\tH\vR\DC2previousResponseId\136\SOH\SOH\DC2%\n\
    \\SOstore_messages\CAN\ETB \SOH(\bR\rstoreMessages\DC22\n\
    \\NAKuse_encrypted_content\CAN\CAN \SOH(\bR\DC3useEncryptedContent\DC2 \n\
    \\tmax_turns\CAN\EM \SOH(\ENQH\fR\bmaxTurns\136\SOH\SOH\DC20\n\
    \\ainclude\CAN\SUB \ETX(\SO2\SYN.xai_api.IncludeOptionR\ainclude\DC29\n\
    \\vagent_count\CAN\GS \SOH(\SO2\DC3.xai_api.AgentCountH\rR\n\
    \agentCount\136\SOH\SOHB\EOT\n\
    \\STX_nB\r\n\
    \\v_max_tokensB\a\n\
    \\ENQ_seedB\SO\n\
    \\f_temperatureB\b\n\
    \\ACK_top_pB\SI\n\
    \\r_top_logprobsB\DC4\n\
    \\DC2_frequency_penaltyB\DC3\n\
    \\DC1_presence_penaltyB\DC3\n\
    \\DC1_reasoning_effortB\DC4\n\
    \\DC2_search_parametersB\SYN\n\
    \\DC4_parallel_tool_callsB\ETB\n\
    \\NAK_previous_response_idB\f\n\
    \\n\
    \_max_turnsB\SO\n\
    \\f_agent_countJ\EOT\b\EOT\DLE\ENQ\"\150\ETX\n\
    \\EMGetChatCompletionResponse\DC2\SO\n\
    \\STXid\CAN\SOH \SOH(\tR\STXid\DC23\n\
    \\aoutputs\CAN\STX \ETX(\v2\EM.xai_api.CompletionOutputR\aoutputs\DC24\n\
    \\acreated\CAN\ENQ \SOH(\v2\SUB.google.protobuf.TimestampR\acreated\DC2\DC4\n\
    \\ENQmodel\CAN\ACK \SOH(\tR\ENQmodel\DC2-\n\
    \\DC2system_fingerprint\CAN\a \SOH(\tR\DC1systemFingerprint\DC2,\n\
    \\ENQusage\CAN\t \SOH(\v2\SYN.xai_api.SamplingUsageR\ENQusage\DC2\FS\n\
    \\tcitations\CAN\n\
    \ \ETX(\tR\tcitations\DC24\n\
    \\bsettings\CAN\v \SOH(\v2\CAN.xai_api.RequestSettingsR\bsettings\DC27\n\
    \\fdebug_output\CAN\f \SOH(\v2\DC4.xai_api.DebugOutputR\vdebugOutput\"\226\STX\n\
    \\SYNGetChatCompletionChunk\DC2\SO\n\
    \\STXid\CAN\SOH \SOH(\tR\STXid\DC28\n\
    \\aoutputs\CAN\STX \ETX(\v2\RS.xai_api.CompletionOutputChunkR\aoutputs\DC24\n\
    \\acreated\CAN\ETX \SOH(\v2\SUB.google.protobuf.TimestampR\acreated\DC2\DC4\n\
    \\ENQmodel\CAN\EOT \SOH(\tR\ENQmodel\DC2-\n\
    \\DC2system_fingerprint\CAN\ENQ \SOH(\tR\DC1systemFingerprint\DC2,\n\
    \\ENQusage\CAN\ACK \SOH(\v2\SYN.xai_api.SamplingUsageR\ENQusage\DC2\FS\n\
    \\tcitations\CAN\a \ETX(\tR\tcitations\DC27\n\
    \\fdebug_output\CAN\n\
    \ \SOH(\v2\DC4.xai_api.DebugOutputR\vdebugOutput\"\162\SOH\n\
    \\GSGetDeferredCompletionResponse\DC2/\n\
    \\ACKstatus\CAN\STX \SOH(\SO2\ETB.xai_api.DeferredStatusR\ACKstatus\DC2C\n\
    \\bresponse\CAN\SOH \SOH(\v2\".xai_api.GetChatCompletionResponseH\NULR\bresponse\136\SOH\SOHB\v\n\
    \\t_response\"\201\SOH\n\
    \\DLECompletionOutput\DC2:\n\
    \\rfinish_reason\CAN\SOH \SOH(\SO2\NAK.xai_api.FinishReasonR\ffinishReason\DC2\DC4\n\
    \\ENQindex\CAN\STX \SOH(\ENQR\ENQindex\DC24\n\
    \\amessage\CAN\ETX \SOH(\v2\SUB.xai_api.CompletionMessageR\amessage\DC2-\n\
    \\blogprobs\CAN\EOT \SOH(\v2\DC1.xai_api.LogProbsR\blogprobs\"\154\STX\n\
    \\DC1CompletionMessage\DC2\CAN\n\
    \\acontent\CAN\SOH \SOH(\tR\acontent\DC2+\n\
    \\DC1reasoning_content\CAN\EOT \SOH(\tR\DLEreasoningContent\DC2(\n\
    \\EOTrole\CAN\STX \SOH(\SO2\DC4.xai_api.MessageRoleR\EOTrole\DC20\n\
    \\n\
    \tool_calls\CAN\ETX \ETX(\v2\DC1.xai_api.ToolCallR\ttoolCalls\DC2+\n\
    \\DC1encrypted_content\CAN\ENQ \SOH(\tR\DLEencryptedContent\DC25\n\
    \\tcitations\CAN\ACK \ETX(\v2\ETB.xai_api.InlineCitationR\tcitations\"\190\SOH\n\
    \\NAKCompletionOutputChunk\DC2$\n\
    \\ENQdelta\CAN\SOH \SOH(\v2\SO.xai_api.DeltaR\ENQdelta\DC2-\n\
    \\blogprobs\CAN\STX \SOH(\v2\DC1.xai_api.LogProbsR\blogprobs\DC2:\n\
    \\rfinish_reason\CAN\ETX \SOH(\SO2\NAK.xai_api.FinishReasonR\ffinishReason\DC2\DC4\n\
    \\ENQindex\CAN\EOT \SOH(\ENQR\ENQindex\"\142\STX\n\
    \\ENQDelta\DC2\CAN\n\
    \\acontent\CAN\SOH \SOH(\tR\acontent\DC2+\n\
    \\DC1reasoning_content\CAN\EOT \SOH(\tR\DLEreasoningContent\DC2(\n\
    \\EOTrole\CAN\STX \SOH(\SO2\DC4.xai_api.MessageRoleR\EOTrole\DC20\n\
    \\n\
    \tool_calls\CAN\ETX \ETX(\v2\DC1.xai_api.ToolCallR\ttoolCalls\DC2+\n\
    \\DC1encrypted_content\CAN\ENQ \SOH(\tR\DLEencryptedContent\DC25\n\
    \\tcitations\CAN\ACK \ETX(\v2\ETB.xai_api.InlineCitationR\tcitations\"\173\STX\n\
    \\SOInlineCitation\DC2\SO\n\
    \\STXid\CAN\SOH \SOH(\tR\STXid\DC2\US\n\
    \\vstart_index\CAN\STX \SOH(\ENQR\n\
    \startIndex\DC2\ESC\n\
    \\tend_index\CAN\ACK \SOH(\ENQR\bendIndex\DC29\n\
    \\fweb_citation\CAN\ETX \SOH(\v2\DC4.xai_api.WebCitationH\NULR\vwebCitation\DC23\n\
    \\n\
    \x_citation\CAN\EOT \SOH(\v2\DC2.xai_api.XCitationH\NULR\txCitation\DC2Q\n\
    \\DC4collections_citation\CAN\ENQ \SOH(\v2\FS.xai_api.CollectionsCitationH\NULR\DC3collectionsCitationB\n\
    \\n\
    \\bcitation\"\US\n\
    \\vWebCitation\DC2\DLE\n\
    \\ETXurl\CAN\SOH \SOH(\tR\ETXurl\"\GS\n\
    \\tXCitation\DC2\DLE\n\
    \\ETXurl\CAN\SOH \SOH(\tR\ETXurl\"\171\SOH\n\
    \\DC3CollectionsCitation\DC2\ETB\n\
    \\afile_id\CAN\SOH \SOH(\tR\ACKfileId\DC2\EM\n\
    \\bchunk_id\CAN\STX \SOH(\tR\achunkId\DC2#\n\
    \\rchunk_content\CAN\ETX \SOH(\tR\fchunkContent\DC2\DC4\n\
    \\ENQscore\CAN\EOT \SOH(\STXR\ENQscore\DC2%\n\
    \\SOcollection_ids\CAN\ENQ \ETX(\tR\rcollectionIds\"6\n\
    \\bLogProbs\DC2*\n\
    \\acontent\CAN\SOH \ETX(\v2\DLE.xai_api.LogProbR\acontent\"\135\SOH\n\
    \\aLogProb\DC2\DC4\n\
    \\ENQtoken\CAN\SOH \SOH(\tR\ENQtoken\DC2\CAN\n\
    \\alogprob\CAN\STX \SOH(\STXR\alogprob\DC2\DC4\n\
    \\ENQbytes\CAN\ETX \SOH(\fR\ENQbytes\DC26\n\
    \\ftop_logprobs\CAN\EOT \ETX(\v2\DC3.xai_api.TopLogProbR\vtopLogprobs\"R\n\
    \\n\
    \TopLogProb\DC2\DC4\n\
    \\ENQtoken\CAN\SOH \SOH(\tR\ENQtoken\DC2\CAN\n\
    \\alogprob\CAN\STX \SOH(\STXR\alogprob\DC2\DC4\n\
    \\ENQbytes\CAN\ETX \SOH(\fR\ENQbytes\"\143\SOH\n\
    \\aContent\DC2\DC4\n\
    \\EOTtext\CAN\SOH \SOH(\tH\NULR\EOTtext\DC27\n\
    \\timage_url\CAN\STX \SOH(\v2\CAN.xai_api.ImageUrlContentH\NULR\bimageUrl\DC2*\n\
    \\EOTfile\CAN\ETX \SOH(\v2\DC4.xai_api.FileContentH\NULR\EOTfileB\t\n\
    \\acontent\"\133\SOH\n\
    \\vFileContent\DC2\ETB\n\
    \\afile_id\CAN\SOH \SOH(\tR\ACKfileId\DC2\DC2\n\
    \\EOTdata\CAN\STX \SOH(\fR\EOTdata\DC2\SUB\n\
    \\bfilename\CAN\ETX \SOH(\tR\bfilename\DC2\ESC\n\
    \\tmime_type\CAN\EOT \SOH(\tR\bmimeType\DC2\DLE\n\
    \\ETXurl\CAN\ENQ \SOH(\tR\ETXurl\"\210\STX\n\
    \\aMessage\DC2*\n\
    \\acontent\CAN\SOH \ETX(\v2\DLE.xai_api.ContentR\acontent\DC20\n\
    \\DC1reasoning_content\CAN\ENQ \SOH(\tH\NULR\DLEreasoningContent\136\SOH\SOH\DC2(\n\
    \\EOTrole\CAN\STX \SOH(\SO2\DC4.xai_api.MessageRoleR\EOTrole\DC2\DC2\n\
    \\EOTname\CAN\ETX \SOH(\tR\EOTname\DC20\n\
    \\n\
    \tool_calls\CAN\EOT \ETX(\v2\DC1.xai_api.ToolCallR\ttoolCalls\DC2+\n\
    \\DC1encrypted_content\CAN\ACK \SOH(\tR\DLEencryptedContent\DC2%\n\
    \\ftool_call_id\CAN\a \SOH(\tH\SOHR\n\
    \toolCallId\136\SOH\SOHB\DC4\n\
    \\DC2_reasoning_contentB\SI\n\
    \\r_tool_call_id\"k\n\
    \\n\
    \ToolChoice\DC2'\n\
    \\EOTmode\CAN\SOH \SOH(\SO2\DC1.xai_api.ToolModeH\NULR\EOTmode\DC2%\n\
    \\rfunction_name\CAN\STX \SOH(\tH\NULR\ffunctionNameB\r\n\
    \\vtool_choice\"\157\ETX\n\
    \\EOTTool\DC2/\n\
    \\bfunction\CAN\SOH \SOH(\v2\DC1.xai_api.FunctionH\NULR\bfunction\DC23\n\
    \\n\
    \web_search\CAN\ETX \SOH(\v2\DC2.xai_api.WebSearchH\NULR\twebSearch\DC2-\n\
    \\bx_search\CAN\EOT \SOH(\v2\DLE.xai_api.XSearchH\NULR\axSearch\DC2?\n\
    \\SOcode_execution\CAN\ENQ \SOH(\v2\SYN.xai_api.CodeExecutionH\NULR\rcodeExecution\DC2K\n\
    \\DC2collections_search\CAN\ACK \SOH(\v2\SUB.xai_api.CollectionsSearchH\NULR\DC1collectionsSearch\DC2 \n\
    \\ETXmcp\CAN\a \SOH(\v2\f.xai_api.MCPH\NULR\ETXmcp\DC2H\n\
    \\DC1attachment_search\CAN\b \SOH(\v2\EM.xai_api.AttachmentSearchH\NULR\DLEattachmentSearchB\ACK\n\
    \\EOTtool\"\231\STX\n\
    \\ETXMCP\DC2!\n\
    \\fserver_label\CAN\SOH \SOH(\tR\vserverLabel\DC2-\n\
    \\DC2server_description\CAN\STX \SOH(\tR\DC1serverDescription\DC2\GS\n\
    \\n\
    \server_url\CAN\ETX \SOH(\tR\tserverUrl\DC2,\n\
    \\DC2allowed_tool_names\CAN\EOT \ETX(\tR\DLEallowedToolNames\DC2)\n\
    \\rauthorization\CAN\ENQ \SOH(\tH\NULR\rauthorization\136\SOH\SOH\DC2C\n\
    \\rextra_headers\CAN\ACK \ETX(\v2\RS.xai_api.MCP.ExtraHeadersEntryR\fextraHeaders\SUB?\n\
    \\DC1ExtraHeadersEntry\DC2\DLE\n\
    \\ETXkey\CAN\SOH \SOH(\tR\ETXkey\DC2\DC4\n\
    \\ENQvalue\CAN\STX \SOH(\tR\ENQvalue:\STX8\SOHB\DLE\n\
    \\SO_authorization\"\234\STX\n\
    \\tWebSearch\DC2)\n\
    \\DLEexcluded_domains\CAN\SOH \ETX(\tR\SIexcludedDomains\DC2'\n\
    \\SIallowed_domains\CAN\STX \ETX(\tR\SOallowedDomains\DC2A\n\
    \\SUBenable_image_understanding\CAN\ETX \SOH(\bH\NULR\CANenableImageUnderstanding\136\SOH\SOH\DC2H\n\
    \\ruser_location\CAN\EOT \SOH(\v2\RS.xai_api.WebSearchUserLocationH\SOHR\fuserLocation\136\SOH\SOH\DC23\n\
    \\DC3enable_image_search\CAN\ENQ \SOH(\bH\STXR\DC1enableImageSearch\136\SOH\SOHB\GS\n\
    \\ESC_enable_image_understandingB\DLE\n\
    \\SO_user_locationB\SYN\n\
    \\DC4_enable_image_search\"\186\SOH\n\
    \\NAKWebSearchUserLocation\DC2\GS\n\
    \\acountry\CAN\SOH \SOH(\tH\NULR\acountry\136\SOH\SOH\DC2\ETB\n\
    \\EOTcity\CAN\STX \SOH(\tH\SOHR\EOTcity\136\SOH\SOH\DC2\ESC\n\
    \\ACKregion\CAN\ETX \SOH(\tH\STXR\ACKregion\136\SOH\SOH\DC2\US\n\
    \\btimezone\CAN\EOT \SOH(\tH\ETXR\btimezone\136\SOH\SOHB\n\
    \\n\
    \\b_countryB\a\n\
    \\ENQ_cityB\t\n\
    \\a_regionB\v\n\
    \\t_timezone\"\185\ETX\n\
    \\aXSearch\DC2<\n\
    \\tfrom_date\CAN\SOH \SOH(\v2\SUB.google.protobuf.TimestampH\NULR\bfromDate\136\SOH\SOH\DC28\n\
    \\ato_date\CAN\STX \SOH(\v2\SUB.google.protobuf.TimestampH\SOHR\ACKtoDate\136\SOH\SOH\DC2*\n\
    \\DC1allowed_x_handles\CAN\ETX \ETX(\tR\SIallowedXHandles\DC2,\n\
    \\DC2excluded_x_handles\CAN\EOT \ETX(\tR\DLEexcludedXHandles\DC2A\n\
    \\SUBenable_image_understanding\CAN\ENQ \SOH(\bH\STXR\CANenableImageUnderstanding\136\SOH\SOH\DC2A\n\
    \\SUBenable_video_understanding\CAN\ACK \SOH(\bH\ETXR\CANenableVideoUnderstanding\136\SOH\SOHB\f\n\
    \\n\
    \_from_dateB\n\
    \\n\
    \\b_to_dateB\GS\n\
    \\ESC_enable_image_understandingB\GS\n\
    \\ESC_enable_video_understanding\"\SI\n\
    \\rCodeExecution\"\137\ETX\n\
    \\DC1CollectionsSearch\DC2%\n\
    \\SOcollection_ids\CAN\SOH \ETX(\tR\rcollectionIds\DC2\EM\n\
    \\ENQlimit\CAN\STX \SOH(\ENQH\SOHR\ENQlimit\136\SOH\SOH\DC2'\n\
    \\finstructions\CAN\ETX \SOH(\tH\STXR\finstructions\136\SOH\SOH\DC2E\n\
    \\DLEhybrid_retrieval\CAN\EOT \SOH(\v2\CAN.xai_api.HybridRetrievalH\NULR\SIhybridRetrieval\DC2K\n\
    \\DC2semantic_retrieval\CAN\ENQ \SOH(\v2\SUB.xai_api.SemanticRetrievalH\NULR\DC1semanticRetrieval\DC2H\n\
    \\DC1keyword_retrieval\CAN\ACK \SOH(\v2\EM.xai_api.KeywordRetrievalH\NULR\DLEkeywordRetrievalB\DLE\n\
    \\SOretrieval_modeB\b\n\
    \\ACK_limitB\SI\n\
    \\r_instructions\"7\n\
    \\DLEAttachmentSearch\DC2\EM\n\
    \\ENQlimit\CAN\STX \SOH(\ENQH\NULR\ENQlimit\136\SOH\SOHB\b\n\
    \\ACK_limit\"x\n\
    \\bFunction\DC2\DC2\n\
    \\EOTname\CAN\SOH \SOH(\tR\EOTname\DC2 \n\
    \\vdescription\CAN\STX \SOH(\tR\vdescription\DC2\SYN\n\
    \\ACKstrict\CAN\ETX \SOH(\bR\ACKstrict\DC2\RS\n\
    \\n\
    \parameters\CAN\EOT \SOH(\tR\n\
    \parameters\"\239\SOH\n\
    \\bToolCall\DC2\SO\n\
    \\STXid\CAN\SOH \SOH(\tR\STXid\DC2)\n\
    \\EOTtype\CAN\STX \SOH(\SO2\NAK.xai_api.ToolCallTypeR\EOTtype\DC2/\n\
    \\ACKstatus\CAN\ETX \SOH(\SO2\ETB.xai_api.ToolCallStatusR\ACKstatus\DC2(\n\
    \\rerror_message\CAN\EOT \SOH(\tH\SOHR\ferrorMessage\136\SOH\SOH\DC23\n\
    \\bfunction\CAN\n\
    \ \SOH(\v2\NAK.xai_api.FunctionCallH\NULR\bfunctionB\ACK\n\
    \\EOTtoolB\DLE\n\
    \\SO_error_message\"@\n\
    \\fFunctionCall\DC2\DC2\n\
    \\EOTname\CAN\SOH \SOH(\tR\EOTname\DC2\FS\n\
    \\targuments\CAN\STX \SOH(\tR\targuments\"n\n\
    \\SOResponseFormat\DC24\n\
    \\vformat_type\CAN\SOH \SOH(\SO2\DC3.xai_api.FormatTypeR\n\
    \formatType\DC2\ESC\n\
    \\ACKschema\CAN\STX \SOH(\tH\NULR\ACKschema\136\SOH\SOHB\t\n\
    \\a_schema\"\201\STX\n\
    \\DLESearchParameters\DC2'\n\
    \\EOTmode\CAN\SOH \SOH(\SO2\DC3.xai_api.SearchModeR\EOTmode\DC2)\n\
    \\asources\CAN\t \ETX(\v2\SI.xai_api.SourceR\asources\DC27\n\
    \\tfrom_date\CAN\EOT \SOH(\v2\SUB.google.protobuf.TimestampR\bfromDate\DC23\n\
    \\ato_date\CAN\ENQ \SOH(\v2\SUB.google.protobuf.TimestampR\ACKtoDate\DC2)\n\
    \\DLEreturn_citations\CAN\a \SOH(\bR\SIreturnCitations\DC21\n\
    \\DC2max_search_results\CAN\b \SOH(\ENQH\NULR\DLEmaxSearchResults\136\SOH\SOHB\NAK\n\
    \\DC3_max_search_results\"\175\SOH\n\
    \\ACKSource\DC2&\n\
    \\ETXweb\CAN\SOH \SOH(\v2\DC2.xai_api.WebSourceH\NULR\ETXweb\DC2)\n\
    \\EOTnews\CAN\STX \SOH(\v2\DC3.xai_api.NewsSourceH\NULR\EOTnews\DC2 \n\
    \\SOHx\CAN\ETX \SOH(\v2\DLE.xai_api.XSourceH\NULR\SOHx\DC2&\n\
    \\ETXrss\CAN\EOT \SOH(\v2\DC2.xai_api.RssSourceH\NULR\ETXrssB\b\n\
    \\ACKsource\"\175\SOH\n\
    \\tWebSource\DC2+\n\
    \\DC1excluded_websites\CAN\STX \ETX(\tR\DLEexcludedWebsites\DC2)\n\
    \\DLEallowed_websites\CAN\ENQ \ETX(\tR\SIallowedWebsites\DC2\GS\n\
    \\acountry\CAN\ETX \SOH(\tH\NULR\acountry\136\SOH\SOH\DC2\US\n\
    \\vsafe_search\CAN\EOT \SOH(\bR\n\
    \safeSearchB\n\
    \\n\
    \\b_country\"\133\SOH\n\
    \\n\
    \NewsSource\DC2+\n\
    \\DC1excluded_websites\CAN\STX \ETX(\tR\DLEexcludedWebsites\DC2\GS\n\
    \\acountry\CAN\ETX \SOH(\tH\NULR\acountry\136\SOH\SOH\DC2\US\n\
    \\vsafe_search\CAN\EOT \SOH(\bR\n\
    \safeSearchB\n\
    \\n\
    \\b_country\"\249\SOH\n\
    \\aXSource\DC2,\n\
    \\DC2included_x_handles\CAN\a \ETX(\tR\DLEincludedXHandles\DC2,\n\
    \\DC2excluded_x_handles\CAN\b \ETX(\tR\DLEexcludedXHandles\DC23\n\
    \\DC3post_favorite_count\CAN\t \SOH(\ENQH\NULR\DC1postFavoriteCount\136\SOH\SOH\DC2+\n\
    \\SIpost_view_count\CAN\n\
    \ \SOH(\ENQH\SOHR\rpostViewCount\136\SOH\SOHB\SYN\n\
    \\DC4_post_favorite_countB\DC2\n\
    \\DLE_post_view_countJ\EOT\b\ACK\DLE\a\"!\n\
    \\tRssSource\DC2\DC4\n\
    \\ENQlinks\CAN\SOH \ETX(\tR\ENQlinks\"\159\ACK\n\
    \\SIRequestSettings\DC2\"\n\
    \\n\
    \max_tokens\CAN\SOH \SOH(\ENQH\NULR\tmaxTokens\136\SOH\SOH\DC2.\n\
    \\DC3parallel_tool_calls\CAN\STX \SOH(\bR\DC1parallelToolCalls\DC25\n\
    \\DC4previous_response_id\CAN\ETX \SOH(\tH\SOHR\DC2previousResponseId\136\SOH\SOH\DC2H\n\
    \\DLEreasoning_effort\CAN\EOT \SOH(\SO2\CAN.xai_api.ReasoningEffortH\STXR\SIreasoningEffort\136\SOH\SOH\DC2%\n\
    \\vtemperature\CAN\ENQ \SOH(\STXH\ETXR\vtemperature\136\SOH\SOH\DC2@\n\
    \\SIresponse_format\CAN\ACK \SOH(\v2\ETB.xai_api.ResponseFormatR\SOresponseFormat\DC24\n\
    \\vtool_choice\CAN\a \SOH(\v2\DC3.xai_api.ToolChoiceR\n\
    \toolChoice\DC2#\n\
    \\ENQtools\CAN\b \ETX(\v2\r.xai_api.ToolR\ENQtools\DC2\CAN\n\
    \\ENQtop_p\CAN\t \SOH(\STXH\EOTR\EOTtopP\136\SOH\SOH\DC2\DC2\n\
    \\EOTuser\CAN\n\
    \ \SOH(\tR\EOTuser\DC2K\n\
    \\DC1search_parameters\CAN\v \SOH(\v2\EM.xai_api.SearchParametersH\ENQR\DLEsearchParameters\136\SOH\SOH\DC2%\n\
    \\SOstore_messages\CAN\f \SOH(\bR\rstoreMessages\DC22\n\
    \\NAKuse_encrypted_content\CAN\r \SOH(\bR\DC3useEncryptedContent\DC20\n\
    \\ainclude\CAN\SO \ETX(\SO2\SYN.xai_api.IncludeOptionR\aincludeB\r\n\
    \\v_max_tokensB\ETB\n\
    \\NAK_previous_response_idB\DC3\n\
    \\DC1_reasoning_effortB\SO\n\
    \\f_temperatureB\b\n\
    \\ACK_top_pB\DC4\n\
    \\DC2_search_parameters\"=\n\
    \\SUBGetStoredCompletionRequest\DC2\US\n\
    \\vresponse_id\CAN\SOH \SOH(\tR\n\
    \responseId\"@\n\
    \\GSDeleteStoredCompletionRequest\DC2\US\n\
    \\vresponse_id\CAN\SOH \SOH(\tR\n\
    \responseId\"A\n\
    \\RSDeleteStoredCompletionResponse\DC2\US\n\
    \\vresponse_id\CAN\SOH \SOH(\tR\n\
    \responseId\"\186\ETX\n\
    \\vDebugOutput\DC2\SUB\n\
    \\battempts\CAN\SOH \SOH(\ENQR\battempts\DC2\CAN\n\
    \\arequest\CAN\STX \SOH(\tR\arequest\DC2\SYN\n\
    \\ACKprompt\CAN\ETX \SOH(\tR\ACKprompt\DC2%\n\
    \\SOengine_request\CAN\t \SOH(\tR\rengineRequest\DC2\FS\n\
    \\tresponses\CAN\EOT \ETX(\tR\tresponses\DC2\SYN\n\
    \\ACKchunks\CAN\f \ETX(\tR\ACKchunks\DC2(\n\
    \\DLEcache_read_count\CAN\ENQ \SOH(\rR\SOcacheReadCount\DC23\n\
    \\SYNcache_read_input_bytes\CAN\ACK \SOH(\EOTR\DC3cacheReadInputBytes\DC2*\n\
    \\DC1cache_write_count\CAN\a \SOH(\rR\SIcacheWriteCount\DC25\n\
    \\ETBcache_write_input_bytes\CAN\b \SOH(\EOTR\DC4cacheWriteInputBytes\DC2\GS\n\
    \\n\
    \lb_address\CAN\n\
    \ \SOH(\tR\tlbAddress\DC2\US\n\
    \\vsampler_tag\CAN\v \SOH(\tR\n\
    \samplerTag\"U\n\
    \\NAKCompactContextRequest\DC2\DC4\n\
    \\ENQmodel\CAN\SOH \SOH(\tR\ENQmodel\DC2&\n\
    \\ENQinput\CAN\STX \ETX(\v2\DLE.xai_api.MessageR\ENQinput\"\183\SOH\n\
    \\SYNCompactContextResponse\DC2\SO\n\
    \\STXid\CAN\SOH \SOH(\tR\STXid\DC2+\n\
    \\DC1encrypted_content\CAN\STX \SOH(\tR\DLEencryptedContent\DC22\n\
    \\NAKdropped_message_count\CAN\ETX \SOH(\rR\DC3droppedMessageCount\DC2,\n\
    \\ENQusage\CAN\EOT \SOH(\v2\SYN.xai_api.SamplingUsageR\ENQusage*\130\ETX\n\
    \\rIncludeOption\DC2\SUB\n\
    \\SYNINCLUDE_OPTION_INVALID\DLE\NUL\DC2)\n\
    \%INCLUDE_OPTION_WEB_SEARCH_CALL_OUTPUT\DLE\SOH\DC2'\n\
    \#INCLUDE_OPTION_X_SEARCH_CALL_OUTPUT\DLE\STX\DC2-\n\
    \)INCLUDE_OPTION_CODE_EXECUTION_CALL_OUTPUT\DLE\ETX\DC21\n\
    \-INCLUDE_OPTION_COLLECTIONS_SEARCH_CALL_OUTPUT\DLE\EOT\DC20\n\
    \,INCLUDE_OPTION_ATTACHMENT_SEARCH_CALL_OUTPUT\DLE\ENQ\DC2\"\n\
    \\RSINCLUDE_OPTION_MCP_CALL_OUTPUT\DLE\ACK\DC2#\n\
    \\USINCLUDE_OPTION_INLINE_CITATIONS\DLE\a\DC2$\n\
    \ INCLUDE_OPTION_VERBOSE_STREAMING\DLE\b*\141\SOH\n\
    \\vMessageRole\DC2\DLE\n\
    \\fINVALID_ROLE\DLE\NUL\DC2\r\n\
    \\tROLE_USER\DLE\SOH\DC2\DC2\n\
    \\SOROLE_ASSISTANT\DLE\STX\DC2\SI\n\
    \\vROLE_SYSTEM\DLE\ETX\DC2\NAK\n\
    \\rROLE_FUNCTION\DLE\EOT\SUB\STX\b\SOH\DC2\r\n\
    \\tROLE_TOOL\DLE\ENQ\DC2\DC2\n\
    \\SOROLE_DEVELOPER\DLE\ACK*j\n\
    \\SIReasoningEffort\DC2\DC2\n\
    \\SOINVALID_EFFORT\DLE\NUL\DC2\SO\n\
    \\n\
    \EFFORT_LOW\DLE\SOH\DC2\DC1\n\
    \\rEFFORT_MEDIUM\DLE\STX\DC2\SI\n\
    \\vEFFORT_HIGH\DLE\ETX\DC2\SI\n\
    \\vEFFORT_NONE\DLE\EOT*P\n\
    \\n\
    \AgentCount\DC2\ESC\n\
    \\ETBAGENT_COUNT_UNSPECIFIED\DLE\NUL\DC2\DC1\n\
    \\rAGENT_COUNT_4\DLE\SOH\DC2\DC2\n\
    \\SOAGENT_COUNT_16\DLE\STX*a\n\
    \\bToolMode\DC2\NAK\n\
    \\DC1TOOL_MODE_INVALID\DLE\NUL\DC2\DC2\n\
    \\SOTOOL_MODE_AUTO\DLE\SOH\DC2\DC2\n\
    \\SOTOOL_MODE_NONE\DLE\STX\DC2\SYN\n\
    \\DC2TOOL_MODE_REQUIRED\DLE\ETX*u\n\
    \\n\
    \FormatType\DC2\ETB\n\
    \\DC3FORMAT_TYPE_INVALID\DLE\NUL\DC2\DC4\n\
    \\DLEFORMAT_TYPE_TEXT\DLE\SOH\DC2\ESC\n\
    \\ETBFORMAT_TYPE_JSON_OBJECT\DLE\STX\DC2\ESC\n\
    \\ETBFORMAT_TYPE_JSON_SCHEMA\DLE\ETX*\177\STX\n\
    \\fToolCallType\DC2\SUB\n\
    \\SYNTOOL_CALL_TYPE_INVALID\DLE\NUL\DC2#\n\
    \\USTOOL_CALL_TYPE_CLIENT_SIDE_TOOL\DLE\SOH\DC2\"\n\
    \\RSTOOL_CALL_TYPE_WEB_SEARCH_TOOL\DLE\STX\DC2 \n\
    \\FSTOOL_CALL_TYPE_X_SEARCH_TOOL\DLE\ETX\DC2&\n\
    \\"TOOL_CALL_TYPE_CODE_EXECUTION_TOOL\DLE\EOT\DC2*\n\
    \&TOOL_CALL_TYPE_COLLECTIONS_SEARCH_TOOL\DLE\ENQ\DC2\ESC\n\
    \\ETBTOOL_CALL_TYPE_MCP_TOOL\DLE\ACK\DC2)\n\
    \%TOOL_CALL_TYPE_ATTACHMENT_SEARCH_TOOL\DLE\a*\144\SOH\n\
    \\SOToolCallStatus\DC2 \n\
    \\FSTOOL_CALL_STATUS_IN_PROGRESS\DLE\NUL\DC2\RS\n\
    \\SUBTOOL_CALL_STATUS_COMPLETED\DLE\SOH\DC2\US\n\
    \\ESCTOOL_CALL_STATUS_INCOMPLETE\DLE\STX\DC2\ESC\n\
    \\ETBTOOL_CALL_STATUS_FAILED\DLE\ETX*d\n\
    \\n\
    \SearchMode\DC2\ETB\n\
    \\DC3INVALID_SEARCH_MODE\DLE\NUL\DC2\DC3\n\
    \\SIOFF_SEARCH_MODE\DLE\SOH\DC2\DC2\n\
    \\SOON_SEARCH_MODE\DLE\STX\DC2\DC4\n\
    \\DLEAUTO_SEARCH_MODE\DLE\ETX2\153\ENQ\n\
    \\EOTChat\DC2U\n\
    \\rGetCompletion\DC2\RS.xai_api.GetCompletionsRequest\SUB\".xai_api.GetChatCompletionResponse\"\NUL\DC2Y\n\
    \\DC2GetCompletionChunk\DC2\RS.xai_api.GetCompletionsRequest\SUB\US.xai_api.GetChatCompletionChunk\"\NUL0\SOH\DC2[\n\
    \\ETBStartDeferredCompletion\DC2\RS.xai_api.GetCompletionsRequest\SUB\RS.xai_api.StartDeferredResponse\"\NUL\DC2^\n\
    \\NAKGetDeferredCompletion\DC2\ESC.xai_api.GetDeferredRequest\SUB&.xai_api.GetDeferredCompletionResponse\"\NUL\DC2`\n\
    \\DC3GetStoredCompletion\DC2#.xai_api.GetStoredCompletionRequest\SUB\".xai_api.GetChatCompletionResponse\"\NUL\DC2k\n\
    \\SYNDeleteStoredCompletion\DC2&.xai_api.DeleteStoredCompletionRequest\SUB'.xai_api.DeleteStoredCompletionResponse\"\NUL\DC2S\n\
    \\SOCompactContext\DC2\RS.xai_api.CompactContextRequest\SUB\US.xai_api.CompactContextResponse\"\NULJ\159\137\ETX\n\
    \\a\DC2\ENQ\NUL\NUL\143\t\SOH\n\
    \\b\n\
    \\SOH\f\DC2\ETX\NUL\NUL\DC2\n\
    \\b\n\
    \\SOH\STX\DC2\ETX\STX\NUL\DLE\n\
    \\t\n\
    \\STX\ETX\NUL\DC2\ETX\EOT\NUL)\n\
    \\t\n\
    \\STX\ETX\SOH\DC2\ETX\ENQ\NUL#\n\
    \\t\n\
    \\STX\ETX\STX\DC2\ETX\ACK\NUL$\n\
    \\t\n\
    \\STX\ETX\ETX\DC2\ETX\a\NUL \n\
    \\t\n\
    \\STX\ETX\EOT\DC2\ETX\b\NUL!\n\
    \\t\n\
    \\STX\ETX\ENQ\DC2\ETX\t\NUL \n\
    \K\n\
    \\STX\ACK\NUL\DC2\EOT\f\NUL(\SOH\SUB? An API that exposes our language models via a Chat interface.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\ACK\NUL\SOH\DC2\ETX\f\b\f\n\
    \i\n\
    \\EOT\ACK\NUL\STX\NUL\DC2\ETX\SI\STXQ\SUB\\ Samples a response from the model and blocks until the response has been\n\
    \ fully generated.\n\
    \\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\NUL\SOH\DC2\ETX\SI\ACK\DC3\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\NUL\STX\DC2\ETX\SI\DC4)\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\NUL\ETX\DC2\ETX\SI4M\n\
    \o\n\
    \\EOT\ACK\NUL\STX\SOH\DC2\ETX\DC3\STXZ\SUBb Samples a response from the model and streams out the model tokens as they\n\
    \ are being generated.\n\
    \\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\SOH\SOH\DC2\ETX\DC3\ACK\CAN\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\SOH\STX\DC2\ETX\DC3\EM.\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\SOH\ACK\DC2\ETX\DC39?\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\SOH\ETX\DC2\ETX\DC3@V\n\
    \\174\SOH\n\
    \\EOT\ACK\NUL\STX\STX\DC2\ETX\CAN\STXW\SUB\160\SOH Starts sampling of the model and immediately returns a response containing\n\
    \ a request id. The request id may be used to poll\n\
    \ the `GetDeferredCompletion` RPC.\n\
    \\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\STX\SOH\DC2\ETX\CAN\ACK\GS\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\STX\STX\DC2\ETX\CAN\RS3\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\STX\ETX\DC2\ETX\CAN>S\n\
    \e\n\
    \\EOT\ACK\NUL\STX\ETX\DC2\ETX\ESC\STXZ\SUBX Gets the result of a deferred completion started by calling `StartDeferredCompletion`.\n\
    \\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\ETX\SOH\DC2\ETX\ESC\ACK\ESC\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\ETX\STX\DC2\ETX\ESC\FS.\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\ETX\ETX\DC2\ETX\ESC9V\n\
    \@\n\
    \\EOT\ACK\NUL\STX\EOT\DC2\ETX\RS\STX\\\SUB3 Retrieve a stored response using the response ID.\n\
    \\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\EOT\SOH\DC2\ETX\RS\ACK\EM\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\EOT\STX\DC2\ETX\RS\SUB4\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\EOT\ETX\DC2\ETX\RS?X\n\
    \>\n\
    \\EOT\ACK\NUL\STX\ENQ\DC2\ETX!\STXg\SUB1 Delete a stored response using the response ID.\n\
    \\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\ENQ\SOH\DC2\ETX!\ACK\FS\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\ENQ\STX\DC2\ETX!\GS:\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\ENQ\ETX\DC2\ETX!Ec\n\
    \\249\SOH\n\
    \\EOT\ACK\NUL\STX\ACK\DC2\ETX'\STXO\SUB\235\SOH Compacts a full input context and returns a compacted context.\n\
    \ The client sends the current input items and receives back a compacted\n\
    \ set of items (with an opaque compaction blob) suitable for use as\n\
    \ the input to the next request.\n\
    \\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\ACK\SOH\DC2\ETX'\ACK\DC4\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\ACK\STX\DC2\ETX'\NAK*\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\ACK\ETX\DC2\ETX'5K\n\
    \\v\n\
    \\STX\EOT\NUL\DC2\ENQ*\NUL\177\SOH\SOH\n\
    \\n\
    \\n\
    \\ETX\EOT\NUL\SOH\DC2\ETX*\b\GS\n\
    \\n\
    \\n\
    \\ETX\EOT\NUL\t\DC2\ETX+\STX\r\n\
    \\v\n\
    \\EOT\EOT\NUL\t\NUL\DC2\ETX+\v\f\n\
    \\f\n\
    \\ENQ\EOT\NUL\t\NUL\SOH\DC2\ETX+\v\f\n\
    \\f\n\
    \\ENQ\EOT\NUL\t\NUL\STX\DC2\ETX+\v\f\n\
    \\130\SOH\n\
    \\EOT\EOT\NUL\STX\NUL\DC2\ETX/\STX \SUBu A sequence of messages in the conversation. There must be at least a single\n\
    \ message that the model can respond to.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\EOT\DC2\ETX/\STX\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\ACK\DC2\ETX/\v\DC2\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\SOH\DC2\ETX/\DC3\ESC\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\ETX\DC2\ETX/\RS\US\n\
    \\150\SOH\n\
    \\EOT\EOT\NUL\STX\SOH\DC2\ETX3\STX\DC3\SUB\136\SOH Name of the model. This is the name as reported by the models API. More\n\
    \ details can be found on your console at https://console.x.ai.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\SOH\ENQ\DC2\ETX3\STX\b\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\SOH\SOH\DC2\ETX3\t\SO\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\SOH\ETX\DC2\ETX3\DC1\DC2\n\
    \\205\SOH\n\
    \\EOT\EOT\NUL\STX\STX\DC2\ETX8\STX\DC3\SUB\191\SOH An opaque string supplied by the API client (customer) to identify a user.\n\
    \ The string will be stored in the logs and can be used in customer service\n\
    \ requests to identify certain requests.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\STX\ENQ\DC2\ETX8\STX\b\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\STX\SOH\DC2\ETX8\t\r\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\STX\ETX\DC2\ETX8\DLE\DC2\n\
    \\176\STX\n\
    \\EOT\EOT\NUL\STX\ETX\DC2\ETX>\STX\ETB\SUB\162\STX The number of completions to create concurrently. A single completion will\n\
    \ be generated if the parameter is unset. Each completion is charged at the\n\
    \ same rate. You can generate at most 128 concurrent completions.\n\
    \ PLEASE NOTE: This field is deprecated and will be removed in the future.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ETX\EOT\DC2\ETX>\STX\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ETX\ENQ\DC2\ETX>\v\DLE\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ETX\SOH\DC2\ETX>\DC1\DC2\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ETX\ETX\DC2\ETX>\NAK\SYN\n\
    \\172\EOT\n\
    \\EOT\EOT\NUL\STX\EOT\DC2\ETXL\STX \SUB\158\EOT The maximum number of tokens to sample. If unset, the model samples until\n\
    \ one of the following stop-conditions is reached:\n\
    \ - The context length of the model is exceeded\n\
    \ - One of the `stop` sequences has been observed.\n\
    \ - The time limit exceeds.\n\
    \\n\
    \ Note that for reasoning models and models that support function calls, the\n\
    \ limit is only applied to the main content and not to the reasoning content\n\
    \ or function calls.\n\
    \\n\
    \ We recommend choosing a reasonable value to reduce the risk of accidental\n\
    \ long-generations that consume many tokens.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\EOT\EOT\DC2\ETXL\STX\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\EOT\ENQ\DC2\ETXL\v\DLE\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\EOT\SOH\DC2\ETXL\DC1\ESC\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\EOT\ETX\DC2\ETXL\RS\US\n\
    \\211\STX\n\
    \\EOT\EOT\NUL\STX\ENQ\DC2\ETXS\STX\ESC\SUB\197\STX A random seed used to make the sampling process deterministic. This is\n\
    \ provided in a best-effort basis without guarantee that sampling is 100%\n\
    \ deterministic given a seed. This is primarily provided for short-lived\n\
    \ testing purposes. Given a fixed request and seed, the answers may change\n\
    \ over time as our systems evolve.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ENQ\EOT\DC2\ETXS\STX\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ENQ\ENQ\DC2\ETXS\v\DLE\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ENQ\SOH\DC2\ETXS\DC1\NAK\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ENQ\ETX\DC2\ETXS\CAN\SUB\n\
    \\169\ENQ\n\
    \\EOT\EOT\NUL\STX\ACK\DC2\ETX`\STX\FS\SUB\155\ENQ String patterns that will cause the sampling procedure to stop prematurely\n\
    \ when observed.\n\
    \ Note that the completion is based on individual tokens and sampling can\n\
    \ only terminate at token boundaries. If a stop string is a substring of an\n\
    \ individual token, the completion will include the entire token, which\n\
    \ extends beyond the stop string.\n\
    \ For example, if `stop = [\"wor\"]` and we prompt the model with \"hello\" to\n\
    \ which it responds with \"world\", then the sampling procedure will stop after\n\
    \ observing the \"world\" token and the completion will contain\n\
    \ the entire world \"world\" even though the stop string was just \"wor\".\n\
    \ You can provide at most 8 stop strings.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ACK\EOT\DC2\ETX`\STX\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ACK\ENQ\DC2\ETX`\v\DC1\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ACK\SOH\DC2\ETX`\DC2\SYN\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ACK\ETX\DC2\ETX`\EM\ESC\n\
    \\239\ETX\n\
    \\EOT\EOT\NUL\STX\a\DC2\ETXi\STX\"\SUB\225\ETX A number between 0 and 2 used to control the variance of completions.\n\
    \ The smaller the value, the more deterministic the model will become. For\n\
    \ example, if we sample 1000 answers to the same prompt at a temperature of\n\
    \ 0.001, then most of the 1000 answers will be identical. Conversely, if we\n\
    \ conduct the same experiment at a temperature of 2, virtually no two answers\n\
    \ will be identical. Note that increasing the temperature will cause\n\
    \ the model to hallucinate more strongly.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\a\EOT\DC2\ETXi\STX\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\a\ENQ\DC2\ETXi\v\DLE\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\a\SOH\DC2\ETXi\DC1\FS\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\a\ETX\DC2\ETXi\US!\n\
    \\132\ENQ\n\
    \\EOT\EOT\NUL\STX\b\DC2\ETXt\STX\FS\SUB\246\EOT A number between 0 and 1 controlling the likelihood of the model to use\n\
    \ less-common answers. Recall that the model produces a probability for\n\
    \ each token. This means, for any choice of token there are thousands of\n\
    \ possibilities to choose from. This parameter controls the \"nucleus sampling\n\
    \ algorithm\". Instead of considering every possible token at every step, we\n\
    \ only look at the K tokens who's probabilities exceed `top_p`.\n\
    \ For example, if we set `top_p = 0.9`, then the set of tokens we actually\n\
    \ sample from, will have a probability mass of at least 90%. In practice,\n\
    \ low values will make the model more deterministic.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\b\EOT\DC2\ETXt\STX\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\b\ENQ\DC2\ETXt\v\DLE\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\b\SOH\DC2\ETXt\DC1\SYN\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\b\ETX\DC2\ETXt\EM\ESC\n\
    \N\n\
    \\EOT\EOT\NUL\STX\t\DC2\ETXw\STX\DC4\SUBA If set to true, log probabilities of the sampling are returned.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\t\ENQ\DC2\ETXw\STX\ACK\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\t\SOH\DC2\ETXw\a\SI\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\t\ETX\DC2\ETXw\DC2\DC3\n\
    \9\n\
    \\EOT\EOT\NUL\STX\n\
    \\DC2\ETXz\STX\"\SUB, Number of top log probabilities to return.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\n\
    \\EOT\DC2\ETXz\STX\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\n\
    \\ENQ\DC2\ETXz\v\DLE\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\n\
    \\SOH\DC2\ETXz\DC1\GS\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\n\
    \\ETX\DC2\ETXz !\n\
    \\184\SOH\n\
    \\EOT\EOT\NUL\STX\v\DC2\ETX\DEL\STX\ESC\SUB\170\SOH A list of tools the model may call. Currently, only functions are supported\n\
    \ as a tool. Use this to provide a list of functions the model may generate\n\
    \ JSON inputs for.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\v\EOT\DC2\ETX\DEL\STX\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\v\ACK\DC2\ETX\DEL\v\SI\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\v\SOH\DC2\ETX\DEL\DLE\NAK\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\v\ETX\DC2\ETX\DEL\CAN\SUB\n\
    \I\n\
    \\EOT\EOT\NUL\STX\f\DC2\EOT\130\SOH\STX\RS\SUB; Controls if the model can, should, or must not use tools.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\NUL\STX\f\ACK\DC2\EOT\130\SOH\STX\f\n\
    \\r\n\
    \\ENQ\EOT\NUL\STX\f\SOH\DC2\EOT\130\SOH\r\CAN\n\
    \\r\n\
    \\ENQ\EOT\NUL\STX\f\ETX\DC2\EOT\130\SOH\ESC\GS\n\
    \6\n\
    \\EOT\EOT\NUL\STX\r\DC2\EOT\133\SOH\STX&\SUB( Formatting constraint on the response.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\NUL\STX\r\ACK\DC2\EOT\133\SOH\STX\DLE\n\
    \\r\n\
    \\ENQ\EOT\NUL\STX\r\SOH\DC2\EOT\133\SOH\DC1 \n\
    \\r\n\
    \\ENQ\EOT\NUL\STX\r\ETX\DC2\EOT\133\SOH#%\n\
    \\176\SOH\n\
    \\EOT\EOT\NUL\STX\SO\DC2\EOT\138\SOH\STX'\SUB\161\SOH Positive values penalize new tokens based on their existing frequency in\n\
    \ the text so far, decreasing the model's likelihood to repeat the same line\n\
    \ verbatim.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\NUL\STX\SO\EOT\DC2\EOT\138\SOH\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\NUL\STX\SO\ENQ\DC2\EOT\138\SOH\v\DLE\n\
    \\r\n\
    \\ENQ\EOT\NUL\STX\SO\SOH\DC2\EOT\138\SOH\DC1\"\n\
    \\r\n\
    \\ENQ\EOT\NUL\STX\SO\ETX\DC2\EOT\138\SOH%&\n\
    \\163\SOH\n\
    \\EOT\EOT\NUL\STX\SI\DC2\EOT\143\SOH\STX&\SUB\148\SOH Positive values penalize new tokens based on whether they appear in\n\
    \ the text so far, increasing the model's likelihood to talk about\n\
    \ new topics.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\NUL\STX\SI\EOT\DC2\EOT\143\SOH\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\NUL\STX\SI\ENQ\DC2\EOT\143\SOH\v\DLE\n\
    \\r\n\
    \\ENQ\EOT\NUL\STX\SI\SOH\DC2\EOT\143\SOH\DC1!\n\
    \\r\n\
    \\ENQ\EOT\NUL\STX\SI\ETX\DC2\EOT\143\SOH$%\n\
    \`\n\
    \\EOT\EOT\NUL\STX\DLE\DC2\EOT\146\SOH\STX1\SUBR Constrains effort on reasoning for reasoning models. Default to `EFFORT_MEDIUM`.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\NUL\STX\DLE\EOT\DC2\EOT\146\SOH\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\NUL\STX\DLE\ACK\DC2\EOT\146\SOH\v\SUB\n\
    \\r\n\
    \\ENQ\EOT\NUL\STX\DLE\SOH\DC2\EOT\146\SOH\ESC+\n\
    \\r\n\
    \\ENQ\EOT\NUL\STX\DLE\ETX\DC2\EOT\146\SOH.0\n\
    \|\n\
    \\EOT\EOT\NUL\STX\DC1\DC2\EOT\149\SOH\STX3\SUBn Set the parameters to be used for realtime data. If not set, no realtime data will be acquired by the model.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\NUL\STX\DC1\EOT\DC2\EOT\149\SOH\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\NUL\STX\DC1\ACK\DC2\EOT\149\SOH\v\ESC\n\
    \\r\n\
    \\ENQ\EOT\NUL\STX\DC1\SOH\DC2\EOT\149\SOH\FS-\n\
    \\r\n\
    \\ENQ\EOT\NUL\STX\DC1\ETX\DC2\EOT\149\SOH02\n\
    \l\n\
    \\EOT\EOT\NUL\STX\DC2\DC2\EOT\152\SOH\STX)\SUB^/ If set to false, the model can perform maximum one tool call per response. Default to true.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\NUL\STX\DC2\EOT\DC2\EOT\152\SOH\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\NUL\STX\DC2\ENQ\DC2\EOT\152\SOH\v\SI\n\
    \\r\n\
    \\ENQ\EOT\NUL\STX\DC2\SOH\DC2\EOT\152\SOH\DLE#\n\
    \\r\n\
    \\ENQ\EOT\NUL\STX\DC2\ETX\DC2\EOT\152\SOH&(\n\
    \V\n\
    \\EOT\EOT\NUL\STX\DC3\DC2\EOT\155\SOH\STX,\SUBH Previous response id. The messages from this response must be chained.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\NUL\STX\DC3\EOT\DC2\EOT\155\SOH\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\NUL\STX\DC3\ENQ\DC2\EOT\155\SOH\v\DC1\n\
    \\r\n\
    \\ENQ\EOT\NUL\STX\DC3\SOH\DC2\EOT\155\SOH\DC2&\n\
    \\r\n\
    \\ENQ\EOT\NUL\STX\DC3\ETX\DC2\EOT\155\SOH)+\n\
    \I\n\
    \\EOT\EOT\NUL\STX\DC4\DC2\EOT\158\SOH\STX\ESC\SUB; Whether to store request and responses. Default is false.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\NUL\STX\DC4\ENQ\DC2\EOT\158\SOH\STX\ACK\n\
    \\r\n\
    \\ENQ\EOT\NUL\STX\DC4\SOH\DC2\EOT\158\SOH\a\NAK\n\
    \\r\n\
    \\ENQ\EOT\NUL\STX\DC4\ETX\DC2\EOT\158\SOH\CAN\SUB\n\
    \Q\n\
    \\EOT\EOT\NUL\STX\NAK\DC2\EOT\161\SOH\STX\"\SUBC Whether to use encrypted thinking for thinking trace rehydration.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\NUL\STX\NAK\ENQ\DC2\EOT\161\SOH\STX\ACK\n\
    \\r\n\
    \\ENQ\EOT\NUL\STX\NAK\SOH\DC2\EOT\161\SOH\a\FS\n\
    \\r\n\
    \\ENQ\EOT\NUL\STX\NAK\ETX\DC2\EOT\161\SOH\US!\n\
    \\192\ETX\n\
    \\EOT\EOT\NUL\STX\SYN\DC2\EOT\169\SOH\STX \SUB\177\ETX Maximum number of agentic tool calling turns allowed for this request.\n\
    \ If not set, defaults to the server's global cap.\n\
    \ The effective max_turns will be the min of the server's global cap and the request's max_turns.\n\
    \ This parameter will be ignored for any non-agentic requests.\n\
    \ With parallel tool calls, multiple tool calls can occur within a single turn,\n\
    \ so max_turns does not necessarily equal the total number of tool calls.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\NUL\STX\SYN\EOT\DC2\EOT\169\SOH\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\NUL\STX\SYN\ENQ\DC2\EOT\169\SOH\v\DLE\n\
    \\r\n\
    \\ENQ\EOT\NUL\STX\SYN\SOH\DC2\EOT\169\SOH\DC1\SUB\n\
    \\r\n\
    \\ENQ\EOT\NUL\STX\SYN\ETX\DC2\EOT\169\SOH\GS\US\n\
    \_\n\
    \\EOT\EOT\NUL\STX\ETB\DC2\EOT\172\SOH\STX&\SUBQ Allow the users to control what optional fields to be returned in the response.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\NUL\STX\ETB\EOT\DC2\EOT\172\SOH\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\NUL\STX\ETB\ACK\DC2\EOT\172\SOH\v\CAN\n\
    \\r\n\
    \\ENQ\EOT\NUL\STX\ETB\SOH\DC2\EOT\172\SOH\EM \n\
    \\r\n\
    \\ENQ\EOT\NUL\STX\ETB\ETX\DC2\EOT\172\SOH#%\n\
    \\152\SOH\n\
    \\EOT\EOT\NUL\STX\CAN\DC2\EOT\176\SOH\STX'\SUB\137\SOH Number of agents to use for multi-agent models.\n\
    \ Only valid when model is a `multi-agent` model. Defaults to `AGENT_COUNT_UNSPECIFIED`.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\NUL\STX\CAN\EOT\DC2\EOT\176\SOH\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\NUL\STX\CAN\ACK\DC2\EOT\176\SOH\v\NAK\n\
    \\r\n\
    \\ENQ\EOT\NUL\STX\CAN\SOH\DC2\EOT\176\SOH\SYN!\n\
    \\r\n\
    \\ENQ\EOT\NUL\STX\CAN\ETX\DC2\EOT\176\SOH$&\n\
    \\f\n\
    \\STX\EOT\SOH\DC2\ACK\179\SOH\NUL\215\SOH\SOH\n\
    \\v\n\
    \\ETX\EOT\SOH\SOH\DC2\EOT\179\SOH\b!\n\
    \\159\SOH\n\
    \\EOT\EOT\SOH\STX\NUL\DC2\EOT\182\SOH\STX\DLE\SUB\144\SOH The ID of this request. This ID will also show up on your billing records\n\
    \ and you can use it when contacting us regarding a specific request.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\SOH\STX\NUL\ENQ\DC2\EOT\182\SOH\STX\b\n\
    \\r\n\
    \\ENQ\EOT\SOH\STX\NUL\SOH\DC2\EOT\182\SOH\t\v\n\
    \\r\n\
    \\ENQ\EOT\SOH\STX\NUL\ETX\DC2\EOT\182\SOH\SO\SI\n\
    \\214\SOH\n\
    \\EOT\EOT\SOH\STX\SOH\DC2\EOT\187\SOH\STX(\SUB\199\SOH Model-generated outputs/responses to the input messages. Each output contains\n\
    \ the model's response including text content, reasoning traces, tool calls, and\n\
    \ metadata about the generation process.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\SOH\STX\SOH\EOT\DC2\EOT\187\SOH\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\SOH\STX\SOH\ACK\DC2\EOT\187\SOH\v\ESC\n\
    \\r\n\
    \\ENQ\EOT\SOH\STX\SOH\SOH\DC2\EOT\187\SOH\FS#\n\
    \\r\n\
    \\ENQ\EOT\SOH\STX\SOH\ETX\DC2\EOT\187\SOH&'\n\
    \\155\SOH\n\
    \\EOT\EOT\SOH\STX\STX\DC2\EOT\191\SOH\STX(\SUB\140\SOH A UNIX timestamp (UTC) indicating when the response object was created.\n\
    \ The timestamp is taken when the model starts generating response.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\SOH\STX\STX\ACK\DC2\EOT\191\SOH\STX\ESC\n\
    \\r\n\
    \\ENQ\EOT\SOH\STX\STX\SOH\DC2\EOT\191\SOH\FS#\n\
    \\r\n\
    \\ENQ\EOT\SOH\STX\STX\ETX\DC2\EOT\191\SOH&'\n\
    \\235\SOH\n\
    \\EOT\EOT\SOH\STX\ETX\DC2\EOT\197\SOH\STX\DC3\SUB\220\SOH The name of the model used for the request. This model name contains\n\
    \ the actual model name used rather than any aliases.\n\
    \ This means the this can be `grok-2-1212` even when the request was\n\
    \ specifying `grok-2-latest`.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\SOH\STX\ETX\ENQ\DC2\EOT\197\SOH\STX\b\n\
    \\r\n\
    \\ENQ\EOT\SOH\STX\ETX\SOH\DC2\EOT\197\SOH\t\SO\n\
    \\r\n\
    \\ENQ\EOT\SOH\STX\ETX\ETX\DC2\EOT\197\SOH\DC1\DC2\n\
    \`\n\
    \\EOT\EOT\SOH\STX\EOT\DC2\EOT\201\SOH\STX \SUBR This fingerprint represents the backend configuration that the model runs\n\
    \ with.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\SOH\STX\EOT\ENQ\DC2\EOT\201\SOH\STX\b\n\
    \\r\n\
    \\ENQ\EOT\SOH\STX\EOT\SOH\DC2\EOT\201\SOH\t\ESC\n\
    \\r\n\
    \\ENQ\EOT\SOH\STX\EOT\ETX\DC2\EOT\201\SOH\RS\US\n\
    \>\n\
    \\EOT\EOT\SOH\STX\ENQ\DC2\EOT\204\SOH\STX\SUB\SUB0 The number of tokens consumed by this request.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\SOH\STX\ENQ\ACK\DC2\EOT\204\SOH\STX\SI\n\
    \\r\n\
    \\ENQ\EOT\SOH\STX\ENQ\SOH\DC2\EOT\204\SOH\DLE\NAK\n\
    \\r\n\
    \\ENQ\EOT\SOH\STX\ENQ\ETX\DC2\EOT\204\SOH\CAN\EM\n\
    \\228\SOH\n\
    \\EOT\EOT\SOH\STX\ACK\DC2\EOT\208\SOH\STX!\SUB\213\SOH/ List of all the external pages (urls) used by the model to produce its final answer.\n\
    \ This is only present when live search is enabled, (That is `SearchParameters` have been defined in `GetCompletionsRequest`).\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\SOH\STX\ACK\EOT\DC2\EOT\208\SOH\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\SOH\STX\ACK\ENQ\DC2\EOT\208\SOH\v\DC1\n\
    \\r\n\
    \\ENQ\EOT\SOH\STX\ACK\SOH\DC2\EOT\208\SOH\DC2\ESC\n\
    \\r\n\
    \\ENQ\EOT\SOH\STX\ACK\ETX\DC2\EOT\208\SOH\RS \n\
    \<\n\
    \\EOT\EOT\SOH\STX\a\DC2\EOT\211\SOH\STX \SUB. Settings used while generating the response.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\SOH\STX\a\ACK\DC2\EOT\211\SOH\STX\DC1\n\
    \\r\n\
    \\ENQ\EOT\SOH\STX\a\SOH\DC2\EOT\211\SOH\DC2\SUB\n\
    \\r\n\
    \\ENQ\EOT\SOH\STX\a\ETX\DC2\EOT\211\SOH\GS\US\n\
    \@\n\
    \\EOT\EOT\SOH\STX\b\DC2\EOT\214\SOH\STX \SUB2 Debug output. Only available to trusted testers.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\SOH\STX\b\ACK\DC2\EOT\214\SOH\STX\r\n\
    \\r\n\
    \\ENQ\EOT\SOH\STX\b\SOH\DC2\EOT\214\SOH\SO\SUB\n\
    \\r\n\
    \\ENQ\EOT\SOH\STX\b\ETX\DC2\EOT\214\SOH\GS\US\n\
    \\f\n\
    \\STX\EOT\STX\DC2\ACK\217\SOH\NUL\251\SOH\SOH\n\
    \\v\n\
    \\ETX\EOT\STX\SOH\DC2\EOT\217\SOH\b\RS\n\
    \\159\SOH\n\
    \\EOT\EOT\STX\STX\NUL\DC2\EOT\220\SOH\STX\DLE\SUB\144\SOH The ID of this request. This ID will also show up on your billing records\n\
    \ and you can use it when contacting us regarding a specific request.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\STX\STX\NUL\ENQ\DC2\EOT\220\SOH\STX\b\n\
    \\r\n\
    \\ENQ\EOT\STX\STX\NUL\SOH\DC2\EOT\220\SOH\t\v\n\
    \\r\n\
    \\ENQ\EOT\STX\STX\NUL\ETX\DC2\EOT\220\SOH\SO\SI\n\
    \\161\SOH\n\
    \\EOT\EOT\STX\STX\SOH\DC2\EOT\224\SOH\STX-\SUB\146\SOH Model-generated outputs/responses being streamed as they are generated.\n\
    \ Each output chunk contains incremental updates to the model's response.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\STX\STX\SOH\EOT\DC2\EOT\224\SOH\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\STX\STX\SOH\ACK\DC2\EOT\224\SOH\v \n\
    \\r\n\
    \\ENQ\EOT\STX\STX\SOH\SOH\DC2\EOT\224\SOH!(\n\
    \\r\n\
    \\ENQ\EOT\STX\STX\SOH\ETX\DC2\EOT\224\SOH+,\n\
    \\155\SOH\n\
    \\EOT\EOT\STX\STX\STX\DC2\EOT\228\SOH\STX(\SUB\140\SOH A UNIX timestamp (UTC) indicating when the response object was created.\n\
    \ The timestamp is taken when the model starts generating response.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\STX\STX\STX\ACK\DC2\EOT\228\SOH\STX\ESC\n\
    \\r\n\
    \\ENQ\EOT\STX\STX\STX\SOH\DC2\EOT\228\SOH\FS#\n\
    \\r\n\
    \\ENQ\EOT\STX\STX\STX\ETX\DC2\EOT\228\SOH&'\n\
    \\235\SOH\n\
    \\EOT\EOT\STX\STX\ETX\DC2\EOT\234\SOH\STX\DC3\SUB\220\SOH The name of the model used for the request. This model name contains\n\
    \ the actual model name used rather than any aliases.\n\
    \ This means the this can be `grok-2-1212` even when the request was\n\
    \ specifying `grok-2-latest`.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\STX\STX\ETX\ENQ\DC2\EOT\234\SOH\STX\b\n\
    \\r\n\
    \\ENQ\EOT\STX\STX\ETX\SOH\DC2\EOT\234\SOH\t\SO\n\
    \\r\n\
    \\ENQ\EOT\STX\STX\ETX\ETX\DC2\EOT\234\SOH\DC1\DC2\n\
    \`\n\
    \\EOT\EOT\STX\STX\EOT\DC2\EOT\238\SOH\STX \SUBR This fingerprint represents the backend configuration that the model runs\n\
    \ with.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\STX\STX\EOT\ENQ\DC2\EOT\238\SOH\STX\b\n\
    \\r\n\
    \\ENQ\EOT\STX\STX\EOT\SOH\DC2\EOT\238\SOH\t\ESC\n\
    \\r\n\
    \\ENQ\EOT\STX\STX\EOT\ETX\DC2\EOT\238\SOH\RS\US\n\
    \\185\SOH\n\
    \\EOT\EOT\STX\STX\ENQ\DC2\EOT\243\SOH\STX\SUB\SUB\170\SOH The total number of tokens consumed when this chunk was streamed. Note that\n\
    \ this is not the final number of tokens billed unless this is the last chunk\n\
    \ in the stream.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\STX\STX\ENQ\ACK\DC2\EOT\243\SOH\STX\SI\n\
    \\r\n\
    \\ENQ\EOT\STX\STX\ENQ\SOH\DC2\EOT\243\SOH\DLE\NAK\n\
    \\r\n\
    \\ENQ\EOT\STX\STX\ENQ\ETX\DC2\EOT\243\SOH\CAN\EM\n\
    \\205\SOH\n\
    \\EOT\EOT\STX\STX\ACK\DC2\EOT\247\SOH\STX \SUB\190\SOH/ List of all the external pages used by the model to answer. Only populated for the last chunk.\n\
    \ This is only present for requests that make use of live search or server-side search tools.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\STX\STX\ACK\EOT\DC2\EOT\247\SOH\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\STX\STX\ACK\ENQ\DC2\EOT\247\SOH\v\DC1\n\
    \\r\n\
    \\ENQ\EOT\STX\STX\ACK\SOH\DC2\EOT\247\SOH\DC2\ESC\n\
    \\r\n\
    \\ENQ\EOT\STX\STX\ACK\ETX\DC2\EOT\247\SOH\RS\US\n\
    \H\n\
    \\EOT\EOT\STX\STX\a\DC2\EOT\250\SOH\STX \SUB: Only available for teams that have debugging privileges.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\STX\STX\a\ACK\DC2\EOT\250\SOH\STX\r\n\
    \\r\n\
    \\ENQ\EOT\STX\STX\a\SOH\DC2\EOT\250\SOH\SO\SUB\n\
    \\r\n\
    \\ENQ\EOT\STX\STX\a\ETX\DC2\EOT\250\SOH\GS\US\n\
    \\136\SOH\n\
    \\STX\EOT\ETX\DC2\ACK\255\SOH\NUL\133\STX\SOH\SUBz Response from GetDeferredCompletion, including the response if the completion\n\
    \ request has been processed without error.\n\
    \\n\
    \\v\n\
    \\ETX\EOT\ETX\SOH\DC2\EOT\255\SOH\b%\n\
    \.\n\
    \\EOT\EOT\ETX\STX\NUL\DC2\EOT\129\STX\STX\FS\SUB  Current status of the request.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\ETX\STX\NUL\ACK\DC2\EOT\129\STX\STX\DLE\n\
    \\r\n\
    \\ENQ\EOT\ETX\STX\NUL\SOH\DC2\EOT\129\STX\DC1\ETB\n\
    \\r\n\
    \\ENQ\EOT\ETX\STX\NUL\ETX\DC2\EOT\129\STX\SUB\ESC\n\
    \7\n\
    \\EOT\EOT\ETX\STX\SOH\DC2\EOT\132\STX\STX2\SUB) Response. Only present if `status=DONE`\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\ETX\STX\SOH\EOT\DC2\EOT\132\STX\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\ETX\STX\SOH\ACK\DC2\EOT\132\STX\v$\n\
    \\r\n\
    \\ENQ\EOT\ETX\STX\SOH\SOH\DC2\EOT\132\STX%-\n\
    \\r\n\
    \\ENQ\EOT\ETX\STX\SOH\ETX\DC2\EOT\132\STX01\n\
    \=\n\
    \\STX\EOT\EOT\DC2\ACK\136\STX\NUL\149\STX\SOH\SUB/ Contains the response generated by the model.\n\
    \\n\
    \\v\n\
    \\ETX\EOT\EOT\SOH\DC2\EOT\136\STX\b\CAN\n\
    \:\n\
    \\EOT\EOT\EOT\STX\NUL\DC2\EOT\138\STX\STX!\SUB, Indicating why the model stopped sampling.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\EOT\STX\NUL\ACK\DC2\EOT\138\STX\STX\SO\n\
    \\r\n\
    \\ENQ\EOT\EOT\STX\NUL\SOH\DC2\EOT\138\STX\SI\FS\n\
    \\r\n\
    \\ENQ\EOT\EOT\STX\NUL\ETX\DC2\EOT\138\STX\US \n\
    \\163\SOH\n\
    \\EOT\EOT\EOT\STX\SOH\DC2\EOT\142\STX\STX\DC2\SUB\148\SOH The index of this output in the list of outputs. When multiple outputs are\n\
    \ generated, each output is assigned a sequential index starting from 0.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\EOT\STX\SOH\ENQ\DC2\EOT\142\STX\STX\a\n\
    \\r\n\
    \\ENQ\EOT\EOT\STX\SOH\SOH\DC2\EOT\142\STX\b\r\n\
    \\r\n\
    \\ENQ\EOT\EOT\STX\SOH\ETX\DC2\EOT\142\STX\DLE\DC1\n\
    \:\n\
    \\EOT\EOT\EOT\STX\STX\DC2\EOT\145\STX\STX \SUB, The actual message generated by the model.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\EOT\STX\STX\ACK\DC2\EOT\145\STX\STX\DC3\n\
    \\r\n\
    \\ENQ\EOT\EOT\STX\STX\SOH\DC2\EOT\145\STX\DC4\ESC\n\
    \\r\n\
    \\ENQ\EOT\EOT\STX\STX\ETX\DC2\EOT\145\STX\RS\US\n\
    \6\n\
    \\EOT\EOT\EOT\STX\ETX\DC2\EOT\148\STX\STX\CAN\SUB( The log probabilities of the sampling.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\EOT\STX\ETX\ACK\DC2\EOT\148\STX\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\EOT\STX\ETX\SOH\DC2\EOT\148\STX\v\DC3\n\
    \\r\n\
    \\ENQ\EOT\EOT\STX\ETX\ETX\DC2\EOT\148\STX\SYN\ETB\n\
    \Q\n\
    \\STX\EOT\ENQ\DC2\ACK\152\STX\NUL\170\STX\SOH\SUBC Holds the model output (i.e. the result of the sampling process).\n\
    \\n\
    \\v\n\
    \\ETX\EOT\ENQ\SOH\DC2\EOT\152\STX\b\EM\n\
    \=\n\
    \\EOT\EOT\ENQ\STX\NUL\DC2\EOT\154\STX\STX\NAK\SUB/ The generated text based on the input prompt.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\ENQ\STX\NUL\ENQ\DC2\EOT\154\STX\STX\b\n\
    \\r\n\
    \\ENQ\EOT\ENQ\STX\NUL\SOH\DC2\EOT\154\STX\t\DLE\n\
    \\r\n\
    \\ENQ\EOT\ENQ\STX\NUL\ETX\DC2\EOT\154\STX\DC3\DC4\n\
    \S\n\
    \\EOT\EOT\ENQ\STX\SOH\DC2\EOT\157\STX\STX\US\SUBE Reasoning trace the model produced before issuing the final answer.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\ENQ\STX\SOH\ENQ\DC2\EOT\157\STX\STX\b\n\
    \\r\n\
    \\ENQ\EOT\ENQ\STX\SOH\SOH\DC2\EOT\157\STX\t\SUB\n\
    \\r\n\
    \\ENQ\EOT\ENQ\STX\SOH\ETX\DC2\EOT\157\STX\GS\RS\n\
    \S\n\
    \\EOT\EOT\ENQ\STX\STX\DC2\EOT\160\STX\STX\ETB\SUBE The role of the message author. Will always default to \"assistant\".\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\ENQ\STX\STX\ACK\DC2\EOT\160\STX\STX\r\n\
    \\r\n\
    \\ENQ\EOT\ENQ\STX\STX\SOH\DC2\EOT\160\STX\SO\DC2\n\
    \\r\n\
    \\ENQ\EOT\ENQ\STX\STX\ETX\DC2\EOT\160\STX\NAK\SYN\n\
    \;\n\
    \\EOT\EOT\ENQ\STX\ETX\DC2\EOT\163\STX\STX#\SUB- The tools that the assistant wants to call.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\ENQ\STX\ETX\EOT\DC2\EOT\163\STX\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\ENQ\STX\ETX\ACK\DC2\EOT\163\STX\v\DC3\n\
    \\r\n\
    \\ENQ\EOT\ENQ\STX\ETX\SOH\DC2\EOT\163\STX\DC4\RS\n\
    \\r\n\
    \\ENQ\EOT\ENQ\STX\ETX\ETX\DC2\EOT\163\STX!\"\n\
    \&\n\
    \\EOT\EOT\ENQ\STX\EOT\DC2\EOT\166\STX\STX\US\SUB\CAN The encrypted content.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\ENQ\STX\EOT\ENQ\DC2\EOT\166\STX\STX\b\n\
    \\r\n\
    \\ENQ\EOT\ENQ\STX\EOT\SOH\DC2\EOT\166\STX\t\SUB\n\
    \\r\n\
    \\ENQ\EOT\ENQ\STX\EOT\ETX\DC2\EOT\166\STX\GS\RS\n\
    \I\n\
    \\EOT\EOT\ENQ\STX\ENQ\DC2\EOT\169\STX\STX(\SUB; The citations that the model used to answer the question.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\ENQ\STX\ENQ\EOT\DC2\EOT\169\STX\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\ENQ\STX\ENQ\ACK\DC2\EOT\169\STX\v\EM\n\
    \\r\n\
    \\ENQ\EOT\ENQ\STX\ENQ\SOH\DC2\EOT\169\STX\SUB#\n\
    \\r\n\
    \\ENQ\EOT\ENQ\STX\ENQ\ETX\DC2\EOT\169\STX&'\n\
    \i\n\
    \\STX\EOT\ACK\DC2\ACK\174\STX\NUL\186\STX\SOH\SUB[ Holds the differences (deltas) that when concatenated make up the entire\n\
    \ agent response.\n\
    \\n\
    \\v\n\
    \\ETX\EOT\ACK\SOH\DC2\EOT\174\STX\b\GS\n\
    \V\n\
    \\EOT\EOT\ACK\STX\NUL\DC2\EOT\176\STX\STX\DC2\SUBH The actual text differences that need to be accumulated on the client.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\ACK\STX\NUL\ACK\DC2\EOT\176\STX\STX\a\n\
    \\r\n\
    \\ENQ\EOT\ACK\STX\NUL\SOH\DC2\EOT\176\STX\b\r\n\
    \\r\n\
    \\ENQ\EOT\ACK\STX\NUL\ETX\DC2\EOT\176\STX\DLE\DC1\n\
    \2\n\
    \\EOT\EOT\ACK\STX\SOH\DC2\EOT\179\STX\STX\CAN\SUB$ The log probability of the choice.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\ACK\STX\SOH\ACK\DC2\EOT\179\STX\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\ACK\STX\SOH\SOH\DC2\EOT\179\STX\v\DC3\n\
    \\r\n\
    \\ENQ\EOT\ACK\STX\SOH\ETX\DC2\EOT\179\STX\SYN\ETB\n\
    \:\n\
    \\EOT\EOT\ACK\STX\STX\DC2\EOT\182\STX\STX!\SUB, Indicating why the model stopped sampling.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\ACK\STX\STX\ACK\DC2\EOT\182\STX\STX\SO\n\
    \\r\n\
    \\ENQ\EOT\ACK\STX\STX\SOH\DC2\EOT\182\STX\SI\FS\n\
    \\r\n\
    \\ENQ\EOT\ACK\STX\STX\ETX\DC2\EOT\182\STX\US \n\
    \L\n\
    \\EOT\EOT\ACK\STX\ETX\DC2\EOT\185\STX\STX\DC2\SUB> The index of this output chunk in the list of output chunks.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\ACK\STX\ETX\ENQ\DC2\EOT\185\STX\STX\a\n\
    \\r\n\
    \\ENQ\EOT\ACK\STX\ETX\SOH\DC2\EOT\185\STX\b\r\n\
    \\r\n\
    \\ENQ\EOT\ACK\STX\ETX\ETX\DC2\EOT\185\STX\DLE\DC1\n\
    \2\n\
    \\STX\EOT\a\DC2\ACK\189\STX\NUL\208\STX\SOH\SUB$ The delta of a streaming response.\n\
    \\n\
    \\v\n\
    \\ETX\EOT\a\SOH\DC2\EOT\189\STX\b\r\n\
    \-\n\
    \\EOT\EOT\a\STX\NUL\DC2\EOT\191\STX\STX\NAK\SUB\US The main model output/answer.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\a\STX\NUL\ENQ\DC2\EOT\191\STX\STX\b\n\
    \\r\n\
    \\ENQ\EOT\a\STX\NUL\SOH\DC2\EOT\191\STX\t\DLE\n\
    \\r\n\
    \\ENQ\EOT\a\STX\NUL\ETX\DC2\EOT\191\STX\DC3\DC4\n\
    \4\n\
    \\EOT\EOT\a\STX\SOH\DC2\EOT\194\STX\STX\US\SUB& Part of the model's reasoning trace.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\a\STX\SOH\ENQ\DC2\EOT\194\STX\STX\b\n\
    \\r\n\
    \\ENQ\EOT\a\STX\SOH\SOH\DC2\EOT\194\STX\t\SUB\n\
    \\r\n\
    \\ENQ\EOT\a\STX\SOH\ETX\DC2\EOT\194\STX\GS\RS\n\
    \u\n\
    \\EOT\EOT\a\STX\STX\DC2\EOT\198\STX\STX\ETB\SUBg The entity type who sent the message. For example, a message can be sent by\n\
    \ a user or the assistant.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\a\STX\STX\ACK\DC2\EOT\198\STX\STX\r\n\
    \\r\n\
    \\ENQ\EOT\a\STX\STX\SOH\DC2\EOT\198\STX\SO\DC2\n\
    \\r\n\
    \\ENQ\EOT\a\STX\STX\ETX\DC2\EOT\198\STX\NAK\SYN\n\
    \L\n\
    \\EOT\EOT\a\STX\ETX\DC2\EOT\201\STX\STX#\SUB> A list of tool calls if tool call is requested by the model.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\a\STX\ETX\EOT\DC2\EOT\201\STX\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\a\STX\ETX\ACK\DC2\EOT\201\STX\v\DC3\n\
    \\r\n\
    \\ENQ\EOT\a\STX\ETX\SOH\DC2\EOT\201\STX\DC4\RS\n\
    \\r\n\
    \\ENQ\EOT\a\STX\ETX\ETX\DC2\EOT\201\STX!\"\n\
    \&\n\
    \\EOT\EOT\a\STX\EOT\DC2\EOT\204\STX\STX\US\SUB\CAN The encrypted content.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\a\STX\EOT\ENQ\DC2\EOT\204\STX\STX\b\n\
    \\r\n\
    \\ENQ\EOT\a\STX\EOT\SOH\DC2\EOT\204\STX\t\SUB\n\
    \\r\n\
    \\ENQ\EOT\a\STX\EOT\ETX\DC2\EOT\204\STX\GS\RS\n\
    \I\n\
    \\EOT\EOT\a\STX\ENQ\DC2\EOT\207\STX\STX(\SUB; The citations that the model used to answer the question.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\a\STX\ENQ\EOT\DC2\EOT\207\STX\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\a\STX\ENQ\ACK\DC2\EOT\207\STX\v\EM\n\
    \\r\n\
    \\ENQ\EOT\a\STX\ENQ\SOH\DC2\EOT\207\STX\SUB#\n\
    \\r\n\
    \\ENQ\EOT\a\STX\ENQ\ETX\DC2\EOT\207\STX&'\n\
    \\f\n\
    \\STX\EOT\b\DC2\ACK\210\STX\NUL\241\STX\SOH\n\
    \\v\n\
    \\ETX\EOT\b\SOH\DC2\EOT\210\STX\b\SYN\n\
    \\229\SOH\n\
    \\EOT\EOT\b\STX\NUL\DC2\EOT\215\STX\STX\DLE\SUB\214\SOH The display number for this citation (e.g., \"1\", \"2\", \"3\").\n\
    \ This ID is reused when the same source is cited multiple times in a\n\
    \ response, ensuring consistent numbering (e.g., the same URL always shows as\n\
    \ [1]).\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\b\STX\NUL\ENQ\DC2\EOT\215\STX\STX\b\n\
    \\r\n\
    \\ENQ\EOT\b\STX\NUL\SOH\DC2\EOT\215\STX\t\v\n\
    \\r\n\
    \\ENQ\EOT\b\STX\NUL\ETX\DC2\EOT\215\STX\SO\SI\n\
    \\136\STX\n\
    \\EOT\EOT\b\STX\SOH\DC2\EOT\221\STX\STX\CAN\SUB\249\SOH The character position in the response text where the citation markdown\n\
    \ link begins. This is the index of the first '[' character in the citation\n\
    \ format [[id]](url). Uses inclusive indexing (the character at this index is\n\
    \ part of the citation).\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\b\STX\SOH\ENQ\DC2\EOT\221\STX\STX\a\n\
    \\r\n\
    \\ENQ\EOT\b\STX\SOH\SOH\DC2\EOT\221\STX\b\DC3\n\
    \\r\n\
    \\ENQ\EOT\b\STX\SOH\ETX\DC2\EOT\221\STX\SYN\ETB\n\
    \\242\STX\n\
    \\EOT\EOT\b\STX\STX\DC2\EOT\228\STX\STX\SYN\SUB\227\STX The character position in the response text immediately after the citation\n\
    \ markdown link ends. This is the index after the final ']' character in the\n\
    \ citation format [[id]](url). Uses exclusive indexing (the character at this\n\
    \ index is NOT part of the citation). Together with start_index,\n\
    \ text[start_index:end_index] extracts the full citation link.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\b\STX\STX\ENQ\DC2\EOT\228\STX\STX\a\n\
    \\r\n\
    \\ENQ\EOT\b\STX\STX\SOH\DC2\EOT\228\STX\b\DC1\n\
    \\r\n\
    \\ENQ\EOT\b\STX\STX\ETX\DC2\EOT\228\STX\DC4\NAK\n\
    \$\n\
    \\EOT\EOT\b\b\NUL\DC2\ACK\231\STX\STX\240\STX\ETX\SUB\DC4 The citation type.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\b\b\NUL\SOH\DC2\EOT\231\STX\b\DLE\n\
    \?\n\
    \\EOT\EOT\b\STX\ETX\DC2\EOT\233\STX\EOT!\SUB1 The citation returned from the web search tool.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\b\STX\ETX\ACK\DC2\EOT\233\STX\EOT\SI\n\
    \\r\n\
    \\ENQ\EOT\b\STX\ETX\SOH\DC2\EOT\233\STX\DLE\FS\n\
    \\r\n\
    \\ENQ\EOT\b\STX\ETX\ETX\DC2\EOT\233\STX\US \n\
    \=\n\
    \\EOT\EOT\b\STX\EOT\DC2\EOT\236\STX\EOT\GS\SUB/ The citation returned from the X search tool.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\b\STX\EOT\ACK\DC2\EOT\236\STX\EOT\r\n\
    \\r\n\
    \\ENQ\EOT\b\STX\EOT\SOH\DC2\EOT\236\STX\SO\CAN\n\
    \\r\n\
    \\ENQ\EOT\b\STX\EOT\ETX\DC2\EOT\236\STX\ESC\FS\n\
    \G\n\
    \\EOT\EOT\b\STX\ENQ\DC2\EOT\239\STX\EOT1\SUB9 The citation returned from the collections search tool.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\b\STX\ENQ\ACK\DC2\EOT\239\STX\EOT\ETB\n\
    \\r\n\
    \\ENQ\EOT\b\STX\ENQ\SOH\DC2\EOT\239\STX\CAN,\n\
    \\r\n\
    \\ENQ\EOT\b\STX\ENQ\ETX\DC2\EOT\239\STX/0\n\
    \\f\n\
    \\STX\EOT\t\DC2\ACK\243\STX\NUL\246\STX\SOH\n\
    \\v\n\
    \\ETX\EOT\t\SOH\DC2\EOT\243\STX\b\DC3\n\
    \B\n\
    \\EOT\EOT\t\STX\NUL\DC2\EOT\245\STX\STX\DC1\SUB4 The url of the web page that the citation is from.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\t\STX\NUL\ENQ\DC2\EOT\245\STX\STX\b\n\
    \\r\n\
    \\ENQ\EOT\t\STX\NUL\SOH\DC2\EOT\245\STX\t\f\n\
    \\r\n\
    \\ENQ\EOT\t\STX\NUL\ETX\DC2\EOT\245\STX\SI\DLE\n\
    \\f\n\
    \\STX\EOT\n\
    \\DC2\ACK\248\STX\NUL\252\STX\SOH\n\
    \\v\n\
    \\ETX\EOT\n\
    \\SOH\DC2\EOT\248\STX\b\DC1\n\
    \k\n\
    \\EOT\EOT\n\
    \\STX\NUL\DC2\EOT\251\STX\STX\DC1\SUB] The url of the X post or profile that the citation is from.\n\
    \ The url is always a x.com url.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\n\
    \\STX\NUL\ENQ\DC2\EOT\251\STX\STX\b\n\
    \\r\n\
    \\ENQ\EOT\n\
    \\STX\NUL\SOH\DC2\EOT\251\STX\t\f\n\
    \\r\n\
    \\ENQ\EOT\n\
    \\STX\NUL\ETX\DC2\EOT\251\STX\SI\DLE\n\
    \\f\n\
    \\STX\EOT\v\DC2\ACK\254\STX\NUL\141\ETX\SOH\n\
    \\v\n\
    \\ETX\EOT\v\SOH\DC2\EOT\254\STX\b\ESC\n\
    \=\n\
    \\EOT\EOT\v\STX\NUL\DC2\EOT\128\ETX\STX\NAK\SUB/ The id of the file that the citation is from.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\v\STX\NUL\ENQ\DC2\EOT\128\ETX\STX\b\n\
    \\r\n\
    \\ENQ\EOT\v\STX\NUL\SOH\DC2\EOT\128\ETX\t\DLE\n\
    \\r\n\
    \\ENQ\EOT\v\STX\NUL\ETX\DC2\EOT\128\ETX\DC3\DC4\n\
    \>\n\
    \\EOT\EOT\v\STX\SOH\DC2\EOT\131\ETX\STX\SYN\SUB0 The id of the chunk that the citation is from.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\v\STX\SOH\ENQ\DC2\EOT\131\ETX\STX\b\n\
    \\r\n\
    \\ENQ\EOT\v\STX\SOH\SOH\DC2\EOT\131\ETX\t\DC1\n\
    \\r\n\
    \\ENQ\EOT\v\STX\SOH\ETX\DC2\EOT\131\ETX\DC4\NAK\n\
    \C\n\
    \\EOT\EOT\v\STX\STX\DC2\EOT\134\ETX\STX\ESC\SUB5 The content of the chunk that the citation is from.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\v\STX\STX\ENQ\DC2\EOT\134\ETX\STX\b\n\
    \\r\n\
    \\ENQ\EOT\v\STX\STX\SOH\DC2\EOT\134\ETX\t\SYN\n\
    \\r\n\
    \\ENQ\EOT\v\STX\STX\ETX\DC2\EOT\134\ETX\EM\SUB\n\
    \4\n\
    \\EOT\EOT\v\STX\ETX\DC2\EOT\137\ETX\STX\DC2\SUB& The relevance score of the citation.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\v\STX\ETX\ENQ\DC2\EOT\137\ETX\STX\a\n\
    \\r\n\
    \\ENQ\EOT\v\STX\ETX\SOH\DC2\EOT\137\ETX\b\r\n\
    \\r\n\
    \\ENQ\EOT\v\STX\ETX\ETX\DC2\EOT\137\ETX\DLE\DC1\n\
    \E\n\
    \\EOT\EOT\v\STX\EOT\DC2\EOT\140\ETX\STX%\SUB7 The ids of the collections that the citation is from.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\v\STX\EOT\EOT\DC2\EOT\140\ETX\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\v\STX\EOT\ENQ\DC2\EOT\140\ETX\v\DC1\n\
    \\r\n\
    \\ENQ\EOT\v\STX\EOT\SOH\DC2\EOT\140\ETX\DC2 \n\
    \\r\n\
    \\ENQ\EOT\v\STX\EOT\ETX\DC2\EOT\140\ETX#$\n\
    \>\n\
    \\STX\EOT\f\DC2\ACK\144\ETX\NUL\148\ETX\SOH\SUB0 Holding the log probabilities of the sampling.\n\
    \\n\
    \\v\n\
    \\ETX\EOT\f\SOH\DC2\EOT\144\ETX\b\DLE\n\
    \r\n\
    \\EOT\EOT\f\STX\NUL\DC2\EOT\147\ETX\STX\US\SUBd A list of log probability entries, each corresponding to a sampled token\n\
    \ and its associated data.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\f\STX\NUL\EOT\DC2\EOT\147\ETX\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\f\STX\NUL\ACK\DC2\EOT\147\ETX\v\DC2\n\
    \\r\n\
    \\ENQ\EOT\f\STX\NUL\SOH\DC2\EOT\147\ETX\DC3\SUB\n\
    \\r\n\
    \\ENQ\EOT\f\STX\NUL\ETX\DC2\EOT\147\ETX\GS\RS\n\
    \`\n\
    \\STX\EOT\r\DC2\ACK\152\ETX\NUL\167\ETX\SOH\SUBR Represents the logarithmic probability and metadata for a single sampled\n\
    \ token.\n\
    \\n\
    \\v\n\
    \\ETX\EOT\r\SOH\DC2\EOT\152\ETX\b\SI\n\
    \=\n\
    \\EOT\EOT\r\STX\NUL\DC2\EOT\154\ETX\STX\DC3\SUB/ The text representation of the sampled token.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\r\STX\NUL\ENQ\DC2\EOT\154\ETX\STX\b\n\
    \\r\n\
    \\ENQ\EOT\r\STX\NUL\SOH\DC2\EOT\154\ETX\t\SO\n\
    \\r\n\
    \\ENQ\EOT\r\STX\NUL\ETX\DC2\EOT\154\ETX\DC1\DC2\n\
    \b\n\
    \\EOT\EOT\r\STX\SOH\DC2\EOT\158\ETX\STX\DC4\SUBT The logarithmic probability of this token being sampled, given the prior\n\
    \ context.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\r\STX\SOH\ENQ\DC2\EOT\158\ETX\STX\a\n\
    \\r\n\
    \\ENQ\EOT\r\STX\SOH\SOH\DC2\EOT\158\ETX\b\SI\n\
    \\r\n\
    \\ENQ\EOT\r\STX\SOH\ETX\DC2\EOT\158\ETX\DC2\DC3\n\
    \h\n\
    \\EOT\EOT\r\STX\STX\DC2\EOT\162\ETX\STX\DC2\SUBZ The raw byte representation of the token, useful for handling non-text or\n\
    \ encoded data.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\r\STX\STX\ENQ\DC2\EOT\162\ETX\STX\a\n\
    \\r\n\
    \\ENQ\EOT\r\STX\STX\SOH\DC2\EOT\162\ETX\b\r\n\
    \\r\n\
    \\ENQ\EOT\r\STX\STX\ETX\DC2\EOT\162\ETX\DLE\DC1\n\
    \h\n\
    \\EOT\EOT\r\STX\ETX\DC2\EOT\166\ETX\STX'\SUBZ A list of the top alternative tokens and their log probabilities at this\n\
    \ sampling step.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\r\STX\ETX\EOT\DC2\EOT\166\ETX\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\r\STX\ETX\ACK\DC2\EOT\166\ETX\v\NAK\n\
    \\r\n\
    \\ENQ\EOT\r\STX\ETX\SOH\DC2\EOT\166\ETX\SYN\"\n\
    \\r\n\
    \\ENQ\EOT\r\STX\ETX\ETX\DC2\EOT\166\ETX%&\n\
    \b\n\
    \\STX\EOT\SO\DC2\ACK\171\ETX\NUL\180\ETX\SOH\SUBT Represents an alternative token and its log probability among the top\n\
    \ candidates.\n\
    \\n\
    \\v\n\
    \\ETX\EOT\SO\SOH\DC2\EOT\171\ETX\b\DC2\n\
    \X\n\
    \\EOT\EOT\SO\STX\NUL\DC2\EOT\173\ETX\STX\DC3\SUBJ The text representation of an alternative token considered by the model.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\SO\STX\NUL\ENQ\DC2\EOT\173\ETX\STX\b\n\
    \\r\n\
    \\ENQ\EOT\SO\STX\NUL\SOH\DC2\EOT\173\ETX\t\SO\n\
    \\r\n\
    \\ENQ\EOT\SO\STX\NUL\ETX\DC2\EOT\173\ETX\DC1\DC2\n\
    \T\n\
    \\EOT\EOT\SO\STX\SOH\DC2\EOT\176\ETX\STX\DC4\SUBF The logarithmic probability of this alternative token being sampled.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\SO\STX\SOH\ENQ\DC2\EOT\176\ETX\STX\a\n\
    \\r\n\
    \\ENQ\EOT\SO\STX\SOH\SOH\DC2\EOT\176\ETX\b\SI\n\
    \\r\n\
    \\ENQ\EOT\SO\STX\SOH\ETX\DC2\EOT\176\ETX\DC2\DC3\n\
    \E\n\
    \\EOT\EOT\SO\STX\STX\DC2\EOT\179\ETX\STX\DC2\SUB7 The raw byte representation of the alternative token.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\SO\STX\STX\ENQ\DC2\EOT\179\ETX\STX\a\n\
    \\r\n\
    \\ENQ\EOT\SO\STX\STX\SOH\DC2\EOT\179\ETX\b\r\n\
    \\r\n\
    \\ENQ\EOT\SO\STX\STX\ETX\DC2\EOT\179\ETX\DLE\DC1\n\
    \P\n\
    \\STX\EOT\SI\DC2\ACK\183\ETX\NUL\194\ETX\SOH\SUBB Holds a single content element that is part of an input message.\n\
    \\n\
    \\v\n\
    \\ETX\EOT\SI\SOH\DC2\EOT\183\ETX\b\SI\n\
    \\SO\n\
    \\EOT\EOT\SI\b\NUL\DC2\ACK\184\ETX\STX\193\ETX\ETX\n\
    \\r\n\
    \\ENQ\EOT\SI\b\NUL\SOH\DC2\EOT\184\ETX\b\SI\n\
    \3\n\
    \\EOT\EOT\SI\STX\NUL\DC2\EOT\186\ETX\EOT\DC4\SUB% The content is a pure text message.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\SI\STX\NUL\ENQ\DC2\EOT\186\ETX\EOT\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\SI\STX\NUL\SOH\DC2\EOT\186\ETX\v\SI\n\
    \\r\n\
    \\ENQ\EOT\SI\STX\NUL\ETX\DC2\EOT\186\ETX\DC2\DC3\n\
    \.\n\
    \\EOT\EOT\SI\STX\SOH\DC2\EOT\189\ETX\EOT\"\SUB  The content is a single image.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\SI\STX\SOH\ACK\DC2\EOT\189\ETX\EOT\DC3\n\
    \\r\n\
    \\ENQ\EOT\SI\STX\SOH\SOH\DC2\EOT\189\ETX\DC4\GS\n\
    \\r\n\
    \\ENQ\EOT\SI\STX\SOH\ETX\DC2\EOT\189\ETX !\n\
    \G\n\
    \\EOT\EOT\SI\STX\STX\DC2\EOT\192\ETX\EOT\EM\SUB9 The content is a file attachment (PDF, document, etc.).\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\SI\STX\STX\ACK\DC2\EOT\192\ETX\EOT\SI\n\
    \\r\n\
    \\ENQ\EOT\SI\STX\STX\SOH\DC2\EOT\192\ETX\DLE\DC4\n\
    \\r\n\
    \\ENQ\EOT\SI\STX\STX\ETX\DC2\EOT\192\ETX\ETB\CAN\n\
    \/\n\
    \\STX\EOT\DLE\DC2\ACK\197\ETX\NUL\228\ETX\SOH\SUB! A file attachment in a message.\n\
    \\n\
    \\v\n\
    \\ETX\EOT\DLE\SOH\DC2\EOT\197\ETX\b\DC3\n\
    \o\n\
    \\EOT\EOT\DLE\STX\NUL\DC2\EOT\201\ETX\STX\NAK\SUBa The file ID from the Files API.\n\
    \\n\
    \ When set, the file content will be fetched via the Files API.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\DLE\STX\NUL\ENQ\DC2\EOT\201\ETX\STX\b\n\
    \\r\n\
    \\ENQ\EOT\DLE\STX\NUL\SOH\DC2\EOT\201\ETX\t\DLE\n\
    \\r\n\
    \\ENQ\EOT\DLE\STX\NUL\ETX\DC2\EOT\201\ETX\DC3\DC4\n\
    \\232\SOH\n\
    \\EOT\EOT\DLE\STX\SOH\DC2\EOT\209\ETX\STX\DC1\SUB\217\SOH Inline file bytes (optional).\n\
    \\n\
    \ When set, the file content is provided directly in the chat request and does\n\
    \ NOT require uploading to the Files API first.\n\
    \\n\
    \ Exactly one of `file_id`, `data`, or `url` SHOULD be set.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\DLE\STX\SOH\ENQ\DC2\EOT\209\ETX\STX\a\n\
    \\r\n\
    \\ENQ\EOT\DLE\STX\SOH\SOH\DC2\EOT\209\ETX\b\f\n\
    \\r\n\
    \\ENQ\EOT\DLE\STX\SOH\ETX\DC2\EOT\209\ETX\SI\DLE\n\
    \\155\SOH\n\
    \\EOT\EOT\DLE\STX\STX\DC2\EOT\215\ETX\STX\SYN\SUB\140\SOH Filename for inline uploads.\n\
    \\n\
    \ Recommended when `data` is set. Used for display and may be used by\n\
    \ downstream systems to infer file type.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\DLE\STX\STX\ENQ\DC2\EOT\215\ETX\STX\b\n\
    \\r\n\
    \\ENQ\EOT\DLE\STX\STX\SOH\DC2\EOT\215\ETX\t\DC1\n\
    \\r\n\
    \\ENQ\EOT\DLE\STX\STX\ETX\DC2\EOT\215\ETX\DC4\NAK\n\
    \\181\SOH\n\
    \\EOT\EOT\DLE\STX\ETX\DC2\EOT\221\ETX\STX\ETB\SUB\166\SOH Optional MIME type for inline uploads (e.g. \"application/pdf\").\n\
    \\n\
    \ If unset, downstream systems may attempt to infer the MIME type from the\n\
    \ content and/or filename.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\DLE\STX\ETX\ENQ\DC2\EOT\221\ETX\STX\b\n\
    \\r\n\
    \\ENQ\EOT\DLE\STX\ETX\SOH\DC2\EOT\221\ETX\t\DC2\n\
    \\r\n\
    \\ENQ\EOT\DLE\STX\ETX\ETX\DC2\EOT\221\ETX\NAK\SYN\n\
    \\177\SOH\n\
    \\EOT\EOT\DLE\STX\EOT\DC2\EOT\227\ETX\STX\DC1\SUB\162\SOH Public URL to a file attachment.\n\
    \\n\
    \ When set, the file will be fetched from this URL as an attachment.\n\
    \ Exactly one of `file_id`, `data`, or `url` SHOULD be set.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\DLE\STX\EOT\ENQ\DC2\EOT\227\ETX\STX\b\n\
    \\r\n\
    \\ENQ\EOT\DLE\STX\EOT\SOH\DC2\EOT\227\ETX\t\f\n\
    \\r\n\
    \\ENQ\EOT\DLE\STX\EOT\ETX\DC2\EOT\227\ETX\SI\DLE\n\
    \\f\n\
    \\STX\ENQ\NUL\DC2\ACK\230\ETX\NUL\134\EOT\SOH\n\
    \\v\n\
    \\ETX\ENQ\NUL\SOH\DC2\EOT\230\ETX\ENQ\DC2\n\
    \/\n\
    \\EOT\ENQ\NUL\STX\NUL\DC2\EOT\232\ETX\STX\GS\SUB! Default value / invalid option.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\NUL\STX\NUL\SOH\DC2\EOT\232\ETX\STX\CAN\n\
    \\r\n\
    \\ENQ\ENQ\NUL\STX\NUL\STX\DC2\EOT\232\ETX\ESC\FS\n\
    \V\n\
    \\EOT\ENQ\NUL\STX\SOH\DC2\EOT\235\ETX\STX,\SUBH Include the encrypted output from the web search tool in the response.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\NUL\STX\SOH\SOH\DC2\EOT\235\ETX\STX'\n\
    \\r\n\
    \\ENQ\ENQ\NUL\STX\SOH\STX\DC2\EOT\235\ETX*+\n\
    \T\n\
    \\EOT\ENQ\NUL\STX\STX\DC2\EOT\238\ETX\STX*\SUBF Include the encrypted output from the X search tool in the response.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\NUL\STX\STX\SOH\DC2\EOT\238\ETX\STX%\n\
    \\r\n\
    \\ENQ\ENQ\NUL\STX\STX\STX\DC2\EOT\238\ETX()\n\
    \Z\n\
    \\EOT\ENQ\NUL\STX\ETX\DC2\EOT\241\ETX\STX0\SUBL Include the plaintext output from the code execution tool in the response.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\NUL\STX\ETX\SOH\DC2\EOT\241\ETX\STX+\n\
    \\r\n\
    \\ENQ\ENQ\NUL\STX\ETX\STX\DC2\EOT\241\ETX./\n\
    \^\n\
    \\EOT\ENQ\NUL\STX\EOT\DC2\EOT\244\ETX\STX4\SUBP Include the plaintext output from the collections search tool in the response.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\NUL\STX\EOT\SOH\DC2\EOT\244\ETX\STX/\n\
    \\r\n\
    \\ENQ\ENQ\NUL\STX\EOT\STX\DC2\EOT\244\ETX23\n\
    \]\n\
    \\EOT\ENQ\NUL\STX\ENQ\DC2\EOT\247\ETX\STX3\SUBO Include the plaintext output from the attachment search tool in the response.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\NUL\STX\ENQ\SOH\DC2\EOT\247\ETX\STX.\n\
    \\r\n\
    \\ENQ\ENQ\NUL\STX\ENQ\STX\DC2\EOT\247\ETX12\n\
    \O\n\
    \\EOT\ENQ\NUL\STX\ACK\DC2\EOT\250\ETX\STX%\SUBA Include the plaintext output from the MCP tool in the response.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\NUL\STX\ACK\SOH\DC2\EOT\250\ETX\STX \n\
    \\r\n\
    \\ENQ\ENQ\NUL\STX\ACK\STX\DC2\EOT\250\ETX#$\n\
    \C\n\
    \\EOT\ENQ\NUL\STX\a\DC2\EOT\253\ETX\STX&\SUB5 Include the inline citations in the final response.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\NUL\STX\a\SOH\DC2\EOT\253\ETX\STX!\n\
    \\r\n\
    \\ENQ\ENQ\NUL\STX\a\STX\DC2\EOT\253\ETX$%\n\
    \\243\STX\n\
    \\EOT\ENQ\NUL\STX\b\DC2\EOT\133\EOT\STX'\SUB\228\STX Stream back any chunks that are generated by the model or the agent tools\n\
    \ even if there is no user-visible content in the chunk, e.g. only the usage\n\
    \ statistics are being updated.\n\
    \ The chunks without user-visible content are not streamed to the client when\n\
    \ this option is not included by default.\n\
    \ This option is only available for streaming responses.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\NUL\STX\b\SOH\DC2\EOT\133\EOT\STX\"\n\
    \\r\n\
    \\ENQ\ENQ\NUL\STX\b\STX\DC2\EOT\133\EOT%&\n\
    \\254\SOH\n\
    \\STX\EOT\DC1\DC2\ACK\140\EOT\NUL\165\EOT\SOH\SUB\239\SOH A message in a conversation. This message is part of the model input. Each\n\
    \ message originates from a \"role\", which indicates the entity type who sent\n\
    \ the message. Messages can contain multiple content elements such as text and\n\
    \ images.\n\
    \\n\
    \\v\n\
    \\ETX\EOT\DC1\SOH\DC2\EOT\140\EOT\b\SI\n\
    \\186\SOH\n\
    \\EOT\EOT\DC1\STX\NUL\DC2\EOT\144\EOT\STX\US\SUB\171\SOH The content of the message. Some model support multi-modal message contents\n\
    \ that consist of text and images. At least one content element must be set\n\
    \ for each message.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\DC1\STX\NUL\EOT\DC2\EOT\144\EOT\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\DC1\STX\NUL\ACK\DC2\EOT\144\EOT\v\DC2\n\
    \\r\n\
    \\ENQ\EOT\DC1\STX\NUL\SOH\DC2\EOT\144\EOT\DC3\SUB\n\
    \\r\n\
    \\ENQ\EOT\DC1\STX\NUL\ETX\DC2\EOT\144\EOT\GS\RS\n\
    \S\n\
    \\EOT\EOT\DC1\STX\SOH\DC2\EOT\147\EOT\STX(\SUBE Reasoning trace the model produced before issuing the final answer.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\DC1\STX\SOH\EOT\DC2\EOT\147\EOT\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\DC1\STX\SOH\ENQ\DC2\EOT\147\EOT\v\DC1\n\
    \\r\n\
    \\ENQ\EOT\DC1\STX\SOH\SOH\DC2\EOT\147\EOT\DC2#\n\
    \\r\n\
    \\ENQ\EOT\DC1\STX\SOH\ETX\DC2\EOT\147\EOT&'\n\
    \u\n\
    \\EOT\EOT\DC1\STX\STX\DC2\EOT\151\EOT\STX\ETB\SUBg The entity type who sent the message. For example, a message can be sent by\n\
    \ a user or the assistant.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\DC1\STX\STX\ACK\DC2\EOT\151\EOT\STX\r\n\
    \\r\n\
    \\ENQ\EOT\DC1\STX\STX\SOH\DC2\EOT\151\EOT\SO\DC2\n\
    \\r\n\
    \\ENQ\EOT\DC1\STX\STX\ETX\DC2\EOT\151\EOT\NAK\SYN\n\
    \p\n\
    \\EOT\EOT\DC1\STX\ETX\DC2\EOT\155\EOT\STX\DC2\SUBb The name of the entity who sent the message. The name can only be set if\n\
    \ the role is ROLE_USER.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\DC1\STX\ETX\ENQ\DC2\EOT\155\EOT\STX\b\n\
    \\r\n\
    \\ENQ\EOT\DC1\STX\ETX\SOH\DC2\EOT\155\EOT\t\r\n\
    \\r\n\
    \\ENQ\EOT\DC1\STX\ETX\ETX\DC2\EOT\155\EOT\DLE\DC1\n\
    \;\n\
    \\EOT\EOT\DC1\STX\EOT\DC2\EOT\158\EOT\STX#\SUB- The tools that the assistant wants to call.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\DC1\STX\EOT\EOT\DC2\EOT\158\EOT\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\DC1\STX\EOT\ACK\DC2\EOT\158\EOT\v\DC3\n\
    \\r\n\
    \\ENQ\EOT\DC1\STX\EOT\SOH\DC2\EOT\158\EOT\DC4\RS\n\
    \\r\n\
    \\ENQ\EOT\DC1\STX\EOT\ETX\DC2\EOT\158\EOT!\"\n\
    \&\n\
    \\EOT\EOT\DC1\STX\ENQ\DC2\EOT\161\EOT\STX\US\SUB\CAN The encrypted content.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\DC1\STX\ENQ\ENQ\DC2\EOT\161\EOT\STX\b\n\
    \\r\n\
    \\ENQ\EOT\DC1\STX\ENQ\SOH\DC2\EOT\161\EOT\t\SUB\n\
    \\r\n\
    \\ENQ\EOT\DC1\STX\ENQ\ETX\DC2\EOT\161\EOT\GS\RS\n\
    \e\n\
    \\EOT\EOT\DC1\STX\ACK\DC2\EOT\164\EOT\STX#\SUBW The ID associating this tool response with a prior invocation (for role = ROLE_TOOL).\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\DC1\STX\ACK\EOT\DC2\EOT\164\EOT\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\DC1\STX\ACK\ENQ\DC2\EOT\164\EOT\v\DC1\n\
    \\r\n\
    \\ENQ\EOT\DC1\STX\ACK\SOH\DC2\EOT\164\EOT\DC2\RS\n\
    \\r\n\
    \\ENQ\EOT\DC1\STX\ACK\ETX\DC2\EOT\164\EOT!\"\n\
    \\f\n\
    \\STX\ENQ\SOH\DC2\ACK\167\EOT\NUL\188\EOT\SOH\n\
    \\v\n\
    \\ETX\ENQ\SOH\SOH\DC2\EOT\167\EOT\ENQ\DLE\n\
    \-\n\
    \\EOT\ENQ\SOH\STX\NUL\DC2\EOT\169\EOT\STX\DC3\SUB\US Default value / invalid role.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\SOH\STX\NUL\SOH\DC2\EOT\169\EOT\STX\SO\n\
    \\r\n\
    \\ENQ\ENQ\SOH\STX\NUL\STX\DC2\EOT\169\EOT\DC1\DC2\n\
    \\SUB\n\
    \\EOT\ENQ\SOH\STX\SOH\DC2\EOT\172\EOT\STX\DLE\SUB\f User role.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\SOH\STX\SOH\SOH\DC2\EOT\172\EOT\STX\v\n\
    \\r\n\
    \\ENQ\ENQ\SOH\STX\SOH\STX\DC2\EOT\172\EOT\SO\SI\n\
    \E\n\
    \\EOT\ENQ\SOH\STX\STX\DC2\EOT\175\EOT\STX\NAK\SUB7 Assistant role, normally the response from the model.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\SOH\STX\STX\SOH\DC2\EOT\175\EOT\STX\DLE\n\
    \\r\n\
    \\ENQ\ENQ\SOH\STX\STX\STX\DC2\EOT\175\EOT\DC3\DC4\n\
    \?\n\
    \\EOT\ENQ\SOH\STX\ETX\DC2\EOT\178\EOT\STX\DC2\SUB1 System role, typically for system instructions.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\SOH\STX\ETX\SOH\DC2\EOT\178\EOT\STX\r\n\
    \\r\n\
    \\ENQ\ENQ\SOH\STX\ETX\STX\DC2\EOT\178\EOT\DLE\DC1\n\
    \V\n\
    \\EOT\ENQ\SOH\STX\EOT\DC2\EOT\181\EOT\STX(\SUBH Indicates a return from a tool call. Deprecated in favor of ROLE_TOOL.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\SOH\STX\EOT\SOH\DC2\EOT\181\EOT\STX\SI\n\
    \\r\n\
    \\ENQ\ENQ\SOH\STX\EOT\STX\DC2\EOT\181\EOT\DC2\DC3\n\
    \\r\n\
    \\ENQ\ENQ\SOH\STX\EOT\ETX\DC2\EOT\181\EOT\DC4'\n\
    \\SO\n\
    \\ACK\ENQ\SOH\STX\EOT\ETX\SOH\DC2\EOT\181\EOT\NAK&\n\
    \4\n\
    \\EOT\ENQ\SOH\STX\ENQ\DC2\EOT\184\EOT\STX\DLE\SUB& Indicates a return from a tool call.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\SOH\STX\ENQ\SOH\DC2\EOT\184\EOT\STX\v\n\
    \\r\n\
    \\ENQ\ENQ\SOH\STX\ENQ\STX\DC2\EOT\184\EOT\SO\SI\n\
    \c\n\
    \\EOT\ENQ\SOH\STX\ACK\DC2\EOT\187\EOT\STX\NAK\SUBU Developer role, typically for developer instructions, e.g. tool usage instructions.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\SOH\STX\ACK\SOH\DC2\EOT\187\EOT\STX\DLE\n\
    \\r\n\
    \\ENQ\ENQ\SOH\STX\ACK\STX\DC2\EOT\187\EOT\DC3\DC4\n\
    \\f\n\
    \\STX\ENQ\STX\DC2\ACK\190\EOT\NUL\196\EOT\SOH\n\
    \\v\n\
    \\ETX\ENQ\STX\SOH\DC2\EOT\190\EOT\ENQ\DC4\n\
    \\f\n\
    \\EOT\ENQ\STX\STX\NUL\DC2\EOT\191\EOT\STX\NAK\n\
    \\r\n\
    \\ENQ\ENQ\STX\STX\NUL\SOH\DC2\EOT\191\EOT\STX\DLE\n\
    \\r\n\
    \\ENQ\ENQ\STX\STX\NUL\STX\DC2\EOT\191\EOT\DC3\DC4\n\
    \\f\n\
    \\EOT\ENQ\STX\STX\SOH\DC2\EOT\192\EOT\STX\DC1\n\
    \\r\n\
    \\ENQ\ENQ\STX\STX\SOH\SOH\DC2\EOT\192\EOT\STX\f\n\
    \\r\n\
    \\ENQ\ENQ\STX\STX\SOH\STX\DC2\EOT\192\EOT\SI\DLE\n\
    \\f\n\
    \\EOT\ENQ\STX\STX\STX\DC2\EOT\193\EOT\STX\DC4\n\
    \\r\n\
    \\ENQ\ENQ\STX\STX\STX\SOH\DC2\EOT\193\EOT\STX\SI\n\
    \\r\n\
    \\ENQ\ENQ\STX\STX\STX\STX\DC2\EOT\193\EOT\DC2\DC3\n\
    \\f\n\
    \\EOT\ENQ\STX\STX\ETX\DC2\EOT\194\EOT\STX\DC2\n\
    \\r\n\
    \\ENQ\ENQ\STX\STX\ETX\SOH\DC2\EOT\194\EOT\STX\r\n\
    \\r\n\
    \\ENQ\ENQ\STX\STX\ETX\STX\DC2\EOT\194\EOT\DLE\DC1\n\
    \\f\n\
    \\EOT\ENQ\STX\STX\EOT\DC2\EOT\195\EOT\STX\DC2\n\
    \\r\n\
    \\ENQ\ENQ\STX\STX\EOT\SOH\DC2\EOT\195\EOT\STX\r\n\
    \\r\n\
    \\ENQ\ENQ\STX\STX\EOT\STX\DC2\EOT\195\EOT\DLE\DC1\n\
    \?\n\
    \\STX\ENQ\ETX\DC2\ACK\199\EOT\NUL\206\EOT\SOH\SUB1 Number of agents to use for multi-agent models.\n\
    \\n\
    \\v\n\
    \\ETX\ENQ\ETX\SOH\DC2\EOT\199\EOT\ENQ\SI\n\
    \*\n\
    \\EOT\ENQ\ETX\STX\NUL\DC2\EOT\201\EOT\STX\RS\SUB\FS Unspecified / unset value.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\ETX\STX\NUL\SOH\DC2\EOT\201\EOT\STX\EM\n\
    \\r\n\
    \\ENQ\ENQ\ETX\STX\NUL\STX\DC2\EOT\201\EOT\FS\GS\n\
    \\GS\n\
    \\EOT\ENQ\ETX\STX\SOH\DC2\EOT\203\EOT\STX\DC4\SUB\SI Use 4 agents.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\ETX\STX\SOH\SOH\DC2\EOT\203\EOT\STX\SI\n\
    \\r\n\
    \\ENQ\ENQ\ETX\STX\SOH\STX\DC2\EOT\203\EOT\DC2\DC3\n\
    \\RS\n\
    \\EOT\ENQ\ETX\STX\STX\DC2\EOT\205\EOT\STX\NAK\SUB\DLE Use 16 agents.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\ETX\STX\STX\SOH\DC2\EOT\205\EOT\STX\DLE\n\
    \\r\n\
    \\ENQ\ENQ\ETX\STX\STX\STX\DC2\EOT\205\EOT\DC3\DC4\n\
    \\f\n\
    \\STX\ENQ\EOT\DC2\ACK\208\EOT\NUL\220\EOT\SOH\n\
    \\v\n\
    \\ETX\ENQ\EOT\SOH\DC2\EOT\208\EOT\ENQ\r\n\
    \\"\n\
    \\EOT\ENQ\EOT\STX\NUL\DC2\EOT\210\EOT\STX\CAN\SUB\DC4 Invalid tool mode.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\EOT\STX\NUL\SOH\DC2\EOT\210\EOT\STX\DC3\n\
    \\r\n\
    \\ENQ\ENQ\EOT\STX\NUL\STX\DC2\EOT\210\EOT\SYN\ETB\n\
    \=\n\
    \\EOT\ENQ\EOT\STX\SOH\DC2\EOT\213\EOT\STX\NAK\SUB/ Let the model decide if a tool shall be used.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\EOT\STX\SOH\SOH\DC2\EOT\213\EOT\STX\DLE\n\
    \\r\n\
    \\ENQ\ENQ\EOT\STX\SOH\STX\DC2\EOT\213\EOT\DC3\DC4\n\
    \1\n\
    \\EOT\ENQ\EOT\STX\STX\DC2\EOT\216\EOT\STX\NAK\SUB# Force the model to not use tools.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\EOT\STX\STX\SOH\DC2\EOT\216\EOT\STX\DLE\n\
    \\r\n\
    \\ENQ\ENQ\EOT\STX\STX\STX\DC2\EOT\216\EOT\DC3\DC4\n\
    \-\n\
    \\EOT\ENQ\EOT\STX\ETX\DC2\EOT\219\EOT\STX\EM\SUB\US Force the model to use tools.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\EOT\STX\ETX\SOH\DC2\EOT\219\EOT\STX\DC4\n\
    \\r\n\
    \\ENQ\ENQ\EOT\STX\ETX\STX\DC2\EOT\219\EOT\ETB\CAN\n\
    \\f\n\
    \\STX\ENQ\ENQ\DC2\ACK\222\EOT\NUL\231\EOT\SOH\n\
    \\v\n\
    \\ETX\ENQ\ENQ\SOH\DC2\EOT\222\EOT\ENQ\SI\n\
    \$\n\
    \\EOT\ENQ\ENQ\STX\NUL\DC2\EOT\224\EOT\STX\SUB\SUB\SYN Invalid format type.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\ENQ\STX\NUL\SOH\DC2\EOT\224\EOT\STX\NAK\n\
    \\r\n\
    \\ENQ\ENQ\ENQ\STX\NUL\STX\DC2\EOT\224\EOT\CAN\EM\n\
    \\EM\n\
    \\EOT\ENQ\ENQ\STX\SOH\DC2\EOT\226\EOT\STX\ETB\SUB\v Raw text.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\ENQ\STX\SOH\SOH\DC2\EOT\226\EOT\STX\DC2\n\
    \\r\n\
    \\ENQ\ENQ\ENQ\STX\SOH\STX\DC2\EOT\226\EOT\NAK\SYN\n\
    \ \n\
    \\EOT\ENQ\ENQ\STX\STX\DC2\EOT\228\EOT\STX\RS\SUB\DC2 Any JSON object.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\ENQ\STX\STX\SOH\DC2\EOT\228\EOT\STX\EM\n\
    \\r\n\
    \\ENQ\ENQ\ENQ\STX\STX\STX\DC2\EOT\228\EOT\FS\GS\n\
    \%\n\
    \\EOT\ENQ\ENQ\STX\ETX\DC2\EOT\230\EOT\STX\RS\SUB\ETB Follow a JSON schema.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\ENQ\STX\ETX\SOH\DC2\EOT\230\EOT\STX\EM\n\
    \\r\n\
    \\ENQ\ENQ\ENQ\STX\ETX\STX\DC2\EOT\230\EOT\FS\GS\n\
    \\f\n\
    \\STX\EOT\DC2\DC2\ACK\233\EOT\NUL\241\EOT\SOH\n\
    \\v\n\
    \\ETX\EOT\DC2\SOH\DC2\EOT\233\EOT\b\DC2\n\
    \\SO\n\
    \\EOT\EOT\DC2\b\NUL\DC2\ACK\234\EOT\STX\240\EOT\ETX\n\
    \\r\n\
    \\ENQ\EOT\DC2\b\NUL\SOH\DC2\EOT\234\EOT\b\DC3\n\
    \;\n\
    \\EOT\EOT\DC2\STX\NUL\DC2\EOT\236\EOT\EOT\SYN\SUB- Force the model to perform in a given mode.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\DC2\STX\NUL\ACK\DC2\EOT\236\EOT\EOT\f\n\
    \\r\n\
    \\ENQ\EOT\DC2\STX\NUL\SOH\DC2\EOT\236\EOT\r\DC1\n\
    \\r\n\
    \\ENQ\EOT\DC2\STX\NUL\ETX\DC2\EOT\236\EOT\DC4\NAK\n\
    \>\n\
    \\EOT\EOT\DC2\STX\SOH\DC2\EOT\239\EOT\EOT\GS\SUB0 Force the model to call a particular function.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\DC2\STX\SOH\ENQ\DC2\EOT\239\EOT\EOT\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\DC2\STX\SOH\SOH\DC2\EOT\239\EOT\v\CAN\n\
    \\r\n\
    \\ENQ\EOT\DC2\STX\SOH\ETX\DC2\EOT\239\EOT\ESC\FS\n\
    \\f\n\
    \\STX\EOT\DC3\DC2\ACK\243\EOT\NUL\132\ENQ\SOH\n\
    \\v\n\
    \\ETX\EOT\DC3\SOH\DC2\EOT\243\EOT\b\f\n\
    \\SO\n\
    \\EOT\EOT\DC3\b\NUL\DC2\ACK\244\EOT\STX\131\ENQ\ETX\n\
    \\r\n\
    \\ENQ\EOT\DC3\b\NUL\SOH\DC2\EOT\244\EOT\b\f\n\
    \)\n\
    \\EOT\EOT\DC3\STX\NUL\DC2\EOT\246\EOT\EOT\SUB\SUB\ESC Tool Call defined by user\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\DC3\STX\NUL\ACK\DC2\EOT\246\EOT\EOT\f\n\
    \\r\n\
    \\ENQ\EOT\DC3\STX\NUL\SOH\DC2\EOT\246\EOT\r\NAK\n\
    \\r\n\
    \\ENQ\EOT\DC3\STX\NUL\ETX\DC2\EOT\246\EOT\CAN\EM\n\
    \$\n\
    \\EOT\EOT\DC3\STX\SOH\DC2\EOT\248\EOT\EOT\GS\SUB\SYN Built in web search.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\DC3\STX\SOH\ACK\DC2\EOT\248\EOT\EOT\r\n\
    \\r\n\
    \\ENQ\EOT\DC3\STX\SOH\SOH\DC2\EOT\248\EOT\SO\CAN\n\
    \\r\n\
    \\ENQ\EOT\DC3\STX\SOH\ETX\DC2\EOT\248\EOT\ESC\FS\n\
    \\"\n\
    \\EOT\EOT\DC3\STX\STX\DC2\EOT\250\EOT\EOT\EM\SUB\DC4 Built in X search.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\DC3\STX\STX\ACK\DC2\EOT\250\EOT\EOT\v\n\
    \\r\n\
    \\ENQ\EOT\DC3\STX\STX\SOH\DC2\EOT\250\EOT\f\DC4\n\
    \\r\n\
    \\ENQ\EOT\DC3\STX\STX\ETX\DC2\EOT\250\EOT\ETB\CAN\n\
    \(\n\
    \\EOT\EOT\DC3\STX\ETX\DC2\EOT\252\EOT\EOT%\SUB\SUB Built in code execution.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\DC3\STX\ETX\ACK\DC2\EOT\252\EOT\EOT\DC1\n\
    \\r\n\
    \\ENQ\EOT\DC3\STX\ETX\SOH\DC2\EOT\252\EOT\DC2 \n\
    \\r\n\
    \\ENQ\EOT\DC3\STX\ETX\ETX\DC2\EOT\252\EOT#$\n\
    \,\n\
    \\EOT\EOT\DC3\STX\EOT\DC2\EOT\254\EOT\EOT-\SUB\RS Built in collections search.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\DC3\STX\EOT\ACK\DC2\EOT\254\EOT\EOT\NAK\n\
    \\r\n\
    \\ENQ\EOT\DC3\STX\EOT\SOH\DC2\EOT\254\EOT\SYN(\n\
    \\r\n\
    \\ENQ\EOT\DC3\STX\EOT\ETX\DC2\EOT\254\EOT+,\n\
    \+\n\
    \\EOT\EOT\DC3\STX\ENQ\DC2\EOT\128\ENQ\EOT\DLE\SUB\GS A remote MCP server to use.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\DC3\STX\ENQ\ACK\DC2\EOT\128\ENQ\EOT\a\n\
    \\r\n\
    \\ENQ\EOT\DC3\STX\ENQ\SOH\DC2\EOT\128\ENQ\b\v\n\
    \\r\n\
    \\ENQ\EOT\DC3\STX\ENQ\ETX\DC2\EOT\128\ENQ\SO\SI\n\
    \+\n\
    \\EOT\EOT\DC3\STX\ACK\DC2\EOT\130\ENQ\EOT+\SUB\GS Built in attachment search.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\DC3\STX\ACK\ACK\DC2\EOT\130\ENQ\EOT\DC4\n\
    \\r\n\
    \\ENQ\EOT\DC3\STX\ACK\SOH\DC2\EOT\130\ENQ\NAK&\n\
    \\r\n\
    \\ENQ\EOT\DC3\STX\ACK\ETX\DC2\EOT\130\ENQ)*\n\
    \\f\n\
    \\STX\EOT\DC4\DC2\ACK\134\ENQ\NUL\147\ENQ\SOH\n\
    \\v\n\
    \\ETX\EOT\DC4\SOH\DC2\EOT\134\ENQ\b\v\n\
    \\\\n\
    \\EOT\EOT\DC4\STX\NUL\DC2\EOT\136\ENQ\STX\SUB\SUBN A label for the server. if provided, this will be used to prefix tool calls.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\DC4\STX\NUL\ENQ\DC2\EOT\136\ENQ\STX\b\n\
    \\r\n\
    \\ENQ\EOT\DC4\STX\NUL\SOH\DC2\EOT\136\ENQ\t\NAK\n\
    \\r\n\
    \\ENQ\EOT\DC4\STX\NUL\ETX\DC2\EOT\136\ENQ\CAN\EM\n\
    \,\n\
    \\EOT\EOT\DC4\STX\SOH\DC2\EOT\138\ENQ\STX \SUB\RS A description of the server.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\DC4\STX\SOH\ENQ\DC2\EOT\138\ENQ\STX\b\n\
    \\r\n\
    \\ENQ\EOT\DC4\STX\SOH\SOH\DC2\EOT\138\ENQ\t\ESC\n\
    \\r\n\
    \\ENQ\EOT\DC4\STX\SOH\ETX\DC2\EOT\138\ENQ\RS\US\n\
    \*\n\
    \\EOT\EOT\DC4\STX\STX\DC2\EOT\140\ENQ\STX\CAN\SUB\FS The URL of the MCP server.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\DC4\STX\STX\ENQ\DC2\EOT\140\ENQ\STX\b\n\
    \\r\n\
    \\ENQ\EOT\DC4\STX\STX\SOH\DC2\EOT\140\ENQ\t\DC3\n\
    \\r\n\
    \\ENQ\EOT\DC4\STX\STX\ETX\DC2\EOT\140\ENQ\SYN\ETB\n\
    \q\n\
    \\EOT\EOT\DC4\STX\ETX\DC2\EOT\142\ENQ\STX)\SUBc A list of tool names that are allowed to be called by the model. If empty, all tools are allowed.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\DC4\STX\ETX\EOT\DC2\EOT\142\ENQ\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\DC4\STX\ETX\ENQ\DC2\EOT\142\ENQ\v\DC1\n\
    \\r\n\
    \\ENQ\EOT\DC4\STX\ETX\SOH\DC2\EOT\142\ENQ\DC2$\n\
    \\r\n\
    \\ENQ\EOT\DC4\STX\ETX\ETX\DC2\EOT\142\ENQ'(\n\
    \\129\SOH\n\
    \\EOT\EOT\DC4\STX\EOT\DC2\EOT\144\ENQ\STX$\SUBs An optional authorization token to use when calling the MCP server. This will be set as the Authorization header.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\DC4\STX\EOT\EOT\DC2\EOT\144\ENQ\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\DC4\STX\EOT\ENQ\DC2\EOT\144\ENQ\v\DC1\n\
    \\r\n\
    \\ENQ\EOT\DC4\STX\EOT\SOH\DC2\EOT\144\ENQ\DC2\US\n\
    \\r\n\
    \\ENQ\EOT\DC4\STX\EOT\ETX\DC2\EOT\144\ENQ\"#\n\
    \U\n\
    \\EOT\EOT\DC4\STX\ENQ\DC2\EOT\146\ENQ\STX(\SUBG Extra headers that will be included in the request to the MCP server.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\DC4\STX\ENQ\ACK\DC2\EOT\146\ENQ\STX\NAK\n\
    \\r\n\
    \\ENQ\EOT\DC4\STX\ENQ\SOH\DC2\EOT\146\ENQ\SYN#\n\
    \\r\n\
    \\ENQ\EOT\DC4\STX\ENQ\ETX\DC2\EOT\146\ENQ&'\n\
    \\f\n\
    \\STX\EOT\NAK\DC2\ACK\149\ENQ\NUL\174\ENQ\SOH\n\
    \\v\n\
    \\ETX\EOT\NAK\SOH\DC2\EOT\149\ENQ\b\DC1\n\
    \\169\STX\n\
    \\EOT\EOT\NAK\STX\NUL\DC2\EOT\153\ENQ\STX'\SUB\154\STX List of website domains (without protocol specification or subdomains) to exclude from search results (e.g., [\"example.com\"]).\n\
    \ Use this to prevent results from unwanted sites. A maximum of 5 websites can be excluded.\n\
    \ This parameter cannot be set together with `allowed_domains`.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\NAK\STX\NUL\EOT\DC2\EOT\153\ENQ\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\NAK\STX\NUL\ENQ\DC2\EOT\153\ENQ\v\DC1\n\
    \\r\n\
    \\ENQ\EOT\NAK\STX\NUL\SOH\DC2\EOT\153\ENQ\DC2\"\n\
    \\r\n\
    \\ENQ\EOT\NAK\STX\NUL\ETX\DC2\EOT\153\ENQ%&\n\
    \\137\EOT\n\
    \\EOT\EOT\NAK\STX\SOH\DC2\EOT\161\ENQ\STX&\SUB\250\ETX List of website domains (without protocol specification or subdomains)\n\
    \ to restrict search results to (e.g., [\"example.com\"]). A maximum of 5 websites can be allowed.\n\
    \ Use this as a whitelist to limit results to only these specific sites; no other websites will\n\
    \ be considered. If no relevant information is found on these websites, the number of results\n\
    \ returned might be smaller than `max_search_results` set in `SearchParameters`. Note: This\n\
    \ parameter cannot be set together with `excluded_domains`.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\NAK\STX\SOH\EOT\DC2\EOT\161\ENQ\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\NAK\STX\SOH\ENQ\DC2\EOT\161\ENQ\v\DC1\n\
    \\r\n\
    \\ENQ\EOT\NAK\STX\SOH\SOH\DC2\EOT\161\ENQ\DC2!\n\
    \\r\n\
    \\ENQ\EOT\NAK\STX\SOH\ETX\DC2\EOT\161\ENQ$%\n\
    \\188\SOH\n\
    \\EOT\EOT\NAK\STX\STX\DC2\EOT\165\ENQ\STX/\SUB\173\SOH Enable image understanding in downstream tools (e.g. allow fetching and interpreting images).\n\
    \ When true, the server may add image viewing tools to the active MCP toolset.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\NAK\STX\STX\EOT\DC2\EOT\165\ENQ\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\NAK\STX\STX\ENQ\DC2\EOT\165\ENQ\v\SI\n\
    \\r\n\
    \\ENQ\EOT\NAK\STX\STX\SOH\DC2\EOT\165\ENQ\DLE*\n\
    \\r\n\
    \\ENQ\EOT\NAK\STX\STX\ETX\DC2\EOT\165\ENQ-.\n\
    \\239\SOH\n\
    \\EOT\EOT\NAK\STX\ETX\DC2\EOT\170\ENQ\STX3\SUB\224\SOH The user location to use for a preference on the search results.\n\
    \ Setting this will make the agentic search results more relevant to the specified location,\n\
    \ which is useful for geolocation-based search results refinement.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\NAK\STX\ETX\EOT\DC2\EOT\170\ENQ\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\NAK\STX\ETX\ACK\DC2\EOT\170\ENQ\v \n\
    \\r\n\
    \\ENQ\EOT\NAK\STX\ETX\SOH\DC2\EOT\170\ENQ!.\n\
    \\r\n\
    \\ENQ\EOT\NAK\STX\ETX\ETX\DC2\EOT\170\ENQ12\n\
    \N\n\
    \\EOT\EOT\NAK\STX\EOT\DC2\EOT\173\ENQ\STX(\SUB@ Enable image search results that can be embedded in responses.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\NAK\STX\EOT\EOT\DC2\EOT\173\ENQ\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\NAK\STX\EOT\ENQ\DC2\EOT\173\ENQ\v\SI\n\
    \\r\n\
    \\ENQ\EOT\NAK\STX\EOT\SOH\DC2\EOT\173\ENQ\DLE#\n\
    \\r\n\
    \\ENQ\EOT\NAK\STX\EOT\ETX\DC2\EOT\173\ENQ&'\n\
    \P\n\
    \\STX\EOT\SYN\DC2\ACK\177\ENQ\NUL\189\ENQ\SOH\SUBB The user location to use for a preference on the search results.\n\
    \\n\
    \\v\n\
    \\ETX\EOT\SYN\SOH\DC2\EOT\177\ENQ\b\GS\n\
    \M\n\
    \\EOT\EOT\SYN\STX\NUL\DC2\EOT\179\ENQ\STX\RS\SUB? Two-letter ISO 3166-1 alpha-2 country code, like US, GB, etc.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\SYN\STX\NUL\EOT\DC2\EOT\179\ENQ\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\SYN\STX\NUL\ENQ\DC2\EOT\179\ENQ\v\DC1\n\
    \\r\n\
    \\ENQ\EOT\SYN\STX\NUL\SOH\DC2\EOT\179\ENQ\DC2\EM\n\
    \\r\n\
    \\ENQ\EOT\SYN\STX\NUL\ETX\DC2\EOT\179\ENQ\FS\GS\n\
    \.\n\
    \\EOT\EOT\SYN\STX\SOH\DC2\EOT\182\ENQ\STX\ESC\SUB  Free text string for the city.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\SYN\STX\SOH\EOT\DC2\EOT\182\ENQ\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\SYN\STX\SOH\ENQ\DC2\EOT\182\ENQ\v\DC1\n\
    \\r\n\
    \\ENQ\EOT\SYN\STX\SOH\SOH\DC2\EOT\182\ENQ\DC2\SYN\n\
    \\r\n\
    \\ENQ\EOT\SYN\STX\SOH\ETX\DC2\EOT\182\ENQ\EM\SUB\n\
    \0\n\
    \\EOT\EOT\SYN\STX\STX\DC2\EOT\185\ENQ\STX\GS\SUB\" Free text string for the region.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\SYN\STX\STX\EOT\DC2\EOT\185\ENQ\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\SYN\STX\STX\ENQ\DC2\EOT\185\ENQ\v\DC1\n\
    \\r\n\
    \\ENQ\EOT\SYN\STX\STX\SOH\DC2\EOT\185\ENQ\DC2\CAN\n\
    \\r\n\
    \\ENQ\EOT\SYN\STX\STX\ETX\DC2\EOT\185\ENQ\ESC\FS\n\
    \G\n\
    \\EOT\EOT\SYN\STX\ETX\DC2\EOT\188\ENQ\STX\US\SUB9 IANA timezone like America/Chicago, Europe/London, etc.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\SYN\STX\ETX\EOT\DC2\EOT\188\ENQ\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\SYN\STX\ETX\ENQ\DC2\EOT\188\ENQ\v\DC1\n\
    \\r\n\
    \\ENQ\EOT\SYN\STX\ETX\SOH\DC2\EOT\188\ENQ\DC2\SUB\n\
    \\r\n\
    \\ENQ\EOT\SYN\STX\ETX\ETX\DC2\EOT\188\ENQ\GS\RS\n\
    \\f\n\
    \\STX\EOT\ETB\DC2\ACK\191\ENQ\NUL\222\ENQ\SOH\n\
    \\v\n\
    \\ETX\EOT\ETB\SOH\DC2\EOT\191\ENQ\b\SI\n\
    \\140\STX\n\
    \\EOT\EOT\ETB\STX\NUL\DC2\EOT\195\ENQ\STX3\SUB\253\SOH Optional start date for search results in ISO-8601 YYYY-MM-DD format (e.g., \"2024-05-24\").\n\
    \ Only content after this date will be considered. Defaults to unset (no start date restriction).\n\
    \ See https://en.wikipedia.org/wiki/ISO_8601 for format details.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\ETB\STX\NUL\EOT\DC2\EOT\195\ENQ\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\ETB\STX\NUL\ACK\DC2\EOT\195\ENQ\v$\n\
    \\r\n\
    \\ENQ\EOT\ETB\STX\NUL\SOH\DC2\EOT\195\ENQ%.\n\
    \\r\n\
    \\ENQ\EOT\ETB\STX\NUL\ETX\DC2\EOT\195\ENQ12\n\
    \\137\STX\n\
    \\EOT\EOT\ETB\STX\SOH\DC2\EOT\200\ENQ\STX1\SUB\250\SOH Optional end date for search results in ISO-8601 YYYY-MM-DD format (e.g., \"2024-12-24\").\n\
    \ Only content before this date will be considered. Defaults to unset (no end date restriction).\n\
    \ See https://en.wikipedia.org/wiki/ISO_8601 for format details.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\ETB\STX\SOH\EOT\DC2\EOT\200\ENQ\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\ETB\STX\SOH\ACK\DC2\EOT\200\ENQ\v$\n\
    \\r\n\
    \\ENQ\EOT\ETB\STX\SOH\SOH\DC2\EOT\200\ENQ%,\n\
    \\r\n\
    \\ENQ\EOT\ETB\STX\SOH\ETX\DC2\EOT\200\ENQ/0\n\
    \\203\STX\n\
    \\EOT\EOT\ETB\STX\STX\DC2\EOT\207\ENQ\STX(\SUB\188\STX Optional list of X usernames (without the '@' symbol) to limit search results to posts\n\
    \ from specific accounts (e.g., [\"xai\"]). If set, only posts authored by these\n\
    \ handles will be considered in the agentic search.\n\
    \ This field can not be set together with `excluded_x_handles`.\n\
    \ Defaults to unset (no exclusions).\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\ETB\STX\STX\EOT\DC2\EOT\207\ENQ\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\ETB\STX\STX\ENQ\DC2\EOT\207\ENQ\v\DC1\n\
    \\r\n\
    \\ENQ\EOT\ETB\STX\STX\SOH\DC2\EOT\207\ENQ\DC2#\n\
    \\r\n\
    \\ENQ\EOT\ETB\STX\STX\ETX\DC2\EOT\207\ENQ&'\n\
    \\177\STX\n\
    \\EOT\EOT\ETB\STX\ETX\DC2\EOT\213\ENQ\STX)\SUB\162\STX Optional list of X usernames (without the '@' symbol) used to exclude posts from specific accounts.\n\
    \ If set, posts authored by these handles will be excluded from the agentic search results.\n\
    \ This field can not be set together with `allowed_x_handles`.\n\
    \ Defaults to unset (no exclusions).\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\ETB\STX\ETX\EOT\DC2\EOT\213\ENQ\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\ETB\STX\ETX\ENQ\DC2\EOT\213\ENQ\v\DC1\n\
    \\r\n\
    \\ENQ\EOT\ETB\STX\ETX\SOH\DC2\EOT\213\ENQ\DC2$\n\
    \\r\n\
    \\ENQ\EOT\ETB\STX\ETX\ETX\DC2\EOT\213\ENQ'(\n\
    \\188\SOH\n\
    \\EOT\EOT\ETB\STX\EOT\DC2\EOT\217\ENQ\STX/\SUB\173\SOH Enable image understanding in downstream tools (e.g. allow fetching and interpreting images).\n\
    \ When true, the server may add image viewing tools to the active MCP toolset.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\ETB\STX\EOT\EOT\DC2\EOT\217\ENQ\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\ETB\STX\EOT\ENQ\DC2\EOT\217\ENQ\v\SI\n\
    \\r\n\
    \\ENQ\EOT\ETB\STX\EOT\SOH\DC2\EOT\217\ENQ\DLE*\n\
    \\r\n\
    \\ENQ\EOT\ETB\STX\EOT\ETX\DC2\EOT\217\ENQ-.\n\
    \\188\SOH\n\
    \\EOT\EOT\ETB\STX\ENQ\DC2\EOT\221\ENQ\STX/\SUB\173\SOH Enable video understanding in downstream tools (e.g. allow fetching and interpreting videos).\n\
    \ When true, the server may add video viewing tools to the active MCP toolset.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\ETB\STX\ENQ\EOT\DC2\EOT\221\ENQ\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\ETB\STX\ENQ\ENQ\DC2\EOT\221\ENQ\v\SI\n\
    \\r\n\
    \\ENQ\EOT\ETB\STX\ENQ\SOH\DC2\EOT\221\ENQ\DLE*\n\
    \\r\n\
    \\ENQ\EOT\ETB\STX\ENQ\ETX\DC2\EOT\221\ENQ-.\n\
    \\n\
    \\n\
    \\STX\EOT\CAN\DC2\EOT\224\ENQ\NUL\CAN\n\
    \\v\n\
    \\ETX\EOT\CAN\SOH\DC2\EOT\224\ENQ\b\NAK\n\
    \\f\n\
    \\STX\EOT\EM\DC2\ACK\226\ENQ\NUL\247\ENQ\SOH\n\
    \\v\n\
    \\ETX\EOT\EM\SOH\DC2\EOT\226\ENQ\b\EM\n\
    \\156\SOH\n\
    \\EOT\EOT\EM\STX\NUL\DC2\EOT\229\ENQ\STX%\SUB\141\SOH The ID(s) of the source collection(s) within which the search should be performed.\n\
    \ A maximum of 10 collections IDs can be used for search.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\EM\STX\NUL\EOT\DC2\EOT\229\ENQ\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\EM\STX\NUL\ENQ\DC2\EOT\229\ENQ\v\DC1\n\
    \\r\n\
    \\ENQ\EOT\EM\STX\NUL\SOH\DC2\EOT\229\ENQ\DC2 \n\
    \\r\n\
    \\ENQ\EOT\EM\STX\NUL\ETX\DC2\EOT\229\ENQ#$\n\
    \f\n\
    \\EOT\EOT\EM\STX\SOH\DC2\EOT\232\ENQ\STX\ESC\SUBX Optional number of chunks to be returned for each collections search.\n\
    \ Defaults to 10.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\EM\STX\SOH\EOT\DC2\EOT\232\ENQ\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\EM\STX\SOH\ENQ\DC2\EOT\232\ENQ\v\DLE\n\
    \\r\n\
    \\ENQ\EOT\EM\STX\SOH\SOH\DC2\EOT\232\ENQ\DC1\SYN\n\
    \\r\n\
    \\ENQ\EOT\EM\STX\SOH\ETX\DC2\EOT\232\ENQ\EM\SUB\n\
    \\168\SOH\n\
    \\EOT\EOT\EM\STX\STX\DC2\EOT\236\ENQ\STX#\SUB\153\SOH User-defined instructions to be included in the search query. Defaults to generic search\n\
    \ instructions used by the collections search backend if unset.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\EM\STX\STX\EOT\DC2\EOT\236\ENQ\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\EM\STX\STX\ENQ\DC2\EOT\236\ENQ\v\DC1\n\
    \\r\n\
    \\ENQ\EOT\EM\STX\STX\SOH\DC2\EOT\236\ENQ\DC2\RS\n\
    \\r\n\
    \\ENQ\EOT\EM\STX\STX\ETX\DC2\EOT\236\ENQ!\"\n\
    \^\n\
    \\EOT\EOT\EM\b\NUL\DC2\ACK\239\ENQ\STX\246\ENQ\ETX\SUBN How to perform the document search. Defaults to hybrid retrieval when unset.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\EM\b\NUL\SOH\DC2\EOT\239\ENQ\b\SYN\n\
    \O\n\
    \\EOT\EOT\EM\STX\ETX\DC2\EOT\241\ENQ\EOT)\SUBA Perform hybrid retrieval combining keyword and semantic search.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\EM\STX\ETX\ACK\DC2\EOT\241\ENQ\EOT\DC3\n\
    \\r\n\
    \\ENQ\EOT\EM\STX\ETX\SOH\DC2\EOT\241\ENQ\DC4$\n\
    \\r\n\
    \\ENQ\EOT\EM\STX\ETX\ETX\DC2\EOT\241\ENQ'(\n\
    \G\n\
    \\EOT\EOT\EM\STX\EOT\DC2\EOT\243\ENQ\EOT-\SUB9 Perform pure semantic retrieval using dense embeddings.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\EM\STX\EOT\ACK\DC2\EOT\243\ENQ\EOT\NAK\n\
    \\r\n\
    \\ENQ\EOT\EM\STX\EOT\SOH\DC2\EOT\243\ENQ\SYN(\n\
    \\r\n\
    \\ENQ\EOT\EM\STX\EOT\ETX\DC2\EOT\243\ENQ+,\n\
    \H\n\
    \\EOT\EOT\EM\STX\ENQ\DC2\EOT\245\ENQ\EOT+\SUB: Perform keyword-based retrieval using sparse embeddings.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\EM\STX\ENQ\ACK\DC2\EOT\245\ENQ\EOT\DC4\n\
    \\r\n\
    \\ENQ\EOT\EM\STX\ENQ\SOH\DC2\EOT\245\ENQ\NAK&\n\
    \\r\n\
    \\ENQ\EOT\EM\STX\ENQ\ETX\DC2\EOT\245\ENQ)*\n\
    \\f\n\
    \\STX\EOT\SUB\DC2\ACK\249\ENQ\NUL\252\ENQ\SOH\n\
    \\v\n\
    \\ETX\EOT\SUB\SOH\DC2\EOT\249\ENQ\b\CAN\n\
    \@\n\
    \\EOT\EOT\SUB\STX\NUL\DC2\EOT\251\ENQ\STX\ESC\SUB2 Optional number of files to limit the search to.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\SUB\STX\NUL\EOT\DC2\EOT\251\ENQ\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\SUB\STX\NUL\ENQ\DC2\EOT\251\ENQ\v\DLE\n\
    \\r\n\
    \\ENQ\EOT\SUB\STX\NUL\SOH\DC2\EOT\251\ENQ\DC1\SYN\n\
    \\r\n\
    \\ENQ\EOT\SUB\STX\NUL\ETX\DC2\EOT\251\ENQ\EM\SUB\n\
    \\f\n\
    \\STX\EOT\ESC\DC2\ACK\254\ENQ\NUL\138\ACK\SOH\n\
    \\v\n\
    \\ETX\EOT\ESC\SOH\DC2\EOT\254\ENQ\b\DLE\n\
    \%\n\
    \\EOT\EOT\ESC\STX\NUL\DC2\EOT\128\ACK\STX\DC2\SUB\ETB Name of the function.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\ESC\STX\NUL\ENQ\DC2\EOT\128\ACK\STX\b\n\
    \\r\n\
    \\ENQ\EOT\ESC\STX\NUL\SOH\DC2\EOT\128\ACK\t\r\n\
    \\r\n\
    \\ENQ\EOT\ESC\STX\NUL\ETX\DC2\EOT\128\ACK\DLE\DC1\n\
    \,\n\
    \\EOT\EOT\ESC\STX\SOH\DC2\EOT\131\ACK\STX\EM\SUB\RS Description of the function.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\ESC\STX\SOH\ENQ\DC2\EOT\131\ACK\STX\b\n\
    \\r\n\
    \\ENQ\EOT\ESC\STX\SOH\SOH\DC2\EOT\131\ACK\t\DC4\n\
    \\r\n\
    \\ENQ\EOT\ESC\STX\SOH\ETX\DC2\EOT\131\ACK\ETB\CAN\n\
    \C\n\
    \\EOT\EOT\ESC\STX\STX\DC2\EOT\134\ACK\STX\DC2\SUB5 Not supported: Only kept for compatibility reasons.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\ESC\STX\STX\ENQ\DC2\EOT\134\ACK\STX\ACK\n\
    \\r\n\
    \\ENQ\EOT\ESC\STX\STX\SOH\DC2\EOT\134\ACK\a\r\n\
    \\r\n\
    \\ENQ\EOT\ESC\STX\STX\ETX\DC2\EOT\134\ACK\DLE\DC1\n\
    \X\n\
    \\EOT\EOT\ESC\STX\ETX\DC2\EOT\137\ACK\STX\CAN\SUBJ The parameters the functions accepts, described as a JSON Schema object.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\ESC\STX\ETX\ENQ\DC2\EOT\137\ACK\STX\b\n\
    \\r\n\
    \\ENQ\EOT\ESC\STX\ETX\SOH\DC2\EOT\137\ACK\t\DC3\n\
    \\r\n\
    \\ENQ\EOT\ESC\STX\ETX\ETX\DC2\EOT\137\ACK\SYN\ETB\n\
    \\f\n\
    \\STX\ENQ\ACK\DC2\ACK\140\ACK\NUL\170\ACK\SOH\n\
    \\v\n\
    \\ETX\ENQ\ACK\SOH\DC2\EOT\140\ACK\ENQ\DC1\n\
    \\f\n\
    \\EOT\ENQ\ACK\STX\NUL\DC2\EOT\141\ACK\STX\GS\n\
    \\r\n\
    \\ENQ\ENQ\ACK\STX\NUL\SOH\DC2\EOT\141\ACK\STX\CAN\n\
    \\r\n\
    \\ENQ\ENQ\ACK\STX\NUL\STX\DC2\EOT\141\ACK\ESC\FS\n\
    \\149\SOH\n\
    \\EOT\ENQ\ACK\STX\SOH\DC2\EOT\145\ACK\STX&\SUB\134\SOH Indicates the tool is a client-side tool, and should be executed on client side.\n\
    \ Maps to `function_call` type in OAI Responses API.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\ACK\STX\SOH\SOH\DC2\EOT\145\ACK\STX!\n\
    \\r\n\
    \\ENQ\ENQ\ACK\STX\SOH\STX\DC2\EOT\145\ACK$%\n\
    \\162\SOH\n\
    \\EOT\ENQ\ACK\STX\STX\DC2\EOT\149\ACK\STX%\SUB\147\SOH Indicates the tool is a server-side web_search tool, and client side won't need to execute.\n\
    \ Maps to `web_search_call` type in OAI Responses API.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\ACK\STX\STX\SOH\DC2\EOT\149\ACK\STX \n\
    \\r\n\
    \\ENQ\ENQ\ACK\STX\STX\STX\DC2\EOT\149\ACK#$\n\
    \\158\SOH\n\
    \\EOT\ENQ\ACK\STX\ETX\DC2\EOT\153\ACK\STX#\SUB\143\SOH Indicates the tool is a server-side x_search tool, and client side won't need to execute.\n\
    \ Maps to `x_search_call` type in OAI Responses API.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\ACK\STX\ETX\SOH\DC2\EOT\153\ACK\STX\RS\n\
    \\r\n\
    \\ENQ\ENQ\ACK\STX\ETX\STX\DC2\EOT\153\ACK!\"\n\
    \\172\SOH\n\
    \\EOT\ENQ\ACK\STX\EOT\DC2\EOT\157\ACK\STX)\SUB\157\SOH Indicates the tool is a server-side code_execution tool, and client side won't need to execute.\n\
    \ Maps to `code_interpreter_call` type in OAI Responses API.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\ACK\STX\EOT\SOH\DC2\EOT\157\ACK\STX$\n\
    \\r\n\
    \\ENQ\ENQ\ACK\STX\EOT\STX\DC2\EOT\157\ACK'(\n\
    \\171\SOH\n\
    \\EOT\ENQ\ACK\STX\ENQ\DC2\EOT\161\ACK\STX-\SUB\156\SOH Indicates the tool is a server-side collections_search tool, and client side won't need to execute.\n\
    \ Maps to `file_search_call` type in OAI Responses API.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\ACK\STX\ENQ\SOH\DC2\EOT\161\ACK\STX(\n\
    \\r\n\
    \\ENQ\ENQ\ACK\STX\ENQ\STX\DC2\EOT\161\ACK+,\n\
    \\148\SOH\n\
    \\EOT\ENQ\ACK\STX\ACK\DC2\EOT\165\ACK\STX\RS\SUB\133\SOH Indicates the tool is a server-side mcp_tool, and client side won't need to execute.\n\
    \ Maps to `mcp_call` type in OAI Responses API.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\ACK\STX\ACK\SOH\DC2\EOT\165\ACK\STX\EM\n\
    \\r\n\
    \\ENQ\ENQ\ACK\STX\ACK\STX\DC2\EOT\165\ACK\FS\GS\n\
    \\176\SOH\n\
    \\EOT\ENQ\ACK\STX\a\DC2\EOT\169\ACK\STX,\SUB\161\SOH Indicates the tool is a server-side attachment_search tool, and client side won't need to execute.\n\
    \ Maps to `attachment_search_call` type in OAI Responses API.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\ACK\STX\a\SOH\DC2\EOT\169\ACK\STX'\n\
    \\r\n\
    \\ENQ\ENQ\ACK\STX\a\STX\DC2\EOT\169\ACK*+\n\
    \\f\n\
    \\STX\ENQ\a\DC2\ACK\172\ACK\NUL\184\ACK\SOH\n\
    \\v\n\
    \\ETX\ENQ\a\SOH\DC2\EOT\172\ACK\ENQ\DC3\n\
    \-\n\
    \\EOT\ENQ\a\STX\NUL\DC2\EOT\174\ACK\STX#\SUB\US The tool call is in progress.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\a\STX\NUL\SOH\DC2\EOT\174\ACK\STX\RS\n\
    \\r\n\
    \\ENQ\ENQ\a\STX\NUL\STX\DC2\EOT\174\ACK!\"\n\
    \+\n\
    \\EOT\ENQ\a\STX\SOH\DC2\EOT\177\ACK\STX!\SUB\GS The tool call is completed.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\a\STX\SOH\SOH\DC2\EOT\177\ACK\STX\FS\n\
    \\r\n\
    \\ENQ\ENQ\a\STX\SOH\STX\DC2\EOT\177\ACK\US \n\
    \,\n\
    \\EOT\ENQ\a\STX\STX\DC2\EOT\180\ACK\STX\"\SUB\RS The tool call is incomplete.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\a\STX\STX\SOH\DC2\EOT\180\ACK\STX\GS\n\
    \\r\n\
    \\ENQ\ENQ\a\STX\STX\STX\DC2\EOT\180\ACK !\n\
    \(\n\
    \\EOT\ENQ\a\STX\ETX\DC2\EOT\183\ACK\STX\RS\SUB\SUB The tool call is failed.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\a\STX\ETX\SOH\DC2\EOT\183\ACK\STX\EM\n\
    \\r\n\
    \\ENQ\ENQ\a\STX\ETX\STX\DC2\EOT\183\ACK\FS\GS\n\
    \K\n\
    \\STX\EOT\FS\DC2\ACK\187\ACK\NUL\205\ACK\SOH\SUB= Content of a tool call, typically in a response from model.\n\
    \\n\
    \\v\n\
    \\ETX\EOT\FS\SOH\DC2\EOT\187\ACK\b\DLE\n\
    \(\n\
    \\EOT\EOT\FS\STX\NUL\DC2\EOT\189\ACK\STX\DLE\SUB\SUB The ID of the tool call.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\FS\STX\NUL\ENQ\DC2\EOT\189\ACK\STX\b\n\
    \\r\n\
    \\ENQ\EOT\FS\STX\NUL\SOH\DC2\EOT\189\ACK\t\v\n\
    \\r\n\
    \\ENQ\EOT\FS\STX\NUL\ETX\DC2\EOT\189\ACK\SO\SI\n\
    \\180\SOH\n\
    \\EOT\EOT\FS\STX\SOH\DC2\EOT\193\ACK\STX\CAN\SUB\165\SOH Information to indicate whether the tool call needs to be executed on client side or server side.\n\
    \ By default, it will be a client-side tool call if not specified.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\FS\STX\SOH\ACK\DC2\EOT\193\ACK\STX\SO\n\
    \\r\n\
    \\ENQ\EOT\FS\STX\SOH\SOH\DC2\EOT\193\ACK\SI\DC3\n\
    \\r\n\
    \\ENQ\EOT\FS\STX\SOH\ETX\DC2\EOT\193\ACK\SYN\ETB\n\
    \(\n\
    \\EOT\EOT\FS\STX\STX\DC2\EOT\196\ACK\STX\FS\SUB\SUB Status of the tool call.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\FS\STX\STX\ACK\DC2\EOT\196\ACK\STX\DLE\n\
    \\r\n\
    \\ENQ\EOT\FS\STX\STX\SOH\DC2\EOT\196\ACK\DC1\ETB\n\
    \\r\n\
    \\ENQ\EOT\FS\STX\STX\ETX\DC2\EOT\196\ACK\SUB\ESC\n\
    \9\n\
    \\EOT\EOT\FS\STX\ETX\DC2\EOT\199\ACK\STX$\SUB+ Error message if the tool call is failed.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\FS\STX\ETX\EOT\DC2\EOT\199\ACK\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\FS\STX\ETX\ENQ\DC2\EOT\199\ACK\v\DC1\n\
    \\r\n\
    \\ENQ\EOT\FS\STX\ETX\SOH\DC2\EOT\199\ACK\DC2\US\n\
    \\r\n\
    \\ENQ\EOT\FS\STX\ETX\ETX\DC2\EOT\199\ACK\"#\n\
    \?\n\
    \\EOT\EOT\FS\b\NUL\DC2\ACK\202\ACK\STX\204\ACK\ETX\SUB/ Information regarding invoking the tool call.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\FS\b\NUL\SOH\DC2\EOT\202\ACK\b\f\n\
    \\f\n\
    \\EOT\EOT\FS\STX\EOT\DC2\EOT\203\ACK\EOT\US\n\
    \\r\n\
    \\ENQ\EOT\FS\STX\EOT\ACK\DC2\EOT\203\ACK\EOT\DLE\n\
    \\r\n\
    \\ENQ\EOT\FS\STX\EOT\SOH\DC2\EOT\203\ACK\DC1\EM\n\
    \\r\n\
    \\ENQ\EOT\FS\STX\EOT\ETX\DC2\EOT\203\ACK\FS\RS\n\
    \&\n\
    \\STX\EOT\GS\DC2\ACK\208\ACK\NUL\214\ACK\SOH\SUB\CAN Tool call information.\n\
    \\n\
    \\v\n\
    \\ETX\EOT\GS\SOH\DC2\EOT\208\ACK\b\DC4\n\
    \-\n\
    \\EOT\EOT\GS\STX\NUL\DC2\EOT\210\ACK\STX\DC2\SUB\US Name of the function to call.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\GS\STX\NUL\ENQ\DC2\EOT\210\ACK\STX\b\n\
    \\r\n\
    \\ENQ\EOT\GS\STX\NUL\SOH\DC2\EOT\210\ACK\t\r\n\
    \\r\n\
    \\ENQ\EOT\GS\STX\NUL\ETX\DC2\EOT\210\ACK\DLE\DC1\n\
    \C\n\
    \\EOT\EOT\GS\STX\SOH\DC2\EOT\213\ACK\STX\ETB\SUB5 Arguments used to call the function as json string.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\GS\STX\SOH\ENQ\DC2\EOT\213\ACK\STX\b\n\
    \\r\n\
    \\ENQ\EOT\GS\STX\SOH\SOH\DC2\EOT\213\ACK\t\DC2\n\
    \\r\n\
    \\ENQ\EOT\GS\STX\SOH\ETX\DC2\EOT\213\ACK\NAK\SYN\n\
    \<\n\
    \\STX\EOT\RS\DC2\ACK\217\ACK\NUL\224\ACK\SOH\SUB. The response format for structured response.\n\
    \\n\
    \\v\n\
    \\ETX\EOT\RS\SOH\DC2\EOT\217\ACK\b\SYN\n\
    \W\n\
    \\EOT\EOT\RS\STX\NUL\DC2\EOT\219\ACK\STX\GS\SUBI Type of format expected for the response. Default to `FORMAT_TYPE_TEXT`\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\RS\STX\NUL\ACK\DC2\EOT\219\ACK\STX\f\n\
    \\r\n\
    \\ENQ\EOT\RS\STX\NUL\SOH\DC2\EOT\219\ACK\r\CAN\n\
    \\r\n\
    \\ENQ\EOT\RS\STX\NUL\ETX\DC2\EOT\219\ACK\ESC\FS\n\
    \\132\SOH\n\
    \\EOT\EOT\RS\STX\SOH\DC2\EOT\223\ACK\STX\GS\SUBv The JSON schema that the response should conform to.\n\
    \ Only considered if `format_type` is `FORMAT_TYPE_JSON_SCHEMA`.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\RS\STX\SOH\EOT\DC2\EOT\223\ACK\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\RS\STX\SOH\ENQ\DC2\EOT\223\ACK\v\DC1\n\
    \\r\n\
    \\ENQ\EOT\RS\STX\SOH\SOH\DC2\EOT\223\ACK\DC2\CAN\n\
    \\r\n\
    \\ENQ\EOT\RS\STX\SOH\ETX\DC2\EOT\223\ACK\ESC\FS\n\
    \/\n\
    \\STX\ENQ\b\DC2\ACK\227\ACK\NUL\232\ACK\SOH\SUB! Mode to control the web search.\n\
    \\n\
    \\v\n\
    \\ETX\ENQ\b\SOH\DC2\EOT\227\ACK\ENQ\SI\n\
    \\f\n\
    \\EOT\ENQ\b\STX\NUL\DC2\EOT\228\ACK\STX\SUB\n\
    \\r\n\
    \\ENQ\ENQ\b\STX\NUL\SOH\DC2\EOT\228\ACK\STX\NAK\n\
    \\r\n\
    \\ENQ\ENQ\b\STX\NUL\STX\DC2\EOT\228\ACK\CAN\EM\n\
    \\f\n\
    \\EOT\ENQ\b\STX\SOH\DC2\EOT\229\ACK\STX\SYN\n\
    \\r\n\
    \\ENQ\ENQ\b\STX\SOH\SOH\DC2\EOT\229\ACK\STX\DC1\n\
    \\r\n\
    \\ENQ\ENQ\b\STX\SOH\STX\DC2\EOT\229\ACK\DC4\NAK\n\
    \\f\n\
    \\EOT\ENQ\b\STX\STX\DC2\EOT\230\ACK\STX\NAK\n\
    \\r\n\
    \\ENQ\ENQ\b\STX\STX\SOH\DC2\EOT\230\ACK\STX\DLE\n\
    \\r\n\
    \\ENQ\ENQ\b\STX\STX\STX\DC2\EOT\230\ACK\DC3\DC4\n\
    \\f\n\
    \\EOT\ENQ\b\STX\ETX\DC2\EOT\231\ACK\STX\ETB\n\
    \\r\n\
    \\ENQ\ENQ\b\STX\ETX\SOH\DC2\EOT\231\ACK\STX\DC2\n\
    \\r\n\
    \\ENQ\ENQ\b\STX\ETX\STX\DC2\EOT\231\ACK\NAK\SYN\n\
    \\232\STX\n\
    \\STX\EOT\US\DC2\ACK\240\ACK\NUL\141\a\SOH\SUB\217\STX Parameters for configuring search behavior in a chat request.\n\
    \\n\
    \ This message allows customization of search functionality when using models that support\n\
    \ searching external sources for information. You can specify which sources to search,\n\
    \ set date ranges for relevant content, control the search mode, and configure how\n\
    \ results are returned.\n\
    \\n\
    \\v\n\
    \\ETX\EOT\US\SOH\DC2\EOT\240\ACK\b\CAN\n\
    \\175\ETX\n\
    \\EOT\EOT\US\STX\NUL\DC2\EOT\245\ACK\STX\SYN\SUB\160\ETX Controls when search is performed. Possible values are:\n\
    \   - OFF_SEARCH_MODE (default): No search is performed, and no external data will be considered.\n\
    \   - ON_SEARCH_MODE: Search is always performed when sampling from the model and the model will search in every source provided for relevant data.\n\
    \   - AUTO_SEARCH_MODE: The model decides whether to perform a search based on the prompt and which sources to use.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\US\STX\NUL\ACK\DC2\EOT\245\ACK\STX\f\n\
    \\r\n\
    \\ENQ\EOT\US\STX\NUL\SOH\DC2\EOT\245\ACK\r\DC1\n\
    \\r\n\
    \\ENQ\EOT\US\STX\NUL\ETX\DC2\EOT\245\ACK\DC4\NAK\n\
    \\203\SOH\n\
    \\EOT\EOT\US\STX\SOH\DC2\EOT\250\ACK\STX\RS\SUB\188\SOH A list of search sources to query, such as web, news, X, or RSS feeds.\n\
    \ Multiple sources can be specified. If no sources are provided, the model will default to\n\
    \ searching the web and X.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\US\STX\SOH\EOT\DC2\EOT\250\ACK\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\US\STX\SOH\ACK\DC2\EOT\250\ACK\v\DC1\n\
    \\r\n\
    \\ENQ\EOT\US\STX\SOH\SOH\DC2\EOT\250\ACK\DC2\EM\n\
    \\r\n\
    \\ENQ\EOT\US\STX\SOH\ETX\DC2\EOT\250\ACK\FS\GS\n\
    \\140\STX\n\
    \\EOT\EOT\US\STX\STX\DC2\EOT\255\ACK\STX*\SUB\253\SOH Optional start date for search results in ISO-8601 YYYY-MM-DD format (e.g., \"2024-05-24\").\n\
    \ Only content after this date will be considered. Defaults to unset (no start date restriction).\n\
    \ See https://en.wikipedia.org/wiki/ISO_8601 for format details.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\US\STX\STX\ACK\DC2\EOT\255\ACK\STX\ESC\n\
    \\r\n\
    \\ENQ\EOT\US\STX\STX\SOH\DC2\EOT\255\ACK\FS%\n\
    \\r\n\
    \\ENQ\EOT\US\STX\STX\ETX\DC2\EOT\255\ACK()\n\
    \\137\STX\n\
    \\EOT\EOT\US\STX\ETX\DC2\EOT\132\a\STX(\SUB\250\SOH Optional end date for search results in ISO-8601 YYYY-MM-DD format (e.g., \"2024-12-24\").\n\
    \ Only content before this date will be considered. Defaults to unset (no end date restriction).\n\
    \ See https://en.wikipedia.org/wiki/ISO_8601 for format details.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\US\STX\ETX\ACK\DC2\EOT\132\a\STX\ESC\n\
    \\r\n\
    \\ENQ\EOT\US\STX\ETX\SOH\DC2\EOT\132\a\FS#\n\
    \\r\n\
    \\ENQ\EOT\US\STX\ETX\ETX\DC2\EOT\132\a&'\n\
    \\162\SOH\n\
    \\EOT\EOT\US\STX\EOT\DC2\EOT\136\a\STX\FS\SUB\147\SOH If set to true, the model will return a list of citations (URLs or references)\n\
    \ to the sources used in generating the response. Defaults to true.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\US\STX\EOT\ENQ\DC2\EOT\136\a\STX\ACK\n\
    \\r\n\
    \\ENQ\EOT\US\STX\EOT\SOH\DC2\EOT\136\a\a\ETB\n\
    \\r\n\
    \\ENQ\EOT\US\STX\EOT\ETX\DC2\EOT\136\a\SUB\ESC\n\
    \\150\SOH\n\
    \\EOT\EOT\US\STX\ENQ\DC2\EOT\140\a\STX(\SUB\135\SOH Optional limit on the number of search results to consider\n\
    \ when generating a response. Must be in the range [1, 30]. Defaults to 15.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\US\STX\ENQ\EOT\DC2\EOT\140\a\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\US\STX\ENQ\ENQ\DC2\EOT\140\a\v\DLE\n\
    \\r\n\
    \\ENQ\EOT\US\STX\ENQ\SOH\DC2\EOT\140\a\DC1#\n\
    \\r\n\
    \\ENQ\EOT\US\STX\ENQ\ETX\DC2\EOT\140\a&'\n\
    \\247\SOH\n\
    \\STX\EOT \DC2\ACK\146\a\NUL\164\a\SOH\SUB\232\SOH Defines a source for search requests, specifying the type of content to search.\n\
    \ This message acts as a container for different types of search sources. Only one type\n\
    \ of source can be specified per instance using the oneof field.\n\
    \\n\
    \\v\n\
    \\ETX\EOT \SOH\DC2\EOT\146\a\b\SO\n\
    \\SO\n\
    \\EOT\EOT \b\NUL\DC2\ACK\147\a\STX\163\a\ETX\n\
    \\r\n\
    \\ENQ\EOT \b\NUL\SOH\DC2\EOT\147\a\b\SO\n\
    \\194\SOH\n\
    \\EOT\EOT \STX\NUL\DC2\EOT\150\a\EOT\SYN\SUB\179\SOH Configuration for searching online web content. Use this to search general websites\n\
    \ with options to filter by country, exclude specific domains, or only allow specific domains.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT \STX\NUL\ACK\DC2\EOT\150\a\EOT\r\n\
    \\r\n\
    \\ENQ\EOT \STX\NUL\SOH\DC2\EOT\150\a\SO\DC1\n\
    \\r\n\
    \\ENQ\EOT \STX\NUL\ETX\DC2\EOT\150\a\DC4\NAK\n\
    \\145\SOH\n\
    \\EOT\EOT \STX\SOH\DC2\EOT\154\a\EOT\CAN\SUB\130\SOH Configuration for searching recent articles and reports from news outlets.\n\
    \ Useful for current events or topic-specific updates.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT \STX\SOH\ACK\DC2\EOT\154\a\EOT\SO\n\
    \\r\n\
    \\ENQ\EOT \STX\SOH\SOH\DC2\EOT\154\a\SI\DC3\n\
    \\r\n\
    \\ENQ\EOT \STX\SOH\ETX\DC2\EOT\154\a\SYN\ETB\n\
    \y\n\
    \\EOT\EOT \STX\STX\DC2\EOT\158\a\EOT\DC2\SUBk Configuration for searching content on X. Allows focusing on\n\
    \ specific user handles for targeted content.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT \STX\STX\ACK\DC2\EOT\158\a\EOT\v\n\
    \\r\n\
    \\ENQ\EOT \STX\STX\SOH\DC2\EOT\158\a\f\r\n\
    \\r\n\
    \\ENQ\EOT \STX\STX\ETX\DC2\EOT\158\a\DLE\DC1\n\
    \j\n\
    \\EOT\EOT \STX\ETX\DC2\EOT\162\a\EOT\SYN\SUB\\ Configuration for searching content from RSS feeds. Requires specific feed URLs\n\
    \ to query.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT \STX\ETX\ACK\DC2\EOT\162\a\EOT\r\n\
    \\r\n\
    \\ENQ\EOT \STX\ETX\SOH\DC2\EOT\162\a\SO\DC1\n\
    \\r\n\
    \\ENQ\EOT \STX\ETX\ETX\DC2\EOT\162\a\DC4\NAK\n\
    \\152\STX\n\
    \\STX\EOT!\DC2\ACK\171\a\NUL\192\a\SOH\SUB\137\STX Configuration for a web search source in search requests.\n\
    \\n\
    \ This message configures a source for searching online web content. It allows specification\n\
    \ of regional content through country codes and filtering of results by excluding or allowing\n\
    \ specific websites.\n\
    \\n\
    \\v\n\
    \\ETX\EOT!\SOH\DC2\EOT\171\a\b\DC1\n\
    \\170\STX\n\
    \\EOT\EOT!\STX\NUL\DC2\EOT\175\a\STX(\SUB\155\STX List of website domains (without protocol specification or subdomains) to exclude from search results (e.g., [\"example.com\"]).\n\
    \ Use this to prevent results from unwanted sites. A maximum of 5 websites can be excluded.\n\
    \ This parameter cannot be set together with `allowed_websites`.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT!\STX\NUL\EOT\DC2\EOT\175\a\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT!\STX\NUL\ENQ\DC2\EOT\175\a\v\DC1\n\
    \\r\n\
    \\ENQ\EOT!\STX\NUL\SOH\DC2\EOT\175\a\DC2#\n\
    \\r\n\
    \\ENQ\EOT!\STX\NUL\ETX\DC2\EOT\175\a&'\n\
    \\138\EOT\n\
    \\EOT\EOT!\STX\SOH\DC2\EOT\183\a\STX'\SUB\251\ETX List of website domains (without protocol specification or subdomains)\n\
    \ to restrict search results to (e.g., [\"example.com\"]). A maximum of 5 websites can be allowed.\n\
    \ Use this as a whitelist to limit results to only these specific sites; no other websites will\n\
    \ be considered. If no relevant information is found on these websites, the number of results\n\
    \ returned might be smaller than `max_search_results` set in `SearchParameters`. Note: This\n\
    \ parameter cannot be set together with `excluded_websites`.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT!\STX\SOH\EOT\DC2\EOT\183\a\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT!\STX\SOH\ENQ\DC2\EOT\183\a\v\DC1\n\
    \\r\n\
    \\ENQ\EOT!\STX\SOH\SOH\DC2\EOT\183\a\DC2\"\n\
    \\r\n\
    \\ENQ\EOT!\STX\SOH\ETX\DC2\EOT\183\a%&\n\
    \\244\SOH\n\
    \\EOT\EOT!\STX\STX\DC2\EOT\188\a\STX\RS\SUB\229\SOH Optional ISO alpha-2 country code (e.g., \"BE\" for Belgium) to limit search results\n\
    \ to content from a specific region or country. Defaults to unset (global search).\n\
    \ See https://en.wikipedia.org/wiki/ISO_3166-2 for valid codes.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT!\STX\STX\EOT\DC2\EOT\188\a\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT!\STX\STX\ENQ\DC2\EOT\188\a\v\DC1\n\
    \\r\n\
    \\ENQ\EOT!\STX\STX\SOH\DC2\EOT\188\a\DC2\EM\n\
    \\r\n\
    \\ENQ\EOT!\STX\STX\ETX\DC2\EOT\188\a\FS\GS\n\
    \[\n\
    \\EOT\EOT!\STX\ETX\DC2\EOT\191\a\STX\ETB\SUBM Whether to exclude adult content from the search results. Defaults to true.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT!\STX\ETX\ENQ\DC2\EOT\191\a\STX\ACK\n\
    \\r\n\
    \\ENQ\EOT!\STX\ETX\SOH\DC2\EOT\191\a\a\DC2\n\
    \\r\n\
    \\ENQ\EOT!\STX\ETX\ETX\DC2\EOT\191\a\NAK\SYN\n\
    \\137\STX\n\
    \\STX\EOT\"\DC2\ACK\198\a\NUL\211\a\SOH\SUB\250\SOH Configuration for a news search source in search requests.\n\
    \\n\
    \ This message configures a source for searching recent articles and reports from news outlets.\n\
    \ It is useful for obtaining current events or topic-specific updates with regional filtering.\n\
    \\n\
    \\v\n\
    \\ETX\EOT\"\SOH\DC2\EOT\198\a\b\DC2\n\
    \\147\STX\n\
    \\EOT\EOT\"\STX\NUL\DC2\EOT\202\a\STX(\SUB\132\STX List of website domains (without protocol specification or subdomains)\n\
    \ to exclude from search results (e.g., [\"example.com\"]). A maximum of 5 websites can be excluded.\n\
    \ Use this to prevent results from specific news sites. Defaults to unset (no exclusions).\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\"\STX\NUL\EOT\DC2\EOT\202\a\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\"\STX\NUL\ENQ\DC2\EOT\202\a\v\DC1\n\
    \\r\n\
    \\ENQ\EOT\"\STX\NUL\SOH\DC2\EOT\202\a\DC2#\n\
    \\r\n\
    \\ENQ\EOT\"\STX\NUL\ETX\DC2\EOT\202\a&'\n\
    \\239\SOH\n\
    \\EOT\EOT\"\STX\SOH\DC2\EOT\207\a\STX\RS\SUB\224\SOH Optional ISO alpha-2 country code (e.g., \"BE\" for Belgium) to limit search results\n\
    \ to news from a specific region or country. Defaults to unset (global news).\n\
    \ See https://en.wikipedia.org/wiki/ISO_3166-2 for valid codes.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\"\STX\SOH\EOT\DC2\EOT\207\a\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\"\STX\SOH\ENQ\DC2\EOT\207\a\v\DC1\n\
    \\r\n\
    \\ENQ\EOT\"\STX\SOH\SOH\DC2\EOT\207\a\DC2\EM\n\
    \\r\n\
    \\ENQ\EOT\"\STX\SOH\ETX\DC2\EOT\207\a\FS\GS\n\
    \[\n\
    \\EOT\EOT\"\STX\STX\DC2\EOT\210\a\STX\ETB\SUBM Whether to exclude adult content from the search results. Defaults to true.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\"\STX\STX\ENQ\DC2\EOT\210\a\STX\ACK\n\
    \\r\n\
    \\ENQ\EOT\"\STX\STX\SOH\DC2\EOT\210\a\a\DC2\n\
    \\r\n\
    \\ENQ\EOT\"\STX\STX\ETX\DC2\EOT\210\a\NAK\SYN\n\
    \\128\STX\n\
    \\STX\EOT#\DC2\ACK\217\a\NUL\240\a\SOH\SUB\241\SOH Configuration for an X (formerly Twitter) search source in search requests.\n\
    \\n\
    \ This message configures a source for searching content on X. It allows focusing the search\n\
    \ on specific user handles to retrieve targeted posts and interactions.\n\
    \\n\
    \\v\n\
    \\ETX\EOT#\SOH\DC2\EOT\217\a\b\SI\n\
    \\v\n\
    \\ETX\EOT#\t\DC2\EOT\218\a\STX\r\n\
    \\f\n\
    \\EOT\EOT#\t\NUL\DC2\EOT\218\a\v\f\n\
    \\r\n\
    \\ENQ\EOT#\t\NUL\SOH\DC2\EOT\218\a\v\f\n\
    \\r\n\
    \\ENQ\EOT#\t\NUL\STX\DC2\EOT\218\a\v\f\n\
    \\200\STX\n\
    \\EOT\EOT#\STX\NUL\DC2\EOT\225\a\STX)\SUB\185\STX Optional list of X usernames (without the '@' symbol) to limit search results to posts\n\
    \ from specific accounts (e.g., [\"xai\"]). If set, only posts authored by these\n\
    \ handles will be considered in the live search.\n\
    \ This field can not be set together with `excluded_x_handles`.\n\
    \ Defaults to unset (no exclusions).\n\
    \\n\
    \\r\n\
    \\ENQ\EOT#\STX\NUL\EOT\DC2\EOT\225\a\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT#\STX\NUL\ENQ\DC2\EOT\225\a\v\DC1\n\
    \\r\n\
    \\ENQ\EOT#\STX\NUL\SOH\DC2\EOT\225\a\DC2$\n\
    \\r\n\
    \\ENQ\EOT#\STX\NUL\ETX\DC2\EOT\225\a'(\n\
    \\175\STX\n\
    \\EOT\EOT#\STX\SOH\DC2\EOT\231\a\STX)\SUB\160\STX Optional list of X usernames (without the '@' symbol) used to exclude posts from specific accounts.\n\
    \ If set, posts authored by these handles will be excluded from the live search results.\n\
    \ This field can not be set together with `included_x_handles`.\n\
    \ Defaults to unset (no exclusions).\n\
    \\n\
    \\r\n\
    \\ENQ\EOT#\STX\SOH\EOT\DC2\EOT\231\a\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT#\STX\SOH\ENQ\DC2\EOT\231\a\v\DC1\n\
    \\r\n\
    \\ENQ\EOT#\STX\SOH\SOH\DC2\EOT\231\a\DC2$\n\
    \\r\n\
    \\ENQ\EOT#\STX\SOH\ETX\DC2\EOT\231\a'(\n\
    \\221\SOH\n\
    \\EOT\EOT#\STX\STX\DC2\EOT\235\a\STX)\SUB\206\SOH Optional post favorite count threshold. Defaults to unset (don't filter posts by post favorite count).\n\
    \ If set, only posts with a favorite count greater than or equal to this threshold will be considered.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT#\STX\STX\EOT\DC2\EOT\235\a\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT#\STX\STX\ENQ\DC2\EOT\235\a\v\DLE\n\
    \\r\n\
    \\ENQ\EOT#\STX\STX\SOH\DC2\EOT\235\a\DC1$\n\
    \\r\n\
    \\ENQ\EOT#\STX\STX\ETX\DC2\EOT\235\a'(\n\
    \\209\SOH\n\
    \\EOT\EOT#\STX\ETX\DC2\EOT\239\a\STX&\SUB\194\SOH Optional post view count threshold. Defaults to unset (don't filter posts by post view count).\n\
    \ If set, only posts with a view count greater than or equal to this threshold will be considered.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT#\STX\ETX\EOT\DC2\EOT\239\a\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT#\STX\ETX\ENQ\DC2\EOT\239\a\v\DLE\n\
    \\r\n\
    \\ENQ\EOT#\STX\ETX\SOH\DC2\EOT\239\a\DC1 \n\
    \\r\n\
    \\ENQ\EOT#\STX\ETX\ETX\DC2\EOT\239\a#%\n\
    \\210\SOH\n\
    \\STX\EOT$\DC2\ACK\246\a\NUL\250\a\SOH\SUB\195\SOH Configuration for an RSS search source in search requests.\n\
    \\n\
    \ This message configures a source for searching content from RSS feeds. It requires specific\n\
    \ feed URLs to query for content updates.\n\
    \\n\
    \\v\n\
    \\ETX\EOT$\SOH\DC2\EOT\246\a\b\DC1\n\
    \~\n\
    \\EOT\EOT$\STX\NUL\DC2\EOT\249\a\STX\FS\SUBp List of RSS feed URLs to search. Each URL must point to a valid RSS feed.\n\
    \ At least one link must be provided.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT$\STX\NUL\EOT\DC2\EOT\249\a\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT$\STX\NUL\ENQ\DC2\EOT\249\a\v\DC1\n\
    \\r\n\
    \\ENQ\EOT$\STX\NUL\SOH\DC2\EOT\249\a\DC2\ETB\n\
    \\r\n\
    \\ENQ\EOT$\STX\NUL\ETX\DC2\EOT\249\a\SUB\ESC\n\
    \\f\n\
    \\STX\EOT%\DC2\ACK\252\a\NUL\184\b\SOH\n\
    \\v\n\
    \\ETX\EOT%\SOH\DC2\EOT\252\a\b\ETB\n\
    \y\n\
    \\EOT\EOT%\STX\NUL\DC2\EOT\254\a\STX \SUBk Max number of tokens that can be generated in a response. This includes both output and reasoning tokens.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT%\STX\NUL\EOT\DC2\EOT\254\a\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT%\STX\NUL\ENQ\DC2\EOT\254\a\v\DLE\n\
    \\r\n\
    \\ENQ\EOT%\STX\NUL\SOH\DC2\EOT\254\a\DC1\ESC\n\
    \\r\n\
    \\ENQ\EOT%\STX\NUL\ETX\DC2\EOT\254\a\RS\US\n\
    \_\n\
    \\EOT\EOT%\STX\SOH\DC2\EOT\129\b\STX\US\SUBQ/ If set to false, the model can perform maximum one tool call. Default to true.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT%\STX\SOH\ENQ\DC2\EOT\129\b\STX\ACK\n\
    \\r\n\
    \\ENQ\EOT%\STX\SOH\SOH\DC2\EOT\129\b\a\SUB\n\
    \\r\n\
    \\ENQ\EOT%\STX\SOH\ETX\DC2\EOT\129\b\GS\RS\n\
    \?\n\
    \\EOT\EOT%\STX\STX\DC2\EOT\132\b\STX+\SUB1 The ID of the previous response from the model.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT%\STX\STX\EOT\DC2\EOT\132\b\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT%\STX\STX\ENQ\DC2\EOT\132\b\v\DC1\n\
    \\r\n\
    \\ENQ\EOT%\STX\STX\SOH\DC2\EOT\132\b\DC2&\n\
    \\r\n\
    \\ENQ\EOT%\STX\STX\ETX\DC2\EOT\132\b)*\n\
    \`\n\
    \\EOT\EOT%\STX\ETX\DC2\EOT\135\b\STX0\SUBR Constrains effort on reasoning for reasoning models. Default to `EFFORT_MEDIUM`.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT%\STX\ETX\EOT\DC2\EOT\135\b\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT%\STX\ETX\ACK\DC2\EOT\135\b\v\SUB\n\
    \\r\n\
    \\ENQ\EOT%\STX\ETX\SOH\DC2\EOT\135\b\ESC+\n\
    \\r\n\
    \\ENQ\EOT%\STX\ETX\ETX\DC2\EOT\135\b./\n\
    \\240\ETX\n\
    \\EOT\EOT%\STX\EOT\DC2\EOT\144\b\STX!\SUB\225\ETX A number between 0 and 2 used to control the variance of completions.\n\
    \ The smaller the value, the more deterministic the model will become. For\n\
    \ example, if we sample 1000 answers to the same prompt at a temperature of\n\
    \ 0.001, then most of the 1000 answers will be identical. Conversely, if we\n\
    \ conduct the same experiment at a temperature of 2, virtually no two answers\n\
    \ will be identical. Note that increasing the temperature will cause\n\
    \ the model to hallucinate more strongly.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT%\STX\EOT\EOT\DC2\EOT\144\b\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT%\STX\EOT\ENQ\DC2\EOT\144\b\v\DLE\n\
    \\r\n\
    \\ENQ\EOT%\STX\EOT\SOH\DC2\EOT\144\b\DC1\FS\n\
    \\r\n\
    \\ENQ\EOT%\STX\EOT\ETX\DC2\EOT\144\b\US \n\
    \6\n\
    \\EOT\EOT%\STX\ENQ\DC2\EOT\147\b\STX%\SUB( Formatting constraint on the response.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT%\STX\ENQ\ACK\DC2\EOT\147\b\STX\DLE\n\
    \\r\n\
    \\ENQ\EOT%\STX\ENQ\SOH\DC2\EOT\147\b\DC1 \n\
    \\r\n\
    \\ENQ\EOT%\STX\ENQ\ETX\DC2\EOT\147\b#$\n\
    \I\n\
    \\EOT\EOT%\STX\ACK\DC2\EOT\150\b\STX\GS\SUB; Controls if the model can, should, or must not use tools.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT%\STX\ACK\ACK\DC2\EOT\150\b\STX\f\n\
    \\r\n\
    \\ENQ\EOT%\STX\ACK\SOH\DC2\EOT\150\b\r\CAN\n\
    \\r\n\
    \\ENQ\EOT%\STX\ACK\ETX\DC2\EOT\150\b\ESC\FS\n\
    \\185\SOH\n\
    \\EOT\EOT%\STX\a\DC2\EOT\155\b\STX\SUB\SUB\170\SOH A list of tools the model may call. Currently, only functions are supported\n\
    \ as a tool. Use this to provide a list of functions the model may generate\n\
    \ JSON inputs for.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT%\STX\a\EOT\DC2\EOT\155\b\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT%\STX\a\ACK\DC2\EOT\155\b\v\SI\n\
    \\r\n\
    \\ENQ\EOT%\STX\a\SOH\DC2\EOT\155\b\DLE\NAK\n\
    \\r\n\
    \\ENQ\EOT%\STX\a\ETX\DC2\EOT\155\b\CAN\EM\n\
    \\133\ENQ\n\
    \\EOT\EOT%\STX\b\DC2\EOT\166\b\STX\ESC\SUB\246\EOT A number between 0 and 1 controlling the likelihood of the model to use\n\
    \ less-common answers. Recall that the model produces a probability for\n\
    \ each token. This means, for any choice of token there are thousands of\n\
    \ possibilities to choose from. This parameter controls the \"nucleus sampling\n\
    \ algorithm\". Instead of considering every possible token at every step, we\n\
    \ only look at the K tokens who's probabilities exceed `top_p`.\n\
    \ For example, if we set `top_p = 0.9`, then the set of tokens we actually\n\
    \ sample from, will have a probability mass of at least 90%. In practice,\n\
    \ low values will make the model more deterministic.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT%\STX\b\EOT\DC2\EOT\166\b\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT%\STX\b\ENQ\DC2\EOT\166\b\v\DLE\n\
    \\r\n\
    \\ENQ\EOT%\STX\b\SOH\DC2\EOT\166\b\DC1\SYN\n\
    \\r\n\
    \\ENQ\EOT%\STX\b\ETX\DC2\EOT\166\b\EM\SUB\n\
    \\206\SOH\n\
    \\EOT\EOT%\STX\t\DC2\EOT\171\b\STX\DC3\SUB\191\SOH An opaque string supplied by the API client (customer) to identify a user.\n\
    \ The string will be stored in the logs and can be used in customer service\n\
    \ requests to identify certain requests.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT%\STX\t\ENQ\DC2\EOT\171\b\STX\b\n\
    \\r\n\
    \\ENQ\EOT%\STX\t\SOH\DC2\EOT\171\b\t\r\n\
    \\r\n\
    \\ENQ\EOT%\STX\t\ETX\DC2\EOT\171\b\DLE\DC2\n\
    \|\n\
    \\EOT\EOT%\STX\n\
    \\DC2\EOT\174\b\STX3\SUBn Set the parameters to be used for realtime data. If not set, no realtime data will be acquired by the model.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT%\STX\n\
    \\EOT\DC2\EOT\174\b\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT%\STX\n\
    \\ACK\DC2\EOT\174\b\v\ESC\n\
    \\r\n\
    \\ENQ\EOT%\STX\n\
    \\SOH\DC2\EOT\174\b\FS-\n\
    \\r\n\
    \\ENQ\EOT%\STX\n\
    \\ETX\DC2\EOT\174\b02\n\
    \I\n\
    \\EOT\EOT%\STX\v\DC2\EOT\177\b\STX\ESC\SUB; Whether to store request and responses. Default is false.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT%\STX\v\ENQ\DC2\EOT\177\b\STX\ACK\n\
    \\r\n\
    \\ENQ\EOT%\STX\v\SOH\DC2\EOT\177\b\a\NAK\n\
    \\r\n\
    \\ENQ\EOT%\STX\v\ETX\DC2\EOT\177\b\CAN\SUB\n\
    \Q\n\
    \\EOT\EOT%\STX\f\DC2\EOT\180\b\STX\"\SUBC Whether to use encrypted thinking for thinking trace rehydration.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT%\STX\f\ENQ\DC2\EOT\180\b\STX\ACK\n\
    \\r\n\
    \\ENQ\EOT%\STX\f\SOH\DC2\EOT\180\b\a\FS\n\
    \\r\n\
    \\ENQ\EOT%\STX\f\ETX\DC2\EOT\180\b\US!\n\
    \_\n\
    \\EOT\EOT%\STX\r\DC2\EOT\183\b\STX&\SUBQ Allow the users to control what optional fields to be returned in the response.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT%\STX\r\EOT\DC2\EOT\183\b\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT%\STX\r\ACK\DC2\EOT\183\b\v\CAN\n\
    \\r\n\
    \\ENQ\EOT%\STX\r\SOH\DC2\EOT\183\b\EM \n\
    \\r\n\
    \\ENQ\EOT%\STX\r\ETX\DC2\EOT\183\b#%\n\
    \A\n\
    \\STX\EOT&\DC2\ACK\187\b\NUL\190\b\SOH\SUB3 Request to retrieve a stored completion response.\n\
    \\n\
    \\v\n\
    \\ETX\EOT&\SOH\DC2\EOT\187\b\b\"\n\
    \0\n\
    \\EOT\EOT&\STX\NUL\DC2\EOT\189\b\STX\EM\SUB\" The response id to be retrieved.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT&\STX\NUL\ENQ\DC2\EOT\189\b\STX\b\n\
    \\r\n\
    \\ENQ\EOT&\STX\NUL\SOH\DC2\EOT\189\b\t\DC4\n\
    \\r\n\
    \\ENQ\EOT&\STX\NUL\ETX\DC2\EOT\189\b\ETB\CAN\n\
    \?\n\
    \\STX\EOT'\DC2\ACK\193\b\NUL\196\b\SOH\SUB1 Request to delete a stored completion response.\n\
    \\n\
    \\v\n\
    \\ETX\EOT'\SOH\DC2\EOT\193\b\b%\n\
    \.\n\
    \\EOT\EOT'\STX\NUL\DC2\EOT\195\b\STX\EM\SUB  The response id to be deleted.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT'\STX\NUL\ENQ\DC2\EOT\195\b\STX\b\n\
    \\r\n\
    \\ENQ\EOT'\STX\NUL\SOH\DC2\EOT\195\b\t\DC4\n\
    \\r\n\
    \\ENQ\EOT'\STX\NUL\ETX\DC2\EOT\195\b\ETB\CAN\n\
    \:\n\
    \\STX\EOT(\DC2\ACK\199\b\NUL\202\b\SOH\SUB, Response for deleting a stored completion.\n\
    \\n\
    \\v\n\
    \\ETX\EOT(\SOH\DC2\EOT\199\b\b&\n\
    \1\n\
    \\EOT\EOT(\STX\NUL\DC2\EOT\201\b\STX\EM\SUB# The response id that was deleted.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT(\STX\NUL\ENQ\DC2\EOT\201\b\STX\b\n\
    \\r\n\
    \\ENQ\EOT(\STX\NUL\SOH\DC2\EOT\201\b\t\DC4\n\
    \\r\n\
    \\ENQ\EOT(\STX\NUL\ETX\DC2\EOT\201\b\ETB\CAN\n\
    \K\n\
    \\STX\EOT)\DC2\ACK\205\b\NUL\241\b\SOH\SUB= Holds debug information. Only available to trusted testers.\n\
    \\n\
    \\v\n\
    \\ETX\EOT)\SOH\DC2\EOT\205\b\b\DC3\n\
    \5\n\
    \\EOT\EOT)\STX\NUL\DC2\EOT\207\b\STX\NAK\SUB' Number of attempts made to the model.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT)\STX\NUL\ENQ\DC2\EOT\207\b\STX\a\n\
    \\r\n\
    \\ENQ\EOT)\STX\NUL\SOH\DC2\EOT\207\b\b\DLE\n\
    \\r\n\
    \\ENQ\EOT)\STX\NUL\ETX\DC2\EOT\207\b\DC3\DC4\n\
    \3\n\
    \\EOT\EOT)\STX\SOH\DC2\EOT\210\b\STX\NAK\SUB% The request received from the user.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT)\STX\SOH\ENQ\DC2\EOT\210\b\STX\b\n\
    \\r\n\
    \\ENQ\EOT)\STX\SOH\SOH\DC2\EOT\210\b\t\DLE\n\
    \\r\n\
    \\ENQ\EOT)\STX\SOH\ETX\DC2\EOT\210\b\DC3\DC4\n\
    \:\n\
    \\EOT\EOT)\STX\STX\DC2\EOT\213\b\STX\DC4\SUB, The prompt sent to the model in text form.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT)\STX\STX\ENQ\DC2\EOT\213\b\STX\b\n\
    \\r\n\
    \\ENQ\EOT)\STX\STX\SOH\DC2\EOT\213\b\t\SI\n\
    \\r\n\
    \\ENQ\EOT)\STX\STX\ETX\DC2\EOT\213\b\DC2\DC3\n\
    \I\n\
    \\EOT\EOT)\STX\ETX\DC2\EOT\216\b\STX\FS\SUB; The JSON-serialized request sent to the inference engine.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT)\STX\ETX\ENQ\DC2\EOT\216\b\STX\b\n\
    \\r\n\
    \\ENQ\EOT)\STX\ETX\SOH\DC2\EOT\216\b\t\ETB\n\
    \\r\n\
    \\ENQ\EOT)\STX\ETX\ETX\DC2\EOT\216\b\SUB\ESC\n\
    \8\n\
    \\EOT\EOT)\STX\EOT\DC2\EOT\219\b\STX \SUB* The response(s) received from the model.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT)\STX\EOT\EOT\DC2\EOT\219\b\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT)\STX\EOT\ENQ\DC2\EOT\219\b\v\DC1\n\
    \\r\n\
    \\ENQ\EOT)\STX\EOT\SOH\DC2\EOT\219\b\DC2\ESC\n\
    \\r\n\
    \\ENQ\EOT)\STX\EOT\ETX\DC2\EOT\219\b\RS\US\n\
    \F\n\
    \\EOT\EOT)\STX\ENQ\DC2\EOT\222\b\STX\RS\SUB8 The raw chunks returned from the pipeline of samplers.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT)\STX\ENQ\EOT\DC2\EOT\222\b\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT)\STX\ENQ\ENQ\DC2\EOT\222\b\v\DC1\n\
    \\r\n\
    \\ENQ\EOT)\STX\ENQ\SOH\DC2\EOT\222\b\DC2\CAN\n\
    \\r\n\
    \\ENQ\EOT)\STX\ENQ\ETX\DC2\EOT\222\b\ESC\GS\n\
    \%\n\
    \\EOT\EOT)\STX\ACK\DC2\EOT\225\b\STX\RS\SUB\ETB Number of cache reads\n\
    \\n\
    \\r\n\
    \\ENQ\EOT)\STX\ACK\ENQ\DC2\EOT\225\b\STX\b\n\
    \\r\n\
    \\ENQ\EOT)\STX\ACK\SOH\DC2\EOT\225\b\t\EM\n\
    \\r\n\
    \\ENQ\EOT)\STX\ACK\ETX\DC2\EOT\225\b\FS\GS\n\
    \\"\n\
    \\EOT\EOT)\STX\a\DC2\EOT\228\b\STX$\SUB\DC4 Size of cache read\n\
    \\n\
    \\r\n\
    \\ENQ\EOT)\STX\a\ENQ\DC2\EOT\228\b\STX\b\n\
    \\r\n\
    \\ENQ\EOT)\STX\a\SOH\DC2\EOT\228\b\t\US\n\
    \\r\n\
    \\ENQ\EOT)\STX\a\ETX\DC2\EOT\228\b\"#\n\
    \&\n\
    \\EOT\EOT)\STX\b\DC2\EOT\231\b\STX\US\SUB\CAN Number of cache writes\n\
    \\n\
    \\r\n\
    \\ENQ\EOT)\STX\b\ENQ\DC2\EOT\231\b\STX\b\n\
    \\r\n\
    \\ENQ\EOT)\STX\b\SOH\DC2\EOT\231\b\t\SUB\n\
    \\r\n\
    \\ENQ\EOT)\STX\b\ETX\DC2\EOT\231\b\GS\RS\n\
    \#\n\
    \\EOT\EOT)\STX\t\DC2\EOT\234\b\STX%\SUB\NAK Size of cache write\n\
    \\n\
    \\r\n\
    \\ENQ\EOT)\STX\t\ENQ\DC2\EOT\234\b\STX\b\n\
    \\r\n\
    \\ENQ\EOT)\STX\t\SOH\DC2\EOT\234\b\t \n\
    \\r\n\
    \\ENQ\EOT)\STX\t\ETX\DC2\EOT\234\b#$\n\
    \%\n\
    \\EOT\EOT)\STX\n\
    \\DC2\EOT\237\b\STX\EM\SUB\ETB The lb address header\n\
    \\n\
    \\r\n\
    \\ENQ\EOT)\STX\n\
    \\ENQ\DC2\EOT\237\b\STX\b\n\
    \\r\n\
    \\ENQ\EOT)\STX\n\
    \\SOH\DC2\EOT\237\b\t\DC3\n\
    \\r\n\
    \\ENQ\EOT)\STX\n\
    \\ETX\DC2\EOT\237\b\SYN\CAN\n\
    \@\n\
    \\EOT\EOT)\STX\v\DC2\EOT\240\b\STX\SUB\SUB2 The tag of the sampler that served this request.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT)\STX\v\ENQ\DC2\EOT\240\b\STX\b\n\
    \\r\n\
    \\ENQ\EOT)\STX\v\SOH\DC2\EOT\240\b\t\DC4\n\
    \\r\n\
    \\ENQ\EOT)\STX\v\ETX\DC2\EOT\240\b\ETB\EM\n\
    \\225\SOH\n\
    \\STX\EOT*\DC2\ACK\246\b\NUL\254\b\SOH\SUB0 Request for the standalone CompactContext RPC.\n\
    \2\160\SOH \226\148\128\226\148\128 Context compaction messages \226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\n\
    \\n\
    \\v\n\
    \\ETX\EOT*\SOH\DC2\EOT\246\b\b\GS\n\
    \@\n\
    \\EOT\EOT*\STX\NUL\DC2\EOT\248\b\STX\DC3\SUB2 Model to use for generating the compaction blob.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT*\STX\NUL\ENQ\DC2\EOT\248\b\STX\b\n\
    \\r\n\
    \\ENQ\EOT*\STX\NUL\SOH\DC2\EOT\248\b\t\SO\n\
    \\r\n\
    \\ENQ\EOT*\STX\NUL\ETX\DC2\EOT\248\b\DC1\DC2\n\
    \\153\SOH\n\
    \\EOT\EOT*\STX\SOH\DC2\EOT\253\b\STX\GS\SUB\138\SOH Full current input window as proto messages.\n\
    \ This is the same set of messages the client would send in\n\
    \ GetCompletionsRequest.messages.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT*\STX\SOH\EOT\DC2\EOT\253\b\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT*\STX\SOH\ACK\DC2\EOT\253\b\v\DC2\n\
    \\r\n\
    \\ENQ\EOT*\STX\SOH\SOH\DC2\EOT\253\b\DC3\CAN\n\
    \\r\n\
    \\ENQ\EOT*\STX\SOH\ETX\DC2\EOT\253\b\ESC\FS\n\
    \@\n\
    \\STX\EOT+\DC2\ACK\129\t\NUL\143\t\SOH\SUB2 Response from the standalone CompactContext RPC.\n\
    \\n\
    \\v\n\
    \\ETX\EOT+\SOH\DC2\EOT\129\t\b\RS\n\
    \7\n\
    \\EOT\EOT+\STX\NUL\DC2\EOT\131\t\STX\DLE\SUB) Unique compaction ID (e.g. cmp_<uuid>).\n\
    \\n\
    \\r\n\
    \\ENQ\EOT+\STX\NUL\ENQ\DC2\EOT\131\t\STX\b\n\
    \\r\n\
    \\ENQ\EOT+\STX\NUL\SOH\DC2\EOT\131\t\t\v\n\
    \\r\n\
    \\ENQ\EOT+\STX\NUL\ETX\DC2\EOT\131\t\SO\SI\n\
    \\131\SOH\n\
    \\EOT\EOT+\STX\SOH\DC2\EOT\135\t\STX\US\SUBu Opaque blob representing the compacted conversation. Clients must pass\n\
    \ this back unchanged in subsequent requests.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT+\STX\SOH\ENQ\DC2\EOT\135\t\STX\b\n\
    \\r\n\
    \\ENQ\EOT+\STX\SOH\SOH\DC2\EOT\135\t\t\SUB\n\
    \\r\n\
    \\ENQ\EOT+\STX\SOH\ETX\DC2\EOT\135\t\GS\RS\n\
    \\149\SOH\n\
    \\EOT\EOT+\STX\STX\DC2\EOT\139\t\STX#\SUB\134\SOH Number of input Message entries (role + content pairs) from the\n\
    \ original input that were dropped or folded into the compacted blob.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT+\STX\STX\ENQ\DC2\EOT\139\t\STX\b\n\
    \\r\n\
    \\ENQ\EOT+\STX\STX\SOH\DC2\EOT\139\t\t\RS\n\
    \\r\n\
    \\ENQ\EOT+\STX\STX\ETX\DC2\EOT\139\t!\"\n\
    \;\n\
    \\EOT\EOT+\STX\ETX\DC2\EOT\142\t\STX\SUB\SUB- Token usage from the compacting model call.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT+\STX\ETX\ACK\DC2\EOT\142\t\STX\SI\n\
    \\r\n\
    \\ENQ\EOT+\STX\ETX\SOH\DC2\EOT\142\t\DLE\NAK\n\
    \\r\n\
    \\ENQ\EOT+\STX\ETX\ETX\DC2\EOT\142\t\CAN\EMb\ACKproto3"