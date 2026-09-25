# M1-v2 integration review disposition — 2026-09-23

An independent read-only review was run after parallel training/runtime integration. Findings were reviewed against the current timing contract rather than accepted mechanically.

## Accepted and fixed

### Late-season template support

The reviewer correctly identified that using every post-M0 observation could eventually make the fixed peak-relative template domain infeasible. M1-F and M1-C now trim only observations older than the maximum candidate/template overlap needed for the earliest admissible candidate. This preserves the existing likelihood whenever the full history fits, while preventing late-season `No admissible ... candidates` failures.

A regression test exercises M1-F and M1-C more than 20 observed weeks after activation.

### PCA sign determinism

The first PC sign is now anchored deterministically at the loading with largest absolute magnitude. If that loading is negative, both loading and scores are multiplied by -1 before bounds and hashes are constructed. This removes cross-BLAS sign ambiguity from the M1-v2 library/artifact identity without changing the represented shape family.

### Runtime governance identity

`run_m1_v2_timing()` now recomputes and verifies the M1-v2 governance identity when a governed base-kit identity is present. Direct runtime calls therefore receive the same governance protection as `validate_page_kit()`.

### Activation payload integrity

The governed M0 activation table now contains a canonical payload hash over sorted season, integer activation origin, and decimal activation coordinate. Calibration/passage training verifies this hash before use. Post-construction mutation is rejected.

### Passage-policy delay tie-break

Inner passage histories now extend through truth peak+6. `miss_by_peak2` remains the primary miss criterion, but delay tie-breaking can observe late confirmations. Inner seasons still unconfirmed by +6 receive a +7-week delay penalty for tie-breaking.

### Handoff schema cleanup

The runtime handoff uses one canonical elapsed clock (`weeks_elapsed_since_activation`) and one calibrated remaining clock (`weeks_to_calibrated_peak`). Raw and calibrated interval endpoints are explicit and validated.

### Stage identity coverage

The M1-v2 stage artifact identity now binds declared training seasons and the M2 handoff contract in addition to the library/calibrator/passage policy/configuration.

## Reviewed but intentionally not changed

### Passage probability boundary

The reviewer suggested evaluating passage at `T <= origin_week` rather than `T <= origin_week + 1`.

This was rejected because it conflicts with the frozen release-time timing contract. Observation week `w` represents interval `[w,w+1)`, and origin `w` is defined immediately after that aggregate is available. The continuous as-of boundary is therefore `w+1`, so passage probability is correctly evaluated as `P(T <= w+1 | data through w)`.

The 2018-19 early-lock failure revealed by the nested replay was addressed through the asymmetric safety contract instead: the fast passage branch now requires posterior passage probability >=0.95 plus an immediate consecutive-week decline. The extra drop-from-running-maximum floor remains zero in the validated default rule.

### Exact-integer truth confirmation boundary

The reviewer suggested replacing `ceiling(T*) - 1` with `floor(T*)`. Under the release-time contract, the first origin whose as-of boundary reaches a peak is the smallest integer `w` satisfying `w+1 >= T*`, which is `ceiling(T*) - 1`, including exact-integer peaks. The current definition is therefore retained.

## Verification

After these fixes, direct-source focused tests pass:

- M1-v2 core: 41 assertions;
- M1-v2 pipeline integration: 27 assertions;
- no focused failures or assertion warnings.

All 74 package R files parse successfully.

Full namespace/package tests remain blocked by the local R dependency problem (`ns_registry_env()` is defunct under the installed package stack). Tests that invoke the stale installed `PAGe::` namespace are not treated as worktree regression evidence.
