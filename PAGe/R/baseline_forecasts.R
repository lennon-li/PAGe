# Leakage-safe comparator baselines for the publication evaluation.
# These helpers emit prediction rows compatible with the PAGe outer
# prediction schema so they can be scored alongside the primary pipeline.

.baseline_clip <- function(p) {
  pmin(1 - 1e-6, pmax(1e-6, p))
}

.baseline_season_id <- function(season) {
  if (length(season) != 1L || is.na(season) ||
    !nzchar(trimws(as.character(season)))) {
    stop("`season` must be one non-empty identifier.", call. = FALSE)
  }
  trimws(as.character(season))
}

.baseline_weeks <- function(x, name) {
  if (!is.numeric(x) || !length(x) || anyNA(x) || any(!is.finite(x)) ||
    any(x < 1) || any(x != round(x))) {
    stop("`", name, "` must be whole positive week numbers.", call. = FALSE)
  }
  as.numeric(x)
}

.baseline_prepare <- function(data) {
  if (!is.data.frame(data)) {
    stop("`data` must be a data frame.", call. = FALSE)
  }
  prepare_surveillance_data(data)
}

.baseline_season_rows <- function(data, season) {
  rows <- data[data$season == season, , drop = FALSE]
  if (!nrow(rows)) {
    stop("`season` is absent from `data`.", call. = FALSE)
  }
  rows[order(rows$weekF), , drop = FALSE]
}

.baseline_grid <- function(origins, horizons) {
  data.frame(
    origin = rep(origins, each = length(horizons)),
    horizon = rep(horizons, times = length(origins))
  )
}

.baseline_target_lookup <- function(rows, target) {
  index <- match(target, rows$weekF)
  list(outcome = rows$p[index], N_lead = rows$N[index])
}

.baseline_ignition <- function(ignition, season, train_seasons, align) {
  if (is.null(ignition)) {
    if (align == "ignition") {
      stop("`align = \"ignition\"` requires a named `ignition` vector.",
        call. = FALSE
      )
    }
    return(NULL)
  }
  if (!is.numeric(ignition) || !length(ignition) || is.null(names(ignition)) ||
    anyNA(ignition) || any(!is.finite(ignition)) ||
    any(!nzchar(names(ignition)))) {
    stop("`ignition` must be a fully named numeric vector.", call. = FALSE)
  }
  if (align == "ignition") {
    missing_seasons <- setdiff(c(train_seasons, season), names(ignition))
    if (length(missing_seasons)) {
      stop(
        "`ignition` is missing season(s): ",
        paste(missing_seasons, collapse = ", "), ".",
        call. = FALSE
      )
    }
  } else if (!season %in% names(ignition)) {
    stop("`ignition` must name `season`.", call. = FALSE)
  }
  ignition
}

.baseline_calendar_mean <- function(train, target) {
  vapply(target, function(week) {
    rows <- train[train$weekF == week, , drop = FALSE]
    total <- sum(rows$N)
    if (!nrow(rows) || total <= 0) {
      return(NA_real_)
    }
    sum(rows$y) / total
  }, numeric(1))
}

.baseline_ignition_mean <- function(train, target, season, ignition) {
  seasons <- unique(train$season)
  anchors <- stats::setNames(unname(ignition[seasons]), seasons)
  vapply(target, function(week) {
    weeks <- anchors + (week - ignition[[season]])
    keep <- train$weekF == weeks[train$season]
    rows <- train[keep, , drop = FALSE]
    total <- sum(rows$N)
    if (!nrow(rows) || total <= 0) {
      return(NA_real_)
    }
    sum(rows$y) / total
  }, numeric(1))
}

#' Persistence baseline forecasts
#'
#' Forecasts the target week as the last observed positivity at or before the
#' origin week (last observation carried forward). Only observations with
#' `weekF <= origin` influence the prediction, so the baseline is leakage-safe
#' for prospective evaluation.
#'
#' @param data Canonical multi-season surveillance data.
#' @param season Single season identifier to forecast.
#' @param origins Numeric vector of whole origin weeks.
#' @param horizons Integer vector of positive forecast horizons. The target week
#'   is `origin + horizon`. Defaults to `1:2`.
#'
#' @return A data frame with one row per origin/horizon pair and columns
#'   `season`, `origin`, `target`, `horizon`, `outcome`, `prediction`,
#'   `t_since_target`, `N_lead`, and `model`. Predictions are clamped to
#'   `[1e-6, 1 - 1e-6]`. `outcome` and `N_lead` are `NA` when the target week is
#'   not observed, and `t_since_target` is `NA` because persistence does not use
#'   ignition timing.
#' @export
baseline_persistence <- function(data, season, origins, horizons = 1:2) {
  data <- .baseline_prepare(data)
  season <- .baseline_season_id(season)
  origins <- .baseline_weeks(origins, "origins")
  horizons <- .baseline_weeks(horizons, "horizons")
  rows <- .baseline_season_rows(data, season)
  observed <- rows[!is.na(rows$p), , drop = FALSE]
  grid <- .baseline_grid(origins, horizons)
  grid$target <- grid$origin + grid$horizon
  carried <- vapply(grid$origin, function(origin) {
    if (!nrow(observed)) {
      return(NA_real_)
    }
    index <- findInterval(origin, observed$weekF)
    if (index < 1L) NA_real_ else observed$p[index]
  }, numeric(1))
  target <- .baseline_target_lookup(rows, grid$target)
  data.frame(
    season = season,
    origin = grid$origin,
    target = grid$target,
    horizon = grid$horizon,
    outcome = target$outcome,
    prediction = .baseline_clip(carried),
    t_since_target = rep(NA_real_, nrow(grid)),
    N_lead = target$N_lead,
    model = "persistence",
    stringsAsFactors = FALSE
  )
}

#' Seasonal-mean baseline forecasts
#'
#' Forecasts the target week as the test-count-weighted mean positivity across
#' `train_seasons`. Calendar alignment matches the target calendar week in every
#' training season. Ignition alignment matches the training week that shares the
#' test season's offset from ignition, which requires a named `ignition` vector.
#' The test season is never used to form predictions, and it is an error for
#' `season` to appear in `train_seasons`.
#'
#' @inheritParams baseline_persistence
#' @param train_seasons Character vector of seasons contributing the seasonal
#'   mean. Must exclude `season`.
#' @param align Alignment mode, `"calendar"` (default) or `"ignition"`.
#' @param ignition Optional named numeric vector of ignition weeks keyed by
#'   season. Required for `align = "ignition"` and used for `t_since_target`
#'   when supplied. When supplied it must name every training season and
#'   `season` for ignition alignment, and at least `season` otherwise.
#'
#' @return A data frame with the same columns and clamping contract as
#'   [baseline_persistence()], with `model` set to `"seasonal_mean"` and
#'   `t_since_target` equal to `target - ignition[season]` when `ignition` is
#'   supplied, otherwise `NA`.
#' @export
baseline_seasonal_mean <- function(data, season, train_seasons, origins,
                                   horizons = 1:2,
                                   align = c("calendar", "ignition"),
                                   ignition = NULL) {
  align <- match.arg(align)
  data <- .baseline_prepare(data)
  season <- .baseline_season_id(season)
  train_seasons <- unique(trimws(as.character(train_seasons)))
  if (!length(train_seasons) || anyNA(train_seasons) ||
    any(!nzchar(train_seasons))) {
    stop("`train_seasons` must contain at least one non-empty identifier.",
      call. = FALSE
    )
  }
  if (season %in% train_seasons) {
    stop("`season` must not appear in `train_seasons`.", call. = FALSE)
  }
  missing_seasons <- setdiff(train_seasons, unique(data$season))
  if (length(missing_seasons)) {
    stop(
      "`train_seasons` are absent from `data`: ",
      paste(missing_seasons, collapse = ", "), ".",
      call. = FALSE
    )
  }
  origins <- .baseline_weeks(origins, "origins")
  horizons <- .baseline_weeks(horizons, "horizons")
  ignition <- .baseline_ignition(ignition, season, train_seasons, align)
  train <- data[data$season %in% train_seasons, , drop = FALSE]
  test <- .baseline_season_rows(data, season)
  grid <- .baseline_grid(origins, horizons)
  grid$target <- grid$origin + grid$horizon
  prediction <- if (align == "calendar") {
    .baseline_calendar_mean(train, grid$target)
  } else {
    .baseline_ignition_mean(train, grid$target, season, ignition)
  }
  target <- .baseline_target_lookup(test, grid$target)
  t_since <- if (is.null(ignition)) {
    rep(NA_real_, nrow(grid))
  } else {
    grid$target - ignition[[season]]
  }
  data.frame(
    season = season,
    origin = grid$origin,
    target = grid$target,
    horizon = grid$horizon,
    outcome = target$outcome,
    prediction = .baseline_clip(prediction),
    t_since_target = t_since,
    N_lead = target$N_lead,
    model = "seasonal_mean",
    stringsAsFactors = FALSE
  )
}
