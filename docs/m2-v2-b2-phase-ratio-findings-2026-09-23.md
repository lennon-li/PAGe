# M2-v2 B2 timing-aware phase-ratio findings — 2026-09-23

## Question

Does the B-specific peak-timing posterior improve +1/+2 Influenza-B positivity forecasts beyond persistence?

This is the first numeric test of timing value. It deliberately avoids fitting the eventual C1/C2/C3 A/B curve model.

## Baseline

B0 is strict persistence:

`p_hat_B(t+h) = p_B(t)`

On the fixed provisional B epidemic ledger:

- overall season-balanced MAE: **1.091 pp**;
- h1: **0.769 pp**;
- h2: **1.413 pp**.

The first B1 persistence-plus-growth model is worse than B0, so persistence remains the hurdle.

## B2 construction

B2 keeps the observed current B positivity as the amplitude anchor and uses historical B peak-relative shape only to estimate short-horizon drift.

For candidate peak time `T`:

- `tau_current = origin - T`;
- `tau_target = origin + h - T`;
- canonical drift ratio = `f(tau_target) / f(tau_current)`;
- candidate forecast = `p_B(origin) * ratio`.

The final B2 forecast averages this nonlinear ratio over the B timing posterior rather than plugging a point peak estimate into the curve.

If timing is unavailable or target phase support is insufficient, B2 equals B0 exactly. No scoring row is removed.

The canonical curve is the training-fold B M1 normalized mean shape. Shape/amplitude estimation uncertainty is intentionally out of scope for this minimal test.

## Timing candidate family

Development sensitivity uses the predeclared B activity/lookback candidates:

- gate max B positivity in last 4 weeks: {1.5%, 2.0%};
- trailing four-week B positive count: >=40;
- lookback: {4, 6} weeks;
- B M1 amplitude grid: 0.5%–25% by 0.5 percentage points.

No candidate is selected from held-out performance in this script.

## Fixed-ledger results

All four timing candidates improve persistence on the provisional epidemic ledger.

### 1.5% gate / 4-week lookback

- overall: **1.091 -> 0.895 pp**;
- h1: **0.769 -> 0.687 pp**;
- h2: **1.413 -> 1.103 pp**.

### 2.0% gate / 4-week lookback

- overall: **1.091 -> 0.915 pp**;
- h1: **0.769 -> 0.696 pp**;
- h2: **1.413 -> 1.133 pp**.

### 1.5% gate / 6-week lookback

- overall: **1.091 -> 0.950 pp**;
- h1: **0.769 -> 0.682 pp**;
- h2: **1.413 -> 1.217 pp**.

### 2.0% gate / 6-week lookback

- overall: **1.091 -> 0.945 pp**;
- h1: **0.769 -> 0.692 pp**;
- h2: **1.413 -> 1.198 pp**.

The improvement is therefore not tied to one gate/lookback choice.

All-week metrics also improve, because timing rows improve while unavailable/unsupported rows fall back exactly to persistence.

## Timing-active rows

The gain is not a fallback artifact. On rows where timing is actually active:

### 2.0% / 4-week candidate

- B0 active-row overall MAE: **1.261 pp**;
- B2: **1.009 pp**;
- h1: **0.923 -> 0.817 pp**;
- h2: **1.635 -> 1.236 pp**.

The same direction holds for every development candidate.

## Posterior choice

Two weighting schemes were compared on the same 2.0% / 4-week ledger:

1. future-only M1-F peak posterior weights;
2. recent-past-capable latent phase posterior weights from the M1 passage-posterior machinery, **without using or trusting the B passage decision**.

Both improve B0:

- B0 overall: **1.091 pp**;
- future-only B2: **0.946 pp**;
- recent-past-capable B2: **0.915 pp**.

By horizon:

- h1: 0.769 -> 0.712 (future-only) -> 0.696 (recent-past-capable);
- h2: 1.413 -> 1.180 -> 1.133.

Using the broader latent phase posterior is therefore numerically useful even though B peak-passage **decisions** remain unsafe. These concepts must stay separate.

The M1-F and M1 passage-library **mean curves agree exactly** on their shared tau domain, so using the passage-domain shape lookup for small positive target tau does not stitch inconsistent mean shapes.

## Numerical safeguard sensitivity

The initial implementation included:

- a small current-shape floor;
- broad ratio caps;
- a minimum posterior mass with valid target-phase support.

The shape-floor/ratio-cap settings were nonbinding in the reference candidate: current, wide, and effectively uncapped settings produced identical forecasts.

Support-mass sensitivity from 0.50 to 0.95 is also stable:

- B2 overall MAE range: approximately **0.909–0.920 pp**;
- active fraction decreases as the threshold becomes more conservative, as expected.

Thus the observed B2 gain is not created by a fragile numerical cutoff.

## Predictive score

The B2 improvement is visible not only in MAE/RMSE but also in the count-weighted deviance diagnostic. The effect is modest because many rows fall back to B0, but the direction is consistently favorable in the provisional epidemic ledger.

Because the B panel spans historical shared-denominator/proxy and modern type-specific-denominator regimes, deviance should remain a secondary development diagnostic until the final B observation model is frozen.

## What this establishes

This is the first evidence that B timing is useful for the actual M2 objective, not merely for estimating a retrospective peak.

The evidence supports continuing to the structured A/B curve models because:

- B0 persistence is strong;
- naive growth does not beat it;
- phase-aware B2 does beat it;
- the gain is largest at h2, where phase should matter most;
- the gain is stable across the small timing candidate family.

## What this does NOT establish

This is still a development experiment, not a sealed final benchmark:

- the activity/lookback candidate family was informed by the same 11-season development set;
- gate/lookback selection has not yet been nested inside each outer fold;
- the provisional B ignition/epidemic ledger is retrospective and not expert-frozen truth;
- canonical shape uncertainty is not propagated;
- no A/B partial-pooling model has yet been fitted.

Before a final B2 promotion claim, gate/lookback/support choices should be selected or frozen without outer-fold optimization and replayed under the governed M2 evaluation contract.

## Decision

**Proceed to C1/C2/C3 A/B curve modeling.**

Use B2 as the timing-aware numeric baseline and preserve B0 fallback. Do not wait for a B passage lock; numeric M2 may use the latent B phase posterior probabilistically while B passage state remains unavailable.

Primary implementation artifact:

`scripts/evaluate_m2_b2_phase_ratio_v1.R`

Artifacts:

`artifacts/m2-v2-b2-phase-ratio-v1/`
