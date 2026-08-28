test_that("M2 rejects a basis larger than per-lead data support", {
  d_train <- data.frame(
    post_ign = TRUE,
    lead = factor(rep(c("h1", "h2"), each = 3), levels = c("h1", "h2")),
    logit_f_eff = rep(c(-1, 0, 1), 2),
    z_ema = rep(c(-0.5, 0, 0.5), 2),
    stringsAsFactors = FALSE
  )
  spec <- PAGe::stage2_make_spec(k_f = 4L, k_e = 0L)
  expect_error(
    PAGe:::.validate_m2_spec_support(d_train, spec),
    "requests k_logit_f_eff=4"
  )
})

test_that("M0 detector rejects unsupported windows before rolling gates", {
  dat <- data.frame(
    season = rep(c("a", "b"), each = 4),
    weekF = rep(1:4, 2),
    p_cls_p = 0.2, p = 0.1, y = 1, N = 10
  )
  expect_error(
    PAGe:::detectIgnitionBySeason_M0v2(
      dat,
      params = list(
        n_consec = 5L, L = 2L, K_sum = 2L, N_req = 3L,
        w_min = 1L, w_max = 4L
      ),
      verbose = FALSE
    ),
    "shortest training season"
  )
})

test_that("M0 weekly runtime accepts intentionally short prospective snapshots", {
  dat <- data.frame(
    season = "a", weekF = 1L, p_cls_p = 0.2, p = 0.1, y = 1, N = 10
  )
  out <- PAGe:::detectIgnition_oneSeason(
    dat,
    params = list(
      n_consec = 5L, L = 2L, K_sum = 5L, N_req = 3L,
      w_min = 13L, w_max = 26L
    )
  )
  expect_true(is.list(out))
  expect_identical(as.integer(out$iWeek_hat), 26L)
})
