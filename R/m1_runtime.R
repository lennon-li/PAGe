#' Prospective alignment and peak detection for one season
#'
#' Production-ready function called once per week with updated season data.
#' Performs real-time ignition detection, alignment, forecast, and peak passage
#' detection, returning the current state of the season.
#'
#' @param currentSeason Data frame for the ongoing season up to the current
#'   \code{weekF}. Must have columns \code{weekF}, \code{y}, and either
#'   \code{N} or \code{neg}.
#' @param ref Output from \code{estimateRef()} (pre-computed from training
#'   data).
#' @param hyper Output from \code{learn_alignment_hyperparams()} (pre-computed
#'   from training data).
#' @param params Named list of Stage-1 detector threshold parameters. Only
#'   used if \code{ign_out} is \code{NULL}. One of \code{params} or
#'   \code{ign_out} must be supplied.
#' @param ign_out Pre-computed output from \code{run_ignition_weekly()}. If
#'   \code{NULL} (default), runs ignition detection internally using
#'   \code{params}.
#' @param use_ci Logical; if \code{TRUE} (default), the peak is declared
#'   passed once the last observed \code{newWeek} exceeds the upper CI bound
#'   for the peak. If \code{FALSE}, uses the point estimate only.
#' @param buffer_weeks Integer. Additional weeks beyond the peak threshold
#'   required before declaring the peak passed (default \code{0L}).
#' @param allow_scale Logical or \code{NULL}. If \code{NULL} (default), scale
#'   identifiability is determined automatically via
#'   \code{check_scale_identifiability()}.
#' @param level Numeric. Confidence level for prediction intervals
#'   (default \code{0.95}).
#' @param min_obs Integer. Minimum number of rows in \code{currentSeason}
#'   required before attempting alignment (default \code{4L}).
#' @param cal Optional peak-calibration object.
#' @param curvature_ratio Numeric coefficient for activating dilation.
#' @param time_weights Optional observation weights.
#' @param trough_weight,rise_weight,peak_decay Alignment-loss controls.
#'
#' @return A named list with components:
#' \describe{
#'   \item{state}{Character: \code{"pre_ignition"} (ignition not yet locked),
#'     \code{"aligning"} (ignition locked, actively forecasting), or
#'     \code{"post_peak"} (peak detected, alignment can stop).}
#'   \item{iWeek_hat}{Integer. Estimated ignition week in original \code{weekF}
#'     space (\code{NA} if pre-ignition).}
#'   \item{ign_week_locked}{Integer. First \code{weekF} where ignition was
#'     confirmed (\code{NA} if pre-ignition).}
#'   \item{tau}{Numeric. Time-shift alignment parameter.}
#'   \item{delta}{Numeric. Scale (dilation) alignment parameter.}
#'   \item{a}{Numeric. Lower asymptote.}
#'   \item{b}{Numeric. Upper asymptote.}
#'   \item{allow_scale}{Logical. Whether scale fitting was enabled.}
#'   \item{delta_on}{Logical. Whether dilation was active.}
#'   \item{t_peak}{Numeric. Estimated peak in \code{newWeek} space.}
#'   \item{t_peak_ci}{Numeric length-2. 95\% CI for the peak in \code{newWeek}
#'     space.}
#'   \item{peak_weekF}{Integer. Estimated peak in original \code{weekF} space.}
#'   \item{peak_weekF_lo}{Integer. Lower CI bound of peak in \code{weekF}
#'     space.}
#'   \item{peak_weekF_hi}{Integer. Upper CI bound of peak in \code{weekF}
#'     space.}
#'   \item{peak_passed}{Logical. \code{TRUE} if the peak is considered to have
#'     passed.}
#'   \item{fallback_reason}{Character or \code{NA}. Reason for a partial
#'     fallback in the alignment, if any.}
#'   \item{forecast_df}{Tibble. Prediction data frame from
#'     \code{align_forecast_pipeline_dilate()} (\code{NULL} if pre-ignition).}
#'   \item{ign_out}{List. Full output from \code{run_ignition_weekly()}.}
#' }
#'
#' @examples
#' \dontrun{
#' ref    <- readRDS("data/ref.rds")
#' hyper  <- readRDS("data/hyper.rds")
#' params <- readRDS("data/stage1_tuning.rds")$best_params
#'
#' # Called once per week as new data arrives
#' ap <- run_alignment_prospective(
#'   currentSeason = current_data,
#'   ref           = ref,
#'   hyper         = hyper,
#'   params        = params
#' )
#' ap$state       # "pre_ignition", "aligning", or "post_peak"
#' ap$peak_weekF  # estimated peak in original week space
#'
#' # Pass previous ign_out to avoid re-running ignition each week
#' ap2 <- run_alignment_prospective(
#'   currentSeason = current_data_next_week,
#'   ref           = ref,
#'   hyper         = hyper,
#'   params        = NULL,
#'   ign_out       = ap$ign_out
#' )
#' }
run_alignment_prospective <- function(
  currentSeason,
  ref,
  hyper,
  params          = NULL,
  ign_out         = NULL,
  use_ci          = TRUE,
  buffer_weeks    = 0L,
  allow_scale     = NULL,
  level           = 0.95,
  min_obs         = 4L,
  cal             = NULL,   # output of fit_peak_calibration(); NULL = no calibration
  curvature_ratio = 1.0,    # passed to fit_tau_delta() delta curvature gate
  time_weights    = NULL,
  trough_weight   = 0.1,
  rise_weight     = 1.0,
  peak_decay      = 0.3
) {

  # Helper: early return in pre-ignition state
  pre_ign <- function(ign_out_val = ign_out) {
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
      t_peak_ci       = c(NA_real_, NA_real_),
      peak_weekF      = NA_integer_,
      peak_weekF_lo   = NA_integer_,
      peak_weekF_hi   = NA_integer_,
      peak_passed     = FALSE,
      fallback_reason = NA_character_,
      forecast_df     = NULL,
      ign_out         = ign_out_val
    )
  }

  # --- Step 1: Run or accept ignition detection ---
  if (is.null(ign_out)) {
    if (is.null(params))
      stop("Either 'ign_out' or 'params' must be provided.")
    ign_out <- run_ignition_weekly(
      currentSeason  = currentSeason,
      ign_fit_or_gam = NULL,
      params         = params,
      start_week     = 1L
    )
  }

  # --- Step 2: Check if ignition has locked within the available data ---
  # max weekF in currentSeason defines the evaluation horizon
  max_weekF_available <- max(currentSeason$weekF, na.rm = TRUE)
  if (is.na(ign_out$ign_week_locked) || ign_out$ign_week_locked > max_weekF_available)
    return(pre_ign(ign_out))

  iWeek_hat       <- as.integer(ign_out$iWeek_hat_locked)
  ign_week_locked <- as.integer(ign_out$ign_week_locked)

  # --- Step 3: Re-anchor data to alignment (newWeek) space ---
  currentD <- currentSeason |>
    dplyr::mutate(newWeek = as.integer(.data$weekF) - iWeek_hat + ref$anchorWeek)

  # --- Step 4: Guard minimum observations ---
  if (nrow(currentD) < as.integer(min_obs))
    return(pre_ign(ign_out))

  # --- Step 5: Scale identifiability check ---
  scale_rec <- if (!is.null(allow_scale)) {
    allow_scale
  } else {
    check_scale_identifiability(
      currentD  = currentD,
      g_ref_fun = ref$g_ref_fun,
      hyper     = hyper
    )$allow_scale_rec
  }

  # --- Step 6: Alignment + forecast ---
  res <- tryCatch(
    align_forecast_pipeline_dilate(
      currentD         = currentD,
      g_ref_fun        = ref$g_ref_fun,
      g_ref_mu_se      = ref$g_ref_mu_se,
      hyper            = hyper,
      allow_scale      = scale_rec,
      level            = level,
      future_weeks     = seq(1, 52, by = 0.5),
      include_observed = TRUE,
      curvature_ratio  = curvature_ratio,
      time_weights     = time_weights,
      trough_weight    = trough_weight,
      rise_weight      = rise_weight,
      peak_decay       = peak_decay
    ),
    error = function(e) NULL
  )

  if (is.null(res))
    return(pre_ign(ign_out))

  # --- Step 7: Peak passage detection ---
  pk <- peak_status_from_align(
    res          = res,
    currentD     = currentD,
    use_ci       = use_ci,
    buffer_weeks = buffer_weeks
  )

  # --- Step 8: Optionally calibrate peak estimate, then convert to weekF ---
  t_since_ign <- max(currentSeason$weekF, na.rm = TRUE) - iWeek_hat

  if (!is.null(cal)) {
    cal_res <- .apply_peak_calibration(
      t_peak      = res$peak$t_peak,
      t_peak_lo   = res$peak$t_peak_ci[1],
      t_peak_hi   = res$peak$t_peak_ci[2],
      t_since_ign = t_since_ign,
      cal         = cal,
      level       = level
    )
    t_peak_use <- cal_res$t_peak
    t_peak_ci_use <- c(cal_res$t_peak_lo, cal_res$t_peak_hi)
  } else {
    t_peak_use    <- res$peak$t_peak
    t_peak_ci_use <- res$peak$t_peak_ci
  }

  peak_weekF    <- round(t_peak_use       - ref$anchorWeek + iWeek_hat)
  peak_weekF_lo <- round(t_peak_ci_use[1] - ref$anchorWeek + iWeek_hat)
  peak_weekF_hi <- round(t_peak_ci_use[2] - ref$anchorWeek + iWeek_hat)

  # --- Step 9: State ---
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
    t_peak_ci       = t_peak_ci_use,
    t_peak_raw      = res$peak$t_peak,
    t_peak_ci_raw   = res$peak$t_peak_ci,
    peak_weekF      = as.integer(peak_weekF),
    peak_weekF_lo   = as.integer(peak_weekF_lo),
    peak_weekF_hi   = as.integer(peak_weekF_hi),
    peak_passed     = pk$peak_passed,
    fallback_reason = res$fallback_reason,
    forecast_df     = res$pred_df,
    ign_out         = ign_out
  )
}


#' Tune peak detection parameters using pre-computed walk-forward results
#'
#' Evaluates combinations of \code{use_ci} and \code{buffer_weeks} for peak
#' passage detection, using the \code{params_df} from \code{loso_walkforward()}.
#' No LOSO rerun is required -- tuning runs in seconds.
#'
#' For each grid point \code{(use_ci, buffer_weeks)}, the function simulates
#' detection at every \code{(season, eval_week)} row in \code{params_df}:
#' the peak is declared passed once the last observed \code{newWeek} meets
#' \code{threshold = t_peak_hi + buffer_weeks} (if \code{use_ci = TRUE}) or
#' \code{t_peak + buffer_weeks}. The first \code{eval_week} per season where
#' detection fires defines \code{detection_weekF}. Delay is computed as
#' \code{detection_weekF - true_peak_weekF} (positive = after peak, negative =
#' false positive).
#'
#' @param params_df Tibble from \code{loso_walkforward()$params_df}. Must have
#'   columns \code{season}, \code{eval_week}, \code{iWeek_hat}, \code{t_peak},
#'   \code{t_peak_hi}, \code{anchorWeek}.
#' @param allD Raw data frame (one row per season-week) used to look up the
#'   true peak \code{weekF} per season. Must have columns \code{season},
#'   \code{weekF}, \code{p}, \code{N}.
#' @param use_ci_grid Logical vector of \code{use_ci} values to evaluate
#'   (default \code{c(TRUE, FALSE)}).
#' @param buffer_weeks_grid Integer vector of \code{buffer_weeks} values to
#'   evaluate (default \code{-2:3}).
#'
#' @return A tibble with one row per \code{(use_ci, buffer_weeks)} combination
#'   and columns:
#' \describe{
#'   \item{use_ci}{Logical. Whether upper CI was used for the threshold.}
#'   \item{buffer_weeks}{Integer. Buffer added beyond the threshold.}
#'   \item{fp_rate}{Numeric. Fraction of seasons with a false-positive
#'     detection (declared before true peak).}
#'   \item{mean_delay}{Numeric. Mean detection delay (weeks after true peak)
#'     among seasons with no false positive.}
#'   \item{median_delay}{Numeric. Median detection delay.}
#'   \item{max_delay}{Numeric. Maximum detection delay.}
#'   \item{n_seasons}{Integer. Total seasons evaluated.}
#' }
#'
#' @examples
#' \dontrun{
#' wf     <- readRDS("data/loso_wf_cache.rds")
#' allD   <- read.csv("data/flu_testing_data.csv") |>
#'   mutate(p = y / N, N = as.integer(N))
#' tuning <- tune_peak_detection(wf$params_df, allD)
#' # Pick smallest buffer_weeks with fp_rate == 0
#' tuning |> filter(fp_rate == 0) |> arrange(mean_delay)
#' }
tune_peak_detection <- function(
  params_df,
  allD,
  use_ci_grid       = c(TRUE, FALSE),
  buffer_weeks_grid = -2:3
) {

  # --- True peak weekF per season from observed data ---
  true_peaks <- allD |>
    dplyr::filter(!is.na(.data$p), is.finite(.data$p), .data$N > 0) |>
    dplyr::group_by(.data$season) |>
    dplyr::slice_max(.data$p, n = 1L, with_ties = FALSE) |>
    dplyr::ungroup() |>
    dplyr::select(season, true_peak_weekF = "weekF")

  # Restrict to rows where alignment succeeded (t_peak and iWeek_hat available)
  pdf <- dplyr::filter(params_df, !is.na(.data$t_peak), !is.na(.data$iWeek_hat))
  all_test_seasons <- unique(pdf$season)

  # Build evaluation grid
  grid <- expand.grid(
    use_ci       = use_ci_grid,
    buffer_weeks = as.integer(buffer_weeks_grid),
    stringsAsFactors = FALSE
  )

  purrr::map_dfr(seq_len(nrow(grid)), function(i) {

    uc <- grid$use_ci[i]
    bw <- as.integer(grid$buffer_weeks[i])

    # Compute last observed newWeek and detection threshold per row
    det <- pdf |>
      dplyr::mutate(
        last_obs_newW = as.numeric(.data$eval_week) - as.numeric(.data$iWeek_hat) +
                        as.numeric(.data$anchorWeek),
        thresh   = if (uc) .data$t_peak_hi + bw else .data$t_peak + bw,
        detected = .data$last_obs_newW >= .data$thresh
      )

    # First eval_week per season where detection fires
    first_det <- det |>
      dplyr::filter(.data$detected) |>
      dplyr::group_by(.data$season) |>
      dplyr::slice_min(.data$eval_week, n = 1L, with_ties = FALSE) |>
      dplyr::ungroup() |>
      dplyr::select(season, detection_weekF = "eval_week")

    # Compute delay vs true peak for all test seasons
    eval_df <- tibble::tibble(season = all_test_seasons) |>
      dplyr::left_join(true_peaks, by = "season") |>
      dplyr::left_join(first_det,  by = "season") |>
      dplyr::filter(!is.na(.data$true_peak_weekF)) |>
      dplyr::mutate(
        delay     = .data$detection_weekF - .data$true_peak_weekF,
        fp        = !is.na(.data$delay) & .data$delay < 0L,
        no_detect = is.na(.data$detection_weekF)
      )

    n_seasons <- nrow(eval_df)

    # Metrics computed only among seasons with no false positive and a detection
    clean <- dplyr::filter(eval_df, !.data$fp, !.data$no_detect)

    tibble::tibble(
      use_ci       = uc,
      buffer_weeks = bw,
      fp_rate      = if (n_seasons > 0L) mean(eval_df$fp, na.rm = TRUE) else NA_real_,
      mean_delay   = if (nrow(clean) > 0L) mean(clean$delay,            na.rm = TRUE) else NA_real_,
      median_delay = if (nrow(clean) > 0L) stats::median(clean$delay,   na.rm = TRUE) else NA_real_,
      max_delay    = if (nrow(clean) > 0L) max(clean$delay,             na.rm = TRUE) else NA_real_,
      n_seasons    = n_seasons
    )
  })
}


# -- Internal helper ----------------------------------------------------------

#' Apply Bayesian shrinkage + bias correction to a peak estimate
#'
#' Internal helper used by \code{run_alignment_prospective()} when
#' \code{cal} is provided. Applies two corrections sequentially:
#' \enumerate{
#'   \item \strong{Shrinkage (C):} pulls \code{t_peak} toward the historical
#'     prior mean, weighted by the ratio of prior variance to data variance
#'     (CI width). Early-season wide CIs -> heavy shrinkage.
#'   \item \strong{Bias correction (A):} subtracts the residual bias predicted
#'     by a GAM fitted on LOSO errors as a function of \code{t_since_ign}.
#' }
#' Returns calibrated \code{t_peak} and updated CI bounds (posterior variance).
#'
#' @param t_peak Numeric. Raw peak estimate in \code{newWeek} space.
#' @param t_peak_lo Numeric. Lower CI bound in \code{newWeek} space.
#' @param t_peak_hi Numeric. Upper CI bound in \code{newWeek} space.
#' @param t_since_ign Numeric. Weeks since true ignition (\code{eval_week - iWeek_hat}).
#' @param cal List. Output of \code{fit_peak_calibration()}.
#' @param level Numeric. CI level (default \code{0.95}).
#' @return Named list with \code{t_peak}, \code{t_peak_lo}, \code{t_peak_hi}.
#' @keywords internal
.apply_peak_calibration <- function(t_peak, t_peak_lo, t_peak_hi,
                                    t_since_ign, cal, level = 0.95) {
  z       <- stats::qnorm((1 + level) / 2)
  se_hat  <- max((t_peak_hi - t_peak_lo) / (2 * z), 0.1)

  # (C) Bayesian shrinkage toward historical prior
  prec_data  <- 1 / se_hat^2
  prec_prior <- 1 / cal$sigma_prior^2
  prec_total <- prec_data + prec_prior
  t_peak_post <- (t_peak * prec_data + cal$mu_prior * prec_prior) / prec_total
  var_post    <- 1 / prec_total

  # (A) Residual bias correction (GAM trained on LOSO residuals)
  bias_pred  <- as.numeric(stats::predict(
    cal$bias_gam, newdata = data.frame(t_since_ign = t_since_ign)
  ))
  t_peak_cal <- t_peak_post - bias_pred

  list(
    t_peak    = t_peak_cal,
    t_peak_lo = t_peak_cal - z * sqrt(var_post),
    t_peak_hi = t_peak_cal + z * sqrt(var_post)
  )
}


#' Fit peak calibration model from LOSO walk-forward results
#'
#' Trains a two-stage calibration on the \code{params_df} produced by
#' \code{loso_walkforward()}:
#' \enumerate{
#'   \item \strong{Prior (for shrinkage):} learns the historical distribution
#'     of true peak timing in aligned \code{newWeek} space (\eqn{\mu}, \eqn{\sigma}).
#'   \item \strong{Residual bias GAM:} after applying shrinkage, fits a smooth
#'     of the remaining prediction error as a function of weeks since ignition.
#' }
#'
#' The returned object is passed to \code{run_alignment_prospective(cal = ...)}
#' to calibrate real-time peak estimates.
#'
#' @param params_df Tibble from \code{loso_walkforward()$params_df}.
#' @param allD Raw data frame with columns \code{season}, \code{weekF},
#'   \code{p}, \code{N} -- used to determine the true peak week per season.
#' @param anchorWeek Integer. Alignment anchor week (default \code{27L}).
#' @param level Numeric. CI level used in \code{params_df} (default \code{0.95}).
#' @param holdout_season Character scalar or \code{NULL}. When non-\code{NULL},
#'   rows for this season are excluded before computing the prior weights
#'   (\eqn{\mu}, \eqn{\sigma}) and before fitting \code{bias_gam}.  Use this
#'   inside a LOSO loop to avoid data leakage from the held-out fold.
#'   When \code{NULL} (default), all seasons are used and behaviour is
#'   bit-for-bit identical to the pre-fix version.
#'
#' @return A list with:
#' \describe{
#'   \item{mu_prior}{Numeric. Prior mean of true peak in \code{newWeek} space.}
#'   \item{sigma_prior}{Numeric. Prior SD of true peak in \code{newWeek} space.}
#'   \item{bias_gam}{A \code{mgcv::gam} object for residual bias correction.}
#'   \item{cal_df}{Tibble. Training rows with raw and shrunk predictions, for
#'     diagnostics.}
#' }
#'
#' @examples
#' \dontrun{
#' wf  <- readRDS("data/loso_wf_cache.rds")
#' allD <- read.csv("data/flu_testing_data.csv") |>
#'   mutate(p = pos_flua / test_flu, N = test_flu)
#' cal <- fit_peak_calibration(wf$params_df, allD)
#' # LOSO-safe usage (exclude held-out season):
#' cal_fold <- fit_peak_calibration(wf$params_df, allD, holdout_season = "2022-23")
#' # Use in production:
#' ap  <- run_alignment_prospective(currentSeason, ref, hyper, params, cal = cal)
#' }
fit_peak_calibration <- function(params_df, allD,
                                  anchorWeek = 27L, level = 0.95,
                                  holdout_season = NULL) {
  z <- stats::qnorm((1 + level) / 2)

  # When a holdout_season is specified, exclude it from prior and GAM fitting
  # to prevent data leakage in LOSO evaluation loops.
  if (!is.null(holdout_season)) {
    params_df <- dplyr::filter(params_df, .data$season != holdout_season)
    allD      <- dplyr::filter(allD, .data$season != holdout_season)
  }

  # --- True peak weekF per season ---
  true_peaks <- allD |>
    dplyr::filter(!is.na(.data$p), is.finite(.data$p), .data$N > 0) |>
    dplyr::group_by(.data$season) |>
    dplyr::slice_max(.data$p, n = 1L, with_ties = FALSE) |>
    dplyr::ungroup() |>
    dplyr::select(season, true_peak_weekF = "weekF")

  # --- Prior: historical distribution of true peak in newWeek space ---
  # Using iWeek_true (ground truth) as the anchor for an unbiased prior.
  prior_df <- params_df |>
    dplyr::filter(!is.na(.data$iWeek_true)) |>
    dplyr::select(season, iWeek_true) |>
    dplyr::distinct() |>
    dplyr::left_join(true_peaks, by = "season") |>
    dplyr::filter(!is.na(.data$true_peak_weekF)) |>
    dplyr::mutate(peak_newW = .data$true_peak_weekF - .data$iWeek_true + anchorWeek)

  mu_prior    <- mean(prior_df$peak_newW)
  sigma_prior <- max(stats::sd(prior_df$peak_newW), 1.0)   # floor at 1 week

  # --- Build calibration dataset (pre-peak rows with successful alignment) ---
  cal_df <- params_df |>
    dplyr::filter(
      !is.na(.data$t_peak), !is.na(.data$t_peak_lo), !is.na(.data$t_peak_hi),
      !is.na(.data$iWeek_true), !is.na(.data$iWeek_hat)
    ) |>
    dplyr::mutate(
      pred_peak_weekF = round(.data$t_peak - anchorWeek + .data$iWeek_hat),
      se_hat          = pmax((.data$t_peak_hi - .data$t_peak_lo) / (2 * z), 0.1),
      t_since_ign     = .data$eval_week - .data$iWeek_true
    ) |>
    dplyr::left_join(true_peaks, by = "season") |>
    dplyr::filter(
      !is.na(.data$true_peak_weekF),
      .data$eval_week <= .data$true_peak_weekF
    ) |>
    dplyr::mutate(
      # (C) Bayesian shrinkage toward prior
      prec_data        = 1 / .data$se_hat^2,
      prec_prior       = 1 / sigma_prior^2,
      prec_total       = .data$prec_data + .data$prec_prior,
      t_peak_post      = (.data$t_peak * .data$prec_data + mu_prior * .data$prec_prior) /
                         .data$prec_total,
      pred_post_weekF  = round(.data$t_peak_post - anchorWeek + .data$iWeek_hat),
      # Residual bias after shrinkage
      residual_bias    = .data$pred_post_weekF - .data$true_peak_weekF,
      # Shrinkage weight (how much prior pulled the estimate)
      shrinkage        = .data$prec_prior / .data$prec_total
    )

  # --- (A) GAM on residual bias ~ s(t_since_ign) ---
  bias_gam <- mgcv::gam(
    residual_bias ~ s(t_since_ign, k = 5),
    data   = cal_df,
    method = "REML"
  )

  list(
    mu_prior    = mu_prior,
    sigma_prior = sigma_prior,
    bias_gam    = bias_gam,
    cal_df      = cal_df
  )
}
