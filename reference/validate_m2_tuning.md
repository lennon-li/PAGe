# Validate an M2 tuning result

Rejects invalid grid identity, incomplete folds, non-finite selected
metric, or absent selected specification.

## Usage

``` r
validate_m2_tuning(x, check_boundaries = FALSE, min_nll_gain = NULL, ...)
```

## Arguments

- x:

  A `page_m2_tuning` object.

- check_boundaries:

  Logical; require every genuinely tuned M2 axis to be bracketed or an
  explicitly accepted null/drop.

- min_nll_gain:

  Named parameter-specific NLL gain threshold, or one scalar applied to
  every M2 axis. Defaults to
  [`default_m2_nll_gain_caps()`](https://lennon-li.github.io/PAGe/reference/default_m2_nll_gain_caps.md);
  omitted names use the governed defaults. A boundary with matched
  outward gain at or below its threshold is accepted as
  \`stop_small_gain\`; a boundary without matched evidence remains
  unresolved.

- ...:

  Reserved.

## Value

`x`, invisibly, if valid.
