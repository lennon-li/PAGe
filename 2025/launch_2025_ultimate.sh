#!/usr/bin/env bash
set -euo pipefail

# Detached launcher for the 2025-26 ultimate outer-fold run.
# Requires PAGE_RUN_ID in the environment; refuses to reuse an existing run dir.
cd /home/yeli/repos/PAGe

export PAGE_FLU_HIST_FILE="${PAGE_FLU_HIST_FILE:-/home/yeli/FLU/flu_testing_data.csv}"
export PAGE_RUN_ROOT="${PAGE_RUN_ROOT:-/home/yeli/repos/PAGe/results/manuscript/nested-outer-2025-26-ultimate-20260911}"
: "${PAGE_RUN_ID:?PAGE_RUN_ID must be set}"

# Nested future workers load an installed package. Build the current source
# into a repo-local library so workers cannot silently use an older user-level
# installation than the source loaded by the runner.
mkdir -p /home/yeli/repos/PAGe/r-lib
R CMD INSTALL --library=/home/yeli/repos/PAGe/r-lib --no-multiarch --with-keep.source PAGe >/tmp/page-2025-package-install.log 2>&1
export R_LIBS_USER="/home/yeli/repos/PAGe/r-lib"
export PAGE_PACKAGE_LIBRARY="/home/yeli/repos/PAGe/r-lib"

run_dir="$PAGE_RUN_ROOT/$PAGE_RUN_ID"
if [[ -e "$run_dir/status.tsv" || -d "$run_dir/artifacts" ]]; then
  echo "refusing to overwrite existing run: $run_dir" >&2
  exit 1
fi
mkdir -p "$run_dir"
printf '%s\n' "$$" > "$run_dir/runner.pid"
exec Rscript 2025/run_2025_ultimate.R >> "$run_dir/run.log" 2>&1
