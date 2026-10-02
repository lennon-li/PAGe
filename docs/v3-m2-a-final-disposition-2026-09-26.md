# V3 M2-A final historical disposition

Date: 2026-09-26
Status: retrospective timing-correction branch closed; retain exact A1

## Decision

For v3 shadow operations:

- **A +1:** exact A1 state/growth forecast.
- **A +2:** exact A1 state/growth forecast.
- Do not promote the posterior-C2 A timing correction.
- Do not continue retrospective A timing-correction parameter searches on the current archive.

Historical verdict:

`retain_A1_stop_retrospective_M2A_timing_search`

Evidence:

`artifacts/v3-m2-a-posterior-c2-chronological-v1/`

Implementation:

`scripts/v3_benchmark_m2_a_posterior_c2_chronological_v1.R`

Audited design:

`docs/v3-m2-a-implementation-plan-2026-09-26.md`

## Historical result

### A +1

Diagnostic only by predeclared policy.

- A1 season-balanced MAE: `0.967864` percentage points
- posterior-C2 MAE: `0.971221` percentage points
- relative change: `-0.35%`

A +1 remains exact A1.

### A +2

Across eight chronological test seasons:

- A1 season-balanced MAE: `1.848796` percentage points
- posterior-C2 MAE: `1.774036` percentage points
- relative MAE gain: `4.0437%`
- A1 worst-season MAE: `2.536388` percentage points
- posterior-C2 worst-season MAE: `2.519031` percentage points
- pooled target-test NLL: `0.2092092 -> 0.2087028`
- seasons improved: `6`
- seasons worsened: `0`

Among the six timing-active seasons:

- A1 season-balanced MAE: `1.796107` percentage points
- posterior-C2 MAE: `1.696428` percentage points
- relative gain: `5.5497%`
- all `6/6` timing-active seasons improve.

Despite those favorable secondary results, the predeclared service-wide threshold required at least `5%` improvement. The observed `4.0437%` therefore fails qualification.

## Why the threshold is not relaxed

The historical result was inspected only after the 5% service-wide threshold was written into the implementation plan.

Changing the threshold from 5% to 4.04% after observing the result would be post-hoc model selection. The point-mean diagnostic also exceeds 5% service-wide improvement, but it was explicitly predeclared as diagnostic only and cannot replace the posterior-mixture candidate after inspection.

Therefore the stopping rule is upheld.

## Diagnostic interpretation

Retrospective +2 phase strata:

- pre-peak: `+5.71%` gain
- post-peak: `+4.77%` gain
- near-peak: `-9.02%` loss

Lower-bound strata among timing-active rows:

- lower-bound mass >= 0.9: `+7.23%` gain
- lower-bound mass < 0.9: `+5.68%` gain

These strata are diagnostic only. The near-peak degradation is an additional reason not to create a post-hoc timing gate from this result.

## Integrity / causal validation

Independent review returned `APPROVE` for the benchmark implementation and negative decision.

Verified:

- causal prefix-only M0-A activation;
- frozen M0-A parameters unchanged;
- activation latch and end-of-season parity across all 11 seasons;
- strictly chronological state/timing/shape folds;
- M1-v2 specification identity preserved;
- full-history canonical-v3 M1-A rebuild reproduces reference hash `ae539389e556fb342c6ea5e1a391fed027c46ff509326536647ff3d34fb79bfb`;
- known peak-truth vintage differences emitted explicitly;
- no scalar M1-A bias calibration inside the M2-A timing correction;
- no hard M1-A passage decision;
- fixed C2 weights `0.5/0.5` and `eta=0.5`;
- B pooled-shape context excludes 2018-19 and 2019-20;
- future-observation perturbation checks pass;
- held-out peak-truth and target perturbation checks pass;
- timing-unavailable rows return exact A1;
- deterministic core output reproduction passes;
- all benchmark integrity checks pass;
- no unexpected failure rows.

## Governance consequence

M1-A remains frozen M1-v2.

M2-A does **not** receive a new v3 timing-informed shadow route from this retrospective experiment. For the combined v3 shadow stack, A remains state-only at M2:

- `A +1 = A1`
- `A +2 = A1`

Future A timing-correction work, if revisited, should be justified by new prospective evidence rather than additional retrospective threshold/phase searches on the same archive.
