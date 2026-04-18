# Global reference environment and accessor shims
# make_reference_functions / set_reference / get_reference / fit_reference_gam
# are in retired.R

.flualign_ref_env <- new.env(parent = emptyenv())

# Shims exported so user code works
#' Global shim: reference curve on logit scale (unbounded domain)
#'
#' Evaluates the global reference function set via \code{set_reference()}.
#' Returns logit-scale predictions for arbitrary (possibly fractional)
#' \code{u} values without clamping.
#'
#' @param u Numeric vector of week positions to evaluate.
#' @return Numeric vector of logit-scale reference values.
#' @keywords internal
g_ref_fun   <- function(u) get("g_ref_fun",   envir = .flualign_ref_env, inherits = FALSE)(u)

#' Global shim: reference curve clamped to support
#'
#' Evaluates the global reference function set via \code{set_reference()},
#' clamping \code{u} to the grid support before prediction to avoid
#' extrapolation artefacts.
#'
#' @param u Numeric vector of week positions to evaluate.
#' @return Numeric vector of logit-scale reference values.
#' @export
g_ref_safe  <- function(u) get("g_ref_safe",  envir = .flualign_ref_env, inherits = FALSE)(u)

#' Global shim: reference curve mean and SE on logit scale
#'
#' Evaluates the global GAM-based reference function set via
#' \code{set_reference()}, returning both the fitted mean and the pointwise
#' standard error on the logit scale.
#'
#' @param u Numeric vector of week positions to evaluate.
#' @return A list with \code{mu} and \code{se} (both numeric vectors of the
#'   same length as \code{u}).
#' @keywords internal
g_ref_mu_se <- function(u) get("g_ref_mu_se", envir = .flualign_ref_env, inherits = FALSE)(u)

