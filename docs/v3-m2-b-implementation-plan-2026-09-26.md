# V3 M2-B implementation plan

Date: 2026-09-26
Status: audited design; approved with fixes incorporated; ready for implementation

## Objective

Test whether the frozen v3 M1-B continuous passage posterior improves Influenza B +2 forecasting beyond the B state/growth baseline, without introducing a hard passage gate.

The primary decision question is:

> Does a posterior-averaged B timing correction improve B +2 under strict chronological replay while preserving exact fallback behavior?

B +1 is diagnostic only and remains routed to exact B1 in this study.

## Frozen upstream contracts

### M1-B

Use the frozen v3 B semantics documented in:

- `docs/v3-m1-b-season-policy-2026-09-26.md`
- `docs/v3-m1-b-final-disposition-2026-09-26.md`

The full-history runtime artifact is:

`artifacts/m1-b-v3-peak-v8/m1_b_v3_peak_artifact.rds`

Historical replay must not use that full-history fitted library directly. Each outer chronological fold rebuilds the same B library from strictly prior timing-eligible seasons.

Frozen semantics:

- 2019-20: `excluded_pandemic_transition`;
- 2018-19: `inactive_no_timing_event` / no finite B peak timing target;
- no scalar timing calibration;
- no A-conditioned B timing;
- no hard passage decision;
- continuous passage posterior only.

### M2-B state baseline

Use the established B1 state/growth form:

`logit p(t+h) = logit p*(t) + horizon + growth_1 + growth_2`

with quasi-binomial fitting and 0.5 pseudocount stabilization.

No denominator-regime coefficient is fitted. Regime remains provenance only.

## Canonical data source

Use one panel everywhere:

`artifacts/v3-joint-ab-audit-v1/canonical_ab_weekly_v3.csv`

The same canonical panel supplies:

- forecast ledger;
- B state-model training;
- fold-local M1-B libraries;
- causal B activation replay;
- retrospective shape construction.

Record its SHA-256 in the source manifest. Do not mix the older `flu_ab_weekly_v1` panel into this benchmark.

## V3 B season policy

For M2-B:

- 2019-20 is excluded from all B state-model training, timing-library training, B shape construction, tuning, and scoring;
- 2018-19 remains valid for state-only B forecasting/training and service-wide scoring, but timing correction is forced to exactly zero regardless of detector output;
- all other canonical B seasons are eligible subject to chronological support.

The 2019-20 exclusion is B-specific. A shapes from 2019-20 may remain in the pooled A contribution because the A policy was not changed.

Because v3 B1 excludes 2019-20, its metrics are a new v3 baseline and are not numerically interchangeable with the reviewed M2-v2 B1 benchmark.

## Candidate-independent forecast ledger

For each season, origin and horizon:

- origins start at `weekF >= 13`;
- require at least two historical B observations for growth features;
- horizons are +1 and +2 only;
- target week must exist and be contiguous;
- row existence must not depend on timing availability.

Required fields:

- `season`, `origin_week`, `target_week`, `horizon`;
- current stabilized B positivity;
- one-week and two-week stabilized logit growth;
- target `y/N/p`;
- denominator-regime provenance.

## Outer chronological validation

For each target season `s`:

- B1 state-model training seasons are strictly earlier B seasons, excluding 2019-20;
- timing-library seasons are strictly earlier meaningful-B seasons, excluding 2018-19 and 2019-20;
- B shape seasons are strictly earlier and B-eligible for timing, excluding 2018-19 and 2019-20;
- pooled A shape contribution may use strictly earlier A seasons, including 2019-20 A where chronologically prior;
- no later season enters any fitted component;
- target outcomes enter only for scoring after predictions are frozen.

Minimum support:

- B1 state baseline: at least 3 prior eligible state-training seasons;
- M1-B timing correction: at least 4 prior meaningful-B timing seasons;
- otherwise return exact B1.

## Causal B activation replay

Never read whole-season activation outputs when constructing an origin prediction.

At each origin:

1. take only the B prefix through the origin;
2. apply the frozen transferred-A-rule B detector contract with window `weekF 8-40` and the fixed A-derived evidence thresholds;
3. if no activation is detectable from that prefix, timing state is `inactive_no_timing_event` and timing correction is zero;
4. if activated, require `activity_week <= origin`;
5. save the causal fractional crossing used at that origin.

Future-perturbation tests must demonstrate that modifying observations after the origin cannot change the prefix-derived activation week, including the fractional crossing.

For 2018-19, the explicit no-event policy overrides any detector output and timing correction remains exactly zero.

## Fold-local M1-B validation

The governed full-history validator hard-codes the nine-season frozen artifact and therefore is not used directly for chronological fold libraries.

Implement a fold-local validator that checks:

- training seasons exactly equal expected prior timing-eligible seasons;
- 2018-19 and 2019-20 are absent;
- B amplitude grid is `0.005:0.005:0.25`;
- no scalar calibration;
- no A-conditioning;
- passage posterior settings are sourced from `scripts/v3_m1_b_runtime_helpers_v7.R`;
- candidate step equals `.M1_B_PASSAGE_CANDIDATE_STEP = 0.2`;
- max future horizon equals `.M1_B_PASSAGE_MAX_FUTURE_WEEKS = 12`.

As a reproduction check, a library built on all nine frozen timing seasons must reproduce the v8 `library_hash`.

## M1-B posterior used by M2-B

The timing distribution used for M2-B is explicitly:

`passage <- m1_v2_passage_posterior(...)`

`posterior <- attr(passage, 'posterior')`

with settings sourced from helper v7:

- candidate step `0.2`;
- max future horizon `12`.

This is the passage posterior, not the 0.1/16 peak-location posterior. The previously reported ~1.66-week peak MAE does not apply to this posterior.

At each active origin, use only B observations available through that origin.

## Posterior lower-bound diagnostic

`m1_v2_passage_posterior()` cannot place a peak more than the passage-component support behind the latest observation. Log for every active origin:

- lower candidate bound;
- posterior mass within one candidate step of that lower bound.

This is diagnostic only and is not used for gating or tuning.

## Shape library

Rebuild the retrospective peak-aligned normalized shape grid from the canonical v3 panel using the v3 timing-contract peak truth.

### B shape contribution

Use only strictly prior B timing-eligible seasons:

- exclude 2018-19;
- exclude 2019-20.

### Pooled A/B contribution

For the pooled component:

- B contribution uses the same eligible prior B seasons above;
- A contribution uses strictly prior A seasons under the unchanged A policy, including 2019-20 A if chronologically prior.

Each outer fold records exactly which A and B seasons contribute to the shape library.

## Fixed C2 correction

Use the already-reviewed fixed C2 shape family only.

For relative timing coordinate `tau` and horizon `h`:

`LR_C2(tau,h) = 0.5 * median_pooled_AB(LR) + 0.5 * median_B(LR)`

where both pieces are constructed strictly from prior eligible shape seasons.

The 0.5/0.5 C2 weights and blend `eta = 0.5` are inherited fixed constants from the reviewed M2-v2 design. They are not retuned here.

## Posterior-mixture correction

For each B candidate peak `T` in the passage posterior:

- `tau(T) = origin_week - T`;
- obtain prior-only `LR_C2(tau(T), h)` when supported;
- compute the C2 shape projection;
- blend B1 and shape projection on the logit scale with fixed `eta = 0.5`.

Supported posterior candidates contribute their blend prediction.

Unsupported posterior candidates contribute **exact B1**, not a renormalized timing prediction:

`p_M2B = sum_supported w(T)*blend(T) + sum_unsupported w(T)*B1`

This makes the correction continuous and removes the arbitrary 0.80 support threshold.

Log supported posterior mass on every row.

## Comparators

For every eligible origin save:

1. `B0_persistence` — current stabilized positivity;
2. `B1_state` — state/growth baseline;
3. `B2_pointmean_C2` — diagnostic fixed-C2 correction using the passage-posterior mean candidate;
4. `B2_posterior_C2` — primary posterior-mixture candidate.

The point-mean comparator is diagnostic only.

## Horizon policy

### B +1

Diagnostic only. Always route the eventual v3 +1 forecast to exact B1 in this study.

No +1 promotion decision is allowed.

### B +2

The posterior-mixture C2 candidate is the sole timing-informed promotion candidate.

## Leakage and integrity tests

Required automated checks:

1. state-training seasons are strictly earlier and never include 2019-20;
2. timing-library seasons are strictly earlier and never include 2018-19 or 2019-20;
3. B shape seasons are strictly earlier and never include 2018-19 or 2019-20;
4. causal prefix activation satisfies `activity_week <= origin` and is invariant to future-data perturbation;
5. future B observations after origin do not change B1, M1-B posterior, or M2 correction;
6. perturbing outer B peak truth does not change predictions;
7. perturbing outer forecast targets changes scoring only, never predictions;
8. 2018-19 timing correction is exactly zero at every row;
9. 2019-20 contributes zero B training/scoring rows;
10. timing-unavailable rows are numerically identical to B1;
11. fully unsupported posterior mass yields exact B1;
12. no hard-passage decision helper is called;
13. fold-local M1-B validators pass;
14. the all-nine-season fold-local library reproduces the v8 library hash;
15. repeated execution is deterministic;
16. source hashes and fold ledgers are emitted.

## Metrics

Report +1 and +2 separately.

Primary:

- season-balanced MAE in percentage points;
- season-balanced RMSE;
- bias;
- per-season MAE difference versus B1;
- worst-season MAE;
- seasons improved/worsened.

Secondary:

- binomial NLL per target test;
- active-timing-only MAE;
- posterior timing availability;
- supported posterior mass distribution;
- passage lower-bound mass diagnostic;
- fallback frequencies;
- denominator-regime provenance summaries.

## Predeclared B +2 decision rule

`historically_promising = TRUE` only if all are true:

- season-balanced MAE improves by at least 5% versus B1;
- timing-active-season MAE improves by at least 10%;
- a strict majority of timing-active seasons improve, with at least 2 improved seasons;
- no timing-active season worsens by more than 0.15 percentage points MAE;
- worst-season service-wide MAE does not worsen by more than 0.10 percentage points;
- binomial NLL does not materially worsen by more than 0.001 per target test;
- all fallback identities and leakage/integrity tests pass.

Passing grants shadow eligibility only because the B activity detector/amplitude support have already seen the historical archive.

## Outputs

Write a new immutable artifact tree:

`artifacts/v3-m2-b-posterior-c2-chronological-v1/`

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

If B +2 passes:

- freeze v3 M2-B routing as `+1 = B1`, `+2 = posterior-mixture C2 when causal M1-B timing is available, otherwise exact B1`;
- package as a separate v3 shadow artifact;
- run prospectively in 2026-27 without historical retuning.

If B +2 fails:

- retain exact B1 for both horizons;
- stop historical M2-B timing-correction tuning and move to prospective evidence rather than searching additional timing models on the same small archive.
