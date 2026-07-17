# Simulate synthetic flu seasons for package examples

Generates `S` synthetic influenza seasons from a Gaussian-bump template
with random per-season amplitude, intercept, and timing (`tau`)
variation. Counts are drawn from a Binomial distribution with weekly `n`
sampled uniformly from \[600, 1500\].

## Usage

``` r
simulate_flu_seasons(S = 10, weeks = 1:52, seed = 2025)
```

## Arguments

- S:

  Integer number of seasons to simulate (default 10).

- weeks:

  Integer vector of within-season week indices to generate (default
  `1:52`).

- seed:

  Integer random seed for reproducibility (default 2025).

## Value

A data frame with columns `season` (factor), `newWeek`, `y` (positives),
and `neg` (negatives).
