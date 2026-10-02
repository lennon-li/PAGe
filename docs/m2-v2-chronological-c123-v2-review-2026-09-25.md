# M2-v2 chronological C1/C2/C3 v2 review — 2026-09-25

## Disposition

**PASS for promotion of fixed C2 to the current research M2-v2 curve family.**

This is not production-runtime approval. Production remains blocked on governed artifact/runtime packaging, a finalized denominator-regime observation model, and stabilization/versioning of the provisional B timing gate.

The prior review in `docs/chronological-c123-audit-2026-09-24.md` is retained as historical evidence of an earlier draft. Its reported A/B `rbind` defect was fixed before the current v2 replay; the present script reruns successfully with exit 0.

## Reviewed implementation

Script:

`scripts/run_m2_ab_curve_ratio_chronological_c123_v2.R`

Artifacts:

`artifacts/m2-v2-ab-curve-ratio-chronological-c123-v2/`

The replay was rerun by the parent after review changes and exited 0.

## Prior-only exclusion contract

For target season `s`, `prior` is exactly the chronologically earlier target-season set.

Verified:

- type-specific state/growth baselines fit only prior seasons;
- C1/C2/C3 family selection uses inner leave-one-prior-season-out shape reconstruction;
- A prior-stage M0 LOSO, M1 library, and scalar timing calibration use prior seasons only;
- target A M0 classifier and detector tuning use prior seasons only;
- target expert ignition information is present solely for retrospective evaluation output and is not consulted by the detection gates;
- B timing library uses prior completed B seasons only;
- B gate and posterior use only the target prefix through the forecast origin;
- target outcomes enter only after prediction for scoring.

The M0 candidate grid is now read directly from `.default_m0_grid()`. The previously referenced all-season replay grid was verified identical to this 36-row package default before that dependency was removed.

## Explicit small-history behavior

- Fewer than 3 prior seasons: learned forecast unavailable and reported explicitly.
- 3 prior seasons: state/growth baseline available, no shape family.
- 4 prior seasons: family selection available, but governed A timing remains unavailable.
- Governed A timing begins with 5 prior seasons because prior-only inner M0 LOSO is rank-deficient with fewer seasons.

No later seasons are borrowed to fill these gaps.

## B causal gate review

The B activity gate is:

- origin/week >=18;
- trailing four-week B positive count >=40;
- trailing four-week maximum B positivity >=5%.

The underlying B series is week-dense in every reconstructed season: all 1,126 within-series `diff(weekF)` values equal 1. Therefore the trailing four rows are exactly trailing four calendar weeks.

B timing is deliberately sparse under this conservative gate. That is treated as abstention, not missing scoring data.

## Hard fallback invariants

Current chronological bundle:

- B +1 rows: 313; exact-baseline violations: **0**.
- timing-unavailable rows: 735; exact-baseline violations: **0**.
- family-unavailable rows also return exact baseline.

The script contains stop assertions for these identities.

## Training-only family-selection evidence

Chronological family selection:

- 2012-13, 2013-14, 2014-15: insufficient history;
- 2016-17: baseline available, fewer than four priors for family selection;
- 2017-18: C2;
- 2018-19: C3, narrowly over C2 (inner RMSE 0.11637 versus 0.11690);
- 2019-20: C2;
- 2022-23: C2;
- 2023-24: C2;
- 2024-25: C2;
- 2025-26: C2.

C2 is selected in 6 of 7 selectable chronological targets, and C1 is selected in none.

Exchangeable training-only selection had previously chosen C2 in all 11 outer folds.

## Fixed-C2 chronological evidence

Runtime research packaging freezes C2 rather than carrying the family selector. The current script therefore emits a separate fixed-C2 evidence bundle.

Season-balanced service-wide metrics:

| Type | Horizon | Baseline MAE pp | Fixed C2 MAE pp | Relative MAE gain | Better / worse seasons |
|---|---:|---:|---:|---:|---:|
| A | +1 | 0.96325 | 0.95137 | 1.23% | 4 / 2 |
| B | +1 | 0.32536 | 0.32536 | 0% | 0 / 0 |
| A | +2 | 1.83805 | 1.71398 | 6.75% | 6 / 0 |
| B | +2 | 0.54092 | 0.48838 | 9.71% | 2 / 0 |

NLL also improves slightly in every active aggregate cell and is unchanged for B +1.

When restricted to rows/seasons where a timing correction can actually be active:

- A +1: ~2.5% MAE improvement; 4 seasons better, 2 worse;
- A +2: ~10.4% improvement; 6/6 active seasons better;
- B +2: ~32.2% improvement; 2/2 active seasons better.

A +1 is the principal robustness watchpoint. Fixed C2 worsens 2018-19 slightly and 2025-26 more materially. There is no monotonic late-era degradation: 2024-25 improves, and A +2 improves in every timing-active season.

## Denominator-regime disposition

Historical rows use `historical_shared_flu_test_proxy`; 2025-26 uses `orvt_type_specific`.

The current state/growth baseline does not fit a denominator-regime factor. This avoids attempting to estimate an unseen 2025-26 factor level from historical-only training. Current level is the offset/amplitude anchor and curve correction is a relative drift.

This is acceptable for the **research** comparison, with denominator regime retained as provenance. It is not a finalized production likelihood. Production promotion still requires an explicit decision on overdispersion/measurement-regime treatment.

In 2025-26 B timing never activates, so B predictions remain exactly B1 through the modern denominator transition.

## Independent audit

A workspace-relative read-only Opencode audit completed with exit 0 and a final **PASS**. It independently verified:

1. prior-only exclusions for all learned components;
2. A M0/M1/calibration chronology;
3. causal B prefix usage;
4. nested prior-only family selection;
5. B +1 exact fallback;
6. timing-unavailable exact fallback;
7. no target-outcome leakage;
8. safe research handling of the unseen modern denominator regime;
9. explicit early-history unavailable states.

## Decision

Promote **fixed C2** to the current **research M2-v2 curve family**.

Do not carry the C1/C2/C3 selector into runtime. C1 and C3 remain ablation/evaluation comparators.

Current routing target for research packaging:

- A +1/+2: type-A state/growth baseline plus C2 correction only when governed A timing is valid;
- B +1: exact B1;
- B +2: exact B1 unless the reviewed B activity gate is active and valid B soft timing is available, then apply C2;
- any invalid/unavailable timing: exact type-specific baseline;
- A timing must never substitute for B timing.

Production runtime remains disabled until the research artifact is fully identity-bound and its remaining governance blockers are resolved.
