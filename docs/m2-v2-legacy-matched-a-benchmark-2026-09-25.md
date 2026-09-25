# M2-v2 versus frozen legacy M2 — matched A-only benchmark — 2026-09-25

## Purpose

Provide the direct comparison that the immutable legacy benchmark contract requires: score frozen legacy M2 and M2-v2 on the **same Influenza-A season/origin/target/horizon rows and the same target probabilities**.

This is an exchangeable cross-fitted/outer-LOSO comparison. It is separate from the prior-seasons-only chronological replay, which remains the main deployment-style validation for M2-v2.

## Frozen legacy comparator

Final kit:

`../PAGe/results/final-kit-2026-27/20260918T1520Z-final-2026-27-wmin8-venkata/`

Artifact ID:

`m2_c1e467afffdadff25087be357fa42d231c3632d776e639bffafb9173ae1e3c54`

Family:

`offset_subset_v1`

Governed specification:

`h1:i0_kz0_ku0_kd0|h2:i0_kz0_ku0_kd0`

The frozen fit is `type = all_off` at both horizons. By the governed predictor contract, an all-off M2 returns the supplied saved M1 probability **bit-for-bit** and applies zero M2 correction. Therefore the frozen legacy M2 matched prediction is the saved cross-fitted `m1_p_hat` in `m2_frozen.rds`.

## M2-v2 comparator

Source:

`artifacts/m2-v2-ab-curve-ratio-c123-v1/outer_loso_predictions.csv`

Use A rows only.

- `pred_base`: type-A state/growth baseline trained out-of-season.
- `pred_C2`: fixed C2 curve correction with exact baseline fallback when timing is unavailable.

No selected-family result is used in this benchmark.

## Matched ledger

Exact key:

`season + origin_week + target_week + horizon`

Matched rows:

- total: **635**;
- +1: **323**;
- +2: **312**;
- all 11 seasons represented.

The first 10 historical seasons have **identical target y/N counts** between the legacy final kit and the current M2-v2 reconstruction.

2025-26 differs because the current data snapshot was revised after the September 18 legacy final kit:

- 33 rows have changed A-positive counts;
- 57 rows have changed denominators;
- sum absolute positive-count revision: 1,374;
- sum absolute denominator revision: 3,364.

Therefore the primary comparison uses the first 10 seasons with identical target counts. An 11-season sensitivity scores both predictions on the current M2-v2 target snapshot.

Important limitation: even in the 10-season target-identical comparison, the **training snapshots are not perfectly vintage-matched**, because exchangeable M2-v2 outer fits can train on the revised 2025-26 season whereas the old final kit trained on its earlier 2025-26 snapshot. The result is target-ledger matched, not a claim of bit-identical historical training inputs.

## Primary result — 10 historical seasons, identical target counts

Season-balanced metrics:

| Horizon | Frozen legacy M2 MAE pp | M2-v2 state/growth MAE pp | Fixed C2 MAE pp | C2 vs legacy relative MAE gain | C2 vs new baseline gain |
|---|---:|---:|---:|---:|---:|
| +1 | 8.4087 | 1.7757 | **1.5435** | 81.6% | 13.1% |
| +2 | 9.2056 | 2.4124 | **2.1531** | 76.6% | 10.8% |

RMSE:

| Horizon | Legacy | New baseline | Fixed C2 |
|---|---:|---:|---:|
| +1 | 11.2141 pp | 2.9531 pp | **2.4915 pp** |
| +2 | 12.3544 pp | 3.8306 pp | **3.3459 pp** |

Mean per-test Bernoulli NLL on the matched rows:

| Horizon | Legacy | New baseline | Fixed C2 |
|---|---:|---:|---:|
| +1 | 0.39017 | 0.26441 | **0.26339** |
| +2 | 0.39544 | 0.26954 | **0.26784** |

Season-level direction:

- +1: fixed C2 better than frozen legacy in **10/10** seasons;
- +2: fixed C2 better in **10/10** seasons;
- exact paired sign-test p-value: **0.001953** at each horizon;
- median season-level MAE reduction: **2.12 pp (+1)** and **2.13 pp (+2)**.

## Legacy outlier sensitivity

The mean relative improvement is inflated by a major legacy failure in 2013-14:

- legacy +1 MAE: 45.44 pp;
- legacy +2 MAE: 46.09 pp;
- fixed C2: 2.12 pp / 3.09 pp.

Removing 2013-14 entirely:

| Horizon | Legacy mean MAE pp | Fixed C2 mean MAE pp | Relative gain | All remaining seasons better? |
|---|---:|---:|---:|---|
| +1 | 4.2935 | **1.4792** | 65.5% | yes, 9/9 |
| +2 | 5.1075 | **2.0487** | 59.9% | yes, 9/9 |

Thus the direction is not driven by the 2013-14 blow-up, although the headline mean percentage is.

## 11-season current-target sensitivity

Scoring both systems against the current target snapshot:

| Horizon | Frozen legacy M2 MAE pp | New baseline MAE pp | Fixed C2 MAE pp |
|---|---:|---:|---:|
| +1 | 8.9133 | 1.7053 | **1.5041** |
| +2 | 9.6026 | 2.4848 | **2.2421** |

Fixed C2 is better in 11/11 seasons at both horizons, but this sensitivity mixes a later 2025-26 target revision with predictions produced under different data vintages and should not replace the 10-season primary result.

## Interpretation

The matched benchmark supports two distinct conclusions:

1. The large improvement over frozen legacy M2 is primarily an **M2-v2 architecture/baseline redesign effect**: anchoring +1/+2 forecasts on the current observed type-specific level and recent growth removes the very large errors seen in the old all-off/legacy-M1 forecast.
2. Fixed C2 then contributes an additional **~11–13% matched-ledger MAE improvement** over the new state/growth baseline.

Therefore do not attribute the full ~77–82% legacy-to-C2 mean improvement to the C2 curve family itself.

## Artifacts

Script:

`scripts/compare_m2_v2_legacy_matched_a_v1.R`

Outputs:

`artifacts/m2-v2-legacy-matched-a-v1/`

- `matched_predictions.csv`
- `per_season_metrics.csv`
- `summary.csv`
- `paired_season_summary.csv`
- `target_vintage_audit.csv`
- `provenance.csv`

## Decision impact

This matched benchmark removes the earlier restriction that no direct legacy comparison was available. A direct **A-only, matched-target-ledger exchangeable comparison now exists**.

It does not replace the prior-seasons-only chronological evidence and does not resolve production blockers around the B timing gate or denominator-regime likelihood.
