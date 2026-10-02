# PAGe v3 walk-forward report -------------------------------------------------

.page_v3_report_asset <- function(...) {
  rel <- do.call(file.path, as.list(c(...)))
  path <- system.file(rel, package = "PAGe")
  if (nzchar(path) && file.exists(path)) return(path)

  # Source-tree fallback used by package tests/development.
  src <- file.path("PAGe", "inst", rel)
  if (file.exists(src)) return(normalizePath(src, winslash = "/", mustWork = TRUE))
  stop("PAGe report asset is missing: ", rel, call. = FALSE)
}

.page_v3_report_support <- function() {
  base <- c("extdata", "v3-week12", "report-support")
  list(
    prior = utils::read.csv(
      .page_v3_report_asset(base, "walkforward_week8_11.csv"),
      stringsAsFactors = FALSE, check.names = FALSE
    ),
    intervals = utils::read.csv(
      .page_v3_report_asset(base, "forecast_intervals_week8_12.csv"),
      stringsAsFactors = FALSE, check.names = FALSE
    ),
    shape = utils::read.csv(
      .page_v3_report_asset(base, "peak_aligned_smoothed_grid.csv"),
      stringsAsFactors = FALSE, check.names = FALSE
    ),
    timing = utils::read.csv(
      .page_v3_report_asset(base, "season_timing.csv"),
      stringsAsFactors = FALSE, check.names = FALSE
    ),
    uncertainty = readRDS(
      .page_v3_report_asset(base, "report_uncertainty.rds")
    )
  )
}

.page_v3_report_html_escape <- function(x) {
  x <- as.character(x)
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  x <- gsub(">", "&gt;", x, fixed = TRUE)
  x <- gsub('"', "&quot;", x, fixed = TRUE)
  x
}

.page_v3_report_fmt_number <- function(x, digits = 0L) {
  if (length(x) != 1L || !is.finite(x)) return("Not available yet")
  formatC(x, format = "f", digits = digits, big.mark = ",")
}

.page_v3_report_fmt_week <- function(x, digits = 2L) {
  if (length(x) != 1L || !is.finite(x)) return("Not available yet")
  if (abs(x - round(x)) < 1e-10) return(paste("Week", as.integer(round(x))))
  paste("Week", formatC(x, format = "f", digits = digits))
}

.page_v3_report_m1a <- function(panel, models, origin_weekF) {
  a <- data.frame(
    season = panel$season,
    weekF = panel$weekF,
    y = panel$y_A,
    N = panel$N_A,
    p = panel$p_A,
    stringsAsFactors = FALSE
  )
  a <- a[a$weekF <= origin_weekF, , drop = FALSE]
  m0 <- detectIgnitionBySeason_M0v2_timing(
    a, models$m0_a$best_params,
    verbose = FALSE, iWeek = FALSE, validate_support = FALSE
  )
  det <- m0$by_season[1L, , drop = FALSE]
  ignited <- nrow(det) == 1L && !isTRUE(det$detection_failed[[1L]]) &&
    is.finite(det$iWeek_hat[[1L]]) && is.finite(det$iWeek_hatF[[1L]])
  if (!ignited) {
    return(list(ignited = FALSE, m0 = m0, m1 = NULL, cdf = data.frame()))
  }
  m0_result <- list(
    ign_out = m0,
    iWeek_locked = as.numeric(det$iWeek_hat[[1L]]),
    iWeek_lockedF = as.numeric(det$iWeek_hatF[[1L]]),
    overridden = FALSE
  )
  m1 <- run_m1_v2_timing(
    list(m1_v2 = models$m1_a), a, m0_result, verbose = FALSE
  )
  h <- m1$m2_handoff
  cdf <- data.frame()
  if (is.list(h) && is.data.frame(h$raw_peak_posterior) &&
      nrow(h$raw_peak_posterior) && is.finite(h$calibration_offset_week)) {
    post <- h$raw_peak_posterior
    future_week <- post$peak_week_decimal + h$calibration_offset_week
    prob_passed <- if (is.finite(h$prob_peak_passed)) h$prob_peak_passed else 0
    max_week <- max(origin_weekF + 1L, ceiling(max(future_week)))
    weeks <- seq.int(origin_weekF + 1L, max_week)
    vals <- vapply(weeks, function(w) {
      p_future <- sum(post$probability[future_week <= w])
      min(1, prob_passed + (1 - prob_passed) * p_future)
    }, numeric(1L))
    if (length(vals)) vals[[length(vals)]] <- 1
    cdf <- data.frame(weekF = weeks, cdf = vals, stringsAsFactors = FALSE)
  }
  list(ignited = TRUE, m0 = m0, m1 = m1, cdf = cdf)
}

.page_v3_report_diagnostic_forecast <- function(panel, models, origin_weekF) {
  a <- data.frame(
    season = panel$season, weekF = panel$weekF,
    y = panel$y_A, N = panel$N_A, p = panel$p_A,
    stringsAsFactors = FALSE
  )
  b <- data.frame(
    season = panel$season, weekF = panel$weekF,
    y_B = panel$y_B, N_B = panel$N_B, p_B = panel$p_B,
    stringsAsFactors = FALSE
  )
  out <- vector("list", 4L)
  k <- 0L
  for (type in c("A", "B")) {
    for (h in 1:2) {
      k <- k + 1L
      if (type == "A") {
        q <- .page_v3_m2a_forecast(models$m2_a, a, origin_weekF, h)
        pred <- q$forecast
        route <- paste0(q$route, "_diagnostic")
      } else if (origin_weekF >= .PAGE_V3_M2_MIN_ORIGIN) {
        q <- .page_v3_m2b_forecast(models$m2_b, models$m1_b, b, origin_weekF, h)
        pred <- q$forecast[[1L]]
        route <- paste0(q$route[[1L]], "_diagnostic")
      } else {
        d <- .page_v3_normalize_current(b)
        f <- .page_v3_state_features(d, origin_weekF)
        pred <- .page_v3_state_predict(models$m2_b, f, h)
        route <- if (h == 1L) "exact_B1_state_diagnostic" else "exact_B1_fallback_diagnostic"
      }
      out[[k]] <- data.frame(
        origin_weekF = origin_weekF,
        type = type,
        horizon = h,
        target_weekF = origin_weekF + h,
        forecast_pct = 100 * pred,
        route = route,
        stringsAsFactors = FALSE
      )
    }
  }
  do.call(rbind, out)
}

.page_v3_report_dynamic_interval <- function(panel, support, forecast_row) {
  type <- as.character(forecast_row$type[[1L]])
  h <- as.integer(forecast_row$horizon[[1L]])
  origin <- as.integer(forecast_row$origin_weekF[[1L]])
  route <- as.character(forecast_row$route[[1L]])
  state_route <- type == "A" || grepl("exact_B1_(state|fallback)", route)
  if (!state_route) return(NULL)

  d <- if (type == "A") {
    data.frame(
      season = panel$season, weekF = panel$weekF,
      y = panel$y_A, N = panel$N_A, p = panel$p_A,
      stringsAsFactors = FALSE
    )
  } else {
    data.frame(
      season = panel$season, weekF = panel$weekF,
      y = panel$y_B, N = panel$N_B, p = panel$p_B,
      stringsAsFactors = FALSE
    )
  }
  f <- .page_v3_state_features(d, origin)
  meta <- support$uncertainty[[type]]
  x <- c(1, as.numeric(h == 2L), f$growth1[[1L]], f$growth2[[1L]])
  names(x) <- names(meta$coefficients)
  eta <- f$logit_current[[1L]] + sum(x * meta$coefficients)
  se <- sqrt(drop(t(x) %*% meta$vcov %*% x))
  point <- stats::plogis(eta)
  ci <- stats::plogis(eta + c(-1, 1) * stats::qnorm(0.975) * se)

  target <- origin + h
  rr <- panel[panel$weekF == target, , drop = FALSE]
  pi <- c(NA_real_, NA_real_)
  n_target <- NA_real_
  if (nrow(rr) == 1L) {
    n_target <- as.numeric(rr[[paste0("N_", type)]][[1L]])
    # Report-only approximate PI. The frozen runtime is quasibinomial, so there
    # is no unique predictive distribution. Combine delta-method coefficient
    # uncertainty with conditional binomial sampling variance at realized N.
    var_model <- (point * (1 - point) * se)^2
    var_obs <- point * (1 - point) / n_target
    sd_pred <- sqrt(var_model + var_obs)
    pi <- pmin(1, pmax(0, point + c(-1, 1) * stats::qnorm(0.975) * sd_pred))
  }
  data.frame(
    origin_weekF = origin,
    type = type,
    horizon = h,
    target_weekF = target,
    point_pct = 100 * point,
    ci_lo_pct = 100 * ci[[1L]],
    ci_hi_pct = 100 * ci[[2L]],
    pi_lo_pct = 100 * pi[[1L]],
    pi_hi_pct = 100 * pi[[2L]],
    target_N = n_target,
    stringsAsFactors = FALSE
  )
}

.page_v3_report_replace <- function(x, token, value) {
  gsub(token, value, x, fixed = TRUE)
}

#' Render the PAGe v3 walk-forward HTML report
#'
#' Generates the same interactive A/B/A+B walk-forward report used by the
#' governed 2026-27 Week-12 shadow workflow. The report includes current hero
#' metrics, historical origin diagnostics, A/B forecast uncertainty, the Flu A
#' peak CDF/hazard views, and the peak-normalized full-season M1 shape view.
#'
#' The frozen forecasting release is not modified. Historical shapes,
#' origin-vintage Week 8-11 diagnostics, and covariance metadata used only for
#' report uncertainty/visualization are shipped separately as report-support
#' assets under `inst/extdata/v3-week12/report-support`.
#'
#' @param data A canonical typed A/B panel, an OLIS `.RData` snapshot, or a
#'   local official ORVT CSV accepted by [page_v3_forecast()].
#' @param season Optional season label. Required where [page_v3_forecast()]
#'   requires it (for example an ORVT CSV path).
#' @param origins Integer origin weeks to expose as report tabs. Defaults to
#'   Weeks 8 through the latest available origin.
#' @param output_file Destination HTML file. Parent directories are created.
#' @param self_contained Logical. When `TRUE` (default), embeds the Plotly
#'   JavaScript runtime so the report has no network dependency. When `FALSE`,
#'   the report references the Plotly CDN.
#' @param strict Passed to [page_v3_forecast()] and the typed-panel validator.
#'
#' @return Invisibly, the normalized path to the generated HTML report.
page_v3_walkforward_report <- function(data,
                                       season = NULL,
                                       origins = NULL,
                                       output_file = "PAGe_walkforward_report.html",
                                       self_contained = TRUE,
                                       strict = TRUE) {
  if (!is.logical(self_contained) || length(self_contained) != 1L || is.na(self_contained)) {
    stop("`self_contained` must be TRUE or FALSE.", call. = FALSE)
  }
  panel_info <- .page_v3_panel(data, season = season, strict = strict)
  panel <- panel_info$data
  season <- panel_info$season
  current_origin <- max(panel$weekF)
  if (current_origin < 8L) stop("Walk-forward report requires at least Week 8.", call. = FALSE)

  if (is.null(origins)) origins <- seq.int(8L, current_origin)
  if (!is.numeric(origins) || any(!is.finite(origins)) || any(origins != as.integer(origins))) {
    stop("`origins` must contain finite integer weeks.", call. = FALSE)
  }
  origins <- sort(unique(as.integer(origins)))
  origins <- origins[origins >= 8L & origins <= current_origin & origins %in% panel$weekF]
  if (!length(origins) || !current_origin %in% origins) {
    stop("`origins` must include the latest observed origin.", call. = FALSE)
  }

  support <- .page_v3_report_support()
  models <- page_v3_models()
  current <- page_v3_forecast(
    panel, season = season, origin_weekF = current_origin, strict = strict
  )

  current_pred <- current$forecasts[, c(
    "origin_weekF", "type", "horizon", "forecast_pct", "route", "timing_reason"
  ), drop = FALSE]
  current_pred$target_weekF <- current_pred$origin_weekF + current_pred$horizon
  current_pred <- current_pred[, c(
    "origin_weekF", "type", "horizon", "target_weekF",
    "forecast_pct", "route", "timing_reason"
  ), drop = FALSE]

  prior_origins <- setdiff(origins, current_origin)
  prior_parts <- list()
  for (w in prior_origins) {
    bundled <- support$prior[support$prior$origin_weekF == w, , drop = FALSE]
    if (nrow(bundled) == 4L) {
      prior_parts[[length(prior_parts) + 1L]] <- bundled
    } else {
      prior_parts[[length(prior_parts) + 1L]] <-
        .page_v3_report_diagnostic_forecast(panel, models, w)
    }
  }
  prior <- if (length(prior_parts)) do.call(rbind, prior_parts) else support$prior[0, , drop = FALSE]

  m1a <- .page_v3_report_m1a(panel, models, current_origin)
  cdf <- m1a$cdf

  shape <- support$shape[, intersect(c("season", "weekF", "p_smooth"), names(support$shape)), drop = FALSE]
  timing <- support$timing[, intersect(
    c("season", "ignition_week_decimal", "peak_week_decimal"), names(support$timing)
  ), drop = FALSE]

  interval_parts <- list()
  all_forecasts <- rbind(
    prior[, intersect(names(prior), c("origin_weekF", "type", "horizon", "target_weekF", "forecast_pct", "route")), drop = FALSE],
    current_pred[, c("origin_weekF", "type", "horizon", "target_weekF", "forecast_pct", "route"), drop = FALSE]
  )
  for (i in seq_len(nrow(all_forecasts))) {
    r <- all_forecasts[i, , drop = FALSE]
    exact <- support$intervals[
      support$intervals$origin_weekF == r$origin_weekF &
        support$intervals$type == r$type &
        support$intervals$horizon == r$horizon,
      , drop = FALSE
    ]
    if (nrow(exact) == 1L && abs(exact$point_pct[[1L]] - r$forecast_pct[[1L]]) < 1e-9) {
      interval_parts[[length(interval_parts) + 1L]] <- exact
    } else {
      q <- .page_v3_report_dynamic_interval(panel, support, r)
      if (!is.null(q)) interval_parts[[length(interval_parts) + 1L]] <- q
    }
  }
  intervals <- if (length(interval_parts)) do.call(rbind, interval_parts) else data.frame()

  # A+B is a display aggregation of two separately fitted component models.
  # Its model-mean CI uses independent component model uncertainty unless a
  # justified cross-model covariance is supplied. Shared-denominator sampling
  # dependence belongs to the predictive layer and requires a compatible
  # denominator contract.
  aggregate_intervals <- list()
  keys <- unique(all_forecasts[, c("origin_weekF", "horizon", "target_weekF"), drop = FALSE])
  for (i in seq_len(nrow(keys))) {
    key <- keys[i, , drop = FALSE]
    ff <- all_forecasts[
      all_forecasts$origin_weekF == key$origin_weekF &
        all_forecasts$horizon == key$horizon &
        all_forecasts$type %in% c("A", "B"),
      , drop = FALSE
    ]
    ii <- intervals[
      intervals$origin_weekF == key$origin_weekF &
        intervals$horizon == key$horizon &
        intervals$type %in% c("A", "B"),
      , drop = FALSE
    ]
    if (nrow(ff) != 2L || nrow(ii) != 2L) next
    ff <- ff[match(c("A", "B"), ff$type), , drop = FALSE]
    ii <- ii[match(c("A", "B"), ii$type), , drop = FALSE]
    if (anyNA(ff$type) || anyNA(ii$type)) next
    agg <- aggregate_strata(
      estimate = stats::setNames(ff$forecast_pct / 100, ff$type),
      lower = stats::setNames(ii$ci_lo_pct / 100, ii$type),
      upper = stats::setNames(ii$ci_hi_pct / 100, ii$type),
      method = "sum",
      dependence = "independent",
      bounds = c(0, 1)
    )
    aggregate_intervals[[length(aggregate_intervals) + 1L]] <- data.frame(
      origin_weekF = key$origin_weekF,
      horizon = key$horizon,
      target_weekF = key$target_weekF,
      estimate_pct = 100 * agg$estimate,
      ci_lo_pct = 100 * agg$lower,
      ci_hi_pct = 100 * agg$upper,
      dependence = "independent_model_mean",
      stringsAsFactors = FALSE
    )
  }
  aggregate_intervals <- if (length(aggregate_intervals)) {
    do.call(rbind, aggregate_intervals)
  } else {
    data.frame()
  }

  panel_json <- panel[, intersect(
    c("weekF", "week_end_date", "y_A", "N_A", "p_A", "y_B", "N_B", "p_B"),
    names(panel)
  ), drop = FALSE]
  if (!"week_end_date" %in% names(panel_json)) panel_json$week_end_date <- NA_character_

  payload <- list(
    panel = panel_json,
    prior = prior,
    pred = current_pred,
    cdf = cdf,
    shape = shape,
    histTiming = timing,
    intervals = intervals,
    aggregateIntervals = aggregate_intervals
  )
  payload_json <- jsonlite::toJSON(
    payload, dataframe = "rows", auto_unbox = TRUE, digits = 16, na = "string"
  )

  cur <- panel[panel$weekF == current_origin, , drop = FALSE]
  fA <- current_pred[current_pred$type == "A", , drop = FALSE]
  fB <- current_pred[current_pred$type == "B", , drop = FALSE]
  fA <- fA[order(fA$horizon), , drop = FALSE]
  fB <- fB[order(fB$horizon), , drop = FALSE]

  monA <- current$monitoring$A
  monB <- current$monitoring$B$m1
  a_ignited <- isTRUE(monA$m0$ignited)
  a_timing <- isTRUE(monA$m1$available)
  b_timing <- isTRUE(monB$available)

  latest_date <- if ("week_end_date" %in% names(cur) && !is.na(cur$week_end_date[[1L]])) {
    d <- as.Date(cur$week_end_date[[1L]])
    sub("^0", "", format(d, "%d %b %Y"))
  } else {
    paste0("Week ", current_origin)
  }

  a_interval <- if (a_timing && is.finite(monA$m1$peak_q05_weekF) && is.finite(monA$m1$peak_q95_weekF)) {
    paste0(
      formatC(monA$m1$peak_q05_weekF, format = "f", digits = 2), "-",
      formatC(monA$m1$peak_q95_weekF, format = "f", digits = 2)
    )
  } else "Not available yet"

  b_peak <- if (b_timing && is.finite(monB$peak_mean_weekF)) {
    .page_v3_report_fmt_week(monB$peak_mean_weekF)
  } else "Not available yet"

  template <- paste(
    readLines(.page_v3_report_asset("report", "v3_walkforward_report_template.html"), warn = FALSE),
    collapse = "\n"
  )
  if (self_contained) {
    plotly_js <- system.file(
      "htmlwidgets", "lib", "plotlyjs", "plotly-latest.min.js",
      package = "plotly"
    )
    if (!nzchar(plotly_js) || !file.exists(plotly_js)) {
      stop("Could not locate the installed Plotly JavaScript runtime.", call. = FALSE)
    }
    plotly_script <- paste0(
      "<script>", paste(readLines(plotly_js, warn = FALSE), collapse = "\n"), "</script>"
    )
  } else {
    plotly_script <- '<script src="https://cdn.plot.ly/plotly-2.25.2.min.js"></script>'
  }

  title <- paste0("PAGe ", season, " Flu Season Walk-Forward Report -- Week ", current_origin)
  subtitle <- paste0("Prospective surveillance summary and model diagnostics through ", latest_date)
  tokens <- list(
    "__PLOTLY_SCRIPT__" = plotly_script,
    "__PAGE_DATA_JSON__" = as.character(payload_json),
    "__ORIGIN_NUM__" = as.character(current_origin),
    "__WEEKS_JSON__" = as.character(jsonlite::toJSON(origins, auto_unbox = FALSE)),
    "__HTML_DOC_TITLE__" = .page_v3_report_html_escape(title),
    "__REPORT_TITLE__" = .page_v3_report_html_escape(title),
    "__REPORT_SUBTITLE__" = .page_v3_report_html_escape(subtitle),
    "__SEASON__" = .page_v3_report_html_escape(season),
    "__ORIGIN__" = as.character(current_origin),
    "__LATEST_DATE__" = .page_v3_report_html_escape(latest_date),
    "__A_POS__" = paste0(formatC(100 * cur$p_A[[1L]], format = "f", digits = 3), "%"),
    "__A_Y__" = .page_v3_report_fmt_number(cur$y_A[[1L]]),
    "__A_N__" = .page_v3_report_fmt_number(cur$N_A[[1L]]),
    "__A_IGNITION__" = if (a_ignited) .page_v3_report_fmt_week(monA$m0$ignition_weekF) else "Not available yet",
    "__A_IGNITION_DETAIL__" = if (a_ignited) "M0 detected" else "M0 not detected",
    "__A_PEAK__" = if (a_timing) .page_v3_report_fmt_week(monA$m1$peak_mean_weekF) else "Not available yet",
    "__A_PEAK_DETAIL__" = if (a_timing) "M1 active" else "M1 timing unavailable",
    "__A_INTERVAL__" = a_interval,
    "__A_INTERVAL_DETAIL__" = if (a_timing) "Flu weeks" else "M1 timing unavailable",
    "__A_FORECAST__" = if (nrow(fA) == 2L) paste0(
      formatC(fA$forecast_pct[[1L]], format = "f", digits = 3), " / ",
      formatC(fA$forecast_pct[[2L]], format = "f", digits = 3), "%"
    ) else "Not available yet",
    "__A_FORECAST_DETAIL__" = if (nrow(fA) == 2L) paste0(
      "Weeks ", fA$target_weekF[[1L]], " / ", fA$target_weekF[[2L]]
    ) else "Forecast unavailable",
    "__B_POS__" = paste0(formatC(100 * cur$p_B[[1L]], format = "f", digits = 3), "%"),
    "__B_Y__" = .page_v3_report_fmt_number(cur$y_B[[1L]]),
    "__B_N__" = .page_v3_report_fmt_number(cur$N_B[[1L]]),
    "__B_IGNITION__" = if (b_timing && is.finite(monB$activity_weekF)) .page_v3_report_fmt_week(monB$activity_weekF) else "Not available yet",
    "__B_IGNITION_DETAIL__" = if (b_timing) "B activity detected" else "No B timing event",
    "__B_PEAK__" = b_peak,
    "__B_PEAK_DETAIL__" = if (b_timing) "M1-B timing active" else "M1-B timing unavailable",
    "__B_INTERVAL__" = "Not available yet",
    "__B_INTERVAL_DETAIL__" = "M1-B interval unavailable",
    "__B_FORECAST__" = if (nrow(fB) == 2L) paste0(
      formatC(fB$forecast_pct[[1L]], format = "f", digits = 4), " / ",
      formatC(fB$forecast_pct[[2L]], format = "f", digits = 4), "%"
    ) else "Not available yet",
    "__B_FORECAST_DETAIL__" = if (nrow(fB) == 2L) paste0(
      "Weeks ", fB$target_weekF[[1L]], " / ", fB$target_weekF[[2L]]
    ) else "Forecast unavailable"
  )
  html <- template
  for (nm in names(tokens)) html <- .page_v3_report_replace(html, nm, tokens[[nm]])
  unresolved <- names(tokens)[vapply(names(tokens), function(tok) grepl(tok, html, fixed = TRUE), logical(1L))]
  if (length(unresolved)) {
    stop("Unresolved report template token(s): ", paste(unresolved, collapse = ", "), call. = FALSE)
  }

  output_file <- normalizePath(output_file, winslash = "/", mustWork = FALSE)
  dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)
  writeLines(html, output_file, useBytes = TRUE)
  invisible(output_file)
}
