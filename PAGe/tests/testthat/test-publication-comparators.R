helper_path <- file.path("scripts", "publication_comparator_helpers.R")
if (!file.exists(helper_path)) {
  helper_path <- file.path("..", "..", "..", helper_path)
}
if (!file.exists(helper_path)) {
  testthat::skip("Repository-only publication sidecar is not installed")
}
sys.source(helper_path, envir = environment())

testthat::test_that("NLL weights trials, clips probabilities, and rejects bad rows", {
  y <- c(1, 90)
  n <- c(10, 100)
  p <- c(0.2, 0.8)
  testthat::expect_equal(pc_nll(y, n, p),
    sum(-y * log(p) - (n - y) * log1p(-p)) / sum(n))
  testthat::expect_true(is.finite(pc_nll(c(0, 1), c(1, 1), c(0, 1))))
  testthat::expect_error(pc_nll(2, 1, 0.5), "counts")
  testthat::expect_error(pc_nll(0, 0, 0.5), "counts")
  testthat::expect_error(pc_nll(0, 1, NA_real_), "probabilities")
})

testthat::test_that("features use exact origin and lag, never future outcomes", {
  d <- data.frame(season = "a", week = 1:12, y = 1:12, N = 100)
  q <- data.frame(season = "a", origin = 6L, lead = 2L)
  before <- pc_features(d, q)
  d$y[d$week > 6] <- 99
  testthat::expect_identical(pc_features(d, q), before)
  testthat::expect_equal(before$z, qlogis(0.06))
  testthat::expect_equal(before$dz, qlogis(0.06) - qlogis(0.05))
  testthat::expect_error(pc_features(d[d$week != 5, ], q), "missing origin/lag")
})

testthat::test_that("fixed comparators and analogue respect the information boundary", {
  d <- expand.grid(week = 1:12, season = c("a", "b", "target"))
  d$N <- ifelse(d$season == "b", 200, 100)
  d$y <- ifelse(d$season == "b", 20, 10)
  q <- data.frame(season = "target", origin = 6L, lead = 2L)
  train <- pc_training(d, c("a", "b"), "target")
  testthat::expect_equal(pc_naive(train, q), 30.5 / 301)
  testthat::expect_equal(pc_persistence(d, q), 0.1)
  a <- pc_analogue(train, d, q, 1L, 4L)
  testthat::expect_equal(a, 0.1)
  d$y[d$season == "target" & d$week > 6] <- 99
  testthat::expect_equal(pc_analogue(train, d, q, 1L, 4L), a)
  testthat::expect_identical(pc_training(d, c("a", "b"), "target"), train)
  testthat::expect_error(pc_training(d, c("a", "target"), "target"), "held-out")
  testthat::expect_error(pc_analogue(train, d, q, 3L, 4L), "analogue support")
  testthat::expect_error(pc_naive(train, transform(q, origin = 99)), "seasonal-naive")
})

testthat::test_that("one SE uses season scores and deterministic complexity ties", {
  grid <- data.frame(id = c("a", "b", "c"), complexity = c(1, 2, 3))
  scores <- rbind(c(0.2, 0.4, 0.6), c(0.1, 0.3, 0.5), c(0.3, 0.3, 0.3))
  selected <- pc_select(grid, scores)
  testthat::expect_equal(selected$best_id, "b")
  testthat::expect_equal(selected$id, "a")
  testthat::expect_equal(selected$threshold, 0.3 + 0.2 / sqrt(3))
  testthat::expect_error(pc_select(grid, scores * NA_real_), "finite")
})

testthat::test_that("GAM fits h1/h2 but inner selection scores only h2 common rows", {
  testthat::skip_if_not_installed("mgcv")
  d <- expand.grid(week = 1:30, season = c("a", "b", "c", "target"))
  d$N <- 100 + d$week * 10
  d$y <- round(d$N * plogis(-3 + sin(d$week / 5) +
    match(d$season, c("a", "b", "c", "target")) / 10))
  windows <- data.frame(season = rep(c("a", "b", "c", "target"), each = 8),
    origin = rep(10:17, 4), lead = 2L)
  grid <- pc_grid("calendar")
  grid <- grid[1, ]
  a <- pc_tune(d, c("a", "b", "c"), "target", windows, "calendar", grid)
  d$y[d$season == "target"] <- 0
  b <- pc_tune(d, c("a", "b", "c"), "target", windows, "calendar", grid)
  testthat::expect_equal(a$scores, b$scores)
  testthat::expect_equal(a$selection, b$selection)
  train <- pc_training(d, c("a", "b", "c"), "target")
  fit <- pc_fit_calendar(train, grid[1, ])
  q <- windows[windows$season == "a", ]
  p <- pc_predict_calendar(fit, d, q)
  testthat::expect_true(all(is.finite(p) & p > 0 & p < 1))
  testthat::expect_equal(sort(unique(pc_pairs(train)$lead)), c(1L, 2L))
  testthat::expect_equal(pc_nll(pc_targets(d, q)$y, pc_targets(d, q)$N, p),
    a$scores[1, "a"], tolerance = 0.1)
})
