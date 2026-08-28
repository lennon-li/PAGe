test_that("M1 reference guard reports insufficient aligned weeks", {
  aligned <- data.frame(
    newWeek = rep(seq_len(10), 2),
    season = rep(c("a", "b"), each = 10),
    y = 1, neg = 99, fit = 0.01
  )

  expect_error(
    PAGe:::.validate_m1_reference_support(aligned, k = 11L, n_weeks = 52L),
    "cannot support k_ref=11.*10 unique.*Use k_ref <= 10"
  )
  expect_silent(
    PAGe:::.validate_m1_reference_support(aligned, k = 10L, n_weeks = 52L)
  )
})

test_that("M1 tuning grid guard rejects a basis beyond its domain", {
  expect_error(
    PAGe:::.validate_m1_grid_support(
      data.frame(k_ref = c(25L, 60L), slope_window = 6L),
      n_weeks = 52L
    ),
    "unsupported.*60.*\\[2, 52\\]"
  )
})

test_that("M1 tuning fail-fast returns the candidate and fold error", {
  local_mocked_bindings(
    loso_walkforward = function(...) stop("fold-specific reference failure"),
    .package = "PAGe"
  )
  dat <- data.frame(
    season = c("a", "b"), weekF = c(1L, 1L),
    p = c(0.01, 0.02), N = c(100, 100)
  )

  expect_error(
    PAGe::tune_m1_alignment(
      allD = dat,
      params = list(p_thr = 0.005),
      grid = data.frame(k_ref = 2L),
      n_cores = 1L,
      checkpoint_dir = withr::local_tempdir(),
      verbose = FALSE,
      fail_fast = TRUE
    ),
    "specification s001 failed.*fold-specific reference failure"
  )
})
