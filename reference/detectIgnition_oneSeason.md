# Single-season wrapper around detectIgnitionBySeason_M0v2

Runs
[`detectIgnitionBySeason_M0v2`](https://lennon-li.github.io/PAGe/reference/detectIgnitionBySeason_M0v2.md)
on a single-season data.frame and returns signals for the last observed
week in the format expected by
[`run_ignition_weekly`](https://lennon-li.github.io/PAGe/reference/run_ignition_weekly.md).

## Usage

``` r
detectIgnition_oneSeason(d_now, params)
```

## Arguments

- d_now:

  A data.frame for one season, with columns: season, weekF, y, N, p,
  p_cls_p.

- params:

  List of ignition detection parameters (same as
  detectIgnitionBySeason_M0v2).

## Value

A list with:

- now:

  A 1-row data.frame with signal columns: p_now, cum_p_now, prev_now,
  p_cls_p_now, n_hit_now, d1_last, d2_last, cond_win, cond_cls,
  cond_cum, cond_p, cond_prev, cond_inc, ignite_ok_now.

- iWeek_hat:

  Integer ignition week estimate, or NA.
