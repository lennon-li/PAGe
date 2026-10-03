# Construct a phase-based scoring-weight contract

Defines the non-negative per-phase weights used to score M2 forecasts
and the M2-vs-M1 gate. Weights are resolved against a target week
relative to a season's ignition week (\`I\`) and its observed peak week
(\`P\`).

## Usage

``` r
page_scoring_weights(
  pre_ignition = 0,
  rise = 2,
  turning = 3,
  decline = 1,
  turning_before = -1L,
  turning_after = 3L
)
```

## Arguments

- pre_ignition:

  Weight for target weeks before ignition (\`t \< I\`).

- rise:

  Weight for the rising limb (\`I \<= t \< P + turning_before\`).

- turning:

  Weight for the peak neighbourhood (\`P - turning_before \<= t \<= P +
  turning_after\`).

- decline:

  Weight for the declining limb (\`t \> P + turning_after\`).

- turning_before:

  Whole-number offset from the observed peak at which the turning window
  begins. The default is `-1`.

- turning_after:

  Whole-number offset from the observed peak at which the turning window
  ends. The default is `3`.

## Value

A list of class \`page_scoring_weights\` with elements \`pre_ignition\`,
\`rise\`, \`turning\`, \`decline\`, \`turning_before\`, and
\`turning_after\`.

## Details

Observed seasonal peaks are retrospective scoring references for
completed seasons only. They must never be supplied as forecast inputs
or used to build covariates available at forecast time. Fractional peak
labels are used on their native week scale; the resulting boundaries are
not rounded.

## Examples

``` r
PAGe:::page_scoring_weights()
#> $pre_ignition
#> [1] 0
#> 
#> $rise
#> [1] 2
#> 
#> $turning
#> [1] 3
#> 
#> $decline
#> [1] 1
#> 
#> $turning_before
#> [1] -1
#> 
#> $turning_after
#> [1] 3
#> 
#> attr(,"class")
#> [1] "page_scoring_weights"
PAGe:::page_scoring_weights(turning_before = 0L, turning_after = 0L, decline = 0)
#> $pre_ignition
#> [1] 0
#> 
#> $rise
#> [1] 2
#> 
#> $turning
#> [1] 3
#> 
#> $decline
#> [1] 0
#> 
#> $turning_before
#> [1] 0
#> 
#> $turning_after
#> [1] 0
#> 
#> attr(,"class")
#> [1] "page_scoring_weights"
```
