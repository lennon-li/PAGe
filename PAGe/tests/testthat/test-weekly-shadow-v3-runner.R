find_page_repo_root_weekly_v3 <- function() {
  candidates <- c('.', '..', '../..', '../../..')
  hit <- candidates[file.exists(file.path(candidates,'2026','run_weekly_shadow_v3.R'))]
  if (!length(hit)) return(NA_character_)
  normalizePath(hit[[1]],winslash='/',mustWork=TRUE)
}

.weekly_v3_env <- function(repo) {
  old <- setwd(repo); on.exit(setwd(old),add=TRUE)
  env <- new.env(parent=globalenv())
  sys.source('2026/run_weekly_shadow_v3.R',envir=env)
  env
}

.weekly_v3_fixture <- function(repo, origin=45L) {
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

test_that('combined v3 preflight is a hard barrier before source resolution', {
  repo <- find_page_repo_root_weekly_v3(); skip_if(is.na(repo),'PAGe repo unavailable')
  old <- setwd(repo); on.exit(setwd(old),add=TRUE)
  env <- .weekly_v3_env(repo)
  flag <- new.env(parent=emptyenv()); flag$called <- FALSE
  env$.shadow_v3_resolve_panel <- function(...) { flag$called <- TRUE; stop('resolver should not run') }

  expect_error(
    env$.shadow_v3_main(c('--season=2026-27','--m0-artifact=does-not-exist.rds')),
    'Missing frozen v3 shadow artifact',fixed=TRUE)
  expect_false(flag$called)

  tmp <- tempfile('m2b-package-'); dir.create(tmp)
  file.copy('artifacts/m2-b-v3-shadow-v3/m2_b_v3_shadow_artifact.rds',file.path(tmp,'m2_b_v3_shadow_artifact.rds'))
  manifest <- read.csv('artifacts/m2-b-v3-shadow-v3/source_manifest.csv',check.names=FALSE)
  manifest$sha256[1] <- paste0(substr(manifest$sha256[1],1,63),'0')
  write.csv(manifest,file.path(tmp,'source_manifest.csv'),row.names=FALSE)
  expect_error(
    env$.shadow_v3_main(c('--season=2026-27',paste0('--m2-b-artifact=',file.path(tmp,'m2_b_v3_shadow_artifact.rds')))),
    'manifest identity mismatch',fixed=FALSE)
  expect_false(flag$called)
})

test_that('combined v3 validates both A and B panel contracts fail closed', {
  repo <- find_page_repo_root_weekly_v3(); skip_if(is.na(repo),'PAGe repo unavailable')
  old <- setwd(repo); on.exit(setwd(old),add=TRUE)
  env <- .weekly_v3_env(repo)
  x <- read.csv(.weekly_v3_fixture(repo,20),check.names=FALSE)

  bad <- x; bad$y_A[3] <- bad$N_A[3] + 1
  expect_error(env$.shadow_v3_validate_panel(bad,'2026-27'),'invalid A counts/proportions',fixed=FALSE)
  bad <- x; bad$p_B[4] <- bad$p_B[4] + .01
  expect_error(env$.shadow_v3_validate_panel(bad,'2026-27'),'B proportions do not match y/N',fixed=TRUE)
  bad <- x[-5,]
  expect_error(env$.shadow_v3_validate_panel(bad,'2026-27'),'weekF coverage must be contiguous',fixed=TRUE)
  bad <- x; bad$week_start_date <- as.character(as.Date('2026-07-01') + 7*(seq_len(nrow(bad))-1L))
  expect_error(env$.shadow_v3_validate_panel(bad,'2026-27'),'both week_start_date and week_end_date',fixed=TRUE)
  bad$week_end_date <- as.character(as.Date(bad$week_start_date)+6); bad$week_end_date[4] <- as.character(as.Date(bad$week_start_date[4])+5)
  expect_error(env$.shadow_v3_validate_panel(bad,'2026-27'),'weekly date bounds are invalid',fixed=TRUE)
})

test_that('combined v3 before weekF13 emits four non-issued rows and calls no forecast model', {
  repo <- find_page_repo_root_weekly_v3(); skip_if(is.na(repo),'PAGe repo unavailable')
  old <- setwd(repo); on.exit(setwd(old),add=TRUE)
  env <- .weekly_v3_env(repo)
  typed <- .weekly_v3_fixture(repo,11)
  env$run_m2_v2_c2_governed_runtime <- function(...) stop('A forecast must not run before week13')
  env$m2_b_v3_shadow_forecast <- function(...) stop('B forecast must not run before week13')
  res <- env$.shadow_v3_main(c('--season=2026-27',paste0('--typed-panel=',typed),paste0('--output-root=',tempfile('weekly-v3-pre-'))))

  expect_identical(res$status$origin_weekF,11L)
  expect_false(res$status$in_validated_window)
  expect_identical(nrow(res$predictions),4L)
  expect_true(all(is.na(res$predictions$forecast)))
  expect_true(all(res$predictions$route=='not_issued'))
  expect_true(all(res$predictions$timing_reason=='not_in_validated_window_before_weekF13'))
  expect_true(all(res$predictions$production_eligible==FALSE))
})

test_that('combined v3 valid active replay enforces final four-route contract', {
  repo <- find_page_repo_root_weekly_v3(); skip_if(is.na(repo),'PAGe repo unavailable')
  old <- setwd(repo); on.exit(setwd(old),add=TRUE)
  env <- .weekly_v3_env(repo)
  typed <- .weekly_v3_fixture(repo,45)
  res <- env$.shadow_v3_main(c('--season=2026-27',paste0('--typed-panel=',typed),paste0('--output-root=',tempfile('weekly-v3-active-'))))
  p <- res$predictions

  expect_identical(nrow(p),4L)
  a <- p[p$type=='A',]
  expect_true(all(a$route=='exact_A1_state'))
  expect_equal(a$forecast,a$state_baseline,tolerance=0)
  expect_false(any(a$timing_available))
  b1 <- p[p$type=='B' & p$horizon==1L,]
  b2 <- p[p$type=='B' & p$horizon==2L,]
  expect_identical(b1$route,'exact_B1_state')
  expect_equal(b1$forecast,b1$state_baseline,tolerance=0)
  expect_false(b1$timing_available)
  expect_true(b2$timing_available)
  expect_identical(b2$route,'posterior_C2')
  expect_identical(b2$timing_reason,'posterior_C2')
  expect_lte(b2$activity_week,45)
  expect_gte(b2$supported_mass,0); expect_lte(b2$supported_mass,1)
  expect_identical(b2$lower_bound_saturated,b2$lower_bound_mass>=.9)
  expect_true(all(p$production_eligible==FALSE))
  expect_false(res$provenance$production_eligible)
  expect_false(res$provenance$hard_b_passage_allowed)
})

test_that('combined v3 weak B timing falls back exactly to B1 while A remains A1', {
  repo <- find_page_repo_root_weekly_v3(); skip_if(is.na(repo),'PAGe repo unavailable')
  old <- setwd(repo); on.exit(setwd(old),add=TRUE)
  env <- .weekly_v3_env(repo)
  typed <- .weekly_v3_fixture(repo,20)
  res <- env$.shadow_v3_main(c('--season=2026-27',paste0('--typed-panel=',typed),paste0('--output-root=',tempfile('weekly-v3-weak-'))))
  p <- res$predictions
  expect_true(all(p$forecast[p$type=='A']==p$state_baseline[p$type=='A']))
  b2 <- p[p$type=='B' & p$horizon==2L,]
  expect_false(b2$timing_available)
  expect_identical(b2$route,'exact_B1_fallback')
  expect_equal(b2$forecast,b2$state_baseline,tolerance=0)
})

test_that('combined v3 A timing monitoring cannot alter A forecast', {
  repo <- find_page_repo_root_weekly_v3(); skip_if(is.na(repo),'PAGe repo unavailable')
  old <- setwd(repo); on.exit(setwd(old),add=TRUE)
  typed <- .weekly_v3_fixture(repo,20)

  run_fake <- function(tag) {
    env <- .weekly_v3_env(repo)
    env$run_m1_v2_timing <- function(...) list(status=tag,timing_df=data.frame(),m2_handoff=list(fake=tag))
    env$.shadow_v3_main(c('--season=2026-27',paste0('--typed-panel=',typed),paste0('--output-root=',tempfile(paste0('weekly-v3-a-',tag,'-')))))
  }
  r1 <- run_fake('monitor_A')
  r2 <- run_fake('monitor_B')
  a1 <- r1$predictions[r1$predictions$type=='A',c('horizon','forecast','state_baseline','route')]
  a2 <- r2$predictions[r2$predictions$type=='A',c('horizon','forecast','state_baseline','route')]
  expect_identical(a1,a2)
  expect_true(all(a1$forecast==a1$state_baseline))
})

test_that('combined v3 resolves one shared panel and replay outputs are deterministic', {
  repo <- find_page_repo_root_weekly_v3(); skip_if(is.na(repo),'PAGe repo unavailable')
  old <- setwd(repo); on.exit(setwd(old),add=TRUE)
  typed <- .weekly_v3_fixture(repo,20)

  env <- .weekly_v3_env(repo)
  original <- env$.shadow_v3_resolve_panel
  counter <- new.env(parent=emptyenv()); counter$n <- 0L
  env$.shadow_v3_resolve_panel <- function(...) { counter$n <- counter$n+1L; original(...) }
  r1 <- env$.shadow_v3_main(c('--season=2026-27',paste0('--typed-panel=',typed),paste0('--output-root=',tempfile('weekly-v3-det1-'))))
  expect_identical(counter$n,1L)

  env2 <- .weekly_v3_env(repo)
  r2 <- env2$.shadow_v3_main(c('--season=2026-27',paste0('--typed-panel=',typed),paste0('--output-root=',tempfile('weekly-v3-det2-'))))
  expect_identical(r1$predictions,r2$predictions)
  expect_identical(r1$provenance$source_sha256,r2$provenance$source_sha256)
  expect_true(file.exists(file.path(r1$run_dir,'combined_predictions.csv')))
  expect_true(file.exists(file.path(r1$run_dir,'provenance.tsv')))
})

test_that('combined v3 exposes no production or hard-passage route', {
  repo <- find_page_repo_root_weekly_v3(); skip_if(is.na(repo),'PAGe repo unavailable')
  old <- setwd(repo); on.exit(setwd(old),add=TRUE)
  env <- .weekly_v3_env(repo)
  expect_true(exists('m2_b_v3_production_forecast',envir=.GlobalEnv,mode='function'))
  expect_true(exists('m1_b_v3_passage_decision',envir=.GlobalEnv,mode='function'))
  expect_error(get('m2_b_v3_production_forecast',envir=.GlobalEnv)(),'shadow-only',fixed=FALSE)
  expect_error(get('m1_b_v3_passage_decision',envir=.GlobalEnv)(),'Hard M1-B passage decisions are forbidden',fixed=TRUE)
})
