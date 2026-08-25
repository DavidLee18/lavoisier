-- | A minimal, dependency-free **pull-based stream** — the Haskell analogue of Rust's
-- @BoxStream<'static, T>@. A 'Producer' yields items on demand ('Nothing' = end of stream); the
-- provider adapters build one over an HTTP body reader, and the agent loop / gateways consume it.
--
-- Rolling our own (rather than pulling in @conduit@/@streaming@) matches the repo's minimal-deps
-- ethos and stays faithful to the original: @BoxStream@ is itself a pull-based async iterator.
module Lavoisier.Protocol.Stream
  ( Producer (..),
    fromList,
    drain,
    forEach,
    mapProducer,
    prepend,
  )
where

import Data.IORef (atomicModifyIORef', newIORef)

-- | A pull stream: each call to 'nextItem' yields the next item, or 'Nothing' at the end.
newtype Producer a = Producer {nextItem :: IO (Maybe a)}

-- | A producer that yields the elements of a list, in order.
fromList :: [a] -> IO (Producer a)
fromList xs0 = do
  ref <- newIORef xs0
  pure $
    Producer $
      atomicModifyIORef' ref $ \case
        [] -> ([], Nothing)
        (x : rest) -> (rest, Just x)

-- | Pull every item into a list (forces the whole stream).
drain :: Producer a -> IO [a]
drain p = go id
  where
    go acc =
      nextItem p >>= \case
        Nothing -> pure (acc [])
        Just x -> go (acc . (x :))

-- | Run an action for each item as it arrives.
forEach :: Producer a -> (a -> IO ()) -> IO ()
forEach p f = loop
  where
    loop =
      nextItem p >>= \case
        Nothing -> pure ()
        Just x -> f x >> loop

-- | Yield the given items first, then everything the underlying producer yields. Used to emit
-- capability notices ahead of a provider's own events without buffering the stream.
prepend :: [a] -> Producer a -> IO (Producer a)
prepend [] p = pure p
prepend xs0 p = do
  ref <- newIORef xs0
  pure $
    Producer $
      atomicModifyIORef' ref (\case [] -> ([], Nothing); (x : rest) -> (rest, Just x))
        >>= \case
          Just x -> pure (Just x)
          Nothing -> nextItem p

-- | Transform each item as it is pulled (lazy — no buffering).
mapProducer :: (a -> b) -> Producer a -> Producer b
mapProducer f p = Producer (fmap (fmap f) (nextItem p))
