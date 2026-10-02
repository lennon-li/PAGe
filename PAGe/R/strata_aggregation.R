# Stratified forecast aggregation -------------------------------------------

.page_agg_match_names <- function(x, strata, what) {
  if (is.null(x)) return(NULL)
  x <- as.numeric(x)
  if (length(x) != length(strata)) {
    stop("`", what, "` must have one value per stratum.", call. = FALSE)
  }
  names(x) <- strata
  x
}

.page_agg_validate_prob <- function(x, what = "estimate") {
  if (any(!is.finite(x))) stop("`", what, "` must be finite.", call. = FALSE)
  if (any(x < 0 | x > 1)) {
    stop("`", what, "` must be probabilities in [0, 1].", call. = FALSE)
  }
  invisible(TRUE)
}

.page_agg_operator <- function(k, method, weights = NULL) {
  method <- match.arg(method, c("sum", "weighted_mean", "linear"))
  if (method == "sum") return(rep(1, k))
  if (is.null(weights)) stop("`weights` is required for `weighted_mean` or `linear`.", call. = FALSE)
  w <- as.numeric(weights)
  if (length(w) != k || any(!is.finite(w))) {
    stop("`weights` must contain one finite value per stratum.", call. = FALSE)
  }
  if (method == "weighted_mean") {
    if (any(w < 0)) stop("`weighted_mean` weights must be non-negative.", call. = FALSE)
    sw <- sum(w)
    if (!is.finite(sw) || sw <= 0) stop("`weighted_mean` weights must sum to > 0.", call. = FALSE)
    w <- w / sw
  }
  w
}

#' Multinomial correlation for mutually exclusive shared-denominator strata
#'
#' Constructs the response-scale correlation matrix implied when multiple
#' mutually exclusive categories are counted out of the same denominator.
#' For strata `i != j`,
#' `rho_ij = -sqrt(p_i p_j / ((1-p_i)(1-p_j)))`.
#'
#' @param p Named or unnamed vector of category probabilities.
#' @param tolerance Numerical tolerance used to validate that the categories can
#'   coexist in a multinomial partition (`sum(p) <= 1 + tolerance`).
#'
#' @return A correlation matrix with the same stratum names as `p`.
#' @export
page_shared_denominator_correlation <- function(p, tolerance = 1e-10) {
  nm <- names(p)
  p <- as.numeric(p)
  if (!length(p)) stop("`p` must contain at least one stratum.", call. = FALSE)
  .page_agg_validate_prob(p, "p")
  if (sum(p) > 1 + tolerance) {
    stop(
      "Shared-denominator multinomial strata must satisfy sum(p) <= 1. ",
      "Use an explicit correlation/covariance matrix if categories can overlap.",
      call. = FALSE
    )
  }
  if (is.null(nm)) nm <- paste0("stratum", seq_along(p))
  k <- length(p)
  R <- diag(1, k)
  dimnames(R) <- list(nm, nm)
  if (k == 1L) return(R)
  for (i in seq_len(k - 1L)) {
    for (j in seq.int(i + 1L, k)) {
      den <- (1 - p[[i]]) * (1 - p[[j]])
      rho <- if (den <= 0) 0 else -sqrt((p[[i]] * p[[j]]) / den)
      rho <- max(-1, min(1, rho))
      R[i, j] <- R[j, i] <- rho
    }
  }
  ev <- eigen((R + t(R)) / 2, symmetric = TRUE, only.values = TRUE)$values
  if (min(ev) < -sqrt(.Machine$double.eps)) {
    stop("Derived shared-denominator correlation matrix is not positive semidefinite.", call. = FALSE)
  }
  R
}

.page_agg_matrix <- function(x, k, strata, what, correlation = FALSE) {
  if (is.null(x)) return(NULL)
  x <- as.matrix(x)
  if (!all(dim(x) == c(k, k)) || any(!is.finite(x))) {
    stop("`", what, "` must be a finite ", k, " x ", k, " matrix.", call. = FALSE)
  }
  if (!is.null(rownames(x)) && !is.null(colnames(x))) {
    if (!all(strata %in% rownames(x)) || !all(strata %in% colnames(x))) {
      stop("`", what, "` names must cover all strata.", call. = FALSE)
    }
    x <- x[strata, strata, drop = FALSE]
  } else {
    dimnames(x) <- list(strata, strata)
  }
  if (max(abs(x - t(x))) > 1e-8) stop("`", what, "` must be symmetric.", call. = FALSE)
  if (correlation) {
    if (any(abs(diag(x) - 1) > 1e-8) || any(abs(x) > 1 + 1e-8)) {
      stop("`correlation` must have unit diagonal and entries in [-1, 1].", call. = FALSE)
    }
  }
  ev <- eigen((x + t(x)) / 2, symmetric = TRUE, only.values = TRUE)$values
  if (min(ev) < -1e-8) stop("`", what, "` must be positive semidefinite.", call. = FALSE)
  x
}

.page_agg_var <- function(a, Sigma) {
  max(0, drop(t(a) %*% Sigma %*% a))
}

#' Aggregate stratified forecast estimates and uncertainty
#'
#' Aggregates related stratum-level forecasts while respecting their dependence
#' structure. Common examples are influenza A+B (`method = "sum"`,
#' `dependence = "shared_denominator"`) and all-ages positivity
#' (`method = "weighted_mean"`, typically `dependence = "independent"`).
#'
#' The function supports four analytic dependence structures:
#' \describe{
#'   \item{independent}{Zero off-diagonal covariance.}
#'   \item{shared_denominator}{Mutually exclusive multinomial categories counted
#'     from one denominator; correlations are derived from the component
#'     probabilities.}
#'   \item{correlation}{A user-supplied correlation matrix combined with
#'     component standard errors or confidence intervals.}
#'   \item{covariance}{A user-supplied covariance matrix; this is the most
#'     general analytic path.}
#' }
#'
#' If posterior/simulation draws are available, prefer
#' [page_aggregate_strata_draws()], which propagates nonlinear and non-Gaussian
#' uncertainty without analytic approximations.
#'
#' @param estimate Named vector of stratum estimates. For proportion forecasts,
#'   values must lie in `[0, 1]` unless `bounds = NULL`.
#' @param se Optional component standard errors on the response scale.
#' @param lower,upper Optional component confidence bounds. Supplying asymmetric
#'   bounds allows lower and upper aggregate half-widths to differ. If `se` is
#'   omitted, side-specific standard errors are inferred from these bounds and
#'   `level`.
#' @param method Aggregation operator: `"sum"`, `"weighted_mean"`, or
#'   `"linear"`.
#' @param weights Required for `weighted_mean` and `linear`. Weighted-mean
#'   weights are normalized to sum to one; linear weights are used as supplied.
#' @param dependence One of `"independent"`, `"shared_denominator"`,
#'   `"correlation"`, or `"covariance"`.
#' @param correlation Optional stratum correlation matrix for
#'   `dependence = "correlation"`.
#' @param covariance Optional stratum covariance matrix for
#'   `dependence = "covariance"`.
#' @param level Confidence level, e.g. `0.95`.
#' @param bounds Optional length-two output bounds. Use `c(0, 1)` for
#'   probabilities or `NULL` (default) for an unbounded linear estimand.
#'
#' @return An object of class `page_strata_aggregate` containing the aggregate
#'   estimate, interval, standard error(s), operator weights, and dependence
#'   matrix used.
#' @export
page_aggregate_strata <- function(estimate,
                                  se = NULL,
                                  lower = NULL,
                                  upper = NULL,
                                  method = c("sum", "weighted_mean", "linear"),
                                  weights = NULL,
                                  dependence = c("independent", "shared_denominator", "correlation", "covariance"),
                                  correlation = NULL,
                                  covariance = NULL,
                                  level = 0.95,
                                  bounds = NULL) {
  method <- match.arg(method)
  dependence <- match.arg(dependence)
  if (!is.numeric(estimate) || !length(estimate) || any(!is.finite(estimate))) {
    stop("`estimate` must be a non-empty finite numeric vector.", call. = FALSE)
  }
  strata <- names(estimate)
  if (is.null(strata)) strata <- paste0("stratum", seq_along(estimate))
  estimate <- as.numeric(estimate)
  names(estimate) <- strata
  k <- length(estimate)
  a <- .page_agg_operator(k, method, weights)
  names(a) <- strata

  if (!is.null(bounds)) {
    if (!is.numeric(bounds) || length(bounds) != 2L || any(!is.finite(bounds)) || bounds[[1L]] >= bounds[[2L]]) {
      stop("`bounds` must be NULL or two finite increasing numbers.", call. = FALSE)
    }
    if (any(estimate < bounds[[1L]] | estimate > bounds[[2L]])) {
      stop("`estimate` lies outside `bounds`.", call. = FALSE)
    }
  }
  if (dependence == "shared_denominator") .page_agg_validate_prob(estimate, "estimate")

  if (!is.numeric(level) || length(level) != 1L || !is.finite(level) || level <= 0 || level >= 1) {
    stop("`level` must be strictly between 0 and 1.", call. = FALSE)
  }
  z <- stats::qnorm((1 + level) / 2)
  se <- .page_agg_match_names(se, strata, "se")
  lower <- .page_agg_match_names(lower, strata, "lower")
  upper <- .page_agg_match_names(upper, strata, "upper")
  if (xor(is.null(lower), is.null(upper))) stop("Supply both `lower` and `upper`, or neither.", call. = FALSE)
  if (!is.null(lower) && any(lower > estimate)) stop("`lower` cannot exceed `estimate`.", call. = FALSE)
  if (!is.null(upper) && any(upper < estimate)) stop("`upper` cannot be below `estimate`.", call. = FALSE)
  if (!is.null(se) && any(se < 0)) stop("`se` must be non-negative.", call. = FALSE)

  R <- NULL
  Sigma <- NULL
  if (dependence == "covariance") {
    Sigma <- .page_agg_matrix(covariance, k, strata, "covariance", correlation = FALSE)
    if (is.null(Sigma)) stop("`covariance` is required for covariance dependence.", call. = FALSE)
  } else {
    if (dependence == "independent") {
      R <- diag(1, k)
      dimnames(R) <- list(strata, strata)
    } else if (dependence == "shared_denominator") {
      R <- page_shared_denominator_correlation(estimate)
    } else {
      R <- .page_agg_matrix(correlation, k, strata, "correlation", correlation = TRUE)
      if (is.null(R)) stop("`correlation` is required for correlation dependence.", call. = FALSE)
    }
  }

  aggregate_estimate <- sum(a * estimate)
  result <- list(
    estimate = aggregate_estimate,
    se = NA_real_,
    lower = NA_real_,
    upper = NA_real_,
    se_lower = NA_real_,
    se_upper = NA_real_,
    level = level,
    method = method,
    dependence = dependence,
    strata = strata,
    weights = a,
    correlation = R,
    covariance = Sigma,
    component = data.frame(
      stratum = strata, estimate = estimate,
      se = if (is.null(se)) NA_real_ else se,
      lower = if (is.null(lower)) NA_real_ else lower,
      upper = if (is.null(upper)) NA_real_ else upper,
      weight = a,
      stringsAsFactors = FALSE
    )
  )

  if (dependence == "covariance") {
    agg_se <- sqrt(.page_agg_var(a, Sigma))
    result$se <- agg_se
    result$se_lower <- agg_se
    result$se_upper <- agg_se
    result$lower <- aggregate_estimate - z * agg_se
    result$upper <- aggregate_estimate + z * agg_se
  } else {
    if (!is.null(lower) && !is.null(upper)) {
      sd_lo <- (estimate - lower) / z
      sd_hi <- (upper - estimate) / z
      Sigma_lo <- diag(sd_lo, k) %*% R %*% diag(sd_lo, k)
      Sigma_hi <- diag(sd_hi, k) %*% R %*% diag(sd_hi, k)
      se_lo <- sqrt(.page_agg_var(a, Sigma_lo))
      se_hi <- sqrt(.page_agg_var(a, Sigma_hi))
      result$se_lower <- se_lo
      result$se_upper <- se_hi
      result$se <- (se_lo + se_hi) / 2
      result$lower <- aggregate_estimate - z * se_lo
      result$upper <- aggregate_estimate + z * se_hi
      # Store a symmetric reference covariance when component SE is available;
      # otherwise expose the two side-specific covariance matrices explicitly.
      result$covariance_lower <- Sigma_lo
      result$covariance_upper <- Sigma_hi
    } else if (!is.null(se)) {
      Sigma <- diag(se, k) %*% R %*% diag(se, k)
      agg_se <- sqrt(.page_agg_var(a, Sigma))
      result$covariance <- Sigma
      result$se <- agg_se
      result$se_lower <- agg_se
      result$se_upper <- agg_se
      result$lower <- aggregate_estimate - z * agg_se
      result$upper <- aggregate_estimate + z * agg_se
    }
  }

  if (!is.null(bounds)) {
    if (is.finite(result$lower)) result$lower <- max(bounds[[1L]], result$lower)
    if (is.finite(result$upper)) result$upper <- min(bounds[[2L]], result$upper)
  }
  class(result) <- "page_strata_aggregate"
  result
}

#' Aggregate posterior or simulation draws across strata
#'
#' This is the preferred uncertainty propagation path when joint stratum draws
#' are available. Aggregation is applied inside every draw and the requested
#' interval is then taken from the aggregate draw distribution.
#'
#' @param draws Numeric matrix/data frame with rows as draws and columns as
#'   strata. A numeric vector is treated as one stratum.
#' @param method `"sum"`, `"weighted_mean"`, or `"linear"`.
#' @param weights Required for weighted mean or linear aggregation.
#' @param level Central interval level.
#' @param bounds Optional output bounds; use `c(0, 1)` for probabilities.
#' @param keep_draws Logical; include aggregate draws in the result.
#'
#' @return A `page_strata_aggregate_draws` object.
#' @export
page_aggregate_strata_draws <- function(draws,
                                        method = c("sum", "weighted_mean", "linear"),
                                        weights = NULL,
                                        level = 0.95,
                                        bounds = NULL,
                                        keep_draws = FALSE) {
  method <- match.arg(method)
  if (is.vector(draws) && is.numeric(draws)) draws <- matrix(draws, ncol = 1L)
  draws <- as.matrix(draws)
  storage.mode(draws) <- "double"
  if (!nrow(draws) || !ncol(draws) || any(!is.finite(draws))) {
    stop("`draws` must be a non-empty finite numeric matrix/data frame.", call. = FALSE)
  }
  strata <- colnames(draws)
  if (is.null(strata)) strata <- paste0("stratum", seq_len(ncol(draws)))
  colnames(draws) <- strata
  a <- .page_agg_operator(ncol(draws), method, weights)
  names(a) <- strata
  if (!is.numeric(level) || length(level) != 1L || !is.finite(level) || level <= 0 || level >= 1) {
    stop("`level` must be strictly between 0 and 1.", call. = FALSE)
  }
  aggregate_draws <- drop(draws %*% a)
  if (!is.null(bounds)) {
    if (!is.numeric(bounds) || length(bounds) != 2L || any(!is.finite(bounds)) || bounds[[1L]] >= bounds[[2L]]) {
      stop("`bounds` must be NULL or two finite increasing numbers.", call. = FALSE)
    }
    aggregate_draws <- pmin(bounds[[2L]], pmax(bounds[[1L]], aggregate_draws))
  }
  alpha <- (1 - level) / 2
  q <- stats::quantile(aggregate_draws, probs = c(alpha, 0.5, 1 - alpha), names = FALSE, type = 8)
  out <- list(
    estimate = mean(aggregate_draws),
    median = q[[2L]],
    se = stats::sd(aggregate_draws),
    lower = q[[1L]],
    upper = q[[3L]],
    level = level,
    method = method,
    strata = strata,
    weights = a,
    n_draws = nrow(draws),
    draws = if (isTRUE(keep_draws)) aggregate_draws else NULL
  )
  class(out) <- "page_strata_aggregate_draws"
  out
}

#' @export
print.page_strata_aggregate <- function(x, ...) {
  cat("PAGe stratified aggregate\n")
  cat("  method:      ", x$method, "\n", sep = "")
  cat("  dependence:  ", x$dependence, "\n", sep = "")
  cat("  estimate:    ", format(x$estimate, digits = 6), "\n", sep = "")
  if (is.finite(x$lower) && is.finite(x$upper)) {
    cat("  ", formatC(100 * x$level, format = "f", digits = 1), "% CI:    [",
        format(x$lower, digits = 6), ", ", format(x$upper, digits = 6), "]\n", sep = "")
  }
  invisible(x)
}

#' @export
print.page_strata_aggregate_draws <- function(x, ...) {
  cat("PAGe stratified aggregate (draw-based)\n")
  cat("  method:      ", x$method, "\n", sep = "")
  cat("  draws:       ", x$n_draws, "\n", sep = "")
  cat("  mean:        ", format(x$estimate, digits = 6), "\n", sep = "")
  cat("  median:      ", format(x$median, digits = 6), "\n", sep = "")
  cat("  ", formatC(100 * x$level, format = "f", digits = 1), "% interval: [",
      format(x$lower, digits = 6), ", ", format(x$upper, digits = 6), "]\n", sep = "")
  invisible(x)
}
