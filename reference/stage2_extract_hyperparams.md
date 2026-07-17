# Extract Stage-2 hyperparameters from tuning output

Pulls the commonly used Stage-2 hyperparameters from a list or 1-row
data frame, supporting alternate column names (`shift` as an alias for
`delta`). Any keys not recognised as core hyperparameters are collected
in `extra`.

## Usage

``` r
stage2_extract_hyperparams(best_mean_nll)
```

## Arguments

- best_mean_nll:

  A list or 1-row data frame containing tuned parameters. Recognised
  keys: `delta` (or `shift`), `K`, `leads`, `use_ramp`.

## Value

A list with `delta` (integer template shift), `K` (integer EMA
half-life), `leads` (integer vector of forecast horizons), `use_ramp`
(logical), and `extra` (list of any remaining keys).
