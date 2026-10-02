# V3 M2-B final historical disposition

Date: 2026-09-26
Status: historically qualified for prospective shadow; not production-promoted

## Frozen routing decision

For v3 M2-B shadow evaluation:

- **B +1:** route to exact B1 state/growth forecast.
- **B +2:** when causal M1-B timing is available, use the fixed C2 posterior-mixture correction; otherwise return exact B1.
- No hard M1-B passage gate is allowed.
- No scalar M1-B calibration or A-conditioned B timing is allowed.

Historical benchmark:

`artifacts/v3-m2-b-posterior-c2-chronological-v3/`

Implementation:

`scripts/v3_benchmark_m2_b_posterior_c2_chronological_v3.R`

Audited design:

`docs/v3-m2-b-implementation-plan-2026-09-26.md`

## Season policy

The canonical panel remains unchanged for audit/provenance.

For v3 B modeling:

- `2019-20` is excluded as `pandemic_transition` from B state training, B timing training, B shape training and B forecast scoring/model selection.
- `2018-19` remains eligible for B state forecasting/training but is an explicit no-B-timing-event season; its timing correction is exactly zero.
- This policy does not alter frozen M2-v2 or M1-A results.

## Historical result

### B +1

The timing challenger is diagnostic only.

Season-balanced MAE:

- B1: `0.305075` percentage points
- posterior C2: `0.296929` percentage points
- relative gain: `2.67%`

Per the predeclared plan, +1 remains exact B1 regardless of this diagnostic improvement.

### B +2

Across seven service-wide chronological test seasons:

- B1 season-balanced MAE: `0.514552` percentage points
- posterior C2 season-balanced MAE: `0.436010` percentage points
- relative MAE gain: `15.26%`
- B1 worst-season MAE: `1.172716` percentage points
- posterior C2 worst-season MAE: `0.763391` percentage points
- pooled per-target-test NLL: `0.0778858 -> 0.0776416`
- seasons improved: `5`
- seasons worsened: `0`

Among the five timing-active seasons:

- B1 season-balanced MAE: `0.735688` percentage points
- posterior C2 season-balanced MAE: `0.552439` percentage points
- relative MAE gain: `24.91%`
- all `5/5` timing-active seasons improve.

The predeclared +2 historical criteria all pass.

## Interpretation of the M1-B timing contribution

The passage posterior used here has a causal lower support boundary roughly three weeks before the origin. At later origins, posterior mass frequently accumulates at that boundary.

This is therefore best interpreted as a **continuous B phase/post-peak correction informed by M1-B**, not as proof of finely resolved B peak timing.

Post-review diagnostic at +2:

- active rows: `89`
- rows with lower-bound posterior mass >= `0.9`: `44`
- lower-bound-saturated rows: B1 MAE `0.7696` pp -> posterior C2 `0.4616` pp (`40.0%` gain)
- remaining active rows: B1 MAE `0.8984` pp -> posterior C2 `0.7345` pp (`18.2%` gain)

If the 44 lower-bound-saturated rows are diagnostically reset to B1, season-balanced active improvement falls from `24.9%` to `8.3%`, with `4/5` active seasons still improving.

This diagnostic does **not** change the historical candidate. It establishes a mandatory prospective monitoring stratum.

## Causal / integrity validation

Validation-hardened v3 preserves the v2 model predictions and decision outputs exactly while completing provenance for helper-v7 and all sourced PAGe timing code.

Verified:

- prefix-only causal B activation;
- strict chronological state/timing/shape folds;
- 2019-20 absent from all B training/scoring paths;
- 2018-19 exact B1 timing fallback;
- fold-local M1-B libraries reproduce the frozen v8 full-history library hash when trained on the same nine seasons;
- passage posterior settings are pinned to step `0.2`, horizon `12` from helper v7;
- B shapes use the canonical v3 panel and exclude 2018-19/2019-20;
- A 2019-20 shape may contribute only to the pooled A component under the unchanged A policy;
- unsupported posterior mass contributes exact B1 rather than being renormalized;
- no hard passage decision is called;
- all predeclared integrity checks pass;
- no unexpected failure rows.

Real perturbation reruns:

- seven held-out truth/forecast-target recomputation checks: zero change to prediction; for 2016-17 and 2018-19 the truth-library portion is trivially inactive because no timing library is available, while the target/B1 recomputation remains real;
- ten first/last timing-active-origin future-observation perturbations: zero change to activation, posterior, B1 or M2-B prediction.

Determinism:

- the v2 determinism rerun matched byte-for-byte across all emitted CSV artifacts; the final v3 evidence run is numerically identical to v2 and adds complete source-code/helper hashes plus an explicit no-hard-passage-call integrity check.

Tests:

- hardened M2-B v2 contract: `98/98` assertions passed with zero failures/warnings/skips; the v3 evidence run adds provenance/integrity hardening without changing model outputs;
- combined M1-B/M2-B contract suite was also clean before the v2 hardening rerun.

## Historical decision

`historically_promising = TRUE`

Decision:

`eligible_for_v3_shadow_plus2`

This means **prospective shadow eligibility only**.

It does not authorize:

- replacing the frozen production/v2 forecast;
- a hard B peak-passage gate;
- further retrospective threshold tuning;
- claiming the M1-B passage posterior is a calibrated fine-grained peak posterior.

The B activity detector and B amplitude support were developed with knowledge of the historical archive, and the historical test set is small. 2026-27 must therefore be treated as prospective evidence.

## Required shadow monitoring

Every prospective B +2 shadow forecast must log:

- B1 forecast;
- posterior-C2 forecast;
- timing available / fallback reason;
- causal B activity week;
- passage posterior probability peak passed;
- supported posterior mass;
- lower-bound posterior mass;
- whether lower-bound mass is >= `0.9`;
- M1-B and M2-B artifact IDs/hashes;
- as-issued data vintage.

Prospective scoring must report:

1. all B +2 shadow forecasts;
2. timing-active forecasts;
3. lower-bound-mass >=0.9 forecasts;
4. lower-bound-mass <0.9 forecasts;
5. exact-B1 fallback forecasts.

## Frozen shadow packaging target

Package this decision as a separate v3 M2-B **shadow-only runtime artifact/helper**:

- target artifact version: `m2-b-v3-shadow-v2`;
- target helper: `scripts/v3_m2_b_runtime_helpers_v2.R`;
- full-history B1 fit excludes 2019-20;
- full-history M1-B timing library is the frozen v8 artifact;
- full-history C2 shape library uses the canonical v3 panel with the frozen season policy;
- runtime route is `+1 = B1`; `+2 = posterior C2 if causal timing is available, otherwise B1`;
- lower-bound saturation (`>=0.9`) is monitoring-only and cannot change routing;
- helper must expose diagnostics above and forbid any production/promotion flag;
- integrate only into the separate v3 weekly shadow runner.
