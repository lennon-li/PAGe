# PAGe v2 weekly shadow operations — 2026-27

## Purpose

This is the frozen operational shadow path for M0-v2 → M1-v2 → governed M2-v2 during the 2026-27 season. It runs in parallel with the immutable production/legacy weekly forecast and does not replace the frozen production kit.

The v2 shadow forecasts influenza A and influenza B separately:

- A +1 and A +2 are generated from the A state/growth baseline, with A C2 timing correction only when the governed A M1-v2 handoff is available.
- B +1 is always the B1 baseline.
- B +2 is the B1 baseline while the operational B gate review remains closed. No A timing is borrowed for B.

## Frozen v2 timing policy

M0-v2:

- classifier disabled (`use_cls = FALSE`);
- earliest eligible week `w_min = 12`;
- three-week raw positivity persistence window (`raw_nondec_n = 3`);
- a weekly decline is tolerated when no larger than one standard error of the difference between the adjacent weekly binomial positivity estimates (`raw_drop_se_tol = 1.0`);
- otherwise the validated classifier-free M0-v2 evidence grid is unchanged.

M1-v2 uses the full-history timing stage trained only through 2025-26.

## Weekly command

Run from the repository root:

```bash
Rscript 2026/run_weekly_shadow_v2.R --season=2026-27 --source=auto
```

`--source=auto` first attempts the live PHO ORVT feed. If the live endpoint is unavailable, it falls back to the local OLIS snapshot at:

`../IRVRI/wf_output/olis_snapshot/hist_olis.RData`

The fallback path can be overridden with `--olis-fallback=PATH`.

For a specific archived input vintage:

```bash
Rscript 2026/run_weekly_shadow_v2.R \
  --season=2026-27 \
  --source=olis \
  --input=/path/to/hist_olis.RData
```

or:

```bash
Rscript 2026/run_weekly_shadow_v2.R \
  --season=2026-27 \
  --source=orvt \
  --input=/path/to/ORVT_Lab_Testing_Data_2025-26_2026-27.csv
```

## Full-history refresh requirement

Every run rebuilds the entire available current-season A/B history from one exact source vintage. Do not append only the newly reported week.

The source snapshot is archived under the run's `data_cache/` directory with its SHA-256 hash. This preserves as-issued data vintages and captures retrospective changes in previously reported weeks.

## Outputs

Runs are written under:

`results/weekly-shadow-v2/<season>/<UTC timestamp>-weekFXX/`

Key files:

- `data_cache/` — exact archived ORVT/OLIS input vintage;
- `typed_ab_weekly.csv` — paired A/B weekly counts, denominators, and positivity;
- `revision_audit.csv` — row-level differences versus the preceding shadow run when available;
- `revision_summary.tsv` — number and magnitude of retrospective A/B revisions;
- `m0_signals.csv` / `m0_detection.csv` — current A ignition diagnostics;
- `m1_v2_runtime.rds` / `m1_v2_timing.csv` — governed A peak-timing state when available;
- `m2_v2_predictions.csv` — full governed M2-v2 A/B output;
- `forecast_summary.tsv` — concise separate A +1/+2 and B +1/+2 forecasts;
- `provenance.tsv` — source hash, artifact hashes/IDs, and gate policy;
- `status.tsv` — operational checkpoint summary.

## Retrospective revision audit

By default the runner compares the new full-history panel with the most recent preceding v2 shadow panel for the same season. An explicit comparison vintage can be supplied using:

```bash
--compare-panel=/path/to/typed_ab_weekly.csv
```

The audit compares A and B positive counts, denominators, and positivity for every overlapping week.

As-issued forecasts must never be overwritten after later data revisions. Revised-history reruns and real-time issued forecasts answer different evaluation questions and must remain distinguishable through their archived source hashes and run directories.

## Artifact inputs

Default governed shadow artifacts:

- M0-v2: `artifacts/m0-v2-wmin12-raw3-se1-decimal-loso-v1/loso_result.rds`
- M1-v2: `artifacts/m1-v2-wmin12-raw3-se1-full-history-v1/m1_v2_stage.rds`
- M2-v2: `artifacts/m2-v2-c2-governed-v1/m2_v2_c2_governed_fit.rds`

The runner verifies the frozen M0-v2 policy before forecasting and records SHA-256 hashes for all three artifacts.

## V2 freeze boundary

After this weekly shadow path is validated, v2 is frozen except for correctness fixes and weekly data refreshes. New model architecture should be developed as v3 rather than added piecemeal to v2.

The planned v3 research direction is a joint A+B timing/phase model using paired multiplex surveillance, feeding separate A and B short-horizon forecast heads. That work must be evaluated against the prospectively accumulated v2 shadow record.
