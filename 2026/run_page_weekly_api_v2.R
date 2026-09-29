#!/usr/bin/env Rscript
options(stringsAsFactors=FALSE)

.bootstrap_deployment_id <- function(deployment_dir) {
  mp <- file.path(deployment_dir,'deployment_manifest.tsv'); cp <- file.path(deployment_dir,'effective_config.tsv'); ip <- file.path(deployment_dir,'deployment_id.txt')
  if (!file.exists(mp)||!file.exists(cp)||!file.exists(ip)) stop('API deployment bootstrap files missing.',call.=FALSE)
  m <- utils::read.delim(mp,sep='\t',stringsAsFactors=FALSE,check.names=FALSE)
  if (!identical(names(m),c('role','path','sha256','size_bytes'))) stop('API deployment manifest columns invalid.',call.=FALSE)
  m$size_bytes <- as.character(m$size_bytes); m <- m[order(m$role,m$path,method='radix'),,drop=FALSE]
  manifest_text <- paste0(paste(apply(m,1,function(r) paste(r,collapse='\t')),collapse='\n'),'\n')
  cdf <- utils::read.delim(cp,sep='\t',stringsAsFactors=FALSE,check.names=FALSE)
  if (!identical(names(cdf),c('key','value')) || anyDuplicated(cdf$key)) stop('API deployment effective config invalid.',call.=FALSE)
  kv <- setNames(as.character(cdf$value),as.character(cdf$key)); kv <- kv[order(names(kv),method='radix')]
  config_text <- paste0(paste0(names(kv),'\t',as.character(kv),collapse='\n'),'\n')
  payload <- paste0(manifest_text,'--effective-config--\n',config_text)
  tf <- tempfile('page-api-bootstrap-id-'); on.exit(unlink(tf),add=TRUE)
  con <- file(tf,'wb'); writeBin(charToRaw(enc2utf8(payload)),con); close(con)
  out <- system2('sha256sum',tf,stdout=TRUE,stderr=TRUE); if (!length(out)) stop('Could not hash API deployment bootstrap payload.',call.=FALSE)
  computed <- strsplit(out[[1]],' +')[[1]][[1]]; recorded <- trimws(readLines(ip,warn=FALSE,n=1L))
  if (!identical(computed,recorded) || !identical(basename(normalizePath(deployment_dir,winslash='/',mustWork=TRUE)),computed)) stop('API deployment bootstrap identity mismatch.',call.=FALSE)
  computed
}

.bootstrap_sha <- function(path) {
  o <- system2('sha256sum',path,stdout=TRUE,stderr=TRUE); if (!length(o)) stop('sha256sum failed.',call.=FALSE)
  strsplit(o[[1]],' +')[[1]][[1]]
}
.bootstrap <- function(dep,repo) {
  m <- utils::read.delim(file.path(dep,'deployment_manifest.tsv'),sep='\t',stringsAsFactors=FALSE,check.names=FALSE)
  needed <- c('scripts/v3_weekly_api_deployment_helpers_v2.R','scripts/v3_weekly_api_helpers_v2.R','2026/page_weekly_api_v1.R','scripts/v3_shadow_release_helpers_v1.R','scripts/v3_shadow_ops_helpers_v1.R','2026/run_weekly_shadow_release_v4.R')
  for (rel in needed) { r<-m[m$path==rel,,drop=FALSE]; if(nrow(r)!=1L||!identical(.bootstrap_sha(file.path(repo,rel)),r$sha256[[1]])) stop('API bootstrap hash validation failed.',call.=FALSE) }
  invisible(TRUE)
}

.main <- function() {
  if (!file.exists('PAGe/DESCRIPTION')) stop('Run API service from PAGe repository root.',call.=FALSE)
  repo <- normalizePath(getwd(),winslash='/',mustWork=TRUE)
  dep_env <- Sys.getenv('PAGE_API_DEPLOYMENT_DIR',unset=''); if (!nzchar(dep_env)) stop('PAGE_API_DEPLOYMENT_DIR is required.',call.=FALSE)
  dep <- normalizePath(dep_env,winslash='/',mustWork=TRUE)
  .bootstrap_deployment_id(dep)
  .bootstrap(dep,repo)
  source('scripts/v3_weekly_api_deployment_helpers_v2.R')
  source('scripts/v3_weekly_api_helpers_v2.R')
  source('2026/page_weekly_api_v1.R')
  cfg <- .api_load_config_from_env(repo_root=repo,strict_storage=TRUE)
  .api_validate_storage_atomic_semantics(cfg)
  deployment <- .api_deployment_validate(dep,repo_root=repo,validate_environment=TRUE)
  if (!identical(deployment$config[['deployment_mode']],'production')) stop('API service refuses non-production/test deployment bundles.',call.=FALSE)
  if (!.api_path_under(dep,cfg$artifact_mount,TRUE) || !identical(.api_fs_device(dep),.api_fs_device(cfg$artifact_mount))) stop('API deployment bundle must live on the configured private artifact mount.',call.=FALSE)
  fallback_base <- if(is.null(cfg$olis_fallback)||!nzchar(cfg$olis_fallback)) 'none' else basename(cfg$olis_fallback)
  fallback_sha <- if(!is.null(cfg$olis_fallback)&&nzchar(cfg$olis_fallback)&&file.exists(cfg$olis_fallback)) .api_sha256_file(cfg$olis_fallback) else 'none'
  runtime_map <- c(
    forecast_release_id=cfg$forecast_release_id,season=cfg$season,source_mode=cfg$source_mode,bind_host=cfg$bind_host,port=as.character(cfg$port),
    artifact_mount=normalizePath(cfg$artifact_mount,winslash='/',mustWork=TRUE),artifact_fs_type=as.character(cfg$artifact_fs_type),artifact_mount_source=as.character(cfg$artifact_mount_source),job_root=normalizePath(cfg$job_root,winslash='/',mustWork=TRUE),output_root=normalizePath(cfg$output_root,winslash='/',mustWork=TRUE),
    rscript=normalizePath(cfg$rscript,winslash='/',mustWork=TRUE),rscript_sha256=.api_sha256_file(cfg$rscript),max_runtime_seconds=as.character(cfg$max_runtime_seconds),repo_root=repo,R_home=normalizePath(R.home(),winslash='/',mustWork=TRUE),
    R_LIBS_USER=Sys.getenv('R_LIBS_USER',unset=''),R_LIBS_SITE=Sys.getenv('R_LIBS_SITE',unset=''),timezone=Sys.getenv('TZ',unset=''),locale=Sys.getenv('LC_ALL',unset=Sys.getenv('LANG',unset='')),
    olis_fallback_basename=fallback_base,olis_fallback_sha256=fallback_sha)
  for (k in names(runtime_map)) if (!identical(as.character(deployment$config[[k]]),as.character(runtime_map[[k]]))) stop('Runtime config differs from API deployment identity: ',k,call.=FALSE)
  source('scripts/v3_shadow_release_helpers_v1.R')
  .v3_release_validate(cfg$forecast_release_dir,expected_id=cfg$forecast_release_id)
  token <- .api_read_token_file(cfg$token_file)
  ctx <- .page_api_create_context(cfg,deployment$deployment_id,token,strict_mount=TRUE)
  .api_init_store(cfg)
  # Recover stale admission mutex before reconciliation; startup remains unready until this succeeds.
  if (!.api_acquire_admission(cfg,ctx$service_instance_id)) stop('Admission mutex unexpectedly busy during single-instance startup.',call.=FALSE)
  tryCatch(.api_reconcile_all(cfg,ctx$service_instance_id,ctx$process_registry),finally=.api_release_admission(cfg,ctx$service_instance_id))
  if (!.page_api_refresh_ready(ctx,TRUE)) stop('API deployment is not ready.',call.=FALSE)
  if (!requireNamespace('httpuv',quietly=TRUE)||!requireNamespace('later',quietly=TRUE)||!requireNamespace('processx',quietly=TRUE)) stop('API runtime packages unavailable.',call.=FALSE)

  tick <- NULL
  tick <- function() {
    try(.page_api_reconcile(ctx),silent=TRUE)
    .page_api_refresh_ready(ctx,FALSE)
    later::later(tick,delay=5)
  }
  later::later(tick,delay=5)
  app <- .page_api_httpuv_app(ctx)
  server <- httpuv::startServer(cfg$bind_host,cfg$port,app)
  on.exit({ try(httpuv::stopServer(server),silent=TRUE); if(!is.null(ctx$preflight_process)&&isTRUE(tryCatch(ctx$preflight_process$is_alive(),error=function(e)FALSE)))try(ctx$preflight_process$kill_tree(),silent=TRUE); ids<-ls(ctx$process_registry); for(id in ids){p<-get(id,envir=ctx$process_registry); if(isTRUE(tryCatch(p$is_alive(),error=function(e)FALSE))) try(p$kill_tree(),silent=TRUE)} },add=TRUE)
  cat('PAGe weekly shadow API v2 listening on ',cfg$bind_host,':',cfg$port,'\n',sep='')
  cat('api_deployment_id: ',deployment$deployment_id,'\n',sep='')
  cat('forecast_release_id: ',cfg$forecast_release_id,'\n',sep='')
  while (TRUE) httpuv::service(timeoutMs=1000L)
}

if (sys.nframe()==0L) .main()
