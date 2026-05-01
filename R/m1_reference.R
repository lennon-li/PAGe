#' Estimate a reference (template) curve for influenza positivity
#'
#' Fits a season-pooled model on aligned week index \code{newWeek} with a cyclic
#' smooth and a season random intercept. Multiple estimation methods are available
#' via the \code{method} parameter.
#'
#' @param alignedD Data frame with at least: \code{season}, \code{newWeek}, \code{y}, \code{neg}.
#'   Methods \code{"gaussian_logit"} and \code{"median_smooth"} also require \code{fit}
#'   (from \code{estimateDerivs()}).
#' @param exSeason Character vector of season labels to exclude.
#' @param k Basis dimension for the cyclic smooth.
#' @param n_weeks Integer. Number of weeks in the template domain (default 52).
#' @param nAGQ Passed to \code{gamm4}; default 1 (Laplace). Only used by binomial methods.
#' @param method Character. Estimation method:
#'   \describe{
#'     \item{"binomial"}{Binomial GAMM on raw counts via gamm4 (original).}
#'     \item{"binomial_weighted"}{Binomial GAMM on raw counts with ignition-to-peak
#'       count inflation (like estimateDerivs weighting).}
#'     \item{"gaussian_logit"}{Gaussian GAM on logit(fit) with trough downweighting.
#'       Requires \code{fit} column.}
#'     \item{"median_smooth"}{Pointwise median of per-season \code{fit} across seasons
#'       at each newWeek, then smooth with cyclic GAM. Requires \code{fit} column.}
#'     \item{"fs"}{Factor-smooth interaction via \code{s(newWeek, season, bs="fs")}.
#'       Each season gets its own smooth with shared smoothness penalty; population
#'       curve = average of per-season predictions. Requires \code{fit} column.}
#'     \item{"gaussian_logit_fs"}{Combined: global cyclic smooth \code{s(newWeek, bs="cc")}
#'       plus factor-smooth \code{s(newWeek, season, bs="fs")} for per-season shape
#'       deviations. Population curve from the global smooth only (fs excluded from
#'       prediction). Requires \code{fit} column.}
#'   }
#' @param trough_weight Numeric in (0,1]. Weight for pre-season (phase==0) rows.
#'   Only used by \code{"gaussian_logit"} and \code{"binomial_weighted"}. Default 0.1.
#' @param peak_weight_boost Numeric >= 1. Count inflation factor for ignition-to-peak
#'   rows. Only used by \code{"binomial_weighted"}. Default 3.
#' @param agg Character. Aggregation method for the \code{"fs"} method's population curve:
#'   \code{"median"} (default) takes pointwise median across seasons on logit scale;
#'   \code{"mean"} takes the mean. Ignored for other methods.
#'
#' @return A list with components: \code{mod2}, \code{g_ref_fun}, \code{g_ref_safe},
#'   \code{g_ref_mu_se}, \code{ref_df}, \code{pred_df}, \code{dat}, \code{anchorWeek},
#'   \code{method}.
#'
estimateRef <- function(alignedD,
                        exSeason = NULL,
                        k = 10,
                        n_weeks = 52L,
                        nAGQ = 1,
                        method = c("binomial", "binomial_weighted",
                                   "gaussian_logit", "median_smooth",
                                   "fs", "gaussian_logit_fs"),
                        trough_weight = 0.1,
                        peak_weight_boost = 3,
                        agg = c("median", "mean")) {

  method <- match.arg(method)
  agg    <- match.arg(agg)

  if (!requireNamespace("gamm4",  quietly = TRUE)) stop("Need 'gamm4'.")
  if (!requireNamespace("mgcv",   quietly = TRUE)) stop("Need 'mgcv'.")
  if (!requireNamespace("tibble", quietly = TRUE)) stop("Need 'tibble'.")
  if (!requireNamespace("dplyr",  quietly = TRUE)) stop("Need 'dplyr'.")
  if (!requireNamespace("gratia", quietly = TRUE)) stop("Need 'gratia'.")

  needed <- c("season", "newWeek", "y", "neg")
  miss <- setdiff(needed, names(alignedD))
  if (length(miss) > 0) stop("alignedD is missing columns: ", paste(miss, collapse = ", "))

  # ---- Helper: compute ignition-to-peak weights per row ----
  .make_weights <- function(dat, trough_weight, peak_weight_boost,
                            peak_weight_decay = 0.3) {
    wt <- rep(1.0, nrow(dat))
    if (!"phase" %in% names(dat)) return(wt)
    wt[dat$phase == 0L] <- trough_weight
    if (peak_weight_boost > 1 && "iWeek" %in% names(dat) && "weekF" %in% names(dat)) {
      for (s in unique(dat$season)) {
        idx <- which(dat$season == s & dat$phase == 1L)
        if (length(idx) == 0) next
        iw <- dat$iWeek[idx[1]]
        wk <- dat$weekF[idx]
        p_obs <- dat$fit[idx]
        pk <- wk[which.max(p_obs)]
        w <- rep(1.0, length(idx))
        in_rise <- wk >= iw & wk <= pk
        past_pk <- wk > pk
        w[in_rise]  <- peak_weight_boost
        w[past_pk]  <- 1 + (peak_weight_boost - 1) *
          exp(-peak_weight_decay * (wk[past_pk] - pk))
        wt[idx] <- w
      }
    }
    wt
  }

  dat <- alignedD
  if (!is.null(exSeason) && length(exSeason) > 0) {
    dat <- dplyr::filter(dat, !(.data$season %in% exSeason))
  }
  dat <- dplyr::mutate(dat, newWeek = pmin(as.integer(.data$newWeek), as.integer(n_weeks)))

  # ---------- helpers for re-smooth models ----------
  # gaussian_logit: s(season, bs="re") — exclude="s(season)" for population curve
  # fs: s(newWeek, season, bs="fs") — population curve = average across seasons
  # gaussian_logit_fs: global s(newWeek) + fs deviations — exclude fs for population curve
  uses_re_smooth <- method == "gaussian_logit"
  uses_fs        <- method == "fs"              # average-across-seasons approach
  uses_fs_combo  <- method == "gaussian_logit_fs"  # exclude-fs approach

  # ==================== METHOD: binomial (original) ====================
  if (method == "binomial") {
    mod2 <- gamm4::gamm4(
      cbind(y, neg) ~ s(newWeek, bs = "cc", k = k),
      random = ~(1 | season),
      data   = dat,
      family = stats::binomial(),
      nAGQ   = nAGQ
    )

  # ==================== METHOD: binomial_weighted ====================
  } else if (method == "binomial_weighted") {
    # Inflate counts for in-season rows (like estimateDerivs' ignition-to-peak boost).
    # phase==1 rows get counts multiplied by peak_weight_boost; phase==0 by trough_weight.
    wt <- rep(1.0, nrow(dat))
    if ("phase" %in% names(dat)) {
      wt[dat$phase == 1L] <- peak_weight_boost
      wt[dat$phase == 0L] <- trough_weight
    }
    dat$.y_w   <- as.integer(round(wt * dat$y))
    dat$.neg_w <- as.integer(round(wt * dat$neg))
    mod2 <- gamm4::gamm4(
      cbind(.y_w, .neg_w) ~ s(newWeek, bs = "cc", k = k),
      random = ~(1 | season),
      data   = dat,
      family = stats::binomial(),
      nAGQ   = nAGQ
    )
    dat$.y_w <- NULL; dat$.neg_w <- NULL

  # ==================== METHOD: gaussian_logit ====================
  } else if (method == "gaussian_logit") {
    if (!"fit" %in% names(dat))
      stop("method='gaussian_logit' requires a 'fit' column from estimateDerivs().")
    dat$logit_fit <- stats::qlogis(pmin(pmax(dat$fit, 1e-4), 1 - 1e-4))
    dat$.gw <- .make_weights(dat, trough_weight, peak_weight_boost)
    dat$season <- factor(dat$season)
    mod_gam <- mgcv::gam(
      logit_fit ~ s(newWeek, bs = "cc", k = k) + s(season, bs = "re"),
      data = dat, weights = .gw, method = "REML"
    )
    dat$.gw <- NULL
    mod2 <- list(gam = mod_gam)

  # ==================== METHOD: median_smooth ====================
  } else if (method == "median_smooth") {
    if (!"fit" %in% names(dat))
      stop("method='median_smooth' requires a 'fit' column from estimateDerivs().")
    # Step 1: pointwise median of per-season smoothed fit at each newWeek
    agg <- dat |>
      dplyr::group_by(newWeek) |>
      dplyr::summarise(
        med_p  = stats::median(fit, na.rm = TRUE),
        n_seas = dplyr::n_distinct(season),
        .groups = "drop"
      ) |>
      dplyr::filter(!is.na(med_p), med_p > 0)
    agg$logit_med <- stats::qlogis(pmin(pmax(agg$med_p, 1e-4), 1 - 1e-4))
    # Step 2: smooth the median curve with a single cyclic GAM (no RE needed)
    mod_gam <- mgcv::gam(
      logit_med ~ s(newWeek, bs = "cc", k = k),
      data = agg, method = "REML"
    )
    mod2 <- list(gam = mod_gam, agg = agg)

  # ==================== METHOD: fs (factor smooth) ====================
  } else if (method == "fs") {
    if (!"fit" %in% names(dat))
      stop("method='fs' requires a 'fit' column from estimateDerivs().")
    dat$logit_fit <- stats::qlogis(pmin(pmax(dat$fit, 1e-4), 1 - 1e-4))
    dat$.gw <- .make_weights(dat, trough_weight, peak_weight_boost)
    dat$season <- factor(dat$season)
    mod_gam <- mgcv::gam(
      logit_fit ~ s(newWeek, season, bs = "fs", xt = list(bs = "cc"), k = k),
      data = dat, weights = .gw, method = "REML",
      knots = list(newWeek = c(0.5, n_weeks + 0.5))
    )
    dat$.gw <- NULL
    mod2 <- list(gam = mod_gam)

  # ==================== METHOD: gaussian_logit_fs (ensemble) ====================
  } else if (method == "gaussian_logit_fs") {
    # Ensemble: average the population curves from gaussian_logit and fs methods.
    # Both sub-models are fit internally, then their logit-scale predictions are averaged.
    if (!"fit" %in% names(dat))
      stop("method='gaussian_logit_fs' requires a 'fit' column from estimateDerivs().")
    dat$logit_fit <- stats::qlogis(pmin(pmax(dat$fit, 1e-4), 1 - 1e-4))
    dat$.gw <- .make_weights(dat, trough_weight, peak_weight_boost)
    dat$season <- factor(dat$season)

    # Sub-model 1: gaussian_logit (global smooth + season RE)
    mod_gl <- mgcv::gam(
      logit_fit ~ s(newWeek, bs = "cc", k = k) + s(season, bs = "re"),
      data = dat, weights = .gw, method = "REML"
    )
    # Sub-model 2: fs (factor smooth)
    mod_fs <- mgcv::gam(
      logit_fit ~ s(newWeek, season, bs = "fs", xt = list(bs = "cc"), k = k),
      data = dat, weights = .gw, method = "REML",
      knots = list(newWeek = c(0.5, n_weeks + 0.5))
    )
    dat$.gw <- NULL
    mod2 <- list(gam = mod_gl, gam_fs = mod_fs)
  }

  # ==================== Common output construction ====================
  grid <- data.frame(newWeek = seq_len(n_weeks))
  pred_exclude <- if (uses_re_smooth) {
    "s(season)"
  } else if (uses_fs_combo) {
    "s(newWeek,season)"
  } else {
    NULL
  }

  needs_season_col <- uses_re_smooth || uses_fs_combo
  pred_grid <- if (needs_season_col) {
    cbind(grid, season = factor(levels(dat$season)[1L], levels = levels(dat$season)))
  } else if (method == "median_smooth") {
    grid
  } else {
    grid
  }

  # For fs method: aggregate predictions across all season levels for population curve
  if (uses_fs) {
    seas_levs <- levels(dat$season)
    eta_mat <- sapply(seas_levs, function(s) {
      nd <- cbind(grid, season = factor(s, levels = seas_levs))
      drop(stats::predict(mod2$gam, newdata = nd, type = "link"))
    })
    colnames(eta_mat) <- seas_levs
    eta_hat <- if (agg == "median") {
      apply(eta_mat, 1, stats::median)
    } else {
      rowMeans(eta_mat)
    }
  } else if (uses_fs_combo) {
    # Ensemble: average logit-scale predictions from gaussian_logit and fs sub-models
    seas_levs <- levels(dat$season)
    # gaussian_logit population curve (exclude season RE)
    gl_grid <- cbind(grid, season = factor(seas_levs[1L], levels = seas_levs))
    eta_gl <- drop(stats::predict(mod2$gam, newdata = gl_grid, type = "link",
                                  exclude = "s(season)"))
    # fs population curve (average across seasons)
    eta_fs_mat <- sapply(seas_levs, function(s) {
      nd <- cbind(grid, season = factor(s, levels = seas_levs))
      drop(stats::predict(mod2$gam_fs, newdata = nd, type = "link"))
    })
    eta_fs <- rowMeans(eta_fs_mat)
    # Average on logit scale
    eta_hat <- (eta_gl + eta_fs) / 2
  } else {
    eta_hat <- drop(stats::predict(mod2$gam, newdata = pred_grid, type = "link",
                                   exclude = pred_exclude))
  }
  g_ref_fun  <- stats::splinefun(grid$newWeek, eta_hat, method = "natural")
  g_ref_safe <- function(u) g_ref_fun(pmin(pmax(u, 1L), n_weeks))

  dat <- dplyr::mutate(dat, fit_ref = stats::plogis(g_ref_safe(.data$newWeek)))

  weeks  <- seq_len(n_weeks)
  ref_df <- tibble::tibble(newWeek = weeks, p_gamm = stats::plogis(g_ref_fun(weeks)))

  # --- predictions + CI ---
  is_logit_model <- method %in% c("gaussian_logit", "median_smooth", "fs", "gaussian_logit_fs")

  if (uses_fs || uses_fs_combo) {
    fit    <- stats::plogis(eta_hat)
    se_fit <- if (uses_fs) {
      apply(eta_mat, 1, stats::sd) / sqrt(ncol(eta_mat))
    } else {
      rep(0, length(fit))
    }
    low      <- stats::plogis(eta_hat - 1.96 * se_fit)
    high     <- stats::plogis(eta_hat + 1.96 * se_fit)
    binom_se <- rep(0, length(fit))
    total_se <- se_fit
  } else if (is_logit_model) {
    pr_nd <- if (needs_season_col) pred_grid
             else if (method == "median_smooth") grid
             else dplyr::mutate(grid, season = "fit")
    pr <- stats::predict(mod2$gam, newdata = pr_nd, type = "response",
                         se.fit = TRUE, exclude = pred_exclude)
    fit    <- as.numeric(pr$fit)
    se_fit <- as.numeric(pr$se.fit)
    low      <- stats::plogis(eta_hat - 1.96 * se_fit)
    high     <- stats::plogis(eta_hat + 1.96 * se_fit)
    fit      <- stats::plogis(fit)
    binom_se <- rep(0, length(fit))
    total_se <- se_fit
  } else {
    # binomial / binomial_weighted: predict from gamm4 GAM component
    pr     <- stats::predict(mod2$gam, newdata = grid, type = "response", se.fit = TRUE)
    fit    <- as.numeric(pr$fit)
    se_fit <- as.numeric(pr$se.fit)
    if ("N" %in% names(dat)) {
      N_med <- tapply(dat$N, dat$newWeek, stats::median, na.rm = TRUE)
      N_vec <- as.numeric(N_med[as.character(grid$newWeek)])
    } else {
      N_vec <- rep(NA_real_, nrow(grid))
    }
    binom_se <- if (all(is.na(N_vec))) rep(0, length(fit)) else sqrt(pmax(0, fit * (1 - fit) / N_vec))
    total_se <- sqrt(binom_se^2 + se_fit^2)
    low  <- pmax(0, fit - 1.96 * total_se)
    high <- pmin(1, fit + 1.96 * total_se)
  }

  # --- derivatives ---
  if (uses_fs || uses_fs_combo) {
    # Analytical derivatives from the spline interpolant of eta_hat
    d1_eta <- g_ref_fun(grid$newWeek, deriv = 1)
    d2_eta <- g_ref_fun(grid$newWeek, deriv = 2)
  } else {
    deriv_grid   <- if (needs_season_col) pred_grid else grid
    deriv_select <- if (needs_season_col) "s(newWeek)" else NULL
    d1_eta <- gratia::derivatives(mod2$gam, order = 1, se = TRUE, data = deriv_grid,
                                  select = deriv_select)$.derivative
    d2_eta <- gratia::derivatives(mod2$gam, order = 2, se = TRUE, data = deriv_grid,
                                  select = deriv_select)$.derivative
  }

  pred_df <- tibble::tibble(
    newWeek = grid$newWeek, fit = fit, se.fit = se_fit,
    binom.se = binom_se, total.se = total_se,
    low = low, high = high, season = "fit",
    d1_eta = d1_eta, d2_eta = d2_eta,
    d1_p = fit * (1 - fit) * d1_eta,
    d2_p = fit * (1 - fit) * d2_eta + fit * (1 - fit) * (1 - 2 * fit) * (d1_eta^2)
  )

  anchorWeek <- attr(alignedD, "anchorWeek")
  if (is.null(anchorWeek)) anchorWeek <- NA_integer_

  if (uses_fs) {
    g_ref_mu_se <- (function(gam_obj, seas_levs, agg_method) {
      function(u) {
        eta_mat <- sapply(seas_levs, function(s) {
          nd <- data.frame(newWeek = u, season = factor(s, levels = seas_levs))
          drop(stats::predict(gam_obj, newdata = nd, type = "link"))
        })
        if (is.null(dim(eta_mat))) eta_mat <- matrix(eta_mat, nrow = 1)
        mu <- if (agg_method == "median") {
          apply(eta_mat, 1, stats::median)
        } else {
          rowMeans(eta_mat)
        }
        list(mu = mu,
             se = apply(eta_mat, 1, stats::sd) / sqrt(ncol(eta_mat)))
      }
    })(mod2$gam, levels(dat$season), agg)
  } else if (uses_fs_combo) {
    # Ensemble: average gaussian_logit + fs population curves
    g_ref_mu_se <- (function(gam_gl, gam_fs, seas_levs) {
      function(u) {
        # gaussian_logit population curve
        nd_gl <- data.frame(newWeek = u, season = factor(seas_levs[1L], levels = seas_levs))
        eta_gl <- drop(stats::predict(gam_gl, newdata = nd_gl, type = "link",
                                      exclude = "s(season)"))
        # fs population curve (average across seasons)
        eta_fs_mat <- sapply(seas_levs, function(s) {
          nd <- data.frame(newWeek = u, season = factor(s, levels = seas_levs))
          drop(stats::predict(gam_fs, newdata = nd, type = "link"))
        })
        if (is.null(dim(eta_fs_mat))) eta_fs_mat <- matrix(eta_fs_mat, nrow = 1)
        eta_fs <- rowMeans(eta_fs_mat)
        mu <- (eta_gl + eta_fs) / 2
        list(mu = mu, se = rep(0, length(mu)))
      }
    })(mod2$gam, mod2$gam_fs, levels(dat$season))
  } else {
    g_ref_mu_se <- (function(gam_obj, excl, season_lev) {
      function(u) {
        nd <- if (!is.null(season_lev)) {
          data.frame(newWeek = u, season = factor(season_lev[1L], levels = season_lev))
        } else {
          data.frame(newWeek = u)
        }
        out <- stats::predict(gam_obj, newdata = nd, type = "link", se.fit = TRUE,
                              exclude = excl)
        list(mu = drop(out$fit), se = drop(out$se.fit))
      }
    })(mod2$gam, pred_exclude,
       if (needs_season_col) levels(dat$season) else NULL)
  }

  out <- list(
    mod2        = mod2,
    g_ref_fun   = g_ref_fun,
    g_ref_safe  = g_ref_safe,
    g_ref_mu_se = g_ref_mu_se,
    ref_df      = ref_df,
    pred_df     = pred_df,
    dat         = dat,
    anchorWeek  = anchorWeek,
    method      = method,
    agg         = agg
  )
  # For fs method: include per-season logit predictions for diagnostics
  if (uses_fs) out$eta_mat <- eta_mat
  out
}

#' Estimate smoothed positivity and derivatives (d1/d2) by season using binomial GAMs
#'
#' Fits a separate binomial GAM for each season to smooth weekly positivity and
#' computes first and second derivatives of the fitted smooth. Returns the input
#' data augmented with fitted values, confidence intervals, and derivative estimates
#' (with simultaneous intervals), plus the fitted model objects.
#'
#' When \code{peak_weight_boost > 1}, observations between ignition and the observed
#' peak receive higher weight, with a soft exponential decay after the peak. This
#' emphasises the rising-limb-through-peak region that downstream alignment and
#' forecasting (M2) care about most.
#'
#' @param allD A data.frame containing (at minimum) season, week index, positives, and tests.
#' @param k Integer. Basis dimension passed to \code{mgcv::s()} for the within-season smooth.
#' @param bs Character. Smoother basis for \code{mgcv::s()}, e.g. \code{"ps"} or \code{"tp"}.
#' @param week_col Character. Column name for the within-season week index used in smoothing
#'   (default \code{"weekF"}).
#' @param season_col Character. Column name identifying season (default \code{"season"}).
#' @param y_col Character. Column name for positives (default \code{"y"}).
#' @param n_col Character. Column name for tests (default \code{"N"}).
#' @param ci_level Numeric in (0,1). Confidence level for fitted mean intervals on the response
#'   scale (default 0.95).
#' @param deriv_interval Character. Interval type passed to \code{gratia::derivatives()},
#'   typically \code{"simultaneous"} (default) or \code{"confidence"}.
#' @param method Character. Smoothing parameter estimation method passed to \code{mgcv::gam()},
#'   default \code{"REML"}.
#' @param peak_weight_boost Numeric >= 1. Multiplicative weight applied to observations
#'   between ignition and observed peak (default 1 = no boost).
#' @param peak_weight_decay Numeric > 0. Exponential decay rate for weights after the
#'   observed peak. Smaller values = slower decay (default 0.3, ~2-week half-life).
#' @param ignition_weeks Optional named integer vector mapping season labels to ignition
#'   week values (in \code{week_col} space). Required when \code{peak_weight_boost > 1}.
#'   If \code{NULL} and boosting is requested, falls back to the first week where
#'   \code{p = y/N >= 0.01}.
#'
#' @return A list with two elements:
#' \describe{
#'   \item{data}{A data.frame of \code{allD} augmented with columns:
#'     \code{neg}, \code{fit}, \code{fit_low}, \code{fit_high},
#'     \code{d1}, \code{d1_low}, \code{d1_high},
#'     \code{d2}, \code{d2_low}, \code{d2_high}.}
#'   \item{models}{A named list of fitted \code{mgcv::gam} objects (one per season).}
#' }
#'
#' @importFrom stats as.formula predict qnorm
#' @import data.table
estimateDerivs <- function(
    allD,
    k = 10,
    bs = "ps",
    week_col   = "weekF",
    season_col = "season",
    y_col      = "y",
    n_col      = "N",
    ci_level   = 0.95,
    deriv_interval = "simultaneous",
    method = "REML",
    peak_weight_boost = 1,
    peak_weight_decay = 0.3,
    ignition_weeks    = NULL
) {
  stopifnot(
    is.data.frame(allD),
    all(c(season_col, week_col, y_col, n_col) %in% names(allD))
  )
  
  if (!requireNamespace("mgcv", quietly = TRUE)) stop("Package 'mgcv' is required.")
  if (!requireNamespace("gratia", quietly = TRUE)) stop("Package 'gratia' is required.")
  if (!requireNamespace("data.table", quietly = TRUE)) stop("Package 'data.table' is required.")
  
  DT <- data.table::as.data.table(allD)
  DT[, (season_col) := as.factor(as.character(get(season_col)))]
  DT[, neg := get(n_col) - get(y_col)]
  
  z <- stats::qnorm(1 - (1 - ci_level) / 2)
  
  idx_by_season <- split(seq_len(nrow(DT)), DT[[season_col]])
  
  fit_one <- function(idx) {
    dts <- DT[idx]
    data.table::setorderv(dts, week_col)

    # ensure unique week within season
    if (anyDuplicated(dts[[week_col]]) > 0L) {
      stop("Duplicate ", week_col, " within a season; cannot merge derivatives safely.")
    }

    # --- ignition-to-peak weighting ---
    # Inflate counts in temporary columns to upweight the ignition-to-peak region.
    # Original y/neg columns are left untouched so downstream p = y/N remains valid.
    if (peak_weight_boost > 1) {
      s_label <- as.character(dts[[season_col]][1])
      wk      <- dts[[week_col]]
      p_obs   <- dts[[y_col]] / (dts[[y_col]] + dts[["neg"]])

      # ignition week: from user-supplied map, or fallback to first p >= 0.01
      iw <- if (!is.null(ignition_weeks) && s_label %in% names(ignition_weeks)) {
        as.integer(ignition_weeks[[s_label]])
      } else {
        cand <- wk[!is.na(p_obs) & p_obs >= 0.01]
        if (length(cand) > 0) min(cand) else min(wk, na.rm = TRUE)
      }

      # observed peak: argmax of raw positivity (guard against all-zero/all-NA)
      valid_idx <- which(!is.na(p_obs) & p_obs > 0)
      obs_peak <- if (length(valid_idx) > 0) {
        wk[valid_idx[which.max(p_obs[valid_idx])]]
      } else {
        max(wk, na.rm = TRUE)  # no valid peak: boost nowhere, decay starts at end
      }

      # soft ramp weight vector
      wt <- rep(1.0, nrow(dts))
      in_region  <- wk >= iw & wk <= obs_peak
      past_peak  <- wk > obs_peak
      wt[in_region] <- peak_weight_boost
      wt[past_peak] <- 1 + (peak_weight_boost - 1) *
        exp(-peak_weight_decay * (wk[past_peak] - obs_peak))

      # inflate counts into temporary columns — originals y/neg stay intact in output
      dts[, .y_fit   := as.integer(round(wt * get(y_col)))]
      dts[, .neg_fit := as.integer(round(wt * neg))]
    } else {
      dts[, .y_fit   := get(y_col)]
      dts[, .neg_fit := neg]
    }

    fml <- stats::as.formula(
      sprintf("cbind(.y_fit, .neg_fit) ~ s(%s, k = %d, bs = '%s')",
              week_col, k, bs)
    )

    g <- mgcv::gam(
      formula = fml,
      data    = dts,
      family  = binomial(),
      method  = method
    )
    
    # predictions on link scale -> transform => response-scale CI
    pr  <- stats::predict(g, newdata = dts, type = "link", se.fit = TRUE)
    eta <- as.numeric(pr$fit)
    se  <- as.numeric(pr$se.fit)
    
    dts[, `:=`(
      fit      = g$family$linkinv(eta),
      fit_low  = g$family$linkinv(eta - z * se),
      fit_high = g$family$linkinv(eta + z * se)
    )]
    
    d1 <- gratia::derivatives(g, order = 1, interval = deriv_interval, data = dts)
    d2 <- gratia::derivatives(g, order = 2, interval = deriv_interval, data = dts)
    
    d1 <- data.table::as.data.table(d1)
    d2 <- data.table::as.data.table(d2)
    
    # bring along season + week, keep only needed cols
    # (gratia output includes the covariate column named week_col, e.g. weekF)
    d1 <- d1[, .(
      season_tmp = dts[[season_col]][1],
      week_tmp   = get(week_col),
      d1         = .derivative,
      d1_low     = .lower_ci,
      d1_high    = .upper_ci
    )]
    d2 <- d2[, .(
      season_tmp = dts[[season_col]][1],
      week_tmp   = get(week_col),
      d2         = .derivative,
      d2_low     = .lower_ci,
      d2_high    = .upper_ci
    )]
    
    # ensure unique weeks in derivative outputs too
    if (anyDuplicated(d1$week_tmp) > 0L || anyDuplicated(d2$week_tmp) > 0L) {
      stop("derivatives() returned duplicate ", week_col, " values; cannot merge safely.")
    }
    
    # merge by season+week (robust across seasons)
    out <- merge(
      dts, d1,
      by.x = c(season_col, week_col),
      by.y = c("season_tmp", "week_tmp"),
      all.x = TRUE,
      sort = FALSE
    )
    out <- merge(
      out, d2,
      by.x = c(season_col, week_col),
      by.y = c("season_tmp", "week_tmp"),
      all.x = TRUE,
      sort = FALSE
    )
    
    data.table::setorderv(out, c(season_col, week_col))
    out[, .y_fit   := NULL]
    out[, .neg_fit := NULL]
    list(data = out, model = g)
  }

  res_list  <- lapply(idx_by_season, fit_one)
  data_out  <- data.table::rbindlist(lapply(res_list, `[[`, "data"))
  models_out <- lapply(res_list, `[[`, "model")
  names(models_out) <- names(idx_by_season)
  
  list(
    data   = as.data.frame(data_out),
    models = models_out
  )
}
#' Align within-season week index by shifting ignition to a common anchor week
#'
#' @param outs list of flagIgnition() outputs (each has $data and $ignition)
#' @param season_col season column name (default "season")
#' @param week_col within-season week column name (default "weekF")
#' @param nweek_col season length column name (default "nW_true"); if missing uses max(weekF) per season
#'
#' @return data.frame with newWeek and phase_inSeason added; attributes: anchorWeek, ignD
alignIgnition <- function(outs,
                          season_col = "season",
                          week_col   = "weekF",
                          nweek_col  = "nW_true") {
  stopifnot(is.list(outs), length(outs) > 0)
  if (!requireNamespace("data.table", quietly = TRUE)) stop("Need 'data.table'.")
  if (!requireNamespace("purrr", quietly = TRUE)) stop("Need 'purrr'.")
  
  # bind data + ignition
  allD <- data.table::rbindlist(purrr::map(outs, "data"), fill = TRUE)
  ignD <- data.table::rbindlist(purrr::map(outs, "ignition"), fill = TRUE)
  
  stopifnot(season_col %in% names(allD), week_col %in% names(allD))
  stopifnot(season_col %in% names(ignD), week_col %in% names(ignD))
  
  # robust int coercion (handles factor/character safely)
  to_int <- function(x) suppressWarnings(as.integer(as.character(x)))
  
  allD[, (season_col) := as.character(get(season_col))]
  allD[, (week_col)   := to_int(get(week_col))]
  
  ignD[, (season_col) := as.character(get(season_col))]
  ignD[, (week_col)   := to_int(get(week_col))]
  
  # one ignition week per season (first non-NA)
  ign_small <- ignD[, .(iWeek = get(week_col)) , by = season_col][
    , .(iWeek = if (all(is.na(iWeek))) NA_integer_ else iWeek[which(!is.na(iWeek))[1]]),
    by = season_col
  ]
  
  anchorWeek <- to_int(stats::median(ign_small$iWeek, na.rm = TRUE))
  
  # named maps: season -> iWeek and season -> offset
  iweek_map  <- setNames(ign_small$iWeek, ign_small[[season_col]])
  offset_map <- setNames(anchorWeek - ign_small$iWeek, ign_small[[season_col]])
  
  # season length nW (52/53)
  if (!is.null(nweek_col) && nweek_col %in% names(allD)) {
    allD[, nW := to_int(get(nweek_col))]
    allD[is.na(nW), nW := max(get(week_col), na.rm = TRUE), by = season_col]
  } else {
    allD[, nW := max(get(week_col), na.rm = TRUE), by = season_col]
  }
  
  # lookup iWeek and offset WITHOUT merge
  allD[, iWeek  := iweek_map[get(season_col)]]
  allD[, offset := offset_map[get(season_col)]]
  
  # aligned week (wrap by nW to handle 52 vs 53)
  allD[, newWeek := ifelse(
    is.na(get(week_col)) | is.na(iWeek) | is.na(nW) | is.na(anchorWeek),
    NA_integer_,
    ((get(week_col) + offset - 1L) %% nW) + 1L
  )]
  
  # ---- phase indicator: in-season (>= ignition) vs pre-season (< ignition) ----
  allD[, phase := as.integer(
    !is.na(iWeek) &
      !is.na(get(week_col)) &
      (get(week_col) >= iWeek)
  )]
  
  allD[, offset := NULL]  # drop helper
  
  out <- as.data.frame(allD)
  attr(out, "anchorWeek") <- anchorWeek
  attr(out, "ignD")       <- as.data.frame(ign_small)
  out
}

