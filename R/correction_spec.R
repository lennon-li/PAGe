# Canonical M2 correction configuration shared by frozen LOSO and deployment.

.correction_scalar <- function(value, field) {
  if (!is.numeric(value) || length(value) != 1L || !is.finite(value) ||
    value < 0 || value > 1) {
    stop("Canonical correction spec requires `", field,
      "` to be one finite numeric value in [0, 1].",
      call. = FALSE
    )
  }
  as.numeric(value)
}

#' Resolve the M2 online-bias correction configuration
#'
#' Internal canonical resolver. Production and frozen LOSO must use this
#' function so the structural rates and adaptive rule cannot drift apart.
#'
#' @keywords internal
.resolve_correction_spec <- function(spec,
                                     compatibility = c("strict", "legacy"),
                                     bias_alpha = NULL,
                                     bias_beta = NULL) {
  compatibility <- match.arg(compatibility)
  if (!is.list(spec)) spec <- list()
  legacy_fields <- character()

  resolve_field <- function(field, override, legacy_default) {
    if (!is.null(override)) {
      return(.correction_scalar(override, field))
    }
    value <- spec[[field]]
    valid <- is.numeric(value) && length(value) == 1L && is.finite(value) &&
      value >= 0 && value <= 1
    if (valid) {
      return(as.numeric(value))
    }
    if (identical(compatibility, "legacy")) {
      legacy_fields <<- c(legacy_fields, field)
      return(legacy_default)
    }
    .correction_scalar(value, field)
  }

  resolved <- list(
    bias_alpha = resolve_field("bias_alpha", bias_alpha, 0.2),
    bias_beta = resolve_field("bias_beta", bias_beta, 0.0),
    bias_alpha_high = 0.7,
    same_sign_threshold = 2L,
    post_peak_action = "use_m1"
  )
  if (length(legacy_fields) > 0L) {
    warning(
      "Legacy compatibility: canonical correction spec is missing or invalid for ",
      paste(sprintf("`%s`", legacy_fields), collapse = ", "),
      "; using deprecated fallback values.",
      call. = FALSE
    )
  }
  resolved
}

.new_bias_correction_state <- function() {
  list(
    level = 0,
    trend = 0,
    previous_residual_positive = NA,
    consec_same_sign = 0L
  )
}

.update_bias_correction <- function(state, residual, correction) {
  if (!is.list(state)) stop("`state` must be a correction-state list.", call. = FALSE)
  residual <- as.numeric(residual)
  if (length(residual) != 1L || !is.finite(residual)) {
    stop("`residual` must be one finite numeric value.", call. = FALSE)
  }

  current_positive <- residual > 0
  if (!is.na(state$previous_residual_positive) &&
    identical(current_positive, state$previous_residual_positive)) {
    state$consec_same_sign <- as.integer(state$consec_same_sign) + 1L
  } else {
    state$consec_same_sign <- 0L
  }
  state$previous_residual_positive <- current_positive

  # Preserve the historical threshold: high alpha is used on the third
  # same-sign residual, after two same-sign transitions have accumulated.
  alpha <- if (state$consec_same_sign >= correction$same_sign_threshold) {
    correction$bias_alpha_high
  } else {
    correction$bias_alpha
  }
  level_previous <- state$level
  trend_previous <- state$trend
  level_new <- (level_previous + trend_previous) +
    alpha * (residual - (level_previous + trend_previous))
  trend_new <- trend_previous + correction$bias_beta *
    (level_new - level_previous - trend_previous)

  state$level <- level_new
  state$trend <- trend_new
  list(state = state, alpha = alpha)
}
