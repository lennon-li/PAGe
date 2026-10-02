# PAGe v3 calibrated B-only M1-B benchmark — implementation review

Date: 2026-09-25
Status: calibration branch stopped; raw M1-B0 retained

## Question

Can the frozen M1-v2 governed timing machinery be instantiated for Influenza B, using B-specific amplitude support and B activity activation, to improve raw B-only peak timing and provide a reliable passage state?

## Plan and implementation

Plan:

- `docs/v3-m1-b-governed-implementation-plan-2026-09-25.md`

Implementation:

- `scripts/v3_benchmark_m1_b_calibrated_chronological_v1.R`

Artifacts:

- `artifacts/v3-m1-b-calibrated-chronological-v1/`

The benchmark is explicitly **conditional research**, not governed production evidence, because the current B activity rule/window was selected with knowledge of the full historical archive.

## Peak-location result

### All six scored seasons

| Metric | Raw M1-B0 | Calibrated M1-B |
|---|---:|---:|
| Season-balanced MAE | 1.8705 | 1.8965 |
| Early-weighted MAE | 1.8421 | 1.8655 |
| Season-balanced RMSE | 2.0427 | 2.0778 |
| Bias | +1.4291 | +1.4282 |
| 90% coverage | 0.8125 | 0.7679 |
| Worst-season MAE | 5.2742 | 5.5009 |

Calibration is slightly worse overall.

### Excluding predeclared low-support 2017-18

| Metric | Raw M1-B0 | Calibrated M1-B |
|---|---:|---:|
| Season-balanced MAE | 2.1914 | 2.1453 |
| Early-weighted MAE | 2.1551 | 2.1035 |
| 90% coverage | 0.775 | 0.750 |
| Worst-season MAE | 5.2742 | 5.5009 |

The scalar calibrator is slightly favorable on this restricted set, but the effect is not stable enough for promotion.

## Per-season calibration behavior

- 2017-18: raw 0.266 -> calibrated 0.652 weeks MAE; worsened substantially.
- 2019-20: 2.523 -> 2.499; negligible improvement.
- 2022-23: 5.274 -> 5.501; worsened the main failure case.
- 2023-24: 1.677 -> 1.469; improved.
- 2024-25: 1.005 -> 0.857; improved.
- 2025-26: 0.478 -> 0.400; improved.

Four of six seasons improve numerically, but the two worsened seasons dominate the season-balanced result.

## Calibration offsets are unstable

Chronological fold offsets:

- 2017-18: +0.490 weeks
- 2019-20: +0.094
- 2022-23: +0.227
- 2023-24: -0.208
- 2024-25: -0.318
- 2025-26: -0.291

Independent post-review recomputed the offsets exactly and found their sampling uncertainty much larger than the estimated offsets. The scalar correction is therefore best interpreted as noise at this sample size rather than a stable B timing bias.

The sign flips after the first modern type-specific-denominator season enters the calibration archive.

Diagnostic removal of 2022-23 changes later offsets by roughly +0.56 to +0.94 weeks, confirming that one season has disproportionate leverage.

## Observation-regime diagnostic

Shared-denominator proxy test seasons:

- raw MAE 1.395
- calibrated MAE 1.576

Modern type-specific test seasons:

- raw MAE 2.109
- calibrated MAE 2.057

This is consistent with a possible observation-regime effect, but regime is confounded with calendar era/post-COVID seasons and the sample is too small to estimate a defensible regime-specific calibrator in this branch.

Do not add a regime-specific offset after seeing these results. That would require a new predeclared evaluation cycle.

## Passage result belongs to raw M1-B0

Calibration changes only the reported peak-location summaries. It does not alter the raw posterior or passage probabilities.

Therefore the passage findings below are a property of **raw M1-B0**, not a calibration failure.

Chronological passage replay:

- false-early seasons: 1/6
- false-early magnitude: 1 week
- confirmed by peak+2: 3/6
- mean delay with misses/late confirmations penalized: 1.83 weeks
- median observed delay: 2 weeks

The false-early season is 2019-20:

- retrospective B peak: 33.09
- truth confirmation coordinate: 33
- first passage confirmation: week 32
- branch: `high_posterior_decline`

The post-review reproduced the trajectory and found that a one-week positivity dip plus posterior passage probability ~0.967 triggered the fast branch one week early.

All six outer confirmations used the fast `high_posterior_decline` branch. Consequently the selected sustained-branch parameters are mostly tie-broken rather than empirically identified.

Do not tune `fast_drop_fraction` on 2019-20 in this branch; the season has already been inspected.

## Integrity and causality checks

Passed:

- exact raw B0 recomputation against the prior chronological baseline at every scored origin;
- 33/33 future-B peak-prediction perturbation checks;
- passage future-invariance checks through every replayed origin;
- calibrator/library hash identity in every fold;
- passage-policy/library hash identity in every fold;
- 2018-19 excluded from all meaningful-B timing training stages;
- no silent primary forecast-origin failures.

Activation sensitivity now records all 66 requested rows:

- shift -1: 33 successful origins;
- shift +1: 27 successful origins;
- shift +1: 6 explicit `unsupported_at_origin` rows rather than silent drops.

The benchmark also saves each fold's selected passage-policy inner evaluation.

## Predeclared interpretation

For the all-season set, calibration fails both headline improvement criteria:

- calibrated MAE <= raw: **fail**
- calibrated early-weighted MAE <= raw: **fail**

It passes:

- worst-season degradation <= 0.5 week;
- at most two seasons worse;
- coverage >= 0.70;
- prediction integrity.

Excluding predeclared low-support 2017-18, calibration passes the numerical calibration criteria, but the effect is small and unstable to individual training seasons.

Passage is assessed separately and fails the desired zero-false-early criterion.

## Independent post-review conclusion

No critical code bug invalidates the result.

The correct interpretation is:

1. **Stop scalar B calibration.**
2. **Retain raw M1-B0 for B peak location.**
3. Do not treat the passage failure as evidence against calibration; it is a raw M1-B0 passage issue.
4. Do not connect raw M1-B0 passage directly to an M2-B timing gate without a separate, predeclared passage-robustness evaluation.

## Decision

**Peak location:** retain raw M1-B0.

**Scalar calibration:** stopped.

**B passage:** unresolved research issue; current raw passage has one 1-week false-early season and only 3/6 confirmations by peak+2.

**Governance:** no governed M1-B artifact is promoted from this branch because activation itself remains globally selected and passage is not yet adequate.

## Next step

Open a separate, predeclared **B passage robustness** cycle if a passage gate is needed for M2-B.

That cycle must be designed before inspecting alternative threshold results. It should not retune the current fast branch ad hoc on 2019-20.

Until then, raw M1-B0 may be used as a research peak-location posterior/summary, but not as a governed B passage gate.
