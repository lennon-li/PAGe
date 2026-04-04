#' Peak week (newWeek) per season + suggested peak-rule parameters
#'
#' @param theD historical data with at least:
#'   season, newWeek, and either p or (y, neg).
#' @param value_col column to define the peak. If NULL, uses p if present,
#'   otherwise computes p = y/(y+neg).
#' @param k_for_drop integer: how many weeks after the peak to look at
#'   when estimating the typical drop (also used as suggested min_consec_below).
#' @param drop_prob quantile of the *relative* drop to use, e.g. 0.5 for median.
#' @param abs_drop_prob quantile of the *absolute* drop to use for min_abs_drop.
#' @param max_week_prob quantile of peak_newWeek to use for max_week (e.g. 0.95).
#'
#' @return A list with:
#'   \itemize{
#'     \item \code{peaks}: tibble(season, peak_newWeek, peak_value)
#'     \item \code{suggested}: list with
#'       \itemize{
#'         \item \code{min_week}
#'         \item \code{max_week}
#'         \item \code{drop_frac}
#'         \item \code{min_abs_drop}
#'         \item \code{min_consec_below}
#'       }
#'   }
#' @export
peak_week_distribution <- function(theD,
                                   value_col     = NULL,
                                   k_for_drop    = 2L,
                                   drop_prob     = 0.5,
                                   abs_drop_prob = 0.5,
                                   max_week_prob = 0.95) {
  
  # --- choose value_col (p or y/(y+neg)) ---
  if (is.null(value_col)) {
    if ("p" %in% names(theD)) {
      value_col <- "p"
    } else if (all(c("y", "neg") %in% names(theD))) {
      theD <- dplyr::mutate(theD, p = .data$y / (.data$y + .data$neg))
      value_col <- "p"
    } else {
      stop("Need either column 'p' or columns 'y' and 'neg' to define a peak.")
    }
  }
  
  if (!all(c("season", "newWeek", value_col) %in% names(theD))) {
    stop("theD must contain 'season', 'newWeek' and ", value_col)
  }
  
  # --- 1) Peak per season ---
  peaks <- theD %>%
    dplyr::group_by(.data$season) %>%
    dplyr::filter(
      is.finite(.data[[value_col]]),
      is.finite(.data$newWeek)
    ) %>%
    dplyr::slice_max(
      order_by  = .data[[value_col]],
      with_ties = FALSE
    ) %>%
    dplyr::ungroup() %>%
    dplyr::transmute(
      season,
      peak_newWeek = .data$newWeek,
      peak_value   = .data[[value_col]]
    )
  
  # --- 2) Relative + absolute drop after k_for_drop weeks ---
  future_pts <- peaks %>%
    dplyr::mutate(
      newWeek_future = .data$peak_newWeek + as.integer(k_for_drop)
    )
  
  drop_df <- future_pts %>%
    dplyr::left_join(
      theD %>%
        dplyr::select(season, newWeek, !!rlang::sym(value_col)),
      by = c("season", "newWeek_future" = "newWeek")
    ) %>%
    dplyr::rename(value_future = !!rlang::sym(value_col)) %>%
    dplyr::filter(
      is.finite(.data$value_future),
      is.finite(.data$peak_value)
    ) %>%
    dplyr::mutate(
      abs_drop = .data$peak_value - .data$value_future,
      rel_drop = .data$abs_drop / .data$peak_value
    )
  
  if (nrow(drop_df) == 0L) {
    warning("No seasons have data ", k_for_drop,
            " weeks after peak; cannot estimate drop_frac or min_abs_drop.")
    drop_frac_hat   <- NA_real_
    abs_drop_hat    <- NA_real_
  } else {
    drop_frac_hat <- stats::quantile(
      drop_df$rel_drop,
      probs = drop_prob,
      na.rm = TRUE
    )
    abs_drop_hat  <- stats::quantile(
      drop_df$abs_drop,
      probs = abs_drop_prob,
      na.rm = TRUE
    )
  }
  
  # --- 3) max_week from historical peak distribution ---
  max_week_hat <- as.integer(
    stats::quantile(peaks$peak_newWeek,
                    probs = max_week_prob,
                    na.rm = TRUE)
  )
  

  
  list(
    peaks     = peaks,
    min_week         = min(peaks$peak_newWeek, na.rm = TRUE),
    max_week         = max_week_hat,
    drop_frac        = as.numeric(drop_frac_hat),
    min_abs_drop     = as.numeric(abs_drop_hat),
    min_consec_below = as.integer(k_for_drop)
  )
}
