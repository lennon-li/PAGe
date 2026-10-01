# Parallel outer-holdout runs on Venkata

This runbook prepares the 11 outer holdouts for controlled parallel execution
on Venkata. It does not launch a run until the current 2025–26 single-fold
gate run has completed successfully.

The scheduler uses one Linux process per outer season and sets
`inner_cores = 1` inside each fold. This prevents nested parallelism and avoids
the local TCP sockets used by R `multisession`. The default is four concurrent
outer folds; change `PAGE_OUTER_WORKERS` only after checking Venkata capacity.
Each fold has its own artifacts, checkpoints, log, and status file. The parent
writes the combined predictions and equal-season M2-versus-M1 decision only
after all folds finish.

Venkata currently has 16 CPUs visible, 125 GiB RAM, and two idle RTX A5000
GPUs. The forecasting pipeline is CPU-based, so the GPUs are not required.

The authorized raw CSV currently lives on Asgard at
`/home/yeli/FLU/flu_testing_data.csv`. The prepared, disclosure-sensitive
inputs for the parallel run are currently under
`results/manuscript/all-season-holdout-prep-20260914-r2/` and include the
canonical data RDS, timing-label RDS, fold inputs, and manifests. Transfer the
prepared directory to Venkata through the approved BCC path, or transfer the
raw CSV and regenerate it there. Always pass the destination path explicitly;
Venkata must not assume that the Asgard path exists.

Before deployment, copy the current PAGe checkout to Venkata. Its existing
installed package is stale. The launcher reinstalls `PAGe/` into a repository-
local library, records a source hash, and refuses to run if the installed
package does not match the checkout.

After the current 2025–26 gate run is complete, from the PAGe checkout on
Venkata set:

```bash
export PAGE_REPO_ROOT=/path/to/PAGe
export PAGE_PREP_DIR=/path/to/all-season-holdout-prep-20260914-r2
export PAGE_RUN_ROOT=/path/to/PAGe-results
export PAGE_RUN_ID=all-outer-holdouts-YYYYMMDDTHHMMSSZ
export PAGE_GATE_RUN_DIR=/path/to/2025-26-gate-run
export PAGE_OUTER_WORKERS=4
export PAGE_INNER_CORES=1
export PAGE_FUTURE_BACKEND=multicore
```

The gate directory must contain a final `status.tsv` row with `complete`.
This is a hard launch guard. Start the scheduler only after that condition is
true:

```bash
mkdir -p "$PAGE_RUN_ROOT"
nohup env \
  PAGE_REPO_ROOT="$PAGE_REPO_ROOT" \
  PAGE_PREP_DIR="$PAGE_PREP_DIR" \
  PAGE_RUN_ROOT="$PAGE_RUN_ROOT" \
  PAGE_RUN_ID="$PAGE_RUN_ID" \
  PAGE_GATE_RUN_DIR="$PAGE_GATE_RUN_DIR" \
  PAGE_OUTER_WORKERS="$PAGE_OUTER_WORKERS" \
  PAGE_INNER_CORES="$PAGE_INNER_CORES" \
  bash scripts/launch_outer_holdouts_venkata.sh \
  > "$PAGE_RUN_ROOT/$PAGE_RUN_ID.launcher.log" 2>&1 < /dev/null &
echo $! > "$PAGE_RUN_ROOT/$PAGE_RUN_ID.launcher.pid"
```

The launcher creates the run directory itself and refuses to overwrite an
existing run. The final deployment packet must use a fresh run ID.

Start the zero-token watchdog in a separate Venkata shell:

```bash
bash scripts/watch_outer_holdouts_venkata.sh \
  "$PAGE_RUN_ROOT/$PAGE_RUN_ID" 600
```

Validation requires `parallel_run_summary.rds` with `status = "complete"`,
all requested fold statuses complete or skipped, one `outer_fold_result.rds`
per holdout, and a readable `aggregate_m2_vs_m1.rds`. The results can then be
used for the manuscript, while the final production kit is fit separately
using the fixed protocol on all eligible completed seasons.
