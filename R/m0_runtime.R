# M0 runtime utilities for weekly ignition monitoring

run_ignition_weekly <- function(currentSeason,
                                ign_fit_or_gam = NULL,
                                params,
                                start_week = 5L,
                                week_col = "weekF") {
  stopifnot(is.data.frame(currentSeason), is.list(params))
  if (!requireNamespace("dplyr", quietly = TRUE)) stop("Please install dplyr.")
  if (!requireNamespace("tibble", quietly = TRUE)) stop("Please install tibble.")

  # detectIgnition_oneSeason is now exported from the package

  use_cls <- isTRUE(params$use_cls)
  if (!is.null(ign_fit_or_gam)) {
    gam_cls <- get_gam_cls(ign_fit_or_gam)
  } else if (use_cls) {
    stop("ign_fit_or_gam must be provided when params$use_cls = TRUE")
  } else {
    gam_cls <- NULL
  }
  
  d0 <- dplyr::as_tibble(currentSeason) %>%
    dplyr::transmute(
      season = if ("season" %in% names(.)) as.character(.data$season) else NA_character_,
      weekF  = as.integer(.data[[week_col]]),
      y      = as.integer(.data$y),
      N      = if ("N" %in% names(.)) as.integer(.data$N) else as.integer(.data$y + .data$neg),
      neg    = if ("neg" %in% names(.)) as.integer(.data$neg) else as.integer(.data$N - .data$y),
      p      = if ("p" %in% names(.)) as.numeric(.data$p) else .data$y / pmax(.data$y + .data$neg, 1L)
    ) %>%
    dplyr::filter(!is.na(.data$weekF), is.finite(.data$weekF), .data$weekF >= 1L) %>%
    dplyr::mutate(weekF = pmin(.data$weekF, 52L)) %>%
    dplyr::arrange(.data$weekF) %>%
    dplyr::group_by(.data$season, .data$weekF) %>%
    dplyr::summarise(
      y = sum(.data$y, na.rm = TRUE),
      N = sum(.data$N, na.rm = TRUE),
      neg = sum(.data$neg, na.rm = TRUE),
      p = .data$y / pmax(.data$y + .data$neg, 1L),
      .groups = "drop"
    )
  
  weeks_all  <- sort(unique(d0$weekF))
  weeks_eval <- weeks_all[weeks_all >= as.integer(start_week)]
  if (!length(weeks_eval)) {
    out_df <- tibble::tibble(weekF = integer(), iWeek_hat_dynamic = integer())
    return(list(
      df = out_df,
      iWeek_hat_dynamic_last = NA_integer_,
      iWeek_hat_locked = NA_integer_,
      ign_week_locked = NA_integer_
    ))
  }
  
  rows <- lapply(weeks_eval, function(w) {
    d_now <- d0 %>%
      dplyr::filter(.data$weekF <= w) %>%
      dplyr::mutate(p_cls_p = if (!is.null(gam_cls))
        as.numeric(stats::predict(gam_cls, newdata = ., type = "response"))
      else
        0)
    
    det <- detectIgnition_oneSeason(as.data.frame(d_now), params = params)
    now <- det$now %||% data.frame()
    
    p_now_fallback       <- tail(d_now$p, 1)
    cum_p_now_fallback   <- sum(d_now$p, na.rm = TRUE)
    prev_now_fallback    <- sum(d_now$y, na.rm = TRUE) / pmax(sum(d_now$N, na.rm = TRUE), 1)
    p_cls_p_now_fallback <- tail(d_now$p_cls_p, 1)
    
    p_now       <- now$p_now       %||% p_now_fallback
    cum_p_now   <- now$cum_p_now   %||% cum_p_now_fallback
    prev_now    <- now$prev_now    %||% prev_now_fallback
    p_cls_p_now <- now$p_cls_p_now %||% p_cls_p_now_fallback
    n_hit_now   <- now$n_hit_now   %||% NA_integer_
    
    d1_last <- now$d1_last %||% NA_real_
    d2_last <- now$d2_last %||% NA_real_
    
    ok_w_inrange <- now$cond_win  %||% NA
    ok_cls       <- now$cond_cls  %||% NA
    ok_cum_p     <- now$cond_cum  %||% NA
    ok_p         <- now$cond_p    %||% NA
    ok_prev      <- now$cond_prev %||% NA
    ok_nconsec   <- now$cond_inc  %||% NA
    
    ignite_ok_now <- now$ignite_ok_now %||% NA
    
    tibble::tibble(
      weekF = as.integer(w),
      p_now = as.numeric(p_now),
      cum_p_now = as.numeric(cum_p_now),
      prev_now = as.numeric(prev_now),
      p_cls_p_now = as.numeric(p_cls_p_now),
      n_hit_now = if (is.null(n_hit_now)) NA_integer_ else as.integer(n_hit_now),
      d1_last = as.numeric(d1_last),
      d2_last = as.numeric(d2_last),
      ok_w_inrange = as.logical(ok_w_inrange),
      ok_cls = as.logical(ok_cls),
      ok_p = as.logical(ok_p),
      ok_cum_p = as.logical(ok_cum_p),
      ok_prev = as.logical(ok_prev),
      ok_n_consec = as.logical(ok_nconsec),
      ignite_ok_now = as.logical(ignite_ok_now),
      iWeek_hat_dynamic = if (is.null(det$iWeek_hat)) NA_integer_ else as.integer(det$iWeek_hat)
    )
  })
  
  df <- dplyr::bind_rows(rows)
  
  ign_week_locked <- suppressWarnings(min(df$weekF[df$ignite_ok_now %in% TRUE], na.rm = TRUE))
  ign_week_locked <- ifelse(is.infinite(ign_week_locked), NA_integer_, as.integer(ign_week_locked))
  
  iwh_locked <- suppressWarnings(min(df$iWeek_hat_dynamic, na.rm = TRUE))
  iwh_locked <- ifelse(is.infinite(iwh_locked), NA_integer_, as.integer(iwh_locked))

  list(
    df = df,
    iWeek_hat_dynamic_last = df$iWeek_hat_dynamic[nrow(df)],
    iWeek_hat_locked = iwh_locked,
    ign_week_locked = ign_week_locked
  )
}

#' Extract Stage-2 hyperparameters from tuning output
#'
#' Helper to pull commonly used Stage-2 hyperparameters from a list or 1-row data.frame,
#' supporting alternate names (e.g., \code{shift} for \code{delta}).
#'
#' @param best_mean_nll A list or 1-row data.frame containing tuned parameters. Looks for
#'   \code{delta} (or \code{shift}), \code{K}, \code{leads}, and optionally \code{use_ramp}.
#'
#' @return A list with elements \code{delta}, \code{K}, \code{leads}, \code{use_ramp}, and \code{extra}.


plot_ignition_weekly_snapshots <- function(ign_out,
                                           currentSeason = NULL,
                                           facet = TRUE,
                                           ncol = 4,
                                           base_size = 11,
                                           y_max = 0.20,
                                           start_week = 5L,
                                           maxWeek = Inf,
                                           week_col = "weekF",
                                           y_col = "y",
                                           N_col = "N",
                                           p_col = "p",
                                           date_col = "date") {
  stopifnot(is.list(ign_out), "df" %in% names(ign_out))
  if (!requireNamespace("dplyr", quietly = TRUE)) stop("Need dplyr.")
  if (!requireNamespace("tidyr", quietly = TRUE)) stop("Need tidyr.")
  if (!requireNamespace("ggplot2", quietly = TRUE)) stop("Need ggplot2.")
  if (!requireNamespace("tibble", quietly = TRUE)) stop("Need tibble.")
  
  df <- dplyr::as_tibble(ign_out$df)
  if (!("weekF" %in% names(df))) stop("ign_out$df must contain weekF.")
  
  start_week <- as.integer(start_week)
  if (!is.finite(start_week)) start_week <- 1L
  
  maxWeek_in <- maxWeek
  maxWeek <- suppressWarnings(as.integer(maxWeek))
  if (!is.finite(maxWeek_in) || is.na(maxWeek)) maxWeek <- Inf
  
  df <- df %>%
    dplyr::mutate(weekF = as.integer(.data$weekF)) %>%
    dplyr::arrange(.data$weekF)
  
  # snapshots to include, sorted numerically
  w_seq <- df$weekF[df$weekF >= start_week & df$weekF <= maxWeek]
  w_seq <- sort(unique(w_seq))
  if (!length(w_seq)) stop("No weeks to plot: check start_week/maxWeek vs ign_out$df$weekF.")
  
  # effective maxWeek for xlim
  maxWeek_eff <- if (is.finite(maxWeek)) maxWeek else max(w_seq, na.rm = TRUE)
  x_end_weekF <- as.integer(maxWeek_eff + 1L)  # <-- requested: maxWeek + 1
  x_start_weekF <- as.integer(start_week)
  
  # ----- observed series (per weekF) -----
  has_date <- FALSE
  if (!is.null(currentSeason)) {
    obs <- dplyr::as_tibble(currentSeason)
    if (!(week_col %in% names(obs))) stop("currentSeason missing week column: ", week_col)
    
    has_p  <- p_col %in% names(obs)
    has_yN <- all(c(y_col, N_col) %in% names(obs))
    if (!has_p && !has_yN) stop("currentSeason must have either ", p_col, " or (", y_col, ", ", N_col, ").")
    
    has_date <- date_col %in% names(obs) && any(!is.na(obs[[date_col]]))
    
    obs <- obs %>%
      dplyr::transmute(
        weekF = as.integer(.data[[week_col]]),
        date  = if (has_date) as.Date(.data[[date_col]]) else as.Date(NA),
        y     = if (has_yN) as.numeric(.data[[y_col]]) else NA_real_,
        N     = if (has_yN) as.numeric(.data[[N_col]]) else NA_real_,
        p_raw = if (has_p)  as.numeric(.data[[p_col]]) else NA_real_
      ) %>%
      dplyr::filter(is.finite(.data$weekF), .data$weekF >= start_week) %>%
      dplyr::group_by(.data$weekF) %>%
      dplyr::summarise(
        date = if (has_date) min(.data$date, na.rm = TRUE) else as.Date(NA),
        p = dplyr::if_else(
          all(is.na(.data$y)) || all(is.na(.data$N)),
          mean(.data$p_raw, na.rm = TRUE),
          sum(.data$y, na.rm = TRUE) / pmax(sum(.data$N, na.rm = TRUE), 1)
        ),
        .groups = "drop"
      ) %>%
      dplyr::arrange(.data$weekF)
  } else {
    if (!("p_now" %in% names(df))) stop("No currentSeason provided and ign_out$df has no p_now.")
    obs <- df %>%
      dplyr::transmute(weekF = .data$weekF, date = as.Date(NA), p = as.numeric(.data$p_now)) %>%
      dplyr::filter(is.finite(.data$p), .data$weekF >= start_week) %>%
      dplyr::arrange(.data$weekF)
  }
  
  xvar <- if (has_date) "date" else "weekF"
  
  # map weekF -> date for xlim when date axis is used
  week_to_date <- function(w) {
    w <- as.integer(w)
    m <- obs %>% dplyr::filter(!is.na(.data$date)) %>% dplyr::select(.data$weekF, .data$date)
    if (nrow(m) == 0) return(as.Date(NA))
    
    hit <- m$date[match(w, m$weekF)]
    if (!is.na(hit)) return(hit)
    
    # extrapolate using nearest available date (weekly step = 7 days)
    if (w > max(m$weekF, na.rm = TRUE)) {
      w0 <- max(m$weekF, na.rm = TRUE)
      d0 <- m$date[which.max(m$weekF)]
      return(d0 + 7L * (w - w0))
    } else {
      w0 <- min(m$weekF, na.rm = TRUE)
      d0 <- m$date[which.min(m$weekF)]
      return(d0 - 7L * (w0 - w))
    }
  }
  
  xlim_vec <- if (has_date) {
    c(week_to_date(x_start_weekF), week_to_date(x_end_weekF))
  } else {
    c(x_start_weekF, x_end_weekF)
  }
  
  # ----- ignition lock info (scalar) -----
  ign_week_locked  <- if (!is.null(ign_out$ign_week_locked))  as.integer(ign_out$ign_week_locked)  else NA_integer_
  iWeek_hat_locked <- if (!is.null(ign_out$iWeek_hat_locked)) as.integer(ign_out$iWeek_hat_locked) else NA_integer_
  lock_ok <- is.finite(ign_week_locked) && !is.na(ign_week_locked) &&
    is.finite(iWeek_hat_locked) && !is.na(iWeek_hat_locked)
  
  # per-snapshot meta: snapshot factor is ordered by numeric week
  snap_tbl <- tibble::tibble(asof_weekF = w_seq) %>%
    dplyr::mutate(
      detected_by_now = lock_ok & (.data$asof_weekF >= ign_week_locked),
      iWeek_plot = dplyr::if_else(.data$detected_by_now, iWeek_hat_locked, NA_integer_),
      ign_col    = dplyr::if_else(.data$detected_by_now, "red", "black"),
      snapshot   = factor(paste0("asof_", .data$asof_weekF),
                          levels = paste0("asof_", w_seq))
    )
  
  # attach x positions and observed p at as-of
  snap_tbl <- snap_tbl %>%
    dplyr::left_join(
      obs %>% dplyr::transmute(weekF = .data$weekF, x = .data[[xvar]], p = .data$p),
      by = c("asof_weekF" = "weekF")
    ) %>%
    dplyr::rename(asof_x = .data$x, asof_p = .data$p)
  
  # ignition line x position (only for detected snapshots)
  ign_line <- snap_tbl %>%
    dplyr::filter(.data$detected_by_now, !is.na(.data$iWeek_plot)) %>%
    dplyr::left_join(
      obs %>% dplyr::transmute(weekF = .data$weekF, x = .data[[xvar]]),
      by = c("iWeek_plot" = "weekF")
    ) %>%
    dplyr::rename(ign_x = .data$x)
  
  # all points up to as-of (>= start_week), with red points only after locked ignition
  plot_dat <- tidyr::crossing(asof_weekF = w_seq, weekF = obs$weekF) %>%
    dplyr::filter(.data$weekF <= .data$asof_weekF, .data$weekF >= start_week) %>%
    dplyr::left_join(
      obs %>% dplyr::transmute(weekF = .data$weekF, x = .data[[xvar]], p = .data$p),
      by = "weekF"
    ) %>%
    dplyr::left_join(
      snap_tbl %>% dplyr::select(.data$asof_weekF, .data$snapshot, .data$detected_by_now, .data$iWeek_plot),
      by = "asof_weekF"
    ) %>%
    dplyr::mutate(
      point_col = dplyr::if_else(.data$detected_by_now & !is.na(.data$iWeek_plot) & (.data$weekF >= .data$iWeek_plot),
                                 "red", "black")
    ) %>%
    dplyr::arrange(.data$asof_weekF, .data$weekF)
  
  make_one <- function(asof_w) {
    asof_w <- as.integer(asof_w)
    dat <- plot_dat %>% dplyr::filter(.data$asof_weekF == asof_w)
    snap_info <- snap_tbl %>% dplyr::filter(.data$asof_weekF == asof_w)
    ign_info  <- ign_line %>% dplyr::filter(.data$asof_weekF == asof_w)
    
    p <- ggplot2::ggplot(dat, ggplot2::aes(x = .data$x, y = .data$p)) +
      ggplot2::geom_line(linewidth = 0.6, alpha = 0.6, color = "grey40", na.rm = TRUE) +
      ggplot2::geom_point(ggplot2::aes(color = .data$point_col), size = 1.6, na.rm = TRUE) +
      ggplot2::geom_vline(
        data = snap_info,
        ggplot2::aes(xintercept = .data$asof_x),
        color = "grey60", linewidth = 0.6, inherit.aes = FALSE
      ) +
      ggplot2::geom_point(
        data = snap_info,
        ggplot2::aes(x = .data$asof_x, y = .data$asof_p, color = .data$ign_col),
        size = 3.0, inherit.aes = FALSE, na.rm = TRUE
      )
    
    if (nrow(ign_info) > 0) {
      p <- p + ggplot2::geom_vline(
        data = ign_info,
        ggplot2::aes(xintercept = .data$ign_x),
        color = "red", linetype = "dashed", linewidth = 0.9, inherit.aes = FALSE
      )
    }
    
    p +
      ggplot2::scale_color_identity() +
      ggplot2::coord_cartesian(ylim = c(0, y_max), xlim = xlim_vec) +  # <-- NEW xlim
      ggplot2::labs(
        x = xvar, y = "p (observed)",
        title = paste0("asof_", asof_w,
                       " | detected = ", ifelse(snap_info$detected_by_now[1], "yes", "no"),
                       " | iWeek_hat_locked = ", ifelse(lock_ok, iWeek_hat_locked, "NA"))
      ) +
      ggplot2::theme_minimal(base_size = base_size) +
      ggplot2::theme(panel.grid.minor = ggplot2::element_blank())
  }
  
  if (isTRUE(facet)) {
    p <- ggplot2::ggplot(plot_dat, ggplot2::aes(x = .data$x, y = .data$p)) +
      ggplot2::geom_line(linewidth = 0.6, alpha = 0.6, color = "grey40", na.rm = TRUE) +
      ggplot2::geom_point(ggplot2::aes(color = .data$point_col), size = 1.2, na.rm = TRUE) +
      ggplot2::geom_vline(
        data = snap_tbl,
        ggplot2::aes(xintercept = .data$asof_x),
        color = "grey60", linewidth = 0.5, inherit.aes = FALSE
      ) +
      ggplot2::geom_point(
        data = snap_tbl,
        ggplot2::aes(x = .data$asof_x, y = .data$asof_p, color = .data$ign_col),
        size = 2.3, inherit.aes = FALSE, na.rm = TRUE
      )
    
    if (nrow(ign_line) > 0) {
      p <- p + ggplot2::geom_vline(
        data = ign_line,
        ggplot2::aes(xintercept = .data$ign_x),
        color = "red", linetype = "dashed", linewidth = 0.8, inherit.aes = FALSE
      )
    }
    
    p +
      ggplot2::scale_color_identity() +
      ggplot2::coord_cartesian(ylim = c(0, y_max), xlim = xlim_vec) +  # <-- NEW xlim
      ggplot2::labs(x = xvar, y = "p (observed)") +
      ggplot2::theme_minimal(base_size = base_size) +
      ggplot2::theme(panel.grid.minor = ggplot2::element_blank()) +
      ggplot2::facet_wrap(~ snapshot, ncol = ncol, scales = "fixed")
  } else {
    out <- lapply(w_seq, make_one)
    names(out) <- paste0("asof_", w_seq)
    out
  }
}

# ============================================================================
# Deployment helpers: load_prospective_kit() and run_prospective_pipeline()
# ============================================================================

#' Load pre-built model artifacts for prospective deployment
#'
#' Reads all offline-trained components from \code{data_dir} and returns them
#' as a named list ("kit") ready for \code{run_prospective_pipeline()}.
#' All heavy training (reference curve, M1 LOSO, M2 nested LOSO) is assumed
#' to have been completed beforehand.
#'
#' @param data_dir Path to the data directory containing the RDS files.
#' @param ref_file    Filename of the production reference cache
#'   (\code{ref_production.rds} by default).
#' @param m2_file     Filename of the production M2 model
#'   (\code{m2_production.rds} by default).
#' @param stage1_file Filename of the M0 ignition tuning results
#'   (\code{stage1_tuning.rds} by default).
#'
#' @return A list with slots: \code{ref}, \code{hyper}, \code{M1_PARAMS},
#'   \code{m0_params}, \code{m2_production}, \code{best_spec},
#'   \code{flag_args}, \code{manual_labels}.
#'
