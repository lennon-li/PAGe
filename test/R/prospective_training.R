# Prospective training utilities
# - Prospective-safe feature construction for training (no future leakage)
# - Stage-2 modular model specification (turn terms on/off)
# - Stage-2 tuning and training

`%||%` <- function(x, y) if (!is.null(x)) x else y

# =========================================================
# Stage-2 modular model specification
# =========================================================

#' Create a Stage-2 model specification (hyperparameters + term toggles)
#'
#' This helper defines both (i) the tuned hyperparameters used to construct
#' Stage-2 features (template shift/ramp, state EWMA, leads, etc.) and (ii)
#' the exact Stage-2 model structure (which terms are included and their
#' basis sizes).
#'
#' ## Core feature hyperparameters
#' These control how the Stage-2 design matrix is built in \code{prep_stage2_joint()}:
#' \describe{
#'   \item{\code{delta}}{Template horizontal shift (weeks) applied to the template mean curve.}
#'   \item{\code{K}}{Ramp length controlling how quickly the template effect is turned on after ignition.}
#'   \item{\code{alpha_state}}{EWMA smoothing for the current-state logit positivity \code{z_ema}.}
#'   \item{\code{pre_buffer}}{How many weeks before ignition to include as post-ignition training rows.}
#'   \item{\code{leads}}{Forecast horizons (e.g., \code{c(1L,2L)} gives leads h1 and h2).}
#'   \item{\code{use_ramp}}{Deprecated. Use K only (K<=1 means no ramp).}
#' }
#'
#' ## Model terms (linear predictor)
#' The joint Stage-2 model is fit on stacked leads with lead-specific effects.
#' Terms are enabled/disabled via basis sizes (\code{k_*}).
#'
#' - Template term (backbone):
#'   \itemize{
#'     \item \code{template_mode='smooth'}: \code{s(logit_f_eff, by=lead, bs='ts', k=k_f)}
#'     \item \code{template_mode='offset'}: \code{offset(logit_f_eff)}
#'     \item \code{template_mode='none'}  : omit template term
#'   }
#'
#' - Time/alignment terms:
#'   \itemize{
#'     \item \code{k_w>0}: \code{s(newWeek, by=lead, bs=bs_week, k=k_w)}
#'     \item \code{k_s>0}: \code{s(newWeek, season_h, bs='fs', k=k_s, xt=list(bs=bs_fs_marginal))}
#'   }
#'
#' - Current-state and covariates:
#'   \itemize{
#'     \item \code{k_e>0}: \code{s(z_ema, by=lead, bs='ts', k=k_e)}
#'     \item \code{k_n>0}: \code{s(logN_now, by=lead, bs='ts', k=k_n)}
#'     \item \code{k_1>0}: \code{s(d1_now, by=lead, bs='ts', k=k_1)}
#'     \item \code{k_2>0}: \code{s(d2_now, by=lead, bs='ts', k=k_2)}
#'     \item Season random intercept: \code{s(season, bs='re')} (always included)
#'   }
#'
#' ## How to turn terms on/off
#' - For any smooth term: set its \code{k_*} to \code{0} (off) or \code{>0} (on).
#' - For the template term: set \code{template_mode='none'} to remove it.
#' - You may also disable template contribution at the feature level by setting
#'   \code{delta=NA} or \code{K=NA}, which forces \code{logit_f_eff=0}.
#'
#' @param delta Integer template shift (weeks). Use NA to disable the template covariate.
#' @param K Integer ramp length. Use NA to disable the template covariate.
#' @param k_f Basis size for the template smooth when \code{template_mode='smooth'}.
#' @param alpha_state Numeric in (0,1) for EWMA smoothing of \code{z_ema}.
#' @param pre_buffer Integer >=0 weeks before ignition to include.
#' @param leads Integer vector of forecast horizons.
#' @param use_ramp Deprecated (ignored). Ramp is controlled only by K (K<=1 means no ramp).
#' @param template_mode One of \code{'smooth'}, \code{'offset'}, \code{'none'}.
#' @param k_e,k_n,k_1,k_2 Basis sizes for those smooth terms; \code{<=0} disables.
#' @param k_w Basis size for \code{s(newWeek, by=lead)}; \code{<=0} disables.
#' @param k_s Basis size for \code{s(newWeek, season, bs='fs')}; \code{<=0} disables.
#' @param bs_week Basis for \code{s(newWeek, by=lead)} (default \code{'ts'}).
#' @param bs_fs_marginal Marginal basis for newWeek inside \code{bs='fs'}.
#'   Recommended \code{'tp'} or \code{'cr'}. Default \code{'tp'}.
#' @param use_season_re Deprecated (ignored). The season random intercept b_s is always included.
#'
#' @return A list (spec) containing:
#' \describe{
#'   \item{\code{best_row}}{A 1-row data.frame with \code{delta,K,k_f,alpha_state} for compatibility.}
#'   \item{\code{formula}}{The mgcv formula implied by the spec.}
#'   \item{\code{exclude_newseason}}{Terms to exclude when predicting a brand-new season.}
#'   \item{\code{...}}{All input settings, stored as fields.}
#' }
#'
#' @examples
#' \dontrun{
#' # Base model (similar to the original QMD): template smooth + z_ema + logN + d1 + d2 + season RE
#' spec_base <- stage2_make_spec(delta=0, K=3, k_f=6, alpha_state=0.30,
#'   template_mode='smooth', k_w=0, k_s=0, k_2=6)
#'
#' # Full model (turn on everything)
#' spec_full <- stage2_make_spec(delta=0, K=3, k_f=6, alpha_state=0.30,
#'   template_mode='smooth', k_w=8, k_s=6,
#'   k_e=6, k_n=6, k_1=6, k_2=6, season RE always included)
#'
#' # Drop d2
#' spec_no_d2 <- stage2_make_spec(delta=0, K=3, k_f=6, alpha_state=0.30,
#'   template_mode='smooth', k_2=0)
#' }
#'
#' @export
stage2_make_spec <- function(
    delta = 0L,
    K = 3L,
    k_f = 6L,
    alpha_state = 0.30,
    pre_buffer = 0L,
    leads = c(1L, 2L),
    # --- indicators / template entry ---
    T = c("S", "O", "N"),          # S: smooth, O: offset, N: none
    template_mode = NULL,          # (back-compat) "smooth"/"offset"/"none"
    # (back-compat) if provided, K still controls ramp; when K<=1 there is no ramp
    use_ramp = NULL,
    # --- basis sizes / toggles ---
    k_e = 6L,
    k_n = 6L,
    k_1   = 6L,
    k_2   = 6L,
    k_w = 0L,
    k_s   = 0L,
    bs_week = "ts",
    bs_fs_marginal = "tp",
    use_season_re = TRUE,
    # --- time-decay training weight ---
    lambda_w = 0
) {
  # Map old template_mode -> T if supplied
  if (!is.null(template_mode)) {
    template_mode <- match.arg(template_mode, choices = c("smooth","offset","none"))
    T <- switch(template_mode, smooth = "S", offset = "O", none = "N")
  } else {
    T <- match.arg(T, choices = c("S","O","N"))
  }
  
  # Keep a back-compat string version too (useful for printing)
  template_mode2 <- switch(T, S = "smooth", O = "offset", N = "none")
  
  # 'use_ramp' is deprecated; K controls ramping. If user sets use_ramp=FALSE,
  # we emulate "no ramp" by forcing K=1.
  if (!is.null(use_ramp) && !isTRUE(use_ramp)) K <- 1L
  
  if (!isTRUE(use_season_re)) {
    # b_s is always included in the model; keep argument for backward compatibility.
    use_season_re <- TRUE
  }
  
  spec <- list(
    delta = if (is.na(delta)) NA_integer_ else as.integer(delta),
    K = if (is.na(K)) NA_integer_ else as.integer(K),
    k_f = as.integer(k_f),
    alpha_state = as.numeric(alpha_state),
    pre_buffer = as.integer(pre_buffer),
    leads = as.integer(leads),
    
    # indicators
    T = T,
    template_mode = template_mode2,  # back-compat label
    
    # k’s
    k_e = as.integer(k_e),
    k_n = as.integer(k_n),
    k_1   = as.integer(k_1),
    k_2   = as.integer(k_2),
    k_w = as.integer(k_w),
    k_s   = as.integer(k_s),
    
    # bases
    bs_week = bs_week,
    bs_fs_marginal = bs_fs_marginal,
    
    # RE (always included)
    use_season_re = TRUE,

    # time-decay training weight
    lambda_w = as.numeric(lambda_w)
  )
  
  spec$best_row <- data.frame(
    delta = spec$delta,
    K = spec$K,
    k_f = spec$k_f,
    alpha_state = spec$alpha_state,
    stringsAsFactors = FALSE
  )
  
  spec$exclude_newseason <- stage2_exclude_newseason(spec)
  spec$formula <- stage2_build_joint_formula(spec)
  spec
}

# internal: terms to exclude for brand-new season prediction
stage2_exclude_newseason <- function(spec) {
  # For a brand-new season (unseen factor level), exclude season-dependent terms.
  # We always fit with a season random intercept b_s, so we always exclude s(season) for new-season prediction.
  ex <- c("s(season)")
  if (isTRUE(spec$k_s > 0L)) ex <- c(ex, "s(newWeek,season_h)")
  ex
}

# internal: formula builder (k_f override supported)
stage2_build_joint_formula <- function(spec, k_f = NULL) {
  if (!is.null(k_f)) spec$k_f <- as.integer(k_f)
  
  # Determine template indicator T (prefer spec$T, else map from legacy template_mode)
  if (!is.null(spec$T)) {
    T <- as.character(spec$T)
  } else {
    tm <- spec$template_mode %||% "smooth"
    T <- switch(tm, smooth = "S", offset = "O", none = "N")
  }
  
  k_f    <- as.integer(spec$k_f %||% 6L)
  k_e <- as.integer(spec$k_e %||% 6L)
  k_n <- as.integer(spec$k_n %||% 6L)
  k_1   <- as.integer(spec$k_1 %||% 6L)
  k_2   <- as.integer(spec$k_2 %||% 6L)
  k_w <- as.integer(spec$k_w %||% 0L)
  k_s   <- as.integer(spec$k_s %||% 0L)
  bs_week <- spec$bs_week %||% "ts"
  bs_fs_marginal <- spec$bs_fs_marginal %||% "tp"
  # mgcv::fs is most stable with tp/cr marginals; treat 'ts' as 'tp'
  if (bs_fs_marginal %in% c("ts", "cs")) bs_fs_marginal <- "tp"
  use_season_re <- TRUE
  
  terms <- c("-1 + lead")
  
  # Template term: T in {S,O,N}
  if (T == "S") {
    terms <- c(terms, sprintf("s(logit_f_eff, by=lead, bs='ts', k=%d)", k_f))
  } else if (T == "O") {
    terms <- c(terms, "offset(logit_f_eff)")
  } else {
    # T == "N": omit template term
  }
  
  # Alignment terms
  if (k_w > 0L) {
    terms <- c(terms, sprintf("s(newWeek, by=lead, bs='%s', k=%d)", bs_week, k_w))
  }
  if (k_s > 0L) {
    terms <- c(terms, sprintf(
      "s(newWeek, season_h, bs='fs', k=%d, xt=list(bs='%s'))",
      k_s, bs_fs_marginal
    ))
  }
  
  # Covariates
  if (k_e > 0L) terms <- c(terms, sprintf("s(z_ema,    by=lead, bs='ts', k=%d)", k_e))
  if (k_n > 0L) terms <- c(terms, sprintf("s(logN_now, by=lead, bs='ts', k=%d)", k_n))
  if (k_1   > 0L) terms <- c(terms, sprintf("s(d1_now,   by=lead, bs='ts', k=%d)", k_1))
  if (k_2   > 0L) terms <- c(terms, sprintf("s(d2_now,   by=lead, bs='ts', k=%d)", k_2))
  
  if (use_season_re) terms <- c(terms, "s(season, bs='re')")
  
  stats::as.formula(paste0("cbind(y_lead, N_lead - y_lead) ~ ", paste(terms, collapse = " + ")))
}

# =========================================================
# Core utilities
# =========================================================

#' Numerically stable logit (internal)
#' @keywords internal
logit_stable <- function(p, eps = 1e-6) {
  p <- pmin(pmax(p, eps), 1 - eps)
  stats::qlogis(p)
}

#' Stage-2 ramp weights (internal)
#' @keywords internal
stage2_ramp_weight <- function(t_since, K = 3L) {
  # K controls ramp length. Convention:
  # - K <= 1 : no ramp (template weight is 1 from ignition onward)
  # - K >  1 : linear ramp from 0 at ignition to 1 after K weeks
  K <- as.integer(K[1])
  if (is.na(K) || K < 1L) stop("K must be >= 1")
  
  t_since <- as.numeric(t_since)
  
  if (K <= 1L) {
    return(ifelse(t_since >= 0, 1, 0))
  }
  
  w <- t_since / K
  pmin(1, pmax(0, w))
}

#' Prospective (real-time safe) derivatives of positivity on the logit scale
#' @export
add_prospective_derivs_link <- function(alignedD,
                                        k = 5L,
                                        eps = 1e-6,
                                        min_obs = 4L) {
  stopifnot(all(c("season","weekF","y","neg") %in% names(alignedD)))
  if (!requireNamespace("dplyr", quietly = TRUE)) stop("Please install dplyr.")
  if (!requireNamespace("purrr", quietly = TRUE)) stop("Please install purrr.")
  
  d <- alignedD %>%
    dplyr::mutate(
      y_w = .data$y / (.data$y + .data$neg),
      z_w = stats::qlogis(pmin(pmax(.data$y_w, eps), 1 - eps))
    ) %>%
    dplyr::arrange(.data$season, .data$weekF)
  
  d %>%
    dplyr::group_by(.data$season) %>%
    dplyr::group_modify(function(.x, .g) {
      ww <- .x$weekF
      zz <- .x$z_w
      n  <- nrow(.x)
      
      d1 <- purrr::map_dbl(seq_len(n), function(i) {
        i0 <- max(1L, i - k + 1L)
        ii <- i0:i
        if (length(ii) < min_obs || anyNA(zz[ii])) return(NA_real_)
        w0 <- ww[i]
        u  <- ww[ii] - w0
        fit <- stats::lm(zz[ii] ~ u + I(u^2))
        unname(stats::coef(fit)[["u"]])
      })
      
      d2 <- purrr::map_dbl(seq_len(n), function(i) {
        i0 <- max(1L, i - k + 1L)
        ii <- i0:i
        if (length(ii) < min_obs || anyNA(zz[ii])) return(NA_real_)
        w0 <- ww[i]
        u  <- ww[ii] - w0
        fit <- stats::lm(zz[ii] ~ u + I(u^2))
        2 * unname(stats::coef(fit)[["I(u^2)"]])
      })
      
      dplyr::mutate(.x, d1_link = d1, d2_link = d2)
    }) %>%
    dplyr::ungroup()
}

# =========================================================
# Stage-2 prep
# =========================================================

#' Prepare Stage-2 joint stacked data using a spec or tuned row
#'
#' @param dat Multi-season data.frame with required cols:
#'   season, weekF, phase, newWeek, y, N, d1_link, d2_link.
#' @param template_df Template curve with columns newWeek and fit.
#' @param best_mean_nll 1-row object with delta, K, k_f, alpha_state.
#' @param use_ramp Logical, passed through.
#' @param leads Integer leads.
#' @param ign_week_df Optional data.frame with season and iWeek_hat.
#' @param pre_buffer Integer.
#' @param alpha_state Numeric in (0,1).
#' @param verbose Logical.
#'
#' @return data.frame stacked across leads with engineered covariates.
#' @export
prep_stage2_joint <- function(dat,
                              best_mean_nll,
                              template_df,
                              use_ramp = TRUE,
                              leads = c(1L, 2L),
                              ign_week_df = NULL,
                              pre_buffer = 0L,
                              alpha_state = 0.30,
                              verbose = FALSE) {
  stopifnot(is.data.frame(dat))
  if (!requireNamespace("dplyr", quietly = TRUE)) stop("Please install dplyr.")
  
  if (is.null(template_df) || !is.data.frame(template_df)) stop("template_df must be provided.")
  if (!all(c("newWeek","fit") %in% names(template_df))) stop("template_df must have columns newWeek, fit")
  template_df <- template_df %>% dplyr::select(.data$newWeek, fit_ref = .data$fit)
  
  need <- c("season","weekF","phase","newWeek","y","N","d1_link","d2_link")
  miss <- setdiff(need, names(dat))
  if (length(miss)) stop("prep_stage2_joint: missing cols: ", paste(miss, collapse = ", "))
  
  pre_buffer <- as.integer(pre_buffer)
  if (is.na(pre_buffer) || pre_buffer < 0L) stop("pre_buffer must be >= 0")
  
  alpha_state <- as.numeric(alpha_state)
  if (!is.finite(alpha_state) || alpha_state <= 0 || alpha_state >= 1) stop("alpha_state must be in (0,1).")
  
  get1 <- function(obj, nm, default = NULL) {
    if (is.list(obj) && !is.data.frame(obj) && !is.null(obj[[nm]])) return(obj[[nm]])
    if (is.data.frame(obj) && nm %in% names(obj)) return(obj[[nm]][1])
    default
  }
  
  delta <- get1(best_mean_nll, "delta", 0L)
  delta <- as.integer(delta)
  K <- get1(best_mean_nll, "K", 3L)
  K <- if (is.na(K)) NA_integer_ else as.integer(K)
  
  # template can be disabled by delta=NA or K=NA
  template_on <- is.finite(delta) && !is.na(delta) && is.finite(K) && !is.na(K)
  
  leads <- as.integer(leads)
  
  # ---- ignition from phase==1 (fallback) ----
  ign_true <- dat %>%
    dplyr::group_by(.data$season) %>%
    dplyr::summarise(
      iWeek_true = suppressWarnings(min(.data$weekF[.data$phase == 1L], na.rm = TRUE)),
      .groups = "drop"
    )
  
  d0 <- dat %>%
    dplyr::left_join(ign_true, by = "season")
  
  # ---- optional override ignition week used ----
  if (!is.null(ign_week_df)) {
    stopifnot(all(c("season","iWeek_hat") %in% names(ign_week_df)))
    ign_week_df <- ign_week_df %>%
      dplyr::transmute(season = as.character(.data$season), iWeek_used = as.numeric(.data$iWeek_hat))
    
    d0 <- d0 %>%
      dplyr::mutate(season = as.character(.data$season)) %>%
      dplyr::left_join(ign_week_df, by = "season") %>%
      dplyr::mutate(iWeek_used = dplyr::coalesce(.data$iWeek_used, .data$iWeek_true))
  } else {
    d0 <- d0 %>% dplyr::mutate(iWeek_used = .data$iWeek_true)
  }
  
  # ---- core covariates ----
  d0 <- d0 %>%
    dplyr::filter(is.finite(.data$iWeek_used)) %>%
    dplyr::arrange(.data$season, .data$weekF) %>%
    dplyr::group_by(.data$season) %>%
    dplyr::mutate(
      post_ign  = (.data$weekF >= (.data$iWeek_used - pre_buffer)),
      logN_now  = log(pmax(.data$N, 1L)),
      p_now     = .data$y / pmax(.data$N, 1L),
      z_now     = logit_stable(.data$p_now),
      z0        = dplyr::coalesce(dplyr::first(.data$z_now[is.finite(.data$z_now)]), 0),
      z_fill    = dplyr::coalesce(.data$z_now, .data$z0),
      z_ema     = as.numeric(stats::filter(alpha_state * .data$z_fill,
                                           filter = 1 - alpha_state,
                                           method = "recursive",
                                           init = .data$z_fill[1])),
      d1_now    = .data$d1_link,
      d2_now    = .data$d2_link,
      t_since   = as.numeric(.data$weekF - .data$iWeek_used)
    ) %>%
    dplyr::ungroup() %>%
    dplyr::select(-.data$z0, -.data$z_fill) %>%
    dplyr::left_join(template_df, by = "newWeek")
  
  # ---- shift template by delta ----
  if (!is.na(delta) && delta != 0L) {
    n <- abs(delta)
    if (delta > 0L) {
      d0 <- d0 %>%
        dplyr::group_by(.data$season) %>%
        dplyr::mutate(fit_shift = dplyr::lead(.data$fit_ref, n = n)) %>%
        dplyr::ungroup()
    } else {
      d0 <- d0 %>%
        dplyr::group_by(.data$season) %>%
        dplyr::mutate(fit_shift = dplyr::lag(.data$fit_ref, n = n)) %>%
        dplyr::ungroup()
    }
  } else {
    d0 <- d0 %>% dplyr::mutate(fit_shift = .data$fit_ref)
  }
  
  # ---- template covariate ----
  K_eff <- if (isTRUE(use_ramp)) as.integer(K) else 1L
  
  # ---- template covariate ----
  d0 <- d0 %>%
    dplyr::mutate(
      # K controls ramping; convention:
      # - K <= 1: no ramp (omega=1 from ignition onward)
      # - K >  1: linear ramp from 0 at ignition to 1 after K weeks
      omega = if (isTRUE(template_on)) stage2_ramp_weight(.data$t_since, K = K_eff) else 0,
      logit_f = if (isTRUE(template_on)) logit_stable(.data$fit_shift) else 0,
      logit_f_eff = .data$omega * .data$logit_f
    ) %>%
    dplyr::filter(is.finite(.data$z_ema), is.finite(.data$logN_now))
  
  out <- lapply(leads, function(h) {
    d0 %>%
      dplyr::group_by(.data$season) %>%
      dplyr::mutate(
        y_lead = dplyr::lead(.data$y, n = h),
        N_lead = dplyr::lead(.data$N, n = h)
      ) %>%
      dplyr::ungroup() %>%
      dplyr::mutate(
        lead = factor(paste0("h", h), levels = paste0("h", sort(unique(leads))))
      ) %>%
      dplyr::filter(!is.na(.data$y_lead), !is.na(.data$N_lead), .data$N_lead > 0)
  })
  
  d <- dplyr::bind_rows(out) %>%
    dplyr::mutate(
      season = factor(.data$season),
      y_lead = as.integer(.data$y_lead),
      N_lead = as.integer(.data$N_lead),
      season_h = interaction(.data$season, .data$lead, drop = TRUE)
    )
  
  if (isTRUE(verbose)) {
    message("[prep_stage2_joint] delta=", delta, " K=", K,
            " pre_buffer=", pre_buffer,
            " use_ramp=", use_ramp,
            " alpha_state=", signif(alpha_state, 3),
            " leads={", paste(leads, collapse=","), "} rows=", nrow(d))
  }
  
  as.data.frame(d)
}

# =========================================================
# Stage-2 training
# =========================================================

# internal: score with optional exclude terms
# lambda_w: time-decay weight rate (0 = uniform). Weights w_i = exp(-lambda_w * t_since_i),
#   normalised to sum to n so that mean_nll is on the same scale regardless of lambda_w.
# eval_window: if non-NULL, restrict evaluation to rows where t_since <= eval_window.
#   This provides a *fixed* objective for comparing different lambda_w values fairly
#   (all lambdas are assessed on the same early-window observations).
score_stage2_metrics <- function(fit,
                                 d_test,
                                 exclude_season_re = TRUE,
                                 exclude_terms = NULL,
                                 lambda_w = 0,
                                 eval_window = NULL) {
  ex <- exclude_terms
  if (is.null(ex)) ex <- if (isTRUE(exclude_season_re)) "s(season)" else NULL

  nd <- d_test

  # lead levels
  if ("lead" %in% names(nd) && "lead" %in% names(fit$model) && is.factor(fit$model$lead)) {
    lev <- levels(fit$model$lead)
    nd$lead <- factor(as.character(nd$lead), levels = lev)
    nd$lead[is.na(nd$lead)] <- lev[1]
  }

  # season levels
  if ("season" %in% names(nd) && "season" %in% names(fit$model) && is.factor(fit$model$season)) {
    lev <- levels(fit$model$season)
    nd$season <- factor(as.character(nd$season), levels = lev)
    nd$season[is.na(nd$season)] <- lev[1]
  }

  # season_h levels (lead-specific season factor for fs term)
  if ("season_h" %in% names(nd) && "season_h" %in% names(fit$model) && is.factor(fit$model$season_h)) {
    lev <- levels(fit$model$season_h)
    nd$season_h <- factor(as.character(nd$season_h), levels = lev)
    nd$season_h[is.na(nd$season_h)] <- lev[1]
  }


  p_hat <- as.numeric(stats::predict(fit, newdata = nd, type = "response", exclude = ex))
  eps <- 1e-12
  p_hat <- pmin(1 - eps, pmax(eps, p_hat))

  ll <- stats::dbinom(nd$y_lead, size = nd$N_lead, prob = p_hat, log = TRUE)

  # restrict to early window for evaluation (fixed objective across lambda_w values)
  eval_mask <- rep(TRUE, length(ll))
  if (!is.null(eval_window) && "t_since" %in% names(nd)) {
    eval_mask <- is.finite(nd$t_since) & nd$t_since <= eval_window
  }
  ll_eval   <- ll[eval_mask]
  nd_eval   <- nd[eval_mask, , drop = FALSE]
  p_hat_eval <- p_hat[eval_mask]

  # time-decay weights on the eval set, normalised so mean_nll is interpretable
  if (lambda_w > 0 && "t_since" %in% names(nd_eval) && any(eval_mask)) {
    raw_w <- exp(-lambda_w * as.numeric(nd_eval$t_since))
    raw_w[!is.finite(raw_w)] <- 0
    w <- raw_w / mean(raw_w[raw_w > 0], na.rm = TRUE)  # normalise so mean(w)=1
  } else {
    w <- rep(1, sum(eval_mask))
  }

  nll      <- -sum(w * ll_eval, na.rm = TRUE)
  mean_nll <- nll / max(sum(eval_mask), 1L)

  p_obs_eval <- nd_eval$y_lead / nd_eval$N_lead
  brier   <- stats::weighted.mean((p_hat_eval - p_obs_eval)^2, w = w, na.rm = TRUE)
  rmse_p  <- sqrt(brier)

  list(nll = nll, mean_nll = mean_nll, brier = brier, rmse_p = rmse_p)
}

# internal
train_stage2_joint_prepped <- function(d_all,
                                       best_mean_nll,
                                       template_df = NULL,
                                       spec = NULL,
                                       # Back-compat (only used when spec is NULL)
                                       k_e = 6L,
                                       k_n = 6L,
                                       k_1 = 6L,
                                       k_2 = 6L,
                                       method = "REML",
                                       lambda_w = 0,
                                       verbose = FALSE) {
  if (!requireNamespace("mgcv", quietly = TRUE)) stop("Please install mgcv.")
  stopifnot(is.data.frame(d_all))
  
  get1 <- function(obj, nm, default = NULL) {
    if (is.list(obj) && !is.data.frame(obj) && !is.null(obj[[nm]])) return(obj[[nm]])
    if (is.data.frame(obj) && nm %in% names(obj)) return(obj[[nm]][1])
    default
  }
  k_f <- as.integer(get1(best_mean_nll, "k_f", 6L))
  
  # DEFAULT: full model (everything on) unless user supplies spec
  if (is.null(spec)) {
    spec <- stage2_make_spec(
      delta = get1(best_mean_nll, "delta", 0L),
      K = get1(best_mean_nll, "K", 3L),
      k_f = k_f,
      alpha_state = get1(best_mean_nll, "alpha_state", 0.30),
      template_mode = "smooth",
      # full terms ON
      k_w = 8L,
      k_s   = 6L,
      k_e = as.integer(k_e),
      k_n = as.integer(k_n),
      k_1   = as.integer(k_1),
      k_2   = as.integer(k_2),
      use_season_re = TRUE
    )
  }
  
  d_train <- d_all[d_all$post_ign, , drop = FALSE]
  if (nrow(d_train) == 0L) stop("train_stage2_joint_prepped: no post-ignition rows.")

  # time-decay training weights: w_i = exp(-lambda_w * t_since_i), normalised.
  # Stored as a column in d_train (.w) so mgcv::bam can find it via data-frame eval.
  if (lambda_w > 0 && "t_since" %in% names(d_train)) {
    raw_w <- exp(-lambda_w * as.numeric(d_train$t_since))
    raw_w[!is.finite(raw_w)] <- 0
    mn <- mean(raw_w[raw_w > 0], na.rm = TRUE)
    d_train$.w <- if (is.finite(mn) && mn > 0) raw_w / mn else rep(1, nrow(d_train))
    use_weights <- TRUE
  } else {
    use_weights <- FALSE
  }

  req <- c("post_ign","lead","y_lead","N_lead")
  if (spec$template_mode != "none") req <- c(req, "logit_f_eff")
  if (spec$k_w > 0L || spec$k_s > 0L) req <- c(req, "newWeek")
  if (spec$use_season_re) req <- c(req, "season")
  if (spec$k_s > 0L) req <- c(req, "season_h")
  if (spec$k_e > 0L) req <- c(req, "z_ema")
  if (spec$k_n > 0L) req <- c(req, "logN_now")
  if (spec$k_1   > 0L) req <- c(req, "d1_now")
  if (spec$k_2   > 0L) req <- c(req, "d2_now")
  
  miss <- setdiff(unique(req), names(d_train))
  if (length(miss)) stop("train_stage2_joint_prepped: missing cols: ", paste(miss, collapse = ", "))
  
  form <- stage2_build_joint_formula(spec, k_f = k_f)
  
  if (isTRUE(verbose)) {
    message("[train_stage2_joint_prepped] rows=", nrow(d_train),
            " | template_mode=", spec$template_mode,
            " | k_f=", k_f,
            " | k_w=", spec$k_w,
            " | k_s=", spec$k_s,
            " | k_2=", spec$k_2)
    message("[train_stage2_joint_prepped] formula: ", deparse(form))
  }
  
  # NOTE: mgcv's discrete=TRUE path can be fragile with factor-smooth interactions (bs='fs').
  # If the fs term is enabled (k_s>0), fall back to discrete=FALSE for stability.
  use_discrete <- isTRUE(spec$k_s <= 0L)
  
  # Pass weights via column in d_train to avoid mgcv NSE scoping issue
  if (isTRUE(use_weights)) {
    fit <- mgcv::bam(
      formula  = form,
      data     = d_train,
      family   = stats::binomial(),
      weights  = .w,
      method   = method,
      discrete = use_discrete,
      nthreads = 1
    )
  } else {
    fit <- mgcv::bam(
      formula  = form,
      data     = d_train,
      family   = stats::binomial(),
      method   = method,
      discrete = use_discrete,
      nthreads = 1
    )
  }

  list(fit = fit, train_data = d_train, tuned = best_mean_nll, spec = spec,
       lambda_w = lambda_w)
}

#' Extract best Stage-2 spec from a tuning result
#'
#' Convenience wrapper: given the list returned by
#' \code{tune_stage2_loso_spec_grid_parallel()}, finds the best row in
#' \code{tuned2$by_spec_grid} and calls \code{stage2_make_spec()} with the
#' appropriate column mappings (\code{Kr} -> \code{K}, \code{Kb} ->
#' \code{pre_buffer}).
#'
#' @param tuned2 List with at least \code{$best} (1-row data frame with
#'   \code{spec_id}) and \code{$by_spec_grid} (full grid with hyperparameters).
#' @return A spec list as returned by \code{stage2_make_spec()}.
#' @export
stage2_spec_from_tuning <- function(tuned2) {
  stopifnot(is.list(tuned2), !is.null(tuned2$best), !is.null(tuned2$by_spec_grid))
  best_id  <- tuned2$best$spec_id[[1L]]
  best_row <- tuned2$by_spec_grid[tuned2$by_spec_grid$spec_id == best_id, , drop = FALSE]
  if (nrow(best_row) == 0L) stop("spec_id '", best_id, "' not found in by_spec_grid")
  stage2_make_spec(
    delta          = best_row$delta,
    K              = best_row$Kr,
    k_f            = best_row$k_f,
    alpha_state    = best_row$alpha_state,
    T              = best_row$T,
    k_e            = best_row$k_e,
    k_n            = best_row$k_n,
    k_1            = best_row$k_1,
    k_2            = best_row$k_2,
    k_w            = best_row$k_w,
    k_s            = best_row$k_s,
    pre_buffer     = best_row$Kb,
    bs_week        = best_row$bs_week,
    bs_fs_marginal = best_row$bs_fs_marginal,
    lambda_w       = if ("lambda_w" %in% names(best_row)) best_row$lambda_w else 0
  )
}

#' Train Stage-2 joint model
#'
#' Preferred usage: pass only \code{spec}. The function will use \code{spec$best_row}
#' to construct features and \code{spec$formula} to fit the model.
#'
#' Backward compatible: if \code{spec=NULL}, you may pass \code{best_mean_nll} and legacy
#' basis sizes (k_e, k_n, k_1, k_2).
#'
#' @param dat Multi-season input data.
#' @param template_df Template curve.
#' @param spec Stage-2 spec created by \code{stage2_make_spec()}.
#' @param best_mean_nll Legacy tuned row (delta,K,k_f,alpha_state) if \code{spec=NULL}.
#' @param ign_week_df Optional ignition week estimates for alignment in held-out/new seasons.
#' @param method mgcv method.
#' @param verbose logical.
#'
#' @export
train_stage2_joint <- function(dat,
                               template_df,
                               spec = NULL,
                               # legacy
                               best_mean_nll = NULL,
                               pre_buffer = NULL,
                               alpha_state = NULL,
                               k_e = 6L,
                               k_n = 6L,
                               k_1 = 6L,
                               k_2 = 6L,
                               ign_week_df = NULL,
                               method = "REML",
                               lambda_w = 0,
                               verbose = TRUE) {
  if (!requireNamespace("mgcv", quietly = TRUE)) stop("Please install mgcv.")
  
  if (!is.null(spec)) {
    if (is.null(best_mean_nll)) best_mean_nll <- spec$best_row
    if (is.null(pre_buffer))  pre_buffer  <- spec$pre_buffer
    if (is.null(alpha_state)) alpha_state <- spec$alpha_state
  }
  if (is.null(best_mean_nll)) stop("Provide either spec=... or best_mean_nll=...")
  
  # If spec is NULL and alpha_state was not provided, try to take it from best_mean_nll
  if (is.null(spec) && is.null(alpha_state)) {
    if (is.data.frame(best_mean_nll) && "alpha_state" %in% names(best_mean_nll)) {
      alpha_state <- best_mean_nll
    } else if (is.list(best_mean_nll) && !is.data.frame(best_mean_nll) && !is.null(best_mean_nll)) {
      alpha_state <- best_mean_nll
    }
  }
  # ramp is controlled by K (K<=1 => no ramp)
  leads    <- if (!is.null(spec)) spec$leads else c(1L, 2L)
  
  d_all <- prep_stage2_joint(
    dat,
    best_mean_nll = best_mean_nll,
    template_df   = template_df,
    leads         = leads,
    ign_week_df   = ign_week_df,
    pre_buffer    = as.integer(pre_buffer %||% 0L),
    alpha_state   = as.numeric(alpha_state %||% 0.30),
    verbose       = FALSE
  )
  
  train_stage2_joint_prepped(
    d_all = d_all,
    best_mean_nll = best_mean_nll,
    template_df = template_df,
    spec = spec,
    k_e = k_e,
    k_n = k_n,
    k_1 = k_1,
    k_2 = k_2,
    method = method,
    lambda_w = lambda_w,
    verbose = verbose
  )
}

# =========================================================
# Stage-2 tuning
# =========================================================

#' Tune a list of Stage-2 specs via LOSO
#'
#' This function evaluates each candidate \code{spec} under leave-one-season-out.
#' For each held-out season, it fits the model on the remaining seasons using
#' \code{train_stage2_joint()}, then scores post-ignition rows on the held-out
#' season using \code{score_stage2_metrics()}.
#'
#' @param dat Multi-season input data.
#' @param template_df Template curve.
#' @param specs Named list of spec objects.
#' @param ign_hat_df Optional ignition week estimates by season (cols season,iWeek_hat).
#' @param testSeason NULL for LOSO across all seasons, else a single season.
#' @param method mgcv method.
#' @param exclude_newseason_terms If TRUE, excludes \code{s(season)} and \code{fs} during scoring.
#' @param num.cores Parallel workers.
#'
#' @return list(results, best_by_season, best_overall)
#' @export
tune_stage2_loso_specs <- function(
    dat,
    template_df,
    specs,
    ign_hat_df = NULL,
    testSeason = NULL,
    method = "REML",
    exclude_newseason_terms = TRUE,
    lambda_w = 0,
    eval_window = NULL,
    num.cores = 8L,
    verbose = TRUE,
    progress_every = 200L
) {
  stopifnot(is.data.frame(dat))
  if (!requireNamespace("dplyr", quietly = TRUE)) stop("Please install dplyr.")
  if (!requireNamespace("parallel", quietly = TRUE)) stop("Please install parallel.")
  
  if (!is.list(specs) || length(specs) == 0L) stop("specs must be a non-empty list.")
  if (is.null(names(specs))) names(specs) <- paste0("spec_", seq_along(specs))
  
  seasons_all <- unique(dat$season)
  test_seasons <- if (is.null(testSeason)) seasons_all else testSeason
  if (!all(test_seasons %in% seasons_all)) stop("Unknown testSeason(s): ", paste(setdiff(test_seasons, seasons_all), collapse = ", "))
  
  tasks <- expand.grid(
    spec_id = names(specs),
    test_season = test_seasons,
    KEEP.OUT.ATTRS = FALSE,
    stringsAsFactors = FALSE
  )
  
  if (verbose) message("[tune_stage2_loso_specs] tasks=", nrow(tasks), " specs=", length(specs), " seasons=", length(test_seasons))
  
  getS <- function(spec, nm, default = NULL) {
    if (!is.null(spec[[nm]])) return(spec[[nm]])
    default
  }
  
  eval_one <- function(task_row) {
    sid <- as.character(task_row$spec_id)
    ts  <- as.character(task_row$test_season)
    spec <- specs[[sid]]
    
    train_dat <- dat[dat$season != ts, , drop = FALSE]
    test_dat  <- dat[dat$season == ts, , drop = FALSE]
    
    spec_lambda_w <- getS(spec, "lambda_w", lambda_w)  # per-spec override or function default

    fit_out <- try(train_stage2_joint(
      dat = train_dat,
      template_df = template_df,
      spec = spec,
      method = method,
      lambda_w = spec_lambda_w,
      verbose = FALSE
    ), silent = TRUE)
    
    if (inherits(fit_out, "try-error")) {
      return(data.frame(ok = FALSE, spec_id = sid, test_season = ts,
                        n_train = NA_integer_, n_test = NA_integer_,
                        nll = NA_real_, mean_nll = NA_real_, brier = NA_real_, rmse_p = NA_real_,
                        err = as.character(fit_out)[1], stringsAsFactors = FALSE))
    }
    
    ign_override <- NULL
    if (!is.null(ign_hat_df)) {
      stopifnot(all(c("season","iWeek_hat") %in% names(ign_hat_df)))
      ign_override <- ign_hat_df[ign_hat_df$season == ts, , drop = FALSE]
      if (nrow(ign_override) == 0L) ign_override <- NULL
    }
    
    d_test_all <- prep_stage2_joint(
      dat = test_dat,
      best_mean_nll = spec$best_row,
      template_df = template_df,
      use_ramp = getS(spec, "use_ramp", TRUE),
      leads = getS(spec, "leads", c(1L, 2L)),
      ign_week_df = ign_override,
      pre_buffer = getS(spec, "pre_buffer", 0L),
      alpha_state = getS(spec, "alpha_state", 0.30),
      verbose = FALSE
    )
    
    d_test <- d_test_all[d_test_all$post_ign, , drop = FALSE]
    d_train_used <- fit_out$train_data
    
    if (nrow(d_train_used) == 0L || nrow(d_test) == 0L) {
      return(data.frame(ok = TRUE, spec_id = sid, test_season = ts,
                        n_train = nrow(d_train_used), n_test = nrow(d_test),
                        nll = NA_real_, mean_nll = NA_real_, brier = NA_real_, rmse_p = NA_real_,
                        err = NA_character_, stringsAsFactors = FALSE))
    }
    
    ex_terms <- NULL
    if (isTRUE(exclude_newseason_terms)) ex_terms <- stage2_exclude_newseason(spec)
    
    sc <- score_stage2_metrics(fit_out$fit, d_test, exclude_season_re = FALSE,
                               exclude_terms = ex_terms,
                               lambda_w = 0,           # eval on uniform weights (fixed objective)
                               eval_window = eval_window)
    
    data.frame(
      ok = TRUE,
      spec_id = sid,
      test_season = ts,
      delta = getS(spec, "delta", NA_integer_),
      K = getS(spec, "K", NA_integer_),
      k_f = getS(spec, "k_f", NA_integer_),
      alpha_state = getS(spec, "alpha_state", NA_real_),
      lambda_w = spec_lambda_w,
      template_mode = getS(spec, "template_mode", NA_character_),
      k_w = getS(spec, "k_w", NA_integer_),
      k_s = getS(spec, "k_s", NA_integer_),
      k_2 = getS(spec, "k_2", NA_integer_),
      n_train = nrow(d_train_used),
      n_test = nrow(d_test),
      nll = sc$nll,
      mean_nll = sc$mean_nll,
      brier = sc$brier,
      rmse_p = sc$rmse_p,
      err = NA_character_,
      stringsAsFactors = FALSE
    )
  }
  
  eval_one_safe <- function(task_row) {
    tryCatch(eval_one(task_row), error = function(e) {
      data.frame(ok = FALSE, spec_id = as.character(task_row$spec_id), test_season = as.character(task_row$test_season),
                 n_train = NA_integer_, n_test = NA_integer_, nll = NA_real_, mean_nll = NA_real_, brier = NA_real_, rmse_p = NA_real_,
                 err = conditionMessage(e), stringsAsFactors = FALSE)
    })
  }
  
  num.cores <- as.integer(num.cores)
  if (is.na(num.cores) || num.cores < 1L) num.cores <- 1L
  
  if (num.cores == 1L) {
    out_list <- vector("list", nrow(tasks))
    for (i in seq_len(nrow(tasks))) {
      if (verbose && (i %% progress_every == 0L)) message("  [progress] ", i, "/", nrow(tasks))
      out_list[[i]] <- eval_one_safe(tasks[i, , drop = FALSE])
    }
  } else {
    idx <- seq_len(nrow(tasks))
    if (!requireNamespace("future", quietly = TRUE) ||
        !requireNamespace("future.apply", quietly = TRUE)) {
      stop("tune_stage2_loso_specs: parallel requires 'future' + 'future.apply'.")
    }
    old_plan <- future::plan()
    on.exit(future::plan(old_plan), add = TRUE)
    strat <- if (.Platform$OS.type == "windows") future::multisession else future::multicore
    future::plan(strat, workers = num.cores)

    # capture everything eval_one_safe needs in a globals list for future
    fg <- list(
      dat = dat, template_df = template_df, specs = specs,
      ign_hat_df = ign_hat_df, method = method,
      lambda_w = lambda_w, eval_window = eval_window,
      tasks = tasks,
      eval_one = eval_one, eval_one_safe = eval_one_safe,
      getS = getS,
      prep_stage2_joint = prep_stage2_joint,
      train_stage2_joint = train_stage2_joint,
      train_stage2_joint_prepped = train_stage2_joint_prepped,
      score_stage2_metrics = score_stage2_metrics,
      stage2_exclude_newseason = stage2_exclude_newseason,
      stage2_build_joint_formula = stage2_build_joint_formula,
      stage2_make_spec = stage2_make_spec,
      logit_stable = logit_stable,
      stage2_ramp_weight = stage2_ramp_weight,
      `%||%` = `%||%`
    )

    out_list <- future.apply::future_lapply(
      idx,
      FUN = function(i) eval_one_safe(tasks[i, , drop = FALSE]),
      future.seed = TRUE,
      future.packages = c("dplyr", "mgcv"),
      future.globals  = fg
    )
  }
  
  results <- as.data.frame(dplyr::bind_rows(out_list), stringsAsFactors = FALSE)
  if (nrow(results) == 0L) stop("tune_stage2_loso_specs: no results returned")
  
  metrics <- c("nll","mean_nll","brier","rmse_p")
  
  best_by_season <- list()
  for (ts in unique(results$test_season)) {
    d_ts <- results[results$test_season == ts & results$ok, , drop = FALSE]
    best_by_season[[ts]] <- lapply(metrics, function(m) {
      d2 <- d_ts[is.finite(d_ts[[m]]), , drop = FALSE]
      if (nrow(d2) == 0L) return(NULL)
      d2[which.min(d2[[m]]), , drop = FALSE]
    })
    names(best_by_season[[ts]]) <- metrics
  }
  
  best_overall <- lapply(metrics, function(m) {
    d2 <- results[results$ok & is.finite(results[[m]]), , drop = FALSE]
    if (nrow(d2) == 0L) return(NULL)
    agg <- stats::aggregate(d2[[m]] ~ spec_id, data = d2, FUN = sum)
    names(agg)[2] <- "sum_metric"
    agg <- agg[order(agg$sum_metric), , drop = FALSE]
    agg[1, , drop = FALSE]
  })
  names(best_overall) <- metrics
  
  list(results = results, best_by_season = best_by_season, best_overall = best_overall)
}

#' Tune Stage-2 over (delta,K,k_f,alpha_state) with a fixed model structure
#'
#' This is a compatibility wrapper that replicates the QMD workflow, but internally
#' it expands a grid of specs and calls \code{tune_stage2_loso_specs()}.
#'
#' If \code{spec_base} is NULL, it uses the **full model** (all terms on) as the default.
#' That means your Stage-2 now includes:
#' \code{s(logit_f_eff)} + \code{s(newWeek)} + \code{fs(newWeek,season_h)} + \code{z_ema, logN_now, d1, d2} + season RE.
#'
#' @param dat Multi-season input data.
#' @param template_df Template curve.
#' @param spec_base A spec that defines model structure (k's, template_mode, etc.).
#' @param shift_grid,K_grid,k_f_grid,alpha_grid Grids to tune.
#' @param ign_hat_df Optional ignition week estimates by season.
#' @param pre_buffer Weeks before ignition included.
#' @param leads Forecast horizons.
#' @param num.cores Parallel workers.
#'
#' @return list(results, best_by_season, best_overall)
#' @export
tune_stage2_loso_shift_template <- function(
    dat,
    template_df,
    spec_base = NULL,
    testSeason = NULL,
    shift_grid = -3:3,
    ign_hat_df = NULL,
    pre_buffer = 1L,
    K_grid = 2:6,
    k_f_grid = c(6L, 8L, 10L),
    alpha_grid = c(0.15, 0.25, 0.35, 0.50),
    leads = c(1L, 2L),
    lambda_w_grid = 0,
    eval_window = NULL,
    num.cores = 8L,
    verbose = TRUE
) {
  if (!requireNamespace("dplyr", quietly = TRUE)) stop("Please install dplyr.")

  # Base spec defines *structure* (k's, T, bases) while the grid tunes (delta, K, k_f, alpha_state).
  if (is.null(spec_base)) {
    spec_base <- stage2_make_spec(
      delta = 0L, K = 3L, k_f = 6L, alpha_state = 0.30,
      pre_buffer = as.integer(pre_buffer),
      leads = as.integer(leads),
      T = "S",
      k_w = 8L, k_s = 6L, k_e = 6L, k_n = 6L, k_1 = 6L, k_2 = 6L
    )
  } else {
    spec_base$pre_buffer <- as.integer(pre_buffer)
    spec_base$leads <- as.integer(leads)
  }

  shift_grid    <- as.integer(shift_grid)
  K_grid        <- as.integer(K_grid)
  k_f_grid      <- as.integer(k_f_grid)
  alpha_grid    <- as.numeric(alpha_grid)
  lambda_w_grid <- as.numeric(lambda_w_grid)

  grid <- expand.grid(
    delta       = shift_grid,
    K           = K_grid,
    k_f         = k_f_grid,
    alpha_state = alpha_grid,
    lambda_w    = lambda_w_grid,
    KEEP.OUT.ATTRS = FALSE,
    stringsAsFactors = FALSE
  )

  # Build a list of specs (one per hyperparam combination)
  specs <- vector("list", nrow(grid))
  nm <- character(nrow(grid))
  for (i in seq_len(nrow(grid))) {
    g <- grid[i, ]
    s <- spec_base
    s$delta       <- as.integer(g$delta)
    s$K           <- as.integer(g$K)
    s$k_f         <- as.integer(g$k_f)
    s$alpha_state <- as.numeric(g$alpha_state)
    s$lambda_w    <- as.numeric(g$lambda_w)
    s$best_row    <- data.frame(delta = s$delta, K = s$K, k_f = s$k_f, alpha_state = s$alpha_state,
                                stringsAsFactors = FALSE)
    s$formula          <- stage2_build_joint_formula(s)
    s$exclude_newseason <- stage2_exclude_newseason(s)

    nm[i] <- paste0("d", s$delta, "_K", s$K, "_kf", s$k_f,
                    "_a", formatC(s$alpha_state, digits = 2, format = "f"),
                    "_lw", formatC(s$lambda_w,    digits = 3, format = "f"))
    specs[[i]] <- s
  }
  names(specs) <- nm
  
  tuned <- tune_stage2_loso_specs(
    dat = dat,
    template_df = template_df,
    specs = specs,
    ign_hat_df = ign_hat_df,
    testSeason = testSeason,
    method = "REML",
    exclude_newseason_terms = TRUE,
    lambda_w = 0,          # per-spec lambda_w is read from spec$lambda_w inside eval_one
    eval_window = eval_window,
    num.cores = num.cores,
    verbose = verbose
  )
  
  # Return a legacy-friendly object:
  # - results has delta/K/k_f/alpha_state + metrics for each held-out season
  # - best_by_season / best_overall already computed inside tune_stage2_loso_specs
  tuned$results <- dplyr::select(
    tuned$results,
    .data$ok, .data$test_season, .data$spec_id,
    .data$delta, .data$K, .data$k_f, .data$alpha_state, .data$lambda_w,
    .data$n_train, .data$n_test,
    .data$nll, .data$mean_nll, .data$brier, .data$rmse_p,
    .data$err
  )
  
  tuned
}

# =========================================================
# Plot helper used in QMD

# =========================================================

plot_tune_stage2_heatmap <- function(df,
                                     metric = "mean_nll",
                                     agg = TRUE,
                                     test_season = NULL,
                                     base_size = 10,
                                     normalize01 = TRUE,
                                     norm_scope = c("facet", "global"),
                                     center = c("none", "facet_min", "global_min"),
                                     score_transform = c("none", "log", "log1p", "sqrt"),
                                     eps = 1e-9,
                                     star_best = TRUE,
                                     low = "red",
                                     high = "blue") {
  norm_scope <- match.arg(norm_scope)
  center <- match.arg(center)
  score_transform <- match.arg(score_transform)

  # Accept full tuned2 list: auto-extract by_spec_grid
  if (is.list(df) && !is.data.frame(df) && !is.null(df$by_spec_grid))
    df <- df$by_spec_grid

  stopifnot(is.data.frame(df), metric %in% names(df))
  if (!requireNamespace("dplyr", quietly = TRUE)) stop("Please install dplyr.")
  if (!requireNamespace("ggplot2", quietly = TRUE)) stop("Please install ggplot2.")
  if (!requireNamespace("scales", quietly = TRUE)) stop("Please install scales.")

  # Normalize column names: Kr -> K (new tuning output structure)
  if ("Kr" %in% names(df) && !"K" %in% names(df))
    df <- dplyr::rename(df, K = Kr)
  # Normalize season column: season_out -> test_season
  if ("season_out" %in% names(df) && !"test_season" %in% names(df))
    df <- dplyr::rename(df, test_season = season_out)
  # If already aggregated (no test_season col) and agg=TRUE, add dummy season
  if (!"test_season" %in% names(df) && isTRUE(agg))
    df$test_season <- "pooled"

  need <- c("test_season", "delta", "K", "k_f", "alpha_state", metric)
  miss <- setdiff(need, names(df))
  if (length(miss)) stop("Missing cols: ", paste(miss, collapse = ", "))
  
  d <- df %>%
    dplyr::transmute(
      test_season = as.factor(.data$test_season),
      delta       = as.integer(.data$delta),
      K           = as.integer(.data$K),
      k_f         = as.integer(.data$k_f),
      alpha_state = as.numeric(.data$alpha_state),
      val_raw     = .data[[metric]]
    )
  
  if (!is.null(test_season)) d <- d %>% dplyr::filter(.data$test_season %in% test_season)
  
  if (isTRUE(agg)) {
    d <- d %>%
      dplyr::group_by(.data$delta, .data$K, .data$k_f, .data$alpha_state) %>%
      dplyr::summarise(val_raw = mean(.data$val_raw, na.rm = TRUE), n_folds = dplyr::n(), .groups = "drop")
  }
  
  d <- d %>% dplyr::mutate(val = .data$val_raw)
  
  if (center == "facet_min") {
    grp <- if (isTRUE(agg)) c("k_f", "alpha_state") else c("test_season", "k_f", "alpha_state")
    d <- d %>%
      dplyr::group_by(dplyr::across(dplyr::all_of(grp))) %>%
      dplyr::mutate(val = .data$val - min(.data$val, na.rm = TRUE)) %>%
      dplyr::ungroup()
  } else if (center == "global_min") {
    d <- d %>% dplyr::mutate(val = .data$val - min(.data$val, na.rm = TRUE))
  }
  
  if (score_transform == "log") {
    d <- d %>% dplyr::mutate(val = log(pmax(.data$val, eps)))
  } else if (score_transform == "log1p") {
    d <- d %>% dplyr::mutate(val = log1p(pmax(.data$val, 0)))
  } else if (score_transform == "sqrt") {
    d <- d %>% dplyr::mutate(val = sqrt(pmax(.data$val, 0)))
  }
  
  best_row <- NULL
  if (isTRUE(star_best)) {
    best_row <- d %>%
      dplyr::filter(is.finite(.data$val_raw)) %>%
      dplyr::slice_min(.data$val_raw, n = 1, with_ties = FALSE)
  }
  
  if (isTRUE(normalize01)) {
    if (norm_scope == "facet") {
      grp <- if (isTRUE(agg)) c("k_f", "alpha_state") else c("test_season", "k_f", "alpha_state")
      d <- d %>%
        dplyr::group_by(dplyr::across(dplyr::all_of(grp))) %>%
        dplyr::mutate(val01 = scales::rescale(.data$val, to = c(0, 1), na.rm = TRUE)) %>%
        dplyr::ungroup()
    } else {
      d <- d %>% dplyr::mutate(val01 = scales::rescale(.data$val, to = c(0, 1), na.rm = TRUE))
    }
    fill_col <- "val01"
    fill_lab <- paste0(metric,
                       if (center != "none") " (regret)" else "",
                       if (score_transform != "none") paste0(" + ", score_transform) else "",
                       if (norm_scope == "facet") " (norm facet)" else " (norm global)")
  } else {
    fill_col <- "val"
    fill_lab <- paste0(metric,
                       if (center != "none") " (regret)" else "",
                       if (score_transform != "none") paste0(" + ", score_transform) else "")
  }
  
  ggplot2::ggplot(d, ggplot2::aes(x = .data$delta, y = .data$K)) +
    ggplot2::geom_tile(ggplot2::aes(fill = .data[[fill_col]]), linewidth = 0) +
    ggplot2::facet_grid(
      rows = ggplot2::vars(.data$alpha_state),
      cols = ggplot2::vars(.data$k_f),
      labeller = ggplot2::label_both
    ) +
    ggplot2::scale_x_continuous(breaks = sort(unique(d$delta))) +
    ggplot2::scale_y_continuous(breaks = sort(unique(d$K))) +
    ggplot2::scale_fill_gradient(low = low, high = high, name = fill_lab) +
    ggplot2::labs(x = "delta (shift)", y = "K (ramp)", title = if (agg) "Stage-2 tuning (mean across test_season)" else "Stage-2 tuning") +
    ggplot2::labs(fill = NULL) +
    ggplot2::guides(fill = ggplot2::guide_colorbar(title = NULL)) +
    ggplot2::theme_minimal(base_size = base_size) +
    ggplot2::theme(panel.grid = ggplot2::element_blank()) +
    (if (isTRUE(star_best) && !is.null(best_row) && nrow(best_row) == 1)
      ggplot2::geom_point(data = best_row,
                          ggplot2::aes(x = .data$delta, y = .data$K),
                          inherit.aes = FALSE,
                          shape = 8, size = 3.2, stroke = 1)
     else NULL)
}

# =========================================================
# Training-fit plotting helper (kept compatible with QMD)
# =========================================================

plot_stage2_joint_fit_by_season <- function(joint_out,
                                            dat_raw,
                                            ign_hat_df = NULL,
                                            exclude_season_re = FALSE,
                                            pre_buffer = 0L,
                                            facet_by_lead = TRUE,
                                            template_df = NULL) {
  stopifnot(is.list(joint_out), !is.null(joint_out$fit), !is.null(joint_out$tuned))
  stopifnot(is.data.frame(dat_raw))
  if (!requireNamespace("dplyr", quietly = TRUE)) stop("Please install dplyr.")
  if (!requireNamespace("ggplot2", quietly = TRUE)) stop("Please install ggplot2.")
  
  if (is.null(template_df)) {
    if (exists("template_df", inherits = TRUE)) template_df <- get("template_df", inherits = TRUE)
  }
  if (is.null(template_df)) stop("plot_stage2_joint_fit_by_season: please pass template_df (fit curve) explicitly")
  
  d_all <- prep_stage2_joint(
    dat_raw,
    template_df = template_df,
    best_mean_nll = joint_out$tuned,
    ign_week_df = ign_hat_df,
    pre_buffer = pre_buffer,
    alpha_state = (joint_out$tuned$alpha_state %||% 0.30)
  )
  
  d_all <- d_all %>% dplyr::mutate(p_obs = .data$y_lead / .data$N_lead)
  
  d_fit <- d_all[d_all$post_ign, , drop = FALSE]
  ex <- if (isTRUE(exclude_season_re)) "s(season)" else NULL
  d_fit$p_hat <- as.numeric(stats::predict(joint_out$fit, newdata = d_fit, type = "response", exclude = ex))
  
  ign_true <- dat_raw %>%
    dplyr::group_by(.data$season) %>%
    dplyr::summarise(
      iWeek_true = suppressWarnings(min(.data$weekF[.data$phase == 1L], na.rm = TRUE)),
      .groups = "drop"
    )
  
  if (!is.null(ign_hat_df)) {
    stopifnot(all(c("season","iWeek_hat") %in% names(ign_hat_df)))
    ign_hat_df <- ign_hat_df %>%
      dplyr::transmute(season = as.character(.data$season), iWeek_hat = as.numeric(.data$iWeek_hat))
  }
  
  p <- ggplot2::ggplot(d_all, ggplot2::aes(x = .data$weekF)) +
    ggplot2::geom_point(ggplot2::aes(y = .data$p_obs, alpha = .data$post_ign), colour = "black", size = 1.05) +
    ggplot2::scale_alpha_manual(values = c(`FALSE` = 0.25, `TRUE` = 0.85), guide = "none") +
    ggplot2::geom_line(data = d_fit,
                       ggplot2::aes(y = .data$p_hat, group = interaction(.data$season, .data$lead)),
                       colour = "red", linewidth = 0.9) +
    ggplot2::geom_vline(data = ign_true, ggplot2::aes(xintercept = .data$iWeek_true), linewidth = 0.6) +
    ggplot2::labs(x = "weekF", y = "Lead positivity",
                  title = "Stage-2 fitted vs observed by season (post-ignition fit only)") +
    ggplot2::theme_bw()
  
  if (!is.null(ign_hat_df)) {
    p <- p + ggplot2::geom_vline(data = ign_hat_df, ggplot2::aes(xintercept = .data$iWeek_hat),
                                 linetype = "dashed", linewidth = 0.6)
  }
  
  if (isTRUE(facet_by_lead)) {
    p + ggplot2::facet_grid(lead ~ season, scales = "free_y")
  } else {
    p + ggplot2::facet_wrap(~ season, scales = "free_y")
  }
}


expand_grid_specs <- function(
    # --- grids you want to tune ---
  delta_grid = -3:3,
  K_grid     = 1:6,
  T_grid     = c("O","S"),     # "O" offset, "S" smooth, "N" none (optional)
  
  k_f_grid   = c(6L, 8L, 10L), # only used when T == "S"
  
  # --- fixed (your request) ---
  alpha_state = 0.20,
  k_2 = 0L,
  
  # --- other fixed defaults (can override) ---
  pre_buffer = 1L,
  leads      = c(1L, 2L),
  
  k_w = 8L,
  k_s = 0L,
  k_e = 6L,
  k_n = 6L,
  k_1 = 6L,
  
  bs_week        = "ts",
  bs_fs_marginal = "ts",
  
  # optional: include T="N" in T_grid if you want template off
  drop_unused_kf_for_offset = TRUE,
  verbose = TRUE
) {
  if (!exists("stage2_make_spec", mode = "function")) {
    stop("expand_grid_specs() expects stage2_make_spec() to be defined (source your prospective_training file first).")
  }
  if (!requireNamespace("dplyr", quietly = TRUE)) stop("Please install dplyr.")
  if (!requireNamespace("tidyr", quietly = TRUE)) stop("Please install tidyr.")
  if (!requireNamespace("purrr", quietly = TRUE)) stop("Please install purrr.")
  
  # coerce types
  delta_grid <- as.integer(delta_grid)
  K_grid     <- as.integer(K_grid)
  T_grid     <- as.character(T_grid)
  k_f_grid   <- as.integer(k_f_grid)
  
  alpha_state <- as.numeric(alpha_state)
  if (!is.finite(alpha_state) || alpha_state <= 0 || alpha_state >= 1)
    stop("alpha_state must be in (0,1).")
  
  # --- build grid: k_f only matters for T="S" ---
  grid_O <- tidyr::crossing(delta = delta_grid, K = K_grid, T = T_grid[T_grid != "S"]) %>%
    dplyr::mutate(k_f = if (drop_unused_kf_for_offset) NA_integer_ else k_f_grid[1])
  
  grid_S <- tidyr::crossing(delta = delta_grid, K = K_grid, T = "S", k_f = k_f_grid)
  
  grid <- dplyr::bind_rows(grid_O, grid_S) %>%
    dplyr::arrange(.data$T, .data$delta, .data$K, dplyr::coalesce(.data$k_f, 0L)) %>%
    dplyr::mutate(
      # stable name that won’t collide
      spec_id = dplyr::if_else(
        .data$T == "S",
        sprintf("T%s_d%+d_K%d_kf%d", .data$T, .data$delta, .data$K, .data$k_f),
        sprintf("T%s_d%+d_K%d", .data$T, .data$delta, .data$K)
      )
    )
  
  # --- build specs ---
  specs <- purrr::pmap(
    list(grid$delta, grid$K, grid$T, grid$k_f),
    function(delta, K, T, k_f) {
      # for non-smooth template, k_f is irrelevant; pass a safe default
      if (is.na(k_f)) k_f <- k_f_grid[1]
      
      stage2_make_spec(
        delta = delta,
        K = K,
        k_f = k_f,
        alpha_state = alpha_state,
        pre_buffer = pre_buffer,
        leads = leads,
        
        T = T,
        
        k_w = k_w,
        k_s = k_s,
        
        k_e = k_e,
        k_n = k_n,
        k_1 = k_1,
        k_2 = k_2,
        
        bs_week = bs_week,
        bs_fs_marginal = bs_fs_marginal
      )
    }
  )
  names(specs) <- grid$spec_id
  
  if (isTRUE(verbose)) {
    message("[expand_grid_specs] specs=", length(specs),
            " | delta=", length(delta_grid),
            " K=", length(K_grid),
            " T=", paste(unique(T_grid), collapse = ","),
            " k_f=", length(k_f_grid), " (only when T='S')",
            " | alpha_state=", alpha_state,
            " | fixed: k_2=", k_2, " k_w=", k_w, " k_s=", k_s,
            " k_e=", k_e, " k_n=", k_n, " k_1=", k_1,
            " pre_buffer=", pre_buffer,
            " leads={", paste(leads, collapse=","), "}"
    )
  }
  
  list(specs = specs, grid = grid, n = nrow(grid))
}



# Module-level helper used by apply_calibration and train_calib_platt
.clamp01 <- function(p, eps = 1e-6) pmin(pmax(p, eps), 1 - eps)


#' Build calibration training data from a fitted Stage-2 model
#'
#' Generates in-sample predictions from a fitted Stage-2 GAM and pairs them
#' with observed outcomes, producing the input table required by
#' \code{\link{train_calib_platt}}. For unbiased out-of-sample calibration
#' training data use \code{\link{make_calib_train_loso}} instead.
#'
#' @param joint_out List. Output of \code{train_stage2_joint()}, containing
#'   \code{$fit} (the fitted model) and \code{$train_data} (training data).
#'   If provided, \code{fit_stage2} and \code{d_joint} are extracted from it
#'   automatically.
#' @param fit_stage2 A fitted \code{mgcv} model object. Ignored when
#'   \code{joint_out} is supplied.
#' @param d_joint data.frame or data.table. Training data to predict on.
#'   Must contain columns named by \code{lead_col}, \code{y_col}, and
#'   \code{N_col}. Ignored when \code{joint_out} is supplied.
#' @param y_col Character. Name of the column containing observed positives.
#'   Default \code{"y_lead"}.
#' @param N_col Character. Name of the column containing trial counts.
#'   Default \code{"N_lead"}.
#' @param lead_col Character. Name of the forecast lead column.
#'   Default \code{"lead"}.
#' @param exclude_terms Character vector or \code{NULL}. Smooth terms to exclude
#'   when computing predictions (passed to \code{mgcv::predict.bam} via
#'   \code{exclude}). Useful for dropping season-specific effects.
#' @param eps Numeric. Probability clamping bound; predictions are clipped to
#'   \code{[eps, 1 - eps]}. Default \code{1e-6}.
#'
#' @return A \code{data.table} with columns \code{lead}, \code{y}, \code{N},
#'   and \code{p_hat} (clamped model predictions).
#'
#' @examples
#' \dontrun{
#' d_calib <- make_calib_train(joint_out = joint_out)
#' }
make_calib_train <- function(joint_out = NULL,
                             fit_stage2 = NULL,
                             d_joint = NULL,
                             y_col = "y_lead",
                             N_col = "N_lead",
                             lead_col = "lead",
                             exclude_terms = NULL,
                             eps = 1e-6) {
  if (!requireNamespace("data.table", quietly = TRUE)) stop("Need 'data.table'.")

  clamp01 <- function(p, eps = 1e-6) pmin(pmax(p, eps), 1 - eps)

  if (!is.null(joint_out)) {
    if (is.null(fit_stage2)) fit_stage2 <- joint_out$fit
    if (is.null(d_joint))    d_joint    <- joint_out$train_data
  }

  if (is.null(fit_stage2)) stop("Need either joint_out$fit or fit_stage2.")
  if (is.null(d_joint))    stop("Need either joint_out$train_data or d_joint.")

  d <- data.table::as.data.table(d_joint)

  need <- c(lead_col, y_col, N_col)
  miss <- setdiff(need, names(d))
  if (length(miss)) stop("d_joint is missing columns: ", paste(miss, collapse = ", "))

  p_hat <- stats::predict(fit_stage2, newdata = d_joint, type = "response",
                          exclude = exclude_terms)
  d[, p_hat := clamp01(p_hat, eps)]

  d[, .(
    lead  = get(lead_col),
    y     = get(y_col),
    N     = get(N_col),
    p_hat = p_hat
  )]
}


#' Train a per-lead Platt calibration map
#'
#' Fits a logistic regression of observed outcomes on the logit of raw model
#' predictions separately for each forecast lead, yielding intercept \eqn{a_h}
#' and slope \eqn{b_h} parameters that define the Platt scaling map
#' \deqn{\mathrm{logit}(\pi^{\mathrm{cal}}) = a_h + b_h \, \mathrm{logit}(\hat\pi).}
#' For well-calibrated out-of-sample parameters, supply data produced by
#' \code{\link{make_calib_train_loso}}.
#'
#' @param d_calib data.frame or data.table with columns \code{lead}, \code{y}
#'   (observed positives), \code{N} (trials), and \code{p_hat} (raw model
#'   predictions). Typically the output of \code{\link{make_calib_train}} or
#'   \code{\link{make_calib_train_loso}}.
#' @param eps Numeric. Probability clamping bound applied to \code{p_hat} before
#'   computing logits. Default \code{1e-6}.
#'
#' @return A named list with elements:
#'   \describe{
#'     \item{\code{a}}{Named numeric vector of intercepts, one per lead.}
#'     \item{\code{b}}{Named numeric vector of slopes, one per lead.}
#'     \item{\code{eps}}{The clamping bound used (passed through to
#'       \code{\link{apply_calibration}}).}
#'     \item{\code{meta}}{data.table of per-lead \code{a} and \code{b} values.}
#'   }
#'
#' @examples
#' \dontrun{
#' d_oos  <- make_calib_train_loso(joint_out)
#' cal    <- train_calib_platt(d_oos)
#' }
train_calib_platt <- function(d_calib, eps = 1e-6, lambda_w = 0) {
  d <- data.table::as.data.table(data.table::copy(d_calib))
  stopifnot(all(c("lead", "y", "N", "p_hat") %in% names(d)))
  d[, p_hat := .clamp01(p_hat, eps)]
  d[, logit_p_hat := stats::qlogis(p_hat)]

  # time-decay weights: w_i = exp(-lambda_w * t_since_i), normalised per lead
  has_tsince <- "t_since" %in% names(d) && lambda_w > 0
  if (has_tsince) {
    d[, .w := {
      raw_w <- exp(-lambda_w * as.numeric(t_since))
      raw_w[!is.finite(raw_w)] <- 0
      mn <- mean(raw_w[raw_w > 0], na.rm = TRUE)
      if (is.finite(mn) && mn > 0) raw_w / mn else rep(1, .N)
    }, by = lead]
  } else {
    if (lambda_w > 0 && !has_tsince) {
      message("[train_calib_platt] lambda_w>0 but 't_since' not in d_calib; using uniform weights.")
    }
    d[, .w := 1]
  }

  coefs <- d[, {
    g <- stats::glm(cbind(y, N - y) ~ 1 + logit_p_hat,
                    family = stats::binomial(), data = .SD, weights = .w)
    cf <- stats::coef(g)
    list(a = unname(cf[1]), b = unname(cf[2]))
  }, by = lead]

  list(
    a        = stats::setNames(coefs$a, coefs$lead),
    b        = stats::setNames(coefs$b, coefs$lead),
    eps      = eps,
    lambda_w = lambda_w,
    meta     = coefs
  )
}


#' Apply a Platt calibration map to a prediction table
#'
#' Transforms raw model probabilities \code{p_hat} to calibrated probabilities
#' \code{p_cal} using the per-lead Platt scaling parameters produced by
#' \code{\link{train_calib_platt}}.
#'
#' @param d_pred data.frame or data.table containing at minimum the columns
#'   named by \code{lead_col} and \code{p_col}.
#' @param cal List. Calibration object returned by \code{\link{train_calib_platt}},
#'   containing named vectors \code{$a} and \code{$b} (keyed by lead) and
#'   \code{$eps}.
#' @param p_col Character. Name of the column holding raw predicted probabilities.
#'   Default \code{"p_hat"}.
#' @param lead_col Character. Name of the lead column used to look up
#'   \code{cal$a} and \code{cal$b}. Default \code{"lead"}.
#'
#' @return A copy of \code{d_pred} (as a \code{data.table}) with a new column
#'   \code{p_cal} containing calibrated probabilities.
#'
#' @examples
#' \dontrun{
#' d_forecast_cal <- apply_calibration(d_forecast, cal = cal_off)
#' }
apply_calibration <- function(d_pred, cal, p_col = "p_hat", lead_col = "lead") {
  d <- data.table::as.data.table(data.table::copy(d_pred))
  stopifnot(all(c(lead_col, p_col) %in% names(d)))

  p  <- .clamp01(d[[p_col]], cal$eps)
  lp <- stats::qlogis(p)

  a <- cal$a[as.character(d[[lead_col]])]
  b <- cal$b[as.character(d[[lead_col]])]

  d[, p_cal := stats::plogis(as.numeric(a) + as.numeric(b) * lp)]
  d[]
}


#' Plot observed, fitted, and calibrated probabilities by season and lead
#'
#' Produces a faceted ggplot2 figure (one panel per season x lead combination)
#' overlaying observed rates (grey points), Stage-2 fitted probabilities (green
#' line), and optionally Platt-calibrated probabilities (red line). Useful for
#' visually diagnosing calibration quality on training data.
#'
#' @param joint_out List. Output of \code{train_stage2_joint()}. If provided,
#'   \code{fit_stage2} and \code{d_joint} are extracted from it automatically.
#' @param fit_stage2 A fitted \code{mgcv} model object. Ignored when
#'   \code{joint_out} is supplied.
#' @param d_joint data.frame or data.table. Training data. Ignored when
#'   \code{joint_out} is supplied.
#' @param cal List or \code{NULL}. Calibration object from
#'   \code{\link{train_calib_platt}}. If \code{NULL}, the calibrated line is
#'   omitted.
#' @param season_col Character. Name of the season column. Default
#'   \code{"season"}.
#' @param lead_col Character. Name of the lead column. Default \code{"lead"}.
#' @param y_col Character. Name of the observed-positives column. Default
#'   \code{"y_lead"}.
#' @param N_col Character. Name of the trials column. Default \code{"N_lead"}.
#' @param time_col Character or \code{NULL}. Name of the time axis column.
#'   Auto-detected from \code{c("newWeek", "weekF", "week")} if \code{NULL}.
#' @param exclude_terms Character vector or \code{NULL}. Smooth terms to exclude
#'   during prediction (e.g., season-specific effects).
#' @param eps Numeric. Probability clamping bound. Default \code{1e-6}.
#' @param ncol Integer. Number of facet columns. Default \code{4}.
#' @param interactive Logical. If \code{TRUE}, returns a \code{plotly}
#'   interactive figure; requires the \pkg{plotly} package. Default
#'   \code{FALSE}.
#' @param ymax Numeric. Upper y-axis limit (clipped to \code{[0, 1]}).
#'   Default \code{0.5}.
#'
#' @return A \code{ggplot} object, or a \code{plotly} widget when
#'   \code{interactive = TRUE}.
#'
#' @examples
#' \dontrun{
#' plot_fit_obs_cal_by_season(joint_out = joint_out, cal = cal_off)
#' plot_fit_obs_cal_by_season(joint_out = joint_out, cal = cal_off,
#'                            interactive = TRUE, ymax = 0.3)
#' }
plot_fit_obs_cal_by_season <- function(joint_out = NULL,
                                       fit_stage2 = NULL,
                                       d_joint = NULL,
                                       cal = NULL,
                                       season_col = "season",
                                       lead_col   = "lead",
                                       y_col      = "y_lead",
                                       N_col      = "N_lead",
                                       time_col   = NULL,
                                       exclude_terms = NULL,
                                       eps = 1e-6,
                                       ncol = 4,
                                       interactive = FALSE,
                                       ymax = 0.5) {
  if (!requireNamespace("data.table", quietly = TRUE)) stop("Need 'data.table'.")
  if (!requireNamespace("ggplot2", quietly = TRUE)) stop("Need 'ggplot2'.")

  `%||%` <- function(x, y) if (!is.null(x)) x else y
  clamp01 <- function(p, eps = 1e-6) pmin(pmax(p, eps), 1 - eps)

  if (!is.null(joint_out)) {
    fit_stage2 <- fit_stage2 %||% joint_out$fit
    d_joint    <- d_joint    %||% joint_out$train_data
  }
  if (is.null(fit_stage2)) stop("Need joint_out$fit or fit_stage2.")
  if (is.null(d_joint))    stop("Need joint_out$train_data or d_joint.")

  d <- data.table::as.data.table(d_joint)

  need <- c(season_col, lead_col, y_col, N_col)
  miss <- setdiff(need, names(d))
  if (length(miss)) stop("d_joint is missing columns: ", paste(miss, collapse = ", "))

  if (is.null(time_col)) {
    time_col <- c("newWeek", "weekF", "week")[c("newWeek", "weekF", "week") %in% names(d)][1]
    if (is.na(time_col)) stop("Provide time_col (e.g., 'newWeek' or 'weekF').")
  }
  if (!time_col %in% names(d)) stop("time_col not found in d_joint: ", time_col)

  p_hat <- stats::predict(fit_stage2, newdata = d_joint, type = "response",
                          exclude = exclude_terms)
  d[, p_hat := clamp01(p_hat, eps)]

  d[, p_obs := data.table::fifelse(get(N_col) > 0, get(y_col) / get(N_col), NA_real_)]

  if (!is.null(cal)) {
    if (is.null(cal$a) || is.null(cal$b)) stop("cal must have named vectors cal$a and cal$b by lead.")
    lp <- stats::qlogis(d$p_hat)
    a  <- cal$a[as.character(d[[lead_col]])]
    b  <- cal$b[as.character(d[[lead_col]])]
    d[, p_cal := stats::plogis(as.numeric(a) + as.numeric(b) * lp)]
  } else {
    d[, p_cal := NA_real_]
  }

  d[, panel := sprintf("%s | %s=%s",
                       as.character(get(season_col)), lead_col,
                       as.character(get(lead_col)))]

  dt_obs  <- d[, .(panel, t = get(time_col), series = "Observed",   p = p_obs)]
  dt_fit  <- d[, .(panel, t = get(time_col), series = "Fitted",     p = p_hat)]
  dt_cal  <- d[!is.na(p_cal), .(panel, t = get(time_col), series = "Calibrated", p = p_cal)]

  dt_long <- data.table::rbindlist(list(dt_obs, dt_fit, dt_cal), use.names = TRUE)
  dt_long[, series := factor(series, levels = c("Observed", "Fitted", "Calibrated"))]
  data.table::setorder(dt_long, panel, t, series)

  dt_lines <- dt_long[series %in% c("Fitted", "Calibrated")]
  dt_pts   <- dt_long[series == "Observed"]

  ymax <- as.numeric(ymax)
  if (!is.finite(ymax) || ymax <= 0) ymax <- 0.5
  ymax <- min(1, ymax)

  g <- ggplot2::ggplot() +
    ggplot2::geom_point(
      data = dt_pts,
      ggplot2::aes(x = t, y = p),
      color = "grey60", alpha = 0.45, size = 0.9
    ) +
    ggplot2::geom_line(
      data = dt_lines[series == "Fitted"],
      ggplot2::aes(x = t, y = p),
      color = "green4", linewidth = 1.6
    ) +
    ggplot2::geom_line(
      data = dt_lines[series == "Calibrated"],
      ggplot2::aes(x = t, y = p),
      color = "red3", linewidth = 0.85
    ) +
    ggplot2::facet_wrap(~panel, scales = "free_x", ncol = ncol) +
    ggplot2::scale_y_continuous(limits = c(0, ymax)) +
    ggplot2::labs(
      x     = time_col,
      y     = "Observed rate / probability",
      title = "Training data: Observed (grey) vs fitted (green) vs calibrated (red)"
    ) +
    ggplot2::theme_bw(base_size = 11) +
    ggplot2::theme(
      legend.position = "none",
      strip.text      = ggplot2::element_text(size = 9),
      axis.text.x     = ggplot2::element_text(angle = 90, vjust = 0.5, hjust = 1)
    )

  if (!interactive) return(g)

  if (!requireNamespace("plotly", quietly = TRUE)) stop("Need 'plotly' for interactive=TRUE.")
  plotly::ggplotly(g)
}


#' Build an out-of-sample calibration dataset via leave-one-season-out (LOSO)
#'
#' For each season, refits the Stage-2 model on all other seasons and predicts
#' on the held-out season. Stacking these predictions across all seasons yields
#' an out-of-sample dataset suitable for training Platt calibration parameters
#' that target the prospective setting (season unknown at training time).
#'
#' Season-specific smooth terms are excluded from out-of-season predictions by
#' default (\code{exclude_season_terms = TRUE}), matching the prospective
#' deployment setting where the new season has no history.
#'
#' @param joint_out List. Output of \code{train_stage2_joint()}, must contain
#'   \code{$fit} and \code{$train_data}.
#' @param season_col Character. Name of the season identifier column. Default
#'   \code{"season"}.
#' @param y_col Character. Observed-positives column. Default \code{"y_lead"}.
#' @param N_col Character. Trials column. Default \code{"N_lead"}.
#' @param lead_col Character. Lead column. Default \code{"lead"}.
#' @param time_keep Character vector. Additional time columns to retain in the
#'   output (e.g., for later use in \code{\link{tune_lambda_c}}). Default
#'   \code{c("weekF", "newWeek")}.
#' @param exclude_terms Character vector or \code{NULL}. Explicit smooth terms
#'   to exclude; overrides auto-detection when non-\code{NULL}.
#' @param exclude_season_terms Logical. If \code{TRUE} (default), season-related
#'   smooth terms are auto-detected and excluded from predictions on the
#'   held-out season.
#' @param eps Numeric. Probability clamping bound. Default \code{1e-6}.
#' @param parallel Logical. Use \pkg{future.apply} for parallel LOSO folds.
#'   Default \code{TRUE}.
#' @param workers Integer or \code{NULL}. Number of parallel workers.
#'   Defaults to \code{future::availableCores() - 1}.
#' @param set_plan Logical. If \code{TRUE}, sets a \code{multisession} future
#'   plan and restores the previous plan on exit. Default \code{TRUE}.
#' @param future_max_gb Numeric. Maximum global export size in GB for future
#'   workers. Default \code{8}.
#' @param verbose Logical. Print progress messages per fold. Default \code{TRUE}.
#'
#' @return A \code{data.table} with columns \code{season}, \code{lead},
#'   \code{y}, \code{N}, \code{p_hat}, and any retained \code{time_keep}
#'   columns. Each row is an out-of-sample prediction for the corresponding
#'   held-out season.
#'
#' @examples
#' \dontrun{
#' d_calib_oos <- make_calib_train_loso(joint_out, parallel = TRUE, workers = 8)
#' cal_off     <- train_calib_platt(d_calib_oos)
#' }
make_calib_train_loso <- function(joint_out,
                                  season_col = "season",
                                  y_col      = "y_lead",
                                  N_col      = "N_lead",
                                  lead_col   = "lead",
                                  time_keep  = c("weekF", "newWeek", "t_since"),
                                  exclude_terms = NULL,
                                  exclude_season_terms = TRUE,
                                  eps = 1e-6,
                                  parallel = TRUE,
                                  workers = NULL,
                                  set_plan = TRUE,
                                  future_max_gb = 8,
                                  verbose = TRUE) {
  if (!requireNamespace("data.table", quietly = TRUE)) stop("Need 'data.table'.")
  if (!requireNamespace("mgcv", quietly = TRUE)) stop("Need 'mgcv'.")
  if (is.null(joint_out$fit) || is.null(joint_out$train_data))
    stop("joint_out must contain $fit and $train_data.")

  `%||%` <- function(x, y) if (!is.null(x)) x else y
  clamp01 <- function(p, eps) pmin(pmax(p, eps), 1 - eps)

  d_all   <- data.table::as.data.table(joint_out$train_data)
  fit_ref <- joint_out$fit

  need <- c(season_col, lead_col, y_col, N_col)
  miss <- setdiff(need, names(d_all))
  if (length(miss)) stop("joint_out$train_data is missing: ", paste(miss, collapse = ", "))

  keep_cols <- intersect(c(season_col, lead_col, y_col, N_col, time_keep), names(d_all))
  seasons   <- unique(d_all[[season_col]])

  # ---- safe refit template ----
  call_tpl <- fit_ref$call
  call_tpl$formula <- stats::formula(fit_ref)
  environment(call_tpl$formula) <- baseenv()

  if (!is.null(fit_ref$method))  call_tpl$method  <- fit_ref$method
  if (!is.null(fit_ref$family))  call_tpl$family  <- fit_ref$family
  if (!is.null(fit_ref$control)) call_tpl$control <- fit_ref$control

  call_tpl[[1]] <- mgcv::bam

  # freeze discrete flag if captured as symbol (e.g., discrete = use_discrete)
  if (!is.null(call_tpl$discrete) && is.name(call_tpl$discrete)) {
    nm  <- as.character(call_tpl$discrete)
    val <- NULL
    if (!is.null(joint_out[[nm]])) val <- joint_out[[nm]]
    if (is.null(val) && !is.null(joint_out$spec) && !is.null(joint_out$spec[[nm]])) val <- joint_out$spec[[nm]]
    if (is.null(val) && exists(nm, envir = parent.frame(), inherits = TRUE)) val <- get(nm, envir = parent.frame(), inherits = TRUE)
    call_tpl$discrete <- isTRUE(val)
  }
  if (is.null(call_tpl$discrete) && !is.null(joint_out$use_discrete)) {
    call_tpl$discrete <- isTRUE(joint_out$use_discrete)
  }

  refit_from_tpl <- function(call_tpl, d_train) {
    cl       <- call_tpl
    cl$data  <- quote(d_train)
    eval(cl, envir = environment())
  }

  # auto-exclude season terms
  auto_exclude <- NULL
  if (exclude_season_terms && is.null(exclude_terms)) {
    tt <- try(colnames(stats::predict(fit_ref, newdata = d_all[1:min(50L, nrow(d_all))],
                                      type = "terms")), silent = TRUE)
    if (!inherits(tt, "try-error") && length(tt) > 0) {
      auto_exclude <- tt[grepl(season_col, tt, fixed = TRUE)]
      if (season_col != "season")
        auto_exclude <- unique(c(auto_exclude, tt[grepl("season", tt, fixed = TRUE)]))
    } else {
      auto_exclude <- character(0)
    }
  }
  exclude_terms_use <- exclude_terms %||% auto_exclude

  one_fold <- function(s, d_all, call_tpl, keep_cols,
                       season_col, y_col, N_col, lead_col,
                       exclude_terms_use, exclude_season_terms,
                       eps, verbose) {
    if (!requireNamespace("mgcv", quietly = TRUE))       stop("Need 'mgcv' on worker.")
    if (!requireNamespace("data.table", quietly = TRUE)) stop("Need 'data.table' on worker.")

    tryCatch({
      if (verbose) message("[calib-LOSO] holdout=", s)

      d_train <- d_all[get(season_col) != s]
      d_test  <- d_all[get(season_col) == s]

      fit_fold <- refit_from_tpl(call_tpl, d_train)

      d_pred <- data.table::copy(d_test)
      if (exclude_season_terms) {
        ref_lvl        <- as.character(d_train[[season_col]][1])
        d_pred[[season_col]] <- factor(rep(ref_lvl, nrow(d_pred)),
                                       levels = unique(as.character(d_train[[season_col]])))
      }

      p_hat <- stats::predict(fit_fold, newdata = d_pred, type = "response",
                              exclude = exclude_terms_use)
      p_hat <- clamp01(p_hat, eps)

      out <- d_test[, ..keep_cols]
      out[, p_hat := p_hat]

      if (lead_col != "lead") data.table::setnames(out, lead_col, "lead")
      if (y_col    != "y")    data.table::setnames(out, y_col,    "y")
      if (N_col    != "N")    data.table::setnames(out, N_col,    "N")

      out[]
    }, error = function(e) {
      data.table::data.table(season = as.character(s), error = conditionMessage(e))
    })
  }

  if (!parallel) {
    res <- lapply(seasons, one_fold,
                  d_all = d_all, call_tpl = call_tpl, keep_cols = keep_cols,
                  season_col = season_col, y_col = y_col, N_col = N_col, lead_col = lead_col,
                  exclude_terms_use = exclude_terms_use,
                  exclude_season_terms = exclude_season_terms,
                  eps = eps, verbose = verbose)
    out <- data.table::rbindlist(res, use.names = TRUE, fill = TRUE)
  } else {
    if (!requireNamespace("future", quietly = TRUE) ||
        !requireNamespace("future.apply", quietly = TRUE)) {
      stop("Need 'future' + 'future.apply' for parallel=TRUE.")
    }
    if (is.null(workers)) workers <- max(1L, future::availableCores() - 1L)

    old_opt <- getOption("future.globals.maxSize")
    options(future.globals.maxSize = future_max_gb * 1024^3)
    on.exit(options(future.globals.maxSize = old_opt), add = TRUE)

    if (set_plan) {
      old_plan <- future::plan()
      on.exit(future::plan(old_plan), add = TRUE)
      future::plan(future::multisession, workers = workers)
    }

    fg <- list(d_all = d_all, call_tpl = call_tpl, keep_cols = keep_cols,
               season_col = season_col, y_col = y_col, N_col = N_col, lead_col = lead_col,
               exclude_terms_use = exclude_terms_use,
               exclude_season_terms = exclude_season_terms,
               eps = eps, verbose = verbose,
               refit_from_tpl = refit_from_tpl, clamp01 = clamp01, one_fold = one_fold)

    res <- future.apply::future_lapply(
      seasons,
      FUN = function(s) one_fold(s, d_all, call_tpl, keep_cols,
                                 season_col, y_col, N_col, lead_col,
                                 exclude_terms_use, exclude_season_terms,
                                 eps, verbose),
      future.seed     = TRUE,
      future.packages = c("mgcv", "data.table"),
      future.globals  = fg
    )

    out <- data.table::rbindlist(res, use.names = TRUE, fill = TRUE)
  }

  if ("error" %in% names(out)) {
    bad <- unique(out[!is.na(error), .(season, error)])
    if (nrow(bad) > 0) {
      stop("Some LOSO folds failed:\n",
           paste0(" - ", bad$season, ": ", bad$error, collapse = "\n"),
           call. = FALSE)
    }
  }

  out[]
}


#' Tune the online-updater penalty \eqn{\lambda_c} via LOSO cross-validation
#'
#' For each candidate penalty value \eqn{\lambda_c}, replays the online
#' intercept-shift estimation procedure under exact deployment information
#' constraints (expanding window, outcomes observed with a lag equal to the
#' forecast lead). Selects the \eqn{\lambda_c} that minimises the average
#' held-out binomial negative log-likelihood across seasons and weeks.
#'
#' The online updater estimates a scalar logit-scale intercept shift
#' \eqn{c_{s,w}} at each within-season week \eqn{w} by solving a penalized
#' binomial MLE using all outcomes observed by that week.  The calibrated
#' predictor used as the offset is \eqn{\eta^{h,\mathrm{cal}}_{s,w} =
#' a_h + b_h \eta^h_{s,w}}, where \eqn{(a_h, b_h)} come from \code{cal_off}.
#'
#' @param d_calib_oos data.table. Out-of-sample predictions from
#'   \code{\link{make_calib_train_loso}}, with columns \code{season},
#'   \code{lead}, \code{y}, \code{N}, \code{p_hat}, and a time column matching
#'   \code{time_col}.
#' @param cal_off List. Offline Platt calibration object from
#'   \code{\link{train_calib_platt}}, with named vectors \code{$a} and
#'   \code{$b}.
#' @param ign_df data.frame or data.table with columns \code{season} and
#'   \code{w_ign} (integer ignition week for each season).
#' @param time_col Character. Name of the integer-valued forecast-origin week
#'   column in \code{d_calib_oos}. Default \code{"newWeek"}.
#' @param k_pre Non-negative integer. Number of weeks before ignition to
#'   include in the estimation window. Default \code{0L}.
#' @param lambda_grid Numeric vector. Candidate \eqn{\lambda_c} values to
#'   evaluate. Default \code{c(0, 10^seq(-3, 2, by = 0.5))}.
#' @param eps Numeric. Probability clamping bound. Default \code{1e-6}.
#' @param parallel Logical. Evaluate \code{lambda_grid} values in parallel via
#'   \pkg{future.apply}. Default \code{TRUE}.
#' @param workers Integer or \code{NULL}. Number of parallel workers.
#'   Defaults to \code{future::availableCores() - 1}.
#'
#' @return A \code{data.table} with columns \code{lambda_c}, \code{mean_nll},
#'   and \code{n_eval}, sorted ascending by \code{mean_nll}. The first row
#'   contains the best (lowest NLL) penalty value.
#'
#' @examples
#' \dontrun{
#' ign_df   <- unique(as.data.table(joint_out$train_data)[, .(season, w_ign = iWeek_used)])
#' res_lam  <- tune_lambda_c(d_calib_oos, cal_off = cal_off, ign_df = ign_df)
#' best_lam <- res_lam$lambda_c[1]
#' }
tune_lambda_c <- function(d_calib_oos,
                          cal_off,
                          ign_df,
                          time_col    = "newWeek",
                          k_pre       = 0L,
                          lambda_grid = c(0, 10^seq(-3, 2, by = 0.5)),
                          eps         = 1e-6,
                          parallel    = TRUE,
                          workers     = NULL) {
  if (!requireNamespace("data.table", quietly = TRUE)) stop("Need data.table")
  d      <- data.table::as.data.table(d_calib_oos)
  ign_df <- data.table::as.data.table(ign_df) %>% rename(w_ign = iWeek_true)
  stopifnot(all(c("season", "lead", "y", "N", "p_hat", time_col) %in% names(d)))
  stopifnot(all(c("season", "w_ign") %in% names(ign_df)))
  stopifnot(!is.null(cal_off$a), !is.null(cal_off$b))

  clamp01  <- function(p) pmin(pmax(p, eps), 1 - eps)

  lead_num <- function(x) {
    if (is.numeric(x)) return(as.integer(x))
    as.integer(sub("^h", "", as.character(x)))
  }

  fit_c <- function(y, N, eta, lambda_c) {
    obj <- function(c) {
      p <- clamp01(stats::plogis(eta + c))
      -sum(stats::dbinom(y, size = N, prob = p, log = TRUE)) + lambda_c * c^2
    }
    stats::optimize(obj, interval = c(-5, 5))$minimum
  }

  # build calibrated eta for every row
  d[, p_hat    := clamp01(as.numeric(p_hat))]
  d[, lead_chr := as.character(lead)]
  d[, lp_hat   := stats::qlogis(p_hat)]
  d[, p_cal    := stats::plogis(unname(cal_off$a[lead_chr]) + unname(cal_off$b[lead_chr]) * lp_hat)]
  d[, eta_cal  := stats::qlogis(clamp01(p_cal))]

  d <- ign_df[d, on = "season"]
  if (any(is.na(d$w_ign))) stop("ign_df missing w_ign for some seasons.", call. = FALSE)

  d[, h        := lead_num(lead_chr)]
  d[, t0       := as.integer(get(time_col))]
  d[, obs_week := t0 + h]

  sim_one_lambda <- function(lambda_c) {
    out <- d[, {
      data.table::setorder(.SD, t0, h)

      t_grid <- sort(unique(t0[t0 >= w_ign]))
      if (length(t_grid) == 0L) return(list(mean_nll = NA_real_, n_eval = 0L))

      nll_sum <- 0
      nll_n   <- 0L

      for (t in t_grid) {
        est    <- .SD[t0 >= (w_ign - k_pre) & t0 <= t & obs_week <= t]
        c_hat  <- if (nrow(est) == 0L) 0 else fit_c(est$y, est$N, est$eta_cal, lambda_c)

        eval_rows <- .SD[t0 == t]
        p_final   <- clamp01(stats::plogis(eval_rows$eta_cal + c_hat))

        nll_sum <- nll_sum + sum(-stats::dbinom(eval_rows$y, size = eval_rows$N,
                                                prob = p_final, log = TRUE))
        nll_n   <- nll_n + nrow(eval_rows)
      }

      list(mean_nll = nll_sum / nll_n, n_eval = nll_n)
    }, by = season]

    out <- out[!is.na(mean_nll)]
    data.table::data.table(
      lambda_c = lambda_c,
      mean_nll = sum(out$mean_nll * out$n_eval) / sum(out$n_eval),
      n_eval   = sum(out$n_eval)
    )
  }

  if (!parallel) {
    res <- data.table::rbindlist(lapply(lambda_grid, sim_one_lambda))
  } else {
    if (!requireNamespace("future", quietly = TRUE) ||
        !requireNamespace("future.apply", quietly = TRUE)) stop("Need future + future.apply")

    if (is.null(workers)) workers <- max(1L, future::availableCores() - 1L)
    old_plan <- future::plan()
    on.exit(future::plan(old_plan), add = TRUE)
    future::plan(future::multisession, workers = workers)

    res <- data.table::rbindlist(
      future.apply::future_lapply(
        lambda_grid,
        sim_one_lambda,
        future.seed     = TRUE,
        future.packages = c("data.table"),
        future.globals  = list(
          d             = d,
          sim_one_lambda = sim_one_lambda,
          fit_c         = fit_c,
          clamp01       = clamp01,
          k_pre         = k_pre
        )
      )
    )
  }

  list(res[order(mean_nll)], best = res[which.min(mean_nll)])
}



plot_fit_obs_cal_online_by_season <- function(joint_out = NULL,
                                              fit_stage2 = NULL,
                                              d_joint = NULL,
                                              cal = NULL,
                                              lambda_c = 1000,
                                              k_pre = 0L,
                                              ign_col = "iWeek_used",
                                              season_col = "season",
                                              lead_col   = "lead",
                                              y_col      = "y_lead",
                                              N_col      = "N_lead",
                                              time_col   = NULL,          # for x-axis (origin week); default newWeek->weekF->week
                                              weekF_col  = "weekF",       # used for online availability logic
                                              exclude_terms = NULL,
                                              eps = 1e-6,
                                              c_interval = c(-5, 5),
                                              ymax = 0.5,
                                              ncol = 4,
                                              interactive = FALSE) {
  if (!requireNamespace("data.table", quietly = TRUE)) stop("Need 'data.table'.")
  if (!requireNamespace("ggplot2", quietly = TRUE)) stop("Need 'ggplot2'.")
  
  `%||%` <- function(x, y) if (!is.null(x)) x else y
  clamp01 <- function(p, eps = 1e-6) pmin(pmax(p, eps), 1 - eps)
  
  # ---- allow passing joint_out directly ----
  if (!is.null(joint_out)) {
    fit_stage2 <- fit_stage2 %||% joint_out$fit
    d_joint    <- d_joint    %||% joint_out$train_data
  }
  if (is.null(fit_stage2)) stop("Need joint_out$fit or fit_stage2.")
  if (is.null(d_joint))    stop("Need joint_out$train_data or d_joint.")
  if (is.null(cal) || is.null(cal$a) || is.null(cal$b)) stop("Provide cal with named vectors $a and $b (e.g., cal_off).")
  
  d <- data.table::as.data.table(data.table::copy(d_joint))
  
  need <- c(season_col, lead_col, y_col, N_col, weekF_col, ign_col)
  miss <- setdiff(need, names(d))
  if (length(miss)) stop("d_joint is missing columns: ", paste(miss, collapse = ", "))
  
  if (is.null(time_col)) {
    time_col <- c("newWeek", weekF_col, "week")[c("newWeek", weekF_col, "week") %in% names(d)][1]
    if (is.na(time_col)) stop("Provide time_col (e.g., 'newWeek' or 'weekF').")
  }
  if (!time_col %in% names(d)) stop("time_col not found in d_joint: ", time_col)
  
  # ---- lead tagging (must match cal names h1/h2) ----
  if (is.numeric(d[[lead_col]]) || is.integer(d[[lead_col]])) {
    d[, lead_tag := paste0("h", as.integer(get(lead_col)))]
    d[, h := as.integer(get(lead_col))]
  } else {
    d[, lead_tag := as.character(get(lead_col))]
    d[, h := as.integer(sub("^h", "", lead_tag))]
  }
  if (any(is.na(d$h))) stop("Could not parse lead into 1/2 from: ", lead_col)
  if (any(!d$lead_tag %in% names(cal$a))) {
    stop("lead values in data (", paste(unique(d$lead_tag), collapse = ", "),
         ") do not match cal$a names (", paste(names(cal$a), collapse = ", "), ").")
  }
  
  # ---- Stage-2 fitted (raw) ----
  p_hat <- stats::predict(fit_stage2, newdata = d_joint, type = "response", exclude = exclude_terms)
  d[, p_hat := clamp01(as.numeric(p_hat), eps)]
  
  # ---- observed rate for the lead outcome ----
  d[, p_obs := data.table::fifelse(get(N_col) > 0, get(y_col) / get(N_col), NA_real_)]
  
  # ---- offline Platt calibration ----
  lp_hat <- qlogis(d$p_hat)
  a <- unname(cal$a[d$lead_tag])
  b <- unname(cal$b[d$lead_tag])
  d[, p_cal := plogis(as.numeric(a) + as.numeric(b) * lp_hat)]
  d[, eta_cal := qlogis(clamp01(p_cal, eps))]
  
  # ---- online intercept update c_{s,w} (per season, per origin weekF) ----
  lambda_c <- as.numeric(lambda_c)
  if (!is.finite(lambda_c) || lambda_c < 0) stop("lambda_c must be >= 0.")
  k_pre <- as.integer(k_pre)
  if (!is.finite(k_pre) || k_pre < 0) k_pre <- 0L
  
  d[, weekF_int := as.integer(get(weekF_col))]
  d[, w_ign := as.integer(get(ign_col))]
  d[, obs_weekF := weekF_int + h]
  d[, ok_outcome := !is.na(get(y_col)) & !is.na(get(N_col)) &
      get(N_col) > 0 & get(y_col) >= 0 & get(y_col) <= get(N_col) &
      is.finite(eta_cal)]
  
  fit_c_hat <- function(y, N, eta, lambda_c, interval) {
    obj <- function(c) {
      p <- plogis(eta + c)
      p <- clamp01(p, eps)
      -sum(stats::dbinom(y, size = N, prob = p, log = TRUE)) + lambda_c * c^2
    }
    stats::optimize(obj, interval = interval)$minimum
  }
  
  # compute c_hat by season x origin weekF
  c_tbl <- d[, {
    wign <- unique(w_ign)
    wign <- wign[is.finite(wign) & !is.na(wign)]
    if (length(wign) != 1L) wign <- suppressWarnings(min(wign, na.rm = TRUE))
    wign <- as.integer(wign)
    
    weeks <- sort(unique(weekF_int))
    c_hat <- numeric(length(weeks))
    
    w_start <- wign - k_pre
    
    for (i in seq_along(weeks)) {
      w <- weeks[i]
      if (!is.finite(wign) || is.na(wign) || w < wign) {
        c_hat[i] <- 0
        next
      }
      
      est <- .SD[
        weekF_int >= w_start &
          weekF_int <= w &
          obs_weekF <= w &
          ok_outcome == TRUE
      ]
      
      if (nrow(est) == 0L) {
        c_hat[i] <- 0
      } else {
        c_hat[i] <- fit_c_hat(
          y = est[[y_col]],
          N = est[[N_col]],
          eta = est$eta_cal,
          lambda_c = lambda_c,
          interval = c_interval
        )
      }
    }
    
    data.table::data.table(weekF_int = weeks, c_hat = c_hat)
  }, by = season_col]
  
  d <- c_tbl[d, on = c(season_col, "weekF_int")]
  d[is.na(c_hat), c_hat := 0]
  
  d[, p_online := plogis(eta_cal + c_hat)]
  
  # ---- panel label: one facet per season x lead ----
  d[, panel := sprintf("%s | %s=%s", as.character(get(season_col)), lead_col, as.character(get(lead_col)))]
  
  # ---- long format for plotting ----
  dt_obs <- d[, .(panel, t = get(time_col), series = "Observed", p = p_obs)]
  dt_fit <- d[, .(panel, t = get(time_col), series = "Fitted",   p = p_hat)]
  dt_cal <- d[, .(panel, t = get(time_col), series = "Calibrated", p = p_cal)]
  dt_on  <- d[, .(panel, t = get(time_col), series = "Online",   p = p_online)]
  
  dt_long <- data.table::rbindlist(list(dt_obs, dt_fit, dt_cal, dt_on), use.names = TRUE)
  dt_long[, series := factor(series, levels = c("Observed", "Fitted", "Calibrated", "Online"))]
  data.table::setorder(dt_long, panel, t, series)
  
  # y-axis
  ymax <- as.numeric(ymax)
  if (!is.finite(ymax) || ymax <= 0) ymax <- 0.5
  ymax <- min(1, ymax)
  
  # split draw order: green then red then blue (blue on top)
  dt_pts   <- dt_long[series == "Observed"]
  dt_lines <- dt_long[series != "Observed"]
  
  g <- ggplot2::ggplot() +
    ggplot2::geom_point(
      data = dt_pts,
      ggplot2::aes(x = t, y = p),
      color = "grey60", alpha = 0.45, size = 0.9
    ) +
    ggplot2::geom_line(
      data = dt_lines[series == "Fitted"],
      ggplot2::aes(x = t, y = p),
      color = "green4", linewidth = 1.6
    ) +
    ggplot2::geom_line(
      data = dt_lines[series == "Calibrated"],
      ggplot2::aes(x = t, y = p),
      color = "red3", linewidth = 0.85
    ) +
    ggplot2::geom_line(
      data = dt_lines[series == "Online"],
      ggplot2::aes(x = t, y = p),
      color = "blue3", linewidth = 1.0
    ) +
    ggplot2::facet_wrap(~panel, scales = "free_x", ncol = ncol) +
    ggplot2::scale_y_continuous(limits = c(0, ymax)) +
    ggplot2::labs(
      x = time_col,
      y = "Observed rate / probability",
      title = sprintf("Observed (grey) vs fitted (green) vs offline calibrated (red) vs online (blue); lambda_c=%s", format(lambda_c))
    ) +
    ggplot2::theme_bw(base_size = 11) +
    ggplot2::theme(
      legend.position = "none",
      strip.text = ggplot2::element_text(size = 9),
      axis.text.x = ggplot2::element_text(angle = 90, vjust = 0.5, hjust = 1)
    )
  
  if (!interactive) return(g)
  if (!requireNamespace("plotly", quietly = TRUE)) stop("Need 'plotly' for interactive=TRUE.")
  plotly::ggplotly(g)
}


#’ Bundle all trained components into a prospective forecasting kit
#’
#’ Packages Stage-1 ignition detection, Stage-2 forecasting, offline calibration,
#’ and online-updater configuration into a single list for prospective deployment.
#’
#’ Accepts either high-level training output objects (\code{ign_fit}, \code{joint_out})
#’ or the individual pieces directly. High-level objects take precedence only when the
#’ corresponding individual argument is \code{NULL}.
#’
#’ @param template_df Data frame with columns \code{newWeek} and \code{fit} defining
#’   the reference template curve.
#’ @param ign_fit Output of \code{fitIgnition()}. Used to extract \code{gam_cls} when
#’   \code{gam_cls} is \code{NULL}.
#’ @param gam_cls A trained \pkg{mgcv} \code{gam}/\code{bam} classifier, or a container
#’   accepted by \code{get_gam_cls()}. Overrides extraction from \code{ign_fit}.
#’ @param params_stage1 List of tuned Stage-1 threshold parameters (e.g.
#’   \code{tuned$best_params}).
#’ @param joint_out Output of \code{train_stage2_joint()}. Used to extract
#’   \code{spec_stage2}, \code{stage2_fit}, and \code{train_data_stage2} when those
#’   are \code{NULL}.
#’ @param spec_stage2 Stage-2 spec list from \code{stage2_make_spec()} or
#’   \code{stage2_spec_from_tuning()}. Overrides extraction from \code{joint_out}.
#’ @param stage2_fit Fitted \pkg{mgcv} \code{gam}/\code{bam} Stage-2 model. Overrides
#’   extraction from \code{joint_out}.
#’ @param train_data_stage2 Stage-2 training design data frame (preserves factor levels).
#’   Overrides extraction from \code{joint_out}.
#’ @param best_mean_nll 1-row data frame or list with \code{delta}/\code{K}/\code{leads}.
#’   Derived from \code{spec_stage2$best_row} when \code{NULL}.
#’ @param exclude_stage2 Character vector of model terms to exclude for new-season
#’   prediction. Derived from \code{spec_stage2$exclude_newseason} when \code{NULL}.
#’ @param cal_off Offline Platt calibration object with named vectors \code{$a} and
#’   \code{$b} (one element per lead). May be \code{NULL}.
#’ @param lambda_c Numeric ridge penalty for the online intercept updater.
#’ @param k_pre Integer number of pre-ignition weeks included in the online update window.
#’ @param defaults Named list of prospective pipeline run-time defaults:
#’   \code{align}, \code{anchorWeek}, \code{pre_buffer}, \code{deriv_k}.
#’
#’ @return A named list with components \code{stage1}, \code{stage2}, \code{calib},
#’   \code{online}, and \code{defaults}, ready to be passed to the prospective pipeline.
#’
#’ @examples
#’ \dontrun{
#’ # Preferred: pass training objects directly
#’ kit <- make_prospective_kit(
#’   template_df   = template_df,
#’   ign_fit       = ign_fit,
#’   params_stage1 = tuned$best_params,
#’   joint_out     = joint_out,
#’   cal_off       = cal_off,
#’   lambda_c      = res_lambda$best$lambda_c,
#’   k_pre         = spec_stage2_best$pre_buffer
#’ )
#’
#’ # Legacy: pass individual components
#’ kit <- make_prospective_kit(
#’   template_df       = template_df,
#’   gam_cls           = gam_cls,
#’   params_stage1     = params_stage1,
#’   spec_stage2       = spec_stage2,
#’   stage2_fit        = joint_out$fit,
#’   train_data_stage2 = joint_out$train_data
#’ )
#’ }
#’
#’ @export
make_prospective_kit <- function(template_df,
                                 ign_fit = NULL,
                                 gam_cls = NULL,
                                 params_stage1 = NULL,
                                 joint_out = NULL,
                                 spec_stage2 = NULL,
                                 stage2_fit = NULL,
                                 train_data_stage2 = NULL,
                                 best_mean_nll = NULL,
                                 exclude_stage2 = NULL,
                                 cal_off = NULL,
                                 lambda_c = 1000,
                                 k_pre = 0L,
                                 defaults = list(
                                   align = TRUE,
                                   anchorWeek = 19L,
                                   pre_buffer = 1L,
                                   deriv_k = 5L
                                 )) {
  stopifnot(is.data.frame(template_df))
  stopifnot(is.list(defaults))

  # ---- extract from high-level training objects ----

  # Stage-1: pull gam_cls from ign_fit if not supplied directly
  if (is.null(gam_cls) && !is.null(ign_fit)) {
    gam_cls <- get_gam_cls(ign_fit)
  }

  # Stage-2: pull spec, fit, train_data from joint_out if not supplied directly
  if (!is.null(joint_out)) {
    if (is.null(spec_stage2)       && !is.null(joint_out$spec))       spec_stage2       <- joint_out$spec
    if (is.null(stage2_fit)        && !is.null(joint_out$fit))        stage2_fit        <- joint_out$fit
    if (is.null(train_data_stage2) && !is.null(joint_out$train_data)) train_data_stage2 <- joint_out$train_data
  }

  # ---- derive secondary fields from spec when not explicitly provided ----
  if (is.null(best_mean_nll) && is.list(spec_stage2) && "best_row" %in% names(spec_stage2)) {
    best_mean_nll <- spec_stage2$best_row
  }
  if (is.null(exclude_stage2) && is.list(spec_stage2) && "exclude_newseason" %in% names(spec_stage2)) {
    exclude_stage2 <- spec_stage2$exclude_newseason
  }
  # ---- backfill defaults$pre_buffer from spec (LOSO result) when available ----
  if (is.list(spec_stage2) && !is.null(spec_stage2$pre_buffer)) {
    defaults$pre_buffer <- as.integer(spec_stage2$pre_buffer)
  }

  # ---- validate required pieces ----
  if (is.null(gam_cls)) stop("gam_cls is required (or supply ign_fit to extract it).")
  if (is.null(params_stage1) || !is.list(params_stage1)) stop("params_stage1 must be a list.")
  if (!inherits(stage2_fit, c("gam", "bam"))) stop("stage2_fit must be a mgcv gam/bam (or supply joint_out).")
  if (!is.data.frame(train_data_stage2)) stop("train_data_stage2 must be a data frame (or supply joint_out).")

  # ---- optional offline calibrator check ----
  if (!is.null(cal_off)) {
    if (is.null(cal_off$a) || is.null(cal_off$b)) {
      stop("cal_off must contain named vectors $a and $b (e.g., names ‘h1’,’h2’).")
    }
  }

  list(
    stage1 = list(
      gam_cls = gam_cls,
      params  = params_stage1
    ),
    stage2 = list(
      template_df   = template_df,
      spec_stage2   = spec_stage2,       # single source of truth for spec
      best_mean_nll = best_mean_nll,     # back-compat for helpers expecting delta/K/leads
      exclude_terms = exclude_stage2,    # terms to exclude for brand-new season prediction
      fit           = stage2_fit,
      train_data    = train_data_stage2
    ),
    calib = list(
      cal_off = cal_off                  # may be NULL if not trained yet
    ),
    online = list(
      lambda_c = as.numeric(lambda_c),
      k_pre    = as.integer(k_pre)
    ),
    defaults = defaults
  )
}

check_prospective_kit <- function(kit) {
  stopifnot(is.list(kit))
  req <- list(
    c("stage1","gam_cls"),
    c("stage1","params"),
    c("stage2","template_df"),
    c("stage2","spec_stage2"),
    c("stage2","fit"),
    c("stage2","train_data"),
    c("stage2","best_mean_nll"),
    c("stage2","exclude_terms"),
    c("online","lambda_c"),
    c("online","k_pre"),
    c("defaults")
  )
  
  get_path <- function(x, path) {
    for (nm in path) x <- x[[nm]]
    x
  }
  
  missing <- vapply(req, function(p) is.null(try(get_path(kit, p), silent = TRUE)), logical(1))
  if (any(missing)) {
    bad <- vapply(req[missing], paste, collapse = "/", FUN.VALUE = character(1))
    stop("kit missing: ", paste(bad, collapse = ", "))
  }
  if (!is.null(kit$calib$cal_off)) {
    if (is.null(kit$calib$cal_off$a) || is.null(kit$calib$cal_off$b)) {
      stop("kit$calib$cal_off exists but lacks $a/$b.")
    }
  }
  invisible(TRUE)
}
