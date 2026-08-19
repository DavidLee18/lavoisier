-- | Rough USD cost estimation for the TUI footer, so it can show real spend instead of an abstract
-- token-equivalent.
--
-- Prices are __approximate list prices in USD per 1M tokens__, matched by model-name substring.
-- They drift — treat the footer's @$@ as an estimate (it is prefixed @~@), and update the table here
-- when list prices change. An unrecognised model yields 'Nothing', and the footer falls back to a raw
-- token count. Ported from Rust @lvz-gw-tui@ @price.rs@.
module Lavoisier.Gateway.Tui.Price
  ( estimateUsd,
    fmtTokens,
    fmtUsd,
  )
where

import Data.Text (Text)
import Data.Text qualified as T
import Data.Word (Word64)
import Lavoisier.Protocol.Event (Usage (..))
import Numeric (showFFloat)

-- | USD per 1M tokens for one model's four token classes.
data Price = Price
  { pInput :: Double,
    pOutput :: Double,
    pCacheRead :: Double,
    pCacheWrite :: Double
  }

-- | Look up a model's price by name substring (case-insensitive). Ordered most-specific first.
lookupPrice :: Text -> Maybe Price
lookupPrice model
  -- Anthropic
  | has "opus" = Just (Price 15.0 75.0 1.5 18.75)
  | has "sonnet" = Just (Price 3.0 15.0 0.30 3.75)
  | has "haiku" = Just (Price 0.80 4.0 0.08 1.0)
  -- xAI
  | has "grok" && has "mini" = Just (Price 0.30 0.50 0.075 0.30)
  | has "grok" = Just (Price 3.0 15.0 0.75 3.75)
  -- Google
  | has "gemini" && has "flash" = Just (Price 0.30 2.5 0.075 0.30)
  | has "gemini" = Just (Price 1.25 10.0 0.31 1.625)
  | otherwise = Nothing
  where
    m = T.toLower model
    has needle = needle `T.isInfixOf` m

-- | Estimate the USD spent for @usage@ on @model@, or 'Nothing' if the model isn't in the table.
estimateUsd :: Text -> Usage -> Maybe Double
estimateUsd model usage = do
  p <- lookupPrice model
  pure $
    ( fromIntegral (inputTokens usage) * pInput p
        + fromIntegral (outputTokens usage) * pOutput p
        + fromIntegral (cacheReadTokens usage) * pCacheRead p
        + fromIntegral (cacheCreationTokens usage) * pCacheWrite p
    )
      / 1_000_000.0

-- | A compact token count for the footer (@1234@ → @1.2k@).
fmtTokens :: Word64 -> Text
fmtTokens n
  | n >= 1000 = T.pack (showFFloat (Just 1) (fromIntegral n / 1000.0 :: Double) "") <> "k"
  | otherwise = T.pack (show n)

-- | A dollar amount at the footer's four-decimal precision.
fmtUsd :: Double -> Text
fmtUsd usd = T.pack (showFFloat (Just 4) usd "")
