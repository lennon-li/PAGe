find_page_repo_root_v9 <- function() {
  candidates <- c('.', '..', '../..', '../../..')
  hit <- candidates[file.exists(file.path(candidates, 'scripts', 'v3_m1_b_runtime_helpers_v8.R'))]
  if (!length(hit)) return(NA_character_)
  normalizePath(hit[[1]], winslash='/', mustWork=TRUE)
}

test_that('v9 M1-B artifact pins pandemic exclusions, artifact_id, and runtime parameters', {
  repo <- find_page_repo_root_v9()
  skip_if(is.na(repo), 'PAGe repository root unavailable')
  artifact_path <- file.path(repo,'artifacts','m1-b-v3-peak-v9','m1_b_v3_peak_artifact.rds')
  skip_if_not(file.exists(artifact_path),'M1-B v9 artifact unavailable')
  old <- setwd(repo); on.exit(setwd(old),add=TRUE)
  source('scripts/v3_m1_b_runtime_helpers_v8.R',local=environment())
  a <- load_m1_b_v3_artifact(artifact_path)

  expect_true(validate_m1_b_v3_artifact(a))
  expect_identical(a$version,'m1-b-v3-peak-v9')
  expect_true(is.character(a$artifact_id) && nzchar(a$artifact_id))
  expect_identical(a$artifact_id, compute_m1_b_v3_artifact_id(a))
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

test_that('v9 validator rejects runtime drift, artifact_id mismatch, and policy drift', {
  repo <- find_page_repo_root_v9()
  skip_if(is.na(repo), 'PAGe repository root unavailable')
  artifact_path <- file.path(repo,'artifacts','m1-b-v3-peak-v9','m1_b_v3_peak_artifact.rds')
  skip_if_not(file.exists(artifact_path),'M1-B v9 artifact unavailable')
  old <- setwd(repo); on.exit(setwd(old),add=TRUE)
  source('scripts/v3_m1_b_runtime_helpers_v8.R',local=environment())
  a <- readRDS(artifact_path)

  # artifact_id tampering
  bad_id <- a; bad_id$artifact_id <- 'tampered_id'
  expect_error(validate_m1_b_v3_artifact(bad_id),
               'M1-B artifact_id verification failed: recomputed ID does not match artifact_id.',
               fixed=TRUE)

  # policy drift detection
  bad_pol <- a; bad_pol$season_policy$source_sha256 <- '0000000000000000000000000000000000000000000000000000000000000000'
  expect_error(validate_m1_b_v3_artifact(bad_pol),
               'M1-B artifact_id verification failed',
               fixed=TRUE)

  # timing contract drift detection
  bad_timing <- a; bad_timing$timing_contract_sha256 <- '0000000000000000000000000000000000000000000000000000000000000000'
  expect_error(validate_m1_b_v3_artifact(bad_timing),
               'M1-B artifact_id verification failed',
               fixed=TRUE)

  # runtime contract drift
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

test_that('v9 governed helper forbids hard passage decisions', {
  repo <- find_page_repo_root_v9()
  skip_if(is.na(repo), 'PAGe repository root unavailable')
  old <- setwd(repo); on.exit(setwd(old),add=TRUE)
  source('scripts/v3_m1_b_runtime_helpers_v8.R',local=environment())
  expect_error(m1_b_v3_passage_decision(),
               'Hard M1-B passage decisions are forbidden through the governed M1-B helper',
               fixed=TRUE)
  x <- m1_b_v3_inactive_state()
  expect_identical(x$state,'inactive_no_timing_event')
  expect_identical(x$positive_timing_gate,FALSE)
})

test_that('v9 fitted library hash equals accepted v8 library hash and outputs are numerically equivalent', {
  repo <- find_page_repo_root_v9()
  skip_if(is.na(repo), 'PAGe repository root unavailable')
  v8_path <- file.path(repo,'artifacts','m1-b-v3-peak-v8','m1_b_v3_peak_artifact.rds')
  v9_path <- file.path(repo,'artifacts','m1-b-v3-peak-v9','m1_b_v3_peak_artifact.rds')
  skip_if_not(file.exists(v8_path), 'M1-B v8 artifact unavailable')
  skip_if_not(file.exists(v9_path), 'M1-B v9 artifact unavailable')

  old <- setwd(repo); on.exit(setwd(old),add=TRUE)
  env8 <- new.env()
  sys.source('scripts/v3_m1_b_runtime_helpers_v7.R', envir=env8)
  v8 <- env8$load_m1_b_v3_artifact(v8_path)

  env9 <- new.env()
  sys.source('scripts/v3_m1_b_runtime_helpers_v8.R', envir=env9)
  v9 <- env9$load_m1_b_v3_artifact(v9_path)

  # Library hash equality
  expect_identical(v9$library$provenance$library_hash, v8$library$provenance$library_hash)

  # Replay fixture across multiple origins and seasons
  panel <- read.csv('artifacts/v3-joint-ab-audit-v1/canonical_ab_weekly_v3.csv')
  timing <- read.csv('artifacts/v3-joint-timing-contract-v3/timing_contract_v3.csv')
  test_seasons <- c('2017-18', '2023-24', '2024-25', '2025-26')

  for (s in test_seasons) {
    df <- panel[panel$season == s, ]
    act <- timing$B_activity_weekF[timing$season == s]
    for (w in c(35, 36, 38, 40)) {
      if (w <= act) next
      sub <- df[df$weekF <= w, c('season', 'weekF', 'y_B', 'N_B', 'p_B')]
      names(sub) <- c('season', 'weekF', 'y', 'N', 'p')
      sub$season <- '2026-27' # shadow prospective season to avoid training leakage check

      post_v8 <- env8$m1_b_v3_peak_posterior(v8, sub, act, w)
      post_v9 <- env9$m1_b_v3_peak_posterior(v9, sub, act, w)
      expect_equal(post_v9$posterior$probability, post_v8$posterior$probability, tolerance=1e-12)

      pass_v8 <- env8$m1_b_v3_passage_posterior(v8, sub, act, w)
      pass_v9 <- env9$m1_b_v3_passage_posterior(v9, sub, act, w)
      expect_equal(pass_v9$prob_peak_passed, pass_v8$prob_peak_passed, tolerance=1e-12)
      expect_equal(attr(pass_v9, 'posterior')$probability, attr(pass_v8, 'posterior')$probability, tolerance=1e-12)
    }
  }
})
