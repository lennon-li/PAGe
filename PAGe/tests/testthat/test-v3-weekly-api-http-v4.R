library(testthat)
find_repo_api_http <- function(){d<-normalizePath(getwd(),winslash='/',mustWork=TRUE);for(i in 0:6){if(file.exists(file.path(d,'PAGe/DESCRIPTION')))return(d);d<-dirname(d)};stop('repo')}
repo<-find_repo_api_http();old<-setwd(repo);on.exit(setwd(old),add=TRUE)
source('scripts/v3_weekly_api_helpers_v4.R',local=environment())
source('2026/page_weekly_api_v4.R',local=environment())

make_http_ctx <- function(td){
  mount<-file.path(td,'mount');dir.create(mount);job<-file.path(mount,'jobs');out<-file.path(mount,'out');dir.create(job);dir.create(out)
  cfg<-list(repo_root=repo,api_deployment_dir=file.path(td,'dep'),job_root=job,output_root=out,artifact_mount=mount,season='2026-27',source_mode='olis',forecast_release_id=.PAGE_FORECAST_RELEASE_ID,forecast_release_dir=file.path(repo,'artifacts/v3-shadow-release-v3',.PAGE_FORECAST_RELEASE_ID),rscript=Sys.which('Rscript'),max_runtime_seconds=300L,olis_fallback=NULL,transaction_schema=file.path(repo,'governance/v3_weekly_api_transaction_schema_v1.csv'),api_environment=file.path(repo,'governance/v3_weekly_api_environment_v1.tsv'),token_file=file.path(td,'token'))
  tok<-paste(rep('a',64),collapse='');writeLines(tok,cfg$token_file);Sys.chmod(cfg$token_file,'0600')
  ctx<-.page_api_create_context(cfg,'dep-test',tok,strict_mount=FALSE);ctx$ready<-TRUE;ctx$ready_checked<-Sys.time();.api_init_store(cfg)
  list(ctx=ctx,cfg=cfg,tok=tok)
}

parse_body <- function(resp) jsonlite::fromJSON(resp$body,simplifyVector=FALSE)

test_that('HTTP contract enforces auth, strict request, idempotency, and season single-flight',{
  td<-tempfile();dir.create(td);x<-make_http_ctx(td);ctx<-x$ctx;tok<-x$tok
  live<-new.env(parent=emptyenv());live$is_alive<-function() TRUE
  .page_api_spawn_worker <<- function(ctx,run_id){assign(run_id,live,envir=ctx$process_registry);list(pid=Sys.getpid(),start_token=.api_proc_start_token(),process=live)}
  expect_identical(.page_api_handle(ctx,'GET','/healthz')$status,200L)
  expect_identical(.page_api_handle(ctx,'GET','/v1/release')$status,401L)
  h<-list(authorization=paste('Bearer',tok),'idempotency-key'='cycle-1')
  relresp<-.page_api_handle(ctx,'GET','/v1/release',h);expect_identical(relresp$status,200L);rel<-parse_body(relresp);expect_identical(rel$M1_B_version,'m1-b-v3-peak-v10');expect_identical(rel$M2_B_version,'m2-b-v3-shadow-v5');expect_false(grepl(repo,relresp$body,fixed=TRUE))
  bad<-sprintf('{"season":"2026-27","season":"2026-27","expected_release_id":"%s"}',.PAGE_FORECAST_RELEASE_ID)
  expect_identical(.page_api_handle(ctx,'POST','/v1/weekly-runs',h,bad)$status,400L)
  body<-sprintf('{"season":"2026-27","expected_release_id":"%s"}',.PAGE_FORECAST_RELEASE_ID)
  r1<-.page_api_handle(ctx,'POST','/v1/weekly-runs',h,body);expect_identical(r1$status,202L);b1<-parse_body(r1);expect_match(b1$run_id,.PAGE_RUN_ID_RE)
  r2<-.page_api_handle(ctx,'POST','/v1/weekly-runs',h,body);expect_identical(r2$status,202L);expect_identical(parse_body(r2)$run_id,b1$run_id)
  h2<-h;h2[['idempotency-key']]<-'cycle-2';expect_identical(.page_api_handle(ctx,'POST','/v1/weekly-runs',h2,body)$status,409L)
  st<-.page_api_handle(ctx,'GET',paste0('/v1/weekly-runs/',b1$run_id),h);expect_identical(st$status,200L);expect_identical(parse_body(st)$status,'running')
  expect_identical(.page_api_handle(ctx,'GET',paste0('/v1/weekly-runs/',b1$run_id,'/result'),h)$status,409L)
})

test_that('succeeded result/provenance endpoints serve only immutable projections',{
  td<-tempfile();dir.create(td);x<-make_http_ctx(td);ctx<-x$ctx;cfg<-x$cfg;tok<-x$tok;run_id<-.api_new_run_id();jd<-.api_job_dir(cfg,run_id);dir.create(jd)
  .api_atomic_write_json(list(run_id=run_id,season='2026-27',expected_release_id=.PAGE_FORECAST_RELEASE_ID,created_utc=.api_now()),.api_request_path(cfg,run_id),TRUE)
  .api_write_state(cfg,run_id,list(state='succeeded',finished_utc=.api_now()))
  .api_atomic_write_json(list(run_id=run_id,season='2026-27',origin_weekF=12L,release_id=.PAGE_FORECAST_RELEASE_ID,effective_panel_sha256=paste(rep('c',64),collapse=''),forecasts=lapply(1:4,function(i)list(type=if(i<=2)'A' else 'B',horizon=if(i%%2)1L else 2L,v2_pct=i,v3_pct=i+.1,delta_pp=.1,v3_route=c('exact_A1_state','exact_A1_state','exact_B1_state','posterior_C2')[[i]]))),file.path(jd,'result.json'),TRUE)
  .api_atomic_write_json(list(run_id=run_id,release_id=.PAGE_FORECAST_RELEASE_ID,source_mode='olis',raw_source_sha256=paste(rep('a',64),collapse='')),file.path(jd,'provenance.json'),TRUE)
  h<-list(authorization=paste('Bearer',tok))
  rr<-.page_api_handle(ctx,'GET',paste0('/v1/weekly-runs/',run_id,'/result'),h);expect_identical(rr$status,200L);expect_length(parse_body(rr)$forecasts,4L);expect_false(grepl('/private/|source_original',rr$body))
  rp<-.page_api_handle(ctx,'GET',paste0('/v1/weekly-runs/',run_id,'/provenance'),h);expect_identical(rp$status,200L);expect_false(grepl('/private/|source_original',rp$body))
  for (m in c('POST','PUT','DELETE')) {
    expect_identical(.page_api_handle(ctx,m,paste0('/v1/weekly-runs/',run_id),h)$status,405L)
    expect_identical(.page_api_handle(ctx,m,paste0('/v1/weekly-runs/',run_id,'/result'),h)$status,405L)
    expect_identical(.page_api_handle(ctx,m,paste0('/v1/weekly-runs/',run_id,'/provenance'),h)$status,405L)
  }
  expect_identical(.page_api_handle(ctx,'GET','/v1/weekly-runs/not-a-run',h)$status,404L)
})


test_that('httpuv adapter enforces readiness, media type, and body size without leaking diagnostics', {
  td<-tempfile();dir.create(td);x<-make_http_ctx(td);ctx<-x$ctx
  expect_identical(.page_api_handle(ctx,'GET','/readyz')$status,200L);expect_identical(parse_body(.page_api_handle(ctx,'GET','/readyz'))$ready,TRUE)
  ctx$ready<-FALSE;ctx$ready_checked<-Sys.time();r0<-.page_api_handle(ctx,'GET','/readyz');expect_identical(r0$status,503L);expect_identical(names(parse_body(r0)),'ready')
  app<-.page_api_httpuv_app(ctx);inp<-new.env(parent=emptyenv());inp$read<-function(n)charToRaw('{}')
  big<-list(REQUEST_METHOD='POST',PATH_INFO='/v1/weekly-runs',CONTENT_LENGTH='20000',CONTENT_TYPE='application/json',rook.input=inp);expect_identical(app$call(big)$status,413L)
  badct<-list(REQUEST_METHOD='POST',PATH_INFO='/v1/weekly-runs',CONTENT_LENGTH='2',CONTENT_TYPE='text/plain',rook.input=inp);expect_identical(app$call(badct)$status,415L)
  valid_unknown<-paste0('/v1/weekly-runs/wr_',paste(rep('0',32),collapse=''));h<-list(authorization=paste('Bearer',x$tok));expect_identical(.page_api_handle(ctx,'GET',valid_unknown,h)$status,404L)
})


test_that('weekly trigger derives idempotency from protected cycle file at execution time', {
  skip_if(Sys.which('jq')=='','jq unavailable')
  td<-tempfile('api-trigger-');dir.create(td);bin<-file.path(td,'bin');dir.create(bin);log<-file.path(td,'curl.log')
  fakecurl<-file.path(bin,'curl')
  writeLines(c('#!/bin/sh','printf "%s\\n" "$*" >> "$FAKE_CURL_LOG"','case "$*" in','  *"/v1/weekly-runs/wr_"*) printf "{\\"status\\":\\"succeeded\\"}\\n" ;;','  *) printf "{\\"run_id\\":\\"wr_00000000000000000000000000000000\\"}\\n" ;;','esac'),fakecurl);Sys.chmod(fakecurl,'0755')
  cycle<-file.path(td,'cycle');body<-file.path(td,'body.json');curlcfg<-file.path(td,'curl.cfg');writeLines('{}',body);writeLines('',curlcfg)
  env<-c(paste0('PATH=',bin,':',Sys.getenv('PATH')),paste0('FAKE_CURL_LOG=',log),'PAGE_API_URL=http://127.0.0.1:8088',paste0('PAGE_WEEKLY_CYCLE_ID_FILE=',cycle),paste0('PAGE_TRIGGER_CURL_CONFIG=',curlcfg),paste0('PAGE_TRIGGER_BODY=',body),'PAGE_TRIGGER_POLL_SECONDS=0','PAGE_TRIGGER_MAX_POLLS=2')
  writeLines('publication-A',cycle);Sys.chmod(cycle,'0600');r1<-system2('sh','deploy/systemd/page-weekly-trigger',env=env,stdout=TRUE,stderr=TRUE);expect_identical(attr(r1,'status') %||% 0L,0L)
  writeLines('publication-B',cycle);r2<-system2('sh','deploy/systemd/page-weekly-trigger',env=env,stdout=TRUE,stderr=TRUE);expect_identical(attr(r2,'status') %||% 0L,0L)
  z<-readLines(log,warn=FALSE);expect_true(any(grepl('Idempotency-Key: publication-A',z,fixed=TRUE)));expect_true(any(grepl('Idempotency-Key: publication-B',z,fixed=TRUE)))
  writeLines(c('bad','two-lines'),cycle);r3<-suppressWarnings(system2('sh','deploy/systemd/page-weekly-trigger',env=env,stdout=TRUE,stderr=TRUE));expect_true((attr(r3,'status') %||% 0L)!=0L)
  writeLines('publication-C',cycle);Sys.chmod(cycle,'0666');r4<-suppressWarnings(system2('sh','deploy/systemd/page-weekly-trigger',env=env,stdout=TRUE,stderr=TRUE));expect_true((attr(r4,'status') %||% 0L)!=0L)
})
