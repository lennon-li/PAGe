#!/usr/bin/env bash
# Zero-token watchdog for the M1 reproduction run. Writes one compact row per
# interval and a terminal packet, then exits. It never restarts, signals, or
# edits the job.
set -uo pipefail

run_dir="${1:?run directory}"
interval="${PAGE_WATCH_INTERVAL:-3600}"
stale_after="${PAGE_WATCH_STALE_SECONDS:-7200}"
id_file="$run_dir/runner_identity.tsv"
pid=$(awk -F'\t' '$1=="pid"{print $2}' "$id_file")
start_ticks=$(awk -F'\t' '$1=="start_ticks"{print $2}' "$id_file")
marker=$(awk -F'\t' '$1=="cmd_marker"{print $2}' "$id_file")
out="$run_dir/watch.tsv"
[[ -f "$out" ]] || printf 'timestamp_utc\tstate\tpid_alive\tidentity_ok\tlog_age_s\tckpt_count\tckpt_age_s\tload1\tlast_status\n' > "$out"

last_status() { tail -n 1 "$run_dir/status.tsv" 2>/dev/null | cut -f2; }
age() { [[ -e "$1" ]] && echo $(( $(date +%s) - $(stat -c %Y "$1") )) || echo NA; }

while true; do
  now=$(date -u +%FT%TZ)
  alive=0; identity=0
  if [[ -r "/proc/$pid/stat" ]]; then
    alive=1
    ticks=$(awk '{print $22}' "/proc/$pid/stat")
    if [[ "$ticks" == "$start_ticks" ]] && tr '\0' ' ' < "/proc/$pid/cmdline" | grep -q "$marker"; then
      identity=1
    fi
  fi
  ckpt_dir="$run_dir/checkpoints/m1"
  ckpt_count=$(find "$ckpt_dir" -name 'ckpt_*.rds' 2>/dev/null | wc -l)
  newest=$(ls -t "$ckpt_dir"/*.rds 2>/dev/null | head -n 1)
  ckpt_age=$([[ -n "$newest" ]] && age "$newest" || echo NA)
  log_age=$(age "$run_dir/run.log")
  status=$(last_status)
  load1=$(cut -d' ' -f1 /proc/loadavg)

  if [[ "$status" == "complete" || "$status" == "failed" ]]; then
    state="$status"
  elif [[ $alive -eq 1 && $identity -eq 1 ]]; then
    # Stale only when both the log and the newest checkpoint are old.
    if [[ "$log_age" != NA && "$log_age" -gt "$stale_after" && ( "$ckpt_age" == NA || "$ckpt_age" -gt "$stale_after" ) ]]; then
      state="stale_suspect"
    else
      state="running"
    fi
  elif [[ $alive -eq 1 ]]; then
    state="pid_reused_or_foreign"
  else
    state="died_without_terminal_status"
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$now" "$state" "$alive" "$identity" \
    "$log_age" "$ckpt_count" "$ckpt_age" "$load1" "$status" >> "$out"

  case "$state" in
    complete|failed|died_without_terminal_status|pid_reused_or_foreign)
      {
        echo "terminal_state=$state at $now"
        tail -n 3 "$run_dir/status.tsv" 2>/dev/null
        cat "$run_dir/summary.csv" 2>/dev/null
        grep -m 5 -E 'Error|error' "$run_dir/run.log" 2>/dev/null
      } > "$run_dir/watch_terminal.txt"
      exit 0
      ;;
  esac
  sleep "$interval"
done
