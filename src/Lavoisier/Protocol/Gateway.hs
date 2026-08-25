{- | The 'Gateway' contract: a frontend that serves the shared agent. Ported from Rust
@lvz-protocol@ @gateway.rs@ (@Arc\<dyn Gateway\>@ → a record of functions).
-}
module Lavoisier.Protocol.Gateway (
    GatewayError (..),
    Gateway (..),
)
where

import Data.Text (Text)

import Lavoisier.Protocol.Agent (AgentHandle)

-- | Errors a gateway can fail with.
data GatewayError
    = -- | Could not bind\/authenticate (a genuine config error; surfaces immediately).
      GEBind Text
    | -- | A transient I\/O failure (retryable).
      GEIo Text
    | -- | A protocol-level failure.
      GEProtocol Text
    deriving stock (Eq, Show)

{- | A gateway, as a record of functions. 'gatewayServe' runs until shutdown, driving the shared
'AgentHandle'.
-}
data Gateway = Gateway
    { gatewayName ∷ Text
    , gatewayServe ∷ AgentHandle → IO (Either GatewayError ())
    }
