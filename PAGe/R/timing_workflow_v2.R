#' Review one season for timing-v2 labels
#'
#' Produces the week-level plot and summary used before a user assigns ignition
#' and peak labels. The review is read-only; labels are recorded separately by
#' \code{finalize_season_timing_v2()}.
#'
#' @inheritParams review_ignition_label
#' @return An object of class \code{page_timing_review_v2}, retaining the
#'   signals, candidate summaries, plot, and data provenance.
#' @export
review_season_timing_v2 <- function(data,
                                    season = NULL,
                                    smooth_window = 3L,
                                    p_threshold = 0.01,
                                    candidate_window = NULL,
                                    peak_tolerance = 1e-12,
                                    confidence = 0.95) {
  review <- review_ignition_label(
    data = data,
    season = season,
    smooth_window = smooth_window,
    p_threshold = p_threshold,
    candidate_window = candidate_window,
    peak_tolerance = peak_tolerance,
    confidence = confidence
  )
  structure(
    review,
    class = c("page_timing_review_v2", class(review)),
    timing_version = 2L
  )
}

#' Record user supplied ignition and peak timing labels
#'
#' Each event accepts one week or two consecutive weeks. A singleton is
#' expanded to the preceding pair. The earlier week is stored as the scoring
#' reference, while both weeks remain available as uncertainty metadata.
#'
#' @param review An object returned by \code{review_season_timing_v2()}.
#' @param ignition One ignition week or two consecutive ignition weeks.
#' @param peak One peak week or two consecutive peak weeks.
#' @param n_weeks Optional number of weeks in the season. When omitted, the
#'   larger of 52 and the maximum observed \code{weekF} is used, or the
#'   calendar's count is used when \code{calendar} is supplied.
#' @param calendar Optional \code{page_timing_calendar_v2} object.
#' @param annotator Optional person or process identifier.
#' @param note Optional free-text rationale for the labels.
#' @return An object of class \code{page_season_timing_v2} containing normalized
#'   labels, scoring references, evidence rows, and review provenance.
#' @export
finalize_season_timing_v2 <- function(review, ignition, peak,
                                      n_weeks = NULL, calendar = NULL,
                                      annotator = NULL, note = NULL) {
  if (!inherits(review, "page_timing_review_v2")) {
    stop("`review` must be returned by `review_season_timing_v2()`.", call. = FALSE)
  }
  if (is.null(ignition) || is.null(peak)) {
    stop("Supply both `ignition` and `peak` labels.", call. = FALSE)
  }
  season <- review$provenance$season
  if (is.null(n_weeks) && is.null(calendar)) {
    observed_max <- max(review$signals$weekF, na.rm = TRUE)
    n_weeks <- max(52L, observed_max)
  }
  labels <- label_season_timing(
    season = season,
    ignition = ignition,
    peak = peak,
    n_weeks = n_weeks,
    calendar = calendar
  )
  labels$review_summary <- review$summary
  labels$review_peak_summary <- review$peak_summary
  labels$review_candidates <- review$candidates
  labels$evidence <- compile_timing_evidence(labels)
  labels$rationale <- list(annotator = annotator, note = note)
  labels$provenance$method <- "finalize_season_timing_v2"
  labels$provenance$review_data_hash <- review$provenance$data_hash
  labels$provenance$finalized_at <- as.character(Sys.time())
  labels$provenance$annotator <- annotator
  structure(labels, class = c("page_season_timing_v2", class(labels)))
}

#' Apply timing-v2 labels to canonical surveillance data
#'
#' Applies the earlier ignition week as the alignment and phase reference,
#' adds the earlier peak week when supplied, and attaches the complete timing
#' evidence to the returned data frame. A single finalized object or a list of
#' finalized objects may be supplied for multiple seasons.
#'
#' @param data Canonical or preparable surveillance data.
#' @param labels A \code{page_season_timing_v2} object, a
#'   \code{page_timing_labels_v2} object, or a list of those objects.
#' @param anchor_week Common aligned anchor passed to
#'   \code{apply_ignition_labels()}.
#' @param n_weeks_col Optional column containing each season's total week count.
#'   When omitted, the count recorded with each timing label is used.
#' @param require_all Logical; require an ignition label for every season.
#' @return A new data frame with \code{iWeek}, \code{phase}, \code{newWeek},
#'   and \code{peak_weekF}, plus timing evidence attributes.
#' @export
apply_timing_labels_v2 <- function(data, labels, anchor_week = NULL,
                                   n_weeks_col = NULL, require_all = TRUE) {
  objects <- .timing_v2_as_objects(labels)

  collect <- function(field) {
    values <- lapply(objects, `[[`, field)
    values <- values[!vapply(values, is.null, logical(1L))]
    if (!length(values)) {
      return(NULL)
    }
    result <- unlist(values, use.names = TRUE)
    if (is.null(names(result)) || any(!nzchar(names(result)))) {
      stop("Timing-v2 `", field, "` labels must have season names.", call. = FALSE)
    }
    if (anyDuplicated(names(result))) {
      stop("Timing-v2 `", field, "` labels must have unique season names.", call. = FALSE)
    }
    result
  }

  ignition <- collect("scoring_ignition_labels")
  peak <- collect("scoring_peak_labels")
  if (is.null(ignition)) {
    stop("At least one timing-v2 ignition label is required for application.", call. = FALSE)
  }

  prepared <- prepare_surveillance_data(data)
  if (is.null(n_weeks_col)) {
    season_n_weeks <- unlist(lapply(objects, function(x) {
      stats::setNames(x$n_weeks, names(x$scoring_ignition_labels))
    }), use.names = TRUE)
    if (anyDuplicated(names(season_n_weeks))) {
      stop("Timing-v2 label objects must not repeat seasons.", call. = FALSE)
    }
    prepared$.page_timing_n_weeks <- unname(season_n_weeks[match(prepared$season, names(season_n_weeks))])
    n_weeks_col <- ".page_timing_n_weeks"
  }

  out <- apply_ignition_labels(
    prepared,
    labels = ignition,
    anchor_week = anchor_week,
    n_weeks_col = n_weeks_col,
    require_all = require_all
  )
  if (".page_timing_n_weeks" %in% names(out)) out$.page_timing_n_weeks <- NULL
  if (!is.null(peak)) {
    out$peak_weekF <- as.integer(unname(peak[match(out$season, names(peak))]))
  }
  attr(out, "timing_labels_v2") <- labels
  attr(out, "timing_evidence_v2") <- do.call(rbind, lapply(objects, function(x) x$evidence))
  out
}
