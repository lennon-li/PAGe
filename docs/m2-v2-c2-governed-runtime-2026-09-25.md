# Governed M2-v2 C2 runtime path — 2026-09-25

## Scope and status

This is an opt-in, versioned C2 path that runs alongside the existing legacy M2 kit and
`run_prospective_pipeline()`. It does not replace or alter legacy M2 behavior. The current artifact
is a governed runtime shadow, not a production promotion. The C1/C2/C3 chronological review remains
the source evaluation record.

Build and replay from the repository root:

```sh
Rscript scripts/build_m2_v2_c2_governed_artifact.R
Rscript scripts/replay_m2_v2_c2_governed_shadow_v1.R
```

The versioned artifact is written under `artifacts/m2-v2-c2-governed-v1/`; synthetic contract
replay outputs are under `artifacts/m2-v2-c2-governed-shadow-v1/`. The callable package entry point
is `run_m2_v2_c2_governed_runtime()` in `PAGe/R/m2_v2_c2_governed.R`.

## Frozen contract

- C2 shares peak-relative log drift across A/B and blends it with the type-specific deviation.
- The type pooling and curve blend weights are both fixed at 0.5 under
  `c2-fixed-shrinkage-v1`; they are identity-bound and are not selected at runtime.
- A +1/+2 can use C2 only with a valid `m1-v2-to-m2-v1` A handoff. Invalid, unavailable, or failed
  timing returns the exact type-specific baseline.
- B +1 always returns exact B1. B +2 returns B1 while the gate is closed; opening it requires a
  JSON decision document with the exact policy version, `decision: open`, `status: reviewed_open`,
  and a review ID. The runtime checks the document hash again on each call. A valid B handoff is
  still required, and A timing cannot be substituted for B timing.
- The artifact binds its training seasons, input/source SHA-256 hashes, M1 timing contract IDs, B
  gate policy/version, denominator-regime metadata, historical timing cross-fit evidence, and output
  contract.
- The builder checks that each chronological target's `prior_seasons` exactly equal the earlier
  seasons in the training universe and exclude that target. The candidate-independent forecast
  ledger itself contains no upstream timing features; timing-driven evaluation is season-excluded
  in the chronological predictions used as the audit evidence.

The B gate is currently `closed_pending_review`. The generated replay writes a synthetic review
document only to exercise the opening contract; that document is explicitly not a governance
approval. The artifact also retains the known research limitation that historical shared test
denominators and modern type-specific denominators have not yet been reconciled into a final
observation likelihood. Denominator regime stays explicit metadata and unknown regimes fail closed.

## Current chronological evidence

The reviewed fixed-C2 chronological bundle selected C2 in 6 of 7 selectable outer seasons. The
season-balanced all-row MAE changes were:

| Type | Horizon | Baseline MAE (pp) | C2 MAE (pp) | Relative gain |
|---|---:|---:|---:|---:|
| A | +1 | 0.96325 | 0.95137 | 1.23% |
| B | +1 | 0.32536 | 0.32536 | 0% (exact B1) |
| A | +2 | 1.83805 | 1.71398 | 6.75% |
| B | +2 | 0.54092 | 0.48838 | 9.71% |

These are historical research metrics from the reviewed chronological replay, not new runtime
performance estimates. The governed runtime replay is synthetic and reports contract checks only.
