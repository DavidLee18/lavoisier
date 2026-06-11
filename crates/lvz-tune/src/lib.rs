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
//! Deferred (RECIPE notes these as "later"): counterfactual updates from logged traces,
//! model-version keying for non-stationarity, and Bayesian optimisation. Also note the success
//! signal is only as good as what the agent reports — wire a real quality gate (tests pass /
//! diff accepted) before trusting ATO in production.

use std::collections::HashMap;
use std::sync::Mutex;

use lvz_protocol::{Archetype, Knobs, ModelTier, Outcome, TaskContext, Tuner};

/// Tuning hyper-parameters.
#[derive(Debug, Clone, Copy)]
pub struct TuneConfig {
    /// Probability of exploring a neighbour instead of exploiting the best known vector.
    pub epsilon: f64,
    /// Minimum observed success rate for a candidate to be eligible as "best".
    pub success_target: f32,
    /// Minimum trials before a candidate is trusted (avoids chasing lucky one-offs).
    pub min_trials: u32,
}

impl Default for TuneConfig {
    fn default() -> Self {
        Self {
            epsilon: 0.1,
            success_target: 0.9,
            min_trials: 3,
        }
    }
}

/// Profile key: the context features knob optima depend on. Caching is carried explicitly
/// because it is the dominant confounder (`RECIPE.md` §6.6).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
struct ContextKey {
    archetype: Archetype,
    caching: bool,
    model: ModelTier,
}

impl ContextKey {
    fn of(ctx: &TaskContext) -> Self {
        Self {
            archetype: ctx.archetype,
            caching: ctx.caps.prompt_caching,
            model: ctx.model,
        }
    }
}

/// Running stats for one knob vector under one context.
#[derive(Debug, Default, Clone, Copy)]
struct Stats {
    trials: u32,
    successes: u32,
    /// Summed tokens over *successful* runs (cost-when-it-works).
    success_tokens: u64,
}

impl Stats {
    fn success_rate(&self) -> f32 {
        if self.trials == 0 {
            0.0
        } else {
            self.successes as f32 / self.trials as f32
        }
    }

    fn mean_tokens(&self) -> Option<f64> {
        (self.successes > 0).then(|| self.success_tokens as f64 / self.successes as f64)
    }

    fn trusted(&self, cfg: &TuneConfig) -> bool {
        self.trials >= cfg.min_trials && self.success_rate() >= cfg.success_target
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

impl Tuner for LearningTuner {
    fn select(&self, ctx: &TaskContext) -> Knobs {
        let key = ContextKey::of(ctx);
        let mut guard = self.state.lock().expect("tuner state poisoned");
        let st = &mut *guard;

        // The baseline is always a live candidate, so "best" can never be worse than it.
        let candidates = st.profiles.entry(key).or_default();
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
        let stats = guard
            .profiles
            .entry(key)
            .or_default()
            .entry(*used)
            .or_default();
        stats.trials += 1;
        if out.success {
            stats.successes += 1;
            stats.success_tokens += out.total_tokens;
        }
    }
}

/// The cheapest trusted candidate (lowest mean tokens among those meeting the success
/// constraint), or `None` if nothing is trusted yet.
fn best_candidate(candidates: &HashMap<Knobs, Stats>, cfg: &TuneConfig) -> Option<Knobs> {
    candidates
        .iter()
        .filter(|(_, s)| s.trusted(cfg))
        .filter_map(|(k, s)| s.mean_tokens().map(|m| (*k, m)))
        .min_by(|a, b| a.1.total_cmp(&b.1))
        .map(|(k, _)| k)
}

// --- discrete knob grids (centred on Knobs::default), and one-step neighbour moves ---

const RADIUS_GRID: &[u8] = &[0, 1, 2, 3];
const TRUNCATE_GRID: &[usize] = &[2048, 4096, 8192, 16384, 32768];
const COMPACT_GRID: &[usize] = &[8000, 16000, 24000, 32000, 48000, 64000];
const BATCH_GRID: &[u8] = &[1, 2, 4, 8];

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

fn next_u64(state: &mut u64) -> u64 {
    let mut x = *state;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    *state = x;
    x
}

fn next_f64(state: &mut u64) -> f64 {
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
        }
    }

    fn outcome(tokens: u64, success: bool) -> Outcome {
        Outcome {
            total_tokens: tokens,
            round_trips: 1,
            cache_hit_rate: 0.0,
            success,
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
}
