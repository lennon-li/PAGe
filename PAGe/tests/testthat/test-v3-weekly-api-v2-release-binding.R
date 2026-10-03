library(testthat)

find_repo_api_v2 <- function() {
  d <- normalizePath(getwd(),winslash='/',mustWork=TRUE)
  for (i in 0:6) { if (file.exists(file.path(d,'PAGe/DESCRIPTION'))) return(d); d <- dirname(d) }
  stop('repo')
}

repo <- find_repo_api_v2(); old <- setwd(repo); on.exit(setwd(old),add=TRUE)
source('scripts/v3_weekly_api_helpers_v2.R')
source('scripts/v3_weekly_api_deployment_helpers_v1.R')
source('scripts/build_v3_weekly_api_deployment_v2.R',local=environment())

make_early_fixture <- function(path) {
  dates <- as.Date('2026-07-05') + 7*(0:10)
  r <- list(
    fluA=data.frame(date=dates,pos=c(2,3,4,5,8,12,18,26,38,62,115),tests=c(rep(4000,10),6599)),
    fluB=data.frame(date=dates,pos=c(0,0,1,0,1,1,1,2,1,2,2),tests=c(rep(4000,10),6530)))
  save(r,file=path)
}

test_that('API v2 binds relaxed forecast release and worker issues at weekF11', {
  skip_if_not_installed('processx')
  expect_identical(.PAGE_API_CONTRACT,'page-weekly-api-v2')
  expect_identical(.PAGE_FORECAST_RELEASE_ID,'65f29aeb58c5bc40662855da6e9cbd4e13c55ca66c4183c27a242804d9388d64')

  td <- tempfile('api-v2-binding-'); dir.create(td)
  mount <- file.path(td,'mount'); job <- file.path(mount,'jobs'); out <- file.path(mount,'out'); dep_root <- file.path(mount,'deployments')
  dir.create(job,recursive=TRUE); dir.create(out); dir.create(dep_root)
  fixture <- file.path(td,'hist.RData'); make_early_fixture(fixture)
  release_dir <- file.path(repo,'artifacts/v3-shadow-release-v2',.PAGE_FORECAST_RELEASE_ID)
  stale <- release_dir_stale_reason(release_dir); skip_if(!is.null(stale),stale)
  opt <- list(deployment_root=dep_root,artifact_mount=mount,artifact_fs_type=NULL,artifact_mount_source=NULL,job_root=job,output_root=out,source_mode='olis',season='2026-27',bind_host='127.0.0.1',port='8088',rscript=Sys.which('Rscript'),forecast_release_dir=release_dir,olis_fallback=fixture,max_runtime_seconds='300',mode='test')
  dep <- .api_build_deployment(opt,repo)
  expect_true(file.exists(file.path(dep$deployment_dir,'deployment_manifest.tsv')))
  manifest <- read.delim(file.path(dep$deployment_dir,'deployment_manifest.tsv'),sep='\t',stringsAsFactors=FALSE,check.names=FALSE)
  expect_true('scripts/v3_weekly_api_helpers_v2.R' %in% manifest$path)
  expect_true('2026/run_page_weekly_api_worker_v2.R' %in% manifest$path)
  expect_true('2026/run_weekly_shadow_release_v4.R' %in% manifest$path)

  cfg <- list(repo_root=repo,api_deployment_dir=dep$deployment_dir,job_root=job,output_root=out,artifact_mount=mount,season='2026-27',source_mode='olis',forecast_release_id=.PAGE_FORECAST_RELEASE_ID,forecast_release_dir=release_dir,rscript=Sys.which('Rscript'),max_runtime_seconds=300L,olis_fallback=fixture,transaction_schema=file.path(repo,'governance/v3_weekly_api_transaction_schema_v1.csv'),api_environment=file.path(repo,'governance/v3_weekly_api_environment_v1.tsv'))
  .api_init_store(cfg)
  run_id <- .api_new_run_id(); jd <- .api_job_dir(cfg,run_id); dir.create(jd)
  .api_atomic_write_json(list(run_id=run_id,api_contract_version=.PAGE_API_CONTRACT,season='2026-27',expected_release_id=.PAGE_FORECAST_RELEASE_ID,source_mode='olis',created_utc=.api_now(),service_instance_id='test'),.api_request_path(cfg,run_id),TRUE)
  .api_atomic_write_json(.api_external_worker_config(cfg),file.path(jd,'worker_config.json'),TRUE)

  env <- c(PATH=Sys.getenv('PATH'),HOME='/nonexistent/page-api-home',R_LIBS_USER='/nonexistent/page-api-user-library',R_LIBS_SITE='/usr/local/lib/R/site-library:/usr/lib/R/site-library',R_PROFILE_USER='/dev/null',R_ENVIRON_USER='/dev/null',TZ='UTC',LANG='C.UTF-8',LC_ALL='C.UTF-8')
  preflight_result <- file.path(td,'preflight.json')
  pf <- processx::run(Sys.which('Rscript'),c('--vanilla','2026/run_page_weekly_api_preflight_v2.R',paste0('--deployment-dir=',dep$deployment_dir),paste0('--repo-root=',repo),paste0('--release-dir=',release_dir),paste0('--expected-release-id=',.PAGE_FORECAST_RELEASE_ID),paste0('--result-path=',preflight_result)),wd=repo,env=env,timeout=120,stdout='|',stderr='|',error_on_status=FALSE)
  expect_identical(as.integer(pf$status),0L)

  wr <- processx::run(Sys.which('Rscript'),c('--vanilla','2026/run_page_weekly_api_worker_v2.R',paste0('--job-root=',job),paste0('--run-id=',run_id)),wd=repo,env=env,timeout=360000,stdout='|',stderr='|',error_on_status=FALSE)
  if (as.integer(wr$status)!=0L) cat('WORKER STDOUT\n',wr$stdout,'\nWORKER STDERR\n',wr$stderr,'\n')
  expect_identical(as.integer(wr$status),0L)
  wres <- .api_read_json(.api_worker_result_path(cfg,run_id)); expect_identical(wres$status,'succeeded')
  result <- .api_read_json(file.path(jd,'result.json'))
  expect_identical(as.integer(result$origin_weekF),11L)
  expect_identical(result$release_id,.PAGE_FORECAST_RELEASE_ID)
  expect_identical(length(result$forecasts),4L)
  expect_true(all(vapply(result$forecasts,function(z)is.finite(as.numeric(z$v3_pct)),logical(1))))
})
