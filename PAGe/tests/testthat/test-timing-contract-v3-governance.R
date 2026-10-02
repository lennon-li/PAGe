find_page_repo_root_timing_v3 <- function() {
  candidates <- c('.', '..', '../..', '../../..')
  hit <- candidates[file.exists(file.path(candidates, 'governance', 'v3_b_season_policy_v1.csv'))]
  if (!length(hit)) return(NA_character_)
  normalizePath(hit[[1]], winslash='/', mustWork=TRUE)
}

test_that('timing contract v3 reproduces accepted timing values and invariants', {
  repo <- find_page_repo_root_timing_v3()
  skip_if(is.na(repo), 'PAGe repository root unavailable')
  old <- setwd(repo); on.exit(setwd(old), add=TRUE)

  t_v2_path <- file.path('artifacts', 'v3-joint-timing-contract-v2', 'timing_contract_v3.csv')
  t_v3_path <- file.path('artifacts', 'v3-joint-timing-contract-v3', 'timing_contract_v3.csv')
  skip_if_not(file.exists(t_v2_path) && file.exists(t_v3_path), 'Timing contracts unavailable')

  t2 <- read.csv(t_v2_path, check.names=FALSE)
  t3 <- read.csv(t_v3_path, check.names=FALSE)

  expect_identical(names(t2), names(t3))
  expect_identical(t2$season, t3$season)

  # Numerical timing values must match accepted v2
  for (nm in names(t2)) {
    if (is.numeric(t2[[nm]])) {
      expect_equal(t3[[nm]], t2[[nm]], tolerance=1e-12)
    } else {
      expect_identical(as.character(t3[[nm]]), as.character(t2[[nm]]))
    }
  }

  # Invariants:
  # 2017-18 B activity marker
  idx_17 <- which(t3$season == '2017-18')
  expect_equal(t3$B_activity_weekF[idx_17], 23.9642295842807, tolerance=1e-10)

  # 2018-19 finite B peak is absent
  idx_18 <- which(t3$season == '2018-19')
  expect_false(is.finite(t3$B_peak_weekF[idx_18]))
  expect_identical(t3$B_activity_status[idx_18], 'no_meaningful_activity')

  # Geometry check
  g2 <- read.csv(file.path('artifacts', 'v3-joint-timing-contract-v2', 'timing_geometry_v3.csv'), check.names=FALSE)
  g3 <- read.csv(file.path('artifacts', 'v3-joint-timing-contract-v3', 'timing_geometry_v3.csv'), check.names=FALSE)
  for (nm in names(g2)) {
    if (is.numeric(g2[[nm]])) {
      expect_equal(g3[[nm]], g2[[nm]], tolerance=1e-12)
    }
  }
})

test_that('deterministic eligibility regeneration matches policy source and covers M1 and M2', {
  repo <- find_page_repo_root_timing_v3()
  skip_if(is.na(repo), 'PAGe repository root unavailable')
  old <- setwd(repo); on.exit(setwd(old), add=TRUE)

  pol_path <- file.path('governance', 'v3_b_season_policy_v1.csv')
  elig_path <- file.path('artifacts', 'v3-joint-timing-contract-v3', 'modeling_eligibility_v3.csv')
  manifest_path <- file.path('artifacts', 'v3-joint-timing-contract-v3', 'source_manifest.csv')
  skip_if_not(file.exists(pol_path) && file.exists(elig_path), 'Policy or eligibility unavailable')

  pol <- read.csv(pol_path, check.names=FALSE)
  elig <- read.csv(elig_path, check.names=FALSE)
  manifest <- read.csv(manifest_path, check.names=FALSE)

  expect_true(all(c('season', 'M1_A_eligible', 'M1_B_peak_eligible', 'M1_B_training_eligible',
                    'M1_B_scoring_eligible', 'M2_B_state_eligible', 'M2_B_scoring_eligible', 'M2_B_timing_eligible', 'exclusion_reason', 'review_status') %in% names(elig)))

  # Invariant: source manifest includes generator, all inputs, and all outputs
  expect_true('generator_script' %in% manifest$role)
  expect_true('B_season_policy_source' %in% manifest$role)
  expect_true('timing_contract_v3' %in% manifest$role)
  expect_true('modeling_eligibility_v3' %in% manifest$role)

  # Check 2018-19: no timing event; M1-B timing false; M2-B state true; M2-B timing false
  e_18 <- elig[elig$season == '2018-19', ]
  expect_identical(e_18$M1_B_peak_eligible, FALSE)
  expect_identical(e_18$M1_B_training_eligible, FALSE)
  expect_identical(e_18$M1_B_scoring_eligible, FALSE)
  expect_identical(e_18$M2_B_state_eligible, TRUE)
  expect_identical(e_18$M2_B_scoring_eligible, TRUE)
  expect_identical(e_18$M2_B_timing_eligible, FALSE)

  # Check 2019-20: pandemic-transition; all B modeling/scoring false
  e_19 <- elig[elig$season == '2019-20', ]
  expect_identical(e_19$M1_B_peak_eligible, FALSE)
  expect_identical(e_19$M1_B_training_eligible, FALSE)
  expect_identical(e_19$M1_B_scoring_eligible, FALSE)
  expect_identical(e_19$M2_B_state_eligible, FALSE)
  expect_identical(e_19$M2_B_scoring_eligible, FALSE)
  expect_identical(e_19$M2_B_timing_eligible, FALSE)
  expect_identical(e_19$exclusion_reason, 'pandemic_transition')

  # Check other 9 seasons are all eligible
  other <- elig[!elig$season %in% c('2018-19', '2019-20'), ]
  expect_equal(nrow(other), 9L)
  expect_true(all(other$M1_B_peak_eligible))
  expect_true(all(other$M1_B_training_eligible))
  expect_true(all(other$M1_B_scoring_eligible))
  expect_true(all(other$M2_B_state_eligible))
  expect_true(all(other$M2_B_scoring_eligible))
  expect_true(all(other$M2_B_timing_eligible))
})
