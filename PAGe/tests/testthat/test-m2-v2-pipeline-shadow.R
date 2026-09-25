shadow_test_root <- if (file.exists("PAGe/R/m2_v2_research.R")) "PAGe" else "../.."
source(file.path(shadow_test_root, "R", "m2_v2_research.R"), local = TRUE)
source(file.path(shadow_test_root, "R", "m2_v2_c2_governed.R"), local = TRUE)
source(file.path(shadow_test_root, "R", "pipeline_runtime.R"), local = TRUE)

make_pipeline_shadow_artifact <- function() {
  seasons <- c("2012-13", "2013-14", "2014-15", "2016-17", "2017-18")
  ledger <- expand.grid(
    season = seasons, type = c("A", "B"), horizon = 1:2,
    KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE
  )
  ledger$N_target <- 1000
  ledger$p_star <- ifelse(ledger$type == "A", .04, .025)
  ledger$logit_current <- qlogis(ledger$p_star)
  ledger$growth1 <- sin(seq_len(nrow(ledger)) / 5) / 10
  ledger$growth2 <- cos(seq_len(nrow(ledger)) / 7) / 12
  ledger$y_target <- round(ledger$N_target * plogis(
    ledger$logit_current + .05 * ledger$growth1 + .03 * ledger$growth2 +
      .02 * (ledger$horizon == 2L)
  ))
  ledger$denominator_regime <- "historical_shared_flu_test_proxy"
  shapes <- expand.grid(
    season = seasons, type = c("A", "B"), tau = -5:5,
    KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE
  )
  shapes$p_norm <- plogis(-2 + .15 * shapes$tau)
  fit <- m2_v2_c2_fit(
    ledger, shapes, seasons,
    source_hashes = list(source = strrep("a", 64))
  )
  evidence <- data.frame(
    season = seasons,
    prior_seasons = vapply(seq_along(seasons), function(i) {
      paste(seasons[seq_len(i - 1L)], collapse = ";")
    }, character(1)),
    stringsAsFactors = FALSE
  )
  new_m2_v2_c2_governed_artifact(
    fit,
    provenance = list(
      source_hashes = list(source = strrep("a", 64)),
      training_data_sha256 = strrep("b", 64),
      shape_data_sha256 = strrep("c", 64)
    ),
    training_evidence = evidence
  )
}

make_pipeline_shadow_weekly <- function(season = "future") {
  week <- 18:24
  data.frame(
    season = season,
    weekF = week,
    y_A = c(35, 42, 48, 56, 65, 74, 82),
    N_A = 1000,
    p_A = c(35, 42, 48, 56, 65, 74, 82) / 1000,
    y_B = c(10, 15, 20, 25, 30, 32, 35),
    N_B = 400,
    p_B = c(10, 15, 20, 25, 30, 32, 35) / 400,
    denominator_regime = "orvt_type_specific",
    stringsAsFactors = FALSE
  )
}

testthat::test_that("pipeline shadow is unavailable without governed M2-v2", {
  got <- .run_m2_v2_pipeline_shadow(
    kit = list(), typed_weekly_data = make_pipeline_shadow_weekly(),
    current_season = "future", origin_week = 24L
  )
  testthat::expect_identical(got$status, "unavailable")
  testthat::expect_identical(got$reason, "kit_missing_m2_v2")
  testthat::expect_equal(nrow(got$predictions), 0L)
})

testthat::test_that("pipeline shadow requires an explicit typed A/B panel", {
  artifact <- make_pipeline_shadow_artifact()
  got <- .run_m2_v2_pipeline_shadow(
    kit = list(m2_v2 = artifact), typed_weekly_data = NULL,
    current_season = "future", origin_week = 24L
  )
  testthat::expect_identical(got$status, "unavailable")
  testthat::expect_identical(got$reason, "typed_ab_panel_missing")
  testthat::expect_identical(got$model_artifact_id, artifact$artifact_id)
})

testthat::test_that("pipeline shadow preserves governed B fallbacks", {
  artifact <- make_pipeline_shadow_artifact()
  b <- new_m2_v2_b_soft_timing_handoff(
    season = "future", origin_week = 24L, peak_mean = 28,
    source_artifact_id = "b-soft-test"
  )
  got <- .run_m2_v2_pipeline_shadow(
    kit = list(m2_v2 = artifact),
    typed_weekly_data = make_pipeline_shadow_weekly(),
    current_season = "future", origin_week = 24L,
    b_handoff = b
  )
  testthat::expect_identical(got$status, "governed_m2_v2_c2_shadow")
  testthat::expect_true(is.na(got$reason))
  p <- got$predictions
  b1 <- p$type == "B" & p$horizon == 1L
  b2 <- p$type == "B" & p$horizon == 2L
  testthat::expect_identical(p$pred_selected[b1], p$pred_baseline[b1])
  testthat::expect_identical(p$pred_selected[b2], p$pred_baseline[b2])
  testthat::expect_identical(p$fallback_reason[b1], "policy_b_h1_baseline")
  testthat::expect_identical(p$fallback_reason[b2], "b_gate_closed_pending_review")
  testthat::expect_identical(got$model_artifact_id, artifact$artifact_id)
})

testthat::test_that("pipeline shadow rejects mismatched season or missing origin", {
  artifact <- make_pipeline_shadow_artifact()
  weekly <- make_pipeline_shadow_weekly()
  testthat::expect_error(
    .run_m2_v2_pipeline_shadow(
      list(m2_v2 = artifact), weekly,
      current_season = "other", origin_week = 24L
    ),
    "same current season"
  )
  testthat::expect_error(
    .run_m2_v2_pipeline_shadow(
      list(m2_v2 = artifact), weekly,
      current_season = "future", origin_week = 25L
    ),
    "current origin week"
  )
})
