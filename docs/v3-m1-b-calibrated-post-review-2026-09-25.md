# V3 calibrated M1-B post-implementation review

Date: 2026-09-25
Status: reviewed; scalar calibration branch closed

## Reviewed implementation

Plan:

- `docs/v3-m1-b-governed-implementation-plan-2026-09-25.md`
- `docs/v3-m1-b-calibrated-audit-disposition-2026-09-25.md`

Implementation:

- `scripts/v3_benchmark_m1_b_calibrated_chronological_v2.R`

Artifacts:

- `artifacts/v3-m1-b-calibrated-chronological-v2/`

The corrected v2 run preserves the original v1 first-look artifacts, uses all six eligible seasons as the primary decision set, rebuilds activation ±1 sensitivity correctly, and records a single predeclared overall verdict.

## Primary result

Raw B0 versus scalar-calibrated M1-B on all six eligible chronological test seasons:

- raw season-balanced MAE: `1.87055`
- calibrated season-balanced MAE: `1.89648`
- raw early-weighted MAE: `1.84207`
- calibrated early-weighted MAE: `1.86548`
- raw worst-season MAE: `5.27418`
- calibrated worst-season MAE: `5.50090`
- calibrated 90% interval coverage: `0.76786`
- seasons worsened by calibration: `2`

Calibration does not improve the primary MAE criteria.

The five-season subset excluding low-support 2017-18 improves descriptively, but it has no decision weight by predeclared design.

## Passage result

Primary raw M1-B0 passage replay:

- one false-early season: 2019-20, one week early;
- only 3/6 seasons confirmed by peak+2;
- mean delay `1.83` weeks;
- median delay `2` weeks.

The passage failure is not caused by scalar calibration. Peak-location calibration changes reporting summaries only; raw passage probabilities/policy remain separate.

Activation sensitivity:

- activation `-1` week: one false-early season, 2019-20, five weeks early;
- activation `+1` week: zero false-early seasons.

Because activation -1 produces a large false-early passage, the current raw M1-B0 passage state is not approved as an M2-B timing gate.

## Integrity review

Independent post-review approved the implementation with caveats and found no bug that would reverse the stop decision.

Verified:

- strictly earlier meaningful-B training seasons only;
- exact raw-B0 origin-path and posterior-summary reproduction (maximum numerical difference about `5e-14`);
- early-weight reproduction to numerical precision;
- future-observation invariance for primary peak predictions and passage replay;
- training/test activation shifted together in ±1 sensitivity;
- calibrator and passage policy refit under activation shifts;
- 2018-19 remains excluded from timing fitting/scoring;
- material perturbation of all 2018-19 B observations leaves later-fold stage IDs, predictions, errors, and passage unchanged;
- no unexpected failure rows;
- source manifest hashes verified;
- frozen `PAGe/R` code unchanged.

## Known limitations

1. The current B activity rule/window and B amplitude support were selected with knowledge of the full historical archive, so this remains conditional research rather than governed production evidence.
2. The frozen M1-v2 scalar calibrator can include an inner calibration origin whose as-of boundary is after retrospective peak truth. A diagnostic excluding those post-peak rows makes the calibrated result worse, so this defect does not explain the negative result.
3. Only six B timing seasons are scored, so small numerical differences should not be overinterpreted.
4. The correct interpretation is `no robust calibration gain`, not `calibration is strongly harmful`.

## Decision

`historically_promising = FALSE`

Decision:

`retain_raw_M1_B0_stop_scalar_calibration`

Therefore:

- frozen M1-v2 remains M1-A;
- raw B-only M1-B0 remains the B peak-location baseline;
- A-conditioned M1-B1 remains stopped;
- scalar calibration remains stopped;
- raw M1-B0 passage is **not** approved for an M2-B timing gate.

## Next engineering step

If B timing gating is required for M2-B, run a separate predeclared **B passage robustness** evaluation centred on the existing raw M1-B0 passage machinery. Do not tune thresholds ad hoc against the already-inspected 2019-20 failure. The passage study must preserve chronological folds and explicitly test activation uncertainty, false-early behavior, confirmation delay, and no-event handling before any M2-B integration.
