# Construct an M1 alignment parameter list

Builds the named list consumed by
[`build_m1()`](https://lennon-li.github.io/PAGe/reference/build_m1.md),
[`build_m2()`](https://lennon-li.github.io/PAGe/reference/build_m2.md),
and
[`train_m2()`](https://lennon-li.github.io/PAGe/reference/train_m2.md)
via their `m1_params` argument. Calling this function is the recommended
way to customise alignment settings rather than hand-crafting a raw
list, as it documents every knob and enforces defaults.

## Usage

``` r
m1_make_params(
  k_ref = 25L,
  ref_method = "fs",
  temperature = 0.25,
  rise_weight = 1,
  trough_weight = 0.1,
  peak_decay = 0.3,
  slope_weight = 8,
  slope_window = 6L,
  dynamic_temp = FALSE,
  dynamic_temp_pivot = 10L
)
```

## Arguments

- k_ref:

  Integer. Reference curve GAM basis dimension (default 25).

- ref_method:

  Character. Reference fitting method passed to
  [`estimateRef()`](https://lennon-li.github.io/PAGe/reference/estimateRef.md).
  One of `"fs"` (factor-smooth, default) or `"re"`.

- temperature:

  Numeric. Softmax temperature for template weighting (default 0.25).
  Lower values concentrate weight on the best-matching template.

- rise_weight:

  Numeric. Weight given to rise-phase similarity (default 1.0).

- trough_weight:

  Numeric. Weight given to trough similarity (default 0.1).

- peak_decay:

  Numeric. Exponential decay on peak-proximity weight (default 0.3).

- slope_weight:

  Numeric. Weight on slope similarity at aligned positions (default
  8.0).

- slope_window:

  Integer. Number of weeks used to compute the local slope (default 6).

- dynamic_temp:

  Logical. If `TRUE`, temperature adapts over the season (default
  `FALSE`).

- dynamic_temp_pivot:

  Integer. Week at which dynamic temperature pivots (default 10; ignored
  when `dynamic_temp = FALSE`).

## Value

A named list suitable for the `m1_params` argument of
[`build_m1()`](https://lennon-li.github.io/PAGe/reference/build_m1.md),
[`build_m2()`](https://lennon-li.github.io/PAGe/reference/build_m2.md),
and
[`train_m2()`](https://lennon-li.github.io/PAGe/reference/train_m2.md).

## Examples

``` r
params <- m1_make_params()
params_custom <- m1_make_params(slope_weight = 12, temperature = 0.15)
```
