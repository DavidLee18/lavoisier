{- This file was auto-generated from xai/api/v1/sample.proto by the proto-lens-protoc program. -}
{-# LANGUAGE ScopedTypeVariables, DataKinds, TypeFamilies, UndecidableInstances, GeneralizedNewtypeDeriving, MultiParamTypeClasses, FlexibleContexts, FlexibleInstances, PatternSynonyms, MagicHash, NoImplicitPrelude, DataKinds, BangPatterns, TypeApplications, OverloadedStrings, DerivingStrategies#-}
{-# OPTIONS_GHC -Wno-unused-imports#-}
{-# OPTIONS_GHC -Wno-duplicate-exports#-}
{-# OPTIONS_GHC -Wno-dodgy-exports#-}
module Proto.Xai.Api.V1.Sample_Fields where
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
choices ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "choices" a) =>
  Lens.Family2.LensLike' f s a
choices = Data.ProtoLens.Field.field @"choices"
created ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "created" a) =>
  Lens.Family2.LensLike' f s a
created = Data.ProtoLens.Field.field @"created"
finishReason ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "finishReason" a) =>
  Lens.Family2.LensLike' f s a
finishReason = Data.ProtoLens.Field.field @"finishReason"
frequencyPenalty ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "frequencyPenalty" a) =>
  Lens.Family2.LensLike' f s a
frequencyPenalty = Data.ProtoLens.Field.field @"frequencyPenalty"
id ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "id" a) =>
  Lens.Family2.LensLike' f s a
id = Data.ProtoLens.Field.field @"id"
index ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "index" a) =>
  Lens.Family2.LensLike' f s a
index = Data.ProtoLens.Field.field @"index"
logprobs ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "logprobs" a) =>
  Lens.Family2.LensLike' f s a
logprobs = Data.ProtoLens.Field.field @"logprobs"
maxTokens ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maxTokens" a) =>
  Lens.Family2.LensLike' f s a
maxTokens = Data.ProtoLens.Field.field @"maxTokens"
maybe'created ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'created" a) =>
  Lens.Family2.LensLike' f s a
maybe'created = Data.ProtoLens.Field.field @"maybe'created"
maybe'frequencyPenalty ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'frequencyPenalty" a) =>
  Lens.Family2.LensLike' f s a
maybe'frequencyPenalty
  = Data.ProtoLens.Field.field @"maybe'frequencyPenalty"
maybe'maxTokens ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'maxTokens" a) =>
  Lens.Family2.LensLike' f s a
maybe'maxTokens = Data.ProtoLens.Field.field @"maybe'maxTokens"
maybe'n ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "maybe'n" a) =>
  Lens.Family2.LensLike' f s a
maybe'n = Data.ProtoLens.Field.field @"maybe'n"
maybe'presencePenalty ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'presencePenalty" a) =>
  Lens.Family2.LensLike' f s a
maybe'presencePenalty
  = Data.ProtoLens.Field.field @"maybe'presencePenalty"
maybe'seed ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'seed" a) =>
  Lens.Family2.LensLike' f s a
maybe'seed = Data.ProtoLens.Field.field @"maybe'seed"
maybe'temperature ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'temperature" a) =>
  Lens.Family2.LensLike' f s a
maybe'temperature = Data.ProtoLens.Field.field @"maybe'temperature"
maybe'topLogprobs ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'topLogprobs" a) =>
  Lens.Family2.LensLike' f s a
maybe'topLogprobs = Data.ProtoLens.Field.field @"maybe'topLogprobs"
maybe'topP ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'topP" a) =>
  Lens.Family2.LensLike' f s a
maybe'topP = Data.ProtoLens.Field.field @"maybe'topP"
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
presencePenalty ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "presencePenalty" a) =>
  Lens.Family2.LensLike' f s a
presencePenalty = Data.ProtoLens.Field.field @"presencePenalty"
prompt ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "prompt" a) =>
  Lens.Family2.LensLike' f s a
prompt = Data.ProtoLens.Field.field @"prompt"
seed ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "seed" a) =>
  Lens.Family2.LensLike' f s a
seed = Data.ProtoLens.Field.field @"seed"
stop ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "stop" a) =>
  Lens.Family2.LensLike' f s a
stop = Data.ProtoLens.Field.field @"stop"
systemFingerprint ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "systemFingerprint" a) =>
  Lens.Family2.LensLike' f s a
systemFingerprint = Data.ProtoLens.Field.field @"systemFingerprint"
temperature ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "temperature" a) =>
  Lens.Family2.LensLike' f s a
temperature = Data.ProtoLens.Field.field @"temperature"
text ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "text" a) =>
  Lens.Family2.LensLike' f s a
text = Data.ProtoLens.Field.field @"text"
topLogprobs ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "topLogprobs" a) =>
  Lens.Family2.LensLike' f s a
topLogprobs = Data.ProtoLens.Field.field @"topLogprobs"
topP ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "topP" a) =>
  Lens.Family2.LensLike' f s a
topP = Data.ProtoLens.Field.field @"topP"
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
vec'choices ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "vec'choices" a) =>
  Lens.Family2.LensLike' f s a
vec'choices = Data.ProtoLens.Field.field @"vec'choices"
vec'prompt ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "vec'prompt" a) =>
  Lens.Family2.LensLike' f s a
vec'prompt = Data.ProtoLens.Field.field @"vec'prompt"
vec'stop ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "vec'stop" a) =>
  Lens.Family2.LensLike' f s a
vec'stop = Data.ProtoLens.Field.field @"vec'stop"