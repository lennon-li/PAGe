find_page_repo_root_m2b_shadow_v2 <- function() {
  candidates <- c('.', '..', '../..', '../../..')
  hit <- candidates[file.exists(file.path(candidates,'scripts','v3_m2_b_runtime_helpers_v2.R'))]
  if (!length(hit)) return(NA_character_)
  normalizePath(hit[[1]],winslash='/',mustWork=TRUE)
}

load_m2b_shadow_test_context_v2 <- function(repo) {
  old <- setwd(repo); on.exit(setwd(old),add=TRUE)
  env <- new.env(parent=globalenv())
  sys.source('scripts/v3_m2_b_runtime_helpers_v2.R',envir=env)
  m1_loader <- get('load_m1_b_v3_artifact',envir=globalenv(),inherits=TRUE)
  list(
    env=env,
    artifact=env$load_m2_b_v3_shadow_artifact(),
    m1=m1_loader(),
    panel=read.csv('artifacts/v3-joint-ab-audit-v1/canonical_ab_weekly_v3.csv',check.names=FALSE))
}

prospective_copy <- function(panel, source_season, new_season='2026-27') {
  z <- panel[panel$season==source_season,c('weekF','y_B','N_B','p_B'),drop=FALSE]
  z$season <- new_season
  z[,c('season','weekF','y_B','N_B','p_B')]
}

test_that('M2-B v3 shadow artifact validates frozen season and runtime policy', {
  repo <- find_page_repo_root_m2b_shadow_v2()
  skip_if(is.na(repo),'PAGe repo unavailable')
  old_wd <- setwd(repo); on.exit(setwd(old_wd),add=TRUE)
  ctx <- load_m2b_shadow_test_context_v2(repo)
  a <- ctx$artifact

  expect_true(ctx$env$validate_m2_b_v3_shadow_artifact(a))
  expect_identical(a$version,'m2-b-v3-shadow-v2')
  expect_identical(a$status,'shadow_only_prospective_research')
  expect_identical(a$production_eligible,FALSE)
  expect_false('2019-20' %in% a$state$training_seasons)
  expect_true('2018-19' %in% a$state$training_seasons)
  expect_false(any(c('2018-19','2019-20') %in% a$shape$B_seasons))
  expect_true('2019-20' %in% a$shape$A_seasons)
  expect_identical(a$runtime_contract$plus1_route,'exact_B1')
  expect_identical(a$runtime_contract$plus2_route,'posterior_C2_if_timing_else_B1')
  expect_identical(a$runtime_contract$allow_hard_passage,FALSE)
  expect_identical(a$runtime_contract$allow_production,FALSE)
  expect_identical(a$runtime_contract$lower_bound_step,0.2)
  expect_identical(a$runtime_contract$lower_bound_saturation_threshold,0.9)
  expect_identical(a$historical_evidence$benchmark_version,'v3-m2-b-posterior-c2-chronological-v3')
  expect_identical(a$historical_evidence$plus2_historically_promising,TRUE)
  expect_identical(a$historical_evidence$plus1_route,'exact_B1')
  expect_identical(a$historical_evidence$lower_bound_monitoring_required,TRUE)
  expect_equal(a$historical_evidence$lower_bound_reset_active_gain,0.0833347459757469,tolerance=1e-15)
})

test_that('M2-B v3 validator rejects governance drift', {
  repo <- find_page_repo_root_m2b_shadow_v2()
  skip_if(is.na(repo),'PAGe repo unavailable')
  old_wd <- setwd(repo); on.exit(setwd(old_wd),add=TRUE)
  ctx <- load_m2b_shadow_test_context_v2(repo)
  validate <- ctx$env$validate_m2_b_v3_shadow_artifact
  a <- ctx$artifact

  bad <- a; bad$production_eligible <- TRUE
  expect_error(validate(bad),'must be explicitly non-production',fixed=TRUE)
  bad <- a; bad$runtime_contract$allow_hard_passage <- TRUE
  expect_error(validate(bad),'forbidden runtime route enabled',fixed=TRUE)
  bad <- a; bad$shape$eta <- .6
  expect_error(validate(bad),'eta mismatch',fixed=TRUE)
  bad <- a; bad$runtime_contract$lower_bound_step <- .1
  expect_error(validate(bad),'lower-bound monitoring contract mismatch',fixed=TRUE)
  bad <- a; bad$season_policy$state_training_seasons <- c(bad$season_policy$state_training_seasons,'2019-20')
  expect_error(validate(bad),'state training seasons mismatch',fixed=TRUE)
  bad <- a; bad$historical_evidence$benchmark_version <- 'wrong'
  expect_error(validate(bad),'historical benchmark version mismatch',fixed=TRUE)
  bad <- a; bad$historical_evidence$lower_bound_monitoring_required <- FALSE
  expect_error(validate(bad),'lower-bound monitoring caveat missing',fixed=TRUE)
})

test_that('M2-B v3 shadow runtime enforces prospective-only domain and production prohibition', {
  repo <- find_page_repo_root_m2b_shadow_v2()
  skip_if(is.na(repo),'PAGe repo unavailable')
  old_wd <- setwd(repo); on.exit(setwd(old_wd),add=TRUE)
  ctx <- load_m2b_shadow_test_context_v2(repo)
  a <- ctx$artifact; m1 <- ctx$m1
  active <- prospective_copy(ctx$panel,'2025-26')

  expect_error(ctx$env$m2_b_v3_production_forecast(),'shadow-only',fixed=TRUE)
  expect_error(ctx$env$m2_b_v3_shadow_forecast(a,m1,active,12,2),'not validated before weekF 13',fixed=TRUE)
  expect_error(ctx$env$m2_b_v3_shadow_forecast(a,m1,active,40,3),'supports horizons 1 and 2 only',fixed=TRUE)

  historical <- ctx$panel[ctx$panel$season=='2025-26',c('season','weekF','y_B','N_B','p_B')]
  expect_error(ctx$env$m2_b_v3_shadow_forecast(a,m1,historical,40,2),'prospective-only',fixed=TRUE)
})

test_that('M2-B v3 +1 always routes exact B1', {
  repo <- find_page_repo_root_m2b_shadow_v2()
  skip_if(is.na(repo),'PAGe repo unavailable')
  old_wd <- setwd(repo); on.exit(setwd(old_wd),add=TRUE)
  ctx <- load_m2b_shadow_test_context_v2(repo)
  z <- prospective_copy(ctx$panel,'2025-26')
  q <- ctx$env$m2_b_v3_shadow_forecast(ctx$artifact,ctx$m1,z,40,1)

  expect_equal(nrow(q),1L)
  expect_identical(q$horizon[[1]],1L)
  expect_false(q$timing_available[[1]])
  expect_identical(q$timing_reason[[1]],'plus1_state_only')
  expect_equal(q$forecast[[1]],q$B1_forecast[[1]],tolerance=0)
  expect_true(is.finite(q$forecast[[1]]))
})

test_that('M2-B v3 +2 weak activity falls back exactly to B1', {
  repo <- find_page_repo_root_m2b_shadow_v2()
  skip_if(is.na(repo),'PAGe repo unavailable')
  old_wd <- setwd(repo); on.exit(setwd(old_wd),add=TRUE)
  ctx <- load_m2b_shadow_test_context_v2(repo)
  z <- prospective_copy(ctx$panel,'2018-19')
  q <- ctx$env$m2_b_v3_shadow_forecast(ctx$artifact,ctx$m1,z,40,2)

  expect_false(q$timing_available[[1]])
  expect_identical(q$timing_reason[[1]],'not_detected')
  expect_equal(q$forecast[[1]],q$B1_forecast[[1]],tolerance=0)
  expect_equal(q$supported_mass[[1]],0,tolerance=0)
  expect_equal(q$lower_bound_mass[[1]],0,tolerance=0)
  expect_false(q$lower_bound_saturated[[1]])
})

test_that('M2-B v3 +2 active path calls governed M1 wrapper and exposes diagnostics', {
  repo <- find_page_repo_root_m2b_shadow_v2()
  skip_if(is.na(repo),'PAGe repo unavailable')
  old_wd <- setwd(repo); on.exit(setwd(old_wd),add=TRUE)
  ctx <- load_m2b_shadow_test_context_v2(repo)
  z <- prospective_copy(ctx$panel,'2025-26')

  ctx$env$.m2b_test_called <- FALSE
  ctx$env$.m2b_test_original <- get('m1_b_v3_passage_posterior',envir=globalenv(),inherits=TRUE)
  ctx$env$m1_b_v3_passage_posterior <- eval(quote(function(...) {
    .m2b_test_called <<- TRUE
    .m2b_test_original(...)
  }),envir=ctx$env)
  q <- ctx$env$m2_b_v3_shadow_forecast(ctx$artifact,ctx$m1,z,45,2)

  expect_true(ctx$env$.m2b_test_called)
  expect_true(q$timing_available[[1]])
  expect_identical(q$timing_reason[[1]],'posterior_C2')
  expect_lte(q$activity_week[[1]],45)
  expect_true(is.finite(q$forecast[[1]]))
  expect_true(is.finite(q$B1_forecast[[1]]))
  expect_gte(q$supported_mass[[1]],0)
  expect_lte(q$supported_mass[[1]],1)
  expect_gte(q$lower_bound_mass[[1]],0)
  expect_lte(q$lower_bound_mass[[1]],1)
  expect_identical(q$lower_bound_saturated[[1]],q$lower_bound_mass[[1]]>=0.9)
  expect_identical(q$m1_b_version[[1]],'m1-b-v3-peak-v8')
  expect_identical(q$m2_b_version[[1]],'m2-b-v3-shadow-v2')
  expect_identical(q$m2_b_artifact_id[[1]],ctx$artifact$artifact_id)
})

test_that('M2-B v3 package provenance manifest matches frozen inputs', {
  repo <- find_page_repo_root_m2b_shadow_v2()
  skip_if(is.na(repo),'PAGe repo unavailable')
  old_wd <- setwd(repo); on.exit(setwd(old_wd),add=TRUE)
  skip_if_not(requireNamespace('digest',quietly=TRUE))
  out <- file.path(repo,'artifacts','m2-b-v3-shadow-v2')
  manifest <- read.csv(file.path(out,'source_manifest.csv'),check.names=FALSE)
  expect_gt(nrow(manifest),0L)
  for (i in seq_len(nrow(manifest))) {
    path <- file.path(repo,manifest$path[[i]])
    expect_true(file.exists(path),info=manifest$path[[i]])
    expect_identical(manifest$sha256[[i]],digest::digest(file=path,algo='sha256',serialize=FALSE),info=manifest$path[[i]])
  }
})
