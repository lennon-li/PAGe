# PAGe: Phase-Aligned Gated Epidemic Forecasting

PAGe forecasts seasonal respiratory-virus positivity one and two weeks ahead.
The three-stage M0 -> M1 -> M2 pipeline detects epidemic ignition, aligns a
partial season to historical reference curves, and predicts with a frozen
binomial GAM plus adaptive bias correction.

## Installation

```r
remotes::install_github("lennon-li/PAGe", subdir = "PAGe")

# From the repository root instead:
devtools::install("PAGe")
```

## Safe data workflow

Surveillance observations are not bundled. Supply an authorized historical
CSV explicitly or set `PAGE_FLU_HIST_FILE`, then validate the canonical data
contract.

```r
library(PAGe)

allD <- load_flu_hist("/authorized/path/flu_history.csv") |>
  prepare_surveillance_data()

# High-level compatibility refresh; 2025-26 remains a holdout by default.
training <- train_pipeline(allD, mode = "refresh")
kit <- training$kit
```

## Guarded stages

For explicit stage-by-stage training, declare mutually disjoint season sets and
allow each stage to proceed only after its tuning gate and freeze gate pass:

```r
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
approved_m1_config <- as.list(m1_tuning$best[1, , drop = FALSE])
m1 <- fit_m1(allD, selection, m0, approved_m1_config) |>
  freeze_m1(m1_tuning)

m2_tuning <- tune_m2(allD, selection, m0, m1, m2_grid)
validate_m2_tuning(m2_tuning)
m2 <- fit_m2(allD, selection, m0, m1, m2_tuning$best_spec) |>
  freeze_m2(m2_tuning)

kit <- assemble_kit(m0, m1, m2)
validate_page_kit(kit)
```

Downstream stages reject draft, selection-mismatched, or identity-mismatched
upstream artifacts. A governed kit records its season selection and the three
stage identities. `train_pipeline()` remains available as the high-level
compatibility orchestrator.

## Holdout gate

```r
candidate <- replay_season_holdout(kit, allD, season = "2025-26")
incumbent <- replay_season_holdout(incumbent_kit, allD, season = "2025-26")
promotion <- check_promotion(candidate$metrics, incumbent$metrics)
```

The default gates require 2% NLL improvement, no horizon MAE degradation over
5%, and no phase MAE degradation over 10%. This in-memory report is diagnostic
only: it has no artifact provenance and cannot release the holdout. A governed
release uses `scripts/acceptance/replay_2025_26.R`, preserves its decision
bundle and manifest, performs the fixed-spec refresh with
`season2526/run_retrain_venkata.R`, and registers the refreshed kit using
`scripts/promotion/promote_post_refit.R`. A failed or malformed report keeps
the holdout excluded.

## Prospective run

```r
current <- prepare_surveillance_data(current_csv, season = "2026-27")
forecast <- run_pipeline(kit, current, mode = "frozen")
plot_forecast(forecast, history = allD)
```

Frozen deployment is the default. Weekly refitting is available only by
explicit request for compatibility.

## Retuning options

```r
retuned <- train_pipeline(
  allD,
  mode = "retune",
  previous_results = prior_m2_results,
  selection_method = "min_nll", # or "one_se" / "pareto"
  racing = FALSE
)
```

The adaptive grid uses compatible prior results, retains the v16 incumbent and
diverse finalists, adds local neighbors, and expands reached boundaries.
Optional conservative racing requires a user-supplied fold evaluator; surviving
candidates always receive full nested-LOSO evaluation.

A selected tuning value should normally be bracketed by tested values. Expand
a winning edge by one adjacent valid step, retain the incumbent and local
neighbors, and rerun identical complete folds. Zero-valued optional M2 terms
may be legitimate feature-off boundaries. Record accepted constraints and
finish every expansion before viewing the prospective holdout.

The coded v16 reference specification is `k_f = 4`, `k_e = 2`,
`alpha_state = 0.15`, `k_sp = 6`, `k_r = 0`, `k_de = 0`, `delta = 0`,
`Kr = 1`, `bias_alpha = 0.05`, and `bias_beta = 0` (recorded nested-LOSO
Bernoulli NLL 0.4175). The corresponding private artifact is absent, so the
repository does not independently verify that value or establish a promoted
deployment.

See `vignette("intro", package = "PAGe")`, the
[pipeline overview](https://lennon-li.github.io/PAGe/articles/pipeline-overview.html),
and the [walkthrough](https://lennon-li.github.io/PAGe/articles/pipeline-walkthrough.html).
