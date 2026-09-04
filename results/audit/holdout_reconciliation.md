# PAGe Governed 11-Season Exchangeable Holdout Reconciliation

- **Archive Root**: `/mnt/nfsv4/Users/yeli/PAGe-artifacts/seasonal-archive-20260818`
- **Generated UTC**: `2026-09-03 15:05:35 UTC`
- **Target Seasons**: 11 valid exchangeable holdouts
- **Reconciliation Summary**: 11 complete, 0 pending, 0 missing, 0 invalid

## Principal 11-Season Exchangeable Table

All rows represent exchangeable nested LOSO evaluations using strictly 10 training seasons and fixed exclusions.
Comparisons are descriptive; lower Bernoulli NLL and MAE indicate superior out-of-sample accuracy.

| Season | Run ID | Status | Exchangeable | NLL | MAE | Lead 1 MAE | Lead 2 MAE | Predictions | Commit |
|:---|:---|:---|:---:|---:|---:|---:|---:|---:|:---|
| 2012-13 | 2012-13-current-api-20260901 | complete | TRUE | 0.384700 | 0.045078 | 0.040682 | 0.049526 | 67 | 95c1c9f3 |
| 2013-14 | 2013-14-current-api-20260901 | complete | TRUE | 0.301311 | 0.038506 | 0.035040 | 0.042041 | 63 | 95c1c9f3 |
| 2014-15 | 2014-15-current-api-20260902-r4 | complete | TRUE | 0.419605 | 0.033898 | 0.028806 | 0.039097 | 65 | 95c1c9f3 |
| 2016-17 | 2016-17-current-api-20260902-r4 | complete | TRUE | 0.397904 | 0.038078 | 0.031634 | 0.044673 | 65 | 95c1c9f3 |
| 2017-18 | 2017-18-current-api-20260902-r3 | complete | TRUE | 0.337756 | 0.019278 | 0.016462 | 0.022155 | 63 | 95c1c9f3 |
| 2018-19 | 2018-19-current-api-20260902-r3 | complete | TRUE | 0.358829 | 0.026307 | 0.023469 | 0.029218 | 65 | 95c1c9f3 |
| 2019-20 | 2019-20-current-api-20260902-r3 | complete | TRUE | 0.213888 | 0.021923 | 0.019498 | 0.024406 | 59 | 95c1c9f3 |
| 2022-23 | 2022-23-current-api-20260902-r3 | complete | TRUE | 0.173092 | 0.019562 | 0.016106 | 0.023092 | 73 | 95c1c9f3 |
| 2023-24 | 2023-24-current-api-20260902-r3 | complete | TRUE | 0.230395 | 0.022673 | 0.017822 | 0.027711 | 61 | 95c1c9f3 |
| 2024-25 | 2024-25-current-api-20260902-r3 | complete | TRUE | 0.336284 | 0.026717 | 0.024195 | 0.029337 | 57 | 95c1c9f3 |
| 2025-26 | 2025-26-current-api-20260902-r3 | complete | TRUE | 0.563552 | 0.065553 | 0.047072 | 0.085408 | 17 | 95c1c9f3 |

## Descriptive Aggregate Metrics (Complete Exchangeable Holdouts)

- **Evaluated Complete Seasons**: 11 / 11
- **Total Predictions**: 655
- **Bernoulli NLL**: Mean = 0.337938 | Median = 0.337756 | Range = [0.173092, 0.563552]
- **MAE**: Mean = 0.032507 | Median = 0.026717 | Range = [0.019278, 0.065553]

*Note: Cross-season metrics are descriptive. No inferential hypothesis testing or p-values are calculated.*

## Holdout Variants & Diagnostic Exclusions

The following runs are retained for provenance and audit purposes but excluded from the principal 11-season exchangeable table.

| Season | Variant / Run ID | Classification | Status | NLL | MAE | Predictions | Notes |
|:---|:---|:---|:---|---:|---:|---:|:---|
| 2022-23 | exchangeable | same_season_variant | failed | - | - | - | Secondary candidate directory; raw_status=failed |
| 2023-24 | exchangeable | same_season_variant | complete | 0.227502 | 0.021291 | 63 | Secondary candidate directory; raw_status=exchangeable_replay_success |
| 2024-25 | exchangeable | same_season_variant | complete | 0.336849 | 0.028450 | 57 | Secondary candidate directory; raw_status=exchangeable_replay_success |
| 2015-16 | holdouts-and-docs | diagnostic_exclusion | diagnostic_complete | 0.359028 | 0.063384 | 75 | Permanent exclusion diagnostic drop-test; excluded from principal 11-season table |
