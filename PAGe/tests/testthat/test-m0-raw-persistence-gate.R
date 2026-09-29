.page_test_ns <- asNamespace("PAGe")
detectIgnitionBySeason_M0v2 <- get("detectIgnitionBySeason_M0v2", envir = .page_test_ns, inherits = FALSE)
tuneIgnitionGrid_M0v2 <- get("tuneIgnitionGrid_M0v2", envir = .page_test_ns, inherits = FALSE)
.default_m0_params <- get(".default_m0_params", envir = .page_test_ns, inherits = FALSE)
.default_m0_grid <- get(".default_m0_grid", envir = .page_test_ns, inherits = FALSE)
detectIgnitionBySeason_M0v2_timing <- get("detectIgnitionBySeason_M0v2_timing", envir = .page_test_ns, inherits = FALSE)
.validate_m0_grid_support <- get(".validate_m0_grid_support", envir = .page_test_ns, inherits = FALSE)
rm(.page_test_ns)

testthat::test_that("M0 raw persistence defaults off and can block spike-collapse pattern", {
  d <- data.frame(
    season = rep("s", 5), weekF = 1:5,
    p = c(.01, .015, .02, .04, .01),
    y = c(10, 15, 20, 40, 10), N = rep(1000, 5),
    phase = c(0, 0, 0, 0, 1), stringsAsFactors = FALSE
  )
  base <- list(use_cls=FALSE, cls_thr=.2, p_thr=.005, prev_thr=.001,
               n_consec=2L, L=1L, eps=.05, K_sum=3L, p_sum_thr=.04,
               N_req=4L, w_min=1L, w_max=10L)
  open <- detectIgnitionBySeason_M0v2(d, base, verbose=FALSE, iWeek=FALSE, validate_support=FALSE)
  testthat::expect_true(open$data$cond_raw_nondec[5])

  guarded <- base; guarded$raw_nondec_n <- 3L
  blocked <- detectIgnitionBySeason_M0v2(d, guarded, verbose=FALSE, iWeek=FALSE, validate_support=FALSE)
  testthat::expect_false(blocked$data$cond_raw_nondec[5])
})

testthat::test_that("M0 tuner injects backward-compatible raw persistence default", {
  d <- data.frame(season=rep(c("a","b"),each=6),weekF=rep(1:6,2),
                  p=rep(c(.001,.002,.004,.008,.016,.03),2),
                  y=rep(c(1,2,4,8,16,30),2),N=1000,
                  phase=rep(c(0,0,0,1,1,1),2),p_cls_p=0)
  grid <- data.frame(cls_thr=.2,use_cls=FALSE,p_thr=.002,prev_thr=.001,
                     n_consec=2L,L=1L,eps=0,K_sum=3L,p_sum_thr=.01,
                     N_req=4L,w_min=1L,w_max=6L)
  tt <- data.frame(season=c("a","b"), ignition_target_weekF=c(4,4))
  got <- tuneIgnitionGrid_M0v2(ign_fit=d,grid=grid,timing_truth=tt,
                               timing_mode="fractional",verbose=FALSE,
                               iWeek=TRUE,ncores=1L)
  testthat::expect_equal(got$best_params$raw_nondec_n,1L)
  testthat::expect_equal(got$best_params$raw_drop_se_tol,0)
})


testthat::test_that("new M0-v2 defaults freeze week 12, raw-3 persistence, classifier off", {
  p <- .default_m0_params()
  testthat::expect_identical(p$use_cls, FALSE)
  testthat::expect_identical(p$w_min, 12L)
  testthat::expect_identical(p$raw_nondec_n, 3L)
  testthat::expect_equal(p$raw_drop_se_tol, 1.0)
  g <- .default_m0_grid()
  testthat::expect_true(all(g$use_cls == FALSE))
  testthat::expect_true(all(g$w_min == 12L))
  testthat::expect_true(all(g$raw_nondec_n == 3L))
  testthat::expect_true(all(g$raw_drop_se_tol == 1.0))
})


testthat::test_that("fractional M0 timing respects the eligible week window", {
  d <- data.frame(
    season = rep("s", 5), weekF = 1:5,
    p = c(.005, .005, .005, .015, .030),
    y = c(5, 5, 5, 15, 30), N = rep(1000, 5),
    phase = c(0, 0, 0, 0, 1), stringsAsFactors = FALSE
  )
  params <- list(use_cls=FALSE, cls_thr=.2, p_thr=.001, prev_thr=.001,
                 n_consec=2L, L=1L, eps=.1, K_sum=2L, p_sum_thr=.04,
                 raw_nondec_n=1L, N_req=4L, w_min=5L, w_max=6L)
  got <- detectIgnitionBySeason_M0v2_timing(
    d, params, verbose=FALSE, iWeek=FALSE, validate_support=FALSE
  )
  testthat::expect_identical(got$by_season$iWeek_hat, 5L)
  testthat::expect_gte(got$by_season$iWeek_hatF, 5)
  testthat::expect_lte(got$by_season$iWeek_hatF, 6)
  testthat::expect_equal(got$timing$eligible_window, c(w_min=5, w_max=6))
})


testthat::test_that("1-SE persistence tolerates sampling-scale dip but rejects material collapse", {
  params <- list(use_cls=FALSE, cls_thr=.2, p_thr=.001, prev_thr=.001,
                 n_consec=2L, L=1L, eps=.1, K_sum=2L, p_sum_thr=.01,
                 raw_nondec_n=3L, raw_drop_se_tol=1.0, N_req=4L,
                 w_min=1L, w_max=10L)

  mild <- data.frame(
    season='s', weekF=1:4, N=c(6000,6200,6400,6600),
    p=c(.010,.014,.01848,.01743)
  )
  mild$y <- round(mild$p*mild$N); mild$phase <- c(0,0,0,1)
  got_mild <- detectIgnitionBySeason_M0v2(mild, params, verbose=FALSE,
                                           iWeek=FALSE, validate_support=FALSE)
  testthat::expect_gt(got_mild$data$raw_drop_z[4], -1)
  testthat::expect_true(got_mild$data$raw_step_stable[4])
  testthat::expect_true(got_mild$data$cond_raw_stable[4])

  collapse <- mild
  collapse$p <- c(.010,.014,.03175,.00797)
  collapse$y <- round(collapse$p*collapse$N)
  got_bad <- detectIgnitionBySeason_M0v2(collapse, params, verbose=FALSE,
                                          iWeek=FALSE, validate_support=FALSE)
  testthat::expect_lt(got_bad$data$raw_drop_z[4], -3)
  testthat::expect_false(got_bad$data$raw_step_stable[4])
  testthat::expect_false(got_bad$data$cond_raw_stable[4])
})


testthat::test_that("M0 SE tolerance is non-negative and not probability-capped", {
  g <- data.frame(cls_thr=.2,p_thr=.002,prev_thr=.001,n_consec=2L,L=1L,
                  eps=0,K_sum=3L,p_sum_thr=.01,raw_nondec_n=3L,
                  raw_drop_se_tol=2.0,N_req=4L,w_min=1L,w_max=6L)
  testthat::expect_invisible(.validate_m0_grid_support(g))
  g$raw_drop_se_tol <- -0.1
  testthat::expect_error(.validate_m0_grid_support(g), "raw_drop_se_tol")
})
