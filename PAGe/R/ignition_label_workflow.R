#' Review a season before assigning its retrospective ignition label
#'
#' Creates a transparent, reproducible review object for one canonical PAGe
#' season. The object contains week-level positivity signals, Wilson intervals,
#' simple candidate summaries, and a ggplot object for visual inspection. No
#' label is assigned by this function and the input is never modified.
#'
#' @param data Canonical surveillance data containing \code{season},
#'   \code{weekF}, \code{y}, and \code{N} (or \code{neg}). It must contain one
#'   season after optional filtering; use \code{season} to select one season
#'   from multi-season data.
#' @param season Optional season identifier. Required when \code{data} contains
#'   more than one season.
#' @param smooth_window Positive integer used for the centred moving average.
#' @param p_threshold Positivity threshold shown in the plot and used for
#'   candidate summaries.
#' @param candidate_window Optional two-integer weekF range in which candidates
#'   may be considered. The observed range is used when omitted.
#' @param peak_tolerance Non-negative tolerance for treating observed positivity
#'   values as tied peak candidates.
#' @param confidence Confidence level for Wilson intervals.
#'
#' @return An object of class \code{page_ignition_review} with \code{signals},
#'   \code{summary}, \code{candidates}, \code{plot}, and a \code{provenance}
#'   list. Pass it to \code{finalize_ignition_label()} after visual review.
#' @export
review_ignition_label <- function(data,
                                  season = NULL,
                                  smooth_window = 3L,
                                  p_threshold = 0.01,
                                  candidate_window = NULL,
                                  peak_tolerance = 1e-12,
                                  confidence = 0.95) {
  if (!is.data.frame(data)) stop("`data` must be a data frame.", call. = FALSE)
  if (!is.null(season) && (length(season) != 1L || is.na(season))) {
    stop("`season` must be one non-missing identifier.", call. = FALSE)
  }
  canonical <- prepare_surveillance_data(
    data,
    season = if ("season" %in% names(data)) NULL else season
  )
  if (!is.null(season)) {
    season <- trimws(as.character(season))
    if (!season %in% unique(canonical$season)) {
      stop("Requested `season` is not present in `data`.", call. = FALSE)
    }
    canonical <- canonical[canonical$season == season, , drop = FALSE]
  }
  seasons <- unique(canonical$season)
  if (length(seasons) != 1L) {
    stop("`review_ignition_label()` requires exactly one season.", call. = FALSE)
  }
  if (length(smooth_window) != 1L || !is.numeric(smooth_window) ||
    !is.finite(smooth_window) || smooth_window < 1 ||
    smooth_window != as.integer(smooth_window)) {
    stop("`smooth_window` must be one positive integer.", call. = FALSE)
  }
  smooth_window <- as.integer(smooth_window)
  if (length(p_threshold) != 1L || !is.numeric(p_threshold) ||
    !is.finite(p_threshold) || p_threshold < 0 || p_threshold > 1) {
    stop("`p_threshold` must be one number in [0, 1].", call. = FALSE)
  }
  if (length(confidence) != 1L || !is.numeric(confidence) ||
    !is.finite(confidence) || confidence <= 0 || confidence >= 1) {
    stop("`confidence` must be one number strictly between 0 and 1.", call. = FALSE)
  }
  if (length(peak_tolerance) != 1L || !is.numeric(peak_tolerance) ||
    !is.finite(peak_tolerance) || peak_tolerance < 0) {
    stop("`peak_tolerance` must be one finite, non-negative number.", call. = FALSE)
  }
  observed_window <- range(canonical$weekF, na.rm = TRUE)
  if (is.null(candidate_window)) candidate_window <- observed_window
  if (length(candidate_window) != 2L || any(!is.finite(candidate_window)) ||
    any(candidate_window != as.integer(candidate_window)) ||
    candidate_window[1L] > candidate_window[2L]) {
    stop("`candidate_window` must be an increasing two-integer weekF range.", call. = FALSE)
  }
  candidate_window <- as.integer(candidate_window)

  canonical <- canonical[order(canonical$weekF), , drop = FALSE]
  p <- canonical$p
  valid_n <- canonical$N > 0 & is.finite(p)
  smooth <- rep(NA_real_, nrow(canonical))
  if (any(valid_n)) {
    smooth <- as.numeric(stats::filter(
      ifelse(valid_n, p, NA_real_),
      rep(1 / smooth_window, smooth_window),
      sides = 2L
    ))
  }
  slope <- c(NA_real_, diff(smooth))
  ci <- matrix(NA_real_, nrow(canonical), 2L)
  if (any(valid_n)) {
    ci[valid_n, ] <- wilson_ci(
      canonical$y[valid_n], canonical$N[valid_n],
      level = confidence
    )
  }
  in_window <- canonical$weekF >= candidate_window[1L] &
    canonical$weekF <= candidate_window[2L]
  above <- in_window & is.finite(smooth) & smooth >= p_threshold
  crossing <- above & !dplyr::lag(above, default = FALSE)
  signals <- data.frame(
    season = canonical$season,
    weekF = canonical$weekF,
    y = canonical$y,
    N = canonical$N,
    p = canonical$p,
    p_ci_lo = ci[, 1L],
    p_ci_hi = ci[, 2L],
    p_smooth = smooth,
    slope = slope,
    in_candidate_window = in_window,
    above_threshold = above,
    threshold_crossing = crossing,
    stringsAsFactors = FALSE
  )
  peak_row <- which.max(ifelse(is.finite(p), p, -Inf))
  peak_scope <- in_window & is.finite(p)
  peak_value <- if (any(peak_scope)) max(p[peak_scope]) else NA_real_
  peak_candidates <- if (is.finite(peak_value)) {
    canonical$weekF[peak_scope][p[peak_scope] >= peak_value - peak_tolerance]
  } else {
    integer()
  }
  peak_summary <- data.frame(
    season = seasons,
    missing_weeks = sum(!valid_n),
    observed_weeks = sum(valid_n),
    peak_value = peak_value,
    peak_weekF = if (length(peak_candidates)) peak_candidates[1L] else NA_integer_,
    peak_candidates = paste(peak_candidates, collapse = ","),
    n_peak_candidates = length(peak_candidates),
    plateau = length(peak_candidates) > 1L,
    stringsAsFactors = FALSE
  )
  candidate_rows <- which(crossing)
  candidates <- signals[candidate_rows, c(
    "season", "weekF", "p", "p_smooth", "slope", "p_ci_lo", "p_ci_hi"
  ), drop = FALSE]
  summary <- data.frame(
    season = seasons,
    n_weeks = nrow(signals),
    first_observed_weekF = min(signals$weekF),
    last_observed_weekF = max(signals$weekF),
    first_threshold_crossing = if (length(candidate_rows)) signals$weekF[candidate_rows[1L]] else NA_integer_,
    peak_observed_weekF = signals$weekF[peak_row],
    peak_observed_p = signals$p[peak_row],
    max_smoothed_p = if (any(is.finite(smooth))) max(smooth, na.rm = TRUE) else NA_real_,
    stringsAsFactors = FALSE
  )
  plot <- ggplot2::ggplot(signals, ggplot2::aes(x = weekF)) +
    ggplot2::geom_ribbon(ggplot2::aes(ymin = p_ci_lo, ymax = p_ci_hi), alpha = 0.18, na.rm = TRUE) +
    ggplot2::geom_point(ggplot2::aes(y = p), na.rm = TRUE) +
    ggplot2::geom_line(ggplot2::aes(y = p_smooth), linewidth = 0.7, na.rm = TRUE) +
    ggplot2::geom_point(
      data = signals[signals$weekF %in% peak_candidates, , drop = FALSE],
      ggplot2::aes(y = p), shape = 21, size = 3, stroke = 1, na.rm = TRUE
    ) +
    ggplot2::geom_hline(yintercept = p_threshold, linetype = "dashed") +
    ggplot2::geom_vline(xintercept = candidate_window, alpha = 0.35) +
    ggplot2::labs(
      title = paste0("Ignition label review: ", seasons),
      subtitle = paste0(
        "Points = observed positivity; line = ", smooth_window,
        "-week centred mean; band = ", confidence * 100, "% Wilson interval"
      ),
      x = "weekF", y = "positivity"
    )
  structure(list(
    signals = signals,
    summary = summary,
    peak_summary = peak_summary,
    peak_candidates = peak_candidates,
    candidates = candidates,
    plot = plot,
    parameters = list(
      smooth_window = smooth_window, p_threshold = p_threshold,
      candidate_window = candidate_window, peak_tolerance = peak_tolerance,
      confidence = confidence
    ),
    provenance = list(
      method = "review_ignition_label",
      data_hash = digest::digest(canonical, algo = "sha256"),
      season = seasons,
      created_at = as.character(Sys.time()),
      package = as.character(utils::packageVersion("PAGe"))
    )
  ), class = "page_ignition_review")
}

#' Finalize a reviewed peak label
#'
#' Records a user's selected observed peak week after inspecting the review.
#' Tied or near-tied raw maxima are exposed in \code{peak_candidates}; a user
#' may choose a scientifically justified smoothed peak when
#' \code{require_candidate = FALSE}.
#'
#' @param review An object returned by \code{review_ignition_label()}.
#' @param weekF One observed integer weekF selected by the user.
#' @param annotator Optional person or process identifier.
#' @param note Optional free-text rationale.
#' @param require_candidate Logical; require the selection to be a reported
#'   raw peak candidate.
#' @return An object of class \code{page_peak_label} with a named \code{label}
#'   vector and provenance.
#' @export
finalize_peak_label <- function(review, weekF, annotator = NULL, note = NULL,
                                require_candidate = FALSE) {
  if (!inherits(review, "page_ignition_review")) {
    stop("`review` must be returned by `review_ignition_label()`.", call. = FALSE)
  }
  if (length(weekF) != 1L || !is.numeric(weekF) || !is.finite(weekF) ||
    weekF != as.integer(weekF)) {
    stop("`weekF` must be one finite integer.", call. = FALSE)
  }
  if (length(require_candidate) != 1L || !is.logical(require_candidate) ||
    is.na(require_candidate)) {
    stop("`require_candidate` must be TRUE or FALSE.", call. = FALSE)
  }
  weekF <- as.integer(weekF)
  signals <- review$signals
  if (!weekF %in% signals$weekF) stop("Selected peak `weekF` is not observed.", call. = FALSE)
  p_value <- signals$p[match(weekF, signals$weekF)]
  if (!is.finite(p_value)) stop("Selected peak `weekF` has missing positivity.", call. = FALSE)
  if (require_candidate && !weekF %in% review$peak_candidates) {
    stop("Selected peak `weekF` is not a reported peak candidate.", call. = FALSE)
  }
  season <- review$provenance$season
  structure(list(
    label = stats::setNames(weekF, season), season = season, weekF = weekF,
    is_peak_candidate = weekF %in% review$peak_candidates,
    rationale = list(annotator = annotator, note = note),
    peak_summary = review$peak_summary,
    provenance = list(
      method = "finalize_peak_label", review_data_hash = review$provenance$data_hash,
      finalized_at = as.character(Sys.time()), selected_weekF = weekF
    )
  ), class = "page_peak_label")
}

#' Finalize ignition and peak labels together
#'
#' @param review An object returned by \code{review_ignition_label()}.
#' @param ignition_weekF User-selected ignition weekF.
#' @param peak_weekF User-selected peak weekF.
#' @param annotator Optional person or process identifier.
#' @param note Optional rationale shared by both labels.
#' @return A class \code{page_season_labels} object containing named
#'   \code{ignition_labels} and \code{peak_labels} vectors.
#' @export
finalize_season_labels <- function(review, ignition_weekF, peak_weekF,
                                   annotator = NULL, note = NULL) {
  ignition <- finalize_ignition_label(review, ignition_weekF, annotator, note)
  peak <- finalize_peak_label(review, peak_weekF, annotator, note)
  structure(list(
    ignition_labels = ignition$labels,
    peak_labels = peak$label,
    ignition = ignition,
    peak = peak,
    provenance = list(
      method = "finalize_season_labels", review_data_hash = review$provenance$data_hash,
      finalized_at = as.character(Sys.time())
    )
  ), class = "page_season_labels")
}

#' Finalize a reviewed ignition label
#'
#' Explicitly records a user's selected week after reviewing the output of
#' \code{review_ignition_label()}. The selected week must be an observed week
#' inside the declared candidate window.
#'
#' @param review An object returned by \code{review_ignition_label()}.
#' @param weekF One observed integer weekF selected by the user.
#' @param annotator Optional person or process identifier.
#' @param note Optional free-text rationale.
#'
#' @return An object of class \code{page_ignition_label}; its \code{labels}
#'   element is a named integer vector suitable for training APIs.
#' @export
finalize_ignition_label <- function(review, weekF, annotator = NULL, note = NULL) {
  if (!inherits(review, "page_ignition_review")) {
    stop("`review` must be returned by `review_ignition_label()`.", call. = FALSE)
  }
  if (length(weekF) != 1L || !is.numeric(weekF) || !is.finite(weekF) ||
    weekF != as.integer(weekF)) {
    stop("`weekF` must be one finite integer.", call. = FALSE)
  }
  weekF <- as.integer(weekF)
  signals <- review$signals
  if (!weekF %in% signals$weekF) stop("Selected `weekF` is not observed.", call. = FALSE)
  window <- review$parameters$candidate_window
  if (weekF < window[1L] || weekF > window[2L]) {
    stop("Selected `weekF` is outside `candidate_window`.", call. = FALSE)
  }
  season <- review$provenance$season
  labels <- stats::setNames(weekF, season)
  list(
    labels = labels,
    season = season,
    weekF = weekF,
    rationale = list(annotator = annotator, note = note),
    review_summary = review$summary,
    provenance = list(
      method = "finalize_ignition_label",
      review_data_hash = review$provenance$data_hash,
      finalized_at = as.character(Sys.time()),
      selected_weekF = weekF
    )
  ) |> structure(class = "page_ignition_label")
}

#' Apply finalized ignition labels to canonical training data
#'
#' Adds \code{iWeek}, \code{phase}, and aligned \code{newWeek} columns to a new
#' data frame. Raw counts and positivity are preserved, and the input object is
#' never modified.
#'
#' @param data Canonical surveillance data.
#' @param labels Named integer vector, or a \code{page_ignition_label} object.
#' @param anchor_week Common aligned anchor. Defaults to the median supplied
#'   label, rounded down as in \code{alignIgnition()}.
#' @param n_weeks_col Optional column containing each season's total week count.
#'   If omitted, the maximum observed weekF is used per season.
#' @param require_all Logical; require a label for every season in \code{data}.
#'
#' @return A new data frame with \code{iWeek}, \code{phase}, and \code{newWeek}.
#' @export
apply_ignition_labels <- function(data, labels, anchor_week = NULL,
                                  n_weeks_col = NULL, require_all = TRUE) {
  canonical <- prepare_surveillance_data(data)
  label_vec <- if (inherits(labels, "page_ignition_label")) labels$labels else labels
  if (!is.numeric(label_vec) || is.null(names(label_vec)) || any(!nzchar(names(label_vec)))) {
    stop("`labels` must be a named numeric/integer vector or finalized label.", call. = FALSE)
  }
  if (anyNA(label_vec) || any(label_vec != as.integer(label_vec)) || any(label_vec <= 0)) {
    stop("Ignition labels must be positive whole-number weekF values.", call. = FALSE)
  }
  if (anyDuplicated(names(label_vec))) stop("`labels` must have unique season names.", call. = FALSE)
  missing <- setdiff(unique(canonical$season), names(label_vec))
  if (require_all && length(missing)) {
    stop("Missing ignition label(s) for: ", paste(missing, collapse = ", "), ".", call. = FALSE)
  }
  used <- label_vec[intersect(unique(canonical$season), names(label_vec))]
  if (!length(used)) stop("No supplied labels match the data seasons.", call. = FALSE)
  if (is.null(anchor_week)) anchor_week <- as.integer(stats::median(used, na.rm = TRUE))
  if (length(anchor_week) != 1L || !is.numeric(anchor_week) || !is.finite(anchor_week) ||
    anchor_week != as.integer(anchor_week) || anchor_week <= 0) {
    stop("`anchor_week` must be one positive integer.", call. = FALSE)
  }
  anchor_week <- as.integer(anchor_week)
  out <- canonical
  out$iWeek <- as.integer(unname(label_vec[match(out$season, names(label_vec))]))
  out$phase <- as.integer(!is.na(out$iWeek) & out$weekF >= out$iWeek)
  n_weeks <- if (!is.null(n_weeks_col)) {
    if (length(n_weeks_col) != 1L || !n_weeks_col %in% names(out)) {
      stop("`n_weeks_col` must name a column in `data`.", call. = FALSE)
    }
    as.numeric(out[[n_weeks_col]])
  } else {
    rep(NA_real_, nrow(out))
  }
  by_season <- split(seq_len(nrow(out)), out$season)
  for (idx in by_season) {
    if (all(is.na(n_weeks[idx]))) n_weeks[idx] <- max(out$weekF[idx], na.rm = TRUE)
  }
  offset <- anchor_week - out$iWeek
  out$newWeek <- ifelse(
    is.na(out$iWeek), NA_integer_,
    ((out$weekF + offset - 1L) %% n_weeks) + 1L
  )
  out$newWeek <- as.integer(out$newWeek)
  attr(out, "anchorWeek") <- anchor_week
  attr(out, "ignition_labels") <- label_vec
  out
}
