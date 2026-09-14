# Reproducing the 2025–26 outer-holdout run

This manual describes the governed PAGe run used for the paper's 2025–26
outer holdout. It trains and tunes M0, M1, and M2 using only the eligible
historical seasons, expands unresolved grid boundaries before the holdout is
used, applies the phase-weighted M2 adoption rule, freezes the resulting kit,
and then replays 2025–26 once under the strict unseen-season contract.

The authoritative development entry point is the exported
`PAGe::run_outer_fold()` API. The checked-in wrapper
[`2025/run_2025_ultimate.R`](../2025/run_2025_ultimate.R) adds the data
contract, preflight checks, provenance, source snapshot, resumable artifact
directories, and terminal status record.

## Inputs and season split

The authorized historical CSV is supplied through `PAGE_FLU_HIST_FILE`. For
the pilot run, the outer holdout is `2025-26`. The fixed exclusions are
`2011-12`, `2015-16`, `2020-21`, and `2021-22`. The ten inner training seasons
are therefore `2012-13`, `2013-14`, `2014-15`, `2016-17`, `2017-18`,
`2018-19`, `2019-20`, `2022-23`, `2023-24`, and `2024-25`.

The holdout is isolated before fitting. It is not available to M0, M1, M2,
boundary expansion, model selection, or the M2 adoption gate. It is accessed
only by the final strict replay.

## Reproduction command

Run from the repository root. Use a new `PAGE_RUN_ID` for every attempt;
the wrapper refuses to overwrite an existing run directory. The launcher
reinstalls the current package source into the repository-local `r-lib/`
library before starting, so nested workers use the same source revision.
The runner loads that installed package directly; this avoids the incompatible
`pkgload::load_all()` namespace registry path on the current R version.

```bash
PAGE_FLU_HIST_FILE=/home/yeli/FLU/flu_testing_data.csv \
PAGE_RUN_ROOT="$PWD/results/manuscript/nested-outer-2025-26-ultimate-20260911" \
PAGE_RUN_ID=YYYYMMDDTHHMMSSZ-ultimate-2025-26 \
PAGE_N_CORES=8 \
bash 2025/launch_2025_ultimate.sh
```

For a data and season-selection check without fitting:

```bash
PAGE_FLU_HIST_FILE=/home/yeli/FLU/flu_testing_data.csv \
PAGE_RUN_ROOT="$PWD/results/manuscript/nested-outer-2025-26-ultimate-20260911" \
PAGE_RUN_ID=preflight \
bash -c 'Rscript 2025/run_2025_ultimate.R --preflight'
```

The detached launcher writes the process output to
`<run-dir>/run.log`. The companion watchdog records compact five-minute
health rows in `<run-dir>/watch.tsv` and writes
`<run-dir>/watch_terminal.txt` after the runner exits.

## Exact API call sequence

The wrapper performs the following calls in order:

1. `PAGe::load_flu_hist(PAGE_FLU_HIST_FILE)` loads the authorized CSV.
2. The raw fields are normalized to `season`, `week`, `seasonstart`,
   `pos_flua`, and `test_flu`; weeks are converted to season-relative `weekF`
   using `MMWRweek`, with the season start at epidemiological week 27.
3. `PAGe::prepare_surveillance_data()` enforces the canonical data contract.
4. The wrapper validates the outer holdout, exclusions, expected ten training
   seasons, and absence of a default manual label for `2025-26`.
5. The wrapper calls:

```r
result <- PAGe::run_outer_fold(
  data = allD,
  holdout = "2025-26",
  timing_mode = "fractional",
  exclude = c("2011-12", "2015-16", "2020-21", "2021-22"),
  pre_ignition_weight = 0,
  early_weight = 2,
  early_max_t_since = 12,
  late_weight = 1,
  score_scale = "equal_week",
  min_gain = 0.0012,
  min_gain_by_horizon = c("2" = 0.002),
  confidence = 0.95,
  max_season_degradation = 0,
  m1_min_gain = 0.05,
  max_boundary_rounds = c(M0 = 10L, M1 = 4L, M2 = 6L),
  m0_expansion_steps = c(p_thr = 0.001, prev_thr = 0.001, p_sum_thr = 0.01),
  m1_expansion_steps = c(k_ref = 5, slope_weight = 4),
  m2_expansion_increment = 12L,
  n_cores = 8,
  artifact_dir = "<run-dir>/artifacts",
  checkpoint_dir = "<run-dir>/checkpoints",
  verbose = TRUE
)
```

Internally, `run_outer_fold()` calls `train_outer_fold()` first. That API
performs the governed sequence `tune_m0()` → boundary validation and
expansion → `fit_m0()` → `tune_m1()` → boundary validation and expansion →
`fit_m1()` → `tune_m2()` → boundary validation and expansion → the weighted
M2-versus-M1 adoption decision → `fit_m2()` → `assemble_kit()`. Only after
that training object is frozen does it call
`replay_season_holdout(..., kit_compatibility = "strict")` for `2025-26`.

## Weighting and adoption rule

The primary scale gives equal weight to each eligible week within a season
and equal weight to each season overall. Target-relative weeks from ignition
through `t_since = 12` receive weight 2. Later weeks receive weight 1, and
pre-ignition weeks receive weight 0. The `score_scale = "test_count"` result
is retained as a sensitivity analysis; it does not replace the primary
decision.

M2 is adopted only when its weighted NLL improvement over M1 meets the global
and horizon-specific minimum gains, the one-sided confidence rule, and the
season degradation limit. If the gate fails, the exact all-off M1 fallback is
used and recorded in `gate_decision_applied.rds`.

## Artifacts

The run directory contains provenance and execution records at its root:

- `provenance.rds` records the data hash, source identity, season split, and
  explicit protocol values.
- `package_source_manifest.csv` and `source_snapshot/` preserve the package
  source used by the run.
- `session_info.txt` records the R version and loaded package context.
- `status.tsv` records `started`, `training`, and terminal status rows.
- `run_summary.rds` records elapsed time, outer metrics, sensitivity metrics,
  the applied gate decision, protocol, and source manifest.

The `artifacts/` directory retains the M0, M1, and M2 grids, tuning objects,
boundary plans and reports, frozen stages, adoption evidence, the candidate
kit, the outer replay, and matched predictions. The required outer files are
`outer_training_result.rds`, `outer_replay.rds`,
`outer_predictions.csv`, and `outer_fold_result.rds`.

The `checkpoints/` directory contains resumable inner-fold checkpoints. A
checkpoint is evidence of progress only; the run is valid for reporting after
the terminal status and independent validation checks pass.

## Independent validation

After the runner exits, first require a successful service exit and a terminal
watchdog record:

```bash
systemctl --user show page-2025-ultimate-r3.service \
  -p ActiveState -p SubState -p ExecMainStatus -p ExecMainCode
cat <run-dir>/status.tsv
cat <run-dir>/watch_terminal.txt
```

Then verify, in a fresh R process, that the summary and outer result are
readable, the replay status is `unseen_replay_complete`, the holdout is
`2025-26`, all prediction values and required metrics are finite, and no
training or tuning season set contains `2025-26`. Confirm that the recorded
protocol matches the values above and that every source hash in
`package_source_manifest.csv` matches the corresponding file in
`source_snapshot/`.

The final report should use the weighted outer metrics from
`run_summary.rds`. The test-count-weighted values are reported beside them as
the prespecified sensitivity analysis.

The checked-in independent validator performs these checks and writes the
reviewable audit record:

```bash
Rscript 2025/validate_2025_ultimate.R \
  --run_dir="$PWD/results/manuscript/nested-outer-2025-26-ultimate-20260911/YYYYMMDDTHHMMSSZ-ultimate-2025-26"
```

It must print `independent validation passed` and create
`independent_validation.rds` and `independent_validation.txt` in that run
directory before the metrics are used in the manuscript.
