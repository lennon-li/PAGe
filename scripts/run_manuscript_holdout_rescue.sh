#!/usr/bin/env bash
set -u

# Zero-token follow-up for the two seasons skipped by an earlier launcher
# control-file race.  It starts only after the main seven-season batch has
# recorded completion, so BCC remains limited to two 7-core jobs.

base_root="/mnt/nfsv4/Users/yeli/PAGe-artifacts/seasonal-archive-20260818"
main_status="$base_root/manuscript-batch-20260902-r3/batch_status.tsv"
rescue_id="manuscript-rescue-20260902-r4"
rescue_dir="$base_root/$rescue_id"
script_path="/home/yeli/PAGe-holdout-runs-20260901-95c1c9f/source/scripts/run_manuscript_holdout.R"
watchdog_path="/home/yeli/PAGe-holdout-runs-20260901-95c1c9f/watchdog_runtime.sh"
repo_root="/home/yeli/PAGe-holdout-runs-20260901-95c1c9f/source"
data_path="/home/yeli/repos/PAGe/data/flu_testing_data.csv"
rlib="/home/yeli/PAGe-holdout-runs-20260901-95c1c9f/Rlib:/home/yeli/R/x86_64-pc-linux-gnu-library/4.6"
mkdir -p "$rescue_dir"
status="$rescue_dir/rescue_status.tsv"
printf 'timestamp_utc\tevent\tseason\tpid\treturn_code\tdetail\n' > "$status"

record() {
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$1" "$2" "$3" "$4" "$5" >> "$status"
}

record waiting all "" "" "main batch completion"
while ! grep -q $'\tcomplete\tall\t' "$main_status" 2>/dev/null; do
  sleep 300
done

for season in 2014-15 2016-17; do
  run_id="${season}-current-api-20260902-r4"
  run_dir="$base_root/$season/runs/$run_id"
  mkdir -p "$run_dir"
  nohup bash -c '
    run_dir="$1"
    season="$2"
    export PAGE_HOLDOUT="$season"
    export PAGE_LOAD_MODE=installed
    export PAGE_REPO_ROOT="$3"
    export PAGE_RUN_ID="${season}-current-api-20260902-r4"
    export PAGE_RUN_DIR="$run_dir"
    export PAGE_FLU_HIST_FILE="$4"
    export PAGE_N_CORES=7
    export R_LIBS_USER="$5"
    exec Rscript "$6"
  ' _ "$run_dir" "$season" "$repo_root" "$data_path" "$rlib" "$script_path" \
    > "$rescue_dir/${season}.log" 2>&1 &
  pid=$!
  printf '%s\n' "$pid" > "$run_dir/runner.pid"
  record launched "$season" "$pid" "" "$run_dir"
  nohup bash "$watchdog_path" "$run_dir" 600 > /dev/null 2>&1 &
done

for season in 2014-15 2016-17; do
  run_dir="$base_root/$season/runs/${season}-current-api-20260902-r4"
  pid=$(cat "$run_dir/runner.pid")
  wait "$pid"
  rc=$?
  record terminal "$season" "$pid" "$rc" "child process exited"
done
record complete all "" "0" "rescue supervisor complete"
