#!/usr/bin/env bash
# Detached local supervision; no model calls. Run from repository root.
set -u
job_dir="manuscript/results/publication-repair-20260908/replay/jobs"
mkdir -p "$job_dir"
exec 9>"$job_dir/controller.lock"
flock -n 9 || exit 1
run_job() {
  local job_name="$1" script_path="$2" job_pid rc
  OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 timeout 12h Rscript --vanilla "$script_path" >"$job_dir/$job_name.log" 2>&1 &
  job_pid=$!
  while kill -0 "$job_pid" 2>/dev/null; do
    printf '%s\t%s\trunning\t%s\n' "$(date -u +%FT%TZ)" "$job_name" "$job_pid" >>"$job_dir/status.tsv"
    ps -o pid=,ppid=,pcpu=,rss=,etime= -p "$job_pid" --ppid "$job_pid" >>"$job_dir/resources.tsv" 2>/dev/null || true
    sleep 30
  done
  wait "$job_pid"
  rc=$?
  printf '%s\t%s\texit\t%s\n' "$(date -u +%FT%TZ)" "$job_name" "$rc" >>"$job_dir/status.tsv"
  return "$rc"
}
run_job replay scripts/publication_replay.R
replay_rc=$?
run_job comparators scripts/publication_comparators.R
comparator_rc=$?
printf 'replay=%s comparator=%s\n' "$replay_rc" "$comparator_rc" >"$job_dir/terminal.txt"
