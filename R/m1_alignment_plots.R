#' Plot multiple aligned curves (full season) as observation window grows
#'
#' @param currentSeason data frame with at least:
#'   newWeek, weekF, y, neg, date (date can be NA; will be derived).
#' @param season character like "2017-2018" (you already use this).
#' @param startWeek integer, starting week-of-year for the template season.
#' @param start_cut_week epidemiologic week (in `currentSeason$week`) at which
#'   you start re-fitting (e.g. 44).
#' @param g_ref_fun reference spline on link scale.
#' @param g_ref_mu_se function(u) returning list(mu, se) from GAM.
#' @param hyper list from learn_alignment_hyperparams().
#' @param ref_df data frame with reference curve, typically having
#'   `newWeek` and `p_gamm`.
#' @param allow_scale base setting passed to align_forecast_pipeline_dilate()
#'   if no override is triggered (can be TRUE/FALSE/NULL).
#' @param force_allow_scale_from_week epi week; from this week onward
#'   (in surveillance-week space) we FORCE allow_scale = TRUE for that cut.
#'   Before that, we use `allow_scale` as given (including NULL).
#' @param max_newWeek optional scalar (aligned newWeek). If non-NULL, do not
#'   fit cuts whose last observed newWeek exceeds this. Each fitted cut still
#'   forecasts out to the season end.
#' @param peak_newWeek optional scalar in newWeek space giving the (known)
#'   epidemic peak location. For cuts with last observed newWeek >= peak_newWeek,
#'   use a GAM tail (from `forecast_post_peak_gam`) for newWeek > cut, instead
#'   of continued alignment-based extrapolation.
#' @param k_smooth_post basis dimension for the post-peak GAM tail.
#' @param use_weights logical, passed to pipeline.
#' @param level CI level.
#'
#' @return plotly object with all curves; each cut has its own legend entry.
#' @export
plot_alignment_evolution <- function(currentSeason,
                                     season,
                                     startWeek,
                                     start_cut_week,
                                     g_ref_fun,
                                     g_ref_mu_se,
                                     hyper,
                                     ref_df,
                                     allow_scale = NULL,
                                     force_allow_scale_from_week = NULL,
                                     max_newWeek = 52,
                                     peak_newWeek = NULL,
                                     k_smooth_post = 8,
                                     use_weights = TRUE,
                                     level = 0.95) {
  
  # ---- Basic checks ----
  needed_cols <- c("newWeek", "week", "weekF", "y", "neg")
  missing <- setdiff(needed_cols, names(currentSeason))
  if (length(missing) > 0) {
    stop("currentSeason is missing columns: ",
         paste(missing, collapse = ", "))
  }
  
  # 1) translate start_cut_week (epi week-of-year) -> starting newWeek
  start_newWeek <- currentSeason %>%
    dplyr::filter(.data$week == !!start_cut_week) %>%
    dplyr::summarise(min_nw = min(.data$newWeek, na.rm = TRUE)) %>%
    dplyr::pull(.data$min_nw)
  
  if (!is.finite(start_newWeek)) {
    stop("start_cut_week = ", start_cut_week,
         " not found in currentSeason$week")
  }
  
  last_obs_newWeek <- max(currentSeason$newWeek, na.rm = TRUE)
  
  # apply max_newWeek limit for which cuts we FIT
  if (!is.null(max_newWeek)) {
    if (!is.numeric(max_newWeek) || length(max_newWeek) != 1L || !is.finite(max_newWeek)) {
      stop("max_newWeek must be a single finite numeric")
    }
    last_cut_newWeek <- min(last_obs_newWeek, max_newWeek)
  } else {
    last_cut_newWeek <- last_obs_newWeek
  }
  
  if (last_cut_newWeek < start_newWeek) {
    stop("max_newWeek < start_newWeek; no cuts to fit.")
  }
  
  # all cut points in "newWeek" space (truncated only for *fitting*)
  cut_newWeeks <- seq(from = start_newWeek, to = last_cut_newWeek, by = 1L)
  
  # map each newWeek cut to its surveillance week (currentSeason$week)
  cut_info <- tibble::tibble(cut_newWeek = cut_newWeeks) %>%
    dplyr::left_join(
      currentSeason %>%
        dplyr::select(newWeek, week) %>%
        dplyr::distinct(),
      by = c("cut_newWeek" = "newWeek")
    )
  
  # legend labels in *surveillance week* space
  cut_labels <- paste0("≤ week ", cut_info$week)
  
  start_year <- as.integer(substr(season, 1, 4))
  max_newWeek_season <- if (!is.null(max_newWeek)) as.integer(max_newWeek) else max(currentSeason$newWeek, na.rm = TRUE)

  
  # ---- helper: build xD from a res object ----
  build_xD <- function(res, season_label) {
    res$pred_df %>%
      dplyr::left_join(
        currentSeason %>%
          dplyr::select(date, newWeek = .data$weekF),
        by = "newWeek"
      ) %>%
      tibble::add_column(season = season_label) %>%
      dplyr::mutate(
        date       = as.Date(.data$date),
        start_year = start_year,
        nW_true    = n_weeks_in_start_year(start_year),
        week       = ((.data$newWeek + startWeek - 2L) %% .data$nW_true) + 1L,
        mmwr_year  = ifelse(.data$week >= 35L, start_year, start_year + 1L),
        Rdate      = MMWRweek::MMWRweek2Date(.data$mmwr_year, .data$week, 1L),
        date       = as.Date(ifelse(is.na(.data$date), .data$Rdate, .data$date))
      ) %>%
      dplyr::left_join(ref_df, by = "newWeek")
  }
  
  # ---- Optional: global post-peak GAM tail (used only if peak_newWeek not NULL) ----
  xD_post_template <- NULL
  if (!is.null(peak_newWeek)) {
    post_gam_res <- flualign::forecast_post_peak_gam(
      currentSeason = currentSeason,
      g_ref_fun     = g_ref_fun,
      max_newWeek   = max_newWeek_season,
      k_smooth      = k_smooth_post,
      use_weights   = use_weights,
      level         = level
    )
    xD_post_template <- build_xD(post_gam_res, season_label = season)
  }
  
  # ---- 2) loop over cuts, refit, build xD for each ----
  all_xD <- purrr::map2_dfr(
    cut_newWeeks,
    cut_labels,
    function(cn, lab) {
      
      # data up to this cut
      currentD_cut <- currentSeason %>%
        dplyr::filter(.data$newWeek <= cn) %>%
        dplyr::select(.data$newWeek, .data$y, .data$neg)
      
      # epi-week of the last observation in this cut (surveillance-week scale)
      epi_last <- currentSeason %>%
        dplyr::filter(.data$newWeek == cn) %>%
        dplyr::summarise(w = max(.data$week, na.rm = TRUE)) %>%
        dplyr::pull(.data$w)
      
      # decide allow_scale for THIS cut:
      allow_scale_cut <-
        if (!is.null(force_allow_scale_from_week) &&
            is.finite(epi_last) &&
            epi_last >= force_allow_scale_from_week) {
          TRUE
        } else {
          allow_scale   # TRUE/FALSE/NULL
        }
      
      # alignment-based fit for this cut (full-season prediction)
      res_align <- align_forecast_pipeline_dilate(
        currentD    = currentD_cut,
        g_ref_fun   = g_ref_fun,
        g_ref_mu_se = g_ref_mu_se,
        hyper       = hyper,
        allow_scale = allow_scale_cut,
        use_weights = use_weights,
        level       = level
      )
      
      xD_align <- build_xD(res_align, season_label = season)
      
      # If no peak_newWeek provided OR this cut is before peak -> pure alignment
      if (is.null(peak_newWeek) || cn < peak_newWeek || is.null(xD_post_template)) {
        return(
          xD_align %>%
            dplyr::mutate(cut_label = lab)
        )
      }
      
      # Otherwise: peak has (in truth) occurred already, so:
      # - use alignment up to the cut newWeek
      # - use GAM tail (from xD_post_template) after the cut
      
      x_pre <- xD_align %>%
        dplyr::filter(.data$newWeek <= cn)
      
      x_tail <- xD_post_template %>%
        dplyr::filter(.data$newWeek > cn) %>%
        dplyr::mutate(
          # for this hypothetical cut, everything after cn is "forecast"
          kind = "forecast"
        )
      
      dplyr::bind_rows(x_pre, x_tail) %>%
        dplyr::arrange(.data$newWeek) %>%
        dplyr::mutate(cut_label = lab)
    }
  )
  
  # ---- 3) single ggplot with many curves (each full season curve) ----
  p <- ggplot2::ggplot(all_xD, ggplot2::aes(x = .data$date, y = .data$p_hat)) +
    ggplot2::geom_ribbon(
      ggplot2::aes(
        ymin   = .data$p_lo,
        ymax   = .data$p_hi,
        fill   = .data$cut_label,
        group  = .data$cut_label
      ),
      alpha = 0.15,
      colour = NA
    ) +
    ggplot2::geom_line(
      ggplot2::aes(
        colour = .data$cut_label,
        group  = .data$cut_label
      ),
      linewidth = 0.7
    ) +
    ggplot2::geom_point(
      data = all_xD %>% dplyr::filter(.data$kind == "observed"),
      ggplot2::aes(x = .data$date, y = .data$p_hat),
      inherit.aes = FALSE,
      colour = "black",
      size = 1.5
    ) +
    ggplot2::geom_line(
      ggplot2::aes(y = .data$p_gamm),
      colour = "steelblue",
      linewidth = 0.9,
      inherit.aes = TRUE
    ) +
    ggplot2::scale_x_date(
      breaks = all_xD$date,
      labels = all_xD$week
    ) +
    ggplot2::ylab("Percentage Positivity") +
    ggplot2::xlab("Surveillance Week") +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(
      axis.text.x = ggplot2::element_text(
        angle = 90, vjust = 0.5, hjust = 1
      )
    ) +
    ggplot2::labs(
      colour = "Cut at",
      fill   = "Cut at",
      title  = paste0("Alignment evolution for ", season),
      subtitle = paste0(
        "Curves re-fitted from week ", start_cut_week,
        " to ", max(currentSeason$week, na.rm = TRUE),
        if (!is.null(max_newWeek))
          paste0("; last alignment cut at newWeek ", last_cut_newWeek)
        else "",
        if (!is.null(peak_newWeek))
          paste0("; post-peak tail from GAM (peak newWeek ≈ ", peak_newWeek, ")")
        else ""
      )
    )
  
  p_multi <- plotly::ggplotly(
    p,
    tooltip = c("cut_label", "date", "week", "p_hat", "p_lo", "p_hi", "kind")
  )
  
  # clean legend names (remove "(...,1)" junk from ggplotly)
  for (i in seq_along(p_multi$x$data)) {
    nm <- p_multi$x$data[[i]]$name
    if (!is.null(nm) && nzchar(nm)) {
      nm_clean <- sub("^\\(([^,]+),.*\\)$", "\\1", nm)
      p_multi$x$data[[i]]$name <- nm_clean
    }
  }
  
  p_multi
}
