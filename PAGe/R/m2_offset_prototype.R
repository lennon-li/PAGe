# M2 offset/residual-correction prototype helpers.
#
# These helpers are intentionally separate from the production M2 path.  They
# fit a binomial GAM whose M1 logit is a formula offset, so the fitted terms
# represent a residual correction rather than a second estimate of M1.

m2_offset_formula <- function(k_z = 3L, k_sp = 0L, bs = "ts") {
  k_z <- as.integer(k_z[1L])
  k_sp <- as.integer(k_sp[1L])
  if (is.na(k_z) || k_z < 0L || is.na(k_sp) || k_sp < 0L) {
    stop("k_z and k_sp must be non-negative integers.", call. = FALSE)
  }
  if (!is.character(bs) || length(bs) != 1L || !nzchar(bs)) {
    stop("bs must be one non-empty character value.", call. = FALSE)
  }

  rhs <- c("-1 + lead", "offset(logit_f_eff)")
  if (k_z > 0L) {
    rhs <- c(rhs, sprintf("s(z_ema, by=lead, bs='%s', k=%d)", bs, k_z))
  }
  if (k_sp > 0L) {
    rhs <- c(rhs, sprintf(
      "s(logit_spread, by=lead, bs='%s', k=%d)", bs, k_sp
    ))
  }
  stats::as.formula(paste(
    "cbind(y_lead, N_lead - y_lead) ~", paste(rhs, collapse = " + ")
  ))
}

.validate_m2_offset_data <- function(data, formula) {
  if (!is.data.frame(data)) stop("data must be a data.frame.", call. = FALSE)
  required <- c("y_lead", "N_lead", "lead", "logit_f_eff", "z_ema")
  if (grepl("logit_spread", paste(deparse(formula), collapse = " ")) &&
    !"logit_spread" %in% names(data)) {
    stop("data is missing logit_spread required by the formula.", call. = FALSE)
  }
  missing <- setdiff(required, names(data))
  if (length(missing)) {
    stop("data is missing: ", paste(missing, collapse = ", "), call. = FALSE)
  }
  if (any(!is.finite(data$y_lead) | !is.finite(data$N_lead) |
    data$N_lead <= 0 | data$y_lead < 0 | data$y_lead > data$N_lead)) {
    stop("Invalid binomial response counts in data.", call. = FALSE)
  }
  numeric_columns <- c("logit_f_eff", "z_ema")
  if ("logit_spread" %in% names(data)) numeric_columns <- c(numeric_columns, "logit_spread")
  if (any(!vapply(data[numeric_columns], function(x) all(is.finite(x)), logical(1)))) {
    stop("M2 offset predictors must be finite.", call. = FALSE)
  }
  if (anyNA(data$lead)) stop("lead must not contain missing values.", call. = FALSE)
  invisible(data)
}

#' Fit a regularized binomial M2 offset correction.
#'
#' @param data Stacked lead-specific rows with binomial counts and M1/features.
#' @param k_z Basis size for the horizon-specific z_ema correction.  Zero
#'   disables the smooth and leaves only the residual intercepts.
#' @param k_sp Basis size for the optional horizon-specific logit-spread
#'   correction.  Zero disables this term.
#' @param method GAM fitting method, normally "REML".
#' @param gamma Smoothness selection multiplier passed to mgcv.
#' @param penalize_intercepts Penalize horizon intercepts toward zero.
#' @param intercept_sp Intercept penalty; -1 estimates it by REML.
#' @param season_balance Give each training season equal total trial weight.
#' @return A list containing the fitted GAM, visible formula, fit warnings,
#'   training seasons, and effective degrees of freedom.
fit_m2_offset_correction <- function(data,
                                     k_z = 3L,
                                     k_sp = 0L,
                                     method = "REML",
                                     gamma = 1.4,
                                     penalize_intercepts = FALSE,
                                     intercept_sp = -1,
                                     season_balance = FALSE) {
  formula <- m2_offset_formula(k_z = k_z, k_sp = k_sp)
  .validate_m2_offset_data(data, formula)
  dat <- as.data.frame(data)
  dat$lead <- factor(as.character(dat$lead), levels = sort(unique(as.character(dat$lead))))
  if (nlevels(dat$lead) < 1L) stop("lead must have at least one level.", call. = FALSE)
  dat$.fit_weight <- 1
  season_trial_totals <- numeric()
  fit_weight_by_season <- numeric()
  if (isTRUE(season_balance)) {
    if (!"season" %in% names(dat) || anyNA(dat$season)) stop("season is required for balancing.")
    season_chr <- as.character(dat$season)
    season_trial_totals <- tapply(dat$N_lead, season_chr, sum)
    if (any(!is.finite(season_trial_totals) | season_trial_totals <= 0)) {
      stop("season trial totals must be finite and positive.", call. = FALSE)
    }
    fit_weight_by_season <- mean(season_trial_totals) / season_trial_totals
    dat$.fit_weight <- unname(fit_weight_by_season[season_chr])
  }
  penalty <- if (isTRUE(penalize_intercepts)) {
    list(lead = list(diag(nlevels(dat$lead)), sp = intercept_sp))
  } else {
    NULL
  }

  warnings <- character()
  fit <- withCallingHandlers(
    mgcv::gam(
      formula = formula,
      data = dat,
      family = stats::binomial(),
      method = method,
      select = TRUE,
      gamma = gamma,
      weights = .fit_weight,
      paraPen = penalty,
      na.action = stats::na.fail
    ),
    warning = function(w) {
      warnings <<- unique(c(warnings, conditionMessage(w)))
      invokeRestart("muffleWarning")
    }
  )
  if (!isTRUE(fit$converged)) stop("M2 offset GAM did not converge.", call. = FALSE)

  smry <- summary(fit)
  edf <- if (!is.null(smry$s.table) && nrow(smry$s.table)) {
    stats::setNames(as.numeric(smry$s.table[, "edf"]), rownames(smry$s.table))
  } else {
    numeric(0)
  }
  list(
    fit = fit,
    formula = formula,
    training_rows = nrow(dat),
    training_seasons = if ("season" %in% names(dat)) sort(unique(as.character(dat$season))) else character(),
    warnings = warnings,
    converged = isTRUE(fit$converged),
    edf = edf,
    total_edf = sum(fit$edf),
    penalize_intercepts = isTRUE(penalize_intercepts),
    intercept_sp = intercept_sp,
    season_balance = isTRUE(season_balance),
    season_trial_totals = season_trial_totals,
    fit_weight_by_season = fit_weight_by_season
  )
}

#' Predict an M2 offset correction and return its residual link contribution.
#'
#' The returned `m1_p` is computed directly from the offset, while `p_hat`
#' includes only the fitted correction.  No capping, switching, or online
#' bias adjustment is applied here.
#'
#' @param fit A fitted GAM or the list returned by
#'   `fit_m2_offset_correction()`.
#' @param newdata Prediction rows containing `logit_f_eff` and all terms used
#'   by the fitted correction.
#'
#' @return A data frame containing the M1 probability, corrected probability,
#'   corrected linear predictor, and residual link contribution.
predict_m2_offset_correction <- function(fit, newdata) {
  fit_obj <- if (is.list(fit) && !inherits(fit, "gam")) fit$fit else fit
  if (!inherits(fit_obj, "gam")) stop("fit must be a fitted GAM or helper result.", call. = FALSE)
  if (!is.data.frame(newdata) || !"logit_f_eff" %in% names(newdata)) {
    stop("newdata must contain logit_f_eff.", call. = FALSE)
  }
  nd <- as.data.frame(newdata)
  if (any(!is.finite(nd$logit_f_eff))) stop("Prediction offsets must be finite.")
  if ("lead" %in% names(fit_obj$model)) {
    if (!"lead" %in% names(nd) || anyNA(nd$lead) ||
      any(!as.character(nd$lead) %in% levels(fit_obj$model$lead))) {
      stop("Unknown or missing prediction horizon.")
    }
    nd$lead <- factor(as.character(nd$lead), levels = levels(fit_obj$model$lead))
  }
  eta <- as.numeric(stats::predict(fit_obj, newdata = nd, type = "link"))
  logit_m1 <- as.numeric(nd$logit_f_eff)
  data.frame(
    m1_p = stats::plogis(logit_m1),
    p_hat = stats::plogis(eta),
    eta = eta,
    correction_logit = eta - logit_m1,
    stringsAsFactors = FALSE
  )
}

#' Return the exact no-correction M1 baseline on the probability scale
#'
#' @param newdata Prediction rows containing `logit_f_eff`.
#'
#' @return A numeric vector of M1 probabilities.
m2_offset_baseline <- function(newdata) {
  if (!is.data.frame(newdata) || !"logit_f_eff" %in% names(newdata)) {
    stop("newdata must contain logit_f_eff.", call. = FALSE)
  }
  stats::plogis(as.numeric(newdata$logit_f_eff))
}
