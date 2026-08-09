-- | @Lavoisier.Legion@ — a multi-model __council__ ("legion") that argues out a task before the
-- agent acts. Ported from Rust @lvz-legion@.
--
-- A 'Panel' holds a list of 'Debater's (each a provider + model) and a judge. Given a task it runs
-- three phases — __draft__, __critique__, __judge__ — and returns one agreed 'Deliberation' (a
-- plan-of-action plus the total token cost). The agent injects that plan as the executor's opening
-- move (/deliberate-then-act/), so the models argue about /what to do and how to reply/, then the
-- normal tool-using loop carries the agreed plan out.
--
-- This module implements the 'Deliberator' contract and depends only on the protocol keystone. The
-- arguing is __internal__: only the judge's synthesis leaves the council. Debaters run __tool-less__
-- and __concurrently__ within each phase (via @async@'s 'mapConcurrently').
module Lavoisier.Legion
  ( Debater (..),
    mkDebater,
    Language (..),
    languageFromLocale,
    LegionError (..),
    renderLegionError,
    Panel,
    newPanel,
    withLanguage,
    panelDebaters,
    panelRounds,
    panelDeliberator,
  )
where

import Control.Concurrent.Async (mapConcurrently)
import Control.Monad (foldM)
import Data.Maybe (isNothing)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Word (Word32)
import Lavoisier.Protocol.Deliberate
import Lavoisier.Protocol.Event (Event (..), Usage, accumulateUsage, emptyUsage)
import Lavoisier.Protocol.Message
  ( ChatRequest (..),
    SystemPrompt (..),
    ThinkingLevel,
    ToolDef (..),
    chatRequest,
    userMessage,
  )
import Lavoisier.Protocol.Provider (Provider (..))
import Lavoisier.Protocol.Stream (Producer (..))

-- | Token ceiling for a single debater's draft\/critique call — positions are concise argument.
debaterMaxTokens :: Word32
debaterMaxTokens = 1024

-- | Token ceiling for the judge's synthesis — a little larger; it folds the whole panel into one plan.
judgeMaxTokens :: Word32
judgeMaxTokens = 2048

legionDraftSystem :: Text
legionDraftSystem =
  "You are one member of a council of AI models deliberating on how to handle a task before any \
  \action is taken. Propose, concretely: (1) what should actually be done — the plan of action, \
  \including any tools/steps — and (2) what the reply to the user should say. Be specific and \
  \opinionated; state assumptions and call out risks. This is a first draft other members will \
  \critique, so make your reasoning legible. Keep it tight."

legionCritiqueSystem :: Text
legionCritiqueSystem =
  "You are one member of a deliberating council of AI models. You are shown the whole panel's current \
  \positions. Critique the others where they are wrong, risky, or incomplete, concede points that are \
  \better than yours, and then produce your own REVISED position — the plan of action and the reply \
  \you now stand behind. Argue for the strongest overall outcome, not merely your original take. Keep \
  \it tight."

legionJudgeSystem :: Text
legionJudgeSystem =
  "You are the judge of a council of AI models that has deliberated a task. You are shown every \
  \member's final position. Synthesise them into a SINGLE agreed plan of action for an executor agent \
  \to carry out, plus the key points the final reply to the user should make. Resolve disagreements \
  \on the merits, keep what is strongest, and drop what the debate showed to be wrong. Output only the \
  \agreed plan and reply points — no meta-commentary about the debate itself."

-- | One member of the council: a provider handle paired with the model id it argues under. The panel
-- holds real 'Provider's, so a council can mix providers freely — cross-provider panels are
-- first-class.
data Debater = Debater
  { debName :: Text,
    debProvider :: Provider,
    debModel :: Text,
    debThinking :: Maybe ThinkingLevel
  }

-- | Construct a debater from its parts.
mkDebater :: Text -> Provider -> Text -> Maybe ThinkingLevel -> Debater
mkDebater = Debater

-- | The natural language the council's user-visible progress notices render in. Only the phase
-- notices localize — the debate transcript and the executor's answer are unaffected.
data Language = English | Korean
  deriving stock (Eq, Show)

-- | Resolve a POSIX locale string (a @LANG@ value like @ko_KR.UTF-8@, or a @--lang@ flag) to a
-- 'Language'. Only @KO_KR@ (case-insensitive, any @.encoding@ suffix ignored) selects Korean.
languageFromLocale :: Text -> Language
languageFromLocale raw =
  if T.toUpper (T.takeWhile (/= '.') raw) == "KO_KR" then Korean else English

councilConvened :: Language -> Int -> Text
councilConvened English n = "🧠 council convened — " <> tshow n <> " debaters drafting…"
councilConvened Korean n = "🧠 위원회 소집 — 토론자 " <> tshow n <> "명이 초안 작성 중…"

critiqueRoundNotice :: Language -> Int -> Int -> Text
critiqueRoundNotice English r t = "🗣 critique round " <> tshow r <> "/" <> tshow t <> "…"
critiqueRoundNotice Korean r t = "🗣 비평 라운드 " <> tshow r <> "/" <> tshow t <> "…"

judgeSynthesising :: Language -> Text
judgeSynthesising English = "⚖️ judge synthesising the verdict…"
judgeSynthesising Korean = "⚖️ 심판이 결론을 종합하는 중…"

-- | Errors constructing a 'Panel'. (Runtime deliberation failures use 'DeliberateError'.)
newtype LegionError = TooFewDebaters Int
  deriving stock (Eq, Show)

-- | A human-readable message for a 'LegionError'.
renderLegionError :: LegionError -> Text
renderLegionError (TooFewDebaters n) =
  "a legion panel needs at least 2 debaters, got " <> tshow n

-- | A council of debaters plus a judge. Implements 'Deliberator' via 'panelDeliberator'.
data Panel = Panel
  { pnDebaters :: [Debater],
    pnJudge :: Debater,
    pnRounds :: Int,
    pnLang :: Language
  }

-- | Build a panel from its debaters, a judge, and the number of __critique__ rounds to run after the
-- initial draft (@0@ = draft then judge, no back-and-forth). Fails with 'TooFewDebaters' if fewer
-- than two debaters are given — a one-model "council" is just the advisor pre-pass.
newPanel :: [Debater] -> Debater -> Int -> Either LegionError Panel
newPanel debaters judge rounds
  | length debaters < 2 = Left (TooFewDebaters (length debaters))
  | otherwise = Right (Panel debaters judge rounds English)

-- | Set the language for the council's progress notices (default 'English').
withLanguage :: Language -> Panel -> Panel
withLanguage lang p = p {pnLang = lang}

-- | The debaters on this panel.
panelDebaters :: Panel -> [Debater]
panelDebaters = pnDebaters

-- | The number of critique rounds this panel runs after the draft.
panelRounds :: Panel -> Int
panelRounds = pnRounds

-- | Adapt a 'Panel' to the 'Deliberator' record so the agent can hold it uniformly.
panelDeliberator :: Panel -> Deliberator
panelDeliberator panel = Deliberator (deliberateWithContext panel)

-- --- the deliberation ------------------------------------------------------------------------------

deliberateWithContext :: Panel -> Text -> DeliberationContext -> IO (Either DeliberateError Deliberation)
deliberateWithContext panel task ctx = do
  let preamble = contextPreamble ctx
      draftSystem = legionDraftSystem <> "\n\n" <> preamble
      critiqueSystem = legionCritiqueSystem <> "\n\n" <> preamble
      judgeSystem = legionJudgeSystem <> "\n\n" <> preamble
      debs = pnDebaters panel
      lang = pnLang panel
  dcNotify ctx (councilConvened lang (length debs))
  -- Phase 1 — draft round: every debater proposes independently, concurrently.
  drafts <- mapConcurrently (\d -> ask d draftSystem task debaterMaxTokens) debs
  if all isNothing drafts
    then pure (Left NoPositions)
    else do
      let positions0 = map (fmap fst) drafts
          usage0 = sumUsages [u | Just (_, u) <- drafts]
      -- Phase 2 — critique rounds: each debater sees the board and revises, concurrently.
      (positionsN, usageN) <-
        foldM (critiqueRound ctx lang debs critiqueSystem task (pnRounds panel)) (positions0, usage0) [1 .. pnRounds panel]
      -- Phase 3 — judge synthesis.
      dcNotify ctx (judgeSynthesising lang)
      let board = renderPositions debs positionsN
          judgeUser = "TASK:\n" <> task <> "\n\nFINAL PANEL POSITIONS:\n" <> board
      mj <- ask (pnJudge panel) judgeSystem judgeUser judgeMaxTokens
      case mj of
        Just (plan, u) -> pure (Right (Deliberation plan (accumulateUsage u usageN)))
        Nothing -> pure (Left (JudgeFailed "judge returned no synthesis"))

-- | One critique round: notify, render the board, ask every debater to revise concurrently, and fold
-- the survivors back into the positions (a failed debater keeps its prior position) and the usage.
critiqueRound ::
  DeliberationContext ->
  Language ->
  [Debater] ->
  Text ->
  Text ->
  Int ->
  ([Maybe Text], Usage) ->
  Int ->
  IO ([Maybe Text], Usage)
critiqueRound ctx lang debs critiqueSystem task totalRounds (positions, usage) roundIx = do
  dcNotify ctx (critiqueRoundNotice lang roundIx totalRounds)
  let board = renderPositions debs positions
  results <- mapConcurrently (\d -> ask d critiqueSystem (critiqueUser task board d) debaterMaxTokens) debs
  let positions' = zipWith (\old res -> maybe old (Just . fst) res) positions results
      usage' = foldl (\acc u -> accumulateUsage u acc) usage [u | Just (_, u) <- results]
  pure (positions', usage')

critiqueUser :: Text -> Text -> Debater -> Text
critiqueUser task board d =
  "TASK:\n"
    <> task
    <> "\n\nTHE PANEL'S CURRENT POSITIONS:\n"
    <> board
    <> "\nYou are \""
    <> debName d
    <> "\". Critique the others and give your revised position."

-- | Ask one debater for a position: one tool-less streamed call, drained to @(text, usage)@. Returns
-- 'Nothing' if the call errors or produces empty output (best-effort — a dropped debater just doesn't
-- contribute to this run).
ask :: Debater -> Text -> Text -> Word32 -> IO (Maybe (Text, Usage))
ask deb system user maxTok = do
  let req =
        (chatRequest (debModel deb))
          { crSystem = Just (SystemPrompt system False),
            crMessages = [userMessage user],
            crMaxTokens = maxTok,
            crThinking = debThinking deb
          }
  est <- providerStream (debProvider deb) req
  case est of
    Left _ -> pure Nothing
    Right stream -> drainAsk stream "" emptyUsage
  where
    drainAsk stream acc usg =
      nextItem stream >>= \case
        Nothing -> pure (if T.null (T.strip acc) then Nothing else Just (acc, usg))
        Just (Left _) -> pure Nothing
        Just (Right ev) -> case ev of
          TextDelta t -> drainAsk stream (acc <> t) usg
          Usage u -> drainAsk stream acc u
          _ -> drainAsk stream acc usg

-- | Render the surviving positions into a labelled board the panel and judge read.
renderPositions :: [Debater] -> [Maybe Text] -> Text
renderPositions debs positions =
  T.concat
    ["### " <> debName d <> " (" <> debModel d <> ")\n" <> T.strip t <> "\n\n" | (d, Just t) <- zip debs positions]

-- | Render the executor's context into a grounding block appended to every phase's system prompt —
-- the fix for a council that argues in a vacuum: it tells the debaters __who they are__ (the agent's
-- persona) and __what the executor can do__ (the tools it may call), so they plan to /use/ those
-- tools instead of concluding the task is impossible and seeding the executor with a refusal.
contextPreamble :: DeliberationContext -> Text
contextPreamble ctx = personaBlock <> toolsBlock
  where
    personaBlock
      | T.null (T.strip (dcSystem ctx)) = ""
      | otherwise =
          "You are deliberating on behalf of a specific agent. Adopt its identity, persona, and \
          \constraints as your own — do NOT disclaim being it or being a different assistant:\n\
          \--- AGENT SYSTEM PROMPT ---\n"
            <> T.strip (dcSystem ctx)
            <> "\n--- END AGENT SYSTEM PROMPT ---\n\n"
    toolsBlock
      | null (dcTools ctx) =
          "The executor that will carry out the agreed plan has NO tools available; plan only what can \
          \be done by replying."
      | otherwise =
          "The executor that will carry out the agreed plan can call these tools. Plan to USE the \
          \relevant ones to accomplish the task — do NOT conclude the task is impossible or out of \
          \scope merely because you cannot act yourself; the executor acts:\n"
            <> T.concat ["- `" <> tdName t <> "`: " <> T.strip (tdDescription t) <> "\n" | t <- dcTools ctx]

sumUsages :: [Usage] -> Usage
sumUsages = foldl (\acc u -> accumulateUsage u acc) emptyUsage

tshow :: (Show a) => a -> Text
tshow = T.pack . show
