#!/usr/bin/env bash
set -u

run_dir="${1:?Usage: watch_outer_holdouts_venkata.sh RUN_DIR [INTERVAL_SECONDS]}"
interval="${2:-600}"
status_file="$run_dir/watch.tsv"
pid_file="$run_dir/launcher.pid"
printf 'timestamp_utc\tstate\tpid\touter_complete\touter_failed\trss_mb\tlog_bytes\n' > "$status_file"

write_failure_packet() {
  {
    printf 'watchdog_time_utc=%s\n' "$(date -u +%FT%TZ)"
    printf 'run_dir=%s\n' "$run_dir"
    printf '%s\n' '--- failed fold statuses ---'
    find "$run_dir/folds" -name status.tsv -exec awk -F '\t' 'NR > 1 && $2 == "failed" { print FILENAME ":" $0 }' {} + 2>/dev/null | tail -n 20 || true
    printf '%s\n' '--- bounded run log tail ---'
    tail -n 80 "$run_dir/run.log" 2>/dev/null || true
  } > "$run_dir/agent_handoff.txt"
}

while true; do
  pid="NA"
  state="exited"
  rss="NA"
  if [[ -f "$pid_file" ]]; then
    pid="$(cat "$pid_file")"
    if kill -0 "$pid" 2>/dev/null; then
      state="running"
      rss="$(ps -o rss= -p "$pid" | awk '{print int($1/1024)}')"
    fi
  fi
  complete="$(find "$run_dir/folds" -name status.tsv -exec awk -F '\\t' 'NR > 1 { s = $2 } END { if (s == "complete" || s == "skipped") print 1; else print 0 }' {} + 2>/dev/null | awk '{s += $1} END {print s+0}')"
  failed="$(find "$run_dir/folds" -name status.tsv -exec awk -F '\\t' 'NR > 1 { s = $2 } END { if (s == "failed") print 1; else print 0 }' {} + 2>/dev/null | awk '{s += $1} END {print s+0}')"
  log_bytes="$(wc -c < "$run_dir/run.log" 2>/dev/null || echo 0)"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$state" "$pid" "$complete" "$failed" "$rss" "$log_bytes" >> "$status_file"
  if [[ "$state" != "running" ]]; then
    if [[ "$failed" -gt 0 ]]; then
      state="failed"
      write_failure_packet
    elif [[ "$complete" -gt 0 ]]; then
      state="complete"
    else
      state="alert"
    fi
    printf '%s terminal_state=%s complete=%s failed=%s\n' \
      "$(date -u +%FT%TZ)" "$state" "$complete" "$failed" > "$run_dir/watch_terminal.txt"
    break
  fi
  sleep "$interval"
done
