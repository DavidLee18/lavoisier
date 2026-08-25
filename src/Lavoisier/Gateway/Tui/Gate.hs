{- | The TUI's tool-approval gate: a 'ToolGate' that bridges the agent's \"may I run this tool?\"
question to the render loop, which asks the user interactively.

Policy mirrors Claude Code's default: __read-only tools run unattended__; anything that mutates the
workspace or shells out (and any unrecognised tool — safe default) __asks first__. A per-tool
\"always allow\" set, populated when the user picks /always/, suppresses repeat prompts within the
session. Ported from Rust @lvz-gw-tui@ @gate.rs@ (@mpsc@ + @oneshot@ → a 'Chan' of requests, each
carrying its own reply 'MVar').
-}
module Lavoisier.Gateway.Tui.Gate (
    PermitReply (..),
    PermitRequest (..),
    Permits,
    newChannelGate,
    recvPermit,
    answerPermit,
    isReadOnly,
    argsPreview,
)
where

import Control.Concurrent.Chan
import Control.Concurrent.MVar
import Control.Exception (SomeException, try)
import Data.Aeson (Value (..), encode)
import Data.IORef
import Data.Scientific (floatingOrInteger)
import Data.Set (Set)
import Data.Text (Text)
import Data.Text.Encoding (decodeUtf8Lenient)

import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString.Lazy qualified as BL
import Data.Set qualified as Set
import Data.Text qualified as T

import Lavoisier.Protocol.Gate (ToolDecision (..), ToolGate (..))

-- | How the user (via the render loop) answers a prompt.
data PermitReply
    = -- | Run it this once.
      AllowOnce
    | -- | Run it, and stop asking for this tool for the rest of the session.
      AllowAlways
    | -- | Refuse; the model is told and can adapt.
      DenyOnce
    deriving stock (Eq, Show)

{- | A prompt sent from the gate (agent side) to the render loop (UI side), carrying the 'MVar' the
answer comes back on.
-}
data PermitRequest = PermitRequest
    { prName ∷ Text
    -- ^ The tool being called.
    , prArgs ∷ Text
    -- ^ Its arguments, pretty-printed for display (already truncated).
    , prReply ∷ MVar PermitReply
    -- ^ Where the render loop puts the user's decision.
    }

-- | The receiving end the render loop drains.
newtype Permits = Permits (Chan PermitRequest)

{- | Build a gate and the receiver the render loop drains. Install the gate on the agent with
'Lavoisier.Agent.withToolGate' and hand the receiver to the TUI.
-}
newChannelGate ∷ IO (ToolGate, Permits)
newChannelGate = do
    chan ← newChan
    always ← newIORef Set.empty
    pure (ToolGate (reviewWith chan always), Permits chan)

-- | Await the next approval prompt.
recvPermit ∷ Permits → IO PermitRequest
recvPermit (Permits chan) = readChan chan

-- | Answer an open prompt. A repeat answer (or one for an abandoned prompt) is harmless.
answerPermit ∷ PermitRequest → PermitReply → IO ()
answerPermit req reply = () <$ tryPutMVar (prReply req) reply

reviewWith ∷ Chan PermitRequest → IORef (Set Text) → Text → Value → IO ToolDecision
reviewWith chan always name args = do
    remembered ← readIORef always
    -- Read-only tools, and anything the user already said "always" to, run without a prompt.
    if isReadOnly name || Set.member name remembered
        then pure Allow
        else do
            reply ← newEmptyMVar
            -- If the UI is gone, fail safe: deny rather than silently run.
            sent ← try (writeChan chan (PermitRequest name (argsPreview args) reply)) ∷ IO (Either SomeException ())
            case sent of
                Left _ → pure (Deny "approval channel closed")
                Right () →
                    takeMVar reply >>= \case
                        AllowOnce → pure Allow
                        AllowAlways → modifyIORef' always (Set.insert name) >> pure Allow
                        DenyOnce → pure (Deny "declined by user")

{- | Whether a tool is read-only and so runs unattended (the Claude-Code default). Everything else —
edits, shells, and any unrecognised\/namespaced (MCP) tool — asks first.
-}
isReadOnly ∷ Text → Bool
isReadOnly name = any (`T.isPrefixOf` name) ["read", "list", "find", "grep", "search", "outline", "view", "cat"]

{- | A readable, pretty-printed preview of a call's arguments for the prompt (shown in scrollback, so
generously capped rather than one-lined).
-}
argsPreview ∷ Value → Text
argsPreview args
    | T.length s > cap = T.take cap s <> "…"
    | otherwise = s
    where
        cap = 2000
        s = prettyJson 0 args

{- | A two-space-indented rendering of a 'Value'. Hand-rolled rather than pulling in @aeson-pretty@
for one call site; scalars go through aeson's own encoder so escaping stays correct.
-}
prettyJson ∷ Int → Value → Text
prettyJson depth = \case
    Object o
        | KM.null o → "{}"
        | otherwise →
            "{\n"
                <> T.intercalate ",\n" [pad (depth + 1) <> scalar (String (K.toText k)) <> ": " <> prettyJson (depth + 1) v | (k, v) ← KM.toList o]
                <> "\n"
                <> pad depth
                <> "}"
    Array a
        | null a → "[]"
        | otherwise →
            "[\n"
                <> T.intercalate ",\n" [pad (depth + 1) <> prettyJson (depth + 1) v | v ← foldr (:) [] a]
                <> "\n"
                <> pad depth
                <> "]"
    v → scalar v
    where
        pad n = T.replicate (2 * n) " "
        -- Numbers render without aeson's scientific notation for plain integers; everything else uses
        -- aeson's encoder so string escaping is exactly the wire form.
        scalar (Number n) | Right (i ∷ Integer) ← (floatingOrInteger n ∷ Either Double Integer) = T.pack (show i)
        scalar v = decodeUtf8Lenient (BL.toStrict (encode v))
