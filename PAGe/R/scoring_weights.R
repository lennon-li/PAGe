# Shared phase-based scoring-weight contract for M2 tuning, adoption, and replay.

.psw_weight <- function(value, field) {
  if (!is.numeric(value) || length(value) != 1L || !is.finite(value) || value < 0) {
    stop(
      "`", field, "` must be one finite non-negative numeric weight.",
      call. = FALSE
    )
  }
  as.numeric(value)
}

.psw_offset <- function(value, field) {
  if (!is.numeric(value) || length(value) != 1L || !is.finite(value) ||
    value != floor(value)) {
    stop(
      "`", field, "` must be one finite whole-number offset.",
      call. = FALSE
    )
  }
  if (value > .Machine$integer.max) {
    stop("`", field, "` exceeds the supported integer range.", call. = FALSE)
  }
  as.integer(value)
}

as_page_scoring_weights <- function(weights) {
  if (inherits(weights, "page_scoring_weights")) {
    return(weights)
  }
  if (is.list(weights) && !is.data.frame(weights)) {
    known <- c(
      "pre_ignition", "rise", "turning", "decline",
      "turning_before", "turning_after"
    )
    extra <- setdiff(names(weights), known)
    if (length(extra) > 0L) {
      stop(
        "Unknown scoring-weight field(s): ",
        paste(sprintf("`%s`", extra), collapse = ", "), ".",
        call. = FALSE
      )
    }
    return(do.call(page_scoring_weights, weights[intersect(known, names(weights))]))
  }
  stop(
    "`weights` must be a `page_scoring_weights` object created by ",
    "`page_scoring_weights()`.",
    call. = FALSE
  )
}

#' Construct a phase-based scoring-weight contract
#'
#' Defines the non-negative per-phase weights used to score M2 forecasts and
#' the M2-vs-M1 gate. Weights are resolved against a target week relative to a
#' season's ignition week (`I`) and its observed peak week (`P`).
#'
#' @param pre_ignition Weight for target weeks before ignition (`t < I`).
#' @param rise Weight for the rising limb (`I <= t < P + turning_before`).
#' @param turning Weight for the peak neighbourhood
#'   (`P - turning_before <= t <= P + turning_after`).
#' @param decline Weight for the declining limb (`t > P + turning_after`).
#' @param turning_before Whole-number offset from the observed peak at which
#'   the turning window begins. The default is code{-1}.
#' @param turning_after Whole-number offset from the observed peak at which
#'   the turning window ends. The default is code{3}.
#'
#' @return A list of class `page_scoring_weights` with elements `pre_ignition`,
#'   `rise`, `turning`, `decline`, `turning_before`, and `turning_after`.
#'
#' @details
#' Observed seasonal peaks are retrospective scoring references for completed
#' seasons only. They must never be supplied as forecast inputs or used to
#' build covariates available at forecast time. Fractional peak labels are
#' used on their native week scale; the resulting boundaries are not rounded.
#'
#' @examples
#' page_scoring_weights()
#' page_scoring_weights(turning_before = 0L, turning_after = 0L, decline = 0)
#'
#' @export
page_scoring_weights <- function(pre_ignition = 0, rise = 2, turning = 3,
                                 decline = 1, turning_before = -1L,
                                 turning_after = 3L) {
  object <- list(
    pre_ignition = .psw_weight(pre_ignition, "pre_ignition"),
    rise = .psw_weight(rise, "rise"),
    turning = .psw_weight(turning, "turning"),
    decline = .psw_weight(decline, "decline"),
    turning_before = .psw_offset(turning_before, "turning_before"),
    turning_after = .psw_offset(turning_after, "turning_after")
  )
  structure(object, class = "page_scoring_weights")
}

# Resolve the retrospective references used by both tuning and replay. A
# timing-v2 peak label wins; otherwise an argmax is allowed only when the
# observed season reaches its declared calendar length. This helper deliberately
# returns NA for live/partial seasons so they cannot silently enter the score.
.page_scoring_metadata <- function(data, timing_truth = NULL,
                                   season_col = "season", target_col = "weekF",
                                   ignition_col = "ignition_weekF") {
  if (!is.data.frame(data) || !all(c(season_col, target_col) %in% names(data))) {
    stop("Scoring metadata requires season and target-week columns.", call. = FALSE)
  }
  out <- data.frame(
    season = as.character(data[[season_col]]),
    target_weekF = as.numeric(data[[target_col]]),
    ignition_weekF = NA_real_, observed_peak_weekF = NA_real_,
    stringsAsFactors = FALSE
  )
  if (ignition_col %in% names(data)) {
    out$ignition_weekF <- as.numeric(data[[ignition_col]])
  }
  truth <- if (is.data.frame(timing_truth)) timing_truth else data.frame()
  if (nrow(truth) && "season" %in% names(truth)) {
    truth$season <- as.character(truth$season)
    ignition <- intersect(c("ignition_target_weekF", "iWeekF", "iWeek"), names(truth))[1L]
    peak <- intersect(c("peak_observed_weekF", "peak_target_weekF", "peak_weekF"), names(truth))[1L]
    if (length(ignition) && !is.na(ignition)) {
      out$ignition_weekF <- unname(as.numeric(truth[[ignition]])[match(out$season, truth$season)])
    }
    if (length(peak) && !is.na(peak)) {
      out$observed_peak_weekF <- unname(as.numeric(truth[[peak]])[match(out$season, truth$season)])
    }
  }
  if ("peak_label_weekF" %in% names(data)) {
    label <- as.numeric(data$peak_label_weekF)
    use <- is.finite(label)
    out$observed_peak_weekF[use] <- label[use]
  }
  y_name <- intersect(c("y", "y_lead"), names(data))[1L]
  n_name <- intersect(c("N", "N_lead"), names(data))[1L]
  n_w <- if ("nW_true" %in% names(data)) as.numeric(data$nW_true) else rep(NA_real_, nrow(data))
  if (length(y_name) && length(n_name) && !is.na(y_name) && !is.na(n_name)) {
    y <- as.numeric(data[[y_name]])
    n <- as.numeric(data[[n_name]])
    for (s in unique(out$season)) {
      idx <- which(out$season == s)
      if (any(is.finite(out$observed_peak_weekF[idx]))) next
      nw <- n_w[idx][is.finite(n_w[idx])][1L]
      max_week <- max(out$target_weekF[idx], na.rm = TRUE)
      if (!is.finite(nw)) nw <- max(52, max_week)
      valid <- idx[is.finite(y[idx]) & is.finite(n[idx]) & n[idx] > 0 & y[idx] >= 0 & y[idx] <= n[idx]]
      if (length(valid) && max_week >= nw) {
        p <- y[valid] / n[valid]
        out$observed_peak_weekF[idx] <- out$target_weekF[valid][which.max(p)]
      }
    }
  }
  out
}

.psw_column <- function(rows, col, field) {
  if (!is.character(col) || length(col) != 1L || is.na(col) || !nzchar(col)) {
    stop("`", field, "` must be one non-empty column name.", call. = FALSE)
  }
  if (!col %in% names(rows)) {
    stop("Column `", col, "` (`", field, "`) is not present in `rows`.",
      call. = FALSE
    )
  }
  values <- rows[[col]]
  if (!is.numeric(values)) {
    stop("Column `", col, "` (`", field, "`) must be numeric.", call. = FALSE)
  }
  as.numeric(values)
}

#' Derive per-row phase weights from observed ignition and peak weeks
#'
#' Resolves a numeric scoring weight for every row from its target week `t`
#' (the week being scored) relative to the owning season's ignition week `I`
#' and observed peak week `P`, using the phase rules encoded in `weights`.
#'
#' @param rows A data frame of scored rows.
#' @param weights A `page_scoring_weights` object, or a named list accepted by
#'   [page_scoring_weights()].
#' @param season_col,target_col,ignition_col,peak_col Length-one character
#'   column names. `season_col` identifies the season; `target_col` is the
#'   scored target week `t`; `ignition_col` and `peak_col` carry the season's
#'   ignition week `I` and observed peak week `P`. Fractional weeks are allowed.
#'   `I` and `P` must be constant within each season.
#' @param allow_censored Logical. When `FALSE` (default), a season with a
#'   missing `I` or `P` is an error. When `TRUE`, such rows receive phase
#'   `"censored"` and weight `NA`, leaving the caller to decide how to treat
#'   them.
#'
#' @return `rows` as a data frame with two appended columns: `phase` (character
#'   phase label) and `weight` (numeric scoring weight, `NA` for censored
#'   rows). Row order and existing columns are preserved.
#'
#' @details
#' Observed peaks are retrospective scoring references for completed seasons
#' only. They must never be supplied as forecast inputs or used to build
#' covariates available at forecast time.
#'
#' Phase boundaries are inclusive at the lower edge and exclusive at the upper
#' edge except for the turning window, which is closed on both ends:
#' `t < I` is `pre_ignition`; `I <= t < P + turning_before` is `rise`;
#' `P + turning_before <= t <= P + turning_after` is `turning`; and
#' `t > P + turning_after` is `decline`.
#'
#' @examples
#' rows <- data.frame(
#'   season = c("s1", "s1", "s1", "s1"),
#'   target = c(9, 10, 31, 35),
#'   ignition = 10, peak = 30
#' )
#' page_phase_weights(
#'   rows, page_scoring_weights(), "season", "target",
#'   "ignition", "peak"
#' )
#'
#' @export
page_phase_weights <- function(rows, weights, season_col = "season",
                               target_col = "target_weekF",
                               ignition_col = "ignition_weekF", peak_col = NULL,
                               allow_censored = FALSE, y_col = NULL,
                               n_col = NULL, completed_col = NULL) {
  if (!is.data.frame(rows) || !nrow(rows)) {
    stop("`rows` must be a non-empty data frame.", call. = FALSE)
  }
  weights <- as_page_scoring_weights(weights)
  if (!is.logical(allow_censored) || length(allow_censored) != 1L ||
    is.na(allow_censored)) {
    stop("`allow_censored` must be one non-missing logical.", call. = FALSE)
  }

  if (!is.character(season_col) || length(season_col) != 1L ||
    is.na(season_col) || !nzchar(season_col)) {
    stop("`season_col` must be one non-empty column name.", call. = FALSE)
  }
  season <- rows[[season_col]]
  if (is.null(season)) {
    stop("Column `", season_col, "` (`season_col`) is not present in `rows`.",
      call. = FALSE
    )
  }
  season <- as.character(season)
  if (anyNA(season) || any(!nzchar(season))) {
    stop("`season_col` values must be non-missing and non-empty.",
      call. = FALSE
    )
  }
  target <- .psw_column(rows, target_col, "target_col")
  ignition <- .psw_column(rows, ignition_col, "ignition_col")
  peak_name <- peak_col
  if (is.null(peak_name)) {
    peak_name <- intersect(c("peak_label_weekF", "observed_peak_weekF", "peak_weekF"), names(rows))[1L]
  }
  if (!is.na(peak_name) && length(peak_name)) {
    peak <- .psw_column(rows, peak_name, "peak_col")
  } else {
    y_name <- y_col %||% intersect(c("y", "y_lead"), names(rows))[1L]
    n_name <- n_col %||% intersect(c("N", "N_lead"), names(rows))[1L]
    if (is.na(y_name) || is.na(n_name) || !length(y_name) || !length(n_name)) {
      peak <- rep(NA_real_, nrow(rows))
    } else {
      y <- .psw_column(rows, y_name, "y_col")
      n <- .psw_column(rows, n_name, "n_col")
      if (any(!is.na(n) & (!is.finite(n) | n <= 0)) ||
        any(!is.na(y) & (!is.finite(y) | y < 0)) ||
        any(!is.na(y) & !is.na(n) & y > n)) {
        stop("Observed counts must be finite and satisfy 0 <= y <= N.", call. = FALSE)
      }
      complete <- if (!is.null(completed_col)) {
        as.logical(rows[[completed_col]])
      } else {
        n_w <- if ("nW_true" %in% names(rows)) as.numeric(rows$nW_true) else rep(NA_real_, nrow(rows))
        vapply(seq_len(nrow(rows)), function(i) {
          s <- season[[i]]
          idx <- which(season == s & is.finite(y) & is.finite(n))
          if (!length(idx)) {
            FALSE
          } else {
            nw <- n_w[idx][is.finite(n_w[idx])][1L]
            max_week <- max(target[idx], na.rm = TRUE)
            if (!is.finite(nw)) nw <- max(52, max_week)
            max_week >= nw
          }
        }, logical(1))
      }
      peak <- rep(NA_real_, nrow(rows))
      for (s in unique(season)) {
        idx <- which(season == s & complete & is.finite(y) & is.finite(n))
        if (length(idx)) {
          positivity <- y[idx] / n[idx]
          peak[idx] <- target[idx][which.max(positivity)]
        }
      }
    }
  }

  seasons <- unique(season)
  season_info <- lapply(seasons, function(s) {
    idx <- which(season == s)
    i_vals <- unique(ignition[idx][!is.na(ignition[idx])])
    p_vals <- unique(peak[idx][!is.na(peak[idx])])
    if (length(i_vals) > 1L) {
      stop("Season `", s, "` has multiple ignition values in `", ignition_col,
        "`; `I` must be constant within a season.",
        call. = FALSE
      )
    }
    if (length(p_vals) > 1L) {
      stop("Season `", s, "` has multiple peak values in `", peak_col,
        "`; `P` must be constant within a season.",
        call. = FALSE
      )
    }
    list(
      i = if (length(i_vals) == 1L) i_vals else NA_real_,
      p = if (length(p_vals) == 1L) p_vals else NA_real_
    )
  })
  names(season_info) <- seasons

  i_row <- vapply(season, function(s) season_info[[s]]$i, numeric(1))
  p_row <- vapply(season, function(s) season_info[[s]]$p, numeric(1))
  censored <- is.na(i_row) | is.na(p_row)

  if (any(censored) && !allow_censored) {
    bad <- unique(season[censored])
    stop(
      "Missing ignition (`I`) or observed peak (`P`) for season(s): ",
      paste(sprintf("`%s`", bad), collapse = ", "),
      ". Set `allow_censored = TRUE` to label these rows as censored.",
      call. = FALSE
    )
  }
  if (any(is.na(target) & !censored)) {
    stop("`target_col` has missing values for non-censored rows.",
      call. = FALSE
    )
  }

  n <- nrow(rows)
  phase <- rep(NA_character_, n)
  weight <- rep(NA_real_, n)
  phase[censored] <- "censored"

  keep <- !censored
  if (any(keep)) {
    t2 <- target[keep]
    i2 <- i_row[keep]
    p2 <- p_row[keep]
    ph2 <- ifelse(
      t2 < i2, "pre_ignition",
      ifelse(
        t2 < p2 + weights$turning_before, "rise",
        ifelse(t2 <= p2 + weights$turning_after, "turning", "decline")
      )
    )
    phase[keep] <- ph2
    weight[keep] <- c(
      pre_ignition = weights$pre_ignition,
      rise = weights$rise,
      turning = weights$turning,
      decline = weights$decline
    )[ph2]
  }

  out <- as.data.frame(rows, stringsAsFactors = FALSE)
  out[["phase"]] <- phase
  out[["weight"]] <- as.numeric(weight)
  out
}
