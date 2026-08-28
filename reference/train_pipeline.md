# Train all PAGe pipeline components

Runs either a locked production refresh or a full M0, M1, and M2 retune.
Refresh mode performs no LOSO tuning and uses a compatible prior best M2
specification when available, otherwise deployed v16. Retune mode uses
[`plan_m2_grid()`](https://lennon-li.github.io/PAGe/reference/plan_m2_grid.md)
unless an explicit M2 grid is supplied, then fits the winning M2
specification on all non-excluded seasons.

## Usage

``` r
train_pipeline(
  allD,
  mode = c("refresh", "retune"),
  previous_results = NULL,
  exclude = c("2011-12", "2015-16", "2020-21", "2021-22"),
  prospective_holdout = "2025-26",
  promotion = NULL,
  loso_seasons = "all",
  n_cores = parallel::detectCores() - 1L,
  checkpoint_dir = NULL,
  verbose = TRUE,
  m0_grid = .default_m0_grid(),
  m1_grid = default_m1_grid(),
  m2_grid = NULL,
  max_m2_finalists = 6L,
  max_m2_specs = 64L,
  selection_method = c("min_nll", "one_se", "pareto"),
  racing = FALSE,
  racing_evaluator = NULL,
  racing_stages = c(3L, 6L),
  racing_min_survivors = 3L,
  manual_labels = NULL,
  flag_args = NULL,
  m1_params = NULL,
  m1_min_gain = 0.05,
  m1_hard_caps = list(k_ref = c(lower = 10L, upper = 50L)),
  m2_min_nll_gain = default_m2_nll_gain_caps(),
  m0_params = NULL,
  m2_spec_id = NULL
)
```

## Arguments

- allD:

  Multi-season surveillance data.

- mode:

  `"refresh"` for locked fitting or `"retune"` for LOSO tuning followed
  by production fitting.

- previous_results:

  Optional prior M2 tuning result.

- exclude:

  Seasons excluded from component and final production fitting.

- prospective_holdout:

  Season kept out of every tuning and fitting stage until an explicit
  passing promotion report releases it. Defaults to 2025-26; use NULL
  only when no prospective holdout exists.

- promotion:

  Optional artifact-bound evidence returned by
  [`verify_promotion_evidence()`](https://lennon-li.github.io/PAGe/reference/verify_promotion_evidence.md).
  A bare
  [`check_promotion()`](https://lennon-li.github.io/PAGe/reference/check_promotion.md)
  report is not governed production evidence and cannot release the
  holdout. The R class is forgeable; verification of the retained
  bundle, manifest, data, candidate, and incumbent artifacts is the
  safety boundary.

- loso_seasons:

  LOSO folds passed to all tuning stages.

- n_cores:

  Parallel worker count passed to tuning stages.

- checkpoint_dir:

  Optional parent checkpoint directory.

- verbose:

  Logical progress flag.

- m0_grid, m1_grid:

  Optional explicit M0 and M1 tuning grids.

- m2_grid:

  Optional explicit M2 grid; `NULL` uses
  `plan_m2_grid(previous_results)`.

- max_m2_finalists, max_m2_specs:

  Adaptive M2 plan caps.

- selection_method:

  Final full-LOSO selection rule passed to
  [`select_m2_candidate()`](https://lennon-li.github.io/PAGe/reference/select_m2_candidate.md).
  Defaults to minimum Bernoulli NLL.

- racing:

  Logical; conservatively pre-race the planned M2 grid. This is off by
  default and requires `racing_evaluator`.

- racing_evaluator:

  Callback returning partial fold-level scores. Partial results only
  eliminate clear losers; surviving specs still run full LOSO.

- racing_stages, racing_min_survivors:

  Racing schedule and survivor floor.

- manual_labels, flag_args, m1_params:

  Optional component settings. For a released holdout, these are derived
  exclusively from verified promotion evidence and explicit overrides
  are rejected.

- m1_min_gain:

  Minimum M1 Weibull-MAE improvement, in weeks, required to justify a
  more flexible \`k_ref\` candidate (default 0.05).

- m1_hard_caps:

  Named M1 hard caps accepted by the boundary gate. The default bounds
  \`k_ref\` to 10–50 on the 52-week reference domain.

- m2_min_nll_gain:

  Named parameter-specific NLL gain thresholds passed to the M2 boundary
  gate. Defaults to
  [`default_m2_nll_gain_caps()`](https://lennon-li.github.io/PAGe/reference/default_m2_nll_gain_caps.md)
  and covers every M2 axis. A scalar applies to every M2 axis. An edge
  is accepted only when its matched outward gain is at or below the
  threshold; missing matched evidence still requires expansion.

- m0_params:

  Optional M0 parameters for refresh mode. Defaults to the deployed
  configuration when no holdout has been released. For a released
  holdout it is derived exclusively from verified promotion evidence.

- m2_spec_id:

  Optional identity for an unreleased fixed refresh M2 spec; it is
  derived from promotion evidence after holdout acceptance.

## Value

A transparent list with `mode`, `components`, `tuning` (NULL for
refresh), `grid`, `grid_provenance`, full-result `selection`, optional
`racing` diagnostics, transparent `holdout` release state, and
deployment `kit`.
