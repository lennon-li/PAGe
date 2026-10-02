find_page_repo_root <- function() {
  candidates <- c('.', '..', '../..', '../../..')
  hit <- candidates[file.exists(file.path(candidates, 'scripts', 'v3_m1_b_runtime_helpers_v5.R'))]
  if (!length(hit)) return(NA_character_)
  normalizePath(hit[[1]], winslash='/', mustWork=TRUE)
}

test_that('v3 M1-B shadow artifact preserves pandemic/no-event exclusions', {
  repo <- find_page_repo_root()
  skip_if(is.na(repo), 'PAGe repository root unavailable')
  artifact_path <- file.path(repo, 'artifacts', 'm1-b-v3-peak-v6', 'm1_b_v3_peak_artifact.rds')
  skip_if_not(file.exists(artifact_path), 'serialized M1-B v3 artifact unavailable')

  old <- setwd(repo)
  on.exit(setwd(old), add=TRUE)
  source('scripts/v3_m1_b_runtime_helpers_v5.R', local=environment())

  a <- load_m1_b_v3_artifact(artifact_path)
  expect_true(validate_m1_b_v3_artifact(a))
  expect_identical(a$version, 'm1-b-v3-peak-v6')
  expect_identical(a$season_policy$excluded_B_season, '2019-20')
  expect_identical(a$season_policy$no_event_season, '2018-19')
  expected_training <- c('2012-13','2013-14','2014-15','2016-17','2017-18','2022-23','2023-24','2024-25','2025-26')
  expect_identical(as.character(a$training_seasons), expected_training)
  expect_identical(as.character(a$library$training_seasons), expected_training)
  expect_false('2019-20' %in% a$training_seasons)
  expect_false('2018-19' %in% a$training_seasons)
  expect_length(a$training_seasons, 9L)
  expect_false(a$passage$hard_gate_eligible)
  expect_true(a$passage$historical_threshold_search_closed)
  expect_true(a$passage$continuous_posterior_shadow_only)
  expect_identical(a$runtime_contract$allow_passage_decision, FALSE)
})

test_that('v3 M1-B runtime exposes peak and continuous passage posteriors only', {
  repo <- find_page_repo_root()
  skip_if(is.na(repo), 'PAGe repository root unavailable')
  artifact_path <- file.path(repo, 'artifacts', 'm1-b-v3-peak-v6', 'm1_b_v3_peak_artifact.rds')
  panel_path <- file.path(repo, 'artifacts', 'v3-joint-ab-audit-v1', 'canonical_ab_weekly_v3.csv')
  timing_path <- file.path(repo, 'artifacts', 'v3-joint-timing-contract-v2', 'timing_contract_v3.csv')
  skip_if_not(all(file.exists(c(artifact_path, panel_path, timing_path))), 'M1-B research artifacts unavailable')

  old <- setwd(repo)
  on.exit(setwd(old), add=TRUE)
  source('scripts/v3_m1_b_runtime_helpers_v5.R', local=environment())

  a <- load_m1_b_v3_artifact(artifact_path)
  panel <- read.csv(panel_path, check.names=FALSE)
  timing <- read.csv(timing_path, check.names=FALSE)

  source_season <- '2025-26'
  current <- panel[panel$season == source_season, c('season','weekF','y_B','N_B','p_B')]
  current$season <- '2026-27'
  names(current)[names(current) == 'y_B'] <- 'y'
  names(current)[names(current) == 'N_B'] <- 'N'
  names(current)[names(current) == 'p_B'] <- 'p'
  activity <- timing$B_activity_weekF[timing$season == source_season]
  expect_true(is.finite(activity))
  origin <- max(ceiling(activity) + 1L, 36L)

  pk <- m1_b_v3_peak_posterior(a, current, activity_week=activity, origin_week=origin)
  expect_true(is.data.frame(pk$summary))
  expect_true(is.finite(pk$summary$peak_mean[[1]]))
  expect_true(pk$summary$peak_q05[[1]] <= pk$summary$peak_q95[[1]])

  pp <- m1_b_v3_passage_posterior(a, current, activity_week=activity, origin_week=origin)
  expect_true(is.data.frame(pp))
  expect_true(is.finite(pp$prob_peak_passed[[1]]))
  expect_gte(pp$prob_peak_passed[[1]], 0)
  expect_lte(pp$prob_peak_passed[[1]], 1)

  expect_error(
    m1_b_v3_passage_decision(),
    'Hard M1-B passage decisions are forbidden through the governed M1-B helper',
    fixed=TRUE
  )
})

test_that('v3 M1-B inactive state cannot emit a positive timing gate', {
  repo <- find_page_repo_root()
  skip_if(is.na(repo), 'PAGe repository root unavailable')

  old <- setwd(repo)
  on.exit(setwd(old), add=TRUE)
  source('scripts/v3_m1_b_runtime_helpers_v5.R', local=environment())

  x <- m1_b_v3_inactive_state()
  expect_identical(x$state, 'inactive_no_timing_event')
  expect_false(x$positive_timing_gate)
  expect_null(x$peak_posterior)
  expect_null(x$passage_posterior)
})

test_that('v3 M1-B validator rejects excluded seasons or hard-gate drift', {
  repo <- find_page_repo_root()
  skip_if(is.na(repo), 'PAGe repository root unavailable')
  artifact_path <- file.path(repo, 'artifacts', 'm1-b-v3-peak-v6', 'm1_b_v3_peak_artifact.rds')
  skip_if_not(file.exists(artifact_path), 'serialized M1-B v3 artifact unavailable')

  old <- setwd(repo)
  on.exit(setwd(old), add=TRUE)
  source('scripts/v3_m1_b_runtime_helpers_v5.R', local=environment())
  a <- readRDS(artifact_path)

  bad <- a
  bad$training_seasons <- c(bad$training_seasons, '2019-20')
  expect_error(validate_m1_b_v3_artifact(bad), 'artifact training seasons differ from the frozen 9-season policy', fixed=TRUE)

  bad <- a
  bad$library$training_seasons <- c(bad$library$training_seasons, '2019-20')
  expect_error(validate_m1_b_v3_artifact(bad), 'fitted library training seasons differ from the frozen 9-season policy', fixed=TRUE)

  bad <- a
  bad$library$training_seasons <- c(bad$library$training_seasons, '2018-19')
  expect_error(validate_m1_b_v3_artifact(bad), 'fitted library training seasons differ from the frozen 9-season policy', fixed=TRUE)

  bad <- a
  bad$season_policy$excluded_B_season <- 'none'
  expect_error(validate_m1_b_v3_artifact(bad), 'does not carry the frozen 2019-20 exclusion', fixed=TRUE)

  bad <- a
  bad$season_policy$no_event_season <- 'none'
  expect_error(validate_m1_b_v3_artifact(bad), 'does not carry the frozen 2018-19 no-event season', fixed=TRUE)

  bad <- a
  bad$calibration$enabled <- TRUE
  expect_error(validate_m1_b_v3_artifact(bad), 'scalar calibration must be explicitly disabled', fixed=TRUE)

  bad <- a
  bad$joint_A_conditioning$enabled <- TRUE
  expect_error(validate_m1_b_v3_artifact(bad), 'A-conditioning must be explicitly disabled', fixed=TRUE)

  bad <- a
  bad$passage$hard_gate_eligible <- TRUE
  expect_error(validate_m1_b_v3_artifact(bad), 'unexpectedly permits a hard passage gate', fixed=TRUE)

  bad <- a
  bad$runtime_contract$allow_passage_decision <- TRUE
  expect_error(validate_m1_b_v3_artifact(bad), 'does not explicitly disable passage decisions', fixed=TRUE)
})


test_that('v3 M1-B validator enforces frozen library contents and provenance', {
  repo <- find_page_repo_root()
  skip_if(is.na(repo), 'PAGe repository root unavailable')
  artifact_path <- file.path(repo, 'artifacts', 'm1-b-v3-peak-v6', 'm1_b_v3_peak_artifact.rds')
  skip_if_not(file.exists(artifact_path), 'serialized M1-B v3 artifact unavailable')

  old <- setwd(repo)
  on.exit(setwd(old), add=TRUE)
  source('scripts/v3_m1_b_runtime_helpers_v5.R', local=environment())
  a <- readRDS(artifact_path)

  bad <- a
  bad$calibration <- NULL
  expect_error(validate_m1_b_v3_artifact(bad), 'scalar calibration must be explicitly disabled', fixed=TRUE)

  bad <- a
  bad$joint_A_conditioning <- NULL
  expect_error(validate_m1_b_v3_artifact(bad), 'A-conditioning must be explicitly disabled', fixed=TRUE)

  bad <- a
  bad$training_seasons <- bad$training_seasons[1:5]
  bad$library$training_seasons <- bad$library$training_seasons[1:5]
  expect_error(validate_m1_b_v3_artifact(bad), 'artifact training seasons differ from the frozen 9-season policy', fixed=TRUE)

  bad <- a
  bad$library$peak_truth <- rbind(bad$library$peak_truth,
                                 data.frame(season='2019-20',peak_week_decimal=33.09))
  expect_error(validate_m1_b_v3_artifact(bad), 'peak_truth seasons differ from the frozen training policy', fixed=TRUE)

  bad <- a
  bad$runtime_contract$required_helper <- 'scripts/not-the-frozen-helper.R'
  expect_error(validate_m1_b_v3_artifact(bad), 'runtime helper path differs from the frozen contract', fixed=TRUE)

  bad <- a
  bad$provenance$library_hash <- 'tampered'
  expect_error(validate_m1_b_v3_artifact(bad), 'artifact/library provenance hash mismatch', fixed=TRUE)
})

test_that('v3 M1-B runtime parameters are artifact-authoritative', {
  repo <- find_page_repo_root()
  skip_if(is.na(repo), 'PAGe repository root unavailable')
  artifact_path <- file.path(repo, 'artifacts', 'm1-b-v3-peak-v6', 'm1_b_v3_peak_artifact.rds')
  panel_path <- file.path(repo, 'artifacts', 'v3-joint-ab-audit-v1', 'canonical_ab_weekly_v3.csv')
  timing_path <- file.path(repo, 'artifacts', 'v3-joint-timing-contract-v2', 'timing_contract_v3.csv')
  skip_if_not(all(file.exists(c(artifact_path,panel_path,timing_path))), 'M1-B research artifacts unavailable')

  old <- setwd(repo)
  on.exit(setwd(old), add=TRUE)
  source('scripts/v3_m1_b_runtime_helpers_v5.R', local=environment())
  a <- load_m1_b_v3_artifact(artifact_path)
  panel <- read.csv(panel_path,check.names=FALSE)
  timing <- read.csv(timing_path,check.names=FALSE)
  current <- panel[panel$season=='2025-26',c('season','weekF','y_B','N_B','p_B')]
  current$season <- '2026-27'
  names(current)[names(current)=='y_B'] <- 'y'
  names(current)[names(current)=='N_B'] <- 'N'
  names(current)[names(current)=='p_B'] <- 'p'
  activity <- timing$B_activity_weekF[timing$season=='2025-26']
  origin <- max(ceiling(activity)+1L,36L)

  expect_error(m1_b_v3_peak_posterior(a,current,activity,origin,candidate_step=.2),
               'peak candidate_step override violates frozen runtime contract',fixed=TRUE)
  expect_error(m1_b_v3_peak_posterior(a,current,activity,origin,max_future_weeks=12),
               'peak max_future_weeks override violates frozen runtime contract',fixed=TRUE)
  expect_error(m1_b_v3_passage_posterior(a,current,activity,origin,candidate_step=.1),
               'passage candidate_step override violates frozen runtime contract',fixed=TRUE)
  expect_error(m1_b_v3_passage_posterior(a,current,activity,origin,max_future_weeks=16),
               'passage max_future_weeks override violates frozen runtime contract',fixed=TRUE)
})
