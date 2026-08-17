-- | The auto-batch contract (ports Rust @lvz-protocol::batch@): a provider capability for running
-- many independent 'ChatRequest's as one discounted asynchronous job (Anthropic\/Google message
-- batches, ~50% token cost). Kept a records-of-functions value (the @Arc\<dyn Batch\>@ analogue) so
-- the @batch_edit@ tool is decoupled from the concrete batch API — and testable against a mock.
module Lavoisier.Protocol.Batch
  ( BatchTask (..),
    BatchItem (..),
    BatchError (..),
    Batch (..),
  )
where

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
data BatchItem = BatchItem
  { biId :: Text,
    biText :: Text,
    biUsage :: Usage,
    biError :: Maybe Text
  }
  deriving stock (Show, Eq)

-- | A whole-batch transport\/API failure (aborts the run; no items returned).
newtype BatchError = BatchError Text
  deriving stock (Show, Eq)

-- | The batch runner: submit tasks, poll to completion, fetch — returned as one call.
newtype Batch = Batch
  { runBatch :: [BatchTask] -> IO (Either BatchError [BatchItem])
  }
