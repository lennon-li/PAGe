# Boundary expansion record — 2026-08-01

This is a development plan derived from existing saved artifacts. It is not a
new tuning result and it does not authorize rerunning a grid whose results are
already available.

## Evidence inspected

- Corrected user-test monitor: `results/user-test/v16-corrected-20260730T034430Z/HOURLY_MONITOR.md`
- Historical M1 and M2 tuning artifacts referenced by the project context.
- Prospective holdout season `2025-26` was untouched during development and
  was later opened only for the frozen acceptance replay recorded below.

## Controlled next comparisons

| Stage | Axis | Existing winner | Boundary interpretation | Next candidate |
|---|---|---:|---|---:|
| M1 | `k_ref` | 25 | lower edge | 20 |
| M1 | `slope_weight` | 12 | interior in fresh run | none |
| M2 | `k_e` | 2 | lowest non-null EMA smooth | 0 (drop EMA smooth) |
| M2 | `k_sp` | 8 | upper edge | 10 |
| M2 | `bias_alpha` | 0.05 | lower correction rate | 0 (drop correction) |

The planner now accepts `k_e = 0` as a governed null and rejects `k_e = 1`,
which is not a supported basis size. `k_sp = 0` and `k_r = k_de = 0` remain
existing optional-smooth nulls. These values are comparisons to evaluate in a
future bounded pre-holdout run; they are not promoted configurations.

## Guardrails

1. Preserve the existing candidate results and folds; add only the listed
   one-factor comparisons.
2. Do not open or use the prospective holdout while choosing among them.
3. Revalidate complete folds, inspect per-season stability, and apply the
   declared selection rule before freezing a stage.
4. If a positive parameter still wins at an unresolved edge, expand once more
   or document a scientific/hard constraint; never silently accept the edge.

## Acceptance outcome

The boundary-only run froze the `bias_alpha = 0` candidate against the cached
M1 incumbent (`k_ref = 25`) and replayed it against the existing
`v16-corrected` incumbent (`alpha_state = 0.20`, `k_sp = 8`,
`bias_alpha = 0.05`) on `2025-26`. The candidate's overall Bernoulli NLL was
`0.3153721` versus `0.3153873`, an improvement of `0.0000482`; the locked gate
requires at least `0.02`, so the decision was **FAIL**. Horizon and phase MAE
gates passed. The decision bundle, row-level replays, aggregate metrics, and
manifest are preserved under the ignored run paths
`results/user-test/boundary-expansion-20260801T150000Z/` and
`results/audit/boundary-expansion-20260801T150000Z/`.

No refit, promotion, or artifact replacement followed. The incumbent remains
the accepted configuration. Any future model search must be declared as a new
pre-holdout development cycle; this holdout result cannot be used to tune the
next candidate while retaining confirmatory status.
