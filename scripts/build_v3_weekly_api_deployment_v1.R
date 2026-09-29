#!/usr/bin/env Rscript
options(stringsAsFactors=FALSE)
source('scripts/v3_weekly_api_helpers_v1.R')
source('scripts/v3_weekly_api_deployment_helpers_v1.R')
source('scripts/v3_shadow_release_helpers_v1.R')

.parse <- function(args) {
  out <- list(deployment_root=NULL,artifact_mount=NULL,artifact_fs_type=NULL,artifact_mount_source=NULL,job_root=NULL,output_root=NULL,source_mode='auto',season='2026-27',bind_host='127.0.0.1',port='8088',rscript=Sys.which('Rscript'),forecast_release_dir=NULL,olis_fallback=NULL,max_runtime_seconds='1800',mode='production')
  for (a in args) {
    if (!grepl('^--[^=]+=',a)) stop('Arguments use --key=value.',call.=FALSE)
    k<-gsub('-','_',sub('^--([^=]+)=.*$','\\1',a)); v<-sub('^--[^=]+=','',a); if(!k%in%names(out))stop('Unknown option ',k,call.=FALSE); out[[k]]<-v
  }
  out
}

.api_build_deployment <- function(opt,repo_root=getwd()) {
  repo <- normalizePath(repo_root,winslash='/',mustWork=TRUE)
  required <- c('deployment_root','artifact_mount','job_root','output_root','forecast_release_dir')
  if (identical(opt$mode,'production')) required <- c(required,'artifact_fs_type','artifact_mount_source')
  for (k in required) if (is.null(opt[[k]])||!nzchar(opt[[k]])) stop('Missing deployment build option: ',k,call.=FALSE)
  if (!opt$mode %in% c('production','test')) stop('mode must be production or test.',call.=FALSE)
  if (identical(opt$mode,'production') && !as.character(opt$artifact_fs_type %||% '') %in% c('nfs','nfs4')) stop('Production artifact filesystem must be nfs or nfs4.',call.=FALSE)
  cfg_runtime <- list(artifact_mount=opt$artifact_mount,artifact_fs_type=opt$artifact_fs_type,artifact_mount_source=opt$artifact_mount_source,job_root=opt$job_root,output_root=opt$output_root)
  .api_validate_storage(cfg_runtime,strict_mount=identical(opt$mode,'production'))
  .api_validate_storage_atomic_semantics(cfg_runtime)
  dir.create(opt$deployment_root,recursive=TRUE,mode='0700',showWarnings=FALSE)
  if (identical(opt$mode,'production')) {
    if (!.api_path_under(opt$deployment_root,opt$artifact_mount,TRUE)) stop('Production API deployment root must live under the configured private artifact mount.',call.=FALSE)
    if (!identical(.api_fs_device(opt$deployment_root),.api_fs_device(opt$artifact_mount))) stop('API deployment root must share the artifact filesystem.',call.=FALSE)
  }
  if (!opt$bind_host %in% c('127.0.0.1','::1')) stop('API deployment listener must be loopback.',call.=FALSE)
  if (!identical(opt$season,'2026-27')) stop('API v1 deployment season must be 2026-27.',call.=FALSE)
  if (!opt$source_mode %in% c('auto','orvt','olis')) stop('Invalid source mode.',call.=FALSE)
  .api_assert_regular_nonsymlink(opt$rscript,'Rscript')
  rel <- .v3_release_validate(opt$forecast_release_dir,expected_id=.PAGE_FORECAST_RELEASE_ID)
  .api_validate_environment_manifest(file.path(repo,'governance/v3_weekly_api_environment_v1.tsv'))

  files <- c(
    '2026/page_weekly_api_v1.R','2026/run_page_weekly_api_v1.R','2026/run_page_weekly_api_worker_v1.R','2026/run_page_weekly_api_preflight_v1.R',
    'scripts/v3_weekly_api_helpers_v1.R','scripts/v3_weekly_api_deployment_helpers_v1.R','scripts/build_v3_weekly_api_deployment_v1.R',
    'governance/v3_weekly_api_environment_v1.tsv','governance/v3_weekly_api_routes_v1.csv','governance/v3_weekly_api_transaction_schema_v1.csv','governance/v3_weekly_api_policy_v1.tsv',
    'docs/v3-weekly-deployment-api-plan-2026-09-27.md','docs/v3-weekly-deployment-api-openapi-v1.yaml','docs/v3-weekly-deployment-api-operations-2026-09-27.md','docs/artifact-storage.md',
    'deploy/systemd/page-weekly-api.service','deploy/systemd/page-weekly-trigger.service','deploy/systemd/page-weekly-trigger.timer','deploy/systemd/page-weekly-api.env.example','deploy/systemd/page-weekly-trigger.env.example','deploy/systemd/page-weekly-trigger.curl.example','deploy/systemd/page-weekly-trigger-body.json.example','deploy/systemd/page-weekly-trigger',
    'PAGe/tests/testthat/test-v3-weekly-api-core.R','PAGe/tests/testthat/test-v3-weekly-api-worker.R','PAGe/tests/testthat/test-v3-weekly-api-http.R',
    '2026/run_weekly_shadow_release_v3.R','scripts/v3_shadow_release_helpers_v1.R','scripts/v3_shadow_ops_helpers_v1.R'
  )
  missing <- files[!file.exists(file.path(repo,files))]; if(length(missing)) stop('API deployment source files missing: ',paste(missing,collapse=', '),call.=FALSE)
  roles <- ifelse(grepl('^PAGe/tests/',files),'api_test',ifelse(grepl('^deploy/',files),'deployment_template',ifelse(grepl('^governance/',files),'api_governance',ifelse(grepl('^docs/',files),'documentation',ifelse(grepl('run_weekly_shadow_release|v3_shadow_',files),'forecast_bootstrap','api_source')))))
  manifest <- data.frame(role=roles,path=files,sha256=vapply(file.path(repo,files),.api_sha256_file,character(1)),size_bytes=as.character(file.info(file.path(repo,files))$size),stringsAsFactors=FALSE)
  rscript_abs <- normalizePath(opt$rscript,winslash='/',mustWork=TRUE)
  olis_base <- if(is.null(opt$olis_fallback)||!nzchar(opt$olis_fallback)) 'none' else basename(opt$olis_fallback)
  olis_sha <- if(!is.null(opt$olis_fallback)&&nzchar(opt$olis_fallback)&&file.exists(opt$olis_fallback)) .api_sha256_file(opt$olis_fallback) else 'none'
  effective <- c(
    deployment_mode=opt$mode,forecast_release_id=.PAGE_FORECAST_RELEASE_ID,forecast_release_dir=normalizePath(opt$forecast_release_dir,winslash='/',mustWork=TRUE),
    season=opt$season,source_mode=opt$source_mode,bind_host=opt$bind_host,port=as.character(as.integer(opt$port)),
    artifact_mount=normalizePath(opt$artifact_mount,winslash='/',mustWork=TRUE),artifact_fs_type=as.character(opt$artifact_fs_type %||% 'test-unpinned'),artifact_mount_source=as.character(opt$artifact_mount_source %||% 'test-unpinned'),job_root=normalizePath(opt$job_root,winslash='/',mustWork=TRUE),output_root=normalizePath(opt$output_root,winslash='/',mustWork=TRUE),
    rscript=rscript_abs,rscript_sha256=.api_sha256_file(rscript_abs),max_runtime_seconds=as.character(as.integer(opt$max_runtime_seconds)),repo_root=repo,R_home=normalizePath(R.home(),winslash='/',mustWork=TRUE),
    R_LIBS_USER='/nonexistent/page-api-user-library',R_LIBS_SITE='/usr/local/lib/R/site-library:/usr/lib/R/site-library',timezone='UTC',locale='C.UTF-8',
    olis_fallback_basename=olis_base,olis_fallback_sha256=olis_sha
  )
  cfg_df <- data.frame(key=names(effective),value=unname(effective),stringsAsFactors=FALSE)
  id <- .api_dep_id(manifest,cfg_df)
  root <- normalizePath(opt$deployment_root,winslash='/',mustWork=FALSE); dir.create(root,recursive=TRUE,mode='0700',showWarnings=FALSE)
  final <- file.path(root,id)
  if (dir.exists(final)) { got<-.api_deployment_validate(final,repo,expected_id=id,validate_environment=TRUE); return(got) }
  stage <- file.path(root,paste0('.pending-',Sys.getpid(),'-',substr(id,1,12))); if(dir.exists(stage))stop('API deployment staging directory exists.',call.=FALSE); dir.create(stage,mode='0700')
  utils::write.table(manifest,file.path(stage,'deployment_manifest.tsv'),sep='\t',quote=FALSE,row.names=FALSE)
  utils::write.table(cfg_df,file.path(stage,'effective_config.tsv'),sep='\t',quote=FALSE,row.names=FALSE)
  writeLines(id,file.path(stage,'deployment_id.txt'),useBytes=TRUE)
  meta <- data.frame(key=c('deployment_family','deployment_id','created_utc','forecast_release_id','mode','manifest_entries'),value=c(.PAGE_API_CONTRACT,id,.api_now(),.PAGE_FORECAST_RELEASE_ID,opt$mode,nrow(manifest)),stringsAsFactors=FALSE)
  utils::write.table(meta,file.path(stage,'metadata.tsv'),sep='\t',quote=FALSE,row.names=FALSE)
  .api_deployment_validate(stage,repo,expected_id=id,validate_environment=TRUE,require_content_addressed_name=FALSE)
  if(!file.rename(stage,final))stop('Could not atomically publish API deployment.',call.=FALSE)
  .api_deployment_validate(final,repo,expected_id=id,validate_environment=TRUE)
}

if (sys.nframe()==0L) {
  x <- .api_build_deployment(.parse(commandArgs(trailingOnly=TRUE)))
  cat('Built PAGe weekly API deployment\n'); cat('deployment_id: ',x$deployment_id,'\n',sep=''); cat('deployment_dir: ',x$deployment_dir,'\n',sep='')
}
