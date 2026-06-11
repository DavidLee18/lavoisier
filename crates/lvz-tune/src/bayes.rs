//! [`BayesTuner`] — a Thompson-sampling alternative to the ε-greedy [`LearningTuner`]
//! (`docs/ATO.md` §10 Bayesian optimisation). Same `Tuner` contract, same discrete knob grid and
//! baseline floor, but selection is **Bayesian**: each candidate carries a Beta posterior over its
//! success probability and a Gaussian posterior over its cost, and `select` *samples* from those
//! posteriors and picks the cheapest sample that meets the success target. Posterior uncertainty
//! drives exploration automatically — no explicit ε.
//!
//! Like the hill-climb it keeps the candidate set small (the baseline plus the one-step grid
//! neighbours of the baseline and of the current best), so it stays tractable. Hand-rolled samplers
//! (Box–Muller normal, Marsaglia–Tsang gamma → beta) keep the no-extra-deps rule; the shared
//! xorshift PRNG drives them, so a run is reproducible. **Experimental and in-memory** (no
//! persistence yet) — opt in with `--tune-bayes`.

use std::collections::HashMap;
use std::sync::Mutex;

use lvz_protocol::{Knobs, Outcome, TaskContext, Tuner};

use crate::{all_neighbours, context_footprint, next_f64, ContextKey, TuneConfig};

/// Beta(successes+1, failures+1) over success probability, and a Welford mean/variance over the
/// token cost of *successful* runs (cost-when-it-works), per knob vector under one context.
#[derive(Debug, Default, Clone, Copy)]
struct BayesStats {
    successes: f64,
    failures: f64,
    cost_n: f64,
    cost_mean: f64,
    cost_m2: f64,
}

impl BayesStats {
    fn record(&mut self, out: &Outcome) {
        if out.success {
            self.successes += 1.0;
            // Welford update of the success-cost mean/variance.
            self.cost_n += 1.0;
            let delta = out.total_tokens as f64 - self.cost_mean;
            self.cost_mean += delta / self.cost_n;
            self.cost_m2 += delta * (out.total_tokens as f64 - self.cost_mean);
        } else {
            self.failures += 1.0;
        }
    }

    /// Standard error of the cost mean (0 until we have ≥2 successes).
    fn cost_stderr(&self) -> f64 {
        if self.cost_n < 2.0 {
            0.0
        } else {
            (self.cost_m2 / (self.cost_n - 1.0)).sqrt() / self.cost_n.sqrt()
        }
    }
}

struct State {
    profiles: HashMap<ContextKey, HashMap<Knobs, BayesStats>>,
    rng: u64,
}

/// A Thompson-sampling [`Tuner`]. Share behind an `Arc`.
pub struct BayesTuner {
    cfg: TuneConfig,
    state: Mutex<State>,
}

impl BayesTuner {
    pub fn new() -> Self {
        Self::with_config(TuneConfig::default())
    }

    pub fn with_config(cfg: TuneConfig) -> Self {
        Self {
            cfg,
            state: Mutex::new(State {
                profiles: HashMap::new(),
                rng: 0x2545_F491_4F6C_DD1D,
            }),
        }
    }
}

impl Default for BayesTuner {
    fn default() -> Self {
        Self::new()
    }
}

impl Tuner for BayesTuner {
    fn select(&self, ctx: &TaskContext) -> Knobs {
        let key = ContextKey::of(ctx);
        let mut guard = self.state.lock().expect("bayes tuner state poisoned");
        let st = &mut *guard;
        let candidates = st.profiles.entry(key).or_default();

        // Frontier: the baseline is always present (the floor), plus the one-step neighbours of
        // the baseline and of the current empirical best, so the search can still climb.
        candidates.entry(Knobs::default()).or_default();
        let best = empirical_best(candidates, self.cfg.success_target);
        for n in all_neighbours(Knobs::default())
            .into_iter()
            .chain(all_neighbours(best))
        {
            candidates.entry(n).or_default();
        }

        // Optimistic cost prior for never-succeeded candidates: the cheapest mean seen so far
        // (or 0 when nothing has succeeded yet), so unexplored vectors are worth a sample.
        let optimistic = candidates
            .values()
            .filter(|s| s.cost_n > 0.0)
            .map(|s| s.cost_mean)
            .fold(f64::INFINITY, f64::min);
        let optimistic = if optimistic.is_finite() {
            optimistic
        } else {
            0.0
        };

        // Thompson draw per candidate: sample success prob from its Beta, sample cost from its
        // Gaussian (optimistic prior when unseen). Pick the cheapest draw that clears the target;
        // if none do, move toward feasibility (highest sampled success prob).
        let target = self.cfg.success_target as f64;
        let mut feasible: Option<(Knobs, f64)> = None; // (knobs, sampled cost)
        let mut fallback: Option<(Knobs, f64)> = None; // (knobs, sampled success prob)
        for (knobs, s) in candidates.iter() {
            let p = sample_beta(s.successes + 1.0, s.failures + 1.0, &mut st.rng);
            let cost = if s.cost_n == 0.0 {
                optimistic
            } else {
                s.cost_mean + s.cost_stderr() * next_gaussian(&mut st.rng)
            };
            if p >= target {
                if better_cost(&feasible, *knobs, cost) {
                    feasible = Some((*knobs, cost));
                }
            } else if fallback.map(|(_, bp)| p > bp).unwrap_or(true) {
                fallback = Some((*knobs, p));
            }
        }
        feasible.or(fallback).map(|(k, _)| k).unwrap_or_default()
    }

    fn observe(&self, ctx: &TaskContext, used: &Knobs, out: &Outcome) {
        let key = ContextKey::of(ctx);
        let mut guard = self.state.lock().expect("bayes tuner state poisoned");
        guard
            .profiles
            .entry(key)
            .or_default()
            .entry(*used)
            .or_default()
            .record(out);
    }
}

/// True when `(knobs, cost)` should replace the incumbent feasible pick: strictly cheaper, or
/// equal cost but carrying less context (the same least-context tie-break as the hill-climb).
fn better_cost(incumbent: &Option<(Knobs, f64)>, knobs: Knobs, cost: f64) -> bool {
    match incumbent {
        None => true,
        Some((bk, bc)) => {
            cost < *bc || (cost == *bc && context_footprint(&knobs) < context_footprint(bk))
        }
    }
}

/// The cheapest candidate (by mean success-cost) whose observed success rate clears the target,
/// or the baseline when none qualifies yet — the centre the frontier expands around.
fn empirical_best(candidates: &HashMap<Knobs, BayesStats>, target: f32) -> Knobs {
    candidates
        .iter()
        .filter(|(_, s)| {
            let trials = s.successes + s.failures;
            s.cost_n > 0.0 && trials > 0.0 && (s.successes / trials) as f32 >= target
        })
        .min_by(|a, b| a.1.cost_mean.total_cmp(&b.1.cost_mean))
        .map(|(k, _)| *k)
        .unwrap_or_default()
}

// --- hand-rolled samplers (no `rand`/`statrs`), driven by the shared xorshift PRNG ---

/// A standard normal draw via Box–Muller.
fn next_gaussian(rng: &mut u64) -> f64 {
    let u1 = next_f64(rng).max(1e-12);
    let u2 = next_f64(rng);
    (-2.0 * u1.ln()).sqrt() * (std::f64::consts::TAU * u2).cos()
}

/// A Gamma(shape, 1) draw via Marsaglia–Tsang. Valid for `shape >= 1`, which always holds here
/// (the Beta parameters are `1 + count`).
fn sample_gamma(shape: f64, rng: &mut u64) -> f64 {
    let d = shape - 1.0 / 3.0;
    let c = 1.0 / (9.0 * d).sqrt();
    loop {
        let x = next_gaussian(rng);
        let v = (1.0 + c * x).powi(3);
        if v <= 0.0 {
            continue;
        }
        let u = next_f64(rng);
        if u < 1.0 - 0.0331 * x.powi(4) || u.ln() < 0.5 * x * x + d * (1.0 - v + v.ln()) {
            return d * v;
        }
    }
}

/// A Beta(a, b) draw as `G(a) / (G(a) + G(b))` from two Gamma draws.
fn sample_beta(a: f64, b: f64, rng: &mut u64) -> f64 {
    let x = sample_gamma(a, rng);
    let y = sample_gamma(b, rng);
    if x + y == 0.0 {
        0.5
    } else {
        x / (x + y)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use lvz_protocol::{Capabilities, ModelTier, RepoProfile};

    fn ctx() -> TaskContext {
        TaskContext {
            archetype: lvz_protocol::Archetype::SingleFileEdit,
            repo: RepoProfile::default(),
            caps: Capabilities::default(),
            model: ModelTier::Balanced,
            model_id: "m".into(),
            repo_id: "r".into(),
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
    fn beta_samples_track_their_parameters() {
        let mut rng = 12345u64;
        // Beta(20,2) mean ≈ 0.909; Beta(2,20) mean ≈ 0.091. Averages should separate cleanly.
        let mean = |a: f64, b: f64, rng: &mut u64| {
            let n = 4000;
            (0..n).map(|_| sample_beta(a, b, rng)).sum::<f64>() / n as f64
        };
        let high = mean(20.0, 2.0, &mut rng);
        let low = mean(2.0, 20.0, &mut rng);
        assert!(high > 0.82 && high < 0.97, "high mean was {high}");
        assert!(low > 0.03 && low < 0.18, "low mean was {low}");
    }

    #[test]
    fn converges_to_a_cheaper_reliable_vector() {
        let t = BayesTuner::new();
        let c = ctx();
        let cheaper = Knobs {
            skeleton_radius: 0,
            ..Knobs::default()
        };
        // Baseline succeeds at ~1000; a neighbour succeeds reliably at ~600. After enough
        // evidence, sampling should favour the cheaper reliable vector most of the time.
        for _ in 0..60 {
            t.observe(&c, &Knobs::default(), &outcome(1000, true));
            t.observe(&c, &cheaper, &outcome(600, true));
        }
        // The cheaper reliable vector should be chosen far more than the expensive baseline.
        // (An exact count is flaky: `select` iterates a HashMap, so the per-process seed changes
        // the order draws consume the PRNG, and unexplored neighbours carry an optimistic cost
        // prior that ties `cheaper` — so we assert the signal, not an absolute count.)
        let cheaper_picks = (0..200).filter(|_| t.select(&c) == cheaper).count();
        let baseline_picks = (0..200)
            .filter(|_| t.select(&c) == Knobs::default())
            .count();
        assert!(
            cheaper_picks > baseline_picks * 3 && cheaper_picks > 80,
            "expected the cheaper vector to dominate the baseline, got cheaper={cheaper_picks} baseline={baseline_picks}"
        );
    }

    #[test]
    fn avoids_a_cheap_but_failing_vector() {
        let t = BayesTuner::new();
        let c = ctx();
        let starved = Knobs {
            skeleton_radius: 0,
            truncate_bytes: 2048,
            ..Knobs::default()
        };
        for _ in 0..40 {
            t.observe(&c, &Knobs::default(), &outcome(1000, true));
        }
        // Cheap when it works, but fails most of the time → below target.
        t.observe(&c, &starved, &outcome(300, true));
        for _ in 0..40 {
            t.observe(&c, &starved, &outcome(300, false));
        }
        let starved_picks = (0..200).filter(|_| t.select(&c) == starved).count();
        assert!(
            starved_picks < 20,
            "starved vector picked too often: {starved_picks}/200"
        );
    }
}
