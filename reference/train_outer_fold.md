# Train a nested-tuned PAGe kit

Runs the first two levels of the manuscript evaluation. When \`holdout\`
is supplied, that season is kept outside all fitting and selection.
Within the remaining seasons, the stage tuners perform
leave-one-season-out walk-forward evaluation, boundary grids are
expanded until settled, and the phase-weighted M2-versus-M1 adoption
rule is applied before a frozen kit is assembled. \`holdout = NULL\` is
reserved for the final post-evaluation fit on all eligible seasons.

## Usage

``` r
train_outer_fold(
  data,
  holdout = NULL,
  exclude = .default_nested_exclusions(),
  manual_labels = NULL,
  timing_labels = NULL,
  m0_grid = .default_m0_grid(),
  m0_flag_args = .default_flag_args(),
  m1_grid = default_m1_grid(),
  m1_params = .default_m1_params(),
  m2_grid = m2_subset_grid(),
  m2_family = m2_subset_family(),
  early_weight = 2,
  early_max_t_since = 12,
  pre_ignition_weight = 0,
  late_weight = 1,
  scoring = c("page_v2", "legacy_0_12"),
  score_scale = c("equal_week", "test_count"),
  min_gain = 0.0012,
  min_gain_by_horizon = c(`2` = 0.002),
  confidence = 0.95,
  max_season_degradation = 0,
  m1_min_gain = 0.05,
  m1_hard_caps = default_m1_hard_caps(),
  m1_prefer_simpler = TRUE,
  m2_min_nll_gain = default_m2_nll_gain_caps(),
  max_boundary_rounds = .default_boundary_round_limits(),
  m0_expansion_steps = NULL,
  m1_expansion_steps = .default_m1_expansion_steps(),
  m2_expansion_steps = NULL,
  m2_expansion_increment = .default_m2_expansion_increment(),
  min_training_seasons = 2L,
  n_cores = max(1L, parallel::detectCores() - 1L),
  checkpoint_dir = NULL,
  artifact_dir = NULL,
  verbose = TRUE,
  timing_mode = c("legacy", "fractional"),
  gate_nesting = c("full", "conditional"),
  shadow_m2 = TRUE
)
```

## Arguments

- data:

  Canonical multi-season surveillance data.

- holdout:

  Optional character scalar identifying the outer-held-out season. Use
  \`NULL\` only to fit the final kit after the evaluation procedure has
  been fixed.

- exclude:

  Character vector of fixed exclusions. Defaults to the protocol
  exclusions \`"2011-12"\`, \`"2015-16"\`, \`"2020-21"\`, and
  \`"2021-22"\`.

- manual_labels:

  Optional named ignition-week labels. Any label for \`holdout\` is
  removed before tuning.

- timing_labels:

  Optional timing-v2 label object or list of objects. The earlier
  ignition week is converted to the existing M0/M1 contract; peak weeks
  and the normalized uncertainty pairs are retained in the training
  result and artifacts. Any object for \`holdout\` is removed before
  tuning, while the complete supplied input is retained for provenance.
  Cannot be combined with \`manual_labels\`.

- m0_grid, m1_grid, m2_grid:

  Initial stage tuning grids.

- m0_flag_args:

  Named M0 ignition flag arguments forwarded to \`tune_m0()\` and
  \`fit_m0()\`. Defaults to the package detector defaults
  (\`.default_flag_args()\`).

- m1_params:

  Named baseline M1 settings that \`tune_m1()\` searches around.
  Defaults to \`.default_m1_params()\`.

- m2_family:

  M2 model family forwarded to \`tune_m2()\` and \`fit_m2()\`. Defaults
  to \`m2_subset_family()\` (\`"offset_subset_v1"\`).

- early_weight:

  Weight for target-relative weeks zero through \`early_max_t_since\`.

- early_max_t_since:

  Last target-relative week receiving \`early_weight\`.

- pre_ignition_weight:

  Phase weight for pre-ignition targets. The manuscript protocol is
  \`0\`.

- late_weight:

  Phase weight for targets later than \`early_max_t_since\`. The
  manuscript protocol is \`1\`.

- scoring:

  Scoring contract: `"page_v2"` (default) uses the retrospective phase
  weights, while `"legacy_0_12"` retains the old post-ignition 0:12
  weighting.

- score_scale:

  M2 tuning scale. The manuscript primary is \`equal_week\`;
  \`test_count\` is available as a sensitivity analysis.

- min_gain:

  Overall M2 NLL gain required over M1.

- min_gain_by_horizon:

  Optional named horizon-specific gain floors.

- confidence:

  One-sided season-level confidence used by the adoption rule.

- max_season_degradation:

  Largest permitted season-specific M2 NLL loss.

- m1_min_gain:

  Practical M1 improvement needed for added complexity.

- m1_hard_caps:

  Governed M1 hard caps.

- m1_prefer_simpler:

  Logical; prefer the simplest M1 candidate within \`m1_min_gain\` of
  the best. Defaults to \`TRUE\`.

- m2_min_nll_gain:

  Parameter-specific M2 boundary gain caps.

- max_boundary_rounds:

  Named positive integer vector for M0, M1, and M2. Defaults to \`c(M0 =
  5L, M1 = 4L, M2 = 6L)\`.

- m0_expansion_steps:

  Optional named adjacent expansion steps forwarded to
  \`boundary_action_plan()\` for M0. \`NULL\` uses the grid-derived
  spacing.

- m1_expansion_steps:

  Named positive adjacent expansion steps forwarded to
  \`boundary_action_plan()\` for M1. Defaults to \`c(k_ref = 5,
  slope_weight = 4)\`.

- m2_expansion_steps:

  Optional named adjacent expansion steps forwarded to
  \`boundary_action_plan()\` for M2. \`NULL\` uses the grid-derived
  spacing.

- m2_expansion_increment:

  Additional grid rows permitted per M2 boundary expansion round.
  Defaults to \`12L\`.

- min_training_seasons:

  Minimum number of outer-training seasons required before fitting.
  Defaults to \`2L\`, the leave-one-season-out minimum.

- n_cores:

  Number of workers supplied to stage tuners. Defaults to one fewer than
  \`parallel::detectCores()\`.

- checkpoint_dir:

  Optional resumable checkpoint directory.

- artifact_dir:

  Optional directory receiving grids, tuning objects, boundary reports,
  decisions, frozen stages, and the final kit.

- verbose:

  Logical progress flag.

- timing_mode:

  Character. `"legacy"` preserves integer ignition and aligned
  coordinates; `"fractional"` preserves numeric coordinates.

- gate_nesting:

  Inner-gate nesting depth. \`"full"\` (default) re-runs selection,
  inside each gate season's excluded dataset, for every upstream axis
  the recipe actually tunes (M0 always; M1 only when its grid has more
  than one value) before re-running the full M2 selection procedure.
  \`"conditional"\` re-runs the full M2 selection procedure only and
  passes the outer fold's selected M0/M1 settings through unchanged; its
  evidence is labelled \`"conditional on upstream selection"\`. Both
  options use nested M1 references (rows of \`r\` exclude \`r\` and the
  gate season) and identical estimator settings, and both are recorded
  in run provenance and kit metadata.

- shadow_m2:

  Logical; additionally fit and replay the tuned M2 candidate for
  output-only comparison when an outer fold keeps M1. Defaults to
  \`TRUE\`. Failures are recorded without failing the primary fold.
  Final all-season fits never build a shadow. \`FALSE\` preserves the
  original output schema.

## Value

A \`page_outer_training\` object containing the season selection, tuning
results, boundary histories, adoption evidence, frozen stages, and
assembled kit. With \`shadow_m2 = TRUE\`, the returned \`shadow_m2\`
contains a status and, when built, the shadow kit. Shadow evidence is
saved in separate \`shadow_m2_kit.rds\` and \`shadow_m2_status.rds\`
artifacts; the existing primary training artifact retains its original
schema.
