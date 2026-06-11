//! `lvz-tune` — adaptive token optimisation (ATO, `RECIPE.md` §6.6).
//!
//! [`LearningTuner`] is the online half of the knob-tuning loop: it implements the
//! [`Tuner`] contract so `lvz-agent` can swap it in for the default [`NoopTuner`] with no
//! other change. It treats each `(archetype, caching, model-tier)` context as its own
//! contextual bandit and **ε-greedily hill-climbs** over [`Knobs`]: mostly it exploits the
//! cheapest knob vector that meets a success constraint, occasionally it explores a one-step
//! neighbour on a discrete grid seeded by the §6.5 baseline.
//!
//! Two guarantees keep it safe (§6.6):
//! - **Constrained objective.** It minimises *total task tokens* only among candidates whose
//!   observed success rate clears `success_target` — never the cheapest-but-failing vector
//!   (context-starvation costs *more* in retries).
//! - **Bounded by the baseline floor.** Exploration moves only along a discrete grid whose
//!   centre is [`Knobs::default`] (the CI-gated §6.5 baseline), and until a candidate is
//!   *trusted* the tuner returns that baseline — so it can never regress below it.
//!
//! Caching on/off is a major confounder, so it is part of the profile key (§6.6). The
//! controller is pure in-memory bookkeeping (no extra dependencies, negligible overhead) and
//! its `select`/`observe` are synchronous, matching the trait.
//!
//! Now wired (see `docs/ATO.md`): a real success signal (`--verify-cmd`), model-version + per-repo
//! keying (`ContextKey` carries `model_id` and `repo_id`), observation decay (`TuneConfig.decay`,
//! an EWMA for non-stationarity), the exact byte-identical truncate counterfactual, the opt-in
//! estimated radius counterfactual with a downstream-residency model (emitted by `lvz-agent`; this
//! learner just records the synthetic observations), and profile persistence (`save`/`load`). Still
//! deferred: Bayesian optimisation. The success signal is only as good as what the agent reports —
//! pair `--tune` with `--verify-cmd` for a real quality gate in production.

use std::collections::HashMap;
use std::path::Path;
use std::sync::Mutex;

use lvz_protocol::{Archetype, Knobs, ModelTier, Outcome, TaskContext, Tuner};
use serde::{Deserialize, Serialize};

mod bayes;
pub use bayes::BayesTuner;

/// A [`Tuner`] whose learned profiles can be snapshotted to disk — the common surface behind
/// `--tune-state`, so a persistent wrapper can drive either the ε-greedy [`LearningTuner`] or the
/// Bayesian [`BayesTuner`] uniformly. (Named `persist` to avoid colliding with each tuner's
/// inherent `save`.)
pub trait PersistableTuner: Tuner {
    fn persist(&self, path: &Path) -> std::io::Result<()>;
}

impl PersistableTuner for LearningTuner {
    fn persist(&self, path: &Path) -> std::io::Result<()> {
        self.save(path)
    }
}

impl PersistableTuner for BayesTuner {
    fn persist(&self, path: &Path) -> std::io::Result<()> {
        self.save(path)
    }
}

/// Tuning hyper-parameters.
#[derive(Debug, Clone, Copy)]
pub struct TuneConfig {
    /// Probability of exploring a neighbour instead of exploiting the best known vector.
    pub epsilon: f64,
    /// Minimum observed success rate for a candidate to be eligible as "best".
    pub success_target: f32,
    /// Minimum trials before a candidate is trusted (avoids chasing lucky one-offs).
    pub min_trials: u32,
    /// Per-observation decay in `(0, 1]` for **non-stationarity** (`docs/ATO.md` §6.6): before a
    /// candidate folds in a new sample, its accumulated stats are multiplied by this factor, so
    /// recent outcomes weigh more and a stale optimum (e.g. after a model/codebase shift) fades.
    /// `1.0` = no decay (plain running totals); `0.9` ≈ a soft ~10-sample memory.
    pub decay: f64,
}

impl Default for TuneConfig {
    fn default() -> Self {
        Self {
            epsilon: 0.1,
            success_target: 0.9,
            min_trials: 3,
            decay: 1.0,
        }
    }
}

/// Profile key: the context features knob optima depend on. Caching is carried explicitly
/// because it is the dominant confounder (`RECIPE.md` §6.6); the concrete `model_id` is keyed
/// alongside the coarse tier so a model upgrade (non-stationarity, §6.6) starts a fresh profile
/// rather than averaging a shifted optimum into the old one.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
struct ContextKey {
    archetype: Archetype,
    caching: bool,
    model: ModelTier,
    model_id: String,
    repo_id: String,
}

impl ContextKey {
    fn of(ctx: &TaskContext) -> Self {
        Self {
            archetype: ctx.archetype,
            caching: ctx.caps.prompt_caching,
            model: ctx.model,
            model_id: ctx.model_id.clone(),
            repo_id: ctx.repo_id.clone(),
        }
    }
}

/// Running (optionally decayed) stats for one knob vector under one context. Fields are `f64`
/// so a `< 1.0` decay factor can down-weight old samples (an EWMA); with `decay == 1.0` they are
/// exact running totals.
#[derive(Debug, Default, Clone, Copy, Serialize, Deserialize)]
struct Stats {
    trials: f64,
    successes: f64,
    /// (Decay-weighted) summed tokens over *successful* runs (cost-when-it-works).
    success_tokens: f64,
}

impl Stats {
    fn success_rate(&self) -> f32 {
        if self.trials == 0.0 {
            0.0
        } else {
            (self.successes / self.trials) as f32
        }
    }

    fn mean_tokens(&self) -> Option<f64> {
        (self.successes > 0.0).then(|| self.success_tokens / self.successes)
    }

    fn trusted(&self, cfg: &TuneConfig) -> bool {
        self.trials >= cfg.min_trials as f64 && self.success_rate() >= cfg.success_target
    }
}

struct State {
    profiles: HashMap<ContextKey, HashMap<Knobs, Stats>>,
    rng: u64,
}

/// The learning [`Tuner`]. Clone-free; share it behind an `Arc`.
pub struct LearningTuner {
    cfg: TuneConfig,
    state: Mutex<State>,
}

impl LearningTuner {
    pub fn new() -> Self {
        Self::with_config(TuneConfig::default())
    }

    pub fn with_config(cfg: TuneConfig) -> Self {
        Self {
            cfg,
            state: Mutex::new(State {
                profiles: HashMap::new(),
                // Fixed non-zero seed: reproducible exploration; ε-greedy needs no crypto RNG.
                rng: 0x9E37_79B9_7F4A_7C15,
            }),
        }
    }
}

impl Default for LearningTuner {
    fn default() -> Self {
        Self::new()
    }
}

/// One learned `(context, knobs) → stats` row in a serialised snapshot. The nested in-memory
/// maps are flattened to a list because their keys are structs, which can't be JSON object keys.
#[derive(Serialize, Deserialize)]
struct Row {
    key: ContextKey,
    knobs: Knobs,
    stats: Stats,
}

/// The persisted learner state (profiles + PRNG cursor) — see [`LearningTuner::save`]/[`load`].
#[derive(Serialize, Deserialize, Default)]
struct Snapshot {
    rows: Vec<Row>,
    rng: u64,
}

impl LearningTuner {
    /// Serialise the learned profiles (and PRNG cursor) to `path` as JSON, so a long-running or
    /// restarted gateway keeps what it learned (`docs/ATO.md` §10 profile persistence).
    pub fn save(&self, path: impl AsRef<Path>) -> std::io::Result<()> {
        let guard = self.state.lock().expect("tuner state poisoned");
        let rows = guard
            .profiles
            .iter()
            .flat_map(|(key, candidates)| {
                candidates.iter().map(move |(knobs, stats)| Row {
                    key: key.clone(),
                    knobs: *knobs,
                    stats: *stats,
                })
            })
            .collect();
        let snapshot = Snapshot {
            rows,
            rng: guard.rng,
        };
        let json = serde_json::to_string_pretty(&snapshot)
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))?;
        std::fs::write(path, json)
    }

    /// Build a tuner pre-loaded from a [`save`](Self::save)d snapshot. A missing file yields a
    /// cold tuner (first run), so callers can pass a path unconditionally.
    pub fn load(path: impl AsRef<Path>, cfg: TuneConfig) -> std::io::Result<Self> {
        let tuner = Self::with_config(cfg);
        let json = match std::fs::read_to_string(path) {
            Ok(j) => j,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(tuner),
            Err(e) => return Err(e),
        };
        let snapshot: Snapshot = serde_json::from_str(&json)
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))?;
        {
            let mut guard = tuner.state.lock().expect("tuner state poisoned");
            for row in snapshot.rows {
                guard
                    .profiles
                    .entry(row.key)
                    .or_default()
                    .insert(row.knobs, row.stats);
            }
            if snapshot.rng != 0 {
                guard.rng = snapshot.rng; // keep exploration non-repeating across restarts
            }
        }
        Ok(tuner)
    }
}

impl Tuner for LearningTuner {
    fn select(&self, ctx: &TaskContext) -> Knobs {
        let key = ContextKey::of(ctx);
        let mut guard = self.state.lock().expect("tuner state poisoned");
        let st = &mut *guard;

        // The baseline is always a live candidate, so "best" can never be worse than it.
        let candidates = st.profiles.entry(key.clone()).or_default();
        candidates.entry(Knobs::default()).or_default();

        let best = best_candidate(candidates, &self.cfg).unwrap_or_default();

        if next_f64(&mut st.rng) < self.cfg.epsilon {
            // Explore: step one knob to an adjacent grid value and register the neighbour.
            let knob = (next_u64(&mut st.rng) % 4) as usize;
            let up = next_u64(&mut st.rng).is_multiple_of(2);
            let neighbour = step(best, knob, up);
            st.profiles
                .entry(key)
                .or_default()
                .entry(neighbour)
                .or_default();
            neighbour
        } else {
            best
        }
    }

    fn observe(&self, ctx: &TaskContext, used: &Knobs, out: &Outcome) {
        let key = ContextKey::of(ctx);
        let mut guard = self.state.lock().expect("tuner state poisoned");
        let candidates = guard.profiles.entry(key).or_default();

        let decay = self.cfg.decay;
        record(candidates.entry(*used).or_default(), out, decay);

        // Safe counterfactual (§6.6 / `docs/ATO.md` §3): if nothing in the task exceeded the
        // truncate limit actually used, then every *cheaper* grid value that still ≥ the largest
        // result would have produced a byte-identical transcript — identical tokens, identical
        // success. Credit those provably-equivalent vectors so the learner discovers cheaper
        // truncate settings without ever risking a starved live trial. (Only sound when the live
        // run didn't truncate; if it did, a different limit changes the transcript.)
        if let Some(max_bytes) = out.max_tool_result_bytes {
            if max_bytes <= used.truncate_bytes {
                for &b in TRUNCATE_GRID {
                    if b >= max_bytes && b < used.truncate_bytes {
                        let cf = Knobs {
                            truncate_bytes: b,
                            ..*used
                        };
                        record(candidates.entry(cf).or_default(), out, decay);
                    }
                }
            }
        }
    }
}

/// Fold one realised (or counterfactual) outcome into a candidate's running stats, first decaying
/// the prior totals by `decay` (an EWMA when `decay < 1.0`; plain accumulation at `1.0`).
fn record(stats: &mut Stats, out: &Outcome, decay: f64) {
    stats.trials = stats.trials * decay + 1.0;
    if out.success {
        stats.successes = stats.successes * decay + 1.0;
        stats.success_tokens = stats.success_tokens * decay + out.total_tokens as f64;
    } else {
        // Decay the success side too, so a run of failures fades past success evidence.
        stats.successes *= decay;
        stats.success_tokens *= decay;
    }
}

/// The cheapest trusted candidate (lowest mean tokens among those meeting the success
/// constraint), or `None` if nothing is trusted yet.
///
/// Ties on mean tokens are broken toward the **least context carried** (smaller `truncate_bytes`,
/// then `skeleton_radius`, then `compact_after`). This is what makes safe counterfactual
/// crediting (§3) actually bite: when a tighter truncate limit is proven byte-identical — same
/// cost, same success — the tie-breaker selects it, since carrying less context is weakly better
/// for cache/overrun pressure and never worse on the measured objective. It also makes selection
/// deterministic (independent of hash-map order).
fn best_candidate(candidates: &HashMap<Knobs, Stats>, cfg: &TuneConfig) -> Option<Knobs> {
    candidates
        .iter()
        .filter(|(_, s)| s.trusted(cfg))
        .filter_map(|(k, s)| s.mean_tokens().map(|m| (*k, m)))
        .min_by(|a, b| {
            a.1.total_cmp(&b.1)
                .then_with(|| context_footprint(&a.0).cmp(&context_footprint(&b.0)))
        })
        .map(|(k, _)| k)
}

/// Tie-break key: the context a knob vector carries, smaller = preferred. Ordered by the dials
/// that grow the prompt — truncate ceiling, then skeleton radius, then compaction threshold.
pub(crate) fn context_footprint(k: &Knobs) -> (usize, u8, usize) {
    (k.truncate_bytes, k.skeleton_radius, k.compact_after)
}

// --- discrete knob grids (centred on Knobs::default), and one-step neighbour moves ---

pub(crate) const RADIUS_GRID: &[u8] = &[0, 1, 2, 3];
pub(crate) const TRUNCATE_GRID: &[usize] = &[2048, 4096, 8192, 16384, 32768];
pub(crate) const COMPACT_GRID: &[usize] = &[8000, 16000, 24000, 32000, 48000, 64000];
pub(crate) const BATCH_GRID: &[u8] = &[1, 2, 4, 8];

fn step(knobs: Knobs, which: usize, up: bool) -> Knobs {
    let mut k = knobs;
    match which {
        0 => k.skeleton_radius = neighbour(RADIUS_GRID, k.skeleton_radius, up),
        1 => k.truncate_bytes = neighbour(TRUNCATE_GRID, k.truncate_bytes, up),
        2 => k.compact_after = neighbour(COMPACT_GRID, k.compact_after, up),
        _ => k.batch_width = neighbour(BATCH_GRID, k.batch_width, up),
    }
    k
}

/// All distinct one-step grid neighbours of `knobs` (both directions on all four dials, clamped;
/// the centre itself is excluded). Shared by the Bayesian tuner to expand its candidate frontier.
pub(crate) fn all_neighbours(knobs: Knobs) -> Vec<Knobs> {
    let mut out = Vec::with_capacity(8);
    for which in 0..4 {
        for up in [true, false] {
            let n = step(knobs, which, up);
            if n != knobs && !out.contains(&n) {
                out.push(n);
            }
        }
    }
    out
}

/// Adjacent grid value (clamped at the ends). Off-grid inputs snap to the nearest cell first.
fn neighbour<T: Copy + PartialOrd>(grid: &[T], current: T, up: bool) -> T {
    let idx = grid.iter().position(|v| *v == current).unwrap_or_else(|| {
        grid.iter()
            .position(|v| *v >= current)
            .unwrap_or(grid.len() - 1)
    });
    let next = if up {
        (idx + 1).min(grid.len() - 1)
    } else {
        idx.saturating_sub(1)
    };
    grid[next]
}

// --- xorshift64 PRNG (no `rand` dependency) ---

pub(crate) fn next_u64(state: &mut u64) -> u64 {
    let mut x = *state;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    *state = x;
    x
}

pub(crate) fn next_f64(state: &mut u64) -> f64 {
    // Top 53 bits → a uniform double in [0, 1).
    (next_u64(state) >> 11) as f64 / (1u64 << 53) as f64
}

#[cfg(test)]
mod tests {
    use super::*;
    use lvz_protocol::{Capabilities, RepoProfile};

    fn ctx() -> TaskContext {
        TaskContext {
            archetype: Archetype::SingleFileEdit,
            repo: RepoProfile::default(),
            caps: Capabilities::default(),
            model: ModelTier::Balanced,
            model_id: "test-model".to_string(),
            repo_id: "test-repo".to_string(),
        }
    }

    fn outcome(tokens: u64, success: bool) -> Outcome {
        Outcome {
            total_tokens: tokens,
            round_trips: 1,
            cache_hit_rate: 0.0,
            success,
            max_tool_result_bytes: None,
        }
    }

    #[test]
    fn cold_select_returns_the_baseline() {
        let t = LearningTuner::with_config(TuneConfig {
            epsilon: 0.0,
            ..Default::default()
        });
        assert_eq!(t.select(&ctx()), Knobs::default());
    }

    #[test]
    fn exploits_a_cheaper_trusted_candidate() {
        let t = LearningTuner::with_config(TuneConfig {
            epsilon: 0.0,
            success_target: 0.9,
            min_trials: 3,
            decay: 1.0,
        });
        let c = ctx();
        for _ in 0..3 {
            t.observe(&c, &Knobs::default(), &outcome(1000, true));
        }
        let cheaper = Knobs {
            skeleton_radius: 0,
            ..Knobs::default()
        };
        for _ in 0..3 {
            t.observe(&c, &cheaper, &outcome(600, true));
        }
        assert_eq!(t.select(&c), cheaper);
    }

    #[test]
    fn never_picks_a_cheaper_but_failing_candidate() {
        let t = LearningTuner::with_config(TuneConfig {
            epsilon: 0.0,
            success_target: 0.9,
            min_trials: 3,
            decay: 1.0,
        });
        let c = ctx();
        for _ in 0..4 {
            t.observe(&c, &Knobs::default(), &outcome(1000, true));
        }
        // Cheap when it works, but mostly fails → success rate below target.
        let starved = Knobs {
            skeleton_radius: 0,
            truncate_bytes: 2048,
            ..Knobs::default()
        };
        t.observe(&c, &starved, &outcome(300, true));
        for _ in 0..4 {
            t.observe(&c, &starved, &outcome(300, false));
        }
        assert_eq!(t.select(&c), Knobs::default());
    }

    #[test]
    fn exploration_steps_one_knob_and_stays_within_bounds() {
        let t = LearningTuner::with_config(TuneConfig {
            epsilon: 1.0,
            ..Default::default()
        });
        let c = ctx();
        for _ in 0..200 {
            let k = t.select(&c);
            assert!(k.skeleton_radius <= 3);
            assert!((2048..=32768).contains(&k.truncate_bytes));
            assert!((8000..=64000).contains(&k.compact_after));
            assert!((1..=8).contains(&k.batch_width));
        }
    }

    #[test]
    fn profiles_are_isolated_by_the_caching_confounder() {
        let t = LearningTuner::with_config(TuneConfig {
            epsilon: 0.0,
            success_target: 0.9,
            min_trials: 2,
            decay: 1.0,
        });
        let mut cached = ctx();
        cached.caps.prompt_caching = true;
        let mut uncached = ctx();
        uncached.caps.prompt_caching = false;

        let cheaper = Knobs {
            batch_width: 8,
            ..Knobs::default()
        };
        for _ in 0..2 {
            t.observe(&cached, &cheaper, &outcome(500, true));
        }
        // The uncached profile learned nothing → baseline; the cached profile → its winner.
        assert_eq!(t.select(&uncached), Knobs::default());
        assert_eq!(t.select(&cached), cheaper);
    }

    #[test]
    fn model_id_keys_profiles_apart() {
        let t = LearningTuner::with_config(TuneConfig {
            epsilon: 0.0,
            success_target: 0.9,
            min_trials: 2,
            decay: 1.0,
        });
        let mut v1 = ctx();
        v1.model_id = "model-v1".to_string();
        let mut v2 = ctx();
        v2.model_id = "model-v2".to_string();

        let cheaper = Knobs {
            batch_width: 8,
            ..Knobs::default()
        };
        for _ in 0..2 {
            t.observe(&v1, &cheaper, &outcome(500, true));
        }
        // The upgraded model id starts a fresh profile (non-stationarity), not the old optimum.
        assert_eq!(t.select(&v1), cheaper);
        assert_eq!(t.select(&v2), Knobs::default());
    }

    #[test]
    fn decay_lets_recent_failures_dethrone_a_stale_winner() {
        // Same history — 30 successes then 3 failures on the cheaper vector — under decay vs not.
        let run = |decay: f64| {
            let t = LearningTuner::with_config(TuneConfig {
                epsilon: 0.0,
                success_target: 0.9,
                min_trials: 2,
                decay,
            });
            let c = ctx();
            let cheaper = Knobs {
                skeleton_radius: 0,
                ..Knobs::default()
            };
            for _ in 0..30 {
                t.observe(&c, &cheaper, &outcome(600, true));
            }
            for _ in 0..3 {
                t.observe(&c, &cheaper, &outcome(600, false));
            }
            t.select(&c)
        };
        let cheaper = Knobs {
            skeleton_radius: 0,
            ..Knobs::default()
        };
        // No decay: 30/33 ≈ 0.909 ≥ target, so the cheaper vector is still trusted.
        assert_eq!(run(1.0), cheaper);
        // With decay: the 3 recent failures dominate the EWMA, dropping success rate below
        // target → the once-trusted winner is abandoned, falling back to the baseline.
        assert_eq!(run(0.9), Knobs::default());
    }

    #[test]
    fn repo_id_keys_profiles_apart() {
        let t = LearningTuner::with_config(TuneConfig {
            epsilon: 0.0,
            success_target: 0.9,
            min_trials: 2,
            decay: 1.0,
        });
        let mut repo_a = ctx();
        repo_a.repo_id = "/work/a".to_string();
        let mut repo_b = ctx();
        repo_b.repo_id = "/work/b".to_string();

        let cheaper = Knobs {
            batch_width: 8,
            ..Knobs::default()
        };
        for _ in 0..2 {
            t.observe(&repo_a, &cheaper, &outcome(500, true));
        }
        // Repo A learned its winner; repo B has its own (cold) profile.
        assert_eq!(t.select(&repo_a), cheaper);
        assert_eq!(t.select(&repo_b), Knobs::default());
    }

    #[test]
    fn counterfactual_credits_provably_equivalent_cheaper_truncate() {
        let t = LearningTuner::with_config(TuneConfig {
            epsilon: 0.0,
            success_target: 0.9,
            min_trials: 3,
            decay: 1.0,
        });
        let c = ctx();
        // Three successful runs at the default truncate (8192) where the largest tool result was
        // only 1500 bytes — so 2048 and 4096 would have been byte-identical (and cheaper).
        let mut out = outcome(1000, true);
        out.max_tool_result_bytes = Some(1500);
        for _ in 0..3 {
            t.observe(&c, &Knobs::default(), &out);
        }
        // Both 2048 and 4096 are ≥ 1500, so both were credited as byte-identical at the same
        // cost and are now trusted — learned without a single live trial at either. The tuner
        // picks one of those provably-cheaper-context values over the default 8192.
        let chosen = t.select(&c).truncate_bytes;
        assert!(
            chosen == 2048 || chosen == 4096,
            "expected a counterfactually-credited value, got {chosen}"
        );
        assert!(chosen < Knobs::default().truncate_bytes);
    }

    #[test]
    fn save_and_load_round_trips_profiles() {
        let dir = std::env::temp_dir();
        let path = dir.join(format!("lvz-tune-test-{}.json", std::process::id()));

        let t = LearningTuner::with_config(TuneConfig {
            epsilon: 0.0,
            success_target: 0.9,
            min_trials: 3,
            decay: 1.0,
        });
        let c = ctx();
        let cheaper = Knobs {
            skeleton_radius: 0,
            ..Knobs::default()
        };
        for _ in 0..3 {
            t.observe(&c, &Knobs::default(), &outcome(1000, true));
            t.observe(&c, &cheaper, &outcome(600, true));
        }
        assert_eq!(t.select(&c), cheaper);
        t.save(&path).expect("save");

        // A fresh tuner loaded from the snapshot picks the same learned winner.
        let reloaded = LearningTuner::load(
            &path,
            TuneConfig {
                epsilon: 0.0,
                success_target: 0.9,
                min_trials: 3,
                decay: 1.0,
            },
        )
        .expect("load");
        assert_eq!(reloaded.select(&c), cheaper);

        // A missing file loads cold (baseline), not an error.
        let missing = dir.join("lvz-tune-does-not-exist-xyz.json");
        let cold = LearningTuner::load(&missing, TuneConfig::default()).expect("cold load");
        assert_eq!(cold.select(&c), Knobs::default());

        let _ = std::fs::remove_file(&path);
    }
}
