#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE)

# Reuse only audited source-ingestion/archive helpers from v2 and the governed
# M2-B v3 helper. No component main() is invoked when these files are sourced.
source('2026/run_weekly_shadow_v2.R')
source('scripts/v3_m2_b_runtime_helpers_v3.R')

`%||%` <- function(x, y) if (is.null(x)) y else x

.SHADOW_V3_MIN_ORIGIN <- 13L
.SHADOW_V3_EXPECTED <- list(
  m0_sha256 = '9598486e78eedd8e322da77b0d990db60ca07224c3c6ea6ac61cea9cc6fb611d',
  m1_a_sha256 = 'cfeb370305c5b81d66d7eafd7e45ee7e946836ba9f841854f2ec068cf3d43b09',
  m1_a_artifact_id = '90f06406dbe3a7d5f190070a5ec7a5c3605d28fe2e7f769609666f92d75d20a5',
  m1_a_library_hash = '66152c96fac040ea94b21c6a45ebf6a7ec20c6960ece0ef3c955244fa3da52f8',
  m2_a_sha256 = '1efe590c5222f6061af7bef46b0ea19657ec37e070549898569a62ccd4ac65bb',
  m2_a_artifact_id = 'm2v2g_e61427c696b16f7f23c6287bf684c0ff6e5fb9db11e379687d8a57fe9d13dd29',
  m1_b_sha256 = '761c9c447a0580e36e09221c2af01e29350d0a1464d30707c9cf947dc4771dd1',
  m2_b_sha256 = '45797b427b1082707c01130c22309fe9805ed149e03945c5829f3dcdbf883dfa',
  m2_b_manifest_sha256 = '6428f7ad6194de563c3808b99d15d72171939ce88a02cb48c0ef5867ff266ea9'
)

.shadow_v3_sha256 <- function(path) {
  if (!requireNamespace('digest', quietly = TRUE)) stop('Package `digest` is required.', call. = FALSE)
  if (!file.exists(path)) stop('Required file is missing: ', path, call. = FALSE)
  digest::digest(file = path, algo = 'sha256', serialize = FALSE)
}

.shadow_v3_same_num <- function(x, y, tol = 1e-14) {
  length(x) == 1L && is.numeric(x) && is.finite(x) && abs(as.numeric(x) - as.numeric(y)) <= tol
}

.shadow_v3_parse_args <- function(args) {
  out <- list(
    season = NULL,
    source = 'auto',
    input = NULL,
    typed_panel = NULL,
    output_root = 'results/weekly-shadow-v3',
    compare_panel = NULL,
    m0_artifact = 'artifacts/m0-v2-wmin12-raw3-se1-decimal-loso-v1/loso_result.rds',
    m1_a_artifact = 'artifacts/m1-v2-wmin12-raw3-se1-full-history-v1/m1_v2_stage.rds',
    m2_a_artifact = 'artifacts/m2-v2-c2-governed-v1/m2_v2_c2_governed_fit.rds',
    m1_b_artifact = 'artifacts/m1-b-v3-peak-v9/m1_b_v3_peak_artifact.rds',
    m2_b_artifact = 'artifacts/m2-b-v3-shadow-v3/m2_b_v3_shadow_artifact.rds',
    olis_fallback = '../IRVRI/wf_output/olis_snapshot/hist_olis.RData',
    release_dir = NULL,
    transaction_raw_sha256 = NULL,
    transaction_raw_path = NULL
  )
  for (arg in args) {
    if (arg %in% c('-h', '--help')) {
      cat(paste0(
        'Usage: Rscript 2026/run_weekly_shadow_v3.R --season=YYYY-YY [options]\n\n',
        'Options:\n',
        '  --source=auto|orvt|olis       Raw input source mode (default auto)\n',
        '  --input=PATH                  Explicit ORVT CSV or OLIS .RData snapshot\n',
        '  --typed-panel=PATH            Already-built typed A/B weekly CSV (replay/testing)\n',
        '  --output-root=PATH            Run output root\n',
        '  --compare-panel=PATH          Previous typed_ab_weekly.csv for revision audit\n',
        '  --m0-artifact=PATH            Frozen M0-A artifact (exact hash required)\n',
        '  --m1-a-artifact=PATH          Frozen M1-A artifact (exact hash required)\n',
        '  --m2-a-artifact=PATH          Frozen governed M2-v2 artifact for A1 baseline\n',
        '  --m1-b-artifact=PATH          Frozen M1-B v9 artifact\n',
        '  --m2-b-artifact=PATH          Frozen M2-B v3 shadow-v3 artifact\n',
        '  --olis-fallback=PATH          Local OLIS fallback for --source=auto\n',
        '  --release-dir=PATH            Optional validated v3 release directory\n',
        '  --transaction-raw-sha256=SHA  Raw-source SHA from authoritative transaction launcher\n',
        '  --transaction-raw-path=PATH   Archived raw-source path from authoritative transaction launcher\n'
      ))
      quit(status = 0L)
    }
    if (!grepl('^--[^=]+=', arg)) stop('Unknown argument: ', arg, call. = FALSE)
    key <- sub('^--([^=]+)=.*$', '\\1', arg)
    value <- sub('^--[^=]+=', '', arg)
    key <- gsub('-', '_', key, fixed = TRUE)
    if (!key %in% names(out)) stop('Unknown option --', gsub('_', '-', key), call. = FALSE)
    out[[key]] <- value
  }
  if (is.null(out$season) || !grepl('^[0-9]{4}-[0-9]{2}$', out$season)) stop('--season=YYYY-YY is required.', call. = FALSE)
  if (!out$source %in% c('auto', 'orvt', 'olis')) stop('--source must be auto, orvt, or olis.', call. = FALSE)
  if (!is.null(out$typed_panel) && nzchar(out$typed_panel) && !is.null(out$input) && nzchar(out$input)) {
    stop('Use either --typed-panel or --input, not both.', call. = FALSE)
  }
  out
}

.shadow_v3_verify_m2b_manifest <- function(m2_b_artifact_path) {
  manifest_path <- file.path(dirname(m2_b_artifact_path), 'source_manifest.csv')
  if (!file.exists(manifest_path)) stop('Canonical M2-B package source_manifest.csv is missing.', call. = FALSE)
  if (!identical(.shadow_v3_sha256(manifest_path), .SHADOW_V3_EXPECTED$m2_b_manifest_sha256)) {
    stop('Canonical M2-B package manifest identity mismatch.', call. = FALSE)
  }
  manifest <- utils::read.csv(manifest_path, stringsAsFactors = FALSE, check.names = FALSE)
  if (!all(c('role', 'path', 'sha256') %in% names(manifest)) || !nrow(manifest)) stop('M2-B package manifest is malformed.', call. = FALSE)
  for (i in seq_len(nrow(manifest))) {
    path <- as.character(manifest$path[[i]])
    if (!file.exists(path)) stop('M2-B package manifest dependency is missing: ', path, call. = FALSE)
    if (!identical(as.character(manifest$sha256[[i]]), .shadow_v3_sha256(path))) {
      stop('M2-B package manifest hash mismatch for ', path, call. = FALSE)
    }
  }
  invisible(manifest_path)
}

.shadow_v3_validate_m0 <- function(path) {
  if (!identical(.shadow_v3_sha256(path), .SHADOW_V3_EXPECTED$m0_sha256)) stop('Frozen M0-A artifact hash mismatch.', call. = FALSE)
  z <- readRDS(path)
  p <- z$best_params
  required <- c('p_thr','prev_thr','n_consec','L','eps','K_sum','p_sum_thr','N_req','w_min','w_max','use_cls','raw_nondec_n','raw_drop_se_tol')
  if (!is.list(p) || !all(required %in% names(p))) stop('Frozen M0-A parameter payload is malformed.', call. = FALSE)
  ok <- .shadow_v3_same_num(p$p_thr,.002) && .shadow_v3_same_num(p$prev_thr,.001) &&
    .shadow_v3_same_num(p$n_consec,5) && .shadow_v3_same_num(p$L,2) && .shadow_v3_same_num(p$eps,0) &&
    .shadow_v3_same_num(p$K_sum,5) && .shadow_v3_same_num(p$p_sum_thr,.06) && .shadow_v3_same_num(p$N_req,4) &&
    .shadow_v3_same_num(p$w_min,12) && .shadow_v3_same_num(p$w_max,26) &&
    identical(p$use_cls,FALSE) && .shadow_v3_same_num(p$raw_nondec_n,3) && .shadow_v3_same_num(p$raw_drop_se_tol,1)
  if (!ok) stop('Frozen M0-A policy identity mismatch.', call. = FALSE)
  z
}

.shadow_v3_validate_m1a <- function(path) {
  if (!identical(.shadow_v3_sha256(path), .SHADOW_V3_EXPECTED$m1_a_sha256)) stop('Frozen M1-A artifact hash mismatch.', call. = FALSE)
  z <- readRDS(path)
  if (!inherits(z, 'page_m1_v2_stage') || !identical(z$version, 'page-m1-v2-stage-v1')) stop('Frozen M1-A stage class/version mismatch.', call. = FALSE)
  if (!identical(z$artifact_id, .SHADOW_V3_EXPECTED$m1_a_artifact_id) || !identical(z$artifact_id, .m1_v2_stage_artifact_id(z))) {
    stop('Frozen M1-A stage artifact identity mismatch.', call. = FALSE)
  }
  if (!identical(z$library$provenance$library_hash, .SHADOW_V3_EXPECTED$m1_a_library_hash)) stop('Frozen M1-A library hash mismatch.', call. = FALSE)
  z
}

.shadow_v3_validate_m2a <- function(path) {
  if (!identical(.shadow_v3_sha256(path), .SHADOW_V3_EXPECTED$m2_a_sha256)) stop('Frozen governed M2-v2 artifact hash mismatch.', call. = FALSE)
  z <- readRDS(path)
  validate_m2_v2_c2_governed_artifact(z)
  if (!identical(z$artifact_id, .SHADOW_V3_EXPECTED$m2_a_artifact_id) || !identical(z$contract$model_version, 'm2-v2-c2-governed-v1')) {
    stop('Frozen governed M2-v2 artifact identity mismatch.', call. = FALSE)
  }
  z
}

.shadow_v3_preflight <- function(opts) {
  required <- c(opts$m0_artifact, opts$m1_a_artifact, opts$m2_a_artifact, opts$m1_b_artifact, opts$m2_b_artifact)
  missing <- required[!file.exists(required)]
  if (length(missing)) stop('Missing frozen v3 shadow artifact(s): ', paste(missing, collapse = ', '), call. = FALSE)

  .shadow_v3_verify_m2b_manifest(opts$m2_b_artifact)
  m0 <- .shadow_v3_validate_m0(opts$m0_artifact)
  m1a <- .shadow_v3_validate_m1a(opts$m1_a_artifact)
  m2a <- .shadow_v3_validate_m2a(opts$m2_a_artifact)

  if (!identical(.shadow_v3_sha256(opts$m1_b_artifact), .SHADOW_V3_EXPECTED$m1_b_sha256)) stop('Frozen M1-B artifact hash mismatch.', call. = FALSE)
  m1b <- readRDS(opts$m1_b_artifact)
  validate_m1_b_v3_artifact(m1b)
  if (!identical(m1b$version, 'm1-b-v3-peak-v9')) stop('Frozen M1-B version mismatch.', call. = FALSE)

  if (!identical(.shadow_v3_sha256(opts$m2_b_artifact), .SHADOW_V3_EXPECTED$m2_b_sha256)) stop('Frozen M2-B artifact hash mismatch.', call. = FALSE)
  m2b <- readRDS(opts$m2_b_artifact)
  validate_m2_b_v3_shadow_artifact(m2b)
  if (!identical(m2b$version, 'm2-b-v3-shadow-v3') || !identical(m2b$status, 'shadow_only_prospective_research') ||
      !identical(m2b$production_eligible, FALSE) || !identical(m2b$runtime_contract$allow_hard_passage, FALSE) ||
      !identical(m2b$runtime_contract$allow_production, FALSE)) {
    stop('Frozen M2-B governance identity mismatch.', call. = FALSE)
  }
  if (!identical(m2b$m1_b$artifact_sha256, .shadow_v3_sha256(opts$m1_b_artifact))) stop('M2-B package is not bound to supplied M1-B artifact.', call. = FALSE)
  if ('2019-20' %in% m2b$state$training_seasons || any(c('2018-19','2019-20') %in% m2b$shape$B_seasons)) {
    stop('Frozen B season-policy invariant violated.', call. = FALSE)
  }

  list(m0 = m0, m1a = m1a, m2a = m2a, m1b = m1b, m2b = m2b)
}

.shadow_v3_validate_panel <- function(panel, season, require_forecast_support = FALSE) {
  .shadow_ops_validate_panel(panel,season,require_forecast_support=require_forecast_support)
  panel
}

.shadow_v3_resolve_panel <- function(opts, data_cache) {
  if (!is.null(opts$typed_panel) && nzchar(opts$typed_panel)) {
    original <- normalizePath(opts$typed_panel, winslash = '/', mustWork = TRUE)
    archived <- .shadow_v2_copy_source(original, data_cache, label = 'typed_panel_input')
    panel <- utils::read.csv(archived, stringsAsFactors = FALSE, check.names = FALSE)
    panel <- .shadow_v3_validate_panel(panel, opts$season, require_forecast_support = FALSE)
    return(list(
      panel = panel,
      source = list(mode='typed_panel', path=archived, original=original,
                    sha256=.shadow_v3_sha256(archived), fallback_reason=NA_character_)
    ))
  }
  src <- .shadow_v2_resolve_source(opts, data_cache)
  panel <- if (src$mode == 'olis') .shadow_v2_panel_from_olis(src$path, opts$season) else .shadow_v2_panel_from_orvt(src$path, opts$season)
  panel <- panel[order(panel$weekF),,drop=FALSE]
  panel <- .shadow_v3_validate_panel(panel, opts$season, require_forecast_support = FALSE)
  list(panel = panel, source = src)
}

.shadow_v3_prewindow_rows <- function(season, origin, pf) {
  data.frame(
    season = season,
    origin_weekF = origin,
    type = rep(c('A','B'), each = 2L),
    horizon = rep(1:2, times = 2L),
    forecast = NA_real_, forecast_pct = NA_real_,
    state_baseline = NA_real_, state_baseline_pct = NA_real_,
    route = 'not_issued',
    timing_available = FALSE,
    timing_reason = 'not_in_validated_window_before_weekF13',
    activity_week = NA_real_, prob_peak_passed = NA_real_, posterior_mean_peak = NA_real_,
    supported_mass = 0, lower_bound_mass = 0, lower_bound_saturated = FALSE,
    model_version = c(rep(pf$m2a$contract$model_version,2L),rep(pf$m2b$version,2L)),
    artifact_id = c(rep(pf$m2a$artifact_id,2L),rep(pf$m2b$artifact_id,2L)),
    production_eligible = FALSE,
    stringsAsFactors = FALSE
  )
}

.shadow_v3_build_a_rows <- function(a_runtime, season, origin) {
  p <- a_runtime$predictions[a_runtime$predictions$type == 'A', , drop = FALSE]
  p <- p[order(p$horizon), , drop = FALSE]
  if (nrow(p) != 2L || !identical(as.integer(p$horizon), 1:2)) stop('Governed A runtime did not return exactly A+1/A+2.', call. = FALSE)
  if (any(p$c2_applied) || any(p$timing_used) || any(p$pred_selected != p$pred_baseline)) {
    stop('A route invariant violated: v3 A must equal exact A1 baseline with no timing/C2.', call. = FALSE)
  }
  data.frame(
    season=season, origin_weekF=origin, type='A', horizon=as.integer(p$horizon),
    forecast=as.numeric(p$pred_selected), forecast_pct=100*as.numeric(p$pred_selected),
    state_baseline=as.numeric(p$pred_baseline), state_baseline_pct=100*as.numeric(p$pred_baseline),
    route='exact_A1_state', timing_available=FALSE, timing_reason='policy_A_state_only',
    activity_week=NA_real_, prob_peak_passed=NA_real_, posterior_mean_peak=NA_real_,
    supported_mass=0, lower_bound_mass=0, lower_bound_saturated=FALSE,
    model_version=as.character(p$governed_model_version), artifact_id=as.character(p$model_artifact_id),
    production_eligible=FALSE, stringsAsFactors=FALSE
  )
}

.shadow_v3_build_b_rows <- function(pf, panel, season, origin) {
  current_B <- panel[,c('season','weekF','y_B','N_B','p_B'),drop=FALSE]
  q <- do.call(rbind, lapply(1:2, function(h) m2_b_v3_shadow_forecast(pf$m2b, pf$m1b, current_B, origin, h)))
  q <- q[order(q$horizon), , drop = FALSE]
  if (nrow(q) != 2L || !identical(as.integer(q$horizon),1:2)) stop('M2-B runtime did not return exactly B+1/B+2.', call. = FALSE)
  if (!identical(q$forecast[1], q$B1_forecast[1]) || isTRUE(q$timing_available[1]) || !identical(q$timing_reason[1], 'plus1_state_only')) {
    stop('B+1 route invariant violated.', call. = FALSE)
  }
  if (isTRUE(q$timing_available[2])) {
    if (!identical(q$timing_reason[2], 'posterior_C2')) stop('B+2 active timing route invariant violated.', call. = FALSE)
    route2 <- 'posterior_C2'
  } else {
    if (!identical(q$forecast[2], q$B1_forecast[2])) stop('B+2 fallback must equal exact B1.', call. = FALSE)
    route2 <- 'exact_B1_fallback'
  }
  data.frame(
    season=season, origin_weekF=origin, type='B', horizon=as.integer(q$horizon),
    forecast=as.numeric(q$forecast), forecast_pct=100*as.numeric(q$forecast),
    state_baseline=as.numeric(q$B1_forecast), state_baseline_pct=100*as.numeric(q$B1_forecast),
    route=c('exact_B1_state',route2), timing_available=as.logical(q$timing_available), timing_reason=as.character(q$timing_reason),
    activity_week=as.numeric(q$activity_week), prob_peak_passed=as.numeric(q$prob_peak_passed), posterior_mean_peak=as.numeric(q$posterior_mean_peak),
    supported_mass=as.numeric(q$supported_mass), lower_bound_mass=as.numeric(q$lower_bound_mass), lower_bound_saturated=as.logical(q$lower_bound_saturated),
    model_version=as.character(q$m2_b_version), artifact_id=as.character(q$m2_b_artifact_id),
    production_eligible=FALSE, stringsAsFactors=FALSE
  )
}

.shadow_v3_validate_combined_rows <- function(x, season, origin) {
  if (!is.data.frame(x) || nrow(x) != 4L) stop('Combined v3 forecast contract requires exactly four rows.', call. = FALSE)
  key <- paste(x$type, x$horizon, sep=':')
  if (!setequal(key, c('A:1','A:2','B:1','B:2')) || anyDuplicated(key)) stop('Combined v3 forecast contract type/horizon keys are invalid.', call. = FALSE)
  if (!all(x$season == season) || !all(x$origin_weekF == origin)) stop('Combined v3 forecast contract season/origin mismatch.', call. = FALSE)
  if (any(!is.finite(x$forecast)) || any(x$forecast < 0 | x$forecast > 1) || any(!is.finite(x$state_baseline))) stop('Combined v3 forecast contains invalid probabilities.', call. = FALSE)
  if (!all(x$production_eligible == FALSE)) stop('Combined v3 forecast must be explicitly non-production.', call. = FALSE)
  a <- x[x$type=='A',]
  if (any(a$route!='exact_A1_state') || any(a$forecast != a$state_baseline) || any(a$timing_available)) stop('Combined A routing invariant failed.', call. = FALSE)
  b1 <- x[x$type=='B' & x$horizon==1L,]
  b2 <- x[x$type=='B' & x$horizon==2L,]
  if (nrow(b1)!=1L || b1$route!='exact_B1_state' || b1$forecast!=b1$state_baseline || b1$timing_available) stop('Combined B+1 routing invariant failed.', call. = FALSE)
  if (nrow(b2)!=1L) stop('Combined B+2 row missing.', call. = FALSE)
  if (!b2$timing_available && (b2$route!='exact_B1_fallback' || b2$forecast!=b2$state_baseline)) stop('Combined B+2 fallback invariant failed.', call. = FALSE)
  if (b2$timing_available && b2$route!='posterior_C2') stop('Combined B+2 active route invariant failed.', call. = FALSE)
  invisible(TRUE)
}

.shadow_v3_main <- function(args = commandArgs(trailingOnly = TRUE)) {
  .shadow_v2_repo_root()
  opts <- .shadow_v3_parse_args(args)

  release_info <- if (!is.null(opts$release_dir) && nzchar(opts$release_dir)) .v3_release_validate(opts$release_dir) else NULL

  # Code loading is local-repository preflight, not source-data ingestion.
  .shadow_v2_source_package()

  # Hard barrier: every frozen component and package manifest is validated before
  # any live or replay panel is resolved/archived.
  pf <- .shadow_v3_preflight(opts)

  stamp <- format(Sys.time(), '%Y%m%dT%H%M%SZ', tz='UTC')
  provisional <- file.path(opts$output_root, opts$season, paste0(stamp,'-pending'))
  dir.create(file.path(provisional,'data_cache'), recursive=TRUE, showWarnings=FALSE)
  got <- .shadow_v3_resolve_panel(opts, file.path(provisional,'data_cache'))
  panel <- got$panel
  source_info <- got$source
  origin <- max(as.integer(panel$weekF))
  panel <- .shadow_v3_validate_panel(panel, opts$season, require_forecast_support = origin >= .SHADOW_V3_MIN_ORIGIN)

  final_dir <- file.path(opts$output_root, opts$season, paste0(stamp,'-weekF',sprintf('%02d',origin)))
  if (dir.exists(final_dir)) stop('Combined v3 shadow run directory already exists: ', final_dir, call. = FALSE)
  if (!file.rename(provisional, final_dir)) stop('Could not finalize combined v3 shadow run directory.', call. = FALSE)
  source_info$path <- file.path(final_dir,'data_cache',basename(source_info$path))
  utils::write.csv(panel,file.path(final_dir,'typed_ab_weekly.csv'),row.names=FALSE)

  previous_path <- opts$compare_panel
  if (is.null(previous_path) || !nzchar(previous_path)) previous_path <- .shadow_v2_find_previous_panel(opts$output_root,opts$season,final_dir)
  revision_summary <- list(previous_panel=NA_character_,overlap_weeks=0L,revised_A_weeks=0L,revised_B_weeks=0L,max_abs_A_revision_pp=0,max_abs_B_revision_pp=0)
  if (!is.null(previous_path) && file.exists(previous_path)) {
    previous <- utils::read.csv(previous_path,stringsAsFactors=FALSE)
    audit <- .shadow_v2_revision_audit(panel,previous)
    utils::write.csv(audit,file.path(final_dir,'revision_audit.csv'),row.names=FALSE)
    revision_summary <- list(
      previous_panel=normalizePath(previous_path,winslash='/',mustWork=TRUE),overlap_weeks=nrow(audit),
      revised_A_weeks=if(nrow(audit)) sum(audit$revised_A) else 0L,revised_B_weeks=if(nrow(audit)) sum(audit$revised_B) else 0L,
      max_abs_A_revision_pp=if(nrow(audit)) 100*max(abs(audit$delta_p_A)) else 0,max_abs_B_revision_pp=if(nrow(audit)) 100*max(abs(audit$delta_p_B)) else 0)
  }
  .shadow_v2_write_kv(file.path(final_dir,'revision_summary.tsv'),revision_summary)

  if (origin < .SHADOW_V3_MIN_ORIGIN) {
    combined <- .shadow_v3_prewindow_rows(opts$season,origin,pf)
    m0_result <- NULL; m1_out <- NULL; a_runtime <- NULL; b_runtime <- NULL
  } else {
    a_current <- data.frame(season=panel$season,weekF=panel$weekF,y=panel$y_A,N=panel$N_A,p=panel$p_A,stringsAsFactors=FALSE)
    m0_det <- detectIgnitionBySeason_M0v2_timing(a_current,pf$m0$best_params,verbose=FALSE,iWeek=FALSE,validate_support=FALSE)
    by <- m0_det$by_season[1L,,drop=FALSE]
    ignited <- !isTRUE(by$detection_failed)
    m0_result <- list(
      ign_out=m0_det,
      iWeek_locked=if(ignited) as.numeric(by$iWeek_hat) else NA_real_,
      iWeek_lockedF=if(ignited) as.numeric(by$iWeek_hatF) else NA_real_,
      overridden=FALSE)
    utils::write.csv(m0_det$data,file.path(final_dir,'m0_a_signals.csv'),row.names=FALSE)
    utils::write.csv(by,file.path(final_dir,'m0_a_detection.csv'),row.names=FALSE)

    m1_out <- run_m1_v2_timing(list(m1_v2=pf$m1a),a_current,m0_result,verbose=FALSE)
    saveRDS(m1_out,file.path(final_dir,'m1_a_runtime.rds'))
    if (is.data.frame(m1_out$timing_df) && nrow(m1_out$timing_df)) utils::write.csv(m1_out$timing_df,file.path(final_dir,'m1_a_timing.csv'),row.names=FALSE)

    # Deliberately do not pass m1_out$m2_handoff: final v3 M2-A routing is exact A1.
    a_runtime <- run_m2_v2_c2_governed_runtime(pf$m2a,panel,origin,a_handoff=NULL,b_handoff=NULL,b_gate_review=NULL)
    saveRDS(a_runtime,file.path(final_dir,'a_state_runtime.rds'))
    a_rows <- .shadow_v3_build_a_rows(a_runtime,opts$season,origin)

    b_rows <- .shadow_v3_build_b_rows(pf,panel,opts$season,origin)
    b_runtime <- list(predictions=b_rows,origin_weekF=origin,m1_b_artifact_id=pf$m1b$artifact_id,m2_b_artifact_id=pf$m2b$artifact_id)
    saveRDS(b_runtime,file.path(final_dir,'b_v3_runtime.rds'))

    combined <- rbind(a_rows,b_rows)
    combined <- combined[order(match(combined$type,c('A','B')),combined$horizon),,drop=FALSE]
    .shadow_v3_validate_combined_rows(combined,opts$season,origin)
  }

  utils::write.csv(combined,file.path(final_dir,'combined_predictions.csv'),row.names=FALSE)
  summary_cols <- c('type','horizon','forecast_pct','state_baseline_pct','route','timing_available','timing_reason','activity_week','prob_peak_passed','supported_mass','lower_bound_mass','lower_bound_saturated')
  utils::write.table(combined[,summary_cols,drop=FALSE],file.path(final_dir,'forecast_summary.tsv'),sep='\t',quote=FALSE,row.names=FALSE)

  provenance <- list(
    run_utc=stamp,season=opts$season,origin_weekF=origin,in_validated_window=origin>=.SHADOW_V3_MIN_ORIGIN,
    source_mode=source_info$mode,source_original=source_info$original,source_archived=source_info$path,source_sha256=source_info$sha256,
    source_fallback_reason=source_info$fallback_reason %||% NA_character_,runner_path='2026/run_weekly_shadow_v3.R',runner_sha256=.shadow_v3_sha256('2026/run_weekly_shadow_v3.R'),
    raw_source_path=if (identical(source_info$mode,'typed_panel')) (opts$transaction_raw_path %||% NA_character_) else source_info$path,
    raw_source_sha256=if (identical(source_info$mode,'typed_panel')) (opts$transaction_raw_sha256 %||% NA_character_) else source_info$sha256,
    supplied_typed_panel_sha256=if (identical(source_info$mode,'typed_panel')) source_info$sha256 else NA_character_,
    effective_panel_sha256=.shadow_ops_effective_panel_sha256(panel,opts$season),
    release_dir=opts$release_dir %||% NA_character_,release_id=if (is.null(release_info)) NA_character_ else release_info$release_id,
    m0_artifact_path=opts$m0_artifact,m0_artifact_sha256=.shadow_v3_sha256(opts$m0_artifact),
    m1_a_artifact_path=opts$m1_a_artifact,m1_a_artifact_sha256=.shadow_v3_sha256(opts$m1_a_artifact),m1_a_artifact_id=pf$m1a$artifact_id,
    m2_a_artifact_path=opts$m2_a_artifact,m2_a_artifact_sha256=.shadow_v3_sha256(opts$m2_a_artifact),m2_a_artifact_id=pf$m2a$artifact_id,
    m1_b_artifact_path=opts$m1_b_artifact,m1_b_artifact_sha256=.shadow_v3_sha256(opts$m1_b_artifact),m1_b_artifact_id=pf$m1b$artifact_id,m1_b_library_hash=pf$m1b$library$provenance$library_hash,
    m2_b_artifact_path=opts$m2_b_artifact,m2_b_artifact_sha256=.shadow_v3_sha256(opts$m2_b_artifact),m2_b_artifact_id=pf$m2b$artifact_id,
    m2_b_manifest_sha256=.shadow_v3_sha256(file.path(dirname(opts$m2_b_artifact),'source_manifest.csv')),
    routing='A_h1_A1__A_h2_A1__B_h1_B1__B_h2_posterior_C2_if_timing_else_B1',
    production_eligible=FALSE,hard_b_passage_allowed=FALSE,package_manifest_preflight_passed=TRUE)
  .shadow_v2_write_kv(file.path(final_dir,'provenance.tsv'),provenance)

  status <- list(
    season=opts$season,origin_weekF=origin,in_validated_window=origin>=.SHADOW_V3_MIN_ORIGIN,production_eligible=FALSE,
    A_h1_pct=combined$forecast_pct[combined$type=='A' & combined$horizon==1L],
    A_h2_pct=combined$forecast_pct[combined$type=='A' & combined$horizon==2L],
    B_h1_pct=combined$forecast_pct[combined$type=='B' & combined$horizon==1L],
    B_h2_pct=combined$forecast_pct[combined$type=='B' & combined$horizon==2L],
    B_h2_timing_available=combined$timing_available[combined$type=='B' & combined$horizon==2L],
    B_h2_timing_reason=combined$timing_reason[combined$type=='B' & combined$horizon==2L],
    B_h2_lower_bound_saturated=combined$lower_bound_saturated[combined$type=='B' & combined$horizon==2L])
  .shadow_v2_write_kv(file.path(final_dir,'status.tsv'),status)

  cat('PAGe v3 combined weekly shadow complete\n')
  cat('run_dir:',normalizePath(final_dir,winslash='/',mustWork=TRUE),'\n')
  cat('season:',opts$season,' origin weekF:',origin,' validated_window:',origin>=.SHADOW_V3_MIN_ORIGIN,'\n')
  print(combined[,c('type','horizon','forecast_pct','state_baseline_pct','route','timing_available','timing_reason','lower_bound_mass','lower_bound_saturated')],row.names=FALSE,digits=7)

  invisible(list(run_dir=final_dir,panel=panel,predictions=combined,provenance=provenance,status=status,
                 m0_result=m0_result,m1_a=m1_out,a_runtime=a_runtime,b_runtime=b_runtime,preflight=pf))
}

if (sys.nframe() == 0L) .shadow_v3_main(commandArgs(trailingOnly = TRUE))
