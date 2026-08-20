{- This file was auto-generated from xai/api/v1/sample.proto by the proto-lens-protoc program. -}
{-# LANGUAGE ScopedTypeVariables, DataKinds, TypeFamilies, UndecidableInstances, GeneralizedNewtypeDeriving, MultiParamTypeClasses, FlexibleContexts, FlexibleInstances, PatternSynonyms, MagicHash, NoImplicitPrelude, DataKinds, BangPatterns, TypeApplications, OverloadedStrings, DerivingStrategies#-}
{-# OPTIONS_GHC -Wno-unused-imports#-}
{-# OPTIONS_GHC -Wno-duplicate-exports#-}
{-# OPTIONS_GHC -Wno-dodgy-exports#-}
module Proto.Xai.Api.V1.Sample (
        Sample(..), FinishReason(..), FinishReason(),
        FinishReason'UnrecognizedValue, SampleChoice(),
        SampleTextRequest(), SampleTextResponse()
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
import qualified Proto.Xai.Api.V1.Usage
newtype FinishReason'UnrecognizedValue
  = FinishReason'UnrecognizedValue Data.Int.Int32
  deriving stock (Prelude.Eq, Prelude.Ord, Prelude.Show)
data FinishReason
  = REASON_INVALID |
    REASON_MAX_LEN |
    REASON_MAX_CONTEXT |
    REASON_STOP |
    REASON_TOOL_CALLS |
    REASON_TIME_LIMIT |
    FinishReason'Unrecognized !FinishReason'UnrecognizedValue
  deriving stock (Prelude.Show, Prelude.Eq, Prelude.Ord)
instance Data.ProtoLens.MessageEnum FinishReason where
  maybeToEnum 0 = Prelude.Just REASON_INVALID
  maybeToEnum 1 = Prelude.Just REASON_MAX_LEN
  maybeToEnum 2 = Prelude.Just REASON_MAX_CONTEXT
  maybeToEnum 3 = Prelude.Just REASON_STOP
  maybeToEnum 4 = Prelude.Just REASON_TOOL_CALLS
  maybeToEnum 5 = Prelude.Just REASON_TIME_LIMIT
  maybeToEnum k
    = Prelude.Just
        (FinishReason'Unrecognized
           (FinishReason'UnrecognizedValue (Prelude.fromIntegral k)))
  showEnum REASON_INVALID = "REASON_INVALID"
  showEnum REASON_MAX_LEN = "REASON_MAX_LEN"
  showEnum REASON_MAX_CONTEXT = "REASON_MAX_CONTEXT"
  showEnum REASON_STOP = "REASON_STOP"
  showEnum REASON_TOOL_CALLS = "REASON_TOOL_CALLS"
  showEnum REASON_TIME_LIMIT = "REASON_TIME_LIMIT"
  showEnum
    (FinishReason'Unrecognized (FinishReason'UnrecognizedValue k))
    = Prelude.show k
  readEnum k
    | (Prelude.==) k "REASON_INVALID" = Prelude.Just REASON_INVALID
    | (Prelude.==) k "REASON_MAX_LEN" = Prelude.Just REASON_MAX_LEN
    | (Prelude.==) k "REASON_MAX_CONTEXT"
    = Prelude.Just REASON_MAX_CONTEXT
    | (Prelude.==) k "REASON_STOP" = Prelude.Just REASON_STOP
    | (Prelude.==) k "REASON_TOOL_CALLS"
    = Prelude.Just REASON_TOOL_CALLS
    | (Prelude.==) k "REASON_TIME_LIMIT"
    = Prelude.Just REASON_TIME_LIMIT
    | Prelude.otherwise
    = (Prelude.>>=) (Text.Read.readMaybe k) Data.ProtoLens.maybeToEnum
instance Prelude.Bounded FinishReason where
  minBound = REASON_INVALID
  maxBound = REASON_TIME_LIMIT
instance Prelude.Enum FinishReason where
  toEnum k__
    = Prelude.maybe
        (Prelude.error
           ((Prelude.++)
              "toEnum: unknown value for enum FinishReason: "
              (Prelude.show k__)))
        Prelude.id (Data.ProtoLens.maybeToEnum k__)
  fromEnum REASON_INVALID = 0
  fromEnum REASON_MAX_LEN = 1
  fromEnum REASON_MAX_CONTEXT = 2
  fromEnum REASON_STOP = 3
  fromEnum REASON_TOOL_CALLS = 4
  fromEnum REASON_TIME_LIMIT = 5
  fromEnum
    (FinishReason'Unrecognized (FinishReason'UnrecognizedValue k))
    = Prelude.fromIntegral k
  succ REASON_TIME_LIMIT
    = Prelude.error
        "FinishReason.succ: bad argument REASON_TIME_LIMIT. This value would be out of bounds."
  succ REASON_INVALID = REASON_MAX_LEN
  succ REASON_MAX_LEN = REASON_MAX_CONTEXT
  succ REASON_MAX_CONTEXT = REASON_STOP
  succ REASON_STOP = REASON_TOOL_CALLS
  succ REASON_TOOL_CALLS = REASON_TIME_LIMIT
  succ (FinishReason'Unrecognized _)
    = Prelude.error
        "FinishReason.succ: bad argument: unrecognized value"
  pred REASON_INVALID
    = Prelude.error
        "FinishReason.pred: bad argument REASON_INVALID. This value would be out of bounds."
  pred REASON_MAX_LEN = REASON_INVALID
  pred REASON_MAX_CONTEXT = REASON_MAX_LEN
  pred REASON_STOP = REASON_MAX_CONTEXT
  pred REASON_TOOL_CALLS = REASON_STOP
  pred REASON_TIME_LIMIT = REASON_TOOL_CALLS
  pred (FinishReason'Unrecognized _)
    = Prelude.error
        "FinishReason.pred: bad argument: unrecognized value"
  enumFrom = Data.ProtoLens.Message.Enum.messageEnumFrom
  enumFromTo = Data.ProtoLens.Message.Enum.messageEnumFromTo
  enumFromThen = Data.ProtoLens.Message.Enum.messageEnumFromThen
  enumFromThenTo = Data.ProtoLens.Message.Enum.messageEnumFromThenTo
instance Data.ProtoLens.FieldDefault FinishReason where
  fieldDefault = REASON_INVALID
instance Control.DeepSeq.NFData FinishReason where
  rnf x__ = Prelude.seq x__ ()
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Sample_Fields.finishReason' @:: Lens' SampleChoice FinishReason@
         * 'Proto.Xai.Api.V1.Sample_Fields.index' @:: Lens' SampleChoice Data.Int.Int32@
         * 'Proto.Xai.Api.V1.Sample_Fields.text' @:: Lens' SampleChoice Data.Text.Text@ -}
data SampleChoice
  = SampleChoice'_constructor {_SampleChoice'finishReason :: !FinishReason,
                               _SampleChoice'index :: !Data.Int.Int32,
                               _SampleChoice'text :: !Data.Text.Text,
                               _SampleChoice'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show SampleChoice where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField SampleChoice "finishReason" FinishReason where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SampleChoice'finishReason
           (\ x__ y__ -> x__ {_SampleChoice'finishReason = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SampleChoice "index" Data.Int.Int32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SampleChoice'index (\ x__ y__ -> x__ {_SampleChoice'index = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SampleChoice "text" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SampleChoice'text (\ x__ y__ -> x__ {_SampleChoice'text = y__}))
        Prelude.id
instance Data.ProtoLens.Message SampleChoice where
  messageName _ = Data.Text.pack "xai_api.SampleChoice"
  packedMessageDescriptor _
    = "\n\
      \\fSampleChoice\DC2:\n\
      \\rfinish_reason\CAN\SOH \SOH(\SO2\NAK.xai_api.FinishReasonR\ffinishReason\DC2\DC4\n\
      \\ENQindex\CAN\STX \SOH(\ENQR\ENQindex\DC2\DC2\n\
      \\EOTtext\CAN\ETX \SOH(\tR\EOTtext"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        finishReason__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "finish_reason"
              (Data.ProtoLens.ScalarField Data.ProtoLens.EnumField ::
                 Data.ProtoLens.FieldTypeDescriptor FinishReason)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"finishReason")) ::
              Data.ProtoLens.FieldDescriptor SampleChoice
        index__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "index"
              (Data.ProtoLens.ScalarField Data.ProtoLens.Int32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Int.Int32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"index")) ::
              Data.ProtoLens.FieldDescriptor SampleChoice
        text__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "text"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"text")) ::
              Data.ProtoLens.FieldDescriptor SampleChoice
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, finishReason__field_descriptor),
           (Data.ProtoLens.Tag 2, index__field_descriptor),
           (Data.ProtoLens.Tag 3, text__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _SampleChoice'_unknownFields
        (\ x__ y__ -> x__ {_SampleChoice'_unknownFields = y__})
  defMessage
    = SampleChoice'_constructor
        {_SampleChoice'finishReason = Data.ProtoLens.fieldDefault,
         _SampleChoice'index = Data.ProtoLens.fieldDefault,
         _SampleChoice'text = Data.ProtoLens.fieldDefault,
         _SampleChoice'_unknownFields = []}
  parseMessage
    = let
        loop ::
          SampleChoice -> Data.ProtoLens.Encoding.Bytes.Parser SampleChoice
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
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "text"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"text") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "SampleChoice"
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
                   (let _v = Lens.Family2.view (Data.ProtoLens.Field.field @"text") _x
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
                   (Data.ProtoLens.Encoding.Wire.buildFieldSet
                      (Lens.Family2.view Data.ProtoLens.unknownFields _x))))
instance Control.DeepSeq.NFData SampleChoice where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_SampleChoice'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_SampleChoice'finishReason x__)
                (Control.DeepSeq.deepseq
                   (_SampleChoice'index x__)
                   (Control.DeepSeq.deepseq (_SampleChoice'text x__) ())))
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Sample_Fields.prompt' @:: Lens' SampleTextRequest [Data.Text.Text]@
         * 'Proto.Xai.Api.V1.Sample_Fields.vec'prompt' @:: Lens' SampleTextRequest (Data.Vector.Vector Data.Text.Text)@
         * 'Proto.Xai.Api.V1.Sample_Fields.model' @:: Lens' SampleTextRequest Data.Text.Text@
         * 'Proto.Xai.Api.V1.Sample_Fields.n' @:: Lens' SampleTextRequest Data.Int.Int32@
         * 'Proto.Xai.Api.V1.Sample_Fields.maybe'n' @:: Lens' SampleTextRequest (Prelude.Maybe Data.Int.Int32)@
         * 'Proto.Xai.Api.V1.Sample_Fields.maxTokens' @:: Lens' SampleTextRequest Data.Int.Int32@
         * 'Proto.Xai.Api.V1.Sample_Fields.maybe'maxTokens' @:: Lens' SampleTextRequest (Prelude.Maybe Data.Int.Int32)@
         * 'Proto.Xai.Api.V1.Sample_Fields.seed' @:: Lens' SampleTextRequest Data.Int.Int32@
         * 'Proto.Xai.Api.V1.Sample_Fields.maybe'seed' @:: Lens' SampleTextRequest (Prelude.Maybe Data.Int.Int32)@
         * 'Proto.Xai.Api.V1.Sample_Fields.stop' @:: Lens' SampleTextRequest [Data.Text.Text]@
         * 'Proto.Xai.Api.V1.Sample_Fields.vec'stop' @:: Lens' SampleTextRequest (Data.Vector.Vector Data.Text.Text)@
         * 'Proto.Xai.Api.V1.Sample_Fields.temperature' @:: Lens' SampleTextRequest Prelude.Float@
         * 'Proto.Xai.Api.V1.Sample_Fields.maybe'temperature' @:: Lens' SampleTextRequest (Prelude.Maybe Prelude.Float)@
         * 'Proto.Xai.Api.V1.Sample_Fields.topP' @:: Lens' SampleTextRequest Prelude.Float@
         * 'Proto.Xai.Api.V1.Sample_Fields.maybe'topP' @:: Lens' SampleTextRequest (Prelude.Maybe Prelude.Float)@
         * 'Proto.Xai.Api.V1.Sample_Fields.frequencyPenalty' @:: Lens' SampleTextRequest Prelude.Float@
         * 'Proto.Xai.Api.V1.Sample_Fields.maybe'frequencyPenalty' @:: Lens' SampleTextRequest (Prelude.Maybe Prelude.Float)@
         * 'Proto.Xai.Api.V1.Sample_Fields.logprobs' @:: Lens' SampleTextRequest Prelude.Bool@
         * 'Proto.Xai.Api.V1.Sample_Fields.presencePenalty' @:: Lens' SampleTextRequest Prelude.Float@
         * 'Proto.Xai.Api.V1.Sample_Fields.maybe'presencePenalty' @:: Lens' SampleTextRequest (Prelude.Maybe Prelude.Float)@
         * 'Proto.Xai.Api.V1.Sample_Fields.topLogprobs' @:: Lens' SampleTextRequest Data.Int.Int32@
         * 'Proto.Xai.Api.V1.Sample_Fields.maybe'topLogprobs' @:: Lens' SampleTextRequest (Prelude.Maybe Data.Int.Int32)@
         * 'Proto.Xai.Api.V1.Sample_Fields.user' @:: Lens' SampleTextRequest Data.Text.Text@ -}
data SampleTextRequest
  = SampleTextRequest'_constructor {_SampleTextRequest'prompt :: !(Data.Vector.Vector Data.Text.Text),
                                    _SampleTextRequest'model :: !Data.Text.Text,
                                    _SampleTextRequest'n :: !(Prelude.Maybe Data.Int.Int32),
                                    _SampleTextRequest'maxTokens :: !(Prelude.Maybe Data.Int.Int32),
                                    _SampleTextRequest'seed :: !(Prelude.Maybe Data.Int.Int32),
                                    _SampleTextRequest'stop :: !(Data.Vector.Vector Data.Text.Text),
                                    _SampleTextRequest'temperature :: !(Prelude.Maybe Prelude.Float),
                                    _SampleTextRequest'topP :: !(Prelude.Maybe Prelude.Float),
                                    _SampleTextRequest'frequencyPenalty :: !(Prelude.Maybe Prelude.Float),
                                    _SampleTextRequest'logprobs :: !Prelude.Bool,
                                    _SampleTextRequest'presencePenalty :: !(Prelude.Maybe Prelude.Float),
                                    _SampleTextRequest'topLogprobs :: !(Prelude.Maybe Data.Int.Int32),
                                    _SampleTextRequest'user :: !Data.Text.Text,
                                    _SampleTextRequest'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show SampleTextRequest where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField SampleTextRequest "prompt" [Data.Text.Text] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SampleTextRequest'prompt
           (\ x__ y__ -> x__ {_SampleTextRequest'prompt = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField SampleTextRequest "vec'prompt" (Data.Vector.Vector Data.Text.Text) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SampleTextRequest'prompt
           (\ x__ y__ -> x__ {_SampleTextRequest'prompt = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SampleTextRequest "model" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SampleTextRequest'model
           (\ x__ y__ -> x__ {_SampleTextRequest'model = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SampleTextRequest "n" Data.Int.Int32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SampleTextRequest'n
           (\ x__ y__ -> x__ {_SampleTextRequest'n = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField SampleTextRequest "maybe'n" (Prelude.Maybe Data.Int.Int32) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SampleTextRequest'n
           (\ x__ y__ -> x__ {_SampleTextRequest'n = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SampleTextRequest "maxTokens" Data.Int.Int32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SampleTextRequest'maxTokens
           (\ x__ y__ -> x__ {_SampleTextRequest'maxTokens = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField SampleTextRequest "maybe'maxTokens" (Prelude.Maybe Data.Int.Int32) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SampleTextRequest'maxTokens
           (\ x__ y__ -> x__ {_SampleTextRequest'maxTokens = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SampleTextRequest "seed" Data.Int.Int32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SampleTextRequest'seed
           (\ x__ y__ -> x__ {_SampleTextRequest'seed = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField SampleTextRequest "maybe'seed" (Prelude.Maybe Data.Int.Int32) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SampleTextRequest'seed
           (\ x__ y__ -> x__ {_SampleTextRequest'seed = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SampleTextRequest "stop" [Data.Text.Text] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SampleTextRequest'stop
           (\ x__ y__ -> x__ {_SampleTextRequest'stop = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField SampleTextRequest "vec'stop" (Data.Vector.Vector Data.Text.Text) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SampleTextRequest'stop
           (\ x__ y__ -> x__ {_SampleTextRequest'stop = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SampleTextRequest "temperature" Prelude.Float where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SampleTextRequest'temperature
           (\ x__ y__ -> x__ {_SampleTextRequest'temperature = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField SampleTextRequest "maybe'temperature" (Prelude.Maybe Prelude.Float) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SampleTextRequest'temperature
           (\ x__ y__ -> x__ {_SampleTextRequest'temperature = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SampleTextRequest "topP" Prelude.Float where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SampleTextRequest'topP
           (\ x__ y__ -> x__ {_SampleTextRequest'topP = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField SampleTextRequest "maybe'topP" (Prelude.Maybe Prelude.Float) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SampleTextRequest'topP
           (\ x__ y__ -> x__ {_SampleTextRequest'topP = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SampleTextRequest "frequencyPenalty" Prelude.Float where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SampleTextRequest'frequencyPenalty
           (\ x__ y__ -> x__ {_SampleTextRequest'frequencyPenalty = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField SampleTextRequest "maybe'frequencyPenalty" (Prelude.Maybe Prelude.Float) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SampleTextRequest'frequencyPenalty
           (\ x__ y__ -> x__ {_SampleTextRequest'frequencyPenalty = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SampleTextRequest "logprobs" Prelude.Bool where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SampleTextRequest'logprobs
           (\ x__ y__ -> x__ {_SampleTextRequest'logprobs = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SampleTextRequest "presencePenalty" Prelude.Float where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SampleTextRequest'presencePenalty
           (\ x__ y__ -> x__ {_SampleTextRequest'presencePenalty = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField SampleTextRequest "maybe'presencePenalty" (Prelude.Maybe Prelude.Float) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SampleTextRequest'presencePenalty
           (\ x__ y__ -> x__ {_SampleTextRequest'presencePenalty = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SampleTextRequest "topLogprobs" Data.Int.Int32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SampleTextRequest'topLogprobs
           (\ x__ y__ -> x__ {_SampleTextRequest'topLogprobs = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField SampleTextRequest "maybe'topLogprobs" (Prelude.Maybe Data.Int.Int32) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SampleTextRequest'topLogprobs
           (\ x__ y__ -> x__ {_SampleTextRequest'topLogprobs = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SampleTextRequest "user" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SampleTextRequest'user
           (\ x__ y__ -> x__ {_SampleTextRequest'user = y__}))
        Prelude.id
instance Data.ProtoLens.Message SampleTextRequest where
  messageName _ = Data.Text.pack "xai_api.SampleTextRequest"
  packedMessageDescriptor _
    = "\n\
      \\DC1SampleTextRequest\DC2\SYN\n\
      \\ACKprompt\CAN\SOH \ETX(\tR\ACKprompt\DC2\DC4\n\
      \\ENQmodel\CAN\ETX \SOH(\tR\ENQmodel\DC2\DC1\n\
      \\SOHn\CAN\b \SOH(\ENQH\NULR\SOHn\136\SOH\SOH\DC2\"\n\
      \\n\
      \max_tokens\CAN\a \SOH(\ENQH\SOHR\tmaxTokens\136\SOH\SOH\DC2\ETB\n\
      \\EOTseed\CAN\v \SOH(\ENQH\STXR\EOTseed\136\SOH\SOH\DC2\DC2\n\
      \\EOTstop\CAN\f \ETX(\tR\EOTstop\DC2%\n\
      \\vtemperature\CAN\SO \SOH(\STXH\ETXR\vtemperature\136\SOH\SOH\DC2\CAN\n\
      \\ENQtop_p\CAN\SI \SOH(\STXH\EOTR\EOTtopP\136\SOH\SOH\DC20\n\
      \\DC1frequency_penalty\CAN\r \SOH(\STXH\ENQR\DLEfrequencyPenalty\136\SOH\SOH\DC2\SUB\n\
      \\blogprobs\CAN\ENQ \SOH(\bR\blogprobs\DC2.\n\
      \\DLEpresence_penalty\CAN\t \SOH(\STXH\ACKR\SIpresencePenalty\136\SOH\SOH\DC2&\n\
      \\ftop_logprobs\CAN\ACK \SOH(\ENQH\aR\vtopLogprobs\136\SOH\SOH\DC2\DC2\n\
      \\EOTuser\CAN\DC1 \SOH(\tR\EOTuserB\EOT\n\
      \\STX_nB\r\n\
      \\v_max_tokensB\a\n\
      \\ENQ_seedB\SO\n\
      \\f_temperatureB\b\n\
      \\ACK_top_pB\DC4\n\
      \\DC2_frequency_penaltyB\DC3\n\
      \\DC1_presence_penaltyB\SI\n\
      \\r_top_logprobsJ\EOT\b\STX\DLE\ETXJ\EOT\b\EOT\DLE\ENQJ\EOT\b\DLE\DLE\DC1J\EOT\b\DC2\DLE\DC3"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        prompt__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "prompt"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Unpacked (Data.ProtoLens.Field.field @"prompt")) ::
              Data.ProtoLens.FieldDescriptor SampleTextRequest
        model__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "model"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"model")) ::
              Data.ProtoLens.FieldDescriptor SampleTextRequest
        n__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "n"
              (Data.ProtoLens.ScalarField Data.ProtoLens.Int32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Int.Int32)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'n")) ::
              Data.ProtoLens.FieldDescriptor SampleTextRequest
        maxTokens__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "max_tokens"
              (Data.ProtoLens.ScalarField Data.ProtoLens.Int32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Int.Int32)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'maxTokens")) ::
              Data.ProtoLens.FieldDescriptor SampleTextRequest
        seed__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "seed"
              (Data.ProtoLens.ScalarField Data.ProtoLens.Int32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Int.Int32)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'seed")) ::
              Data.ProtoLens.FieldDescriptor SampleTextRequest
        stop__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "stop"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Unpacked (Data.ProtoLens.Field.field @"stop")) ::
              Data.ProtoLens.FieldDescriptor SampleTextRequest
        temperature__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "temperature"
              (Data.ProtoLens.ScalarField Data.ProtoLens.FloatField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Float)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'temperature")) ::
              Data.ProtoLens.FieldDescriptor SampleTextRequest
        topP__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "top_p"
              (Data.ProtoLens.ScalarField Data.ProtoLens.FloatField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Float)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'topP")) ::
              Data.ProtoLens.FieldDescriptor SampleTextRequest
        frequencyPenalty__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "frequency_penalty"
              (Data.ProtoLens.ScalarField Data.ProtoLens.FloatField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Float)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'frequencyPenalty")) ::
              Data.ProtoLens.FieldDescriptor SampleTextRequest
        logprobs__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "logprobs"
              (Data.ProtoLens.ScalarField Data.ProtoLens.BoolField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Bool)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"logprobs")) ::
              Data.ProtoLens.FieldDescriptor SampleTextRequest
        presencePenalty__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "presence_penalty"
              (Data.ProtoLens.ScalarField Data.ProtoLens.FloatField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Float)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'presencePenalty")) ::
              Data.ProtoLens.FieldDescriptor SampleTextRequest
        topLogprobs__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "top_logprobs"
              (Data.ProtoLens.ScalarField Data.ProtoLens.Int32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Int.Int32)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'topLogprobs")) ::
              Data.ProtoLens.FieldDescriptor SampleTextRequest
        user__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "user"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"user")) ::
              Data.ProtoLens.FieldDescriptor SampleTextRequest
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, prompt__field_descriptor),
           (Data.ProtoLens.Tag 3, model__field_descriptor),
           (Data.ProtoLens.Tag 8, n__field_descriptor),
           (Data.ProtoLens.Tag 7, maxTokens__field_descriptor),
           (Data.ProtoLens.Tag 11, seed__field_descriptor),
           (Data.ProtoLens.Tag 12, stop__field_descriptor),
           (Data.ProtoLens.Tag 14, temperature__field_descriptor),
           (Data.ProtoLens.Tag 15, topP__field_descriptor),
           (Data.ProtoLens.Tag 13, frequencyPenalty__field_descriptor),
           (Data.ProtoLens.Tag 5, logprobs__field_descriptor),
           (Data.ProtoLens.Tag 9, presencePenalty__field_descriptor),
           (Data.ProtoLens.Tag 6, topLogprobs__field_descriptor),
           (Data.ProtoLens.Tag 17, user__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _SampleTextRequest'_unknownFields
        (\ x__ y__ -> x__ {_SampleTextRequest'_unknownFields = y__})
  defMessage
    = SampleTextRequest'_constructor
        {_SampleTextRequest'prompt = Data.Vector.Generic.empty,
         _SampleTextRequest'model = Data.ProtoLens.fieldDefault,
         _SampleTextRequest'n = Prelude.Nothing,
         _SampleTextRequest'maxTokens = Prelude.Nothing,
         _SampleTextRequest'seed = Prelude.Nothing,
         _SampleTextRequest'stop = Data.Vector.Generic.empty,
         _SampleTextRequest'temperature = Prelude.Nothing,
         _SampleTextRequest'topP = Prelude.Nothing,
         _SampleTextRequest'frequencyPenalty = Prelude.Nothing,
         _SampleTextRequest'logprobs = Data.ProtoLens.fieldDefault,
         _SampleTextRequest'presencePenalty = Prelude.Nothing,
         _SampleTextRequest'topLogprobs = Prelude.Nothing,
         _SampleTextRequest'user = Data.ProtoLens.fieldDefault,
         _SampleTextRequest'_unknownFields = []}
  parseMessage
    = let
        loop ::
          SampleTextRequest
          -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Vector Data.ProtoLens.Encoding.Growing.RealWorld Data.Text.Text
             -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Vector Data.ProtoLens.Encoding.Growing.RealWorld Data.Text.Text
                -> Data.ProtoLens.Encoding.Bytes.Parser SampleTextRequest
        loop x mutable'prompt mutable'stop
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do frozen'prompt <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                         (Data.ProtoLens.Encoding.Growing.unsafeFreeze
                                            mutable'prompt)
                      frozen'stop <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.unsafeFreeze mutable'stop)
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
                              (Data.ProtoLens.Field.field @"vec'prompt") frozen'prompt
                              (Lens.Family2.set
                                 (Data.ProtoLens.Field.field @"vec'stop") frozen'stop x)))
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                            Data.ProtoLens.Encoding.Bytes.getText
                                              (Prelude.fromIntegral len))
                                        "prompt"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append mutable'prompt y)
                                loop x v mutable'stop
                        26
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "model"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"model") y x)
                                  mutable'prompt mutable'stop
                        64
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "n"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"n") y x)
                                  mutable'prompt mutable'stop
                        56
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "max_tokens"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"maxTokens") y x)
                                  mutable'prompt mutable'stop
                        88
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "seed"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"seed") y x)
                                  mutable'prompt mutable'stop
                        98
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                            Data.ProtoLens.Encoding.Bytes.getText
                                              (Prelude.fromIntegral len))
                                        "stop"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append mutable'stop y)
                                loop x mutable'prompt v
                        117
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Data.ProtoLens.Encoding.Bytes.wordToFloat
                                          Data.ProtoLens.Encoding.Bytes.getFixed32)
                                       "temperature"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"temperature") y x)
                                  mutable'prompt mutable'stop
                        125
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Data.ProtoLens.Encoding.Bytes.wordToFloat
                                          Data.ProtoLens.Encoding.Bytes.getFixed32)
                                       "top_p"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"topP") y x)
                                  mutable'prompt mutable'stop
                        109
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Data.ProtoLens.Encoding.Bytes.wordToFloat
                                          Data.ProtoLens.Encoding.Bytes.getFixed32)
                                       "frequency_penalty"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"frequencyPenalty") y x)
                                  mutable'prompt mutable'stop
                        40
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          ((Prelude./=) 0) Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "logprobs"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"logprobs") y x)
                                  mutable'prompt mutable'stop
                        77
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Data.ProtoLens.Encoding.Bytes.wordToFloat
                                          Data.ProtoLens.Encoding.Bytes.getFixed32)
                                       "presence_penalty"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"presencePenalty") y x)
                                  mutable'prompt mutable'stop
                        48
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "top_logprobs"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"topLogprobs") y x)
                                  mutable'prompt mutable'stop
                        138
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "user"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"user") y x)
                                  mutable'prompt mutable'stop
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
                                  mutable'prompt mutable'stop
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do mutable'prompt <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                  Data.ProtoLens.Encoding.Growing.new
              mutable'stop <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                Data.ProtoLens.Encoding.Growing.new
              loop Data.ProtoLens.defMessage mutable'prompt mutable'stop)
          "SampleTextRequest"
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
                (Lens.Family2.view (Data.ProtoLens.Field.field @"vec'prompt") _x))
             ((Data.Monoid.<>)
                (let
                   _v = Lens.Family2.view (Data.ProtoLens.Field.field @"model") _x
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
                                   Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral _v))
                      ((Data.Monoid.<>)
                         (case
                              Lens.Family2.view (Data.ProtoLens.Field.field @"maybe'seed") _x
                          of
                            Prelude.Nothing -> Data.Monoid.mempty
                            (Prelude.Just _v)
                              -> (Data.Monoid.<>)
                                   (Data.ProtoLens.Encoding.Bytes.putVarInt 88)
                                   ((Prelude..)
                                      Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral
                                      _v))
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
                                     (case
                                          Lens.Family2.view
                                            (Data.ProtoLens.Field.field @"maybe'frequencyPenalty")
                                            _x
                                      of
                                        Prelude.Nothing -> Data.Monoid.mempty
                                        (Prelude.Just _v)
                                          -> (Data.Monoid.<>)
                                               (Data.ProtoLens.Encoding.Bytes.putVarInt 109)
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
                                                  (Data.ProtoLens.Field.field
                                                     @"maybe'presencePenalty")
                                                  _x
                                            of
                                              Prelude.Nothing -> Data.Monoid.mempty
                                              (Prelude.Just _v)
                                                -> (Data.Monoid.<>)
                                                     (Data.ProtoLens.Encoding.Bytes.putVarInt 77)
                                                     ((Prelude..)
                                                        Data.ProtoLens.Encoding.Bytes.putFixed32
                                                        Data.ProtoLens.Encoding.Bytes.floatToWord
                                                        _v))
                                           ((Data.Monoid.<>)
                                              (case
                                                   Lens.Family2.view
                                                     (Data.ProtoLens.Field.field
                                                        @"maybe'topLogprobs")
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
                                                 (let
                                                    _v
                                                      = Lens.Family2.view
                                                          (Data.ProtoLens.Field.field @"user") _x
                                                  in
                                                    if (Prelude.==)
                                                         _v Data.ProtoLens.fieldDefault then
                                                        Data.Monoid.mempty
                                                    else
                                                        (Data.Monoid.<>)
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
                                                             Data.Text.Encoding.encodeUtf8 _v))
                                                 (Data.ProtoLens.Encoding.Wire.buildFieldSet
                                                    (Lens.Family2.view
                                                       Data.ProtoLens.unknownFields _x))))))))))))))
instance Control.DeepSeq.NFData SampleTextRequest where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_SampleTextRequest'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_SampleTextRequest'prompt x__)
                (Control.DeepSeq.deepseq
                   (_SampleTextRequest'model x__)
                   (Control.DeepSeq.deepseq
                      (_SampleTextRequest'n x__)
                      (Control.DeepSeq.deepseq
                         (_SampleTextRequest'maxTokens x__)
                         (Control.DeepSeq.deepseq
                            (_SampleTextRequest'seed x__)
                            (Control.DeepSeq.deepseq
                               (_SampleTextRequest'stop x__)
                               (Control.DeepSeq.deepseq
                                  (_SampleTextRequest'temperature x__)
                                  (Control.DeepSeq.deepseq
                                     (_SampleTextRequest'topP x__)
                                     (Control.DeepSeq.deepseq
                                        (_SampleTextRequest'frequencyPenalty x__)
                                        (Control.DeepSeq.deepseq
                                           (_SampleTextRequest'logprobs x__)
                                           (Control.DeepSeq.deepseq
                                              (_SampleTextRequest'presencePenalty x__)
                                              (Control.DeepSeq.deepseq
                                                 (_SampleTextRequest'topLogprobs x__)
                                                 (Control.DeepSeq.deepseq
                                                    (_SampleTextRequest'user x__) ())))))))))))))
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Sample_Fields.id' @:: Lens' SampleTextResponse Data.Text.Text@
         * 'Proto.Xai.Api.V1.Sample_Fields.choices' @:: Lens' SampleTextResponse [SampleChoice]@
         * 'Proto.Xai.Api.V1.Sample_Fields.vec'choices' @:: Lens' SampleTextResponse (Data.Vector.Vector SampleChoice)@
         * 'Proto.Xai.Api.V1.Sample_Fields.created' @:: Lens' SampleTextResponse Proto.Google.Protobuf.Timestamp.Timestamp@
         * 'Proto.Xai.Api.V1.Sample_Fields.maybe'created' @:: Lens' SampleTextResponse (Prelude.Maybe Proto.Google.Protobuf.Timestamp.Timestamp)@
         * 'Proto.Xai.Api.V1.Sample_Fields.model' @:: Lens' SampleTextResponse Data.Text.Text@
         * 'Proto.Xai.Api.V1.Sample_Fields.systemFingerprint' @:: Lens' SampleTextResponse Data.Text.Text@
         * 'Proto.Xai.Api.V1.Sample_Fields.usage' @:: Lens' SampleTextResponse Proto.Xai.Api.V1.Usage.SamplingUsage@
         * 'Proto.Xai.Api.V1.Sample_Fields.maybe'usage' @:: Lens' SampleTextResponse (Prelude.Maybe Proto.Xai.Api.V1.Usage.SamplingUsage)@ -}
data SampleTextResponse
  = SampleTextResponse'_constructor {_SampleTextResponse'id :: !Data.Text.Text,
                                     _SampleTextResponse'choices :: !(Data.Vector.Vector SampleChoice),
                                     _SampleTextResponse'created :: !(Prelude.Maybe Proto.Google.Protobuf.Timestamp.Timestamp),
                                     _SampleTextResponse'model :: !Data.Text.Text,
                                     _SampleTextResponse'systemFingerprint :: !Data.Text.Text,
                                     _SampleTextResponse'usage :: !(Prelude.Maybe Proto.Xai.Api.V1.Usage.SamplingUsage),
                                     _SampleTextResponse'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show SampleTextResponse where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField SampleTextResponse "id" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SampleTextResponse'id
           (\ x__ y__ -> x__ {_SampleTextResponse'id = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SampleTextResponse "choices" [SampleChoice] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SampleTextResponse'choices
           (\ x__ y__ -> x__ {_SampleTextResponse'choices = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField SampleTextResponse "vec'choices" (Data.Vector.Vector SampleChoice) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SampleTextResponse'choices
           (\ x__ y__ -> x__ {_SampleTextResponse'choices = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SampleTextResponse "created" Proto.Google.Protobuf.Timestamp.Timestamp where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SampleTextResponse'created
           (\ x__ y__ -> x__ {_SampleTextResponse'created = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage)
instance Data.ProtoLens.Field.HasField SampleTextResponse "maybe'created" (Prelude.Maybe Proto.Google.Protobuf.Timestamp.Timestamp) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SampleTextResponse'created
           (\ x__ y__ -> x__ {_SampleTextResponse'created = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SampleTextResponse "model" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SampleTextResponse'model
           (\ x__ y__ -> x__ {_SampleTextResponse'model = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SampleTextResponse "systemFingerprint" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SampleTextResponse'systemFingerprint
           (\ x__ y__ -> x__ {_SampleTextResponse'systemFingerprint = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SampleTextResponse "usage" Proto.Xai.Api.V1.Usage.SamplingUsage where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SampleTextResponse'usage
           (\ x__ y__ -> x__ {_SampleTextResponse'usage = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage)
instance Data.ProtoLens.Field.HasField SampleTextResponse "maybe'usage" (Prelude.Maybe Proto.Xai.Api.V1.Usage.SamplingUsage) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SampleTextResponse'usage
           (\ x__ y__ -> x__ {_SampleTextResponse'usage = y__}))
        Prelude.id
instance Data.ProtoLens.Message SampleTextResponse where
  messageName _ = Data.Text.pack "xai_api.SampleTextResponse"
  packedMessageDescriptor _
    = "\n\
      \\DC2SampleTextResponse\DC2\SO\n\
      \\STXid\CAN\SOH \SOH(\tR\STXid\DC2/\n\
      \\achoices\CAN\STX \ETX(\v2\NAK.xai_api.SampleChoiceR\achoices\DC24\n\
      \\acreated\CAN\ENQ \SOH(\v2\SUB.google.protobuf.TimestampR\acreated\DC2\DC4\n\
      \\ENQmodel\CAN\ACK \SOH(\tR\ENQmodel\DC2-\n\
      \\DC2system_fingerprint\CAN\a \SOH(\tR\DC1systemFingerprint\DC2,\n\
      \\ENQusage\CAN\t \SOH(\v2\SYN.xai_api.SamplingUsageR\ENQusage"
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
              Data.ProtoLens.FieldDescriptor SampleTextResponse
        choices__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "choices"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor SampleChoice)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Unpacked (Data.ProtoLens.Field.field @"choices")) ::
              Data.ProtoLens.FieldDescriptor SampleTextResponse
        created__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "created"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor Proto.Google.Protobuf.Timestamp.Timestamp)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'created")) ::
              Data.ProtoLens.FieldDescriptor SampleTextResponse
        model__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "model"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"model")) ::
              Data.ProtoLens.FieldDescriptor SampleTextResponse
        systemFingerprint__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "system_fingerprint"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"systemFingerprint")) ::
              Data.ProtoLens.FieldDescriptor SampleTextResponse
        usage__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "usage"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor Proto.Xai.Api.V1.Usage.SamplingUsage)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'usage")) ::
              Data.ProtoLens.FieldDescriptor SampleTextResponse
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, id__field_descriptor),
           (Data.ProtoLens.Tag 2, choices__field_descriptor),
           (Data.ProtoLens.Tag 5, created__field_descriptor),
           (Data.ProtoLens.Tag 6, model__field_descriptor),
           (Data.ProtoLens.Tag 7, systemFingerprint__field_descriptor),
           (Data.ProtoLens.Tag 9, usage__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _SampleTextResponse'_unknownFields
        (\ x__ y__ -> x__ {_SampleTextResponse'_unknownFields = y__})
  defMessage
    = SampleTextResponse'_constructor
        {_SampleTextResponse'id = Data.ProtoLens.fieldDefault,
         _SampleTextResponse'choices = Data.Vector.Generic.empty,
         _SampleTextResponse'created = Prelude.Nothing,
         _SampleTextResponse'model = Data.ProtoLens.fieldDefault,
         _SampleTextResponse'systemFingerprint = Data.ProtoLens.fieldDefault,
         _SampleTextResponse'usage = Prelude.Nothing,
         _SampleTextResponse'_unknownFields = []}
  parseMessage
    = let
        loop ::
          SampleTextResponse
          -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Vector Data.ProtoLens.Encoding.Growing.RealWorld SampleChoice
             -> Data.ProtoLens.Encoding.Bytes.Parser SampleTextResponse
        loop x mutable'choices
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do frozen'choices <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                          (Data.ProtoLens.Encoding.Growing.unsafeFreeze
                                             mutable'choices)
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
                              (Data.ProtoLens.Field.field @"vec'choices") frozen'choices x))
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
                                  mutable'choices
                        18
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                            Data.ProtoLens.Encoding.Bytes.isolate
                                              (Prelude.fromIntegral len)
                                              Data.ProtoLens.parseMessage)
                                        "choices"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append mutable'choices y)
                                loop x v
                        42
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "created"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"created") y x)
                                  mutable'choices
                        50
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "model"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"model") y x)
                                  mutable'choices
                        58
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "system_fingerprint"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"systemFingerprint") y x)
                                  mutable'choices
                        74
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "usage"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"usage") y x)
                                  mutable'choices
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
                                  mutable'choices
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do mutable'choices <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                   Data.ProtoLens.Encoding.Growing.new
              loop Data.ProtoLens.defMessage mutable'choices)
          "SampleTextResponse"
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
                   (Lens.Family2.view (Data.ProtoLens.Field.field @"vec'choices") _x))
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
                            (Data.ProtoLens.Encoding.Wire.buildFieldSet
                               (Lens.Family2.view Data.ProtoLens.unknownFields _x)))))))
instance Control.DeepSeq.NFData SampleTextResponse where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_SampleTextResponse'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_SampleTextResponse'id x__)
                (Control.DeepSeq.deepseq
                   (_SampleTextResponse'choices x__)
                   (Control.DeepSeq.deepseq
                      (_SampleTextResponse'created x__)
                      (Control.DeepSeq.deepseq
                         (_SampleTextResponse'model x__)
                         (Control.DeepSeq.deepseq
                            (_SampleTextResponse'systemFingerprint x__)
                            (Control.DeepSeq.deepseq (_SampleTextResponse'usage x__) ()))))))
data Sample = Sample {}
instance Data.ProtoLens.Service.Types.Service Sample where
  type ServiceName Sample = "Sample"
  type ServicePackage Sample = "xai_api"
  type ServiceMethods Sample = '["sampleText", "sampleTextStreaming"]
  packedServiceDescriptor _
    = "\n\
      \\ACKSample\DC2G\n\
      \\n\
      \SampleText\DC2\SUB.xai_api.SampleTextRequest\SUB\ESC.xai_api.SampleTextResponse\"\NUL\DC2R\n\
      \\DC3SampleTextStreaming\DC2\SUB.xai_api.SampleTextRequest\SUB\ESC.xai_api.SampleTextResponse\"\NUL0\SOH"
instance Data.ProtoLens.Service.Types.HasMethodImpl Sample "sampleText" where
  type MethodName Sample "sampleText" = "SampleText"
  type MethodInput Sample "sampleText" = SampleTextRequest
  type MethodOutput Sample "sampleText" = SampleTextResponse
  type MethodStreamingType Sample "sampleText" = 'Data.ProtoLens.Service.Types.NonStreaming
instance Data.ProtoLens.Service.Types.HasMethodImpl Sample "sampleTextStreaming" where
  type MethodName Sample "sampleTextStreaming" = "SampleTextStreaming"
  type MethodInput Sample "sampleTextStreaming" = SampleTextRequest
  type MethodOutput Sample "sampleTextStreaming" = SampleTextResponse
  type MethodStreamingType Sample "sampleTextStreaming" = 'Data.ProtoLens.Service.Types.ServerStreaming
packedFileDescriptor :: Data.ByteString.ByteString
packedFileDescriptor
  = "\n\
    \\ETBxai/api/v1/sample.proto\DC2\axai_api\SUB\USgoogle/protobuf/timestamp.proto\SUB\SYNxai/api/v1/usage.proto\"\172\EOT\n\
    \\DC1SampleTextRequest\DC2\SYN\n\
    \\ACKprompt\CAN\SOH \ETX(\tR\ACKprompt\DC2\DC4\n\
    \\ENQmodel\CAN\ETX \SOH(\tR\ENQmodel\DC2\DC1\n\
    \\SOHn\CAN\b \SOH(\ENQH\NULR\SOHn\136\SOH\SOH\DC2\"\n\
    \\n\
    \max_tokens\CAN\a \SOH(\ENQH\SOHR\tmaxTokens\136\SOH\SOH\DC2\ETB\n\
    \\EOTseed\CAN\v \SOH(\ENQH\STXR\EOTseed\136\SOH\SOH\DC2\DC2\n\
    \\EOTstop\CAN\f \ETX(\tR\EOTstop\DC2%\n\
    \\vtemperature\CAN\SO \SOH(\STXH\ETXR\vtemperature\136\SOH\SOH\DC2\CAN\n\
    \\ENQtop_p\CAN\SI \SOH(\STXH\EOTR\EOTtopP\136\SOH\SOH\DC20\n\
    \\DC1frequency_penalty\CAN\r \SOH(\STXH\ENQR\DLEfrequencyPenalty\136\SOH\SOH\DC2\SUB\n\
    \\blogprobs\CAN\ENQ \SOH(\bR\blogprobs\DC2.\n\
    \\DLEpresence_penalty\CAN\t \SOH(\STXH\ACKR\SIpresencePenalty\136\SOH\SOH\DC2&\n\
    \\ftop_logprobs\CAN\ACK \SOH(\ENQH\aR\vtopLogprobs\136\SOH\SOH\DC2\DC2\n\
    \\EOTuser\CAN\DC1 \SOH(\tR\EOTuserB\EOT\n\
    \\STX_nB\r\n\
    \\v_max_tokensB\a\n\
    \\ENQ_seedB\SO\n\
    \\f_temperatureB\b\n\
    \\ACK_top_pB\DC4\n\
    \\DC2_frequency_penaltyB\DC3\n\
    \\DC1_presence_penaltyB\SI\n\
    \\r_top_logprobsJ\EOT\b\STX\DLE\ETXJ\EOT\b\EOT\DLE\ENQJ\EOT\b\DLE\DLE\DC1J\EOT\b\DC2\DLE\DC3\"\254\SOH\n\
    \\DC2SampleTextResponse\DC2\SO\n\
    \\STXid\CAN\SOH \SOH(\tR\STXid\DC2/\n\
    \\achoices\CAN\STX \ETX(\v2\NAK.xai_api.SampleChoiceR\achoices\DC24\n\
    \\acreated\CAN\ENQ \SOH(\v2\SUB.google.protobuf.TimestampR\acreated\DC2\DC4\n\
    \\ENQmodel\CAN\ACK \SOH(\tR\ENQmodel\DC2-\n\
    \\DC2system_fingerprint\CAN\a \SOH(\tR\DC1systemFingerprint\DC2,\n\
    \\ENQusage\CAN\t \SOH(\v2\SYN.xai_api.SamplingUsageR\ENQusage\"t\n\
    \\fSampleChoice\DC2:\n\
    \\rfinish_reason\CAN\SOH \SOH(\SO2\NAK.xai_api.FinishReasonR\ffinishReason\DC2\DC4\n\
    \\ENQindex\CAN\STX \SOH(\ENQR\ENQindex\DC2\DC2\n\
    \\EOTtext\CAN\ETX \SOH(\tR\EOTtext*\141\SOH\n\
    \\fFinishReason\DC2\DC2\n\
    \\SOREASON_INVALID\DLE\NUL\DC2\DC2\n\
    \\SOREASON_MAX_LEN\DLE\SOH\DC2\SYN\n\
    \\DC2REASON_MAX_CONTEXT\DLE\STX\DC2\SI\n\
    \\vREASON_STOP\DLE\ETX\DC2\NAK\n\
    \\DC1REASON_TOOL_CALLS\DLE\EOT\DC2\NAK\n\
    \\DC1REASON_TIME_LIMIT\DLE\ENQ2\165\SOH\n\
    \\ACKSample\DC2G\n\
    \\n\
    \SampleText\DC2\SUB.xai_api.SampleTextRequest\SUB\ESC.xai_api.SampleTextResponse\"\NUL\DC2R\n\
    \\DC3SampleTextStreaming\DC2\SUB.xai_api.SampleTextRequest\SUB\ESC.xai_api.SampleTextResponse\"\NUL0\SOHJ\207:\n\
    \\a\DC2\ENQ\NUL\NUL\163\SOH\SOH\n\
    \\b\n\
    \\SOH\f\DC2\ETX\NUL\NUL\DC2\n\
    \\b\n\
    \\SOH\STX\DC2\ETX\STX\NUL\DLE\n\
    \\t\n\
    \\STX\ETX\NUL\DC2\ETX\EOT\NUL)\n\
    \\t\n\
    \\STX\ETX\SOH\DC2\ETX\ENQ\NUL \n\
    \U\n\
    \\STX\ACK\NUL\DC2\EOT\b\NUL\SO\SOH\SUBI An API service for sampling the responses of available language models.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\ACK\NUL\SOH\DC2\ETX\b\b\SO\n\
    \J\n\
    \\EOT\ACK\NUL\STX\NUL\DC2\ETX\n\
    \\STXC\SUB= Get raw sampling of text response from the model inference.\n\
    \\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\NUL\SOH\DC2\ETX\n\
    \\ACK\DLE\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\NUL\STX\DC2\ETX\n\
    \\DC1\"\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\NUL\ETX\DC2\ETX\n\
    \-?\n\
    \T\n\
    \\EOT\ACK\NUL\STX\SOH\DC2\ETX\r\STXS\SUBG Get streaming raw sampling of text response from the model inference.\n\
    \\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\SOH\SOH\DC2\ETX\r\ACK\EM\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\SOH\STX\DC2\ETX\r\SUB+\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\SOH\ACK\DC2\ETX\r6<\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\SOH\ETX\DC2\ETX\r=O\n\
    \A\n\
    \\STX\EOT\NUL\DC2\EOT\DC1\NULf\SOH\SUB5 Request to get a text completion response sampling.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\EOT\NUL\SOH\DC2\ETX\DC1\b\EM\n\
    \\n\
    \\n\
    \\ETX\EOT\NUL\t\DC2\ETX\DC2\STX\CAN\n\
    \\v\n\
    \\EOT\EOT\NUL\t\NUL\DC2\ETX\DC2\v\f\n\
    \\f\n\
    \\ENQ\EOT\NUL\t\NUL\SOH\DC2\ETX\DC2\v\f\n\
    \\f\n\
    \\ENQ\EOT\NUL\t\NUL\STX\DC2\ETX\DC2\v\f\n\
    \\v\n\
    \\EOT\EOT\NUL\t\SOH\DC2\ETX\DC2\SO\SI\n\
    \\f\n\
    \\ENQ\EOT\NUL\t\SOH\SOH\DC2\ETX\DC2\SO\SI\n\
    \\f\n\
    \\ENQ\EOT\NUL\t\SOH\STX\DC2\ETX\DC2\SO\SI\n\
    \\v\n\
    \\EOT\EOT\NUL\t\STX\DC2\ETX\DC2\DC1\DC3\n\
    \\f\n\
    \\ENQ\EOT\NUL\t\STX\SOH\DC2\ETX\DC2\DC1\DC3\n\
    \\f\n\
    \\ENQ\EOT\NUL\t\STX\STX\DC2\ETX\DC2\DC1\DC3\n\
    \\v\n\
    \\EOT\EOT\NUL\t\ETX\DC2\ETX\DC2\NAK\ETB\n\
    \\f\n\
    \\ENQ\EOT\NUL\t\ETX\SOH\DC2\ETX\DC2\NAK\ETB\n\
    \\f\n\
    \\ENQ\EOT\NUL\t\ETX\STX\DC2\ETX\DC2\NAK\ETB\n\
    \)\n\
    \\EOT\EOT\NUL\STX\NUL\DC2\ETX\NAK\STX\GS\SUB\FS Text prompts to sample on.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\EOT\DC2\ETX\NAK\STX\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\ENQ\DC2\ETX\NAK\v\DC1\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\SOH\DC2\ETX\NAK\DC2\CAN\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\ETX\DC2\ETX\NAK\ESC\FS\n\
    \5\n\
    \\EOT\EOT\NUL\STX\SOH\DC2\ETX\CAN\STX\DC3\SUB( Name or alias of the model to be used.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\SOH\ENQ\DC2\ETX\CAN\STX\b\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\SOH\SOH\DC2\ETX\CAN\t\SO\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\SOH\ETX\DC2\ETX\CAN\DC1\DC2\n\
    \\230\SOH\n\
    \\EOT\EOT\NUL\STX\STX\DC2\ETX\GS\STX\ETB\SUB\216\SOH The number of completions to create concurrently. A single completion will\n\
    \ be generated if the parameter is unset. Each completion is charged at the\n\
    \ same rate. You can generate at most 128 concurrent completions.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\STX\EOT\DC2\ETX\GS\STX\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\STX\ENQ\DC2\ETX\GS\v\DLE\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\STX\SOH\DC2\ETX\GS\DC1\DC2\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\STX\ETX\DC2\ETX\GS\NAK\SYN\n\
    \\228\STX\n\
    \\EOT\EOT\NUL\STX\ETX\DC2\ETX&\STX \SUB\214\STX The maximum number of tokens to sample. If unset, the model samples until\n\
    \ one of the following stop-conditions is reached:\n\
    \ - The context length of the model is exceeded\n\
    \ - One of the `stop` sequences has been observed.\n\
    \\n\
    \ We recommend choosing a reasonable value to reduce the risk of accidental\n\
    \ long-generations that consume many tokens.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ETX\EOT\DC2\ETX&\STX\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ETX\ENQ\DC2\ETX&\v\DLE\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ETX\SOH\DC2\ETX&\DC1\ESC\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ETX\ETX\DC2\ETX&\RS\US\n\
    \\211\STX\n\
    \\EOT\EOT\NUL\STX\EOT\DC2\ETX-\STX\ESC\SUB\197\STX A random seed used to make the sampling process deterministic. This is\n\
    \ provided in a best-effort basis without guarantee that sampling is 100%\n\
    \ deterministic given a seed. This is primarily provided for short-lived\n\
    \ testing purposes. Given a fixed request and seed, the answers may change\n\
    \ over time as our systems evolve.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\EOT\EOT\DC2\ETX-\STX\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\EOT\ENQ\DC2\ETX-\v\DLE\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\EOT\SOH\DC2\ETX-\DC1\NAK\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\EOT\ETX\DC2\ETX-\CAN\SUB\n\
    \\169\ENQ\n\
    \\EOT\EOT\NUL\STX\ENQ\DC2\ETX:\STX\FS\SUB\155\ENQ String patterns that will cause the sampling procedure to stop prematurely\n\
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
    \\ENQ\EOT\NUL\STX\ENQ\EOT\DC2\ETX:\STX\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ENQ\ENQ\DC2\ETX:\v\DC1\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ENQ\SOH\DC2\ETX:\DC2\SYN\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ENQ\ETX\DC2\ETX:\EM\ESC\n\
    \\239\ETX\n\
    \\EOT\EOT\NUL\STX\ACK\DC2\ETXC\STX\"\SUB\225\ETX A number between 0 and 2 used to control the variance of completions.\n\
    \ The smaller the value, the more deterministic the model will become. For\n\
    \ example, if we sample 1000 answers to the same prompt at a temperature of\n\
    \ 0.001, then most of the 1000 answers will be identical. Conversely, if we\n\
    \ conduct the same experiment at a temperature of 2, virtually no two answers\n\
    \ will be identical. Note that increasing the temperature will cause\n\
    \ the model to hallucinate more strongly.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ACK\EOT\DC2\ETXC\STX\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ACK\ENQ\DC2\ETXC\v\DLE\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ACK\SOH\DC2\ETXC\DC1\FS\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ACK\ETX\DC2\ETXC\US!\n\
    \\132\ENQ\n\
    \\EOT\EOT\NUL\STX\a\DC2\ETXN\STX\FS\SUB\246\EOT A number between 0 and 1 controlling the likelihood of the model to use\n\
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
    \\ENQ\EOT\NUL\STX\a\EOT\DC2\ETXN\STX\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\a\ENQ\DC2\ETXN\v\DLE\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\a\SOH\DC2\ETXN\DC1\SYN\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\a\ETX\DC2\ETXN\EM\ESC\n\
    \\204\SOH\n\
    \\EOT\EOT\NUL\STX\b\DC2\ETXS\STX(\SUB\190\SOH Number between -2.0 and 2.0.\n\
    \ Positive values penalize new tokens based on their existing frequency in the text so far,\n\
    \ decreasing the model's likelihood to repeat the same line verbatim.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\b\EOT\DC2\ETXS\STX\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\b\ENQ\DC2\ETXS\v\DLE\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\b\SOH\DC2\ETXS\DC1\"\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\b\ETX\DC2\ETXS%'\n\
    \\177\SOH\n\
    \\EOT\EOT\NUL\STX\t\DC2\ETXW\STX\DC4\SUB\163\SOH Whether to return log probabilities of the output tokens or not.\n\
    \ If true, returns the log probabilities of each output token returned in the content of message.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\t\ENQ\DC2\ETXW\STX\ACK\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\t\SOH\DC2\ETXW\a\SI\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\t\ETX\DC2\ETXW\DC2\DC3\n\
    \\222\SOH\n\
    \\EOT\EOT\NUL\STX\n\
    \\DC2\ETX[\STX&\SUB\208\SOH Number between -2.0 and 2.0. Positive values penalize new tokens based on whether they appear in the text so far, increasing the model's likelihood to talk about new topics.\n\
    \ Not supported by grok-3 models.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\n\
    \\EOT\DC2\ETX[\STX\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\n\
    \\ENQ\DC2\ETX[\v\DLE\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\n\
    \\SOH\DC2\ETX[\DC1!\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\n\
    \\ETX\DC2\ETX[$%\n\
    \\219\SOH\n\
    \\EOT\EOT\NUL\STX\v\DC2\ETX`\STX\"\SUB\205\SOH An integer between 0 and 8 specifying the number of most likely tokens to return at each token position,\n\
    \ each with an associated log probability.\n\
    \ logprobs must be set to true if this parameter is used.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\v\EOT\DC2\ETX`\STX\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\v\ENQ\DC2\ETX`\v\DLE\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\v\SOH\DC2\ETX`\DC1\GS\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\v\ETX\DC2\ETX` !\n\
    \\205\SOH\n\
    \\EOT\EOT\NUL\STX\f\DC2\ETXe\STX\DC3\SUB\191\SOH An opaque string supplied by the API client (customer) to identify a user.\n\
    \ The string will be stored in the logs and can be used in customer service\n\
    \ requests to identify certain requests.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\f\ENQ\DC2\ETXe\STX\b\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\f\SOH\DC2\ETXe\t\r\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\f\ETX\DC2\ETXe\DLE\DC2\n\
    \?\n\
    \\STX\EOT\SOH\DC2\ENQi\NUL\129\SOH\SOH\SUB2 Response of a text completion response sampling.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\EOT\SOH\SOH\DC2\ETXi\b\SUB\n\
    \\158\SOH\n\
    \\EOT\EOT\SOH\STX\NUL\DC2\ETXl\STX\DLE\SUB\144\SOH The ID of this request. This ID will also show up on your billing records\n\
    \ and you can use it when contacting us regarding a specific request.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\ENQ\DC2\ETXl\STX\b\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\SOH\DC2\ETXl\t\v\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\ETX\DC2\ETXl\SO\SI\n\
    \\140\SOH\n\
    \\EOT\EOT\SOH\STX\SOH\DC2\ETXp\STX$\SUB\DEL Completions in response to the input messages. The number of completions is\n\
    \ controlled via the `n` parameter on the request.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\SOH\EOT\DC2\ETXp\STX\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\SOH\ACK\DC2\ETXp\v\ETB\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\SOH\SOH\DC2\ETXp\CAN\US\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\SOH\ETX\DC2\ETXp\"#\n\
    \\154\SOH\n\
    \\EOT\EOT\SOH\STX\STX\DC2\ETXt\STX(\SUB\140\SOH A UNIX timestamp (UTC) indicating when the response object was created.\n\
    \ The timestamp is taken when the model starts generating response.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\STX\ACK\DC2\ETXt\STX\ESC\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\STX\SOH\DC2\ETXt\FS#\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\STX\ETX\DC2\ETXt&'\n\
    \\234\SOH\n\
    \\EOT\EOT\SOH\STX\ETX\DC2\ETXz\STX\DC3\SUB\220\SOH The name of the model used for the request. This model name contains\n\
    \ the actual model name used rather than any aliases.\n\
    \ This means the this can be `grok-2-1212` even when the request was\n\
    \ specifying `grok-2-latest`.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\ETX\ENQ\DC2\ETXz\STX\b\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\ETX\SOH\DC2\ETXz\t\SO\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\ETX\ETX\DC2\ETXz\DC1\DC2\n\
    \F\n\
    \\EOT\EOT\SOH\STX\EOT\DC2\ETX}\STX \SUB9 Note supported yet. Included for compatibility reasons.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\EOT\ENQ\DC2\ETX}\STX\b\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\EOT\SOH\DC2\ETX}\t\ESC\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\EOT\ETX\DC2\ETX}\RS\US\n\
    \>\n\
    \\EOT\EOT\SOH\STX\ENQ\DC2\EOT\128\SOH\STX\SUB\SUB0 The number of tokens consumed by this request.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\SOH\STX\ENQ\ACK\DC2\EOT\128\SOH\STX\SI\n\
    \\r\n\
    \\ENQ\EOT\SOH\STX\ENQ\SOH\DC2\EOT\128\SOH\DLE\NAK\n\
    \\r\n\
    \\ENQ\EOT\SOH\STX\ENQ\ETX\DC2\EOT\128\SOH\CAN\EM\n\
    \=\n\
    \\STX\EOT\STX\DC2\ACK\132\SOH\NUL\142\SOH\SOH\SUB/ Contains the response generated by the model.\n\
    \\n\
    \\v\n\
    \\ETX\EOT\STX\SOH\DC2\EOT\132\SOH\b\DC4\n\
    \:\n\
    \\EOT\EOT\STX\STX\NUL\DC2\EOT\134\SOH\STX!\SUB, Indicating why the model stopped sampling.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\STX\STX\NUL\ACK\DC2\EOT\134\SOH\STX\SO\n\
    \\r\n\
    \\ENQ\EOT\STX\STX\NUL\SOH\DC2\EOT\134\SOH\SI\FS\n\
    \\r\n\
    \\ENQ\EOT\STX\STX\NUL\ETX\DC2\EOT\134\SOH\US \n\
    \\158\SOH\n\
    \\EOT\EOT\STX\STX\SOH\DC2\EOT\138\SOH\STX\DC2\SUB\143\SOH The index of this choice in the list of choices. If you set `n > 1` on\n\
    \ your request, you will receive more than one choice in your response.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\STX\STX\SOH\ENQ\DC2\EOT\138\SOH\STX\a\n\
    \\r\n\
    \\ENQ\EOT\STX\STX\SOH\SOH\DC2\EOT\138\SOH\b\r\n\
    \\r\n\
    \\ENQ\EOT\STX\STX\SOH\ETX\DC2\EOT\138\SOH\DLE\DC1\n\
    \7\n\
    \\EOT\EOT\STX\STX\STX\DC2\EOT\141\SOH\STX\DC2\SUB) The actual text generated by the model.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\STX\STX\STX\ENQ\DC2\EOT\141\SOH\STX\b\n\
    \\r\n\
    \\ENQ\EOT\STX\STX\STX\SOH\DC2\EOT\141\SOH\t\r\n\
    \\r\n\
    \\ENQ\EOT\STX\STX\STX\ETX\DC2\EOT\141\SOH\DLE\DC1\n\
    \7\n\
    \\STX\ENQ\NUL\DC2\ACK\145\SOH\NUL\163\SOH\SOH\SUB) Reasons why the model stopped sampling.\n\
    \\n\
    \\v\n\
    \\ETX\ENQ\NUL\SOH\DC2\EOT\145\SOH\ENQ\DC1\n\
    \\US\n\
    \\EOT\ENQ\NUL\STX\NUL\DC2\EOT\147\SOH\STX\NAK\SUB\DC1 Invalid reason.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\NUL\STX\NUL\SOH\DC2\EOT\147\SOH\STX\DLE\n\
    \\r\n\
    \\ENQ\ENQ\NUL\STX\NUL\STX\DC2\EOT\147\SOH\DC3\DC4\n\
    \H\n\
    \\EOT\ENQ\NUL\STX\SOH\DC2\EOT\150\SOH\STX\NAK\SUB: The max_len parameter specified on the input is reached.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\NUL\STX\SOH\SOH\DC2\EOT\150\SOH\STX\DLE\n\
    \\r\n\
    \\ENQ\ENQ\NUL\STX\SOH\STX\DC2\EOT\150\SOH\DC3\DC4\n\
    \C\n\
    \\EOT\ENQ\NUL\STX\STX\DC2\EOT\153\SOH\STX\EM\SUB5 The maximum context length of the model is reached.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\NUL\STX\STX\SOH\DC2\EOT\153\SOH\STX\DC4\n\
    \\r\n\
    \\ENQ\ENQ\NUL\STX\STX\STX\DC2\EOT\153\SOH\ETB\CAN\n\
    \0\n\
    \\EOT\ENQ\NUL\STX\ETX\DC2\EOT\156\SOH\STX\DC2\SUB\" One of the stop words was found.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\NUL\STX\ETX\SOH\DC2\EOT\156\SOH\STX\r\n\
    \\r\n\
    \\ENQ\ENQ\NUL\STX\ETX\STX\DC2\EOT\156\SOH\DLE\DC1\n\
    \8\n\
    \\EOT\ENQ\NUL\STX\EOT\DC2\EOT\159\SOH\STX\CAN\SUB* A tool call is included in the response.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\NUL\STX\EOT\SOH\DC2\EOT\159\SOH\STX\DC3\n\
    \\r\n\
    \\ENQ\ENQ\NUL\STX\EOT\STX\DC2\EOT\159\SOH\SYN\ETB\n\
    \,\n\
    \\EOT\ENQ\NUL\STX\ENQ\DC2\EOT\162\SOH\STX\CAN\SUB\RS Time limit has been reached.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\NUL\STX\ENQ\SOH\DC2\EOT\162\SOH\STX\DC3\n\
    \\r\n\
    \\ENQ\ENQ\NUL\STX\ENQ\STX\DC2\EOT\162\SOH\SYN\ETBb\ACKproto3"