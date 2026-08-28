# Plumbing tests for spread_method propagation through canonical callers.
# These tests inspect formal arguments and call-path forwarding only; they
# do not train models or touch holdout artifacts.

test_that("m1_walkforward_predictions exposes spread_method with between default", {
  f <- PAGe:::m1_walkforward_predictions
  fa <- formals(f)
  expect_true("spread_method" %in% names(fa))
  expect_equal(eval(fa$spread_method), c("between", "total"))
})

test_that("m1_walkforward_multi exposes spread_method with between default", {
  f <- PAGe:::m1_walkforward_multi
  fa <- formals(f)
  expect_true("spread_method" %in% names(fa))
  expect_equal(eval(fa$spread_method), c("between", "total"))
})

test_that("nested_loso_m1_train exposes spread_method with between default", {
  f <- PAGe:::nested_loso_m1_train
  fa <- formals(f)
  expect_true("spread_method" %in% names(fa))
  expect_equal(eval(fa$spread_method), c("between", "total"))
})

test_that("nested_loso_m1_test exposes spread_method with between default", {
  f <- PAGe:::nested_loso_m1_test
  fa <- formals(f)
  expect_true("spread_method" %in% names(fa))
  expect_equal(eval(fa$spread_method), c("between", "total"))
})

test_that("m1_walkforward_predictions forwards spread_method to run_alignment_prospective_multi", {
  src <- paste(deparse(body(PAGe:::m1_walkforward_predictions)), collapse = "\n")
  expect_match(src, "spread_method\\s*=\\s*spread_method", fixed = FALSE)
  expect_match(src, "run_alignment_prospective_multi", fixed = TRUE)
})

test_that("m1_walkforward_multi forwards spread_method to m1_walkforward_predictions", {
  src <- paste(deparse(body(PAGe:::m1_walkforward_multi)), collapse = "\n")
  expect_match(src, "spread_method\\s*=\\s*spread_method", fixed = FALSE)
  expect_match(src, "m1_walkforward_predictions", fixed = TRUE)
})

test_that("nested_loso_m1_train forwards spread_method to m1_walkforward_multi", {
  src <- paste(deparse(body(PAGe:::nested_loso_m1_train)), collapse = "\n")
  expect_match(src, "spread_method\\s*=\\s*spread_method", fixed = FALSE)
  expect_match(src, "m1_walkforward_multi", fixed = TRUE)
})

test_that("nested_loso_m1_test forwards spread_method to m1_walkforward_predictions", {
  src <- paste(deparse(body(PAGe:::nested_loso_m1_test)), collapse = "\n")
  expect_match(src, "spread_method\\s*=\\s*spread_method", fixed = FALSE)
  expect_match(src, "m1_walkforward_predictions", fixed = TRUE)
})

test_that("run_m1_alignment forwards spread_method from M1_PARAMS to run_alignment_prospective_multi", {
  src <- paste(deparse(body(PAGe:::run_m1_alignment)), collapse = "\n")
  expect_match(src, "spread_method\\s*=\\s*M1_PARAMS\\$spread_method", fixed = FALSE)
  expect_match(src, 'M1_PARAMS\\$spread_method\\s*%\\|\\|%\\s*"between"', fixed = FALSE)
})

test_that("build_m2 forwards spread_method from m1_params in both M1 walk-forward calls", {
  src <- paste(deparse(body(PAGe:::build_m2)), collapse = "\n")
  # Two forwarding sites: m1_walkforward_multi and m1_walkforward_predictions
  expect_match(src, 'm1_params\\$spread_method\\s*%\\|\\|%\\s*"between"', fixed = FALSE)
  # Count occurrences -- there should be at least two forwarding sites
  hits <- gregexpr('spread_method\\s*=\\s*m1_params\\$spread_method', src, perl = TRUE)
  n_forward <- sum(lengths(hits)[lengths(hits) > 0])
  expect_gte(n_forward, 2L)
})

test_that("train_m2 forwards spread_method from m1_params to m1_walkforward_multi", {
  src <- paste(deparse(body(PAGe:::train_m2)), collapse = "\n")
  expect_match(src, 'spread_method\\s*=\\s*m1_params\\$spread_method', fixed = FALSE)
  expect_match(src, "m1_walkforward_multi", fixed = TRUE)
})
