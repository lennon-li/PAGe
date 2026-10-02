sp_quantile <- function(pmf, support = as.integer(names(pmf)), prob) {
  p <- as.numeric(pmf); s <- as.integer(support)
  if (length(p) != length(s) || !length(p) || any(!is.finite(p)) || any(p < 0) || any(diff(s) <= 0) ||
      abs(sum(p) - 1) > 1e-10 || length(prob) != 1L || !is.finite(prob) || prob < 0 || prob > 1)
    stop("Invalid PMF or quantile support.", call. = FALSE)
  s[which(cumsum(p) >= prob)[1L]]
}

sp_validate_pmf <- function(pmf) {
  if (is.null(names(pmf))) stop("PMF requires ordered support names.", call. = FALSE)
  support <- suppressWarnings(as.integer(names(pmf)))
  if (length(support) != length(pmf) || anyNA(support) || any(support < 1L) || any(diff(support) != 1L) || any(!is.finite(pmf)) ||
      any(pmf < 0) || abs(sum(pmf) - 1) > 1e-10) stop("Invalid finite nonnegative ordered PMF.", call. = FALSE)
  invisible(TRUE)
}

sp_distribution_summary <- function(pmf, support = as.integer(names(pmf))) {
  sp_validate_pmf(pmf)
  med <- sp_quantile(pmf, support, 0.5); lo <- sp_quantile(pmf, support, 0.1); hi <- sp_quantile(pmf, support, 0.9)
  list(median = as.integer(med), mean = sum(support * pmf), lo = as.integer(lo), hi = as.integer(hi), width = as.integer(hi - lo))
}

sp_prediction_fields <- function(distribution, feature, W, target_weekF = NULL) {
  sp_validate_pmf(distribution$pmf)
  support <- as.integer(names(distribution$pmf)); z <- sp_distribution_summary(distribution$pmf, support)
  out <- data.frame(season = as.character(feature$season), origin = as.integer(feature$weekF), W = as.integer(W), pi = distribution$pi,
    peak_weekF_origin = z$median, peak_weekF_mean = z$mean, peak_weekF_lo = z$lo, peak_weekF_hi = z$hi,
    peak_ci_width = z$width, interval_level = .8, interval_type = "central_discrete_predictive", stringsAsFactors = FALSE)
  out$pmf <- I(list(distribution$pmf)); out$q_minus <- I(list(distribution$q_minus)); out$q_plus <- I(list(distribution$q_plus))
  if (!is.null(target_weekF)) out$tau <- sp_tau(target_weekF, out$peak_weekF_origin)
  out
}

sp_tau <- function(target_weekF, peak_weekF_origin) {
  if (any(!is.finite(target_weekF)) || any(!is.finite(peak_weekF_origin))) stop("tau inputs must be finite.", call. = FALSE)
  pmin(6, pmax(-6, as.numeric(target_weekF) - as.numeric(peak_weekF_origin)))
}

sp_score_one <- function(pmf, K, P = NULL) {
  sp_validate_pmf(pmf); support <- as.integer(names(pmf))
  if (length(K) != 1L || !is.finite(K) || !K %in% support) stop("Observed K outside PMF support.", call. = FALSE)
  truth <- as.integer(support == K); c(log_loss = -log(max(pmf[as.character(K)], 1e-12)), brier = sum((pmf - truth)^2),
    ranked_brier = sum((cumsum(pmf) - cumsum(truth))^2), mean_point_squared_error = (sum(pmf * support) - K)^2,
    median_mae = abs(sp_quantile(pmf, support, .5) - K), mean_mae = abs(sum(pmf * support) - K),
    coverage80 = as.numeric(K >= sp_quantile(pmf, support, .1) & K <= sp_quantile(pmf, support, .9)),
    width80 = sp_quantile(pmf, support, .9) - sp_quantile(pmf, support, .1),
    interval_score80 = (sp_quantile(pmf, support, .9) - sp_quantile(pmf, support, .1)) +
      10 * max(sp_quantile(pmf, support, .1) - K, 0) + 10 * max(K - sp_quantile(pmf, support, .9), 0),
    fractional_abs_error = if (is.null(P)) NA_real_ else abs(sum(pmf * support) - P))
}

sp_empirical_pmf <- function(labels, W, support = seq_len(W), pseudocount = .5) {
  z <- as.data.frame(labels, stringsAsFactors = FALSE)
  if (!all(c("K", "W") %in% names(z)) || !nrow(z) || any(z$K < 1 | z$K > z$W)) stop("Empirical PMF requires valid allowed labels.", call. = FALSE)
  if (length(W) != 1L || !W %in% c(52L, 53L) || any(support < 1 | support > W)) stop("Invalid empirical support.", call. = FALSE)
  counts <- tabulate(z$K[z$K <= W], nbins = W) + pseudocount
  p <- counts[support]; p <- p / sum(p); names(p) <- as.character(support); p
}

sp_equal_season_mean <- function(x, value, season = "season") {
  means <- aggregate(x[[value]], list(season = x[[season]]), mean, na.rm = TRUE)
  mean(means[[2L]])
}

sp_score_predictions <- function(predictions, labels) {
  x <- as.data.frame(predictions, stringsAsFactors = FALSE); y <- as.data.frame(labels, stringsAsFactors = FALSE)
  if (any(c("K", "P", "mature") %in% names(x))) stop("Prediction artifact contains evaluated labels.", call. = FALSE)
  ix <- match(x$season, y$season); if (anyNA(ix)) stop("Missing truth labels after seal.", call. = FALSE)
  if (anyDuplicated(x[c("season", "origin")])) stop("Duplicate scoring origins.", call. = FALSE)
  metrics <- lapply(seq_len(nrow(x)), function(i) {
    sc <- sp_score_one(x$pmf[[i]], y$K[ix[i]], y$P[ix[i]])
    data.frame(season = x$season[i], origin = x$origin[i], K = y$K[ix[i]], P = y$P[ix[i]],
      W = x$W[i], pre_post = if (y$K[ix[i]] > x$origin[i]) "pre" else if (y$K[ix[i]] < x$origin[i]) "post" else "at",
      origin_band = if (x$origin[i] <= 20) "13-20" else if (x$origin[i] <= 30) "21-30" else "31-W", as.list(sc), stringsAsFactors = FALSE)
  })
  detail <- do.call(rbind, metrics); numeric_names <- names(detail)[vapply(detail, is.numeric, logical(1))]
  numeric_names <- setdiff(numeric_names, c("origin", "K", "P", "W"))
  season <- aggregate(detail[numeric_names], list(season = detail$season), mean, na.rm = TRUE)
  pooled <- data.frame(metric = numeric_names, mean_equal_season = vapply(numeric_names, function(nm) mean(season[[nm]], na.rm = TRUE), numeric(1)))
  list(detail = detail, per_season = season, pooled = pooled,
       by_origin_band = split(detail, detail$origin_band), by_phase = split(detail, detail$pre_post))
}

sp_passed_calibration <- function(pi, K, t, bins = c(0, .2, .4, .6, .8, 1)) {
  if (length(pi) != length(K) || length(K) != length(t) || any(!is.finite(pi)) || any(pi < 0 | pi > 1)) stop("Invalid passed-gate calibration inputs.", call. = FALSE)
  y <- as.integer(K <= t); b <- cut(pi, bins, include.lowest = TRUE, right = TRUE)
  data.frame(bin = levels(b), n = vapply(levels(b), function(k) sum(b == k), integer(1)),
    predicted = vapply(levels(b), function(k) if (any(b == k)) mean(pi[b == k]) else NA_real_, numeric(1)),
    observed = vapply(levels(b), function(k) if (any(b == k)) mean(y[b == k]) else NA_real_, numeric(1)))
}

sp_horizon_cdf_calibration <- function(predictions, labels, horizons = c(1L, 2L, 4L)) {
  x <- as.data.frame(predictions); y <- as.data.frame(labels); ix <- match(x$season, y$season)
  out <- list()
  for (h in horizons) for (i in seq_len(nrow(x))) {
    p <- x$pmf[[i]]; support <- as.integer(names(p)); out[[length(out) + 1L]] <- data.frame(season = x$season[i], origin = x$origin[i], horizon = h,
      predicted = sum(p[support <= x$origin[i] + h]), observed = as.numeric(y$K[ix[i]] <= x$origin[i] + h))
  }
  do.call(rbind, out)
}

sp_paired_season_bootstrap <- function(detail_a, detail_b, metric = "log_loss", replicates = 2000L, seed = 20260930L) {
  a <- aggregate(detail_a[[metric]], list(season = detail_a$season), mean); b <- aggregate(detail_b[[metric]], list(season = detail_b$season), mean)
  m <- merge(a, b, by = "season", suffixes = c("_a", "_b")); d <- m[[2L]] - m[[3L]]
  set.seed(seed); draws <- replicate(replicates, mean(sample(d, length(d), replace = TRUE)))
  c(estimate = mean(d), lower = unname(stats::quantile(draws, .025)), upper = unname(stats::quantile(draws, .975)))
}

sp_peak_acceptance <- function(logloss_gain_fraction, bootstrap_upper_loss_difference, median_mae, incumbent_median_mae,
                               equal_season_coverage80, mean_width80, empirical_mean_width80, worst_season_loss_difference) {
  c(loss_gain = logloss_gain_fraction >= .05, paired_bootstrap = bootstrap_upper_loss_difference <= 0,
    median_mae = median_mae <= incumbent_median_mae + .25, coverage = equal_season_coverage80 >= .75 && equal_season_coverage80 <= .90,
    width = mean_width80 <= empirical_mean_width80, season_guard = worst_season_loss_difference <= .10)
}

sp_m2_acceptance <- function(mean_h1_h2_nll_gain, h1_deterioration, h2_deterioration, max_season_horizon_deterioration,
                             forecast_coverage_loss) {
  c(gain = mean_h1_h2_nll_gain >= .00025, h1 = h1_deterioration <= .001, h2 = h2_deterioration <= .001,
    season = max_season_horizon_deterioration <= .002, coverage = forecast_coverage_loss <= 0)
}

sp_analytic_threshold_selftest <- function() {
  stopifnot(all(sp_peak_acceptance(.05, 0, 10.25, 10, .75, 8, 8, .1)),
    !sp_peak_acceptance(.0499, 0, 10, 10, .8, 8, 8, .1)[["loss_gain"]],
    all(sp_m2_acceptance(.00025, .001, .001, .002, 0)),
    !sp_m2_acceptance(.000249, .001, .001, .002, 0)[["gain"]])
  invisible(TRUE)
}
