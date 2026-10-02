# Focused regressions for the round-7 review fixes.

.r7_alignment_failure_fixture <- function() {
  g <- function(u) qlogis(.008 + .22 * exp(-.5 * ((u - 27) / 5.5)^2))
  week <- 1:18
  y <- round(1500 * plogis(g(week - 3)))
  current <- data.frame(weekF = week, y = y, neg = 1500 - y)
  hyper <- list(
    TAU_BOUNDS = c(-9.006965, 12.76346),
    DELTA_BOUNDS = c(-.0962749, .05133914),
    WEEK_THRESHOLD_DELTA = 12, LAMBDA_DELTA = .1
  )
  ref <- list(
    anchorWeek = 15L,
    eta_mat = matrix(g(1:52), 52, 3),
    g_ref_fun = g,
    g_ref_mu_se = function(u) list(mu = g(u), se = rep(.05, length(u)))
  )
  ign <- list(
    ign_week_locked = 18L, iWeek_hat_locked = 18L,
    iWeek_hat_lockedF = 18
  )
  list(current = current, hyper = hyper, ref = ref, ign = ign)
}

test_that("LOSO callers preserve failed alignment origins", {
  fx <- .r7_alignment_failure_fixture()
  seasons <- c("A", "B", "S")
  dat <- do.call(rbind, lapply(seasons, function(s) {
    d <- fx$current
    d$season <- s
    d$N <- d$y + d$neg
    d$p <- d$y / d$N
    d
  }))
  local_mocked_bindings(
    estimateDerivs = function(data, ...) list(data = data),
    flagIgnition = function(df, ...) df,
    alignIgnition = function(x) do.call(rbind, x),
    estimateRef = function(...) fx$ref,
    learn_alignment_hyperparams = function(...) fx$hyper,
    run_ignition_weekly = function(...) fx$ign,
    .package = "PAGe"
  )
  common <- list(
    allD = dat, params = list(), walk_start = 18L, walk_end = 18L,
    train_seasons = c("A", "B"), test_seasons = "S", n_cores = 1L,
    verbose = FALSE, allow_scale = FALSE
  )

  single <- do.call(PAGe:::loso_walkforward, common)
  expect_equal(nrow(single$params_df), 1L)
  expect_match(single$params_df$fallback_reason, "support")
  expect_identical(single$params_df$iWeek_hat, 18L)

  weights <- list(a = list(
    temperature = .25, slope_weight = 8, slope_window = 6L,
    dynamic_temp = FALSE, dynamic_temp_pivot = 10L
  ))
  batched <- do.call(
    PAGe:::loso_walkforward_weights,
    c(common, list(weight_sets = weights))
  )
  expect_equal(nrow(batched[[1L]]$params_df), 1L)
  expect_identical(batched[[1L]]$params_df$iWeek_hat, 18L)
  expect_identical(
    batched[[1L]]$params_df$fallback_reason,
    single$params_df$fallback_reason
  )
})

test_that("public and legacy runtimes retain failed M1 origins", {
  fx <- .r7_alignment_failure_fixture()
  current <- fx$current
  current$season <- "S"
  current$N <- current$y + current$neg
  kit <- list(
    ref = fx$ref, hyper = fx$hyper,
    M1_PARAMS = PAGe:::.default_m1_params(),
    m0_params = list(),
    m2_production = list(family = "legacy")
  )
  m0 <- list(ign_out = fx$ign, iWeek_locked = 18L, iWeek_lockedF = 18)
  m1 <- suppressWarnings(PAGe::run_m1_alignment(
    kit, current, m0,
    walk_start = 18L, verbose = FALSE
  ))
  expect_identical(m1$params_df$iWeek_hat, 18L)
  expect_match(m1$params_df$fallback, "support")

  legacy_kit <- workflow_kit()
  legacy_kit$ref <- fx$ref
  legacy_kit$hyper <- fx$hyper
  local_mocked_bindings(
    make_soft_cap_fn = function(...) identity,
    .package = "PAGe"
  )
  legacy <- suppressWarnings(PAGe::run_m2_forecast(
    legacy_kit, current, m1,
    verbose = FALSE
  ))
  expect_equal(nrow(legacy$m2_preds), 2L)
  expect_true(all(!legacy$m2_preds$forecast_available))
  expect_match(legacy$m2_preds$unavailable_reason, "support")

  subset_kit <- legacy_kit
  subset_kit$best_spec <- PAGe:::m2_subset_config()
  subset_kit$m2_production <- list(
    family = PAGe:::m2_subset_family(), fit = list()
  )
  subset <- suppressWarnings(PAGe::run_m2_forecast(
    subset_kit, current, m1,
    verbose = FALSE
  ))
  expect_equal(nrow(subset$m2_preds), 2L)
  expect_true(all(!subset$m2_preds$forecast_available))
  expect_match(subset$m2_preds$unavailable_reason, "support")
})

test_that("profile curvature stays finite at a tau boundary", {
  g <- function(u) qlogis(.008 + .22 * exp(-.5 * ((u - 27) / 5.5)^2))
  t <- 1:35
  n <- rep(1000, length(t))
  y <- round(n * plogis(g(t - 9)))
  d <- data.frame(newWeek = t, y = y, neg = n - y)
  fit <- PAGe:::fit_tau_delta(
    d, g, c(-6, 6), c(0, 0),
    allow_scale = FALSE,
    week_threshold_delta = Inf, lam_delta = 0
  )
  counts <- integer()
  profile <- PAGe:::tau_profile_se(
    d,
    g_ref = function(u) {
      z <- PAGe:::.page_alignment_eval(g, u)
      counts <<- c(counts, sum(is.finite(z)))
      z
    },
    allow_scale = FALSE, tau0 = fit$tau, tau_bounds = c(-6, 6),
    support = fit$support, weights = fit$w
  )
  expect_true(is.finite(profile$se_tau))
  expect_true(all(counts == sum(fit$support)))
})

test_that("amplitude GLM uses per-observation weights for count responses", {
  g <- function(u) qlogis(.008 + .22 * exp(-.5 * ((u - 27) / 5.5)^2))
  t <- 1:35
  n <- rep(c(100, 4000), length.out = length(t))
  p <- plogis(g(t) + rep(c(-.6, .3), length.out = length(t)))
  y <- round(n * p)
  d <- data.frame(newWeek = t, y = y, neg = n - y)
  hyper <- list(
    TAU_BOUNDS = c(-6, 6), DELTA_BOUNDS = c(0, 0),
    WEEK_THRESHOLD_DELTA = Inf, LAMBDA_DELTA = 0
  )
  fit <- PAGe:::fit_tau_delta(
    d, g, hyper$TAU_BOUNDS, hyper$DELTA_BOUNDS,
    allow_scale = FALSE, week_threshold_delta = Inf, lam_delta = 0
  )
  expected <- glm(
    cbind(y[fit$support], n[fit$support] - y[fit$support]) ~
      1 + offset(g(t[fit$support] - fit$tau)),
    family = binomial(), weights = fit$w[fit$support] / n[fit$support]
  )
  out <- suppressWarnings(PAGe:::align_forecast_pipeline_dilate(
    d, g, function(u) list(mu = g(u), se = rep(.05, length(u))),
    hyper,
    allow_scale = FALSE, future_weeks = integer()
  ))
  expect_equal(out$a, coef(expected)[1L], tolerance = 1e-8)
  expect_equal(out$V_ab[1L, 1L], vcov(expected)[1L, 1L], tolerance = 1e-12)
})

test_that("delta fallback refreshes support and profile weights", {
  g <- function(u) qlogis(.008 + .22 * exp(-.5 * ((u - 27) / 5.5)^2))
  t <- 1:45
  n <- rep(1000, length(t))
  y <- round(n * plogis(g((t - 1) / 1.12)))
  d <- data.frame(newWeek = t, y = y, neg = n - y)
  hyper <- list(
    TAU_BOUNDS = c(-6, 6), DELTA_BOUNDS = c(-.2, .2),
    WEEK_THRESHOLD_DELTA = 1, LAMBDA_DELTA = 0
  )
  real_fit <- PAGe:::fit_tau_delta
  real_profile <- PAGe:::tau_profile_se
  fits <- list()
  profiles <- integer()
  local_mocked_bindings(
    fit_tau_delta = function(...) {
      out <- real_fit(...)
      fits[[length(fits) + 1L]] <<- out
      out
    },
    cov_tau_delta_from_profile = function(...) list(V = diag(NA_real_, 2L)),
    tau_profile_se = function(...) {
      args <- list(...)
      profiles <<- c(profiles, sum(args$support))
      real_profile(...)
    },
    .package = "PAGe"
  )
  out <- suppressWarnings(PAGe:::align_forecast_pipeline_dilate(
    d, g, function(u) list(mu = g(u), se = rep(.05, length(u))),
    hyper,
    allow_scale = FALSE, curvature_ratio = 0, future_weeks = 46:47
  ))
  expect_identical(out$fallback_reason, "delta_unstable_profile")
  expect_equal(sapply(fits, function(x) sum(x$support)), c(28L, 39L))
  expect_identical(profiles, c(39L, 39L))
  expect_identical(out$n_admissible, 39L)
})

test_that("nested gate validation uses its own scored seasons", {
  seasons <- c("A", "B", "C")
  training_rows <- expand.grid(
    season = seasons[1:2], h = 1:2, row = 1:2,
    stringsAsFactors = FALSE
  )
  training_rows$eval_weekF <- training_rows$row
  training_rows$target_weekF <- training_rows$eval_weekF + training_rows$h
  training_rows$lead <- factor(paste0("h", training_rows$h), levels = c("h1", "h2"))
  training_rows$m1_p <- .2
  training_rows$m1_logit <- qlogis(.2)
  training_rows$z <- 0
  training_rows$u <- 0
  training_rows$d <- 0
  training_rows$y_lead <- 20
  training_rows$N_lead <- 100
  training_rows$forecast_available <- TRUE
  training_rows$unavailable_reason <- NA_character_
  grid <- PAGe:::m2_subset_grid(k_values = 0L)
  scores <- expand.grid(
    spec_id = grid$id, season = seasons, horizon = 1:2,
    stringsAsFactors = FALSE
  )
  scores$bernoulli_nll <- 1
  scores$mae <- 1
  scores$status <- "ok"
  tuning <- structure(list(
    recipe_grid = grid,
    scoring = list(score_scale = "equal_week", scored_seasons = list(`1` = seasons, `2` = seasons)),
    alpha_state = .2,
    selection = PAGe::validate_season_selection(
      data.frame(season = seasons),
      training_seasons = seasons
    ),
    family = PAGe:::m2_subset_family(), grid = grid, scores = scores,
    training_rows = training_rows,
    selected_config = PAGe:::m2_subset_config(grid[1L, ], grid[1L, ])
  ), class = c("page_m2_subset_tuning", "page_m2_tuning", "list"))

  out <- PAGe:::.nested_gate_select_config(
    tuning, training_rows,
    training_seasons = seasons[1:2],
    grid = grid, expansion = list(enabled = FALSE)
  )
  expect_silent(PAGe:::validate_m2_tuning(out$selection))
  expect_true(all(out$selection$summary$n_seasons == 2L))
})
