# Causal test-volume trend shadow candidate for the M2-A A1 state model.

.m2_ntrend_logit <- function(p) {
  stats::qlogis(pmin(pmax(as.numeric(p), 1e-6), 1 - 1e-6))
}

.m2_ntrend_prepare <- function(weekly_data, windows = 0:4, min_origin_week = 13L) {
  d <- as.data.frame(weekly_data)
  req <- c("season", "weekF", "y", "N")
  miss <- setdiff(req, names(d))
  if (length(miss)) stop("M2-Ntrend data are missing: ", paste(miss, collapse = ", "), call. = FALSE)
  if (!is.numeric(d$weekF) || !is.numeric(d$y) || !is.numeric(d$N) ||
      any(!is.finite(d$weekF)) || any(!is.finite(d$y)) || any(!is.finite(d$N)) ||
      any(d$N <= 0) || any(d$y < 0) || any(d$y > d$N)) {
    stop("M2-Ntrend data contain invalid week/count values.", call. = FALSE)
  }
  windows <- sort(unique(as.integer(windows)))
  if (!length(windows) || anyNA(windows) || any(windows < 0L) || any(windows > 8L)) {
    stop("`windows` must be unique integers in [0, 8].", call. = FALSE)
  }
  d$season <- as.character(d$season)
  d$weekF <- as.integer(d$weekF)
  d$y <- as.numeric(d$y)
  d$N <- as.numeric(d$N)
  if (!"denominator_regime" %in% names(d)) d$denominator_regime <- "unspecified"
  d$denominator_regime <- as.character(d$denominator_regime)
  d <- d[order(d$season, d$weekF), , drop = FALSE]
  if (anyDuplicated(d[c("season", "weekF")])) stop("M2-Ntrend data require unique season/weekF rows.", call. = FALSE)

  rows <- list()
  for (s in sort(unique(d$season))) {
    z <- d[d$season == s, , drop = FALSE]
    week_to_i <- stats::setNames(seq_len(nrow(z)), z$weekF)
    p_star <- (z$y + 0.5) / (z$N + 1)
    lg <- .m2_ntrend_logit(p_star)
    ln <- log(z$N)
    for (i in seq_len(nrow(z))) {
      w <- z$weekF[i]
      if (w < as.integer(min_origin_week)) next
      i1 <- unname(week_to_i[as.character(w - 1L)])
      i2 <- unname(week_to_i[as.character(w - 2L)])
      if (is.na(i1) || is.na(i2)) next
      base <- list(
        season = s, origin_week = w, p_star = p_star[i], logit_current = lg[i],
        growth1 = lg[i] - lg[i1], growth2 = (lg[i] - lg[i2]) / 2,
        denominator_regime = z$denominator_regime[i]
      )
      for (nw in windows[windows > 0L]) {
        j <- unname(week_to_i[as.character(w - nw)])
        base[[paste0("ntrend_w", nw)]] <- if (is.na(j)) NA_real_ else (ln[i] - ln[j]) / nw
      }
      for (h in 1:2) {
        j <- unname(week_to_i[as.character(w + h)])
        if (is.na(j)) next
        row <- as.data.frame(base, stringsAsFactors = FALSE)
        row$horizon <- h
        row$target_week <- w + h
        row$y_target <- z$y[j]
        row$N_target <- z$N[j]
        row$p_target <- z$y[j] / z$N[j]
        rows[[length(rows) + 1L]] <- row
      }
    }
  }
  if (!length(rows)) stop("M2-Ntrend preparation produced no forecast rows.", call. = FALSE)
  out <- do.call(rbind, rows)
  out$horizon <- as.integer(out$horizon)
  out$horizon_f <- factor(paste0("h", out$horizon), levels = c("h1", "h2"))
  out
}

.m2_ntrend_formula <- function(window) {
  window <- as.integer(window)
  rhs <- "horizon_f + growth1 + growth2"
  if (window > 0L) rhs <- paste(rhs, "+ ntrend")
  stats::as.formula(paste0(
    "cbind(y_target, N_target - y_target) ~ ", rhs, " + offset(logit_current)"
  ))
}

.m2_ntrend_fit_one <- function(train, window) {
  x <- train
  if (window > 0L) {
    nm <- paste0("ntrend_w", as.integer(window))
    if (!nm %in% names(x)) stop("Missing N-trend feature `", nm, "`.", call. = FALSE)
    x$ntrend <- x[[nm]]
    x <- x[is.finite(x$ntrend), , drop = FALSE]
  }
  if (length(unique(x$season)) < 2L || nrow(x) < 20L) return(NULL)
  suppressWarnings(stats::glm(.m2_ntrend_formula(window), data = x, family = stats::quasibinomial()))
}

.m2_ntrend_score <- function(fit, test, window) {
  if (is.null(fit) || !nrow(test)) return(NULL)
  x <- test
  if (window > 0L) {
    nm <- paste0("ntrend_w", as.integer(window))
    x$ntrend <- x[[nm]]
    x <- x[is.finite(x$ntrend), , drop = FALSE]
  }
  if (!nrow(x)) return(NULL)
  p <- pmin(pmax(as.numeric(stats::predict(fit, newdata = x, type = "response")), 1e-9), 1 - 1e-9)
  ll <- stats::dbinom(x$y_target, size = x$N_target, prob = p, log = TRUE)
  data.frame(
    season = x$season, origin_week = x$origin_week, target_week = x$target_week,
    horizon = x$horizon, denominator_regime = x$denominator_regime,
    window = as.integer(window), p_target = x$p_target, p_hat = p,
    abs_error_pp = 100 * abs(p - x$p_target), nll = -ll,
    stringsAsFactors = FALSE
  )
}

.m2_ntrend_summary <- function(scores) {
  keys <- unique(scores[c("window", "horizon")])
  rows <- lapply(seq_len(nrow(keys)), function(i) {
    z <- scores[scores$window == keys$window[i] & scores$horizon == keys$horizon[i], , drop = FALSE]
    data.frame(window = keys$window[i], horizon = keys$horizon[i], n_rows = nrow(z),
               n_seasons = length(unique(z$season)), mean_nll = mean(z$nll),
               mae_pp = mean(z$abs_error_pp), stringsAsFactors = FALSE)
  })
  by_h <- do.call(rbind, rows)
  overall <- do.call(rbind, lapply(sort(unique(scores$window)), function(w) {
    z <- scores[scores$window == w, , drop = FALSE]
    data.frame(window = w, n_rows = nrow(z), n_seasons = length(unique(z$season)),
               mean_nll = mean(z$nll), mae_pp = mean(z$abs_error_pp), stringsAsFactors = FALSE)
  }))
  list(overall = overall[order(overall$window), , drop = FALSE], by_horizon = by_h[order(by_h$window, by_h$horizon), , drop = FALSE])
}

#' Tune a causal test-volume trend for the M2-A state forecast
#'
#' Evaluates causal log-test-volume slopes over a discrete lookback grid. Window
#' zero is the explicit OFF/null model. Selection uses held-out mean binomial NLL
#' and prefers OFF whenever its NLL is within `off_tolerance` of the best score.
#' The returned artifact is shadow-only and does not alter the canonical v3 model.
#'
#' @param weekly_data Weekly A surveillance data with season, weekF, y, and N.
#' @param windows Integer lookback windows. Must include 0 to permit tuning OFF.
#' @param min_origin_week Earliest forecast origin included in evaluation.
#' @param min_chronological_train_seasons Minimum prior seasons for chronological scoring.
#' @param off_tolerance Absolute mean-NLL tolerance favoring the zero/off candidate.
#' @return A `page_m2_a_ntrend_shadow` artifact with LOSO and chronological scores.
#' @export
fit_m2_a_ntrend_shadow <- function(weekly_data, windows = 0:4, min_origin_week = 13L,
                                   min_chronological_train_seasons = 3L,
                                   off_tolerance = 1e-4) {
  windows <- sort(unique(as.integer(windows)))
  if (!0L %in% windows) stop("`windows` must include 0 so tuning can turn N-trend off.", call. = FALSE)
  if (!is.numeric(off_tolerance) || length(off_tolerance) != 1L || !is.finite(off_tolerance) || off_tolerance < 0) {
    stop("`off_tolerance` must be one non-negative finite number.", call. = FALSE)
  }
  ledger <- .m2_ntrend_prepare(weekly_data, windows, min_origin_week)
  seasons <- sort(unique(ledger$season))

  loso <- list()
  coefficient_stability <- list()
  for (s in seasons) for (w in windows) {
    fit <- .m2_ntrend_fit_one(ledger[ledger$season != s, , drop = FALSE], w)
    if (!is.null(fit) && w > 0L && "ntrend" %in% names(stats::coef(fit))) {
      b <- unname(stats::coef(fit)[["ntrend"]])
      se <- unname(sqrt(diag(stats::vcov(fit)))[["ntrend"]])
      coefficient_stability[[length(coefficient_stability) + 1L]] <- data.frame(
        window = as.integer(w), holdout = s, beta = b, se = se, z = b / se,
        stringsAsFactors = FALSE
      )
    }
    sc <- .m2_ntrend_score(fit, ledger[ledger$season == s, , drop = FALSE], w)
    if (!is.null(sc)) loso[[length(loso) + 1L]] <- sc
  }
  loso_scores <- do.call(rbind, loso)
  loso_summary <- .m2_ntrend_summary(loso_scores)
  best_nll <- min(loso_summary$overall$mean_nll)
  off_nll <- loso_summary$overall$mean_nll[loso_summary$overall$window == 0L]
  if (!length(off_nll)) stop("OFF candidate did not produce a valid LOSO score.", call. = FALSE)
  eligible <- loso_summary$overall$window[loso_summary$overall$mean_nll <= best_nll + off_tolerance]
  selected_window <- if (0L %in% eligible) 0L else min(eligible)

  chronological <- list()
  for (s in seasons) {
    prior <- seasons[seasons < s]
    if (length(prior) < as.integer(min_chronological_train_seasons)) next
    tr <- ledger[ledger$season %in% prior, , drop = FALSE]
    te <- ledger[ledger$season == s, , drop = FALSE]
    for (w in windows) {
      fit <- .m2_ntrend_fit_one(tr, w)
      sc <- .m2_ntrend_score(fit, te, w)
      if (!is.null(sc)) chronological[[length(chronological) + 1L]] <- sc
    }
  }
  chronological_scores <- if (length(chronological)) do.call(rbind, chronological) else loso_scores[0, , drop = FALSE]
  chronological_summary <- if (nrow(chronological_scores)) .m2_ntrend_summary(chronological_scores) else list(overall = data.frame(), by_horizon = data.frame())

  coefficient_stability <- if (length(coefficient_stability)) do.call(rbind, coefficient_stability) else data.frame()

  .metric <- function(summary, window, field, horizon = NULL) {
    tab <- if (is.null(horizon)) summary$overall else summary$by_horizon
    z <- tab[tab$window == window, , drop = FALSE]
    if (!is.null(horizon)) z <- z[z$horizon == horizon, , drop = FALSE]
    if (!nrow(z)) return(NA_real_)
    as.numeric(z[[field]][1L])
  }
  loso_off_mae <- .metric(loso_summary, 0L, "mae_pp")
  loso_sel_mae <- .metric(loso_summary, selected_window, "mae_pp")
  chrono_off_mae <- .metric(chronological_summary, 0L, "mae_pp")
  chrono_sel_mae <- .metric(chronological_summary, selected_window, "mae_pp")
  chrono_off_nll <- .metric(chronological_summary, 0L, "mean_nll")
  chrono_sel_nll <- .metric(chronological_summary, selected_window, "mean_nll")
  chrono_h1_off <- .metric(chronological_summary, 0L, "mae_pp", 1L)
  chrono_h1_sel <- .metric(chronological_summary, selected_window, "mae_pp", 1L)
  sel_scores <- loso_scores[loso_scores$window == selected_window, , drop = FALSE]
  off_scores <- loso_scores[loso_scores$window == 0L, , drop = FALSE]
  modern_sel <- sel_scores[sel_scores$denominator_regime == "orvt_type_specific", , drop = FALSE]
  modern_off <- off_scores[off_scores$denominator_regime == "orvt_type_specific", , drop = FALSE]
  modern_seasons <- length(unique(modern_sel$season))
  modern_nonworse <- nrow(modern_sel) > 0L && nrow(modern_off) > 0L && mean(modern_sel$abs_error_pp) <= mean(modern_off$abs_error_pp) + 1e-12
  cs <- coefficient_stability[coefficient_stability$window == selected_window, , drop = FALSE]
  sign_stable <- selected_window == 0L || (nrow(cs) == length(seasons) && (all(cs$beta < 0) || all(cs$beta > 0)))
  promotion_checks <- data.frame(
    check = c("selected_nonzero", "loso_mae_gain_ge_5pct", "chronological_nll_improves",
              "chronological_mae_nonworse", "chronological_h1_degradation_le_2pct",
              "coefficient_sign_stable", "modern_regime_nonworse", "at_least_2_modern_seasons"),
    pass = c(
      selected_window > 0L,
      is.finite(loso_off_mae) && is.finite(loso_sel_mae) && (1 - loso_sel_mae / loso_off_mae) >= 0.05,
      is.finite(chrono_off_nll) && is.finite(chrono_sel_nll) && chrono_sel_nll < chrono_off_nll,
      is.finite(chrono_off_mae) && is.finite(chrono_sel_mae) && chrono_sel_mae <= chrono_off_mae,
      is.finite(chrono_h1_off) && is.finite(chrono_h1_sel) && chrono_h1_sel <= 1.02 * chrono_h1_off,
      sign_stable, modern_nonworse, modern_seasons >= 2L
    ), stringsAsFactors = FALSE
  )
  promotion_gate <- list(
    eligible = all(promotion_checks$pass), checks = promotion_checks,
    loso_mae_relative_gain = if (is.finite(loso_off_mae)) 1 - loso_sel_mae / loso_off_mae else NA_real_,
    chronological_mae_relative_gain = if (is.finite(chrono_off_mae)) 1 - chrono_sel_mae / chrono_off_mae else NA_real_,
    chronological_nll_relative_gain = if (is.finite(chrono_off_nll)) 1 - chrono_sel_nll / chrono_off_nll else NA_real_,
    modern_seasons = modern_seasons
  )

  full_fit <- .m2_ntrend_fit_one(ledger, selected_window)
  out <- list(
    model_version = "m2-a-ntrend-shadow-v1", shadow_only = TRUE,
    windows = windows, selected_window = selected_window,
    off_tolerance = off_tolerance, min_origin_week = as.integer(min_origin_week),
    selection_metric = "LOSO mean binomial NLL; prefer OFF within tolerance",
    ledger = ledger, loso_scores = loso_scores, loso_summary = loso_summary,
    chronological_scores = chronological_scores, chronological_summary = chronological_summary,
    coefficient_stability = coefficient_stability, promotion_gate = promotion_gate,
    full_fit = full_fit
  )
  class(out) <- "page_m2_a_ntrend_shadow"
  out
}

#' Predict from an M2-A test-volume-trend shadow artifact
#'
#' Uses only observations at or before `origin_week`. If tuning selected window
#' zero, prediction is the exact A1-style state model with no volume-trend term.
#'
#' @param artifact Result of `fit_m2_a_ntrend_shadow()`.
#' @param weekly_data One-season weekly data with weekF, y, and N.
#' @param origin_week Forecast origin.
#' @param horizons Integer horizons, default 1 and 2.
#' @return Data frame of shadow predictions.
#' @export
predict_m2_a_ntrend_shadow <- function(artifact, weekly_data, origin_week, horizons = c(1L, 2L)) {
  if (!inherits(artifact, "page_m2_a_ntrend_shadow") || is.null(artifact$full_fit)) stop("Invalid M2-A N-trend shadow artifact.", call. = FALSE)
  d <- as.data.frame(weekly_data)
  if (!all(c("weekF", "y", "N") %in% names(d))) stop("`weekly_data` requires weekF, y, N.", call. = FALSE)
  d <- d[d$weekF <= as.integer(origin_week), , drop = FALSE]
  d$season <- "runtime"
  d$denominator_regime <- "runtime"
  # Add dummy future rows only to reuse the exact causal feature builder; their
  # outcomes are never read by the model.
  for (h in 1:2) if (!any(d$weekF == as.integer(origin_week) + h)) {
    d <- rbind(d, data.frame(weekF = as.integer(origin_week) + h, y = 0, N = 1,
                             season = "runtime", denominator_regime = "runtime"))
  }
  led <- .m2_ntrend_prepare(d, artifact$windows, min_origin_week = as.integer(origin_week))
  x <- led[led$origin_week == as.integer(origin_week) & led$horizon %in% as.integer(horizons), , drop = FALSE]
  if (!nrow(x)) stop("Insufficient exact weekly history for requested M2-A N-trend prediction.", call. = FALSE)
  w <- artifact$selected_window
  if (w > 0L) x$ntrend <- x[[paste0("ntrend_w", w)]]
  p <- pmin(pmax(as.numeric(stats::predict(artifact$full_fit, newdata = x, type = "response")), 1e-9), 1 - 1e-9)
  data.frame(origin_week = x$origin_week, horizon = x$horizon, forecast_pct = 100 * p,
             ntrend_window = w, ntrend_enabled = w > 0L, route = "shadow_A1_ntrend",
             stringsAsFactors = FALSE)
}
