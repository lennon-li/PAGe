# End-to-end deployment runtime for the prospective pipeline

load_prospective_kit <- function(data_dir,
                                 ref_file    = "ref_production.rds",
                                 m2_file     = "m2_production.rds",
                                 stage1_file = "stage1_tuning.rds") {
  `%||%` <- function(x, y) if (is.null(x)) y else x
  data_dir <- normalizePath(data_dir, mustWork = TRUE)

  # ---- Reference curve + hyperparams ----
  ref_path <- file.path(data_dir, ref_file)
  if (!file.exists(ref_path))
    stop("ref_production.rds not found at: ", ref_path,
         "\nRun estimateRef.html or forecast_training.html first.")
  ref_cache <- readRDS(ref_path)
  ref   <- ref_cache$ref
  hyper <- ref_cache$hyper

  # M1_PARAMS: stored alongside ref at training time (fallback to tuned defaults)
  M1_PARAMS <- ref_cache$M1_PARAMS %||% list(
    k_ref              = 25L,
    temperature        = 0.25,
    rise_weight        = 1.0,
    trough_weight      = 0.1,
    peak_decay         = 0.3,
    slope_weight       = 0.5,
    slope_window       = 4L,
    dynamic_temp       = TRUE,
    dynamic_temp_pivot = 10L
  )

  # ---- M2 production model ----
  m2_path <- file.path(data_dir, m2_file)
  if (!file.exists(m2_path))
    stop("m2_production.rds not found at: ", m2_path,
         "\nRun forecast_training.html first.")
  m2_production <- readRDS(m2_path)

  # best_spec: prefer stored in m2_production, else scan nested LOSO files
  best_spec <- m2_production$spec %||% {
    gs <- NULL
    for (fn in c("nested_loso_v4_production.rds",
                 "nested_loso_v3_production.rds",
                 "nested_loso_production.rds")) {
      p <- file.path(data_dir, fn)
      if (file.exists(p)) { gs <- readRDS(p); break }
    }
    if (!is.null(gs)) gs$best_spec else
      stage2_make_spec(delta = 0L, Kr = 1L, k_f = 2L, k_e = 4L,
                       alpha_state = 0.10, k_s = 0L, lambda_w = 0,
                       w_floor = 0.05)
  }

  # ---- M0 ignition params ----
  s1_path <- file.path(data_dir, stage1_file)
  if (!file.exists(s1_path))
    stop("stage1_tuning.rds not found at: ", s1_path)
  m0_params <- readRDS(s1_path)$best_params

  # ---- Static pipeline constants (prefer stored versions) ----
  flag_args <- ref_cache$flag_args %||% list(
    p_thresh = 0.01, k1 = 0.4, k_c = 0.01, n_consec = 2L,
    min_window = 10L, w_min = 21L, w_max = 21L, d2_relax = -0.01
  )
  manual_labels <- ref_cache$manual_labels %||% c(
    "2012-13" = 18L, "2013-14" = 20L, "2014-15" = 20L,
    "2015-16" = 24L, "2016-17" = 19L, "2017-18" = 20L,
    "2018-19" = 19L, "2019-20" = 22L, "2022-23" = 15L,
    "2023-24" = 20L, "2024-25" = 23L
  )

  list(
    ref           = ref,
    hyper         = hyper,
    M1_PARAMS     = M1_PARAMS,
    m0_params     = m0_params,
    m2_production = m2_production,
    best_spec     = best_spec,
    flag_args     = flag_args,
    manual_labels = manual_labels
  )
}


# ============================================================================
# Modular pipeline: run_m0_detection / run_m1_alignment / run_m2_forecast
# run_prospective_pipeline() is a thin wrapper calling all three in sequence.
# ============================================================================

#' Run M0 ignition detection for the current season
#'
#' Detects epidemic ignition from the current season data using pre-trained
#' M0 thresholds. Optionally overrides the automatic estimate with a manual
#' week. Returns the resolved ignition week and the full \code{run_ignition_weekly()}
#' output for downstream M1 alignment.
#'
#' @param kit A kit list returned by \code{load_prospective_kit()}.
#' @param current_data Data frame for the current season. Must contain
#'   \code{weekF}, \code{y}, \code{N}, \code{neg}, \code{p}.
#' @param manual_ign_week Integer or \code{NA_integer_}. When set, overrides
#'   the M0 automatic ignition estimate with a known value.
#' @param verbose Logical. Emit progress messages (default \code{TRUE}).
#'
#' @return A list with:
#'   \describe{
#'     \item{ign_out}{Full output of \code{run_ignition_weekly()}, with
#'       \code{iWeek_hat_locked} and \code{ign_week_locked} updated if
#'       overridden.}
#'     \item{iWeek_locked}{Resolved ignition week (\code{NA} if not detected).}
#'     \item{overridden}{Logical; \code{TRUE} if the manual override was applied.}
#'   }
#'
#' @export
run_m0_detection <- function(kit,
                              current_data,
                              manual_ign_week = NA_integer_,
                              verbose         = TRUE) {
  params <- kit$m0_params

  ign_out <- run_ignition_weekly(
    currentSeason  = current_data,
    ign_fit_or_gam = NULL,
    params         = params,
    start_week     = 1L
  )

  ign_resolved <- resolve_week_override(
    week_est      = ign_out$iWeek_hat_locked,
    override_week = manual_ign_week,
    mode          = "replace"
  )
  if (ign_resolved$overridden) {
    if (verbose) message(sprintf(
      "Manual ignition override: M0 estimated week %s, overriding to week %d.",
      ifelse(is.na(ign_resolved$est), "NA", as.character(ign_resolved$est)),
      ign_resolved$final
    ))
    ign_out$iWeek_hat_locked <- ign_resolved$final
    ign_out$ign_week_locked  <- ign_resolved$final
  } else if (!is.na(ign_resolved$final)) {
    if (verbose) message(sprintf("M0 ignition: week %d (automatic).",
                                 ign_resolved$final))
  } else {
    if (verbose) message("M0: no ignition detected yet.")
  }

  list(
    ign_out      = ign_out,
    iWeek_locked = ign_out$ign_week_locked,
    overridden   = ign_resolved$overridden
  )
}


#' Walk-forward M1 alignment for the current season
#'
#' For each evaluation week from ignition to the last observed week, aligns
#' the partial curve to reference templates using the 4-parameter dilation
#' model. Requires the output of \code{run_m0_detection()}.
#'
#' You may stop here if you only need peak detection (without M2 forecasts),
#' or override \code{m0_result$iWeek_locked} before passing to M1.
#'
#' @param kit A kit list returned by \code{load_prospective_kit()}.
#' @param current_data Data frame for the current season.
#' @param m0_result Output of \code{run_m0_detection()}.
#' @param walk_start Integer. Minimum evaluation week (default \code{5L}).
#'   Actual start is \code{max(walk_start, iWeek_locked)}.
#' @param verbose Logical. Emit progress messages (default \code{TRUE}).
#'
#' @return A list with:
#'   \describe{
#'     \item{params_df}{Tibble with one row per eval_week of alignment params.}
#'     \item{m1_curves}{Tibble of M1 forecast curves by eval_week.}
#'     \item{per_week}{List with one entry per eval_week; each entry holds
#'       \code{ew}, \code{ap} (raw alignment output), and \code{season_to_ew}
#'       (data slice). Passed to \code{run_m2_forecast()}.}
#'     \item{m0_result}{The M0 result passed in, carried forward for M2.}
#'   }
#'
#' @export
run_m1_alignment <- function(kit,
                              current_data,
                              m0_result,
                              walk_start = 5L,
                              verbose    = TRUE) {
  if (!requireNamespace("dplyr",  quietly = TRUE)) stop("Please install dplyr.")
  if (!requireNamespace("tibble", quietly = TRUE)) stop("Please install tibble.")
  `%||%` <- function(x, y) if (is.null(x)) y else x

  ref       <- kit$ref
  hyper     <- kit$hyper
  M1_PARAMS <- kit$M1_PARAMS
  ign_out   <- m0_result$ign_out

  walk_end <- max(current_data$weekF, na.rm = TRUE)
  actual_walk_start <- if (!is.na(m0_result$iWeek_locked)) {
    max(walk_start, as.integer(m0_result$iWeek_locked))
  } else {
    walk_start
  }
  eval_weeks <- seq(actual_walk_start, walk_end)

  per_week <- lapply(eval_weeks, function(ew) {
    season_to_ew <- dplyr::filter(current_data, weekF <= ew)

    ap <- tryCatch(
      run_alignment_prospective_multi(
        currentSeason      = season_to_ew,
        ref                = ref,
        hyper              = hyper,
        ign_out            = ign_out,
        use_ci             = TRUE,
        buffer_weeks       = 0L,
        allow_scale        = NULL,
        level              = 0.95,
        min_obs            = 4L,
        curvature_ratio    = 1.0,
        temperature        = M1_PARAMS$temperature,
        rise_weight        = M1_PARAMS$rise_weight,
        trough_weight      = M1_PARAMS$trough_weight,
        peak_decay         = M1_PARAMS$peak_decay,
        slope_weight       = M1_PARAMS$slope_weight,
        slope_window       = M1_PARAMS$slope_window,
        dynamic_temp       = M1_PARAMS$dynamic_temp,
        dynamic_temp_pivot = M1_PARAMS$dynamic_temp_pivot
      ),
      error = function(e) {
        if (verbose) message("M1 error at week ", ew, ": ", conditionMessage(e))
        NULL
      }
    )

    list(ew = ew, ap = ap, season_to_ew = season_to_ew)
  })

  params_df <- dplyr::bind_rows(lapply(per_week, function(pw) {
    ew <- pw$ew; ap <- pw$ap
    if (is.null(ap) || ap$state == "pre_ignition") {
      return(tibble::tibble(
        eval_week = ew, state = "pre_ignition",
        iWeek_hat = NA_integer_, tau = NA_real_,
        delta_m1 = NA_real_, a = NA_real_, b = NA_real_,
        t_peak = NA_real_, peak_weekF = NA_integer_,
        peak_passed = FALSE, fallback = NA_character_
      ))
    }
    tibble::tibble(
      eval_week   = ew,
      state       = ap$state,
      iWeek_hat   = ap$iWeek_hat,
      tau         = ap$tau,
      delta_m1    = ap$delta,
      a           = ap$a,
      b           = ap$b,
      t_peak      = ap$t_peak,
      peak_weekF  = ap$peak_weekF,
      peak_passed = ap$peak_passed,
      fallback    = ap$fallback_reason %||% NA_character_
    )
  }))

  m1_curves <- dplyr::bind_rows(lapply(per_week, function(pw) {
    if (is.null(pw$ap) || pw$ap$state == "pre_ignition") return(NULL)
    pw$ap$forecast_df |> dplyr::mutate(eval_week = pw$ew)
  }))

  list(
    params_df = params_df,
    m1_curves = m1_curves,
    per_week  = per_week,
    m0_result = m0_result
  )
}


#' Run M2 forecast using M1 alignment outputs
#'
#' For each evaluation week in \code{m1_result$per_week}, builds M2 covariates
#' from the M1 alignment output and predicts 1- and 2-week-ahead positivity
#' using the production GAM. Extrapolation guards (logN cap, soft positivity
#' ceiling) are applied automatically.
#'
#' @param kit A kit list returned by \code{load_prospective_kit()}.
#' @param current_data Data frame for the current season (used for raw covariate
#'   computation in M2 — the \code{season_to_ew} slices are carried in
#'   \code{m1_result$per_week}).
#' @param m1_result Output of \code{run_m1_alignment()}.
#' @param verbose Logical. Emit progress messages (default \code{TRUE}).
#'
#' @return A list with:
#'   \describe{
#'     \item{m2_preds}{Tibble of M2 predictions with columns
#'       \code{eval_week}, \code{h}, \code{target_weekF},
#'       \code{m1_p}, \code{m1_lo}, \code{m1_hi},
#'       \code{m2_p}, \code{m2_lo}, \code{m2_hi}.}
#'   }
#'
#' @export
run_m2_forecast <- function(kit,
                             current_data,
                             m1_result,
                             verbose = TRUE) {
  if (!requireNamespace("dplyr",  quietly = TRUE)) stop("Please install dplyr.")
  if (!requireNamespace("tibble", quietly = TRUE)) stop("Please install tibble.")
  `%||%` <- function(x, y) if (is.null(x)) y else x

  ref           <- kit$ref
  m2_production <- kit$m2_production
  best_spec     <- kit$best_spec
  m2_fit        <- m2_production$fit

  ex_terms <- best_spec$exclude_newseason
  if (is.null(ex_terms)) ex_terms <- stage2_exclude_newseason(best_spec)
  ex_terms   <- unique(c(ex_terms, "s(season)"))
  lev_lead   <- levels(m2_fit$model$lead)
  anchorWeek <- ref$anchorWeek

  # Extrapolation guards (derived from training data)
  logN_train_max <- max(m2_fit$model$logN_now, na.rm = TRUE)
  p_train    <- m2_fit$model[[1]][, 1] / rowSums(m2_fit$model[[1]])
  p_knee     <- as.numeric(stats::quantile(p_train, 0.95, na.rm = TRUE))
  p_train_max <- max(p_train, na.rm = TRUE)
  p_ceil     <- min(p_train_max + 0.5 * (p_train_max - p_knee), 1.0)
  soft_cap_p <- function(p) {
    above <- p > p_knee
    p[above] <- p_knee + (p_ceil - p_knee) *
      tanh((p[above] - p_knee) / (p_ceil - p_knee))
    p
  }
  if (verbose) cat(sprintf(
    "M2 extrapolation guards: logN cap=%.2f, p_knee=%.3f, p_ceil=%.3f\n",
    logN_train_max, p_knee, p_ceil
  ))

  m2_preds <- dplyr::bind_rows(lapply(m1_result$per_week, function(pw) {
    ew           <- pw$ew
    ap           <- pw$ap
    season_to_ew <- pw$season_to_ew

    if (is.null(ap) || ap$state == "pre_ignition") return(NULL)

    iWeek_hat <- ap$iWeek_hat
    fdf       <- ap$forecast_df
    horizons  <- c(1L, 2L)

    dplyr::bind_rows(lapply(horizons, function(h) {
      target_weekF   <- ew + h
      target_newWeek <- as.numeric(target_weekF - iWeek_hat + anchorWeek)

      m1_p  <- stats::approx(fdf$newWeek, fdf$p_hat, xout = target_newWeek, rule = 2)$y
      m1_lo <- stats::approx(fdf$newWeek, fdf$p_lo,  xout = target_newWeek, rule = 2)$y
      m1_hi <- stats::approx(fdf$newWeek, fdf$p_hi,  xout = target_newWeek, rule = 2)$y

      obs_to_ew <- season_to_ew |>
        dplyr::arrange(weekF) |>
        dplyr::mutate(
          p_now = y / pmax(N, 1L),
          z_now = qlogis(pmin(pmax(p_now, 1e-6), 1 - 1e-6))
        )

      alpha_s   <- as.numeric(best_spec$alpha_state %||% 0.25)
      z_vec     <- obs_to_ew$z_now
      z_ema     <- as.numeric(stats::filter(
        alpha_s * z_vec, filter = 1 - alpha_s,
        method = "recursive", init = z_vec[1]
      ))
      z_ema_now <- utils::tail(z_ema, 1)

      logN_now <- min(log(max(obs_to_ew$N[obs_to_ew$weekF == ew], 1)),
                      logN_train_max)

      d_deriv <- add_prospective_derivs_link(
        dplyr::transmute(obs_to_ew, season = "current", weekF, y, neg),
        k = 5L, eps = 1e-6
      )
      d_at_ew <- dplyr::filter(d_deriv, weekF == ew)
      d1_now  <- if (nrow(d_at_ew) > 0) d_at_ew$d1_link[1] else 0
      d2_now  <- if (nrow(d_at_ew) > 0) d_at_ew$d2_link[1] else 0

      logit_f_eff <- qlogis(pmin(pmax(m1_p, 1e-6), 1 - 1e-6))
      t_since     <- as.numeric(ew - iWeek_hat)

      nd <- tibble::tibble(
        weekF       = as.integer(ew),
        newWeek     = as.integer(ew - iWeek_hat + anchorWeek),
        lead        = factor(paste0("h", h), levels = lev_lead),
        season      = factor(levels(m2_fit$model$season)[1],
                             levels = levels(m2_fit$model$season)),
        logit_f_eff = logit_f_eff,
        z_ema       = z_ema_now,
        logN_now    = logN_now,
        d1_now      = d1_now,
        d2_now      = d2_now,
        t_since     = t_since,
        post_ign    = TRUE
      )
      if ("season_h" %in% names(m2_fit$model)) {
        lev_sh <- levels(m2_fit$model$season_h)
        nd$season_h <- factor(lev_sh[1], levels = lev_sh)
      }

      pr <- tryCatch(
        stats::predict(m2_fit, newdata = nd, type = "link",
                       se.fit = TRUE, exclude = ex_terms),
        error = function(e) NULL
      )
      if (is.null(pr)) {
        return(tibble::tibble(
          eval_week = ew, h = h, target_weekF = target_weekF,
          m1_p = m1_p, m1_lo = m1_lo, m1_hi = m1_hi,
          m2_p = NA_real_, m2_lo = NA_real_, m2_hi = NA_real_
        ))
      }

      eta <- as.numeric(pr$fit)
      se  <- as.numeric(pr$se.fit)
      tibble::tibble(
        eval_week = ew, h = h, target_weekF = target_weekF,
        m1_p = m1_p, m1_lo = m1_lo, m1_hi = m1_hi,
        m2_p  = soft_cap_p(stats::plogis(eta)),
        m2_lo = soft_cap_p(stats::plogis(eta - 1.96 * se)),
        m2_hi = soft_cap_p(stats::plogis(eta + 1.96 * se))
      )
    }))
  }))

  list(m2_preds = m2_preds)
}


#' Run the full M0 -> M1 -> M2 walk-forward pipeline for one season
#'
#' Thin wrapper around \code{run_m0_detection()}, \code{run_m1_alignment()},
#' and \code{run_m2_forecast()}. Use the individual functions directly if you
#' need to inspect intermediate results, override the ignition week, or stop
#' after peak detection without running M2.
#'
#' @param kit A kit list returned by \code{load_prospective_kit()}.
#' @param current_data Data frame for the current season.
#' @param walk_start Integer. Minimum evaluation week (default \code{5L}).
#' @param manual_ign_week Integer or \code{NA_integer_}. Manual ignition override.
#' @param verbose Logical. Emit progress messages (default \code{TRUE}).
#'
#' @return A list with \code{params_df}, \code{m1_curves}, \code{m2_preds},
#'   \code{ign_out} — compatible with the prospective deployment QMD.
#'
#' @export
run_prospective_pipeline <- function(kit,
                                     current_data,
                                     walk_start      = 5L,
                                     manual_ign_week = NA_integer_,
                                     verbose         = TRUE) {
  m0 <- run_m0_detection(kit, current_data,
                          manual_ign_week = manual_ign_week, verbose = verbose)
  m1 <- run_m1_alignment(kit, current_data,
                          m0_result = m0, walk_start = walk_start, verbose = verbose)
  m2 <- run_m2_forecast(kit, current_data,
                         m1_result = m1, verbose = verbose)
  list(
    params_df = m1$params_df,
    m1_curves = m1$m1_curves,
    m2_preds  = m2$m2_preds,
    ign_out   = m0$ign_out
  )
}
