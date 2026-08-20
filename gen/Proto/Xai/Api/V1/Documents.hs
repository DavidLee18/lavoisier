{- This file was auto-generated from xai/api/v1/documents.proto by the proto-lens-protoc program. -}
{-# LANGUAGE ScopedTypeVariables, DataKinds, TypeFamilies, UndecidableInstances, GeneralizedNewtypeDeriving, MultiParamTypeClasses, FlexibleContexts, FlexibleInstances, PatternSynonyms, MagicHash, NoImplicitPrelude, DataKinds, BangPatterns, TypeApplications, OverloadedStrings, DerivingStrategies#-}
{-# OPTIONS_GHC -Wno-unused-imports#-}
{-# OPTIONS_GHC -Wno-duplicate-exports#-}
{-# OPTIONS_GHC -Wno-dodgy-exports#-}
module Proto.Xai.Api.V1.Documents (
        Documents(..), DocumentsSource(), HybridRetrieval(),
        HybridRetrieval'Reranker(..), _HybridRetrieval'RerankerModel,
        _HybridRetrieval'ReciprocalRankFusion, KeywordRetrieval(),
        RankingMetric(..), RankingMetric(),
        RankingMetric'UnrecognizedValue, ReciprocalRankFusion(),
        RerankerModel(), SearchMatch(), SearchRequest(),
        SearchRequest'RetrievalMode(..), _SearchRequest'HybridRetrieval,
        _SearchRequest'SemanticRetrieval, _SearchRequest'KeywordRetrieval,
        SearchResponse(), SemanticRetrieval()
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
     
         * 'Proto.Xai.Api.V1.Documents_Fields.collectionIds' @:: Lens' DocumentsSource [Data.Text.Text]@
         * 'Proto.Xai.Api.V1.Documents_Fields.vec'collectionIds' @:: Lens' DocumentsSource (Data.Vector.Vector Data.Text.Text)@ -}
data DocumentsSource
  = DocumentsSource'_constructor {_DocumentsSource'collectionIds :: !(Data.Vector.Vector Data.Text.Text),
                                  _DocumentsSource'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show DocumentsSource where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField DocumentsSource "collectionIds" [Data.Text.Text] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _DocumentsSource'collectionIds
           (\ x__ y__ -> x__ {_DocumentsSource'collectionIds = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField DocumentsSource "vec'collectionIds" (Data.Vector.Vector Data.Text.Text) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _DocumentsSource'collectionIds
           (\ x__ y__ -> x__ {_DocumentsSource'collectionIds = y__}))
        Prelude.id
instance Data.ProtoLens.Message DocumentsSource where
  messageName _ = Data.Text.pack "xai_api.DocumentsSource"
  packedMessageDescriptor _
    = "\n\
      \\SIDocumentsSource\DC2%\n\
      \\SOcollection_ids\CAN\SOH \ETX(\tR\rcollectionIds"
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
              Data.ProtoLens.FieldDescriptor DocumentsSource
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, collectionIds__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _DocumentsSource'_unknownFields
        (\ x__ y__ -> x__ {_DocumentsSource'_unknownFields = y__})
  defMessage
    = DocumentsSource'_constructor
        {_DocumentsSource'collectionIds = Data.Vector.Generic.empty,
         _DocumentsSource'_unknownFields = []}
  parseMessage
    = let
        loop ::
          DocumentsSource
          -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Vector Data.ProtoLens.Encoding.Growing.RealWorld Data.Text.Text
             -> Data.ProtoLens.Encoding.Bytes.Parser DocumentsSource
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
          "DocumentsSource"
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
             (Data.ProtoLens.Encoding.Wire.buildFieldSet
                (Lens.Family2.view Data.ProtoLens.unknownFields _x))
instance Control.DeepSeq.NFData DocumentsSource where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_DocumentsSource'_unknownFields x__)
             (Control.DeepSeq.deepseq (_DocumentsSource'collectionIds x__) ())
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Documents_Fields.searchMultiplier' @:: Lens' HybridRetrieval Data.Int.Int32@
         * 'Proto.Xai.Api.V1.Documents_Fields.maybe'searchMultiplier' @:: Lens' HybridRetrieval (Prelude.Maybe Data.Int.Int32)@
         * 'Proto.Xai.Api.V1.Documents_Fields.maybe'reranker' @:: Lens' HybridRetrieval (Prelude.Maybe HybridRetrieval'Reranker)@
         * 'Proto.Xai.Api.V1.Documents_Fields.maybe'rerankerModel' @:: Lens' HybridRetrieval (Prelude.Maybe RerankerModel)@
         * 'Proto.Xai.Api.V1.Documents_Fields.rerankerModel' @:: Lens' HybridRetrieval RerankerModel@
         * 'Proto.Xai.Api.V1.Documents_Fields.maybe'reciprocalRankFusion' @:: Lens' HybridRetrieval (Prelude.Maybe ReciprocalRankFusion)@
         * 'Proto.Xai.Api.V1.Documents_Fields.reciprocalRankFusion' @:: Lens' HybridRetrieval ReciprocalRankFusion@ -}
data HybridRetrieval
  = HybridRetrieval'_constructor {_HybridRetrieval'searchMultiplier :: !(Prelude.Maybe Data.Int.Int32),
                                  _HybridRetrieval'reranker :: !(Prelude.Maybe HybridRetrieval'Reranker),
                                  _HybridRetrieval'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show HybridRetrieval where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
data HybridRetrieval'Reranker
  = HybridRetrieval'RerankerModel !RerankerModel |
    HybridRetrieval'ReciprocalRankFusion !ReciprocalRankFusion
  deriving stock (Prelude.Show, Prelude.Eq, Prelude.Ord)
instance Data.ProtoLens.Field.HasField HybridRetrieval "searchMultiplier" Data.Int.Int32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _HybridRetrieval'searchMultiplier
           (\ x__ y__ -> x__ {_HybridRetrieval'searchMultiplier = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField HybridRetrieval "maybe'searchMultiplier" (Prelude.Maybe Data.Int.Int32) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _HybridRetrieval'searchMultiplier
           (\ x__ y__ -> x__ {_HybridRetrieval'searchMultiplier = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField HybridRetrieval "maybe'reranker" (Prelude.Maybe HybridRetrieval'Reranker) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _HybridRetrieval'reranker
           (\ x__ y__ -> x__ {_HybridRetrieval'reranker = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField HybridRetrieval "maybe'rerankerModel" (Prelude.Maybe RerankerModel) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _HybridRetrieval'reranker
           (\ x__ y__ -> x__ {_HybridRetrieval'reranker = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (HybridRetrieval'RerankerModel x__val))
                     -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap HybridRetrieval'RerankerModel y__))
instance Data.ProtoLens.Field.HasField HybridRetrieval "rerankerModel" RerankerModel where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _HybridRetrieval'reranker
           (\ x__ y__ -> x__ {_HybridRetrieval'reranker = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (HybridRetrieval'RerankerModel x__val))
                        -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap HybridRetrieval'RerankerModel y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Field.HasField HybridRetrieval "maybe'reciprocalRankFusion" (Prelude.Maybe ReciprocalRankFusion) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _HybridRetrieval'reranker
           (\ x__ y__ -> x__ {_HybridRetrieval'reranker = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (HybridRetrieval'ReciprocalRankFusion x__val))
                     -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap HybridRetrieval'ReciprocalRankFusion y__))
instance Data.ProtoLens.Field.HasField HybridRetrieval "reciprocalRankFusion" ReciprocalRankFusion where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _HybridRetrieval'reranker
           (\ x__ y__ -> x__ {_HybridRetrieval'reranker = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (HybridRetrieval'ReciprocalRankFusion x__val))
                        -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap HybridRetrieval'ReciprocalRankFusion y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Message HybridRetrieval where
  messageName _ = Data.Text.pack "xai_api.HybridRetrieval"
  packedMessageDescriptor _
    = "\n\
      \\SIHybridRetrieval\DC20\n\
      \\DC1search_multiplier\CAN\SOH \SOH(\ENQH\SOHR\DLEsearchMultiplier\136\SOH\SOH\DC2?\n\
      \\SOreranker_model\CAN\STX \SOH(\v2\SYN.xai_api.RerankerModelH\NULR\rrerankerModel\DC2U\n\
      \\SYNreciprocal_rank_fusion\CAN\ETX \SOH(\v2\GS.xai_api.ReciprocalRankFusionH\NULR\DC4reciprocalRankFusionB\n\
      \\n\
      \\brerankerB\DC4\n\
      \\DC2_search_multiplier"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        searchMultiplier__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "search_multiplier"
              (Data.ProtoLens.ScalarField Data.ProtoLens.Int32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Int.Int32)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'searchMultiplier")) ::
              Data.ProtoLens.FieldDescriptor HybridRetrieval
        rerankerModel__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "reranker_model"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor RerankerModel)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'rerankerModel")) ::
              Data.ProtoLens.FieldDescriptor HybridRetrieval
        reciprocalRankFusion__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "reciprocal_rank_fusion"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor ReciprocalRankFusion)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'reciprocalRankFusion")) ::
              Data.ProtoLens.FieldDescriptor HybridRetrieval
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, searchMultiplier__field_descriptor),
           (Data.ProtoLens.Tag 2, rerankerModel__field_descriptor),
           (Data.ProtoLens.Tag 3, reciprocalRankFusion__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _HybridRetrieval'_unknownFields
        (\ x__ y__ -> x__ {_HybridRetrieval'_unknownFields = y__})
  defMessage
    = HybridRetrieval'_constructor
        {_HybridRetrieval'searchMultiplier = Prelude.Nothing,
         _HybridRetrieval'reranker = Prelude.Nothing,
         _HybridRetrieval'_unknownFields = []}
  parseMessage
    = let
        loop ::
          HybridRetrieval
          -> Data.ProtoLens.Encoding.Bytes.Parser HybridRetrieval
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
                                       "search_multiplier"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"searchMultiplier") y x)
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "reranker_model"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"rerankerModel") y x)
                        26
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "reciprocal_rank_fusion"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"reciprocalRankFusion") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "HybridRetrieval"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (case
                  Lens.Family2.view
                    (Data.ProtoLens.Field.field @"maybe'searchMultiplier") _x
              of
                Prelude.Nothing -> Data.Monoid.mempty
                (Prelude.Just _v)
                  -> (Data.Monoid.<>)
                       (Data.ProtoLens.Encoding.Bytes.putVarInt 8)
                       ((Prelude..)
                          Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral _v))
             ((Data.Monoid.<>)
                (case
                     Lens.Family2.view (Data.ProtoLens.Field.field @"maybe'reranker") _x
                 of
                   Prelude.Nothing -> Data.Monoid.mempty
                   (Prelude.Just (HybridRetrieval'RerankerModel v))
                     -> (Data.Monoid.<>)
                          (Data.ProtoLens.Encoding.Bytes.putVarInt 18)
                          ((Prelude..)
                             (\ bs
                                -> (Data.Monoid.<>)
                                     (Data.ProtoLens.Encoding.Bytes.putVarInt
                                        (Prelude.fromIntegral (Data.ByteString.length bs)))
                                     (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                             Data.ProtoLens.encodeMessage v)
                   (Prelude.Just (HybridRetrieval'ReciprocalRankFusion v))
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
                   (Lens.Family2.view Data.ProtoLens.unknownFields _x)))
instance Control.DeepSeq.NFData HybridRetrieval where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_HybridRetrieval'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_HybridRetrieval'searchMultiplier x__)
                (Control.DeepSeq.deepseq (_HybridRetrieval'reranker x__) ()))
instance Control.DeepSeq.NFData HybridRetrieval'Reranker where
  rnf (HybridRetrieval'RerankerModel x__) = Control.DeepSeq.rnf x__
  rnf (HybridRetrieval'ReciprocalRankFusion x__)
    = Control.DeepSeq.rnf x__
_HybridRetrieval'RerankerModel ::
  Data.ProtoLens.Prism.Prism' HybridRetrieval'Reranker RerankerModel
_HybridRetrieval'RerankerModel
  = Data.ProtoLens.Prism.prism'
      HybridRetrieval'RerankerModel
      (\ p__
         -> case p__ of
              (HybridRetrieval'RerankerModel p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
_HybridRetrieval'ReciprocalRankFusion ::
  Data.ProtoLens.Prism.Prism' HybridRetrieval'Reranker ReciprocalRankFusion
_HybridRetrieval'ReciprocalRankFusion
  = Data.ProtoLens.Prism.prism'
      HybridRetrieval'ReciprocalRankFusion
      (\ p__
         -> case p__ of
              (HybridRetrieval'ReciprocalRankFusion p__val)
                -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Documents_Fields.reranker' @:: Lens' KeywordRetrieval RerankerModel@
         * 'Proto.Xai.Api.V1.Documents_Fields.maybe'reranker' @:: Lens' KeywordRetrieval (Prelude.Maybe RerankerModel)@ -}
data KeywordRetrieval
  = KeywordRetrieval'_constructor {_KeywordRetrieval'reranker :: !(Prelude.Maybe RerankerModel),
                                   _KeywordRetrieval'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show KeywordRetrieval where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField KeywordRetrieval "reranker" RerankerModel where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _KeywordRetrieval'reranker
           (\ x__ y__ -> x__ {_KeywordRetrieval'reranker = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage)
instance Data.ProtoLens.Field.HasField KeywordRetrieval "maybe'reranker" (Prelude.Maybe RerankerModel) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _KeywordRetrieval'reranker
           (\ x__ y__ -> x__ {_KeywordRetrieval'reranker = y__}))
        Prelude.id
instance Data.ProtoLens.Message KeywordRetrieval where
  messageName _ = Data.Text.pack "xai_api.KeywordRetrieval"
  packedMessageDescriptor _
    = "\n\
      \\DLEKeywordRetrieval\DC27\n\
      \\breranker\CAN\SOH \SOH(\v2\SYN.xai_api.RerankerModelH\NULR\breranker\136\SOH\SOHB\v\n\
      \\t_reranker"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        reranker__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "reranker"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor RerankerModel)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'reranker")) ::
              Data.ProtoLens.FieldDescriptor KeywordRetrieval
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, reranker__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _KeywordRetrieval'_unknownFields
        (\ x__ y__ -> x__ {_KeywordRetrieval'_unknownFields = y__})
  defMessage
    = KeywordRetrieval'_constructor
        {_KeywordRetrieval'reranker = Prelude.Nothing,
         _KeywordRetrieval'_unknownFields = []}
  parseMessage
    = let
        loop ::
          KeywordRetrieval
          -> Data.ProtoLens.Encoding.Bytes.Parser KeywordRetrieval
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
                                       "reranker"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"reranker") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "KeywordRetrieval"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (case
                  Lens.Family2.view (Data.ProtoLens.Field.field @"maybe'reranker") _x
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
                (Lens.Family2.view Data.ProtoLens.unknownFields _x))
instance Control.DeepSeq.NFData KeywordRetrieval where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_KeywordRetrieval'_unknownFields x__)
             (Control.DeepSeq.deepseq (_KeywordRetrieval'reranker x__) ())
newtype RankingMetric'UnrecognizedValue
  = RankingMetric'UnrecognizedValue Data.Int.Int32
  deriving stock (Prelude.Eq, Prelude.Ord, Prelude.Show)
data RankingMetric
  = RANKING_METRIC_UNKNOWN |
    RANKING_METRIC_L2_DISTANCE |
    RANKING_METRIC_COSINE_SIMILARITY |
    RankingMetric'Unrecognized !RankingMetric'UnrecognizedValue
  deriving stock (Prelude.Show, Prelude.Eq, Prelude.Ord)
instance Data.ProtoLens.MessageEnum RankingMetric where
  maybeToEnum 0 = Prelude.Just RANKING_METRIC_UNKNOWN
  maybeToEnum 1 = Prelude.Just RANKING_METRIC_L2_DISTANCE
  maybeToEnum 2 = Prelude.Just RANKING_METRIC_COSINE_SIMILARITY
  maybeToEnum k
    = Prelude.Just
        (RankingMetric'Unrecognized
           (RankingMetric'UnrecognizedValue (Prelude.fromIntegral k)))
  showEnum RANKING_METRIC_UNKNOWN = "RANKING_METRIC_UNKNOWN"
  showEnum RANKING_METRIC_L2_DISTANCE = "RANKING_METRIC_L2_DISTANCE"
  showEnum RANKING_METRIC_COSINE_SIMILARITY
    = "RANKING_METRIC_COSINE_SIMILARITY"
  showEnum
    (RankingMetric'Unrecognized (RankingMetric'UnrecognizedValue k))
    = Prelude.show k
  readEnum k
    | (Prelude.==) k "RANKING_METRIC_UNKNOWN"
    = Prelude.Just RANKING_METRIC_UNKNOWN
    | (Prelude.==) k "RANKING_METRIC_L2_DISTANCE"
    = Prelude.Just RANKING_METRIC_L2_DISTANCE
    | (Prelude.==) k "RANKING_METRIC_COSINE_SIMILARITY"
    = Prelude.Just RANKING_METRIC_COSINE_SIMILARITY
    | Prelude.otherwise
    = (Prelude.>>=) (Text.Read.readMaybe k) Data.ProtoLens.maybeToEnum
instance Prelude.Bounded RankingMetric where
  minBound = RANKING_METRIC_UNKNOWN
  maxBound = RANKING_METRIC_COSINE_SIMILARITY
instance Prelude.Enum RankingMetric where
  toEnum k__
    = Prelude.maybe
        (Prelude.error
           ((Prelude.++)
              "toEnum: unknown value for enum RankingMetric: "
              (Prelude.show k__)))
        Prelude.id (Data.ProtoLens.maybeToEnum k__)
  fromEnum RANKING_METRIC_UNKNOWN = 0
  fromEnum RANKING_METRIC_L2_DISTANCE = 1
  fromEnum RANKING_METRIC_COSINE_SIMILARITY = 2
  fromEnum
    (RankingMetric'Unrecognized (RankingMetric'UnrecognizedValue k))
    = Prelude.fromIntegral k
  succ RANKING_METRIC_COSINE_SIMILARITY
    = Prelude.error
        "RankingMetric.succ: bad argument RANKING_METRIC_COSINE_SIMILARITY. This value would be out of bounds."
  succ RANKING_METRIC_UNKNOWN = RANKING_METRIC_L2_DISTANCE
  succ RANKING_METRIC_L2_DISTANCE = RANKING_METRIC_COSINE_SIMILARITY
  succ (RankingMetric'Unrecognized _)
    = Prelude.error
        "RankingMetric.succ: bad argument: unrecognized value"
  pred RANKING_METRIC_UNKNOWN
    = Prelude.error
        "RankingMetric.pred: bad argument RANKING_METRIC_UNKNOWN. This value would be out of bounds."
  pred RANKING_METRIC_L2_DISTANCE = RANKING_METRIC_UNKNOWN
  pred RANKING_METRIC_COSINE_SIMILARITY = RANKING_METRIC_L2_DISTANCE
  pred (RankingMetric'Unrecognized _)
    = Prelude.error
        "RankingMetric.pred: bad argument: unrecognized value"
  enumFrom = Data.ProtoLens.Message.Enum.messageEnumFrom
  enumFromTo = Data.ProtoLens.Message.Enum.messageEnumFromTo
  enumFromThen = Data.ProtoLens.Message.Enum.messageEnumFromThen
  enumFromThenTo = Data.ProtoLens.Message.Enum.messageEnumFromThenTo
instance Data.ProtoLens.FieldDefault RankingMetric where
  fieldDefault = RANKING_METRIC_UNKNOWN
instance Control.DeepSeq.NFData RankingMetric where
  rnf x__ = Prelude.seq x__ ()
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Documents_Fields.k' @:: Lens' ReciprocalRankFusion Data.Int.Int32@
         * 'Proto.Xai.Api.V1.Documents_Fields.maybe'k' @:: Lens' ReciprocalRankFusion (Prelude.Maybe Data.Int.Int32)@
         * 'Proto.Xai.Api.V1.Documents_Fields.embeddingWeight' @:: Lens' ReciprocalRankFusion Prelude.Float@
         * 'Proto.Xai.Api.V1.Documents_Fields.textWeight' @:: Lens' ReciprocalRankFusion Prelude.Float@ -}
data ReciprocalRankFusion
  = ReciprocalRankFusion'_constructor {_ReciprocalRankFusion'k :: !(Prelude.Maybe Data.Int.Int32),
                                       _ReciprocalRankFusion'embeddingWeight :: !Prelude.Float,
                                       _ReciprocalRankFusion'textWeight :: !Prelude.Float,
                                       _ReciprocalRankFusion'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show ReciprocalRankFusion where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField ReciprocalRankFusion "k" Data.Int.Int32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ReciprocalRankFusion'k
           (\ x__ y__ -> x__ {_ReciprocalRankFusion'k = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField ReciprocalRankFusion "maybe'k" (Prelude.Maybe Data.Int.Int32) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ReciprocalRankFusion'k
           (\ x__ y__ -> x__ {_ReciprocalRankFusion'k = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField ReciprocalRankFusion "embeddingWeight" Prelude.Float where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ReciprocalRankFusion'embeddingWeight
           (\ x__ y__ -> x__ {_ReciprocalRankFusion'embeddingWeight = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField ReciprocalRankFusion "textWeight" Prelude.Float where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ReciprocalRankFusion'textWeight
           (\ x__ y__ -> x__ {_ReciprocalRankFusion'textWeight = y__}))
        Prelude.id
instance Data.ProtoLens.Message ReciprocalRankFusion where
  messageName _ = Data.Text.pack "xai_api.ReciprocalRankFusion"
  packedMessageDescriptor _
    = "\n\
      \\DC4ReciprocalRankFusion\DC2\DC1\n\
      \\SOHk\CAN\SOH \SOH(\ENQH\NULR\SOHk\136\SOH\SOH\DC2)\n\
      \\DLEembedding_weight\CAN\ETX \SOH(\STXR\SIembeddingWeight\DC2\US\n\
      \\vtext_weight\CAN\EOT \SOH(\STXR\n\
      \textWeightB\EOT\n\
      \\STX_kJ\EOT\b\STX\DLE\ETX"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        k__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "k"
              (Data.ProtoLens.ScalarField Data.ProtoLens.Int32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Int.Int32)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'k")) ::
              Data.ProtoLens.FieldDescriptor ReciprocalRankFusion
        embeddingWeight__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "embedding_weight"
              (Data.ProtoLens.ScalarField Data.ProtoLens.FloatField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Float)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"embeddingWeight")) ::
              Data.ProtoLens.FieldDescriptor ReciprocalRankFusion
        textWeight__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "text_weight"
              (Data.ProtoLens.ScalarField Data.ProtoLens.FloatField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Float)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"textWeight")) ::
              Data.ProtoLens.FieldDescriptor ReciprocalRankFusion
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, k__field_descriptor),
           (Data.ProtoLens.Tag 3, embeddingWeight__field_descriptor),
           (Data.ProtoLens.Tag 4, textWeight__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _ReciprocalRankFusion'_unknownFields
        (\ x__ y__ -> x__ {_ReciprocalRankFusion'_unknownFields = y__})
  defMessage
    = ReciprocalRankFusion'_constructor
        {_ReciprocalRankFusion'k = Prelude.Nothing,
         _ReciprocalRankFusion'embeddingWeight = Data.ProtoLens.fieldDefault,
         _ReciprocalRankFusion'textWeight = Data.ProtoLens.fieldDefault,
         _ReciprocalRankFusion'_unknownFields = []}
  parseMessage
    = let
        loop ::
          ReciprocalRankFusion
          -> Data.ProtoLens.Encoding.Bytes.Parser ReciprocalRankFusion
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
                                       "k"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"k") y x)
                        29
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Data.ProtoLens.Encoding.Bytes.wordToFloat
                                          Data.ProtoLens.Encoding.Bytes.getFixed32)
                                       "embedding_weight"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"embeddingWeight") y x)
                        37
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Data.ProtoLens.Encoding.Bytes.wordToFloat
                                          Data.ProtoLens.Encoding.Bytes.getFixed32)
                                       "text_weight"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"textWeight") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "ReciprocalRankFusion"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (case
                  Lens.Family2.view (Data.ProtoLens.Field.field @"maybe'k") _x
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
                         (Data.ProtoLens.Field.field @"embeddingWeight") _x
                 in
                   if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                       Data.Monoid.mempty
                   else
                       (Data.Monoid.<>)
                         (Data.ProtoLens.Encoding.Bytes.putVarInt 29)
                         ((Prelude..)
                            Data.ProtoLens.Encoding.Bytes.putFixed32
                            Data.ProtoLens.Encoding.Bytes.floatToWord _v))
                ((Data.Monoid.<>)
                   (let
                      _v
                        = Lens.Family2.view (Data.ProtoLens.Field.field @"textWeight") _x
                    in
                      if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                          Data.Monoid.mempty
                      else
                          (Data.Monoid.<>)
                            (Data.ProtoLens.Encoding.Bytes.putVarInt 37)
                            ((Prelude..)
                               Data.ProtoLens.Encoding.Bytes.putFixed32
                               Data.ProtoLens.Encoding.Bytes.floatToWord _v))
                   (Data.ProtoLens.Encoding.Wire.buildFieldSet
                      (Lens.Family2.view Data.ProtoLens.unknownFields _x))))
instance Control.DeepSeq.NFData ReciprocalRankFusion where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_ReciprocalRankFusion'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_ReciprocalRankFusion'k x__)
                (Control.DeepSeq.deepseq
                   (_ReciprocalRankFusion'embeddingWeight x__)
                   (Control.DeepSeq.deepseq
                      (_ReciprocalRankFusion'textWeight x__) ())))
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Documents_Fields.model' @:: Lens' RerankerModel Data.Text.Text@
         * 'Proto.Xai.Api.V1.Documents_Fields.maybe'model' @:: Lens' RerankerModel (Prelude.Maybe Data.Text.Text)@
         * 'Proto.Xai.Api.V1.Documents_Fields.instructions' @:: Lens' RerankerModel Data.Text.Text@
         * 'Proto.Xai.Api.V1.Documents_Fields.maybe'instructions' @:: Lens' RerankerModel (Prelude.Maybe Data.Text.Text)@ -}
data RerankerModel
  = RerankerModel'_constructor {_RerankerModel'model :: !(Prelude.Maybe Data.Text.Text),
                                _RerankerModel'instructions :: !(Prelude.Maybe Data.Text.Text),
                                _RerankerModel'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show RerankerModel where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField RerankerModel "model" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RerankerModel'model
           (\ x__ y__ -> x__ {_RerankerModel'model = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField RerankerModel "maybe'model" (Prelude.Maybe Data.Text.Text) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RerankerModel'model
           (\ x__ y__ -> x__ {_RerankerModel'model = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField RerankerModel "instructions" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RerankerModel'instructions
           (\ x__ y__ -> x__ {_RerankerModel'instructions = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField RerankerModel "maybe'instructions" (Prelude.Maybe Data.Text.Text) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _RerankerModel'instructions
           (\ x__ y__ -> x__ {_RerankerModel'instructions = y__}))
        Prelude.id
instance Data.ProtoLens.Message RerankerModel where
  messageName _ = Data.Text.pack "xai_api.RerankerModel"
  packedMessageDescriptor _
    = "\n\
      \\rRerankerModel\DC2\EM\n\
      \\ENQmodel\CAN\SOH \SOH(\tH\NULR\ENQmodel\136\SOH\SOH\DC2'\n\
      \\finstructions\CAN\STX \SOH(\tH\SOHR\finstructions\136\SOH\SOHB\b\n\
      \\ACK_modelB\SI\n\
      \\r_instructions"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        model__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "model"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'model")) ::
              Data.ProtoLens.FieldDescriptor RerankerModel
        instructions__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "instructions"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'instructions")) ::
              Data.ProtoLens.FieldDescriptor RerankerModel
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, model__field_descriptor),
           (Data.ProtoLens.Tag 2, instructions__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _RerankerModel'_unknownFields
        (\ x__ y__ -> x__ {_RerankerModel'_unknownFields = y__})
  defMessage
    = RerankerModel'_constructor
        {_RerankerModel'model = Prelude.Nothing,
         _RerankerModel'instructions = Prelude.Nothing,
         _RerankerModel'_unknownFields = []}
  parseMessage
    = let
        loop ::
          RerankerModel -> Data.ProtoLens.Encoding.Bytes.Parser RerankerModel
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
                                       "model"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"model") y x)
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "instructions"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"instructions") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "RerankerModel"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (case
                  Lens.Family2.view (Data.ProtoLens.Field.field @"maybe'model") _x
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
                     Lens.Family2.view
                       (Data.ProtoLens.Field.field @"maybe'instructions") _x
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
instance Control.DeepSeq.NFData RerankerModel where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_RerankerModel'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_RerankerModel'model x__)
                (Control.DeepSeq.deepseq (_RerankerModel'instructions x__) ()))
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Documents_Fields.fileId' @:: Lens' SearchMatch Data.Text.Text@
         * 'Proto.Xai.Api.V1.Documents_Fields.chunkId' @:: Lens' SearchMatch Data.Text.Text@
         * 'Proto.Xai.Api.V1.Documents_Fields.chunkContent' @:: Lens' SearchMatch Data.Text.Text@
         * 'Proto.Xai.Api.V1.Documents_Fields.score' @:: Lens' SearchMatch Prelude.Float@
         * 'Proto.Xai.Api.V1.Documents_Fields.collectionIds' @:: Lens' SearchMatch [Data.Text.Text]@
         * 'Proto.Xai.Api.V1.Documents_Fields.vec'collectionIds' @:: Lens' SearchMatch (Data.Vector.Vector Data.Text.Text)@ -}
data SearchMatch
  = SearchMatch'_constructor {_SearchMatch'fileId :: !Data.Text.Text,
                              _SearchMatch'chunkId :: !Data.Text.Text,
                              _SearchMatch'chunkContent :: !Data.Text.Text,
                              _SearchMatch'score :: !Prelude.Float,
                              _SearchMatch'collectionIds :: !(Data.Vector.Vector Data.Text.Text),
                              _SearchMatch'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show SearchMatch where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField SearchMatch "fileId" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SearchMatch'fileId (\ x__ y__ -> x__ {_SearchMatch'fileId = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SearchMatch "chunkId" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SearchMatch'chunkId
           (\ x__ y__ -> x__ {_SearchMatch'chunkId = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SearchMatch "chunkContent" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SearchMatch'chunkContent
           (\ x__ y__ -> x__ {_SearchMatch'chunkContent = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SearchMatch "score" Prelude.Float where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SearchMatch'score (\ x__ y__ -> x__ {_SearchMatch'score = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SearchMatch "collectionIds" [Data.Text.Text] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SearchMatch'collectionIds
           (\ x__ y__ -> x__ {_SearchMatch'collectionIds = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField SearchMatch "vec'collectionIds" (Data.Vector.Vector Data.Text.Text) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SearchMatch'collectionIds
           (\ x__ y__ -> x__ {_SearchMatch'collectionIds = y__}))
        Prelude.id
instance Data.ProtoLens.Message SearchMatch where
  messageName _ = Data.Text.pack "xai_api.SearchMatch"
  packedMessageDescriptor _
    = "\n\
      \\vSearchMatch\DC2\ETB\n\
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
              Data.ProtoLens.FieldDescriptor SearchMatch
        chunkId__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "chunk_id"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"chunkId")) ::
              Data.ProtoLens.FieldDescriptor SearchMatch
        chunkContent__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "chunk_content"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"chunkContent")) ::
              Data.ProtoLens.FieldDescriptor SearchMatch
        score__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "score"
              (Data.ProtoLens.ScalarField Data.ProtoLens.FloatField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Float)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"score")) ::
              Data.ProtoLens.FieldDescriptor SearchMatch
        collectionIds__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "collection_ids"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Unpacked
                 (Data.ProtoLens.Field.field @"collectionIds")) ::
              Data.ProtoLens.FieldDescriptor SearchMatch
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, fileId__field_descriptor),
           (Data.ProtoLens.Tag 2, chunkId__field_descriptor),
           (Data.ProtoLens.Tag 3, chunkContent__field_descriptor),
           (Data.ProtoLens.Tag 4, score__field_descriptor),
           (Data.ProtoLens.Tag 5, collectionIds__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _SearchMatch'_unknownFields
        (\ x__ y__ -> x__ {_SearchMatch'_unknownFields = y__})
  defMessage
    = SearchMatch'_constructor
        {_SearchMatch'fileId = Data.ProtoLens.fieldDefault,
         _SearchMatch'chunkId = Data.ProtoLens.fieldDefault,
         _SearchMatch'chunkContent = Data.ProtoLens.fieldDefault,
         _SearchMatch'score = Data.ProtoLens.fieldDefault,
         _SearchMatch'collectionIds = Data.Vector.Generic.empty,
         _SearchMatch'_unknownFields = []}
  parseMessage
    = let
        loop ::
          SearchMatch
          -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Vector Data.ProtoLens.Encoding.Growing.RealWorld Data.Text.Text
             -> Data.ProtoLens.Encoding.Bytes.Parser SearchMatch
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
          "SearchMatch"
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
instance Control.DeepSeq.NFData SearchMatch where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_SearchMatch'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_SearchMatch'fileId x__)
                (Control.DeepSeq.deepseq
                   (_SearchMatch'chunkId x__)
                   (Control.DeepSeq.deepseq
                      (_SearchMatch'chunkContent x__)
                      (Control.DeepSeq.deepseq
                         (_SearchMatch'score x__)
                         (Control.DeepSeq.deepseq (_SearchMatch'collectionIds x__) ())))))
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Documents_Fields.query' @:: Lens' SearchRequest Data.Text.Text@
         * 'Proto.Xai.Api.V1.Documents_Fields.source' @:: Lens' SearchRequest DocumentsSource@
         * 'Proto.Xai.Api.V1.Documents_Fields.maybe'source' @:: Lens' SearchRequest (Prelude.Maybe DocumentsSource)@
         * 'Proto.Xai.Api.V1.Documents_Fields.limit' @:: Lens' SearchRequest Data.Int.Int32@
         * 'Proto.Xai.Api.V1.Documents_Fields.maybe'limit' @:: Lens' SearchRequest (Prelude.Maybe Data.Int.Int32)@
         * 'Proto.Xai.Api.V1.Documents_Fields.instructions' @:: Lens' SearchRequest Data.Text.Text@
         * 'Proto.Xai.Api.V1.Documents_Fields.maybe'instructions' @:: Lens' SearchRequest (Prelude.Maybe Data.Text.Text)@
         * 'Proto.Xai.Api.V1.Documents_Fields.rankingMetric' @:: Lens' SearchRequest RankingMetric@
         * 'Proto.Xai.Api.V1.Documents_Fields.maybe'rankingMetric' @:: Lens' SearchRequest (Prelude.Maybe RankingMetric)@
         * 'Proto.Xai.Api.V1.Documents_Fields.maybe'retrievalMode' @:: Lens' SearchRequest (Prelude.Maybe SearchRequest'RetrievalMode)@
         * 'Proto.Xai.Api.V1.Documents_Fields.maybe'hybridRetrieval' @:: Lens' SearchRequest (Prelude.Maybe HybridRetrieval)@
         * 'Proto.Xai.Api.V1.Documents_Fields.hybridRetrieval' @:: Lens' SearchRequest HybridRetrieval@
         * 'Proto.Xai.Api.V1.Documents_Fields.maybe'semanticRetrieval' @:: Lens' SearchRequest (Prelude.Maybe SemanticRetrieval)@
         * 'Proto.Xai.Api.V1.Documents_Fields.semanticRetrieval' @:: Lens' SearchRequest SemanticRetrieval@
         * 'Proto.Xai.Api.V1.Documents_Fields.maybe'keywordRetrieval' @:: Lens' SearchRequest (Prelude.Maybe KeywordRetrieval)@
         * 'Proto.Xai.Api.V1.Documents_Fields.keywordRetrieval' @:: Lens' SearchRequest KeywordRetrieval@ -}
data SearchRequest
  = SearchRequest'_constructor {_SearchRequest'query :: !Data.Text.Text,
                                _SearchRequest'source :: !(Prelude.Maybe DocumentsSource),
                                _SearchRequest'limit :: !(Prelude.Maybe Data.Int.Int32),
                                _SearchRequest'instructions :: !(Prelude.Maybe Data.Text.Text),
                                _SearchRequest'rankingMetric :: !(Prelude.Maybe RankingMetric),
                                _SearchRequest'retrievalMode :: !(Prelude.Maybe SearchRequest'RetrievalMode),
                                _SearchRequest'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show SearchRequest where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
data SearchRequest'RetrievalMode
  = SearchRequest'HybridRetrieval !HybridRetrieval |
    SearchRequest'SemanticRetrieval !SemanticRetrieval |
    SearchRequest'KeywordRetrieval !KeywordRetrieval
  deriving stock (Prelude.Show, Prelude.Eq, Prelude.Ord)
instance Data.ProtoLens.Field.HasField SearchRequest "query" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SearchRequest'query
           (\ x__ y__ -> x__ {_SearchRequest'query = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SearchRequest "source" DocumentsSource where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SearchRequest'source
           (\ x__ y__ -> x__ {_SearchRequest'source = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage)
instance Data.ProtoLens.Field.HasField SearchRequest "maybe'source" (Prelude.Maybe DocumentsSource) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SearchRequest'source
           (\ x__ y__ -> x__ {_SearchRequest'source = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SearchRequest "limit" Data.Int.Int32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SearchRequest'limit
           (\ x__ y__ -> x__ {_SearchRequest'limit = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField SearchRequest "maybe'limit" (Prelude.Maybe Data.Int.Int32) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SearchRequest'limit
           (\ x__ y__ -> x__ {_SearchRequest'limit = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SearchRequest "instructions" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SearchRequest'instructions
           (\ x__ y__ -> x__ {_SearchRequest'instructions = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField SearchRequest "maybe'instructions" (Prelude.Maybe Data.Text.Text) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SearchRequest'instructions
           (\ x__ y__ -> x__ {_SearchRequest'instructions = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SearchRequest "rankingMetric" RankingMetric where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SearchRequest'rankingMetric
           (\ x__ y__ -> x__ {_SearchRequest'rankingMetric = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.fieldDefault)
instance Data.ProtoLens.Field.HasField SearchRequest "maybe'rankingMetric" (Prelude.Maybe RankingMetric) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SearchRequest'rankingMetric
           (\ x__ y__ -> x__ {_SearchRequest'rankingMetric = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SearchRequest "maybe'retrievalMode" (Prelude.Maybe SearchRequest'RetrievalMode) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SearchRequest'retrievalMode
           (\ x__ y__ -> x__ {_SearchRequest'retrievalMode = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField SearchRequest "maybe'hybridRetrieval" (Prelude.Maybe HybridRetrieval) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SearchRequest'retrievalMode
           (\ x__ y__ -> x__ {_SearchRequest'retrievalMode = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (SearchRequest'HybridRetrieval x__val))
                     -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap SearchRequest'HybridRetrieval y__))
instance Data.ProtoLens.Field.HasField SearchRequest "hybridRetrieval" HybridRetrieval where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SearchRequest'retrievalMode
           (\ x__ y__ -> x__ {_SearchRequest'retrievalMode = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (SearchRequest'HybridRetrieval x__val))
                        -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap SearchRequest'HybridRetrieval y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Field.HasField SearchRequest "maybe'semanticRetrieval" (Prelude.Maybe SemanticRetrieval) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SearchRequest'retrievalMode
           (\ x__ y__ -> x__ {_SearchRequest'retrievalMode = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (SearchRequest'SemanticRetrieval x__val))
                     -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap SearchRequest'SemanticRetrieval y__))
instance Data.ProtoLens.Field.HasField SearchRequest "semanticRetrieval" SemanticRetrieval where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SearchRequest'retrievalMode
           (\ x__ y__ -> x__ {_SearchRequest'retrievalMode = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (SearchRequest'SemanticRetrieval x__val))
                        -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap SearchRequest'SemanticRetrieval y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Field.HasField SearchRequest "maybe'keywordRetrieval" (Prelude.Maybe KeywordRetrieval) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SearchRequest'retrievalMode
           (\ x__ y__ -> x__ {_SearchRequest'retrievalMode = y__}))
        (Lens.Family2.Unchecked.lens
           (\ x__
              -> case x__ of
                   (Prelude.Just (SearchRequest'KeywordRetrieval x__val))
                     -> Prelude.Just x__val
                   _otherwise -> Prelude.Nothing)
           (\ _ y__ -> Prelude.fmap SearchRequest'KeywordRetrieval y__))
instance Data.ProtoLens.Field.HasField SearchRequest "keywordRetrieval" KeywordRetrieval where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SearchRequest'retrievalMode
           (\ x__ y__ -> x__ {_SearchRequest'retrievalMode = y__}))
        ((Prelude..)
           (Lens.Family2.Unchecked.lens
              (\ x__
                 -> case x__ of
                      (Prelude.Just (SearchRequest'KeywordRetrieval x__val))
                        -> Prelude.Just x__val
                      _otherwise -> Prelude.Nothing)
              (\ _ y__ -> Prelude.fmap SearchRequest'KeywordRetrieval y__))
           (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage))
instance Data.ProtoLens.Message SearchRequest where
  messageName _ = Data.Text.pack "xai_api.SearchRequest"
  packedMessageDescriptor _
    = "\n\
      \\rSearchRequest\DC2\DC4\n\
      \\ENQquery\CAN\SOH \SOH(\tR\ENQquery\DC20\n\
      \\ACKsource\CAN\STX \SOH(\v2\CAN.xai_api.DocumentsSourceR\ACKsource\DC2\EM\n\
      \\ENQlimit\CAN\ETX \SOH(\ENQH\SOHR\ENQlimit\136\SOH\SOH\DC2'\n\
      \\finstructions\CAN\ENQ \SOH(\tH\STXR\finstructions\136\SOH\SOH\DC2E\n\
      \\DLEhybrid_retrieval\CAN\v \SOH(\v2\CAN.xai_api.HybridRetrievalH\NULR\SIhybridRetrieval\DC2K\n\
      \\DC2semantic_retrieval\CAN\f \SOH(\v2\SUB.xai_api.SemanticRetrievalH\NULR\DC1semanticRetrieval\DC2H\n\
      \\DC1keyword_retrieval\CAN\r \SOH(\v2\EM.xai_api.KeywordRetrievalH\NULR\DLEkeywordRetrieval\DC2F\n\
      \\SOranking_metric\CAN\EOT \SOH(\SO2\SYN.xai_api.RankingMetricH\ETXR\rrankingMetricB\STX\CAN\SOH\136\SOH\SOHB\DLE\n\
      \\SOretrieval_modeB\b\n\
      \\ACK_limitB\SI\n\
      \\r_instructionsB\DC1\n\
      \\SI_ranking_metricJ\EOT\b\ACK\DLE\aJ\EOT\b\a\DLE\bJ\EOT\b\b\DLE\tJ\EOT\b\t\DLE\n\
      \J\EOT\b\n\
      \\DLE\v"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        query__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "query"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"query")) ::
              Data.ProtoLens.FieldDescriptor SearchRequest
        source__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "source"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor DocumentsSource)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'source")) ::
              Data.ProtoLens.FieldDescriptor SearchRequest
        limit__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "limit"
              (Data.ProtoLens.ScalarField Data.ProtoLens.Int32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Int.Int32)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'limit")) ::
              Data.ProtoLens.FieldDescriptor SearchRequest
        instructions__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "instructions"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'instructions")) ::
              Data.ProtoLens.FieldDescriptor SearchRequest
        rankingMetric__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "ranking_metric"
              (Data.ProtoLens.ScalarField Data.ProtoLens.EnumField ::
                 Data.ProtoLens.FieldTypeDescriptor RankingMetric)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'rankingMetric")) ::
              Data.ProtoLens.FieldDescriptor SearchRequest
        hybridRetrieval__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "hybrid_retrieval"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor HybridRetrieval)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'hybridRetrieval")) ::
              Data.ProtoLens.FieldDescriptor SearchRequest
        semanticRetrieval__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "semantic_retrieval"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor SemanticRetrieval)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'semanticRetrieval")) ::
              Data.ProtoLens.FieldDescriptor SearchRequest
        keywordRetrieval__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "keyword_retrieval"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor KeywordRetrieval)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'keywordRetrieval")) ::
              Data.ProtoLens.FieldDescriptor SearchRequest
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, query__field_descriptor),
           (Data.ProtoLens.Tag 2, source__field_descriptor),
           (Data.ProtoLens.Tag 3, limit__field_descriptor),
           (Data.ProtoLens.Tag 5, instructions__field_descriptor),
           (Data.ProtoLens.Tag 4, rankingMetric__field_descriptor),
           (Data.ProtoLens.Tag 11, hybridRetrieval__field_descriptor),
           (Data.ProtoLens.Tag 12, semanticRetrieval__field_descriptor),
           (Data.ProtoLens.Tag 13, keywordRetrieval__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _SearchRequest'_unknownFields
        (\ x__ y__ -> x__ {_SearchRequest'_unknownFields = y__})
  defMessage
    = SearchRequest'_constructor
        {_SearchRequest'query = Data.ProtoLens.fieldDefault,
         _SearchRequest'source = Prelude.Nothing,
         _SearchRequest'limit = Prelude.Nothing,
         _SearchRequest'instructions = Prelude.Nothing,
         _SearchRequest'rankingMetric = Prelude.Nothing,
         _SearchRequest'retrievalMode = Prelude.Nothing,
         _SearchRequest'_unknownFields = []}
  parseMessage
    = let
        loop ::
          SearchRequest -> Data.ProtoLens.Encoding.Bytes.Parser SearchRequest
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
                                       "query"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"query") y x)
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "source"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"source") y x)
                        24
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "limit"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"limit") y x)
                        42
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "instructions"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"instructions") y x)
                        32
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.toEnum
                                          (Prelude.fmap
                                             Prelude.fromIntegral
                                             Data.ProtoLens.Encoding.Bytes.getVarInt))
                                       "ranking_metric"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"rankingMetric") y x)
                        90
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "hybrid_retrieval"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"hybridRetrieval") y x)
                        98
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "semantic_retrieval"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"semanticRetrieval") y x)
                        106
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.isolate
                                             (Prelude.fromIntegral len) Data.ProtoLens.parseMessage)
                                       "keyword_retrieval"
                                loop
                                  (Lens.Family2.set
                                     (Data.ProtoLens.Field.field @"keywordRetrieval") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "SearchRequest"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v = Lens.Family2.view (Data.ProtoLens.Field.field @"query") _x
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
                     Lens.Family2.view (Data.ProtoLens.Field.field @"maybe'source") _x
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
                   (case
                        Lens.Family2.view (Data.ProtoLens.Field.field @"maybe'limit") _x
                    of
                      Prelude.Nothing -> Data.Monoid.mempty
                      (Prelude.Just _v)
                        -> (Data.Monoid.<>)
                             (Data.ProtoLens.Encoding.Bytes.putVarInt 24)
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
                              Lens.Family2.view
                                (Data.ProtoLens.Field.field @"maybe'rankingMetric") _x
                          of
                            Prelude.Nothing -> Data.Monoid.mempty
                            (Prelude.Just _v)
                              -> (Data.Monoid.<>)
                                   (Data.ProtoLens.Encoding.Bytes.putVarInt 32)
                                   ((Prelude..)
                                      ((Prelude..)
                                         Data.ProtoLens.Encoding.Bytes.putVarInt
                                         Prelude.fromIntegral)
                                      Prelude.fromEnum _v))
                         ((Data.Monoid.<>)
                            (case
                                 Lens.Family2.view
                                   (Data.ProtoLens.Field.field @"maybe'retrievalMode") _x
                             of
                               Prelude.Nothing -> Data.Monoid.mempty
                               (Prelude.Just (SearchRequest'HybridRetrieval v))
                                 -> (Data.Monoid.<>)
                                      (Data.ProtoLens.Encoding.Bytes.putVarInt 90)
                                      ((Prelude..)
                                         (\ bs
                                            -> (Data.Monoid.<>)
                                                 (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                    (Prelude.fromIntegral
                                                       (Data.ByteString.length bs)))
                                                 (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                         Data.ProtoLens.encodeMessage v)
                               (Prelude.Just (SearchRequest'SemanticRetrieval v))
                                 -> (Data.Monoid.<>)
                                      (Data.ProtoLens.Encoding.Bytes.putVarInt 98)
                                      ((Prelude..)
                                         (\ bs
                                            -> (Data.Monoid.<>)
                                                 (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                    (Prelude.fromIntegral
                                                       (Data.ByteString.length bs)))
                                                 (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                         Data.ProtoLens.encodeMessage v)
                               (Prelude.Just (SearchRequest'KeywordRetrieval v))
                                 -> (Data.Monoid.<>)
                                      (Data.ProtoLens.Encoding.Bytes.putVarInt 106)
                                      ((Prelude..)
                                         (\ bs
                                            -> (Data.Monoid.<>)
                                                 (Data.ProtoLens.Encoding.Bytes.putVarInt
                                                    (Prelude.fromIntegral
                                                       (Data.ByteString.length bs)))
                                                 (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                         Data.ProtoLens.encodeMessage v))
                            (Data.ProtoLens.Encoding.Wire.buildFieldSet
                               (Lens.Family2.view Data.ProtoLens.unknownFields _x)))))))
instance Control.DeepSeq.NFData SearchRequest where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_SearchRequest'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_SearchRequest'query x__)
                (Control.DeepSeq.deepseq
                   (_SearchRequest'source x__)
                   (Control.DeepSeq.deepseq
                      (_SearchRequest'limit x__)
                      (Control.DeepSeq.deepseq
                         (_SearchRequest'instructions x__)
                         (Control.DeepSeq.deepseq
                            (_SearchRequest'rankingMetric x__)
                            (Control.DeepSeq.deepseq
                               (_SearchRequest'retrievalMode x__) ()))))))
instance Control.DeepSeq.NFData SearchRequest'RetrievalMode where
  rnf (SearchRequest'HybridRetrieval x__) = Control.DeepSeq.rnf x__
  rnf (SearchRequest'SemanticRetrieval x__) = Control.DeepSeq.rnf x__
  rnf (SearchRequest'KeywordRetrieval x__) = Control.DeepSeq.rnf x__
_SearchRequest'HybridRetrieval ::
  Data.ProtoLens.Prism.Prism' SearchRequest'RetrievalMode HybridRetrieval
_SearchRequest'HybridRetrieval
  = Data.ProtoLens.Prism.prism'
      SearchRequest'HybridRetrieval
      (\ p__
         -> case p__ of
              (SearchRequest'HybridRetrieval p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
_SearchRequest'SemanticRetrieval ::
  Data.ProtoLens.Prism.Prism' SearchRequest'RetrievalMode SemanticRetrieval
_SearchRequest'SemanticRetrieval
  = Data.ProtoLens.Prism.prism'
      SearchRequest'SemanticRetrieval
      (\ p__
         -> case p__ of
              (SearchRequest'SemanticRetrieval p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
_SearchRequest'KeywordRetrieval ::
  Data.ProtoLens.Prism.Prism' SearchRequest'RetrievalMode KeywordRetrieval
_SearchRequest'KeywordRetrieval
  = Data.ProtoLens.Prism.prism'
      SearchRequest'KeywordRetrieval
      (\ p__
         -> case p__ of
              (SearchRequest'KeywordRetrieval p__val) -> Prelude.Just p__val
              _otherwise -> Prelude.Nothing)
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Documents_Fields.matches' @:: Lens' SearchResponse [SearchMatch]@
         * 'Proto.Xai.Api.V1.Documents_Fields.vec'matches' @:: Lens' SearchResponse (Data.Vector.Vector SearchMatch)@ -}
data SearchResponse
  = SearchResponse'_constructor {_SearchResponse'matches :: !(Data.Vector.Vector SearchMatch),
                                 _SearchResponse'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show SearchResponse where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField SearchResponse "matches" [SearchMatch] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SearchResponse'matches
           (\ x__ y__ -> x__ {_SearchResponse'matches = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField SearchResponse "vec'matches" (Data.Vector.Vector SearchMatch) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SearchResponse'matches
           (\ x__ y__ -> x__ {_SearchResponse'matches = y__}))
        Prelude.id
instance Data.ProtoLens.Message SearchResponse where
  messageName _ = Data.Text.pack "xai_api.SearchResponse"
  packedMessageDescriptor _
    = "\n\
      \\SOSearchResponse\DC2.\n\
      \\amatches\CAN\SOH \ETX(\v2\DC4.xai_api.SearchMatchR\amatches"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        matches__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "matches"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor SearchMatch)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Unpacked (Data.ProtoLens.Field.field @"matches")) ::
              Data.ProtoLens.FieldDescriptor SearchResponse
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, matches__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _SearchResponse'_unknownFields
        (\ x__ y__ -> x__ {_SearchResponse'_unknownFields = y__})
  defMessage
    = SearchResponse'_constructor
        {_SearchResponse'matches = Data.Vector.Generic.empty,
         _SearchResponse'_unknownFields = []}
  parseMessage
    = let
        loop ::
          SearchResponse
          -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Vector Data.ProtoLens.Encoding.Growing.RealWorld SearchMatch
             -> Data.ProtoLens.Encoding.Bytes.Parser SearchResponse
        loop x mutable'matches
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do frozen'matches <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                          (Data.ProtoLens.Encoding.Growing.unsafeFreeze
                                             mutable'matches)
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
                              (Data.ProtoLens.Field.field @"vec'matches") frozen'matches x))
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                            Data.ProtoLens.Encoding.Bytes.isolate
                                              (Prelude.fromIntegral len)
                                              Data.ProtoLens.parseMessage)
                                        "matches"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append mutable'matches y)
                                loop x v
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
                                  mutable'matches
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do mutable'matches <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                   Data.ProtoLens.Encoding.Growing.new
              loop Data.ProtoLens.defMessage mutable'matches)
          "SearchResponse"
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
                (Lens.Family2.view (Data.ProtoLens.Field.field @"vec'matches") _x))
             (Data.ProtoLens.Encoding.Wire.buildFieldSet
                (Lens.Family2.view Data.ProtoLens.unknownFields _x))
instance Control.DeepSeq.NFData SearchResponse where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_SearchResponse'_unknownFields x__)
             (Control.DeepSeq.deepseq (_SearchResponse'matches x__) ())
{- | Fields :
     
         * 'Proto.Xai.Api.V1.Documents_Fields.reranker' @:: Lens' SemanticRetrieval RerankerModel@
         * 'Proto.Xai.Api.V1.Documents_Fields.maybe'reranker' @:: Lens' SemanticRetrieval (Prelude.Maybe RerankerModel)@ -}
data SemanticRetrieval
  = SemanticRetrieval'_constructor {_SemanticRetrieval'reranker :: !(Prelude.Maybe RerankerModel),
                                    _SemanticRetrieval'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show SemanticRetrieval where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField SemanticRetrieval "reranker" RerankerModel where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SemanticRetrieval'reranker
           (\ x__ y__ -> x__ {_SemanticRetrieval'reranker = y__}))
        (Data.ProtoLens.maybeLens Data.ProtoLens.defMessage)
instance Data.ProtoLens.Field.HasField SemanticRetrieval "maybe'reranker" (Prelude.Maybe RerankerModel) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _SemanticRetrieval'reranker
           (\ x__ y__ -> x__ {_SemanticRetrieval'reranker = y__}))
        Prelude.id
instance Data.ProtoLens.Message SemanticRetrieval where
  messageName _ = Data.Text.pack "xai_api.SemanticRetrieval"
  packedMessageDescriptor _
    = "\n\
      \\DC1SemanticRetrieval\DC27\n\
      \\breranker\CAN\SOH \SOH(\v2\SYN.xai_api.RerankerModelH\NULR\breranker\136\SOH\SOHB\v\n\
      \\t_reranker"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        reranker__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "reranker"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor RerankerModel)
              (Data.ProtoLens.OptionalField
                 (Data.ProtoLens.Field.field @"maybe'reranker")) ::
              Data.ProtoLens.FieldDescriptor SemanticRetrieval
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, reranker__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _SemanticRetrieval'_unknownFields
        (\ x__ y__ -> x__ {_SemanticRetrieval'_unknownFields = y__})
  defMessage
    = SemanticRetrieval'_constructor
        {_SemanticRetrieval'reranker = Prelude.Nothing,
         _SemanticRetrieval'_unknownFields = []}
  parseMessage
    = let
        loop ::
          SemanticRetrieval
          -> Data.ProtoLens.Encoding.Bytes.Parser SemanticRetrieval
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
                                       "reranker"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"reranker") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "SemanticRetrieval"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (case
                  Lens.Family2.view (Data.ProtoLens.Field.field @"maybe'reranker") _x
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
                (Lens.Family2.view Data.ProtoLens.unknownFields _x))
instance Control.DeepSeq.NFData SemanticRetrieval where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_SemanticRetrieval'_unknownFields x__)
             (Control.DeepSeq.deepseq (_SemanticRetrieval'reranker x__) ())
data Documents = Documents {}
instance Data.ProtoLens.Service.Types.Service Documents where
  type ServiceName Documents = "Documents"
  type ServicePackage Documents = "xai_api"
  type ServiceMethods Documents = '["search"]
  packedServiceDescriptor _
    = "\n\
      \\tDocuments\DC2;\n\
      \\ACKSearch\DC2\SYN.xai_api.SearchRequest\SUB\ETB.xai_api.SearchResponse\"\NUL"
instance Data.ProtoLens.Service.Types.HasMethodImpl Documents "search" where
  type MethodName Documents "search" = "Search"
  type MethodInput Documents "search" = SearchRequest
  type MethodOutput Documents "search" = SearchResponse
  type MethodStreamingType Documents "search" = 'Data.ProtoLens.Service.Types.NonStreaming
packedFileDescriptor :: Data.ByteString.ByteString
packedFileDescriptor
  = "\n\
    \\SUBxai/api/v1/documents.proto\DC2\axai_api\"\253\SOH\n\
    \\SIHybridRetrieval\DC20\n\
    \\DC1search_multiplier\CAN\SOH \SOH(\ENQH\SOHR\DLEsearchMultiplier\136\SOH\SOH\DC2?\n\
    \\SOreranker_model\CAN\STX \SOH(\v2\SYN.xai_api.RerankerModelH\NULR\rrerankerModel\DC2U\n\
    \\SYNreciprocal_rank_fusion\CAN\ETX \SOH(\v2\GS.xai_api.ReciprocalRankFusionH\NULR\DC4reciprocalRankFusionB\n\
    \\n\
    \\brerankerB\DC4\n\
    \\DC2_search_multiplier\"X\n\
    \\DLEKeywordRetrieval\DC27\n\
    \\breranker\CAN\SOH \SOH(\v2\SYN.xai_api.RerankerModelH\NULR\breranker\136\SOH\SOHB\v\n\
    \\t_reranker\"Y\n\
    \\DC1SemanticRetrieval\DC27\n\
    \\breranker\CAN\SOH \SOH(\v2\SYN.xai_api.RerankerModelH\NULR\breranker\136\SOH\SOHB\v\n\
    \\t_reranker\"\129\SOH\n\
    \\DC4ReciprocalRankFusion\DC2\DC1\n\
    \\SOHk\CAN\SOH \SOH(\ENQH\NULR\SOHk\136\SOH\SOH\DC2)\n\
    \\DLEembedding_weight\CAN\ETX \SOH(\STXR\SIembeddingWeight\DC2\US\n\
    \\vtext_weight\CAN\EOT \SOH(\STXR\n\
    \textWeightB\EOT\n\
    \\STX_kJ\EOT\b\STX\DLE\ETX\"n\n\
    \\rRerankerModel\DC2\EM\n\
    \\ENQmodel\CAN\SOH \SOH(\tH\NULR\ENQmodel\136\SOH\SOH\DC2'\n\
    \\finstructions\CAN\STX \SOH(\tH\SOHR\finstructions\136\SOH\SOHB\b\n\
    \\ACK_modelB\SI\n\
    \\r_instructions\"\159\EOT\n\
    \\rSearchRequest\DC2\DC4\n\
    \\ENQquery\CAN\SOH \SOH(\tR\ENQquery\DC20\n\
    \\ACKsource\CAN\STX \SOH(\v2\CAN.xai_api.DocumentsSourceR\ACKsource\DC2\EM\n\
    \\ENQlimit\CAN\ETX \SOH(\ENQH\SOHR\ENQlimit\136\SOH\SOH\DC2'\n\
    \\finstructions\CAN\ENQ \SOH(\tH\STXR\finstructions\136\SOH\SOH\DC2E\n\
    \\DLEhybrid_retrieval\CAN\v \SOH(\v2\CAN.xai_api.HybridRetrievalH\NULR\SIhybridRetrieval\DC2K\n\
    \\DC2semantic_retrieval\CAN\f \SOH(\v2\SUB.xai_api.SemanticRetrievalH\NULR\DC1semanticRetrieval\DC2H\n\
    \\DC1keyword_retrieval\CAN\r \SOH(\v2\EM.xai_api.KeywordRetrievalH\NULR\DLEkeywordRetrieval\DC2F\n\
    \\SOranking_metric\CAN\EOT \SOH(\SO2\SYN.xai_api.RankingMetricH\ETXR\rrankingMetricB\STX\CAN\SOH\136\SOH\SOHB\DLE\n\
    \\SOretrieval_modeB\b\n\
    \\ACK_limitB\SI\n\
    \\r_instructionsB\DC1\n\
    \\SI_ranking_metricJ\EOT\b\ACK\DLE\aJ\EOT\b\a\DLE\bJ\EOT\b\b\DLE\tJ\EOT\b\t\DLE\n\
    \J\EOT\b\n\
    \\DLE\v\"@\n\
    \\SOSearchResponse\DC2.\n\
    \\amatches\CAN\SOH \ETX(\v2\DC4.xai_api.SearchMatchR\amatches\"\163\SOH\n\
    \\vSearchMatch\DC2\ETB\n\
    \\afile_id\CAN\SOH \SOH(\tR\ACKfileId\DC2\EM\n\
    \\bchunk_id\CAN\STX \SOH(\tR\achunkId\DC2#\n\
    \\rchunk_content\CAN\ETX \SOH(\tR\fchunkContent\DC2\DC4\n\
    \\ENQscore\CAN\EOT \SOH(\STXR\ENQscore\DC2%\n\
    \\SOcollection_ids\CAN\ENQ \ETX(\tR\rcollectionIds\"8\n\
    \\SIDocumentsSource\DC2%\n\
    \\SOcollection_ids\CAN\SOH \ETX(\tR\rcollectionIds*q\n\
    \\rRankingMetric\DC2\SUB\n\
    \\SYNRANKING_METRIC_UNKNOWN\DLE\NUL\DC2\RS\n\
    \\SUBRANKING_METRIC_L2_DISTANCE\DLE\SOH\DC2$\n\
    \ RANKING_METRIC_COSINE_SIMILARITY\DLE\STX2H\n\
    \\tDocuments\DC2;\n\
    \\ACKSearch\DC2\SYN.xai_api.SearchRequest\SUB\ETB.xai_api.SearchResponse\"\NULJ\249-\n\
    \\a\DC2\ENQ\NUL\NUL\139\SOH\SOH\n\
    \\b\n\
    \\SOH\f\DC2\ETX\NUL\NUL\DC2\n\
    \\b\n\
    \\SOH\STX\DC2\ETX\STX\NUL\DLE\n\
    \\n\
    \\n\
    \\STX\ACK\NUL\DC2\EOT\EOT\NUL\ACK\SOH\n\
    \\n\
    \\n\
    \\ETX\ACK\NUL\SOH\DC2\ETX\EOT\b\DC1\n\
    \\v\n\
    \\EOT\ACK\NUL\STX\NUL\DC2\ETX\ENQ\STX7\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\NUL\SOH\DC2\ETX\ENQ\ACK\f\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\NUL\STX\DC2\ETX\ENQ\r\SUB\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\NUL\ETX\DC2\ETX\ENQ%3\n\
    \Q\n\
    \\STX\EOT\NUL\DC2\EOT\t\NUL\ETB\SOH\SUBE Document search using a combination of keyword and semantic search.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\EOT\NUL\SOH\DC2\ETX\t\b\ETB\n\
    \\154\STX\n\
    \\EOT\EOT\NUL\STX\NUL\DC2\ETX\SO\STX'\SUB\140\STX Overfetch multiplier applied to the requested search limit.\n\
    \ When set, fetches (limit * search_multiplier) results from each retrieval method\n\
    \ before reranking, then returns the top `limit` results after reranking.\n\
    \ Valid range is [1, 100]. Defaults to 1 when unset.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\EOT\DC2\ETX\SO\STX\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\ENQ\DC2\ETX\SO\v\DLE\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\SOH\DC2\ETX\SO\DC1\"\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\ETX\DC2\ETX\SO%&\n\
    \L\n\
    \\EOT\EOT\NUL\b\NUL\DC2\EOT\DC1\STX\SYN\ETX\SUB> Which reranker to use to limit results to the desired value.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\b\NUL\SOH\DC2\ETX\DC1\b\DLE\n\
    \=\n\
    \\EOT\EOT\NUL\STX\SOH\DC2\ETX\DC3\EOT%\SUB0 Use a reranker model to perform the reranking.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\SOH\ACK\DC2\ETX\DC3\EOT\DC1\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\SOH\SOH\DC2\ETX\DC3\DC2 \n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\SOH\ETX\DC2\ETX\DC3#$\n\
    \0\n\
    \\EOT\EOT\NUL\STX\STX\DC2\ETX\NAK\EOT4\SUB# Use RRF to perform the reranking.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\STX\ACK\DC2\ETX\NAK\EOT\CAN\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\STX\SOH\DC2\ETX\NAK\EM/\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\STX\ETX\DC2\ETX\NAK23\n\
    \I\n\
    \\STX\EOT\SOH\DC2\EOT\SUB\NUL\GS\SOH\SUB= Document search using keyword matching (sparse embeddings).\n\
    \\n\
    \\n\
    \\n\
    \\ETX\EOT\SOH\SOH\DC2\ETX\SUB\b\CAN\n\
    \W\n\
    \\EOT\EOT\SOH\STX\NUL\DC2\ETX\FS\STX&\SUBJ Optional, but always used when doing search across multiple collections.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\EOT\DC2\ETX\FS\STX\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\ACK\DC2\ETX\FS\v\CAN\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\SOH\DC2\ETX\FS\EM!\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\ETX\DC2\ETX\FS$%\n\
    \K\n\
    \\STX\EOT\STX\DC2\EOT \NUL#\SOH\SUB? Document search using semantic similarity (dense embeddings).\n\
    \\n\
    \\n\
    \\n\
    \\ETX\EOT\STX\SOH\DC2\ETX \b\EM\n\
    \W\n\
    \\EOT\EOT\STX\STX\NUL\DC2\ETX\"\STX&\SUBJ Optional, but always used when doing search across multiple collections.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\NUL\EOT\DC2\ETX\"\STX\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\NUL\ACK\DC2\ETX\"\v\CAN\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\NUL\SOH\DC2\ETX\"\EM!\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\NUL\ETX\DC2\ETX\"$%\n\
    \G\n\
    \\STX\EOT\ETX\DC2\EOT&\NUL2\SOH\SUB; Configuration for reciprocal rank fusion (RRF) reranking.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\EOT\ETX\SOH\DC2\ETX&\b\FS\n\
    \]\n\
    \\EOT\EOT\ETX\STX\NUL\DC2\ETX(\STX\ETB\SUBP The RRF constant k used in the reciprocal rank fusion formula. Defaults to 60.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\NUL\EOT\DC2\ETX(\STX\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\NUL\ENQ\DC2\ETX(\v\DLE\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\NUL\SOH\DC2\ETX(\DC1\DC2\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\NUL\ETX\DC2\ETX(\NAK\SYN\n\
    \g\n\
    \\EOT\EOT\ETX\STX\SOH\DC2\ETX+\STX\GS\SUBZ Weight for embedding (dense) search results. Should be between 0 and 1. Defaults to 0.5.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\SOH\ENQ\DC2\ETX+\STX\a\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\SOH\SOH\DC2\ETX+\b\CAN\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\SOH\ETX\DC2\ETX+\ESC\FS\n\
    \f\n\
    \\EOT\EOT\ETX\STX\STX\DC2\ETX.\STX\CAN\SUBY Weight for keyword (sparse) search results. Should be between 0 and 1. Defaults to 0.5.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\STX\ENQ\DC2\ETX.\STX\a\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\STX\SOH\DC2\ETX.\b\DC3\n\
    \\f\n\
    \\ENQ\EOT\ETX\STX\STX\ETX\DC2\ETX.\SYN\ETB\n\
    \G\n\
    \\ETX\EOT\ETX\t\DC2\ETX1\STX\r\SUB; Deprecated: Use embedding_weight and text_weight instead.\n\
    \\n\
    \\v\n\
    \\EOT\EOT\ETX\t\NUL\DC2\ETX1\v\f\n\
    \\f\n\
    \\ENQ\EOT\ETX\t\NUL\SOH\DC2\ETX1\v\f\n\
    \\f\n\
    \\ENQ\EOT\ETX\t\NUL\STX\DC2\ETX1\v\f\n\
    \6\n\
    \\STX\EOT\EOT\DC2\EOT5\NUL;\SOH\SUB* Configuration for model-based reranking.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\EOT\EOT\SOH\DC2\ETX5\b\NAK\n\
    \S\n\
    \\EOT\EOT\EOT\STX\NUL\DC2\ETX7\STX\FS\SUBF The model to use for reranking. Defaults to standard reranker model.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\NUL\EOT\DC2\ETX7\STX\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\NUL\ENQ\DC2\ETX7\v\DC1\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\NUL\SOH\DC2\ETX7\DC2\ETB\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\NUL\ETX\DC2\ETX7\SUB\ESC\n\
    \`\n\
    \\EOT\EOT\EOT\STX\SOH\DC2\ETX:\STX#\SUBS Instructions for the reranking model. Defaults to generic reranking instructions.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\SOH\EOT\DC2\ETX:\STX\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\SOH\ENQ\DC2\ETX:\v\DC1\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\SOH\SOH\DC2\ETX:\DC2\RS\n\
    \\f\n\
    \\ENQ\EOT\EOT\STX\SOH\ETX\DC2\ETX:!\"\n\
    \\139\SOH\n\
    \\STX\ENQ\NUL\DC2\EOT?\NULC\SOH\SUB\DEL RankingMetric is the metric to use for the search.\n\
    \ Deprecated: Metric now comes from what is set in the collection creation.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\ENQ\NUL\SOH\DC2\ETX?\ENQ\DC2\n\
    \\v\n\
    \\EOT\ENQ\NUL\STX\NUL\DC2\ETX@\STX\GS\n\
    \\f\n\
    \\ENQ\ENQ\NUL\STX\NUL\SOH\DC2\ETX@\STX\CAN\n\
    \\f\n\
    \\ENQ\ENQ\NUL\STX\NUL\STX\DC2\ETX@\ESC\FS\n\
    \\v\n\
    \\EOT\ENQ\NUL\STX\SOH\DC2\ETXA\STX!\n\
    \\f\n\
    \\ENQ\ENQ\NUL\STX\SOH\SOH\DC2\ETXA\STX\FS\n\
    \\f\n\
    \\ENQ\ENQ\NUL\STX\SOH\STX\DC2\ETXA\US \n\
    \\v\n\
    \\EOT\ENQ\NUL\STX\STX\DC2\ETXB\STX'\n\
    \\f\n\
    \\ENQ\ENQ\NUL\STX\STX\SOH\DC2\ETXB\STX\"\n\
    \\f\n\
    \\ENQ\ENQ\NUL\STX\STX\STX\DC2\ETXB%&\n\
    \L\n\
    \\STX\EOT\ENQ\DC2\EOTF\NULc\SOH\SUB@ Message that contains settings needed to do a document search.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\EOT\ENQ\SOH\DC2\ETXF\b\NAK\n\
    \\134\SOH\n\
    \\EOT\EOT\ENQ\STX\NUL\DC2\ETXI\STX\DC3\SUBy The query to search for which will be embedded using the\n\
    \ same embedding model as the one used for the source to query.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\NUL\ENQ\DC2\ETXI\STX\b\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\NUL\SOH\DC2\ETXI\t\SO\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\NUL\ETX\DC2\ETXI\DC1\DC2\n\
    \#\n\
    \\EOT\EOT\ENQ\STX\SOH\DC2\ETXK\STX\GS\SUB\SYN The source to query.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\SOH\ACK\DC2\ETXK\STX\DC1\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\SOH\SOH\DC2\ETXK\DC2\CAN\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\SOH\ETX\DC2\ETXK\ESC\FS\n\
    \v\n\
    \\EOT\EOT\ENQ\STX\STX\DC2\ETXO\STX\ESC\SUBi The number of chunks to return.\n\
    \ Will always return the top matching chunks.\n\
    \ Optional, defaults to 10.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\STX\EOT\DC2\ETXO\STX\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\STX\ENQ\DC2\ETXO\v\DLE\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\STX\SOH\DC2\ETXO\DC1\SYN\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\STX\ETX\DC2\ETXO\EM\SUB\n\
    \u\n\
    \\EOT\EOT\ENQ\STX\ETX\DC2\ETXQ\STX#\SUBh User-defined instructions to be included in the search query. Defaults to generic search instructions.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\ETX\EOT\DC2\ETXQ\STX\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\ETX\ENQ\DC2\ETXQ\v\DC1\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\ETX\SOH\DC2\ETXQ\DC2\RS\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\ETX\ETX\DC2\ETXQ!\"\n\
    \O\n\
    \\EOT\EOT\ENQ\b\NUL\DC2\EOTT\STXX\ETX\SUBA How to perform the document search. Defaults to HybridRetrieval\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\ENQ\b\NUL\SOH\DC2\ETXT\b\SYN\n\
    \\v\n\
    \\EOT\EOT\ENQ\STX\EOT\DC2\ETXU\EOT*\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\EOT\ACK\DC2\ETXU\EOT\DC3\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\EOT\SOH\DC2\ETXU\DC4$\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\EOT\ETX\DC2\ETXU')\n\
    \\v\n\
    \\EOT\EOT\ENQ\STX\ENQ\DC2\ETXV\EOT.\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\ENQ\ACK\DC2\ETXV\EOT\NAK\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\ENQ\SOH\DC2\ETXV\SYN(\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\ENQ\ETX\DC2\ETXV+-\n\
    \\v\n\
    \\EOT\EOT\ENQ\STX\ACK\DC2\ETXW\EOT,\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\ACK\ACK\DC2\ETXW\EOT\DC4\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\ACK\SOH\DC2\ETXW\NAK&\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\ACK\ETX\DC2\ETXW)+\n\
    \X\n\
    \\EOT\EOT\ENQ\STX\a\DC2\ETX[\STX@\SUBK Deprecated: Metric now comes from what is set during collection creation.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\a\EOT\DC2\ETX[\STX\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\a\ACK\DC2\ETX[\v\CAN\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\a\SOH\DC2\ETX[\EM'\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\a\ETX\DC2\ETX[*+\n\
    \\f\n\
    \\ENQ\EOT\ENQ\STX\a\b\DC2\ETX[,?\n\
    \\r\n\
    \\ACK\EOT\ENQ\STX\a\b\ETX\DC2\ETX[->\n\
    \4\n\
    \\ETX\EOT\ENQ\t\DC2\ETX^\STX\r\SUB( Deprecated: Use retrieval_mode instead\n\
    \\n\
    \\v\n\
    \\EOT\EOT\ENQ\t\NUL\DC2\ETX^\v\f\n\
    \\f\n\
    \\ENQ\EOT\ENQ\t\NUL\SOH\DC2\ETX^\v\f\n\
    \\f\n\
    \\ENQ\EOT\ENQ\t\NUL\STX\DC2\ETX^\v\f\n\
    \\n\
    \\n\
    \\ETX\EOT\ENQ\t\DC2\ETX_\STX\r\n\
    \\v\n\
    \\EOT\EOT\ENQ\t\SOH\DC2\ETX_\v\f\n\
    \\f\n\
    \\ENQ\EOT\ENQ\t\SOH\SOH\DC2\ETX_\v\f\n\
    \\f\n\
    \\ENQ\EOT\ENQ\t\SOH\STX\DC2\ETX_\v\f\n\
    \\n\
    \\n\
    \\ETX\EOT\ENQ\t\DC2\ETX`\STX\r\n\
    \\v\n\
    \\EOT\EOT\ENQ\t\STX\DC2\ETX`\v\f\n\
    \\f\n\
    \\ENQ\EOT\ENQ\t\STX\SOH\DC2\ETX`\v\f\n\
    \\f\n\
    \\ENQ\EOT\ENQ\t\STX\STX\DC2\ETX`\v\f\n\
    \\n\
    \\n\
    \\ETX\EOT\ENQ\t\DC2\ETXa\STX\r\n\
    \\v\n\
    \\EOT\EOT\ENQ\t\ETX\DC2\ETXa\v\f\n\
    \\f\n\
    \\ENQ\EOT\ENQ\t\ETX\SOH\DC2\ETXa\v\f\n\
    \\f\n\
    \\ENQ\EOT\ENQ\t\ETX\STX\DC2\ETXa\v\f\n\
    \\n\
    \\n\
    \\ETX\EOT\ENQ\t\DC2\ETXb\STX\SO\n\
    \\v\n\
    \\EOT\EOT\ENQ\t\EOT\DC2\ETXb\v\r\n\
    \\f\n\
    \\ENQ\EOT\ENQ\t\EOT\SOH\DC2\ETXb\v\r\n\
    \\f\n\
    \\ENQ\EOT\ENQ\t\EOT\STX\DC2\ETXb\v\r\n\
    \\170\SOH\n\
    \\STX\EOT\ACK\DC2\EOTg\NULk\SOH\SUB\157\SOH SearchResponse message contains the results of a document search operation.\n\
    \ It returns a collection of matching document chunks sorted by relevance score.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\EOT\ACK\SOH\DC2\ETXg\b\SYN\n\
    \}\n\
    \\EOT\EOT\ACK\STX\NUL\DC2\ETXj\STX#\SUBp Collection of document chunks that match the search query, ordered by relevance score\n\
    \ from highest to lowest.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\ACK\STX\NUL\EOT\DC2\ETXj\STX\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\ACK\STX\NUL\ACK\DC2\ETXj\v\SYN\n\
    \\f\n\
    \\ENQ\EOT\ACK\STX\NUL\SOH\DC2\ETXj\ETB\RS\n\
    \\f\n\
    \\ENQ\EOT\ACK\STX\NUL\ETX\DC2\ETXj!\"\n\
    \\220\SOH\n\
    \\STX\EOT\a\DC2\ENQp\NUL\129\SOH\SOH\SUB\206\SOH SearchMatch message represents a single document chunk that matches the search query.\n\
    \ It contains the document ID, chunk ID, content text, and a relevance score indicating\n\
    \ how well it matches the query.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\EOT\a\SOH\DC2\ETXp\b\DC3\n\
    \R\n\
    \\EOT\EOT\a\STX\NUL\DC2\ETXr\STX\NAK\SUBE Unique identifier of the document that contains the matching chunk.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\a\STX\NUL\ENQ\DC2\ETXr\STX\b\n\
    \\f\n\
    \\ENQ\EOT\a\STX\NUL\SOH\DC2\ETXr\t\DLE\n\
    \\f\n\
    \\ENQ\EOT\a\STX\NUL\ETX\DC2\ETXr\DC3\DC4\n\
    \i\n\
    \\EOT\EOT\a\STX\SOH\DC2\ETXu\STX\SYN\SUB\\ Unique identifier of the specific chunk within the document that matched the search query.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\a\STX\SOH\ENQ\DC2\ETXu\STX\b\n\
    \\f\n\
    \\ENQ\EOT\a\STX\SOH\SOH\DC2\ETXu\t\DC1\n\
    \\f\n\
    \\ENQ\EOT\a\STX\SOH\ETX\DC2\ETXu\DC4\NAK\n\
    \_\n\
    \\EOT\EOT\a\STX\STX\DC2\ETXx\STX\ESC\SUBR The actual text content of the matching chunk that can be presented to the user.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\a\STX\STX\ENQ\DC2\ETXx\STX\b\n\
    \\f\n\
    \\ENQ\EOT\a\STX\STX\SOH\DC2\ETXx\t\SYN\n\
    \\f\n\
    \\ENQ\EOT\a\STX\STX\ETX\DC2\ETXx\EM\SUB\n\
    \\246\SOH\n\
    \\EOT\EOT\a\STX\ETX\DC2\ETX}\STX\DC2\SUB\232\SOH Score is the score of the chunk, which is determined by the ranking metric.\n\
    \ For L2 distance, lower scores indicate better matches. Range is [0, inf).\n\
    \ For cosine similarity, higher scores indicate better matches. Range is [0, 1].\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\a\STX\ETX\ENQ\DC2\ETX}\STX\a\n\
    \\f\n\
    \\ENQ\EOT\a\STX\ETX\SOH\DC2\ETX}\b\r\n\
    \\f\n\
    \\ENQ\EOT\a\STX\ETX\ETX\DC2\ETX}\DLE\DC1\n\
    \N\n\
    \\EOT\EOT\a\STX\EOT\DC2\EOT\128\SOH\STX%\SUB@ The ID(s) of the collection(s) to which this document belongs.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\a\STX\EOT\EOT\DC2\EOT\128\SOH\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\a\STX\EOT\ENQ\DC2\EOT\128\SOH\v\DC1\n\
    \\r\n\
    \\ENQ\EOT\a\STX\EOT\SOH\DC2\EOT\128\SOH\DC2 \n\
    \\r\n\
    \\ENQ\EOT\a\STX\EOT\ETX\DC2\EOT\128\SOH#$\n\
    \\162\STX\n\
    \\STX\EOT\b\DC2\ACK\136\SOH\NUL\139\SOH\SOH\SUB\147\STX Configuration for a documents sources in search requests.\n\
    \\n\
    \ This message configures a source for search content within documents or collections of documents.\n\
    \ Those documents must be uploaded through the management API or directly on the xAI console:\n\
    \ https://console.x.ai.\n\
    \\n\
    \\v\n\
    \\ETX\EOT\b\SOH\DC2\EOT\136\SOH\b\ETB\n\
    \*\n\
    \\EOT\EOT\b\STX\NUL\DC2\EOT\138\SOH\STX%\SUB\FS IDs of collections to use.\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\b\STX\NUL\EOT\DC2\EOT\138\SOH\STX\n\
    \\n\
    \\r\n\
    \\ENQ\EOT\b\STX\NUL\ENQ\DC2\EOT\138\SOH\v\DC1\n\
    \\r\n\
    \\ENQ\EOT\b\STX\NUL\SOH\DC2\EOT\138\SOH\DC2 \n\
    \\r\n\
    \\ENQ\EOT\b\STX\NUL\ETX\DC2\EOT\138\SOH#$b\ACKproto3"