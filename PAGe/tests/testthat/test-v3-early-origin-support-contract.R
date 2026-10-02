find_page_repo_root_early_v3 <- function() {
  candidates <- c('.', '..', '../..', '../../..')
  hit <- candidates[file.exists(file.path(candidates,'2026','run_weekly_shadow_v3_early_v1.R'))]
  if (!length(hit)) return(NA_character_)
  normalizePath(hit[[1]],winslash='/',mustWork=TRUE)
}

.early_v3_fixture <- function(repo, origin) {
  old <- setwd(repo); on.exit(setwd(old),add=TRUE)
  x <- read.csv('artifacts/v3-joint-ab-audit-v1/canonical_ab_weekly_v3.csv',check.names=FALSE)
  z <- x[x$season=='2025-26' & x$weekF<=origin,
         c('season','weekF','y_A','N_A','p_A','y_B','N_B','p_B','denominator_regime')]
  z$season <- '2026-27'
  z$denominator_regime <- 'orvt_type_specific'
  path <- tempfile(fileext='.csv')
  write.csv(z,path,row.names=FALSE)
  path
}

.early_v3_env <- function(repo) {
  old <- setwd(repo); on.exit(setwd(old),add=TRUE)
  env <- new.env(parent=globalenv())
  sys.source('2026/run_weekly_shadow_v3_early_v1.R',envir=env)
  env
}

test_that('M2-B shadow-v4 changes only the early-origin support contract', {
  repo <- find_page_repo_root_early_v3(); skip_if(is.na(repo),'PAGe repo unavailable')
  old <- setwd(repo); on.exit(setwd(old),add=TRUE)
  source('scripts/v3_m2_b_runtime_helpers_v4.R',local=TRUE)
  v3 <- readRDS('artifacts/m2-b-v3-shadow-v3/m2_b_v3_shadow_artifact.rds')
  v4 <- readRDS('artifacts/m2-b-v3-shadow-v4/m2_b_v3_shadow_artifact.rds')
  expect_silent(validate_m2_b_v3_shadow_artifact(v4))
  expect_identical(v4$version,'m2-b-v3-shadow-v4')
  expect_identical(v4$runtime_contract$min_origin_week,1L)
  expect_identical(v4$runtime_contract$min_history_observations,3L)
  expect_identical(v4$runtime_contract$support_rule,'three_consecutive_weeks_through_origin')
  expect_identical(stats::coef(v4$state$model),stats::coef(v3$state$model))
  expect_identical(v4$shape$grid,v3$shape$grid)
  expect_identical(v4$activity$params,v3$activity$params)
})

test_that('weekF11 now issues finite A/B state forecasts without implying ignition', {
  repo <- find_page_repo_root_early_v3(); skip_if(is.na(repo),'PAGe repo unavailable')
  old <- setwd(repo); on.exit(setwd(old),add=TRUE)
  env <- .early_v3_env(repo)
  typed <- 'artifacts/v3-live-2026-27-week11-deployment-v1/input/typed_ab_weekly.csv'
  res <- env$.shadow_v3_main(c('--season=2026-27',paste0('--typed-panel=',typed),paste0('--output-root=',tempfile('early-v3-w11-'))))
  p <- res$predictions
  expect_true(res$status$in_validated_window)
  expect_true(all(is.finite(p$forecast)))
  expect_equal(p$forecast_pct[p$type=='A' & p$horizon==1L],1.67726744,tolerance=1e-7)
  expect_equal(p$forecast_pct[p$type=='A' & p$horizon==2L],1.66785435,tolerance=1e-7)
  b2 <- p[p$type=='B' & p$horizon==2L,]
  expect_false(b2$timing_available)
  expect_identical(b2$timing_reason,'not_detected')
  expect_identical(b2$route,'exact_B1_fallback')
  expect_equal(b2$forecast,b2$state_baseline,tolerance=0)
  expect_true(all(p$production_eligible==FALSE))
})

test_that('fewer than three consecutive observations emits explicit non-issuance', {
  repo <- find_page_repo_root_early_v3(); skip_if(is.na(repo),'PAGe repo unavailable')
  old <- setwd(repo); on.exit(setwd(old),add=TRUE)
  env <- .early_v3_env(repo)
  typed <- .early_v3_fixture(repo,2L)
  env$run_m2_v2_c2_governed_runtime <- function(...) stop('A model must not run without state support')
  env$m2_b_v3_shadow_forecast <- function(...) stop('B model must not run without state support')
  res <- env$.shadow_v3_main(c('--season=2026-27',paste0('--typed-panel=',typed),paste0('--output-root=',tempfile('early-v3-short-'))))
  expect_false(res$status$in_validated_window)
  expect_true(all(is.na(res$predictions$forecast)))
  expect_true(all(res$predictions$route=='not_issued'))
  expect_true(all(res$predictions$timing_reason=='insufficient_state_history'))
})

test_that('standalone B v4 matches combined B at weekF11', {
  repo <- find_page_repo_root_early_v3(); skip_if(is.na(repo),'PAGe repo unavailable')
  old <- setwd(repo); on.exit(setwd(old),add=TRUE)
  env <- .early_v3_env(repo)
  typed <- 'artifacts/v3-live-2026-27-week11-deployment-v1/input/typed_ab_weekly.csv'
  combined <- env$.shadow_v3_main(c('--season=2026-27',paste0('--typed-panel=',typed),paste0('--output-root=',tempfile('early-v3-c-'))))
  benv <- new.env(parent=globalenv()); sys.source('2026/run_weekly_m2_b_shadow_v4.R',envir=benv)
  b <- benv$.shadow_m2b_v3_main(c('--season=2026-27',paste0('--typed-panel=',typed),paste0('--output-root=',tempfile('early-v3-b-'))))
  cb <- combined$predictions[combined$predictions$type=='B',]
  cb <- cb[order(cb$horizon),]; bp <- b$predictions[order(b$predictions$horizon),]
  expect_equal(cb$forecast,bp$forecast,tolerance=0)
  expect_identical(as.character(cb$timing_reason),as.character(bp$timing_reason))
})

test_that('M2-B v4 direct runtime rejects a gap in the three-week support window', {
  repo <- find_page_repo_root_early_v3(); skip_if(is.na(repo),'PAGe repo unavailable')
  old <- setwd(repo); on.exit(setwd(old),add=TRUE)
  source('scripts/v3_m2_b_runtime_helpers_v4.R',local=TRUE)
  m2 <- readRDS('artifacts/m2-b-v3-shadow-v4/m2_b_v3_shadow_artifact.rds')
  m1 <- readRDS('artifacts/m1-b-v3-peak-v9/m1_b_v3_peak_artifact.rds')
  x <- read.csv('artifacts/v3-live-2026-27-week11-deployment-v1/input/typed_ab_weekly.csv',check.names=FALSE)
  b <- data.frame(season=x$season,weekF=x$weekF,y_B=x$y_B,N_B=x$N_B,p_B=x$p_B)
  b <- b[b$weekF!=10L,]
  expect_error(m2_b_v3_shadow_forecast(m2,m1,b,11L,1L),'three consecutive observations',fixed=TRUE)
})


test_that('relaxed combined runner is numerically identical to prior runner at supported late origins', {
  repo <- find_page_repo_root_early_v3(); skip_if(is.na(repo),'PAGe repo unavailable')
  oldwd <- setwd(repo); on.exit(setwd(oldwd),add=TRUE)
  typed <- .early_v3_fixture(repo,45L)
  old_env <- new.env(parent=globalenv()); sys.source('2026/run_weekly_shadow_v3.R',envir=old_env)
  source('scripts/v3_m2_b_runtime_helpers_v3.R',local=.GlobalEnv)
  old_res <- old_env$.shadow_v3_main(c('--season=2026-27',paste0('--typed-panel=',typed),paste0('--output-root=',tempfile('old-v3-late-'))))
  new_env <- .early_v3_env(repo)
  source('scripts/v3_m2_b_runtime_helpers_v4.R',local=.GlobalEnv)
  new_res <- new_env$.shadow_v3_main(c('--season=2026-27',paste0('--typed-panel=',typed),paste0('--output-root=',tempfile('new-v3-late-'))))
  cols <- c('type','horizon','forecast','state_baseline','route','timing_available','timing_reason','activity_week','prob_peak_passed','supported_mass','lower_bound_mass','lower_bound_saturated')
  a <- old_res$predictions[,cols,drop=FALSE]
  b <- new_res$predictions[,cols,drop=FALSE]
  expect_identical(a$type,b$type)
  expect_identical(a$horizon,b$horizon)
  for (nm in c('forecast','state_baseline','activity_week','prob_peak_passed','supported_mass','lower_bound_mass')) {
    expect_equal(a[[nm]],b[[nm]],tolerance=0)
  }
  expect_identical(a$route,b$route)
  expect_identical(a$timing_available,b$timing_available)
  expect_identical(a$timing_reason,b$timing_reason)
  expect_identical(a$lower_bound_saturated,b$lower_bound_saturated)
})
