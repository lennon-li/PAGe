# Opt-in fractional timing pipeline helpers.
#
# The legacy M0/M1/M2 functions remain the default archive path. These helpers
# carry numeric ignition coordinates while preserving integer weekly data and
# the raw detector bracket.

.timing_v2_crossing <- function(signals, raw_week, threshold, score_col = "p_cls_p",
                                gate_col = "ignite_ok") {
  if (!is.data.frame(signals) || !nrow(signals)) {
    return(list(
      estimate = as.numeric(raw_week), bracket = c(raw_week, raw_week),
      method = "integer_fallback"
    ))
  }
  w <- as.numeric(signals$weekF)
  score <- as.numeric(signals[[score_col]])
  gate <- as.logical(signals[[gate_col]])
  hit <- which(gate %in% TRUE)[1L]
  if (is.na(hit) || !is.finite(raw_week)) {
    return(list(
      estimate = as.numeric(raw_week),
      bracket = c(as.numeric(raw_week), as.numeric(raw_week)),
      method = "integer_fallback"
    ))
  }
  prev <- which(seq_along(w) < hit & is.finite(w) & is.finite(score) & score < threshold)
  prev <- if (length(prev)) prev[length(prev)] else NA_integer_
  if (is.na(prev) || !is.finite(score[hit]) || score[hit] <= score[prev] ||
    score[prev] >= threshold || score[hit] < threshold) {
    return(list(
      estimate = as.numeric(w[hit]),
      bracket = c(as.numeric(w[hit]), as.numeric(w[hit])),
      method = "integer_fallback"
    ))
  }
  estimate <- w[prev] + (threshold - score[prev]) /
    (score[hit] - score[prev]) * (w[hit] - w[prev])
  list(
    estimate = min(max(estimate, w[prev]), w[hit]),
    bracket = c(w[prev], w[hit]),
    method = "linear_detector_score_crossing",
    threshold = threshold,
    score_col = score_col
  )
}

#' Detect ignition with an opt-in fractional week estimate
#'
#' Runs the existing prospective M0 detector and interpolates the first
#' adjacent classifier-probability crossing of the class threshold. Weekly
#' observations and the legacy integer estimate are retained; the decimal
#' estimate is in \code{iWeek_hatF}.
#'
#' @param ign_fit Data frame, data.table, or fitIgnition result.
#' @param params M0 detector parameters.
#' @param ... Arguments passed to \code{detectIgnitionBySeason_M0v2()}.
#' @return The detector result with numeric timing columns and provenance.
#' @export
detectIgnitionBySeason_M0v2_timing <- function(ign_fit, params, ...) {
  det <- detectIgnitionBySeason_M0v2(
    ign_fit = ign_fit, params = params, ...
  )
  by <- det$by_season
  if (!nrow(by)) {
    return(det)
  }
  score_specs <- list()
  use_cls <- .m0_use_cls(params)
  if (use_cls) {
    score_specs <- c(score_specs, list(
      list(column = "p_cls_p", threshold = as.numeric(params$cls_thr %||% 0.2))
    ))
  }
  # Try active non-classifier gates in a stable order. This keeps fractional
  # timing informative when the optional classifier is disabled and p_cls_p
  # is therefore a constant zero.
  score_specs <- c(score_specs, list(
    list(column = "p_sumK", threshold = as.numeric(params$p_sum_thr %||% 0.04)),
    list(column = "p_sm", threshold = as.numeric(params$p_thr %||% 0.01)),
    list(column = "prev", threshold = as.numeric(params$prev_thr %||% 0.01))
  ))
  estimates <- lapply(seq_len(nrow(by)), function(i) {
    season <- as.character(by$season[i])
    signals <- det$data[as.character(det$data$season) == season, , drop = FALSE]
    attempted <- lapply(score_specs, function(spec) {
      if (!spec$column %in% names(signals)) {
        return(NULL)
      }
      .timing_v2_crossing(
        signals, by$iWeek_hat[i], spec$threshold,
        score_col = spec$column
      )
    })
    usable <- attempted[!vapply(attempted, is.null, logical(1))]
    crossing <- Filter(
      function(x) identical(x$method, "linear_detector_score_crossing"),
      usable
    )
    if (length(crossing)) crossing[[1L]] else usable[[1L]]
  })
  by$iWeek_hatF <- vapply(estimates, `[[`, numeric(1L), "estimate")
  by$iWeek_bracket <- I(lapply(estimates, `[[`, "bracket"))
  by$iWeek_bracket_lo <- vapply(estimates, function(x) x$bracket[1L], numeric(1L))
  by$iWeek_bracket_hi <- vapply(estimates, function(x) x$bracket[2L], numeric(1L))
  by$iWeek_fraction_method <- vapply(estimates, `[[`, character(1L), "method")
  det$by_season <- by
  if (!is.null(det$data)) {
    map <- setNames(by$iWeek_hatF, as.character(by$season))
    det$data$iWeek_hatF <- unname(map[as.character(det$data$season)])
  }
  det$timing <- list(
    mode = "fractional",
    rule = "linear interpolation of the first active detector score crossing",
    thresholds = vapply(score_specs, `[[`, numeric(1L), "threshold"),
    score_candidates = vapply(score_specs, `[[`, character(1L), "column"),
    raw_integer_field = "iWeek_hat",
    fractional_field = "iWeek_hatF"
  )
  if (!is.null(det$compare) && "iWeek_true" %in% names(det$compare)) {
    det$compare$diffF <- det$by_season$iWeek_hatF[
      match(det$compare$season, det$by_season$season)
    ] - as.numeric(det$compare$iWeek_true)
  }
  det
}

#' Single-season fractional M0 detector helper
#'
#' @param d_now One-season detector data containing the standard M0 columns.
#' @param params M0 detector parameters.
#' @return A list with current detector signals and integer/fractional timing.
#' @export
detectIgnition_oneSeason_timing_v2 <- function(d_now, params) {
  det <- detectIgnitionBySeason_M0v2_timing(
    d_now,
    params = params,
    verbose = FALSE, validate_support = FALSE
  )
  if (is.null(det$data) || !nrow(det$data)) {
    return(list(now = data.frame(), iWeek_hat = NA_integer_, iWeek_hatF = NA_real_))
  }
  dd <- det$data
  last <- dd[nrow(dd), , drop = FALSE]
  now <- data.frame(
    p_now = last$p, cum_p_now = sum(dd$p, na.rm = TRUE), prev_now = last$prev,
    p_cls_p_now = last$p_cls_p, n_hit_now = as.numeric(last$n_hit),
    d1_last = last$dp, d2_last = NA_real_, cond_win = last$cond_win,
    cond_cls = last$cond_cls, cond_cum = last$cond_sum, cond_p = last$cond_p,
    cond_prev = last$cond_prev, cond_inc = last$cond_inc,
    ignite_ok_now = last$ignite_ok, stringsAsFactors = FALSE
  )
  i_week <- as.integer(det$by_season$iWeek_hat[1L])
  detection_failed <- is.na(i_week)
  fallback_week <- as.integer(params$w_max %||% 30L)
  list(
    now = now,
    iWeek_hat = if (detection_failed) fallback_week else i_week,
    iWeek_hatF = if (detection_failed) {
      as.numeric(fallback_week)
    } else {
      as.numeric(det$by_season$iWeek_hatF[1L])
    },
    detection_failed = detection_failed
  )
}

#' Run prospective M0 with fractional ignition timing
#'
#' @param currentSeason One-season weekly surveillance data frame.
#' @param params M0 detector parameters.
#' @param start_week First week to evaluate.
#' @param ... Additional arguments are reserved for future detector controls.
#' @return The legacy weekly output with \code{iWeek_hat_dynamicF},
#'   \code{iWeek_hat_lockedF}, and integer brackets.
#' @export
run_ignition_weekly_timing_v2 <- function(currentSeason, params, start_week = 5L, ...) {
  d0 <- dplyr::as_tibble(currentSeason) |>
    dplyr::transmute(
      season = if ("season" %in% names(currentSeason)) as.character(.data$season) else NA_character_,
      weekF = as.integer(.data$weekF), y = as.integer(.data$y),
      N = if ("N" %in% names(currentSeason)) as.integer(.data$N) else as.integer(.data$y + .data$neg),
      neg = if ("neg" %in% names(currentSeason)) as.integer(.data$neg) else as.integer(.data$N - .data$y),
      p = if ("p" %in% names(currentSeason)) as.numeric(.data$p) else .data$y / pmax(.data$N, 1L),
      p_cls_p = if ("p_cls_p" %in% names(currentSeason)) as.numeric(.data$p_cls_p) else 0
    ) |>
    dplyr::filter(is.finite(.data$weekF), .data$weekF >= 1L) |>
    dplyr::arrange(.data$weekF)
  eval_weeks <- sort(unique(d0$weekF[d0$weekF >= as.integer(start_week)]))
  if (!length(eval_weeks)) {
    return(list(
      df = tibble::tibble(
        weekF = integer(), iWeek_hat_dynamic = integer(),
        iWeek_hat_dynamicF = numeric()
      ),
      iWeek_hat_dynamic_last = NA_real_, iWeek_hat_locked = NA_integer_,
      iWeek_hat_lockedF = NA_real_, ign_week_locked = NA_integer_,
      ign_week_lockedF = NA_real_, timing = list(mode = "fractional")
    ))
  }
  rows <- lapply(eval_weeks, function(w) {
    d_now <- d0[d0$weekF <= w, , drop = FALSE]
    det <- detectIgnitionBySeason_M0v2_timing(
      d_now,
      params = params, validate_support = FALSE, verbose = FALSE
    )
    now <- det$data[nrow(det$data), , drop = FALSE]
    hat <- det$by_season$iWeek_hat[1L]
    hatF <- det$by_season$iWeek_hatF[1L]
    detection_failed <- is.na(hat) || isTRUE(det$detection_failed)
    fallback_week <- as.integer(params$w_max %||% 30L)
    tibble::tibble(
      weekF = as.integer(w), p_now = now$p[nrow(now)],
      n_hit_now = as.numeric(now$n_hit[nrow(now)]),
      ignite_ok_now = as.logical(now$ignite_ok[nrow(now)]),
      detection_failed = detection_failed,
      iWeek_hat_dynamic = if (detection_failed) fallback_week else as.integer(hat),
      iWeek_hat_dynamicF = if (detection_failed) as.numeric(fallback_week) else as.numeric(hatF)
    )
  })
  df <- dplyr::bind_rows(rows)
  locked <- which(df$ignite_ok_now %in% TRUE)[1L]
  locked_week <- if (is.na(locked)) NA_integer_ else df$weekF[locked]
  valid_hat <- is.finite(df$iWeek_hat_dynamicF)
  list(
    df = df,
    iWeek_hat_dynamic_last = tail(df$iWeek_hat_dynamic, 1L),
    iWeek_hat_dynamic_lastF = tail(df$iWeek_hat_dynamicF, 1L),
    iWeek_hat_locked = if (any(valid_hat)) min(df$iWeek_hat_dynamic[valid_hat]) else NA_integer_,
    iWeek_hat_lockedF = if (any(valid_hat)) min(df$iWeek_hat_dynamicF[valid_hat]) else NA_real_,
    ign_week_locked = locked_week,
    ign_week_lockedF = if (is.na(locked)) NA_real_ else df$iWeek_hat_dynamicF[locked],
    detection_failed = isTRUE(tail(df$detection_failed, 1L)),
    timing = list(
      mode = "fractional", raw_integer_field = "iWeek_hat_dynamic",
      fractional_field = "iWeek_hat_dynamicF"
    )
  )
}

#' Build numeric timing targets for opt-in M0 training
#'
#' @param data Weekly training data with season and weekF.
#' @param labels Timing-v2 label object or list of objects.
#' @return A copy of \code{data} with numeric \code{ignition_target_weekF}
#'   and \code{peak_observed_weekF} columns.
#' @export
prepare_timing_training_data_v2 <- function(data, labels) {
  targets <- as_timing_targets_v2(labels)
  out <- dplyr::as_tibble(data) |>
    dplyr::mutate(season = as.character(.data$season)) |>
    dplyr::left_join(targets |> dplyr::select(
      .data$season, .data$ignition_target_weekF, .data$peak_observed_weekF,
      .data$peak_second_weekF
    ), by = "season") |>
    dplyr::mutate(
      phase = as.integer(.data$weekF >= .data$ignition_target_weekF)
    )
  out
}

#' Fit the M0 classifier using fractional timing targets
#'
#' @param data Weekly training data accepted by \code{fitIgnition()}.
#' @param labels Timing-v2 labels for the training seasons.
#' @param ... Arguments passed to \code{fitIgnition()}.
#' @return An M0 classifier result with numeric timing provenance.
#' @export
fitIgnition_timing_v2 <- function(data, labels, ...) {
  targets <- as_timing_targets_v2(labels)
  fit <- fitIgnition(
    prepare_timing_training_data_v2(data, labels),
    timing_truth = targets, ...
  )
  fit$timing <- list(
    mode = "fractional",
    target = "ignition_target_weekF",
    target_definition = "mean of the two normalized ignition weeks"
  )
  fit$timing_targets <- targets
  fit
}

#' Score fractional M0 detections against midpoint ignition labels
#'
#' @param detection Output from \code{detectIgnitionBySeason_M0v2_timing()}.
#' @param labels Timing-v2 labels used as truth.
#' @return A per-season data frame with numeric truth, estimate, and error.
#' @export
score_ignition_timing_v2 <- function(detection, labels) {
  if (!is.list(detection) || is.null(detection$by_season)) {
    stop("`detection` must contain `$by_season`.", call. = FALSE)
  }
  truth <- as_timing_targets_v2(labels) |>
    dplyr::select(.data$season, true_weekF = .data$ignition_target_weekF)
  estimate <- dplyr::as_tibble(detection$by_season) |>
    dplyr::transmute(
      season = as.character(.data$season),
      iWeek_hat = as.numeric(.data$iWeek_hat),
      estimate_weekF = as.numeric(.data$iWeek_hatF)
    )
  dplyr::left_join(truth, estimate, by = "season") |>
    dplyr::mutate(
      error = .data$estimate_weekF - .data$true_weekF,
      abs_error = abs(.data$error)
    )
}

#' Score peak timing against the observed peak week
#'
#' @param predictions Data frame with \code{season} and a numeric predicted
#'   peak column.
#' @param labels Timing-v2 labels.
#' @param prediction_col Name of the prediction column.
#' @return A data frame with observed truth, retained second label, and error.
#' @export
score_peak_timing_v2 <- function(predictions, labels, prediction_col = "peak_weekF") {
  if (!is.data.frame(predictions) || !all(c("season", prediction_col) %in% names(predictions))) {
    stop("`predictions` must contain season and `prediction_col`.", call. = FALSE)
  }
  truth <- as_timing_targets_v2(labels) |>
    dplyr::select(.data$season,
      true_peak_weekF = .data$peak_observed_weekF,
      peak_second_weekF = .data$peak_second_weekF
    )
  pred <- dplyr::transmute(predictions,
    season = as.character(.data$season),
    estimate_peak_weekF = as.numeric(.data[[prediction_col]])
  )
  dplyr::left_join(truth, pred, by = "season") |>
    dplyr::mutate(
      error = .data$estimate_peak_weekF - .data$true_peak_weekF,
      abs_error = abs(.data$error)
    )
}

#' Apply fractional timing to an M1 alignment result
#'
#' This opt-in adapter reuses the existing M1 result but re-computes aligned
#' coordinates from the numeric ignition estimate without integer coercion.
#'
#' @param current_data Weekly current-season data.
#' @param m0_result Output from \code{run_ignition_weekly_timing_v2()}.
#' @param anchor_week Numeric aligned anchor.
#' @return A list containing numeric \code{iWeek_hatF} and \code{currentD}.
#' @export
fractional_alignment_coordinates_v2 <- function(current_data, m0_result,
                                                anchor_week) {
  i_week <- as.numeric(m0_result$iWeek_hat_lockedF)
  if (length(i_week) != 1L || !is.finite(i_week)) {
    stop("M0 fractional result has no finite iWeek_hat_lockedF.", call. = FALSE)
  }
  out <- dplyr::as_tibble(current_data) |>
    dplyr::mutate(
      newWeek = as.numeric(.data$weekF) - i_week + as.numeric(anchor_week),
      iWeekF = i_week,
      phase = as.integer(.data$weekF >= i_week)
    )
  list(
    iWeek_hatF = i_week, currentD = out,
    raw_integer_bracket = m0_result$df$iWeek_hat_dynamic[1L] %||% NA_integer_
  )
}
