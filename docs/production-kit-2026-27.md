# Designated production kit, 2026-27

**Designated 2026-09-18 by Lennon.** This is the kit the weekly 2026-27
forecast runs against. Nothing else is production; the other final-kit runs
under `results/final-kit-2026-27/` are superseded and kept only as history.

## Identity

| | |
|---|---|
| Kit | `results/final-kit-2026-27/20260918T1520Z-final-2026-27-wmin8-venkata/final_kit.rds` |
| `kit_sha256` | `cef535799994a68f5dbacfddced46eeea23d2e5deb15dbd6a823e8c555bf87cc` |
| Run id | `20260918T1520Z-final-2026-27-wmin8-venkata` |
| Trained on | venkata (`phl-hpcdl-011`), 24 cores, 9166 s |
| Completed | 2026-09-18 17:53:44 UTC |
| Input feed | `/home/yeli/FLU/flu_testing_data_orvt_20260916.csv` |
| Input `sha256` | `516ce54f85316d576be187f4a3be8035912dbfc88bfb354e8dfb99cdd204c0e7` |
| Package source | `9635cce` (PAGe branch `agent/page-governance-audit`) |

Verify before any weekly run:

```sh
sha256sum results/final-kit-2026-27/20260918T1520Z-final-2026-27-wmin8-venkata/final_kit.rds
# must print cef535799994a68f5dbacfddced46eeea23d2e5deb15dbd6a823e8c555bf87cc
```

## What it selected

M0 (11 tuned parameters, inner LOSO over 11 eligible seasons):

```
cls_thr 0.26   p_thr 0.002   prev_thr 0.001   p_sum_thr 0.07   eps 0
n_consec 5     L 2           K_sum 5          N_req 4
w_min 8        w_max 26
```

M2: `h1:i0_kz0_ku0_kd0|h2:i0_kz0_ku0_kd0`, family `offset_subset_v1`,
`enabled_count = 0` at both horizons. The inner adoption gate returned
`keep_m1`, so the frozen M2 is the all-off candidate and reproduces M1
bit-for-bit. Gate reasons: `m2_not_strictly_better_than_m1`,
`overall_minimum_gain_failed`, `horizon_minimum_gain_failed`,
`season_degradation_limit_failed`.

## Why v2.1 rather than v2.0

The predecessor kit (`8f3e9104...`, Asgard, 2026-09-18 05:54 UTC) is
identical in every tuned parameter; the two differ only in `w_min` (13 vs 8).
`w_min` is the M0 eligibility-window floor: the earliest week ignition may be
declared at all. Epidemiological review moved it to weekF 8, the week the
weekly run actually starts and the minimum history PAGe needs to run, leaving
`w_max = 26` untouched.

`w_min` was never a tuned axis — it was held fixed at 13 across all three
rounds of the v2.0 M0 grid while only the thresholds varied — so this is a
change to an operational constant, not an override of a fitted result.

Three checks were run before adopting it:

1. At the v2.0 selected parameters, relaxing 13 to 8 changes no ignition week
   in any of the 12 detected historical seasons. The earliest detection
   anywhere is 2015-16 at week 15, so a floor of 13 was never binding.
2. It is nevertheless a real perturbation: 38 of the 40 M0 grid specs *do*
   change their detections under `w_min = 8`, with the earliest dropping to
   week 10. The winner survived a landscape that moved under almost every
   other candidate.
3. The v2.1 tuning independently reselected the identical configuration.

It also does **not** make 2026-27 ignite. The binding constraint there is the
4-of-5 vote (`p_sum` 0.0621 against a 0.070 threshold), not the window — so
the change cannot be read as having been fitted to the current season.

Registered as a deviation; see `ANALYSIS_DEVIATIONS`.

## Standing caveat

The 11-fold outer evaluation does **not** currently characterise this kit.
That campaign trained on a truncated feed (2025-26 ending at weekF 28 of 53)
and must be re-run on the full feed before any performance claim is made.
The kit itself is unaffected — it was trained on the complete feed, verified
by the input hash above — but "how well does it forecast" has no valid answer
until the clean re-run lands.

## Weekly use

```sh
PAGE_KIT_PATH=results/final-kit-2026-27/20260918T1520Z-final-2026-27-wmin8-venkata/final_kit.rds
PAGE_KIT_SHA256=cef535799994a68f5dbacfddced46eeea23d2e5deb15dbd6a823e8c555bf87cc
```

See `docs/weekly-operations-2026-27.md` for the operator workflow. Note that
the weekly runner honours `PAGE_PACKAGE_LIBRARY` but does not require it; a
run against a stale ambient library will silently use old code. Set it.
