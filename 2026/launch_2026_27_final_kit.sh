#!/usr/bin/env bash
# Invoke from the chosen Linux host shell only, after r5 validation.
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
export PAGE_REPO_ROOT="${PAGE_REPO_ROOT:-$(dirname -- "$script_dir")}"
PAGE_REPO_ROOT=$(cd -- "$PAGE_REPO_ROOT" && pwd)
cd "$PAGE_REPO_ROOT"
export OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 MKL_NUM_THREADS=1
export PAGE_FUTURE_BACKEND="${PAGE_FUTURE_BACKEND:-auto}"
export PAGE_N_CORES="${PAGE_N_CORES:-8}"
case "${1:-}" in
  --gate-check-only) gate_only=1 ;;
  "") gate_only=0 ;;
  *) echo "usage: $0 [--gate-check-only]" >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || exit 2
: "${PAGE_GATE_RUN_DIR:?PAGE_GATE_RUN_DIR must name the 2025-26 r5 run}"
expected_gate_id=20260915T0150Z-m1reuse-m2parallel-r5

check_gate() {
  local last state
  if [[ "${PAGE_GATE_OVERRIDE:-}" == I_ACCEPT_UNVALIDATED_GATE ]]; then
    printf 'GATE OVERRIDE: I_ACCEPT_UNVALIDATED_GATE; NOT FOR PRODUCTION; gate=%s\n' "$PAGE_GATE_RUN_DIR"
    return 0
  fi
  if [[ -n "${PAGE_GATE_OVERRIDE:-}" ]]; then
    echo 'GATE REFUSED: invalid PAGE_GATE_OVERRIDE value' >&2; return 1
  fi
  if [[ "$(basename -- "$PAGE_GATE_RUN_DIR")" != "$expected_gate_id" ]]; then
    echo "GATE REFUSED: expected r5 run ID $expected_gate_id" >&2; return 1
  fi
  last=$(awk -F '\t' 'NR > 1 && NF { last=$2 } END { print last }' "$PAGE_GATE_RUN_DIR/status.tsv" 2>/dev/null) || {
    echo 'GATE REFUSED: missing/unreadable status.tsv' >&2; return 1;
  }
  if [[ "$last" != complete ]]; then
    printf 'GATE REFUSED: r5 status=%s; require complete and independent validation\n' "${last:-missing}" >&2
    return 1
  fi
  if [[ -f "$PAGE_GATE_RUN_DIR/watch_terminal.txt" ]]; then
    state=$(sed -n 's/.*terminal_state=\([^[:space:]]*\).*/\1/p' "$PAGE_GATE_RUN_DIR/watch_terminal.txt")
    if [[ "$state" != complete ]]; then
      printf 'GATE REFUSED: watch_terminal state=%s\n' "${state:-unrecognized}" >&2; return 1
    fi
  fi
  # Actual validator CLI; it writes independent_validation.{rds,txt} on success.
  if ! Rscript "$PAGE_REPO_ROOT/2025/validate_2025_ultimate.R" "--run_dir=$PAGE_GATE_RUN_DIR"; then
    echo 'GATE REFUSED: independent r5 validator failed' >&2; return 1
  fi
  echo "GATE PASSED: r5 complete and independently validated; gate=$PAGE_GATE_RUN_DIR"
}

# This branch can never install, detach, create a final-kit run, or start a fit.
if [[ "$gate_only" -eq 1 ]]; then
  check_gate
  exit $?
fi
host_init=$(cat /proc/1/comm)
if [[ "$host_init" != systemd && "$host_init" != init ]]; then
  echo 'launch from a host shell (PID 1 must be systemd/init); setsid cannot escape a PID sandbox' >&2
  exit 1
fi
for program in setsid nohup R Rscript sha256sum find sort awk; do
  command -v "$program" >/dev/null
done
: "${PAGE_FLU_HIST_FILE:?Set PAGE_FLU_HIST_FILE to the authorized CSV}"
: "${PAGE_RUN_ID:?Set PAGE_RUN_ID to a fresh run identifier}"
[[ "$PAGE_RUN_ID" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || {
  echo 'PAGE_RUN_ID must be a simple identifier' >&2; exit 1;
}
[[ "$PAGE_N_CORES" =~ ^[1-9][0-9]*$ ]] || { echo 'invalid PAGE_N_CORES' >&2; exit 1; }
[[ -f "$PAGE_FLU_HIST_FILE" ]] || { echo 'authorized CSV is missing' >&2; exit 1; }
export PAGE_RUN_ROOT="${PAGE_RUN_ROOT:-$PAGE_REPO_ROOT/results/final-kit-2026-27}"
run_dir="$PAGE_RUN_ROOT/$PAGE_RUN_ID"
[[ ! -e "$run_dir" && ! -L "$run_dir" ]] || { echo "refusing to overwrite existing run: $run_dir" >&2; exit 1; }
gate_log=$(mktemp)
trap 'rm -f -- "$gate_log"' EXIT
if ! check_gate > "$gate_log" 2>&1; then
  cat "$gate_log" >&2
  exit 1
fi
cat "$gate_log"
mkdir -p "$PAGE_RUN_ROOT"
mkdir "$run_dir"
run_dir=$(cd -- "$run_dir" && pwd)
export PAGE_RUN_ROOT="$(dirname -- "$run_dir")" PAGE_RUN_DIR="$run_dir"
cp "$gate_log" "$run_dir/gate_check.log"
# Failures before detach also leave a compact terminal status.
launch_failed() {
  local rc=$?
  if [[ ! -f "$run_dir/status.tsv" ]]; then
    printf 'timestamp_utc\tstatus\tdetail\n' > "$run_dir/status.tsv"
  fi
  printf '%s\tfailed\tlauncher failed before detach; inspect install/preflight logs\n' "$(date -u +%FT%TZ)" >> "$run_dir/status.tsv"
  exit "$rc"
}
trap launch_failed ERR
printf '%s\n' "gate_run_dir=$PAGE_GATE_RUN_DIR" "gate_override=${PAGE_GATE_OVERRIDE:-}" > "$run_dir/gate_receipt.txt"
# Bind the validation receipt to its evidence without copying private gate artifacts.
if [[ "${PAGE_GATE_OVERRIDE:-}" != I_ACCEPT_UNVALIDATED_GATE ]]; then
  sha256sum "$PAGE_GATE_RUN_DIR/status.tsv" "$PAGE_GATE_RUN_DIR/watch_terminal.txt" \
    "$PAGE_GATE_RUN_DIR/independent_validation.rds" \
    "$PAGE_GATE_RUN_DIR/artifacts/outer_fold_result.rds" > "$run_dir/gate_evidence.sha256"
fi
source_manifest() {
  { find PAGe -type f -print0
    printf '%s\0' 2026/run_2026_27_final_kit.R 2026/launch_2026_27_final_kit.sh \
      2026/watch_2026_27_final_kit.sh 2025/validate_2025_ultimate.R docs/final-kit-2026-27-runbook.md
  } | LC_ALL=C sort -z | xargs -0 sha256sum
}
source_manifest > "$run_dir/source_before_install.sha256"
sha256sum "$PAGE_FLU_HIST_FILE" > "$run_dir/input.sha256"
export PAGE_PACKAGE_LIBRARY="$run_dir/r-lib"
mkdir "$PAGE_PACKAGE_LIBRARY"
R CMD INSTALL --library="$PAGE_PACKAGE_LIBRARY" --no-multiarch --with-keep.source PAGe \
  > "$run_dir/package_install.log" 2>&1
# Preserve dependency search paths while putting the immutable run library first.
dependency_libraries=$(Rscript -e 'cat(paste(.libPaths(), collapse = .Platform$path.sep))')
export R_LIBS_USER="$PAGE_PACKAGE_LIBRARY:$dependency_libraries"
source_manifest > "$run_dir/source_after_install.sha256"
cmp "$run_dir/source_before_install.sha256" "$run_dir/source_after_install.sha256"
sha256sum -c --quiet "$run_dir/source_before_install.sha256"
Rscript -e '
  lib <- normalizePath(Sys.getenv("PAGE_PACKAGE_LIBRARY"), mustWork = TRUE)
  .libPaths(unique(c(lib, .libPaths())))
  pkg <- normalizePath(find.package("PAGe"), mustWork = TRUE)
  stopifnot(identical(pkg, file.path(lib, "PAGe")))
  src_version <- unname(read.dcf("PAGe/DESCRIPTION")[1, "Version"])
  stopifnot(identical(as.character(packageVersion("PAGe")), src_version))
  files <- c("PAGe/DESCRIPTION", "PAGe/NAMESPACE", list.files("PAGe/R", full.names = TRUE))
  rdb <- file.path(pkg, "R", "PAGe.rdb")
  stopifnot(file.info(rdb)$mtime >= max(file.info(files)$mtime))
  installed_files <- sort(list.files(pkg, recursive = TRUE, full.names = TRUE))
  hashes <- vapply(installed_files, digest::digest, character(1), file = TRUE,
                   algo = "sha256", serialize = FALSE)
  write.table(data.frame(path = installed_files, sha256 = hashes),
    file.path(Sys.getenv("PAGE_RUN_DIR"), "installed_package_manifest.tsv"),
    sep = "\t", row.names = FALSE, quote = FALSE)
  cat("verified installed PAGe", src_version, "at", pkg, "\n")
' > "$run_dir/package_revision_check.txt" 2>&1
Rscript "$PAGE_REPO_ROOT/2026/run_2026_27_final_kit.R" --preflight > "$run_dir/preflight.log" 2>&1
cat "$run_dir/preflight.log"
# Recheck content immediately before detach (also detects added source files).
source_manifest > "$run_dir/source_before_launch.sha256"
cmp "$run_dir/source_before_install.sha256" "$run_dir/source_before_launch.sha256"
sha256sum -c --quiet "$run_dir/input.sha256"
trap - ERR
# The detached child publishes its own identity atomically, then retains it via exec.
setsid nohup bash -c '
  set -euo pipefail
  runner_script="$1"
  proc_stat=$(cat "/proc/$$/stat")
  proc_fields=${proc_stat##*) }
  start_ticks=$(awk "{print \$20}" <<< "$proc_fields")
  printf "%s\n" "$$" > "$PAGE_RUN_DIR/runner.pid"
  printf "pid\t%s\nstart_ticks\t%s\ncmd_marker\t%s\n" \
    "$$" "$start_ticks" "$runner_script" > "$PAGE_RUN_DIR/runner_identity.tsv.tmp"
  mv "$PAGE_RUN_DIR/runner_identity.tsv.tmp" "$PAGE_RUN_DIR/runner_identity.tsv"
  exec Rscript "$runner_script"
' page-2026-runner "$PAGE_REPO_ROOT/2026/run_2026_27_final_kit.R" \
  >> "$run_dir/run.log" 2>&1 < /dev/null &
for ((attempt = 0; attempt < 100; attempt++)); do
  if [[ -s "$run_dir/runner_identity.tsv" ]]; then
    setsid nohup bash "$PAGE_REPO_ROOT/2026/watch_2026_27_final_kit.sh" \
      > "$run_dir/watchdog.log" 2>&1 < /dev/null &
    printf 'launched pid=%s run_dir=%s; detached identity watchdog started\n' "$(cat "$run_dir/runner.pid")" "$run_dir"
    exit 0
  fi
  sleep 0.05
done
echo "runner identity was not published; inspect $run_dir/run.log (do not relaunch into this directory)" >&2
exit 1
