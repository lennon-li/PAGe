# Spec: IRVRI legacy daily GAM comparator adapter

Draft 2026-09-15 (ming-oracle). Implementation: Wei, after PROTOCOL v2.0
freeze. Target path (claimed): `scripts/comparators/irvri_gam_adapter.R`.
Design context: `new-cycle-audit-and-evidence-plan-2026-09-15.md` s9.

## Inputs

| Input | Source | Notes |
|---|---|---|
| Daily influenza counts | `~/FLU/hist2026-04-01.RData`, object `r$flu` | Path via env var `PAGE_OLIS_DAILY_FILE`; never copied into the repo or printed. Run only on local hosts (Asgard/BCC); never transfer daily data or run this adapter on SciNet (Lennon, 2026-09-15). Columns: `date` (Date), `age.` (Adult/Pediatric/Senior), `pos`, `tests`, `neg`, `prop`, `date.`, `weekends`, `fluYear` (calendar-month July-June; not used for mapping). One row per date x age; continuous daily 2019-12-29 to 2026-03-28. |
| PAGe fold rows | New-cycle 2025-26 outer-fold export (A3) | Join keys (dates primary): `season`, `origin_week_start_date`, `h`, `target_week_start_date`; `origin_weekF`/`target_weekF` for readability. Fields: y, N, t_since, phase, both weight sets, M1/gate/shadow-M2 p |
| Season calendar | `PAGe::page_season_calendar(dates, start_week = 27L)` (`PAGe/R/season_calendar.R:17`; uncommitted, may change after re-review) returning `season`, `start_year`, `week`, `nW_true`, `weekF`, `weekS` | Do not use IRVRI `irvri_wf_seasonize()` (`start_week = 35`, row-index `flu_week`) or IRVRI `fluYear` (calendar-month July-June, not MMWR week 27) |
| Legacy model | `IRVRI::irvri_adapter_gam()` (IRVRI `2e71d7c` or later; record SHA) | Production defaults: `num_days = 365`, `spacing = 14`, `offset = 14`, `summer = c(6, 8)`, `week_start = 7`, all three strata |

## Procedure

1. **Preflight.** Record file SHA-256, IRVRI SHA/version, mgcv version, platform. Assert one row per date x age, no gaps, `tests >= pos >= 0`.
2. **Reconciliation gate (before any forecast).** Aggregate daily all-ages counts to Sunday-Saturday MMWR weeks keyed by `week_start_date`, mapped with `page_season_calendar()`. The daily source is a different extract/vintage, so differences are expected. Compare with PAGe weekly `y`, `N` for every week in the scored seasons. Output aggregates only: exact-match rate, and max/median absolute and relative difference in `y`, `N`, `p`. Stop if weeks are missing. A mismatch does not stop the run; it is reported, and each method is scored on its own target (see Scoring).
3. **Origins.** Exactly the PAGe origins in the fold export for that season. Origin cutoff = `origin_week_start_date + 6` (Saturday ending MMWR week `t`). No reporting lag: both PAGe and the comparator are final-data retrospective replays (symmetric; G-05), stated as such.
4. **Fit per origin.** Daily rows with `date <= cutoff`, trailing `num_days`; knots re-derived from that refit's last date (adapter does this). No future test volumes (adapter uses 28-day mean fallback).
5. **Predict.** Weekly all-ages positivity for target weeks `t+1`, `t+2`; keep posterior-mean `p_hat` and draw quantiles (2.5/50/97.5) for descriptive use.
6. **Output (one row per origin x h).** `season`, `origin_week_start_date`, `origin_weekF`, `h`, `target_week_start_date`, `target_weekF`, `p_hat_gam`, `q025`, `q500`, `q975`, `y_daily_agg`, `N_daily_agg`, `fit_status`, `n_train_days`, `last_train_date`. Failures kept with reason codes, not dropped.
7. **Coverage flag.** Mark rows whose target week ends after the last daily date (2026-03-28) as `not_scorable_data_end`.

## Scoring (done by the PAGe scorer, not the adapter)

- Join on season + origin + h. Primary: PAGe `y`, `N` targets, PAGe post-ignition rows, three-phase weights (D-2); plus legacy 0-12 weights and registered h2 trial-weighted line.
- Sensitivity: score both methods against `y_daily_agg`/`N_daily_agg`.
- Secondary: legacy pre-ignition rows alone; per-week paired differences; by phase and horizon; positivity MAE. No interval comparison; no tests.

## Tests (before real data)

- Synthetic daily series: no row with `date > cutoff` enters any fit (poison future days; forecasts unchanged).
- Poison days before cutoff: forecasts change (non-vacuous).
- Week-53 season maps to 53 weeks; no 53->52 collapse.
- Origin/h join is 1:1 with the PAGe export.
- Output contains no raw daily rows.

## Tiers

- Tier 1 (2025-26): data present for the fit windows; targets after 2026-03-28 unscorable (late decline truncated). Report coverage.
- Tier 2 (2022-23 to 2024-25): daily data sufficient (365-day windows from 2020-12); needs prior-only PAGe kits.
- Tier 3 (2026-27): needs a later daily snapshot.
