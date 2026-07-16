#' Validate a PAGe deployment kit
#'
#' Checks the in-memory artifacts required by the prospective runtime. Frozen
#' forecasting requires no historical-data files. Weekly refitting additionally
#' requires historical aligned data and a template data frame.
#'
#' @param kit A kit returned by \code{assemble_kit()} or
#'   \code{load_prospective_kit()}.
#' @param mode Runtime mode: \code{"frozen"} or \code{"weekly_refit"}.
#'
#' @return The validated kit.
#' @export
validate_page_kit <- function(kit, mode = c("frozen", "weekly_refit")) {
  mode <- match.arg(mode)
  if (!is.list(kit)) stop("`kit` must be a list of trained PAGe artifacts.")

  required <- c(
    "m0_params", "ref", "hyper", "M1_PARAMS", "m2_production", "best_spec"
  )
  missing <- required[vapply(required, function(name) is.null(kit[[name]]), logical(1))]
  if (length(missing)) {
    stop("PAGe kit is missing required field(s): ", paste(missing, collapse = ", "), ".")
  }
  if (!is.list(kit$m0_params) || !length(kit$m0_params)) {
    stop("PAGe kit field `m0_params` must be a non-empty parameter list.")
  }
  if (!is.list(kit$ref) || !is.numeric(kit$ref$anchorWeek) ||
    length(kit$ref$anchorWeek) != 1L ||
    !is.finite(kit$ref$anchorWeek)) {
    stop("PAGe kit field `ref$anchorWeek` must be one finite reference week.")
  }
  if (!is.list(kit$hyper)) {
    stop("PAGe kit field `hyper` must be an alignment hyperparameter list.")
  }
  m1_fields <- c(
    "temperature", "rise_weight", "trough_weight", "peak_decay",
    "slope_weight", "slope_window", "dynamic_temp", "dynamic_temp_pivot"
  )
  if (!is.list(kit$M1_PARAMS)) {
    stop("PAGe kit field `M1_PARAMS` must be a runtime parameter list.")
  }
  missing_m1 <- setdiff(m1_fields, names(kit$M1_PARAMS))
  if (length(missing_m1)) {
    stop(
      "PAGe kit field `M1_PARAMS` is missing runtime parameter(s): ",
      paste(missing_m1, collapse = ", "), "."
    )
  }
  if (!is.list(kit$m2_production) || is.null(kit$m2_production$fit)) {
    stop("PAGe kit field `m2_production$fit` is required.")
  }
  if (!is.list(kit$best_spec)) {
    stop("PAGe kit field `best_spec` must be a Stage-2 specification list.")
  }
  fit <- kit$m2_production$fit
  if (!inherits(fit, "gam")) {
    stop("PAGe kit field `m2_production$fit` must be a fitted GAM/BAM object.")
  }
  model_fields <- c("logit_f_eff", "z_ema", "lead")
  conditional_fields <- c(
    if ((kit$best_spec$k_n %||% 0L) > 0L) "logN_now",
    if ((kit$best_spec$k_de %||% 0L) > 0L) "dz_ema",
    if ((kit$best_spec$k_r %||% 0L) > 0L) "z_resid",
    if ((kit$best_spec$k_sp %||% 0L) > 0L) "logit_spread"
  )
  model_fields <- c(model_fields, conditional_fields)
  missing_model <- if (is.data.frame(fit$model)) {
    setdiff(model_fields, names(fit$model))
  } else {
    model_fields
  }
  if (length(missing_model)) {
    stop(
      "PAGe kit GAM model frame is missing runtime field(s): ",
      paste(missing_model, collapse = ", "), "."
    )
  }
  if (mode == "weekly_refit") {
    missing_refit <- c(
      if (!is.data.frame(kit$hist_data)) "hist_data",
      if (!is.data.frame(kit$template_df)) "template_df"
    )
    if (length(missing_refit)) {
      stop(
        "Weekly refit mode requires kit field(s): ",
        paste(missing_refit, collapse = ", "), "."
      )
    }
  }
  kit
}

#' @export
print.page_training_result <- function(x, ...) {
  cat("<PAGe training result>\n")
  cat("  mode: ", x$mode %||% "unknown", "\n", sep = "")
  holdout <- x$holdout$status %||% "not recorded"
  cat("  holdout: ", holdout, "\n", sep = "")
  cat("  deployment kit: ", if (is.null(x$kit)) "absent" else "ready", "\n", sep = "")
  invisible(x)
}

#' @export
summary.page_forecast <- function(object, ...) {
  pred <- object$pred_df
  forecast <- if (is.data.frame(pred) && all(c("kind", "p_hat") %in% names(pred))) {
    pred[!is.na(pred$kind) & pred$kind == "forecast", , drop = FALSE]
  } else {
    data.frame(p_hat = numeric())
  }
  horizons <- if (is.data.frame(object$m2_preds) && "h" %in% names(object$m2_preds)) {
    sort(unique(as.integer(object$m2_preds$h[is.finite(object$m2_preds$h)])))
  } else {
    integer()
  }
  forecast_range <- if (nrow(forecast) && any(is.finite(forecast$p_hat))) {
    range(forecast$p_hat[is.finite(forecast$p_hat)])
  } else {
    c(NA_real_, NA_real_)
  }
  list(
    last_observation = as.integer(object$last_obs %||% NA_integer_),
    n_forecasts = as.integer(nrow(forecast)),
    horizons = horizons,
    forecast_range = forecast_range
  )
}

#' @export
print.page_forecast <- function(x, ...) {
  info <- summary.page_forecast(x)
  cat("<PAGe forecast>\n")
  cat("  last observation week: ",
    if (is.na(info$last_observation)) "not available" else info$last_observation,
    "\n",
    sep = ""
  )
  cat("  forecasts: ", info$n_forecasts, "\n", sep = "")
  if (length(info$horizons)) {
    cat("  horizons: ", paste(info$horizons, collapse = ", "), "\n", sep = "")
  }
  invisible(x)
}
