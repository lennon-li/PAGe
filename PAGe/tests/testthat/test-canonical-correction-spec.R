test_that("locked v16 correction settings resolve canonically", {
  spec <- PAGe:::.default_m2_spec()
  resolved <- PAGe:::.resolve_correction_spec(spec)

  expect_equal(resolved$bias_alpha, 0.05)
  expect_equal(resolved$bias_beta, 0)
  expect_equal(resolved$bias_alpha_high, 0.7)
  expect_equal(resolved$same_sign_threshold, 2L)
  expect_identical(resolved$post_peak_action, "use_m1")
})

test_that("canonical correction settings fail closed and legacy use is explicit", {
  expect_error(
    PAGe:::.resolve_correction_spec(list(bias_alpha = 0.05)),
    "bias_beta"
  )
  expect_error(
    PAGe:::.resolve_correction_spec(list(bias_alpha = 2, bias_beta = 0)),
    "bias_alpha"
  )
  expect_warning(
    legacy <- PAGe:::.resolve_correction_spec(list(), compatibility = "legacy"),
    "Legacy compatibility"
  )
  expect_equal(legacy$bias_alpha, 0.2)
  expect_equal(legacy$bias_beta, 0)
})

test_that("runtime and frozen LOSO use the same correction resolver", {
  spec <- PAGe:::.default_m2_spec()
  loso <- PAGe:::.resolve_correction_spec(spec)
  runtime <- PAGe:::.resolve_correction_spec(spec)

  expect_identical(loso, runtime)
})

test_that("adaptive correction switches after two same-sign transitions", {
  correction <- PAGe:::.resolve_correction_spec(PAGe:::.default_m2_spec())
  state <- PAGe:::.new_bias_correction_state()

  first <- PAGe:::.update_bias_correction(state, residual = 1, correction = correction)
  second <- PAGe:::.update_bias_correction(first$state, residual = 1, correction = correction)
  third <- PAGe:::.update_bias_correction(second$state, residual = 1, correction = correction)

  expect_equal(first$alpha, 0.05)
  expect_equal(second$alpha, 0.05)
  expect_equal(third$alpha, 0.7)
  expect_equal(third$state$consec_same_sign, 2L)
})

test_that("assemble_kit uses every locked M1 default and stores correction metadata", {
  m0 <- list(best_params = list(ok = TRUE))
  m1 <- list(
    ref = list(pred_df = data.frame(newWeek = 1L, fit = 0)),
    hyper = list()
  )
  m2_model <- list(
    spec = PAGe:::.default_m2_spec(), fit = "fit", feature_ranges = list(),
    m1_train_preds = data.frame(), training_seasons = "2024-25",
    spec_version = "v16_fresh"
  )

  kit <- PAGe::assemble_kit(m0, m1, m2_model)

  expect_identical(kit$M1_PARAMS, PAGe:::.default_m1_params())
  expect_identical(
    kit$m2_production$correction_spec,
    PAGe:::.resolve_correction_spec(m2_model$spec)
  )
  expect_true(nzchar(kit$m2_production$best_spec_id))
})
