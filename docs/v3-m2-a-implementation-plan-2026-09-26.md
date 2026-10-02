# V3 M2-A implementation plan

Date: 2026-09-26
Status: audited design; approved with fixes incorporated; ready for implementation

## Objective

Test whether an M1-v2-specification A timing model refit causally on the canonical v3 panel improves Influenza A +2 forecasting beyond the A state/growth baseline under strict chronological replay.

The primary decision question is:

> Does a posterior-averaged A timing correction improve A +2 without introducing a hard passage gate or destabilizing A +1?

A +1 is diagnostic only and remains routed to exact A1 state forecast in this study.

## Frozen upstream contracts

### M0-A

Use the frozen M0-v2 operational detector policy from:

`artifacts/m0-v2-wmin12-raw3-se1-decimal-loso-v1/loso_result.rds`

Required frozen settings include:

- classifier disabled;
- `w_min = 12`;
- `raw_nondec_n = 3`;
- `raw_drop_se_tol = 1.0`;
- original epidemiologic vote structure unchanged.

For each historical forecast origin, activation must be recomputed from the A prefix available through that origin. Whole-season activation tables may not be used for prediction. The M0 parameter object is loaded from the frozen artifact and hash-checked; parameters are not retyped or retuned.

This historical M2-A study is conditional on the globally selected frozen M0-A policy, which was chosen with knowledge of all 11 historical seasons. That limitation must be carried into the final interpretation.

### M1-A

Operational M1-A remains frozen M1-v2. Historical v3 replay uses the **same M1-v2 specification refit on canonical v3 data inside each chronological fold**. Because the canonical v3 panel and retrospective peak truth differ from the original M1-v2 training vintage, historical fold libraries are not expected to reproduce the original frozen library hash.

Full-history reference artifact:

`artifacts/m1-v2-wmin12-raw3-se1-full-history-v1/m1_v2_stage.rds`

Reference identifiers:

- artifact ID: `90f06406dbe3a7d5f190070a5ec7a5c3605d28fe2e7f769609666f92d75d20a5`
- frozen library hash: `66152c96fac040ea94b21c6a45ebf6a7ec20c6960ece0ef3c955244fa3da52f8`
- amplitude grid: `0.08:0.02:0.44`
- passage candidate step: `0.2`

Canonical-v3 full-history specification-refit reference hash, independently cross-checked during audit:

`ae539389e556fb342c6ea5e1a391fed027c46ff509326536647ff3d34fb79bfb`

Historical replay rebuilds this specification from strictly prior seasons rather than using the full-history operational library directly. The benchmark must emit a parity table comparing canonical-v3 A peak truth to the original frozen M1-A `library$peak_truth`, including the known vintage differences.

The timing distribution supplied to M2-A is the **raw continuous passage posterior** from `m1_v2_passage_posterior()`. The frozen scalar calibrator and hard passage policy are not applied: `m1_v2_apply_bias_calibration()` and `m1_v2_passage_decision()` must never be called. This is a new M2 timing input relative to the repaired M2-v2 evidence, which used calibrated peak means and then locked peak coordinates after hard passage confirmation. The point-mean diagnostic is defined as the mean of this same raw passage posterior, not a calibrated mean.

### M2-A state baseline

Use the same state/growth form as the repaired M2-v2 work:

`logit p(t+h) = logit p*(t) + horizon + growth_1 + growth_2`

with quasi-binomial fitting and 0.5 pseudocount stabilization.

No denominator-regime coefficient is fitted.

## Canonical data source

Use only:

`artifacts/v3-joint-ab-audit-v1/canonical_ab_weekly_v3.csv`

The same canonical panel supplies:

- A state-model ledger;
- fold-local M1-A libraries;
- causal A activation replay;
- A retrospective shape construction;
- eligible pooled B shape context.

Record its SHA-256 in the source manifest.

## Season policy

A modeling retains the unchanged A policy:

- all 11 canonical A seasons are eligible for A state training, A timing training, A shape construction and scoring;
- 2019-20 is **not** excluded from A modeling.

For the pooled C2 shape contribution only:

- A shapes follow the unchanged A policy and may include 2019-20;
- B shapes use the finalized B policy and exclude 2018-19 and 2019-20.

The B exclusions do not alter A truth, A timing, or A state training.

## Candidate-independent A forecast ledger

For each season, origin and horizon:

- origins start at `weekF >= 13`;
- require at least two prior A observations for growth features;
- horizons are +1 and +2 only;
- target week must exist and be contiguous;
- row existence must not depend on M1-A availability.

Fields:

- `season`, `origin_week`, `target_week`, `horizon`;
- current stabilized A positivity;
- one-week and two-week stabilized logit growth;
- target A `y/N/p`;
- denominator regime provenance.

## Outer chronological validation

For each target season `s`:

- A state-model training seasons are strictly earlier seasons;
- M1-A library seasons are strictly earlier A seasons;
- A shape seasons are strictly earlier A seasons;
- pooled B shape seasons are strictly earlier B-shape-eligible seasons;
- no later season enters any fitted component;
- target outcomes enter only after predictions are frozen.

Minimum support:

- A1 state baseline: at least 3 prior seasons;
- M1-A timing correction: at least 5 prior A seasons, matching the repaired governed-A evidence support;
- otherwise timing challenger returns exact A1.

## Causal A activation

At every forecast origin:

1. take only the A prefix through the origin;
2. load the exact frozen M0-A parameter object and call `detectIgnitionBySeason_M0v2_timing(prefix, params, iWeek=FALSE, validate_support=FALSE)` as in the weekly-v2 runtime;
3. do **not** modify `w_max` to the current origin; the detector must see the frozen policy and the prefix data naturally limits available observations;
4. treat activation as inactive whenever `detection_failed` is true or `iWeek_hat` / `iWeek_hatF` is missing; never interpret the detector's `w_max` fallback as activation;
5. if activated, require fractional activation week `<= origin`;
6. record the causal fractional crossing used at that origin.

Add an activation latch audit: once a season activates, later prefixes must retain the same integer/fractional activation coordinate or the mismatch is explicitly logged and treated as an integrity failure. Emit a separate end-of-season prefix-vs-frozen-activation-table comparison for audit only; the frozen activation table is never a predictor.

Future perturbation must prove that changing A observations after the origin cannot alter the prefix activation or forecast.

## Fold-local M1-A library

For each outer fold:

- fit `fit_m1_v2_library()` on strictly prior A seasons;
- use v3 timing-contract A peak truth;
- `k = 8`, grid step `.01`, tau step `.1`;
- amplitude grid exactly `0.08:0.02:0.44`.

A full-history canonical-v3 reproduction check must rebuild all 11 A seasons and reproduce the **canonical-v3 reference hash** `ae539389e556fb342c6ea5e1a391fed027c46ff509326536647ff3d34fb79bfb`. Separately verify specification identity with the frozen stage (`version`, `k=8`, grid step `.01`, tau step `.1`, amplitude grid). Do not require the canonical-v3 rebuild to equal the original frozen library hash.

No scalar calibration is applied inside M2-A timing correction. No hard passage decision is called.

## Continuous M1-A passage posterior

At active origins call:

`m1_v2_passage_posterior()`

using:

- candidate step `0.2`;
- max future horizon `12` weeks.

Use the attached posterior over candidate peak weeks as the timing distribution for M2-A. Any `m1_v2_passage_posterior()` error or empty admissible candidate set is timing-unavailable and must fall back exactly to A1 with the error reason logged.

Log:

- probability peak passed;
- posterior mean peak;
- posterior supported mass;
- lower candidate-bound mass as a monitoring diagnostic.

The passage component cannot represent arbitrarily old peaks; therefore the benchmark must also report +2 performance stratified by retrospective scoring phase (pre-peak, near-peak, post-peak) and by lower-bound-mass strata. These are diagnostics only and cannot change routing.

## Shape library

Rebuild peak-aligned normalized shapes from the canonical v3 panel and v3 retrospective peak truth.

Tau grid:

`-8:0.25:+8`

### A-specific contribution

Use strictly prior A seasons.

### Pooled A/B contribution

Use:

- strictly prior A shapes under unchanged A policy;
- strictly prior eligible B shapes excluding 2018-19 and 2019-20.

No target retrospective shape enters prediction. The B-pool policy is an explicit departure from older fixed-C2 evidence: B 2018-19 is infeasible under v3 timing truth and B 2019-20 is excluded by the finalized pandemic-transition policy. `shape_library_ledger.csv` must record A and B contributors separately for every outer fold.

## Fixed C2 correction

Use the already-reviewed fixed C2 family only:

`LR_C2_A(tau,h) = 0.5 * median_pooled_AB(LR) + 0.5 * median_A(LR)`

with fixed state/shape logit blend:

`eta = 0.5`

No alpha/eta/threshold tuning is performed in this study.

## Posterior-mixture correction

For each candidate A peak week `T` in the M1-A passage posterior:

- `tau(T) = origin_week - T`;
- obtain prior-only `LR_C2_A(tau(T),h)` when supported; a candidate is supported **only when both the pooled A/B median LR and the A-specific median LR are finite** at the required current/future tau coordinates; there is no half-C2 fallback;
- calculate the C2 shape projection;
- blend A1 and shape projection with fixed `eta = 0.5`.

Unsupported posterior candidates contribute exact A1 rather than renormalizing the timing posterior.

Final prediction:

`p_M2A = sum_supported w(T)*blend_A(T) + sum_unsupported w(T)*A1`

## Comparators

For each origin:

1. `A0_persistence`
2. `A1_state`
3. `A2_pointmean_C2` — diagnostic only, using the mean of the same raw passage posterior
4. `A2_posterior_C2` — primary timing challenger

## Horizon policy

### A +1

Diagnostic only. Final v3 shadow routing remains exact A1 regardless of retrospective result in this study.

### A +2

Posterior-C2 is the sole timing-informed candidate eligible for shadow qualification.

## Leakage / integrity tests

Required:

1. all state/timing/shape training seasons are strictly earlier than target;
2. causal prefix activation is invariant to future-data perturbation;
3. future A observations after origin do not change A1, M1-A posterior or M2-A correction;
4. perturbing held-out A peak truth does not change predictions;
5. perturbing held-out A forecast target changes scoring only;
6. timing-unavailable rows equal exact A1;
7. fully unsupported posterior mass equals exact A1;
8. full-history canonical-v3 library reproduces the canonical-v3 reference hash, M1-v2 specification identity matches the frozen stage, and a frozen-vs-v3 peak-truth parity table is emitted;
9. neither `m1_v2_apply_bias_calibration()` nor `m1_v2_passage_decision()` is called;
10. fixed C2 weights/eta are unchanged;
11. B pooled-shape context excludes 2018-19 and 2019-20 B shapes;
12. repeated execution is deterministic;
13. M0 parameter-artifact hash and final-vintage canonical-panel hash are emitted;
14. activation latch and end-of-season activation-parity audits pass;
15. all source hashes/fold ledgers are emitted.

## Metrics

Report +1/+2 separately.

Primary:

- season-balanced MAE percentage points;
- RMSE;
- bias;
- per-season change versus A1;
- worst-season MAE;
- seasons improved/worsened.

Secondary:

- pooled per-target-test binomial NLL;
- timing-active-only MAE;
- timing availability;
- posterior support diagnostics;
- fallback frequencies;
- denominator-regime provenance;
- retrospective phase-stratified +2 metrics (pre / near / post peak, scoring only);
- lower-bound-mass-stratified +2 metrics.

This is a **final-vintage historical replay**, not an as-issued real-time-vintage replay. Historical revisions are documented in the v3 source-overlap/revision audit, especially for modern seasons; this limitation must be carried into the interpretation.

## Predeclared A +2 decision rule

`historically_promising = TRUE` only if all are true:

- season-balanced MAE improves by at least 5% versus A1;
- timing-active-season MAE improves by at least 5%;
- strict majority of timing-active seasons improve, with at least 3 improved seasons;
- no timing-active season worsens by more than 0.15 percentage points MAE;
- worst-season service-wide MAE does not worsen by more than 0.20 percentage points, defined as `max_s(MAE_M2A(s)) - max_s(MAE_A1(s)) <= 0.20`;
- pooled target-test NLL does not worsen by more than 0.001;
- all integrity/leakage checks pass.

A timing-active season is predeclared as a scored season with at least one +2 row receiving a non-zero timing correction. A1 is recomputed on the canonical v3 panel inside the same chronological folds and must not be numerically compared to the older repaired-v2 A1 benchmark as if they were identical datasets.

Passing grants shadow eligibility only. It does not replace frozen v2 or authorize production promotion.

## Outputs

Write to:

`artifacts/v3-m2-a-posterior-c2-chronological-v1/`

Required files:

- `candidate_independent_ledger.csv`
- `outer_fold_ledger.csv`
- `timing_library_ledger.csv`
- `shape_library_ledger.csv`
- `per_origin_predictions.csv`
- `per_season_metrics.csv`
- `summary_metrics.csv`
- `active_timing_summary.csv`
- `posterior_support_diagnostics.csv`
- `fallback_summary.csv`
- `future_perturbation_checks.csv`
- `truth_target_perturbation_checks.csv`
- `integrity_checks.csv`
- `acceptance_criteria.csv`
- `overall_verdict.csv`
- `source_manifest.csv`
- `benchmark_config.csv`

## Post-benchmark action

If A +2 passes:

- freeze shadow routing as `A +1 = A1`, `A +2 = posterior C2 when causal M1-A timing is available, otherwise A1`;
- package separately from the B artifact;
- later combine A and B into the full v3 weekly shadow runner.

If A +2 fails:

- retain exact A1 for both horizons;
- stop retrospective A timing-correction tuning and rely on prospective evidence rather than searching more historical variants.
