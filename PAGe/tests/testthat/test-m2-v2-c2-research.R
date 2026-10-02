.page_test_ns <- asNamespace("PAGe")
m2_v2_c2_fit <- get("m2_v2_c2_fit", envir = .page_test_ns, inherits = FALSE)
m2_v2_c2_predict <- get("m2_v2_c2_predict", envir = .page_test_ns, inherits = FALSE)
validate_m2_v2_c2_research_fit <- get("validate_m2_v2_c2_research_fit", envir = .page_test_ns, inherits = FALSE)
new_m2_v2_b_soft_timing_handoff <- get("new_m2_v2_b_soft_timing_handoff", envir = .page_test_ns, inherits = FALSE)
run_m2_v2_c2_research_runtime <- get("run_m2_v2_c2_research_runtime", envir = .page_test_ns, inherits = FALSE)
.m2_v2_runtime_gate_b <- get(".m2_v2_runtime_gate_b", envir = .page_test_ns, inherits = FALSE)
validate_m1_v2_handoff <- get("validate_m1_v2_handoff", envir = .page_test_ns, inherits = FALSE)
rm(.page_test_ns)

make_m2_v2_c2_fixture <- function() {
  ledger <- expand.grid(
    season = paste0("s", 1:5), type = c("A", "B"), horizon = 1:2, origin = 1:6,
    KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE
  )
  ledger$N_target <- 1000
  ledger$p_star <- .025 + .004 * (ledger$type == "B") + .003 * (ledger$horizon == 2) + .0015 * ledger$origin
  ledger$logit_current <- qlogis(ledger$p_star)
  ledger$growth1 <- sin(seq_len(nrow(ledger)) / 7) / 10
  ledger$growth2 <- cos(seq_len(nrow(ledger)) / 9) / 12
  p_target <- plogis(ledger$logit_current + .08 * ledger$growth1 + .04 * ledger$growth2 + .03 * (ledger$horizon == 2))
  ledger$y_target <- round(ledger$N_target * p_target)
  ledger$denominator_regime <- ifelse(
    ledger$season == "s5", "orvt_type_specific", "historical_shared_flu_test_proxy"
  )
  shapes <- expand.grid(
    season = paste0("s", 1:5), type = c("A", "B"), tau = seq(-5, 5, by = .5),
    KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE
  )
  shapes$p_norm <- plogis(-2 + .2 * shapes$tau + .1 * (shapes$type == "B"))
  model <- m2_v2_c2_fit(
    ledger, shapes, training_seasons = paste0("s", 1:5),
    source_hashes = list(test_source = "abc123")
  )
  list(ledger = ledger, shapes = shapes, model = model)
}

testthat::test_that("M2-v2 C2 spec freezes distinct pooling and curve-blend weights", {
  fx <- make_m2_v2_c2_fixture()
  model <- fx$model
  testthat::expect_identical(model$spec$family, "C2")
  testthat::expect_identical(model$spec$type_pool_weight, 0.5)
  testthat::expect_identical(model$spec$curve_blend_weight, 0.5)
  testthat::expect_identical(model$spec$timing_contracts$A, "m1-v2-to-m2-v1")
  testthat::expect_identical(model$spec$timing_contracts$B, "m1-v2-b-soft-timing-provisional-v1")
  testthat::expect_identical(model$spec$b_gate_policy$version, "b-epidemic-gate-5pct-v1")
  testthat::expect_equal(
    model$denominator_regime_metadata$levels,
    c("historical_shared_flu_test_proxy", "orvt_type_specific")
  )
  testthat::expect_named(model$baseline_coefficients, c("A", "B"))
  testthat::expect_match(model$data_id, "^[0-9a-f]{64}$")
  testthat::expect_match(model$shape_id, "^[0-9a-f]{64}$")
  testthat::expect_match(model$artifact_id, "^m2v2_[0-9a-f]{64}$")
  testthat::expect_silent(validate_m2_v2_c2_research_fit(model))
})

testthat::test_that("M2-v2 C2 routes unavailable and policy-disabled timing to exact baseline", {
  model <- make_m2_v2_c2_fixture()$model
  nd <- data.frame(
    type = c("A", "A", "A", "B", "B", "B", "B"),
    horizon = c(1, 2, 2, 1, 2, 2, 2),
    p_star = .04, logit_current = qlogis(.04), growth1 = .1, growth2 = .03,
    origin_week = 24, timing_type = c("A", "A", "A", "B", "B", "B", "B"),
    timing_contract_version = c(
      rep("m1-v2-to-m2-v1", 3),
      rep("m1-v2-b-soft-timing-provisional-v1", 4)
    ),
    timing_available = c(TRUE, TRUE, FALSE, TRUE, TRUE, TRUE, FALSE),
    timing_peak = 27, timing_gate_active = c(FALSE, FALSE, FALSE, TRUE, TRUE, FALSE, TRUE),
    timing_failed = FALSE
  )
  got <- m2_v2_c2_predict(model, nd)
  testthat::expect_true(all(got$c2_applied[1:2]))
  testthat::expect_identical(got$pred_selected[3], got$pred_baseline[3])
  testthat::expect_identical(got$fallback_reason[3], "type_timing_unavailable")
  testthat::expect_identical(got$pred_selected[4], got$pred_baseline[4])
  testthat::expect_identical(got$fallback_reason[4], "policy_b_h1_baseline")
  testthat::expect_true(got$c2_applied[5])
  testthat::expect_identical(got$pred_selected[6], got$pred_baseline[6])
  testthat::expect_identical(got$fallback_reason[6], "b_timing_gate_inactive")
  testthat::expect_identical(got$pred_selected[7], got$pred_baseline[7])
  testthat::expect_identical(got$fallback_reason[7], "type_timing_unavailable")
  testthat::expect_true(all(got$model_artifact_id == model$artifact_id))
})

testthat::test_that("M2-v2 C2 rejects A timing presented as B timing", {
  model <- make_m2_v2_c2_fixture()$model
  nd <- data.frame(
    type = "B", horizon = 2, p_star = .03, logit_current = qlogis(.03),
    growth1 = .1, growth2 = .02, origin_week = 24, timing_type = "A",
    timing_contract_version = "m1-v2-to-m2-v1", timing_available = TRUE,
    timing_peak = 27, timing_gate_active = TRUE
  )
  testthat::expect_error(m2_v2_c2_predict(model, nd), "cross-type timing substitution")
})

testthat::test_that("M2-v2 C2 contract mismatch falls back exactly", {
  model <- make_m2_v2_c2_fixture()$model
  nd <- data.frame(
    type = "A", horizon = 2, p_star = .03, logit_current = qlogis(.03),
    growth1 = .1, growth2 = .02, origin_week = 24, timing_type = "A",
    timing_contract_version = "wrong-contract", timing_available = TRUE,
    timing_peak = 27, timing_gate_active = FALSE
  )
  got <- m2_v2_c2_predict(model, nd)
  testthat::expect_identical(got$pred_selected, got$pred_baseline)
  testthat::expect_identical(got$fallback_reason, "upstream_identity_mismatch")
  testthat::expect_false(got$timing_contract_valid)
})

testthat::test_that("M2-v2 C2 artifact identity detects fitted-payload mutation", {
  model <- make_m2_v2_c2_fixture()$model
  bad <- model
  bad$spec$curve_blend_weight <- 0.4
  testthat::expect_error(validate_m2_v2_c2_research_fit(bad), "artifact identity mismatch")
})

testthat::test_that("M2-v2 C2 fit rejects seasons outside explicit training universe", {
  fx <- make_m2_v2_c2_fixture()
  bad <- fx$ledger
  bad$season[1] <- "future-season"
  testthat::expect_error(
    m2_v2_c2_fit(bad, fx$shapes, training_seasons = paste0("s", 1:5)),
    "outside training_seasons"
  )
})


testthat::test_that("M2-v2 C2 identity is invariant to input row ordering", {
  fx <- make_m2_v2_c2_fixture()
  fit_a <- fx$model
  fit_b <- m2_v2_c2_fit(
    fx$ledger[nrow(fx$ledger):1, , drop = FALSE],
    fx$shapes[nrow(fx$shapes):1, , drop = FALSE],
    training_seasons = rev(paste0("s", 1:5)),
    source_hashes = list(test_source = "abc123")
  )
  testthat::expect_identical(fit_b$data_id, fit_a$data_id)
  testthat::expect_identical(fit_b$shape_id, fit_a$shape_id)
  testthat::expect_equal(fit_b$baseline_coefficients, fit_a$baseline_coefficients, tolerance = 0)
  testthat::expect_identical(fit_b$artifact_id, fit_a$artifact_id)
})


make_m2_v2_valid_a_handoff <- function(season = "current", origin = 24) {
  asof <- origin + 1
  list(
    version = "m1-v2-to-m2-v1",
    m1_v2_artifact_id = "m1-test-artifact",
    season = season,
    state = "active",
    origin_week = origin,
    asof_boundary = asof,
    activation_week = origin - 5,
    weeks_elapsed_since_activation = 6,
    weeks_to_calibrated_peak = 3,
    raw_peak_posterior = data.frame(
      peak_week_decimal = c(asof + 2, asof + 3, asof + 4),
      probability = c(.2, .6, .2)
    ),
    raw_peak_mean = asof + 3,
    calibrated_peak_mean = asof + 3,
    calibrated_mean_is_future = TRUE,
    raw_peak_q05 = asof + 2,
    raw_peak_q95 = asof + 4,
    calibrated_peak_q05 = asof + 2,
    calibrated_peak_q95 = asof + 4,
    peak_q05 = asof + 2,
    peak_q95 = asof + 4,
    interval_width_90 = 2,
    prob_peak_passed = .1,
    prob_peak_within_1w = .2,
    prob_peak_within_2w = .4,
    prob_peak_within_3w = .6,
    locked_peak_week = NA_real_,
    locked_at_origin = NA_real_,
    calibration_offset_week = 0
  )
}

make_m2_v2_runtime_weekly <- function(b_epidemic = TRUE) {
  week <- 18:24
  N_A <- rep(1000, length(week))
  y_A <- c(35, 42, 48, 56, 65, 74, 82)
  N_B <- rep(400, length(week))
  y_B <- if (b_epidemic) c(10, 15, 20, 25, 30, 32, 35) else c(1, 1, 2, 2, 3, 3, 4)
  data.frame(
    season = "current", weekF = week,
    y_A = y_A, N_A = N_A, p_A = y_A / N_A,
    y_B = y_B, N_B = N_B, p_B = y_B / N_B,
    denominator_regime = "orvt_type_specific",
    stringsAsFactors = FALSE
  )
}

testthat::test_that("research runtime adapter consumes real A handoff and gated typed B timing", {
  model <- make_m2_v2_c2_fixture()$model
  weekly <- make_m2_v2_runtime_weekly(TRUE)
  a <- make_m2_v2_valid_a_handoff()
  testthat::expect_silent(validate_m1_v2_handoff(a))
  b <- new_m2_v2_b_soft_timing_handoff(
    season = "current", origin_week = 24, peak_mean = 28,
    source_artifact_id = "b-soft-test", interval_width_90 = 3,
    prob_peak_passed = .15
  )
  got <- run_m2_v2_c2_research_runtime(model, weekly, 24, a, b)
  testthat::expect_identical(got$status, "research_shadow_only")
  testthat::expect_true(got$b_gate$active)
  testthat::expect_identical(got$b_gate$status, "active_latched")
  testthat::expect_identical(got$b_gate$activation_week, 21L)
  testthat::expect_equal(got$b_gate$trailing_positive_count, sum(head(weekly$y_B, 4)))
  p <- got$predictions
  testthat::expect_equal(nrow(p), 4)
  testthat::expect_true(all(p$c2_applied[p$type == "A"]))
  testthat::expect_false(p$c2_applied[p$type == "B" & p$horizon == 1])
  testthat::expect_identical(
    p$pred_selected[p$type == "B" & p$horizon == 1],
    p$pred_baseline[p$type == "B" & p$horizon == 1]
  )
  testthat::expect_identical(p$fallback_reason[p$type == "B" & p$horizon == 1], "policy_b_h1_baseline")
  testthat::expect_true(p$c2_applied[p$type == "B" & p$horizon == 2])
  testthat::expect_true(all(p$model_artifact_id == model$artifact_id))
})

testthat::test_that("research runtime adapter recomputes inactive B gate and falls back exactly", {
  model <- make_m2_v2_c2_fixture()$model
  weekly <- make_m2_v2_runtime_weekly(FALSE)
  b <- new_m2_v2_b_soft_timing_handoff(
    season = "current", origin_week = 24, peak_mean = 28,
    source_artifact_id = "b-soft-test"
  )
  got <- run_m2_v2_c2_research_runtime(model, weekly, 24, NULL, b)
  testthat::expect_false(got$b_gate$active)
  p <- got$predictions
  testthat::expect_true(all(!p$c2_applied[p$type == "A"]))
  testthat::expect_true(all(p$fallback_reason[p$type == "A"] == "type_timing_unavailable"))
  b2 <- p[p$type == "B" & p$horizon == 2, ]
  testthat::expect_false(b2$c2_applied)
  testthat::expect_identical(b2$pred_selected, b2$pred_baseline)
  testthat::expect_identical(b2$fallback_reason, "b_timing_gate_inactive")
})

testthat::test_that("research B timing gate remains causally latched after activity declines", {
  spec <- make_m2_v2_c2_fixture()$model$spec$b_gate_policy
  week <- 18:30
  y_B <- c(10, 15, 20, 25, 30, 32, 35, 8, 5, 3, 2, 1, 1)
  weekly <- data.frame(
    season = "current", weekF = week,
    y_B = y_B, N_B = 400, p_B = y_B / 400,
    stringsAsFactors = FALSE
  )
  gate <- .m2_v2_runtime_gate_b(weekly, 30, spec)
  testthat::expect_true(gate$active)
  testthat::expect_identical(gate$status, "active_latched")
  testthat::expect_identical(gate$activation_week, 21L)
  current <- weekly[weekly$weekF %in% 27:30, ]
  testthat::expect_lt(max(current$p_B), spec$min_trailing_max_positivity)
})

testthat::test_that("research runtime adapter marks mismatched handoff origin failed and forbids cross-type B handoff", {
  model <- make_m2_v2_c2_fixture()$model
  weekly <- make_m2_v2_runtime_weekly(TRUE)
  b_bad_origin <- new_m2_v2_b_soft_timing_handoff(
    season = "current", origin_week = 23, peak_mean = 28,
    source_artifact_id = "b-soft-test"
  )
  got <- run_m2_v2_c2_research_runtime(model, weekly, 24, NULL, b_bad_origin)
  b2 <- got$predictions[got$predictions$type == "B" & got$predictions$horizon == 2, ]
  testthat::expect_false(b2$c2_applied)
  testthat::expect_identical(b2$fallback_reason, "type_timing_failed")

  cross <- b_bad_origin
  cross$type <- "A"
  testthat::expect_error(
    run_m2_v2_c2_research_runtime(model, weekly, 24, NULL, cross),
    "cross-type timing substitution"
  )
})

testthat::test_that("research runtime requires exact recent weekly history", {
  model <- make_m2_v2_c2_fixture()$model
  weekly <- make_m2_v2_runtime_weekly(TRUE)
  weekly <- weekly[weekly$weekF != 23, ]
  testthat::expect_error(
    run_m2_v2_c2_research_runtime(model, weekly, 24),
    "exact origin, origin-1, and origin-2"
  )
})


testthat::test_that("research runtime refuses training-season leakage and unknown denominator regime", {
  model <- make_m2_v2_c2_fixture()$model
  weekly <- make_m2_v2_runtime_weekly(TRUE)
  leaked <- weekly
  leaked$season <- "s1"
  testthat::expect_error(
    run_m2_v2_c2_research_runtime(model, leaked, 24),
    "present in the M2-v2 research training artifact"
  )
  unknown <- weekly
  unknown$denominator_regime <- "future_unknown_regime"
  testthat::expect_error(
    run_m2_v2_c2_research_runtime(model, unknown, 24),
    "unsupported denominator regime"
  )
})

testthat::test_that("research fit rejects unsupported denominator regimes", {
  fx <- make_m2_v2_c2_fixture()
  bad <- fx$ledger
  bad$denominator_regime[1] <- "unknown_regime"
  testthat::expect_error(
    m2_v2_c2_fit(bad, fx$shapes, training_seasons = paste0("s", 1:5)),
    "unsupported denominator regime"
  )
})
