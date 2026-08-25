-- | The auto-batch contract (ports Rust @lvz-protocol::batch@): a provider capability for running
-- many independent 'ChatRequest's as one discounted asynchronous job (Anthropic\/Google message
-- batches, ~50% token cost). Kept a records-of-functions value (the @Arc\<dyn Batch\>@ analogue) so
-- the @batch_edit@ tool is decoupled from the concrete batch API — and testable against a mock.
module Lavoisier.Protocol.Batch
  ( BatchTask (..),
    BatchItem (..),
    batchItem,
    attachNotices,
    BatchError (..),
    Batch (..),
  )
where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Lavoisier.Protocol.Event (Usage)
import Lavoisier.Protocol.Message (ChatRequest)

-- | One request in a batch run: a caller-chosen @custom_id@ (echoed back to correlate the result)
-- and the request to run under it.
data BatchTask = BatchTask
  { btId :: Text,
    btRequest :: ChatRequest
  }

-- | The outcome of one batched request, correlated by 'btId'. @biError@ is set when that item failed
-- (the others still return); otherwise @biText@ is the completion.
--
-- @biNotices@ carries capability notices raised when the task was negotiated at submit time — the
-- batch analogue of the @Notice@ events the streaming path emits. A batch has no event stream, so
-- without this a degraded knob (@--thinking@ against a provider with no extended thinking) would be
-- applied silently, which is the failure the negotiation work exists to remove.
data BatchItem = BatchItem
  { biId :: Text,
    biText :: Text,
    biUsage :: Usage,
    biError :: Maybe Text,
    biNotices :: [Text]
  }
  deriving stock (Show, Eq)

-- | A 'BatchItem' with no notices — the common case, and the shape every result parser builds before
-- submit-time notices are attached. Prefer this to the positional constructor.
batchItem :: Text -> Text -> Usage -> Maybe Text -> BatchItem
batchItem i t u e = BatchItem i t u e []

-- | Attach submit-time capability notices to the parsed results, correlating on @custom_id@. An
-- item with no entry keeps an empty list.
attachNotices :: Map Text [Text] -> [BatchItem] -> [BatchItem]
attachNotices byId = map (\it -> it {biNotices = Map.findWithDefault [] (biId it) byId})

-- | A whole-batch transport\/API failure (aborts the run; no items returned).
newtype BatchError = BatchError Text
  deriving stock (Show, Eq)

-- | The batch runner: submit tasks, poll to completion, fetch — returned as one call.
newtype Batch = Batch
  { runBatch :: [BatchTask] -> IO (Either BatchError [BatchItem])
  }
