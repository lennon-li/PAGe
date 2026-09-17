#!/usr/bin/env bash
# Detached zero-token watchdog for the 2025-26 e2e pilot run.
# Records compact health rows in watch.tsv and a terminal marker on exit.
set -u
artifact_root="${PAGE_ARTIFACT_ROOT:-/home/yeli/PAGe-bcc-artifacts/asgard-archive-20260812}"
run_id="${PAGE_RUN_ID:-2025-26-e2e-phase2-min-gain-20260911}"
run_dir="$artifact_root/$run_id"
pid_file="$run_dir/runner.pid"
watch_file="$run_dir/watch.tsv"
log_file="$run_dir/run.log"
mkdir -p "$run_dir"
if [[ ! -f "$watch_file" ]]; then
  printf 'timestamp_utc\tstate\tpid\tworkers\tcpu_pct\trss_mb\tstage\tlog_age_s\tlog_bytes\tckpt_count\tartifact_count\n' > "$watch_file"
fi
while true; do
  pid=$(cat "$pid_file" 2>/dev/null || true)
  now=$(date -u +%FT%TZ)
  now_s=$(date +%s)
  state="running"
  alive=0
  if [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null; then
    alive=1
  else
    state="exited"
  fi
  workers=0
  cpu="NA"
  rss="NA"
  if [[ "$alive" -eq 1 ]]; then
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
  ckpt=$(find "$run_dir/checkpoints" -name '*.rds' 2>/dev/null | wc -l | tr -d ' ')
  arts=$(find "$run_dir/artifacts" -type f 2>/dev/null | wc -l | tr -d ' ')
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$now" "$state" "${pid:-NA}" "$workers" "$cpu" "$rss" "${stage:-none}" \
    "$log_age" "$log_bytes" "$ckpt" "$arts" >> "$watch_file"
  if [[ "$alive" -eq 0 ]]; then
    final=$(tail -n 1 "$run_dir/status.tsv" 2>/dev/null | cut -f2 || true)
    printf '%s terminal_state=%s stage=%s artifacts=%s\n' \
      "$now" "${final:-unknown}" "${stage:-none}" "$arts" > "$run_dir/watch_terminal.txt"
    break
  fi
  sleep 300
done
