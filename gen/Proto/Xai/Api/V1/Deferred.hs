{- This file was auto-generated from xai/api/v1/deferred.proto by the proto-lens-protoc program. -}
{-# LANGUAGE ScopedTypeVariables, DataKinds, TypeFamilies, UndecidableInstances, GeneralizedNewtypeDeriving, MultiParamTypeClasses, FlexibleContexts, FlexibleInstances, PatternSynonyms, MagicHash, NoImplicitPrelude, DataKinds, BangPatterns, TypeApplications, OverloadedStrings, DerivingStrategies#-}
{-# OPTIONS_GHC -Wno-unused-imports#-}
{-# OPTIONS_GHC -Wno-duplicate-exports#-}
{-# OPTIONS_GHC -Wno-dodgy-exports#-}
module Proto.Xai.Api.V1.Deferred (
        DeferredStatus(..), DeferredStatus(),
        DeferredStatus'UnrecognizedValue, GetDeferredRequest(),
        StartDeferredResponse()
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
newtype DeferredStatus'UnrecognizedValue
  = DeferredStatus'UnrecognizedValue Data.Int.Int32
  deriving stock (Prelude.Eq, Prelude.Ord, Prelude.Show)
data DeferredStatus
  = INVALID_DEFERRED_STATUS |
    DONE |
    EXPIRED |
    PENDING |
    FAILED |
    DeferredStatus'Unrecognized !DeferredStatus'UnrecognizedValue
  deriving stock (Prelude.Show, Prelude.Eq, Prelude.Ord)
instance Data.ProtoLens.MessageEnum DeferredStatus where
  maybeToEnum 0 = Prelude.Just INVALID_DEFERRED_STATUS
  maybeToEnum 1 = Prelude.Just DONE
  maybeToEnum 2 = Prelude.Just EXPIRED
  maybeToEnum 3 = Prelude.Just PENDING
  maybeToEnum 4 = Prelude.Just FAILED
  maybeToEnum k
    = Prelude.Just
        (DeferredStatus'Unrecognized
           (DeferredStatus'UnrecognizedValue (Prelude.fromIntegral k)))
  showEnum INVALID_DEFERRED_STATUS = "INVALID_DEFERRED_STATUS"
  showEnum DONE = "DONE"
  showEnum EXPIRED = "EXPIRED"
  showEnum PENDING = "PENDING"
  showEnum FAILED = "FAILED"
  showEnum
    (DeferredStatus'Unrecognized (DeferredStatus'UnrecognizedValue k))
    = Prelude.show k
  readEnum k
    | (Prelude.==) k "INVALID_DEFERRED_STATUS"
    = Prelude.Just INVALID_DEFERRED_STATUS
    | (Prelude.==) k "DONE" = Prelude.Just DONE
    | (Prelude.==) k "EXPIRED" = Prelude.Just EXPIRED
    | (Prelude.==) k "PENDING" = Prelude.Just PENDING
    | (Prelude.==) k "FAILED" = Prelude.Just FAILED
    | Prelude.otherwise
    = (Prelude.>>=) (Text.Read.readMaybe k) Data.ProtoLens.maybeToEnum
instance Prelude.Bounded DeferredStatus where
  minBound = INVALID_DEFERRED_STATUS
  maxBound = FAILED
instance Prelude.Enum DeferredStatus where
  toEnum k__
    = Prelude.maybe
        (Prelude.error
           ((Prelude.++)
              "toEnum: unknown value for enum DeferredStatus: "
              (Prelude.show k__)))
        Prelude.id (Data.ProtoLens.maybeToEnum k__)
  fromEnum INVALID_DEFERRED_STATUS = 0
  fromEnum DONE = 1
  fromEnum EXPIRED = 2
  fromEnum PENDING = 3
  fromEnum FAILED = 4
  fromEnum
    (DeferredStatus'Unrecognized (DeferredStatus'UnrecognizedValue k))
    = Prelude.fromIntegral k
  succ FAILED
    = Prelude.error
        "DeferredStatus.succ: bad argument FAILED. This value would be out of bounds."
  succ INVALID_DEFERRED_STATUS = DONE
  succ DONE = EXPIRED
  succ EXPIRED = PENDING
  succ PENDING = FAILED
  succ (DeferredStatus'Unrecognized _)
    = Prelude.error
        "DeferredStatus.succ: bad argument: unrecognized value"
  pred INVALID_DEFERRED_STATUS
    = Prelude.error
        "DeferredStatus.pred: bad argument INVALID_DEFERRED_STATUS. This value would be out of bounds."
  pred DONE = INVALID_DEFERRED_STATUS
  pred EXPIRED = DONE
  pred PENDING = EXPIRED
  pred FAILED = PENDING
  pred (DeferredStatus'Unrecognized _)
    = Prelude.error
        "DeferredStatus.pred: bad argument: unrecognized value"
  enumFrom = Data.ProtoLens.Message.Enum.messageEnumFrom
  enumFromTo = Data.ProtoLens.Message.Enum.messageEnumFromTo
  enumFromThen = Data.ProtoLens.Message.Enum.messageEnumFromThen
  enumFromThenTo = Data.ProtoLens.Message.Enum.messageEnumFromThenTo
instance Data.ProtoLens.FieldDefault DeferredStatus where
  fieldDefault = INVALID_DEFERRED_STATUS
instance Control.DeepSeq.NFData DeferredStatus where
  rnf x__ = Prelude.seq x__ ()
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Deferred_Fields.requestId' @:: Lens' GetDeferredRequest Data.Text.Text@ -}
data GetDeferredRequest
  = GetDeferredRequest'_constructor {_GetDeferredRequest'requestId :: !Data.Text.Text,
                                     _GetDeferredRequest'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show GetDeferredRequest where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField GetDeferredRequest "requestId" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GetDeferredRequest'requestId
           (\ x__ y__ -> x__ {_GetDeferredRequest'requestId = y__}))
        Prelude.id
instance Data.ProtoLens.Message GetDeferredRequest where
  messageName _ = Data.Text.pack "xai_api.GetDeferredRequest"
  packedMessageDescriptor _
    = "\n\
      \\DC2GetDeferredRequest\DC2\GS\n\
      \\n\
      \request_id\CAN\SOH \SOH(\tR\trequestId"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        requestId__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "request_id"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"requestId")) ::
              Data.ProtoLens.FieldDescriptor GetDeferredRequest
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, requestId__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _GetDeferredRequest'_unknownFields
        (\ x__ y__ -> x__ {_GetDeferredRequest'_unknownFields = y__})
  defMessage
    = GetDeferredRequest'_constructor
        {_GetDeferredRequest'requestId = Data.ProtoLens.fieldDefault,
         _GetDeferredRequest'_unknownFields = []}
  parseMessage
    = let
        loop ::
          GetDeferredRequest
          -> Data.ProtoLens.Encoding.Bytes.Parser GetDeferredRequest
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
                                       "request_id"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"requestId") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "GetDeferredRequest"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v = Lens.Family2.view (Data.ProtoLens.Field.field @"requestId") _x
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
instance Control.DeepSeq.NFData GetDeferredRequest where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_GetDeferredRequest'_unknownFields x__)
             (Control.DeepSeq.deepseq (_GetDeferredRequest'requestId x__) ())
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Deferred_Fields.requestId' @:: Lens' StartDeferredResponse Data.Text.Text@ -}
data StartDeferredResponse
  = StartDeferredResponse'_constructor {_StartDeferredResponse'requestId :: !Data.Text.Text,
                                        _StartDeferredResponse'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show StartDeferredResponse where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField StartDeferredResponse "requestId" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _StartDeferredResponse'requestId
           (\ x__ y__ -> x__ {_StartDeferredResponse'requestId = y__}))
        Prelude.id
instance Data.ProtoLens.Message StartDeferredResponse where
  messageName _ = Data.Text.pack "xai_api.StartDeferredResponse"
  packedMessageDescriptor _
    = "\n\
      \\NAKStartDeferredResponse\DC2\GS\n\
      \\n\
      \request_id\CAN\SOH \SOH(\tR\trequestId"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        requestId__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "request_id"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"requestId")) ::
              Data.ProtoLens.FieldDescriptor StartDeferredResponse
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, requestId__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _StartDeferredResponse'_unknownFields
        (\ x__ y__ -> x__ {_StartDeferredResponse'_unknownFields = y__})
  defMessage
    = StartDeferredResponse'_constructor
        {_StartDeferredResponse'requestId = Data.ProtoLens.fieldDefault,
         _StartDeferredResponse'_unknownFields = []}
  parseMessage
    = let
        loop ::
          StartDeferredResponse
          -> Data.ProtoLens.Encoding.Bytes.Parser StartDeferredResponse
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
                                       "request_id"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"requestId") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "StartDeferredResponse"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v = Lens.Family2.view (Data.ProtoLens.Field.field @"requestId") _x
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
instance Control.DeepSeq.NFData StartDeferredResponse where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_StartDeferredResponse'_unknownFields x__)
             (Control.DeepSeq.deepseq (_StartDeferredResponse'requestId x__) ())
packedFileDescriptor :: Data.ByteString.ByteString
packedFileDescriptor
  = "\n\
    \\EMxai/api/v1/deferred.proto\DC2\axai_api\"6\n\
    \\NAKStartDeferredResponse\DC2\GS\n\
    \\n\
    \request_id\CAN\SOH \SOH(\tR\trequestId\"3\n\
    \\DC2GetDeferredRequest\DC2\GS\n\
    \\n\
    \request_id\CAN\SOH \SOH(\tR\trequestId*]\n\
    \\SODeferredStatus\DC2\ESC\n\
    \\ETBINVALID_DEFERRED_STATUS\DLE\NUL\DC2\b\n\
    \\EOTDONE\DLE\SOH\DC2\v\n\
    \\aEXPIRED\DLE\STX\DC2\v\n\
    \\aPENDING\DLE\ETX\DC2\n\
    \\n\
    \\ACKFAILED\DLE\EOTJ\192\b\n\
    \\ACK\DC2\EOT\NUL\NUL$\SOH\n\
    \\b\n\
    \\SOH\f\DC2\ETX\NUL\NUL\DC2\n\
    \\b\n\
    \\SOH\STX\DC2\ETX\STX\NUL\DLE\n\
    \Y\n\
    \\STX\EOT\NUL\DC2\EOT\ENQ\NUL\t\SOH\SUBM The response from the service, when creating a deferred completion request.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\EOT\NUL\SOH\DC2\ETX\ENQ\b\GS\n\
    \a\n\
    \\EOT\EOT\NUL\STX\NUL\DC2\ETX\b\STX\CAN\SUBT The ID of this request. This ID can be used to retrieve completion results\n\
    \ later.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\ENQ\DC2\ETX\b\STX\b\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\SOH\DC2\ETX\b\t\DC3\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\ETX\DC2\ETX\b\SYN\ETB\n\
    \l\n\
    \\STX\EOT\SOH\DC2\EOT\r\NUL\DLE\SOH\SUB` Retrieve the deferred chat request's response with the `request_id` in\n\
    \ StartDeferredResponse.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\EOT\SOH\SOH\DC2\ETX\r\b\SUB\n\
    \-\n\
    \\EOT\EOT\SOH\STX\NUL\DC2\ETX\SI\STX\CAN\SUB  The ID of this request to get.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\ENQ\DC2\ETX\SI\STX\b\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\SOH\DC2\ETX\SI\t\DC3\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\ETX\DC2\ETX\SI\SYN\ETB\n\
    \4\n\
    \\STX\ENQ\NUL\DC2\EOT\DC3\NUL$\SOH\SUB( Status of deferred completion request.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\ENQ\NUL\SOH\DC2\ETX\DC3\ENQ\DC3\n\
    \\RS\n\
    \\EOT\ENQ\NUL\STX\NUL\DC2\ETX\NAK\STX\RS\SUB\DC1 Invalid status.\n\
    \\n\
    \\f\n\
    \\ENQ\ENQ\NUL\STX\NUL\SOH\DC2\ETX\NAK\STX\EM\n\
    \\f\n\
    \\ENQ\ENQ\NUL\STX\NUL\STX\DC2\ETX\NAK\FS\GS\n\
    \L\n\
    \\EOT\ENQ\NUL\STX\SOH\DC2\ETX\CAN\STX\v\SUB? The request has been processed and is available for download.\n\
    \\n\
    \\f\n\
    \\ENQ\ENQ\NUL\STX\SOH\SOH\DC2\ETX\CAN\STX\ACK\n\
    \\f\n\
    \\ENQ\ENQ\NUL\STX\SOH\STX\DC2\ETX\CAN\t\n\
    \\n\
    \h\n\
    \\EOT\ENQ\NUL\STX\STX\DC2\ETX\FS\STX\SO\SUB[ The request has been processed but the content has expired and is not\n\
    \ available anymore.\n\
    \\n\
    \\f\n\
    \\ENQ\ENQ\NUL\STX\STX\SOH\DC2\ETX\FS\STX\t\n\
    \\f\n\
    \\ENQ\ENQ\NUL\STX\STX\STX\DC2\ETX\FS\f\r\n\
    \4\n\
    \\EOT\ENQ\NUL\STX\ETX\DC2\ETX\US\STX\SO\SUB' The request is still being processed.\n\
    \\n\
    \\f\n\
    \\ENQ\ENQ\NUL\STX\ETX\SOH\DC2\ETX\US\STX\t\n\
    \\f\n\
    \\ENQ\ENQ\NUL\STX\ETX\STX\DC2\ETX\US\f\r\n\
    \\DEL\n\
    \\EOT\ENQ\NUL\STX\EOT\DC2\ETX#\STX\r\SUBr The request failed due to an internal service error.\n\
    \ The error message is in the `error` field of the response.\n\
    \\n\
    \\f\n\
    \\ENQ\ENQ\NUL\STX\EOT\SOH\DC2\ETX#\STX\b\n\
    \\f\n\
    \\ENQ\ENQ\NUL\STX\EOT\STX\DC2\ETX#\v\fb\ACKproto3"