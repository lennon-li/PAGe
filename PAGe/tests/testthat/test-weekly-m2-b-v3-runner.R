find_page_repo_root_weekly_m2b_v3 <- function() {
  candidates <- c('.', '..', '../..', '../../..')
  hit <- candidates[file.exists(file.path(candidates,'2026','run_weekly_m2_b_shadow_v3.R'))]
  if (!length(hit)) return(NA_character_)
  normalizePath(hit[[1]],winslash='/',mustWork=TRUE)
}

test_that('weekly M2-B v3 runner records pre-window current panel without issuing forecast', {
  repo <- find_page_repo_root_weekly_m2b_v3()
  skip_if(is.na(repo),'PAGe repo unavailable')
  panel_path <- file.path(repo,'artifacts','m2-v2-live-shadow-2026-27-week11','typed_ab_weekly_revised.csv')
  skip_if_not(file.exists(panel_path),'week11 typed panel unavailable')
  old <- setwd(repo); on.exit(setwd(old),add=TRUE)
  env <- new.env(parent=globalenv())
  sys.source('2026/run_weekly_m2_b_shadow_v3.R',envir=env)
  out_root <- tempfile('weekly-m2b-v3-pre-')
  res <- env$.shadow_m2b_v3_main(c('--season=2026-27',paste0('--typed-panel=',panel_path),paste0('--output-root=',out_root)))

  expect_identical(res$status$origin_weekF,11L)
  expect_false(res$status$in_validated_window)
  expect_true(all(is.na(res$predictions$forecast)))
  expect_true(all(res$predictions$timing_reason=='not_in_validated_window_before_weekF13'))
  expect_identical(res$predictions$m2_b_version[[1]],'m2-b-v3-shadow-v3')
  expect_true(file.exists(file.path(res$run_dir,'provenance.tsv')))
  expect_true(file.exists(file.path(res$run_dir,'m2_b_v3_predictions.csv')))
})

test_that('weekly M2-B v3 runner enforces +1 B1 and exposes +2 timing diagnostics in valid window', {
  repo <- find_page_repo_root_weekly_m2b_v3()
  skip_if(is.na(repo),'PAGe repo unavailable')
  old <- setwd(repo); on.exit(setwd(old),add=TRUE)
  env <- new.env(parent=globalenv())
  sys.source('2026/run_weekly_m2_b_shadow_v3.R',envir=env)

  panel <- read.csv('artifacts/v3-joint-ab-audit-v1/canonical_ab_weekly_v3.csv',check.names=FALSE)
  z <- panel[panel$season=='2025-26' & panel$weekF<=45,c('season','weekF','y_A','N_A','p_A','y_B','N_B','p_B','denominator_regime')]
  z$season <- '2026-27'
  typed <- tempfile(fileext='.csv')
  write.csv(z,typed,row.names=FALSE)
  out_root <- tempfile('weekly-m2b-v3-active-')
  res <- env$.shadow_m2b_v3_main(c('--season=2026-27',paste0('--typed-panel=',typed),paste0('--output-root=',out_root)))

  expect_identical(res$status$origin_weekF,45L)
  expect_true(res$status$in_validated_window)
  h1 <- res$predictions[res$predictions$horizon==1L,,drop=FALSE]
  h2 <- res$predictions[res$predictions$horizon==2L,,drop=FALSE]
  expect_equal(h1$forecast,h1$B1_forecast,tolerance=0)
  expect_false(h1$timing_available)
  expect_identical(h1$timing_reason,'plus1_state_only')
  expect_true(is.finite(h2$forecast))
  expect_true(is.finite(h2$B1_forecast))
  expect_true(h2$timing_available)
  expect_identical(h2$timing_reason,'posterior_C2')
  expect_lte(h2$activity_week,45)
  expect_gte(h2$supported_mass,0)
  expect_lte(h2$supported_mass,1)
  expect_gte(h2$lower_bound_mass,0)
  expect_lte(h2$lower_bound_mass,1)
  expect_identical(h2$lower_bound_saturated,h2$lower_bound_mass>=0.9)
  expect_identical(h2$m2_b_version,'m2-b-v3-shadow-v3')
  expect_true(file.exists(file.path(res$run_dir,'forecast_summary.tsv')))
})


test_that('weekly M2-B v3 runner preflights the complete package manifest', {
  repo <- find_page_repo_root_weekly_m2b_v3()
  skip_if(is.na(repo),'PAGe repo unavailable')
  old <- setwd(repo); on.exit(setwd(old),add=TRUE)
  env <- new.env(parent=globalenv())
  sys.source('2026/run_weekly_m2_b_shadow_v3.R',envir=env)
  artifact <- 'artifacts/m2-b-v3-shadow-v3/m2_b_v3_shadow_artifact.rds'
  expect_true(env$.shadow_m2b_v3_verify_package_manifest(artifact))

  tmp <- tempfile('m2b-package-')
  dir.create(tmp)
  file.copy(artifact,file.path(tmp,'m2_b_v3_shadow_artifact.rds'))
  manifest <- read.csv('artifacts/m2-b-v3-shadow-v3/source_manifest.csv',check.names=FALSE)
  manifest$sha256[1] <- paste0(substr(manifest$sha256[1],1,63),'0')
  write.csv(manifest,file.path(tmp,'source_manifest.csv'),row.names=FALSE)
  expect_error(env$.shadow_m2b_v3_verify_package_manifest(file.path(tmp,'m2_b_v3_shadow_artifact.rds')),
               'package manifest hash mismatch',fixed=FALSE)
})


test_that('weekly M2-B v3 standalone runner rejects gapped weekF before forecast issuance', {
  repo <- find_page_repo_root_weekly_m2b_v3()
  skip_if(is.na(repo),'PAGe repo unavailable')
  old <- setwd(repo); on.exit(setwd(old),add=TRUE)
  env <- new.env(parent=globalenv())
  sys.source('2026/run_weekly_m2_b_shadow_v3.R',envir=env)
  panel <- read.csv('artifacts/v3-joint-ab-audit-v1/canonical_ab_weekly_v3.csv',check.names=FALSE)
  z <- panel[panel$season=='2025-26' & panel$weekF<=20,c('season','weekF','y_A','N_A','p_A','y_B','N_B','p_B','denominator_regime')]
  z$season <- '2026-27'
  z <- z[z$weekF != 15,,drop=FALSE]
  typed <- tempfile(fileext='.csv'); write.csv(z,typed,row.names=FALSE)
  expect_error(
    env$.shadow_m2b_v3_main(c('--season=2026-27',paste0('--typed-panel=',typed),paste0('--output-root=',tempfile('weekly-m2b-gap-')))),
    'weekF coverage must be contiguous',fixed=TRUE)
})
