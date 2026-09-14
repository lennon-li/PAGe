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
#' expanded to the preceding pair. Ignition is scored at the pair midpoint.
#' For peak, the observed week is selected from the supplied pair by the
#' larger observed positivity (ties select the earlier week); the other week
#' remains second-label provenance.
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
  if (!is.null(labels$peak)) {
    peak_weeks <- labels$peak$weeks
    peak_rows <- match(peak_weeks, review$signals$weekF)
    peak_values <- review$signals$p[peak_rows]
    if (length(peak_rows) != 2L || anyNA(peak_rows) || any(!is.finite(peak_values))) {
      stop("The review must contain finite observed values for both supplied peak weeks.",
        call. = FALSE
      )
    }
    observed_idx <- if (peak_values[1L] >= peak_values[2L]) 1L else 2L
    labels$peak$observed_weekF <- peak_weeks[observed_idx]
    labels$peak$second_weekF <- peak_weeks[3L - observed_idx]
    labels$target_peak_weekF <- stats::setNames(labels$peak$observed_weekF, season)
    labels$target_peak_labels <- labels$target_peak_weekF
    labels$second_peak_labels <- stats::setNames(labels$peak$second_weekF, season)
  }
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
#' Applies the numeric ignition midpoint as the alignment and phase reference,
#' adds the observed peak week when supplied, and attaches the complete timing
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
#' @return A new data frame with legacy integer \code{iWeek}, numeric
#' \code{iWeekF}, \code{phase}, numeric \code{newWeek}, and observed
#' \code{peak_weekF}, plus timing evidence attributes.
#' @export
apply_timing_labels_v2 <- function(data, labels, anchor_week = NULL,
                                   n_weeks_col = NULL, require_all = TRUE) {
  objects <- .timing_v2_as_objects(labels)
  prepared <- prepare_surveillance_data(data)

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

  ignition <- collect("target_ignition_labels")
  peak <- collect("target_peak_labels")
  if (is.null(ignition)) {
    stop("At least one timing-v2 ignition label is required for application.", call. = FALSE)
  }
  if (!is.null(peak) && any(!is.finite(peak))) {
    stop("Peak labels must have an explicit observed week before application.", call. = FALSE)
  }
  matched_seasons <- unique(as.character(prepared$season))
  missing_ignition <- setdiff(matched_seasons, names(ignition))
  if (isTRUE(require_all) && length(missing_ignition)) {
    stop("Missing timing-v2 ignition label(s) for: ",
         paste(missing_ignition, collapse = ", "), ".", call. = FALSE)
  }
  if (!length(intersect(matched_seasons, names(ignition)))) {
    stop("No supplied timing-v2 labels match the data seasons.", call. = FALSE)
  }

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

  if (is.null(anchor_week)) anchor_week <- stats::median(ignition, na.rm = TRUE)
  if (length(anchor_week) != 1L || !is.numeric(anchor_week) ||
    !is.finite(anchor_week) || anchor_week <= 0) {
    stop("`anchor_week` must be one positive numeric week.", call. = FALSE)
  }
  anchor_week <- as.numeric(anchor_week)
  out <- prepared
  out$iWeekF <- as.numeric(unname(ignition[match(out$season, names(ignition))]))
  out$iWeek <- as.integer(floor(out$iWeekF))
  out$phase <- as.integer(!is.na(out$iWeekF) & out$weekF >= out$iWeekF)
  n_weeks <- if (!is.null(n_weeks_col)) {
    if (length(n_weeks_col) != 1L || !n_weeks_col %in% names(out)) {
      stop("`n_weeks_col` must name a column in `data`.", call. = FALSE)
    }
    as.numeric(out[[n_weeks_col]])
  } else {
    n_map <- unlist(lapply(objects, function(x) {
      stats::setNames(x$n_weeks, names(x$target_ignition_labels))
    }), use.names = TRUE)
    unname(n_map[match(out$season, names(n_map))])
  }
  if (anyNA(n_weeks)) {
    by_season <- split(seq_len(nrow(out)), out$season)
    for (idx in by_season) {
      if (all(is.na(n_weeks[idx]))) n_weeks[idx] <- max(out$weekF[idx], na.rm = TRUE)
    }
  }
  out$newWeek <- ((as.numeric(out$weekF) + anchor_week - out$iWeekF - 1) %% n_weeks) + 1
  out$target_weekF <- out$iWeekF
  if (".page_timing_n_weeks" %in% names(out)) out$.page_timing_n_weeks <- NULL
  if (!is.null(peak)) {
    out$peak_weekF <- as.numeric(unname(peak[match(out$season, names(peak))]))
    out$peak_label_weekF <- out$peak_weekF
    second <- collect("second_peak_labels")
    out$peak_second_weekF <- if (!is.null(second)) {
      as.numeric(unname(second[match(out$season, names(second))]))
    } else NA_real_
  }
  attr(out, "timing_labels_v2") <- labels
  attr(out, "timing_evidence_v2") <- do.call(rbind, lapply(objects, function(x) x$evidence))
  out
}
