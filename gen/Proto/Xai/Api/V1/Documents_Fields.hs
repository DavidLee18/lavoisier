{- This file was auto-generated from xai/api/v1/documents.proto by the proto-lens-protoc program. -}
{-# LANGUAGE ScopedTypeVariables, DataKinds, TypeFamilies, UndecidableInstances, GeneralizedNewtypeDeriving, MultiParamTypeClasses, FlexibleContexts, FlexibleInstances, PatternSynonyms, MagicHash, NoImplicitPrelude, DataKinds, BangPatterns, TypeApplications, OverloadedStrings, DerivingStrategies#-}
{-# OPTIONS_GHC -Wno-unused-imports#-}
{-# OPTIONS_GHC -Wno-duplicate-exports#-}
{-# OPTIONS_GHC -Wno-dodgy-exports#-}
module Proto.Xai.Api.V1.Documents_Fields where
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
chunkContent ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "chunkContent" a) =>
  Lens.Family2.LensLike' f s a
chunkContent = Data.ProtoLens.Field.field @"chunkContent"
chunkId ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "chunkId" a) =>
  Lens.Family2.LensLike' f s a
chunkId = Data.ProtoLens.Field.field @"chunkId"
collectionIds ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "collectionIds" a) =>
  Lens.Family2.LensLike' f s a
collectionIds = Data.ProtoLens.Field.field @"collectionIds"
embeddingWeight ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "embeddingWeight" a) =>
  Lens.Family2.LensLike' f s a
embeddingWeight = Data.ProtoLens.Field.field @"embeddingWeight"
fileId ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "fileId" a) =>
  Lens.Family2.LensLike' f s a
fileId = Data.ProtoLens.Field.field @"fileId"
hybridRetrieval ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "hybridRetrieval" a) =>
  Lens.Family2.LensLike' f s a
hybridRetrieval = Data.ProtoLens.Field.field @"hybridRetrieval"
instructions ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "instructions" a) =>
  Lens.Family2.LensLike' f s a
instructions = Data.ProtoLens.Field.field @"instructions"
k ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "k" a) =>
  Lens.Family2.LensLike' f s a
k = Data.ProtoLens.Field.field @"k"
keywordRetrieval ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "keywordRetrieval" a) =>
  Lens.Family2.LensLike' f s a
keywordRetrieval = Data.ProtoLens.Field.field @"keywordRetrieval"
limit ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "limit" a) =>
  Lens.Family2.LensLike' f s a
limit = Data.ProtoLens.Field.field @"limit"
matches ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "matches" a) =>
  Lens.Family2.LensLike' f s a
matches = Data.ProtoLens.Field.field @"matches"
maybe'hybridRetrieval ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'hybridRetrieval" a) =>
  Lens.Family2.LensLike' f s a
maybe'hybridRetrieval
  = Data.ProtoLens.Field.field @"maybe'hybridRetrieval"
maybe'instructions ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'instructions" a) =>
  Lens.Family2.LensLike' f s a
maybe'instructions
  = Data.ProtoLens.Field.field @"maybe'instructions"
maybe'k ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "maybe'k" a) =>
  Lens.Family2.LensLike' f s a
maybe'k = Data.ProtoLens.Field.field @"maybe'k"
maybe'keywordRetrieval ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'keywordRetrieval" a) =>
  Lens.Family2.LensLike' f s a
maybe'keywordRetrieval
  = Data.ProtoLens.Field.field @"maybe'keywordRetrieval"
maybe'limit ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'limit" a) =>
  Lens.Family2.LensLike' f s a
maybe'limit = Data.ProtoLens.Field.field @"maybe'limit"
maybe'model ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'model" a) =>
  Lens.Family2.LensLike' f s a
maybe'model = Data.ProtoLens.Field.field @"maybe'model"
maybe'rankingMetric ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'rankingMetric" a) =>
  Lens.Family2.LensLike' f s a
maybe'rankingMetric
  = Data.ProtoLens.Field.field @"maybe'rankingMetric"
maybe'reciprocalRankFusion ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'reciprocalRankFusion" a) =>
  Lens.Family2.LensLike' f s a
maybe'reciprocalRankFusion
  = Data.ProtoLens.Field.field @"maybe'reciprocalRankFusion"
maybe'reranker ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'reranker" a) =>
  Lens.Family2.LensLike' f s a
maybe'reranker = Data.ProtoLens.Field.field @"maybe'reranker"
maybe'rerankerModel ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'rerankerModel" a) =>
  Lens.Family2.LensLike' f s a
maybe'rerankerModel
  = Data.ProtoLens.Field.field @"maybe'rerankerModel"
maybe'retrievalMode ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'retrievalMode" a) =>
  Lens.Family2.LensLike' f s a
maybe'retrievalMode
  = Data.ProtoLens.Field.field @"maybe'retrievalMode"
maybe'searchMultiplier ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'searchMultiplier" a) =>
  Lens.Family2.LensLike' f s a
maybe'searchMultiplier
  = Data.ProtoLens.Field.field @"maybe'searchMultiplier"
maybe'semanticRetrieval ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'semanticRetrieval" a) =>
  Lens.Family2.LensLike' f s a
maybe'semanticRetrieval
  = Data.ProtoLens.Field.field @"maybe'semanticRetrieval"
maybe'source ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'source" a) =>
  Lens.Family2.LensLike' f s a
maybe'source = Data.ProtoLens.Field.field @"maybe'source"
model ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "model" a) =>
  Lens.Family2.LensLike' f s a
model = Data.ProtoLens.Field.field @"model"
query ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "query" a) =>
  Lens.Family2.LensLike' f s a
query = Data.ProtoLens.Field.field @"query"
rankingMetric ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "rankingMetric" a) =>
  Lens.Family2.LensLike' f s a
rankingMetric = Data.ProtoLens.Field.field @"rankingMetric"
reciprocalRankFusion ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "reciprocalRankFusion" a) =>
  Lens.Family2.LensLike' f s a
reciprocalRankFusion
  = Data.ProtoLens.Field.field @"reciprocalRankFusion"
reranker ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "reranker" a) =>
  Lens.Family2.LensLike' f s a
reranker = Data.ProtoLens.Field.field @"reranker"
rerankerModel ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "rerankerModel" a) =>
  Lens.Family2.LensLike' f s a
rerankerModel = Data.ProtoLens.Field.field @"rerankerModel"
score ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "score" a) =>
  Lens.Family2.LensLike' f s a
score = Data.ProtoLens.Field.field @"score"
searchMultiplier ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "searchMultiplier" a) =>
  Lens.Family2.LensLike' f s a
searchMultiplier = Data.ProtoLens.Field.field @"searchMultiplier"
semanticRetrieval ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "semanticRetrieval" a) =>
  Lens.Family2.LensLike' f s a
semanticRetrieval = Data.ProtoLens.Field.field @"semanticRetrieval"
source ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "source" a) =>
  Lens.Family2.LensLike' f s a
source = Data.ProtoLens.Field.field @"source"
textWeight ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "textWeight" a) =>
  Lens.Family2.LensLike' f s a
textWeight = Data.ProtoLens.Field.field @"textWeight"
vec'collectionIds ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "vec'collectionIds" a) =>
  Lens.Family2.LensLike' f s a
vec'collectionIds = Data.ProtoLens.Field.field @"vec'collectionIds"
vec'matches ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "vec'matches" a) =>
  Lens.Family2.LensLike' f s a
vec'matches = Data.ProtoLens.Field.field @"vec'matches"