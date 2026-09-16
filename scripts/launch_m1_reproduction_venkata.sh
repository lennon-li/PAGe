#!/usr/bin/env bash
# Launch the M1-only reproduction on Venkata with a verified source build and a
# zero-token watchdog. Refuses to reuse a run directory.
set -euo pipefail

: "${PAGE_REPO_ROOT:?Set PAGE_REPO_ROOT (source tree copied from Asgard)}"
: "${PAGE_M1_OUT_DIR:?Set PAGE_M1_OUT_DIR (artifact root)}"
: "${PAGE_M1_RUN_ID:?Set PAGE_M1_RUN_ID to a fresh run identifier}"
: "${PAGE_M1_INPUT_DIR:?Set PAGE_M1_INPUT_DIR (r4 reference inputs + manifests)}"
export PAGE_FLU_HIST_FILE="${PAGE_FLU_HIST_FILE:-/home/yeli/FLU/flu_testing_data.csv}"
export PAGE_N_CORES="${PAGE_N_CORES:-8}"

run_dir="$PAGE_M1_OUT_DIR/$PAGE_M1_RUN_ID"
if [[ -e "$run_dir" ]]; then
  echo "Refusing to overwrite existing run: $run_dir" >&2
  exit 1
fi
mkdir -p "$run_dir"

# Source identity: the copied tree must match the manifest generated on Asgard.
cd "$PAGE_REPO_ROOT"
sha256sum -c --quiet "$PAGE_M1_INPUT_DIR/source.sha256" > "$run_dir/source_check.log" 2>&1 || {
  echo "Source manifest mismatch; see $run_dir/source_check.log" >&2
  exit 1
}
cp "$PAGE_M1_INPUT_DIR/source.sha256" "$PAGE_M1_INPUT_DIR/inputs.sha256" "$run_dir/"
sha256sum "$PAGE_M1_INPUT_DIR/source.sha256" | cut -d' ' -f1 > "$run_dir/source_manifest_id.txt"

# Run-local library so no other job's package can change underneath this run.
export PAGE_PACKAGE_LIBRARY="$run_dir/r-lib"
mkdir -p "$PAGE_PACKAGE_LIBRARY"
R CMD INSTALL --preclean --no-multiarch --library="$PAGE_PACKAGE_LIBRARY" PAGe > "$run_dir/package_install.log" 2>&1
Rscript -e 'cat(as.character(packageVersion("PAGe", lib.loc = Sys.getenv("PAGE_PACKAGE_LIBRARY"))), "\n")' \
  > "$run_dir/package_version.txt"
Rscript -e 'sessionInfo()' > "$run_dir/session_info.txt" 2>&1
{ hostname; nproc; free -g | sed -n 2p; } > "$run_dir/host.txt"

export PAGE_M1_RUN_DIR="$run_dir"
setsid nohup Rscript scripts/run_m1_reproduction_venkata.R > "$run_dir/run.log" 2>&1 < /dev/null &
pid=$!
sleep 2
# Record identity from /proc so the watchdog can reject PID reuse.
start_ticks=$(awk '{print $22}' "/proc/$pid/stat")
printf 'pid\t%s\nstart_ticks\t%s\ncmd_marker\t%s\n' "$pid" "$start_ticks" "run_m1_reproduction_venkata.R" \
  > "$run_dir/runner_identity.tsv"

setsid nohup bash scripts/watch_m1_reproduction.sh "$run_dir" > "$run_dir/watchdog.log" 2>&1 < /dev/null &
echo "launched pid=$pid run_dir=$run_dir"
