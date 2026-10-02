# PAGe v1, v2, and v3: What Can Be Compared Fairly?

PAGe evolved in stages, and the evaluation ledgers changed with the
model. A single pooled “v1 vs v2 vs v3” score would mix different
targets, origins, pathogens, and model-routing decisions. This vignette
therefore reports only comparisons supported by matched or explicitly
chronological evidence.

This vignette is a historical compatibility diagnostic.
[`page_version_metrics()`](https://lennon-li.github.io/PAGe/reference/page_version_metrics.md)
is intentionally internal and is not part of the supported public API.

``` r

library(PAGe)
metrics <- PAGe:::page_version_metrics()
metrics[, c(
  "comparison_scope", "component", "horizon", "metric", "unit",
  "n_rows", "n_seasons", "v1_legacy", "v2", "v3",
  "relative_gain_v1_to_v2", "relative_gain_v2_to_v3"
)]
#>                    comparison_scope        component horizon metric
#> 1             matched_common_ledger M1_A_peak_timing      NA    MAE
#> 2 matched_historical_target_vintage             M2_A       1    MAE
#> 3 matched_historical_target_vintage             M2_A       2    MAE
#> 4                   chronological_B             M2_B       2    MAE
#> 5     chronological_B_active_timing             M2_B       2    MAE
#>                unit n_rows n_seasons v1_legacy        v2        v3
#> 1             weeks     81        10  1.375185 1.0925412        NA
#> 2 percentage_points    294        10  8.408648 1.7757197        NA
#> 3 percentage_points    284        10  9.205609 2.4124362        NA
#> 4 percentage_points     NA         7        NA 0.5145516 0.4360104
#> 5 percentage_points     89         5        NA 0.7356880 0.5524389
#>   relative_gain_v1_to_v2 relative_gain_v2_to_v3
#> 1              0.2055316                     NA
#> 2              0.7888222                     NA
#> 3              0.7379385                     NA
#> 4                     NA              0.1526400
#> 5                     NA              0.2490853
```

## M1-A peak timing: v1/legacy versus v2

The strict common ledger contains 81 matched origin/truth rows across 10
seasons. Mean absolute peak-timing error is approximately:

- v1/legacy: 1.375 weeks;
- v2: 1.093 weeks;
- relative reduction: 20.6%.

The same v2 timing family feeds the canonical v3 A stack, but this exact
historical ledger is not an independent v3 re-score. For that reason the
v3 metric cell is intentionally `NA` rather than copied from v2.

The underlying v2 ledger also has mean 90% interval coverage of
approximately 0.802 and mean interval width of about 4.01 weeks. Those
uncertainty metrics describe that M1-v2 evaluation ledger, not a
separate v3 experiment.

## M2-A: v1/legacy versus v2 on matched targets

For 10 historical seasons whose target counts are identical across the
two systems, the matched-target benchmark gives:

``` r

metrics[metrics$component == "M2_A",
        c("horizon", "n_rows", "n_seasons", "v1_legacy", "v2",
          "relative_gain_v1_to_v2", "caveat")]
#>   horizon n_rows n_seasons v1_legacy       v2 relative_gain_v1_to_v2
#> 2       1    294        10  8.408648 1.775720              0.7888222
#> 3       2    284        10  9.205609 2.412436              0.7379385
#>                                                                                                                                                                                                                                                          caveat
#> 2 Identical target counts/rows across 10 historical seasons; historical training snapshots are not perfectly vintage-matched. The canonical v3 A route preserves governed A1 state forecasting but was not independently re-scored on this exact legacy ledger.
#> 3 Identical target counts/rows across 10 historical seasons; historical training snapshots are not perfectly vintage-matched. The canonical v3 A route preserves governed A1 state forecasting but was not independently re-scored on this exact legacy ledger.
```

At +1 week, MAE falls from about 8.41 percentage points to 1.78
percentage points. At +2 weeks, MAE falls from about 9.21 to 2.41
percentage points.

This benchmark matches target rows and target counts, but historical
training snapshots are not perfectly vintage-matched. It should
therefore be interpreted as strong stage-specific evidence rather than a
fully prospective head-to-head trial.

Canonical v3 preserves the governed A1 state route. It was not
independently re-scored on this exact v1/legacy comparison ledger, so v3
remains `NA` in this table.

## M2-B +2: the direct v2 to v3 improvement

The clearest direct v2-to-v3 performance comparison is Influenza B +2
forecasting. v2’s exact B1 state forecast is the baseline. v3 uses
posterior-C2 when causal B timing is available and otherwise falls back
to the exact B1 route.

Across the seven-season chronological B benchmark:

``` r

metrics[metrics$component == "M2_B",
        c("comparison_scope", "horizon", "n_rows", "n_seasons", "v2", "v3",
          "relative_gain_v2_to_v3", "caveat")]
#>                comparison_scope horizon n_rows n_seasons        v2        v3
#> 4               chronological_B       2     NA         7 0.5145516 0.4360104
#> 5 chronological_B_active_timing       2     89         5 0.7356880 0.5524389
#>   relative_gain_v2_to_v3
#> 4              0.1526400
#> 5              0.2490853
#>                                                                                                                              caveat
#> 4 Chronological B benchmark; v3 posterior-C2 activates only when causal B timing is available and otherwise falls back to exact B1.
#> 5                                                                             Timing-active rows only; 5/5 active seasons improved.
```

Overall +2 MAE improves from about 0.515 percentage points to 0.436
percentage points, a 15.3% reduction.

On the timing-active subset, 89 rows across five seasons, MAE improves
from about 0.736 to 0.552 percentage points, a 24.9% reduction. All five
timing-active seasons improved on +2 MAE in that benchmark.

## What is intentionally not claimed

PAGe does not currently publish a single universal v1/v2/v3 score. In
particular:

- there is no verified common-ledger M0 performance comparison suitable
  for a v1/v2/v3 accuracy claim;
- the v1/legacy M2 benchmark is A-only;
- v3’s main new historical accuracy evidence is on B +2 routing;
- inherited/frozen A components are not assigned v3 metrics merely
  because their lineage descends from v2;
- prospective 2026-27 v2/v3 paired accuracy should be accumulated only
  after each forecast target is observed.

The full table, evidence paths, and caveats are available
programmatically:

``` r

PAGe:::page_version_metrics()
#>                    comparison_scope        component horizon metric
#> 1             matched_common_ledger M1_A_peak_timing      NA    MAE
#> 2 matched_historical_target_vintage             M2_A       1    MAE
#> 3 matched_historical_target_vintage             M2_A       2    MAE
#> 4                   chronological_B             M2_B       2    MAE
#> 5     chronological_B_active_timing             M2_B       2    MAE
#>                unit n_rows n_seasons v1_legacy        v2        v3
#> 1             weeks     81        10  1.375185 1.0925412        NA
#> 2 percentage_points    294        10  8.408648 1.7757197        NA
#> 3 percentage_points    284        10  9.205609 2.4124362        NA
#> 4 percentage_points     NA         7        NA 0.5145516 0.4360104
#> 5 percentage_points     89         5        NA 0.7356880 0.5524389
#>                            v3_relationship relative_gain_v1_to_v2
#> 1          frozen_M1A_lineage_not_rescored              0.2055316
#> 2 governed_A1_route_preserved_not_rescored              0.7888222
#> 3 governed_A1_route_preserved_not_rescored              0.7379385
#> 4                 v2_B1_vs_v3_posterior_C2                     NA
#> 5     v2_B1_vs_v3_posterior_C2_active_rows                     NA
#>   relative_gain_v2_to_v3
#> 1                     NA
#> 2                     NA
#> 3                     NA
#> 4              0.1526400
#> 5              0.2490853
#>                                                                                                    evidence_path
#> 1 artifacts/m1-v2-lowrank-posterior-v10-release-consistent/common_ledger_vs_legacy_v16_strict_future_release.csv
#> 2                                                                artifacts/m2-v2-legacy-matched-a-v1/summary.csv
#> 3                                                                artifacts/m2-v2-legacy-matched-a-v1/summary.csv
#> 4                                            artifacts/v3-m2-b-posterior-c2-chronological-v3/summary_metrics.csv
#> 5                                      artifacts/v3-m2-b-posterior-c2-chronological-v3/active_timing_summary.csv
#>                                                                                                                                                                                                                                                          caveat
#> 1                                                                                                                                          Matched origin/truth rows; v3 preserves the M1-A v2 lineage but this exact ledger is not an independent v3 re-score.
#> 2 Identical target counts/rows across 10 historical seasons; historical training snapshots are not perfectly vintage-matched. The canonical v3 A route preserves governed A1 state forecasting but was not independently re-scored on this exact legacy ledger.
#> 3 Identical target counts/rows across 10 historical seasons; historical training snapshots are not perfectly vintage-matched. The canonical v3 A route preserves governed A1 state forecasting but was not independently re-scored on this exact legacy ledger.
#> 4                                                                                                                             Chronological B benchmark; v3 posterior-C2 activates only when causal B timing is available and otherwise falls back to exact B1.
#> 5                                                                                                                                                                                                         Timing-active rows only; 5/5 active seasons improved.
```
