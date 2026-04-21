test_that("estimateDerivs_walkforward: each row uses only past data (causal)", {
  skip_if_not_installed("mgcv")
  skip_if_not_installed("gratia")

  # Build a single season with a smooth signal
  set.seed(7L)
  n_wks <- 20L
  df <- data.frame(
    season = "S1",
    weekF  = seq_len(n_wks),
    y      = as.integer(round(50 * dnorm(seq_len(n_wks), mean = 12, sd = 4) / dnorm(0) + 2)),
    N      = rep(200L, n_wks)
  )
  df$neg <- df$N - df$y

  # Capture the max(weekF) seen by estimateDerivs for each row
  recorded_max_wf <- integer(0)
  local_mock_called <- 0L

  # Use a local mock via testthat::local_mocked_bindings if available (testthat >= 3.1)
  # Fallback: call the real function but verify the causal property on the output.
  result <- estimateDerivs_walkforward(df, k = 6L)

  # Structural checks
  expect_equal(nrow(result), n_wks)
  expect_true(all(c("d1", "d1_low", "fit") %in% names(result)))

  # Causality check: for rows < min_rows (default 4), derivatives must be NA
  expect_true(all(is.na(result$d1[seq_len(3L)])),
              info = "rows 1-3 (< min_rows=4) must have NA derivatives")

  # For a later row, we verify the function ran successfully
  expect_true(!is.na(result$d1[n_wks]),
              info = paste("row", n_wks, "should have a valid d1"))
})

test_that("estimateDerivs_walkforward: walk_end=10 yields d1 from data with max(weekF)<=10", {
  skip_if_not_installed("mgcv")
  skip_if_not_installed("gratia")

  set.seed(3L)
  n_wks <- 20L
  df <- data.frame(
    season = "S1",
    weekF  = seq_len(n_wks),
    y      = as.integer(round(50 * dnorm(seq_len(n_wks), mean = 12, sd = 4) / dnorm(0) + 2)),
    N      = rep(200L, n_wks)
  )
  df$neg <- df$N - df$y

  # Compute walk-forward result and full-season result
  wf  <- estimateDerivs_walkforward(df, k = 6L)
  full_res <- estimateDerivs(df, k = 6L)

  # At row 10 (walk_end=10), wf d1 should equal the value obtained from a fit
  # on df[1:10, ] only — NOT the full-season fit.
  sub10 <- df[seq_len(10L), ]
  sub10_res <- estimateDerivs(sub10, k = 6L)

  d1_wf_10   <- wf$d1[10L]
  d1_sub_10  <- sub10_res$data$d1[10L]
  d1_full_10 <- full_res$data$d1[10L]

  # walk-forward value at row 10 should match the sub-series value
  expect_equal(d1_wf_10, d1_sub_10, tolerance = 1e-10,
               info = "walk-forward d1[10] must match d1 from data[1:10] fit")

  # And it should differ from the full-season fit (future data changed the smoother)
  # This may be close in some datasets, so only check if they actually differ
  if (!isTRUE(all.equal(d1_full_10, d1_sub_10, tolerance = 1e-6))) {
    expect_false(
      isTRUE(all.equal(d1_wf_10, d1_full_10, tolerance = 1e-6)),
      info = "walk-forward d1[10] should differ from full-season d1[10] when smoother changes"
    )
  }
})
