# Liz handoff: stage evidence and M1-only comparison

## Files

- `scripts/publication_stage_report.R` — runnable report and synthetic checks.
- `stage-report/m0_stage_summary.csv` — all 11 M0 rows with onset/declaration definitions and provenance flags.
- `stage-report/m1_peak_summary.csv` — all 11 M1 peak availability/error aggregates.
- `stage-report/comparison_aggregate.csv` — h2 0--12 primary, h1 0--12 secondary, h2 full, and full supplementary metrics.
- `stage-report/comparison_season.csv` — per-season descriptive scores.
- `stage-report/comparison_season_deltas.csv` — paired per-season M1-only minus PAGe deltas.
- `stage-report/forecast_availability.csv` — ledger, target, forecast, and score denominators.
- `stage-report/report.md` — definitions, limitations, and primary table.
- `stage-report/private/` — gitignored weekly and per-origin evidence rows (`weekly_comparison_rows.rds`, `m1_peak_by_origin.rds`).

## Command and checks

Run from the project root:

```sh
Rscript scripts/publication_stage_report.R
Rscript manuscript/results/publication-repair-20260908/stage-report/tests/test_stage_report.R
```

The report completed with replay state `complete_diagnostic_only`, report elapsed 1.806174 seconds, 11 replay-RDS reads, 11 archived-manifest reads, and zero retraining/tuning calls. Replay call count is not recorded in the source artifacts. All synthetic checks passed.

## Primary result (descriptive only)

| Model | equal-season NLL | pooled-trial NLL | equal-season MAE | scored seasons |
|---|---:|---:|---:|---:|
| M1-only continuation (saved m1_p) | 0.460079 | 0.436736 | 0.050304 | 11/11 |
| PAGe repaired runtime | 0.462821 | 0.438180 | 0.054065 | 11/11 |

The M1-only rows are saved `m1_p` forecasts from the same fitted upstream kit, so this is a pipeline-component diagnostic rather than a separately retuned standalone M1 model. Per-season differences are descriptive; no p-values or hypothesis tests were calculated. `2025-26` has only 20 source weeks (weekF 9--28), so its full-season M1 peak error is censored. Its archived M0 label value 19 is not independently provenance-verified.

## Parent recomputation

To recompute one season, read `replay/<timestamp>/private/2012-13.rds`, join `stages$m2_predictions` by `eval_week = forecast_ledger$weekF` and `h = forecast_ledger$lead`, and apply the NLL formula in the report script to rows with exact keys and `0 <= t_since <= 12`. The public availability table records the corresponding denominators.

