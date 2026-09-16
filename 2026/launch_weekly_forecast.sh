#!/usr/bin/env bash
# Detached launcher for the weekly frozen-kit forecast.
# Invoke from a chosen Linux host shell; never from inside a PID sandbox.
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
export PAGE_REPO_ROOT="${PAGE_REPO_ROOT:-$(dirname -- "$script_dir")}"
PAGE_REPO_ROOT=$(cd -- "$PAGE_REPO_ROOT" && pwd)
cd "$PAGE_REPO_ROOT"
export OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 MKL_NUM_THREADS=1

dry_run=0
case "${1:-}" in
  --dry-run) dry_run=1 ;;
  "") ;;
  *) echo "usage: $0 [--dry-run]" >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || exit 2

: "${PAGE_KIT_PATH:?Set PAGE_KIT_PATH to the frozen final kit RDS}"
: "${PAGE_KIT_SHA256:?Set PAGE_KIT_SHA256 to the expected kit sha256}"
: "${PAGE_WEEKLY_OUT_ROOT:?Set PAGE_WEEKLY_OUT_ROOT for weekly run directories}"
: "${PAGE_FORECAST_RUN_ID:?Set PAGE_FORECAST_RUN_ID to a fresh week/run identifier}"
[[ "$PAGE_FORECAST_RUN_ID" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || {
  echo 'PAGE_FORECAST_RUN_ID must be a simple identifier' >&2; exit 1;
}
[[ -f "$PAGE_KIT_PATH" ]] || {
  echo "PAGE_KIT_PATH does not exist: $PAGE_KIT_PATH; refusing to launch (fail closed)" >&2; exit 1;
}

for program in setsid nohup Rscript sha256sum find sort awk; do
  command -v "$program" >/dev/null
done

run_dir="$PAGE_WEEKLY_OUT_ROOT/$PAGE_FORECAST_RUN_ID"
[[ ! -e "$run_dir" && ! -L "$run_dir" ]] || {
  echo "refusing to overwrite existing week directory: $run_dir" >&2; exit 1;
}
export PAGE_WEEKLY_OUT_ROOT="$(dirname -- "$run_dir")" PAGE_WEEKLY_RUN_DIR="$run_dir"

if [[ "$dry_run" -eq 1 ]]; then
  exec Rscript "$PAGE_REPO_ROOT/2026/run_weekly_forecast.R" --dry-run
fi

host_init=$(cat /proc/1/comm)
if [[ "$host_init" != systemd && "$host_init" != init ]]; then
  echo 'launch from a host shell (PID 1 must be systemd/init); setsid cannot escape a PID sandbox' >&2
  exit 1
fi

mkdir -p "$PAGE_WEEKLY_OUT_ROOT"
mkdir "$run_dir"
run_dir=$(cd -- "$run_dir" && pwd)
export PAGE_WEEKLY_OUT_ROOT="$(dirname -- "$run_dir")" PAGE_WEEKLY_RUN_DIR="$run_dir"
printf '%s\n' "run_id=$PAGE_FORECAST_RUN_ID" "kit_path=$PAGE_KIT_PATH" \
  "kit_sha256_expected=$PAGE_KIT_SHA256" "out_root=$PAGE_WEEKLY_OUT_ROOT" \
  > "$run_dir/launch_receipt.txt"

# Optional run-local library: PAGE_WEEKLY_INSTALL_LIB=1 installs PAGe into
# $run_dir/r-lib and pins it; unset for an ambient, already-installed PAGe.
if [[ "${PAGE_WEEKLY_INSTALL_LIB:-0}" == 1 ]]; then
  export PAGE_PACKAGE_LIBRARY="$run_dir/r-lib"
  mkdir "$PAGE_PACKAGE_LIBRARY"
  R CMD INSTALL --library="$PAGE_PACKAGE_LIBRARY" --no-multiarch --with-keep.source \
    "$PAGE_REPO_ROOT/PAGe" > "$run_dir/package_install.log" 2>&1
  dependency_libraries=$(Rscript -e 'cat(paste(.libPaths(), collapse = .Platform$path.sep))')
  export R_LIBS_USER="$PAGE_PACKAGE_LIBRARY:$dependency_libraries"
fi

watch_loop() {
  local id_file="$PAGE_WEEKLY_RUN_DIR/runner_identity.tsv"
  local watch_file="$PAGE_WEEKLY_RUN_DIR/watch.tsv"
  local status_file="$PAGE_WEEKLY_RUN_DIR/status.tsv"
  local interval="${PAGE_WATCH_INTERVAL:-60}"
  [[ -f "$watch_file" ]] || printf 'timestamp_utc\tstate\tpid\tpid_alive\tidentity_ok\tstage\n' > "$watch_file"
  while true; do
    local now pid start_ticks marker final_status alive identity state
    now=$(date -u +%FT%TZ)
    pid=$(awk -F '\t' '$1 == "pid" { print $2 }' "$id_file" 2>/dev/null || true)
    start_ticks=$(awk -F '\t' '$1 == "start_ticks" { print $2 }' "$id_file" 2>/dev/null || true)
    marker=$(awk -F '\t' '$1 == "cmd_marker" { print $2 }' "$id_file" 2>/dev/null || true)
    final_status=$(awk -F '\t' 'NR > 1 { last = $2 } END { print last }' "$status_file" 2>/dev/null || true)
    alive=0
    identity=0
    local proc_stat proc_fields
    if [[ "$pid" =~ ^[1-9][0-9]*$ ]] && proc_stat=$(cat "/proc/$pid/stat" 2>/dev/null); then
      proc_fields=${proc_stat##*) }
      local proc_state ticks cmdline
      proc_state=$(awk '{print $1}' <<< "$proc_fields")
      ticks=$(awk '{print $20}' <<< "$proc_fields")
      if [[ "$proc_state" != Z && "$proc_state" != X ]]; then
        alive=1
        cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)
        if [[ "$start_ticks" =~ ^[0-9]+$ && "$ticks" == "$start_ticks" &&
              -n "$marker" && "$cmdline" == *"$marker"* ]]; then
          identity=1
        fi
      fi
    fi
    if [[ "$final_status" == "complete" || "$final_status" == "failed" ]]; then
      state="$final_status"
    elif [[ "$alive" -eq 0 ]]; then
      state="died_without_terminal_status"
    elif [[ "$identity" -eq 0 ]]; then
      state="pid_reused"
    else
      state="running"
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$now" "$state" "${pid:-NA}" "$alive" \
      "$identity" "${final_status:-none}" >> "$watch_file"
    if [[ "$state" != "running" ]]; then
      printf '%s terminal_state=%s\n' "$now" "$state" > "$PAGE_WEEKLY_RUN_DIR/watch_terminal.txt"
      break
    fi
    sleep "$interval"
  done
}
export -f watch_loop

launch_failed() {
  local rc=$?
  if [[ ! -f "$run_dir/status.tsv" ]]; then
    printf 'timestamp_utc\tstatus\tdetail\n' > "$run_dir/status.tsv"
  fi
  printf '%s\tfailed\tlauncher failed before detach; inspect package_install.log\n' \
    "$(date -u +%FT%TZ)" >> "$run_dir/status.tsv"
  exit "$rc"
}
trap launch_failed ERR

setsid nohup bash -c '
  set -euo pipefail
  runner_script="$1"
  shift
  proc_stat=$(cat "/proc/$$/stat")
  proc_fields=${proc_stat##*) }
  start_ticks=$(awk "{print \$20}" <<< "$proc_fields")
  printf "%s\n" "$$" > "$PAGE_WEEKLY_RUN_DIR/runner.pid"
  printf "pid\t%s\nstart_ticks\t%s\ncmd_marker\t%s\n" \
    "$$" "$start_ticks" "$runner_script" > "$PAGE_WEEKLY_RUN_DIR/runner_identity.tsv.tmp"
  mv "$PAGE_WEEKLY_RUN_DIR/runner_identity.tsv.tmp" "$PAGE_WEEKLY_RUN_DIR/runner_identity.tsv"
  exec Rscript "$runner_script" "$@"
' page-weekly-runner "$PAGE_REPO_ROOT/2026/run_weekly_forecast.R" \
  >> "$run_dir/weekly_forecast.log" 2>&1 < /dev/null &
for ((attempt = 0; attempt < 100; attempt++)); do
  if [[ -s "$run_dir/runner_identity.tsv" ]]; then
    setsid nohup bash -c 'watch_loop' > "$run_dir/watchdog.log" 2>&1 < /dev/null &
    printf 'launched pid=%s run_dir=%s; detached identity watchdog started\n' \
      "$(cat "$run_dir/runner.pid")" "$run_dir"
    exit 0
  fi
  sleep 0.05
done
echo "runner identity was not published; inspect $run_dir/weekly_forecast.log (do not relaunch into this directory)" >&2
exit 1
