# ============================================================
# M1 → M2 Bridge: Generate M1 walk-forward predictions
# for use as M2 training features (stacking architecture)
# ============================================================

#' Run M1 walk-forward for one season and collect predictions at target weeks
#'
#' For each evaluation week, runs \code{run_alignment_prospective()} and
#' extracts M1's template-based prediction at each forecast target week
#' (weekF + h). Returns a tidy tibble suitable for joining to M2 training data.
#'
#' @param seasonD Data frame for ONE season (all weeks). Must have
#'   columns \code{weekF}, \code{y}, and either \code{N} or \code{neg}.
#' @param ref Output from \code{estimateRef()} (pre-computed from training data).
#' @param hyper Output from \code{learn_alignment_hyperparams()}.
#' @param ign_out Pre-computed output from \code{run_ignition_weekly()}.
#'   If NULL, must supply \code{params} to run M0 internally.
#' @param params M0 detection params. Used only if \code{ign_out} is NULL.
#' @param horizons Integer vector of forecast horizons (default \code{c(1L, 2L)}).
#' @param eval_weeks Optional integer vector of weekF values to evaluate at.
#'   If NULL, evaluates from ignition lock through end of season.
#' @param allow_scale Passed to \code{run_alignment_prospective()}.
#' @param use_ci Logical; peak CI control (default TRUE).
#' @param buffer_weeks Integer; peak buffer (default 0L).
#' @param min_obs Integer; minimum rows for alignment (default 4L).
#' @param curvature_ratio Numeric; delta curvature gate (default 1.0).
#'
#' @return A tibble with columns:
#' \describe{
#'   \item{season}{Season label}
#'   \item{eval_weekF}{The weekF at which M1 was run (data up to this week)}
#'   \item{target_weekF}{The weekF for which M1 predicts (eval_weekF + h)}
#'   \item{h}{Forecast horizon (1 or 2)}
#'   \item{m1_p_hat}{M1's predicted positivity at target week}
#'   \item{m1_p_lo}{M1's lower PI at target week}
#'   \item{m1_p_hi}{M1's upper PI at target week}
#'   \item{m1_tau}{M1's shift parameter at eval_weekF}
#'   \item{m1_delta}{M1's dilation parameter at eval_weekF}
#'   \item{m1_state}{M1 state: "aligning" or "post_peak"}
#' }
#'
#' @export
m1_walkforward_predictions <- function(seasonD,
                                       ref,
                                       hyper,
                                       ign_out            = NULL,
                                       params             = NULL,
                                       horizons           = c(1L, 2L),
                                       eval_weeks         = NULL,
                                       allow_scale        = NULL,
                                       use_ci             = TRUE,
                                       buffer_weeks       = 0L,
                                       min_obs            = 4L,
                                       curvature_ratio    = 1.0,
                                       temperature        = 0.25,
                                       rise_weight        = 1.0,
                                       trough_weight      = 0.1,
                                       peak_decay         = 0.3,
                                       slope_weight       = 0.5,
                                       slope_window       = 4L,
                                       dynamic_temp       = TRUE,
                                       dynamic_temp_pivot = 10L,
                                       top_k              = NULL,
                                       blend_alpha        = 1.0) {

  season_name <- unique(as.character(seasonD$season))[1]
  horizons    <- as.integer(horizons)
  max_weekF   <- max(seasonD$weekF, na.rm = TRUE)

  # --- M0: run ignition detection if not supplied ---
  if (is.null(ign_out)) {
    if (is.null(params))
      stop("Either 'ign_out' or 'params' must be provided.")
    ign_out <- run_ignition_weekly(
      currentSeason  = seasonD,
      ign_fit_or_gam = NULL,
      params         = params,
      start_week     = 1L
    )
  }

  # No ignition detected → empty result
  if (is.na(ign_out$ign_week_locked))
    return(.empty_m1_preds())

  # --- Resolve eval weeks ---
  if (is.null(eval_weeks)) {
    eval_weeks <- seq(as.integer(ign_out$ign_week_locked), max_weekF)
  }
  eval_weeks <- as.integer(eval_weeks)

  # --- Walk-forward over eval weeks ---
  results <- vector("list", length(eval_weeks))

  for (i in seq_along(eval_weeks)) {
    ew <- eval_weeks[i]
    season_to_ew <- dplyr::filter(seasonD, .data$weekF <= ew)

    ap <- tryCatch(
      run_alignment_prospective_multi(
        currentSeason      = season_to_ew,
        ref                = ref,
        hyper              = hyper,
        ign_out            = ign_out,
        use_ci             = use_ci,
        buffer_weeks       = buffer_weeks,
        allow_scale        = allow_scale,
        min_obs            = min_obs,
        curvature_ratio    = curvature_ratio,
        temperature        = temperature,
        rise_weight        = rise_weight,
        trough_weight      = trough_weight,
        peak_decay         = peak_decay,
        slope_weight       = slope_weight,
        slope_window       = slope_window,
        dynamic_temp       = dynamic_temp,
        dynamic_temp_pivot = dynamic_temp_pivot,
        top_k              = top_k,
        blend_alpha        = blend_alpha
      ),
      error = function(e) NULL
    )

    if (is.null(ap) || ap$state == "pre_ignition" || is.null(ap$forecast_df))
      next

    iWeek_hat  <- ap$iWeek_hat
    anchorWeek <- ref$anchorWeek
    fdf        <- ap$forecast_df

    # Extract predictions at each target week for each horizon
    rows <- vector("list", length(horizons))
    for (j in seq_along(horizons)) {
      h <- horizons[j]
      target_weekF   <- ew + h
      target_newWeek <- as.numeric(target_weekF - iWeek_hat + anchorWeek)

      # Interpolate M1's prediction and spread at target_newWeek.
      # logit_spread is the weighted SD of logit-scale template predictions —
      # high values indicate M1 ensemble disagreement (alignment uncertainty).
      p_hat  <- stats::approx(fdf$newWeek, fdf$p_hat, xout = target_newWeek,
                              rule = 2)$y
      p_lo   <- stats::approx(fdf$newWeek, fdf$p_lo,  xout = target_newWeek,
                              rule = 2)$y
      p_hi   <- stats::approx(fdf$newWeek, fdf$p_hi,  xout = target_newWeek,
                              rule = 2)$y
      spread <- if ("logit_spread" %in% names(fdf))
        stats::approx(fdf$newWeek, fdf$logit_spread, xout = target_newWeek, rule = 2)$y
      else NA_real_

      rows[[j]] <- tibble::tibble(
        season           = season_name,
        eval_weekF       = ew,
        target_weekF     = target_weekF,
        h                = h,
        m1_p_hat         = p_hat,
        m1_p_lo          = p_lo,
        m1_p_hi          = p_hi,
        m1_logit_spread  = spread,
        m1_tau           = ap$tau,
        m1_delta         = ap$delta,
        m1_state         = ap$state
      )
    }
    results[[i]] <- dplyr::bind_rows(rows)
  }

  out <- dplyr::bind_rows(results)
  if (nrow(out) == 0) return(.empty_m1_preds())
  out
}


#' Run M1 walk-forward for multiple seasons (parallelized)
#'
#' Calls \code{m1_walkforward_predictions()} for each season, optionally
#' in parallel via \code{furrr::future_map()}.
#'
#' @param allD Multi-season data frame.
#' @param ref Output from \code{estimateRef()}.
#' @param hyper Output from \code{learn_alignment_hyperparams()}.
#' @param params M0 detection params.
#' @param seasons Character vector of seasons to process.
#' @param horizons Forecast horizons (default \code{c(1L, 2L)}).
#' @param eval_weeks Optional; if NULL, determined per season from ignition.
#' @param allow_scale Passed through.
#' @param use_ci Passed through.
#' @param buffer_weeks Passed through.
#' @param min_obs Passed through.
#' @param curvature_ratio Passed through.
#' @param parallel Logical; use parallel via furrr (default TRUE).
#' @param verbose Logical; print progress (default TRUE).
#'
#' @return A tibble (stacked across seasons) with the same columns as
#'   \code{m1_walkforward_predictions()}.
#' @export
m1_walkforward_multi <- function(allD,
                                 ref,
                                 hyper,
                                 params,
                                 seasons            = NULL,
                                 horizons           = c(1L, 2L),
                                 eval_weeks         = NULL,
                                 allow_scale        = NULL,
                                 use_ci             = TRUE,
                                 buffer_weeks       = 0L,
                                 min_obs            = 4L,
                                 curvature_ratio    = 1.0,
                                 temperature        = 0.25,
                                 rise_weight        = 1.0,
                                 trough_weight      = 0.1,
                                 peak_decay         = 0.3,
                                 slope_weight       = 0.5,
                                 slope_window       = 4L,
                                 dynamic_temp       = TRUE,
                                 dynamic_temp_pivot = 10L,
                                 top_k              = NULL,
                                 blend_alpha        = 1.0,
                                 parallel           = TRUE,
                                 verbose            = TRUE) {

  if (is.null(seasons)) seasons <- sort(unique(as.character(allD$season)))

  map_fn <- if (isTRUE(parallel) && requireNamespace("furrr", quietly = TRUE)) {
    function(...) furrr::future_map(..., .options = furrr::furrr_options(seed = TRUE))
  } else {
    purrr::map
  }

  results <- map_fn(seasons, function(s) {
    if (isTRUE(verbose)) message("[m1_walkforward_multi] Processing season: ", s)
    seasonD <- dplyr::filter(allD, .data$season == s)

    m1_walkforward_predictions(
      seasonD            = seasonD,
      ref                = ref,
      hyper              = hyper,
      params             = params,
      horizons           = horizons,
      eval_weeks         = eval_weeks,
      allow_scale        = allow_scale,
      use_ci             = use_ci,
      buffer_weeks       = buffer_weeks,
      min_obs            = min_obs,
      curvature_ratio    = curvature_ratio,
      temperature        = temperature,
      rise_weight        = rise_weight,
      trough_weight      = trough_weight,
      peak_decay         = peak_decay,
      slope_weight       = slope_weight,
      slope_window       = slope_window,
      dynamic_temp       = dynamic_temp,
      dynamic_temp_pivot = dynamic_temp_pivot,
      top_k              = top_k,
      blend_alpha        = blend_alpha
    )
  })

  dplyr::bind_rows(results)
}


# internal: empty tibble with correct columns
.empty_m1_preds <- function() {
  tibble::tibble(
    season         = character(0),
    eval_weekF     = integer(0),
    target_weekF   = integer(0),
    h              = integer(0),
    m1_p_hat       = numeric(0),
    m1_p_lo        = numeric(0),
    m1_p_hi        = numeric(0),
    m1_tau         = numeric(0),
    m1_delta       = numeric(0),
    m1_state       = character(0)
  )
}


# ============================================================
# Runtime helper: Inject M1 prediction into M2 snapshot
# ============================================================

#' Replace logit_f_eff in M2 snapshots with M1's aligned prediction
#'
#' Takes the output of \code{build_stage2_pseudo_prospective_list()} and
#' replaces each snapshot's \code{logit_f_eff} with M1's prediction at
#' the corresponding target week.
#'
#' @param pp List with \code{meta} and \code{df} from
#'   \code{build_stage2_pseudo_prospective_list()}.
#' @param m1_result Output from \code{run_alignment_prospective()} for the
#'   current evaluation week.
#' @param ref Reference object (must have \code{anchorWeek}).
#' @param horizons Integer vector of forecast horizons (default \code{c(1L, 2L)}).
#' @param eps Clipping epsilon for logit (default 1e-6).
#'
#' @return Modified \code{pp} with \code{logit_f_eff} replaced by M1 predictions.
#' @export
inject_m1_into_snapshots <- function(pp,
                                     m1_result,
                                     ref,
                                     horizons = c(1L, 2L),
                                     eps      = 1e-6) {

  if (is.null(m1_result) || m1_result$state == "pre_ignition" ||
      is.null(m1_result$forecast_df))
    return(pp)

  fdf        <- m1_result$forecast_df
  iWeek_hat  <- m1_result$iWeek_hat
  anchorWeek <- ref$anchorWeek

  for (i in seq_along(pp$df)) {
    snap <- pp$df[[i]]
    if (!is.data.frame(snap) || nrow(snap) == 0) next

    # For each row, compute M1's prediction at the target week
    h_int <- as.integer(sub("^h", "", as.character(snap$lead)))
    target_weekF   <- as.integer(snap$weekF) + h_int
    target_newWeek <- as.numeric(target_weekF - iWeek_hat + anchorWeek)

    m1_p <- stats::approx(fdf$newWeek, fdf$p_hat, xout = target_newWeek,
                          rule = 2)$y

    has_m1 <- is.finite(m1_p) & !is.na(m1_p)
    m1_logit <- ifelse(has_m1, logit_stable(m1_p, eps = eps), snap$logit_f_eff)

    pp$df[[i]]$logit_f_eff <- m1_logit
  }

  pp
}

