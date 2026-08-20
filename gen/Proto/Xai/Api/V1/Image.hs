{- This file was auto-generated from xai/api/v1/image.proto by the proto-lens-protoc program. -}
{-# LANGUAGE ScopedTypeVariables, DataKinds, TypeFamilies, UndecidableInstances, GeneralizedNewtypeDeriving, MultiParamTypeClasses, FlexibleContexts, FlexibleInstances, PatternSynonyms, MagicHash, NoImplicitPrelude, DataKinds, BangPatterns, TypeApplications, OverloadedStrings, DerivingStrategies#-}
{-# OPTIONS_GHC -Wno-unused-imports#-}
{-# OPTIONS_GHC -Wno-duplicate-exports#-}
{-# OPTIONS_GHC -Wno-dodgy-exports#-}
module Proto.Xai.Api.V1.Image (
        Image(..), GenerateImageRequest(), GeneratedImage(),
        GeneratedImage'Image(..), _GeneratedImage'Base64,
        _GeneratedImage'Url, ImageAspectRatio(..), ImageAspectRatio(),
        ImageAspectRatio'UnrecognizedValue, ImageDetail(..), ImageDetail(),
        ImageDetail'UnrecognizedValue, ImageFormat(..), ImageFormat(),
        ImageFormat'UnrecognizedValue, ImageQuality(..), ImageQuality(),
        ImageQuality'UnrecognizedValue, ImageResolution(..),
        ImageResolution(), ImageResolution'UnrecognizedValue,
        ImageResponse(), ImageUrlContent()
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
import qualified Proto.Xai.Api.V1.Usage
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Image_Fields.prompt' @:: Lens' GenerateImageRequest Data.Text.Text@
         * 'Proto.Xai.Api.V1.Image_Fields.image' @:: Lens' GenerateImageRequest ImageUrlContent@
         * 'Proto.Xai.Api.V1.Image_Fields.maybe'image' @:: Lens' GenerateImageRequest (Prelude.Maybe ImageUrlContent)@
         * 'Proto.Xai.Api.V1.Image_Fields.model' @:: Lens' GenerateImageRequest Data.Text.Text@
         * 'Proto.Xai.Api.V1.Image_Fields.n' @:: Lens' GenerateImageRequest Data.Int.Int32@
         * 'Proto.Xai.Api.V1.Image_Fields.maybe'n' @:: Lens' GenerateImageRequest (Prelude.Maybe Data.Int.Int32)@
         * 'Proto.Xai.Api.V1.Image_Fields.user' @:: Lens' GenerateImageRequest Data.Text.Text@
         * 'Proto.Xai.Api.V1.Image_Fields.format' @:: Lens' GenerateImageRequest ImageFormat@
         * 'Proto.Xai.Api.V1.Image_Fields.aspectRatio' @:: Lens' GenerateImageRequest ImageAspectRatio@
         * 'Proto.Xai.Api.V1.Image_Fields.maybe'aspectRatio' @:: Lens' GenerateImageRequest (Prelude.Maybe ImageAspectRatio)@
         * 'Proto.Xai.Api.V1.Image_Fields.resolution' @:: Lens' GenerateImageRequest ImageResolution@
         * 'Proto.Xai.Api.V1.Image_Fields.maybe'resolution' @:: Lens' GenerateImageRequest (Prelude.Maybe ImageResolution)@
         * 'Proto.Xai.Api.V1.Image_Fields.images' @:: Lens' GenerateImageRequest [ImageUrlContent]@
         * 'Proto.Xai.Api.V1.Image_Fields.vec'images' @:: Lens' GenerateImageRequest (Data.Vector.Vector ImageUrlContent)@ -}
data GenerateImageRequest
  = GenerateImageRequest'_constructor {_GenerateImageRequest'prompt :: !Data.Text.Text,
                                       _GenerateImageRequest'image :: !(Prelude.Maybe ImageUrlContent),
                                       _GenerateImageRequest'model :: !Data.Text.Text,
                                       _GenerateImageRequest'n :: !(Prelude.Maybe Data.Int.Int32),
                                       _GenerateImageRequest'user :: !Data.Text.Text,
                                       _GenerateImageRequest'format :: !ImageFormat,
                                       _GenerateImageRequest'aspectRatio :: !(Prelude.Maybe ImageAspectRatio),
                                       _GenerateImageRequest'resolution :: !(Prelude.Maybe ImageResolution),
                                       _GenerateImageRequest'images :: !(Data.Vector.Vector ImageUrlContent),
                                       _GenerateImageRequest'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show GenerateImageRequest where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField GenerateImageRequest "prompt" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GenerateImageRequest'prompt
           (\ x__ y__ -> x__ {_GenerateImageRequest'prompt = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GenerateImageRequest "image" ImageUrlContent where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GenerateImageRequest'image
           (\ x__ y__ -> x__ {_GenerateImageRequest'image = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage)
instance Data.ProtoLens.Field.HasField GenerateImageRequest "maybe'image" (Prelude.Maybe ImageUrlContent) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GenerateImageRequest'image
           (\ x__ y__ -> x__ {_GenerateImageRequest'image = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GenerateImageRequest "model" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GenerateImageRequest'model
           (\ x__ y__ -> x__ {_GenerateImageRequest'model = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GenerateImageRequest "n" Data.Int.Int32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GenerateImageRequest'n
           (\ x__ y__ -> x__ {_GenerateImageRequest'n = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField GenerateImageRequest "maybe'n" (Prelude.Maybe Data.Int.Int32) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GenerateImageRequest'n
           (\ x__ y__ -> x__ {_GenerateImageRequest'n = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GenerateImageRequest "user" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GenerateImageRequest'user
           (\ x__ y__ -> x__ {_GenerateImageRequest'user = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GenerateImageRequest "format" ImageFormat where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GenerateImageRequest'format
           (\ x__ y__ -> x__ {_GenerateImageRequest'format = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GenerateImageRequest "aspectRatio" ImageAspectRatio where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GenerateImageRequest'aspectRatio
           (\ x__ y__ -> x__ {_GenerateImageRequest'aspectRatio = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField GenerateImageRequest "maybe'aspectRatio" (Prelude.Maybe ImageAspectRatio) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GenerateImageRequest'aspectRatio
           (\ x__ y__ -> x__ {_GenerateImageRequest'aspectRatio = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GenerateImageRequest "resolution" ImageResolution where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GenerateImageRequest'resolution
           (\ x__ y__ -> x__ {_GenerateImageRequest'resolution = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField GenerateImageRequest "maybe'resolution" (Prelude.Maybe ImageResolution) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GenerateImageRequest'resolution
           (\ x__ y__ -> x__ {_GenerateImageRequest'resolution = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GenerateImageRequest "images" [ImageUrlContent] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GenerateImageRequest'images
           (\ x__ y__ -> x__ {_GenerateImageRequest'images = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField GenerateImageRequest "vec'images" (Data.Vector.Vector ImageUrlContent) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GenerateImageRequest'images
           (\ x__ y__ -> x__ {_GenerateImageRequest'images = y__}))
        Prelude.id
instance Data.ProtoLens.Message GenerateImageRequest where
  messageName _ = Data.Text.pack "xai_api.GenerateImageRequest"
  packedMessageDescriptor _
    = "\n\
      \\DC4GenerateImageRequest\DC2\SYN\n\
      \\ACKprompt\CAN\SOH \SOH(\tR\ACKprompt\DC2.\n\
      \\ENQimage\CAN\ENQ \SOH(\v2\CAN.xai_api.ImageUrlContentR\ENQimage\DC2\DC4\n\
      \\ENQmodel\CAN\STX \SOH(\tR\ENQmodel\DC2\DC1\n\
      \\SOHn\CAN\ETX \SOH(\ENQH\NULR\SOHn\136\SOH\SOH\DC2\DC2\n\
      \\EOTuser\CAN\EOT \SOH(\tR\EOTuser\DC2,\n\
      \\ACKformat\CAN\v \SOH(\SO2\DC4.xai_api.ImageFormatR\ACKformat\DC2A\n\
      \\faspect_ratio\CAN\SO \SOH(\SO2\EM.xai_api.ImageAspectRatioH\SOHR\vaspectRatio\136\SOH\SOH\DC2=\n\
      \\n\
      \resolution\CAN\SI \SOH(\SO2\CAN.xai_api.ImageResolutionH\STXR\n\
      \resolution\136\SOH\SOH\DC20\n\
      \\ACKimages\CAN\DC1 \ETX(\v2\CAN.xai_api.ImageUrlContentR\ACKimagesB\EOT\n\
      \\STX_nB\SI\n\
      \\r_aspect_ratioB\r\n\
      \\v_resolutionJ\EOT\b\r\DLE\SO"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        prompt__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "prompt"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"prompt")) ::
              Data.ProtoLens.FieldDescriptor GenerateImageRequest
        image__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "image"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor ImageUrlContent)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'image")) ::
              Data.ProtoLens.FieldDescriptor GenerateImageRequest
        model__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "model"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"model")) ::
              Data.ProtoLens.FieldDescriptor GenerateImageRequest
        n__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "n"
              (Data.ProtoLens.ScalarField Data.ProtoLens.Int32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Int.Int32)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'n")) ::
              Data.ProtoLens.FieldDescriptor GenerateImageRequest
        user__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "user"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"user")) ::
              Data.ProtoLens.FieldDescriptor GenerateImageRequest
        format__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "format"
              (Data.ProtoLens.ScalarField Data.ProtoLens.EnumField ::
                 Data.ProtoLens.FieldTypeDescriptor ImageFormat)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"format")) ::
              Data.ProtoLens.FieldDescriptor GenerateImageRequest
        aspectRatio__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "aspect_ratio"
              (Data.ProtoLens.ScalarField Data.ProtoLens.EnumField ::
                 Data.ProtoLens.FieldTypeDescriptor ImageAspectRatio)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'aspectRatio")) ::
              Data.ProtoLens.FieldDescriptor GenerateImageRequest
        resolution__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "resolution"
              (Data.ProtoLens.ScalarField Data.ProtoLens.EnumField ::
                 Data.ProtoLens.FieldTypeDescriptor ImageResolution)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'resolution")) ::
              Data.ProtoLens.FieldDescriptor GenerateImageRequest
        images__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "images"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor ImageUrlContent)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Unpacked (Data.ProtoLens.Field.field @"images")) ::
              Data.ProtoLens.FieldDescriptor GenerateImageRequest
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, prompt__field_descriptor),
           (Data.ProtoLens.Tag 5, image__field_descriptor),
           (Data.ProtoLens.Tag 2, model__field_descriptor),
           (Data.ProtoLens.Tag 3, n__field_descriptor),
           (Data.ProtoLens.Tag 4, user__field_descriptor),
           (Data.ProtoLens.Tag 11, format__field_descriptor),
           (Data.ProtoLens.Tag 14, aspectRatio__field_descriptor),
           (Data.ProtoLens.Tag 15, resolution__field_descriptor),
           (Data.ProtoLens.Tag 17, images__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _GenerateImageRequest'_unknownFields
        (\ x__ y__ -> x__ {_GenerateImageRequest'_unknownFields = y__})
  defMessage
    = GenerateImageRequest'_constructor
        {_GenerateImageRequest'prompt = Data.ProtoLens.fieldDefault,
         _GenerateImageRequest'image = Prelude.Nothing,
         _GenerateImageRequest'model = Data.ProtoLens.fieldDefault,
         _GenerateImageRequest'n = Prelude.Nothing,
         _GenerateImageRequest'user = Data.ProtoLens.fieldDefault,
         _GenerateImageRequest'format = Data.ProtoLens.fieldDefault,
         _GenerateImageRequest'aspectRatio = Prelude.Nothing,
         _GenerateImageRequest'resolution = Prelude.Nothing,
         _GenerateImageRequest'images = Data.Vector.Generic.empty,
         _GenerateImageRequest'_unknownFields = []}
  parseMessage
    = let
        loop ::
          GenerateImageRequest
          -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Vector Data.ProtoLens.Encoding.Growing.RealWorld ImageUrlContent
             -> Data.ProtoLens.Encoding.Bytes.Parser GenerateImageRequest
        loop x mutable'images
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do frozen'images <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                         (Data.ProtoLens.Encoding.Growing.unsafeFreeze
                                            mutable'images)
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
                              (Data.ProtoLens.Field.field @"vec'images") frozen'images x))
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "prompt"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"prompt") y x)
                                  mutable'images
                        42
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "image"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"image") y x)
                                  mutable'images
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "model"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"model") y x)
                                  mutable'images
                        24
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "n"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"n") y x)
                                  mutable'images
                        34
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "user"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"user") y x)
                                  mutable'images
                        88
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.toEnum
                                          (Prelude.fmap
                                             Prelude.fromIntegral
                                             Data.ProtoLens.Encoding.Bytes.getVarInt))
                                       "format"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"format") y x)
                                  mutable'images
                        112
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.toEnum
                                          (Prelude.fmap
                                             Prelude.fromIntegral
                                             Data.ProtoLens.Encoding.Bytes.getVarInt))
                                       "aspect_ratio"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"aspectRatio") y x)
                                  mutable'images
                        120
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.toEnum
                                          (Prelude.fmap
                                             Prelude.fromIntegral
                                             Data.ProtoLens.Encoding.Bytes.getVarInt))
                                       "resolution"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"resolution") y x)
                                  mutable'images
                        138
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                            Data.ProtoLens.Encoding.Bytes.isolate
                                              (Prelude.fromIntegral len)
                                              Data.ProtoLens.parseMessage)
                                        "images"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append mutable'images y)
                                loop x v
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
                                  mutable'images
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do mutable'images <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                  Data.ProtoLens.Encoding.Growing.new
              loop Data.ProtoLens.defMessage mutable'images)
          "GenerateImageRequest"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v = Lens.Family2.view (Data.ProtoLens.Field.field @"prompt") _x
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
                (case
                     Lens.Family2.view (Data.ProtoLens.Field.field @"maybe'image") _x
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
                           Lens.Family2.view (Data.ProtoLens.Field.field @"maybe'n") _x
                       of
                         Prelude.Nothing -> Data.Monoid.mempty
                         (Prelude.Just _v)
                           -> (Data.Monoid.<>)
                                (Data.ProtoLens.Encoding.Bytes.putVarInt 24)
                                ((Prelude..)
                                   Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral _v))
                      ((Data.Monoid.<>)
                         (let _v = Lens.Family2.view (Data.ProtoLens.Field.field @"user") _x
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
                               _v = Lens.Family2.view (Data.ProtoLens.Field.field @"format") _x
                             in
                               if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                                   Data.Monoid.mempty
                               else
                                   (Data.Monoid.<>)
                                     (Data.ProtoLens.Encoding.Bytes.putVarInt 88)
                                     ((Prelude..)
                                        ((Prelude..)
                                           Data.ProtoLens.Encoding.Bytes.putVarInt
                                           Prelude.fromIntegral)
                                        Prelude.fromEnum _v))
                            ((Data.Monoid.<>)
                               (case
                                    Lens.Family2.view
                                      (Data.ProtoLens.Field.field @"maybe'aspectRatio") _x
                                of
                                  Prelude.Nothing -> Data.Monoid.mempty
                                  (Prelude.Just _v)
                                    -> (Data.Monoid.<>)
                                         (Data.ProtoLens.Encoding.Bytes.putVarInt 112)
                                         ((Prelude..)
                                            ((Prelude..)
                                               Data.ProtoLens.Encoding.Bytes.putVarInt
                                               Prelude.fromIntegral)
                                            Prelude.fromEnum _v))
                               ((Data.Monoid.<>)
                                  (case
                                       Lens.Family2.view
                                         (Data.ProtoLens.Field.field @"maybe'resolution") _x
                                   of
                                     Prelude.Nothing -> Data.Monoid.mempty
                                     (Prelude.Just _v)
                                       -> (Data.Monoid.<>)
                                            (Data.ProtoLens.Encoding.Bytes.putVarInt 120)
                                            ((Prelude..)
                                               ((Prelude..)
                                                  Data.ProtoLens.Encoding.Bytes.putVarInt
                                                  Prelude.fromIntegral)
                                               Prelude.fromEnum _v))
                                  ((Data.Monoid.<>)
                                     (Data.ProtoLens.Encoding.Bytes.foldMapBuilder
                                        (\ _v
                                           -> (Data.Monoid.<>)
                                                (Data.ProtoLens.Encoding.Bytes.putVarInt 138)
                                                ((Prelude..)
                                                   (\ bs
                                                      -> (Data.Monoid.<>)
                                                           (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                              (Prelude.fromIntegral
                                                                 (Data.ByteString.length bs)))
                                                           (Data.ProtoLens.Encoding.Bytes.putBytes
                                                              bs))
                                                   Data.ProtoLens.encodeMessage _v))
                                        (Lens.Family2.view
                                           (Data.ProtoLens.Field.field @"vec'images") _x))
                                     (Data.ProtoLens.Encoding.Wire.buildFieldSet
                                        (Lens.Family2.view Data.ProtoLens.unknownFields _x))))))))))
instance Control.DeepSeq.NFData GenerateImageRequest where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_GenerateImageRequest'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_GenerateImageRequest'prompt x__)
                (Control.DeepSeq.deepseq
                   (_GenerateImageRequest'image x__)
                   (Control.DeepSeq.deepseq
                      (_GenerateImageRequest'model x__)
                      (Control.DeepSeq.deepseq
                         (_GenerateImageRequest'n x__)
                         (Control.DeepSeq.deepseq
                            (_GenerateImageRequest'user x__)
                            (Control.DeepSeq.deepseq
                               (_GenerateImageRequest'format x__)
                               (Control.DeepSeq.deepseq
                                  (_GenerateImageRequest'aspectRatio x__)
                                  (Control.DeepSeq.deepseq
                                     (_GenerateImageRequest'resolution x__)
                                     (Control.DeepSeq.deepseq
                                        (_GenerateImageRequest'images x__) ())))))))))
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Image_Fields.respectModeration' @:: Lens' GeneratedImage Prelude.Bool@
         * 'Proto.Xai.Api.V1.Image_Fields.maybe'image' @:: Lens' GeneratedImage (Prelude.Maybe GeneratedImage'Image)@
         * 'Proto.Xai.Api.V1.Image_Fields.maybe'base64' @:: Lens' GeneratedImage (Prelude.Maybe Data.Text.Text)@
         * 'Proto.Xai.Api.V1.Image_Fields.base64' @:: Lens' GeneratedImage Data.Text.Text@
         * 'Proto.Xai.Api.V1.Image_Fields.maybe'url' @:: Lens' GeneratedImage (Prelude.Maybe Data.Text.Text)@
         * 'Proto.Xai.Api.V1.Image_Fields.url' @:: Lens' GeneratedImage Data.Text.Text@ -}
data GeneratedImage
  = GeneratedImage'_constructor {_GeneratedImage'respectModeration :: !Prelude.Bool,
                                 _GeneratedImage'image :: !(Prelude.Maybe GeneratedImage'Image),
                                 _GeneratedImage'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show GeneratedImage where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
data GeneratedImage'Image
  = GeneratedImage'Base64 !Data.Text.Text |
    GeneratedImage'Url !Data.Text.Text
  deriving stock (Prelude.Show, Prelude.Eq, Prelude.Ord)
instance Data.ProtoLens.Field.HasField GeneratedImage "respectModeration" Prelude.Bool where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GeneratedImage'respectModeration
           (\ x__ y__ -> x__ {_GeneratedImage'respectModeration = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GeneratedImage "maybe'image" (Prelude.Maybe GeneratedImage'Image) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GeneratedImage'image
           (\ x__ y__ -> x__ {_GeneratedImage'image = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField GeneratedImage "maybe'base64" (Prelude.Maybe Data.Text.Text) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GeneratedImage'image
           (\ x__ y__ -> x__ {_GeneratedImage'image = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (GeneratedImage'Base64 x__val))
                     -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap GeneratedImage'Base64 y__))
instance Data.ProtoLens.Field.HasField GeneratedImage "base64" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GeneratedImage'image
           (\ x__ y__ -> x__ {_GeneratedImage'image = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (GeneratedImage'Base64 x__val))
                        -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap GeneratedImage'Base64 y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault))
instance Data.ProtoLens.Field.HasField GeneratedImage "maybe'url" (Prelude.Maybe Data.Text.Text) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GeneratedImage'image
           (\ x__ y__ -> x__ {_GeneratedImage'image = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (GeneratedImage'Url x__val)) -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap GeneratedImage'Url y__))
instance Data.ProtoLens.Field.HasField GeneratedImage "url" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _GeneratedImage'image
           (\ x__ y__ -> x__ {_GeneratedImage'image = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (GeneratedImage'Url x__val)) -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap GeneratedImage'Url y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault))
instance Data.ProtoLens.Message GeneratedImage where
  messageName _ = Data.Text.pack "xai_api.GeneratedImage"
  packedMessageDescriptor _
    = "\n\
      \\SOGeneratedImage\DC2\CAN\n\
      \\ACKbase64\CAN\SOH \SOH(\tH\NULR\ACKbase64\DC2\DC2\n\
      \\ETXurl\CAN\ETX \SOH(\tH\NULR\ETXurl\DC2-\n\
      \\DC2respect_moderation\CAN\EOT \SOH(\bR\DC1respectModerationB\a\n\
      \\ENQimageJ\EOT\b\STX\DLE\ETX"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        respectModeration__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "respect_moderation"
              (Data.ProtoLens.ScalarField Data.ProtoLens.BoolField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Bool)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"respectModeration")) ::
              Data.ProtoLens.FieldDescriptor GeneratedImage
        base64__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "base64"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'base64")) ::
              Data.ProtoLens.FieldDescriptor GeneratedImage
        url__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "url"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'url")) ::
              Data.ProtoLens.FieldDescriptor GeneratedImage
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 4, respectModeration__field_descriptor),
           (Data.ProtoLens.Tag 1, base64__field_descriptor),
           (Data.ProtoLens.Tag 3, url__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _GeneratedImage'_unknownFields
        (\ x__ y__ -> x__ {_GeneratedImage'_unknownFields = y__})
  defMessage
    = GeneratedImage'_constructor
        {_GeneratedImage'respectModeration = Data.ProtoLens.fieldDefault,
         _GeneratedImage'image = Prelude.Nothing,
         _GeneratedImage'_unknownFields = []}
  parseMessage
    = let
        loop ::
          GeneratedImage
          -> Data.ProtoLens.Encoding.Bytes.Parser GeneratedImage
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
                        32
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          ((Prelude./=) 0) Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "respect_moderation"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"respectModeration") y x)
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "base64"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"base64") y x)
                        26
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
          (do loop Data.ProtoLens.defMessage) "GeneratedImage"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v
                  = Lens.Family2.view
                      (Data.ProtoLens.Field.field @"respectModeration") _x
              in
                if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 32)
                      ((Prelude..)
                         Data.ProtoLens.Encoding.Bytes.putVarInt (\ b -> if b then 1 else 0)
                         _v))
             ((Data.Monoid.<>)
                (case
                     Lens.Family2.view (Data.ProtoLens.Field.field @"maybe'image") _x
                 of
                   Prelude.Nothing -> Data.Monoid.mempty
                   (Prelude.Just (GeneratedImage'Base64 v))
                     -> (Data.Monoid.<>)
                          (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                          ((Prelude..)
                             (\ bs
                                -> (Data.Monoid.<>)
                                     (Data.ProtoLens.Encoding.Bytes.putVarInt
                                        (Prelude.fromIntegral (Data.ByteString.length bs)))
                                     (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                             Data.Text.Encoding.encodeUtf8 v)
                   (Prelude.Just (GeneratedImage'Url v))
                     -> (Data.Monoid.<>)
                          (Data.ProtoLens.Encoding.Bytes.putVarInt 26)
                          ((Prelude..)
                             (\ bs
                                -> (Data.Monoid.<>)
                                     (Data.ProtoLens.Encoding.Bytes.putVarInt
                                        (Prelude.fromIntegral (Data.ByteString.length bs)))
                                     (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                             Data.Text.Encoding.encodeUtf8 v))
                (Data.ProtoLens.Encoding.Wire.buildFieldSet
                   (Lens.Family2.view Data.ProtoLens.unknownFields _x)))
instance Control.DeepSeq.NFData GeneratedImage where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_GeneratedImage'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_GeneratedImage'respectModeration x__)
                (Control.DeepSeq.deepseq (_GeneratedImage'image x__) ()))
instance Control.DeepSeq.NFData GeneratedImage'Image where
  rnf (GeneratedImage'Base64 x__) = Control.DeepSeq.rnf x__
  rnf (GeneratedImage'Url x__) = Control.DeepSeq.rnf x__
_GeneratedImage'Base64 ::
  Data.ProtoLens.Prism.Prism' GeneratedImage'Image Data.Text.Text
_GeneratedImage'Base64
  = Data.ProtoLens.Prism.prism'
      GeneratedImage'Base64
      (\ p__
         -> case p__ of
              (GeneratedImage'Base64 p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
_GeneratedImage'Url ::
  Data.ProtoLens.Prism.Prism' GeneratedImage'Image Data.Text.Text
_GeneratedImage'Url
  = Data.ProtoLens.Prism.prism'
      GeneratedImage'Url
      (\ p__
         -> case p__ of
              (GeneratedImage'Url p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
newtype ImageAspectRatio'UnrecognizedValue
  = ImageAspectRatio'UnrecognizedValue Data.Int.Int32
  deriving stock (Prelude.Eq, Prelude.Ord, Prelude.Show)
data ImageAspectRatio
  = IMG_ASPECT_RATIO_INVALID |
    IMG_ASPECT_RATIO_1_1 |
    IMG_ASPECT_RATIO_3_4 |
    IMG_ASPECT_RATIO_4_3 |
    IMG_ASPECT_RATIO_9_16 |
    IMG_ASPECT_RATIO_16_9 |
    IMG_ASPECT_RATIO_2_3 |
    IMG_ASPECT_RATIO_3_2 |
    IMG_ASPECT_RATIO_AUTO |
    IMG_ASPECT_RATIO_9_19_5 |
    IMG_ASPECT_RATIO_19_5_9 |
    IMG_ASPECT_RATIO_9_20 |
    IMG_ASPECT_RATIO_20_9 |
    IMG_ASPECT_RATIO_1_2 |
    IMG_ASPECT_RATIO_2_1 |
    ImageAspectRatio'Unrecognized !ImageAspectRatio'UnrecognizedValue
  deriving stock (Prelude.Show, Prelude.Eq, Prelude.Ord)
instance Data.ProtoLens.MessageEnum ImageAspectRatio where
  maybeToEnum 0 = Prelude.Just IMG_ASPECT_RATIO_INVALID
  maybeToEnum 1 = Prelude.Just IMG_ASPECT_RATIO_1_1
  maybeToEnum 2 = Prelude.Just IMG_ASPECT_RATIO_3_4
  maybeToEnum 3 = Prelude.Just IMG_ASPECT_RATIO_4_3
  maybeToEnum 4 = Prelude.Just IMG_ASPECT_RATIO_9_16
  maybeToEnum 5 = Prelude.Just IMG_ASPECT_RATIO_16_9
  maybeToEnum 6 = Prelude.Just IMG_ASPECT_RATIO_2_3
  maybeToEnum 7 = Prelude.Just IMG_ASPECT_RATIO_3_2
  maybeToEnum 8 = Prelude.Just IMG_ASPECT_RATIO_AUTO
  maybeToEnum 9 = Prelude.Just IMG_ASPECT_RATIO_9_19_5
  maybeToEnum 10 = Prelude.Just IMG_ASPECT_RATIO_19_5_9
  maybeToEnum 11 = Prelude.Just IMG_ASPECT_RATIO_9_20
  maybeToEnum 12 = Prelude.Just IMG_ASPECT_RATIO_20_9
  maybeToEnum 13 = Prelude.Just IMG_ASPECT_RATIO_1_2
  maybeToEnum 14 = Prelude.Just IMG_ASPECT_RATIO_2_1
  maybeToEnum k
    = Prelude.Just
        (ImageAspectRatio'Unrecognized
           (ImageAspectRatio'UnrecognizedValue (Prelude.fromIntegral k)))
  showEnum IMG_ASPECT_RATIO_INVALID = "IMG_ASPECT_RATIO_INVALID"
  showEnum IMG_ASPECT_RATIO_1_1 = "IMG_ASPECT_RATIO_1_1"
  showEnum IMG_ASPECT_RATIO_3_4 = "IMG_ASPECT_RATIO_3_4"
  showEnum IMG_ASPECT_RATIO_4_3 = "IMG_ASPECT_RATIO_4_3"
  showEnum IMG_ASPECT_RATIO_9_16 = "IMG_ASPECT_RATIO_9_16"
  showEnum IMG_ASPECT_RATIO_16_9 = "IMG_ASPECT_RATIO_16_9"
  showEnum IMG_ASPECT_RATIO_2_3 = "IMG_ASPECT_RATIO_2_3"
  showEnum IMG_ASPECT_RATIO_3_2 = "IMG_ASPECT_RATIO_3_2"
  showEnum IMG_ASPECT_RATIO_AUTO = "IMG_ASPECT_RATIO_AUTO"
  showEnum IMG_ASPECT_RATIO_9_19_5 = "IMG_ASPECT_RATIO_9_19_5"
  showEnum IMG_ASPECT_RATIO_19_5_9 = "IMG_ASPECT_RATIO_19_5_9"
  showEnum IMG_ASPECT_RATIO_9_20 = "IMG_ASPECT_RATIO_9_20"
  showEnum IMG_ASPECT_RATIO_20_9 = "IMG_ASPECT_RATIO_20_9"
  showEnum IMG_ASPECT_RATIO_1_2 = "IMG_ASPECT_RATIO_1_2"
  showEnum IMG_ASPECT_RATIO_2_1 = "IMG_ASPECT_RATIO_2_1"
  showEnum
    (ImageAspectRatio'Unrecognized (ImageAspectRatio'UnrecognizedValue k))
    = Prelude.show k
  readEnum k
    | (Prelude.==) k "IMG_ASPECT_RATIO_INVALID"
    = Prelude.Just IMG_ASPECT_RATIO_INVALID
    | (Prelude.==) k "IMG_ASPECT_RATIO_1_1"
    = Prelude.Just IMG_ASPECT_RATIO_1_1
    | (Prelude.==) k "IMG_ASPECT_RATIO_3_4"
    = Prelude.Just IMG_ASPECT_RATIO_3_4
    | (Prelude.==) k "IMG_ASPECT_RATIO_4_3"
    = Prelude.Just IMG_ASPECT_RATIO_4_3
    | (Prelude.==) k "IMG_ASPECT_RATIO_9_16"
    = Prelude.Just IMG_ASPECT_RATIO_9_16
    | (Prelude.==) k "IMG_ASPECT_RATIO_16_9"
    = Prelude.Just IMG_ASPECT_RATIO_16_9
    | (Prelude.==) k "IMG_ASPECT_RATIO_2_3"
    = Prelude.Just IMG_ASPECT_RATIO_2_3
    | (Prelude.==) k "IMG_ASPECT_RATIO_3_2"
    = Prelude.Just IMG_ASPECT_RATIO_3_2
    | (Prelude.==) k "IMG_ASPECT_RATIO_AUTO"
    = Prelude.Just IMG_ASPECT_RATIO_AUTO
    | (Prelude.==) k "IMG_ASPECT_RATIO_9_19_5"
    = Prelude.Just IMG_ASPECT_RATIO_9_19_5
    | (Prelude.==) k "IMG_ASPECT_RATIO_19_5_9"
    = Prelude.Just IMG_ASPECT_RATIO_19_5_9
    | (Prelude.==) k "IMG_ASPECT_RATIO_9_20"
    = Prelude.Just IMG_ASPECT_RATIO_9_20
    | (Prelude.==) k "IMG_ASPECT_RATIO_20_9"
    = Prelude.Just IMG_ASPECT_RATIO_20_9
    | (Prelude.==) k "IMG_ASPECT_RATIO_1_2"
    = Prelude.Just IMG_ASPECT_RATIO_1_2
    | (Prelude.==) k "IMG_ASPECT_RATIO_2_1"
    = Prelude.Just IMG_ASPECT_RATIO_2_1
    | Prelude.otherwise
    = (Prelude.>>=) (Text.Read.readMaybe k) Data.ProtoLens.maybeToEnum
instance Prelude.Bounded ImageAspectRatio where
  minBound = IMG_ASPECT_RATIO_INVALID
  maxBound = IMG_ASPECT_RATIO_2_1
instance Prelude.Enum ImageAspectRatio where
  toEnum k__
    = Prelude.maybe
        (Prelude.error
           ((Prelude.++)
              "toEnum: unknown value for enum ImageAspectRatio: "
              (Prelude.show k__)))
        Prelude.id (Data.ProtoLens.maybeToEnum k__)
  fromEnum IMG_ASPECT_RATIO_INVALID = 0
  fromEnum IMG_ASPECT_RATIO_1_1 = 1
  fromEnum IMG_ASPECT_RATIO_3_4 = 2
  fromEnum IMG_ASPECT_RATIO_4_3 = 3
  fromEnum IMG_ASPECT_RATIO_9_16 = 4
  fromEnum IMG_ASPECT_RATIO_16_9 = 5
  fromEnum IMG_ASPECT_RATIO_2_3 = 6
  fromEnum IMG_ASPECT_RATIO_3_2 = 7
  fromEnum IMG_ASPECT_RATIO_AUTO = 8
  fromEnum IMG_ASPECT_RATIO_9_19_5 = 9
  fromEnum IMG_ASPECT_RATIO_19_5_9 = 10
  fromEnum IMG_ASPECT_RATIO_9_20 = 11
  fromEnum IMG_ASPECT_RATIO_20_9 = 12
  fromEnum IMG_ASPECT_RATIO_1_2 = 13
  fromEnum IMG_ASPECT_RATIO_2_1 = 14
  fromEnum
    (ImageAspectRatio'Unrecognized (ImageAspectRatio'UnrecognizedValue k))
    = Prelude.fromIntegral k
  succ IMG_ASPECT_RATIO_2_1
    = Prelude.error
        "ImageAspectRatio.succ: bad argument IMG_ASPECT_RATIO_2_1. This value would be out of bounds."
  succ IMG_ASPECT_RATIO_INVALID = IMG_ASPECT_RATIO_1_1
  succ IMG_ASPECT_RATIO_1_1 = IMG_ASPECT_RATIO_3_4
  succ IMG_ASPECT_RATIO_3_4 = IMG_ASPECT_RATIO_4_3
  succ IMG_ASPECT_RATIO_4_3 = IMG_ASPECT_RATIO_9_16
  succ IMG_ASPECT_RATIO_9_16 = IMG_ASPECT_RATIO_16_9
  succ IMG_ASPECT_RATIO_16_9 = IMG_ASPECT_RATIO_2_3
  succ IMG_ASPECT_RATIO_2_3 = IMG_ASPECT_RATIO_3_2
  succ IMG_ASPECT_RATIO_3_2 = IMG_ASPECT_RATIO_AUTO
  succ IMG_ASPECT_RATIO_AUTO = IMG_ASPECT_RATIO_9_19_5
  succ IMG_ASPECT_RATIO_9_19_5 = IMG_ASPECT_RATIO_19_5_9
  succ IMG_ASPECT_RATIO_19_5_9 = IMG_ASPECT_RATIO_9_20
  succ IMG_ASPECT_RATIO_9_20 = IMG_ASPECT_RATIO_20_9
  succ IMG_ASPECT_RATIO_20_9 = IMG_ASPECT_RATIO_1_2
  succ IMG_ASPECT_RATIO_1_2 = IMG_ASPECT_RATIO_2_1
  succ (ImageAspectRatio'Unrecognized _)
    = Prelude.error
        "ImageAspectRatio.succ: bad argument: unrecognized value"
  pred IMG_ASPECT_RATIO_INVALID
    = Prelude.error
        "ImageAspectRatio.pred: bad argument IMG_ASPECT_RATIO_INVALID. This value would be out of bounds."
  pred IMG_ASPECT_RATIO_1_1 = IMG_ASPECT_RATIO_INVALID
  pred IMG_ASPECT_RATIO_3_4 = IMG_ASPECT_RATIO_1_1
  pred IMG_ASPECT_RATIO_4_3 = IMG_ASPECT_RATIO_3_4
  pred IMG_ASPECT_RATIO_9_16 = IMG_ASPECT_RATIO_4_3
  pred IMG_ASPECT_RATIO_16_9 = IMG_ASPECT_RATIO_9_16
  pred IMG_ASPECT_RATIO_2_3 = IMG_ASPECT_RATIO_16_9
  pred IMG_ASPECT_RATIO_3_2 = IMG_ASPECT_RATIO_2_3
  pred IMG_ASPECT_RATIO_AUTO = IMG_ASPECT_RATIO_3_2
  pred IMG_ASPECT_RATIO_9_19_5 = IMG_ASPECT_RATIO_AUTO
  pred IMG_ASPECT_RATIO_19_5_9 = IMG_ASPECT_RATIO_9_19_5
  pred IMG_ASPECT_RATIO_9_20 = IMG_ASPECT_RATIO_19_5_9
  pred IMG_ASPECT_RATIO_20_9 = IMG_ASPECT_RATIO_9_20
  pred IMG_ASPECT_RATIO_1_2 = IMG_ASPECT_RATIO_20_9
  pred IMG_ASPECT_RATIO_2_1 = IMG_ASPECT_RATIO_1_2
  pred (ImageAspectRatio'Unrecognized _)
    = Prelude.error
        "ImageAspectRatio.pred: bad argument: unrecognized value"
  enumFrom = Data.ProtoLens.Message.Enum.messageEnumFrom
  enumFromTo = Data.ProtoLens.Message.Enum.messageEnumFromTo
  enumFromThen = Data.ProtoLens.Message.Enum.messageEnumFromThen
  enumFromThenTo = Data.ProtoLens.Message.Enum.messageEnumFromThenTo
instance Data.ProtoLens.FieldDefault ImageAspectRatio where
  fieldDefault = IMG_ASPECT_RATIO_INVALID
instance Control.DeepSeq.NFData ImageAspectRatio where
  rnf x__ = Prelude.seq x__ ()
newtype ImageDetail'UnrecognizedValue
  = ImageDetail'UnrecognizedValue Data.Int.Int32
  deriving stock (Prelude.Eq, Prelude.Ord, Prelude.Show)
data ImageDetail
  = DETAIL_INVALID |
    DETAIL_AUTO |
    DETAIL_LOW |
    DETAIL_HIGH |
    ImageDetail'Unrecognized !ImageDetail'UnrecognizedValue
  deriving stock (Prelude.Show, Prelude.Eq, Prelude.Ord)
instance Data.ProtoLens.MessageEnum ImageDetail where
  maybeToEnum 0 = Prelude.Just DETAIL_INVALID
  maybeToEnum 1 = Prelude.Just DETAIL_AUTO
  maybeToEnum 2 = Prelude.Just DETAIL_LOW
  maybeToEnum 3 = Prelude.Just DETAIL_HIGH
  maybeToEnum k
    = Prelude.Just
        (ImageDetail'Unrecognized
           (ImageDetail'UnrecognizedValue (Prelude.fromIntegral k)))
  showEnum DETAIL_INVALID = "DETAIL_INVALID"
  showEnum DETAIL_AUTO = "DETAIL_AUTO"
  showEnum DETAIL_LOW = "DETAIL_LOW"
  showEnum DETAIL_HIGH = "DETAIL_HIGH"
  showEnum
    (ImageDetail'Unrecognized (ImageDetail'UnrecognizedValue k))
    = Prelude.show k
  readEnum k
    | (Prelude.==) k "DETAIL_INVALID" = Prelude.Just DETAIL_INVALID
    | (Prelude.==) k "DETAIL_AUTO" = Prelude.Just DETAIL_AUTO
    | (Prelude.==) k "DETAIL_LOW" = Prelude.Just DETAIL_LOW
    | (Prelude.==) k "DETAIL_HIGH" = Prelude.Just DETAIL_HIGH
    | Prelude.otherwise
    = (Prelude.>>=) (Text.Read.readMaybe k) Data.ProtoLens.maybeToEnum
instance Prelude.Bounded ImageDetail where
  minBound = DETAIL_INVALID
  maxBound = DETAIL_HIGH
instance Prelude.Enum ImageDetail where
  toEnum k__
    = Prelude.maybe
        (Prelude.error
           ((Prelude.++)
              "toEnum: unknown value for enum ImageDetail: " (Prelude.show k__)))
        Prelude.id (Data.ProtoLens.maybeToEnum k__)
  fromEnum DETAIL_INVALID = 0
  fromEnum DETAIL_AUTO = 1
  fromEnum DETAIL_LOW = 2
  fromEnum DETAIL_HIGH = 3
  fromEnum
    (ImageDetail'Unrecognized (ImageDetail'UnrecognizedValue k))
    = Prelude.fromIntegral k
  succ DETAIL_HIGH
    = Prelude.error
        "ImageDetail.succ: bad argument DETAIL_HIGH. This value would be out of bounds."
  succ DETAIL_INVALID = DETAIL_AUTO
  succ DETAIL_AUTO = DETAIL_LOW
  succ DETAIL_LOW = DETAIL_HIGH
  succ (ImageDetail'Unrecognized _)
    = Prelude.error
        "ImageDetail.succ: bad argument: unrecognized value"
  pred DETAIL_INVALID
    = Prelude.error
        "ImageDetail.pred: bad argument DETAIL_INVALID. This value would be out of bounds."
  pred DETAIL_AUTO = DETAIL_INVALID
  pred DETAIL_LOW = DETAIL_AUTO
  pred DETAIL_HIGH = DETAIL_LOW
  pred (ImageDetail'Unrecognized _)
    = Prelude.error
        "ImageDetail.pred: bad argument: unrecognized value"
  enumFrom = Data.ProtoLens.Message.Enum.messageEnumFrom
  enumFromTo = Data.ProtoLens.Message.Enum.messageEnumFromTo
  enumFromThen = Data.ProtoLens.Message.Enum.messageEnumFromThen
  enumFromThenTo = Data.ProtoLens.Message.Enum.messageEnumFromThenTo
instance Data.ProtoLens.FieldDefault ImageDetail where
  fieldDefault = DETAIL_INVALID
instance Control.DeepSeq.NFData ImageDetail where
  rnf x__ = Prelude.seq x__ ()
newtype ImageFormat'UnrecognizedValue
  = ImageFormat'UnrecognizedValue Data.Int.Int32
  deriving stock (Prelude.Eq, Prelude.Ord, Prelude.Show)
data ImageFormat
  = IMG_FORMAT_INVALID |
    IMG_FORMAT_BASE64 |
    IMG_FORMAT_URL |
    ImageFormat'Unrecognized !ImageFormat'UnrecognizedValue
  deriving stock (Prelude.Show, Prelude.Eq, Prelude.Ord)
instance Data.ProtoLens.MessageEnum ImageFormat where
  maybeToEnum 0 = Prelude.Just IMG_FORMAT_INVALID
  maybeToEnum 1 = Prelude.Just IMG_FORMAT_BASE64
  maybeToEnum 2 = Prelude.Just IMG_FORMAT_URL
  maybeToEnum k
    = Prelude.Just
        (ImageFormat'Unrecognized
           (ImageFormat'UnrecognizedValue (Prelude.fromIntegral k)))
  showEnum IMG_FORMAT_INVALID = "IMG_FORMAT_INVALID"
  showEnum IMG_FORMAT_BASE64 = "IMG_FORMAT_BASE64"
  showEnum IMG_FORMAT_URL = "IMG_FORMAT_URL"
  showEnum
    (ImageFormat'Unrecognized (ImageFormat'UnrecognizedValue k))
    = Prelude.show k
  readEnum k
    | (Prelude.==) k "IMG_FORMAT_INVALID"
    = Prelude.Just IMG_FORMAT_INVALID
    | (Prelude.==) k "IMG_FORMAT_BASE64"
    = Prelude.Just IMG_FORMAT_BASE64
    | (Prelude.==) k "IMG_FORMAT_URL" = Prelude.Just IMG_FORMAT_URL
    | Prelude.otherwise
    = (Prelude.>>=) (Text.Read.readMaybe k) Data.ProtoLens.maybeToEnum
instance Prelude.Bounded ImageFormat where
  minBound = IMG_FORMAT_INVALID
  maxBound = IMG_FORMAT_URL
instance Prelude.Enum ImageFormat where
  toEnum k__
    = Prelude.maybe
        (Prelude.error
           ((Prelude.++)
              "toEnum: unknown value for enum ImageFormat: " (Prelude.show k__)))
        Prelude.id (Data.ProtoLens.maybeToEnum k__)
  fromEnum IMG_FORMAT_INVALID = 0
  fromEnum IMG_FORMAT_BASE64 = 1
  fromEnum IMG_FORMAT_URL = 2
  fromEnum
    (ImageFormat'Unrecognized (ImageFormat'UnrecognizedValue k))
    = Prelude.fromIntegral k
  succ IMG_FORMAT_URL
    = Prelude.error
        "ImageFormat.succ: bad argument IMG_FORMAT_URL. This value would be out of bounds."
  succ IMG_FORMAT_INVALID = IMG_FORMAT_BASE64
  succ IMG_FORMAT_BASE64 = IMG_FORMAT_URL
  succ (ImageFormat'Unrecognized _)
    = Prelude.error
        "ImageFormat.succ: bad argument: unrecognized value"
  pred IMG_FORMAT_INVALID
    = Prelude.error
        "ImageFormat.pred: bad argument IMG_FORMAT_INVALID. This value would be out of bounds."
  pred IMG_FORMAT_BASE64 = IMG_FORMAT_INVALID
  pred IMG_FORMAT_URL = IMG_FORMAT_BASE64
  pred (ImageFormat'Unrecognized _)
    = Prelude.error
        "ImageFormat.pred: bad argument: unrecognized value"
  enumFrom = Data.ProtoLens.Message.Enum.messageEnumFrom
  enumFromTo = Data.ProtoLens.Message.Enum.messageEnumFromTo
  enumFromThen = Data.ProtoLens.Message.Enum.messageEnumFromThen
  enumFromThenTo = Data.ProtoLens.Message.Enum.messageEnumFromThenTo
instance Data.ProtoLens.FieldDefault ImageFormat where
  fieldDefault = IMG_FORMAT_INVALID
instance Control.DeepSeq.NFData ImageFormat where
  rnf x__ = Prelude.seq x__ ()
newtype ImageQuality'UnrecognizedValue
  = ImageQuality'UnrecognizedValue Data.Int.Int32
  deriving stock (Prelude.Eq, Prelude.Ord, Prelude.Show)
data ImageQuality
  = IMG_QUALITY_INVALID |
    IMG_QUALITY_LOW |
    IMG_QUALITY_MEDIUM |
    IMG_QUALITY_HIGH |
    ImageQuality'Unrecognized !ImageQuality'UnrecognizedValue
  deriving stock (Prelude.Show, Prelude.Eq, Prelude.Ord)
instance Data.ProtoLens.MessageEnum ImageQuality where
  maybeToEnum 0 = Prelude.Just IMG_QUALITY_INVALID
  maybeToEnum 1 = Prelude.Just IMG_QUALITY_LOW
  maybeToEnum 2 = Prelude.Just IMG_QUALITY_MEDIUM
  maybeToEnum 3 = Prelude.Just IMG_QUALITY_HIGH
  maybeToEnum k
    = Prelude.Just
        (ImageQuality'Unrecognized
           (ImageQuality'UnrecognizedValue (Prelude.fromIntegral k)))
  showEnum IMG_QUALITY_INVALID = "IMG_QUALITY_INVALID"
  showEnum IMG_QUALITY_LOW = "IMG_QUALITY_LOW"
  showEnum IMG_QUALITY_MEDIUM = "IMG_QUALITY_MEDIUM"
  showEnum IMG_QUALITY_HIGH = "IMG_QUALITY_HIGH"
  showEnum
    (ImageQuality'Unrecognized (ImageQuality'UnrecognizedValue k))
    = Prelude.show k
  readEnum k
    | (Prelude.==) k "IMG_QUALITY_INVALID"
    = Prelude.Just IMG_QUALITY_INVALID
    | (Prelude.==) k "IMG_QUALITY_LOW" = Prelude.Just IMG_QUALITY_LOW
    | (Prelude.==) k "IMG_QUALITY_MEDIUM"
    = Prelude.Just IMG_QUALITY_MEDIUM
    | (Prelude.==) k "IMG_QUALITY_HIGH" = Prelude.Just IMG_QUALITY_HIGH
    | Prelude.otherwise
    = (Prelude.>>=) (Text.Read.readMaybe k) Data.ProtoLens.maybeToEnum
instance Prelude.Bounded ImageQuality where
  minBound = IMG_QUALITY_INVALID
  maxBound = IMG_QUALITY_HIGH
instance Prelude.Enum ImageQuality where
  toEnum k__
    = Prelude.maybe
        (Prelude.error
           ((Prelude.++)
              "toEnum: unknown value for enum ImageQuality: "
              (Prelude.show k__)))
        Prelude.id (Data.ProtoLens.maybeToEnum k__)
  fromEnum IMG_QUALITY_INVALID = 0
  fromEnum IMG_QUALITY_LOW = 1
  fromEnum IMG_QUALITY_MEDIUM = 2
  fromEnum IMG_QUALITY_HIGH = 3
  fromEnum
    (ImageQuality'Unrecognized (ImageQuality'UnrecognizedValue k))
    = Prelude.fromIntegral k
  succ IMG_QUALITY_HIGH
    = Prelude.error
        "ImageQuality.succ: bad argument IMG_QUALITY_HIGH. This value would be out of bounds."
  succ IMG_QUALITY_INVALID = IMG_QUALITY_LOW
  succ IMG_QUALITY_LOW = IMG_QUALITY_MEDIUM
  succ IMG_QUALITY_MEDIUM = IMG_QUALITY_HIGH
  succ (ImageQuality'Unrecognized _)
    = Prelude.error
        "ImageQuality.succ: bad argument: unrecognized value"
  pred IMG_QUALITY_INVALID
    = Prelude.error
        "ImageQuality.pred: bad argument IMG_QUALITY_INVALID. This value would be out of bounds."
  pred IMG_QUALITY_LOW = IMG_QUALITY_INVALID
  pred IMG_QUALITY_MEDIUM = IMG_QUALITY_LOW
  pred IMG_QUALITY_HIGH = IMG_QUALITY_MEDIUM
  pred (ImageQuality'Unrecognized _)
    = Prelude.error
        "ImageQuality.pred: bad argument: unrecognized value"
  enumFrom = Data.ProtoLens.Message.Enum.messageEnumFrom
  enumFromTo = Data.ProtoLens.Message.Enum.messageEnumFromTo
  enumFromThen = Data.ProtoLens.Message.Enum.messageEnumFromThen
  enumFromThenTo = Data.ProtoLens.Message.Enum.messageEnumFromThenTo
instance Data.ProtoLens.FieldDefault ImageQuality where
  fieldDefault = IMG_QUALITY_INVALID
instance Control.DeepSeq.NFData ImageQuality where
  rnf x__ = Prelude.seq x__ ()
newtype ImageResolution'UnrecognizedValue
  = ImageResolution'UnrecognizedValue Data.Int.Int32
  deriving stock (Prelude.Eq, Prelude.Ord, Prelude.Show)
data ImageResolution
  = IMG_RESOLUTION_INVALID |
    IMG_RESOLUTION_1K |
    IMG_RESOLUTION_2K |
    ImageResolution'Unrecognized !ImageResolution'UnrecognizedValue
  deriving stock (Prelude.Show, Prelude.Eq, Prelude.Ord)
instance Data.ProtoLens.MessageEnum ImageResolution where
  maybeToEnum 0 = Prelude.Just IMG_RESOLUTION_INVALID
  maybeToEnum 1 = Prelude.Just IMG_RESOLUTION_1K
  maybeToEnum 2 = Prelude.Just IMG_RESOLUTION_2K
  maybeToEnum k
    = Prelude.Just
        (ImageResolution'Unrecognized
           (ImageResolution'UnrecognizedValue (Prelude.fromIntegral k)))
  showEnum IMG_RESOLUTION_INVALID = "IMG_RESOLUTION_INVALID"
  showEnum IMG_RESOLUTION_1K = "IMG_RESOLUTION_1K"
  showEnum IMG_RESOLUTION_2K = "IMG_RESOLUTION_2K"
  showEnum
    (ImageResolution'Unrecognized (ImageResolution'UnrecognizedValue k))
    = Prelude.show k
  readEnum k
    | (Prelude.==) k "IMG_RESOLUTION_INVALID"
    = Prelude.Just IMG_RESOLUTION_INVALID
    | (Prelude.==) k "IMG_RESOLUTION_1K"
    = Prelude.Just IMG_RESOLUTION_1K
    | (Prelude.==) k "IMG_RESOLUTION_2K"
    = Prelude.Just IMG_RESOLUTION_2K
    | Prelude.otherwise
    = (Prelude.>>=) (Text.Read.readMaybe k) Data.ProtoLens.maybeToEnum
instance Prelude.Bounded ImageResolution where
  minBound = IMG_RESOLUTION_INVALID
  maxBound = IMG_RESOLUTION_2K
instance Prelude.Enum ImageResolution where
  toEnum k__
    = Prelude.maybe
        (Prelude.error
           ((Prelude.++)
              "toEnum: unknown value for enum ImageResolution: "
              (Prelude.show k__)))
        Prelude.id (Data.ProtoLens.maybeToEnum k__)
  fromEnum IMG_RESOLUTION_INVALID = 0
  fromEnum IMG_RESOLUTION_1K = 1
  fromEnum IMG_RESOLUTION_2K = 2
  fromEnum
    (ImageResolution'Unrecognized (ImageResolution'UnrecognizedValue k))
    = Prelude.fromIntegral k
  succ IMG_RESOLUTION_2K
    = Prelude.error
        "ImageResolution.succ: bad argument IMG_RESOLUTION_2K. This value would be out of bounds."
  succ IMG_RESOLUTION_INVALID = IMG_RESOLUTION_1K
  succ IMG_RESOLUTION_1K = IMG_RESOLUTION_2K
  succ (ImageResolution'Unrecognized _)
    = Prelude.error
        "ImageResolution.succ: bad argument: unrecognized value"
  pred IMG_RESOLUTION_INVALID
    = Prelude.error
        "ImageResolution.pred: bad argument IMG_RESOLUTION_INVALID. This value would be out of bounds."
  pred IMG_RESOLUTION_1K = IMG_RESOLUTION_INVALID
  pred IMG_RESOLUTION_2K = IMG_RESOLUTION_1K
  pred (ImageResolution'Unrecognized _)
    = Prelude.error
        "ImageResolution.pred: bad argument: unrecognized value"
  enumFrom = Data.ProtoLens.Message.Enum.messageEnumFrom
  enumFromTo = Data.ProtoLens.Message.Enum.messageEnumFromTo
  enumFromThen = Data.ProtoLens.Message.Enum.messageEnumFromThen
  enumFromThenTo = Data.ProtoLens.Message.Enum.messageEnumFromThenTo
instance Data.ProtoLens.FieldDefault ImageResolution where
  fieldDefault = IMG_RESOLUTION_INVALID
instance Control.DeepSeq.NFData ImageResolution where
  rnf x__ = Prelude.seq x__ ()
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Image_Fields.images' @:: Lens' ImageResponse [GeneratedImage]@
         * 'Proto.Xai.Api.V1.Image_Fields.vec'images' @:: Lens' ImageResponse (Data.Vector.Vector GeneratedImage)@
         * 'Proto.Xai.Api.V1.Image_Fields.model' @:: Lens' ImageResponse Data.Text.Text@
         * 'Proto.Xai.Api.V1.Image_Fields.usage' @:: Lens' ImageResponse Proto.Xai.Api.V1.Usage.SamplingUsage@
         * 'Proto.Xai.Api.V1.Image_Fields.maybe'usage' @:: Lens' ImageResponse (Prelude.Maybe Proto.Xai.Api.V1.Usage.SamplingUsage)@ -}
data ImageResponse
  = ImageResponse'_constructor {_ImageResponse'images :: !(Data.Vector.Vector GeneratedImage),
                                _ImageResponse'model :: !Data.Text.Text,
                                _ImageResponse'usage :: !(Prelude.Maybe Proto.Xai.Api.V1.Usage.SamplingUsage),
                                _ImageResponse'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show ImageResponse where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField ImageResponse "images" [GeneratedImage] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ImageResponse'images
           (\ x__ y__ -> x__ {_ImageResponse'images = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField ImageResponse "vec'images" (Data.Vector.Vector GeneratedImage) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ImageResponse'images
           (\ x__ y__ -> x__ {_ImageResponse'images = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField ImageResponse "model" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ImageResponse'model
           (\ x__ y__ -> x__ {_ImageResponse'model = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField ImageResponse "usage" Proto.Xai.Api.V1.Usage.SamplingUsage where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ImageResponse'usage
           (\ x__ y__ -> x__ {_ImageResponse'usage = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage)
instance Data.ProtoLens.Field.HasField ImageResponse "maybe'usage" (Prelude.Maybe Proto.Xai.Api.V1.Usage.SamplingUsage) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ImageResponse'usage
           (\ x__ y__ -> x__ {_ImageResponse'usage = y__}))
        Prelude.id
instance Data.ProtoLens.Message ImageResponse where
  messageName _ = Data.Text.pack "xai_api.ImageResponse"
  packedMessageDescriptor _
    = "\n\
      \\rImageResponse\DC2/\n\
      \\ACKimages\CAN\SOH \ETX(\v2\ETB.xai_api.GeneratedImageR\ACKimages\DC2\DC4\n\
      \\ENQmodel\CAN\STX \SOH(\tR\ENQmodel\DC2,\n\
      \\ENQusage\CAN\ETX \SOH(\v2\SYN.xai_api.SamplingUsageR\ENQusage"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        images__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "images"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor GeneratedImage)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Unpacked (Data.ProtoLens.Field.field @"images")) ::
              Data.ProtoLens.FieldDescriptor ImageResponse
        model__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "model"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"model")) ::
              Data.ProtoLens.FieldDescriptor ImageResponse
        usage__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "usage"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor Proto.Xai.Api.V1.Usage.SamplingUsage)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'usage")) ::
              Data.ProtoLens.FieldDescriptor ImageResponse
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, images__field_descriptor),
           (Data.ProtoLens.Tag 2, model__field_descriptor),
           (Data.ProtoLens.Tag 3, usage__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _ImageResponse'_unknownFields
        (\ x__ y__ -> x__ {_ImageResponse'_unknownFields = y__})
  defMessage
    = ImageResponse'_constructor
        {_ImageResponse'images = Data.Vector.Generic.empty,
         _ImageResponse'model = Data.ProtoLens.fieldDefault,
         _ImageResponse'usage = Prelude.Nothing,
         _ImageResponse'_unknownFields = []}
  parseMessage
    = let
        loop ::
          ImageResponse
          -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Vector Data.ProtoLens.Encoding.Growing.RealWorld GeneratedImage
             -> Data.ProtoLens.Encoding.Bytes.Parser ImageResponse
        loop x mutable'images
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do frozen'images <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                         (Data.ProtoLens.Encoding.Growing.unsafeFreeze
                                            mutable'images)
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
                              (Data.ProtoLens.Field.field @"vec'images") frozen'images x))
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                            Data.ProtoLens.Encoding.Bytes.isolate
                                              (Prelude.fromIntegral len)
                                              Data.ProtoLens.parseMessage)
                                        "images"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append mutable'images y)
                                loop x v
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "model"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"model") y x)
                                  mutable'images
                        26
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "usage"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"usage") y x)
                                  mutable'images
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
                                  mutable'images
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do mutable'images <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                  Data.ProtoLens.Encoding.Growing.new
              loop Data.ProtoLens.defMessage mutable'images)
          "ImageResponse"
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
                (Lens.Family2.view (Data.ProtoLens.Field.field @"vec'images") _x))
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
                   (case
                        Lens.Family2.view (Data.ProtoLens.Field.field @"maybe'usage") _x
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
                   (Data.ProtoLens.Encoding.Wire.buildFieldSet
                      (Lens.Family2.view Data.ProtoLens.unknownFields _x))))
instance Control.DeepSeq.NFData ImageResponse where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_ImageResponse'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_ImageResponse'images x__)
                (Control.DeepSeq.deepseq
                   (_ImageResponse'model x__)
                   (Control.DeepSeq.deepseq (_ImageResponse'usage x__) ())))
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Image_Fields.imageUrl' @:: Lens' ImageUrlContent Data.Text.Text@
         * 'Proto.Xai.Api.V1.Image_Fields.detail' @:: Lens' ImageUrlContent ImageDetail@ -}
data ImageUrlContent
  = ImageUrlContent'_constructor {_ImageUrlContent'imageUrl :: !Data.Text.Text,
                                  _ImageUrlContent'detail :: !ImageDetail,
                                  _ImageUrlContent'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show ImageUrlContent where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField ImageUrlContent "imageUrl" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ImageUrlContent'imageUrl
           (\ x__ y__ -> x__ {_ImageUrlContent'imageUrl = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField ImageUrlContent "detail" ImageDetail where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ImageUrlContent'detail
           (\ x__ y__ -> x__ {_ImageUrlContent'detail = y__}))
        Prelude.id
instance Data.ProtoLens.Message ImageUrlContent where
  messageName _ = Data.Text.pack "xai_api.ImageUrlContent"
  packedMessageDescriptor _
    = "\n\
      \\SIImageUrlContent\DC2\ESC\n\
      \\timage_url\CAN\SOH \SOH(\tR\bimageUrl\DC2,\n\
      \\ACKdetail\CAN\STX \SOH(\SO2\DC4.xai_api.ImageDetailR\ACKdetail"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        imageUrl__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "image_url"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"imageUrl")) ::
              Data.ProtoLens.FieldDescriptor ImageUrlContent
        detail__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "detail"
              (Data.ProtoLens.ScalarField Data.ProtoLens.EnumField ::
                 Data.ProtoLens.FieldTypeDescriptor ImageDetail)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"detail")) ::
              Data.ProtoLens.FieldDescriptor ImageUrlContent
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, imageUrl__field_descriptor),
           (Data.ProtoLens.Tag 2, detail__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _ImageUrlContent'_unknownFields
        (\ x__ y__ -> x__ {_ImageUrlContent'_unknownFields = y__})
  defMessage
    = ImageUrlContent'_constructor
        {_ImageUrlContent'imageUrl = Data.ProtoLens.fieldDefault,
         _ImageUrlContent'detail = Data.ProtoLens.fieldDefault,
         _ImageUrlContent'_unknownFields = []}
  parseMessage
    = let
        loop ::
          ImageUrlContent
          -> Data.ProtoLens.Encoding.Bytes.Parser ImageUrlContent
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
                                       "image_url"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"imageUrl") y x)
                        16
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.toEnum
                                          (Prelude.fmap
                                             Prelude.fromIntegral
                                             Data.ProtoLens.Encoding.Bytes.getVarInt))
                                       "detail"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"detail") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "ImageUrlContent"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v = Lens.Family2.view (Data.ProtoLens.Field.field @"imageUrl") _x
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
                   _v = Lens.Family2.view (Data.ProtoLens.Field.field @"detail") _x
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
                (Data.ProtoLens.Encoding.Wire.buildFieldSet
                   (Lens.Family2.view Data.ProtoLens.unknownFields _x)))
instance Control.DeepSeq.NFData ImageUrlContent where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_ImageUrlContent'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_ImageUrlContent'imageUrl x__)
                (Control.DeepSeq.deepseq (_ImageUrlContent'detail x__) ()))
data Image = Image {}
instance Data.ProtoLens.Service.Types.Service Image where
  type ServiceName Image = "Image"
  type ServicePackage Image = "xai_api"
  type ServiceMethods Image = '["generateImage"]
  packedServiceDescriptor _
    = "\n\
      \\ENQImage\DC2H\n\
      \\rGenerateImage\DC2\GS.xai_api.GenerateImageRequest\SUB\SYN.xai_api.ImageResponse\"\NUL"
instance Data.ProtoLens.Service.Types.HasMethodImpl Image "generateImage" where
  type MethodName Image "generateImage" = "GenerateImage"
  type MethodInput Image "generateImage" = GenerateImageRequest
  type MethodOutput Image "generateImage" = ImageResponse
  type MethodStreamingType Image "generateImage" = 'Data.ProtoLens.Service.Types.NonStreaming
packedFileDescriptor :: Data.ByteString.ByteString
packedFileDescriptor
  = "\n\
    \\SYNxai/api/v1/image.proto\DC2\axai_api\SUB\SYNxai/api/v1/usage.proto\"\169\ETX\n\
    \\DC4GenerateImageRequest\DC2\SYN\n\
    \\ACKprompt\CAN\SOH \SOH(\tR\ACKprompt\DC2.\n\
    \\ENQimage\CAN\ENQ \SOH(\v2\CAN.xai_api.ImageUrlContentR\ENQimage\DC2\DC4\n\
    \\ENQmodel\CAN\STX \SOH(\tR\ENQmodel\DC2\DC1\n\
    \\SOHn\CAN\ETX \SOH(\ENQH\NULR\SOHn\136\SOH\SOH\DC2\DC2\n\
    \\EOTuser\CAN\EOT \SOH(\tR\EOTuser\DC2,\n\
    \\ACKformat\CAN\v \SOH(\SO2\DC4.xai_api.ImageFormatR\ACKformat\DC2A\n\
    \\faspect_ratio\CAN\SO \SOH(\SO2\EM.xai_api.ImageAspectRatioH\SOHR\vaspectRatio\136\SOH\SOH\DC2=\n\
    \\n\
    \resolution\CAN\SI \SOH(\SO2\CAN.xai_api.ImageResolutionH\STXR\n\
    \resolution\136\SOH\SOH\DC20\n\
    \\ACKimages\CAN\DC1 \ETX(\v2\CAN.xai_api.ImageUrlContentR\ACKimagesB\EOT\n\
    \\STX_nB\SI\n\
    \\r_aspect_ratioB\r\n\
    \\v_resolutionJ\EOT\b\r\DLE\SO\"\132\SOH\n\
    \\rImageResponse\DC2/\n\
    \\ACKimages\CAN\SOH \ETX(\v2\ETB.xai_api.GeneratedImageR\ACKimages\DC2\DC4\n\
    \\ENQmodel\CAN\STX \SOH(\tR\ENQmodel\DC2,\n\
    \\ENQusage\CAN\ETX \SOH(\v2\SYN.xai_api.SamplingUsageR\ENQusage\"|\n\
    \\SOGeneratedImage\DC2\CAN\n\
    \\ACKbase64\CAN\SOH \SOH(\tH\NULR\ACKbase64\DC2\DC2\n\
    \\ETXurl\CAN\ETX \SOH(\tH\NULR\ETXurl\DC2-\n\
    \\DC2respect_moderation\CAN\EOT \SOH(\bR\DC1respectModerationB\a\n\
    \\ENQimageJ\EOT\b\STX\DLE\ETX\"\\\n\
    \\SIImageUrlContent\DC2\ESC\n\
    \\timage_url\CAN\SOH \SOH(\tR\bimageUrl\DC2,\n\
    \\ACKdetail\CAN\STX \SOH(\SO2\DC4.xai_api.ImageDetailR\ACKdetail*S\n\
    \\vImageDetail\DC2\DC2\n\
    \\SODETAIL_INVALID\DLE\NUL\DC2\SI\n\
    \\vDETAIL_AUTO\DLE\SOH\DC2\SO\n\
    \\n\
    \DETAIL_LOW\DLE\STX\DC2\SI\n\
    \\vDETAIL_HIGH\DLE\ETX*P\n\
    \\vImageFormat\DC2\SYN\n\
    \\DC2IMG_FORMAT_INVALID\DLE\NUL\DC2\NAK\n\
    \\DC1IMG_FORMAT_BASE64\DLE\SOH\DC2\DC2\n\
    \\SOIMG_FORMAT_URL\DLE\STX*j\n\
    \\fImageQuality\DC2\ETB\n\
    \\DC3IMG_QUALITY_INVALID\DLE\NUL\DC2\DC3\n\
    \\SIIMG_QUALITY_LOW\DLE\SOH\DC2\SYN\n\
    \\DC2IMG_QUALITY_MEDIUM\DLE\STX\DC2\DC4\n\
    \\DLEIMG_QUALITY_HIGH\DLE\ETX*\167\ETX\n\
    \\DLEImageAspectRatio\DC2\FS\n\
    \\CANIMG_ASPECT_RATIO_INVALID\DLE\NUL\DC2\CAN\n\
    \\DC4IMG_ASPECT_RATIO_1_1\DLE\SOH\DC2\CAN\n\
    \\DC4IMG_ASPECT_RATIO_3_4\DLE\STX\DC2\CAN\n\
    \\DC4IMG_ASPECT_RATIO_4_3\DLE\ETX\DC2\EM\n\
    \\NAKIMG_ASPECT_RATIO_9_16\DLE\EOT\DC2\EM\n\
    \\NAKIMG_ASPECT_RATIO_16_9\DLE\ENQ\DC2\CAN\n\
    \\DC4IMG_ASPECT_RATIO_2_3\DLE\ACK\DC2\CAN\n\
    \\DC4IMG_ASPECT_RATIO_3_2\DLE\a\DC2\EM\n\
    \\NAKIMG_ASPECT_RATIO_AUTO\DLE\b\DC2\ESC\n\
    \\ETBIMG_ASPECT_RATIO_9_19_5\DLE\t\DC2\ESC\n\
    \\ETBIMG_ASPECT_RATIO_19_5_9\DLE\n\
    \\DC2\EM\n\
    \\NAKIMG_ASPECT_RATIO_9_20\DLE\v\DC2\EM\n\
    \\NAKIMG_ASPECT_RATIO_20_9\DLE\f\DC2\CAN\n\
    \\DC4IMG_ASPECT_RATIO_1_2\DLE\r\DC2\CAN\n\
    \\DC4IMG_ASPECT_RATIO_2_1\DLE\SO*[\n\
    \\SIImageResolution\DC2\SUB\n\
    \\SYNIMG_RESOLUTION_INVALID\DLE\NUL\DC2\NAK\n\
    \\DC1IMG_RESOLUTION_1K\DLE\SOH\DC2\NAK\n\
    \\DC1IMG_RESOLUTION_2K\DLE\STX2Q\n\
    \\ENQImage\DC2H\n\
    \\rGenerateImage\DC2\GS.xai_api.GenerateImageRequest\SUB\SYN.xai_api.ImageResponse\"\NULJ\217:\n\
    \\a\DC2\ENQ\NUL\NUL\215\SOH\SOH\n\
    \\b\n\
    \\SOH\f\DC2\ETX\NUL\NUL\DC2\n\
    \\b\n\
    \\SOH\STX\DC2\ETX\STX\NUL\DLE\n\
    \\t\n\
    \\STX\ETX\NUL\DC2\ETX\EOT\NUL \n\
    \J\n\
    \\STX\ACK\NUL\DC2\EOT\a\NUL\n\
    \\SOH\SUB> An API service for interaction with image generation models.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\ACK\NUL\SOH\DC2\ETX\a\b\r\n\
    \S\n\
    \\EOT\ACK\NUL\STX\NUL\DC2\ETX\t\STXD\SUBF Create an image based on a text prompt and optionally another image.\n\
    \\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\NUL\SOH\DC2\ETX\t\ACK\DC3\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\NUL\STX\DC2\ETX\t\DC4(\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\NUL\ETX\DC2\ETX\t3@\n\
    \6\n\
    \\STX\EOT\NUL\DC2\EOT\r\NUL7\SOH\SUB* Request message for generating an image.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\EOT\NUL\SOH\DC2\ETX\r\b\FS\n\
    \\n\
    \\n\
    \\ETX\EOT\NUL\t\DC2\ETX\SO\STX\SO\n\
    \\v\n\
    \\EOT\EOT\NUL\t\NUL\DC2\ETX\SO\v\r\n\
    \\f\n\
    \\ENQ\EOT\NUL\t\NUL\SOH\DC2\ETX\SO\v\r\n\
    \\f\n\
    \\ENQ\EOT\NUL\t\NUL\STX\DC2\ETX\SO\v\r\n\
    \6\n\
    \\EOT\EOT\NUL\STX\NUL\DC2\ETX\DC1\STX\DC4\SUB) Input prompt to generate an image from.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\ENQ\DC2\ETX\DC1\STX\b\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\SOH\DC2\ETX\DC1\t\SI\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\ETX\DC2\ETX\DC1\DC2\DC3\n\
    \D\n\
    \\EOT\EOT\NUL\STX\SOH\DC2\ETX\DC4\STX\FS\SUB7 Optional input image to perform generations based on.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\SOH\ACK\DC2\ETX\DC4\STX\DC1\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\SOH\SOH\DC2\ETX\DC4\DC2\ETB\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\SOH\ETX\DC2\ETX\DC4\SUB\ESC\n\
    \F\n\
    \\EOT\EOT\NUL\STX\STX\DC2\ETX\ETB\STX\DC3\SUB9 Name or alias of the image generation model to be used.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\STX\ENQ\DC2\ETX\ETB\STX\b\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\STX\SOH\DC2\ETX\ETB\t\SO\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\STX\ETX\DC2\ETX\ETB\DC1\DC2\n\
    \H\n\
    \\EOT\EOT\NUL\STX\ETX\DC2\ETX\SUB\STX\ETB\SUB; Number of images to generate. Allowed values are [1, 10].\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ETX\EOT\DC2\ETX\SUB\STX\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ETX\ENQ\DC2\ETX\SUB\v\DLE\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ETX\SOH\DC2\ETX\SUB\DC1\DC2\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ETX\ETX\DC2\ETX\SUB\NAK\SYN\n\
    \\205\SOH\n\
    \\EOT\EOT\NUL\STX\EOT\DC2\ETX\US\STX\DC2\SUB\191\SOH An opaque string supplied by the API client (customer) to identify a user.\n\
    \ The string will be stored in the logs and can be used in customer service\n\
    \ requests to identify certain requests.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\EOT\ENQ\DC2\ETX\US\STX\b\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\EOT\SOH\DC2\ETX\US\t\r\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\EOT\ETX\DC2\ETX\US\DLE\DC1\n\
    \\129\SOH\n\
    \\EOT\EOT\NUL\STX\ENQ\DC2\ETX#\STX\SUB\SUBt Optional field to specify the image format to return the generated image(s)\n\
    \ in. See ImageFormat enum for options.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ENQ\ACK\DC2\ETX#\STX\r\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ENQ\SOH\DC2\ETX#\SO\DC4\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ENQ\ETX\DC2\ETX#\ETB\EM\n\
    \\214\SOH\n\
    \\EOT\EOT\NUL\STX\ACK\DC2\ETX)\STX.\SUB\200\SOH Optional aspect ratio for image generation/editing.\n\
    \ Only supported by grok-imagine models.\n\
    \ Defaults to 1:1 if not specified. Auto is only supported for image generation\n\
    \ with a thinking upsampler.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ACK\EOT\DC2\ETX)\STX\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ACK\ACK\DC2\ETX)\v\ESC\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ACK\SOH\DC2\ETX)\FS(\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ACK\ETX\DC2\ETX)+-\n\
    \\250\STX\n\
    \\EOT\EOT\NUL\STX\a\DC2\ETX1\STX+\SUB\236\STX Optional resolution for image generation/editing.\n\
    \ Only supported by grok-imagine models.\n\
    \ Defaults to 1k if not specified.\n\
    \ When 2k is selected, the image is generated at 1k and upscaled using super-resolution.\n\
    \ The final output area is capped at approximately 2048x2048 pixels, with dimensions\n\
    \ adjusted to preserve aspect ratio and rounded to multiples of 16.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\a\EOT\DC2\ETX1\STX\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\a\ACK\DC2\ETX1\v\SUB\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\a\SOH\DC2\ETX1\ESC%\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\a\ETX\DC2\ETX1(*\n\
    \\216\SOH\n\
    \\EOT\EOT\NUL\STX\b\DC2\ETX6\STX'\SUB\202\SOH Optional list of input images for multi-reference image editing.\n\
    \ Each image is either an image URL or a base64-encoded version of the image.\n\
    \ This field cannot be set together with the `image` field.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\b\EOT\DC2\ETX6\STX\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\b\ACK\DC2\ETX6\v\SUB\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\b\SOH\DC2\ETX6\ESC!\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\b\ETX\DC2\ETX6$&\n\
    \^\n\
    \\STX\EOT\SOH\DC2\EOT:\NULC\SOH\SUBR The response from the image generation models containing the generated image(s).\n\
    \\n\
    \\n\
    \\n\
    \\ETX\EOT\SOH\SOH\DC2\ETX:\b\NAK\n\
    \H\n\
    \\EOT\EOT\SOH\STX\NUL\DC2\ETX<\STX%\SUB; A list of generated images (including relevant metadata).\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\EOT\DC2\ETX<\STX\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\ACK\DC2\ETX<\v\EM\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\SOH\DC2\ETX<\SUB \n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\ETX\DC2\ETX<#$\n\
    \G\n\
    \\EOT\EOT\SOH\STX\SOH\DC2\ETX?\STX\DC3\SUB: The model used to generate the image (ignoring aliases).\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\SOH\ENQ\DC2\ETX?\STX\b\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\SOH\SOH\DC2\ETX?\t\SO\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\SOH\ETX\DC2\ETX?\DC1\DC2\n\
    \(\n\
    \\EOT\EOT\SOH\STX\STX\DC2\ETXB\STX\SUB\SUB\ESC The usage of the request.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\STX\ACK\DC2\ETXB\STX\SI\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\STX\SOH\DC2\ETXB\DLE\NAK\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\STX\ETX\DC2\ETXB\CAN\EM\n\
    \=\n\
    \\STX\EOT\STX\DC2\EOTF\NULX\SOH\SUB1 Contains all data related to a generated image.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\EOT\STX\SOH\DC2\ETXF\b\SYN\n\
    \\n\
    \\n\
    \\ETX\EOT\STX\t\DC2\ETXG\STX\r\n\
    \\v\n\
    \\EOT\EOT\STX\t\NUL\DC2\ETXG\v\f\n\
    \\f\n\
    \\ENQ\EOT\STX\t\NUL\SOH\DC2\ETXG\v\f\n\
    \\f\n\
    \\ENQ\EOT\STX\t\NUL\STX\DC2\ETXG\v\f\n\
    \$\n\
    \\EOT\EOT\STX\b\NUL\DC2\EOTJ\STXR\ETX\SUB\SYN The generated image.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\STX\b\NUL\SOH\DC2\ETXJ\b\r\n\
    \\159\SOH\n\
    \\EOT\EOT\STX\STX\NUL\DC2\ETXM\EOT\SYN\SUB\145\SOH A base-64 encoded string of the image. Provided if user specified `IMG_FORMAT_BASE64` in `format` field of the\n\
    \ `GenerateImageRequest` message.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\NUL\ENQ\DC2\ETXM\EOT\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\NUL\SOH\DC2\ETXM\v\DC1\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\NUL\ETX\DC2\ETXM\DC4\NAK\n\
    \\159\SOH\n\
    \\EOT\EOT\STX\STX\SOH\DC2\ETXQ\EOT\DC3\SUB\145\SOH A url that points to the generated image. Provided if user specified `IMG_FORMAT_URL` in `format` field of the\n\
    \ `GenerateImageRequest` message.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\SOH\ENQ\DC2\ETXQ\EOT\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\SOH\SOH\DC2\ETXQ\v\SO\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\SOH\ETX\DC2\ETXQ\DC1\DC2\n\
    \\231\SOH\n\
    \\EOT\EOT\STX\STX\STX\DC2\ETXW\STX\RS\SUB\217\SOH Whether the image generated by the model respects moderation rules.\n\
    \ The field will be true if the image respect moderation rules. Otherwise\n\
    \ the field will be false and the image field is replaced by a placeholder.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\STX\ENQ\DC2\ETXW\STX\ACK\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\STX\SOH\DC2\ETXW\a\EM\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\STX\ETX\DC2\ETXW\FS\GS\n\
    \O\n\
    \\STX\EOT\ETX\DC2\EOT[\NULg\SOH\SUBC Contains data relating to an image that is provided to the model.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\EOT\ETX\SOH\DC2\ETX[\b\ETB\n\
    \\195\ETX\n\
    \\EOT\EOT\ETX\STX\NUL\DC2\ETXc\STX\ETB\SUB\181\ETX This is either an image URL or a base64-encoded version of the image.\n\
    \ The following image formats are supported: PNG, JPG, and WebP.\n\
    \ If an image URL is provided, the image will be downloaded for every API\n\
    \ request without being cached. Images are fetched using\n\
    \ \"XaiImageApiFetch/1.0\" user agent, and will timeout after 5 seconds.\n\
    \ The image size is limited to 10 MiB. If the image download fails, the API\n\
    \ request will fail as well.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\NUL\ENQ\DC2\ETXc\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\NUL\SOH\DC2\ETXc\t\DC2\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\NUL\ETX\DC2\ETXc\NAK\SYN\n\
    \X\n\
    \\EOT\EOT\ETX\STX\SOH\DC2\ETXf\STX\EM\SUBK The level of pre-processing resolution that will be applied to the image.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\SOH\ACK\DC2\ETXf\STX\r\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\SOH\SOH\DC2\ETXf\SO\DC4\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\SOH\ETX\DC2\ETXf\ETB\CAN\n\
    \e\n\
    \\STX\ENQ\NUL\DC2\EOTk\NULz\SOH\SUBY Indicates the level of preprocessing to apply to images that will be fed to\n\
    \ the model.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\ENQ\NUL\SOH\DC2\ETXk\ENQ\DLE\n\
    \'\n\
    \\EOT\ENQ\NUL\STX\NUL\DC2\ETXm\STX\NAK\SUB\SUB Detail level is invalid.\n\
    \\n\
    \\f\n\
    \\ENQ\ENQ\NUL\STX\NUL\SOH\DC2\ETXm\STX\DLE\n\
    \\f\n\
    \\ENQ\ENQ\NUL\STX\NUL\STX\DC2\ETXm\DC3\DC4\n\
    \B\n\
    \\EOT\ENQ\NUL\STX\SOH\DC2\ETXp\STX\DC2\SUB5 The system will decide the image resolution to use.\n\
    \\n\
    \\f\n\
    \\ENQ\ENQ\NUL\STX\SOH\SOH\DC2\ETXp\STX\r\n\
    \\f\n\
    \\ENQ\ENQ\NUL\STX\SOH\STX\DC2\ETXp\DLE\DC1\n\
    \\134\SOH\n\
    \\EOT\ENQ\NUL\STX\STX\DC2\ETXt\STX\DC1\SUBy The model will process a low-resolution version of the image. This is\n\
    \ faster and cheaper (i.e. consumes fewer tokens).\n\
    \\n\
    \\f\n\
    \\ENQ\ENQ\NUL\STX\STX\SOH\DC2\ETXt\STX\f\n\
    \\f\n\
    \\ENQ\ENQ\NUL\STX\STX\STX\DC2\ETXt\SI\DLE\n\
    \\179\SOH\n\
    \\EOT\ENQ\NUL\STX\ETX\DC2\ETXy\STX\DC2\SUB\165\SOH The model will process a high-resolution of the image. This is slower and\n\
    \ more expensive but will allow the model to attend to more nuanced details\n\
    \ in the image.\n\
    \\n\
    \\f\n\
    \\ENQ\ENQ\NUL\STX\ETX\SOH\DC2\ETXy\STX\r\n\
    \\f\n\
    \\ENQ\ENQ\NUL\STX\ETX\STX\DC2\ETXy\DLE\DC1\n\
    \_\n\
    \\STX\ENQ\SOH\DC2\ENQ~\NUL\135\SOH\SOH\SUBR The image format to be returned (base-64 encoded string or a url of\n\
    \ the image).\n\
    \\n\
    \\n\
    \\n\
    \\ETX\ENQ\SOH\SOH\DC2\ETX~\ENQ\DLE\n\
    \(\n\
    \\EOT\ENQ\SOH\STX\NUL\DC2\EOT\128\SOH\STX\EM\SUB\SUB Image format is invalid.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\SOH\STX\NUL\SOH\DC2\EOT\128\SOH\STX\DC4\n\
    \\r\n\
    \\ENQ\ENQ\SOH\STX\NUL\STX\DC2\EOT\128\SOH\ETB\CAN\n\
    \0\n\
    \\EOT\ENQ\SOH\STX\SOH\DC2\EOT\131\SOH\STX\CAN\SUB\" A base-64 encoding of the image.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\SOH\STX\SOH\SOH\DC2\EOT\131\SOH\STX\DC3\n\
    \\r\n\
    \\ENQ\ENQ\SOH\STX\SOH\STX\DC2\EOT\131\SOH\SYN\ETB\n\
    \@\n\
    \\EOT\ENQ\SOH\STX\STX\DC2\EOT\134\SOH\STX\NAK\SUB2 An URL at which the user can download the image.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\SOH\STX\STX\SOH\DC2\EOT\134\SOH\STX\DLE\n\
    \\r\n\
    \\ENQ\ENQ\SOH\STX\STX\STX\DC2\EOT\134\SOH\DC3\DC4\n\
    \\139\SOH\n\
    \\STX\ENQ\STX\DC2\ACK\139\SOH\NUL\151\SOH\SOH\SUB} Quality levels for image generation with their corresponding resolutions.\n\
    \ Currently only supported by grok-imagine models.\n\
    \\n\
    \\v\n\
    \\ETX\ENQ\STX\SOH\DC2\EOT\139\SOH\ENQ\DC1\n\
    \#\n\
    \\EOT\ENQ\STX\STX\NUL\DC2\EOT\141\SOH\STX\SUB\SUB\NAK Quality is invalid.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\STX\STX\NUL\SOH\DC2\EOT\141\SOH\STX\NAK\n\
    \\r\n\
    \\ENQ\ENQ\STX\STX\NUL\STX\DC2\EOT\141\SOH\CAN\EM\n\
    \\FS\n\
    \\EOT\ENQ\STX\STX\SOH\DC2\EOT\144\SOH\STX\SYN\SUB\SO Low quality.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\STX\STX\SOH\SOH\DC2\EOT\144\SOH\STX\DC1\n\
    \\r\n\
    \\ENQ\ENQ\STX\STX\SOH\STX\DC2\EOT\144\SOH\DC4\NAK\n\
    \*\n\
    \\EOT\ENQ\STX\STX\STX\DC2\EOT\147\SOH\STX\EM\SUB\FS Medium quality: (default).\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\STX\STX\STX\SOH\DC2\EOT\147\SOH\STX\DC4\n\
    \\r\n\
    \\ENQ\ENQ\STX\STX\STX\STX\DC2\EOT\147\SOH\ETB\CAN\n\
    \\GS\n\
    \\EOT\ENQ\STX\STX\ETX\DC2\EOT\150\SOH\STX\ETB\SUB\SI High quality.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\STX\STX\ETX\SOH\DC2\EOT\150\SOH\STX\DC2\n\
    \\r\n\
    \\ENQ\ENQ\STX\STX\ETX\STX\DC2\EOT\150\SOH\NAK\SYN\n\
    \Z\n\
    \\STX\ENQ\ETX\DC2\ACK\155\SOH\NUL\201\SOH\SOH\SUBL Aspect ratio for image generation.\n\
    \ Only supported by grok-imagine models.\n\
    \\n\
    \\v\n\
    \\ETX\ENQ\ETX\SOH\DC2\EOT\155\SOH\ENQ\NAK\n\
    \%\n\
    \\EOT\ENQ\ETX\STX\NUL\DC2\EOT\157\SOH\STX\US\SUB\ETB Invalid aspect ratio.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\ETX\STX\NUL\SOH\DC2\EOT\157\SOH\STX\SUB\n\
    \\r\n\
    \\ENQ\ENQ\ETX\STX\NUL\STX\DC2\EOT\157\SOH\GS\RS\n\
    \*\n\
    \\EOT\ENQ\ETX\STX\SOH\DC2\EOT\160\SOH\STX\ESC\SUB\FS 1:1 aspect ratio (square).\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\ETX\STX\SOH\SOH\DC2\EOT\160\SOH\STX\SYN\n\
    \\r\n\
    \\ENQ\ENQ\ETX\STX\SOH\STX\DC2\EOT\160\SOH\EM\SUB\n\
    \,\n\
    \\EOT\ENQ\ETX\STX\STX\DC2\EOT\163\SOH\STX\ESC\SUB\RS 3:4 aspect ratio (portrait).\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\ETX\STX\STX\SOH\DC2\EOT\163\SOH\STX\SYN\n\
    \\r\n\
    \\ENQ\ENQ\ETX\STX\STX\STX\DC2\EOT\163\SOH\EM\SUB\n\
    \-\n\
    \\EOT\ENQ\ETX\STX\ETX\DC2\EOT\166\SOH\STX\ESC\SUB\US 4:3 aspect ratio (landscape).\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\ETX\STX\ETX\SOH\DC2\EOT\166\SOH\STX\SYN\n\
    \\r\n\
    \\ENQ\ENQ\ETX\STX\ETX\STX\DC2\EOT\166\SOH\EM\SUB\n\
    \2\n\
    \\EOT\ENQ\ETX\STX\EOT\DC2\EOT\169\SOH\STX\FS\SUB$ 9:16 aspect ratio (tall portrait).\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\ETX\STX\EOT\SOH\DC2\EOT\169\SOH\STX\ETB\n\
    \\r\n\
    \\ENQ\ENQ\ETX\STX\EOT\STX\DC2\EOT\169\SOH\SUB\ESC\n\
    \3\n\
    \\EOT\ENQ\ETX\STX\ENQ\DC2\EOT\172\SOH\STX\FS\SUB% 16:9 aspect ratio (wide landscape).\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\ETX\STX\ENQ\SOH\DC2\EOT\172\SOH\STX\ETB\n\
    \\r\n\
    \\ENQ\ENQ\ETX\STX\ENQ\STX\DC2\EOT\172\SOH\SUB\ESC\n\
    \2\n\
    \\EOT\ENQ\ETX\STX\ACK\DC2\EOT\175\SOH\STX\ESC\SUB$ 2:3 aspect ratio (photo portrait).\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\ETX\STX\ACK\SOH\DC2\EOT\175\SOH\STX\SYN\n\
    \\r\n\
    \\ENQ\ENQ\ETX\STX\ACK\STX\DC2\EOT\175\SOH\EM\SUB\n\
    \3\n\
    \\EOT\ENQ\ETX\STX\a\DC2\EOT\178\SOH\STX\ESC\SUB% 3:2 aspect ratio (photo landscape).\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\ETX\STX\a\SOH\DC2\EOT\178\SOH\STX\SYN\n\
    \\r\n\
    \\ENQ\ENQ\ETX\STX\a\STX\DC2\EOT\178\SOH\EM\SUB\n\
    \\135\SOH\n\
    \\EOT\ENQ\ETX\STX\b\DC2\EOT\182\SOH\STX\FS\SUBy Auto aspect ratio (model auto-selects based on prompt).\n\
    \ Only supported for image generation with a thinking upsampler.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\ETX\STX\b\SOH\DC2\EOT\182\SOH\STX\ETB\n\
    \\r\n\
    \\ENQ\ENQ\ETX\STX\b\STX\DC2\EOT\182\SOH\SUB\ESC\n\
    \J\n\
    \\EOT\ENQ\ETX\STX\t\DC2\EOT\185\SOH\STX\RS\SUB< 9:19.5 aspect ratio (extra tall portrait - phone screens).\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\ETX\STX\t\SOH\DC2\EOT\185\SOH\STX\EM\n\
    \\r\n\
    \\ENQ\ENQ\ETX\STX\t\STX\DC2\EOT\185\SOH\FS\GS\n\
    \;\n\
    \\EOT\ENQ\ETX\STX\n\
    \\DC2\EOT\188\SOH\STX\US\SUB- 19.5:9 aspect ratio (extra wide landscape).\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\ETX\STX\n\
    \\SOH\DC2\EOT\188\SOH\STX\EM\n\
    \\r\n\
    \\ENQ\ENQ\ETX\STX\n\
    \\STX\DC2\EOT\188\SOH\FS\RS\n\
    \I\n\
    \\EOT\ENQ\ETX\STX\v\DC2\EOT\191\SOH\STX\GS\SUB; 9:20 aspect ratio (tall portrait - modern phone screens).\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\ETX\STX\v\SOH\DC2\EOT\191\SOH\STX\ETB\n\
    \\r\n\
    \\ENQ\ENQ\ETX\STX\v\STX\DC2\EOT\191\SOH\SUB\FS\n\
    \9\n\
    \\EOT\ENQ\ETX\STX\f\DC2\EOT\194\SOH\STX\GS\SUB+ 20:9 aspect ratio (ultra wide landscape).\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\ETX\STX\f\SOH\DC2\EOT\194\SOH\STX\ETB\n\
    \\r\n\
    \\ENQ\ENQ\ETX\STX\f\STX\DC2\EOT\194\SOH\SUB\FS\n\
    \1\n\
    \\EOT\ENQ\ETX\STX\r\DC2\EOT\197\SOH\STX\FS\SUB# 1:2 aspect ratio (tall portrait).\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\ETX\STX\r\SOH\DC2\EOT\197\SOH\STX\SYN\n\
    \\r\n\
    \\ENQ\ENQ\ETX\STX\r\STX\DC2\EOT\197\SOH\EM\ESC\n\
    \2\n\
    \\EOT\ENQ\ETX\STX\SO\DC2\EOT\200\SOH\STX\FS\SUB$ 2:1 aspect ratio (wide landscape).\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\ETX\STX\SO\SOH\DC2\EOT\200\SOH\STX\SYN\n\
    \\r\n\
    \\ENQ\ENQ\ETX\STX\SO\STX\DC2\EOT\200\SOH\EM\ESC\n\
    \X\n\
    \\STX\ENQ\EOT\DC2\ACK\205\SOH\NUL\215\SOH\SOH\SUBJ Resolution for image generation.\n\
    \ Only supported by grok-imagine models.\n\
    \\n\
    \\v\n\
    \\ETX\ENQ\EOT\SOH\DC2\EOT\205\SOH\ENQ\DC4\n\
    \#\n\
    \\EOT\ENQ\EOT\STX\NUL\DC2\EOT\207\SOH\STX\GS\SUB\NAK Invalid resolution.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\EOT\STX\NUL\SOH\DC2\EOT\207\SOH\STX\CAN\n\
    \\r\n\
    \\ENQ\ENQ\EOT\STX\NUL\STX\DC2\EOT\207\SOH\ESC\FS\n\
    \U\n\
    \\EOT\ENQ\EOT\STX\SOH\DC2\EOT\211\SOH\STX\CAN\SUBG 1k resolution (~1 megapixel total).\n\
    \ Dimensions vary by aspect ratio.\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\EOT\STX\SOH\SOH\DC2\EOT\211\SOH\STX\DC3\n\
    \\r\n\
    \\ENQ\ENQ\EOT\STX\SOH\STX\DC2\EOT\211\SOH\SYN\ETB\n\
    \3\n\
    \\EOT\ENQ\EOT\STX\STX\DC2\EOT\214\SOH\STX\CAN\SUB% 2k resolution (~4 megapixel total).\n\
    \\n\
    \\r\n\
    \\ENQ\ENQ\EOT\STX\STX\SOH\DC2\EOT\214\SOH\STX\DC3\n\
    \\r\n\
    \\ENQ\ENQ\EOT\STX\STX\STX\DC2\EOT\214\SOH\SYN\ETBb\ACKproto3"