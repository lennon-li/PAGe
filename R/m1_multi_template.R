#' Multi-template ensemble alignment and forecast
#'
#' Aligns observed data to each training season's curve (from \code{eta_mat}
#' returned by \code{estimateRef(method = "fs")}), then ensembles the forecasts
#' weighted by alignment NLL via softmax.
#'
#' @param currentD tibble/data.frame with \code{newWeek}, \code{y}, \code{neg}.
#' @param eta_mat Numeric matrix (\code{n_weeks} x \code{n_seasons}) of
#'   logit-scale per-season predictions from \code{estimateRef(method = "fs")}.
#' @param g_ref_fun Population reference curve function (logit scale). Used as
#'   the blending anchor when \code{blend_alpha < 1}.
#' @param g_ref_mu_se Population reference uncertainty function (fallback).
#' @param hyper List of alignment hyperparameters (TAU_BOUNDS, etc.).
#' @param allow_scale Logical or NULL. Passed through.
#' @param use_weights Logical; use \code{y + neg} as binomial weights.
#' @param level CI level (default 0.95).
#' @param future_weeks Numeric vector of future newWeek values.
#' @param include_observed Logical; include observed block in pred_df.
#' @param fallback_when_unstable Logical; refit with delta=0 if unstable.
#' @param curvature_ratio Numeric; delta gate coefficient.
#' @param temperature Numeric; softmax temperature for NLL weighting
#'   (default 1.0). Lower = more peaked (winner-take-all).
#' @param top_k Integer or NULL. If not NULL, pre-filter to top-K templates
#'   ranked by Spearman correlation with observed data.
#' @param blend_alpha Numeric 0--1. Blend each per-season template toward the
#'   population reference: \code{g_blend = (1-alpha)*g_ref + alpha*g_s}.
#'   Default 1.0 (pure per-season curve).
#' @param time_weights Numeric vector or NULL; pre-computed time weights.
#' @param trough_weight Numeric; alignment loss trough weight.
#' @param rise_weight Numeric; alignment loss rise weight.
#' @param peak_decay Numeric; exponential decay after peak.
#' @param slope_weight Numeric; strength of growth-rate-aware template weighting
#'   (default 0.5). Higher values make templates with similar recent slope to
#'   observed data receive more weight. Set to 0 to disable.
#' @param slope_window Integer; number of recent weeks to compute slope over
#'   (default 4).
#' @param dynamic_temp Logical; if TRUE (default), scale temperature up when
#'   few observations available (wider ensemble early, sharper late).
#' @param dynamic_temp_pivot Integer; observation count below which temperature
#'   is inflated (default 10). Temperature is scaled by
#'   \code{pivot / n_obs} when \code{n_obs < pivot}.
#'
#' @return List with the same structure as
#'   \code{align_forecast_pipeline_dilate()} output, plus:
#'   \describe{
#'     \item{per_template}{List of per-template alignment results.}
#'     \item{weights}{Named numeric vector of softmax ensemble weights.}
#'     \item{template_names}{Character vector of template season labels.}
#'   }
#' @export
align_multi_template <- function(currentD,
                                 eta_mat,
                                 g_ref_fun,
                                 g_ref_mu_se,
                                 hyper,
                                 allow_scale         = NULL,
                                 use_weights         = TRUE,
                                 level               = 0.95,
                                 future_weeks        = NULL,
                                 include_observed     = TRUE,
                                 fallback_when_unstable = TRUE,
                                 curvature_ratio     = 1.0,
                                 temperature         = 1.0,
                                 top_k               = NULL,
                                 blend_alpha         = 1.0,
                                 time_weights        = NULL,
                                 trough_weight       = 0.1,
                                 rise_weight         = 1.0,
                                 peak_decay          = 0.3,
                                 slope_weight        = 1.0,
                                 slope_window        = 6L,
                                 dynamic_temp        = TRUE,
                                 dynamic_temp_pivot  = 10L,
                                 gam_obj             = NULL) {

  stopifnot(is.matrix(eta_mat), ncol(eta_mat) >= 2)
  n_weeks       <- nrow(eta_mat)
  seas_names    <- colnames(eta_mat)
  if (is.null(seas_names)) seas_names <- paste0("S", seq_len(ncol(eta_mat)))
  all_seas_levs <- seas_names  # preserve full level set before top_k filtering

  # --- 1. Build per-season template functions ---
  template_funs <- lapply(seq_along(seas_names), function(s_idx) {
    s_name  <- seas_names[s_idx]
    g_s_raw <- stats::splinefun(seq_len(n_weeks), eta_mat[, s_idx], method = "natural")
    if (blend_alpha < 1) {
      # Blend toward population reference
      alpha <- blend_alpha
      g_s <- function(u) (1 - alpha) * g_ref_fun(u) + alpha * g_s_raw(u)
    } else {
      g_s <- g_s_raw
    }
    g_s_safe  <- function(u) g_s(pmin(pmax(u, 1), n_weeks))
    # SE: use GAM prediction uncertainty if gam_obj provided; else zero (no CI)
    if (!is.null(gam_obj)) {
      g_s_mu_se <- (function(gam, sn, levs, n_wk) {
        function(u) {
          u_cl <- pmin(pmax(round(u), 1L), n_wk)
          nd   <- data.frame(newWeek = u_cl,
                             season  = factor(sn, levels = levs))
          pr   <- tryCatch(
            stats::predict(gam, newdata = nd, type = "link", se.fit = TRUE),
            error = function(e) list(fit = g_s_safe(u), se.fit = rep(0, length(u)))
          )
          list(mu = g_s_safe(u), se = as.numeric(pr$se.fit))
        }
      })(gam_obj, s_name, all_seas_levs, n_weeks)
    } else {
      g_s_mu_se <- function(u) list(mu = g_s_safe(u), se = rep(0, length(u)))
    }
    list(g_ref_fun = g_s, g_ref_safe = g_s_safe, g_ref_mu_se = g_s_mu_se,
         season = s_name)
  })
  names(template_funs) <- seas_names

  # --- 2. Optional top-K pre-filtering by correlation ---
  if (!is.null(top_k) && top_k < length(template_funs)) {
    t_obs <- currentD$newWeek
    p_obs <- currentD$y / (currentD$y + currentD$neg)
    cors <- vapply(template_funs, function(tf) {
      p_ref <- stats::plogis(tf$g_ref_safe(t_obs))
      stats::cor(p_obs, p_ref, method = "spearman", use = "complete.obs")
    }, numeric(1))
    keep_idx <- order(cors, decreasing = TRUE)[seq_len(min(top_k, length(cors)))]
    template_funs <- template_funs[keep_idx]
    seas_names    <- seas_names[keep_idx]
  }

  # --- 3. Align to each template ---
  results <- lapply(template_funs, function(tf) {
    tryCatch(
      align_forecast_pipeline_dilate(
        currentD               = currentD,
        g_ref_fun              = tf$g_ref_fun,
        g_ref_mu_se            = tf$g_ref_mu_se,
        hyper                  = hyper,
        allow_scale            = allow_scale,
        use_weights            = use_weights,
        level                  = level,
        future_weeks           = future_weeks,
        include_observed       = include_observed,
        fallback_when_unstable = fallback_when_unstable,
        curvature_ratio        = curvature_ratio,
        time_weights           = time_weights,
        trough_weight          = trough_weight,
        rise_weight            = rise_weight,
        peak_decay             = peak_decay
      ),
      error = function(e) NULL
    )
  })

  # --- 4. Compute softmax weights from NLL + slope similarity ---
  valid   <- !vapply(results, is.null, logical(1))
  n_obs   <- nrow(currentD)
  nlls    <- vapply(results, function(r) {
    if (is.null(r) || is.null(r$nll) || !is.finite(r$nll)) Inf else r$nll / max(n_obs, 1)
  }, numeric(1))

  if (sum(valid & is.finite(nlls)) == 0) {
    # All templates failed — fall back to population reference
    return(align_forecast_pipeline_dilate(
      currentD = currentD, g_ref_fun = g_ref_fun, g_ref_mu_se = g_ref_mu_se,
      hyper = hyper, allow_scale = allow_scale, use_weights = use_weights,
      level = level, future_weeks = future_weeks,
      include_observed = include_observed,
      fallback_when_unstable = fallback_when_unstable,
      curvature_ratio = curvature_ratio,
      time_weights = time_weights, trough_weight = trough_weight,
      rise_weight = rise_weight, peak_decay = peak_decay
    ))
  }

  # Dynamic temperature: widen ensemble early (few obs), sharpen late
  temp_eff <- if (dynamic_temp && n_obs < dynamic_temp_pivot) {
    temperature * (dynamic_temp_pivot / max(n_obs, 1L))
  } else {
    temperature
  }

  # Growth-rate-aware weighting: compare observed slope to each template's slope
  slope_factor <- rep(1, length(results))
  if (slope_weight > 0 && n_obs >= slope_window) {
    # Observed slope: logit-scale derivative over recent window
    obs_tail <- utils::tail(currentD[order(currentD$newWeek), ], slope_window)
    p_obs    <- obs_tail$y / (obs_tail$y + obs_tail$neg)
    p_obs    <- pmin(pmax(p_obs, 0.001), 0.999)
    logit_obs <- log(p_obs / (1 - p_obs))
    t_obs     <- obs_tail$newWeek
    # Simple linear slope
    obs_slope <- if (length(unique(t_obs)) >= 2) {
      stats::coef(stats::lm.fit(cbind(1, t_obs), logit_obs))[2]
    } else 0

    for (i in seq_along(results)) {
      if (!valid[i] || !is.finite(nlls[i])) next
      # Template slope evaluated at the same raw positions as the observation.
      # Using aligned positions (u_hat) was tried but hurt MAE by ~17% due to
      # unit inconsistency across templates with different tau/delta — reverted.
      tf <- template_funs[[i]]
      logit_template <- tf$g_ref_safe(t_obs)
      tmpl_slope <- if (length(unique(t_obs)) >= 2) {
        stats::coef(stats::lm.fit(cbind(1, t_obs), logit_template))[2]
      } else 0
      # Similarity: exp(-slope_weight * |obs_slope - tmpl_slope|)
      slope_factor[i] <- exp(-slope_weight * abs(obs_slope - tmpl_slope))
    }
  }

  # Softmax: shift for numerical stability
  nlls_valid   <- nlls[valid & is.finite(nlls)]
  min_nll      <- min(nlls_valid)
  w_raw        <- exp(-(nlls - min_nll) / temp_eff) * slope_factor
  w_raw[!valid | !is.finite(nlls)] <- 0
  w_s          <- w_raw / sum(w_raw)
  names(w_s)   <- names(results)

  # --- 5. Ensemble forecasts (logit scale) ---
  # Collect forecast-only rows from each valid result
  valid_idx <- which(valid & w_s > 0)
  ref_pred  <- results[[valid_idx[1]]]$pred_df

  future_rows <- ref_pred$kind == "forecast"
  obs_rows    <- ref_pred$kind == "observed"

  # Stack forecast p_hat from each template; work on logit scale throughout
  fw_weeks <- ref_pred$newWeek[future_rows]
  n_fw     <- length(fw_weeks)

  if (n_fw > 0) {
    p_mat <- matrix(NA_real_, nrow = n_fw, ncol = length(valid_idx))
    for (j in seq_along(valid_idx)) {
      vi <- valid_idx[j]
      pred_j <- results[[vi]]$pred_df
      fj <- pred_j$kind == "forecast"
      if (sum(fj) == n_fw) {
        p_mat[, j] <- pred_j$p_hat[fj]
      }
    }

    wts <- w_s[valid_idx]
    wts <- wts / sum(wts)

    # Logit-scale ensemble: average and quantiles on log-odds, then back-transform.
    # This respects the binomial model geometry (log-odds is the linear predictor)
    # and avoids probability-scale distortion near 0/1.
    eps       <- 1e-9
    logit_mat <- log(pmax(p_mat, eps) / pmax(1 - p_mat, eps))

    # Weighted mean on logit scale
    logit_mean_ens <- drop(logit_mat %*% wts)
    p_hat_ens      <- stats::plogis(logit_mean_ens)

    # Weighted median on logit scale
    logit_med_ens <- vapply(seq_len(n_fw), function(i) {
      .weighted_quantile(logit_mat[i, ], wts, 0.5)
    }, numeric(1))
    p_hat_median_ens <- stats::plogis(logit_med_ens)

    # Template spread: weighted SD on logit scale (alignment uncertainty signal)
    logit_spread_ens <- vapply(seq_len(n_fw), function(i) {
      lv <- logit_mat[i, ]
      mu <- sum(wts * lv)
      sqrt(sum(wts * (lv - mu)^2))
    }, numeric(1))

    # CIs: weighted quantiles on logit scale, back-transformed
    alpha_lo <- (1 - level) / 2
    alpha_hi <- 1 - alpha_lo
    p_lo_ens <- stats::plogis(vapply(seq_len(n_fw), function(i) {
      .weighted_quantile(logit_mat[i, ], wts, alpha_lo)
    }, numeric(1)))
    p_hi_ens <- stats::plogis(vapply(seq_len(n_fw), function(i) {
      .weighted_quantile(logit_mat[i, ], wts, alpha_hi)
    }, numeric(1)))

    forecast_block <- tibble::tibble(
      newWeek          = fw_weeks,
      p_hat            = p_hat_ens,
      p_hat_median     = p_hat_median_ens,
      logit_spread     = logit_spread_ens,
      p_lo             = p_lo_ens,
      p_hi             = p_hi_ens,
      kind             = "forecast"
    )
  } else {
    forecast_block <- tibble::tibble()
  }

  # Observed block from first valid result (same across templates)
  obs_block <- if (include_observed && any(obs_rows)) {
    ref_pred[obs_rows, ]
  } else {
    tibble::tibble()
  }

  pred_df <- dplyr::bind_rows(obs_block, forecast_block) %>%
    dplyr::arrange(newWeek)

  # --- 6. Ensemble peak estimate ---
  t_peaks <- vapply(results[valid_idx], function(r) {
    if (!is.null(r$peak$t_peak) && is.finite(r$peak$t_peak)) r$peak$t_peak else NA_real_
  }, numeric(1))
  pk_valid <- is.finite(t_peaks)

  if (any(pk_valid)) {
    pk_wts       <- wts[pk_valid] / sum(wts[pk_valid])
    t_peak       <- sum(t_peaks[pk_valid] * pk_wts)
    t_peak_med   <- .weighted_quantile(t_peaks[pk_valid], pk_wts, 0.5)

    # CI from weighted distribution of peaks
    t_peak_lo <- .weighted_quantile(t_peaks[pk_valid], pk_wts, (1 - level) / 2)
    t_peak_hi <- .weighted_quantile(t_peaks[pk_valid], pk_wts, 1 - (1 - level) / 2)
  } else {
    t_peak     <- NA_real_
    t_peak_med <- NA_real_
    t_peak_lo  <- NA_real_
    t_peak_hi  <- NA_real_
  }

  # Weighted average alignment parameters
  tau_ens   <- sum(vapply(results[valid_idx], `[[`, numeric(1), "tau") * wts)
  delta_ens <- sum(vapply(results[valid_idx], `[[`, numeric(1), "delta") * wts)
  a_ens     <- sum(vapply(results[valid_idx], `[[`, numeric(1), "a") * wts)
  b_ens     <- sum(vapply(results[valid_idx], `[[`, numeric(1), "b") * wts)

  # Best template info
  best_idx <- valid_idx[which.max(w_s[valid_idx])]
  best_res <- results[[best_idx]]

  peak_out <- list(
    t_peak        = t_peak,
    t_peak_median = t_peak_med,
    t_peak_ci     = c(t_peak_lo, t_peak_hi),
    u_star    = if (!is.null(best_res$peak)) best_res$peak$u_star else NA_real_,
    p_peak    = if (is.finite(t_peak) && n_fw > 0) {
      # Interpolate ensemble p_hat at t_peak
      approx_p <- stats::approx(fw_weeks, p_hat_ens, xout = t_peak)$y
      if (!is.null(approx_p) && is.finite(approx_p)) approx_p else NA_real_
    } else NA_real_
  )

  list(
    tau             = tau_ens,
    delta           = delta_ens,
    a               = a_ens,
    b               = b_ens,
    allow_scale     = best_res$allow_scale,
    delta_on        = best_res$delta_on,
    nll             = sum(nlls[valid_idx] * wts),
    pred_df         = pred_df,
    last_obs        = max(currentD$newWeek),
    V_ab            = best_res$V_ab,
    V_td            = best_res$V_td,
    peak            = peak_out,
    fallback_reason = best_res$fallback_reason,
    per_template    = results,
    weights         = w_s,
    template_names  = names(results)
  )
}


#' Prospective multi-template alignment wrapper
#'
#' Drop-in replacement for \code{run_alignment_prospective()} that uses
#' \code{align_multi_template()} internally. Returns the same output structure.
#'
#' @param currentSeason Data frame for one season up to current eval_week.
#' @param ref Reference object from \code{estimateRef(method = "fs")}, must
#'   contain \code{eta_mat}.
#' @param hyper Alignment hyperparameters.
#' @param ign_out Ignition detection output.
#' @param use_ci Logical; use CI for peak passage detection.
#' @param buffer_weeks Integer; weeks past peak threshold.
#' @param allow_scale Logical or NULL.
#' @param level CI level.
#' @param min_obs Integer; minimum observations required.
#' @param curvature_ratio Numeric; delta gate coefficient.
#' @param trough_weight Numeric; alignment loss trough weight.
#' @param rise_weight Numeric; alignment loss rise weight.
#' @param peak_decay Numeric; exponential decay after peak.
#' @param temperature Numeric; softmax temperature.
#' @param top_k Integer or NULL; pre-filter templates.
#' @param blend_alpha Numeric 0--1; template blending.
#'
#' @return List with same structure as \code{run_alignment_prospective()} output.
#' @export
run_alignment_prospective_multi <- function(
  currentSeason,
  ref,
  hyper,
  ign_out,
  use_ci              = TRUE,
  buffer_weeks        = 0L,
  allow_scale         = NULL,
  level               = 0.95,
  min_obs             = 4L,
  curvature_ratio     = 1.0,
  trough_weight       = 0.1,
  rise_weight         = 1.0,
  peak_decay          = 0.3,
  temperature         = 1.0,
  top_k               = NULL,
  blend_alpha         = 1.0,
  slope_weight        = 1.0,
  slope_window        = 6L,
  dynamic_temp        = TRUE,
  dynamic_temp_pivot  = 10L
) {

  # Helper: early return in pre-ignition state
  pre_ign <- function() {
    list(
      state           = "pre_ignition",
      iWeek_hat       = NA_integer_,
      ign_week_locked = NA_integer_,
      tau             = NA_real_,
      delta           = NA_real_,
      a               = NA_real_,
      b               = NA_real_,
      allow_scale     = NA,
      delta_on        = NA,
      t_peak          = NA_real_,
      t_peak_median   = NA_real_,
      t_peak_ci       = c(NA_real_, NA_real_),
      peak_weekF      = NA_integer_,
      peak_weekF_lo   = NA_integer_,
      peak_weekF_hi   = NA_integer_,
      peak_passed     = FALSE,
      fallback_reason = NA_character_,
      forecast_df     = NULL,
      ign_out         = ign_out
    )
  }

  # Check ignition locked
  max_weekF <- max(currentSeason$weekF, na.rm = TRUE)
  if (is.na(ign_out$ign_week_locked) || ign_out$ign_week_locked > max_weekF)
    return(pre_ign())

  iWeek_hat       <- as.integer(ign_out$iWeek_hat_locked)
  ign_week_locked <- as.integer(ign_out$ign_week_locked)

  # Re-anchor to alignment space

  currentD <- currentSeason %>%
    dplyr::mutate(newWeek = as.integer(.data$weekF) - iWeek_hat + ref$anchorWeek)

  if (nrow(currentD) < as.integer(min_obs))
    return(pre_ign())

  # Scale identifiability check
  scale_rec <- if (!is.null(allow_scale)) {
    allow_scale
  } else {
    check_scale_identifiability(
      currentD  = currentD,
      g_ref_fun = ref$g_ref_fun,
      hyper     = hyper
    )$allow_scale_rec
  }

  # Multi-template alignment + forecast
  res <- tryCatch(
    align_multi_template(
      currentD               = currentD,
      eta_mat                = ref$eta_mat,
      g_ref_fun              = ref$g_ref_fun,
      g_ref_mu_se            = ref$g_ref_mu_se,
      hyper                  = hyper,
      allow_scale            = scale_rec,
      level                  = level,
      future_weeks           = seq(1, 52, by = 0.5),
      include_observed       = TRUE,
      curvature_ratio        = curvature_ratio,
      temperature            = temperature,
      top_k                  = top_k,
      blend_alpha            = blend_alpha,
      trough_weight          = trough_weight,
      rise_weight            = rise_weight,
      peak_decay             = peak_decay,
      slope_weight           = slope_weight,
      slope_window           = slope_window,
      dynamic_temp           = dynamic_temp,
      dynamic_temp_pivot     = dynamic_temp_pivot,
      gam_obj                = if (!is.null(ref$mod2$gam)) ref$mod2$gam else NULL
    ),
    error = function(e) NULL
  )

  if (is.null(res))
    return(pre_ign())

  # Peak passage detection
  pk <- peak_status_from_align(
    res          = res,
    currentD     = currentD,
    use_ci       = use_ci,
    buffer_weeks = buffer_weeks
  )

  # Convert peak to weekF space
  t_peak_use    <- res$peak$t_peak
  t_peak_ci_use <- res$peak$t_peak_ci

  peak_weekF    <- round(t_peak_use       - ref$anchorWeek + iWeek_hat)
  peak_weekF_lo <- round(t_peak_ci_use[1] - ref$anchorWeek + iWeek_hat)
  peak_weekF_hi <- round(t_peak_ci_use[2] - ref$anchorWeek + iWeek_hat)

  state <- if (pk$peak_passed) "post_peak" else "aligning"

  list(
    state           = state,
    iWeek_hat       = iWeek_hat,
    ign_week_locked = ign_week_locked,
    tau             = res$tau,
    delta           = res$delta,
    a               = res$a,
    b               = res$b,
    allow_scale     = res$allow_scale,
    delta_on        = res$delta_on,
    t_peak          = t_peak_use,
    t_peak_median   = res$peak$t_peak_median,
    t_peak_ci       = t_peak_ci_use,
    t_peak_raw      = res$peak$t_peak,
    t_peak_ci_raw   = res$peak$t_peak_ci,
    peak_weekF      = as.integer(peak_weekF),
    peak_weekF_lo   = as.integer(peak_weekF_lo),
    peak_weekF_hi   = as.integer(peak_weekF_hi),
    peak_passed     = pk$peak_passed,
    fallback_reason = res$fallback_reason,
    forecast_df     = res$pred_df,
    ign_out         = ign_out,
    weights         = res$weights,
    template_names  = res$template_names
  )
}


#' Weighted quantile (internal helper)
#' @keywords internal
.weighted_quantile <- function(x, w, prob) {
  if (length(x) == 0 || all(is.na(x))) return(NA_real_)
  ok <- !is.na(x)
  x <- x[ok]; w <- w[ok]
  if (length(x) == 0) return(NA_real_)
  if (length(x) == 1) return(x)
  ord <- order(x)
  x <- x[ord]; w <- w[ord]
  w <- w / sum(w)
  cum_w <- cumsum(w)
  # Linear interpolation
  idx <- which(cum_w >= prob)[1]
  if (idx == 1) return(x[1])
  # Interpolate between idx-1 and idx
  w_below <- cum_w[idx - 1]
  w_at    <- cum_w[idx]
  frac    <- (prob - w_below) / (w_at - w_below)
  x[idx - 1] + frac * (x[idx] - x[idx - 1])
}
