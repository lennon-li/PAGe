# Resolve a week estimate with an optional manual override

Applies an override week to an estimated week using a selected policy:

- `"replace"`: force the week to the override.

- `"cap"`: final week cannot be later than override
  (`min(est, override)`).

- `"floor"`: final week cannot be earlier than override
  (`max(est, override)`).

- `"nearest_valid"`: snap override to the nearest value in
  `valid_weeks`.

## Usage

``` r
resolve_week_override(
  week_est,
  override_week = NULL,
  mode = c("replace", "cap", "floor", "nearest_valid"),
  valid_weeks = 1:52
)
```

## Arguments

- week_est:

  Integer-ish scalar estimate (can be `NA`).

- override_week:

  Optional integer-ish scalar override (can be `NULL`/`NA`).

- mode:

  Override policy.

- valid_weeks:

  Integer vector of valid week values. Default 1:52.

## Value

A list with elements `final`, `est`, `overridden`, `override`.

## Examples

``` r
resolve_week_override(18, NULL)
#> $final
#> [1] 18
#> 
#> $est
#> [1] 18
#> 
#> $overridden
#> [1] FALSE
#> 
#> $override
#> [1] NA
#> 
resolve_week_override(18, 20, mode = "cap")
#> $final
#> [1] 18
#> 
#> $est
#> [1] 18
#> 
#> $overridden
#> [1] TRUE
#> 
#> $override
#> [1] 20
#> 
resolve_week_override(NA, 15, mode = "replace")
#> $final
#> [1] 15
#> 
#> $est
#> [1] NA
#> 
#> $overridden
#> [1] TRUE
#> 
#> $override
#> [1] 15
#> 
```
