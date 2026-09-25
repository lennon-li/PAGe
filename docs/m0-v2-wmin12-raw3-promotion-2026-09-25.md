> **Superseded:** this strict non-decreasing raw-3 policy was replaced the same day by the 1-SE noise-tolerant persistence policy documented in `m0-v2-wmin12-raw3-se1-promotion-2026-09-25.md`. The strict artifact is retained only as an experiment/comparator.

# M0-v2 week-12 + raw-3 persistence promotion — 2026-09-25

## Decision

Promote the new M0-v2 pipeline policy from a hard lower eligible week of 13 to:

- `use_cls = FALSE` explicitly;
- `w_min = 12`;
- `raw_nondec_n = 3` as a mandatory causal persistence safeguard;
- otherwise retain the validated 36-spec classifier-free threshold grid and `w_max = 26`.

The raw-persistence safeguard requires the latest three observed weekly positivities to be non-decreasing. It is mandatory in addition to the existing N-of-4 evidence rule; it is not an additional interchangeable vote.

Low-level detector/tuner fallbacks remain backward compatible: callers that omit `raw_nondec_n` receive `1`, which disables the new safeguard. The promoted pipeline defaults set it explicitly to `3`.

## Why not simply change 13 to 12?

A strict nested LOSO replay with only `w_min: 13 -> 12` was unsafe. The 2017-18 holdout fired at integer week 12 (fractional 11.11) versus expert ignition 19.2, producing a ~7-8 week false-early error. The season contained a short early influenza-A surge that satisfied the existing accumulation/level/prevalence/trend gates but then receded.

A fully gate-free `w_min = 1` version was also unsafe without additional protection, and explicitly enabling the classifier did not eliminate the 2017-18 failure. The classifier therefore remains disabled.

The raw-3 persistence condition directly targets this causal failure mode without reintroducing a later calendar veto. At every historically validated ignition point in the 11-season campaign, the most recent three raw weekly positivity values are non-decreasing.

## Strict LOSO M0-v2 result

Replay:

`scripts/run_m0_v2_wmin12_raw3_loso_v1.R`

Artifacts:

`artifacts/m0-v2-wmin12-raw3-decimal-loso-v1/`

Held-out result:

- 11/11 seasons detected;
- fractional MAE: **0.366140 weeks**;
- median absolute error: **0.316131 weeks**;
- bias: **+0.039829 weeks**;
- maximum absolute error: **0.911042 weeks**;
- >1-week false-early detections: **0/11**;
- misses: **0**.

The held-out integer ignition weeks are exactly identical to the validated `w_min = 13` M0-v2 baseline for all 11 seasons. Fractional estimates differ only at floating-point noise (`max abs difference ~= 4.6e-14`).

Aggregate promoted parameters:

- `use_cls = FALSE`;
- `cls_thr = 0.26` retained only as inert provenance;
- `p_thr = 0.002`;
- `prev_thr = 0.001`;
- `p_sum_thr = 0.06`;
- `eps = 0`;
- `n_consec = 5`;
- `L = 2`;
- `K_sum = 5`;
- `raw_nondec_n = 3`;
- `N_req = 4`;
- `w_min = 12`;
- `w_max = 26`.

## Fractional timing contract fix

The fractional M0-v2 interpolation layer now clamps `iWeek_hatF` to the detector's declared `[w_min, w_max]` eligibility window. Previously an integer detection at the lower boundary could interpolate to a fractional value before the eligible window. This is a contract fix; it does not alter the accepted week-12/raw-3 historical replay because all accepted detections are already inside the window.

## Governed M1-v2 downstream replay

Replay:

`scripts/replay_m1_v2_governed_nested_m0_wmin12_raw3.R`

Artifacts:

`artifacts/m1-v2-governed-nested-m0-wmin12-raw3-replay/`

The downstream governed M1-v2 result is numerically identical to the original governed replay:

- active integer peak metric: **1.373248**;
- native decimal peak metric: **1.246155**;
- raw native decimal metric: **1.349451**;
- primary origins: **103**;
- passage false-early: **0/11**;
- passage confirmed by peak+2: **10/11**;
- mean passage delay among confirmations: **0.8 weeks**;
- median delay: **0.5 weeks**;
- same single +2 passage miss: 2012-13.

All 119 M1-v2 per-origin runtime rows match the prior governed replay numerically. Nested M0 activation-origin integers are identical. A few inner cross-fit decimal activation coordinates differ modestly (maximum ~0.36 weeks), but no nested activation is near the new lower boundary (minimum decimal activation 14.74), and M1-v2 outputs are unchanged.

## Current 2026-27 weekF11 state

Current diagnostic artifacts:

`artifacts/m0-v2-wmin12-raw3-current-2026-27-week11/`

Using the fully refreshed weekF11 A history:

- weekF11 A positivity: 1.7427%;
- 5-week positivity sum: 0.06203 vs threshold 0.060: pass;
- smoothed positivity: pass;
- cumulative prevalence: pass;
- sustained smoothed trend: pass;
- four evidence votes active: 4/4;
- raw-3 persistence: **fail** because weekF11 is slightly below weekF10;
- eligible-week condition: **fail** because current origin is week 11 and `w_min = 12`;
- ignition: **not declared**.

Because weekF10 positivity (1.8482%) exceeds weekF11 positivity (1.7427%), the three-week non-decreasing condition cannot be satisfied at weekF12 regardless of the weekF12 value. For the current season, the earliest possible signal-qualified ignition is therefore weekF13, but this is now a consequence of the observed trajectory rather than a hard week-13 calendar rule.

A full-history M1-v2 shadow stage trained only through 2025-26 has been built at:

`artifacts/m1-v2-wmin12-raw3-full-history-v1/`

Artifact ID:

`a542e264450de2624c9375925f792338c26d9e4de0f80aebfbcecf8432fff2e2`

At weekF11 this stage returns `pre_ignition` and a pre-ignition M2 handoff. No peak timing is fabricated.

## Tests and compatibility

Focused M0-v2 persistence/default/timing-window tests pass. Existing LOSO fold-parallel tests also pass. All 76 package R files parse.

Formal installed-package checks remain partially blocked by the workstation's known stale package/dependency environment; source-level tests, strict replay artifacts, and direct runtime checks are authoritative for this branch.

## Operational boundary

This change updates the new/shadow M0-v2 policy and training defaults. It does not mutate the frozen 2026-27 production kit in place. The frozen kit remains an immutable comparator until a separately governed shadow-kit refresh is explicitly promoted.
