# Argie Survey Packet — M1 peak-accuracy regression, v16 vs current

From: Ming (Claude Code, asgard)
To: Argie / Antigravity

## Objective

One question: **what structural change between the v16-era M1 and the current
M1 accounts for a 3.8x regression in peak accuracy?**

| | v16 | current |
|---|---:|---:|
| mean abs final peak error, 10 shared seasons | **0.766 wk** | **2.912 wk** |
| seasons where v16 is better | — | 9 of 10 |
| state un-latch events | 1 | 6 of 11 seasons |

This is diagnosis. Do not repair, tune, or "improve" M1.

## What has already been ruled out — do not re-test

Four hypotheses are dead. Re-testing any of them is wasted budget.

1. **`LAMBDA_DELTA` scale bug** (documented 0.20, actual 164,672.9, forbidding
   dilation). Refuted three times, most recently by direct artifact read: v16
   has `delta_on = TRUE` on 169 of 334 origins, `allow_scale = TRUE` on 324,
   and fitted `delta` in `[-0.0061, +0.0127]`. v16 had the identical crushed
   dilation and scored 0.766 anyway.
2. **D-32** (2026-09-15 pin of `k_ref` 25->30, `slope_weight` 8->16). v16's
   full 20-spec grid is on disk: the pin costs 0.050 wk against the optimum and
   the entire surface spans 0.293 wk, against a 2.15 wk regression.
3. **v16's other fixed settings.** v16's grid records `multi_temperature=0.25`,
   `template_shift=0`, `align_rise_weight=1`, `slope_window=6`. Every one
   matches the current default in `PAGe/R/pipeline_training.R:179-182`.
4. **`peak_decay`** (0.3). Not in v16's grid, but it appears in
   `align_forecast_pipeline_dilate.R`, a v16-era path, so it almost certainly
   existed at the same value.

**Configuration is therefore closed as a class.** Every axis visible in v16's
tuning artifact matches current. The cause is structural — code or pipeline.
Treat the ordering below as suspicion, not conclusion; two earlier confident
hypotheses were refuted on artifact evidence.

## Scan boundary

Root: `/home/yeli/repos/PAGe`

Included, in source-priority order:

1. `PAGe/R/m1_multi_template.R` — **primary suspect**, especially lines
   288-301. The ensemble peak is a weighted mean of per-template peaks and its
   CI an upper weighted quantile of the same. An earlier task localised a
   week-to-week oscillation here: 2013-14 produced consecutive-origin peak
   estimates of 24.7 -> 33.1 -> 24.7 -> 32.6.
2. `PAGe/R/m1_fit.R`, `PAGe/R/m1_peak_status.R`, `PAGe/R/m1_hyperparams.R`
3. `PAGe/R/m1_loso.R`, `PAGe/R/pipeline_training.R`
4. `PAGe/R/align_forecast_pipeline_dilate.R` — the v16-era path; comparing it
   against the current multi-template path may be the fastest route to the
   delta.

Read-only reference artifacts under
`/home/yeli/PAGe-bcc-artifacts/seasonal-archive-20260818/_shared/`:

- `data/align_multi_cache.rds` — `params_df` (334 rows x 19 cols, 10 seasons,
  per-origin `tau, delta, a, b, t_peak, t_peak_lo, t_peak_hi, peak_weekF,
  peak_passed, fallback_reason, n_train, anchorWeek`); `forecast_df` (46,371
  rows); `ref_list`.
- `data/fresh_m1_alignment_tuning_v7.rds` — the 20-spec grid (`$results`,
  `$grid`).
- `data/fresh_deploy_wf_cache.rds` — 2025-26, v16's **holdout**. Single season.
  Generalising from it produced a wrong conclusion once already. Use the
  10-season cache for any claim.

Current side:
`results/final-kit-2026-27/20260918T1520Z-final-2026-27-wmin8-venkata/artifacts/m2_tuning.rds`
(`m1_train_preds`, `training_rows` — the latter has `tau, d,
peak_weekF_origin`).

Excluded — touching these is a hard failure:

- `PAGe/R/m2_subset_correction.R` and `manuscript/**` (another agent owns them)
- anything under `/home/yeli/PAGe-bcc-artifacts/` for writing

Stop condition: you have either named a minimal change set with measured
evidence, or established that the evidence does not identify one.

## Specific questions

1. **Does the current multi-template peak derivation differ structurally from
   what v16 ran?** Compare the ensemble peak/CI construction against
   `align_forecast_pipeline_dilate.R`. Is the weighted-mean-of-peaks reduction
   new? An earlier single-template or argmax-based derivation would explain
   both the oscillation and the accuracy loss.
2. **`tau` anchor.** v16's `tau` sits between about -5 and -0.2; current
   saturates at exactly 6.0 on many origins. v16's `anchorWeek` is **19,
   constant across all 10 seasons** (verified). Establish whether current uses
   the same anchor convention before calling saturation a defect — a
   reparameterisation would explain it innocently. If the anchors do match, a
   hard bound being hit on many origins is a strong lead.
3. **`buffer_weeks`.** `pipeline_training.R:710` passes `5L` while every other
   path defaults to `0L`. Which produced the current artifacts, and which
   produced v16's? This is cheap to check and is a candidate un-latching cause.
4. **M0 ignition input.** v16 records `iWeek_hat` and `iWeek_true` per origin.
   Compare against current ignition. If ignition moved, M1 inherits the error.

## Known traps

- `run_2025_cycle.R` uses `devtools::load_all("PAGe")`, so **the working tree
  runs**, not the installed library. A previous session lost a day to this.
- Authoritative positivity is `pos_flua / test_flu` (`realtime_sources.R:155-156`),
  **not** the CSV's `fluAPercentPositive`, a different quantity differing by up
  to 0.13 pp. Using the wrong field has already caused one defect.
- Surveillance data is private (`/home/yeli/FLU/flu_testing_data_orvt_20260916.csv`):
  do not copy it, do not quote raw rows.
- v16 is **not** better on amplitude. Its `a` reaches 6.441 and max forecast
  0.9871 — the same pathology as current. Amplitude is governed separately and
  is not part of this regression.
- v16's 10-season cache is genuinely leave-one-season-out (`n_train = 9` on
  every row, verified), so the 0.766 vs 2.912 comparison is fair. 2013-14 is
  the exception worth noting: it fell back on 17 of 33 origins, so v16's number
  there is fallback-driven.

## Authorization

~~~text
Permission Level: 2
Interaction Mode: AUTONOMOUS
Authorization: READ-ONLY, plus ONE write path
~~~

Step budget: **60 tool calls.** Stop and report on exhaustion — a partial
report against budget is the expected outcome, not a failure.

Allowed:

- read any file in the scan boundary
- run read-only R (`Rscript -e`, `devtools::load_all("PAGe")`) to inspect
  artifacts and to test a hypothesis, reverting each test before the next

Forbidden:

- **any file write whatsoever.** You are running headless and the `write_file`
  permission cannot be prompted for, so any write attempt is auto-denied and
  *discards your entire turn output along with it*. A previous run of this
  packet was lost exactly this way. Do not call `write_file` or `edit_file`.
  Do not write via a shell redirect or heredoc either.
- commit, push, branch, PR; deploy; config change
- tuning runs, sweeps, production changes
- expanding the scan boundary without approval

## Required output

**Print the complete report to stdout as your final message.** It is captured
from there. Do not save it to a file. Structure:

- inspected scope, and explicitly what you did **not** inspect and why
- the minimal change set explaining 0.766 -> 2.912, with the measured effect of
  each change in isolation
- what you tested and ruled out, with numbers — negative results are as
  valuable as positive ones here
- contradictions and unknowns
- anything in this packet you found to be wrong
- recommended next action, and whether it goes to Ming, Jax, Wei, or Lennon

State your confidence. If the evidence does not identify a cause, **say so
plainly** rather than nominating the most plausible candidate. Two confident
hypotheses have already been refuted on this question; a third confident wrong
answer costs more than an honest null.

## Reference

- `docs/m1-retune-plan-2026-09-19.md` (rev 5) — full plan; §0 has the v16 analysis
- `docs/m1-stage1-brief.md` — the longer-form version of this task
- `docs/audits/m1-plan-audit*-sol-2026-09-19.md` — four audit rounds
- `results/m1-diagnosis/TASK_A_report.md`, `TASK_B_report.md`, `TASK_C_report.md`
