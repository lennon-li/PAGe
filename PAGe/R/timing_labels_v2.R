#' Normalize one user timing label
#'
#' A timing-v2 label is one integer week or two consecutive integer weeks.
#' A singleton \code{w} is normalized to \code{c(w - 1, w)} so that the
#' earlier week is always available for scoring and operational use. The
#' original input is preserved separately. This function does not modify any
#' legacy label vector.
#'
#' @param label One or two integer week numbers.
#' @param event_type Either \code{"ignition"} or \code{"peak"}.
#' @param n_weeks Number of weeks in the season.
#' @return A normalized timing label object.
#' @keywords internal
normalize_timing_label <- function(label, event_type = c("ignition", "peak"),
                                   n_weeks = 52L) {
  event_type <- match.arg(event_type)
  n_weeks <- .timing_check_n_weeks(n_weeks)
  if (is.logical(label) || !is.numeric(label) || length(label) < 1L || length(label) > 2L ||
    anyNA(label) || any(!is.finite(label)) || any(label != trunc(label))) {
    stop("`", event_type, "` must be one integer week or two integer weeks.", call. = FALSE)
  }
  if (length(label) == 1L) {
    if (label < 2) {
      stop("A singleton `", event_type, "` label must be at least week 2 because it expands to w-1,w.", call. = FALSE)
    }
    if (label > n_weeks) {
      stop("`", event_type, "` label must fall within weeks 1 through ", n_weeks, ".", call. = FALSE)
    }
    original <- as.integer(label)
    normalized <- c(original - 1L, original)
  } else {
    if (any(label < 1 | label > n_weeks)) {
      stop("`", event_type, "` label must fall within weeks 1 through ", n_weeks, ".", call. = FALSE)
    }
    original <- as.integer(label)
    if (length(unique(original)) != 2L || abs(diff(original)) != 1L) {
      stop("Two `", event_type, "` labels must be consecutive weeks.", call. = FALSE)
    }
    normalized <- sort(original)
  }
  if (any(normalized < 1L | normalized > n_weeks)) {
    stop("`", event_type, "` label must fall within weeks 1 through ", n_weeks, ".", call. = FALSE)
  }

  structure(
    list(
      event_type = event_type,
      original_input = original,
      weeks = normalized,
      lower_weekF = normalized[1L],
      upper_weekF = normalized[2L],
      scoring_weekF = normalized[1L],
      input_length = length(original)
    ),
    class = "page_timing_label_v2"
  )
}

#' Validate and normalize independent ignition and peak labels
#'
#' Users may provide either event independently. Each supplied event accepts
#' one integer week or exactly two consecutive integer weeks. A singleton is
#' expanded to the preceding pair, for example \code{18 -> c(17, 18)}.
#' The normalized pair is uncertainty metadata; the earlier week is retained
#' as the scalar scoring reference.
#'
#' @param ignition Optional ignition label.
#' @param peak Optional peak label.
#' @param season Optional season identifier.
#' @param n_weeks Number of weeks in the season.
#' @param calendar Optional timing calendar. Its week count must agree with
#'   \code{n_weeks}.
#' @return A class \code{page_timing_labels_v2} object.
#' @keywords internal
validate_timing_labels <- function(ignition = NULL, peak = NULL, season = NULL,
                                   n_weeks = NULL, calendar = NULL) {
  if (is.null(ignition) && is.null(peak)) {
    stop("Supply at least one of `ignition` or `peak`.", call. = FALSE)
  }
  requested_n_weeks <- if (is.null(n_weeks)) NULL else .timing_check_n_weeks(n_weeks)
  if (!is.null(calendar)) {
    validate_timing_calendar(calendar)
    if (!is.null(requested_n_weeks) && requested_n_weeks != calendar$n_weeks) {
      stop("`n_weeks` must agree with `calendar$n_weeks`.", call. = FALSE)
    }
    n_weeks <- calendar$n_weeks
  } else if (is.null(requested_n_weeks)) {
    n_weeks <- 52L
  } else {
    n_weeks <- requested_n_weeks
  }
  n_weeks <- .timing_check_n_weeks(n_weeks)
  if (!is.null(season)) {
    if (length(season) != 1L || is.na(season) || !nzchar(trimws(as.character(season)))) {
      stop("`season` must be one non-empty identifier.", call. = FALSE)
    }
    season <- trimws(as.character(season))
  }
  if (!is.null(calendar) && !is.null(season) && !is.null(calendar$season) &&
    !identical(season, calendar$season)) {
    stop("`season` must agree with `calendar$season`.", call. = FALSE)
  }

  ignition_norm <- if (is.null(ignition)) NULL else normalize_timing_label(ignition, "ignition", n_weeks)
  peak_norm <- if (is.null(peak)) NULL else normalize_timing_label(peak, "peak", n_weeks)
  scalar_ignition <- if (is.null(ignition_norm)) {
    NULL
  } else {
    if (is.null(season)) {
      ignition_norm$scoring_weekF
    } else {
      stats::setNames(ignition_norm$scoring_weekF, season)
    }
  }
  scalar_peak <- if (is.null(peak_norm)) {
    NULL
  } else {
    if (is.null(season)) {
      peak_norm$scoring_weekF
    } else {
      stats::setNames(peak_norm$scoring_weekF, season)
    }
  }

  structure(
    list(
      season = season,
      n_weeks = n_weeks,
      calendar_id = if (is.null(calendar)) NULL else calendar$calendar_id,
      ignition = ignition_norm,
      peak = peak_norm,
      scoring_ignition_labels = scalar_ignition,
      scoring_peak_labels = scalar_peak,
      legacy_scalar_labels = list(ignition = scalar_ignition, peak = scalar_peak),
      provenance = list(method = "validate_timing_labels", normalized = TRUE)
    ),
    class = "page_timing_labels_v2"
  )
}

#' Create season timing labels from user input
#'
#' @inheritParams validate_timing_labels
#' @return A validated \code{page_timing_labels_v2} object.
#' @keywords internal
label_season_timing <- function(season = NULL, ignition = NULL, peak = NULL,
                                n_weeks = NULL, calendar = NULL) {
  validate_timing_labels(
    ignition = ignition, peak = peak, season = season,
    n_weeks = n_weeks, calendar = calendar
  )
}

#' Compile normalized timing labels into evidence rows
#'
#' @param labels A \code{page_timing_labels_v2} object.
#' @return A data frame with one row per supplied event and list columns that
#'   preserve original and normalized week vectors.
#' @keywords internal
compile_timing_evidence <- function(labels) {
  if (!inherits(labels, "page_timing_labels_v2")) {
    stop("`labels` must be created by `validate_timing_labels()`.", call. = FALSE)
  }
  events <- c("ignition", "peak")
  events <- events[!vapply(events, function(x) is.null(labels[[x]]), logical(1L))]
  if (!length(events)) {
    return(data.frame())
  }
  data.frame(
    season = rep(if (is.null(labels$season)) NA_character_ else labels$season, length(events)),
    event_type = events,
    original_input = I(lapply(events, function(x) labels[[x]]$original_input)),
    normalized_weeks = I(lapply(events, function(x) labels[[x]]$weeks)),
    lower_weekF = vapply(events, function(x) labels[[x]]$lower_weekF, integer(1L)),
    upper_weekF = vapply(events, function(x) labels[[x]]$upper_weekF, integer(1L)),
    scoring_weekF = vapply(events, function(x) labels[[x]]$scoring_weekF, integer(1L)),
    stringsAsFactors = FALSE
  )
}
