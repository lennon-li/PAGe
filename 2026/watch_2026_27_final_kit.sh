#!/usr/bin/env bash
# Detached zero-token watchdog for the 2026-27 final-kit run.
# Records compact hourly health rows and a bounded repair packet on failure.
set -uo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root="${PAGE_REPO_ROOT:-$(dirname -- "$script_dir")}"
run_root="${PAGE_RUN_ROOT:-$repo_root/results/final-kit-2026-27}"
run_id="${PAGE_RUN_ID:?PAGE_RUN_ID must be set}"
run_dir="$run_root/$run_id"
once=0
case "${1:-}" in
  --once) once=1 ;;
  "") ;;
  *) echo "usage: $0 [--once]" >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || exit 2
[[ -d "$run_dir" && -s "$run_dir/runner_identity.tsv" ]] || {
  echo "existing run directory and runner identity required" >&2; exit 1;
}
id_file="$run_dir/runner_identity.tsv"
interval="${PAGE_WATCH_INTERVAL:-3600}"
stale_after="${PAGE_WATCH_STALE_SECONDS:-7200}"
watch_file="$run_dir/watch.tsv"
log_file="$run_dir/run.log"
[[ "$interval" =~ ^[1-9][0-9]*$ && "$stale_after" =~ ^[1-9][0-9]*$ ]] || {
  echo "watch intervals must be positive integer seconds" >&2; exit 2;
}
if [[ ! -f "$watch_file" ]]; then
  printf 'timestamp_utc\tstate\tpid\tworkers\tcpu_pct\trss_mb\tstage\tlog_age_s\tlog_bytes\tckpt_count\tartifact_count\tpid_alive\tidentity_ok\tckpt_age_s\n' > "$watch_file"
fi

last_status() {
  awk -F '\t' 'NR > 1 { last = $2 } END { print last }' "$run_dir/status.tsv" 2>/dev/null || true
}

write_failure_packet() {
  local now="$1"
  local status="$2"
  {
    printf 'watchdog_time_utc=%s\n' "$now"
    printf 'run_dir=%s\n' "$run_dir"
    printf 'terminal_status=%s\n' "${status:-unknown}"
    printf '%s\n' '--- last status row ---'
    tail -n 1 "$run_dir/status.tsv" 2>/dev/null || true
    printf '%s\n' '--- fatal signatures (bounded) ---'
    grep -Ein 'error|execution halted|failed|cannot|unable|stop' "$log_file" 2>/dev/null | tail -n 20 || true
    printf '%s\n' '--- log tail (bounded) ---'
    tail -n 30 "$log_file" 2>/dev/null || true
  } > "$run_dir/agent_handoff.txt"
}

while true; do
  pid=$(awk -F '\t' '$1 == "pid" { print $2 }' "$id_file" 2>/dev/null || true)
  start_ticks=$(awk -F '\t' '$1 == "start_ticks" { print $2 }' "$id_file" 2>/dev/null || true)
  marker=$(awk -F '\t' '$1 == "cmd_marker" { print $2 }' "$id_file" 2>/dev/null || true)
  now=$(date -u +%FT%TZ)
  now_s=$(date +%s)
  final_status=$(last_status)
  state="running"
  alive=0
  identity=0
  if [[ "$pid" =~ ^[1-9][0-9]*$ ]] && proc_stat=$(cat "/proc/$pid/stat" 2>/dev/null); then
    # Strip the parenthesized comm field, which can itself contain spaces.
    proc_fields=${proc_stat##*) }
    proc_state=$(awk '{print $1}' <<< "$proc_fields")
    ticks=$(awk '{print $20}' <<< "$proc_fields")
    if [[ "$proc_state" != Z && "$proc_state" != X ]]; then
      alive=1
      cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)
      if [[ "$start_ticks" =~ ^[0-9]+$ && "$ticks" == "$start_ticks" &&
            -n "$marker" && "$cmdline" == *"$marker"* ]]; then
        identity=1
      fi
    fi
  fi
  workers=0
  cpu="NA"
  rss="NA"
  if [[ "$identity" -eq 1 ]]; then
    workers=$(pgrep -P "$pid" 2>/dev/null | wc -l | tr -d ' ')
    sample=$(ps -o %cpu=,rss= -p "$pid" 2>/dev/null | awk '{print $1, int($2/1024)}')
    cpu=$(echo "$sample" | awk '{print $1}')
    rss=$(echo "$sample" | awk '{print $2}')
    cpu="${cpu:-NA}"
    rss="${rss:-NA}"
  fi
  stage=$(tail -n 1 "$run_dir/status.tsv" 2>/dev/null | cut -f2- | tr '\t' ':' || true)
  log_age="NA"
  log_bytes=0
  if [[ -f "$log_file" ]]; then
    log_bytes=$(stat -c %s "$log_file" 2>/dev/null || echo 0)
    log_mtime=$(stat -c %Y "$log_file" 2>/dev/null || echo "$now_s")
    log_age=$(( now_s - log_mtime ))
  fi
  ckpt_times=$(find "$run_dir/checkpoints" \
    -type f -name '*.rds' -printf '%T@\n' 2>/dev/null || true)
  ckpt=$(awk 'NF { n++ } END { print n+0 }' <<< "$ckpt_times")
  newest=$(awk '$1 > newest { newest=$1 } END { if (newest) printf "%.0f", int(newest) }' <<< "$ckpt_times")
  ckpt_age=NA
  [[ -z "$newest" ]] || ckpt_age=$(( now_s - newest ))
  arts=$(find "$run_dir/artifacts" -type f 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$final_status" == "failed" ]]; then
    state="failed"
  elif [[ "$final_status" == "complete" ]]; then
    state="complete"
  elif [[ "$alive" -eq 0 ]]; then
    state="died_without_terminal_status"
  elif [[ "$identity" -eq 0 ]]; then
    state="pid_reused"
  elif [[ "$log_age" != NA && "$ckpt_age" != NA &&
          "$log_age" -gt "$stale_after" && "$ckpt_age" -gt "$stale_after" ]]; then
    state="stale_suspect"
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$now" "$state" "${pid:-NA}" "$workers" "$cpu" "$rss" "${stage:-none}" \
    "$log_age" "$log_bytes" "$ckpt" "$arts" "$alive" "$identity" "$ckpt_age" >> "$watch_file"
  if [[ "$state" == "failed" || "$state" == "complete" || "$state" == "died_without_terminal_status" || "$state" == "pid_reused" ]]; then
    printf '%s terminal_state=%s stage=%s artifacts=%s\n' \
      "$now" "$state" "${stage:-none}" "$arts" > "$run_dir/watch_terminal.txt"
    if [[ "$state" == "failed" || "$state" == "died_without_terminal_status" || "$state" == "pid_reused" ]]; then
      write_failure_packet "$now" "$state"
    fi
    break
  fi
  [[ "$once" -eq 0 ]] || break
  sleep "$interval"
done
