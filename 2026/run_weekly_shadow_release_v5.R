#!/usr/bin/env Rscript

options(stringsAsFactors=FALSE)

# Authoritative one-source transaction launcher for v2/v3 shadow comparison.
# Only release/operations helpers are loaded before release validation.
source('scripts/v3_shadow_release_helpers_v1.R')
source('scripts/v3_shadow_ops_helpers_v1.R')

`%||%` <- function(x,y) if (is.null(x)) y else x

.shadow_release_parse_args <- function(args) {
  out <- list(
    season=NULL,
    source='auto',
    input=NULL,
    output_root='results/weekly-shadow-release-v5',
    release_dir=NULL,
    olis_fallback='../IRVRI/wf_output/olis_snapshot/hist_olis.RData'
  )
  for (arg in args) {
    if (arg %in% c('-h','--help')) {
      cat(paste0(
        'Usage: Rscript 2026/run_weekly_shadow_release_v5.R --season=YYYY-YY --release-dir=PATH [options]\n\n',
        'Options:\n',
        '  --source=auto|orvt|olis       Resolve one raw source vintage (default auto)\n',
        '  --input=PATH                  Explicit ORVT CSV or OLIS .RData source\n',
        '  --output-root=PATH            Transaction output root\n',
        '  --release-dir=PATH            Validated content-addressed v3 release directory (required)\n',
        '  --olis-fallback=PATH          Local OLIS fallback for --source=auto\n'
      ))
      quit(status=0L)
    }
    if (!grepl('^--[^=]+=',arg)) stop('Unknown argument: ',arg,call.=FALSE)
    key <- gsub('-','_',sub('^--([^=]+)=.*$','\\1',arg),fixed=TRUE)
    value <- sub('^--[^=]+=','',arg)
    if (!key %in% names(out)) stop('Unknown option --',gsub('_','-',key),call.=FALSE)
    out[[key]] <- value
  }
  if (is.null(out$season) || !grepl('^[0-9]{4}-[0-9]{2}$',out$season)) stop('--season=YYYY-YY is required.',call.=FALSE)
  if (!out$source %in% c('auto','orvt','olis')) stop('--source must be auto, orvt, or olis.',call.=FALSE)
  if (is.null(out$release_dir) || !nzchar(out$release_dir)) stop('--release-dir=PATH is required for authoritative comparison issuance.',call.=FALSE)
  out
}

.shadow_release_read_tsv <- function(path) {
  if (!file.exists(path)) stop('Missing child provenance: ',path,call.=FALSE)
  x <- utils::read.delim(path,sep='\t',stringsAsFactors=FALSE,check.names=FALSE)
  setNames(as.character(x$value),as.character(x$key))
}

.shadow_release_rebase_tsv <- function(path,old_prefix,new_prefix) {
  if (!file.exists(path)) return(invisible(FALSE))
  x <- utils::read.delim(path,sep='\t',stringsAsFactors=FALSE,check.names=FALSE)
  x$value <- gsub(old_prefix,new_prefix,x$value,fixed=TRUE)
  utils::write.table(x,path,sep='\t',quote=FALSE,row.names=FALSE)
  invisible(TRUE)
}

.shadow_release_fail <- function(opts,stamp,release_id,pending,error) {
  fail_root <- file.path(opts$output_root,opts$season,'failures')
  dir.create(fail_root,recursive=TRUE,showWarnings=FALSE)
  receipt <- file.path(fail_root,paste0(stamp,'-release-',substr(release_id,1,12),'.tsv'))
  .shadow_v2_write_kv(receipt,list(
    run_utc=stamp,
    season=opts$season,
    release_id=release_id,
    status='FAILED',
    error=conditionMessage(error),
    staged_directory=pending
  ))
  if (dir.exists(pending)) {
    failed_dir <- paste0(pending,'-FAILED')
    if (!dir.exists(failed_dir)) file.rename(pending,failed_dir)
  }
  stop('Shadow release transaction failed: ',conditionMessage(error),' | receipt: ',receipt,call.=FALSE)
}

.shadow_release_main <- function(args=commandArgs(trailingOnly=TRUE)) {
  if (!file.exists('PAGe/DESCRIPTION')) stop('Run this script from the PAGe repository root.',call.=FALSE)
  opts <- .shadow_release_parse_args(args)

  # Hard barrier: content-addressed release validates before child runners/model code or source data are loaded.
  release <- .v3_release_validate(opts$release_dir)
  release_id <- release$release_id
  source('2026/run_weekly_shadow_v2.R')
  source('2026/run_weekly_shadow_v3_week12_v1.R')
  .shadow_v2_source_package()

  stamp <- format(Sys.time(),'%Y%m%dT%H%M%SZ',tz='UTC')
  season_root <- file.path(opts$output_root,opts$season)
  dir.create(file.path(season_root,'.pending'),recursive=TRUE,showWarnings=FALSE)
  pending <- file.path(season_root,'.pending',paste0(stamp,'-',substr(release_id,1,12)))
  if (dir.exists(pending)) stop('Transaction staging directory already exists: ',pending,call.=FALSE)
  dir.create(file.path(pending,'data_cache'),recursive=TRUE,showWarnings=FALSE)

  work <- tryCatch({
    source_opts <- list(season=opts$season,source=opts$source,input=opts$input,olis_fallback=opts$olis_fallback)
    raw <- .shadow_v2_resolve_source(source_opts,file.path(pending,'data_cache'))
    panel <- if (raw$mode=='olis') .shadow_v2_panel_from_olis(raw$path,opts$season) else .shadow_v2_panel_from_orvt(raw$path,opts$season)
    panel <- panel[order(panel$weekF),,drop=FALSE]
    .shadow_ops_validate_panel(panel,opts$season,require_forecast_support=FALSE)
    origin <- max(as.integer(panel$weekF))
    state_support <- .shadow_v3_has_state_support(panel,origin)
    if (!state_support) stop('Authoritative comparison requires origin weekF >= 12 and exact three-week support through the origin.',call.=FALSE)
    .shadow_ops_validate_panel(panel,opts$season,require_forecast_support=TRUE)

    typed_path <- file.path(pending,'typed_ab_weekly.csv')
    utils::write.csv(panel,typed_path,row.names=FALSE)
    supplied_panel_sha <- .shadow_ops_sha256(typed_path)
    # The serialized typed panel is the authoritative child input. Re-read it
    # before computing semantic identity so date/class normalization at the CSV
    # boundary cannot create a parent/child hash disagreement.
    deployed_panel <- utils::read.csv(typed_path,stringsAsFactors=FALSE,check.names=FALSE)
    .shadow_ops_validate_panel(deployed_panel,opts$season,require_forecast_support=TRUE)
    effective_panel_sha <- .shadow_ops_effective_panel_sha256(deployed_panel,opts$season)
    raw_ref <- paste0('transaction:data_cache/',basename(raw$path))

    v2_args <- c(
      paste0('--season=',opts$season),paste0('--typed-panel=',normalizePath(typed_path,winslash='/',mustWork=TRUE)),
      paste0('--output-root=',file.path(pending,'v2')),paste0('--release-dir=',release$release_dir),
      paste0('--transaction-raw-sha256=',raw$sha256),paste0('--transaction-raw-path=',raw_ref)
    )
    v3_args <- c(
      paste0('--season=',opts$season),paste0('--typed-panel=',normalizePath(typed_path,winslash='/',mustWork=TRUE)),
      paste0('--output-root=',file.path(pending,'v3')),paste0('--release-dir=',release$release_dir),
      paste0('--transaction-raw-sha256=',raw$sha256),paste0('--transaction-raw-path=',raw_ref)
    )

    v2 <- .shadow_v2_main(v2_args)
    v3 <- .shadow_v3_main(v3_args)

    if (!identical(as.integer(max(v2$panel$weekF)),origin) || !identical(as.integer(max(v3$panel$weekF)),origin)) stop('Child origin mismatch in authoritative transaction.',call.=FALSE)
    if (!identical(.shadow_ops_effective_panel_sha256(v2$panel,opts$season),effective_panel_sha) ||
        !identical(.shadow_ops_effective_panel_sha256(v3$panel,opts$season),effective_panel_sha)) stop('Child effective-panel SHA mismatch.',call.=FALSE)
    if (!identical(as.character(v2$provenance$release_id),release_id) || !identical(as.character(v3$provenance$release_id),release_id)) stop('Child release-ID mismatch.',call.=FALSE)
    if (!identical(as.character(v2$provenance$supplied_typed_panel_sha256),supplied_panel_sha) ||
        !identical(as.character(v3$provenance$supplied_typed_panel_sha256),supplied_panel_sha)) stop('Child supplied-panel byte SHA mismatch.',call.=FALSE)
    if (!identical(as.character(v2$provenance$raw_source_sha256),raw$sha256) || !identical(as.character(v3$provenance$raw_source_sha256),raw$sha256)) stop('Child raw-source SHA mismatch.',call.=FALSE)

    v2p <- v2$m2$predictions
    v3p <- v3$predictions
    v2_cmp <- data.frame(type=as.character(v2p$type),horizon=as.integer(v2p$horizon),v2_forecast=as.numeric(v2p$pred_selected),stringsAsFactors=FALSE)
    v3_cmp <- data.frame(type=as.character(v3p$type),horizon=as.integer(v3p$horizon),v3_forecast=as.numeric(v3p$forecast),v3_route=as.character(v3p$route),stringsAsFactors=FALSE)
    cmp <- merge(v2_cmp,v3_cmp,by=c('type','horizon'),all=TRUE,sort=FALSE)
    if (nrow(cmp)!=4L || anyNA(cmp$v2_forecast) || anyNA(cmp$v3_forecast)) stop('Official comparison does not contain four complete A/B horizon rows.',call.=FALSE)
    cmp$season <- opts$season; cmp$origin_weekF <- origin
    cmp$v2_forecast_pct <- 100*cmp$v2_forecast; cmp$v3_forecast_pct <- 100*cmp$v3_forecast
    cmp$delta_v3_minus_v2_pp <- 100*(cmp$v3_forecast-cmp$v2_forecast)
    cmp$release_id <- release_id; cmp$effective_panel_sha256 <- effective_panel_sha
    cmp <- cmp[,c('season','origin_weekF','type','horizon','v2_forecast_pct','v3_forecast_pct','delta_v3_minus_v2_pp','v3_route','release_id','effective_panel_sha256')]
    utils::write.csv(cmp,file.path(pending,'v2_v3_comparison.csv'),row.names=FALSE)

    .shadow_v2_write_kv(file.path(pending,'source_transaction.tsv'),list(
      run_utc=stamp,season=opts$season,origin_weekF=origin,status='COMPLETE_PENDING_PUBLISH',
      release_id=release_id,release_manifest_sha256=.shadow_ops_sha256(file.path(release$release_dir,'release_manifest.tsv')),
      source_mode=raw$mode,source_original=raw$original,raw_source_archived=raw_ref,raw_source_sha256=raw$sha256,
      supplied_typed_panel_sha256=supplied_panel_sha,effective_panel_sha256=effective_panel_sha,
      v2_child_run=file.path('v2',opts$season,basename(v2$run_dir)),v3_child_run=file.path('v3',opts$season,basename(v3$run_dir))
    ))
    writeLines(release_id,file.path(pending,'release_id.txt'),useBytes=TRUE)
    list(raw=raw,panel=deployed_panel,origin=origin,v2=v2,v3=v3,comparison=cmp,effective_panel_sha=effective_panel_sha,supplied_panel_sha=supplied_panel_sha)
  },error=identity)

  if (inherits(work,'error')) .shadow_release_fail(opts,stamp,release_id,pending,work)

  final_dir <- file.path(season_root,paste0(stamp,'-weekF',sprintf('%02d',work$origin),'-release-',substr(release_id,1,12)))
  if (dir.exists(final_dir)) stop('Final transaction directory already exists: ',final_dir,call.=FALSE)

  # Complete every publishable byte while the transaction is still staged. The
  # final rename is the sole publication action; nothing inside the final tree
  # is mutated after it becomes visible.
  finalized <- tryCatch({
    old_prefix <- normalizePath(pending,winslash='/',mustWork=TRUE)
    new_prefix <- normalizePath(final_dir,winslash='/',mustWork=FALSE)
    child_prov <- list.files(pending,pattern='provenance[.]tsv$',recursive=TRUE,full.names=TRUE)
    for (p in child_prov) .shadow_release_rebase_tsv(p,old_prefix,new_prefix)

    tx <- .shadow_release_read_tsv(file.path(pending,'source_transaction.tsv'))
    tx[['status']] <- 'COMPLETE'
    tx_df <- data.frame(key=names(tx),value=unname(tx),stringsAsFactors=FALSE)
    utils::write.table(tx_df,file.path(pending,'source_transaction.tsv'),sep='\t',quote=FALSE,row.names=FALSE)
    writeLines(c('COMPLETE',release_id),file.path(pending,'COMPLETED'),useBytes=TRUE)
    TRUE
  },error=identity)
  if (inherits(finalized,'error')) .shadow_release_fail(opts,stamp,release_id,pending,finalized)

  if (!file.rename(pending,final_dir)) {
    publish_error <- simpleError('Could not atomically publish completed v2/v3 transaction.')
    .shadow_release_fail(opts,stamp,release_id,pending,publish_error)
  }
  new_prefix <- normalizePath(final_dir,winslash='/',mustWork=TRUE)

  cat('PAGe v2/v3 authoritative shadow transaction complete\n')
  cat('run_dir:',new_prefix,'\n')
  cat('release_id:',release_id,' origin weekF:',work$origin,'\n')
  print(work$comparison,row.names=FALSE,digits=7)
  invisible(list(run_dir=final_dir,release_id=release_id,origin_weekF=work$origin,comparison=work$comparison))
}

if (sys.nframe()==0L) .shadow_release_main(commandArgs(trailingOnly=TRUE))
