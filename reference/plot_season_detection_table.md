# Per-season ignition detection signal table

Filters the full detection data to a single season and returns an
interactive [`DT::datatable`](https://rdrr.io/pkg/DT/man/datatable.html)
showing the week-by-week gate conditions and ignition flags, with row
highlighting: green for the detected ignition week
(`ignite_flag == TRUE`) and yellow for weeks where all conditions passed
(`ignite_ok == TRUE`).

## Usage

``` r
plot_season_detection_table(det_all, season)
```

## Arguments

- det_all:

  List returned by
  [`detect_ignition_from_tuning()`](https://lennon-li.github.io/PAGe/reference/detect_ignition_from_tuning.md)
  or
  [`detectIgnitionBySeason_M0v2()`](https://lennon-li.github.io/PAGe/reference/detectIgnitionBySeason_M0v2.md)
  with `keep_signals = TRUE`. Must contain a `$data` data frame with
  columns `season`, `weekF`, `p`, `cond_win`, `cond_cls`, `cond_sum`,
  `cond_p`, `cond_prev`, `cond_inc`, `n_hit`, `ignite_ok`, and
  `ignite_flag`.

- season:

  Character string identifying the season to display (e.g. `"2019-20"`).

## Value

A [`DT::datatable`](https://rdrr.io/pkg/DT/man/datatable.html) object
with conditional row highlighting.

## Examples

``` r
if (FALSE) { # \dontrun{
det_all <- detect_ignition_from_tuning(tuned, alignedD)
plot_season_detection_table(det_all, "2019-20")
} # }
```
