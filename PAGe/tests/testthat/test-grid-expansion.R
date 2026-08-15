test_that("boundary inspection warns and expansion preserves M1 rows", {
  tuning <- structure(
    list(
      scores = data.frame(spec_id = "s001", mae_weibull = 1),
      best = data.frame(k_ref = 20L, slope_weight = 8, mae_weibull = 1),
      grid = data.frame(
        k_ref = c(20L, 30L), slope_weight = c(8, 12),
        spec_id = c("s001", "s002")
      )
    ),
    class = "page_m1_tuning"
  )

  expect_warning(
    report <- PAGe::inspect_tuning_boundaries(tuning, stage = "M1"),
    class = "page_boundary_warning"
  )
  expect_true(all(report$decision == "expand_required"))

  expanded <- PAGe::expand_tuning_grid(
    tuning,
    stage = "M1", steps = c(k_ref = 5, slope_weight = 4)
  )
  expect_equal(expanded$spec_id[1:2], tuning$grid$spec_id)
  expect_true(any(expanded$k_ref == 15L))
  expect_true(any(expanded$slope_weight == 4))
  expect_equal(nrow(expanded), 4L)
})

test_that("M1 expansion halves spacing and stays inside the reference domain", {
  tuning <- structure(
    list(
      scores = data.frame(spec_id = "s001", mae_weibull = 1),
      best = data.frame(k_ref = 50L, slope_weight = 8, mae_weibull = 1),
      grid = data.frame(
        k_ref = c(20L, 25L, 30L, 40L, 50L),
        slope_weight = c(8, 12, 16, 20, 30),
        spec_id = paste0("s00", 1:5)
      )
    ),
    class = "page_m1_tuning"
  )

  expanded <- PAGe::expand_tuning_grid(tuning, stage = "M1")
  expect_true(any(expanded$k_ref == 52L))
  expect_true(any(expanded$slope_weight == 6))
  expect_lte(max(expanded$k_ref), 52L)
})

test_that("M1 expansion rejects an already unsupported reference basis", {
  tuning <- structure(
    list(
      scores = data.frame(spec_id = c("s001", "s002"), mae_weibull = c(1, 2)),
      best = data.frame(k_ref = 60L, slope_weight = 8, mae_weibull = 1),
      grid = data.frame(
        k_ref = c(20L, 60L), slope_weight = c(8, 12),
        spec_id = c("s001", "s002")
      )
    ),
    class = "page_m1_tuning"
  )
  expect_error(
    PAGe::expand_tuning_grid(tuning, stage = "M1"),
    "unsupported value|reference domain"
  )
})

test_that("M0 expansion halves numeric spacing and validates detector support", {
  tuning <- structure(
    list(
      best_params = list(
        cls_thr = 0.2, p_thr = 0.2, prev_thr = 0.1,
        n_consec = 2L, L = 2L, eps = 0, K_sum = 2L,
        p_sum_thr = 0.1, N_req = 3L, w_min = 1L, w_max = 4L
      ),
      grid = data.frame(
        p_thr = c(0.1, 0.2), spec_id = c("m0a", "m0b")
      )
    ),
    class = "page_m0_tuning"
  )
  expanded <- PAGe::expand_tuning_grid(tuning, stage = "M0")
  expect_true(any(abs(expanded$p_thr - 0.25) < 1e-8))
  expect_error(
    PAGe:::.validate_m0_grid_support(
      transform(tuning$grid, K_sum = 6L),
      data = data.frame(
        season = rep(c("a", "b"), each = 4), weekF = rep(1:4, 2)
      )
    ),
    "shortest training season"
  )
})

test_that("M2 expansion is additive and keeps canonical identities", {
  grid <- data.frame(
    delta = 0L, Kr = 1L, k_f = c(4L, 5L), k_e = 2L,
    alpha_state = 0.2, k_r = 0L, k_de = 0L, k_sp = 8L,
    bias_alpha = 0.05, bias_beta = 0
  )
  grid$spec_id <- PAGe:::.m2_spec_ids(grid)
  tuning <- structure(
    list(
      grid = grid,
      summary = data.frame(
        spec_id = grid$spec_id, bernoulli_nll = c(0.1, 0.2)
      ),
      best_spec_id = grid$spec_id[1],
      best_spec = as.list(grid[1, setdiff(names(grid), "spec_id"), drop = FALSE])
    ),
    class = "page_m2_tuning"
  )
  expanded <- PAGe::expand_tuning_grid(tuning, stage = "M2")
  expect_true(all(grid$spec_id %in% expanded$spec_id))
  expect_true(nrow(expanded) > nrow(grid))
  expect_equal(length(unique(expanded$spec_id)), nrow(expanded))
})

test_that("M2 checkpoint accepts an additive grid with the same context", {
  dat <- data.frame(
    season = c("2023-24", "2024-25"), weekF = c(1L, 1L),
    y = c(1L, 2L), N = c(100L, 100L)
  )
  base_grid <- data.frame(
    delta = 0L, Kr = 1L, k_f = 4L, k_e = 2L, alpha_state = 0.2,
    k_r = 0L, k_de = 0L, k_sp = 8L, bias_alpha = 0.05, bias_beta = 0
  )
  expanded_grid <- rbind(base_grid, transform(base_grid, k_f = 5L))
  m0 <- list(best_params = list(p_thr = 0.005))
  m1 <- list(m1_params = list(k_ref = 25L), ref = list(anchorWeek = 20L), hyper = list())
  base_id <- PAGe:::.m2_checkpoint_identity(dat, c("2023-24", "2024-25"), base_grid, m0, m1)
  expanded_id <- PAGe:::.m2_checkpoint_identity(dat, c("2023-24", "2024-25"), expanded_grid, m0, m1)
  path <- tempfile(fileext = ".rds")
  on.exit(unlink(path), add = TRUE)
  PAGe:::.write_m2_checkpoint(path, base_id, list(old = list(scores = data.frame())))
  expect_null(PAGe:::.read_m2_checkpoint(path, expanded_id))
  expect_identical(
    PAGe:::.read_m2_checkpoint(path, expanded_id, allow_grid_extension = TRUE),
    list(old = list(scores = data.frame()))
  )
})
