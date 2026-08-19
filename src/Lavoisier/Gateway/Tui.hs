-- | @Lavoisier.Gateway.Tui@ — an __inline terminal-UI__ frontend for Lavoisier.
--
-- An interactive, scrollback-native REPL: it drives the shared agent via 'AgentHandle' and renders
-- the normalised 'Event' stream as a chat. Unlike a fullscreen (alt-screen) TUI it keeps an __inline
-- viewport__ — finalized output flows into the terminal's own scrollback (so natural scrolling,
-- copy\/paste, and @Ctrl-L@ all work), while a small live region at the bottom holds the input box, a
-- status line, and a token\/cost footer.
--
-- It is a __leaf frontend__: it depends only on the protocol contracts, never on a provider or on
-- the agent's internals, so the same shared agent drives the CLI, every network gateway, and this
-- TUI unchanged.
--
-- Concurrency: the render loop consumes one 'Chan' of 'UiMsg's fed by three producers — a key
-- reader, the __current turn's__ agent stream (a forked thread, never inline in the loop), and the
-- approval-prompt receiver. That separation is what lets a tool-approval prompt be answered while a
-- turn is mid-flight without deadlocking the stream that is waiting on the answer.
--
-- Ported from Rust @lvz-gw-tui@ 0.1.0. The Rust builds on @ratatui@\/@crossterm@\/@tui-textarea@;
-- the port drives the terminal with ANSI escapes directly (the inline viewport is a small amount of
-- cursor arithmetic) and reads raw keys through @unix@'s termios, in keeping with the tree's
-- hand-rolled adapters. @terminal-size@ is the one added dependency.
module Lavoisier.Gateway.Tui
  ( TuiConfig (..),
    defaultTuiConfig,
    tuiGateway,

    -- * Exposed for tests
    Command (..),
    parseCommand,
    toolHint,
    hardWrap,
    App (..),
    newApp,
    activeModel,
    footerLine,
  )
where

import Control.Concurrent (ThreadId, forkIO, killThread)
import Control.Concurrent.Chan
import Control.Exception (SomeException, bracket, finally, try)
import Control.Monad (forever, unless, when)
import Data.Aeson (Value (..), decodeStrict)
import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.IORef
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding (encodeUtf8)
import Data.Text.IO qualified as TIO
import Data.Word (Word64)
import Lavoisier.Gateway.Tui.Gate
import Lavoisier.Gateway.Tui.Md
import Lavoisier.Gateway.Tui.Price (estimateUsd, fmtTokens, fmtUsd)
import Lavoisier.Protocol.Agent (AgentHandle (..), TurnRequest (..), turnRequest)
import Lavoisier.Protocol.Event (Event (..), StopReason (..), Usage (..), accumulateUsage, emptyUsage)
import Lavoisier.Protocol.Gateway (Gateway (..), GatewayError (..))
import Lavoisier.Protocol.Stream (Producer (..))
import System.Console.Terminal.Size qualified as TS
import System.IO (BufferMode (NoBuffering), hFlush, hSetBuffering, hSetEcho, hSetEncoding, hWaitForInput, stdin, stdout, utf8)
import System.Posix.IO (stdInput)
import System.Posix.Terminal

-- | The inline viewport height: one status line + a 3-row bordered input + one footer line.
viewportHeight :: Int
viewportHeight = 5

-- | How the TUI gateway is configured.
data TuiConfig = TuiConfig
  { -- | Session id conversations run under (so memory accrues across turns).
    tuiSession :: Text,
    -- | Model label shown in the footer, and the baseline @\/model@ resets to.
    tuiModel :: Text,
    -- | The approval-prompt receiver paired with a gate installed on the agent. Without it, no
    -- prompts appear (every tool runs unattended).
    tuiPermits :: Maybe Permits
  }

-- | The default session (@tui@) and a generic model label, with no approval gate.
defaultTuiConfig :: TuiConfig
defaultTuiConfig = TuiConfig {tuiSession = "tui", tuiModel = "agent", tuiPermits = Nothing}

-- | The inline-TUI gateway. It takes over the terminal for the duration of 'gatewayServe'.
tuiGateway :: TuiConfig -> Gateway
tuiGateway cfg =
  Gateway
    { gatewayName = "tui",
      gatewayServe = \agent -> do
        r <- try (withRawTerminal (runTui cfg agent)) :: IO (Either SomeException ())
        pure (either (Left . GEIo . T.pack . show) Right r)
    }

-- --- messages -------------------------------------------------------------------------------------

-- | A key press, already decoded from its escape sequence.
data Key
  = KChar Char
  | KEnter
  | KAltEnter
  | KBackspace
  | KDelete
  | KLeft
  | KRight
  | KHome
  | KEnd
  | KEsc
  | KCtrlC
  | KCtrlD
  | KCtrlL
  deriving stock (Eq, Show)

-- | A message from the current turn's thread to the render loop, tagged with the turn generation so
-- events from a cancelled\/superseded turn are ignored.
data TurnMsg
  = -- | One normalised event from the agent stream.
    TmEvent Event
  | -- | The turn's stream errored (submit failure or mid-stream error).
    TmError Text
  | -- | The turn's stream ended.
    TmFinished

-- | Everything the render loop selects over, funnelled through one channel.
data UiMsg
  = UiKey Key
  | UiTurn Int TurnMsg
  | UiPermit PermitRequest
  | -- | stdin closed.
    UiEof

-- --- app state ------------------------------------------------------------------------------------

-- | The interactive state: the input buffer, the current turn, streaming buffers, and running totals.
data App = App
  { appSession :: Text,
    appModel :: Text,
    -- | The input buffer and the cursor's index into it (in characters).
    appInput :: Text,
    appCursor :: Int,
    appRunning :: Bool,
    appTurnGen :: Int,
    -- | The thread streaming the current turn, so @Ctrl-C@ can abort it (dropping the agent stream,
    -- which cancels the provider request).
    appTurnThread :: Maybe ThreadId,
    -- | The unfinished tail of the current assistant line (shown live on the status row; committed
    -- to scrollback on newline \/ turn end).
    appPending :: Text,
    -- | A transient status line (@thinking…@, @running shell…@).
    appStatus :: Text,
    -- | In-flight tool calls: id → name, and id → accumulated argument JSON.
    appToolNames :: Map Text Text,
    appToolArgs :: Map Text Text,
    appUsage :: Usage,
    -- | An open tool-approval prompt awaiting a keypress; while set, the viewport shows the prompt
    -- and keys answer it instead of editing the input.
    appPermit :: Maybe PermitRequest,
    -- | Whether the assistant stream is currently inside a @\`\`\`@ fenced code block (so those lines
    -- render as gutter-prefixed code). Reset at each turn's end.
    appInCodeFence :: Bool,
    -- | Buffered consecutive @|…|@ table rows, held until the table ends so columns can be aligned
    -- as a unit (a block construct can't be rendered line-by-line as it streams).
    appTableBuf :: [Text],
    -- | Monotonic counter backing @\/new@ fresh-session ids (no clock\/rng needed).
    appSessionSeq :: Int,
    -- | The @\/model@ override for this session, if any (else the configured model is used).
    appModelOverride :: Maybe Text
  }

newApp :: Text -> Text -> App
newApp session model =
  App
    { appSession = session,
      appModel = model,
      appInput = "",
      appCursor = 0,
      appRunning = False,
      appTurnGen = 0,
      appTurnThread = Nothing,
      appPending = "",
      appStatus = "",
      appToolNames = Map.empty,
      appToolArgs = Map.empty,
      appUsage = emptyUsage,
      appPermit = Nothing,
      appInCodeFence = False,
      appTableBuf = [],
      appSessionSeq = 0,
      appModelOverride = Nothing
    }

-- | The model this session's turns run on: the @\/model@ override if set, else the configured one.
activeModel :: App -> Text
activeModel app = fromMaybe (appModel app) (appModelOverride app)

-- --- slash commands -------------------------------------------------------------------------------

-- | A parsed slash command.
data Command
  = -- | List the available commands.
    CmdHelp
  | -- | Quit the TUI.
    CmdQuit
  | -- | Reset the running token\/cost totals.
    CmdClear
  | -- | Start a fresh conversation session.
    CmdNew
  | -- | Switch to (or, when empty, report) the named session.
    CmdSession Text
  | -- | Switch to (or, when empty, report) the model this session's turns run on. @reset@ clears the
    -- override back to the configured model.
    CmdModel Text
  | -- | An unrecognised command.
    CmdUnknown Text
  deriving stock (Eq, Show)

-- | Parse the text after a leading @\/@ into a 'Command'.
parseCommand :: Text -> Command
parseCommand cmd = case T.words cmd of
  [] -> CmdUnknown ""
  (verb : rest) -> case verb of
    _ | verb `elem` ["help", "h", "?"] -> CmdHelp
    _ | verb `elem` ["quit", "exit", "q"] -> CmdQuit
    _ | verb `elem` ["clear", "cls"] -> CmdClear
    "new" -> CmdNew
    _ | verb `elem` ["session", "s"] -> CmdSession (arg rest)
    _ | verb `elem` ["model", "m"] -> CmdModel (arg rest)
    other -> CmdUnknown other
  where
    arg (x : _) = x
    arg [] = ""

helpText :: Text
helpText = "commands: /help · /model <name|reset> · /session <id> · /new · /clear (reset counters) · /quit  —  Ctrl-L clears the screen"

-- --- the render loop ------------------------------------------------------------------------------

runTui :: TuiConfig -> AgentHandle -> IO ()
runTui cfg agent = do
  msgs <- newChan
  appRef <- newIORef (newApp (tuiSession cfg) (tuiModel cfg))
  keyThread <- forkIO (keyReader msgs)
  permitThread <- traverse (\p -> forkIO (forever (recvPermit p >>= writeChan msgs . UiPermit))) (tuiPermits cfg)
  reserveViewport
  emitWelcome
  readIORef appRef >>= drawViewport
  let cleanup = mapM_ killThread (keyThread : maybe [] pure permitThread)
  loop msgs appRef `finally` cleanup
  -- Leave the cursor on a fresh line below the (now-final) viewport.
  clearViewport
  TIO.putStrLn ""
  where
    loop msgs appRef = do
      msg <- readChan msgs
      app <- readIORef appRef
      quit <- case msg of
        UiEof -> pure True
        UiKey k -> handleKey msgs appRef agent app k
        UiTurn gen tm
          | gen == appTurnGen app -> handleTurnMsg appRef app tm >> pure False
          | otherwise -> pure False
        UiPermit req -> do
          -- Put the full call + arguments in scrollback (unbounded height), so the compact viewport
          -- prompt only has to carry the question.
          emitPermit (prName req) (prArgs req)
          writeIORef appRef app {appPermit = Just req}
          pure False
      unless quit $ do
        readIORef appRef >>= drawViewport
        loop msgs appRef

-- | Handle one key. Returns 'True' when the user asked to quit.
handleKey :: Chan UiMsg -> IORef App -> AgentHandle -> App -> Key -> IO Bool
handleKey msgs appRef agent app key
  -- Ctrl-C always wins — even mid-approval — so the user is never trapped.
  | key == KCtrlC =
      if appRunning app
        then do
          app' <- cancelTurn app
          writeIORef appRef app'
          emitNotice "cancelled"
          pure False
        else pure True
  -- An open approval prompt swallows keys until answered.
  | Just req <- appPermit app = do
      case permitReplyFor key of
        Nothing -> pure ()
        Just reply -> answerPermit req reply >> writeIORef appRef app {appPermit = Nothing}
      pure False
  | key == KCtrlD, T.null (appInput app) = pure True
  | key == KCtrlL = do
      clearScreen
      reserveViewport
      pure False
  | key == KEnter = do
      let prompt = appInput app
          trimmed = T.strip prompt
          app0 = app {appInput = "", appCursor = 0}
      if T.null trimmed || appRunning app
        then writeIORef appRef app0 >> pure False
        else case T.stripPrefix "/" trimmed of
          -- A leading `/` is a slash command, handled locally (never sent to the agent).
          Just cmd -> dispatchCommand appRef app0 cmd
          Nothing -> submitTurn msgs appRef agent app0 prompt >> pure False
  | otherwise = writeIORef appRef (editInput key app) >> pure False

-- | Answer an open approval prompt: @y@\/Enter allow once, @a@ allow-always, @n@\/Esc deny.
permitReplyFor :: Key -> Maybe PermitReply
permitReplyFor = \case
  KChar c | c `elem` ("yY" :: String) -> Just AllowOnce
  KEnter -> Just AllowOnce
  KChar c | c `elem` ("aA" :: String) -> Just AllowAlways
  KChar c | c `elem` ("nN" :: String) -> Just DenyOnce
  KEsc -> Just DenyOnce
  _ -> Nothing

-- | Apply an editing key to the input buffer.
editInput :: Key -> App -> App
editInput key app = case key of
  KChar c -> ins (T.singleton c)
  KAltEnter -> ins "\n"
  KBackspace
    | cur > 0 -> app {appInput = T.take (cur - 1) txt <> T.drop cur txt, appCursor = cur - 1}
    | otherwise -> app
  KDelete -> app {appInput = T.take cur txt <> T.drop (cur + 1) txt}
  KLeft -> app {appCursor = max 0 (cur - 1)}
  KRight -> app {appCursor = min (T.length txt) (cur + 1)}
  KHome -> app {appCursor = 0}
  KEnd -> app {appCursor = T.length txt}
  _ -> app
  where
    txt = appInput app
    cur = appCursor app
    ins s = app {appInput = T.take cur txt <> s <> T.drop cur txt, appCursor = cur + T.length s}

-- | Run a slash command against the app. Returns 'True' to quit.
dispatchCommand :: IORef App -> App -> Text -> IO Bool
dispatchCommand appRef app cmd = case parseCommand cmd of
  CmdHelp -> emitNotice helpText >> keep app
  CmdQuit -> pure True
  CmdClear -> do
    emitNotice "counters reset (Ctrl-L clears the screen)"
    keep app {appUsage = emptyUsage}
  CmdNew -> do
    let n = appSessionSeq app + 1
        sid = "tui-" <> T.pack (show n)
    emitNotice ("new session: " <> sid)
    keep app {appSessionSeq = n, appSession = sid}
  CmdSession "" -> emitNotice ("session: " <> appSession app) >> keep app
  CmdSession sid -> emitNotice ("switched to session: " <> sid) >> keep app {appSession = sid}
  CmdModel "" -> emitNotice ("model: " <> activeModel app) >> keep app
  CmdModel m
    | m `elem` ["reset", "default"] -> do
        emitNotice ("model reset to " <> appModel app)
        keep app {appModelOverride = Nothing}
  CmdModel name -> do
    emitNotice ("model set to " <> name <> " (next turn)")
    keep app {appModelOverride = Just name}
  CmdUnknown c -> emitNotice ("unknown command: /" <> c <> " (try /help)") >> keep app
  where
    keep a = writeIORef appRef a >> pure False

-- | Emit the user's line to scrollback and fork the turn thread that streams the agent's reply back
-- over the UI channel, tagged with a fresh generation.
submitTurn :: Chan UiMsg -> IORef App -> AgentHandle -> App -> Text -> IO ()
submitTurn msgs appRef agent app prompt = do
  emitUser prompt
  let gen = appTurnGen app + 1
      turn = (turnRequest (appSession app) prompt) {trModel = appModelOverride app}
      drain stream =
        nextItem stream >>= \case
          Nothing -> pure ()
          Just (Right ev) -> writeChan msgs (UiTurn gen (TmEvent ev)) >> drain stream
          Just (Left e) -> writeChan msgs (UiTurn gen (TmError (T.pack (show e))))
  tid <- forkIO $ do
    submit agent turn >>= \case
      Left e -> writeChan msgs (UiTurn gen (TmError (T.pack (show e))))
      Right stream -> drain stream
    writeChan msgs (UiTurn gen TmFinished)
  writeIORef appRef app {appTurnGen = gen, appRunning = True, appStatus = "", appTurnThread = Just tid}

-- | Fold one turn message into the conversation: stream text\/tool activity into scrollback and
-- update the live status\/footer.
handleTurnMsg :: IORef App -> App -> TurnMsg -> IO ()
handleTurnMsg appRef app = \case
  TmEvent ev -> onEvent appRef app ev
  TmError e -> do
    app' <- flushPending app
    emitError e
    writeIORef appRef (finishTurn app')
  TmFinished -> do
    app' <- flushPending app
    writeIORef appRef (finishTurn app')

-- | Map a single 'Event' onto scrollback + live state.
onEvent :: IORef App -> App -> Event -> IO ()
onEvent appRef app = \case
  TextDelta t -> pushText app t >>= writeIORef appRef
  Thinking _ -> writeIORef appRef app {appStatus = "thinking…"}
  ToolUseStart i n -> do
    app' <- flushPending app
    writeIORef appRef app' {appStatus = "running " <> n <> "…", appToolNames = Map.insert i n (appToolNames app')}
  ToolUseDelta i j -> writeIORef appRef app {appToolArgs = Map.insertWith (flip (<>)) i j (appToolArgs app)}
  ToolUseEnd i -> do
    let name = Map.findWithDefault "tool" i (appToolNames app)
        hint = maybe "" toolHint (Map.lookup i (appToolArgs app))
    emitTool name hint
    writeIORef appRef app {appStatus = "", appToolNames = Map.delete i (appToolNames app), appToolArgs = Map.delete i (appToolArgs app)}
  Notice t -> do
    app' <- flushPending app
    emitNotice t
    writeIORef appRef app'
  Citation src cited -> emitNotice ("[" <> src <> "] " <> cited) >> writeIORef appRef app
  Usage u -> writeIORef appRef app {appUsage = accumulateUsage u (appUsage app)}
  Done reason -> do
    app' <- flushPending app
    when (reason == Refusal) (emitNotice "(refused)")
    writeIORef appRef app'
  ServerToolUse _ n -> writeIORef appRef app {appStatus = "running " <> n <> "… (server)"}
  ServerToolResult _ _ -> writeIORef appRef app {appStatus = ""}

-- | A one-line hint from a tool call's accumulated argument JSON (the first string-ish value).
toolHint :: Text -> Text
toolHint argsJson = case decodeStrict (encodeUtf8 argsJson) of
  Just (Object o) -> firstOf ["path", "file", "cmd", "command", "query", "pattern"] o
  _ -> ""
  where
    firstOf [] _ = ""
    firstOf (k : ks) o = case KM.lookup (K.fromText k) o of
      Just (String v) -> T.take 60 v
      _ -> firstOf ks o

-- | Append streamed assistant text, rendering each /complete/ line to scrollback and keeping the
-- partial tail live in 'appPending'.
pushText :: App -> Text -> IO App
pushText app delta = go app {appPending = appPending app <> delta}
  where
    go a = case T.breakOn "\n" (appPending a) of
      (_, rest) | T.null rest -> pure a
      (line, rest) -> renderLine a {appPending = T.drop 1 rest} line >>= go

-- | Flush the partial tail and close any open blocks — end of turn or before an interruption.
flushPending :: App -> IO App
flushPending app
  | T.null (appPending app) = closeBlocks app
  | otherwise = renderLine app {appPending = ""} (appPending app) >>= closeBlocks

-- | Render one finalized assistant line, block-aware:
--
-- * a @\`\`\`@ fence opens\/closes a code block (top\/bottom border; a language tag on open);
-- * lines inside a fence render as gutter-prefixed code (no inline markdown);
-- * consecutive @|…|@ rows buffer into a table, flushed (aligned) when the block ends;
-- * a @#@-heading renders bold cyan; everything else gets inline styling (bold\/italic\/code).
renderLine :: App -> Text -> IO App
renderLine app line
  | "```" `T.isPrefixOf` t =
      if appInCodeFence app
        then emitCodeClose >> pure app {appInCodeFence = False}
        else do
          -- A fence ends any pending table.
          app' <- flushTable app
          emitCodeOpen (T.strip (T.dropWhile (== '`') t))
          pure app' {appInCodeFence = True}
  | appInCodeFence app = emitCodeLine line >> pure app
  | isTableRow line = pure app {appTableBuf = appTableBuf app <> [line]}
  | otherwise = do
      -- A non-table line ends any pending table.
      app' <- flushTable app
      case T.stripPrefix "#" t of
        Just rest -> emitBlock [[(T.stripStart (T.dropWhile (== '#') rest), bold (fg Cyan defaultStyle))]]
        Nothing -> emitRich (inline line)
      pure app'
  where
    t = T.stripStart line

-- | Render the buffered table rows (aligned) to scrollback, or fall back to plain rendering when
-- they don't form a valid table.
flushTable :: App -> IO App
flushTable app
  | null (appTableBuf app) = pure app
  | otherwise = do
      w <- termWidth
      case renderTable (appTableBuf app) w of
        Just rows -> emitBlock rows
        Nothing -> mapM_ (emitRich . inline) (appTableBuf app)
      pure app {appTableBuf = []}

-- | Close any open block at turn's end: flush a buffered table, and close an unterminated code fence
-- with its bottom border.
closeBlocks :: App -> IO App
closeBlocks app = do
  app' <- flushTable app
  if appInCodeFence app'
    then emitCodeClose >> pure app' {appInCodeFence = False}
    else pure app'

-- | Mark the turn finished and clear transient state.
finishTurn :: App -> App
finishTurn app =
  app
    { appRunning = False,
      appStatus = "",
      appTurnThread = Nothing,
      appToolNames = Map.empty,
      appToolArgs = Map.empty,
      appInCodeFence = False,
      appTableBuf = []
    }

-- | Cancel the in-flight turn: killing the thread drops the agent stream, which cancels the provider
-- request. Bumping the generation makes any buffered events from it be ignored.
cancelTurn :: App -> IO App
cancelTurn app = do
  mapM_ killThread (appTurnThread app)
  -- Dropping any open prompt answers it as a deny on the agent side, so the tool call resolves.
  mapM_ (`answerPermit` DenyOnce) (appPermit app)
  pure (finishTurn app {appTurnGen = appTurnGen app + 1, appPending = "", appPermit = Nothing})

-- --- the terminal ---------------------------------------------------------------------------------

-- | Put the terminal in raw mode (no echo, no line discipline, no signal keys — so @Ctrl-C@ reaches
-- the loop as a keystroke) for the duration, restoring the previous attributes on any exit path.
withRawTerminal :: IO a -> IO a
withRawTerminal act =
  bracket acquire restore (const act)
  where
    acquire = do
      hSetEncoding stdin utf8
      hSetEncoding stdout utf8
      prev <- getTerminalAttributes stdInput
      let raw =
            flip withMinInput 1
              . flip withTime 0
              . foldr ((.) . flip withoutMode) id [EnableEcho, ProcessInput, KeyboardInterrupts, ExtendedFunctions]
              $ prev
      setTerminalAttributes stdInput raw Immediately
      hSetBuffering stdin NoBuffering
      hSetBuffering stdout NoBuffering
      hSetEcho stdin False
      pure prev
    restore prev = setTerminalAttributes stdInput prev Immediately

-- | Current terminal width in columns, defaulting to 80 when it can't be read. A pty that reports no
-- size at all answers 0, which would collapse every wrap to a few columns — so an implausibly narrow
-- answer is treated as "unknown" rather than obeyed.
termWidth :: IO Int
termWidth = plausible . fmap TS.width <$> TS.size
  where
    plausible (Just w) | w >= 20 = w
    plausible _ = 80

-- | Read keys forever, decoding escape sequences, and post them to the UI channel. Signals 'UiEof'
-- when stdin closes.
keyReader :: Chan UiMsg -> IO ()
keyReader msgs = loop
  where
    loop = do
      r <- try getChar :: IO (Either SomeException Char)
      case r of
        Left _ -> writeChan msgs UiEof
        Right c -> decode c >>= mapM_ (writeChan msgs . UiKey) >> loop

    decode = \case
      '\ETX' -> pure (Just KCtrlC)
      '\EOT' -> pure (Just KCtrlD)
      '\f' -> pure (Just KCtrlL)
      '\r' -> pure (Just KEnter)
      '\n' -> pure (Just KEnter)
      '\DEL' -> pure (Just KBackspace)
      '\b' -> pure (Just KBackspace)
      '\ESC' -> escape
      c | c < ' ' -> pure Nothing -- other control bytes are ignored
      c -> pure (Just (KChar c))

    -- An ESC with nothing following within the poll window is a bare Escape; otherwise it opens a
    -- CSI/SS3 sequence (arrows, Home/End, Delete) or an Alt-modified key. The 25ms window is the
    -- usual compromise: long enough that a terminal's own sequence arrives whole, short enough that
    -- a real Escape keypress doesn't feel laggy.
    escape = do
      more <- hWaitForInput stdin 25 `orElse` pure False
      if more then csi else pure (Just KEsc)

    csi =
      getChar >>= \case
        '[' -> final ""
        'O' -> final ""
        '\r' -> pure (Just KAltEnter)
        '\n' -> pure (Just KAltEnter)
        _ -> pure Nothing

    -- Consume the parameter bytes up to the sequence's final byte, then map it.
    final acc = do
      c <- getChar
      if c >= '@' && c <= '~'
        then pure (mapCsi acc c)
        else final (acc <> [c])

    mapCsi params fin = case (params, fin) of
      ("", 'A') -> Nothing -- up: history is not implemented
      ("", 'B') -> Nothing -- down
      ("", 'C') -> Just KRight
      ("", 'D') -> Just KLeft
      ("", 'H') -> Just KHome
      ("", 'F') -> Just KEnd
      ("1", 'H') -> Just KHome
      ("3", '~') -> Just KDelete
      _ -> Nothing

    orElse a b = (try a :: IO (Either SomeException Bool)) >>= either (const b) pure

-- --- the inline viewport --------------------------------------------------------------------------
--
-- The viewport is the last 'viewportHeight' rows. After every draw the cursor is parked at its
-- top-left, so a scrollback insert is: clear from the cursor to the end of the screen, print the
-- block (the terminal scrolls naturally), then redraw the viewport below it.

-- | Scroll the terminal up far enough to make room for the viewport and park the cursor at its top.
reserveViewport :: IO ()
reserveViewport = do
  TIO.putStr (T.replicate viewportHeight "\n")
  TIO.putStr ("\ESC[" <> T.pack (show viewportHeight) <> "A\r")
  hFlush stdout

clearScreen :: IO ()
clearScreen = TIO.putStr "\ESC[2J\ESC[H" >> hFlush stdout

-- | Erase the viewport, leaving the cursor where it started.
clearViewport :: IO ()
clearViewport = TIO.putStr "\ESC[0J" >> hFlush stdout

-- | Draw the viewport's rows at the cursor, then park the cursor back at its top-left.
putViewport :: [Text] -> IO ()
putViewport rows = do
  TIO.putStr "\ESC[0J"
  TIO.putStr (T.intercalate "\r\n" (map ("\ESC[2K" <>) padded))
  TIO.putStr ("\ESC[" <> T.pack (show (viewportHeight - 1)) <> "A\r")
  hFlush stdout
  where
    padded = take viewportHeight (rows <> repeat "")

-- | Insert a finalized block above the viewport, into the terminal's own scrollback.
insertBefore :: [Text] -> IO ()
insertBefore rows = do
  TIO.putStr "\ESC[0J"
  mapM_ (\r -> TIO.putStr ("\ESC[2K" <> r <> "\r\n")) rows
  hFlush stdout
  reserveViewport

-- --- scrollback emitters --------------------------------------------------------------------------

-- | Hard-wrap a line to @width@ display columns (greedy by display width; a single wide token is
-- broken mid-run rather than overflowing).
hardWrap :: Text -> Int -> [Text]
hardWrap line width
  | T.null line = [""]
  | otherwise = go (T.unpack line) "" 0 []
  where
    w = max 1 width
    go [] cur _ acc = reverse (T.pack (reverse cur) : acc)
    go (c : cs) cur used acc
      | used + cw > w && not (null cur) = go (c : cs) "" 0 (T.pack (reverse cur) : acc)
      | otherwise = go cs (c : cur) (used + cw) acc
      where
        cw = max 1 (charWidth c)

-- | Insert a styled multi-line block into scrollback, wrapping to the current width so nothing is
-- clipped, with continuation rows indented under the prefix.
emit :: (Text, Style) -> Text -> Style -> IO ()
emit (prefix, prefixStyle) body style = do
  w <- termWidth
  let indent = displayWidth prefix
      avail = max 4 (w - indent)
      rows =
        [ (if i == (0 :: Int) && j == (0 :: Int) then styled prefixStyle prefix else T.replicate indent " ") <> styled style row
        | (i, logical) <- zip [0 ..] (T.splitOn "\n" body),
          (j, row) <- zip [0 ..] (hardWrap logical avail)
        ]
  insertBefore rows

-- | Wrap text in its SGR escape, if it has any style at all.
styled :: Style -> Text -> Text
styled st t
  | st == defaultStyle = t
  | otherwise = sgr st <> t <> resetSgr

-- | Insert one line of pre-styled markdown segments into scrollback, wrapping the styled runs to the
-- current width so nothing is clipped and styles survive the wrap.
emitRich :: [Segment] -> IO ()
emitRich segments = do
  w <- termWidth
  emitBlock (wrap segments w)

-- | Insert a pre-styled multi-row block (e.g. an aligned table) into scrollback as one unit.
emitBlock :: [[Segment]] -> IO ()
emitBlock rows = insertBefore [T.concat [styled st t | (t, st) <- row] | row <- rows']
  where
    rows' = if null rows then [[]] else rows

codeFrame :: Style
codeFrame = fg DarkGray defaultStyle

-- | Open a fenced code block: a top border carrying the language tag (if any).
emitCodeOpen :: Text -> IO ()
emitCodeOpen lang = emit ("", defaultStyle) head' codeFrame
  where
    head' = if T.null lang then "╭─────" else "╭─ " <> lang <> " "

-- | Close a fenced code block: the bottom border.
emitCodeClose :: IO ()
emitCodeClose = emit ("", defaultStyle) "╰─────" codeFrame

-- | One line inside a fenced code block: a dim @│ @ gutter (on every wrapped row) + the code in
-- green, with no inline-markdown interpretation.
emitCodeLine :: Text -> IO ()
emitCodeLine text = do
  w <- termWidth
  emitBlock [[("│ ", codeFrame), (row, fg Green defaultStyle)] | row <- hardWrap text (max 4 (w - 2))]

-- | Announce a pending tool-approval request in scrollback: a yellow header plus the call's full
-- arguments (so the small viewport prompt can stay compact).
emitPermit :: Text -> Text -> IO ()
emitPermit name args = emit ("🔒 approve ", bold (fg Yellow defaultStyle)) (name <> "\n" <> args) (fg Yellow defaultStyle)

emitWelcome :: IO ()
emitWelcome = emit ("lavoisier", bold (fg Cyan defaultStyle)) " — inline agent shell. Type a task and press Enter." (fg DarkGray defaultStyle)

emitUser :: Text -> IO ()
emitUser text = emit ("› ", bold (fg Cyan defaultStyle)) text (fg Cyan defaultStyle)

emitTool :: Text -> Text -> IO ()
emitTool name hint = emit ("🔧 ", fg Yellow defaultStyle) body (fg Yellow defaultStyle)
  where
    body = if T.null hint then name else name <> " · " <> hint

emitNotice :: Text -> IO ()
emitNotice text = emit ("• ", fg DarkGray defaultStyle) text (italic (fg DarkGray defaultStyle))

emitError :: Text -> IO ()
emitError text = emit ("error: ", bold (fg Red defaultStyle)) text (fg Red defaultStyle)

-- --- viewport rendering ---------------------------------------------------------------------------

-- | Draw the inline viewport: either an open approval prompt, or the status\/input\/footer.
drawViewport :: App -> IO ()
drawViewport app = do
  w <- termWidth
  putViewport (rowsFor app w)

rowsFor :: App -> Int -> [Text]
rowsFor app w = case appPermit app of
  Just req ->
    [ styled (bold (fg Yellow defaultStyle)) ("⚠ allow tool `" <> prName req <> "`?  (arguments shown above)"),
      boxTop w warn "",
      boxMid w warn keysLine,
      boxBot w warn,
      styled (fg DarkGray defaultStyle) "Ctrl-C cancels the turn"
    ]
  Nothing ->
    [ styled (fg DarkGray defaultStyle) statusLine,
      boxTop w defaultStyle " ask ",
      boxMid w defaultStyle (inputRow (w - 4)),
      boxBot w defaultStyle,
      styled (fg DarkGray defaultStyle) (footerLine app)
    ]
  where
    warn = fg Yellow defaultStyle
    keysLine =
      styled (bold (fg Green defaultStyle)) "[y] "
        <> "allow once   "
        <> styled (bold (fg Green defaultStyle)) "[a] "
        <> "always allow this tool   "
        <> styled (bold (fg Red defaultStyle)) "[n] "
        <> "deny"
    statusLine
      | appRunning app =
          let tail' = T.takeEnd 80 (appPending app)
           in if T.null (appStatus app) then "◐ " <> tail' else "◐ " <> appStatus app <> "  " <> tail'
      | otherwise = "ready · Enter to send · Alt+Enter newline · Ctrl-C quit"
    -- Show the tail of the buffer that fits, with the cursor marked by a reverse-video cell.
    inputRow avail =
      let txt = T.replace "\n" "⏎" (appInput app)
          cur = appCursor app
          from = max 0 (cur - avail + 1)
          visible = T.take avail (T.drop from txt)
          at = cur - from
       in T.take at visible <> "\ESC[7m" <> (if T.length visible > at then T.take 1 (T.drop at visible) else " ") <> "\ESC[0m" <> T.drop (at + 1) visible

-- | The three rows of a bordered box: a top edge carrying an optional title, one body row, and a
-- bottom edge. The body may contain SGR escapes, so its padding is measured with 'visibleWidth'.
boxTop :: Int -> Style -> Text -> Text
boxTop w st title = styled st ("╭─" <> title <> T.replicate (max 0 (w - 3 - displayWidth title)) "─" <> "╮")

boxMid :: Int -> Style -> Text -> Text
boxMid w st body = styled st "│" <> " " <> body <> T.replicate (max 0 (w - 4 - visibleWidth body)) " " <> " " <> styled st "│"

boxBot :: Int -> Style -> Text
boxBot w st = styled st ("╰" <> T.replicate (max 0 (w - 2)) "─" <> "╯")

-- | Display width ignoring SGR escape sequences (which occupy no columns).
visibleWidth :: Text -> Int
visibleWidth = displayWidth . stripSgr
  where
    stripSgr t = case T.breakOn "\ESC[" t of
      (before, rest)
        | T.null rest -> before
        | otherwise -> before <> stripSgr (T.drop 1 (T.dropWhile (/= 'm') rest))

-- | The footer: session, model, token flows, and estimated spend.
footerLine :: App -> Text
footerLine app =
  T.intercalate
    " · "
    [ appSession app,
      model,
      "↑" <> fmtTokens (inputTokens u) <> " ↓" <> fmtTokens (outputTokens u) <> cacheNote,
      spend
    ]
  where
    u = appUsage app
    model = activeModel app
    cache = cacheReadTokens u + cacheCreationTokens u
    cacheNote = if cache > 0 then " ⚡" <> fmtTokens cache else ""
    spend = case estimateUsd model u of
      Just usd -> "~$" <> fmtUsd usd
      Nothing -> fmtTokens (totalOf u) <> " tok"
    totalOf :: Usage -> Word64
    totalOf x = inputTokens x + outputTokens x
