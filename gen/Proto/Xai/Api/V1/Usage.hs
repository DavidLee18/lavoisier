{- This file was auto-generated from xai/api/v1/usage.proto by the proto-lens-protoc program. -}
{-# LANGUAGE ScopedTypeVariables, DataKinds, TypeFamilies, UndecidableInstances, GeneralizedNewtypeDeriving, MultiParamTypeClasses, FlexibleContexts, FlexibleInstances, PatternSynonyms, MagicHash, NoImplicitPrelude, DataKinds, BangPatterns, TypeApplications, OverloadedStrings, DerivingStrategies#-}
{-# OPTIONS_GHC -Wno-unused-imports#-}
{-# OPTIONS_GHC -Wno-duplicate-exports#-}
{-# OPTIONS_GHC -Wno-dodgy-exports#-}
module Proto.Xai.Api.V1.Usage (
        EmbeddingUsage(), SamplingUsage(), ServerSideTool(..),
        ServerSideTool(), ServerSideTool'UnrecognizedValue
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
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Usage_Fields.numTextEmbeddings' @:: Lens' EmbeddingUsage Data.Int.Int32@
         * 'Proto.Xai.Api.V1.Usage_Fields.numImageEmbeddings' @:: Lens' EmbeddingUsage Data.Int.Int32@ -}
data EmbeddingUsage
  = EmbeddingUsage'_constructor {_EmbeddingUsage'numTextEmbeddings :: !Data.Int.Int32,
                                 _EmbeddingUsage'numImageEmbeddings :: !Data.Int.Int32,
                                 _EmbeddingUsage'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show EmbeddingUsage where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField EmbeddingUsage "numTextEmbeddings" Data.Int.Int32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _EmbeddingUsage'numTextEmbeddings
           (\ x__ y__ -> x__ {_EmbeddingUsage'numTextEmbeddings = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField EmbeddingUsage "numImageEmbeddings" Data.Int.Int32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _EmbeddingUsage'numImageEmbeddings
           (\ x__ y__ -> x__ {_EmbeddingUsage'numImageEmbeddings = y__}))
        Prelude.id
instance Data.ProtoLens.Message EmbeddingUsage where
  messageName _ = Data.Text.pack "xai_api.EmbeddingUsage"
  packedMessageDescriptor _
    = "\n\
      \\SOEmbeddingUsage\DC2.\n\
      \\DC3num_text_embeddings\CAN\SOH \SOH(\ENQR\DC1numTextEmbeddings\DC20\n\
      \\DC4num_image_embeddings\CAN\STX \SOH(\ENQR\DC2numImageEmbeddings"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        numTextEmbeddings__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "num_text_embeddings"
              (Data.ProtoLens.ScalarField Data.ProtoLens.Int32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Int.Int32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"numTextEmbeddings")) ::
              Data.ProtoLens.FieldDescriptor EmbeddingUsage
        numImageEmbeddings__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "num_image_embeddings"
              (Data.ProtoLens.ScalarField Data.ProtoLens.Int32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Int.Int32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"numImageEmbeddings")) ::
              Data.ProtoLens.FieldDescriptor EmbeddingUsage
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, numTextEmbeddings__field_descriptor),
           (Data.ProtoLens.Tag 2, numImageEmbeddings__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _EmbeddingUsage'_unknownFields
        (\ x__ y__ -> x__ {_EmbeddingUsage'_unknownFields = y__})
  defMessage
    = EmbeddingUsage'_constructor
        {_EmbeddingUsage'numTextEmbeddings = Data.ProtoLens.fieldDefault,
         _EmbeddingUsage'numImageEmbeddings = Data.ProtoLens.fieldDefault,
         _EmbeddingUsage'_unknownFields = []}
  parseMessage
    = let
        loop ::
          EmbeddingUsage
          -> Data.ProtoLens.Encoding.Bytes.Parser EmbeddingUsage
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
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "num_text_embeddings"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"numTextEmbeddings") y x)
                        16
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "num_image_embeddings"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"numImageEmbeddings") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "EmbeddingUsage"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v
                  = Lens.Family2.view
                      (Data.ProtoLens.Field.field @"numTextEmbeddings") _x
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
                   _v
                     = Lens.Family2.view
                         (Data.ProtoLens.Field.field @"numImageEmbeddings") _x
                 in
                   if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                       Data.Monoid.mempty
                   else
                       (Data.Monoid.<>)
                         (Data.ProtoLens.Encoding.Bytes.putVarInt 16)
                         ((Prelude..)
                            Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral _v))
                (Data.ProtoLens.Encoding.Wire.buildFieldSet
                   (Lens.Family2.view Data.ProtoLens.unknownFields _x)))
instance Control.DeepSeq.NFData EmbeddingUsage where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_EmbeddingUsage'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_EmbeddingUsage'numTextEmbeddings x__)
                (Control.DeepSeq.deepseq
                   (_EmbeddingUsage'numImageEmbeddings x__) ()))
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Usage_Fields.completionTokens' @:: Lens' SamplingUsage Data.Int.Int32@
         * 'Proto.Xai.Api.V1.Usage_Fields.reasoningTokens' @:: Lens' SamplingUsage Data.Int.Int32@
         * 'Proto.Xai.Api.V1.Usage_Fields.promptTokens' @:: Lens' SamplingUsage Data.Int.Int32@
         * 'Proto.Xai.Api.V1.Usage_Fields.totalTokens' @:: Lens' SamplingUsage Data.Int.Int32@
         * 'Proto.Xai.Api.V1.Usage_Fields.promptTextTokens' @:: Lens' SamplingUsage Data.Int.Int32@
         * 'Proto.Xai.Api.V1.Usage_Fields.cachedPromptTextTokens' @:: Lens' SamplingUsage Data.Int.Int32@
         * 'Proto.Xai.Api.V1.Usage_Fields.promptImageTokens' @:: Lens' SamplingUsage Data.Int.Int32@
         * 'Proto.Xai.Api.V1.Usage_Fields.numSourcesUsed' @:: Lens' SamplingUsage Data.Int.Int32@
         * 'Proto.Xai.Api.V1.Usage_Fields.serverSideToolsUsed' @:: Lens' SamplingUsage [ServerSideTool]@
         * 'Proto.Xai.Api.V1.Usage_Fields.vec'serverSideToolsUsed' @:: Lens' SamplingUsage (Data.Vector.Vector ServerSideTool)@
         * 'Proto.Xai.Api.V1.Usage_Fields.costInUsdTicks' @:: Lens' SamplingUsage Data.Int.Int64@
         * 'Proto.Xai.Api.V1.Usage_Fields.maybe'costInUsdTicks' @:: Lens' SamplingUsage (Prelude.Maybe Data.Int.Int64)@ -}
data SamplingUsage
  = SamplingUsage'_constructor {_SamplingUsage'completionTokens :: !Data.Int.Int32,
                                _SamplingUsage'reasoningTokens :: !Data.Int.Int32,
                                _SamplingUsage'promptTokens :: !Data.Int.Int32,
                                _SamplingUsage'totalTokens :: !Data.Int.Int32,
                                _SamplingUsage'promptTextTokens :: !Data.Int.Int32,
                                _SamplingUsage'cachedPromptTextTokens :: !Data.Int.Int32,
                                _SamplingUsage'promptImageTokens :: !Data.Int.Int32,
                                _SamplingUsage'numSourcesUsed :: !Data.Int.Int32,
                                _SamplingUsage'serverSideToolsUsed :: !(Data.Vector.Vector ServerSideTool),
                                _SamplingUsage'costInUsdTicks :: !(Prelude.Maybe Data.Int.Int64),
                                _SamplingUsage'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show SamplingUsage where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField SamplingUsage "completionTokens" Data.Int.Int32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SamplingUsage'completionTokens
           (\ x__ y__ -> x__ {_SamplingUsage'completionTokens = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SamplingUsage "reasoningTokens" Data.Int.Int32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SamplingUsage'reasoningTokens
           (\ x__ y__ -> x__ {_SamplingUsage'reasoningTokens = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SamplingUsage "promptTokens" Data.Int.Int32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SamplingUsage'promptTokens
           (\ x__ y__ -> x__ {_SamplingUsage'promptTokens = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SamplingUsage "totalTokens" Data.Int.Int32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SamplingUsage'totalTokens
           (\ x__ y__ -> x__ {_SamplingUsage'totalTokens = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SamplingUsage "promptTextTokens" Data.Int.Int32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SamplingUsage'promptTextTokens
           (\ x__ y__ -> x__ {_SamplingUsage'promptTextTokens = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SamplingUsage "cachedPromptTextTokens" Data.Int.Int32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SamplingUsage'cachedPromptTextTokens
           (\ x__ y__ -> x__ {_SamplingUsage'cachedPromptTextTokens = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SamplingUsage "promptImageTokens" Data.Int.Int32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SamplingUsage'promptImageTokens
           (\ x__ y__ -> x__ {_SamplingUsage'promptImageTokens = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SamplingUsage "numSourcesUsed" Data.Int.Int32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SamplingUsage'numSourcesUsed
           (\ x__ y__ -> x__ {_SamplingUsage'numSourcesUsed = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SamplingUsage "serverSideToolsUsed" [ServerSideTool] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SamplingUsage'serverSideToolsUsed
           (\ x__ y__ -> x__ {_SamplingUsage'serverSideToolsUsed = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField SamplingUsage "vec'serverSideToolsUsed" (Data.Vector.Vector ServerSideTool) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SamplingUsage'serverSideToolsUsed
           (\ x__ y__ -> x__ {_SamplingUsage'serverSideToolsUsed = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SamplingUsage "costInUsdTicks" Data.Int.Int64 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SamplingUsage'costInUsdTicks
           (\ x__ y__ -> x__ {_SamplingUsage'costInUsdTicks = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField SamplingUsage "maybe'costInUsdTicks" (Prelude.Maybe Data.Int.Int64) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SamplingUsage'costInUsdTicks
           (\ x__ y__ -> x__ {_SamplingUsage'costInUsdTicks = y__}))
        Prelude.id
instance Data.ProtoLens.Message SamplingUsage where
  messageName _ = Data.Text.pack "xai_api.SamplingUsage"
  packedMessageDescriptor _
    = "\n\
      \\rSamplingUsage\DC2+\n\
      \\DC1completion_tokens\CAN\SOH \SOH(\ENQR\DLEcompletionTokens\DC2)\n\
      \\DLEreasoning_tokens\CAN\ACK \SOH(\ENQR\SIreasoningTokens\DC2#\n\
      \\rprompt_tokens\CAN\STX \SOH(\ENQR\fpromptTokens\DC2!\n\
      \\ftotal_tokens\CAN\ETX \SOH(\ENQR\vtotalTokens\DC2,\n\
      \\DC2prompt_text_tokens\CAN\EOT \SOH(\ENQR\DLEpromptTextTokens\DC29\n\
      \\EMcached_prompt_text_tokens\CAN\a \SOH(\ENQR\SYNcachedPromptTextTokens\DC2.\n\
      \\DC3prompt_image_tokens\CAN\ENQ \SOH(\ENQR\DC1promptImageTokens\DC2(\n\
      \\DLEnum_sources_used\CAN\b \SOH(\ENQR\SOnumSourcesUsed\DC2L\n\
      \\SYNserver_side_tools_used\CAN\t \ETX(\SO2\ETB.xai_api.ServerSideToolR\DC3serverSideToolsUsed\DC2.\n\
      \\DC1cost_in_usd_ticks\CAN\v \SOH(\ETXH\NULR\SOcostInUsdTicks\136\SOH\SOHB\DC4\n\
      \\DC2_cost_in_usd_ticks"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        completionTokens__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "completion_tokens"
              (Data.ProtoLens.ScalarField Data.ProtoLens.Int32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Int.Int32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"completionTokens")) ::
              Data.ProtoLens.FieldDescriptor SamplingUsage
        reasoningTokens__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "reasoning_tokens"
              (Data.ProtoLens.ScalarField Data.ProtoLens.Int32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Int.Int32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"reasoningTokens")) ::
              Data.ProtoLens.FieldDescriptor SamplingUsage
        promptTokens__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "prompt_tokens"
              (Data.ProtoLens.ScalarField Data.ProtoLens.Int32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Int.Int32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"promptTokens")) ::
              Data.ProtoLens.FieldDescriptor SamplingUsage
        totalTokens__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "total_tokens"
              (Data.ProtoLens.ScalarField Data.ProtoLens.Int32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Int.Int32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"totalTokens")) ::
              Data.ProtoLens.FieldDescriptor SamplingUsage
        promptTextTokens__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "prompt_text_tokens"
              (Data.ProtoLens.ScalarField Data.ProtoLens.Int32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Int.Int32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"promptTextTokens")) ::
              Data.ProtoLens.FieldDescriptor SamplingUsage
        cachedPromptTextTokens__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "cached_prompt_text_tokens"
              (Data.ProtoLens.ScalarField Data.ProtoLens.Int32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Int.Int32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"cachedPromptTextTokens")) ::
              Data.ProtoLens.FieldDescriptor SamplingUsage
        promptImageTokens__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "prompt_image_tokens"
              (Data.ProtoLens.ScalarField Data.ProtoLens.Int32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Int.Int32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"promptImageTokens")) ::
              Data.ProtoLens.FieldDescriptor SamplingUsage
        numSourcesUsed__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "num_sources_used"
              (Data.ProtoLens.ScalarField Data.ProtoLens.Int32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Int.Int32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"numSourcesUsed")) ::
              Data.ProtoLens.FieldDescriptor SamplingUsage
        serverSideToolsUsed__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "server_side_tools_used"
              (Data.ProtoLens.ScalarField Data.ProtoLens.EnumField ::
                 Data.ProtoLens.FieldTypeDescriptor ServerSideTool)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Packed
                 (Data.ProtoLens.Field.field @"serverSideToolsUsed")) ::
              Data.ProtoLens.FieldDescriptor SamplingUsage
        costInUsdTicks__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "cost_in_usd_ticks"
              (Data.ProtoLens.ScalarField Data.ProtoLens.Int64Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Int.Int64)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'costInUsdTicks")) ::
              Data.ProtoLens.FieldDescriptor SamplingUsage
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, completionTokens__field_descriptor),
           (Data.ProtoLens.Tag 6, reasoningTokens__field_descriptor),
           (Data.ProtoLens.Tag 2, promptTokens__field_descriptor),
           (Data.ProtoLens.Tag 3, totalTokens__field_descriptor),
           (Data.ProtoLens.Tag 4, promptTextTokens__field_descriptor),
           (Data.ProtoLens.Tag 7, cachedPromptTextTokens__field_descriptor),
           (Data.ProtoLens.Tag 5, promptImageTokens__field_descriptor),
           (Data.ProtoLens.Tag 8, numSourcesUsed__field_descriptor),
           (Data.ProtoLens.Tag 9, serverSideToolsUsed__field_descriptor),
           (Data.ProtoLens.Tag 11, costInUsdTicks__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _SamplingUsage'_unknownFields
        (\ x__ y__ -> x__ {_SamplingUsage'_unknownFields = y__})
  defMessage
    = SamplingUsage'_constructor
        {_SamplingUsage'completionTokens = Data.ProtoLens.fieldDefault,
         _SamplingUsage'reasoningTokens = Data.ProtoLens.fieldDefault,
         _SamplingUsage'promptTokens = Data.ProtoLens.fieldDefault,
         _SamplingUsage'totalTokens = Data.ProtoLens.fieldDefault,
         _SamplingUsage'promptTextTokens = Data.ProtoLens.fieldDefault,
         _SamplingUsage'cachedPromptTextTokens = Data.ProtoLens.fieldDefault,
         _SamplingUsage'promptImageTokens = Data.ProtoLens.fieldDefault,
         _SamplingUsage'numSourcesUsed = Data.ProtoLens.fieldDefault,
         _SamplingUsage'serverSideToolsUsed = Data.Vector.Generic.empty,
         _SamplingUsage'costInUsdTicks = Prelude.Nothing,
         _SamplingUsage'_unknownFields = []}
  parseMessage
    = let
        loop ::
          SamplingUsage
          -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Vector Data.ProtoLens.Encoding.Growing.RealWorld ServerSideTool
             -> Data.ProtoLens.Encoding.Bytes.Parser SamplingUsage
        loop x mutable'serverSideToolsUsed
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do frozen'serverSideToolsUsed <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                                      (Data.ProtoLens.Encoding.Growing.unsafeFreeze
                                                         mutable'serverSideToolsUsed)
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
                              (Data.ProtoLens.Field.field @"vec'serverSideToolsUsed")
                              frozen'serverSideToolsUsed x))
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        8 -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "completion_tokens"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"completionTokens") y x)
                                  mutable'serverSideToolsUsed
                        48
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "reasoning_tokens"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"reasoningTokens") y x)
                                  mutable'serverSideToolsUsed
                        16
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "prompt_tokens"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"promptTokens") y x)
                                  mutable'serverSideToolsUsed
                        24
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "total_tokens"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"totalTokens") y x)
                                  mutable'serverSideToolsUsed
                        32
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "prompt_text_tokens"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"promptTextTokens") y x)
                                  mutable'serverSideToolsUsed
                        56
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "cached_prompt_text_tokens"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"cachedPromptTextTokens") y x)
                                  mutable'serverSideToolsUsed
                        40
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "prompt_image_tokens"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"promptImageTokens") y x)
                                  mutable'serverSideToolsUsed
                        64
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "num_sources_used"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"numSourcesUsed") y x)
                                  mutable'serverSideToolsUsed
                        72
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (Prelude.fmap
                                           Prelude.toEnum
                                           (Prelude.fmap
                                              Prelude.fromIntegral
                                              Data.ProtoLens.Encoding.Bytes.getVarInt))
                                        "server_side_tools_used"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append
                                          mutable'serverSideToolsUsed y)
                                loop x v
                        74
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
                                                                    "server_side_tools_used"
                                                            qs' <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                                                     (Data.ProtoLens.Encoding.Growing.append
                                                                        qs q)
                                                            ploop qs'
                                            in ploop)
                                             mutable'serverSideToolsUsed)
                                loop x y
                        88
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "cost_in_usd_ticks"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"costInUsdTicks") y x)
                                  mutable'serverSideToolsUsed
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
                                  mutable'serverSideToolsUsed
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do mutable'serverSideToolsUsed <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                               Data.ProtoLens.Encoding.Growing.new
              loop Data.ProtoLens.defMessage mutable'serverSideToolsUsed)
          "SamplingUsage"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v
                  = Lens.Family2.view
                      (Data.ProtoLens.Field.field @"completionTokens") _x
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
                   _v
                     = Lens.Family2.view
                         (Data.ProtoLens.Field.field @"reasoningTokens") _x
                 in
                   if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                       Data.Monoid.mempty
                   else
                       (Data.Monoid.<>)
                         (Data.ProtoLens.Encoding.Bytes.putVarInt 48)
                         ((Prelude..)
                            Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral _v))
                ((Data.Monoid.<>)
                   (let
                      _v
                        = Lens.Family2.view (Data.ProtoLens.Field.field @"promptTokens") _x
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
                         _v
                           = Lens.Family2.view (Data.ProtoLens.Field.field @"totalTokens") _x
                       in
                         if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                             Data.Monoid.mempty
                         else
                             (Data.Monoid.<>)
                               (Data.ProtoLens.Encoding.Bytes.putVarInt 24)
                               ((Prelude..)
                                  Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral _v))
                      ((Data.Monoid.<>)
                         (let
                            _v
                              = Lens.Family2.view
                                  (Data.ProtoLens.Field.field @"promptTextTokens") _x
                          in
                            if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                Data.Monoid.mempty
                            else
                                (Data.Monoid.<>)
                                  (Data.ProtoLens.Encoding.Bytes.putVarInt 32)
                                  ((Prelude..)
                                     Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral
                                     _v))
                         ((Data.Monoid.<>)
                            (let
                               _v
                                 = Lens.Family2.view
                                     (Data.ProtoLens.Field.field @"cachedPromptTextTokens") _x
                             in
                               if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                   Data.Monoid.mempty
                               else
                                   (Data.Monoid.<>)
                                     (Data.ProtoLens.Encoding.Bytes.putVarInt 56)
                                     ((Prelude..)
                                        Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral
                                        _v))
                            ((Data.Monoid.<>)
                               (let
                                  _v
                                    = Lens.Family2.view
                                        (Data.ProtoLens.Field.field @"promptImageTokens") _x
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
                                           (Data.ProtoLens.Field.field @"numSourcesUsed") _x
                                   in
                                     if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                         Data.Monoid.mempty
                                     else
                                         (Data.Monoid.<>)
                                           (Data.ProtoLens.Encoding.Bytes.putVarInt 64)
                                           ((Prelude..)
                                              Data.ProtoLens.Encoding.Bytes.putVarInt
                                              Prelude.fromIntegral _v))
                                  ((Data.Monoid.<>)
                                     (let
                                        p = Lens.Family2.view
                                              (Data.ProtoLens.Field.field
                                                 @"vec'serverSideToolsUsed")
                                              _x
                                      in
                                        if Data.Vector.Generic.null p then
                                            Data.Monoid.mempty
                                        else
                                            (Data.Monoid.<>)
                                              (Data.ProtoLens.Encoding.Bytes.putVarInt 74)
                                              ((\ bs
                                                  -> (Data.Monoid.<>)
                                                       (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                          (Prelude.fromIntegral
                                                             (Data.ByteString.length bs)))
                                                       (Data.ProtoLens.Encoding.Bytes.putBytes bs))
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
                                               (Data.ProtoLens.Field.field @"maybe'costInUsdTicks")
                                               _x
                                         of
                                           Prelude.Nothing -> Data.Monoid.mempty
                                           (Prelude.Just _v)
                                             -> (Data.Monoid.<>)
                                                  (Data.ProtoLens.Encoding.Bytes.putVarInt 88)
                                                  ((Prelude..)
                                                     Data.ProtoLens.Encoding.Bytes.putVarInt
                                                     Prelude.fromIntegral _v))
                                        (Data.ProtoLens.Encoding.Wire.buildFieldSet
                                           (Lens.Family2.view
                                              Data.ProtoLens.unknownFields _x)))))))))))
instance Control.DeepSeq.NFData SamplingUsage where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_SamplingUsage'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_SamplingUsage'completionTokens x__)
                (Control.DeepSeq.deepseq
                   (_SamplingUsage'reasoningTokens x__)
                   (Control.DeepSeq.deepseq
                      (_SamplingUsage'promptTokens x__)
                      (Control.DeepSeq.deepseq
                         (_SamplingUsage'totalTokens x__)
                         (Control.DeepSeq.deepseq
                            (_SamplingUsage'promptTextTokens x__)
                            (Control.DeepSeq.deepseq
                               (_SamplingUsage'cachedPromptTextTokens x__)
                               (Control.DeepSeq.deepseq
                                  (_SamplingUsage'promptImageTokens x__)
                                  (Control.DeepSeq.deepseq
                                     (_SamplingUsage'numSourcesUsed x__)
                                     (Control.DeepSeq.deepseq
                                        (_SamplingUsage'serverSideToolsUsed x__)
                                        (Control.DeepSeq.deepseq
                                           (_SamplingUsage'costInUsdTicks x__) ()))))))))))
newtype ServerSideTool'UnrecognizedValue
  = ServerSideTool'UnrecognizedValue Data.Int.Int32
  deriving stock (Prelude.Eq, Prelude.Ord, Prelude.Show)
data ServerSideTool
  = SERVER_SIDE_TOOL_INVALID |
    SERVER_SIDE_TOOL_WEB_SEARCH |
    SERVER_SIDE_TOOL_X_SEARCH |
    SERVER_SIDE_TOOL_CODE_EXECUTION |
    SERVER_SIDE_TOOL_VIEW_IMAGE |
    SERVER_SIDE_TOOL_VIEW_X_VIDEO |
    SERVER_SIDE_TOOL_COLLECTIONS_SEARCH |
    SERVER_SIDE_TOOL_MCP |
    SERVER_SIDE_TOOL_ATTACHMENT_SEARCH |
    SERVER_SIDE_TOOL_IMAGE_SEARCH |
    ServerSideTool'Unrecognized !ServerSideTool'UnrecognizedValue
  deriving stock (Prelude.Show, Prelude.Eq, Prelude.Ord)
instance Data.ProtoLens.MessageEnum ServerSideTool where
  maybeToEnum 0 = Prelude.Just SERVER_SIDE_TOOL_INVALID
  maybeToEnum 1 = Prelude.Just SERVER_SIDE_TOOL_WEB_SEARCH
  maybeToEnum 2 = Prelude.Just SERVER_SIDE_TOOL_X_SEARCH
  maybeToEnum 3 = Prelude.Just SERVER_SIDE_TOOL_CODE_EXECUTION
  maybeToEnum 4 = Prelude.Just SERVER_SIDE_TOOL_VIEW_IMAGE
  maybeToEnum 5 = Prelude.Just SERVER_SIDE_TOOL_VIEW_X_VIDEO
  maybeToEnum 6 = Prelude.Just SERVER_SIDE_TOOL_COLLECTIONS_SEARCH
  maybeToEnum 7 = Prelude.Just SERVER_SIDE_TOOL_MCP
  maybeToEnum 8 = Prelude.Just SERVER_SIDE_TOOL_ATTACHMENT_SEARCH
  maybeToEnum 10 = Prelude.Just SERVER_SIDE_TOOL_IMAGE_SEARCH
  maybeToEnum k
    = Prelude.Just
        (ServerSideTool'Unrecognized
           (ServerSideTool'UnrecognizedValue (Prelude.fromIntegral k)))
  showEnum SERVER_SIDE_TOOL_INVALID = "SERVER_SIDE_TOOL_INVALID"
  showEnum SERVER_SIDE_TOOL_WEB_SEARCH
    = "SERVER_SIDE_TOOL_WEB_SEARCH"
  showEnum SERVER_SIDE_TOOL_X_SEARCH = "SERVER_SIDE_TOOL_X_SEARCH"
  showEnum SERVER_SIDE_TOOL_CODE_EXECUTION
    = "SERVER_SIDE_TOOL_CODE_EXECUTION"
  showEnum SERVER_SIDE_TOOL_VIEW_IMAGE
    = "SERVER_SIDE_TOOL_VIEW_IMAGE"
  showEnum SERVER_SIDE_TOOL_VIEW_X_VIDEO
    = "SERVER_SIDE_TOOL_VIEW_X_VIDEO"
  showEnum SERVER_SIDE_TOOL_COLLECTIONS_SEARCH
    = "SERVER_SIDE_TOOL_COLLECTIONS_SEARCH"
  showEnum SERVER_SIDE_TOOL_MCP = "SERVER_SIDE_TOOL_MCP"
  showEnum SERVER_SIDE_TOOL_ATTACHMENT_SEARCH
    = "SERVER_SIDE_TOOL_ATTACHMENT_SEARCH"
  showEnum SERVER_SIDE_TOOL_IMAGE_SEARCH
    = "SERVER_SIDE_TOOL_IMAGE_SEARCH"
  showEnum
    (ServerSideTool'Unrecognized (ServerSideTool'UnrecognizedValue k))
    = Prelude.show k
  readEnum k
    | (Prelude.==) k "SERVER_SIDE_TOOL_INVALID"
    = Prelude.Just SERVER_SIDE_TOOL_INVALID
    | (Prelude.==) k "SERVER_SIDE_TOOL_WEB_SEARCH"
    = Prelude.Just SERVER_SIDE_TOOL_WEB_SEARCH
    | (Prelude.==) k "SERVER_SIDE_TOOL_X_SEARCH"
    = Prelude.Just SERVER_SIDE_TOOL_X_SEARCH
    | (Prelude.==) k "SERVER_SIDE_TOOL_CODE_EXECUTION"
    = Prelude.Just SERVER_SIDE_TOOL_CODE_EXECUTION
    | (Prelude.==) k "SERVER_SIDE_TOOL_VIEW_IMAGE"
    = Prelude.Just SERVER_SIDE_TOOL_VIEW_IMAGE
    | (Prelude.==) k "SERVER_SIDE_TOOL_VIEW_X_VIDEO"
    = Prelude.Just SERVER_SIDE_TOOL_VIEW_X_VIDEO
    | (Prelude.==) k "SERVER_SIDE_TOOL_COLLECTIONS_SEARCH"
    = Prelude.Just SERVER_SIDE_TOOL_COLLECTIONS_SEARCH
    | (Prelude.==) k "SERVER_SIDE_TOOL_MCP"
    = Prelude.Just SERVER_SIDE_TOOL_MCP
    | (Prelude.==) k "SERVER_SIDE_TOOL_ATTACHMENT_SEARCH"
    = Prelude.Just SERVER_SIDE_TOOL_ATTACHMENT_SEARCH
    | (Prelude.==) k "SERVER_SIDE_TOOL_IMAGE_SEARCH"
    = Prelude.Just SERVER_SIDE_TOOL_IMAGE_SEARCH
    | Prelude.otherwise
    = (Prelude.>>=) (Text.Read.readMaybe k) Data.ProtoLens.maybeToEnum
instance Prelude.Bounded ServerSideTool where
  minBound = SERVER_SIDE_TOOL_INVALID
  maxBound = SERVER_SIDE_TOOL_IMAGE_SEARCH
instance Prelude.Enum ServerSideTool where
  toEnum k__
    = Prelude.maybe
        (Prelude.error
           ((Prelude.++)
              "toEnum: unknown value for enum ServerSideTool: "
              (Prelude.show k__)))
        Prelude.id (Data.ProtoLens.maybeToEnum k__)
  fromEnum SERVER_SIDE_TOOL_INVALID = 0
  fromEnum SERVER_SIDE_TOOL_WEB_SEARCH = 1
  fromEnum SERVER_SIDE_TOOL_X_SEARCH = 2
  fromEnum SERVER_SIDE_TOOL_CODE_EXECUTION = 3
  fromEnum SERVER_SIDE_TOOL_VIEW_IMAGE = 4
  fromEnum SERVER_SIDE_TOOL_VIEW_X_VIDEO = 5
  fromEnum SERVER_SIDE_TOOL_COLLECTIONS_SEARCH = 6
  fromEnum SERVER_SIDE_TOOL_MCP = 7
  fromEnum SERVER_SIDE_TOOL_ATTACHMENT_SEARCH = 8
  fromEnum SERVER_SIDE_TOOL_IMAGE_SEARCH = 10
  fromEnum
    (ServerSideTool'Unrecognized (ServerSideTool'UnrecognizedValue k))
    = Prelude.fromIntegral k
  succ SERVER_SIDE_TOOL_IMAGE_SEARCH
    = Prelude.error
        "ServerSideTool.succ: bad argument SERVER_SIDE_TOOL_IMAGE_SEARCH. This value would be out of bounds."
  succ SERVER_SIDE_TOOL_INVALID = SERVER_SIDE_TOOL_WEB_SEARCH
  succ SERVER_SIDE_TOOL_WEB_SEARCH = SERVER_SIDE_TOOL_X_SEARCH
  succ SERVER_SIDE_TOOL_X_SEARCH = SERVER_SIDE_TOOL_CODE_EXECUTION
  succ SERVER_SIDE_TOOL_CODE_EXECUTION = SERVER_SIDE_TOOL_VIEW_IMAGE
  succ SERVER_SIDE_TOOL_VIEW_IMAGE = SERVER_SIDE_TOOL_VIEW_X_VIDEO
  succ SERVER_SIDE_TOOL_VIEW_X_VIDEO
    = SERVER_SIDE_TOOL_COLLECTIONS_SEARCH
  succ SERVER_SIDE_TOOL_COLLECTIONS_SEARCH = SERVER_SIDE_TOOL_MCP
  succ SERVER_SIDE_TOOL_MCP = SERVER_SIDE_TOOL_ATTACHMENT_SEARCH
  succ SERVER_SIDE_TOOL_ATTACHMENT_SEARCH
    = SERVER_SIDE_TOOL_IMAGE_SEARCH
  succ (ServerSideTool'Unrecognized _)
    = Prelude.error
        "ServerSideTool.succ: bad argument: unrecognized value"
  pred SERVER_SIDE_TOOL_INVALID
    = Prelude.error
        "ServerSideTool.pred: bad argument SERVER_SIDE_TOOL_INVALID. This value would be out of bounds."
  pred SERVER_SIDE_TOOL_WEB_SEARCH = SERVER_SIDE_TOOL_INVALID
  pred SERVER_SIDE_TOOL_X_SEARCH = SERVER_SIDE_TOOL_WEB_SEARCH
  pred SERVER_SIDE_TOOL_CODE_EXECUTION = SERVER_SIDE_TOOL_X_SEARCH
  pred SERVER_SIDE_TOOL_VIEW_IMAGE = SERVER_SIDE_TOOL_CODE_EXECUTION
  pred SERVER_SIDE_TOOL_VIEW_X_VIDEO = SERVER_SIDE_TOOL_VIEW_IMAGE
  pred SERVER_SIDE_TOOL_COLLECTIONS_SEARCH
    = SERVER_SIDE_TOOL_VIEW_X_VIDEO
  pred SERVER_SIDE_TOOL_MCP = SERVER_SIDE_TOOL_COLLECTIONS_SEARCH
  pred SERVER_SIDE_TOOL_ATTACHMENT_SEARCH = SERVER_SIDE_TOOL_MCP
  pred SERVER_SIDE_TOOL_IMAGE_SEARCH
    = SERVER_SIDE_TOOL_ATTACHMENT_SEARCH
  pred (ServerSideTool'Unrecognized _)
    = Prelude.error
        "ServerSideTool.pred: bad argument: unrecognized value"
  enumFrom = Data.ProtoLens.Message.Enum.messageEnumFrom
  enumFromTo = Data.ProtoLens.Message.Enum.messageEnumFromTo
  enumFromThen = Data.ProtoLens.Message.Enum.messageEnumFromThen
  enumFromThenTo = Data.ProtoLens.Message.Enum.messageEnumFromThenTo
instance Data.ProtoLens.FieldDefault ServerSideTool where
  fieldDefault = SERVER_SIDE_TOOL_INVALID
instance Control.DeepSeq.NFData ServerSideTool where
  rnf x__ = Prelude.seq x__ ()
packedFileDescriptor :: Data.ByteString.ByteString
packedFileDescriptor
  = "\n\
    \\SYNxai/api/v1/usage.proto\DC2\axai_api\"\134\EOT\n\
    \\rSamplingUsage\DC2+\n\
    \\DC1completion_tokens\CAN\SOH \SOH(\ENQR\DLEcompletionTokens\DC2)\n\
    \\DLEreasoning_tokens\CAN\ACK \SOH(\ENQR\SIreasoningTokens\DC2#\n\
    \\rprompt_tokens\CAN\STX \SOH(\ENQR\fpromptTokens\DC2!\n\
    \\ftotal_tokens\CAN\ETX \SOH(\ENQR\vtotalTokens\DC2,\n\
    \\DC2prompt_text_tokens\CAN\EOT \SOH(\ENQR\DLEpromptTextTokens\DC29\n\
    \\EMcached_prompt_text_tokens\CAN\a \SOH(\ENQR\SYNcachedPromptTextTokens\DC2.\n\
    \\DC3prompt_image_tokens\CAN\ENQ \SOH(\ENQR\DC1promptImageTokens\DC2(\n\
    \\DLEnum_sources_used\CAN\b \SOH(\ENQR\SOnumSourcesUsed\DC2L\n\
    \\SYNserver_side_tools_used\CAN\t \ETX(\SO2\ETB.xai_api.ServerSideToolR\DC3serverSideToolsUsed\DC2.\n\
    \\DC1cost_in_usd_ticks\CAN\v \SOH(\ETXH\NULR\SOcostInUsdTicks\136\SOH\SOHB\DC4\n\
    \\DC2_cost_in_usd_ticks\"r\n\
    \\SOEmbeddingUsage\DC2.\n\
    \\DC3num_text_embeddings\CAN\SOH \SOH(\ENQR\DC1numTextEmbeddings\DC20\n\
    \\DC4num_image_embeddings\CAN\STX \SOH(\ENQR\DC2numImageEmbeddings*\229\STX\n\
    \\SOServerSideTool\DC2\FS\n\
    \\CANSERVER_SIDE_TOOL_INVALID\DLE\NUL\DC2\US\n\
    \\ESCSERVER_SIDE_TOOL_WEB_SEARCH\DLE\SOH\DC2\GS\n\
    \\EMSERVER_SIDE_TOOL_X_SEARCH\DLE\STX\DC2#\n\
    \\USSERVER_SIDE_TOOL_CODE_EXECUTION\DLE\ETX\DC2\US\n\
    \\ESCSERVER_SIDE_TOOL_VIEW_IMAGE\DLE\EOT\DC2!\n\
    \\GSSERVER_SIDE_TOOL_VIEW_X_VIDEO\DLE\ENQ\DC2'\n\
    \#SERVER_SIDE_TOOL_COLLECTIONS_SEARCH\DLE\ACK\DC2\CAN\n\
    \\DC4SERVER_SIDE_TOOL_MCP\DLE\a\DC2&\n\
    \\"SERVER_SIDE_TOOL_ATTACHMENT_SEARCH\DLE\b\DC2!\n\
    \\GSSERVER_SIDE_TOOL_IMAGE_SEARCH\DLE\n\
    \J\236\DC3\n\
    \\ACK\DC2\EOT\NUL\NULC\SOH\n\
    \\b\n\
    \\SOH\f\DC2\ETX\NUL\NUL\DC2\n\
    \\b\n\
    \\SOH\STX\DC2\ETX\STX\NUL\DLE\n\
    \d\n\
    \\STX\EOT\NUL\DC2\EOT\ACK\NUL-\SOH\SUBX Records the cost associated with a sampling request (both chat and sample\n\
    \ endpoints).\n\
    \\n\
    \\n\
    \\n\
    \\ETX\EOT\NUL\SOH\DC2\ETX\ACK\b\NAK\n\
    \e\n\
    \\EOT\EOT\NUL\STX\NUL\DC2\ETX\t\STX\RS\SUBX Total number of text completion tokens generated across all choices\n\
    \ (in case of n>1).\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\ENQ\DC2\ETX\t\STX\a\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\SOH\DC2\ETX\t\b\EM\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\ETX\DC2\ETX\t\FS\GS\n\
    \M\n\
    \\EOT\EOT\NUL\STX\SOH\DC2\ETX\f\STX\GS\SUB@ Total number of reasoning tokens generated across all choices.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\SOH\ENQ\DC2\ETX\f\STX\a\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\SOH\SOH\DC2\ETX\f\b\CAN\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\SOH\ETX\DC2\ETX\f\ESC\FS\n\
    \D\n\
    \\EOT\EOT\NUL\STX\STX\DC2\ETX\SI\STX\SUB\SUB7 Total number of prompt tokens (both text and images).\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\STX\ENQ\DC2\ETX\SI\STX\a\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\STX\SOH\DC2\ETX\SI\b\NAK\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\STX\ETX\DC2\ETX\SI\CAN\EM\n\
    \<\n\
    \\EOT\EOT\NUL\STX\ETX\DC2\ETX\DC2\STX\EM\SUB/ Total number of tokens (prompt + completion).\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ETX\ENQ\DC2\ETX\DC2\STX\a\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ETX\SOH\DC2\ETX\DC2\b\DC4\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ETX\ETX\DC2\ETX\DC2\ETB\CAN\n\
    \D\n\
    \\EOT\EOT\NUL\STX\EOT\DC2\ETX\NAK\STX\US\SUB7 Total number of (uncached) text tokens in the prompt.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\EOT\ENQ\DC2\ETX\NAK\STX\a\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\EOT\SOH\DC2\ETX\NAK\b\SUB\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\EOT\ETX\DC2\ETX\NAK\GS\RS\n\
    \@\n\
    \\EOT\EOT\NUL\STX\ENQ\DC2\ETX\CAN\STX&\SUB3 Total number of cached text tokens in the prompt.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ENQ\ENQ\DC2\ETX\CAN\STX\a\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ENQ\SOH\DC2\ETX\CAN\b!\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ENQ\ETX\DC2\ETX\CAN$%\n\
    \:\n\
    \\EOT\EOT\NUL\STX\ACK\DC2\ETX\ESC\STX \SUB- Total number of image tokens in the prompt.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ACK\ENQ\DC2\ETX\ESC\STX\a\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ACK\SOH\DC2\ETX\ESC\b\ESC\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ACK\ETX\DC2\ETX\ESC\RS\US\n\
    \\218\STX\n\
    \\EOT\EOT\NUL\STX\a\DC2\ETX\"\STX\GS\SUB\204\STX [DEPRECATED - live search feature has been deprecated so this field is\n\
    \ redundant] Number of individual live search sources used. Only applicable\n\
    \ when live search is enabled. e.g. If a live search query returns citations\n\
    \ from both X and Web and news sources, this will be 3. If it returns\n\
    \ citations from only X, this will be 1.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\a\ENQ\DC2\ETX\"\STX\a\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\a\SOH\DC2\ETX\"\b\CAN\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\a\ETX\DC2\ETX\"\ESC\FS\n\
    \0\n\
    \\EOT\EOT\NUL\STX\b\DC2\ETX%\STX5\SUB# List of server side tools called.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\b\EOT\DC2\ETX%\STX\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\b\ACK\DC2\ETX%\v\EM\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\b\SOH\DC2\ETX%\SUB0\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\b\ETX\DC2\ETX%34\n\
    \\191\STX\n\
    \\EOT\EOT\NUL\STX\t\DC2\ETX,\STX(\SUB\177\STX Full price paid by the user for this request, in USD ticks.\n\
    \ For requests with server-side tools, this is the sum of token cost and\n\
    \ server-side tool cost. Also used for image gen, video gen, etc.\n\
    \ 1 USD = 10,000,000,000 ticks (i.e. 1 tick = 1e-10 USD).\n\
    \ To convert to dollars, divide by 10,000,000,000.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\t\EOT\DC2\ETX,\STX\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\t\ENQ\DC2\ETX,\v\DLE\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\t\SOH\DC2\ETX,\DC1\"\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\t\ETX\DC2\ETX,%'\n\
    \(\n\
    \\STX\EOT\SOH\DC2\EOT0\NUL6\SOH\SUB\FS Usage of embedding models.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\EOT\SOH\SOH\DC2\ETX0\b\SYN\n\
    \G\n\
    \\EOT\EOT\SOH\STX\NUL\DC2\ETX2\STX \SUB: The number of feature vectors produced from text inputs.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\ENQ\DC2\ETX2\STX\a\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\SOH\DC2\ETX2\b\ESC\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\ETX\DC2\ETX2\RS\US\n\
    \H\n\
    \\EOT\EOT\SOH\STX\SOH\DC2\ETX5\STX!\SUB; The number of feature vectors produced from image inputs.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\SOH\ENQ\DC2\ETX5\STX\a\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\SOH\SOH\DC2\ETX5\b\FS\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\SOH\ETX\DC2\ETX5\US \n\
    \\n\
    \\n\
    \\STX\ENQ\NUL\DC2\EOT8\NULC\SOH\n\
    \\n\
    \\n\
    \\ETX\ENQ\NUL\SOH\DC2\ETX8\ENQ\DC3\n\
    \\v\n\
    \\EOT\ENQ\NUL\STX\NUL\DC2\ETX9\STX\US\n\
    \\f\n\
    \\ENQ\ENQ\NUL\STX\NUL\SOH\DC2\ETX9\STX\SUB\n\
    \\f\n\
    \\ENQ\ENQ\NUL\STX\NUL\STX\DC2\ETX9\GS\RS\n\
    \\v\n\
    \\EOT\ENQ\NUL\STX\SOH\DC2\ETX:\STX\"\n\
    \\f\n\
    \\ENQ\ENQ\NUL\STX\SOH\SOH\DC2\ETX:\STX\GS\n\
    \\f\n\
    \\ENQ\ENQ\NUL\STX\SOH\STX\DC2\ETX: !\n\
    \\v\n\
    \\EOT\ENQ\NUL\STX\STX\DC2\ETX;\STX \n\
    \\f\n\
    \\ENQ\ENQ\NUL\STX\STX\SOH\DC2\ETX;\STX\ESC\n\
    \\f\n\
    \\ENQ\ENQ\NUL\STX\STX\STX\DC2\ETX;\RS\US\n\
    \\v\n\
    \\EOT\ENQ\NUL\STX\ETX\DC2\ETX<\STX&\n\
    \\f\n\
    \\ENQ\ENQ\NUL\STX\ETX\SOH\DC2\ETX<\STX!\n\
    \\f\n\
    \\ENQ\ENQ\NUL\STX\ETX\STX\DC2\ETX<$%\n\
    \\v\n\
    \\EOT\ENQ\NUL\STX\EOT\DC2\ETX=\STX\"\n\
    \\f\n\
    \\ENQ\ENQ\NUL\STX\EOT\SOH\DC2\ETX=\STX\GS\n\
    \\f\n\
    \\ENQ\ENQ\NUL\STX\EOT\STX\DC2\ETX= !\n\
    \\v\n\
    \\EOT\ENQ\NUL\STX\ENQ\DC2\ETX>\STX$\n\
    \\f\n\
    \\ENQ\ENQ\NUL\STX\ENQ\SOH\DC2\ETX>\STX\US\n\
    \\f\n\
    \\ENQ\ENQ\NUL\STX\ENQ\STX\DC2\ETX>\"#\n\
    \\v\n\
    \\EOT\ENQ\NUL\STX\ACK\DC2\ETX?\STX*\n\
    \\f\n\
    \\ENQ\ENQ\NUL\STX\ACK\SOH\DC2\ETX?\STX%\n\
    \\f\n\
    \\ENQ\ENQ\NUL\STX\ACK\STX\DC2\ETX?()\n\
    \\v\n\
    \\EOT\ENQ\NUL\STX\a\DC2\ETX@\STX\ESC\n\
    \\f\n\
    \\ENQ\ENQ\NUL\STX\a\SOH\DC2\ETX@\STX\SYN\n\
    \\f\n\
    \\ENQ\ENQ\NUL\STX\a\STX\DC2\ETX@\EM\SUB\n\
    \\v\n\
    \\EOT\ENQ\NUL\STX\b\DC2\ETXA\STX)\n\
    \\f\n\
    \\ENQ\ENQ\NUL\STX\b\SOH\DC2\ETXA\STX$\n\
    \\f\n\
    \\ENQ\ENQ\NUL\STX\b\STX\DC2\ETXA'(\n\
    \\v\n\
    \\EOT\ENQ\NUL\STX\t\DC2\ETXB\STX%\n\
    \\f\n\
    \\ENQ\ENQ\NUL\STX\t\SOH\DC2\ETXB\STX\US\n\
    \\f\n\
    \\ENQ\ENQ\NUL\STX\t\STX\DC2\ETXB\"$b\ACKproto3"