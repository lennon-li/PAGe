test_that("template width propagates correctly to inner fitting calls", {
  captured_n_weeks <- integer(0)
  
  stub_estimateRef <- function(alignedD, exSeason, k, n_weeks, ...) {
    captured_n_weeks <<- c(captured_n_weeks, n_weeks)
    list(
      mod2 = list(gam = list()), 
      g_ref_fun = function(x) x, 
      g_ref_safe = function(x) x, 
      g_ref_mu_se = function(x) list(mu=x, se=x*0), 
      ref_df = data.frame(), 
      pred_df = data.frame(newWeek=1:n_weeks, fit=runif(n_weeks)), 
      dat = alignedD, 
      anchorWeek = 20, 
      method = "fs", 
      agg = "median",
      eta_mat = matrix(0, nrow=n_weeks, ncol=2)
    )
  }

  testthat::local_mocked_bindings(estimateRef = stub_estimateRef, .package = "PAGe")

  # 1. Drive m2_subset_correction.R's held-out reference builder (.m1_heldout_references)
  m1_stub <- list(
    aligned_train = data.frame(
      season = rep(c("2012-13", "2013-14"), each=20),
      weekF = rep(1:20, 2),
      iWeek = 10,
      y = 10, neg = 90
    ),
    m1_params = list(k_ref = 2)
  )
  tryCatch({
    PAGe:::.m1_heldout_references(m1_stub, c("2012-13", "2013-14"))
  }, error = function(e) {})
  
  expect_true(length(captured_n_weeks) > 0)
  expect_true(all(captured_n_weeks == PAGe:::.page_template_weeks()))
  
  captured_n_weeks <<- integer(0)

  # 2. Drive one m1_loso.R site (loso_walkforward)
  small_df <- data.frame(
    season = rep(c("2012-13", "2013-14"), each=30),
    weekF = rep(1:30, 2),
    y = 5,
    N = 100,
    p = 0.05
  )
  tryCatch({
    PAGe:::loso_walkforward(
      allD = small_df, 
      params = list(), 
      train_seasons = c("2012-13"), 
      test_seasons = "2013-14",
      walk_start = 20, 
      walk_end = 21,
      manual_labels = c("2012-13"=20, "2013-14"=20)
    )
  }, error = function(e) {})
  
  expect_true(length(captured_n_weeks) > 0)
  expect_true(all(captured_n_weeks == PAGe:::.page_template_weeks()))
})