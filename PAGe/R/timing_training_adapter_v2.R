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
