# M0 Model

## Purpose

M0 detects epidemic ignition prospectively from weekly surveillance data. Its output is a locked ignition week that activates the aligned coordinate system used downstream by M1 and M2.

## Inputs

- Weekly raw surveillance counts: `y`, `N`, `p = y / N`
- Within-season week index: `weekF`
- Historical labels for training and evaluation

## Core idea

M0 is a gated detector. Each week it evaluates four threshold-based conditions:

- `cond_sum`: cumulative burden
- `cond_p`: current positivity level
- `cond_prev`: sustained elevation
- `cond_inc`: recent increase

Ignition fires only when all four conditions agree within a tuned eligibility window. This is intentionally conservative because a false start contaminates all downstream alignment.

## Statistical structure

There are two pieces:

1. A stage-1 ignition scoring model built by `fitIgnition()`
2. A stage-0 rule-based detector built by `detectIgnitionBySeason_M0v2()`

The detector is tuned by leave-one-season-out grid search to minimize ignition timing error without using future information from the held-out season.

## Output

Primary output:

- Locked ignition week `iWeek_hat_locked`

Derived consequence:

- Aligned week transformation for downstream stages

`newWeek = weekF - iWeek_hat + anchorWeek`

## Role in the pipeline

- Before ignition: M1 and M2 should not run in their normal post-ignition mode
- At ignition: M1 alignment starts
- After ignition locks: the same week anchor is used consistently through deployment

## References

- `docs/pipeline_overview.qmd`
- `docs/ignition_training.qmd`
- [[M0-Implementation]]
- [[M1-Model]]
