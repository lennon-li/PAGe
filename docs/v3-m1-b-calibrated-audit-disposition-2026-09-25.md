# V3 calibrated M1-B pre-run audit disposition

Date: 2026-09-25
Status: approved with required fixes before confirmatory rerun

## Decision

Proceed with the calibrated B-only M1-B benchmark only as a **conditional research benchmark**.

The primary evaluation population is all six chronologically eligible B timing seasons. The five-season subset excluding 2017-18 is descriptive only and cannot determine promotion.

The original `v1` benchmark artifacts are preserved as the first look at these outcomes. The corrected rerun writes to a new `v2` artifact directory and cannot overwrite `v1`.

## Required audit fixes accepted

1. Preserve the first run and record its hashes in the corrected-run manifest.
2. Add one overall `historically_promising` verdict based on the primary six-season calibration criteria, passage criteria, integrity checks, and activation sensitivity.
3. Rebuild activation ±1 sensitivity correctly:
   - shift training activations as well as test activation;
   - rebuild fold calibration and passage policy under each shift;
   - regenerate the scored origin path from the shifted activation;
   - replay passage under the shifted activation;
   - treat any false-early passage under either ±1 shift as a veto.
4. Keep frozen M1-v2 calibrator code unchanged, but add a diagnostic for inner calibration rows whose as-of boundary is after retrospective peak truth.
5. Add explicit fold-isolation and timing-contract semantic assertions.
6. Add `activity_detected = FALSE` to explicit inactive/no-event rows and run a real 2018-19 exclusion perturbation check.
7. Wrap passage computation in explicit failure capture; any unexpected failure vetoes the benchmark.
8. Assert recomputed early weights match the stored B0 benchmark and record `max_future_weeks` in benchmark configuration.

## Predeclared overall decision

`historically_promising = TRUE` only if all of the following hold on the primary six-season set:

- calibrated season-balanced MAE <= raw B0 MAE;
- calibrated season-balanced early-weighted MAE <= raw B0 early-weighted MAE;
- calibrated worst-season MAE <= raw worst-season MAE + 0.5 week;
- no more than two seasons worsen;
- calibrated 90% interval coverage >= 0.70;
- primary passage false-early seasons = 0;
- no false-early passage in either activation -1 or +1 sensitivity;
- all future-perturbation/integrity checks pass;
- exact raw-B0 recomputation passes;
- no unexpected stage/prediction/passage failures occur.

Passing this benchmark still does not make M1-B governed, because the B activation rule/window and B amplitude support were selected with knowledge of the full archive.

If the corrected benchmark fails the overall decision, retain raw M1-B0 and stop scalar calibration complexity.
