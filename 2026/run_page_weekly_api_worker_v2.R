#!/usr/bin/env Rscript
options(stringsAsFactors=FALSE)

.parse_args <- function(args) {
  out <- list(job_root=NULL,run_id=NULL)
  for (a in args) {
    if (!grepl('^--[^=]+=',a)) stop('Worker arguments must use --key=value.',call.=FALSE)
    k <- gsub('-','_',sub('^--([^=]+)=.*$','\\1',a)); v <- sub('^--[^=]+=','',a)
    if (!k %in% names(out)) stop('Unknown worker argument.',call.=FALSE); out[[k]] <- v
  }
  if (is.null(out$job_root)||is.null(out$run_id)) stop('--job-root and --run-id are required.',call.=FALSE)
  out
}

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
  o <- system2('sha256sum',path,stdout=TRUE,stderr=TRUE)
  if (!length(o)) stop('sha256sum failed.',call.=FALSE)
  strsplit(o[[1]],' +')[[1]][[1]]
}

.bootstrap_validate <- function(deployment_dir,repo_root,paths) {
  m <- utils::read.delim(file.path(deployment_dir,'deployment_manifest.tsv'),sep='\t',stringsAsFactors=FALSE,check.names=FALSE)
  for (rel in paths) {
    r <- m[m$path==rel,,drop=FALSE]; if (nrow(r)!=1L) stop('Deployment missing bootstrap binding.',call.=FALSE)
    if (!identical(.bootstrap_sha(file.path(repo_root,rel)),r$sha256[[1]])) stop('Bootstrap hash drift.',call.=FALSE)
  }
  invisible(TRUE)
}

.main <- function(args=commandArgs(trailingOnly=TRUE)) {
  opt <- .parse_args(args)
  if (!grepl('^wr_[0-9a-f]{32}$',opt$run_id)) stop('Invalid run_id.',call.=FALSE)
  job_dir <- file.path(opt$job_root,'jobs',opt$run_id)
  wc_path <- file.path(job_dir,'worker_config.json'); req_path <- file.path(job_dir,'request.json')
  if (!file.exists(wc_path)||!file.exists(req_path)) stop('Worker job files missing.',call.=FALSE)
  if (!requireNamespace('jsonlite',quietly=TRUE)) stop('jsonlite missing.',call.=FALSE)
  wc <- jsonlite::fromJSON(wc_path,simplifyVector=FALSE); req <- jsonlite::fromJSON(req_path,simplifyVector=FALSE)
  repo <- normalizePath(wc$repo_root,winslash='/',mustWork=TRUE); setwd(repo)
  dep <- normalizePath(wc$api_deployment_dir,winslash='/',mustWork=TRUE)
  .bootstrap_deployment_id(dep)
  boot <- c('scripts/v3_weekly_api_deployment_helpers_v2.R','scripts/v3_weekly_api_helpers_v2.R','scripts/v3_shadow_release_helpers_v1.R','scripts/v3_shadow_ops_helpers_v1.R','2026/run_weekly_shadow_release_v4.R')
  .bootstrap_validate(dep,repo,boot)
  source('scripts/v3_weekly_api_deployment_helpers_v2.R')
  source('scripts/v3_weekly_api_helpers_v2.R')
  # Private worker diagnostics for deployment identity failures only. These IDs
  # contain no secrets and remain in the private worker stderr log.
  dm <- .api_dep_read_manifest(file.path(dep,'deployment_manifest.tsv'))
  dc <- utils::read.delim(file.path(dep,'effective_config.tsv'),sep='\t',stringsAsFactors=FALSE,check.names=FALSE)
  computed_dep_id <- .api_dep_id(dm,dc)
  recorded_dep_id <- trimws(readLines(file.path(dep,'deployment_id.txt'),warn=FALSE,n=1L))
  if (!identical(computed_dep_id,recorded_dep_id)) {
    cat('api deployment identity mismatch: recorded=',recorded_dep_id,' computed=',computed_dep_id,'\n',sep='',file=stderr())
  }
  deployment <- .api_deployment_validate(dep,repo_root=repo,validate_environment=TRUE)
  fallback_base <- if(is.null(wc$olis_fallback)||!nzchar(wc$olis_fallback)) 'none' else basename(wc$olis_fallback)
  fallback_sha <- if(!is.null(wc$olis_fallback)&&nzchar(wc$olis_fallback)&&file.exists(wc$olis_fallback)) .api_sha256_file(wc$olis_fallback) else 'none'
  worker_map <- c(
    forecast_release_id=wc$forecast_release_id,forecast_release_dir=normalizePath(wc$forecast_release_dir,winslash='/',mustWork=TRUE),season=wc$season,source_mode=wc$source_mode,
    job_root=normalizePath(wc$job_root,winslash='/',mustWork=TRUE),output_root=normalizePath(wc$output_root,winslash='/',mustWork=TRUE),rscript=normalizePath(wc$rscript,winslash='/',mustWork=TRUE),
    rscript_sha256=.api_sha256_file(wc$rscript),max_runtime_seconds=as.character(as.integer(wc$max_runtime_seconds)),repo_root=repo,
    olis_fallback_basename=fallback_base,olis_fallback_sha256=fallback_sha)
  for (k in names(worker_map)) if (!identical(as.character(deployment$config[[k]]),as.character(worker_map[[k]]))) stop('Worker configuration differs from API deployment identity: ',k,call.=FALSE)
  source('scripts/v3_shadow_release_helpers_v1.R')
  rel <- .v3_release_validate(wc$forecast_release_dir,expected_id=wc$forecast_release_id)
  if (!identical(rel$release_id,.PAGE_FORECAST_RELEASE_ID)) stop('Unexpected forecast release.',call.=FALSE)

  cfg <- list(repo_root=repo,api_deployment_dir=dep,job_root=opt$job_root,season=wc$season,
    forecast_release_dir=wc$forecast_release_dir,forecast_release_id=wc$forecast_release_id,
    output_root=wc$output_root,source_mode=wc$source_mode,olis_fallback=wc$olis_fallback,
    rscript=wc$rscript,max_runtime_seconds=as.integer(wc$max_runtime_seconds),transaction_schema=wc$transaction_schema)
  if (!identical(req$season,cfg$season)||!identical(req$expected_release_id,cfg$forecast_release_id)) stop('Worker request/config mismatch.',call.=FALSE)
  if (!requireNamespace('processx',quietly=TRUE)) stop('processx missing.',call.=FALSE)

  run_root <- file.path(cfg$output_root,'api-runs',opt$run_id)
  stdout_path <- file.path(job_dir,'worker.stdout.log'); stderr_path <- file.path(job_dir,'worker.stderr.log')
  if (dir.exists(run_root)) {
    fail <- .api_safe_failure('transaction_binding_failed')
    .api_atomic_write_json(c(list(status='failed',exit_code=NA_integer_,finished_utc=.api_now()),list(failure_code=fail$code,failure_message=fail$message)),.api_worker_result_path(cfg,opt$run_id),immutable=TRUE)
    return(invisible(FALSE))
  }
  args2 <- c('--vanilla','2026/run_weekly_shadow_release_v4.R',paste0('--season=',cfg$season),paste0('--release-dir=',normalizePath(cfg$forecast_release_dir,winslash='/',mustWork=TRUE)),paste0('--source=',cfg$source_mode),paste0('--output-root=',run_root))
  if (!is.null(cfg$olis_fallback)&&nzchar(cfg$olis_fallback)) args2 <- c(args2,paste0('--olis-fallback=',cfg$olis_fallback))
  child_env <- c(
    R_LIBS_USER='/nonexistent/page-api-user-library',
    R_PROFILE_USER='/dev/null',R_ENVIRON_USER='/dev/null',
    R_LIBS_SITE='/usr/local/lib/R/site-library:/usr/lib/R/site-library',
    TZ='UTC',LANG='C.UTF-8',LC_ALL='C.UTF-8'
  )
  # Preserve only transport/certificate variables potentially required by the governed source resolver.
  keep <- c('http_proxy','https_proxy','HTTP_PROXY','HTTPS_PROXY','NO_PROXY','no_proxy','SSL_CERT_FILE','SSL_CERT_DIR')
  vals <- Sys.getenv(keep,unset=NA_character_); vals <- vals[!is.na(vals)&nzchar(vals)]; if (length(vals)) child_env <- c(child_env,vals)

  run <- tryCatch(processx::run(cfg$rscript,args2,wd=repo,env=child_env,stdout=stdout_path,stderr=stderr_path,timeout=cfg$max_runtime_seconds,cleanup_tree=TRUE,error_on_status=FALSE),error=identity)
  if (inherits(run,'error')) {
    code <- if (grepl('timed out|timeout',conditionMessage(run),ignore.case=TRUE)) 'worker_timeout' else 'forecast_transaction_failed'
    f <- .api_safe_failure(code)
    .api_atomic_write_json(list(status='failed',exit_code=NA_integer_,failure_code=f$code,failure_message=f$message,finished_utc=.api_now()),.api_worker_result_path(cfg,opt$run_id),immutable=TRUE)
    return(invisible(FALSE))
  }
  if (isTRUE(run$timeout)) {
    f <- .api_safe_failure('worker_timeout')
    .api_atomic_write_json(list(status='failed',exit_code=as.integer(run$status),failure_code=f$code,failure_message=f$message,finished_utc=.api_now()),.api_worker_result_path(cfg,opt$run_id),immutable=TRUE)
    return(invisible(FALSE))
  }
  if (!identical(as.integer(run$status),0L)) {
    f <- .api_safe_failure('forecast_transaction_failed')
    .api_atomic_write_json(list(status='failed',exit_code=as.integer(run$status),failure_code=f$code,failure_message=f$message,finished_utc=.api_now()),.api_worker_result_path(cfg,opt$run_id),immutable=TRUE)
    return(invisible(FALSE))
  }
  proj <- tryCatch(.api_validate_and_project_transaction(cfg,opt$run_id,persist=TRUE),error=identity)
  if (inherits(proj,'error')) {
    f <- .api_safe_failure('transaction_validation_failed')
    .api_atomic_write_json(list(status='failed',exit_code=0L,failure_code=f$code,failure_message=f$message,finished_utc=.api_now()),.api_worker_result_path(cfg,opt$run_id),immutable=TRUE)
    return(invisible(FALSE))
  }
  .api_atomic_write_json(list(status='succeeded',exit_code=0L,finished_utc=.api_now(),origin_weekF=proj$result$origin_weekF,effective_panel_sha256=proj$result$effective_panel_sha256,transaction_id=proj$transaction_ref$transaction_id),.api_worker_result_path(cfg,opt$run_id),immutable=TRUE)
  invisible(TRUE)
}

if (sys.nframe()==0L) .main(commandArgs(trailingOnly=TRUE))
