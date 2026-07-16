#' Plot a PAGe 2-week-ahead forecast
#'
#' Draws the current-season positivity forecast produced by the M0/M1/M2
#' pipeline. Optionally overlays historical season trajectories as a grey
#' background for context.
#'
#' @param res List returned by the prospective pipeline (e.g.
#'   \code{run_prospective_pipeline()}). Must contain \code{$pred_df} (with
#'   columns \code{newWeek}, \code{p_hat}, \code{p_lo}, \code{p_hi}, and
#'   \code{kind}) and \code{$last_obs}.
#' @param history Optional data frame of historical seasons with columns
#'   \code{season}, \code{newWeek} or \code{weekF}, \code{y}, and either
#'   \code{N} or \code{neg}. When supplied,
#'   season trajectories are plotted as translucent grey lines.
#'
#' @return A \code{ggplot} object.
#' @export
plot_forecast <- function(res, history = NULL) {
  if (!is.list(res) || !is.data.frame(res$pred_df)) {
    stop("`res` must be a page_forecast or compatible list with data-frame `pred_df`.")
  }
  required <- c("newWeek", "p_hat", "kind")
  missing <- setdiff(required, names(res$pred_df))
  if (length(missing)) {
    stop(
      "`res$pred_df` is missing required column(s): ",
      paste(missing, collapse = ", "), "."
    )
  }
  pred <- res$pred_df
  invalid_kind <- !is.na(pred$kind) & !pred$kind %in% c("observed", "forecast")
  if (any(invalid_kind)) {
    stop("`res$pred_df$kind` must contain only `observed` or `forecast`.")
  }
  observed <- pred[!is.na(pred$kind) & pred$kind == "observed", , drop = FALSE]
  forecast <- pred[!is.na(pred$kind) & pred$kind == "forecast", , drop = FALSE]
  if (nrow(forecast)) {
    missing_interval <- setdiff(c("p_lo", "p_hi"), names(forecast))
    if (length(missing_interval)) {
      stop(
        "Forecast rows require interval column(s): ",
        paste(missing_interval, collapse = ", "), "."
      )
    }
  }

  p <- ggplot2::ggplot()
  if (!is.null(history)) {
    if (!is.data.frame(history)) stop("`history` must be a data frame.")
    if (nrow(history)) {
      if (!"weekF" %in% names(history) && "newWeek" %in% names(history)) {
        history$weekF <- history$newWeek
      }
      bg <- prepare_surveillance_data(history)
      if (!"newWeek" %in% names(bg)) bg$newWeek <- bg$weekF
      bg$p_obs <- bg$p
      p <- p +
        ggplot2::geom_line(
          data = bg,
          ggplot2::aes(x = newWeek, y = p_obs, group = season),
          color = "grey75", alpha = 0.4
        )
    }
  }
  if (nrow(forecast)) {
    p <- p + ggplot2::geom_ribbon(
      data = forecast,
      ggplot2::aes(x = newWeek, ymin = p_lo, ymax = p_hi),
      fill = "steelblue", alpha = 0.20
    ) +
      ggplot2::geom_line(
        data = forecast,
        ggplot2::aes(x = newWeek, y = p_hat),
        color = "steelblue", linewidth = 1.2
      )
  }
  if (nrow(observed)) {
    p <- p + ggplot2::geom_point(
      data = observed,
      ggplot2::aes(x = newWeek, y = p_hat),
      color = "tomato", size = 2
    )
  }
  last_obs <- res$last_obs %||% {
    if (nrow(observed)) max(observed$newWeek, na.rm = TRUE) else NA_real_
  }
  if (length(last_obs) != 1L) stop("`res$last_obs` must be one week value.")
  if (is.finite(last_obs)) {
    p <- p + ggplot2::geom_vline(
      xintercept = last_obs, linetype = 2, color = "grey50"
    )
  }
  p +
    ggplot2::labs(x = "Week", y = "Probability", title = "PAGe forecast") +
    ggplot2::theme_minimal(base_size = 13)
}
