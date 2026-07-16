# PAGe: Phase-Aligned Gated Epidemic Forecasting

PAGe is an R package for prospective one- and two-week-ahead forecasts of
seasonal respiratory-virus positivity. Its M0 -> M1 -> M2 pipeline detects
epidemic ignition, aligns the partial season to historical reference curves,
and predicts with a frozen binomial GAM plus adaptive bias correction.

## Installation

The package lives in the repository's `PAGe/` subdirectory.

```r
# From GitHub
remotes::install_github("lennon-li/PAGe", subdir = "PAGe")

# From a local repository checkout
devtools::install("PAGe")
```

## Data and training

PAGe does not distribute surveillance observations. Supply an authorized CSV
explicitly (or set `PAGE_FLU_HIST_FILE`) and normalize it before training.
The full refresh is computationally substantial; run it offline and save the
resulting kit.

```r
library(PAGe)

allD <- load_flu_hist("/authorized/path/flu_history.csv") |>
  prepare_surveillance_data()

# Uses the locked v16 production specification. The prospective holdout
# 2025-26 is excluded from every fit by default.
training <- train_pipeline(allD, mode = "refresh")
kit <- training$kit
saveRDS(kit, "page_kit.rds")
```

## Holdout replay and promotion

Replay 2025-26 with kits that did not train on it, then compare the candidate
against the incumbent. Promotion requires at least 2% NLL improvement, while
allowing no more than 5% degradation at any horizon and 10% in any phase.

```r
candidate <- replay_season_holdout(kit, allD, season = "2025-26")
incumbent <- replay_season_holdout(incumbent_kit, allD, season = "2025-26")
promotion <- check_promotion(candidate$metrics, incumbent$metrics)

# A passing report releases 2025-26 into the refresh used for 2026-27.
# Failed or malformed reports keep it excluded.
# Use the full M2 tuning object retained from an earlier retune. A refresh
# intentionally has training$tuning = NULL.
next_training <- train_pipeline(
  allD,
  mode = "refresh",
  previous_results = prior_m2_results, # e.g. retuned$tuning$m2
  promotion = promotion
)
```

## Frozen prospective forecasting

```r
current <- prepare_surveillance_data(current_csv, season = "2026-27")
forecast <- run_pipeline(kit, current, mode = "frozen")
plot_forecast(forecast, history = allD)
```

`mode = "frozen"` is the deployment default. Weekly refitting remains an
explicit compatibility option, not the validated production path.

## Full retuning

```r
retuned <- train_pipeline(
  allD,
  mode = "retune",
  previous_results = prior_m2_results,
  selection_method = "min_nll", # or "one_se" / "pareto"
  racing = FALSE
)
```

Retuning creates a bounded grid from compatible prior results, retains the
v16 incumbent and diverse finalists, adds local neighbors, and expands reached
boundaries. Optional `racing = TRUE` requires a fold evaluator; it only removes
clear losers, and all survivors still receive full nested-LOSO evaluation.

See the [pipeline overview](https://lennon-li.github.io/PAGe/articles/pipeline-overview.html)
and [walkthrough](https://lennon-li.github.io/PAGe/articles/pipeline-walkthrough.html).

## Production reference

The deployed v16 specification is `k_f = 4`, `k_e = 2`,
`alpha_state = 0.15`, `k_sp = 6`, `k_r = 0`, `k_de = 0`, `delta = 0`,
`Kr = 1`, `bias_alpha = 0.05`, and `bias_beta = 0`. Its recorded nested-LOSO
Bernoulli NLL is 0.4175.

PAGe is released under the MIT License.
