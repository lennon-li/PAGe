# Decide whether an M2 candidate earns adoption over M1

Applies a prospective, equal-season baseline decision to matched
forecasts. M1 is the incumbent and M2 is adopted only when its Bernoulli
NLL gain is larger than both the requested practical floor and a
one-sided season-level uncertainty allowance. The all-off M2
configuration can use this decision as an exact M1 fallback.

## Usage

``` r
decide_m2_vs_m1(
  forecasts,
  outcome_col,
  m1_col,
  m2_col,
  season_col,
  origin_col,
  target_col,
  horizon_col,
  phase_col = NULL,
  t_since_col = NULL,
  phase_break = NULL,
  phase_weights = NULL,
  denominator_col = NULL,
  horizon_weights = NULL,
  min_gain = 0,
  min_gain_by_horizon = NULL,
  confidence = 0.95,
  max_season_degradation = 0,
  eps = 1e-12,
  scoring = c("page_v2", "legacy_0_12"),
  score_weight_col = NULL
)
```

## Arguments

- forecasts:

  Data frame with one row per season, origin, target, and horizon,
  containing the observed proportion and M1/M2 predictions.

- outcome_col, m1_col, m2_col:

  Character scalar column names for the observed proportion and the two
  predictions.

- season_col, origin_col, target_col, horizon_col:

  Character scalar column names defining the unique forecast key.

- phase_col:

  Optional phase-label column. When supplied with `phase_weights`, every
  observed non-missing phase must have a named weight.

- t_since_col:

  Optional numeric column used to derive `pre_ignition`, `early`, and
  `late` labels. Values from zero through `phase_break` are early;
  larger values are late.

- phase_break:

  Non-negative numeric boundary used with `t_since_col`. It must be
  supplied when `t_since_col` is used; there is no pathogen-specific
  default.

- phase_weights:

  Optional named non-negative weights. With no phase source, all rows
  have weight one. A zero weight excludes a phase from the score while
  retaining it in the input accounting.

- denominator_col:

  Optional positive numeric column, such as test volume. It is
  multiplied by the phase weight when supplied.

- horizon_weights:

  Optional named non-negative weights by horizon. Unspecified horizons
  receive equal weight when this is `NULL`.

- min_gain:

  Non-negative practical NLL gain floor on the equal-season overall
  score.

- min_gain_by_horizon:

  Optional named practical NLL gain floors for selected horizons. These
  are additional horizon-specific adoption gates.

- confidence:

  One-sided confidence level used for the season-level uncertainty
  allowance.

- max_season_degradation:

  Maximum tolerated equal-season NLL increase for any season after
  combining horizons. The default zero is a strict historical
  non-degradation rule.

- eps:

  Probability clipping value used in the NLL calculation.

- scoring:

  Scoring contract: code"page_v2" uses the retrospective phase weights
  (default), while code"legacy_0_12" retains the old post-ignition 0:12
  weighting.

- score_weight_col:

  Optional precomputed row-weight column. When omitted,
  codeweight_page_v2 or codeweight_legacy is used when available for the
  selected contract.

## Value

A `page_m2_baseline_decision` list with `decision`, `reasons`, `rule`,
`overall`, `by_horizon`, `by_season`, and row-accounting entries.

## Details

Rows may be weighted by a supplied denominator and/or phase weights. The
primary aggregation is always equal across seasons: rows are summarized
within season and horizon first, then seasons are averaged. No pathogen,
source column, or influenza-specific season label is assumed.
