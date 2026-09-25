# M2-v2 C2 governed chronological replay — 2026-09-25

## Status

Governed shadow integration is validated against the frozen prior-seasons-only fixed-C2 replay.

Current canonical identities:

- research fit: `m2v2_e39772e6d890d28d9ea7e22961ac2506870220005249c597d47d54dccc005e9a`
- governed wrapper: `m2v2g_e61427c696b16f7f23c6287bf684c0ff6e5fb9db11e379687d8a57fe9d13dd29`
- governed wrapper binds the exact canonical research-fit artifact ID above.

The governed B gate contract uses `causal_latch_after_first_qualifying_trailing_window` semantics for policy `b-epidemic-gate-5pct-v1`.

## Replay contract

Script:

`scripts/replay_m2_v2_c2_governed_chronological_v1.R`

Artifacts:

`artifacts/m2-v2-c2-governed-chronological-v1/`

For every target season, the replay builds a fold-specific C2 fit/governed artifact using only chronologically prior seasons. Historical typed A/B observations are then passed through the actual governed runtime adapter at each origin. Historical timing values are translated into contract-valid A/B handoffs. Family-unavailable early history remains baseline-only.

Two policy views are reported:

1. `governed_closed`: literal current governance, where B +2 remains B1 because formal B gate review is still closed.
2. `evaluation_open`: retrospective evaluation only, using a temporary non-operational gate-review object to measure B +2 model skill under the reviewed causal gate semantics. This is not operational authorization.

## Season-balanced MAE results

| stream | baseline MAE pp | governed-closed MAE pp | evaluation-open MAE pp | evaluation-open relative gain |
|---|---:|---:|---:|---:|
| A +1 | 0.96325 | 0.95137 | 0.95137 | 1.23% |
| A +2 | 1.83805 | 1.71398 | 1.71398 | 6.75% |
| B +1 | 0.32536 | 0.32536 | 0.32536 | 0.00% |
| B +2 | 0.54092 | 0.54092 | 0.48838 | 9.71% |

The governed runtime therefore reproduces the frozen fixed-C2 chronological result to numerical precision once the historical family-availability gate is honored.

## B +2 gate stratification

Under retrospective evaluation-only gate opening:

- gate inactive: 247 rows across 8 seasons; MAE unchanged at 0.40415 pp.
- gate active: 58 rows across 3 seasons; baseline MAE 1.12060 pp vs C2 MAE 0.84520 pp, a 24.58% relative gain.

This isolates the B +2 benefit to the exact regime where the B timing gate authorizes curve correction. Outside that regime the governed runtime is exactly B1.

## Replay invariants

All invariants pass at tolerance `1e-10`:

- runtime baseline matches the frozen chronological baseline: max absolute difference `6.38e-16`.
- evaluation-open governed runtime matches frozen fixed C2: max absolute difference `1.11e-15`.
- B +1 governed-closed is exactly baseline.
- B +1 evaluation-open is exactly baseline.
- B +2 governed-closed is exactly baseline.
- timing-unavailable/family-unavailable evaluation-open rows are exactly baseline.

## Regression tests

Focused parent-owned regression suite after governed pipeline integration:

- M2-v2 research: 63 assertions passed.
- M2-v2 governed: 12 assertions passed.
- M2-v2 pipeline shadow: 15 assertions passed.
- existing M1-v2 pipeline integration: 32 assertions passed.
- total: 122 passed, 0 failed.

All 76 package R source files parse.

Formal roxygen/package loading remains blocked by the existing local dependency-stack issue (`ns_registry_env()` defunct). Source-level parsing, focused tests, artifact builds, and replay scripts remain the authoritative validation path on this workstation.

## Current governance boundary

M2-v2 remains a parallel shadow path and does not replace legacy M2.

- A +1/+2 may use C2 when valid A timing is available.
- B +1 is always B1.
- B +2 is B1 while the operational B gate review remains closed.
- Retrospective evidence supports B1 + C2 after the causal B gate opens, but operational authorization is still a separate governance decision.
- missing/failed timing falls back exactly to the type baseline.
- cross-type A-to-B timing substitution is forbidden.
- the pipeline requires an explicit typed A/B panel for M2-v2 shadow execution; otherwise M2-v2 reports unavailable and legacy behavior is unchanged.
