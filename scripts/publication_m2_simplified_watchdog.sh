#!/usr/bin/env bash
# Zero-token supervision for the bounded native M2 comparison.
set -u

run_dir="${1:?run directory required}"
job_pid="${2:?job pid required}"
status_dir="${3:-$run_dir}"
mkdir -p "$status_dir"
status_path="$status_dir/watchdog.tsv"
resources_path="$status_dir/watchdog_resources.tsv"

printf 'timestamp_utc\tstate\tpid\n' > "$status_path"
printf 'timestamp_utc\tpid\tpcpu\trss_kb\tetime\n' > "$resources_path"
while kill -0 "$job_pid" 2>/dev/null; do
  printf '%s\trunning\t%s\n' "$(date -u +%FT%TZ)" "$job_pid" >> "$status_path"
  ps -o pid=,pcpu=,rss=,etime= -p "$job_pid" |
    awk -v ts="$(date -u +%FT%TZ)" -v pid="$job_pid" \
      'NF {print ts "\t" pid "\t" $2 "\t" $3 "\t" $4}' >> "$resources_path"
  sleep 30
done
printf '%s\tfinished\t%s\n' "$(date -u +%FT%TZ)" "$job_pid" >> "$status_path"
