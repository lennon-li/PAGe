# Build a provisional type-B soft-timing handoff for M2-v2

Build a provisional type-B soft-timing handoff for M2-v2

## Usage

``` r
new_m2_v2_b_soft_timing_handoff(
  season,
  origin_week,
  peak_mean = NA_real_,
  timing_available = is.finite(peak_mean),
  source_artifact_id = NA_character_,
  interval_width_90 = NA_real_,
  prob_peak_passed = NA_real_
)
```

## Arguments

- season:

  Single season identifier.

- origin_week:

  Current integer origin week.

- peak_mean:

  Soft posterior mean B peak week; may be \`NA\`.

- timing_available:

  Logical flag indicating whether B timing is available.

- source_artifact_id:

  Nonempty upstream B timing artifact identity when available.

- interval_width_90:

  Optional 90 percent timing interval width.

- prob_peak_passed:

  Optional posterior probability that the B peak has passed.

## Value

A validated provisional type-B timing handoff list.
