# Prepare raw and stabilized peak fields for one alignment origin

Prepare raw and stabilized peak fields for one alignment origin

## Usage

``` r
.m1_prepare_peak(
  res,
  peak_stabilization = c("legacy", "causal"),
  previous_state = NULL,
  max_jump_weeks = 2
)
```

## Arguments

- res:

  Alignment result with a \`peak\` list.

- peak_stabilization:

  Character mode, either \`"legacy"\` or \`"causal"\`.

- previous_state:

  Optional same-season prior stabilized state.

- max_jump_weeks:

  Positive maximum causal center movement.

## Value

A list containing raw and downstream stabilized peak fields.
