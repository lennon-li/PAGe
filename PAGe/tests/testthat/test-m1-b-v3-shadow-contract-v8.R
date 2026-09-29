find_page_repo_root_v8 <- function() {
  candidates <- c('.', '..', '../..', '../../..')
  hit <- candidates[file.exists(file.path(candidates, 'scripts', 'v3_m1_b_runtime_helpers_v7.R'))]
  if (!length(hit)) return(NA_character_)
  normalizePath(hit[[1]], winslash='/', mustWork=TRUE)
}

test_that('v8 M1-B artifact pins pandemic exclusions and runtime parameters', {
  repo <- find_page_repo_root_v8()
  skip_if(is.na(repo), 'PAGe repository root unavailable')
  artifact_path <- file.path(repo,'artifacts','m1-b-v3-peak-v8','m1_b_v3_peak_artifact.rds')
  skip_if_not(file.exists(artifact_path),'M1-B v8 artifact unavailable')
  old <- setwd(repo); on.exit(setwd(old),add=TRUE)
  source('scripts/v3_m1_b_runtime_helpers_v7.R',local=environment())
  a <- load_m1_b_v3_artifact(artifact_path)

  expect_true(validate_m1_b_v3_artifact(a))
  expect_identical(a$version,'m1-b-v3-peak-v8')
  expect_identical(a$season_policy$excluded_B_season,'2019-20')
  expect_identical(a$season_policy$no_event_season,'2018-19')
  expect_false('2019-20' %in% a$training_seasons)
  expect_false('2018-19' %in% a$training_seasons)
  expect_identical(a$passage$hard_gate_eligible,FALSE)
  expect_identical(a$runtime_contract$allow_passage_decision,FALSE)
  expect_identical(a$runtime_contract$peak_candidate_step,0.1)
  expect_identical(a$runtime_contract$peak_max_future_weeks,16)
  expect_identical(a$runtime_contract$passage_candidate_step,0.2)
  expect_identical(a$runtime_contract$passage_max_future_weeks,12)
})

test_that('v8 validator rejects runtime drift and loose hard-gate state', {
  repo <- find_page_repo_root_v8()
  skip_if(is.na(repo), 'PAGe repository root unavailable')
  artifact_path <- file.path(repo,'artifacts','m1-b-v3-peak-v8','m1_b_v3_peak_artifact.rds')
  skip_if_not(file.exists(artifact_path),'M1-B v8 artifact unavailable')
  old <- setwd(repo); on.exit(setwd(old),add=TRUE)
  source('scripts/v3_m1_b_runtime_helpers_v7.R',local=environment())
  a <- readRDS(artifact_path)

  bad <- a; bad$runtime_contract$peak_candidate_step <- 0.2
  expect_error(validate_m1_b_v3_artifact(bad),'peak candidate_step differs from the frozen runtime contract',fixed=TRUE)
  bad <- a; bad$runtime_contract$peak_max_future_weeks <- 30
  expect_error(validate_m1_b_v3_artifact(bad),'peak max_future_weeks differs from the frozen runtime contract',fixed=TRUE)
  bad <- a; bad$runtime_contract$passage_candidate_step <- 0.1
  expect_error(validate_m1_b_v3_artifact(bad),'passage candidate_step differs from the frozen runtime contract',fixed=TRUE)
  bad <- a; bad$runtime_contract$passage_max_future_weeks <- 16
  expect_error(validate_m1_b_v3_artifact(bad),'passage max_future_weeks differs from the frozen runtime contract',fixed=TRUE)
  bad <- a; bad$passage$hard_gate_eligible <- NULL
  expect_error(validate_m1_b_v3_artifact(bad),'hard passage eligibility must be explicitly FALSE',fixed=TRUE)
  bad <- a; bad$passage$hard_gate_eligible <- TRUE
  expect_error(validate_m1_b_v3_artifact(bad),'hard passage eligibility must be explicitly FALSE',fixed=TRUE)
})

test_that('v8 governed helper forbids hard passage decisions', {
  repo <- find_page_repo_root_v8()
  skip_if(is.na(repo), 'PAGe repository root unavailable')
  old <- setwd(repo); on.exit(setwd(old),add=TRUE)
  source('scripts/v3_m1_b_runtime_helpers_v7.R',local=environment())
  expect_error(m1_b_v3_passage_decision(),
               'Hard M1-B passage decisions are forbidden through the governed M1-B helper',
               fixed=TRUE)
  x <- m1_b_v3_inactive_state()
  expect_identical(x$state,'inactive_no_timing_event')
  expect_identical(x$positive_timing_gate,FALSE)
})
