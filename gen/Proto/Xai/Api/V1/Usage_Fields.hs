{- This file was auto-generated from xai/api/v1/usage.proto by the proto-lens-protoc program. -}
{-# LANGUAGE ScopedTypeVariables, DataKinds, TypeFamilies, UndecidableInstances, GeneralizedNewtypeDeriving, MultiParamTypeClasses, FlexibleContexts, FlexibleInstances, PatternSynonyms, MagicHash, NoImplicitPrelude, DataKinds, BangPatterns, TypeApplications, OverloadedStrings, DerivingStrategies#-}
{-# OPTIONS_GHC -Wno-unused-imports#-}
{-# OPTIONS_GHC -Wno-duplicate-exports#-}
{-# OPTIONS_GHC -Wno-dodgy-exports#-}
module Proto.Xai.Api.V1.Usage_Fields where
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
cachedPromptTextTokens ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "cachedPromptTextTokens" a) =>
  Lens.Family2.LensLike' f s a
cachedPromptTextTokens
  = Data.ProtoLens.Field.field @"cachedPromptTextTokens"
completionTokens ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "completionTokens" a) =>
  Lens.Family2.LensLike' f s a
completionTokens = Data.ProtoLens.Field.field @"completionTokens"
costInUsdTicks ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "costInUsdTicks" a) =>
  Lens.Family2.LensLike' f s a
costInUsdTicks = Data.ProtoLens.Field.field @"costInUsdTicks"
maybe'costInUsdTicks ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'costInUsdTicks" a) =>
  Lens.Family2.LensLike' f s a
maybe'costInUsdTicks
  = Data.ProtoLens.Field.field @"maybe'costInUsdTicks"
numImageEmbeddings ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "numImageEmbeddings" a) =>
  Lens.Family2.LensLike' f s a
numImageEmbeddings
  = Data.ProtoLens.Field.field @"numImageEmbeddings"
numSourcesUsed ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "numSourcesUsed" a) =>
  Lens.Family2.LensLike' f s a
numSourcesUsed = Data.ProtoLens.Field.field @"numSourcesUsed"
numTextEmbeddings ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "numTextEmbeddings" a) =>
  Lens.Family2.LensLike' f s a
numTextEmbeddings = Data.ProtoLens.Field.field @"numTextEmbeddings"
promptImageTokens ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "promptImageTokens" a) =>
  Lens.Family2.LensLike' f s a
promptImageTokens = Data.ProtoLens.Field.field @"promptImageTokens"
promptTextTokens ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "promptTextTokens" a) =>
  Lens.Family2.LensLike' f s a
promptTextTokens = Data.ProtoLens.Field.field @"promptTextTokens"
promptTokens ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "promptTokens" a) =>
  Lens.Family2.LensLike' f s a
promptTokens = Data.ProtoLens.Field.field @"promptTokens"
reasoningTokens ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "reasoningTokens" a) =>
  Lens.Family2.LensLike' f s a
reasoningTokens = Data.ProtoLens.Field.field @"reasoningTokens"
serverSideToolsUsed ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "serverSideToolsUsed" a) =>
  Lens.Family2.LensLike' f s a
serverSideToolsUsed
  = Data.ProtoLens.Field.field @"serverSideToolsUsed"
totalTokens ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "totalTokens" a) =>
  Lens.Family2.LensLike' f s a
totalTokens = Data.ProtoLens.Field.field @"totalTokens"
vec'serverSideToolsUsed ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "vec'serverSideToolsUsed" a) =>
  Lens.Family2.LensLike' f s a
vec'serverSideToolsUsed
  = Data.ProtoLens.Field.field @"vec'serverSideToolsUsed"