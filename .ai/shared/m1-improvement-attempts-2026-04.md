# M1 Alignment Improvement Attempts (2026-04)

## Background

Current locked M1 spec: `k_ref=25, slope_window=6, slope_weight=8, temperature=0.25, ref_method="fs"`
LOSO Weibull-weighted peak MAE = **1.276 weeks** (logit-scale ensemble; 67-spec grid v5–v7).

Three failure modes were hypothesized:
1. Mid-ignition seasons fail worst (weekF 18–21)
2. Overconfident spread on bad alignments (`cor(logit_spread, |peak_error|) = 0.366`)
3. Tau oscillation in failing seasons

All improvements restricted to existing data — no external predictors.

---

## Phase 1: Peak-time prior from M0 (FAILED)

### Idea

Use the empirical distribution of `peak_weekF − iWeek` across training seasons as a soft Gaussian prior on which templates can win. Templates whose implied peak falls outside the expected window are down-weighted.

### Implementation

- `estimateRef()` (`m1_reference.R`): computed `peak_lag_prior = list(med, mad, n)` from per-season peak minus ignition week; stored on `ref$peak_lag_prior`.
- `align_multi_template()` (`m1_multi_template.R`): added `prior_factor_j = exp(-0.5 * ((peak_weekF_j - (iWeek_hat + med_lag)) / (kappa * 1.4826 * mad_lag))^2)`, multiplied into `w_raw` alongside `slope_factor`.
- `run_alignment_prospective_multi()`: threaded `iWeek_hat`, `anchorWeek`, `peak_lag_prior`, `peak_prior_kappa`.
- `loso_walkforward()` (`m1_loso.R`): added `peak_prior_kappa` parameter.
- Kappa sweep script: `scripts/fresh_run/03b_m1_kappa_sweep.R` (untracked, kept for reference).

### Hyperparameter sweep

Swept `peak_prior_kappa ∈ {Inf, 3.0, 2.0, 1.5}` at locked spec via `tune_m1_alignment()`.

| kappa | mae_weibull |
|-------|-------------|
| Inf   | 1.276       |
| 3.0   | 1.309       |
| 2.0   | 1.325       |
| 1.5   | 1.451       |

Every finite kappa hurt. Monotonic degradation.

### Why it failed

The initial premise (2018-19 = 14-week error, mean ~9 weeks for mid-season) was incorrect — based on a faulty Explore agent report. The locked-spec LOSO actual errors were 1–4 weeks per season. The prior was optimized against `which.max(fit)` peaks (the same peaks it shifts weight toward), creating circular validation in the micro-sweep. The full LOSO uses Weibull-weighted evaluation over all post-ignition weeks, which is harder to game.

Additional root cause: `iWeek_hat` is M0's estimate and is itself biased in the difficult mid-season cases the prior was meant to help — so anchoring the prior to `iWeek_hat + med_lag` can propagate M0 bias into the template weights.

### Decision

Reverted. The Inf baseline (no prior) remains optimal.

---

## Phase 2: Honest `logit_spread` with within-template GAM SE (FAILED)

### Idea

Current `logit_spread` is the between-template weighted SD of per-template logit predictions. Add within-template GAM uncertainty (SE from `g_ref_mu_se()`) to get total predictive variance:

```
sigma2_between_i = sum(w_j * (logit_ij - logit_mean_i)^2)
sigma2_within_i  = sum(w_j * se_ij^2)
logit_spread_i   = sqrt(sigma2_between + sigma2_within)
```

### Implementation

- `align_multi_template()` lines 261–265: replaced between-only SD with the variance decomposition.
- Script: `scripts/fresh_run/04k_m2_loso_v18_spread.R` — Phase A rebuilds M1 fold cache with updated logit_spread (`data/fresh_nested_loso_v18_phase1.rds`); Phase B sweeps `k_sp ∈ {0,2,4,6,8,10}` at v16 best spec.

### v18 ksp sweep results

| k_sp | bernoulli_nll | brier    |
|------|---------------|----------|
| 10   | 0.42941       | 0.075037 |
| 8    | 0.42941       | 0.075037 |
| 6    | 0.42944       | 0.075037 |
| 4    | 0.42950       | 0.075041 |
| 2    | 0.42951       | 0.075048 |
| 0    | 0.43009       | 0.075141 |

v16 best NLL: 0.42646; v18 best: 0.42941 — **marginally worse** (+0.003).

### Why it failed

Adding `sigma2_within` from `g_ref_mu_se()` uniformly inflated `logit_spread`. The M2 `s(logit_spread, k=k_sp)` term had already been tuned on the smaller between-only spread. With larger spread values, the M2 smooth becomes less discriminative — the M2 GAM cannot easily re-tune within a fixed spec. A full M2 grid re-tune would be needed to recover, but the fact that best k_sp shifted upward (10 > 6) without surpassing v16 suggests the signal-to-noise ratio of the new spread measure is lower, not higher.

### Decision

Reverted. v16 logit_spread (between-template only) retained.

---

## Phase 3: Recursive Bayesian carry-forward (DEFERRED)

Not implemented. Phase 1's prior already partially addresses tau oscillation by deprioritizing templates that produce implausible peak timing. Phase 3 would require threading `prev_align_state` through `loso_walkforward()`, `align_multi_template()`, and `align_forecast_pipeline_dilate()` — a multi-file change that forces a full LOSO grid re-tune of `(temperature, slope_weight, k_ref)`. Deferred until M1 oscillation is re-measured post 2025-26.

---

## Net result

No improvement to M1 alignment from this session. The v16 M1 spec (locked, Weibull MAE = 1.276) remains production. The most promising next step for M1 is adding the completed 2025-26 season to training data once the season ends.

---

## Data files generated (kept for reference)

- `data/fresh_m1_kappa_ckpt/` — kappa sweep checkpoint directory
- `data/fresh_m1_kappa_sweep.rds` — Phase 1 kappa sweep results
- `data/fresh_nested_loso_v18_phase1.rds` — M1 fold cache with Phase 2 logit_spread
- `data/fresh_nested_loso_v18_ksp_sweep.rds` — Phase 2 ksp sweep results

## Scripts generated (untracked, kept for reference)

- `scripts/fresh_run/03b_m1_kappa_sweep.R` — Phase 1 kappa sweep
- `scripts/fresh_run/04h_m2_loso_v17_adaptive_ba.R` — v17 adaptive ba grid (abandoned)
- `scripts/fresh_run/04k_m2_loso_v18_spread.R` — Phase 2 ksp sweep
