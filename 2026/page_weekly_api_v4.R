# PAGe weekly API v4 httpuv adapter. Assumes deployment/core/release helpers loaded.

.page_json_response <- function(status,obj) list(status=as.integer(status),headers=list('Content-Type'='application/json; charset=utf-8','Cache-Control'='no-store','X-Content-Type-Options'='nosniff'),body=.api_canonical_json(obj))

.page_api_sanitized_env <- function() c(PATH=Sys.getenv('PATH'),HOME='/nonexistent/page-api-home',R_LIBS_USER='/nonexistent/page-api-user-library',R_LIBS_SITE='/usr/local/lib/R/site-library:/usr/lib/R/site-library',R_PROFILE_USER='/dev/null',R_ENVIRON_USER='/dev/null',TZ='UTC',LANG='C.UTF-8',LC_ALL='C.UTF-8')

.page_api_spawn_worker <- function(ctx,run_id) {
  jd <- .api_job_dir(ctx$config,run_id)
  env <- .page_api_sanitized_env()
  p <- processx::process$new(ctx$config$rscript,c('--vanilla','2026/run_page_weekly_api_worker_v4.R',paste0('--job-root=',ctx$config$job_root),paste0('--run-id=',run_id)),wd=ctx$config$repo_root,env=env,stdout=file.path(jd,'supervisor-worker.stdout.log'),stderr=file.path(jd,'supervisor-worker.stderr.log'),cleanup_tree=TRUE)
  assign(run_id,p,envir=ctx$process_registry)
  list(pid=p$get_pid(),start_token=.api_proc_start_token(p$get_pid()),process=p)
}

.page_api_quick_preflight <- function(ctx) {
  tryCatch({ .api_validate_storage(ctx$config,strict_mount=ctx$strict_mount); .api_read_token_file(ctx$config$token_file); TRUE },error=function(e) FALSE)
}

.page_api_preflight_result_path <- function(ctx) {
  d <- file.path(ctx$config$job_root,'runtime'); dir.create(d,recursive=TRUE,mode='0700',showWarnings=FALSE)
  file.path(d,paste0('preflight-',ctx$service_instance_id,'.json'))
}

.page_api_preflight_args <- function(ctx,result_path) c('--vanilla','2026/run_page_weekly_api_preflight_v4.R',paste0('--deployment-dir=',ctx$config$api_deployment_dir),paste0('--repo-root=',ctx$config$repo_root),paste0('--release-dir=',ctx$config$forecast_release_dir),paste0('--expected-release-id=',ctx$config$forecast_release_id),paste0('--result-path=',result_path))

.page_api_run_preflight_sync <- function(ctx) {
  if (!.page_api_quick_preflight(ctx)) { ctx$ready<-FALSE; return(FALSE) }
  rp <- .page_api_preflight_result_path(ctx); unlink(rp)
  r <- tryCatch(processx::run(ctx$config$rscript,.page_api_preflight_args(ctx,rp),wd=ctx$config$repo_root,env=.page_api_sanitized_env(),timeout=120,stdout='|',stderr='|',error_on_status=FALSE),error=function(e) NULL)
  ok <- !is.null(r) && identical(as.integer(r$status),0L) && file.exists(rp) && isTRUE(tryCatch(.api_read_json(rp)$ok,error=function(e) FALSE))
  ctx$ready <- ok; ctx$ready_checked <- Sys.time(); ok
}

.page_api_start_preflight <- function(ctx) {
  if (!is.null(ctx$preflight_process) && isTRUE(tryCatch(ctx$preflight_process$is_alive(),error=function(e) FALSE))) return(invisible(FALSE))
  if (!.page_api_quick_preflight(ctx)) { ctx$ready<-FALSE; ctx$ready_checked<-Sys.time(); return(invisible(FALSE)) }
  rp <- .page_api_preflight_result_path(ctx); unlink(rp)
  p <- tryCatch(processx::process$new(ctx$config$rscript,.page_api_preflight_args(ctx,rp),wd=ctx$config$repo_root,env=.page_api_sanitized_env(),stdout=file.path(ctx$config$job_root,'runtime','preflight.stdout.log'),stderr=file.path(ctx$config$job_root,'runtime','preflight.stderr.log'),cleanup_tree=TRUE),error=function(e) NULL)
  if (is.null(p)) { ctx$ready<-FALSE; ctx$ready_checked<-Sys.time(); return(invisible(FALSE)) }
  ctx$preflight_process <- p; ctx$preflight_result_path <- rp; invisible(TRUE)
}

.page_api_poll_preflight <- function(ctx) {
  p <- ctx$preflight_process; if (is.null(p)) return(invisible(NULL))
  if (isTRUE(tryCatch(p$is_alive(),error=function(e) FALSE))) return(invisible(NULL))
  status <- tryCatch(p$get_exit_status(),error=function(e) NA_integer_)
  ok <- identical(as.integer(status),0L) && !is.null(ctx$preflight_result_path) && file.exists(ctx$preflight_result_path) && isTRUE(tryCatch(.api_read_json(ctx$preflight_result_path)$ok,error=function(e) FALSE))
  ctx$ready <- ok; ctx$ready_checked <- Sys.time(); ctx$preflight_process <- NULL; invisible(ok)
}

.page_api_refresh_ready <- function(ctx,force=FALSE) {
  .page_api_poll_preflight(ctx)
  if (isTRUE(force)) return(.page_api_run_preflight_sync(ctx))
  age <- as.numeric(difftime(Sys.time(),ctx$ready_checked,units='secs'))
  if (!is.finite(age)) age <- Inf
  if (age > 45 && is.null(ctx$preflight_process)) .page_api_start_preflight(ctx)
  if (age > 60) ctx$ready <- FALSE
  isTRUE(ctx$ready) && age <= 60
}

.page_api_reconcile <- function(ctx,run_id=NULL) {
  got <- .api_acquire_admission(ctx$config,ctx$service_instance_id)
  if (!isTRUE(got)) return(invisible(NULL))
  on.exit(.api_release_admission(ctx$config,ctx$service_instance_id),add=TRUE)
  if (is.null(run_id)) .api_reconcile_all(ctx$config,ctx$service_instance_id,ctx$process_registry) else .api_reconcile_job(ctx$config,run_id,ctx$service_instance_id,ctx$process_registry)
}

.page_api_release_projection <- function(ctx) {
  inv_path <- file.path(ctx$config$forecast_release_dir,'canonical_component_inventory.csv')
  inv <- utils::read.csv(inv_path,stringsAsFactors=FALSE,check.names=FALSE)
  if (all(c('component','canonical_path','status') %in% names(inv))) {
    names(inv)[names(inv)=='component'] <- 'role'
    names(inv)[names(inv)=='canonical_path'] <- 'path'
    inv$status[inv$status %in% c('shadow_only','accepted_shadow')] <- 'canonical'
  }
  if (!all(c('role','path','status') %in% names(inv))) stop('Release component inventory schema is unsupported.',call.=FALSE)
  get_version <- function(role) { r<-inv[inv$role==role & inv$status=='canonical',,drop=FALSE]; if(nrow(r)!=1L)return(NA_character_); basename(dirname(r$path[[1]])) }
  list(release_id=ctx$config$forecast_release_id,release_basename=basename(ctx$config$forecast_release_dir),status='shadow_only',api_contract_version=.PAGE_API_CONTRACT,api_deployment_id=ctx$deployment_id,api_environment_sha256=.api_sha256_file(ctx$config$api_environment),M1_B_version=get_version('M1_B'),M2_B_version=get_version('M2_B'))
}

.page_api_handle <- function(ctx,method,path,headers=list(),body='') {
  method <- toupper(method); path <- sub('[?].*$','',path)
  if (identical(path,'/healthz') && method=='GET') return(.page_json_response(200,list(status='ok')))
  if (identical(path,'/readyz') && method=='GET') {
    ok <- .page_api_refresh_ready(ctx,FALSE); return(.page_json_response(if(ok)200 else 503,list(ready=ok)))
  }
  auth <- headers[['authorization']] %||% headers[['Authorization']]
  if (!.api_validate_bearer(auth,ctx$token)) return(.page_json_response(401,list(error='unauthorized')))
  if (identical(path,'/v1/release') && method=='GET') return(.page_json_response(200,.page_api_release_projection(ctx)))
  if (identical(path,'/v1/weekly-runs') && method=='POST') {
    if (!.page_api_refresh_ready(ctx,FALSE)) return(.page_json_response(503,list(error='api_not_ready')))
    idem <- headers[['idempotency-key']] %||% headers[['Idempotency-Key']]
    req <- tryCatch(.api_validate_trigger_request(body,ctx$config),error=function(e) NULL)
    key <- tryCatch(.api_validate_idempotency_key(idem),error=function(e) NULL)
    if (is.null(req)||is.null(key)) return(.page_json_response(400,list(error='invalid_request')))
    a <- tryCatch(.api_admit(ctx$config,req,key,ctx$service_instance_id,function(id).page_api_spawn_worker(ctx,id)),error=identity)
    if (inherits(a,'error')) return(.page_json_response(500,list(error='internal_error')))
    if (a$status=='conflict') return(.page_json_response(409,list(error='idempotency_conflict',run_id=a$run_id)))
    if (a$status=='busy') return(.page_json_response(409,list(error='season_busy',run_id=a$run_id)))
    if (a$status=='failed') return(.page_json_response(500,list(error='worker_spawn_failed',run_id=a$run_id)))
    pr <- .api_job_projection(ctx$config,a$run_id)
    pr$status_url <- paste0('/v1/weekly-runs/',a$run_id)
    return(.page_json_response(if(a$status=='existing' && pr$status %in% c('succeeded','failed'))200 else 202,pr))
  }
  m <- regexec('^/v1/weekly-runs/(wr_[0-9a-f]{32})(/(result|provenance))?$',path); hit <- regmatches(path,m)[[1]]
  if (length(hit)) {
    if (!identical(method,'GET')) return(.page_json_response(405,list(error='method_not_allowed')))
    run_id <- hit[[2]]; suffix <- if(length(hit)>=4) hit[[4]] else ''
    jd <- .api_job_dir(ctx$config,run_id); if (!dir.exists(jd)) return(.page_json_response(404,list(error='not_found')))
    .page_api_reconcile(ctx,run_id)
    if (!nzchar(suffix) && method=='GET') return(.page_json_response(200,.api_job_projection(ctx$config,run_id)))
    st <- .api_job_projection(ctx$config,run_id); if (!identical(st$status,'succeeded')) return(.page_json_response(409,list(error='run_not_succeeded',status=st$status)))
    f <- file.path(jd,paste0(suffix,'.json')); if (!file.exists(f)) return(.page_json_response(500,list(error='internal_error')))
    return(.page_json_response(200,.api_read_json(f)))
  }
  .page_json_response(404,list(error='not_found'))
}

.page_api_create_context <- function(config,deployment_id,token,strict_mount=TRUE) {
  e <- new.env(parent=emptyenv()); e$config<-config; e$deployment_id<-deployment_id; e$token<-token; e$strict_mount<-strict_mount; e$service_instance_id<-.api_random_hex(16L); e$process_registry<-new.env(parent=emptyenv()); e$ready<-FALSE; e$ready_checked<-as.POSIXct(0,origin='1970-01-01',tz='UTC'); e$preflight_process<-NULL; e$preflight_result_path<-NULL; e
}

.page_api_httpuv_app <- function(ctx) {
  list(call=function(req) {
    len <- suppressWarnings(as.integer(req$CONTENT_LENGTH %||% '0')); if (!is.na(len) && len>16384L) return(.page_json_response(413,list(error='request_too_large')))
    method <- req$REQUEST_METHOD %||% 'GET'; path <- req$PATH_INFO %||% '/'; headers <- list(authorization=req$HTTP_AUTHORIZATION,idempotency_key=req$HTTP_IDEMPOTENCY_KEY)
    headers[['idempotency-key']] <- req$HTTP_IDEMPOTENCY_KEY
    body <- ''
    if (method=='POST') {
      ct <- req$CONTENT_TYPE %||% ''; if (!grepl('^application/json($|;)',ct,ignore.case=TRUE)) return(.page_json_response(415,list(error='unsupported_media_type')))
      raw <- req$rook.input$read(16385L); if (length(raw)>16384L) return(.page_json_response(413,list(error='request_too_large'))); body <- rawToChar(raw)
    }
    .page_api_handle(ctx,method,path,headers,body)
  })
}
