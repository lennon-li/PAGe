library(testthat)
find_repo_api_worker <- function(){d<-normalizePath(getwd(),winslash='/',mustWork=TRUE);for(i in 0:6){if(file.exists(file.path(d,'PAGe/DESCRIPTION')))return(d);d<-dirname(d)};stop('repo')}
repo<-find_repo_api_worker();old<-setwd(repo);on.exit(setwd(old),add=TRUE)
source('scripts/v3_weekly_api_helpers_v1.R')
source('scripts/v3_weekly_api_deployment_helpers_v1.R')
source('scripts/build_v3_weekly_api_deployment_v1.R',local=environment())
source('2026/page_weekly_api_v1.R',local=environment())
source('2026/run_page_weekly_api_worker_v1.R',local=environment())

make_fixture <- function(path){dates<-as.Date('2026-07-05')+7*(0:14);r<-list(fluA=data.frame(date=dates,pos=round(seq(2,30,length.out=15)),tests=rep(1000,15)),fluB=data.frame(date=dates,pos=round(seq(1,8,length.out=15)),tests=rep(1000,15)));save(r,file=path)}
find_tx <- function(root){ds<-list.dirs(file.path(root,'2026-27'),recursive=FALSE,full.names=TRUE);ds<-ds[!basename(ds)%in%c('.pending','failures') & !grepl('-FAILED$',basename(ds))];ds[file.exists(file.path(ds,'COMPLETED'))][[1]]}

test_that('API worker is semantically equivalent to direct governed CLI transaction',{
  skip_if_not_installed('processx')
  td<-tempfile('api-worker-');dir.create(td); mount<-file.path(td,'mount');dir.create(mount);job<-file.path(mount,'jobs');out<-file.path(mount,'out');dep_root<-file.path(mount,'deployments');dir.create(job);dir.create(out);dir.create(dep_root)
  fixture<-file.path(td,'hist.RData');make_fixture(fixture)
  release_dir<-file.path(repo,'artifacts/v3-shadow-release-v1',.PAGE_FORECAST_RELEASE_ID)
  opt<-list(deployment_root=dep_root,artifact_mount=mount,job_root=job,output_root=out,source_mode='olis',season='2026-27',bind_host='127.0.0.1',port='8088',rscript=Sys.which('Rscript'),forecast_release_dir=release_dir,olis_fallback=fixture,max_runtime_seconds='300',mode='test')
  dep<-.api_build_deployment(opt,repo)
  tamper_repo<-file.path(td,'tamper-repo');dir.create(tamper_repo)
  boot<-c('scripts/v3_weekly_api_deployment_helpers_v1.R','scripts/v3_weekly_api_helpers_v1.R','scripts/v3_shadow_release_helpers_v1.R','scripts/v3_shadow_ops_helpers_v1.R','2026/run_weekly_shadow_release_v3.R')
  for(rel in boot){dst<-file.path(tamper_repo,rel);dir.create(dirname(dst),recursive=TRUE,showWarnings=FALSE);file.copy(file.path(repo,rel),dst,overwrite=TRUE)}
  cat('\n# injected drift\n',file=file.path(tamper_repo,'scripts/v3_weekly_api_helpers_v1.R'),append=TRUE)
  expect_error(.bootstrap_validate(dep$deployment_dir,tamper_repo,boot),'Bootstrap hash drift',fixed=TRUE)
  cfg<-list(repo_root=repo,api_deployment_dir=dep$deployment_dir,job_root=job,output_root=out,artifact_mount=mount,season='2026-27',source_mode='olis',forecast_release_id=.PAGE_FORECAST_RELEASE_ID,forecast_release_dir=release_dir,rscript=Sys.which('Rscript'),max_runtime_seconds=300L,olis_fallback=fixture,transaction_schema=file.path(repo,'governance/v3_weekly_api_transaction_schema_v1.csv'),api_environment=file.path(repo,'governance/v3_weekly_api_environment_v1.tsv'))
  token<-paste(rep('a',64),collapse='');cfg$token_file<-file.path(td,'token');writeLines(token,cfg$token_file);Sys.chmod(cfg$token_file,'0600')
  ctx<-.page_api_create_context(cfg,dep$deployment_id,token,strict_mount=FALSE);.api_init_store(cfg);expect_true(.page_api_run_preflight_sync(ctx));ctx$ready<-TRUE;ctx$ready_checked<-Sys.time()-61;expect_false(.page_api_refresh_ready(ctx,FALSE));expect_false(ctx$ready);deadline<-Sys.time()+30;while(!is.null(ctx$preflight_process)&&isTRUE(ctx$preflight_process$is_alive())&&Sys.time()<deadline)Sys.sleep(.05);.page_api_poll_preflight(ctx);expect_true(ctx$ready)
  run_id<-.api_new_run_id();jd<-.api_job_dir(cfg,run_id);dir.create(jd)
  .api_atomic_write_json(list(run_id=run_id,api_contract_version=.PAGE_API_CONTRACT,season='2026-27',expected_release_id=.PAGE_FORECAST_RELEASE_ID,source_mode='olis',created_utc=.api_now(),service_instance_id='test'),.api_request_path(cfg,run_id),TRUE)
  .api_atomic_write_json(.api_external_worker_config(cfg),file.path(jd,'worker_config.json'),TRUE)
  env<-c(PATH=Sys.getenv('PATH'),HOME='/nonexistent/page-api-home',R_LIBS_USER='/nonexistent/page-api-user-library',R_LIBS_SITE='/usr/local/lib/R/site-library:/usr/lib/R/site-library',R_PROFILE_USER='/dev/null',R_ENVIRON_USER='/dev/null',TZ='UTC',LANG='C.UTF-8',LC_ALL='C.UTF-8')
  preflight_result<-file.path(td,'preflight.json')
  pf<-processx::run(Sys.which('Rscript'),c('--vanilla','2026/run_page_weekly_api_preflight_v1.R',paste0('--deployment-dir=',dep$deployment_dir),paste0('--repo-root=',repo),paste0('--release-dir=',release_dir),paste0('--expected-release-id=',.PAGE_FORECAST_RELEASE_ID),paste0('--result-path=',preflight_result)),wd=repo,env=env,timeout=120,stdout='|',stderr='|',error_on_status=FALSE)
  expect_identical(as.integer(pf$status),0L); expect_true(file.exists(preflight_result)); expect_true(isTRUE(.api_read_json(preflight_result)$ok))
  wr<-processx::run(Sys.which('Rscript'),c('--vanilla','2026/run_page_weekly_api_worker_v1.R',paste0('--job-root=',job),paste0('--run-id=',run_id)),wd=repo,env=env,timeout=360000,stdout='|',stderr='|',error_on_status=FALSE)
  if(as.integer(wr$status)!=0L) cat('WORKER STDOUT\n',wr$stdout,'\nWORKER STDERR\n',wr$stderr,'\n'); expect_identical(as.integer(wr$status),0L)
  wres<-.api_read_json(.api_worker_result_path(cfg,run_id));expect_identical(wres$status,'succeeded');expect_true(file.exists(file.path(jd,'result.json')));expect_true(file.exists(file.path(jd,'provenance.json')))
  api_result<-.api_read_json(file.path(jd,'result.json'));api_prov<-.api_read_json(file.path(jd,'provenance.json'))

  direct_root<-file.path(td,'direct');dr<-processx::run(Sys.which('Rscript'),c('--vanilla','2026/run_weekly_shadow_release_v3.R','--season=2026-27','--source=olis',paste0('--olis-fallback=',fixture),paste0('--release-dir=',release_dir),paste0('--output-root=',direct_root)),wd=repo,env=env,timeout=360000,stdout='|',stderr='|',error_on_status=FALSE)
  expect_identical(as.integer(dr$status),0L)
  dtx<-find_tx(direct_root);cmp<-read.csv(file.path(dtx,'v2_v3_comparison.csv'),stringsAsFactors=FALSE);tx<-read.delim(file.path(dtx,'source_transaction.tsv'),stringsAsFactors=FALSE);tx<-setNames(tx$value,tx$key)
  af<-do.call(rbind,lapply(api_result$forecasts,function(z)data.frame(type=z$type,horizon=as.integer(z$horizon),v2=as.numeric(z$v2_pct),v3=as.numeric(z$v3_pct),delta=as.numeric(z$delta_pp),route=z$v3_route)))
  cmp<-cmp[order(cmp$type,cmp$horizon),];af<-af[order(af$type,af$horizon),]
  expect_identical(af$type,cmp$type);expect_identical(af$horizon,as.integer(cmp$horizon));expect_equal(af$v2,cmp$v2_forecast_pct,tolerance=1e-12);expect_equal(af$v3,cmp$v3_forecast_pct,tolerance=1e-12);expect_equal(af$delta,cmp$delta_v3_minus_v2_pp,tolerance=1e-12);expect_identical(af$route,cmp$v3_route)
  expect_identical(api_prov$raw_source_sha256,unname(tx[['raw_source_sha256']]));expect_identical(api_prov$effective_panel_sha256,unname(tx[['effective_panel_sha256']]));expect_identical(api_prov$release_id,.PAGE_FORECAST_RELEASE_ID)
})


test_that('worker hard timeout is enforced in seconds and reported safely', {
  skip_if_not_installed('processx')
  td<-tempfile('api-worker-timeout-');dir.create(td);mount<-file.path(td,'mount');dir.create(mount);job<-file.path(mount,'jobs');out<-file.path(mount,'out');dep_root<-file.path(mount,'deployments');dir.create(job);dir.create(out);dir.create(dep_root)
  fixture<-file.path(td,'hist.RData');make_fixture(fixture);release_dir<-file.path(repo,'artifacts/v3-shadow-release-v1',.PAGE_FORECAST_RELEASE_ID)
  opt<-list(deployment_root=dep_root,artifact_mount=mount,job_root=job,output_root=out,source_mode='olis',season='2026-27',bind_host='127.0.0.1',port='8088',rscript=Sys.which('Rscript'),forecast_release_dir=release_dir,olis_fallback=fixture,max_runtime_seconds='0',mode='test');dep<-.api_build_deployment(opt,repo)
  cfg<-list(repo_root=repo,api_deployment_dir=dep$deployment_dir,job_root=job,output_root=out,artifact_mount=mount,season='2026-27',source_mode='olis',forecast_release_id=.PAGE_FORECAST_RELEASE_ID,forecast_release_dir=release_dir,rscript=Sys.which('Rscript'),max_runtime_seconds=0L,olis_fallback=fixture,transaction_schema=file.path(repo,'governance/v3_weekly_api_transaction_schema_v1.csv'))
  .api_init_store(cfg);rid<-.api_new_run_id();jd<-.api_job_dir(cfg,rid);dir.create(jd);.api_atomic_write_json(list(run_id=rid,api_contract_version=.PAGE_API_CONTRACT,season='2026-27',expected_release_id=.PAGE_FORECAST_RELEASE_ID,source_mode='olis',created_utc=.api_now(),service_instance_id='test'),.api_request_path(cfg,rid),TRUE);.api_atomic_write_json(.api_external_worker_config(cfg),file.path(jd,'worker_config.json'),TRUE)
  env<-c(PATH=Sys.getenv('PATH'),HOME='/nonexistent/page-api-home',R_LIBS_USER='/nonexistent/page-api-user-library',R_LIBS_SITE='/usr/local/lib/R/site-library:/usr/lib/R/site-library',R_PROFILE_USER='/dev/null',R_ENVIRON_USER='/dev/null',TZ='UTC',LANG='C.UTF-8',LC_ALL='C.UTF-8')
  z<-processx::run(Sys.which('Rscript'),c('--vanilla','2026/run_page_weekly_api_worker_v1.R',paste0('--job-root=',job),paste0('--run-id=',rid)),wd=repo,env=env,timeout=120,stdout='|',stderr='|',error_on_status=FALSE)
  expect_identical(as.integer(z$status),0L);wr<-.api_read_json(.api_worker_result_path(cfg,rid));expect_identical(wr$status,'failed');expect_identical(wr$failure_code,'worker_timeout');expect_identical(wr$failure_message,.PAGE_SAFE_FAILURES[['worker_timeout']])
})


test_that('production API deployment requires explicit governed mount identity', {
  opt <- list(deployment_root='/does/not/matter',artifact_mount='/does/not/matter',artifact_fs_type=NULL,artifact_mount_source=NULL,job_root='/does/not/matter/jobs',output_root='/does/not/matter/out',source_mode='auto',season='2026-27',bind_host='127.0.0.1',port='8088',rscript=Sys.which('Rscript'),forecast_release_dir=file.path(repo,'artifacts/v3-shadow-release-v1',.PAGE_FORECAST_RELEASE_ID),olis_fallback=NULL,max_runtime_seconds='1800',mode='production')
  expect_error(.api_build_deployment(opt,repo),'Missing deployment build option: artifact_fs_type',fixed=TRUE)
  opt$artifact_fs_type <- 'nfs4'
  expect_error(.api_build_deployment(opt,repo),'Missing deployment build option: artifact_mount_source',fixed=TRUE)
  opt$artifact_mount_source <- 'server:/export/page'; opt$artifact_fs_type <- 'ext4'
  expect_error(.api_build_deployment(opt,repo),'Production artifact filesystem must be nfs or nfs4',fixed=TRUE)
})
