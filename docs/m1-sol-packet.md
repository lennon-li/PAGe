# Sol packet — M1 peak regression: identify the cause, and correct the plan

Date: 2026-09-19. You are the adjudicating reviewer. Two workers have reported;
they agree on direction and conflict on mechanism. Ming's own reasoning has been
wrong three times on this question. Assume nothing below is safe.

## The question

M1's mean absolute final peak error regressed from **0.640 wk (v16)** to
**2.736 wk (current)** on the 10 shared seasons under the plan's declared
interval truth; v16 is better in 9 of 10 seasons under every truth convention
tested. **What structural change causes it?**

Secondary, and nearly as important: **which claims in
`docs/m1-retune-plan-2026-09-19.md` (rev 5) must change** given the findings
below? Rev 5 has not yet been audited. Prior revs were rejected four times.

## State of the evidence

### Independently confirmed (computed three times, agreeing)

- v16's 10-season cache is **genuine LOSO**, not in-sample: `n_train = 9` on
  every row, and each `ref_list` entry's `ref$dat` contains exactly the other 9
  seasons. The current run is also LOSO. The comparison does not collapse.
- v16 `peak_passed` reverts TRUE->FALSE exactly **once** (2024-25). Current
  reverts **34 times across 8 of 11 seasons** under the same stateless rule.
- v16 ran `buffer_weeks = 5`: lag from `peak_weekF` to first `peak_passed` is
  exactly 5 in 7 of 10 seasons (6 in two, 7 in one). `pipeline_training.R:710`
  passes `5L`; every other path defaults to `0L`.
- v16's `peak_weekF` is **integer-valued and nearly static** — median
  consecutive-origin jump 0, Q1 0, Q3 0, max 4, never >5 wk. Current is
  fractional, jumps >2 wk ten times as often (9.3% vs 0.9% of transitions),
  >5 wk on 2.1%, max 8.38 wk. Worst season 2013-14, 4.9x v16's mean jump — also
  the season with the largest current final error (+4.60).
- Current error is **bidirectional**, not biased: 2013-14 +4.60, 2014-15 +4.09,
  2016-17 +3.65 against 2012-13 -1.82, 2018-19 -3.58. Variance, not drift.

### Ruled out (do not re-test)

1. **`LAMBDA_DELTA`** (documented 0.20, actual 164,672.9). v16 has the identical
   defect — `delta_on` TRUE on 169/334, `allow_scale` TRUE on 324/334, fitted
   `delta` in `[-0.0061, +0.0127]` — and scored 0.640 anyway.
2. **v16's other fixed settings.** v16's grid records `multi_temperature=0.25`,
   `template_shift=0`, `align_rise_weight=1`, `slope_window=6`; every one
   matches the current default at `pipeline_training.R:179-182`. `peak_decay`
   (0.3) also appears in the v16-era `align_forecast_pipeline_dilate.R`.
3. **"M1 `tau` saturates at 6.0."** This was Ming's error: that column is
   `training_rows$tau`, an **M2 time-since-peak feature clamped to [-6, 6]**
   (372/693 rows at the bound). M1's actual shift is `m1_train_preds$m1_tau`,
   range -4.657 to +5.761, no saturation.

### Live candidates — adjudicate these

**A. Multi-template peak derivation** (`m1_multi_template.R:288-301`). The
ensemble peak is a weighted mean of per-template peaks; its CI an upper weighted
quantile of the same. Argie (Gemini 3.1 Pro high) proposed this as primary,
citing CI collapse. **Ming verified the CI framing is overstated**: Argie
claimed v16 CIs are "4 to 6 weeks wide"; v16's median width is **0.709 wk**
against current **0.436** — a 1.6x median ratio, overlapping distributions, not
a collapse. The surviving hard core is qualitative: **current produces 132 of
690 origins with exactly zero-width CI; v16 produces 0 of 334.**

But deepseek found **`t_peak_hi < t_peak` in 96 of 334 v16 rows (29%)** — the
CI fails to bracket its own point estimate *in v16 too*, same `.weighted_quantile()`
cause. So the CI construction is not obviously the regression.

The point-estimate half is untouched by that objection and matches the
oscillation evidence. **Is the weighted-mean-of-peaks reduction new, and did
v16 derive the ensemble peak differently?** Note v16's integer-valued
`peak_weekF` — quantisation would damp exactly this jitter.

**B. D-32 — previously refuted, now un-refuted.** The 2026-09-15 pin of
`k_ref` 25->30 and `slope_weight` 8->16. Ming killed this because v16's 20-spec
grid spans only 0.293 wk. **deepseek showed that flatness was measured under
v16 code and does not transfer**: under current code the same 25/8 -> 30/16
change moves the final peak by 1-3 weeks (2013-14: 31->29; 2019-20: 28->27).
Ming's refutation was invalid. How much of the 2.1 wk gap does this carry?

**C. `anchorWeek` 19 -> 20.5, and legacy integer vs fractional timing.** v16
used `anchorWeek = 19` constant across all 10 seasons; current uses 20.5 with
fractional timing. M0 ignition itself is *not* the regression — deepseek
reproduced v16's `iWeek_hat`/`iWeek_true` exactly for two seasons.

**D. `buffer_weeks` 5 -> 0.** Ming measured this in isolation: it cuts
reversions 34 -> 18 and then **plateaus from buffer 3 onward**, never
approaching v16's 1. And it never enters `peak_weekF`, so it explains **none**
of the accuracy regression. Worth restoring as a state-machine fix; it is not
the cause. Confirm or refute this bounding.

### The confounder you must weigh

deepseek could not reproduce v16 under current code + v16 configuration (max
|Δpeak_weekF| 5 wk on 2013-14, 3 wk on 2019-20; only 6/33 and 11/31 origins
matching). That looks like "the difference is in code, not configuration" —
**but v16's input snapshot `data/flu_testing_data.csv` is absent from the repo**,
so the September ORVT CSV was substituted, and it differs from the cache's
observed series in **21% of observed rows** (up to 2.08 pp). Code change and
data revision cannot currently be separated. Say whether this confounder can be
broken, and how.

## Plan corrections deepseek surfaced

Verify each and say whether it blocks rev 5:

1. **`mae`-side anchor inconsistency.** The headline `2.912` is an **11-season**
   mean; **Gate V is defined on the 10 shared seasons**, whose mean is `2.854`.
   The plan's §0 table lists only the 10 shared seasons yet quotes 2.912.
2. **Truth-convention inconsistency.** `0.766 / 2.912` are computed on parabolic
   decimals *including* for seasons §1.1 declares to be **interval** truth.
   Under the plan's own §1.1 truth the pair is **0.635 / 2.731**; under the
   brief's intervals, **0.640 / 2.736**. The ratio survives; the frozen
   constants do not. `peak_incumbent = 0.2155` was measured under the superseded
   convention and must be rechecked.
3. **"Last origin per season" is not the same quantity on both sides.** v16's
   last origin is eval week 52-53; the current run's last *available* origin is
   week 42-51, and a literal "last origin" returns NA for 10 of 11 seasons.
4. **v16's `iWeek_true` is not ground truth** — it is `canonical label - 1`, an
   intentional offset (`scripts/fresh_run/03_m1_loso.R:6-8`).
5. 2013-14 is **51.5% fallback** in v16 (17 of 33 origins,
   `delta_unstable_profile`), so v16's number there is fallback-driven.

## Artifacts

Read-only, `/home/yeli/PAGe-bcc-artifacts/seasonal-archive-20260818/_shared/`:
`data/align_multi_cache.rds` (`params_df` 334x19, `forecast_df` 46,371,
`ref_list`), `data/fresh_m1_alignment_tuning_v7.rds` (`$results` 20-spec grid),
`data/fresh_deploy_wf_cache.rds` (2025-26, v16's **holdout**, n=1).

Current: `results/final-kit-2026-27/20260918T1520Z-final-2026-27-wmin8-venkata/artifacts/m2_tuning.rds`
(`m1_train_preds` 726x19, `training_rows` 693x22).

Prior reports: `docs/m1-argie-findings.md` (Argie + Ming's verification),
`docs/m1-v16-repro-findings.md` (deepseek), `docs/m1-retune-plan-2026-09-19.md`
(rev 5), `docs/audits/m1-plan-audit*-sol-2026-09-19.md` (your four prior audits).

## Constraints

- Read-only on `/home/yeli/PAGe-bcc-artifacts/`.
- **Do not touch `PAGe/R/m2_subset_correction.R` or `manuscript/**`** — another
  agent owns them; editing them is a hard failure.
- No commits. No tuning runs, sweeps, or production changes.
- `devtools::load_all("PAGe")` means the **working tree** runs.
- Authoritative positivity is `pos_flua / test_flu`
  (`realtime_sources.R:155-156`), **not** `fluAPercentPositive`.
- Surveillance CSV is private: do not copy or quote raw rows.
- Amplitude is **not** part of this regression — v16's `a` reaches 6.441 and max
  forecast 0.9871, the same pathology as current. Governed separately.

## Deliverable

`docs/m1-sol-adjudication.md`:

1. **Cause.** Rank A/B/C/D by how much of the 2.1 wk gap each carries, with
   measured evidence. If the evidence does not identify a cause, say so plainly
   — three confident hypotheses have already died here, two of them Ming's.
2. **The confounder.** Can code be separated from data vintage? How?
3. **Plan corrections.** Which of the five block rev 5; what each must become.
4. **Next action**, minimal and testable, and who should run it.

State confidence per item. Prefer an honest null over a plausible nomination.
