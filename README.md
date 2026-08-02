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

# Compatibility orchestrator: uses the coded locked v16 specification.
# The prospective holdout 2025-26 is excluded from every fit by default.
training <- train_pipeline(allD, mode = "refresh")
kit <- training$kit
saveRDS(kit, "page_kit.rds")
```

## Guarded stage lifecycle

Use the guarded API when training must stop at every stage boundary. First
declare the season sets; then tune, validate, fit, and freeze M0 before M1 can
start, and repeat the same lifecycle for M1 and M2.

```r
selection <- validate_season_selection(
  allD,
  training_seasons = development_seasons,
  exclude_seasons = c("2011-12", "2015-16", "2020-21", "2021-22"),
  holdout_seasons = "2025-26",
  application_seasons = "2026-27"
)

m0_tuning <- tune_m0(allD, selection = selection)
validate_m0_tuning(m0_tuning)
m0 <- fit_m0(allD, selection, config = m0_tuning$best_params) |>
  freeze_m0(tuning = m0_tuning)

m1_tuning <- tune_m1(allD, m0 = m0, selection = selection)
validate_m1_tuning(m1_tuning)
approved_m1_config <- as.list(m1_tuning$best[1, , drop = FALSE])
m1 <- fit_m1(allD, selection, m0, config = approved_m1_config) |>
  freeze_m1(tuning = m1_tuning)

m2_tuning <- tune_m2(allD, selection, m0, m1, grid = m2_grid)
validate_m2_tuning(m2_tuning)
m2 <- fit_m2(allD, selection, m0, m1, config = m2_tuning$best_spec) |>
  freeze_m2(tuning = m2_tuning)

kit <- assemble_kit(m0, m1, m2)
validate_page_kit(kit)
```

A tuning object is evidence for selection, not a fitted stage. `freeze_*()`
checks that the fit, tuning result, season selection, and upstream identities
agree. If any governed component is passed to `assemble_kit()`, all three
components must be governed and frozen.

`train_pipeline()` remains the high-level compatibility orchestrator and now
composes the guarded lifecycle for refresh and retune while preserving its
compatibility result shape.

## Holdout replay and promotion

Production release follows a four-phase, artifact-bound workflow:

1. replay frozen candidate and incumbent kits that both exclude `2025-26`;
2. preserve the locked gate decision and source hashes as immutable evidence;
3. after a pass, refresh the accepted fixed specification with `2025-26`
   included; and
4. register the refreshed kit immutably and load it only with its verified
   deployment manifest.

Retuning belongs before the untouched holdout. Changing a grid, feature,
threshold, or specification after viewing holdout results starts a new
development cycle; it is not a continuation of the accepted refresh.

See the [governed deployment workflow](docs/deployment-workflow.qmd) for the
operator commands, private versus disclosure-safe output locations,
`--preflight-only` checks, and no-overwrite rules. This local checkout contains
an ignored acceptance evidence run (`boundary-expansion-20260801T150000Z`) whose
candidate failed the locked NLL gate. No refresh or promotion was performed;
the incumbent remains accepted.

The bounded public smoke command exercises the same artifact-governance chain
using synthetic fixtures and temporary outputs:

```sh
Rscript scripts/public/synthetic_release_workflow.R --smoke
```

It is disclosure-safe and suitable for CI. It does not fit or validate the
real PAGe model, and it is not evidence that the private `2025-26` workflow ran.

## Frozen prospective forecasting

```r
kit <- load_promoted_kit(
  kit_path = "/secure/PAGe/deployment-registry/<deployment-id>/promoted_kit.rds",
  deployment_manifest_path =
    "results/deployment-audit/<deployment-id>/deployment_manifest.json"
)
current <- prepare_surveillance_data(current_csv, season = "2026-27")
forecast <- run_pipeline(kit, current, mode = "frozen")
plot_forecast(forecast, history = allD)
```

`mode = "frozen"` is the deployment default. Weekly refitting remains an
explicit compatibility option, not the validated production path.

## Pre-acceptance retuning

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
When `previous_results` is supplied, the planner consolidates finite NLL by
specification, falls back to finite fold scores where needed, rejects ambiguous
identities by requiring unique IDs that exactly match the parameter-derived
canonical IDs, and uses the spacing adjacent to the previous winner for
boundary expansion. Bernoulli NLL is preferred to `mean_nll`; ranking ties use
the canonical ID. The v16 incumbent and best prior specification survive even
a tight grid cap.

`selection_method` is an explicit user choice:

- `"min_nll"` selects the lowest full-LOSO Bernoulli NLL, breaking ties by
  complexity and specification ID.
- `"one_se"` selects the simplest candidate within one standard error of the
  best NLL; it requires finite fold-level scores.
- `"pareto"` retains candidates not dominated jointly on NLL, worst-horizon
  MAE, and worst-phase MAE, then selects by NLL, complexity, and specification
  ID.

See the [pipeline overview](docs/pipeline_overview.qmd), the
[governed deployment workflow](docs/deployment-workflow.qmd), and the
[walkthrough](docs/pipeline_walkthrough.qmd). The
[stage API map](docs/stage-api-map.md) records the current implementation and
remaining orchestration work. The
[tuning playbook](docs/tuning-playbook.md) explains boundary diagnostics,
controlled grid expansion, stage-specific parameter tips, and stopping rules.

## Coded production reference

The locked v16 incumbent in code is `k_f = 4`, `k_e = 2`,
`alpha_state = 0.15`, `k_sp = 6`, `k_r = 0`, `k_de = 0`, `delta = 0`,
`Kr = 1`, `bias_alpha = 0.05`, and `bias_beta = 0`. Historical notes record a
nested-LOSO Bernoulli NLL of 0.4175, but the corresponding private artifact is
absent, so this repository does not verify that value or establish a promoted
deployment.

PAGe is released under the MIT License.
