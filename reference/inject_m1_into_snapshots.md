# Replace logit_f_eff in M2 snapshots with M1's aligned prediction

Takes the output of
[`build_stage2_pseudo_prospective_list()`](https://lennon-li.github.io/PAGe/reference/build_stage2_pseudo_prospective_list.md)
and replaces each snapshot's `logit_f_eff` with M1's prediction at the
corresponding target week.

## Usage

``` r
inject_m1_into_snapshots(pp, m1_result, ref, horizons = c(1L, 2L), eps = 1e-06)
```

## Arguments

- pp:

  List with `meta` and `df` from
  [`build_stage2_pseudo_prospective_list()`](https://lennon-li.github.io/PAGe/reference/build_stage2_pseudo_prospective_list.md).

- m1_result:

  Output from
  [`run_alignment_prospective()`](https://lennon-li.github.io/PAGe/reference/run_alignment_prospective.md)
  for the current evaluation week.

- ref:

  Reference object (must have `anchorWeek`).

- horizons:

  Integer vector of forecast horizons (default `c(1L, 2L)`).

- eps:

  Clipping epsilon for logit (default 1e-6).

## Value

Modified `pp` with `logit_f_eff` replaced by M1 predictions.
