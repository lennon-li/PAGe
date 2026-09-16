test_that("page-v2 scoring resolves defaults, fractional edges, and completed seasons", {
  weights <- PAGe::page_scoring_weights()
  expect_equal(
    weights[c("pre_ignition", "rise", "turning", "decline")],
    list(pre_ignition = 0, rise = 2, turning = 3, decline = 1)
  )
  rows <- data.frame(
    season = "s1", target_weekF = c(9, 10, 28, 29, 33, 34),
    ignition_weekF = 10, observed_peak_weekF = 30,
    stringsAsFactors = FALSE
  )
  scored <- PAGe::page_phase_weights(rows, weights)
  expect_equal(
    scored$phase,
    c("pre_ignition", "rise", "rise", "turning", "turning", "decline")
  )
  expect_equal(scored$weight, c(0, 2, 2, 3, 3, 1))

  fractional <- data.frame(
    season = "s1",
    target_weekF = c(29.249, 29.25, 33.25, 33.251),
    ignition_weekF = 10.5, observed_peak_weekF = 30.25
  )
  expect_equal(
    PAGe::page_phase_weights(fractional, weights)$phase,
    c("rise", "turning", "turning", "decline")
  )

  completed <- data.frame(
    season = c(rep("s53", 53), rep("partial", 10)),
    weekF = c(seq_len(53), seq_len(10)),
    y = c(rep(1, 52), 8, rep(1, 10)),
    N = 10, nW_true = c(rep(53, 53), rep(53, 10))
  )
  metadata <- PAGe:::.page_scoring_metadata(completed)
  expect_equal(unique(metadata$observed_peak_weekF[metadata$season == "s53"]), 53)
  expect_true(all(is.na(metadata$observed_peak_weekF[metadata$season == "partial"])))
})

test_that("page-v2 rows emit both scoring schemes and exclude missing peaks", {
  data <- do.call(rbind, lapply(c("a", "b"), function(s) {
    data.frame(
      season = s, weekF = 1:8, y = c(1, 2, 3, 4, 5, 4, 3, 2),
      N = 20, nW_true = 8L
    )
  }))
  preds <- do.call(rbind, lapply(c("a", "b"), function(s) {
    data.frame(
      season = s, eval_weekF = 3:6, target_weekF = 4:7,
      h = 1L, m1_p_hat = .2
    )
  }))
  detector <- function(currentSeason, params, start_week) {
    list(
      ign_week_locked = 2L,
      df = data.frame(
        weekF = currentSeason$weekF,
        ignite_ok_now = currentSeason$weekF == 2L
      )
    )
  }
  rows <- PAGe:::m2_subset_make_rows(
    data, list(best_params = list()), list(), preds,
    seasons = c("a", "b"), detector = detector
  )$data
  expect_true(all(c("weight_page_v2", "weight_legacy") %in% names(rows)))
  expect_true(any(rows$weight_page_v2 != rows$weight_legacy))

  partial <- data[data$season == "a", , drop = FALSE]
  partial$nW_true <- 53L
  metadata <- PAGe:::.page_scoring_metadata(partial)
  expect_true(all(is.na(metadata$observed_peak_weekF)))
})

test_that("tau is origin-time capped and confidence scaling is explicit", {
  expect_equal(PAGe:::.m2_subset_confidence(
    data.frame(peak_ci_width = c(1, 2, NA_real_, 5)),
    "peak_ci",
    w_ref = 4
  )$scale, c(.25, .5, 1, 1))
  expect_equal(PAGe:::.m2_subset_confidence(
    data.frame(peak_ci_width = c(1, 2, NA_real_, 5)),
    "peak_ci",
    w_ref = 4
  )$missing, c(FALSE, FALSE, TRUE, FALSE))

  data <- data.frame(
    season = "a", weekF = 1:8, y = c(1, 2, 3, 4, 5, 4, 3, 2),
    N = 20, nW_true = 8L
  )
  fs <- PAGe:::m2_subset_observed_features(data[1:6, ], 2, .2)
  declaration <- list(week = 2)
  row <- PAGe:::m2_subset_runtime_feature_row(
    data, 6, declaration, .2, 1, .2,
    observed_features = fs,
    tau = 6, peak_ci_width = 2, conf_scale = "peak_ci", w_ref = 4
  )
  expect_equal(row$tau, 6)
  expect_equal(row$confidence_scale, .5)
  expect_false(row$confidence_scale_missing)

  grid <- PAGe::m2_subset_grid()
  expect_equal(nrow(grid), 686L)
  expect_true(any(grid$enabled_count == 0L))
  stage_b <- PAGe:::.m2_subset_stage_b_grid(
    grid, data.frame(spec_id = grid$id, bernoulli_nll = seq_len(nrow(grid)))
  )
  expect_equal(nrow(stage_b), 700L)
  expect_true(all(c(0L, 3L, 4L, 5L) %in% stage_b$k_tau))
  expect_true(all(c("none", "peak_ci") %in% stage_b$conf_scale))
})
