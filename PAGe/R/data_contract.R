#' Prepare surveillance data for PAGe
#'
#' Normalizes weekly surveillance data to PAGe's canonical columns. Input must
#' contain \code{weekF}, \code{y}, and either \code{N} or \code{neg}.
#' Missing totals, negatives, and positivity are derived deterministically.
#' When \code{N} is zero, \code{p} is left missing rather than treating an
#' unobserved week as zero positivity.
#'
#' @param data A data frame containing weekly surveillance observations.
#' @param season Optional single season identifier used only when \code{data}
#'   does not contain a \code{season} column.
#' @param tolerance Numeric tolerance for redundant count and positivity
#'   consistency checks.
#'
#' @return A data frame with canonical columns \code{season}, \code{weekF},
#'   \code{y}, \code{N}, \code{p}, and \code{neg}, followed by any extra input
#'   columns in their original order.
#' @export
prepare_surveillance_data <- function(data, season = NULL, tolerance = 1e-8) {
  if (!is.data.frame(data)) {
    stop("`data` must be a data frame.")
  }
  if (length(tolerance) != 1L || !is.finite(tolerance) || tolerance < 0) {
    stop("`tolerance` must be one finite, non-negative number.")
  }

  out <- as.data.frame(data)
  if (!"season" %in% names(out)) {
    if (is.null(season)) {
      stop("`data` must contain `season`, or `season` must be supplied explicitly.")
    }
    .check_one_season(season)
    out$season <- rep(as.character(season), nrow(out))
  } else if (!is.null(season)) {
    .check_one_season(season)
    supplied <- trimws(as.character(out$season))
    if (anyNA(supplied) || any(supplied != as.character(season))) {
      stop("Explicit `season` is inconsistent with the `data$season` values.")
    }
  }

  required <- c("weekF", "y")
  missing_required <- setdiff(required, names(out))
  if (length(missing_required)) {
    stop(
      "`data` is missing required column(s): ",
      paste(missing_required, collapse = ", "), "."
    )
  }
  if (!"N" %in% names(out) && !"neg" %in% names(out)) {
    stop("`data` must contain either `N` or `neg` in addition to `y`.")
  }

  out$weekF <- .numeric_contract_field(out$weekF, "weekF")
  out$y <- .numeric_contract_field(out$y, "y")
  if ("N" %in% names(out)) out$N <- .numeric_contract_field(out$N, "N")
  if ("neg" %in% names(out)) {
    out$neg <- .numeric_contract_field(out$neg, "neg")
  }
  if ("p" %in% names(out)) out$p <- .numeric_contract_field(out$p, "p", allow_na = TRUE)

  if (!"N" %in% names(out)) out$N <- out$y + out$neg
  if (!"neg" %in% names(out)) out$neg <- out$N - out$y

  if ("N" %in% names(data) && "neg" %in% names(data)) {
    inconsistent_counts <- abs(out$N - (out$y + out$neg)) > tolerance
    if (any(inconsistent_counts)) {
      stop("Redundant `N`, `y`, and `neg` fields are inconsistent.")
    }
  }

  expected_p <- out$y / out$N
  expected_p[out$N == 0] <- NA_real_
  if ("p" %in% names(data)) {
    comparable <- out$N > 0
    inconsistent_p <- comparable &
      (is.na(out$p) | abs(out$p - expected_p) > tolerance)
    zero_has_value <- out$N == 0 & !is.na(out$p)
    if (any(inconsistent_p | zero_has_value)) {
      stop("Redundant `p` is inconsistent with `y / N`.")
    }
  }
  out$p <- expected_p

  out <- validate_surveillance_data(out, tolerance = tolerance)
  canonical <- c("season", "weekF", "y", "N", "p", "neg")
  out[c(canonical, setdiff(names(out), canonical))]
}

#' Validate canonical PAGe surveillance data
#'
#' Checks the complete canonical surveillance schema without deriving missing
#' columns. Use \code{prepare_surveillance_data()} first for partial inputs.
#'
#' @inheritParams prepare_surveillance_data
#'
#' @return The validated data frame, unchanged apart from safe canonical type
#'   normalization.
#' @export
validate_surveillance_data <- function(data, tolerance = 1e-8) {
  if (!is.data.frame(data)) {
    stop("`data` must be a data frame.")
  }
  if (length(tolerance) != 1L || !is.finite(tolerance) || tolerance < 0) {
    stop("`tolerance` must be one finite, non-negative number.")
  }
  canonical <- c("season", "weekF", "y", "N", "p", "neg")
  missing_columns <- setdiff(canonical, names(data))
  if (length(missing_columns)) {
    stop(
      "Canonical surveillance data are missing column(s): ",
      paste(missing_columns, collapse = ", "), "."
    )
  }

  out <- as.data.frame(data)
  out$season <- trimws(as.character(out$season))
  if (anyNA(out$season) || any(!nzchar(out$season))) {
    stop("`season` must contain non-empty identifiers.")
  }
  out$weekF <- .numeric_contract_field(out$weekF, "weekF")
  out$y <- .numeric_contract_field(out$y, "y")
  out$N <- .numeric_contract_field(out$N, "N")
  out$neg <- .numeric_contract_field(out$neg, "neg")
  out$p <- .numeric_contract_field(out$p, "p", allow_na = TRUE)

  .check_whole(out$weekF, "weekF", tolerance)
  if (any(out$weekF <= 0)) stop("`weekF` must contain positive integers.")
  for (field in c("y", "N", "neg")) {
    .check_whole(out[[field]], field, tolerance)
  }
  for (field in c("y", "N")) {
    if (any(out[[field]] < 0)) {
      stop("`", field, "` must contain non-negative counts.")
    }
  }
  if (any(out$y > out$N + tolerance)) {
    stop("Positive counts `y` cannot exceed total counts `N`.")
  }
  if (any(out$neg < 0)) {
    stop("`neg` must contain non-negative counts.")
  }
  if (any(abs(out$N - (out$y + out$neg)) > tolerance)) {
    stop("Canonical `N`, `y`, and `neg` fields are inconsistent.")
  }

  positive_n <- out$N > 0
  if (any(is.na(out$p[positive_n])) ||
    any(!is.finite(out$p[positive_n])) ||
    any(out$p[positive_n] < 0 | out$p[positive_n] > 1)) {
    stop("`p` must be finite and between 0 and 1 when `N` is positive.")
  }
  if (any(!is.na(out$p[!positive_n]))) {
    stop("`p` must be missing when `N` is zero.")
  }
  expected_p <- out$y[positive_n] / out$N[positive_n]
  if (any(abs(out$p[positive_n] - expected_p) > tolerance)) {
    stop("Canonical `p` is inconsistent with `y / N`.")
  }

  keys <- data.frame(season = out$season, weekF = out$weekF)
  if (anyDuplicated(keys)) {
    stop("Surveillance data must have exactly one row per `season` and `weekF`.")
  }
  out
}

.numeric_contract_field <- function(x, name, allow_na = FALSE) {
  value <- suppressWarnings(as.numeric(as.character(x)))
  invalid <- if (allow_na) !is.na(x) & !is.finite(value) else !is.finite(value)
  if (any(invalid)) {
    stop(
      "`", name, "` must contain finite numeric values",
      if (allow_na) " or allowed missing values." else "."
    )
  }
  value
}

.check_whole <- function(x, name, tolerance) {
  if (any(abs(x - round(x)) > tolerance)) {
    stop("`", name, "` must contain whole-number values.")
  }
}

.check_one_season <- function(season) {
  if (length(season) != 1L || is.na(season) || !nzchar(trimws(as.character(season)))) {
    stop("`season` must be one non-empty identifier.")
  }
}
