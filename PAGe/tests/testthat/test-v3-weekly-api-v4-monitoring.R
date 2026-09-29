library(testthat)

find_repo_v4_monitoring <- function() {
  d <- normalizePath(getwd(), winslash='/', mustWork=TRUE)
  for (i in 0:6) {
    if (file.exists(file.path(d,'PAGe','DESCRIPTION'))) return(d)
    d <- dirname(d)
  }
  stop('repo root not found')
}

repo <- find_repo_v4_monitoring(); old <- setwd(repo); on.exit(setwd(old), add=TRUE)
source('scripts/v3_weekly_api_helpers_v4.R')

.fixture_tx <- function() {
  hits <- Sys.glob('artifacts/v3-end-to-end-audit-2026-09-28-v2/synthetic-weekF12/mount/out/api-runs/*/2026-27/*')
  hits <- hits[dir.exists(hits) & !endsWith(hits,'/failures') & !endsWith(hits,'/.pending')]
  if (!length(hits)) skip('retained weekF12 transaction unavailable')
  hits[[1]]
}

.copy_case <- function() {
  tx <- .fixture_tx()
  td <- tempfile('api-v4-monitoring-'); dir.create(td)
  out <- file.path(td,'out'); jobs <- file.path(td,'jobs'); dir.create(out); dir.create(jobs)
  run_id <- 'wr_687d36b8a98642be187856d652bc4ce0'
  dest_parent <- file.path(out,'api-runs',run_id,'2026-27'); dir.create(dest_parent,recursive=TRUE)
  dest <- file.path(dest_parent,basename(tx))
  cp <- system2('cp',c('-a',tx,dest_parent),stdout=TRUE,stderr=TRUE)
  expect_true(dir.exists(dest))
  cfg <- list(
    output_root=out,job_root=jobs,season='2026-27',
    forecast_release_id=.PAGE_FORECAST_RELEASE_ID,
    forecast_release_dir=file.path(repo,'artifacts','v3-shadow-release-v3',.PAGE_FORECAST_RELEASE_ID),
    transaction_schema=file.path(repo,'governance','v3_weekly_api_transaction_schema_v1.csv')
  )
  list(td=td,out=out,jobs=jobs,run_id=run_id,tx=dest,cfg=cfg)
}

.child_dir <- function(case) {
  r <- read.delim(file.path(case$tx,'source_transaction.tsv'),sep='\t',stringsAsFactors=FALSE,check.names=FALSE)
  kv <- setNames(r$value,r$key)
  file.path(case$tx,kv[['v3_child_run']])
}


test_that('v4 HTTP adapter launches only v4 worker and preflight scripts', {
  source('2026/page_weekly_api_v4.R',local=environment())
  expect_match(paste(deparse(body(.page_api_spawn_worker)),collapse=' '),'run_page_weekly_api_worker_v4.R',fixed=TRUE)
  expect_match(paste(deparse(body(.page_api_preflight_args)),collapse=' '),'run_page_weekly_api_preflight_v4.R',fixed=TRUE)
})

test_that('v4 monitoring projection exactly reflects governed weekF12 child artifacts', {
  c <- .copy_case()
  p <- .api_validate_and_project_transaction(c$cfg,c$run_id,persist=FALSE)
  m <- p$result$monitoring
  expect_true(m$A$m0$ignited)
  expect_equal(m$A$m0$ignition_weekF,12)
  expect_equal(m$A$m0$ignition_week,12L)
  expect_equal(m$A$m0$eligible_from_weekF,12L)
  expect_true(m$A$m1$available)
  expect_identical(m$A$m1$state,'active')
  expect_equal(m$A$m1$peak_mean_weekF,19.4070212513883,tolerance=1e-12)
  expect_equal(m$A$m1$peak_q05_weekF,16.4827983132156,tolerance=1e-12)
  expect_equal(m$A$m1$peak_q95_weekF,22.1827983132156,tolerance=1e-12)
  expect_equal(m$A$m1$prob_peak_passed,5.82793562418698e-06,tolerance=1e-15)
  expect_equal(m$A$m1$prob_peak_within_1w,6.77329931948804e-11,tolerance=1e-18)
  expect_equal(m$A$m1$prob_peak_within_2w,2.57634801312247e-05,tolerance=1e-15)
  expect_equal(m$A$m1$prob_peak_within_3w,0.00367389046442521,tolerance=1e-15)
  expect_false(m$B$m1$available)
  expect_identical(m$B$m1$timing_reason,'not_detected')
  expect_null(m$B$m1$activity_weekF)
  expect_null(m$B$m1$peak_mean_weekF)
  expect_null(m$B$m1$prob_peak_passed)
  expect_length(p$result$forecasts,4L)
  expect_identical(p$provenance$api_contract_version,'page-weekly-api-v4')
  expect_setequal(names(p$provenance$monitoring_file_sha256),c('m0_detection','signals','m1a','combined','provenance','status'))
})

test_that('v4 monitoring fails closed on tampered M0 signals', {
  c <- .copy_case(); child <- .child_dir(c)
  s <- read.csv(file.path(child,'m0_a_signals.csv'),stringsAsFactors=FALSE,check.names=FALSE)
  s$iWeek_hatF[nrow(s)] <- 99
  write.csv(s,file.path(child,'m0_a_signals.csv'),row.names=FALSE)
  expect_error(.api_validate_and_project_transaction(c$cfg,c$run_id,persist=FALSE),'M0 detection state inconsistent|M0 signals identity mismatch|Monitoring')
})

test_that('v4 monitoring fails closed on tampered M1 probabilities', {
  c <- .copy_case(); child <- .child_dir(c)
  x <- read.csv(file.path(child,'m1_a_timing.csv'),stringsAsFactors=FALSE,check.names=FALSE)
  x$prob_peak_passed <- 1.5
  write.csv(x,file.path(child,'m1_a_timing.csv'),row.names=FALSE)
  expect_error(.api_validate_and_project_transaction(c$cfg,c$run_id,persist=FALSE),'outside')
})

test_that('v4 monitoring rejects dangling optional M1-A symlink before ignition', {
  c <- .copy_case(); child <- .child_dir(c)
  m1p <- file.path(child,'m1_a_timing.csv'); if (file.exists(m1p)) unlink(m1p)
  file.symlink(file.path(child,'does-not-exist.csv'),m1p)
  expect_error(.api_validate_and_project_transaction(c$cfg,c$run_id,persist=FALSE),'regular non-symlink')
})

test_that('v4 monitoring fails closed on child/parent forecast drift', {
  c <- .copy_case(); child <- .child_dir(c)
  x <- read.csv(file.path(child,'combined_predictions.csv'),stringsAsFactors=FALSE,check.names=FALSE)
  x$forecast_pct[x$type=='A' & x$horizon==1] <- x$forecast_pct[x$type=='A' & x$horizon==1] + 0.5
  write.csv(x,file.path(child,'combined_predictions.csv'),row.names=FALSE)
  expect_error(.api_validate_and_project_transaction(c$cfg,c$run_id,persist=FALSE),'Child/parent mismatch')
})


test_that('v4 monitoring fails closed on malformed B timing_available type', {
  c <- .copy_case(); child <- .child_dir(c)
  x <- read.csv(file.path(child,'combined_predictions.csv'),stringsAsFactors=FALSE,check.names=FALSE)
  x$timing_available <- ifelse(x$timing_available,'TRUE','FALSE')
  x$timing_available[x$type=='B' & x$horizon==2] <- 'BOGUS'
  write.csv(x,file.path(child,'combined_predictions.csv'),row.names=FALSE)
  expect_error(.api_validate_and_project_transaction(c$cfg,c$run_id,persist=FALSE),'column type mismatch')
})
