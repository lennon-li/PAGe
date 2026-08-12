# Getting started with PAGe

**PAGe** (Phase-Aligned Gated Epidemic Forecasting) produces 1–2 week
ahead forecasts of seasonal respiratory-virus percentage positivity from
surveillance data. The pipeline is three stages run in sequence each
week:

- **M0** – ignition detection (when the season has started)
- **M1** – alignment to a learned reference curve via shift `tau` and
  optional dilation `delta`
- **M2** – binomial GAM forecast with adaptive Holt EMA bias correction

## Data and training

``` r

library(PAGe)

# PAGe does not bundle surveillance observations.
allD <- load_flu_hist("/authorized/path/flu_history.csv") |>
  prepare_surveillance_data()

# High-level compatibility refresh. The 2025-26 holdout is excluded by default.
training <- train_pipeline(allD, mode = "refresh")
kit <- training$kit
```

Use `mode = "retune"` for full M0/M1/M2 tuning. Its adaptive M2 grid is
informed by compatible prior results and supports `"min_nll"`,
`"one_se"`, and `"pareto"` selection. Optional conservative racing only
removes clear losers; finalists still receive full nested-LOSO
evaluation.

For explicit training gates, declare disjoint season sets and complete
each stage before starting the next:

``` r

selection <- validate_season_selection(
  allD,
  training_seasons = development_seasons,
  exclude_seasons = excluded_seasons,
  holdout_seasons = "2025-26",
  application_seasons = "2026-27"
)

m0_tuning <- tune_m0(allD, selection = selection)
validate_m0_tuning(m0_tuning)
m0 <- fit_m0(allD, selection, m0_tuning$best_params) |>
  freeze_m0(m0_tuning)

m1_tuning <- tune_m1(allD, m0 = m0, selection = selection)
validate_m1_tuning(m1_tuning)
m1_config <- as.list(m1_tuning$best[1, , drop = FALSE])
m1 <- fit_m1(allD, selection, m0, m1_config) |>
  freeze_m1(m1_tuning)

m2_tuning <- tune_m2(allD, selection, m0, m1, m2_grid)
validate_m2_tuning(m2_tuning)
m2 <- fit_m2(allD, selection, m0, m1, m2_tuning$best_spec) |>
  freeze_m2(m2_tuning)

kit <- assemble_kit(m0, m1, m2)
validate_page_kit(kit)
```

A downstream stage rejects a draft or provenance-mismatched upstream
artifact.
[`train_pipeline()`](https://lennon-li.github.io/PAGe/reference/train_pipeline.md)
remains the high-level compatibility orchestrator and has not yet been
refactored to compose these stage contracts.

## Holdout replay and promotion

``` r

candidate <- replay_season_holdout(kit, allD, season = "2025-26")
incumbent <- replay_season_holdout(incumbent_kit, allD, season = "2025-26")
promotion <- check_promotion(candidate$metrics, incumbent$metrics)
```

The default gates require 2% NLL improvement, at most 5% horizon-MAE
degradation, and at most 10% phase-MAE degradation. This in-memory
comparison is diagnostic only. It has no artifact provenance and must
not be passed to
[`train_pipeline()`](https://lennon-li.github.io/PAGe/reference/train_pipeline.md)
to release the holdout. A governed release uses
`scripts/acceptance/replay_2025_26.R`, preserves its decision bundle and
manifest, performs the fixed-spec refresh with
`season2526/run_retrain_venkata.R`, and registers the result immutably
with `scripts/promotion/promote_post_refit.R`.

## Weekly forecasting

Given `kit` and the current season’s observed weeks so far, produce a
forecast with:

``` r

current <- prepare_surveillance_data(current_csv, season = "2026-27")
res <- run_pipeline(kit, current, mode = "frozen")
plot_forecast(res, history = allD)
```

Frozen-GAM prediction is the default validated deployment path. Weekly
refitting is retained only as an explicit compatibility option.

## Where to read more

- [Pipeline
  overview](https://lennon-li.github.io/PAGe/articles/articles/pipeline-overview.md)
  – architecture and notation.
- [Pipeline
  walkthrough](https://lennon-li.github.io/PAGe/articles/articles/pipeline-walkthrough.md)
  – an end-to-end training and deployment walkthrough.
- `?stage_contracts`,
  [`?tune_m0`](https://lennon-li.github.io/PAGe/reference/tune_m0.md),
  [`?tune_m1`](https://lennon-li.github.io/PAGe/reference/tune_m1.md),
  [`?assemble_kit`](https://lennon-li.github.io/PAGe/reference/assemble_kit.md),
  [`?run_pipeline`](https://lennon-li.github.io/PAGe/reference/run_prospective_pipeline.md)
  – reference pages for the guarded and high-level APIs.
