library(testthat)

find_repo_api <- function() {
  d <- normalizePath(getwd(),winslash='/',mustWork=TRUE)
  for(i in 0:6){ if(file.exists(file.path(d,'PAGe/DESCRIPTION'))) return(d); d<-dirname(d) }
  stop('repo root not found')
}
repo <- find_repo_api(); old <- setwd(repo); on.exit(setwd(old),add=TRUE)
source('scripts/v3_weekly_api_helpers_v4.R')
source('scripts/v3_weekly_api_deployment_helpers_v4.R')

make_cfg <- function(td) {
  mount <- file.path(td,'mount'); dir.create(mount); job<-file.path(mount,'jobs'); out<-file.path(mount,'out'); dir.create(job);dir.create(out)
  list(repo_root=repo,api_deployment_dir=file.path(td,'dep'),job_root=job,output_root=out,artifact_mount=mount,season='2026-27',source_mode='olis',forecast_release_id=.PAGE_FORECAST_RELEASE_ID,forecast_release_dir=file.path(repo,'artifacts/v3-shadow-release-v3',.PAGE_FORECAST_RELEASE_ID),rscript=Sys.which('Rscript'),max_runtime_seconds=300L,olis_fallback=NULL,transaction_schema=file.path(repo,'governance/v3_weekly_api_transaction_schema_v1.csv'))
}

test_that('strict trigger schema rejects duplicates and policy drift', {
  td<-tempfile();dir.create(td); cfg<-make_cfg(td)
  good <- sprintf('{"season":"2026-27","expected_release_id":"%s"}',.PAGE_FORECAST_RELEASE_ID)
  expect_identical(.api_validate_trigger_request(good,cfg)$season,'2026-27')
  expect_error(.api_validate_trigger_request('{"season":"2026-27","season":"2026-27","expected_release_id":"x"}',cfg),'Duplicate')
  expect_error(.api_validate_trigger_request(sprintf('{"season":"2025-26","expected_release_id":"%s"}',.PAGE_FORECAST_RELEASE_ID),cfg),'configured deployment season')
  expect_error(.api_validate_trigger_request('{"season":"2026-27","expected_release_id":"x"}',cfg),'Release assertion')
})

test_that('token validation is strict and constant-time comparator behaves', {
  td<-tempfile();dir.create(td); f<-file.path(td,'token'); tok<-paste(rep('a',64),collapse=''); writeLines(tok,f); Sys.chmod(f,'0600')
  expect_identical(.api_read_token_file(f),tok)
  expect_true(.api_validate_bearer(paste('Bearer',tok),tok)); expect_false(.api_validate_bearer(paste('Bearer',sub('a','b',tok)),tok))
  writeLines(paste0(tok,' '),f); expect_error(.api_read_token_file(f),'64-hex')
})

test_that('storage and stale admission lock recovery are fail-closed/testable', {
  td<-tempfile();dir.create(td); cfg<-make_cfg(td); expect_silent(.api_validate_storage(cfg,strict_mount=FALSE)); .api_init_store(cfg)
  lock<-.api_admission_lock(cfg);dir.create(lock)
  .api_atomic_write_json(list(service_instance_id='old',pid=99999999L,start_token='1',created_utc=.api_now()),file.path(lock,'owner.json'))
  expect_true(.api_acquire_admission(cfg,'new')); expect_true(length(list.dirs(file.path(cfg$job_root,'locks','quarantine'),recursive=FALSE))==1L); .api_release_admission(cfg,'new')
  dir.create(lock); expect_error(.api_acquire_admission(cfg,'new'),'no valid owner')
})

test_that('idempotency is evaluated before season busy and state writer is supervisor', {
  td<-tempfile();dir.create(td); cfg<-make_cfg(td); .api_init_store(cfg); req<-list(season='2026-27',expected_release_id=.PAGE_FORECAST_RELEASE_ID); inst<-'inst1'
  spawned <- function(id) list(pid=Sys.getpid(),start_token=.api_proc_start_token(),process=NULL)
  a<-.api_admit(cfg,req,'cycle-1',inst,spawned); expect_identical(a$status,'accepted'); expect_identical(.api_read_state(cfg,a$run_id)$state,'running')
  b<-.api_admit(cfg,req,'cycle-1',inst,spawned); expect_identical(b$status,'existing'); expect_identical(b$run_id,a$run_id)
  c<-.api_admit(cfg,req,'cycle-2',inst,spawned); expect_identical(c$status,'busy')
  bad<-list(season='2026-27',expected_release_id=paste(rep('0',64),collapse=''))
  # same idempotency key/different canonical request is conflict without allocating another run
  d<-.api_admit(cfg,bad,'cycle-1',inst,spawned); expect_identical(d$status,'conflict')
})

write_fake_tx <- function(cfg,run_id) {
  root<-file.path(cfg$output_root,'api-runs',run_id,cfg$season,'20260928T120000Z-weekF12-release-5472d08992b5');dir.create(root,recursive=TRUE)
  writeLines(c('COMPLETE',.PAGE_FORECAST_RELEASE_ID),file.path(root,'COMPLETED'))
  relsha<-.api_sha256_file(file.path(cfg$forecast_release_dir,'release_manifest.tsv'))
  vals<-c(run_utc='2026-09-27T12:00:00Z',season='2026-27',origin_weekF='12',status='COMPLETE',release_id=.PAGE_FORECAST_RELEASE_ID,release_manifest_sha256=relsha,source_mode='olis',source_original='/private/secret/source.RData',raw_source_archived='transaction:data_cache/source.RData',raw_source_sha256=paste(rep('a',64),collapse=''),supplied_typed_panel_sha256=paste(rep('b',64),collapse=''),effective_panel_sha256=paste(rep('c',64),collapse=''),v2_child_run='v2/2026-27/run-a',v3_child_run='v3/2026-27/run-b')
  write.table(data.frame(key=names(vals),value=unname(vals)),file.path(root,'source_transaction.tsv'),sep='\t',quote=FALSE,row.names=FALSE)
  cmp<-data.frame(season=rep('2026-27',4),origin_weekF=rep(12,4),type=c('A','A','B','B'),horizon=c(1,2,1,2),v2_forecast_pct=c(1,2,3,4),v3_forecast_pct=c(1.1,2.1,3.1,4.1),delta_v3_minus_v2_pp=rep(.1,4),v3_route=c('exact_A1_state','exact_A1_state','exact_B1_state','posterior_C2'),release_id=rep(.PAGE_FORECAST_RELEASE_ID,4),effective_panel_sha256=rep(paste(rep('c',64),collapse=''),4),stringsAsFactors=FALSE)
  write.csv(cmp,file.path(root,'v2_v3_comparison.csv'),row.names=FALSE)
  child <- file.path(root,'v3','2026-27','run-b'); dir.create(child,recursive=TRUE)
  sig_cols <- c('season','weekF','y','N','p','cum_y','cum_N','prev','p0','p_sumK','raw_p_prev','raw_N_prev','raw_dp','raw_diff_se','raw_drop_z','raw_step_stable','cond_raw_nondec','cond_raw_stable','p_sm','dp','inc','cond_inc','cond_win','cond_cls','cond_sum','cond_p','cond_prev','n_hit','ignite_ok','iWeek_hat','detection_failed','ignite_flag','iWeek_hatF')
  sig <- as.data.frame(setNames(replicate(length(sig_cols), rep(NA,12), simplify=FALSE),sig_cols),stringsAsFactors=FALSE)
  sig$season <- rep('2026-27',12); sig$weekF <- 1:12; sig$y <- 1:12; sig$N <- rep(1000,12); sig$p <- sig$y/sig$N
  sig$iWeek_hat <- rep(12L,12); sig$detection_failed <- rep(FALSE,12); sig$ignite_flag <- c(rep(FALSE,11),TRUE); sig$iWeek_hatF <- rep(12,12)
  write.csv(sig,file.path(child,'m0_a_signals.csv'),row.names=FALSE)
  detection <- data.frame(season='2026-27',iWeek_hat=12L,detection_failed=FALSE,iWeek_hatF=12,iWeek_bracket='c(10, 12)',iWeek_bracket_lo=10L,iWeek_bracket_hi=12L,iWeek_fraction_method='fixture',stringsAsFactors=FALSE)
  write.csv(detection,file.path(child,'m0_a_detection.csv'),row.names=FALSE)
  m1 <- data.frame(season='2026-27',origin_week=12L,asof_boundary=13L,state='active',weeks_elapsed_since_activation=1L,weeks_to_calibrated_peak=6.4,raw_peak_mean=20,calibrated_peak_mean=20,calibrated_mean_is_future=TRUE,raw_peak_q05=18,raw_peak_q95=22,calibrated_peak_q05=18,calibrated_peak_q95=22,peak_q05=18,peak_q95=22,interval_width_90=4,prob_peak_passed=.01,prob_peak_within_1w=.02,prob_peak_within_2w=.03,prob_peak_within_3w=.04,passage_peak_mean_raw=20,passage_peak_mean_calibrated=20,peak_passed=FALSE,locked_peak_week=NA_real_,locked_at_origin=NA,error=NA,stringsAsFactors=FALSE)
  write.csv(m1,file.path(child,'m1_a_timing.csv'),row.names=FALSE)
  pred <- data.frame(season=rep('2026-27',4),origin_weekF=rep(12L,4),type=c('A','A','B','B'),horizon=c(1L,2L,1L,2L),forecast=c(.011,.021,.031,.041),forecast_pct=cmp$v3_forecast_pct,state_baseline=c(.011,.021,.031,.041),state_baseline_pct=cmp$v3_forecast_pct,route=cmp$v3_route,timing_available=c(FALSE,FALSE,FALSE,TRUE),timing_reason=c('policy_A_state_only','policy_A_state_only','plus1_state_only','posterior_available'),activity_week=c(NA,NA,NA,12),prob_peak_passed=c(NA,NA,NA,.2),posterior_mean_peak=c(NA,NA,NA,25),supported_mass=c(0,0,0,1),lower_bound_mass=c(0,0,0,0),lower_bound_saturated=c(FALSE,FALSE,FALSE,FALSE),model_version=c('A','A','B','B'),artifact_id=c('a','a','b','b'),production_eligible=FALSE,stringsAsFactors=FALSE)
  write.csv(pred,file.path(child,'combined_predictions.csv'),row.names=FALSE)
  prov <- c(season='2026-27',origin_weekF='12',effective_panel_sha256=paste(rep('c',64),collapse=''),release_id=.PAGE_FORECAST_RELEASE_ID,production_eligible='FALSE')
  write.table(data.frame(key=names(prov),value=unname(prov)),file.path(child,'provenance.tsv'),sep='\t',quote=FALSE,row.names=FALSE)
  st <- c(season='2026-27',origin_weekF='12',in_validated_window='TRUE',production_eligible='FALSE')
  write.table(data.frame(key=names(st),value=unname(st)),file.path(child,'status.tsv'),sep='\t',quote=FALSE,row.names=FALSE)
  root
}

test_that('transaction projection is exact, disclosure-safe, and recovery materializes projections', {
  td<-tempfile();dir.create(td); cfg<-make_cfg(td); .api_init_store(cfg); run_id<-.api_new_run_id(); dir.create(.api_job_dir(cfg,run_id));
  req<-list(run_id=run_id,api_contract_version=.PAGE_API_CONTRACT,season='2026-27',expected_release_id=.PAGE_FORECAST_RELEASE_ID,created_utc=.api_now(),service_instance_id='old'); .api_atomic_write_json(req,.api_request_path(cfg,run_id),TRUE); .api_write_state(cfg,run_id,list(state='running',service_instance_id='old'))
  write_fake_tx(cfg,run_id); x<-.api_validate_and_project_transaction(cfg,run_id,TRUE)
  expect_length(x$result$forecasts,4); expect_false('source_original'%in%names(x$provenance)); expect_false(any(grepl('/private/',unlist(x$provenance),fixed=TRUE)))
  unlink(file.path(.api_job_dir(cfg,run_id),c('transaction_ref.json','result.json','provenance.json')))
  .api_reconcile_job(cfg,run_id,'new',new.env(parent=emptyenv())); expect_identical(.api_read_state(cfg,run_id)$state,'succeeded')
  expect_true(all(file.exists(file.path(.api_job_dir(cfg,run_id),c('transaction_ref.json','result.json','provenance.json')))))
})


test_that('corrupt idempotency stays blocked while safe missing reservation can be rebuilt', {
  td<-tempfile();dir.create(td); cfg<-make_cfg(td); .api_init_store(cfg)
  kh<-paste(rep('a',64),collapse=''); ip<-.api_idem_path(cfg,kh); writeLines('{broken',ip)
  expect_error(.api_read_idempotency_strict(cfg,ip),'quarantined'); expect_false(file.exists(ip))
  expect_true(file.exists(.api_idem_block_path(cfg,kh)))
  rid<-.api_new_run_id(); jd<-.api_job_dir(cfg,rid);dir.create(jd)
  rd<-paste(rep('b',64),collapse=''); .api_atomic_write_json(list(run_id=rid,season='2026-27',expected_release_id=.PAGE_FORECAST_RELEASE_ID,created_utc=.api_now(),key_hash=kh,request_digest=rd,service_instance_id='old'),.api_request_path(cfg,rid),TRUE)
  .api_write_state(cfg,rid,list(state='accepted_pending',service_instance_id='old'))
  .api_reconcile_job(cfg,rid,'new',new.env(parent=emptyenv()))
  st<-.api_read_state(cfg,rid); expect_identical(st$state,'failed'); expect_identical(st$failure_code,'idempotency_blocked'); expect_false(file.exists(.api_idem_path(cfg,kh)))

  kh2<-paste(rep('c',64),collapse=''); rid2<-.api_new_run_id(); dir.create(.api_job_dir(cfg,rid2)); rd2<-.api_request_digest(list(season='2026-27',expected_release_id=.PAGE_FORECAST_RELEASE_ID),cfg$source_mode)
  .api_atomic_write_json(list(run_id=rid2,api_contract_version=.PAGE_API_CONTRACT,season='2026-27',expected_release_id=.PAGE_FORECAST_RELEASE_ID,source_mode=cfg$source_mode,created_utc=.api_now(),key_hash=kh2,request_digest=rd2,service_instance_id='old'),.api_request_path(cfg,rid2),TRUE)
  .api_write_state(cfg,rid2,list(state='accepted_pending',service_instance_id='old'))
  .api_reconcile_job(cfg,rid2,'new',new.env(parent=emptyenv()))
  expect_identical(.api_read_state(cfg,rid2)$failure_code,'admission_interrupted'); expect_true(file.exists(.api_idem_path(cfg,kh2)))
  rr<-.api_read_idempotency_strict(cfg,.api_idem_path(cfg,kh2)); expect_identical(rr$run_id,rid2)
})

test_that('API runtime environment manifest matches isolated sanitized service and worker namespace closures', {
  skip_if_not_installed('processx')
  envm<-read.delim('governance/v3_weekly_api_environment_v1.tsv',sep='\t',stringsAsFactors=FALSE,check.names=FALSE)
  env<-c(R_LIBS_USER='/nonexistent/page-api-user-library',R_LIBS_SITE='/usr/local/lib/R/site-library:/usr/lib/R/site-library',R_PROFILE_USER='/dev/null',R_ENVIRON_USER='/dev/null',TZ='UTC',LANG='C.UTF-8',LC_ALL='C.UTF-8')
  inventory <- function(pkgs){
    expr<-sprintf("invisible(lapply(c(%s),requireNamespace,quietly=TRUE)); ip<-installed.packages(); ns<-sort(loadedNamespaces()); z<-ns[vapply(ns,function(p){pr<-ip[p,'Priority'];is.na(pr)||!nzchar(pr)},logical(1))]; cat(paste(z,collapse=','))",paste(sprintf("'%s'",pkgs),collapse=','))
    r<-processx::run(Sys.which('Rscript'),c('--vanilla','-e',expr),env=env,error_on_status=TRUE); if(!nzchar(r$stdout)) character() else strsplit(trimws(r$stdout),',',fixed=TRUE)[[1]]
  }
  expect_setequal(inventory(c('httpuv','jsonlite','processx','digest')),envm$component[grepl('service',envm$role,fixed=TRUE) & envm$component!='R'])
  expect_setequal(inventory(c('jsonlite','processx','digest')),envm$component[grepl('worker',envm$role,fixed=TRUE) & envm$component!='R'])
})


test_that('spawn failure is durable, releases season lock, and retains idempotency reservation', {
  td<-tempfile();dir.create(td);cfg<-make_cfg(td);.api_init_store(cfg);req<-list(season='2026-27',expected_release_id=.PAGE_FORECAST_RELEASE_ID)
  a<-.api_admit(cfg,req,'spawn-failure-cycle','inst',function(id)stop('injected spawn failure'))
  expect_identical(a$status,'failed');expect_identical(.api_read_state(cfg,a$run_id)$state,'failed');expect_false(dir.exists(.api_season_lock(cfg)))
  ip<-.api_idem_path(cfg,.api_idem_hash('spawn-failure-cycle'));expect_true(file.exists(ip));expect_identical(.api_read_idempotency_strict(cfg,ip)$run_id,a$run_id)
})

test_that('failed worker receipt reconciles to safe failure and releases lock', {
  td<-tempfile();dir.create(td);cfg<-make_cfg(td);.api_init_store(cfg);req<-list(season='2026-27',expected_release_id=.PAGE_FORECAST_RELEASE_ID)
  a<-.api_admit(cfg,req,'worker-failure-cycle','inst',function(id)list(pid=Sys.getpid(),start_token=.api_proc_start_token(),process=NULL));rid<-a$run_id
  .api_atomic_write_json(list(status='failed',exit_code=9L,failure_code='forecast_transaction_failed',failure_message='SHOULD_NOT_BE_TRUSTED'),.api_worker_result_path(cfg,rid),TRUE)
  z<-.api_reconcile_job(cfg,rid,'inst',new.env(parent=emptyenv()));expect_identical(z$status,'failed');expect_identical(z$failure_code,'forecast_transaction_failed');expect_identical(z$failure_message,.PAGE_SAFE_FAILURES[['forecast_transaction_failed']]);expect_false(dir.exists(.api_season_lock(cfg)))
})


.test_write_request <- function(cfg,run_id,key_hash,instance='old',request_digest=NULL) {
  req0 <- list(season=cfg$season,expected_release_id=cfg$forecast_release_id)
  rd <- request_digest %||% .api_request_digest(req0,cfg$source_mode)
  req <- list(run_id=run_id,api_contract_version=.PAGE_API_CONTRACT,season=cfg$season,expected_release_id=cfg$forecast_release_id,source_mode=cfg$source_mode,key_hash=key_hash,request_digest=rd,created_utc=.api_now(),service_instance_id=instance)
  .api_atomic_write_json(req,.api_request_path(cfg,run_id),TRUE)
  invisible(req)
}

.test_write_idem <- function(cfg,key_hash,run_id,request_digest) {
  .api_atomic_write_json(list(key_hash=key_hash,request_digest=request_digest,run_id=run_id),.api_idem_path(cfg,key_hash),TRUE)
}

test_that('idempotency reservation is cryptographically tied to its filename and full immutable request lineage', {
  td<-tempfile();dir.create(td);cfg<-make_cfg(td);.api_init_store(cfg)
  kh<-paste(rep('a',64),collapse=''); other<-paste(rep('b',64),collapse=''); rd<-paste(rep('c',64),collapse=''); rid<-.api_new_run_id()
  .api_atomic_write_json(list(key_hash=other,request_digest=rd,run_id=rid),.api_idem_path(cfg,kh),TRUE)
  expect_error(.api_read_idempotency_strict(cfg,.api_idem_path(cfg,kh)),'quarantined')
  expect_true(.api_blocked_idempotency(cfg,kh)); expect_false(file.exists(.api_idem_path(cfg,kh)))

  kh2<-paste(rep('d',64),collapse=''); rid2<-.api_new_run_id();dir.create(.api_job_dir(cfg,rid2))
  bad_rd<-paste(rep('e',64),collapse=''); .test_write_request(cfg,rid2,kh2,request_digest=bad_rd);.api_write_state(cfg,rid2,list(state='accepted_pending',service_instance_id='old'))
  z<-.api_reconcile_job(cfg,rid2,'new',new.env(parent=emptyenv())); expect_identical(z$status,'failed');expect_identical(z$failure_code,'idempotency_blocked');expect_false(file.exists(.api_idem_path(cfg,kh2)));expect_true(.api_blocked_idempotency(cfg,kh2))
})

test_that('admission lock recovery refuses live or unverifiable owners and only recovers provably stale ownership', {
  td<-tempfile();dir.create(td);cfg<-make_cfg(td);.api_init_store(cfg);lock<-.api_admission_lock(cfg)
  dir.create(lock);.api_atomic_write_json(list(service_instance_id='other',pid=Sys.getpid(),start_token=.api_proc_start_token(),created_utc=.api_now()),file.path(lock,'owner.json'))
  expect_error(.api_acquire_admission(cfg,'new'),'live prior process');expect_true(dir.exists(lock));unlink(lock,recursive=TRUE)
  dir.create(lock);.api_atomic_write_json(list(service_instance_id='other',pid=Sys.getpid(),start_token='not-a-token',created_utc=.api_now()),file.path(lock,'owner.json'))
  expect_error(.api_acquire_admission(cfg,'new'),'cannot be verified');expect_true(dir.exists(lock));unlink(lock,recursive=TRUE)
  dir.create(lock);.api_atomic_write_json(list(service_instance_id='other',pid=99999999L,start_token='1',created_utc=.api_now()),file.path(lock,'owner.json'))
  expect_true(.api_acquire_admission(cfg,'new'));.api_release_admission(cfg,'new');expect_true(length(list.dirs(file.path(cfg$job_root,'locks','quarantine'),recursive=FALSE))>=1L)
})

test_that('every interrupted admission boundary resolves without duplicate allocation', {
  make_case <- function(boundary) {
    td<-tempfile();dir.create(td);cfg<-make_cfg(td);.api_init_store(cfg);rid<-.api_new_run_id();dir.create(.api_job_dir(cfg,rid));kh<-.api_idem_hash(paste0('cycle-',boundary));rd<-.api_request_digest(list(season=cfg$season,expected_release_id=cfg$forecast_release_id),cfg$source_mode)
    .test_write_request(cfg,rid,kh,'old',rd);.api_write_state(cfg,rid,list(state='accepted_pending',service_instance_id='old'))
    if (boundary %in% c('after_season_lock','after_idempotency','starting')) expect_true(.api_create_season_lock(cfg,rid,'old'))
    if (boundary %in% c('after_idempotency','starting')) .test_write_idem(cfg,kh,rid,rd)
    if (boundary=='starting') .api_write_state(cfg,rid,list(state='starting',service_instance_id='old',started_utc=.api_now()))
    list(cfg=cfg,rid=rid,kh=kh)
  }
  for (b in c('after_request','after_season_lock','after_idempotency')) {
    x<-make_case(b);z<-.api_reconcile_job(x$cfg,x$rid,'new',new.env(parent=emptyenv()));expect_identical(z$status,'failed',info=b);expect_identical(z$failure_code,'admission_interrupted',info=b);expect_true(file.exists(.api_idem_path(x$cfg,x$kh)),info=b);expect_false(dir.exists(.api_season_lock(x$cfg)),info=b)
  }
  x<-make_case('starting');z<-.api_reconcile_job(x$cfg,x$rid,'new',new.env(parent=emptyenv()));expect_identical(z$status,'failed');expect_identical(z$failure_code,'worker_lost');expect_true(file.exists(.api_idem_path(x$cfg,x$kh)));expect_false(dir.exists(.api_season_lock(x$cfg)))
})

test_that('malformed partial job is quarantined without preventing reconciliation of valid jobs', {
  td<-tempfile();dir.create(td);cfg<-make_cfg(td);.api_init_store(cfg)
  bad<-.api_new_run_id();dir.create(.api_job_dir(cfg,bad))
  good<-.api_new_run_id();dir.create(.api_job_dir(cfg,good));kh<-.api_idem_hash('good-cycle');.test_write_request(cfg,good,kh,'old');.api_write_state(cfg,good,list(state='failed',failure_code='internal_error',failure_message=.PAGE_SAFE_FAILURES[['internal_error']]))
  expect_silent(.api_reconcile_all(cfg,'new',new.env(parent=emptyenv())))
  expect_false(dir.exists(.api_job_dir(cfg,bad)));q<-list.dirs(file.path(cfg$job_root,'jobs','quarantine'),recursive=FALSE,full.names=FALSE);expect_true(any(startsWith(q,paste0(bad,'-reconcile-invalid-'))));expect_true(dir.exists(.api_job_dir(cfg,good)))
})

.test_mutate_tx_kv <- function(tx,key,value) {
  f<-file.path(tx,'source_transaction.tsv');x<-read.delim(f,sep='\t',stringsAsFactors=FALSE,check.names=FALSE);x$value[x$key==key]<-value;write.table(x,f,sep='\t',quote=FALSE,row.names=FALSE)
}

test_that('authoritative transaction validator rejects malformed marker receipt and comparison types', {
  run_case <- function(mutator,pattern) {
    td<-tempfile();dir.create(td);cfg<-make_cfg(td);rid<-.api_new_run_id();tx<-write_fake_tx(cfg,rid);mutator(tx);expect_error(.api_validate_and_project_transaction(cfg,rid,FALSE),pattern)
  }
  run_case(function(tx){con<-file(file.path(tx,'COMPLETED'),'wb');writeBin(charToRaw(paste0('COMPLETE\r\n',.PAGE_FORECAST_RELEASE_ID,'\r\n')),con);close(con)},'COMPLETED marker bytes')
  run_case(function(tx){con<-file(file.path(tx,'COMPLETED'),'wb');writeBin(charToRaw(paste0('COMPLETE\n',.PAGE_FORECAST_RELEASE_ID)),con);close(con)},'COMPLETED marker bytes')
  run_case(function(tx).test_mutate_tx_kv(tx,'run_utc','not-a-time'),'run_utc')
  run_case(function(tx).test_mutate_tx_kv(tx,'source_original',''),'source_original')
  run_case(function(tx).test_mutate_tx_kv(tx,'origin_weekF','0'),'origin_weekF')
  run_case(function(tx){f<-file.path(tx,'v2_v3_comparison.csv');x<-read.csv(f,stringsAsFactors=FALSE);x$horizon<-as.numeric(x$horizon);x$horizon[[1]]<-1.5;write.csv(x,f,row.names=FALSE)},'column type|key-set')
  run_case(function(tx){f<-file.path(tx,'v2_v3_comparison.csv');x<-read.csv(f,stringsAsFactors=FALSE);x$delta_v3_minus_v2_pp[[1]]<-99;write.csv(x,f,row.names=FALSE)},'delta is inconsistent')
})

test_that('malformed authoritative transaction can never be recovered as succeeded', {
  td<-tempfile();dir.create(td);cfg<-make_cfg(td);.api_init_store(cfg);rid<-.api_new_run_id();dir.create(.api_job_dir(cfg,rid));kh<-.api_idem_hash('malformed-tx');.test_write_request(cfg,rid,kh,'old');.api_write_state(cfg,rid,list(state='running',service_instance_id='old',started_utc=.api_now()));tx<-write_fake_tx(cfg,rid);.test_mutate_tx_kv(tx,'run_utc','bad');.api_atomic_write_json(list(status='succeeded',exit_code=0L),.api_worker_result_path(cfg,rid),TRUE)
  z<-.api_reconcile_job(cfg,rid,'new',new.env(parent=emptyenv()));expect_identical(z$status,'failed');expect_identical(z$failure_code,'transaction_validation_failed');expect_false(file.exists(file.path(.api_job_dir(cfg,rid),'result.json')));expect_false(file.exists(file.path(.api_job_dir(cfg,rid),'provenance.json')))
})


test_that('invalid run-ID directory names are quarantined without aborting global reconciliation', {
  td<-tempfile();dir.create(td);cfg<-make_cfg(td);.api_init_store(cfg)
  bad_name<-'not-a-valid-run-id';bad_dir<-file.path(cfg$job_root,'jobs',bad_name);dir.create(bad_dir)
  good<-.api_new_run_id();dir.create(.api_job_dir(cfg,good));kh<-.api_idem_hash('valid-neighbor');.test_write_request(cfg,good,kh,'old');.api_write_state(cfg,good,list(state='failed',failure_code='internal_error',failure_message=.PAGE_SAFE_FAILURES[['internal_error']]))
  expect_silent(.api_reconcile_all(cfg,'new',new.env(parent=emptyenv())))
  expect_false(dir.exists(bad_dir));q<-list.dirs(file.path(cfg$job_root,'jobs','quarantine'),recursive=FALSE,full.names=FALSE);expect_true(any(grepl('^invalid-[0-9a-f]{16}-reconcile-invalid-',q)));expect_true(dir.exists(.api_job_dir(cfg,good)))
})
