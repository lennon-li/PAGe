#' @export
# Plot helper
plot_forecast <- function(res, history = NULL) {
  p <- ggplot2::ggplot()
  if (!is.null(history)) {
    bg <- history %>% dplyr::mutate(p_obs = y / (y + neg))
    p <- p +
      ggplot2::geom_line(data = bg,
                         ggplot2::aes(x = newWeek, y = p_obs, group = season),
                         color = "grey75", alpha = 0.4)
  }
  p +
    ggplot2::geom_ribbon(
      data = subset(res$pred_df, kind == "forecast"),
      ggplot2::aes(x = newWeek, ymin = p_lo, ymax = p_hi),
      fill = "steelblue", alpha = 0.20
    ) +
    ggplot2::geom_line(
      data = subset(res$pred_df, kind == "forecast"),
      ggplot2::aes(x = newWeek, y = p_hat),
      color = "steelblue", linewidth = 1.2
    ) +
    ggplot2::geom_point(
      data = subset(res$pred_df, kind == "observed"),
      ggplot2::aes(x = newWeek, y = p_hat),
      color = "tomato", size = 2
    ) +
    ggplot2::geom_vline(xintercept = res$last_obs, linetype = 2, color = "grey50") +
    ggplot2::labs(x = "Week", y = "Probability", title = "flualign forecast") +
    ggplot2::theme_minimal(base_size = 13)
}
