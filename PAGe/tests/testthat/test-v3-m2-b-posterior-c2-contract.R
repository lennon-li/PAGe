find_page_repo_root_m2b_v3 <- function() {
  candidates <- c('.', '..', '../..', '../../..')
  hit <- candidates[file.exists(file.path(candidates,'artifacts','v3-m2-b-posterior-c2-chronological-v1','overall_verdict.csv'))]
  if (!length(hit)) return(NA_character_)
  normalizePath(hit[[1]],winslash='/',mustWork=TRUE)
}

split_seasons_m2b_v3 <- function(x) {
  if (is.na(x) || !nzchar(x)) character() else strsplit(x,';',fixed=TRUE)[[1]]
}

season_start_m2b_v3 <- function(x) as.integer(substr(as.character(x),1,4))

test_that('v3 M2-B posterior C2 benchmark satisfies frozen verdict contract', {
  repo <- find_page_repo_root_m2b_v3()
  skip_if(is.na(repo),'v3 M2-B benchmark artifacts unavailable')
  out <- file.path(repo,'artifacts','v3-m2-b-posterior-c2-chronological-v1')

  verdict <- read.csv(file.path(out,'overall_verdict.csv'),check.names=FALSE)
  expect_equal(nrow(verdict),1L)
  expect_true(verdict$historically_promising[[1]])
  expect_identical(verdict$plus1_route[[1]],'exact_B1_diagnostic_only')
  expect_identical(verdict$decision[[1]],'eligible_for_v3_shadow_plus2')

  criteria <- read.csv(file.path(out,'acceptance_criteria.csv'),check.names=FALSE)
  expect_true(all(criteria$pass))
  integrity <- read.csv(file.path(out,'integrity_checks.csv'),check.names=FALSE)
  expect_true(all(integrity$pass))

  failures <- read.csv(file.path(out,'failures.csv'),check.names=FALSE)
  expect_equal(nrow(failures),0L)
})

test_that('v3 M2-B season policy and exact fallback identities are preserved', {
  repo <- find_page_repo_root_m2b_v3()
  skip_if(is.na(repo),'v3 M2-B benchmark artifacts unavailable')
  out <- file.path(repo,'artifacts','v3-m2-b-posterior-c2-chronological-v1')
  p <- read.csv(file.path(out,'per_origin_predictions.csv'),check.names=FALSE)

  expect_false(any(p$season=='2019-20'))
  z18 <- p[p$season=='2018-19',,drop=FALSE]
  expect_gt(nrow(z18),0L)
  expect_true(all(!z18$timing_available))
  expect_lt(max(abs(z18$pred_B2_posterior-z18$pred_B1)),1e-12)

  no_timing <- p[!p$timing_available,,drop=FALSE]
  expect_lt(max(abs(no_timing$pred_B2_posterior-no_timing$pred_B1)),1e-12)
  zero_support <- p[p$timing_available & p$supported_mass<=1e-15,,drop=FALSE]
  if (nrow(zero_support)) expect_lt(max(abs(zero_support$pred_B2_posterior-zero_support$pred_B1)),1e-12)
})

test_that('v3 M2-B chronological folds exclude future and ineligible B seasons', {
  repo <- find_page_repo_root_m2b_v3()
  skip_if(is.na(repo),'v3 M2-B benchmark artifacts unavailable')
  out <- file.path(repo,'artifacts','v3-m2-b-posterior-c2-chronological-v1')

  folds <- read.csv(file.path(out,'outer_fold_ledger.csv'),check.names=FALSE)
  for (i in seq_len(nrow(folds))) {
    target <- folds$target_season[[i]]
    ps <- split_seasons_m2b_v3(folds$prior_state[[i]])
    pt <- split_seasons_m2b_v3(folds$prior_timing[[i]])
    if (length(ps)) expect_true(all(season_start_m2b_v3(ps)<season_start_m2b_v3(target)))
    if (length(pt)) expect_true(all(season_start_m2b_v3(pt)<season_start_m2b_v3(target)))
    expect_false('2019-20' %in% ps)
    expect_false(any(c('2018-19','2019-20') %in% pt))
  }

  shapes <- read.csv(file.path(out,'shape_library_ledger.csv'),check.names=FALSE)
  for (i in seq_len(nrow(shapes))) {
    target <- shapes$target_season[[i]]
    bs <- split_seasons_m2b_v3(shapes$B_shape_seasons[[i]])
    if (length(bs)) expect_true(all(season_start_m2b_v3(bs)<season_start_m2b_v3(target)))
    expect_false(any(c('2018-19','2019-20') %in% bs))
  }
})

test_that('v3 M2-B plus2 improvement is broad rather than single-season', {
  repo <- find_page_repo_root_m2b_v3()
  skip_if(is.na(repo),'v3 M2-B benchmark artifacts unavailable')
  out <- file.path(repo,'artifacts','v3-m2-b-posterior-c2-chronological-v1')

  active <- read.csv(file.path(out,'active_timing_per_season.csv'),check.names=FALSE)
  a2 <- active[active$horizon==2,,drop=FALSE]
  expect_equal(nrow(a2),5L)
  expect_true(all(a2$B2_posterior_mae_pp<a2$B1_mae_pp))

  summary <- read.csv(file.path(out,'summary_metrics.csv'),check.names=FALSE)
  s2 <- summary[summary$horizon==2,,drop=FALSE]
  expect_equal(nrow(s2),1L)
  expect_gte(s2$relative_mae_gain[[1]],0.05)
  expect_lte(s2$B2_posterior_nll[[1]]-s2$B1_nll[[1]],0.001)
})

test_that('v3 M2-B perturbation and provenance checks remain green', {
  repo <- find_page_repo_root_m2b_v3()
  skip_if(is.na(repo),'v3 M2-B benchmark artifacts unavailable')
  out <- file.path(repo,'artifacts','v3-m2-b-posterior-c2-chronological-v1')

  future <- read.csv(file.path(out,'future_perturbation_checks.csv'),check.names=FALSE)
  if (nrow(future)) expect_true(all(future$pass))
  truth <- read.csv(file.path(out,'truth_target_perturbation_checks.csv'),check.names=FALSE)
  if (nrow(truth)) expect_true(all(truth$pass))

  manifest <- read.csv(file.path(out,'source_manifest.csv'),check.names=FALSE)
  panel_row <- manifest[manifest$role=='canonical_panel',,drop=FALSE]
  expect_equal(nrow(panel_row),1L)
  skip_if_not(requireNamespace('digest',quietly=TRUE))
  panel_path <- file.path(repo,panel_row$path[[1]])
  expect_identical(panel_row$sha256[[1]],digest::digest(file=panel_path,algo='sha256',serialize=FALSE))
})
