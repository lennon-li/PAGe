#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE)

# Reuse the audited v2 data-ingestion/archive helpers without invoking its main.
source('2026/run_weekly_shadow_v2.R')
source('scripts/v3_m2_b_runtime_helpers_v3.R')

`%||%` <- function(x, y) if (is.null(x)) y else x

.shadow_m2b_v3_parse_args <- function(args) {
  out <- list(
    season = NULL,
    source = 'auto',
    input = NULL,
    typed_panel = NULL,
    output_root = 'results/weekly-m2-b-shadow-v3',
    compare_panel = NULL,
    m1_b_artifact = 'artifacts/m1-b-v3-peak-v9/m1_b_v3_peak_artifact.rds',
    m2_b_artifact = 'artifacts/m2-b-v3-shadow-v3/m2_b_v3_shadow_artifact.rds',
    olis_fallback = '../IRVRI/wf_output/olis_snapshot/hist_olis.RData',
    release_dir = NULL
  )
  for (arg in args) {
    if (arg %in% c('-h','--help')) {
      cat(paste0(
        'Usage: Rscript 2026/run_weekly_m2_b_shadow_v3.R --season=YYYY-YY [options]\n\n',
        'Options:\n',
        '  --source=auto|orvt|olis       Raw input source mode (default auto)\n',
        '  --input=PATH                  Explicit ORVT CSV or OLIS .RData snapshot\n',
        '  --typed-panel=PATH            Already-built typed A/B weekly CSV (testing/replay)\n',
        '  --output-root=PATH            Run output root\n',
        '  --compare-panel=PATH          Previous typed_ab_weekly.csv for revision audit\n',
        '  --m1-b-artifact=PATH          Frozen M1-B v9 artifact\n',
        '  --m2-b-artifact=PATH          Frozen M2-B v3 shadow artifact\n',
        '  --olis-fallback=PATH          Local OLIS fallback for --source=auto\n',
        '  --release-dir=PATH            Optional validated v3 release directory\n'
      ))
      quit(status=0L)
    }
    if (!grepl('^--[^=]+=',arg)) stop('Unknown argument: ',arg,call.=FALSE)
    key <- sub('^--([^=]+)=.*$','\\1',arg)
    value <- sub('^--[^=]+=','',arg)
    key <- gsub('-','_',key,fixed=TRUE)
    if (!key %in% names(out)) stop('Unknown option --',gsub('_','-',key),call.=FALSE)
    out[[key]] <- value
  }
  if (is.null(out$season) || !grepl('^[0-9]{4}-[0-9]{2}$',out$season)) stop('--season=YYYY-YY is required.',call.=FALSE)
  if (!out$source %in% c('auto','orvt','olis')) stop('--source must be auto, orvt, or olis.',call.=FALSE)
  if (!is.null(out$typed_panel) && nzchar(out$typed_panel) && !is.null(out$input) && nzchar(out$input)) stop('Use either --typed-panel or --input, not both.',call.=FALSE)
  out
}

.shadow_m2b_v3_validate_panel <- function(panel,season,require_forecast_support=FALSE) {
  .shadow_ops_validate_panel(panel,season,require_forecast_support=require_forecast_support)
  panel
}

.shadow_m2b_v3_resolve_panel <- function(opts,data_cache) {
  if (!is.null(opts$typed_panel) && nzchar(opts$typed_panel)) {
    original <- normalizePath(opts$typed_panel,winslash='/',mustWork=TRUE)
    archived <- .shadow_v2_copy_source(original,data_cache,label='typed_panel_input')
    panel <- utils::read.csv(archived,stringsAsFactors=FALSE)
    panel <- .shadow_m2b_v3_validate_panel(panel,opts$season,require_forecast_support=FALSE)
    return(list(
      panel=panel,
      source=list(mode='typed_panel',path=archived,original=original,sha256=.shadow_v2_sha256(archived),fallback_reason=NA_character_)
    ))
  }
  src <- .shadow_v2_resolve_source(opts,data_cache)
  panel <- if (src$mode=='olis') .shadow_v2_panel_from_olis(src$path,opts$season) else .shadow_v2_panel_from_orvt(src$path,opts$season)
  panel <- panel[order(panel$weekF),,drop=FALSE]
  panel <- .shadow_m2b_v3_validate_panel(panel,opts$season,require_forecast_support=FALSE)
  list(panel=panel,source=src)
}

.shadow_m2b_v3_verify_package_manifest <- function(artifact_path) {
  manifest_path <- file.path(dirname(artifact_path),'source_manifest.csv')
  if (!file.exists(manifest_path)) stop('M2-B package source_manifest.csv is missing.',call.=FALSE)
  manifest <- utils::read.csv(manifest_path,stringsAsFactors=FALSE,check.names=FALSE)
  if (!all(c('role','path','sha256') %in% names(manifest)) || !nrow(manifest)) stop('M2-B package manifest is malformed.',call.=FALSE)
  for (i in seq_len(nrow(manifest))) {
    path <- as.character(manifest$path[[i]])
    if (!file.exists(path)) stop('M2-B package manifest dependency is missing: ',path,call.=FALSE)
    actual <- .shadow_v2_sha256(path)
    if (!identical(as.character(manifest$sha256[[i]]),actual)) stop('M2-B package manifest hash mismatch for ',path,call.=FALSE)
  }
  invisible(TRUE)
}

.shadow_m2b_v3_prewindow_rows <- function(season,origin,m1b,m2b) {
  data.frame(
    season=season,origin_week=origin,horizon=c(1L,2L),
    forecast=NA_real_,B1_forecast=NA_real_,
    timing_available=FALSE,
    timing_reason='not_in_validated_window_before_weekF13',
    activity_week=NA_real_,prob_peak_passed=NA_real_,posterior_mean_peak=NA_real_,
    supported_mass=0,lower_bound_mass=0,lower_bound_saturated=FALSE,
    m1_b_version=m1b$version,m1_b_library_hash=m1b$library$provenance$library_hash,
    m2_b_version=m2b$version,m2_b_artifact_id=m2b$artifact_id,
    stringsAsFactors=FALSE)
}

.shadow_m2b_v3_main <- function(args=commandArgs(trailingOnly=TRUE)) {
  .shadow_v2_repo_root()
  opts <- .shadow_m2b_v3_parse_args(args)
  release_info <- if (!is.null(opts$release_dir) && nzchar(opts$release_dir)) .v3_release_validate(opts$release_dir) else NULL
  .shadow_v2_source_package()

  required <- c(opts$m1_b_artifact,opts$m2_b_artifact)
  missing <- required[!file.exists(required)]
  if (length(missing)) stop('Missing M1-B/M2-B shadow artifact(s): ',paste(missing,collapse=', '),call.=FALSE)
  .shadow_m2b_v3_verify_package_manifest(opts$m2_b_artifact)

  # Load and validate frozen artifacts before touching live data.
  m1b <- readRDS(opts$m1_b_artifact)
  validate_m1_b_v3_artifact(m1b)
  m2b <- readRDS(opts$m2_b_artifact)
  validate_m2_b_v3_shadow_artifact(m2b)
  if (!identical(m2b$m1_b$artifact_sha256,.shadow_v2_sha256(opts$m1_b_artifact))) stop('M2-B artifact is not bound to the supplied M1-B artifact.',call.=FALSE)
  if (!identical(m2b$version,'m2-b-v3-shadow-v3')) stop('Weekly runner requires m2-b-v3-shadow-v3.',call.=FALSE)

  stamp <- format(Sys.time(),'%Y%m%dT%H%M%SZ',tz='UTC')
  provisional <- file.path(opts$output_root,opts$season,paste0(stamp,'-pending'))
  dir.create(file.path(provisional,'data_cache'),recursive=TRUE,showWarnings=FALSE)
  got <- .shadow_m2b_v3_resolve_panel(opts,file.path(provisional,'data_cache'))
  panel <- got$panel
  source_info <- got$source
  origin <- max(as.integer(panel$weekF))
  .shadow_m2b_v3_validate_panel(panel,opts$season,require_forecast_support=origin>=13L)
  final_dir <- file.path(opts$output_root,opts$season,paste0(stamp,'-weekF',sprintf('%02d',origin)))
  if (dir.exists(final_dir)) stop('Shadow run directory already exists: ',final_dir,call.=FALSE)
  if (!file.rename(provisional,final_dir)) stop('Could not finalize v3 shadow run directory.',call.=FALSE)
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
      previous_panel=normalizePath(previous_path,winslash='/',mustWork=TRUE),
      overlap_weeks=nrow(audit),
      revised_A_weeks=if(nrow(audit)) sum(audit$revised_A) else 0L,
      revised_B_weeks=if(nrow(audit)) sum(audit$revised_B) else 0L,
      max_abs_A_revision_pp=if(nrow(audit)) 100*max(abs(audit$delta_p_A)) else 0,
      max_abs_B_revision_pp=if(nrow(audit)) 100*max(abs(audit$delta_p_B)) else 0)
  }
  .shadow_v2_write_kv(file.path(final_dir,'revision_summary.tsv'),revision_summary)

  current_B <- panel[,c('season','weekF','y_B','N_B','p_B'),drop=FALSE]
  predictions <- if (origin < 13L) {
    .shadow_m2b_v3_prewindow_rows(opts$season,origin,m1b,m2b)
  } else {
    do.call(rbind,lapply(1:2,function(h) m2_b_v3_shadow_forecast(m2b,m1b,current_B,origin,h)))
  }
  predictions$forecast_pct <- 100*predictions$forecast
  predictions$B1_forecast_pct <- 100*predictions$B1_forecast
  utils::write.csv(predictions,file.path(final_dir,'m2_b_v3_predictions.csv'),row.names=FALSE)
  saveRDS(list(predictions=predictions,origin_weekF=origin,m1_b_artifact_id=m1b$artifact_id,m2_b_artifact_id=m2b$artifact_id),file.path(final_dir,'m2_b_v3_runtime.rds'))

  summary_cols <- c('horizon','forecast_pct','B1_forecast_pct','timing_available','timing_reason','activity_week','prob_peak_passed','supported_mass','lower_bound_mass','lower_bound_saturated')
  utils::write.table(predictions[,summary_cols,drop=FALSE],file.path(final_dir,'forecast_summary.tsv'),sep='\t',quote=FALSE,row.names=FALSE)

  provenance <- list(
    run_utc=stamp,season=opts$season,origin_weekF=origin,
    source_mode=source_info$mode,source_original=source_info$original,source_archived=source_info$path,source_sha256=source_info$sha256,
    source_fallback_reason=source_info$fallback_reason %||% NA_character_,
    supplied_typed_panel_sha256=if (identical(source_info$mode,'typed_panel')) source_info$sha256 else NA_character_,
    effective_panel_sha256=.shadow_ops_effective_panel_sha256(panel,opts$season),
    release_dir=opts$release_dir %||% NA_character_,release_id=if (is.null(release_info)) NA_character_ else release_info$release_id,
    runner_path='2026/run_weekly_m2_b_shadow_v3.R',runner_sha256=.shadow_v2_sha256('2026/run_weekly_m2_b_shadow_v3.R'),
    m1_b_artifact_path=opts$m1_b_artifact,m1_b_artifact_sha256=.shadow_v2_sha256(opts$m1_b_artifact),m1_b_version=m1b$version,m1_b_artifact_id=m1b$artifact_id,m1_b_library_hash=m1b$library$provenance$library_hash,
    m2_b_artifact_path=opts$m2_b_artifact,m2_b_artifact_sha256=.shadow_v2_sha256(opts$m2_b_artifact),m2_b_version=m2b$version,m2_b_artifact_id=m2b$artifact_id,
    routing='h1_exact_B1__h2_posterior_C2_if_timing_else_B1',production_eligible=FALSE,
    lower_bound_monitoring_required=TRUE,package_manifest_preflight_passed=TRUE)
  .shadow_v2_write_kv(file.path(final_dir,'provenance.tsv'),provenance)

  status <- list(
    season=opts$season,origin_weekF=origin,
    in_validated_window=origin>=13L,
    B_h1_pct=if(origin>=13L) predictions$forecast_pct[predictions$horizon==1L] else NA_real_,
    B_h2_pct=if(origin>=13L) predictions$forecast_pct[predictions$horizon==2L] else NA_real_,
    B_h2_timing_available=if(origin>=13L) predictions$timing_available[predictions$horizon==2L] else FALSE,
    B_h2_timing_reason=predictions$timing_reason[predictions$horizon==2L],
    B_h2_lower_bound_saturated=if(origin>=13L) predictions$lower_bound_saturated[predictions$horizon==2L] else FALSE)
  .shadow_v2_write_kv(file.path(final_dir,'status.tsv'),status)

  cat('PAGe v3 M2-B weekly shadow complete\n')
  cat('run_dir:',normalizePath(final_dir,winslash='/',mustWork=TRUE),'\n')
  cat('season:',opts$season,' origin weekF:',origin,' validated_window:',origin>=13L,'\n')
  print(predictions[,c('horizon','forecast_pct','B1_forecast_pct','timing_available','timing_reason','lower_bound_mass','lower_bound_saturated')],row.names=FALSE,digits=7)

  invisible(list(run_dir=final_dir,panel=panel,predictions=predictions,provenance=provenance,status=status))
}

if (sys.nframe()==0L) .shadow_m2b_v3_main(commandArgs(trailingOnly=TRUE))
