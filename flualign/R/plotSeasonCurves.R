#' Plot observed vs fitted positivity by season, with ignition week in title
#'
#' @param df Data frame containing at least: season, weekF, y, N, fit.
#'   Also needs either:
#'   - iWeek (ignition weekF repeated within season), OR
#'   - ignition (logical TRUE at ignition row)
#' @param x Character. X-axis column name (default "weekF").
#' @return A ggplot object.
#' @export
plotSeasonCurves <- function(df, x = "weekF") {
  stopifnot(
    is.data.frame(df),
    all(c("season", x, "y", "N", "fit") %in% names(df))
  )
  if (!requireNamespace("dplyr", quietly = TRUE)) stop("Need 'dplyr'.")
  if (!requireNamespace("ggplot2", quietly = TRUE)) stop("Need 'ggplot2'.")
  if (!requireNamespace("scales", quietly = TRUE)) stop("Need 'scales'.")
  
  df <- df %>%
    dplyr::mutate(
      p_obs = y / N,
      season = as.factor(as.character(season))
    )
  
  # compute ignition week per season (prefer iWeek if present)
  if ("iWeek" %in% names(df)) {
    title_map <- df %>%
      dplyr::group_by(season) %>%
      dplyr::summarise(iWeek = dplyr::first(stats::na.omit(iWeek)), .groups = "drop") %>%
      dplyr::mutate(
        title = ifelse(is.na(iWeek),
                       paste0(season, " (ign: NA)"),
                       paste0(season, " (ign: ", iWeek, ")"))
      )
  } else if ("ignition" %in% names(df)) {
    title_map <- df %>%
      dplyr::group_by(season) %>%
      dplyr::summarise(
        iWeek = dplyr::if_else(any(ignition, na.rm = TRUE),
                               df[[x]][which(ignition)[1]],
                               NA_integer_),
        .groups = "drop"
      ) %>%
      dplyr::mutate(
        title = ifelse(is.na(iWeek),
                       paste0(season, " (ign: NA)"),
                       paste0(season, " (ign: ", iWeek, ")"))
      )
  } else {
    stop("Need either 'iWeek' column or 'ignition' column to label titles.")
  }
  
  df <- df %>% dplyr::left_join(title_map, by = "season")
  
  # vertical ignition line data
  vline_df <- title_map %>% dplyr::filter(!is.na(iWeek))
  
  ggplot2::ggplot(df, ggplot2::aes(x = .data[[x]])) +
    ggplot2::geom_point(ggplot2::aes(y = p_obs), alpha = 0.6) +
    ggplot2::geom_line(ggplot2::aes(y = fit), linewidth = 0.9) +
    ggplot2::geom_vline(
      data = vline_df,
      ggplot2::aes(xintercept = iWeek),
      linetype = "dashed",
      linewidth = 0.6
    ) +
    ggplot2::facet_wrap(~ title, scales = "free_x") +
    ggplot2::scale_y_continuous(labels = scales::percent_format(accuracy = 0.1)) +
    ggplot2::labs(x = x, y = "Positivity", title = "Observed vs fitted positivity (by season)") +
    ggplot2::theme_bw()
}
