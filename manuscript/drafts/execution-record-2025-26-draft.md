# Execution record: 2025-26 gate-run attempts

Draft. Recorded: 2026-09-15. Computation and provenance only; no results
numbers other than the verified facts below.

## 2025-26 gate-run attempts

| Attempt | Run ID | Outcome |
|---|---|---|
| Legacy integer replay | `20260912T025500Z-ultimate-2025-26-r3` | Complete. Kept M1: M2 did not pass the minimum gain. h2 phase-weighted NLL 0.5578 on 8 rows common to both replays. |
| Fractional end-to-end replay | `20260913T180000Z-ultimate-2025-26-fractional-e2e-r4` | Complete. Kept M1: M2 did not pass the minimum gain. h2 phase-weighted NLL 0.5575 on the same 8 rows. |
| Parallel-fixed r1-r3 | `parallel-fixed-r1` .. `parallel-fixed-r3` | Identical duplicates of r4 (same protocol/source hash); stopped by operator 2026-09-15 to relieve CPU oversubscription (4 x 8 workers on 12 CPUs). |
| Parallel-fixed r4 | `20260914T180000Z-parallel-fixed-r4` | M0 and M1 completed and frozen (M1 selected `s012` `k_ref=30`, `slope_weight=12` under the 0.05 minimum-gain rule; best `s002` `k_ref=20` gain 0.0476). Killed 2026-09-15 01:15:20 UTC mid-M2 at 228 of 686 spec checkpoints when the Codex agent foreground-launcher session terminated its processes. No R error, no OOM. |
| Venkata M1 reproduction | `m1-repro-20260915T0145Z` (Venkata) | M1 round 1 only, new code, same inputs as r4. Complete in 43.3 min (8 cores). Not bit-identical to r4 (max score difference 0.011; typical about 0.001) because of platform numerics (OpenBLAS 0.3.20/LAPACK 3.10, Ubuntu 22.04, AMD vs reference BLAS/LAPACK 3.12, Ubuntu 24.04, Intel); same best spec `s002`. |
| M1-reuse / M2-parallel r5 | `20260915T0150Z-m1reuse-m2parallel-r5` | Launched 2026-09-15 01:49 UTC, detached, run-local library, identity watchdog. Status in progress. `[PENDING]` |

<!-- parent-verified run table 2026-09-15; prior replays kept M1 and h2 weighted NLL 0.5578 vs 0.5575 on 8 common rows; r5 path results/manuscript/nested-outer-2025-26-ultimate-20260915/20260915T0150Z-m1reuse-m2parallel-r5 -->

## Computational changes

Each change below is computation-only.

- **M1 alignment reuse.** Specs differing only in `slope_weight`/temperature
  share the per-template alignment. A real-data check reproduced the legacy r4
  checkpoints for `k_ref=30`, `slope_weight=8` and `12` with maximum absolute
  difference 0 across all 10 folds. Unit tests pass. Equivalence evidence:
  complete for these checkpoints.
  <!-- parent-verified real-data check and unit tests; m1_loso.R fractional branch -->
- **M2 spec parallelism.** `m2_subset_tune` previously ignored `n_cores` and
  ran serially; it now evaluates specs and per-season preparation in parallel.
  Synthetic serial versus parallel were identical (maximum absolute difference
  0). Real-data equivalence versus r4 checkpoints is `[PENDING]`.
  Equivalence evidence: synthetic only.
  <!-- m2_subset_correction.R:782-799 (n_cores validation and parallel plan); parent-verified synthetic check -->
- **Run-local package library and hash check.** The launcher installs PAGe
  into `<run_dir>/r-lib`, hashes the source before and after installation,
  refuses to run if the source changed, the version differs, or the install
  predates the source, and records the installed `PAGe.rdb` hash in
  `package_revision_check.txt`. r5 recorded a passing check. This replaces the
  shared `r-lib`, which concurrent launches had reinstalled under running
  jobs. No numerical effect expected.
  <!-- 2025/launch_2025_ultimate.sh; r5 package_revision_check.txt -->
- **Cross-platform numerics.** Identical code and inputs gave small score
  differences between Asgard and Venkata (see table). All folds of one analysis
  and the operational kit must use one recorded platform (BLAS/LAPACK, OS,
  CPU, package versions).
- **Detached launch and identity watchdog.** r5 was launched detached with a
  run-local library and an identity watchdog, so the runner is not owned by the
  foreground agent session that killed r4. Equivalence evidence: process
  ownership only; no numerical effect expected.
  <!-- parent-verified r5 launch state 2026-09-15 -->

The `v16-corrected` kit is legacy context only; it is not a comparator and not
a headline model.

<!-- parent-verified statement -->

---

## Markers in this file

- `[PENDING]`: r5 status; real-data M2 serial-versus-parallel equivalence.
- `[PENDING]`: platform decision for the fractional cycle and operational kit.
