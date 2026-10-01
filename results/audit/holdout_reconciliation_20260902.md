# PAGe Governed 11-Season Exchangeable Holdout Reconciliation

- **Archive Root**: `/home/yeli/PAGe-bcc-artifacts/seasonal-archive-20260818`
- **Generated UTC**: `2026-09-02 00:22:33 UTC`
- **Target Seasons**: 11 valid exchangeable holdouts
- **Reconciliation Summary**: 9 complete, 2 pending, 0 missing, 0 invalid

## Principal 11-Season Exchangeable Table

All rows represent exchangeable nested LOSO evaluations using strictly 10 training seasons and fixed exclusions.
Comparisons are descriptive; lower Bernoulli NLL and MAE indicate superior out-of-sample accuracy.

| Season | Run ID | Status | Exchangeable | NLL | MAE | Lead 1 MAE | Lead 2 MAE | Predictions | Commit |
|:---|:---|:---|:---:|---:|---:|---:|---:|---:|:---|
| 2012-13 | 2012-13-current-api-20260901 | pending | TRUE | - | - | - | - | - | 95c1c9f3 |
| 2013-14 | 2013-14-current-api-20260901 | pending | TRUE | - | - | - | - | - | 95c1c9f3 |
| 2014-15 | 2014-15-latest-api-20260818 | complete | TRUE | 0.419667 | 0.034020 | 0.028891 | 0.039254 | 65 | d60d0239 |
| 2016-17 | bcc-2016-17-v5 | complete | TRUE | 0.397588 | 0.037387 | 0.033496 | 0.041368 | 65 | - |
| 2017-18 | bcc-2017-18-v2 | complete | TRUE | 0.338210 | 0.020193 | 0.017234 | 0.023217 | 63 | 48a0935b |
| 2018-19 | 2018-final2-expanded-api | complete | TRUE | 0.358971 | 0.026153 | 0.022220 | 0.030186 | 65 | - |
| 2019-20 | 2019-20-latest-api-20260818-r2 | complete | TRUE | 0.213926 | 0.021932 | 0.019507 | 0.024414 | 59 | d60d0239 |
| 2022-23 | 2022-final-expanded-v3 | complete | TRUE | 0.172942 | 0.017859 | 0.015127 | 0.020649 | 73 | - |
| 2023-24 | exchangeable | complete | TRUE | 0.227502 | 0.021291 | 0.017243 | 0.025481 | 63 | - |
| 2024-25 | exchangeable | complete | TRUE | 0.336849 | 0.028450 | 0.025705 | 0.031302 | 57 | - |
| 2025-26 | 2025-capped-api-20260815-r2 | complete | TRUE | 0.557499 | 0.046727 | 0.035488 | 0.058802 | 17 | - |

## Descriptive Aggregate Metrics (Complete Exchangeable Holdouts)

- **Evaluated Complete Seasons**: 9 / 11
- **Total Predictions**: 527
- **Bernoulli NLL**: Mean = 0.335906 | Median = 0.338210 | Range = [0.172942, 0.557499]
- **MAE**: Mean = 0.028224 | Median = 0.026153 | Range = [0.017859, 0.046727]

*Note: Cross-season metrics are descriptive. No inferential hypothesis testing or p-values are calculated.*

## Holdout Variants & Diagnostic Exclusions

The following runs are retained for provenance and audit purposes but excluded from the principal 11-season exchangeable table.

| Season | Variant / Run ID | Classification | Status | NLL | MAE | Predictions | Notes |
|:---|:---|:---|:---|---:|---:|---:|:---|
| 2022-23 | exchangeable | same_season_variant | failed | - | - | - | Secondary candidate directory; raw_status=failed |
| 2015-16 | holdouts-and-docs | diagnostic_exclusion | diagnostic_complete | 0.359028 | 0.063384 | 75 | Permanent exclusion diagnostic drop-test; excluded from principal 11-season table |

