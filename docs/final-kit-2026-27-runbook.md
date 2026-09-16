# Final 2026-27 PAGe kit

**Do not launch until r5 is validated.** These are prepared operator commands;
no training run was launched while preparing this code. Ming's review and host
selection precede execution.

## Contract

`PAGe::train_outer_fold(data, holdout = NULL, ...)` performs the final
post-evaluation fit, with inner leave-one-season-out tuning, boundary expansion,
validation and freezing in M0 → M1 → M2 order. The M2 adoption decision either
uses M2 or freezes the exact all-off M1 fallback. There is no outer replay.

Training seasons: 2012-13, 2013-14, 2014-15, 2016-17, 2017-18, 2018-19,
2019-20, 2022-23, 2023-24, 2024-25, 2025-26. Fixed exclusions: 2011-12,
2015-16, 2020-21, 2021-22. Extra eligible or missing training seasons are errors.
Timing-v2 labels use the canonical ignition reference and the reviewed observed
peak pair for every training season, exactly as in the 2025 ultimate runner.

The predeclared protocol is fractional timing; pre/early/late weights 0/2/1;
early maximum 12; equal-week scoring; gain 0.0012, h2 gain 0.002; confidence
0.95; maximum season degradation 0; M1 minimum gain 0.05; boundary rounds
M0/M1/M2 = 10/4/6; M0 steps 0.001/0.001/0.01 for
p_thr/prev_thr/p_sum_thr; M1 steps k_ref=5, slope_weight=4; M2 increment 12.
`PAGE_N_CORES` controls inner parallelism. No previous stage cache is reused.

This is the explicitly requested all-season final-fit workflow. It provides no
new untouched holdout estimate and does not itself publish a deployment registry
entry or replace the operational incumbent. It is distinct from the older
fixed-spec acceptance/refresh workflow in `deployment-workflow.qmd`.

## Gate (either host)

Required gate ID: `20260915T0150Z-m1reuse-m2parallel-r5`, under
`results/manuscript/nested-outer-2025-26-ultimate-20260915` on Asgard. Set
`PAGE_GATE_RUN_DIR` to that run or its verified complete copy on Venkata.

```bash
bash "$PAGE_REPO_ROOT/2026/launch_2026_27_final_kit.sh" --gate-check-only
```

This mode cannot install, create a final-kit run, detach, or train. It requires
the last status row to be `complete`, a successful
`Rscript 2025/validate_2025_ultimate.R --run_dir="$PAGE_GATE_RUN_DIR"`, and a
`complete` watchdog terminal state if that file exists. The existing validator
also requires `watch_terminal.txt`; therefore an absent file fails validation.
The validator writes `independent_validation.rds` and `.txt` into the gate
folder on success. A running r5 is refused before invoking the validator.

The sole bypass is `PAGE_GATE_OVERRIDE=I_ACCEPT_UNVALIDATED_GATE`.
**This override is not for production.** It bypasses all gate validation,
requires an explicitly supplied gate path, and is logged to stdout,
`gate_check.log`, `gate_receipt.txt`, and the platform manifest. Unset it for
all operational commands below. No polling or automatic delayed launch occurs.

## Asgard commands

Use a Linux host shell, with PID 1 `systemd` or `init`; the launcher refuses a
PID sandbox. Required software: R and installed PAGe dependencies, GNU coreutils,
findutils, procps, util-linux (`setsid`), and Bash. A run-local PAGe install is
created automatically; the shared repository `r-lib` is not used or modified.
Keep the source tree stable from installation through runner startup.

```bash
set -euo pipefail
export PAGE_REPO_ROOT=/home/yeli/repos/PAGe
export PAGE_FLU_HIST_FILE=/home/yeli/FLU/flu_testing_data.csv
export PAGE_GATE_RUN_DIR="$PAGE_REPO_ROOT/results/manuscript/nested-outer-2025-26-ultimate-20260915/20260915T0150Z-m1reuse-m2parallel-r5"
export PAGE_RUN_ROOT="$PAGE_REPO_ROOT/results/final-kit-2026-27"
export PAGE_RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-final-2026-27-asgard"
export PAGE_N_CORES=8 PAGE_FUTURE_BACKEND=auto
unset PAGE_GATE_OVERRIDE
bash "$PAGE_REPO_ROOT/2026/launch_2026_27_final_kit.sh" --gate-check-only
# Execute the next line only after r5 validation and host selection.
bash "$PAGE_REPO_ROOT/2026/launch_2026_27_final_kit.sh"
```

The launcher sets OPENBLAS_NUM_THREADS, OMP_NUM_THREADS and MKL_NUM_THREADS to
1 before any R invocation; verifies source hashes before/after installing PAGe
and before detach; verifies the loaded package path, version and database age;
records installed package SHA-256 hashes; and runs preflight before detaching.
The child publishes PID/start ticks/command identity atomically. The launcher
also starts the detached identity watchdog. Existing run directories are refused.
If setup fails, inspect the compact failed status and the install/preflight log;
use a new run ID after resolving the failure.

## Venkata: source bundle and verified transfer

Prepare only after the real r5 gate succeeds. Transfer the current reviewed
working source, including uncommitted package changes; a Git archive of HEAD
would omit those changes. Do not copy the surveillance CSV: Venkata already
holds the authorized copy at `/home/yeli/FLU/flu_testing_data.csv`; verify its
sha256 matches Asgard (`fa8add1b...59c54`) instead. The bundle includes private
gate artifacts: transfer through the authorized channel and keep it private.

On Asgard, with the environment above (these commands do not train):

```bash
bash "$PAGE_REPO_ROOT/2026/launch_2026_27_final_kit.sh" --gate-check-only
bundle_dir=$(mktemp -d /tmp/page-final-kit-bundle.XXXXXX)
mkdir "$bundle_dir/source" "$bundle_dir/inputs"
tar -C "$PAGE_REPO_ROOT" -cf - PAGe \
  2026/run_2026_27_final_kit.R 2026/launch_2026_27_final_kit.sh \
  2026/watch_2026_27_final_kit.sh 2025/validate_2025_ultimate.R \
  docs/final-kit-2026-27-runbook.md | tar -C "$bundle_dir/source" -xf -
cp "$PAGE_FLU_HIST_FILE" "$bundle_dir/inputs/flu_hist.csv"
# Validator needs status, summary, provenance, source snapshot and artifacts.
# Copy terminal gate evidence, omitting the installed library, checkpoints and logs.
mkdir "$bundle_dir/inputs/20260915T0150Z-m1reuse-m2parallel-r5"
tar -C "$PAGE_GATE_RUN_DIR" -cf - status.tsv watch_terminal.txt run_summary.rds \
  provenance.rds package_source_manifest.csv source_snapshot artifacts \
  independent_validation.rds independent_validation.txt |
  tar -C "$bundle_dir/inputs/20260915T0150Z-m1reuse-m2parallel-r5" -xf -
(cd "$bundle_dir/source" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum) > "$bundle_dir/source.sha256"
(cd "$bundle_dir/inputs" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum) > "$bundle_dir/inputs.sha256"
tar -C "$bundle_dir" -czf "$bundle_dir.tar.gz" source inputs source.sha256 inputs.sha256
(cd "$(dirname "$bundle_dir")" && sha256sum "$(basename "$bundle_dir").tar.gz") > "$bundle_dir.tar.gz.sha256"
printf 'Transfer these two files: %s.tar.gz and %s.tar.gz.sha256\n' "$bundle_dir" "$bundle_dir"
```

Transfer those two files to Venkata's `$HOME/page-final-kit-transfer/` using
the authorized file-transfer channel. Then in Venkata's host shell, set
`PAGE_BUNDLE_ARCHIVE` to the transferred archive's actual filename:

```bash
set -euo pipefail
cd "$HOME/page-final-kit-transfer"
: "${PAGE_BUNDLE_ARCHIVE:?Set to the transferred page-final-kit-bundle.XXXXXX.tar.gz filename}"
sha256sum -c "$PAGE_BUNDLE_ARCHIVE.sha256"
mkdir "${PAGE_BUNDLE_ARCHIVE%.tar.gz}"  # refuses reuse
cd "${PAGE_BUNDLE_ARCHIVE%.tar.gz}"
tar -xzf "../$PAGE_BUNDLE_ARCHIVE"
(cd source && sha256sum -c --quiet ../source.sha256)
(cd inputs && sha256sum -c --quiet ../inputs.sha256)
export PAGE_REPO_ROOT="$PWD/source"
export PAGE_FLU_HIST_FILE="$PWD/inputs/flu_hist.csv"
export PAGE_GATE_RUN_DIR="$PWD/inputs/20260915T0150Z-m1reuse-m2parallel-r5"
export PAGE_RUN_ROOT="$HOME/PAGe-runs/final-kit-2026-27"
export PAGE_RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-final-2026-27-venkata"
export PAGE_N_CORES=8 PAGE_FUTURE_BACKEND=auto
unset PAGE_GATE_OVERRIDE
bash "$PAGE_REPO_ROOT/2026/launch_2026_27_final_kit.sh" --gate-check-only
# Execute the next line only after r5 validation and host selection.
bash "$PAGE_REPO_ROOT/2026/launch_2026_27_final_kit.sh"
```

No Git checkout is needed on Venkata. Gate validation rewrites its audit receipt
on the copied gate; verify the transfer manifest before running the validator.
Install the required R dependencies on Venkata beforehand. Do not transfer the
Asgard installed PAGe library; compile/install from the hashed source there.
Asgard reference BLAS/LAPACK and Venkata OpenBLAS can select different winners.
The platform manifests record the actual R, packages, BLAS/LAPACK and hardware;
this workflow does not assert identical cross-host numerics.

## Preflight without training

To check data and all 11 timing labels independently, install into a fresh
scratch library, supply a fresh writable run directory, and use `--preflight`:

```bash
scratch=$(mktemp -d /tmp/page-final-kit-preflight.XXXXXX)
mkdir "$scratch/r-lib"
OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 \
  R CMD INSTALL --library="$scratch/r-lib" --no-multiarch --with-keep.source "$PAGE_REPO_ROOT/PAGe" > "$scratch/install.log" 2>&1
PAGE_PACKAGE_LIBRARY="$scratch/r-lib" PAGE_RUN_ROOT="$scratch" PAGE_RUN_ID=preflight \
  OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 \
  Rscript "$PAGE_REPO_ROOT/2026/run_2026_27_final_kit.R" --preflight
```

Preflight creates the run directory and removes a temporary write probe. It
creates no models, checkpoints, status file or training artifacts. Passing
preflight establishes the input/label contract; downstream basis support and
boundary checks remain the training API's responsibility.

## Expected outputs and bounded supervision

Under `$PAGE_RUN_ROOT/$PAGE_RUN_ID`:

- `status.tsv`: started → training → complete, or failed.
- `artifacts/`: stage tuning, selections, frozen stages, boundary plans/reports,
  gate evidence, `candidate_pre_holdout.rds`, `outer_training_result.rds`.
- `checkpoints/`: run-local inner tuning progress.
- `final_kit.rds`, `final_kit.sha256`, `kit_validation.rds`: frozen kit, hash and
  saved validation receipt. The kit has the same bytes as the API candidate.
- `run_summary.rds`: selected M0/M1/M2 configurations, applied adoption action,
  explicit keep-M1 fallback flag, boundary histories, elapsed seconds, protocol.
- `timing_labels_v2.rds`, `platform_manifest.rds` and readable `.txt`:
  labels, sessionInfo, R, extSoftVersion, La_version/La_library, BLAS path,
  OS release, CPU, nproc, package versions, thread/backend environment, input
  SHA-256 and per-file source manifest. Git metadata is optional.
- `source_snapshot/`, `source_manifest.csv`, source/install/input hash manifests,
  `package_revision_check.txt`, `gate_check.log`, `gate_receipt.txt` and
  `gate_evidence.sha256` (the latter only for a validated gate).
- `runner.pid`, `runner_identity.tsv`, `watch.tsv`, `watch_terminal.txt`, logs;
  `agent_handoff.txt` on watchdog failure.

Read `tail -n 2 "$PAGE_RUN_ROOT/$PAGE_RUN_ID/watch.tsv"` for compact health.
The watchdog defaults to hourly samples and flags staleness only when both log
and checkpoint ages exceed two hours. It checks PID, start ticks and command
marker, never signals a process, and exits on terminal completion/failure or
identity loss. `--once` performs one sample for diagnosis/smoke tests.
No recurring AI polling is needed. Runner death cannot write R's failed status;
the watchdog records `died_without_terminal_status` separately.

## Verify a completed kit

```bash
export PAGE_RUN_DIR="$PAGE_RUN_ROOT/$PAGE_RUN_ID"
(cd "$PAGE_RUN_DIR" && sha256sum -c final_kit.sha256)
PAGE_PACKAGE_LIBRARY="$PAGE_RUN_DIR/r-lib" Rscript - <<'RS'
.libPaths(c(Sys.getenv("PAGE_PACKAGE_LIBRARY"), .libPaths()))
d <- Sys.getenv("PAGE_RUN_DIR")
s <- read.delim(file.path(d, "status.tsv"))
stopifnot(identical(tail(s$status, 1L), "complete"))
stopifnot(grepl("terminal_state=complete(?: |$)",
               readLines(file.path(d, "watch_terminal.txt")), perl = TRUE))
kit <- readRDS(file.path(d, "final_kit.rds"))
invisible(PAGe::validate_page_kit(kit, mode = "frozen"))
expected <- c("2012-13", "2013-14", "2014-15", "2016-17", "2017-18", "2018-19",
              "2019-20", "2022-23", "2023-24", "2024-25", "2025-26")
stopifnot(setequal(kit$season_selection$training_seasons, expected),
          length(kit$season_selection$holdout_seasons) == 0L)
r <- readRDS(file.path(d, "run_summary.rds"))
v <- readRDS(file.path(d, "kit_validation.rds"))
h <- digest::digest(file = file.path(d, "final_kit.rds"), algo = "sha256", serialize = FALSE)
stopifnot(isTRUE(v$valid), identical(h, v$kit_sha256), identical(h, r$kit_sha256),
          identical(v$governance_id, kit$governance_id),
          r$adoption$applied$action %in% c("use_m2", "keep_m1"))
stopifnot(all(vapply(r$boundaries, function(x) isTRUE(tail(x, 1L)[[1L]]$settled), logical(1))))
cat("frozen kit validated; 11 training seasons; adoption:", r$adoption$applied$action, "\n")
RS
```

Retain the kit together with its source, platform and gate receipts. Hash checks
establish file identity; governed validation checks the frozen kit contract.
Neither is a claim of predictive performance for the unseen 2026-27 season.
