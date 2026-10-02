# PAGe v3 M1-B1 A-conditioned timing experiment — implementation review

Date: 2026-09-25
Status: STOPPED after audited implementation and independent post-review

## Question

Does causal Influenza A peak timing improve Influenza B peak timing beyond the B-only M1-v2-style timing model?

## Implementation

Plan:

- `docs/v3-m1-b1-implementation-plan-2026-09-25.md`

Code:

- `scripts/v3_benchmark_m1_b1_a_conditioned_v1.R`

Artifacts:

- `artifacts/v3-m1-b1-a-conditioned-v1/`

Candidates:

- `B0`: raw B-only M1-v2 posterior
- `B1_cal`: B likelihood plus prior over prior-season B peak calendar positions
- `B1_A`: B likelihood plus A-conditioned prior using causal M1-A passage timing and historical A-to-B peak lags

The A-conditioned model uses the frozen M1-A passage machinery. Before A peak passage is confirmed it uses the current causal passage posterior. At first confirmation it freezes that posterior and carries it forward to later B origins.

Primary prior settings:

- Gaussian kernel bandwidth `h = 2 weeks`
- uniform robustness mixture `epsilon = 0.10`

Sensitivities:

- `h = 1, 3`
- `epsilon = 0.05, 0.10`

## Primary chronological result

| Model | Season-balanced MAE | Early-weighted MAE | 90% coverage | Mean log score | Worst-season MAE |
|---|---:|---:|---:|---:|---:|
| B0 | 1.871 | 1.842 | 0.81 | -4.64 | 5.274 |
| B1-cal | 1.769 | 1.741 | 0.92 | -4.48 | 3.732 |
| B1-A | 2.208 | 2.187 | 0.75 | -4.89 | 5.274 |

A-conditioning is worse than B0 and worse than the no-A calendar control.

## Per-season A-conditioned change versus B0

Negative is improvement.

- 2017-18: +0.001 weeks MAE
- 2019-20: +0.518
- 2022-23: -0.0005
- 2023-24: +0.194
- 2024-25: +0.994
- 2025-26: +0.318

The 2017-18 and 2022-23 changes are effectively zero because the A-conditioned prior has almost no probability mass on the admissible B candidate grid; the epsilon-uniform component therefore leaves the posterior nearly equal to B0.

Among the four seasons where the A-conditioned prior materially overlaps the B candidate support, A-conditioning is worse in all four.

## Sensitivity result

Across all tested combinations of `h in {1,2,3}` and `epsilon in {0.05,0.10}`, A-conditioning remains worse than B0.

The result moves toward B0 as the A-derived prior is weakened, which is evidence that the A-derived information itself is harmful rather than that one bandwidth was poorly chosen.

## Why the additive A-to-B lag model fails

Historical B timing is not well described by:

`B peak = A peak + approximately stable lag`

Within chronological training folds, the correlation between A peak and `B peak - A peak` is strongly negative (roughly -0.82 to -1.00). The lag distribution ranges from near zero to more than 23 weeks.

This means the lag largely adjusts in the opposite direction of A timing; a later A peak does not imply a similarly shifted B peak. An additive lag prior therefore injects misleading timing structure into the B posterior.

## B1-cal interpretation

The no-A calendar prior is slightly better on the full six-season average, but that improvement is not robust.

Its gain is driven primarily by 2022-23. Excluding that season, the calendar-prior candidate is worse than B0 across the tested sensitivity settings.

Therefore B1-cal is not promoted from this experiment.

## Causality / validation checks

Passed:

- exact B0 recomputation against the existing chronological baseline
- identical B0/B1-cal/B1-A origins and candidate grids
- all 33 per-origin future-B perturbation tests
- all 33 per-origin future-A perturbation tests
- causal sequential M1-A passage handling
- no test-season peak truth used in A/B prior construction

Known limitations noted by post-review:

- formal automated leakage tests for held-out-truth perturbation and later-season removal were not implemented because the candidate failed promotion decisively;
- some A-timing helper errors are caught and could reuse a prior valid state, though no such fallback occurred in the observed run;
- the experiment is research evidence rather than a pristine confirmatory test because held-out timing geometry was inspected during design.

## Decision

**Stop M1-B1 A-conditioned timing.**

Do not escalate this result into a more complex symmetric A+B latent/shared-phase model.

Do not promote B1-cal from this experiment.

Keep frozen M1-v2 as M1-A.

The next M1-B work should remain B-specific and should first establish a governed/calibrated B-only M1-B baseline before considering any other cross-type timing architecture.
