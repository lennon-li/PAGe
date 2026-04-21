# ============================================================
# Nested M1 → M2 LOSO: Shared utilities
#
# Derivative helpers used across the LOSO evaluation pipeline.
# ============================================================

# ---------- 0. Prospective derivatives ----------

#' Prospective (real-time safe) derivatives of positivity on the logit scale
#'
#' For each season in \code{alignedD}, fits a local quadratic to a rolling
#' window of \code{k} observations on the logit scale and returns the
#' instantaneous first and second derivatives as \code{d1_link} and
#' \code{d2_link}. Computation is strictly causal: only observations up to
#' and including the current week are used.
#'
#' @param alignedD Data frame with columns \code{season}, \code{weekF},
#'   \code{y}, and \code{neg}.
#' @param k Integer; window size for local quadratic fit (default 5L).
#' @param eps Numeric; clipping epsilon for logit (default 1e-6).
#' @param min_obs Integer; minimum observations required (default 4L).
#' @return \code{alignedD} with additional columns \code{d1_link} and
#'   \code{d2_link}.
#' @export
add_prospective_derivs_link <- function(alignedD,
                                        k = 5L,
                                        eps = 1e-6,
                                        min_obs = 4L) {
  stopifnot(all(c("season","weekF","y","neg") %in% names(alignedD)))
  if (!requireNamespace("dplyr", quietly = TRUE)) stop("Please install dplyr.")
  if (!requireNamespace("purrr", quietly = TRUE)) stop("Please install purrr.")

  d <- alignedD |>
    dplyr::mutate(
      y_w = .data$y / (.data$y + .data$neg),
      z_w = stats::qlogis(pmin(pmax(.data$y_w, eps), 1 - eps))
    ) |>
    dplyr::arrange(.data$season, .data$weekF)

  d |>
    dplyr::group_by(.data$season) |>
    dplyr::group_modify(function(.x, .g) {
      ww <- .x$weekF
      zz <- .x$z_w
      n  <- nrow(.x)

      d1 <- purrr::map_dbl(seq_len(n), function(i) {
        i0 <- max(1L, i - k + 1L)
        ii <- i0:i
        if (length(ii) < min_obs || anyNA(zz[ii])) return(NA_real_)
        w0 <- ww[i]
        u  <- ww[ii] - w0
        fit <- stats::lm(zz[ii] ~ u + I(u^2))
        unname(stats::coef(fit)[["u"]])
      })

      d2 <- purrr::map_dbl(seq_len(n), function(i) {
        i0 <- max(1L, i - k + 1L)
        ii <- i0:i
        if (length(ii) < min_obs || anyNA(zz[ii])) return(NA_real_)
        w0 <- ww[i]
        u  <- ww[ii] - w0
        fit <- stats::lm(zz[ii] ~ u + I(u^2))
        2 * unname(stats::coef(fit)[["I(u^2)"]])
      })

      dplyr::mutate(.x, d1_link = d1, d2_link = d2)
    }) |>
    dplyr::ungroup()
}

# ---------- 0b. Walk-forward derivative helper ----------

#' Compute derivatives for a single season in a causal (walk-forward) manner
#'
#' For each week \code{w} in \code{season_df}, fits \code{estimateDerivs} on
#' the subset of rows with \code{weekF <= w} and records the derivative values
#' for row \code{w} only.  This prevents future weeks from influencing the GAM
#' smoother at earlier time points — a requirement for honest LOSO evaluation.
#'
#' Results are memoised by \code{walk_end} inside each call: each unique
#' \code{walk_end} value triggers exactly one \code{estimateDerivs} fit.
#'
#' @param season_df Data frame for a single season with columns
#'   \code{weekF}, \code{y}, \code{N} (or \code{neg}) as expected by
#'   \code{estimateDerivs()}.
#' @param k Integer; basis dimension forwarded to \code{estimateDerivs()}
#'   (default \code{10L}).
#' @param min_rows Integer; minimum rows required before attempting a fit
#'   (default \code{4L}).  Rows with too few observations receive \code{NA}
#'   for all derivative columns.
#'
#' @return A data frame with the same rows as \code{season_df} augmented
#'   with columns \code{fit}, \code{fit_low}, \code{fit_high}, \code{d1},
#'   \code{d1_low}, \code{d1_high}, \code{d2}, \code{d2_low}, \code{d2_high}.
#'   These values at row \code{i} are computed using only \code{weekF[1:i]}.
#' @export
estimateDerivs_walkforward <- function(season_df, k = 10L, min_rows = 4L) {
  stopifnot(is.data.frame(season_df), "weekF" %in% names(season_df))

  season_df <- dplyr::arrange(season_df, .data$weekF)
  weeks     <- season_df$weekF
  n         <- nrow(season_df)

  deriv_cols <- c("fit", "fit_low", "fit_high",
                  "d1", "d1_low", "d1_high",
                  "d2", "d2_low", "d2_high")
  out <- season_df
  for (col in deriv_cols) out[[col]] <- NA_real_

  for (i in seq_len(n)) {
    sub <- season_df[seq_len(i), , drop = FALSE]
    if (nrow(sub) < min_rows) next
    res <- tryCatch(
      estimateDerivs(sub, k = min(k, nrow(sub) - 1L)),
      error = function(e) NULL
    )
    if (is.null(res)) next
    last_row <- res$data[nrow(res$data), , drop = FALSE]
    for (col in deriv_cols) {
      if (col %in% names(last_row))
        out[[col]][i] <- last_row[[col]]
    }
  }
  out
}
