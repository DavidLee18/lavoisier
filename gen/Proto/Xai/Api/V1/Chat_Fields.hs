{- This file was auto-generated from xai/api/v1/chat.proto by the proto-lens-protoc program. -}
{-# LANGUAGE ScopedTypeVariables, DataKinds, TypeFamilies, UndecidableInstances, GeneralizedNewtypeDeriving, MultiParamTypeClasses, FlexibleContexts, FlexibleInstances, PatternSynonyms, MagicHash, NoImplicitPrelude, DataKinds, BangPatterns, TypeApplications, OverloadedStrings, DerivingStrategies#-}
{-# OPTIONS_GHC -Wno-unused-imports#-}
{-# OPTIONS_GHC -Wno-duplicate-exports#-}
{-# OPTIONS_GHC -Wno-dodgy-exports#-}
module Proto.Xai.Api.V1.Chat_Fields where
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
agentCount ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "agentCount" a) =>
  Lens.Family2.LensLike' f s a
agentCount = Data.ProtoLens.Field.field @"agentCount"
allowedDomains ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "allowedDomains" a) =>
  Lens.Family2.LensLike' f s a
allowedDomains = Data.ProtoLens.Field.field @"allowedDomains"
allowedToolNames ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "allowedToolNames" a) =>
  Lens.Family2.LensLike' f s a
allowedToolNames = Data.ProtoLens.Field.field @"allowedToolNames"
allowedWebsites ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "allowedWebsites" a) =>
  Lens.Family2.LensLike' f s a
allowedWebsites = Data.ProtoLens.Field.field @"allowedWebsites"
allowedXHandles ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "allowedXHandles" a) =>
  Lens.Family2.LensLike' f s a
allowedXHandles = Data.ProtoLens.Field.field @"allowedXHandles"
arguments ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "arguments" a) =>
  Lens.Family2.LensLike' f s a
arguments = Data.ProtoLens.Field.field @"arguments"
attachmentSearch ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "attachmentSearch" a) =>
  Lens.Family2.LensLike' f s a
attachmentSearch = Data.ProtoLens.Field.field @"attachmentSearch"
attempts ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "attempts" a) =>
  Lens.Family2.LensLike' f s a
attempts = Data.ProtoLens.Field.field @"attempts"
authorization ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "authorization" a) =>
  Lens.Family2.LensLike' f s a
authorization = Data.ProtoLens.Field.field @"authorization"
bytes ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "bytes" a) =>
  Lens.Family2.LensLike' f s a
bytes = Data.ProtoLens.Field.field @"bytes"
cacheReadCount ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "cacheReadCount" a) =>
  Lens.Family2.LensLike' f s a
cacheReadCount = Data.ProtoLens.Field.field @"cacheReadCount"
cacheReadInputBytes ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "cacheReadInputBytes" a) =>
  Lens.Family2.LensLike' f s a
cacheReadInputBytes
  = Data.ProtoLens.Field.field @"cacheReadInputBytes"
cacheWriteCount ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "cacheWriteCount" a) =>
  Lens.Family2.LensLike' f s a
cacheWriteCount = Data.ProtoLens.Field.field @"cacheWriteCount"
cacheWriteInputBytes ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "cacheWriteInputBytes" a) =>
  Lens.Family2.LensLike' f s a
cacheWriteInputBytes
  = Data.ProtoLens.Field.field @"cacheWriteInputBytes"
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
chunks ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "chunks" a) =>
  Lens.Family2.LensLike' f s a
chunks = Data.ProtoLens.Field.field @"chunks"
citations ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "citations" a) =>
  Lens.Family2.LensLike' f s a
citations = Data.ProtoLens.Field.field @"citations"
city ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "city" a) =>
  Lens.Family2.LensLike' f s a
city = Data.ProtoLens.Field.field @"city"
codeExecution ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "codeExecution" a) =>
  Lens.Family2.LensLike' f s a
codeExecution = Data.ProtoLens.Field.field @"codeExecution"
collectionIds ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "collectionIds" a) =>
  Lens.Family2.LensLike' f s a
collectionIds = Data.ProtoLens.Field.field @"collectionIds"
collectionsCitation ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "collectionsCitation" a) =>
  Lens.Family2.LensLike' f s a
collectionsCitation
  = Data.ProtoLens.Field.field @"collectionsCitation"
collectionsSearch ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "collectionsSearch" a) =>
  Lens.Family2.LensLike' f s a
collectionsSearch = Data.ProtoLens.Field.field @"collectionsSearch"
content ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "content" a) =>
  Lens.Family2.LensLike' f s a
content = Data.ProtoLens.Field.field @"content"
country ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "country" a) =>
  Lens.Family2.LensLike' f s a
country = Data.ProtoLens.Field.field @"country"
created ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "created" a) =>
  Lens.Family2.LensLike' f s a
created = Data.ProtoLens.Field.field @"created"
data' ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "data'" a) =>
  Lens.Family2.LensLike' f s a
data' = Data.ProtoLens.Field.field @"data'"
debugOutput ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "debugOutput" a) =>
  Lens.Family2.LensLike' f s a
debugOutput = Data.ProtoLens.Field.field @"debugOutput"
delta ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "delta" a) =>
  Lens.Family2.LensLike' f s a
delta = Data.ProtoLens.Field.field @"delta"
description ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "description" a) =>
  Lens.Family2.LensLike' f s a
description = Data.ProtoLens.Field.field @"description"
droppedMessageCount ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "droppedMessageCount" a) =>
  Lens.Family2.LensLike' f s a
droppedMessageCount
  = Data.ProtoLens.Field.field @"droppedMessageCount"
enableImageSearch ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "enableImageSearch" a) =>
  Lens.Family2.LensLike' f s a
enableImageSearch = Data.ProtoLens.Field.field @"enableImageSearch"
enableImageUnderstanding ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "enableImageUnderstanding" a) =>
  Lens.Family2.LensLike' f s a
enableImageUnderstanding
  = Data.ProtoLens.Field.field @"enableImageUnderstanding"
enableVideoUnderstanding ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "enableVideoUnderstanding" a) =>
  Lens.Family2.LensLike' f s a
enableVideoUnderstanding
  = Data.ProtoLens.Field.field @"enableVideoUnderstanding"
encryptedContent ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "encryptedContent" a) =>
  Lens.Family2.LensLike' f s a
encryptedContent = Data.ProtoLens.Field.field @"encryptedContent"
endIndex ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "endIndex" a) =>
  Lens.Family2.LensLike' f s a
endIndex = Data.ProtoLens.Field.field @"endIndex"
engineRequest ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "engineRequest" a) =>
  Lens.Family2.LensLike' f s a
engineRequest = Data.ProtoLens.Field.field @"engineRequest"
errorMessage ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "errorMessage" a) =>
  Lens.Family2.LensLike' f s a
errorMessage = Data.ProtoLens.Field.field @"errorMessage"
excludedDomains ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "excludedDomains" a) =>
  Lens.Family2.LensLike' f s a
excludedDomains = Data.ProtoLens.Field.field @"excludedDomains"
excludedWebsites ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "excludedWebsites" a) =>
  Lens.Family2.LensLike' f s a
excludedWebsites = Data.ProtoLens.Field.field @"excludedWebsites"
excludedXHandles ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "excludedXHandles" a) =>
  Lens.Family2.LensLike' f s a
excludedXHandles = Data.ProtoLens.Field.field @"excludedXHandles"
extraHeaders ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "extraHeaders" a) =>
  Lens.Family2.LensLike' f s a
extraHeaders = Data.ProtoLens.Field.field @"extraHeaders"
file ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "file" a) =>
  Lens.Family2.LensLike' f s a
file = Data.ProtoLens.Field.field @"file"
fileId ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "fileId" a) =>
  Lens.Family2.LensLike' f s a
fileId = Data.ProtoLens.Field.field @"fileId"
filename ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "filename" a) =>
  Lens.Family2.LensLike' f s a
filename = Data.ProtoLens.Field.field @"filename"
finishReason ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "finishReason" a) =>
  Lens.Family2.LensLike' f s a
finishReason = Data.ProtoLens.Field.field @"finishReason"
formatType ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "formatType" a) =>
  Lens.Family2.LensLike' f s a
formatType = Data.ProtoLens.Field.field @"formatType"
frequencyPenalty ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "frequencyPenalty" a) =>
  Lens.Family2.LensLike' f s a
frequencyPenalty = Data.ProtoLens.Field.field @"frequencyPenalty"
fromDate ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "fromDate" a) =>
  Lens.Family2.LensLike' f s a
fromDate = Data.ProtoLens.Field.field @"fromDate"
function ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "function" a) =>
  Lens.Family2.LensLike' f s a
function = Data.ProtoLens.Field.field @"function"
functionName ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "functionName" a) =>
  Lens.Family2.LensLike' f s a
functionName = Data.ProtoLens.Field.field @"functionName"
hybridRetrieval ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "hybridRetrieval" a) =>
  Lens.Family2.LensLike' f s a
hybridRetrieval = Data.ProtoLens.Field.field @"hybridRetrieval"
id ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "id" a) =>
  Lens.Family2.LensLike' f s a
id = Data.ProtoLens.Field.field @"id"
imageUrl ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "imageUrl" a) =>
  Lens.Family2.LensLike' f s a
imageUrl = Data.ProtoLens.Field.field @"imageUrl"
include ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "include" a) =>
  Lens.Family2.LensLike' f s a
include = Data.ProtoLens.Field.field @"include"
includedXHandles ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "includedXHandles" a) =>
  Lens.Family2.LensLike' f s a
includedXHandles = Data.ProtoLens.Field.field @"includedXHandles"
index ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "index" a) =>
  Lens.Family2.LensLike' f s a
index = Data.ProtoLens.Field.field @"index"
input ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "input" a) =>
  Lens.Family2.LensLike' f s a
input = Data.ProtoLens.Field.field @"input"
instructions ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "instructions" a) =>
  Lens.Family2.LensLike' f s a
instructions = Data.ProtoLens.Field.field @"instructions"
key ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "key" a) =>
  Lens.Family2.LensLike' f s a
key = Data.ProtoLens.Field.field @"key"
keywordRetrieval ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "keywordRetrieval" a) =>
  Lens.Family2.LensLike' f s a
keywordRetrieval = Data.ProtoLens.Field.field @"keywordRetrieval"
lbAddress ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "lbAddress" a) =>
  Lens.Family2.LensLike' f s a
lbAddress = Data.ProtoLens.Field.field @"lbAddress"
limit ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "limit" a) =>
  Lens.Family2.LensLike' f s a
limit = Data.ProtoLens.Field.field @"limit"
links ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "links" a) =>
  Lens.Family2.LensLike' f s a
links = Data.ProtoLens.Field.field @"links"
logprob ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "logprob" a) =>
  Lens.Family2.LensLike' f s a
logprob = Data.ProtoLens.Field.field @"logprob"
logprobs ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "logprobs" a) =>
  Lens.Family2.LensLike' f s a
logprobs = Data.ProtoLens.Field.field @"logprobs"
maxSearchResults ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maxSearchResults" a) =>
  Lens.Family2.LensLike' f s a
maxSearchResults = Data.ProtoLens.Field.field @"maxSearchResults"
maxTokens ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maxTokens" a) =>
  Lens.Family2.LensLike' f s a
maxTokens = Data.ProtoLens.Field.field @"maxTokens"
maxTurns ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maxTurns" a) =>
  Lens.Family2.LensLike' f s a
maxTurns = Data.ProtoLens.Field.field @"maxTurns"
maybe'agentCount ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'agentCount" a) =>
  Lens.Family2.LensLike' f s a
maybe'agentCount = Data.ProtoLens.Field.field @"maybe'agentCount"
maybe'attachmentSearch ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'attachmentSearch" a) =>
  Lens.Family2.LensLike' f s a
maybe'attachmentSearch
  = Data.ProtoLens.Field.field @"maybe'attachmentSearch"
maybe'authorization ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'authorization" a) =>
  Lens.Family2.LensLike' f s a
maybe'authorization
  = Data.ProtoLens.Field.field @"maybe'authorization"
maybe'citation ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'citation" a) =>
  Lens.Family2.LensLike' f s a
maybe'citation = Data.ProtoLens.Field.field @"maybe'citation"
maybe'city ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'city" a) =>
  Lens.Family2.LensLike' f s a
maybe'city = Data.ProtoLens.Field.field @"maybe'city"
maybe'codeExecution ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'codeExecution" a) =>
  Lens.Family2.LensLike' f s a
maybe'codeExecution
  = Data.ProtoLens.Field.field @"maybe'codeExecution"
maybe'collectionsCitation ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'collectionsCitation" a) =>
  Lens.Family2.LensLike' f s a
maybe'collectionsCitation
  = Data.ProtoLens.Field.field @"maybe'collectionsCitation"
maybe'collectionsSearch ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'collectionsSearch" a) =>
  Lens.Family2.LensLike' f s a
maybe'collectionsSearch
  = Data.ProtoLens.Field.field @"maybe'collectionsSearch"
maybe'content ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'content" a) =>
  Lens.Family2.LensLike' f s a
maybe'content = Data.ProtoLens.Field.field @"maybe'content"
maybe'country ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'country" a) =>
  Lens.Family2.LensLike' f s a
maybe'country = Data.ProtoLens.Field.field @"maybe'country"
maybe'created ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'created" a) =>
  Lens.Family2.LensLike' f s a
maybe'created = Data.ProtoLens.Field.field @"maybe'created"
maybe'debugOutput ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'debugOutput" a) =>
  Lens.Family2.LensLike' f s a
maybe'debugOutput = Data.ProtoLens.Field.field @"maybe'debugOutput"
maybe'delta ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'delta" a) =>
  Lens.Family2.LensLike' f s a
maybe'delta = Data.ProtoLens.Field.field @"maybe'delta"
maybe'enableImageSearch ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'enableImageSearch" a) =>
  Lens.Family2.LensLike' f s a
maybe'enableImageSearch
  = Data.ProtoLens.Field.field @"maybe'enableImageSearch"
maybe'enableImageUnderstanding ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'enableImageUnderstanding" a) =>
  Lens.Family2.LensLike' f s a
maybe'enableImageUnderstanding
  = Data.ProtoLens.Field.field @"maybe'enableImageUnderstanding"
maybe'enableVideoUnderstanding ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'enableVideoUnderstanding" a) =>
  Lens.Family2.LensLike' f s a
maybe'enableVideoUnderstanding
  = Data.ProtoLens.Field.field @"maybe'enableVideoUnderstanding"
maybe'errorMessage ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'errorMessage" a) =>
  Lens.Family2.LensLike' f s a
maybe'errorMessage
  = Data.ProtoLens.Field.field @"maybe'errorMessage"
maybe'file ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'file" a) =>
  Lens.Family2.LensLike' f s a
maybe'file = Data.ProtoLens.Field.field @"maybe'file"
maybe'frequencyPenalty ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'frequencyPenalty" a) =>
  Lens.Family2.LensLike' f s a
maybe'frequencyPenalty
  = Data.ProtoLens.Field.field @"maybe'frequencyPenalty"
maybe'fromDate ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'fromDate" a) =>
  Lens.Family2.LensLike' f s a
maybe'fromDate = Data.ProtoLens.Field.field @"maybe'fromDate"
maybe'function ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'function" a) =>
  Lens.Family2.LensLike' f s a
maybe'function = Data.ProtoLens.Field.field @"maybe'function"
maybe'functionName ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'functionName" a) =>
  Lens.Family2.LensLike' f s a
maybe'functionName
  = Data.ProtoLens.Field.field @"maybe'functionName"
maybe'hybridRetrieval ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'hybridRetrieval" a) =>
  Lens.Family2.LensLike' f s a
maybe'hybridRetrieval
  = Data.ProtoLens.Field.field @"maybe'hybridRetrieval"
maybe'imageUrl ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'imageUrl" a) =>
  Lens.Family2.LensLike' f s a
maybe'imageUrl = Data.ProtoLens.Field.field @"maybe'imageUrl"
maybe'instructions ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'instructions" a) =>
  Lens.Family2.LensLike' f s a
maybe'instructions
  = Data.ProtoLens.Field.field @"maybe'instructions"
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
maybe'logprobs ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'logprobs" a) =>
  Lens.Family2.LensLike' f s a
maybe'logprobs = Data.ProtoLens.Field.field @"maybe'logprobs"
maybe'maxSearchResults ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'maxSearchResults" a) =>
  Lens.Family2.LensLike' f s a
maybe'maxSearchResults
  = Data.ProtoLens.Field.field @"maybe'maxSearchResults"
maybe'maxTokens ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'maxTokens" a) =>
  Lens.Family2.LensLike' f s a
maybe'maxTokens = Data.ProtoLens.Field.field @"maybe'maxTokens"
maybe'maxTurns ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'maxTurns" a) =>
  Lens.Family2.LensLike' f s a
maybe'maxTurns = Data.ProtoLens.Field.field @"maybe'maxTurns"
maybe'mcp ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'mcp" a) =>
  Lens.Family2.LensLike' f s a
maybe'mcp = Data.ProtoLens.Field.field @"maybe'mcp"
maybe'message ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'message" a) =>
  Lens.Family2.LensLike' f s a
maybe'message = Data.ProtoLens.Field.field @"maybe'message"
maybe'mode ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'mode" a) =>
  Lens.Family2.LensLike' f s a
maybe'mode = Data.ProtoLens.Field.field @"maybe'mode"
maybe'n ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "maybe'n" a) =>
  Lens.Family2.LensLike' f s a
maybe'n = Data.ProtoLens.Field.field @"maybe'n"
maybe'news ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'news" a) =>
  Lens.Family2.LensLike' f s a
maybe'news = Data.ProtoLens.Field.field @"maybe'news"
maybe'parallelToolCalls ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'parallelToolCalls" a) =>
  Lens.Family2.LensLike' f s a
maybe'parallelToolCalls
  = Data.ProtoLens.Field.field @"maybe'parallelToolCalls"
maybe'postFavoriteCount ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'postFavoriteCount" a) =>
  Lens.Family2.LensLike' f s a
maybe'postFavoriteCount
  = Data.ProtoLens.Field.field @"maybe'postFavoriteCount"
maybe'postViewCount ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'postViewCount" a) =>
  Lens.Family2.LensLike' f s a
maybe'postViewCount
  = Data.ProtoLens.Field.field @"maybe'postViewCount"
maybe'presencePenalty ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'presencePenalty" a) =>
  Lens.Family2.LensLike' f s a
maybe'presencePenalty
  = Data.ProtoLens.Field.field @"maybe'presencePenalty"
maybe'previousResponseId ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'previousResponseId" a) =>
  Lens.Family2.LensLike' f s a
maybe'previousResponseId
  = Data.ProtoLens.Field.field @"maybe'previousResponseId"
maybe'reasoningContent ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'reasoningContent" a) =>
  Lens.Family2.LensLike' f s a
maybe'reasoningContent
  = Data.ProtoLens.Field.field @"maybe'reasoningContent"
maybe'reasoningEffort ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'reasoningEffort" a) =>
  Lens.Family2.LensLike' f s a
maybe'reasoningEffort
  = Data.ProtoLens.Field.field @"maybe'reasoningEffort"
maybe'region ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'region" a) =>
  Lens.Family2.LensLike' f s a
maybe'region = Data.ProtoLens.Field.field @"maybe'region"
maybe'response ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'response" a) =>
  Lens.Family2.LensLike' f s a
maybe'response = Data.ProtoLens.Field.field @"maybe'response"
maybe'responseFormat ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'responseFormat" a) =>
  Lens.Family2.LensLike' f s a
maybe'responseFormat
  = Data.ProtoLens.Field.field @"maybe'responseFormat"
maybe'retrievalMode ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'retrievalMode" a) =>
  Lens.Family2.LensLike' f s a
maybe'retrievalMode
  = Data.ProtoLens.Field.field @"maybe'retrievalMode"
maybe'rss ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'rss" a) =>
  Lens.Family2.LensLike' f s a
maybe'rss = Data.ProtoLens.Field.field @"maybe'rss"
maybe'schema ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'schema" a) =>
  Lens.Family2.LensLike' f s a
maybe'schema = Data.ProtoLens.Field.field @"maybe'schema"
maybe'searchParameters ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'searchParameters" a) =>
  Lens.Family2.LensLike' f s a
maybe'searchParameters
  = Data.ProtoLens.Field.field @"maybe'searchParameters"
maybe'seed ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'seed" a) =>
  Lens.Family2.LensLike' f s a
maybe'seed = Data.ProtoLens.Field.field @"maybe'seed"
maybe'semanticRetrieval ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'semanticRetrieval" a) =>
  Lens.Family2.LensLike' f s a
maybe'semanticRetrieval
  = Data.ProtoLens.Field.field @"maybe'semanticRetrieval"
maybe'settings ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'settings" a) =>
  Lens.Family2.LensLike' f s a
maybe'settings = Data.ProtoLens.Field.field @"maybe'settings"
maybe'source ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'source" a) =>
  Lens.Family2.LensLike' f s a
maybe'source = Data.ProtoLens.Field.field @"maybe'source"
maybe'temperature ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'temperature" a) =>
  Lens.Family2.LensLike' f s a
maybe'temperature = Data.ProtoLens.Field.field @"maybe'temperature"
maybe'text ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'text" a) =>
  Lens.Family2.LensLike' f s a
maybe'text = Data.ProtoLens.Field.field @"maybe'text"
maybe'timezone ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'timezone" a) =>
  Lens.Family2.LensLike' f s a
maybe'timezone = Data.ProtoLens.Field.field @"maybe'timezone"
maybe'toDate ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'toDate" a) =>
  Lens.Family2.LensLike' f s a
maybe'toDate = Data.ProtoLens.Field.field @"maybe'toDate"
maybe'tool ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'tool" a) =>
  Lens.Family2.LensLike' f s a
maybe'tool = Data.ProtoLens.Field.field @"maybe'tool"
maybe'toolCallId ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'toolCallId" a) =>
  Lens.Family2.LensLike' f s a
maybe'toolCallId = Data.ProtoLens.Field.field @"maybe'toolCallId"
maybe'toolChoice ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'toolChoice" a) =>
  Lens.Family2.LensLike' f s a
maybe'toolChoice = Data.ProtoLens.Field.field @"maybe'toolChoice"
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
maybe'userLocation ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'userLocation" a) =>
  Lens.Family2.LensLike' f s a
maybe'userLocation
  = Data.ProtoLens.Field.field @"maybe'userLocation"
maybe'web ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'web" a) =>
  Lens.Family2.LensLike' f s a
maybe'web = Data.ProtoLens.Field.field @"maybe'web"
maybe'webCitation ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'webCitation" a) =>
  Lens.Family2.LensLike' f s a
maybe'webCitation = Data.ProtoLens.Field.field @"maybe'webCitation"
maybe'webSearch ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'webSearch" a) =>
  Lens.Family2.LensLike' f s a
maybe'webSearch = Data.ProtoLens.Field.field @"maybe'webSearch"
maybe'x ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "maybe'x" a) =>
  Lens.Family2.LensLike' f s a
maybe'x = Data.ProtoLens.Field.field @"maybe'x"
maybe'xCitation ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'xCitation" a) =>
  Lens.Family2.LensLike' f s a
maybe'xCitation = Data.ProtoLens.Field.field @"maybe'xCitation"
maybe'xSearch ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "maybe'xSearch" a) =>
  Lens.Family2.LensLike' f s a
maybe'xSearch = Data.ProtoLens.Field.field @"maybe'xSearch"
mcp ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "mcp" a) =>
  Lens.Family2.LensLike' f s a
mcp = Data.ProtoLens.Field.field @"mcp"
message ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "message" a) =>
  Lens.Family2.LensLike' f s a
message = Data.ProtoLens.Field.field @"message"
messages ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "messages" a) =>
  Lens.Family2.LensLike' f s a
messages = Data.ProtoLens.Field.field @"messages"
mimeType ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "mimeType" a) =>
  Lens.Family2.LensLike' f s a
mimeType = Data.ProtoLens.Field.field @"mimeType"
mode ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "mode" a) =>
  Lens.Family2.LensLike' f s a
mode = Data.ProtoLens.Field.field @"mode"
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
name ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "name" a) =>
  Lens.Family2.LensLike' f s a
name = Data.ProtoLens.Field.field @"name"
news ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "news" a) =>
  Lens.Family2.LensLike' f s a
news = Data.ProtoLens.Field.field @"news"
outputs ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "outputs" a) =>
  Lens.Family2.LensLike' f s a
outputs = Data.ProtoLens.Field.field @"outputs"
parallelToolCalls ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "parallelToolCalls" a) =>
  Lens.Family2.LensLike' f s a
parallelToolCalls = Data.ProtoLens.Field.field @"parallelToolCalls"
parameters ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "parameters" a) =>
  Lens.Family2.LensLike' f s a
parameters = Data.ProtoLens.Field.field @"parameters"
postFavoriteCount ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "postFavoriteCount" a) =>
  Lens.Family2.LensLike' f s a
postFavoriteCount = Data.ProtoLens.Field.field @"postFavoriteCount"
postViewCount ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "postViewCount" a) =>
  Lens.Family2.LensLike' f s a
postViewCount = Data.ProtoLens.Field.field @"postViewCount"
presencePenalty ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "presencePenalty" a) =>
  Lens.Family2.LensLike' f s a
presencePenalty = Data.ProtoLens.Field.field @"presencePenalty"
previousResponseId ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "previousResponseId" a) =>
  Lens.Family2.LensLike' f s a
previousResponseId
  = Data.ProtoLens.Field.field @"previousResponseId"
prompt ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "prompt" a) =>
  Lens.Family2.LensLike' f s a
prompt = Data.ProtoLens.Field.field @"prompt"
reasoningContent ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "reasoningContent" a) =>
  Lens.Family2.LensLike' f s a
reasoningContent = Data.ProtoLens.Field.field @"reasoningContent"
reasoningEffort ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "reasoningEffort" a) =>
  Lens.Family2.LensLike' f s a
reasoningEffort = Data.ProtoLens.Field.field @"reasoningEffort"
region ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "region" a) =>
  Lens.Family2.LensLike' f s a
region = Data.ProtoLens.Field.field @"region"
request ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "request" a) =>
  Lens.Family2.LensLike' f s a
request = Data.ProtoLens.Field.field @"request"
response ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "response" a) =>
  Lens.Family2.LensLike' f s a
response = Data.ProtoLens.Field.field @"response"
responseFormat ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "responseFormat" a) =>
  Lens.Family2.LensLike' f s a
responseFormat = Data.ProtoLens.Field.field @"responseFormat"
responseId ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "responseId" a) =>
  Lens.Family2.LensLike' f s a
responseId = Data.ProtoLens.Field.field @"responseId"
responses ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "responses" a) =>
  Lens.Family2.LensLike' f s a
responses = Data.ProtoLens.Field.field @"responses"
returnCitations ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "returnCitations" a) =>
  Lens.Family2.LensLike' f s a
returnCitations = Data.ProtoLens.Field.field @"returnCitations"
role ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "role" a) =>
  Lens.Family2.LensLike' f s a
role = Data.ProtoLens.Field.field @"role"
rss ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "rss" a) =>
  Lens.Family2.LensLike' f s a
rss = Data.ProtoLens.Field.field @"rss"
safeSearch ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "safeSearch" a) =>
  Lens.Family2.LensLike' f s a
safeSearch = Data.ProtoLens.Field.field @"safeSearch"
samplerTag ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "samplerTag" a) =>
  Lens.Family2.LensLike' f s a
samplerTag = Data.ProtoLens.Field.field @"samplerTag"
schema ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "schema" a) =>
  Lens.Family2.LensLike' f s a
schema = Data.ProtoLens.Field.field @"schema"
score ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "score" a) =>
  Lens.Family2.LensLike' f s a
score = Data.ProtoLens.Field.field @"score"
searchParameters ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "searchParameters" a) =>
  Lens.Family2.LensLike' f s a
searchParameters = Data.ProtoLens.Field.field @"searchParameters"
seed ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "seed" a) =>
  Lens.Family2.LensLike' f s a
seed = Data.ProtoLens.Field.field @"seed"
semanticRetrieval ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "semanticRetrieval" a) =>
  Lens.Family2.LensLike' f s a
semanticRetrieval = Data.ProtoLens.Field.field @"semanticRetrieval"
serverDescription ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "serverDescription" a) =>
  Lens.Family2.LensLike' f s a
serverDescription = Data.ProtoLens.Field.field @"serverDescription"
serverLabel ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "serverLabel" a) =>
  Lens.Family2.LensLike' f s a
serverLabel = Data.ProtoLens.Field.field @"serverLabel"
serverUrl ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "serverUrl" a) =>
  Lens.Family2.LensLike' f s a
serverUrl = Data.ProtoLens.Field.field @"serverUrl"
settings ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "settings" a) =>
  Lens.Family2.LensLike' f s a
settings = Data.ProtoLens.Field.field @"settings"
sources ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "sources" a) =>
  Lens.Family2.LensLike' f s a
sources = Data.ProtoLens.Field.field @"sources"
startIndex ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "startIndex" a) =>
  Lens.Family2.LensLike' f s a
startIndex = Data.ProtoLens.Field.field @"startIndex"
status ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "status" a) =>
  Lens.Family2.LensLike' f s a
status = Data.ProtoLens.Field.field @"status"
stop ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "stop" a) =>
  Lens.Family2.LensLike' f s a
stop = Data.ProtoLens.Field.field @"stop"
storeMessages ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "storeMessages" a) =>
  Lens.Family2.LensLike' f s a
storeMessages = Data.ProtoLens.Field.field @"storeMessages"
strict ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "strict" a) =>
  Lens.Family2.LensLike' f s a
strict = Data.ProtoLens.Field.field @"strict"
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
timezone ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "timezone" a) =>
  Lens.Family2.LensLike' f s a
timezone = Data.ProtoLens.Field.field @"timezone"
toDate ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "toDate" a) =>
  Lens.Family2.LensLike' f s a
toDate = Data.ProtoLens.Field.field @"toDate"
token ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "token" a) =>
  Lens.Family2.LensLike' f s a
token = Data.ProtoLens.Field.field @"token"
toolCallId ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "toolCallId" a) =>
  Lens.Family2.LensLike' f s a
toolCallId = Data.ProtoLens.Field.field @"toolCallId"
toolCalls ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "toolCalls" a) =>
  Lens.Family2.LensLike' f s a
toolCalls = Data.ProtoLens.Field.field @"toolCalls"
toolChoice ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "toolChoice" a) =>
  Lens.Family2.LensLike' f s a
toolChoice = Data.ProtoLens.Field.field @"toolChoice"
tools ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "tools" a) =>
  Lens.Family2.LensLike' f s a
tools = Data.ProtoLens.Field.field @"tools"
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
type' ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "type'" a) =>
  Lens.Family2.LensLike' f s a
type' = Data.ProtoLens.Field.field @"type'"
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
useEncryptedContent ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "useEncryptedContent" a) =>
  Lens.Family2.LensLike' f s a
useEncryptedContent
  = Data.ProtoLens.Field.field @"useEncryptedContent"
user ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "user" a) =>
  Lens.Family2.LensLike' f s a
user = Data.ProtoLens.Field.field @"user"
userLocation ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "userLocation" a) =>
  Lens.Family2.LensLike' f s a
userLocation = Data.ProtoLens.Field.field @"userLocation"
value ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "value" a) =>
  Lens.Family2.LensLike' f s a
value = Data.ProtoLens.Field.field @"value"
vec'allowedDomains ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "vec'allowedDomains" a) =>
  Lens.Family2.LensLike' f s a
vec'allowedDomains
  = Data.ProtoLens.Field.field @"vec'allowedDomains"
vec'allowedToolNames ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "vec'allowedToolNames" a) =>
  Lens.Family2.LensLike' f s a
vec'allowedToolNames
  = Data.ProtoLens.Field.field @"vec'allowedToolNames"
vec'allowedWebsites ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "vec'allowedWebsites" a) =>
  Lens.Family2.LensLike' f s a
vec'allowedWebsites
  = Data.ProtoLens.Field.field @"vec'allowedWebsites"
vec'allowedXHandles ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "vec'allowedXHandles" a) =>
  Lens.Family2.LensLike' f s a
vec'allowedXHandles
  = Data.ProtoLens.Field.field @"vec'allowedXHandles"
vec'chunks ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "vec'chunks" a) =>
  Lens.Family2.LensLike' f s a
vec'chunks = Data.ProtoLens.Field.field @"vec'chunks"
vec'citations ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "vec'citations" a) =>
  Lens.Family2.LensLike' f s a
vec'citations = Data.ProtoLens.Field.field @"vec'citations"
vec'collectionIds ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "vec'collectionIds" a) =>
  Lens.Family2.LensLike' f s a
vec'collectionIds = Data.ProtoLens.Field.field @"vec'collectionIds"
vec'content ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "vec'content" a) =>
  Lens.Family2.LensLike' f s a
vec'content = Data.ProtoLens.Field.field @"vec'content"
vec'excludedDomains ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "vec'excludedDomains" a) =>
  Lens.Family2.LensLike' f s a
vec'excludedDomains
  = Data.ProtoLens.Field.field @"vec'excludedDomains"
vec'excludedWebsites ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "vec'excludedWebsites" a) =>
  Lens.Family2.LensLike' f s a
vec'excludedWebsites
  = Data.ProtoLens.Field.field @"vec'excludedWebsites"
vec'excludedXHandles ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "vec'excludedXHandles" a) =>
  Lens.Family2.LensLike' f s a
vec'excludedXHandles
  = Data.ProtoLens.Field.field @"vec'excludedXHandles"
vec'include ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "vec'include" a) =>
  Lens.Family2.LensLike' f s a
vec'include = Data.ProtoLens.Field.field @"vec'include"
vec'includedXHandles ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "vec'includedXHandles" a) =>
  Lens.Family2.LensLike' f s a
vec'includedXHandles
  = Data.ProtoLens.Field.field @"vec'includedXHandles"
vec'input ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "vec'input" a) =>
  Lens.Family2.LensLike' f s a
vec'input = Data.ProtoLens.Field.field @"vec'input"
vec'links ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "vec'links" a) =>
  Lens.Family2.LensLike' f s a
vec'links = Data.ProtoLens.Field.field @"vec'links"
vec'messages ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "vec'messages" a) =>
  Lens.Family2.LensLike' f s a
vec'messages = Data.ProtoLens.Field.field @"vec'messages"
vec'outputs ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "vec'outputs" a) =>
  Lens.Family2.LensLike' f s a
vec'outputs = Data.ProtoLens.Field.field @"vec'outputs"
vec'responses ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "vec'responses" a) =>
  Lens.Family2.LensLike' f s a
vec'responses = Data.ProtoLens.Field.field @"vec'responses"
vec'sources ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "vec'sources" a) =>
  Lens.Family2.LensLike' f s a
vec'sources = Data.ProtoLens.Field.field @"vec'sources"
vec'stop ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "vec'stop" a) =>
  Lens.Family2.LensLike' f s a
vec'stop = Data.ProtoLens.Field.field @"vec'stop"
vec'toolCalls ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "vec'toolCalls" a) =>
  Lens.Family2.LensLike' f s a
vec'toolCalls = Data.ProtoLens.Field.field @"vec'toolCalls"
vec'tools ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "vec'tools" a) =>
  Lens.Family2.LensLike' f s a
vec'tools = Data.ProtoLens.Field.field @"vec'tools"
vec'topLogprobs ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "vec'topLogprobs" a) =>
  Lens.Family2.LensLike' f s a
vec'topLogprobs = Data.ProtoLens.Field.field @"vec'topLogprobs"
web ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "web" a) =>
  Lens.Family2.LensLike' f s a
web = Data.ProtoLens.Field.field @"web"
webCitation ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "webCitation" a) =>
  Lens.Family2.LensLike' f s a
webCitation = Data.ProtoLens.Field.field @"webCitation"
webSearch ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "webSearch" a) =>
  Lens.Family2.LensLike' f s a
webSearch = Data.ProtoLens.Field.field @"webSearch"
x ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "x" a) =>
  Lens.Family2.LensLike' f s a
x = Data.ProtoLens.Field.field @"x"
xCitation ::
  forall f s a.
  (Prelude.Functor f,
   Data.ProtoLens.Field.HasField s "xCitation" a) =>
  Lens.Family2.LensLike' f s a
xCitation = Data.ProtoLens.Field.field @"xCitation"
xSearch ::
  forall f s a.
  (Prelude.Functor f, Data.ProtoLens.Field.HasField s "xSearch" a) =>
  Lens.Family2.LensLike' f s a
xSearch = Data.ProtoLens.Field.field @"xSearch"