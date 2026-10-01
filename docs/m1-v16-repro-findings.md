# Findings: v16 M1 alignment reproduction and soundness audit

Date: 2026-09-19. Verification only; no model code changed, nothing committed.
Artifacts under `/home/yeli/PAGe-bcc-artifacts/` were read only.

All numbers below were computed independently from the artifacts and
`/home/yeli/FLU/flu_testing_data_orvt_20260916.csv`. Raw surveillance rows are
not quoted.

## Bottom line

**The v16 comparison does not collapse for the reason the brief suspected.** The
10-season cache is genuine leave-one-season-out, not in-sample, and the current
run is also LOSO. The regression is real and directionally robust: v16 beats the
current run in 9 of 10 shared seasons under every truth convention tested, by a
factor of 3.7x to 4.3x.

**But the two headline numbers are not cleanly comparable as stated.**

1. The current number, **2.912**, is an **11-season** mean; v16's **0.766** is a
   **10-season** mean. On the 10 shared seasons the current run is **2.854**
   (ratio 3.73x, not 3.80x). The retune plan's §0 table lists only the 10 shared
   seasons but quotes the 11-season mean in the same paragraph (see Task 3).
2. **0.766 and 2.912 are computed on parabolic-decimal truth**, including for
   seasons the plan and the brief declare to be **interval** truth. Under the
   brief's own declared truth the pair is **0.640 vs 2.736** (10 seasons); under
   the retune plan §1.1 truth it is **0.635 vs 2.731**. The ratio survives; the
   quoted values do not (see Task 2).
3. The two sides also differ in M1 configuration (v16 `k_ref=25,
   slope_weight=8`, legacy integer timing; current `k_ref=30, slope_weight=16`,
   fractional timing), in end-of-season origin cutoff, in `anchorWeek`, and in
   input-data vintage. None of these invalidates the regression, but they mean
   the "0.766 vs 2.912" contrast is not the controlled comparison it appears to
   be.

## Task 1 — artifact audit

The artifact loads cleanly. `params_df` is 334 rows x 19 columns over 10
seasons; `forecast_df` is 46,371 rows; `ref_list` has one reference per test
season.

| check | result |
|---|---|
| `tau, delta, a, b, t_peak, t_peak_lo, t_peak_hi, peak_weekF` finite | clean: 0 NA / 0 NaN / 0 Inf in every column |
| `eval_week` contiguous per season | clean: 0 gaps, 0 duplicates, 0 out-of-order; each season is exactly `min..max` |
| `n_obs` tracks `eval_week` | `n_obs == eval_week` for all 334 rows |
| `anchorWeek` constant | 19 for every row of every season |
| `forecast_df` coverage | complete: 334/334 `(season, eval_week)` keys present, 0 missing, 0 extra |
| `iWeek_hat` / `iWeek_true` | constant within season; `iWeek_hat - iWeek_true` is 1 in 9 seasons, 2 in 2023-24 |
| `peak_passed` TRUE→FALSE reverts | **1 event** (2024-25, origin 38; TRUE at 37, FALSE at 38, TRUE again from 39) |
| `fallback_reason` | **24 of 334 rows (7.2%)** flagged `delta_unstable_profile`; 310 NA |

Fallback detail: all 24 fallback rows still have finite `tau/a/b/peak_weekF`
(the flag does not mean a failed fit) and all 24 have `peak_passed = TRUE`.
They are late-season: 2013-14 has 17 of its 33 origins (51.5%) flagged, 2018-19
5, 2012-13 1, 2024-25 1. So the cache is not fallback-driven in aggregate, but
2013-14 — the season with the largest v16 peak error — is half fallback.

### Anomalies found (none fatal, but worth recording)

- **`t_peak_hi < t_peak` in 96 of 334 rows (29%)**, by up to 0.027 weeks. The
  point estimate (weighted mean of per-template peaks) is allowed to exceed the
  upper weighted quantile, so the "CI" does not bracket its own point estimate.
  Magnitude is small, but `peak_weekF_lo/hi` are not guaranteed to bracket
  `peak_weekF`.
- **`p_hat > p_hi` in 9,372 of 34,402 forecast rows (27%)**, by at most 0.0084.
  Same cause: `p_hat` is the logit-scale weighted mean, `p_lo/p_hi` are weighted
  quantiles of a nearly degenerate distribution.
- **`iWeek_true` is a shifted copy of the ignition label, not independent
  truth.** It equals `canonical manual label - 1` for all 10 seasons (e.g.
  2012-13 stored 17 vs canonical 18), while `iWeek_hat` equals the canonical
  label in 9 of 10. This is the intentional "−1L offset" noted in
  `scripts/fresh_run/03_m1_loso.R:6-8`, but it means the artifact's `iWeek_true`
  column is not ground truth and should not be used as such. It does not affect
  `peak_weekF`.
- **Observed `p_hat` does not match the current surveillance CSV for 21% of
  observed rows** (2,569 of 11,969), by up to 2.08 pp (median difference 0). The
  weekF mapping is verified correct (the CSV's `weekF` reproduces
  `load_allD`'s `((week-27) %% nW_true)+1` exactly, and shift tests at ±1 make
  the agreement far worse), so this is a **data-vintage difference** between the
  cache's April snapshot and the September CSV, not a mapping error. It matters
  for Task 4.
- **`params_df` has no `t_peak_median` column**, while current
  `loso_walkforward()` emits one. The cache predates commit `00ab9b4`
  ("propagate t_peak_median...", 2026-04-16).
- `t_peak_lo`/`t_peak_hi` carry a `names` attribute whose order does not match
  the season column. This is benign: the names are the training-template season
  that supplied each weighted quantile (`.weighted_quantile()` preserves
  `names(x)[idx]`), and every name is a valid member of the 10-season set.

### `p_hat` vs the `eta` formula

The brief asks whether `forecast_df$p_hat` agrees with
`eta = a + b*g((t-tau)/(1+delta))` from `params_df`. It does not agree exactly,
and it should not: the cache is a **multi-template ensemble**, so `p_hat` is the
weighted logit mean of several per-template curves while `a, b, tau` are
weighted averages of per-template parameters and `g_ref_fun` is an aggregate
reference. Using the aggregate parameters, median `|p_hat - plogis(eta)|` is
0.0033, 65% of rows agree within 0.01 and 88% within 0.05, max 0.46. This is
consistent with the ensemble construction, not evidence that the two tables came
from different runs. A cleaner cross-check (observed `p_hat` vs CSV) is the
data-vintage point above.

## Task 2 — recomputing the headline comparison

I recomputed peak truth from the CSV with `p = pos_flua / test_flu` and
three-point parabolic interpolation about the argmax. All nine non-interval
truths reproduce the brief exactly: 2014-15 26.800, 2016-17 28.114, 2017-18
32.155, 2018-19 31.051, 2019-20 28.814, 2022-23 21.020, 2023-24 25.902, 2024-25
32.049, 2025-26 25.023. The two interval seasons give parabolic decimals 26.458
(2012-13) and 27.276 (2013-14).

Taking each season's last `peak_weekF` from v16 and each season's last non-NA
`peak_weekF_origin` from the current `training_rows`:

| truth convention | v16 (10 seasons) | current (10 shared) | current (11 seasons) | ratio (10 shared) |
|---|---:|---:|---:|---:|
| parabolic decimal (all) | **0.7665** | **2.8545** | **2.9112** | 3.72x |
| brief intervals (2012-13, 2013-14) | 0.6399 | 2.7364 | 2.8038 | 4.28x |
| plan §1.1 intervals (+2024-25, 2025-26) | 0.6350 | 2.7314 | 2.7105 | 4.30x |

- **Yes, I get 0.766 and 2.912 — but only in the first row**, i.e. treating the
  interval seasons as their parabolic decimals and taking the current mean over
  all 11 seasons.
- Under interval truth, which both the brief's table and the plan §1.1 declare
  authoritative, the v16 number is **0.640–0.635**, not 0.766, and the current
  10-season number is **2.736–2.731**, not 2.854.
- v16 is better in **9 of 10** seasons under all three conventions, so the
  direction is robust.

Two mechanical caveats on the current side:

- A literal reading of "each season's last `peak_weekF_origin`" returns `NA` for
  10 of 11 seasons (the last origin per season has no available forecast). The
  2.912 figure requires "last **non-NA**", which is the last origin with an
  available alignment forecast (eval weeks 42–51 depending on season), not the
  last origin of the season.
- `training_rows$peak_weekF_origin` equals `m1_train_preds$peak_weekF` exactly
  (319/319 shared keys), so either column is a valid current-side source.

## Task 3 — is the comparison fair?

**The brief's central hypothesis is refuted: v16 is not in-sample.**

- `n_train` is **9 for every row of every season**, out of 10 total seasons.
- `ref_list` has one reference per test season, and for each, `ref$dat` contains
  exactly the other 9 seasons — the target season is never present. E.g. the
  reference for held-out 2013-14 contains 2012-13, 2014-15, 2016-17 … 2024-25
  and not 2013-14.
- This matches `loso_walkforward()`'s construction (`tr_seasons =
  setdiff(all_seasons, test_s)`, `m1_loso.R:284-288`).

So the 10-season cache is genuine leave-one-season-out. The current run is also
LOSO: `m2_subset_make_rows()` builds per-season held-out references via
`.m1_heldout_references()` (`m2_subset_correction.R:957, 876-910`), which
explicitly excludes each target season and asserts it is absent from `ref$dat`.
The comparison is therefore LOSO vs LOSO, and the 3.8x claim does **not**
collapse as "in-sample vs out-of-sample".

The comparison is nonetheless not controlled, for these reasons:

1. **Season-set mismatch (headline only).** v16 has no 2025-26; the current
   number includes it. The retune plan §0 tabulates the 10 shared seasons (its
   per-season current errors reproduce mine: -2.29, +5.30, +4.01, +3.62, -3.06,
   -3.40, -1.40, -2.02, +2.97, -0.48) yet quotes 2.912, which is the mean over
   11 seasons. The 10-season mean of that very table is 2.854. The plan's own
   Gate V is defined on the 10 shared seasons, so 2.912 is inconsistent with the
   gate it anchors.
2. **Truth-convention mismatch.** As in Task 2, the headline uses parabolic
   decimals for seasons declared to be interval truth.
3. **M1 configuration mismatch.** v16's winning spec is `k_ref=25,
   slope_weight=8` (legacy integer timing, `anchorWeek=19`); the current run
   selected `k_ref=30, slope_weight=16` with fractional timing and
   `anchorWeek=20.5`. The plan argues the 20-spec grid spans only 0.293 weeks
   and so cannot explain a 2.15-week gap — but that flatness was measured under
   **v16 code**. Under current code the same spec change moves the final peak by
   up to 3 weeks on the two seasons I tested (Task 4), so the refutation does
   not transfer.
4. **End-of-season cutoff mismatch.** v16's "last" origin is eval week 52 (53 in
   2014-15). The current run's eval weeks stop at 51 or 52 (52 only for 2014-15
   and 2025-26), and its last *available* origin is week 42–51. The final
   estimate is being read at different points of the season.
5. **Data vintage.** The cache's observed series differs from the September CSV
   in 21% of observed rows (Task 1).

`eval_week` vs `eval_weekF`: the same quantity. The CSV's `weekF` reproduces
`load_allD`'s convention exactly, both artifacts use it, and both ranges sit on
the same in-season scale (v16 15–53, current 16–52). `peak_weekF` is also on the
same calendar in both (both track the truth table), but v16 rounds to integer
while the current value is fractional. "Last origin per season" does **not** mean
the same thing (point 4).

### The genuinely prospective, n=1 comparison the brief requested

Using v16's 2025-26 holdout (`fresh_deploy_wf_cache.rds`, final `peak_weekF` =
**25**, all 23 origins; `iWeek_hat = 19`) against the current run's 2025-26
final available `peak_weekF_origin` = **28.50**:

| truth for 2025-26 | v16 err | current err |
|---|---:|---:|
| parabolic 25.023 | 0.023 | 3.478 |
| interval [25, 26] | 0.000 | 2.502 |

**n = 1**, and the deploy cache has a different schema (no `n_train`,
`fallback_reason`, `t_peak_lo/hi`), so this corroborates the direction but
cannot carry a ratio. It is the only genuinely prospective v16 evidence.

## Task 4 — reproduction with current code + v16 configuration

Because Tasks 1–3 surfaced anomalies, this is reported as a bounded probe, not a
clean reproduction.

I ran current working-tree code (`devtools::load_all("PAGe")`) through
`loso_walkforward()` with v16's configuration for two seasons (2013-14,
2019-20): `k_ref=25`, `slope_weight=8`, `slope_window=6`, legacy timing,
`buffer_weeks=5`, `k_deriv=20`, `peak_weight_boost=3`, v16's M0 `best_params`,
and `manual_labels = canonical - 1` (matching the cache's `iWeek_true`).

- The ignition input matches exactly: `iWeek_hat` and `iWeek_true` are identical
  to the cache for both seasons (20/19 and 22/21).
- **The alignment does not reproduce.** Max `|Δpeak_weekF|` is 5 weeks
  (2013-14) and 3 weeks (2019-20); only 6/33 and 11/31 origins match exactly;
  max `|Δtau|` is 3.8 and mean `|Δtau|` 1.3–1.9. At the final origin 2013-14
  gives 31 vs v16's 28, and 2019-20 gives 28 vs 27.

This is the "wildly different" outcome, not a configuration difference — but it
is **confounded by the input-data vintage**: v16's `data/flu_testing_data.csv`
is absent from the repository, so I used the September ORVT CSV, which differs
from the cache's observed series in 21% of rows. I could not separate a code
change from a data revision.

One useful side result, which undercuts a premise of the plan rather than of the
brief: under **current code**, changing the spec from v16's 25/8 to the current
run's 30/16 moves the final peak by 1–3 weeks (2013-14: 31 → 29; 2019-20: 28 →
27; max per-origin 3 and 1). So the plan's argument that "the grid spans only
0.293 weeks, therefore the pin is not the cause" is a v16-code measurement and
does not hold under the code now in the tree.

## What I could not check, and why

- **Exact v16 inputs.** `data/flu_testing_data.csv` (the April snapshot used by
  the fresh-run scripts) is not in the repo and the `data/` directory does not
  exist, so Task 4 is confounded by data vintage. I could not locate the script
  that wrote `align_multi_cache.rds`; the repo's `scripts/fresh_run/03_m1_loso.R`
  produces the tuning grid, not this cache.
- **A clean isolation of code vs configuration vs timing mode.** My legacy-timing
  reproduction and the current fractional-timing run differ by up to 4.6 weeks on
  2013-14, but that difference also folds in labels, `anchorWeek`, M0 params and
  data vintage.
- **Full 11-season reruns.** Task 4 was time-boxed to two seasons.

## Confidence

- Task 1 audit: high (direct computation over the whole artifact).
- Task 2 reproduction of 0.766 / 2.912: high, including the finding that both
  depend on a truth convention the documents contradict.
- Task 3 "not in-sample": high (ref contents and `n_train` are decisive).
- Task 3 residual unfairness: high on season-set, cutoff and config differences;
  medium on how much each contributes to the gap.
- Task 4: medium. The non-reproduction is clear, but the data-vintage
  confounder prevents attributing it to code alone.
