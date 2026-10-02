#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/reproduce_weekly_orvt_v1.sh \
    --season=YYYY-YY \
    --input=/path/to/ORVT_Lab_Testing_Data_....csv \
    --release-dir=/path/to/content-addressed/release \
    [--output-root=results/weekly-shadow-release-v5] \
    [--expected-sha256=<64-hex>]

Runs the authoritative weekly v2/v3 transaction from one explicit ORVT CSV.
No live fetch and no OLIS fallback are allowed. The raw CSV is copied into the
transaction data_cache and its SHA256 is propagated through child provenance.
EOF
}

season=""
input=""
release_dir=""
output_root="results/weekly-shadow-release-v5"
expected_sha256=""

for arg in "$@"; do
  case "$arg" in
    --season=*) season="${arg#*=}" ;;
    --input=*) input="${arg#*=}" ;;
    --release-dir=*) release_dir="${arg#*=}" ;;
    --output-root=*) output_root="${arg#*=}" ;;
    --expected-sha256=*) expected_sha256="${arg#*=}" ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$season" =~ ^[0-9]{4}-[0-9]{2}$ ]] || { echo "--season=YYYY-YY is required" >&2; exit 2; }
[[ -n "$input" && -f "$input" ]] || { echo "--input must name an existing ORVT CSV" >&2; exit 2; }
[[ -n "$release_dir" && -d "$release_dir" ]] || { echo "--release-dir must name an existing release directory" >&2; exit 2; }
[[ -f "PAGe/DESCRIPTION" ]] || { echo "Run from the PAGe-m1-v2 repository root" >&2; exit 2; }

case "${input,,}" in
  *.csv) ;;
  *) echo "Refusing non-CSV input for strict ORVT replay: $input" >&2; exit 2 ;;
esac

raw_sha="$(sha256sum "$input" | awk '{print $1}')"
if [[ -n "$expected_sha256" && "$raw_sha" != "$expected_sha256" ]]; then
  echo "Input SHA256 mismatch" >&2
  echo " expected: $expected_sha256" >&2
  echo " observed: $raw_sha" >&2
  exit 3
fi

before="$(mktemp)"
after="$(mktemp)"
trap 'rm -f "$before" "$after"' EXIT
find "$output_root/$season" -mindepth 1 -maxdepth 1 -type d -name '*-weekF*-release-*' -printf '%p\n' 2>/dev/null | sort > "$before" || true

Rscript --vanilla 2026/run_weekly_shadow_release_v5.R \
  "--season=$season" \
  --source=orvt \
  "--input=$input" \
  "--release-dir=$release_dir" \
  "--output-root=$output_root"

find "$output_root/$season" -mindepth 1 -maxdepth 1 -type d -name '*-weekF*-release-*' -printf '%p\n' 2>/dev/null | sort > "$after" || true
run_dir="$(comm -13 "$before" "$after" | tail -n 1)"
[[ -n "$run_dir" && -d "$run_dir" ]] || { echo "Could not identify newly published transaction" >&2; exit 4; }

python3 - "$run_dir" "$raw_sha" "$release_dir" <<'PY'
from pathlib import Path
import csv, sys
run = Path(sys.argv[1])
raw_sha = sys.argv[2]
release_dir = Path(sys.argv[3]).resolve()

def read_kv(path):
    with open(path, newline='') as f:
        rows = csv.DictReader(f, delimiter='\t')
        return {r['key']: r['value'] for r in rows}

tx = read_kv(run / 'source_transaction.tsv')
assert tx.get('status') == 'COMPLETE', tx
assert tx.get('source_mode') == 'orvt', tx
assert tx.get('raw_source_sha256') == raw_sha, (tx.get('raw_source_sha256'), raw_sha)
release_id = (run / 'release_id.txt').read_text().strip()
assert release_id == release_dir.name, (release_id, release_dir.name)
assert tx.get('release_id') == release_id
assert len(tx.get('supplied_typed_panel_sha256','')) == 64
assert len(tx.get('effective_panel_sha256','')) == 64
assert (run / 'COMPLETED').exists()
assert (run / 'typed_ab_weekly.csv').exists()
assert (run / 'v2_v3_comparison.csv').exists()
print(f'REPRODUCIBLE_TRANSACTION={run}')
print(f'RAW_SOURCE_SHA256={raw_sha}')
print(f'RELEASE_ID={release_id}')
print(f'EFFECTIVE_PANEL_SHA256={tx["effective_panel_sha256"]}')
print(f'SUPPLIED_TYPED_PANEL_SHA256={tx["supplied_typed_panel_sha256"]}')
PY
