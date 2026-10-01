#!/usr/bin/env bash
# Zero-token watchdog for publication_m2_subsets.R.
set -u

if [ "$#" -lt 2 ]; then
  echo "usage: $0 RUN_DIR PID [INTERVAL]" >&2
  exit 2
fi
run_dir="$1"
job_pid="$2"
if [ "$#" -ge 3 ]; then interval="$3"; else interval=30; fi
status_path="$run_dir/watchdog.tsv"
resources_path="$run_dir/watchdog_resources.tsv"
exit_code_path="$run_dir/worker.exit_code"
printf 'timestamp_utc\tstate\tpid\tcompleted\ttotal\tlast\n' > "$status_path"
printf 'timestamp_utc\tpid\tpcpu\trss_kb\tetime\n' > "$resources_path"
json_value() {
  sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\\([^,}]*\\).*/\\1/p" \
    "$run_dir/status.json" 2>/dev/null | head -n 1 | tr -d '" '
}
while kill -0 "$job_pid" 2>/dev/null; do
  state=$(json_value status)
  completed=$(json_value completed_outer_seasons)
  total=$(json_value total_outer_seasons)
  last=$(json_value last_season)
  [ -n "$state" ] || state=running
  [ -n "$completed" ] || completed=NA
  [ -n "$total" ] || total=NA
  [ -n "$last" ] || last=NA
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$state" "$job_pid" \
    "$completed" "$total" "$last" >> "$status_path"
  ps -o pid=,pcpu=,rss=,etime= -p "$job_pid" |
    awk -v ts="$(date -u +%FT%TZ)" -v pid="$job_pid" \
      'NF {print ts "\t" pid "\t" $2 "\t" $3 "\t" $4}' >> "$resources_path"
  sleep "$interval"
done
exit_code=1
if [ -f "$exit_code_path" ]; then
  read -r exit_code < "$exit_code_path"
elif [ "$(json_value status)" = "complete_diagnostic_only" ]; then
  exit_code=0
fi
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "finished:$exit_code" \
  "$job_pid" "NA" "NA" "NA" >> "$status_path"
exit "$exit_code"
