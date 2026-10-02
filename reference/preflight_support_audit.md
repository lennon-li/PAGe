# Preflight support audit for M0/M1/M2

A structured, read-only audit that reuses existing per-stage validators
to report whether supplied grids and specifications are supportable by
the available data. Does not launch workers, fit models, or modify
state.

## Usage

``` r
preflight_support_audit(
  data,
  m0_grid = NULL,
  m1_grid = NULL,
  m2_grid = NULL,
  n_weeks = 52L,
  selection = NULL,
  aligned = NULL,
  m2_data = NULL
)
```

## Arguments

- data:

  Canonical surveillance data frame.

- m0_grid:

  Optional M0 tuning grid (data frame).

- m1_grid:

  Optional M1 tuning grid (data frame).

- m2_grid:

  Optional M2 tuning grid (data frame).

- n_weeks:

  Integer reference-domain size (default 52).

- selection:

  Optional `page_season_selection`. When supplied, only training seasons
  are used for data-dependent checks.

- aligned:

  Optional aligned M0 output with a `newWeek` column. When supplied, M1
  reference-basis support is checked for every requested `k_ref`;
  otherwise that check is reported as deferred.

- m2_data:

  Optional prepared M2 training data with `lead` and post-ignition
  covariates. When omitted, M2 grid-domain checks still run, but basis
  support is reported as deferred until this handoff exists.

## Value

A `page_preflight_audit` list with one entry per requested stage. Each
entry contains `valid` (logical), `issues` (character vector of
problems), and `remediation` (character vector of suggestions). The
audit itself stops on malformed input (e.g., wrong types) but records
per-stage validation failures in the report.
