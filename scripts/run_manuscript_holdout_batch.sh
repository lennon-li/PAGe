#!/usr/bin/env bash
set -u

# Zero-token BCC supervisor for the manuscript's remaining governed holdouts.
# It keeps two 7-core R processes active on the 16-core host and starts the
# next season only after a prior child reaches a terminal state.

base_root="/mnt/nfsv4/Users/yeli/PAGe-artifacts/seasonal-archive-20260818"
archive_run_id="manuscript-batch-20260902-r3"
script_path="/home/yeli/PAGe-holdout-runs-20260901-95c1c9f/source/scripts/run_manuscript_holdout.R"
watchdog_path="/home/yeli/PAGe-holdout-runs-20260901-95c1c9f/watchdog_runtime.sh"
repo_root="/home/yeli/PAGe-holdout-runs-20260901-95c1c9f/source"
data_path="/home/yeli/repos/PAGe/data/flu_testing_data.csv"
rlib="/home/yeli/PAGe-holdout-runs-20260901-95c1c9f/Rlib:/home/yeli/R/x86_64-pc-linux-gnu-library/4.6"
batch_dir="$base_root/$archive_run_id"
batch_status="$batch_dir/batch_status.tsv"
mkdir -p "$batch_dir"

printf 'timestamp_utc\tevent\tseason\tpid\treturn_code\tdetail\n' > "$batch_status"

holdouts=(2014-15 2016-17 2017-18 2018-19 2019-20 2022-23 2023-24 2024-25 2025-26)
pending_index=0
active_count=0
declare -A active_pid
declare -A active_dir

record() {
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$1" "$2" "$3" "$4" "$5" >> "$batch_status"
}

launch_one() {
  local season="$1"
  local run_id="${season}-current-api-20260902-r3"
  local run_dir="$base_root/$season/runs/$run_id"
  existing=$(find "$run_dir" -mindepth 1 -type f \
    ! -name runner.pid ! -name watchdog.tsv -print -quit 2>/dev/null)
  if [ -e "$run_dir" ] && [ -n "$existing" ]; then
    record existing "$season" "" "" "non-empty output directory; not overwritten"
    return 1
  fi
  mkdir -p "$run_dir"
  nohup bash -c '
    run_dir="$1"
    season="$2"
    export PAGE_HOLDOUT="$season"
    export PAGE_LOAD_MODE=installed
    export PAGE_REPO_ROOT="$3"
    export PAGE_RUN_ID="${season}-current-api-20260902-r3"
    export PAGE_RUN_DIR="$run_dir"
    export PAGE_FLU_HIST_FILE="$4"
    export PAGE_N_CORES=7
    export R_LIBS_USER="$5"
    exec Rscript "$6"
  ' _ "$run_dir" "$season" "$repo_root" "$data_path" "$rlib" "$script_path" \
    > "$batch_dir/${season}.log" 2>&1 &
  local pid=$!
  printf '%s\n' "$pid" > "$run_dir/runner.pid"
  active_pid["$season"]="$pid"
  active_dir["$season"]="$run_dir"
  active_count=$((active_count + 1))
  record launched "$season" "$pid" "" "$run_dir"
  nohup bash "$watchdog_path" "$run_dir" 600 > /dev/null 2>&1 &
  return 0
}

while [ "$pending_index" -lt "${#holdouts[@]}" ] || [ "$active_count" -gt 0 ]; do
  while [ "$active_count" -lt 2 ] && [ "$pending_index" -lt "${#holdouts[@]}" ]; do
    season="${holdouts[$pending_index]}"
    pending_index=$((pending_index + 1))
    launch_one "$season" || true
  done

  for season in "${!active_pid[@]}"; do
    pid="${active_pid[$season]}"
    if ! kill -0 "$pid" 2>/dev/null; then
      wait "$pid"
      rc=$?
      record terminal "$season" "$pid" "$rc" "child process exited"
      unset 'active_pid[$season]'
      unset 'active_dir[$season]'
      active_count=$((active_count - 1))
    fi
  done

  [ "$pending_index" -lt "${#holdouts[@]}" ] || [ "$active_count" -gt 0 ] || break
  sleep 300
done

record complete "all" "" "0" "batch supervisor complete"
