find_page_repo_root_m2b_v3_v3 <- function() {
  candidates <- c('.', '..', '../..', '../../..')
  hit <- candidates[file.exists(file.path(candidates,'scripts','v3_m2_b_runtime_helpers_v3.R'))]
  if (!length(hit)) return(NA_character_)
  normalizePath(hit[[1]],winslash='/',mustWork=TRUE)
}

.m2b_v3_fixture <- function(repo,origin) {
  old <- setwd(repo); on.exit(setwd(old),add=TRUE)
  x <- read.csv('artifacts/v3-joint-ab-audit-v1/canonical_ab_weekly_v3.csv',check.names=FALSE)
  z <- x[x$season=='2025-26' & x$weekF<=origin,c('season','weekF','y_B','N_B','p_B')]
  z$season <- '2026-27'
  z
}

test_that('M2-B shadow-v3 is an exact governance rebind of shadow-v2 behavioral payload', {
  repo <- find_page_repo_root_m2b_v3_v3(); skip_if(is.na(repo),'PAGe repo unavailable')
  old <- setwd(repo); on.exit(setwd(old),add=TRUE)
  v2 <- readRDS('artifacts/m2-b-v3-shadow-v2/m2_b_v3_shadow_artifact.rds')
  v3 <- readRDS('artifacts/m2-b-v3-shadow-v3/m2_b_v3_shadow_artifact.rds')
  expect_identical(stats::coef(v3$state$model),stats::coef(v2$state$model))
  expect_identical(v3$state$model,v2$state$model)
  expect_identical(v3$state$training_seasons,v2$state$training_seasons)
  expect_identical(v3$shape$grid,v2$shape$grid)
  expect_identical(v3$shape$tau_grid,v2$shape$tau_grid)
  expect_identical(v3$shape$A_seasons,v2$shape$A_seasons)
  expect_identical(v3$shape$B_seasons,v2$shape$B_seasons)
  expect_identical(v3$shape$pooled_weight,v2$shape$pooled_weight)
  expect_identical(v3$shape$B_weight,v2$shape$B_weight)
  expect_identical(v3$shape$eta,v2$shape$eta)
  for (nm in c('min_origin_week','horizons','plus1_route','plus2_route','allow_hard_passage','allow_production','lower_bound_step','lower_bound_saturation_threshold','lower_bound_definition')) {
    expect_identical(v3$runtime_contract[[nm]],v2$runtime_contract[[nm]],info=nm)
  }
  expect_identical(v3$activity$params,v2$activity$params)
  expect_identical(v3$activity$semantics,v2$activity$semantics)
})

test_that('M2-B shadow-v3 recomputes its artifact ID and binds M1-B v9/timing v3', {
  repo <- find_page_repo_root_m2b_v3_v3(); skip_if(is.na(repo),'PAGe repo unavailable')
  old <- setwd(repo); on.exit(setwd(old),add=TRUE)
  source('scripts/v3_m2_b_runtime_helpers_v3.R',local=environment())
  a <- load_m2_b_v3_shadow_artifact()
  expect_true(validate_m2_b_v3_shadow_artifact(a))
  expect_identical(a$version,'m2-b-v3-shadow-v3')
  expect_identical(a$m1_b$version,'m1-b-v3-peak-v9')
  expect_identical(a$artifact_id,digest::digest(.m2b_v3_core(a),algo='sha256'))
  expect_identical(a$provenance$timing_contract_sha256,digest::digest(file='artifacts/v3-joint-timing-contract-v3/timing_contract_v3.csv',algo='sha256',serialize=FALSE))
  expect_identical(a$provenance$modeling_eligibility_sha256,digest::digest(file='artifacts/v3-joint-timing-contract-v3/modeling_eligibility_v3.csv',algo='sha256',serialize=FALSE))
})

test_that('shadow-v2 and shadow-v3 forecasts are numerically equivalent on fallback and active fixtures', {
  repo <- find_page_repo_root_m2b_v3_v3(); skip_if(is.na(repo),'PAGe repo unavailable')
  old <- setwd(repo); on.exit(setwd(old),add=TRUE)

  # Evaluate accepted shadow-v2 first.
  source('scripts/v3_m2_b_runtime_helpers_v2.R',local=environment())
  a2 <- load_m2_b_v3_shadow_artifact('artifacts/m2-b-v3-shadow-v2/m2_b_v3_shadow_artifact.rds')
  m12 <- readRDS('artifacts/m1-b-v3-peak-v8/m1_b_v3_peak_artifact.rds')
  validate_m1_b_v3_artifact(m12)
  fixtures <- list(weak=.m2b_v3_fixture(repo,20L),active=.m2b_v3_fixture(repo,45L))
  out2 <- list()
  for (tag in names(fixtures)) for (h in 1:2) {
    d <- fixtures[[tag]]; o <- max(d$weekF)
    out2[[paste(tag,h)]] <- m2_b_v3_shadow_forecast(a2,m12,d,o,h)
  }

  # Re-source v3 contract and evaluate the rebound package.
  source('scripts/v3_m2_b_runtime_helpers_v3.R',local=environment())
  a3 <- load_m2_b_v3_shadow_artifact('artifacts/m2-b-v3-shadow-v3/m2_b_v3_shadow_artifact.rds')
  m13 <- readRDS('artifacts/m1-b-v3-peak-v9/m1_b_v3_peak_artifact.rds')
  validate_m1_b_v3_artifact(m13)
  out3 <- list()
  for (tag in names(fixtures)) for (h in 1:2) {
    d <- fixtures[[tag]]; o <- max(d$weekF)
    out3[[paste(tag,h)]] <- m2_b_v3_shadow_forecast(a3,m13,d,o,h)
  }

  fields <- c('forecast','B1_forecast','timing_available','timing_reason','activity_week','prob_peak_passed','posterior_mean_peak','supported_mass','lower_bound_mass','lower_bound_saturated')
  for (nm in names(out2)) {
    for (field in fields) expect_equal(out3[[nm]][[field]],out2[[nm]][[field]],tolerance=1e-14,info=paste(nm,field))
  }
  expect_false(out2[['weak 2']]$timing_available)
  expect_true(out2[['active 2']]$timing_available)
  expect_identical(out2[['active 1']]$timing_reason,'plus1_state_only')
  expect_identical(out3[['active 1']]$forecast,out3[['active 1']]$B1_forecast)
  expect_identical(out2[['active 2']]$lower_bound_saturated,out3[['active 2']]$lower_bound_saturated)
})
