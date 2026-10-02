#!/usr/bin/env bash
set -euo pipefail

: "${PAGE_REPO_ROOT:?Set PAGE_REPO_ROOT on Venkata}"
: "${PAGE_M0_OUT_DIR:?Set PAGE_M0_OUT_DIR on Venkata}"
: "${PAGE_M0_RUN_ID:?Set PAGE_M0_RUN_ID to a fresh run identifier}"

cd "$PAGE_REPO_ROOT"
run_dir="$PAGE_M0_OUT_DIR/$PAGE_M0_RUN_ID"
if [[ -e "$run_dir" ]]; then
  echo "Refusing to overwrite existing M0 run: $run_dir" >&2
  exit 1
fi
mkdir -p "$run_dir"
printf '%s\n' "$$" > "$run_dir/launcher.pid"
export PAGE_M0_OUT_DIR="$run_dir"
export PAGE_FLU_HIST_FILE="${PAGE_FLU_HIST_FILE:-/home/yeli/FLU/flu_testing_data.csv}"
export PAGE_M0_OUTER_WORKERS="${PAGE_M0_OUTER_WORKERS:-4}"
export PAGE_M0_INNER_CORES="${PAGE_M0_INNER_CORES:-1}"
export PAGE_M0_TIMING_MODE="${PAGE_M0_TIMING_MODE:-fractional}"
export PAGE_PACKAGE_LIBRARY="${PAGE_PACKAGE_LIBRARY:-$PAGE_REPO_ROOT/r-lib}"
export R_LIBS_USER="$PAGE_PACKAGE_LIBRARY"
mkdir -p "$PAGE_PACKAGE_LIBRARY"
R CMD INSTALL --preclean --library="$PAGE_PACKAGE_LIBRARY" --no-multiarch --with-keep.source PAGe > "$run_dir/package_install.log" 2>&1
Rscript -e '
  lib <- Sys.getenv("PAGE_PACKAGE_LIBRARY")
  .libPaths(unique(c(lib, .libPaths())))
  if (!identical(normalizePath(find.package("PAGe", lib.loc = lib), mustWork = TRUE),
                 normalizePath(file.path(lib, "PAGe"), mustWork = TRUE))) {
    stop("PAGe did not load from the repo-local library")
  }
  if (!("validate_season_selection" %in% getNamespaceExports("PAGe"))) {
    stop("repo-local PAGe is stale: validate_season_selection is not exported")
  }
' > "$run_dir/package_api_check.log" 2>&1
Rscript scripts/run_m0_outer_holdouts_venkata.R >> "$run_dir/run.log" 2>&1
