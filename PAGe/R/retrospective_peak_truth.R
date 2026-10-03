#' Derive retrospective continuous peak truth from a completed season using GAM
#'
#' This procedure is for retrospective truth construction only. It must never
#' be used with partial held-out-season data at runtime.
#'
#' @param data One completed season of surveillance data accepted by
#'   `prepare_surveillance_data()`.
#' @param season Optional season identifier.
#' @param k Basis dimension for the cubic regression spline.
#' @param grid_step Decimal-week resolution used to locate the fitted maximum.
#' @return A list containing the fitted model, continuous peak week, fitted
#'   peak positivity, grid predictions, and provenance.
retrospective_gam_peak_truth <- function(data, season = NULL, k = 8L, grid_step = 0.01) {
  if (!requireNamespace("mgcv", quietly = TRUE)) stop("Package `mgcv` is required.", call. = FALSE)
  d <- prepare_surveillance_data(data, season = if ("season" %in% names(data)) NULL else season)
  if (!is.null(season)) d <- d[d$season == season, , drop = FALSE]
  seasons <- unique(d$season)
  if (length(seasons) != 1L) stop("Exactly one completed season is required.", call. = FALSE)
  d <- d[order(d$weekF), , drop = FALSE]
  if (nrow(d) < 10L) stop("Too few observations for retrospective peak truth.", call. = FALSE)
  if (length(k) != 1L || !is.numeric(k) || k != floor(k) || k < 4L || k >= nrow(d)) stop("`k` must be an integer >=4 and < number of observations.", call. = FALSE)
  if (length(grid_step) != 1L || !is.numeric(grid_step) || !is.finite(grid_step) || grid_step <= 0 || grid_step > 0.25) stop("`grid_step` must be in (0, 0.25].", call. = FALSE)

  fit <- mgcv::gam(cbind(y, N - y) ~ s(weekF, bs = "cr", k = k), data = d,
                   family = stats::quasibinomial(), method = "REML")
  grid <- data.frame(weekF = seq(min(d$weekF), max(d$weekF), by = grid_step))
  grid$fitted_p <- as.numeric(stats::predict(fit, newdata = grid, type = "response"))
  i <- which.max(grid$fitted_p)
  structure(list(
    season = seasons[[1L]],
    peak_week_decimal = grid$weekF[[i]],
    peak_fitted_p = grid$fitted_p[[i]],
    k = as.integer(k),
    grid_step = grid_step,
    fit = fit,
    grid = grid,
    provenance = list(
      method = "retrospective-gam-peak-v1",
      coordinate_version = .expert_timing_coordinate_version,
      data_snapshot_id = digest::digest(d, algo = "sha256"),
      fitted_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
    )
  ), class = "page_retrospective_peak_truth_v1")
}

#' Audit peak-location sensitivity across simple GAM basis dimensions
#'
#' @param data One completed season of surveillance data accepted by
#'   \code{prepare_surveillance_data()}.
#' @param season Optional season identifier.
#' @param k_values Integer vector of cubic regression spline basis dimensions to
#'   compare.
#' @param grid_step Decimal-week resolution used to locate each fitted maximum.
#' @return A data frame of peak-location sensitivity summaries.
retrospective_gam_peak_sensitivity <- function(data, season = NULL, k_values = c(5L, 6L, 8L, 10L), grid_step = 0.01) {
  fits <- lapply(k_values, function(k) retrospective_gam_peak_truth(data, season = season, k = k, grid_step = grid_step))
  out <- data.frame(
    season = vapply(fits, function(x) x$season, character(1)),
    k = vapply(fits, function(x) x$k, integer(1)),
    peak_week_decimal = vapply(fits, function(x) x$peak_week_decimal, numeric(1)),
    peak_fitted_p = vapply(fits, function(x) x$peak_fitted_p, numeric(1)),
    stringsAsFactors = FALSE
  )
  out$peak_range_weeks <- max(out$peak_week_decimal) - min(out$peak_week_decimal)
  out
}

#' Build frozen retrospective peak truth v1 for one or more seasons
#'
#' Uses k=8 for the point estimate and k values of 5, 6, 8, and 10 to quantify
#' smoothing sensitivity. The sensitivity interval is diagnostic, not a
#' confidence interval.
#' @param data Completed surveillance data containing one or more seasons.
#' @param seasons Optional season vector. Defaults to all seasons.
#' @param grid_step Peak-location grid resolution.
#' @param ambiguity_threshold Weeks of smoothing-sensitivity range above which
#'   the peak is flagged ambiguous.
#' @return One-row-per-season data frame.
build_retrospective_peak_truth_v1 <- function(data, seasons = NULL, grid_step = 0.01,
                                              ambiguity_threshold = 1.0) {
  d <- prepare_surveillance_data(data)
  if (is.null(seasons)) seasons <- sort(unique(as.character(d$season)))
  rows <- lapply(as.character(seasons), function(s) {
    sens <- retrospective_gam_peak_sensitivity(
      d, season = s, k_values = c(5L, 6L, 8L, 10L), grid_step = grid_step
    )
    point <- sens$peak_week_decimal[sens$k == 8L]
    if (length(point) != 1L) stop("Expected exactly one k=8 peak for season ", s, ".", call. = FALSE)
    low <- min(sens$peak_week_decimal)
    high <- max(sens$peak_week_decimal)
    range <- high - low
    data.frame(
      truth_spec_version = "retrospective-gam-peak-v1-k8",
      season = s,
      peak_week_decimal = point,
      peak_sensitivity_low = low,
      peak_sensitivity_high = high,
      peak_sensitivity_range = range,
      peak_ambiguous = range > ambiguity_threshold,
      grid_step = grid_step,
      ambiguity_threshold = ambiguity_threshold,
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}
