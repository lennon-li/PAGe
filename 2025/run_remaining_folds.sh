#!/usr/bin/env bash
# Sequential driver for the remaining outer-fold seasons (2025-26/r6 already
# done separately). Runs each season's full M0->M1->M2->gate->replay cycle
# to completion before starting the next -- on a single 16-core host, running
# folds concurrently would just divide the cores rather than add throughput,
# so sequential with full-core-per-fold is the right shape here.
#
# Each season gets up to MAX_ATTEMPTS tries. A "success" or a genuine
# protocol "stopped" halt (boundary unresolved -- needs a human methodology
# call, never blindly retried) ends that season's attempts. Any other
# terminal state ("failed", a crash) is retried with the SAME run_id, so
# the runner's own per-stage (M0/M1/M2) checkpoint-resume skips whatever
# already completed instead of redoing it.
set -u

REPO_ROOT="${PAGE_REPO_ROOT:-/home/yeli/repos/PAGe-r6-run}"
ARTIFACT_ROOT="${PAGE_ARTIFACT_ROOT:-/home/yeli/PAGe-bcc-artifacts/asgard-archive-20260812}"
# No default: the old fallback was a truncated extract (2025-26 ends at
# weekF 28 of 53) that silently trained the 2026-09-17 campaign.
: "${PAGE_FLU_HIST_FILE:?Set PAGE_FLU_HIST_FILE to the authorized CSV}"
HIST_FILE="$PAGE_FLU_HIST_FILE"
N_CORES="${PAGE_N_CORES:-16}"
MAX_ATTEMPTS="${PAGE_MAX_ATTEMPTS:-3}"
DRIVER_LOG="$ARTIFACT_ROOT/campaign_driver.log"
STAMP="${PAGE_CAMPAIGN_STAMP:-$(date -u +%Y%m%dT%H%M%SZ)}"

SEASONS=(2012-13 2013-14 2014-15 2016-17 2017-18 2018-19 2019-20 2022-23 2023-24 2024-25)

cd "$REPO_ROOT" || { echo "cannot cd to $REPO_ROOT" >> "$DRIVER_LOG"; exit 1; }
log() { printf '%s\t%s\n' "$(date -u +%FT%TZ)" "$*" >> "$DRIVER_LOG"; }

log "campaign driver started; stamp=$STAMP; seasons=${SEASONS[*]}"

for season in "${SEASONS[@]}"; do
  run_id="outer-fold-${season}-${STAMP}"
  run_dir="$ARTIFACT_ROOT/$run_id"
  log "season=$season run_id=$run_id starting"
  attempt=0
  final_status="never_ran"
  while [ "$attempt" -lt "$MAX_ATTEMPTS" ]; do
    attempt=$((attempt + 1))
    log "season=$season attempt=$attempt launching"
    PAGE_HOLDOUT_SEASON="$season" \
      PAGE_FLU_HIST_FILE="$HIST_FILE" \
      PAGE_ARTIFACT_ROOT="$ARTIFACT_ROOT" \
      PAGE_RUN_ID="$run_id" \
      PAGE_N_CORES="$N_CORES" \
      bash 2025/launch_2025.sh
    final_status=$(tail -n 1 "$run_dir/status.tsv" 2>/dev/null | cut -f2)
    log "season=$season attempt=$attempt ended status=$final_status"
    if [ "$final_status" = "success" ]; then
      break
    fi
    if [ "$final_status" = "stopped" ]; then
      log "season=$season protocol halt (boundary unresolved) -- not retrying, needs review"
      break
    fi
    if [ "$attempt" -lt "$MAX_ATTEMPTS" ]; then
      log "season=$season will retry (same run_id, checkpoint-resume applies)"
      sleep 10
    fi
  done
  if [ "$final_status" != "success" ] && [ "$final_status" != "stopped" ]; then
    log "season=$season EXHAUSTED $MAX_ATTEMPTS attempts, still status=$final_status -- needs review"
  fi
done

log "campaign driver finished all seasons"
