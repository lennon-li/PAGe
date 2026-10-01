# Brief: PAGe M1 Stage 1 — find what regressed between v16 and now

## Objective

M1's peak accuracy has regressed roughly 3.8x. Find the cause. Change nothing
except to test a hypothesis, and revert each test before the next.

| | v16 | current |
|---|---:|---:|
| mean abs final peak error, 10 shared seasons | **0.766 wk** | **2.912 wk** |
| seasons where v16 is better | — | 9 of 10 |
| state un-latch events | 1 | 6 of 11 seasons |

This is diagnosis, not repair. The deliverable is a written finding naming the
minimal change set that accounts for the gap, with evidence. Do not fix it.

## Context

PAGe: M0 (ignition) -> M1 (phase alignment) -> M2 (GAM correction). M1 fits
`eta = a + b*g((t-tau)/(1+delta))` against a reference template on the logit
scale, ensembling several templates.

v16 is a known-good configuration that existed and worked. It is not a
hypothetical better model — its per-origin alignment parameters and forecasts
are on disk.

**Two hypotheses have already been advanced and refuted. Do not re-test them.**

1. **`LAMBDA_DELTA` scale bug** (documented default 0.20, actual 164,672.9,
   which forbids dilation). Refuted: v16 has `delta_on = TRUE` on 169 of its 334
   origins and `|delta|` still maxes at 0.013 — v16 had the same defect and
   scored 0.766 anyway.
2. **D-32**, the 2026-09-15 pin of `k_ref` 25->30 and `slope_weight` 8->16.
   Refuted: v16's full 20-spec grid is on disk; the pin costs 0.050 weeks
   against the optimum and the entire surface spans 0.293 weeks, against a
   2.15-week regression.

The cause is therefore **structural — code or pipeline — not a hyperparameter
value.** Both refutations came from artifact evidence, so treat the ordering
below as suspicion, not conclusion.

## Artifacts

All under `/home/yeli/PAGe-bcc-artifacts/seasonal-archive-20260818/_shared/`:

- `data/align_multi_cache.rds` — **the key artifact.** `params_df` has 334 rows
  across 10 seasons with per-origin `tau, delta, a, b, allow_scale, delta_on,
  t_peak, t_peak_lo, t_peak_hi, peak_weekF, peak_passed, fallback_reason,
  anchorWeek`. `forecast_df` has 46,371 forecast/observed curve rows.
- `data/fresh_m1_alignment_tuning_v7.rds` — v16's 20-spec grid with peak MAE.
- `data/fresh_deploy_wf_cache.rds` — 2025-26 deployment walk-forward. **Caution:
  this is the cleanest single season and generalising from it produced a wrong
  conclusion once already.** Use the 10-season cache for any claim.

Current side: `results/final-kit-2026-27/20260918T1520Z-final-2026-27-wmin8-venkata/artifacts/m2_tuning.rds`
(`m1_train_preds`, `training_rows`).

## Scope

**In:**

1. Reproduce v16's per-season final peak estimates from `align_multi_cache.rds`
   using current code plus v16's configuration, to within 0.01 weeks. **If this
   fails, that is itself the finding** — the difference is in code, not
   configuration, and it localises the search immediately.
2. Bisect the code/pipeline delta, one change at a time, scoring each against
   Gate V (below). Ordered by suspicion:
   - **multi-template peak derivation** (`m1_multi_template.R:288-301`) — the
     ensemble peak is a weighted mean of per-template peaks and its CI an
     upper weighted quantile of the same. Task B localised the week-to-week
     oscillation here (2013-14: 24.7 -> 33.1 -> 24.7 -> 32.6 across
     consecutive origins).
   - **`tau` bounds and anchor** — v16's `tau` sits between about -5 and -0.2;
     current saturates at exactly 6.0 for many origins. Establish whether the
     two are on the same anchor before calling this a defect; a
     reparameterisation would explain the difference innocently.
   - **M0 ignition input to M1** — v16 records `iWeek_hat` and `iWeek_true` per
     origin; compare against current ignition.
   - **template set and `k_ref` construction.**
3. Reconcile `buffer_weeks`: `pipeline_training.R:710` passes `5L` while every
   other path defaults to `0L`. Establish which produced the current artifacts
   and which produced v16's. This may be the un-latching cause and is cheap to
   check.

**Out:**

- No edits to `PAGe/R/m2_subset_correction.R` or `manuscript/**` — another agent
  owns these; touching them is a hard failure.
- No repair, no tuning run, no sweep, no production change, no commits.
- Do not "improve" M1 while you are in there.

## Gate V — the acceptance bar

Any candidate explanation must, when applied, move the measured numbers toward
v16. The standing gate for later stages is: mean abs final peak error
`<= 0.766`, v16 better in `<= 3 of 10` seasons, un-latch events `<= 1`.

For Stage 1 you are not required to reach it — you are required to **explain the
gap**. A finding that identifies the cause without fixing it is a success.

Note: v16 is NOT better on amplitude. Its `a` reaches 6.441 and its max forecast
is 0.9871, same pathology as current. Do not treat amplitude as part of this
regression; it is governed separately.

## Constraints

- Package source under `PAGe/R/` only; no root-level `R/` mirror.
- `run_2025_cycle.R` uses `devtools::load_all("PAGe")`, so **the working tree is
  what runs**, not the installed library. A previous session lost a day to this.
- Surveillance data is private: `/home/yeli/FLU/flu_testing_data_orvt_20260916.csv`.
  Do not copy, commit, or quote raw rows.
- Authoritative positivity is `pos_flua / test_flu` (what PAGe fits on, see
  `realtime_sources.R:155-156`) — **not** the CSV's `fluAPercentPositive`, which
  is a different quantity differing by up to 0.13 pp. Using the wrong one has
  already caused one defect.
- Vectorised R; `data.table` where joins are hot; native pipe; explicit
  `package::function()` in non-trivial paths.
- Treat all archive artifacts as read-only.

## Deliverable

A written report at `docs/m1-stage1-findings.md`:

- whether v16 reproduced, and if not, where it diverged;
- the minimal change set explaining 0.766 -> 2.912, with the measured effect of
  each change in isolation;
- what you tested and ruled out, with numbers — negative results are as valuable
  as positive ones here;
- anything in this brief you found to be wrong.

State your confidence. If the evidence does not identify a cause, say so plainly
rather than nominating the most plausible candidate. Two confident hypotheses
have already been refuted on this question.

## Reference

- `docs/m1-retune-plan-2026-09-19.md` (rev 5) — full plan; §0 has the v16 analysis
- `docs/audits/m1-plan-audit*-sol-2026-09-19.md` — four audit rounds
- `results/m1-diagnosis/TASK_A_report.md`, `TASK_B_report.md`, `TASK_C_report.md`
- `PAGe/R/m1_fit.R`, `m1_multi_template.R`, `m1_peak_status.R`, `m1_hyperparams.R`
