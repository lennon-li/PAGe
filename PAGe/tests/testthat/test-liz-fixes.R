test_that("forecast availability is explicit and interpolation honors rule", {
  expect_true(is.na(PAGe:::.approx_unique(52, .2, 53, rule = 1)))
  expect_equal(PAGe:::.approx_unique(52, .2, 53, rule = 2), .2)
  contract <- PAGe:::.page_forecast_availability(
    target_weekF = c(53, 54), target_newWeek = c(53, 54), nW_true = 53L
  )
  expect_false(contract$forecast_available[1L])
  expect_identical(
    contract$unavailable_reason[1L],
    "aligned_week_outside_template_support"
  )
  expect_identical(contract$unavailable_reason[2L], "out_of_season")
})

test_that("M0 preserves a chronological week-53 prefix in both timing modes", {
  d <- data.frame(
    season = "2025-26", weekF = 1:53, y = 10, N = 100,
    stringsAsFactors = FALSE
  )
  d$y[52L] <- 10L
  d$y[53L] <- 90L
  params <- list(
    use_cls = FALSE, cls_thr = .2, p_thr = .01, prev_thr = .01,
    n_consec = 2L, L = 1L, eps = 0, K_sum = 1L,
    p_sum_thr = .01, N_req = 1L, w_min = 1L, w_max = 26L
  )
  for (timing in c("legacy", "fractional")) {
    out <- PAGe:::run_ignition_weekly(d,
      params = params,
      start_week = 51L, timing_mode = timing
    )
    expect_equal(out$df$p_now[out$df$weekF == 52L], .1)
    expect_equal(out$df$p_now[out$df$weekF == 53L], .9)
  }
})

test_that("online alignment excludes transformed coordinates outside template support", {
  g <- function(u) as.numeric(u)
  expect_true(is.na(PAGe:::.page_alignment_eval(g, c(0, 53))[1L]))
  expect_true(is.na(PAGe:::.page_alignment_eval(g, c(0, 53))[2L]))
  base <- PAGe:::safe_obj(
    par = c(0, 0, 1, 0), t = c(1, 2, 51, 52),
    y = c(1, 2, 3, 4), n = rep(10, 4), gfun = g,
    allow_scale = TRUE, lam = 0, w = rep(1, 4), min_support = 4L
  )
  # A caller-fixed common support excludes the outside row for every candidate.
  with_outside <- PAGe:::safe_obj(
    par = c(0, 0, 1, 0), t = c(1, 2, 51, 52, 60),
    y = c(1, 2, 3, 4, 10), n = rep(10, 5), gfun = g,
    allow_scale = TRUE, lam = 0, w = rep(1, 5), min_support = 4L,
    support = c(TRUE, TRUE, TRUE, TRUE, FALSE)
  )
  expect_equal(with_outside, base, tolerance = 1e-12)
  # Without a fixed support an out-of-domain required row fails the candidate
  # instead of being silently dropped.
  failed <- PAGe:::safe_obj(
      par = c(0, 0, 1, 0), t = c(1, 2, 51, 52, 60),
      y = c(1, 2, 3, 4, 10), n = rep(10, 5), gfun = g,
      allow_scale = TRUE, lam = 0, w = rep(1, 5), min_support = 4L
  )
  expect_true(is.infinite(failed) && failed > 0)
  expect_identical(attr(failed, "reason"), "reference_outside_common_support")
})

test_that("M2 subset rows retain observed unavailable targets with reasons", {
  d <- data.frame(season = "2025-26", weekF = 1:53, y = 10, N = 100)
  detector <- function(currentSeason, ...) {
    list(
      ign_week_locked = 10L, iWeek_hat_locked = 10L,
      df = data.frame(
        weekF = currentSeason$weekF,
        ignite_ok_now = currentSeason$weekF == 10L
      )
    )
  }
  preds <- data.frame(
    season = "2025-26", eval_weekF = c(20L, 52L, 52L),
    target_weekF = c(21L, 53L, 54L), h = c(1L, 1L, 2L),
    target_newWeek = c(31, 53, 54),
    m1_p_hat = c(.2, NA, NA), forecast_available = c(TRUE, FALSE, FALSE),
    unavailable_reason = c(NA, "aligned_week_outside_template_support", "out_of_season")
  )
  rows <- PAGe:::m2_subset_make_rows(
    d,
    m0 = list(best_params = list()), m1 = list(),
    m1_train_preds = preds, seasons = "2025-26", detector = detector
  )
  retained <- rows$data[rows$data$target_weekF >= 53L, , drop = FALSE]
  expect_equal(nrow(retained), 1L)
  expect_false(retained$forecast_available)
  expect_identical(
    retained$unavailable_reason,
    "aligned_week_outside_template_support"
  )
})

test_that("M1 rebuilds an M0 handoff without preprocessing metadata", {
  aligned <- data.frame(
    season = c("2023-24", "2024-25"), newWeek = c(1, 1),
    y = c(1, 2), neg = c(9, 8)
  )
  rebuilt <- aligned
  attr(rebuilt, "preprocessing") <- list(
    k_deriv = 20L, peak_weight_boost = 3, peak_weight_decay = .3
  )
  calls <- 0L
  testthat::local_mocked_bindings(
    build_m0 = function(...) {
      calls <<- calls + 1L
      list(aligned = rebuilt)
    },
    estimateRef = function(alignedD, ...) {
      list(
        dat = alignedD, g_ref_fun = function(x) x,
        pred_df = data.frame(newWeek = 1, fit = .1), anchorWeek = 20L
      )
    },
    learn_alignment_hyperparams = function(...) list(slope = 8),
    .package = "PAGe"
  )
  out <- PAGe::build_m1(
    allD = data.frame(
      season = aligned$season, weekF = aligned$newWeek,
      y = aligned$y, N = aligned$y + aligned$neg
    ),
    m0 = list(
      aligned = aligned, seasons_used = c("2023-24", "2024-25"),
      best_params = list(), manual_labels = integer(), flag_args = list()
    ),
    exclude = character(), exclude_live = FALSE, m1_params = list(k_ref = 2L)
  )
  expect_equal(calls, 1L)
  expect_identical(out$aligned_train, rebuilt)
})

test_that("undated ORVT input requires an explicit source calendar", {
  raw <- utils::read.csv(
    testthat::test_path("fixtures", "orvt_new.txt"),
    check.names = FALSE, stringsAsFactors = FALSE
  )
  raw[["Week start date"]] <- NULL
  raw[["Week end date"]] <- NULL
  path <- tempfile(fileext = ".csv")
  withr::defer(unlink(path))
  utils::write.csv(raw, path, row.names = FALSE)
  expect_error(
    PAGe::getCurrentD(path, season = "2025-26", include_predecessor = FALSE),
    "source_calendar"
  )
  source_calendar <- data.frame(
    pho_season = c("2025-26", "2025-26", "2025-26", "2025-26", "2025-26", "2026-27"),
    week = c(35L, 27L, 53L, 1L, 34L, 35L),
    week_start_date = as.Date(c(
      "2025-08-24", "2025-06-29", "2025-12-28", "2026-01-04",
      "2025-08-17", "2026-08-30"
    ))
  )
  out <- PAGe::getCurrentD(path,
    season = "2025-26",
    include_predecessor = FALSE, source_calendar = source_calendar
  )
  expect_setequal(unique(out$season), "2025-26")
})

test_that("peak_ci is estimated as a varying coefficient, not post-fit shrinkage", {
  set.seed(123)
  d <- expand.grid(week = 1:30, h = 1:2, season = c("A", "B", "C"))
  d$lead <- factor(paste0("h", d$h))
  d$tau <- seq(-6, 6, length.out = nrow(d))
  d$m1_p <- .15
  d$m1_logit <- qlogis(d$m1_p)
  d$N_lead <- 100
  d$y_lead <- rbinom(nrow(d), 100, plogis(d$m1_logit + .5 + sin(d$tau)))
  d$peak_ci_width <- rep(c(0, 1, 4, 8, NA), length.out = nrow(d))
  spec <- PAGe:::m2_subset_spec(intercept = TRUE, k_tau = 3)
  f_none <- PAGe:::m2_subset_fit(d, spec)
  spec$conf_scale <- "peak_ci"
  f_ci <- PAGe:::m2_subset_fit(d, spec)
  expect_gt(max(abs(stats::coef(f_none$fit) - stats::coef(f_ci$fit))), 1e-6)
  conf <- PAGe:::.m2_subset_confidence(
    data.frame(peak_ci_width = c(NA, 0, 2)), "peak_ci", 4
  )
  expect_equal(conf$scale, c(1, 0, .5))
  expect_equal(conf$missing, c(TRUE, FALSE, FALSE))
  expect_equal(conf$zero, c(FALSE, TRUE, FALSE))
  expect_gt(
    max(abs(
      PAGe:::m2_subset_predict(f_none, d)$correction_logit -
        PAGe:::m2_subset_predict(f_ci, d)$correction_logit
    )),
    1e-6
  )
})

test_that("alignment candidates share a fixed observation support and summed likelihood", {
  flat <- function(x) rep(qlogis(.1), length(x))
  obj <- function(tau) {
    PAGe:::safe_obj(
      c(tau, 0, 0), 1:6, c(99, 99, 10, 10, 10, 10), rep(100, 6),
      flat, FALSE, 0, rep(1, 6)
    )
  }
  expect_gte(obj(2), obj(0))
  expect_gt(obj(0), 1)
  support <- PAGe:::.page_alignment_common_support(
    1:20, rep(100, 20), c(-2, 2), c(0, 0)
  )
  expect_false(support[1])
  expect_true(support[5])
  expect_true(support[20])
})

test_that("per-row export retains unavailable rows from the scheduled ledger", {
  current <- data.frame(
    season = "2025-26", weekF = 1:6, y = c(1, 2, 3, 4, 5, 6), N = 10
  )
  predictions <- data.frame(
    weekF = c(1L, 2L), lead = 1:2, p_hat = c(.2, NA), m1_p = c(.21, .22)
  )
  ledger <- PAGe:::.replay_forecast_ledger(
    predictions, current, "2025-26",
    ignition_week = 1
  )
  expect_true(any(ledger$forecast_status == "not_emitted"))
  expect_true(any(ledger$forecast_status == "prediction_failed"))
  expect_identical(
    ledger$unavailable_reason[ledger$forecast_status == "prediction_failed"],
    "forecast_prediction_failed"
  )
  rows <- PAGe:::.nested_ledger_export(list(forecast_ledger = ledger), current)
  expect_equal(nrow(rows), nrow(ledger))
  expect_true(any(!rows$forecast_available))
  expect_true(any(rows$forecast_available))
  expect_true(all(nzchar(rows$unavailable_reason[!rows$forecast_available])))
  expect_true(all(is.na(rows$unavailable_reason[rows$forecast_available])))
  scored <- data.frame(
    season = "2025-26", origin = 1, target = 2, horizon = 1,
    outcome = .2, m1_prediction = .2, m2_prediction = .25,
    t_since_target = 1, N_lead = 10,
    forecast_available = FALSE, unavailable_reason = "forecast_not_emitted"
  )
  out <- PAGe:::.nested_scoring_export(scored, current)
  expect_false(out$forecast_available)
  expect_identical(out$unavailable_reason, "forecast_not_emitted")
})
