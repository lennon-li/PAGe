#!/usr/bin/env bash
set -u

base_root="/mnt/nfsv4/Users/yeli/PAGe-artifacts/seasonal-archive-20260818"
main_status="$base_root/manuscript-batch-20260902-r3/batch_status.tsv"
rescue_status="$base_root/manuscript-rescue-20260902-r4/rescue_status.tsv"
results_dir="$base_root/manuscript-results-20260902"
output_prefix="$results_dir/holdout_reconciliation"
reconcile="/home/yeli/PAGe-holdout-runs-20260901-95c1c9f/source/scripts/reconcile_holdout_artifacts.R"
rlib="/home/yeli/PAGe-holdout-runs-20260901-95c1c9f/Rlib:/home/yeli/R/x86_64-pc-linux-gnu-library/4.6"

mkdir -p "$results_dir"
while ! grep -q $'\tcomplete\tall\t' "$main_status" 2>/dev/null; do
  sleep 300
done
while ! grep -q $'\tcomplete\tall\t' "$rescue_status" 2>/dev/null; do
  sleep 300
done

R_LIBS_USER="$rlib" Rscript "$reconcile" \
  --artifact-root "$base_root" \
  --output-prefix "$output_prefix" \
  --strict > "$results_dir/reconciliation.log" 2>&1
rc=$?
printf '%s\t%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$rc" > "$results_dir/finalizer_status.tsv"
exit "$rc"
