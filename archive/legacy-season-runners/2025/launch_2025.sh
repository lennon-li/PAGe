#!/usr/bin/env bash
set -euo pipefail

# No default: the old fallback was a truncated extract (2025-26 ends at
# weekF 28 of 53) that silently trained the 2026-09-17 campaign.
: "${PAGE_FLU_HIST_FILE:?Set PAGE_FLU_HIST_FILE to the authorized CSV}"
export PAGE_FLU_HIST_FILE
export PAGE_ARTIFACT_ROOT="${PAGE_ARTIFACT_ROOT:-/home/yeli/PAGe-bcc-artifacts/asgard-archive-20260812}"
export PAGE_RUN_ID="${PAGE_RUN_ID:-2025-26-e2e-phase2-min-gain-20260911}"

run_dir="$PAGE_ARTIFACT_ROOT/$PAGE_RUN_ID"
mkdir -p "$run_dir"
printf '%s\n' "$$" > "$run_dir/runner.pid"
exec Rscript 2025/run_2025_cycle.R >> "$run_dir/run.log" 2>&1
