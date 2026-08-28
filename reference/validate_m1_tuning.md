# Validate an M1 tuning result

Rejects zero evaluable seasons, all-missing metrics, non-finite selected
metric, missing selected configuration, or fold/selection mismatches.
Governed workflows can also require every genuinely tuned M1 axis to be
bracketed before the fit is frozen and passed downstream.

## Usage

``` r
validate_m1_tuning(x, check_boundaries = FALSE, hard_caps = NULL, ...)
```

## Arguments

- x:

  A `page_m1_tuning` object.

- check_boundaries:

  Logical; require all varying numeric M1 axes in the supplied grid to
  have an interior selected value. This is enabled by
  [`train_pipeline()`](https://lennon-li.github.io/PAGe/reference/train_pipeline.md)
  before M1 is frozen for M2.

- hard_caps:

  Optional named numeric vector or named list of lower/upper bounds,
  such as \`list(k_ref = c(lower = 10, upper = 50))\`. A selected value
  exactly at a hard cap is accepted and recorded as \`stop_hard_cap\`.

- ...:

  Reserved.

## Value

`x`, invisibly, if valid.
