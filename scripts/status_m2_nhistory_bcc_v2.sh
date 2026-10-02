#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
OUT="${PAGE_NHISTORY_NESTED_OUT:-artifacts/m2-a-full-ntrend-nested-loso-v2}"

echo "=== PAGe full nested LOSO status ==="
echo "root=$ROOT"
echo "out=$OUT"
if [[ -f "$OUT/run_status.json" ]]; then
  cat "$OUT/run_status.json"
  echo
else
  echo "run_status.json: absent"
fi

for f in preflight_report.json smoke_manifest.json gate3_report.json gate4_report.json gate5_report.json; do
  if [[ -f "$OUT/$f" ]]; then
    printf '%-24s ' "$f"
    Rscript --vanilla -e 'x<-jsonlite::read_json(commandArgs(TRUE)[1],simplifyVector=TRUE); v<-if(!is.null(x$status)) x$status else if(!is.null(x$gate0)) x$gate0 else "UNKNOWN"; cat(v, "\n")' "$OUT/$f" 2>/dev/null || echo "present"
  fi
done

count_rds() { local d="$1"; [[ -d "$d" ]] && find "$d" -type f -name '*.rds' | wc -l | tr -d ' ' || echo 0; }
echo "upstream_rds=$(count_rds "$OUT/upstream") / 231"
echo "context_rds=$(count_rds "$OUT/ledgers/contexts") / 616"
echo "stage_a_groups=$(count_rds "$OUT/jobs/stage_a") / 550"
echo "stage_b_groups=$(count_rds "$OUT/jobs/stage_b")"
echo "boundary_r1_groups=$(count_rds "$OUT/jobs/boundary_r1")"
echo "boundary_r2_groups=$(count_rds "$OUT/jobs/boundary_r2")"

if [[ -f "$OUT/COMPLETE" ]]; then
  echo "--- COMPLETE ---"
  cat "$OUT/COMPLETE"
fi

latest_log=$(find "$OUT/logs" -type f -name 'bcc-*.log' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2- || true)
if [[ -n "$latest_log" ]]; then
  echo "--- latest log: $latest_log ---"
  tail -40 "$latest_log"
fi
