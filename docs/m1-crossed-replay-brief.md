# Brief: crossed replay — separate code from data in the M1 regression

You wrote `docs/m1-v16-repro-findings.md`. This is the follow-up it earned.
Your Task 4 could not attribute the non-reproduction to code, because you
changed code **and** data at once — v16's input snapshot was missing. It is not
missing. This brief recovers it and runs the controlled experiment.

## The finding that unblocks this

**v16's exact input data is embedded inside `align_multi_cache.rds`.** Each of
the 10 `ref_list` entries carries `ref$dat` for its nine training seasons,
including the authoritative `y` (numerator) and `N` (denominator). Verified
independently, twice:

- 4,689 embedded rows; **521 unique `season x weekF` keys**
- every season appears in **exactly 9** folds
- **zero** disagreements in `y`, `N`, or date across repeated keys
- 52 weeks per season, 53 for 2014-15

That is a ninefold internal cross-check of a recoverable, exact snapshot. It is
stronger than reconstructing positivity from `forecast_df`, because it carries
the raw counts rather than a ratio.

## Provenance: the source tree

The cache was written **2026-04-16 12:24:28**. Commit timeline that day:

| commit | time | note |
|---|---|---|
| `aafd0be` | 11:39 | package rename flualign -> PAGe |
| `741bc73` | 11:46 | **last commit before the cache was written** |
| *(cache written)* | **12:24** | |
| `33fcfb6` | 15:34 | remove legacy flualign/ artifact |
| `00ab9b4` | 23:13 | propagate `t_peak_median` |

**Primary candidate tree: `741bc73`.** This is consistent with the cache having
no `t_peak_median` column (added at `00ab9b4`, same day but 11 hours later).
Fall back to `aafd0be` if `741bc73` fails. Do not assume; verify by
reproduction (Stage 1) before drawing any conclusion from the cross.

Work in a scratch worktree or a detached checkout. **Do not modify the current
branch, do not commit, do not leave the tree dirty.**

## Stage 1 — gate: reproduce v16 row-for-row

**Do not proceed past this stage until it passes.** A source tree that cannot
reproduce the cache cannot be used to attribute a difference to code.

1. Reconstruct the v16 input by deduplicating the union of all `ref$dat`.
   Assert the five bullets above before using it. Hash it. Keep it private —
   it is surveillance data.
2. Check out `741bc73` and replay the 10-season LOSO alignment on that input,
   with v16's configuration: `k_ref=25`, `slope_weight=8`, `slope_window=6`,
   `multi_temperature=0.25`, `template_shift=0`, `align_rise_weight=1`,
   `peak_decay=0.3`, legacy integer timing, `anchorWeek=19`, `buffer_weeks=5`,
   v16's M0 `best_params`, and `manual_labels = canonical - 1`.
3. Compare against `params_df` **row-for-row**, not on aggregate MAE:
   `tau, delta, a, b, t_peak, t_peak_lo, t_peak_hi, peak_weekF, peak_passed,
   fallback_reason, n_train, anchorWeek`, plus fold membership.

**Pass:** exact or near-exact on all 334 rows. Report the max absolute
deviation per column. **Fail:** report where it diverges and stop — that
localises the search by itself and is a complete, valuable result. Do not
proceed to Stage 2 on a failed gate.

## Stage 2 — the 2x2 cross

Only after Stage 1 passes. Hold configuration, timing mode, fold declarations,
and origin schedule **fixed**; vary exactly two factors:

|  | v16 data (recovered) | September ORVT CSV |
|---|---|---|
| **v16 code** (`741bc73`) | = Stage 1 baseline | |
| **current code** (working tree) | | = your earlier Task 4 |

Report mean absolute final peak error on the 10 shared seasons for each cell,
under **interval truth** (below). The two off-diagonal cells are the answer:
they separate the code effect from the data effect.

## Stage 3 — one factor at a time, on v16 data

Only after Stage 2. On the recovered v16 input, starting from v16 code, switch
one factor at a time and measure each in isolation:

1. **code** `741bc73` -> working tree
2. **timing/anchor**: legacy integer + `anchorWeek=19` -> fractional +
   `anchorWeek=20.5`
3. **spec**: `k_ref=25, slope_weight=8` -> `k_ref=30, slope_weight=16`

Compare the **full origin trajectory and `fallback_reason` identity**, not only
the final MAE. Report per-season, not just the mean — the current error is
bidirectional (2013-14 +4.60, 2014-15 +4.09 against 2012-13 -1.82, 2018-19
-3.58), so a mean can hide a factor that moves seasons in opposite directions.
This already happened: the spec switch moved 2013-14 toward truth and 2019-20
away from it.

## Truth convention — use this one

Interval truth, the plan's declared rule. Peak truth from
`p = pos_flua / test_flu` (**not** `fluAPercentPositive`):

| season | truth |
|---|---|
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

Interval error is 0 inside the interval, else distance to the nearest endpoint.
Non-interval truths use three-point parabolic interpolation about the argmax.

**The matched-origin reference pair is 0.6350 (v16) / 2.7314 (current), a
2.0964-week gap, v16 better in 9 of 10 seasons.** Do **not** use 0.766 / 2.912;
those mix a 10-season and an 11-season mean and apply parabolic decimals to
interval seasons.

Use the **latest common forecast-available origin** per season, not "the last
origin" — v16 runs to week 52-53 while current's last available origin is week
42-51. A literal last origin returns NA for 10 of 11 current seasons.

## What is already settled — do not re-litigate

Four hypotheses are dead. Testing them again wastes the budget:

1. **`LAMBDA_DELTA`** — v16 has the identical defect (`delta_on` TRUE on
   169/334, `delta` in `[-0.0061, +0.0127]`) and scored 0.635 anyway.
2. **Multi-template weighted-mean peak derivation** — **not new.** Traced to
   commit `47bcdf0` (2026-03-28), before the cache, and confirmed by the v16
   artifact's own 96/334 rows where the upper quantile sits below the point
   estimate.
3. **`tau` saturation at 6.0** — a misread column: that is
   `training_rows$tau`, an M2 time-since-peak feature clamped to `[-6, 6]`.
   M1's shift is `m1_train_preds$m1_tau`, range -4.657 to +5.761.
4. **Output quantisation** — rounding current estimates to integers *worsens*
   MAE (2.7314 -> 2.8224) and leaves jumps intact (max 8.38 -> 8).

`buffer_weeks` is a confirmed state defect but carries **exactly zero** of the
peak-location gap: it is applied only after `peak_weekF` is computed. Record its
state effects if convenient; do not credit it with accuracy.

## Constraints

- Read-only on `/home/yeli/PAGe-bcc-artifacts/`.
- **Never touch `PAGe/R/m2_subset_correction.R` or `manuscript/**`** — another
  agent owns them. Editing them is a hard failure.
- No commits, no branch changes on the working branch, no tuning runs, no
  sweeps, no production changes.
- Surveillance data is private: do not copy outside the scratch area, do not
  commit, do not quote raw rows. The recovered snapshot is surveillance data.
- Authoritative positivity is `pos_flua / test_flu`
  (`realtime_sources.R:155-156`).
- `devtools::load_all()` means the checked-out tree runs — confirm which tree
  is loaded at every stage and record it. Getting this wrong cost a previous
  session a day.

## Deliverable

`docs/m1-crossed-replay-findings.md`:

1. Stage 1: did `741bc73` reproduce the cache? Max deviation per column. If it
   failed, where.
2. Stage 2: the 2x2 table, with the code effect and data effect stated as
   numbers.
3. Stage 3: each factor's isolated effect, per season and on trajectory.
4. Your attribution of the 2.0964-week gap, **or an explicit null.**

**A null is a valid and preferred result.** Three confident hypotheses have
already been refuted here, two of them mine. Do not nominate the most plausible
surviving candidate; report what the numbers support and no more. State
confidence per stage, and say what you could not check and why.
