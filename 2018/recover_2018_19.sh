#!/usr/bin/env bash
set -u

# Detached, one-shot recovery for the governed 2018-19 cycle. It only
# launches the approved lower-edge M1 expansion after the initial run has
# failed specifically at the M1 boundary gate; all other failures remain for
# manual diagnosis.

artifact_root="${PAGE_ARTIFACT_ROOT:-/home/yeli/PAGe-bcc-artifacts/asgard-archive-20260812}"
base_id="2018-final2"
expanded_id="2018-final2-expanded"
base_dir="$artifact_root/$base_id"
expanded_dir="$artifact_root/$expanded_id"
repo_root="/home/yeli/repos/PAGe"
bcc_dir="$artifact_root/bcc-2018-19"
session="page2018-final2-expanded"

while [ ! -f "$base_dir/process.exit" ]; do
  sleep 300
done

base_code=$(tr -d '[:space:]' < "$base_dir/process.exit")
if [ "$base_code" = "0" ]; then
  printf '%s\n' "initial_success_no_recovery" > "$base_dir/recovery_status.txt"
  exit 0
fi

if ! grep -q "M1 tuning has unresolved non-null boundary" "$base_dir/run.log"; then
  printf '%s\n' "initial_failed_non_boundary=$base_code" > "$base_dir/recovery_status.txt"
  exit 2
fi

if [ -e "$expanded_dir" ]; then
  printf '%s\n' "expanded_run_already_exists" > "$base_dir/recovery_status.txt"
  exit 3
fi

mkdir -p "$expanded_dir"
printf '%s\n' "recovering M1 lower-edge boundary after initial exit=$base_code" > "$base_dir/recovery_status.txt"

tmux new-session -d -s "$session" \
  "cd '$repo_root' && env PAGE_ARTIFACT_ROOT='$artifact_root' PAGE_RUN_ID='$expanded_id' PAGE_M1_GRID_PROFILE=expanded_slope_lower Rscript --vanilla 2018/run_2018_cycle.R > '$expanded_dir/run.log' 2>&1; printf '%s\\n' \$? > '$expanded_dir/process.exit'"

while [ ! -f "$expanded_dir/process.exit" ]; do
  sleep 300
done

expanded_code=$(tr -d '[:space:]' < "$expanded_dir/process.exit")
if [ "$expanded_code" != "0" ]; then
  printf '%s\n' "expanded_retune_failed=$expanded_code" > "$expanded_dir/recovery_status.txt"
  exit 4
fi

env PAGE_ARTIFACT_ROOT="$artifact_root" PAGE_RUN_ID="$expanded_id" \
  Rscript --vanilla 2018/replay_2018_19.R > "$expanded_dir/replay.log" 2>&1
replay_code=$?
printf '%s\n' "$replay_code" > "$expanded_dir/replay.exit"
if [ "$replay_code" != "0" ]; then
  printf '%s\n' "expanded_replay_failed=$replay_code" > "$expanded_dir/recovery_status.txt"
  exit 5
fi

env PAGE_ARTIFACT_ROOT="$artifact_root" PAGE_RUN_ID="$expanded_id" \
  PAGE_BCC_RUN_DIR="$bcc_dir" Rscript --vanilla 2018/compare_bcc_2018_19.R > "$expanded_dir/compare.log" 2>&1
compare_code=$?
printf '%s\n' "$compare_code" > "$expanded_dir/compare.exit"
if [ "$compare_code" != "0" ]; then
  printf '%s\n' "expanded_compare_failed=$compare_code" > "$expanded_dir/recovery_status.txt"
  exit 6
fi

printf '%s\n' "expanded_complete" > "$expanded_dir/recovery_status.txt"
