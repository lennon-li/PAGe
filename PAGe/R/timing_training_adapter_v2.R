#' Convert timing-v2 labels to the M0/M1 training label contract
#'
#' Extracts the earlier ignition week from one timing-v2 label object or a list
#' of objects. The normalized pair and peak labels remain available on the
#' original objects; this adapter supplies only the scalar ignition vector
#' expected by the existing leakage-safe M0/M1 training functions.
#'
#' @param labels A \code{page_season_timing_v2} or
#'   \code{page_timing_labels_v2} object, or a list of those objects.
#' @return A named integer vector mapping season to the earlier ignition week.
#' @export
as_manual_labels_v2 <- function(labels) {
  objects <- .timing_v2_as_objects(labels)
  values <- lapply(objects, `[[`, "scoring_ignition_labels")
  if (any(vapply(values, is.null, logical(1L)))) {
    stop("Every timing-v2 label object must include an ignition label.", call. = FALSE)
  }
  result <- unlist(values, use.names = TRUE)
  if (is.null(names(result)) || any(!nzchar(names(result)))) {
    stop("Timing-v2 ignition labels must have season names.", call. = FALSE)
  }
  if (anyDuplicated(names(result))) {
    stop("Timing-v2 ignition labels must have unique season names.", call. = FALSE)
  }
  as.integer(result) |> stats::setNames(names(result))
}

#' Extract fractional timing targets from timing-v2 labels
#'
#' This is the opt-in adapter for the fractional pipeline. Ignition targets
#' are the midpoint of the normalized pair. Peak targets are the observed
#' peak week selected during review; the second adjacent peak label is kept in
#' the returned table for uncertainty and provenance.
#'
#' @param labels A timing-v2 label object or list of objects.
#' @return A data frame with one row per season and numeric ignition and peak
#'   targets, normalized pairs, and second-label provenance.
#' @export
as_timing_targets_v2 <- function(labels) {
  objects <- .timing_v2_as_objects(labels)
  rows <- lapply(objects, function(x) {
    if (is.null(x$season) || is.null(x$target_ignition_labels) ||
      is.null(x$target_peak_labels)) {
      stop("Every timing-v2 object must include season, ignition, and peak labels.", call. = FALSE)
    }
    if (is.null(x$peak$observed_weekF) || is.null(x$peak$second_weekF) ||
      !is.finite(x$peak$observed_weekF) || !is.finite(x$peak$second_weekF)) {
      stop(
        "Peak labels must be finalized with finite observed and second weeks; ",
        "run `finalize_season_timing_v2()` after review.", call. = FALSE
      )
    }
    if (is.null(x$ignition$target_weekF) ||
      !is.finite(x$ignition$target_weekF)) {
      stop("Ignition labels must contain a finite midpoint target.", call. = FALSE)
    }
    data.frame(
      season = as.character(x$season),
      ignition_lower_weekF = x$ignition$lower_weekF,
      ignition_upper_weekF = x$ignition$upper_weekF,
      ignition_target_weekF = as.numeric(x$ignition$target_weekF),
      peak_lower_weekF = x$peak$lower_weekF,
      peak_upper_weekF = x$peak$upper_weekF,
      peak_observed_weekF = as.numeric(x$peak$observed_weekF),
      peak_second_weekF = as.numeric(x$peak$second_weekF),
      peak_target_weekF = as.numeric(x$peak$observed_weekF),
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

.timing_v2_as_objects <- function(labels) {
  if (inherits(labels, "page_timing_labels_v2")) {
    return(list(labels))
  }
  if (is.list(labels) && length(labels) > 0L &&
    all(vapply(labels, inherits, logical(1L), what = "page_timing_labels_v2"))) {
    return(unname(labels))
  }
  stop("`labels` must be a timing-v2 label object or list of label objects.", call. = FALSE)
}

.timing_v2_filter_holdout <- function(labels, holdout = NULL) {
  if (is.null(labels) || is.null(holdout)) {
    return(labels)
  }
  objects <- .timing_v2_as_objects(labels)
  keep <- !vapply(objects, function(x) {
    identical(as.character(x$season), as.character(holdout))
  }, logical(1L))
  objects <- objects[keep]
  if (!length(objects)) {
    return(NULL)
  }
  if (inherits(labels, "page_timing_labels_v2")) {
    objects[[1L]]
  } else {
    unname(objects)
  }
}
