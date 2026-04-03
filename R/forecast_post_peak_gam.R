#' Post-peak GAM forecast without further alignment
#'
#' After the peak has been detected, stop aligning to the common template
#' and instead fit a smooth GAM directly to the observed season, optionally
#' using the template as a covariate. This produces a continuous curve
#' through the last observed week and a smooth forecast to max_newWeek.
#'
#' @param currentSeason Data frame with at least columns:
#'   newWeek (sequential index), y, neg.
#' @param g_ref_fun Optional function(u) giving template on the LINK scale
#'   for week index u (e.g. from make_g_ref_fun). If NULL, the template
#'   is not used as a covariate.
#' @param max_newWeek Integer, maximum newWeek to forecast to (e.g. 52 or 53).
#'   Default: max(currentSeason$newWeek).
#' @param k_smooth Basis dimension for s(newWeek) in the GAM.
#' @param use_weights Logical; if TRUE, use n = y + neg as binomial weights.
#' @param level Confidence level for pointwise intervals.
#'
#' @return A list with components similar to align_forecast_pipeline_dilate():
#'   tau, delta, a, b, allow_scale, delta_on, pred_df, last_obs, V_ab, V_td,
#'   peak, fallback_reason. The alignment-specific slots are mostly NA.
#' @export
forecast_post_peak_gam <- function(currentSeason,
                                   g_ref_fun   = NULL,
                                   max_newWeek = 53,
                                   k_smooth    = 8,
                                   use_weights = TRUE,
                                   level       = 0.95) {
  # basic checks
  needed <- c("newWeek", "y", "neg")
  miss   <- setdiff(needed, names(currentSeason))
  if (length(miss) > 0) {
    stop("currentSeason is missing columns: ",
         paste(miss, collapse = ", "))
  }
  
  df_obs <- currentSeason %>%
    dplyr::mutate(
      newWeek = as.integer(.data$newWeek),
      n       = .data$y + .data$neg
    )
  
  if (is.null(max_newWeek)) {
    max_newWeek <- max(df_obs$newWeek, na.rm = TRUE)
  }
  
  # optional template on link scale
  if (!is.null(g_ref_fun)) {
    g_ref_safe <- function(u) g_ref_fun(pmin(pmax(u, 1), 52))
    df_obs <- df_obs %>%
      dplyr::mutate(
        eta_ref = g_ref_safe(.data$newWeek)
      )
    gam_formula <- stats::as.formula(
      "cbind(y, neg) ~ s(eta_ref, k = 2) + s(newWeek, k = k_smooth)"
    )
  } else {
    gam_formula <- stats::as.formula(
      "cbind(y, neg) ~ s(newWeek, k = k_smooth)"
    )
  }
  
  wts <- if (use_weights) df_obs$n else rep(1, nrow(df_obs))
  
  # fit GAM on link scale
  gam_fit <- mgcv::gam(
    formula = gam_formula,
    family  = binomial(),
    data    = df_obs,
    weights = wts,
    method  = "REML"
  )
  
  # prediction grid from first obs week to max_newWeek
  grid <- tibble::tibble(
    newWeek = seq(min(df_obs$newWeek, na.rm = TRUE),
                  max_newWeek,
                  by = 1L)
  )
  
  if (!is.null(g_ref_fun)) {
    grid <- grid %>%
      dplyr::mutate(
        eta_ref = g_ref_safe(.data$newWeek)
      )
  }
  
  # get link-scale fit + se, then transform to probability
  pred_link <- stats::predict(
    gam_fit,
    newdata = grid,
    type    = "link",
    se.fit  = TRUE
  )
  
  eta_hat <- as.numeric(pred_link$fit)
  se_eta  <- as.numeric(pred_link$se.fit)
  z       <- stats::qnorm((1 + level) / 2)
  
  grid <- grid %>%
    dplyr::mutate(
      p_hat = plogis(eta_hat),
      p_lo  = plogis(eta_hat - z * se_eta),
      p_hi  = plogis(eta_hat + z * se_eta),
      kind  = dplyr::if_else(
        .data$newWeek <= max(df_obs$newWeek, na.rm = TRUE),
        "observed", "forecast"
      )
    ) %>%
    dplyr::arrange(.data$newWeek)
  
  # simple peak summary on the smoothed curve
  idx_peak <- which.max(grid$p_hat)
  peak <- list(
    t_peak    = grid$newWeek[idx_peak],
    t_peak_ci = c(NA_real_, NA_real_),
    p_peak    = grid$p_hat[idx_peak]
  )
  
  last_obs <- max(df_obs$newWeek, na.rm = TRUE)
  
  # return in the same structure your plotRes() expects
  list(
    tau            = NA_real_,
    delta          = NA_real_,
    a              = NA_real_,
    b              = NA_real_,
    allow_scale    = FALSE,
    delta_on       = FALSE,
    pred_df        = grid,
    last_obs       = last_obs,
    V_ab           = matrix(NA_real_, 0, 0),
    V_td           = matrix(NA_real_, 0, 0),
    peak           = peak,
    fallback_reason = NA_character_
  )
}
