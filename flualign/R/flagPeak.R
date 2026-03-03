#' Flag whether the epidemic has passed its peak (real time)
#'
#' Uses only information up to each week (dynamic peak_so_far), and
#' checks whether there has been a sustained drop from that peak.
#'
#' @param df data frame for a single season, with at least:
#'   \itemize{
#'     \item newWeek: monotone-increasing epidemic week index
#'     \item p: positivity (if missing, y/(y+neg) will be computed)
#'   }
#' @param value_col name of the column to treat as positivity (default: "p";
#'   if NULL and p is absent, uses y/(y+neg)).
#' @param min_week minimum newWeek to start considering a "past-peak" flag.
#' @param max_week maximum newWeek to consider (Inf = no upper limit).
#' @param drop_frac required relative drop from the peak_so_far:
#'   flag when rel_drop >= drop_frac.
#' @param min_abs_drop required absolute drop from peak_so_far:
#'   flag when abs_drop >= min_abs_drop.
#' @param min_consec_below number of consecutive weeks that must satisfy
#'   the drop condition before declaring "past peak".
#'
#' @return A list with:
#'   \itemize{
#'     \item df: original data plus helper columns:
#'       \code{peak_so_far}, \code{abs_drop}, \code{rel_drop},
#'       \code{drop_cond}, \code{drop_streak}, \code{eligible},
#'       \code{past_peak_flag}
#'     \item flag_week: newWeek at which "past peak" is first flagged (NA if none)
#'     \item peak_week_so_far: newWeek of the global max within df
#'     \item peak_value_so_far: value at that peak
#'   }
#' @export
flagPeak <- function(df,
                     value_col       = NULL,
                     min_week        = 1L,
                     max_week        = Inf,
                     drop_frac       = 0.25,
                     min_abs_drop    = 0.05,
                     min_consec_below = 2L) {
  
  if (!"newWeek" %in% names(df)) {
    stop("df must contain 'newWeek'.")
  }
  
  # ---- choose value_col (p or y/(y+neg)) ----
  if (is.null(value_col)) {
    if ("p" %in% names(df)) {
      value_col <- "p"
    } else if (all(c("y", "neg") %in% names(df))) {
      df <- dplyr::mutate(df, p = .data$y / (.data$y + .data$neg))
      value_col <- "p"
    } else {
      stop("Need either column 'p' or columns 'y' and 'neg' to define positivity.")
    }
  }
  
  if (!value_col %in% names(df)) {
    stop("Column '", value_col, "' not found in df.")
  }
  
  # ---- sort by newWeek and work on a copy ----
  df <- df %>%
    dplyr::arrange(.data$newWeek)
  
  val <- df[[value_col]]
  
  # guard against all NA
  if (all(!is.finite(val))) {
    warning("All positivity values are NA/inf; cannot flag peak.")
    df$peak_so_far      <- NA_real_
    df$abs_drop         <- NA_real_
    df$rel_drop         <- NA_real_
    df$drop_cond        <- FALSE
    df$drop_streak      <- 0L
    df$eligible         <- FALSE
    df$past_peak_flag   <- FALSE
    return(list(
      df               = df,
      flag_week        = NA_integer_,
      peak_week_so_far = NA_integer_,
      peak_value_so_far = NA_real_
    ))
  }
  
  # ---- dynamic peak so far (only using data up to each week) ----
  peak_so_far <- cummax(val)
  
  abs_drop <- pmax(0, peak_so_far - val)
  rel_drop <- ifelse(peak_so_far > 0,
                     abs_drop / peak_so_far,
                     0)
  
  drop_cond <- (rel_drop >= drop_frac) | (abs_drop >= min_abs_drop)
  
  # eligible window in newWeek space
  eligible <- (df$newWeek >= min_week) &
    (df$newWeek <= max_week)
  
  drop_eff <- drop_cond & eligible
  
  # ---- run-length of consecutive TRUEs for drop_eff ----
  # no explicit loops; reset streak when drop_eff == FALSE
  drop_streak <- ave(
    drop_eff,
    cumsum(!drop_eff),
    FUN = function(x) ifelse(x, seq_along(x), 0L)
  )
  
  # first index where we meet the streak condition
  idx_flag <- which(drop_streak >= min_consec_below)[1L]
  
  flag_week <- if (length(idx_flag) == 0L) NA_integer_ else df$newWeek[idx_flag]
  
  # global peak (within df) for reporting
  peak_idx <- which.max(val)
  peak_week_so_far  <- df$newWeek[peak_idx]
  peak_value_so_far <- val[peak_idx]
  
  df$peak_so_far    <- peak_so_far
  df$abs_drop       <- abs_drop
  df$rel_drop       <- rel_drop
  df$drop_cond      <- drop_cond
  df$drop_streak    <- as.integer(drop_streak)
  df$eligible       <- eligible
  df$past_peak_flag <- !is.na(flag_week) & (df$newWeek >= flag_week)
  
  list(
    df                = df,
    flag_week         = flag_week,
    peak_week_so_far  = peak_week_so_far,
    peak_value_so_far = peak_value_so_far
  )
}
