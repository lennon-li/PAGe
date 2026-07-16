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

# Offline locked-spec refresh; 2025-26 remains a holdout by default.
training <- train_pipeline(allD, mode = "refresh")
kit <- training$kit
```

## Holdout gate

```r
candidate <- replay_season_holdout(kit, allD, season = "2025-26")
incumbent <- replay_season_holdout(incumbent_kit, allD, season = "2025-26")
promotion <- check_promotion(candidate$metrics, incumbent$metrics)

# A passing report permits 2025-26 to enter the 2026-27 training refresh.
next_training <- train_pipeline(allD, mode = "refresh", promotion = promotion)
```

The default gates require 2% NLL improvement, no horizon MAE degradation over
5%, and no phase MAE degradation over 10%. A failed or malformed report keeps
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

The deployed v16 reference specification is `k_f = 4`, `k_e = 2`,
`alpha_state = 0.15`, `k_sp = 6`, `k_r = 0`, `k_de = 0`, `delta = 0`,
`Kr = 1`, `bias_alpha = 0.05`, and `bias_beta = 0` (recorded nested-LOSO
Bernoulli NLL 0.4175).

See `vignette("intro", package = "PAGe")`, the
[pipeline overview](https://lennon-li.github.io/PAGe/articles/pipeline-overview.html),
and the [walkthrough](https://lennon-li.github.io/PAGe/articles/pipeline-walkthrough.html).
