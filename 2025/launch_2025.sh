#!/usr/bin/env bash
set -euo pipefail

export PAGE_FLU_HIST_FILE="${PAGE_FLU_HIST_FILE:-/home/yeli/FLU/flu_testing_data.csv}"
export PAGE_ARTIFACT_ROOT="${PAGE_ARTIFACT_ROOT:-/home/yeli/PAGe-bcc-artifacts/asgard-archive-20260812}"
export PAGE_RUN_ID="${PAGE_RUN_ID:-2025-26-e2e-phase2-min-gain-20260911}"

run_dir="$PAGE_ARTIFACT_ROOT/$PAGE_RUN_ID"
mkdir -p "$run_dir"
printf '%s\n' "$$" > "$run_dir/runner.pid"
exec Rscript 2025/run_2025_cycle.R >> "$run_dir/run.log" 2>&1
