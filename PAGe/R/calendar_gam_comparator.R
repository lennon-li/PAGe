# Calendar-week binomial GAM comparator from the publication protocol.
# Emits prediction rows compatible with the PAGe outer prediction schema so the
# comparator can be scored alongside the primary pipeline.

.calendar_gam_pairs <- function(rows, horizons) {
  rows <- rows[order(rows$weekF), , drop = FALSE]
  pieces <- lapply(horizons, function(h) {
    lag_idx <- match(rows$weekF - 1, rows$weekF)
    target_idx <- match(rows$weekF + h, rows$weekF)
    z <- stats::qlogis(.baseline_clip(rows$p))
    dz <- z - stats::qlogis(.baseline_clip(rows$p[lag_idx]))
    keep <- !is.na(lag_idx) & !is.na(target_idx) &
      is.finite(z) & is.finite(dz) &
      !is.na(rows$N[target_idx]) & rows$N[target_idx] > 0
    data.frame(
      season = rows$season[keep],
      horizon = h,
      target_week = rows$weekF[keep] + h,
      z = z[keep],
      dz = dz[keep],
      y = rows$y[target_idx[keep]],
      N = rows$N[target_idx[keep]],
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, pieces)
}

.calendar_gam_fit <- function(design, k_week, k_signal) {
  design$horizon <- factor(design$horizon, levels = c(1L, 2L))
  formula <- stats::as.formula(sprintf(
    paste0(
      "cbind(y, N - y) ~ horizon + ",
      "s(target_week, bs = 'cc', k = %d, by = horizon) + ",
      "s(z, bs = 'tp', k = %d, by = horizon) + ",
      "s(dz, bs = 'tp', k = %d, by = horizon)"
    ),
    k_week, k_signal, k_signal
  ))
  fit <- mgcv::gam(
    formula,
    data = design,
    family = stats::binomial(),
    method = "REML",
    knots = list(target_week = c(0.5, 53.5))
  )
  if (!isTRUE(fit$converged)) {
    stop("Calendar GAM did not converge.", call. = FALSE)
  }
  fit
}

#' Calendar-week binomial GAM comparator
#'
#' Primary statistical comparator from the frozen publication protocol:
#'
#' > 3. **Calendar-week binomial GAM.** This is the primary comparator. Fit a
#' >    denominator-aware GAM with horizon, a cyclic within-season-week smooth,
#' >    current logit positivity, one-week logit change, and horizon-specific
#' >    smooth effects. It receives no M0 decision, aligned week, template, peak
#' >    estimate, or alignment uncertainty. Candidate basis dimensions are
#' >    `k_week = 6, 8, 10` and `k_signal = 4, 6, 8`; selection follows
#' >    Section 2.2.
#'
#' Leakage control follows the protocol's weekly-replay rule:
#'
#' > Current season observations cannot be added to a model-fitting dataset
#' > during weekly replay.
#'
#' The GAM is therefore fitted once on `train_seasons` alone and reused for
#' every origin in `season`. The target season contributes only origin-time
#' prediction features observed at or before each origin (`weekF <= origin`):
#' its current logit positivity and one-week logit change. No future
#' observation enters either the fit or the features. This is the conservative
#' reading of the protocol; see Details.
#'
#' @details
#' The design follows the frozen sidecar implementation in
#' `scripts/publication_comparator_helpers.R`: a binomial GAM on
#' `cbind(y, N - y)` with a factor `horizon` main effect, a cyclic
#' (`bs = "cc"`) smooth of within-season target week and thin-plate
#' (`bs = "tp"`) smooths of the current logit positivity `z` and one-week
#' logit change `dz`, all with horizon-specific `by` effects and cyclic knots
#' `c(0.5, 53.5)`. The fit always uses horizons 1 and 2 so the horizon factor is
#' fully identified; `horizons` only selects which rows are returned.
#'
#' The protocol defines candidate basis dimensions `k_week = 6, 8, 10` and
#' `k_signal = 4, 6, 8`, selected by the Section 2.2 inner leave-one-season-out
#' replay. That selection is a separate tuning concern; this function fits one
#' frozen configuration supplied by the caller (default `k_week = 8`,
#' `k_signal = 6`).
#'
#' Ambiguities resolved conservatively: (1) the protocol forbids adding the
#' current season to a model-fitting dataset during weekly replay, so fitting
#' uses `train_seasons` only even though the target season's pre-origin
#' observations are available as features; and (2) the comparator receives no
#' M0 decision, so `t_since_target` is always `NA`.
#'
#' @param data Canonical multi-season surveillance data.
#' @param season Single season identifier to forecast.
#' @param train_seasons Character vector of outer training seasons contributing
#'   the GAM fit. Must exclude `season`.
#' @param origins Numeric vector of whole origin weeks.
#' @param horizons Integer vector of forecast horizons, a subset of `1:2`.
#'   Defaults to `1:2`.
#' @param k_week Positive integer cyclic basis dimension for within-season
#'   target week. Protocol candidates are `6, 8, 10`; default `8`.
#' @param k_signal Positive integer basis dimension for the `z` and `dz`
#'   smooths. Protocol candidates are `4, 6, 8`; default `6`.
#'
#' @return A data frame with one row per origin/horizon pair and columns
#'   `season`, `origin`, `target`, `horizon`, `outcome`, `prediction`,
#'   `t_since_target`, `N_lead`, and `model`, with `model` set to
#'   `"calendar_gam"` and predictions clamped to `[1e-6, 1 - 1e-6]`. `outcome`
#'   and `N_lead` are `NA` when the target week is not observed, and
#'   `t_since_target` is always `NA`. Predictions are `NA` when the origin or
#'   its one-week lag is not observed in `season`.
#' @export
baseline_calendar_gam <- function(data, season, train_seasons, origins,
                                  horizons = 1:2, k_week = 8L,
                                  k_signal = 6L) {
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
  if (any(!horizons %in% c(1, 2))) {
    stop("`horizons` must be a subset of `1:2`.", call. = FALSE)
  }
  k_week <- .baseline_weeks(k_week, "k_week")
  k_signal <- .baseline_weeks(k_signal, "k_signal")
  train <- data[data$season %in% train_seasons, , drop = FALSE]
  design <- do.call(rbind, lapply(train_seasons, function(s) {
    .calendar_gam_pairs(train[train$season == s, , drop = FALSE], c(1L, 2L))
  }))
  if (!nrow(design)) {
    stop("Calendar GAM has no training origin/horizon pairs.",
      call. = FALSE
    )
  }
  fit <- .calendar_gam_fit(design, k_week, k_signal)
  rows <- .baseline_season_rows(data, season)
  grid <- .baseline_grid(origins, horizons)
  grid$target <- grid$origin + grid$horizon
  origin_idx <- match(grid$origin, rows$weekF)
  lag_idx <- match(grid$origin - 1, rows$weekF)
  z <- stats::qlogis(.baseline_clip(rows$p[origin_idx]))
  dz <- z - stats::qlogis(.baseline_clip(rows$p[lag_idx]))
  valid <- is.finite(z) & is.finite(dz)
  newdata <- data.frame(
    horizon = factor(grid$horizon, levels = c(1L, 2L)),
    target_week = grid$target,
    z = z,
    dz = dz
  )
  prediction <- rep(NA_real_, nrow(grid))
  if (any(valid)) {
    prediction[valid] <- as.numeric(stats::predict(
      fit,
      newdata = newdata[valid, , drop = FALSE],
      type = "response"
    ))
  }
  target <- .baseline_target_lookup(rows, grid$target)
  data.frame(
    season = season,
    origin = grid$origin,
    target = grid$target,
    horizon = grid$horizon,
    outcome = target$outcome,
    prediction = .baseline_clip(prediction),
    t_since_target = rep(NA_real_, nrow(grid)),
    N_lead = target$N_lead,
    model = "calendar_gam",
    stringsAsFactors = FALSE
  )
}
