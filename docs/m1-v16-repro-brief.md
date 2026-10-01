# Brief: reproduce v16's M1 alignment and verify it is sound

## Objective

A v16-era M1 artifact is being used as the reference baseline for an entire
workstream. Before that happens, verify it is trustworthy. Two questions:

1. **Is the v16 artifact internally consistent and free of errors?**
2. **Can current code reproduce it, given v16's configuration?**

This is verification, not repair. Report what you find; change no model code.

## Why this matters

The claim resting on this artifact: M1's mean absolute final peak error is
**0.766 weeks in v16** versus **2.912 weeks currently**, a ~3.8x regression.
If that claim is wrong — bad artifact, mismatched harness, wrong comparison —
then a large amount of downstream planning is built on sand. Your job is to try
to break it.

## The artifact

`/home/yeli/PAGe-bcc-artifacts/seasonal-archive-20260818/_shared/data/align_multi_cache.rds`

A 3-element list:

- `params_df` — 334 rows, 10 seasons (2012-13 .. 2024-25, no 2025-26). Columns:
  `season, eval_week, n_obs, iWeek_hat, iWeek_true, tau, delta, a, b,
  allow_scale, delta_on, t_peak, t_peak_lo, t_peak_hi, peak_weekF, peak_passed,
  fallback_reason, n_train, anchorWeek`
- `forecast_df` — 46,371 rows: `season, eval_week, newWeek, p_hat, p_lo, p_hi,
  kind` where kind is "forecast" or "observed"
- `ref_list` — reference templates

Also relevant:
- `data/fresh_m1_alignment_tuning_v7.rds` — v16's 20-spec tuning grid
  (`k_ref` x `slope_weight`) with peak MAE per spec
- `data/fresh_deploy_wf_cache.rds` — 2025-26 only. **This is v16's HOLDOUT
  season.** v16 was trained with 2025-26 held out, which is why
  `align_multi_cache.rds` stops at 2024-25. So this file is the only genuinely
  out-of-sample v16 evidence, and the 10-season cache is v16's training set.
  Treat conclusions from either with care: one is in-sample, the other is n=1.

Current side for comparison:
`results/final-kit-2026-27/20260918T1520Z-final-2026-27-wmin8-venkata/artifacts/m2_tuning.rds`
(`m1_train_preds`, `training_rows`).

## Task 1 — audit the artifact for errors

Check, and report anything anomalous:

- Are all 334 rows well-formed? Any NA/NaN/Inf in `tau, a, b, peak_weekF`?
- Is `eval_week` contiguous within each season? Any gaps, duplicates, or
  out-of-order rows?
- Does `n_obs` track `eval_week` consistently?
- `fallback_reason` — how many origins fell back, and to what? A heavily
  fallback-driven cache would not represent normal M1 behaviour.
- Is `anchorWeek` constant within a season, and the same convention across
  seasons? This matters because `tau` is interpreted relative to it.
- Does `forecast_df` cover every `(season, eval_week)` in `params_df`?
- Do `p_hat` values in `forecast_df` agree with what
  `eta = a + b*g((t-tau)/(1+delta))` implies from `params_df`? Spot-check
  several origins across several seasons. A mismatch means the two tables come
  from different runs.
- `peak_passed` — does it ever revert TRUE -> FALSE within a season? Count
  events.

## Task 2 — verify the headline comparison

Recompute independently; do not trust these numbers:

Peak truth per season, computed from
`/home/yeli/FLU/flu_testing_data_orvt_20260916.csv` using positivity
`p = pos_flua / test_flu` (**not** `fluAPercentPositive`, which is a different
quantity differing by up to 0.13 pp):

| season | truth |
|---|---:|
| 2012-13 | [26, 27] interval |
| 2013-14 | [27, 28] interval |
| 2014-15 | 26.800 |
| 2016-17 | 28.114 |
| 2017-18 | 32.155 |
| 2018-19 | 31.051 |
| 2019-20 | 28.814 |
| 2022-23 | 21.020 |
| 2023-24 | 25.902 |
| 2024-25 | 32.049 |

Non-interval truths come from three-point parabolic interpolation about the
argmax: `delta = 0.5*(v[-1]-v[+1]) / (v[-1]-2*v[0]+v[+1])`, `P = w0 + delta`.

Then: take each season's **last** `peak_weekF` from v16's `params_df` and from
the current `training_rows$peak_weekF_origin`, and compute mean absolute error
against the truth. **Do you get 0.766 and 2.912?**

## Task 3 — is the comparison fair?

This is the part most likely to be wrong, so spend real effort here.

v16's cache covers 10 seasons. The current artifact is an 11-season LOSO run.
Determine whether they are comparable at all:

- **v16 held out 2025-26.** Its 10-season `align_multi_cache.rds` is therefore
  the TRAINING set. The critical question: within those 10, was each season
  predicted leave-one-season-out, or did the fit see all 10 together? `n_train`
  per row should tell you. If it is in-sample, comparing 0.766 against the
  current 11-season LOSO is comparing in-sample to out-of-sample, **the 3.8x
  claim collapses, and you should say so in your first paragraph.**
- If the 10-season cache is in-sample, construct the fair comparison instead:
  v16 on its 2025-26 holdout (`fresh_deploy_wf_cache.rds`, final
  `peak_weekF` = 25 against truth 25.023) versus the current run on 2025-26
  (final `peak_weekF_origin` = 28.50, same truth). Both are genuinely
  prospective. Report that number even though n=1, and label it as n=1.
- Is `eval_week` the same quantity as the current artifact's `eval_weekF`?
  Check the ranges and the season-start convention.
- Is `peak_weekF` on the same calendar in both?
- Does "last origin per season" mean the same thing in both — same number of
  origins, same end-of-season cutoff?

If the comparison is invalid, say so directly. That is the single most valuable
thing you could find, and it is worth more than a successful reproduction.

## Task 4 — reproduce, if 1-3 are clean

Using current package code plus v16's configuration (the winning spec from
`fresh_m1_alignment_tuning_v7.rds`), re-run alignment for two or three seasons
and compare per-origin `tau, a, b, peak_weekF` against v16's `params_df`.

Report the divergence. Exact reproduction is not expected; the question is
whether it is close (a configuration difference) or wildly different (a code
change).

## Constraints

- Read-only on everything under `/home/yeli/PAGe-bcc-artifacts/`.
- Do not edit `PAGe/R/m2_subset_correction.R` or `manuscript/**`.
- Do not commit anything.
- Surveillance CSV is private: do not copy it, do not quote raw rows.
- `devtools::load_all("PAGe")` means the working tree runs, not the installed
  library.

## Deliverable

`docs/m1-v16-repro-findings.md`, covering each task in order, with the numbers
you computed rather than the ones quoted here.

Be explicit about what you could not check and why. If the v16 comparison is
invalid, lead with that. Do not soften a negative finding — a wrong baseline
discovered now saves days.
