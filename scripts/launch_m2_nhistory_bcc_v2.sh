#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MODE="${1:-full}"
case "$MODE" in
  prepare|gate3|full|status) ;;
  *) echo "Usage: $0 {prepare|gate3|full|status}" >&2; exit 2 ;;
esac

export PAGE_NHISTORY_SOURCE_ROOT="${PAGE_NHISTORY_SOURCE_ROOT:-../PAGe-m1-v2}"
export PAGE_NHISTORY_NESTED_OUT="${PAGE_NHISTORY_NESTED_OUT:-artifacts/m2-a-full-ntrend-nested-loso-v2}"
export OMP_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1
export VECLIB_MAXIMUM_THREADS=1
export NUMEXPR_NUM_THREADS=1

REQUESTED_WORKERS="${PAGE_WORKERS:-32}"
MIN_MB_PER_WORKER="${PAGE_MIN_MB_PER_WORKER:-1200}"
if [[ ! "$REQUESTED_WORKERS" =~ ^[0-9]+$ ]] || (( REQUESTED_WORKERS < 1 )); then
  echo "PAGE_WORKERS must be a positive integer" >&2; exit 2
fi
if [[ ! "$MIN_MB_PER_WORKER" =~ ^[0-9]+$ ]] || (( MIN_MB_PER_WORKER < 1 )); then
  echo "PAGE_MIN_MB_PER_WORKER must be a positive integer" >&2; exit 2
fi

EFFECTIVE_WORKERS="$REQUESTED_WORKERS"

# Respect scheduler CPU allocation before host topology. Slurm/PBS values win;
# otherwise nproc is a safe local upper bound.
CPU_LIMIT=""
for v in "${SLURM_CPUS_PER_TASK:-}" "${SLURM_CPUS_ON_NODE:-}" "${PBS_NP:-}"; do
  if [[ "$v" =~ ^[0-9]+$ ]] && (( v > 0 )); then CPU_LIMIT="$v"; break; fi
done
if [[ -z "$CPU_LIMIT" ]] && command -v nproc >/dev/null 2>&1; then CPU_LIMIT="$(nproc)"; fi
if [[ "$CPU_LIMIT" =~ ^[0-9]+$ ]] && (( EFFECTIVE_WORKERS > CPU_LIMIT )); then
  echo "Capping PAGE_WORKERS ${EFFECTIVE_WORKERS} -> ${CPU_LIMIT} from allocated CPU limit."
  EFFECTIVE_WORKERS="$CPU_LIMIT"
fi

# Compute the smallest visible memory limit: scheduler allocation, cgroup, or
# physical node RAM. All values are MiB-ish; the guard is deliberately coarse.
RAM_MB=""
if [[ -r /proc/meminfo ]]; then RAM_MB="$(awk '/MemTotal:/ {printf "%d", $2/1024}' /proc/meminfo)"; fi
if [[ "${SLURM_MEM_PER_NODE:-}" =~ ^[0-9]+$ ]] && (( SLURM_MEM_PER_NODE > 0 )); then
  if [[ -z "$RAM_MB" || SLURM_MEM_PER_NODE -lt RAM_MB ]]; then RAM_MB="$SLURM_MEM_PER_NODE"; fi
fi
if [[ "${SLURM_MEM_PER_CPU:-}" =~ ^[0-9]+$ ]] && (( SLURM_MEM_PER_CPU > 0 )) && [[ "$CPU_LIMIT" =~ ^[0-9]+$ ]]; then
  SLURM_CPU_RAM=$(( SLURM_MEM_PER_CPU * CPU_LIMIT ))
  if [[ -z "$RAM_MB" || SLURM_CPU_RAM -lt RAM_MB ]]; then RAM_MB="$SLURM_CPU_RAM"; fi
fi
for cg in /sys/fs/cgroup/memory.max /sys/fs/cgroup/memory/memory.limit_in_bytes; do
  if [[ -r "$cg" ]]; then
    raw="$(cat "$cg")"
    if [[ "$raw" =~ ^[0-9]+$ ]] && (( raw > 0 )) && (( raw < 9000000000000000000 )); then
      CG_MB=$(( raw / 1024 / 1024 ))
      if (( CG_MB > 0 )) && [[ -z "$RAM_MB" || CG_MB -lt RAM_MB ]]; then RAM_MB="$CG_MB"; fi
    fi
  fi
done
if [[ "$RAM_MB" =~ ^[0-9]+$ ]] && (( RAM_MB > 0 )); then
  SAFE_WORKERS=$(( RAM_MB * 65 / 100 / MIN_MB_PER_WORKER ))
  (( SAFE_WORKERS < 1 )) && SAFE_WORKERS=1
  if (( EFFECTIVE_WORKERS > SAFE_WORKERS )); then
    echo "Capping PAGE_WORKERS ${EFFECTIVE_WORKERS} -> ${SAFE_WORKERS} from 65% allocated-memory guard (${RAM_MB} MB visible, ${MIN_MB_PER_WORKER} MB/worker)."
    EFFECTIVE_WORKERS="$SAFE_WORKERS"
  fi
fi
export PAGE_WORKERS="$EFFECTIVE_WORKERS"

mkdir -p "$PAGE_NHISTORY_NESTED_OUT/logs"
STAMP="$(date +%Y%m%dT%H%M%S)"
LOG="$PAGE_NHISTORY_NESTED_OUT/logs/bcc-${MODE}-${STAMP}.log"
exec > >(tee -a "$LOG") 2>&1

echo "=== PAGe strict full nested LOSO BCC launcher ==="
echo "mode=$MODE"
echo "scratch_root=$ROOT"
echo "source_root=$PAGE_NHISTORY_SOURCE_ROOT"
echo "out=$PAGE_NHISTORY_NESTED_OUT"
echo "workers=$PAGE_WORKERS"
echo "host=$(hostname)"
echo "start=$(date -Is)"

if [[ "$MODE" == "status" ]]; then
  exec bash scripts/status_m2_nhistory_bcc_v2.sh
fi

command -v Rscript >/dev/null 2>&1 || { echo "Rscript not found" >&2; exit 3; }
[[ -f "$PAGE_NHISTORY_SOURCE_ROOT/PAGe/DESCRIPTION" ]] || {
  echo "PAGe source root not found: $PAGE_NHISTORY_SOURCE_ROOT" >&2; exit 3;
}

# The locked observation/timing/M0 authorities are intentionally Git-ignored.
# Install or verify the bundled source overlay before Gate 0.
if [[ -f "$ROOT/bcc-source-overlay/SHA256SUMS" ]]; then
  bash scripts/install_bcc_source_overlay_v2.sh "$PAGE_NHISTORY_SOURCE_ROOT"
fi

Rscript --vanilla - <<'RS'
need <- c("digest", "jsonlite", "mgcv", "gamm4", "future", "furrr")
miss <- need[!vapply(need, requireNamespace, logical(1), quietly=TRUE)]
if (length(miss)) stop("Missing R package(s): ", paste(miss, collapse=", "), call.=FALSE)
cat("R dependency check PASS\n")
RS

# Gates 0-2 are deliberately rerun on the BCC environment before any full work.
Rscript --vanilla scripts/run_m2_nhistory_gate0_v2.R
Rscript --vanilla test/m2-nhistory-nested/run_gate1.R
Rscript --vanilla test/m2-nhistory-nested/run_gate2_smoke.R
Rscript --vanilla scripts/run_m2_nhistory_full_nested_loso_v2.R --mode=dry-run --workers="$PAGE_WORKERS"

if [[ "$MODE" == "prepare" ]]; then
  echo "Preparation PASS through Gate 2; Gate 3/full not launched."
  exit 0
fi

# Gate 3 is resumable and safe to rerun; it builds 231 strict upstream caches,
# 616 causal replay contexts, and immutable pair/outer ledgers.
Rscript --vanilla scripts/run_m2_nhistory_full_nested_loso_v2.R --mode=gate3 --workers="$PAGE_WORKERS"

if [[ "$MODE" == "gate3" ]]; then
  echo "Gate 3 PASS; full inner search not launched."
  exit 0
fi

# The explicit `full` launcher mode is the human authorization for Gate 4/5.
export PAGE_FULL_LOSO=YES
Rscript --vanilla scripts/run_m2_nhistory_full_nested_loso_v2.R --mode=full --workers="$PAGE_WORKERS"

echo "finish=$(date -Is)"
echo "Full strict nested LOSO controller completed."
