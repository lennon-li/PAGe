# M0-v2 no-calendar-gate early-safe redesign — 2026-09-25

## Why this change exists

The governed M1-v2 stack used the newer nested M0-v2 machinery, but its 36-spec tuning grid still inherited a legacy lower calendar boundary `w_min = 13`. The classifier was already disabled in every grid row (`use_cls = FALSE`), so the effective detector was a classifier-free N-of-4 rule plus a hard eligible-week window.

For prospective use, the hard lower calendar gate is undesirable: an otherwise sufficient epidemiologic signal should not be vetoed solely because it occurs before week 13.

## First naive gate removal

Changing only `w_min` from 13 to 1 while keeping the old threshold grid was unsafe.

Strict LOSO result:

- fractional MAE: 1.246 weeks
- bias: -1.202 weeks
- max absolute error: 9.270 weeks
- >1-week false-early detections: 3/11
- 2017-18 fired at ~10.73 versus truth ~20.

The 2017-18 failure was a short early A surge. At week 11 its 5-week positivity sum reached ~0.0668, above the old grid's maximum accumulation threshold 0.060, after which activity receded before the true ignition around week 20.

## Early-safe gate-free redesign

The corrected candidate family keeps the classifier disabled and removes the lower calendar gate, but strengthens signal evidence and makes false-early errors more expensive during tuning.

Changes:

- `use_cls = FALSE` explicitly.
- `w_min = 1` (effectively no lower calendar gate).
- `w_max = 26` retained as an administrative/failure boundary.
- N-of-4 evidence structure retained.
- original `p_thr` / `prev_thr` combinations retained.
- 5-week accumulation threshold grid expanded upward to `0.075, 0.080, 0.085, 0.090, 0.095, 0.100`.
- tuning objective gains a backward-compatible `gamma_early` term; default is 0 for historical callers. This replay uses `gamma_early = 100`.

Script:

`scripts/run_m0_v2_nogate_early_safe_loso_v1.R`

Artifacts:

`artifacts/m0-v2-nogate-early-safe-loso-v1/`

## Strict LOSO result

Season-level held-out fractional ignition estimates:

| season | truth | estimate | error |
|---|---:|---:|---:|
| 2012-13 | 19 | 18.212 | -0.788 |
| 2013-14 | 20 | 20.620 | +0.620 |
| 2014-15 | 20 | 20.627 | +0.627 |
| 2016-17 | 19 | 19.041 | +0.041 |
| 2017-18 | 20 | 20.081 | +0.081 |
| 2018-19 | 20 | 19.816 | -0.184 |
| 2019-20 | 21 | 21.735 | +0.735 |
| 2022-23 | 15 | 15.168 | +0.168 |
| 2023-24 | 20 | 20.613 | +0.613 |
| 2024-25 | 23 | 23.332 | +0.332 |
| 2025-26 | 19 | 19.046 | +0.046 |

Summary:

- fractional MAE: **0.385 weeks**
- median absolute error: **0.332 weeks**
- bias: **+0.208 weeks**
- maximum absolute error: **0.788 weeks**
- >1-week false-early detections: **0/11**
- >2-week false-early detections: **0/11**

Aggregate LOSO parameter summary:

- `use_cls = FALSE`
- `w_min = 1`
- `w_max = 26`
- `K_sum = 5`
- `p_sum_thr = 0.075`
- `p_thr = 0.002`
- `prev_thr = 0.001`
- `n_consec = 5`
- `L = 2`
- `N_req = 4`

## Current 2026-27 weekF11 result

Applying the aggregate no-gate early-safe M0-v2 specification to the fully refreshed weekF11 A history gives **no ignition yet**.

This is now signal-based rather than calendar-based:

- weekF11 A positivity: 1.7427%
- 5-week positivity sum: 0.06203
- required accumulation threshold: 0.075
- smoothed positivity gate: pass
- cumulative prevalence gate: pass
- sustained trend gate: pass
- accumulation gate: fail
- total active evidence votes: 3/4
- ignition: false

Therefore the current season remains pre-ignition at weekF11 under the redesigned gate-free detector, but it is free to ignite before week 13 if future data satisfy all four epidemiologic gates.

## Remaining promotion check

The M1-v2 governed nested replay must be rerun using this M0-v2 artifact/grid as its activation source. M0-v2 should not be promoted into the M1-v2 governed stack until M1 timing and passage metrics remain acceptable under the new activation distribution.
