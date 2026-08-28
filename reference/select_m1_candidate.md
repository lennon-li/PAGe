# Select an M1 candidate with a practical-gain backoff rule

When a more flexible \`k_ref\` is only marginally better, select the
smallest tested \`k_ref\` within \`min_gain\` weeks of the best M1
score. This keeps an upper-cap winner from being accepted solely because
it is more flexible.

## Usage

``` r
select_m1_candidate(
  x,
  min_gain = 0.05,
  prefer_simpler = TRUE,
  hard_caps = NULL
)
```

## Arguments

- x:

  A \`page_m1_tuning\` object.

- min_gain:

  Numeric minimum M1 Weibull-MAE improvement, in weeks, needed to
  justify the more complex candidate. Defaults to 0.05.

- prefer_simpler:

  Logical; choose the smallest eligible \`k_ref\`.

- hard_caps:

  Optional M1 hard-cap specification forwarded to the boundary guard.
  Practical backoff never selects an unresolved edge; declared
  structural caps may be selected.

## Value

A list containing \`selected\`, \`selected_spec_id\`, the best and
selected scores, and the backoff gain.
