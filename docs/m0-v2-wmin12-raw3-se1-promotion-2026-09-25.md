# M0-v2 week-12 + raw-3 + 1-SE persistence promotion — 2026-09-25

## Decision

Promote the current M0-v2 shadow policy to:

- `use_cls = FALSE` explicitly;
- `w_min = 12`;
- `raw_nondec_n = 3` (legacy parameter name retained for compatibility; semantically this is now a three-week persistence window);
- `raw_drop_se_tol = 1.0`;
- otherwise retain the validated 36-spec classifier-free threshold grid and `w_max = 26`.

Within the three-week persistence window, a week-to-week decrease is permitted when it is no larger than one standard error of the difference between the two weekly binomial positivity estimates:

`p_t - p_(t-1) >= - raw_drop_se_tol * sqrt(p_(t-1)(1-p_(t-1))/N_(t-1) + p_t(1-p_t)/N_t)`

This is a mandatory causal stability safeguard in addition to the existing N-of-4 evidence rule. It is not an interchangeable vote.

The classifier remains disabled. `cls_thr` is retained only for compatibility/provenance and does not contribute to `n_hit`.

## Motivation

A strict `w_min: 13 -> 12` change was unsafe: held-out 2017-18 fired at week 12 versus expert ignition 19.2 because a transient early spike satisfied the existing accumulation/level/prevalence/trend gates.

Strict three-week non-decrease eliminated that failure and restored the validated historical result, but it was unnecessarily brittle for surveillance data. Small week-to-week changes can be caused by sampling variation, changing denominators, reporting delay, and retrospective revisions. The 2026-27 weekF10-to-weekF11 change is a concrete example: 1.8482% -> 1.7427%, only -0.446 standard errors after accounting for weekly test volumes.

A reproducible threshold scan (`scripts/evaluate_m0_v2_persistence_tolerance_v1.R`; artifacts in `artifacts/m0-v2-persistence-tolerance-v1/`) found that all 11 historical held-out ignition dates remain unchanged for tolerances from 0 through 3.21 SE. The current weekF10-to-weekF11 decline is -0.446 SE, so a tolerance of at least 0.446 SE is needed to treat the present dip as sampling-scale stability. The joint interval that both preserves all historical ignition dates and tolerates the current dip is therefore approximately **0.446 through 3.21 SE**. The promoted 1-SE tolerance sits comfortably inside that interval.

## Strict LOSO result

Replay:

`scripts/run_m0_v2_wmin12_raw3_se1_loso_v1.R`

Artifacts:

`artifacts/m0-v2-wmin12-raw3-se1-decimal-loso-v1/`

Held-out result:

- 11/11 seasons detected;
- fractional MAE: **0.366140 weeks**;
- median absolute error: **0.316131 weeks**;
- bias: **+0.039829 weeks**;
- maximum absolute error: **0.911042 weeks**;
- >1-week false-early detections: **0/11**;
- misses: **0**.

All 11 held-out integer ignition weeks and all 11 fractional ignition estimates are exactly unchanged from the validated `w_min = 13` M0-v2 baseline (fractional differences are zero at machine precision in the final replay comparison).

Aggregate promoted parameters:

- `use_cls = FALSE`;
- `cls_thr = 0.26` (inert provenance only);
- `p_thr = 0.002`;
- `prev_thr = 0.001`;
- `p_sum_thr = 0.06`;
- `eps = 0`;
- `n_consec = 5`;
- `L = 2`;
- `K_sum = 5`;
- `raw_nondec_n = 3`;
- `raw_drop_se_tol = 1.0`;
- `N_req = 4`;
- `w_min = 12`;
- `w_max = 26`.

## Backward compatibility

Low-level detector/tuner callers that omit `raw_nondec_n` retain historical behavior because the default is `1` (persistence disabled).

When callers set `raw_nondec_n > 1` but omit `raw_drop_se_tol`, the default tolerance is `0`, which reproduces the previous strict non-decreasing persistence rule. The promoted pipeline defaults set `raw_drop_se_tol = 1.0` explicitly.

The stage-contract validator treats `raw_drop_se_tol` as a non-negative standard-error multiplier rather than a probability threshold, so it is not artificially capped at 1.

## Current 2026-27 weekF11 application

Artifacts:

`artifacts/m0-v2-wmin12-raw3-se1-current-2026-27-week11/`

At weekF11 on the fully refreshed current-season A series:

- A positivity: **1.7427%**;
- 5-week positivity sum: **0.06203** vs threshold **0.060**: pass;
- all four non-classifier evidence votes: **4/4**;
- weekF10-to-weekF11 standardized change: **-0.446 SE**;
- current step stable under 1-SE tolerance: **yes**;
- three-week persistence window: **pass**;
- calendar eligibility: **fail** because origin is week 11 and `w_min = 12`;
- ignition: **not declared**.

Unlike the strict monotonicity policy, the current weekF11 decline no longer resets persistence. Week 12 is therefore the earliest possible ignition week if the four evidence votes remain active and the next week-to-week decline, if any, is no larger than the 1-SE tolerance.

At a weekF12 testing volume near 6,500, one SE corresponds to roughly 0.22 percentage points at the current positivity level. With weekF11 at 1.7427%, a weekF12 positivity around 1.52% or higher would approximately satisfy the persistence tolerance; the exact boundary is denominator-dependent.

## Downstream M1-v2

The full-history M1-v2 shadow stage trained only through 2025-26 has been rebuilt from the final 1-SE M0 artifact at:

`artifacts/m1-v2-wmin12-raw3-se1-full-history-v1/`

Artifact ID:

`90f06406dbe3a7d5f190070a5ec7a5c3605d28fe2e7f769609666f92d75d20a5`

At weekF11 it returns `pre_ignition` and a pre-ignition M2 handoff. No peak timing is fabricated.

A governed nested M1-v2 replay using the same final M0 artifact is stored separately at:

`artifacts/m1-v2-governed-nested-m0-wmin12-raw3-se1-replay/`

The downstream result is numerically identical to the original governed replay:

- active integer peak metric: **1.373248**;
- native decimal peak metric: **1.246155**;
- raw native decimal metric: **1.349451**;
- primary origins: **103**;
- passage false-early: **0/11**;
- passage confirmed by peak+2: **10/11**;
- mean passage delay among confirmations: **0.8 weeks**;
- median delay: **0.5 weeks**.

All 119 per-origin numeric M1-v2 outputs match the original governed replay exactly.
