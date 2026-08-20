{- This file was auto-generated from xai/api/v1/image.proto by the proto-lens-protoc program. -}
{-# LANGUAGE ScopedTypeVariables, DataKinds, TypeFamilies, UndecidableInstances, GeneralizedNewtypeDeriving, MultiParamTypeClasses, FlexibleContexts, FlexibleInstances, PatternSynonyms, MagicHash, NoImplicitPrelude, DataKinds, BangPatterns, TypeApplications, OverloadedStrings, DerivingStrategies#-}
{-# OPTIONS_GHC -Wno-unused-imports#-}
{-# OPTIONS_GHC -Wno-duplicate-exports#-}
{-# OPTIONS_GHC -Wno-dodgy-exports#-}
module Proto.Xai.Api.V1.Image_Fields where
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
aspectRatio ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "aspectRatio" a) =>
  Lens.Family2.LensLike' f s a
aspectRatio = Data.ProtoLens.Field.field @"aspectRatio"
base64 ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "base64" a) =>
  Lens.Family2.LensLike' f s a
base64 = Data.ProtoLens.Field.field @"base64"
detail ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "detail" a) =>
  Lens.Family2.LensLike' f s a
detail = Data.ProtoLens.Field.field @"detail"
format ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "format" a) =>
  Lens.Family2.LensLike' f s a
format = Data.ProtoLens.Field.field @"format"
image ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "image" a) =>
  Lens.Family2.LensLike' f s a
image = Data.ProtoLens.Field.field @"image"
imageUrl ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "imageUrl" a) =>
  Lens.Family2.LensLike' f s a
imageUrl = Data.ProtoLens.Field.field @"imageUrl"
images ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "images" a) =>
  Lens.Family2.LensLike' f s a
images = Data.ProtoLens.Field.field @"images"
maybe'aspectRatio ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'aspectRatio" a) =>
  Lens.Family2.LensLike' f s a
maybe'aspectRatio = Data.ProtoLens.Field.field @"maybe'aspectRatio"
maybe'base64 ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'base64" a) =>
  Lens.Family2.LensLike' f s a
maybe'base64 = Data.ProtoLens.Field.field @"maybe'base64"
maybe'image ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'image" a) =>
  Lens.Family2.LensLike' f s a
maybe'image = Data.ProtoLens.Field.field @"maybe'image"
maybe'n ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "maybe'n" a) =>
  Lens.Family2.LensLike' f s a
maybe'n = Data.ProtoLens.Field.field @"maybe'n"
maybe'resolution ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'resolution" a) =>
  Lens.Family2.LensLike' f s a
maybe'resolution = Data.ProtoLens.Field.field @"maybe'resolution"
maybe'url ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'url" a) =>
  Lens.Family2.LensLike' f s a
maybe'url = Data.ProtoLens.Field.field @"maybe'url"
maybe'usage ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'usage" a) =>
  Lens.Family2.LensLike' f s a
maybe'usage = Data.ProtoLens.Field.field @"maybe'usage"
model ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "model" a) =>
  Lens.Family2.LensLike' f s a
model = Data.ProtoLens.Field.field @"model"
n ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "n" a) =>
  Lens.Family2.LensLike' f s a
n = Data.ProtoLens.Field.field @"n"
prompt ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "prompt" a) =>
  Lens.Family2.LensLike' f s a
prompt = Data.ProtoLens.Field.field @"prompt"
resolution ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "resolution" a) =>
  Lens.Family2.LensLike' f s a
resolution = Data.ProtoLens.Field.field @"resolution"
respectModeration ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "respectModeration" a) =>
  Lens.Family2.LensLike' f s a
respectModeration = Data.ProtoLens.Field.field @"respectModeration"
url ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "url" a) =>
  Lens.Family2.LensLike' f s a
url = Data.ProtoLens.Field.field @"url"
usage ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "usage" a) =>
  Lens.Family2.LensLike' f s a
usage = Data.ProtoLens.Field.field @"usage"
user ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "user" a) =>
  Lens.Family2.LensLike' f s a
user = Data.ProtoLens.Field.field @"user"
vec'images ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "vec'images" a) =>
  Lens.Family2.LensLike' f s a
vec'images = Data.ProtoLens.Field.field @"vec'images"