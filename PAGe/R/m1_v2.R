.normalize_m1_v2_amplitude_grid <- function(x) {
  grid <- sort(unique(as.numeric(x)))
  if (length(grid) < 3L || any(!is.finite(grid)) ||
      any(grid <= 0) || any(grid >= 1)) {
    stop("`amplitude_grid` must contain at least three unique finite values strictly inside (0, 1).", call. = FALSE)
  }
  steps <- diff(grid)
  tol <- 1e-10 * max(1, max(abs(grid)))
  if (max(abs(steps - stats::median(steps))) > tol) {
    stop("`amplitude_grid` must be regularly spaced; non-uniform grids require explicit quadrature weights.", call. = FALSE)
  }
  grid
}

#' Fit the M1-v2 peak-relative historical library
#'
#' Fits one retrospective smooth per completed training season, aligns each
#' season to supplied continuous peak truth, normalizes by fitted peak height,
#' and learns two one-component peak-relative shape models: one for future-peak
#' inference and one extending through peak +3 for passage inference.
#'
#' The first shape component is constrained so every admissible deformation
#' retains its maximum at relative time zero. This prevents the shape nuisance
#' from exchanging a time shift for the target peak time.
#'
#' @param data Completed historical surveillance data.
#' @param peak_truth Data frame with `season` and `peak_week_decimal`.
#' @param k Basis dimension for the retrospective GAM smoother.
#' @param grid_step Fine-grid resolution for retrospective smoothing.
#' @param tau_step Peak-relative training grid resolution.
#' @param amplitude_grid Positive candidate peak-amplitude values integrated
#'   out by the timing likelihood. Defaults to the frozen Influenza-A grid.
#' @return A `page_m1_v2_library` object.
fit_m1_v2_library <- function(data, peak_truth, k = 8L, grid_step = 0.01,
                              tau_step = 0.1,
                              amplitude_grid = seq(0.08, 0.44, by = 0.02)) {
  d <- prepare_surveillance_data(data)
  amplitude_grid <- .normalize_m1_v2_amplitude_grid(amplitude_grid)
  if (!is.data.frame(peak_truth)) stop("`peak_truth` must be a data frame.", call. = FALSE)
  req <- c("season", "peak_week_decimal")
  miss <- setdiff(req, names(peak_truth))
  if (length(miss)) stop("`peak_truth` is missing: ", paste(miss, collapse = ", "), ".", call. = FALSE)

  pt <- as.data.frame(peak_truth[, req, drop = FALSE])
  pt$season <- as.character(pt$season)
  pt$peak_week_decimal <- as.numeric(pt$peak_week_decimal)
  if (anyDuplicated(pt$season)) stop("`peak_truth` must contain one row per season.", call. = FALSE)
  if (any(!is.finite(pt$peak_week_decimal))) stop("`peak_week_decimal` must be finite.", call. = FALSE)
  seasons <- sort(unique(as.character(d$season)))
  if (!setequal(seasons, pt$season)) {
    stop("Training data seasons and `peak_truth` seasons must match exactly.", call. = FALSE)
  }
  pt <- pt[match(seasons, pt$season), , drop = FALSE]

  smoothed <- vector("list", length(seasons))
  peak_height <- setNames(numeric(length(seasons)), seasons)
  fitted_peak <- setNames(numeric(length(seasons)), seasons)
  for (i in seq_along(seasons)) {
    s <- seasons[[i]]
    fit <- retrospective_gam_peak_truth(d, season = s, k = k, grid_step = grid_step)
    g <- fit$grid
    truth <- pt$peak_week_decimal[[i]]
    if (abs(fit$peak_week_decimal - truth) > max(0.05, 1.5 * grid_step)) {
      stop(
        "Peak truth for season `", s,
        "` is inconsistent with the configured retrospective smoother; ",
        "M1-v2 requires peak truth generated from the same smoothing spec.",
        call. = FALSE
      )
    }
    g$tau <- g$weekF - truth
    g$p_norm <- g$fitted_p / max(g$fitted_p, na.rm = TRUE)
    smoothed[[i]] <- g[, c("tau", "p_norm"), drop = FALSE]
    peak_height[[s]] <- max(g$fitted_p, na.rm = TRUE)
    fitted_peak[[s]] <- fit$peak_week_decimal
  }
  names(smoothed) <- seasons

  forecast <- .fit_m1_v2_component(
    smoothed, peak_height, tau = seq(-14, 0, by = tau_step),
    amplitude_grid = amplitude_grid
  )
  passage <- .fit_m1_v2_component(
    smoothed, peak_height, tau = seq(-14, 3, by = tau_step),
    amplitude_grid = amplitude_grid
  )

  version <- "m1-v2-lowrank-peak-anchored-v1"
  config <- list(k = as.integer(k), grid_step = grid_step, tau_step = tau_step,
                 amplitude_grid = amplitude_grid)
  data_hash <- digest::digest(d, algo = "sha256")
  truth_hash <- digest::digest(pt, algo = "sha256")
  fitted_hash <- digest::digest(
    list(forecast = forecast, passage = passage, peak_height = peak_height,
         fitted_peak = fitted_peak),
    algo = "sha256"
  )
  library_hash <- digest::digest(
    list(version = version, training_seasons = seasons, config = config,
         data_hash = data_hash, truth_hash = truth_hash, fitted_hash = fitted_hash),
    algo = "sha256"
  )

  structure(list(
    version = version,
    training_seasons = seasons,
    peak_truth = pt,
    fitted_peak = fitted_peak,
    peak_height = peak_height,
    forecast = forecast,
    passage = passage,
    config = config,
    provenance = list(
      coordinate_version = "page-continuous-week-v1",
      data_hash = data_hash,
      truth_hash = truth_hash,
      fitted_hash = fitted_hash,
      library_hash = library_hash
    )
  ), class = "page_m1_v2_library")
}

#' Infer a future peak-time posterior with M1-v2
#'
#' The origin convention is release based: origin `w` means the completed
#' aggregate for interval `[w, w+1)` is available, so the continuous as-of
#' boundary is `w + 1`. This function returns a posterior conditional on the
#' peak still being in the future of that boundary.
#'
#' @param library A `page_m1_v2_library`.
#' @param current_data Current-season surveillance data.
#' @param activation_week Causal M0 detection time `A`.
#' @param origin_week Integer observed-week origin.
#' @param candidate_step Candidate peak-time grid spacing.
#' @param max_future_weeks Maximum future support from the release boundary.
#' @return A `page_m1_v2_forecast` object.
m1_v2_peak_posterior <- function(library, current_data, activation_week,
                                 origin_week, candidate_step = 0.1,
                                 max_future_weeks = 14) {
  .validate_m1_v2_library(library)
  d <- .prepare_m1_v2_current(library, current_data, origin_week)
  .check_m1_v2_scalar(activation_week, "activation_week")
  .check_m1_v2_origin(origin_week)
  .check_m1_v2_scalar(candidate_step, "candidate_step", positive = TRUE)
  .check_m1_v2_scalar(max_future_weeks, "max_future_weeks", positive = TRUE)

  start <- ceiling(activation_week)
  obs <- d[d$weekF >= start & d$weekF <= origin_week, , drop = FALSE]
  if (!nrow(obs)) stop("No observations are available from M0 activation through the origin.", call. = FALSE)

  asof <- origin_week + 1
  lower <- asof + candidate_step / 2
  obs <- .m1_v2_trim_obs_for_candidate_support(obs, library$forecast, lower)
  upper <- min(asof + max_future_weeks,
               min(obs$weekF) - min(library$forecast$tau))
  if (upper < lower) stop("No admissible future peak-time candidates for this prefix.", call. = FALSE)
  candidates <- seq(lower, upper, by = candidate_step)

  posterior <- .m1_v2_grid_posterior(obs, candidates, library$forecast)
  summary <- .summarize_m1_v2_posterior(posterior, asof)

  structure(list(
    version = library$version,
    library_hash = library$provenance$library_hash,
    status = "active",
    season = unique(d$season),
    activation_week = activation_week,
    origin_week = origin_week,
    asof_boundary = asof,
    posterior = posterior,
    summary = summary
  ), class = "page_m1_v2_forecast")
}

#' Infer M1-v2 peak-passage probability
#'
#' Uses the peak-relative library extending through peak +3 and permits the
#' candidate peak to lie in the recent past. `prob_peak_passed` is evaluated at
#' the release boundary `origin_week + 1`.
#'
#' @inheritParams m1_v2_peak_posterior
#' @param max_future_weeks Maximum future candidate support.
#' @return A one-row data frame with passage probabilities plus the underlying
#'   posterior as an attribute named `posterior`.
m1_v2_passage_posterior <- function(library, current_data, activation_week,
                                    origin_week, candidate_step = 0.1,
                                    max_future_weeks = 12) {
  .validate_m1_v2_library(library)
  d <- .prepare_m1_v2_current(library, current_data, origin_week)
  .check_m1_v2_scalar(activation_week, "activation_week")
  .check_m1_v2_origin(origin_week)

  start <- ceiling(activation_week)
  obs <- d[d$weekF >= start & d$weekF <= origin_week, , drop = FALSE]
  if (!nrow(obs)) stop("No observations are available from M0 activation through the origin.", call. = FALSE)

  comp <- library$passage
  asof <- origin_week + 1
  lower <- max(obs$weekF) - max(comp$tau)
  obs <- .m1_v2_trim_obs_for_candidate_support(obs, comp, lower)
  upper <- min(asof + max_future_weeks,
               min(obs$weekF) - min(comp$tau))
  if (upper < lower) stop("No admissible passage candidates for this prefix.", call. = FALSE)
  candidates <- seq(lower, upper, by = candidate_step)
  posterior <- .m1_v2_grid_posterior(obs, candidates, comp)
  w <- posterior$probability
  T <- posterior$peak_week_decimal

  out <- data.frame(
    season = unique(d$season),
    activation_week = activation_week,
    origin_week = origin_week,
    asof_boundary = asof,
    prob_peak_passed = sum(w[T <= asof]),
    prob_peak_within_1w = sum(w[T > asof & T <= asof + 1]),
    prob_peak_within_2w = sum(w[T > asof & T <= asof + 2]),
    prob_peak_within_3w = sum(w[T > asof & T <= asof + 3]),
    stringsAsFactors = FALSE
  )
  attr(out, "posterior") <- posterior
  out
}

#' Decide whether M1-v2 peak passage is confirmed
#'
#' Confirmation uses two independent forms of causal evidence. The fast branch
#' requires a high passage posterior and an immediate observed decline. The
#' sustained branch permits a lower passage posterior only after two consecutive
#' declines and a material drop from the post-activation running maximum.
#'
#' @param passage_history Data frame containing at least `origin_week` and
#'   `prob_peak_passed`; typically rows returned by
#'   `m1_v2_passage_posterior()` across sequential origins.
#' @param current_data Current-season surveillance data through the latest
#'   origin.
#' @param activation_week Causal M0 detection time.
#' @param high_threshold Minimum posterior passage probability for the fast
#'   branch. Must be at least 0.9 by contract.
#' @param low_threshold Minimum posterior passage probability for the sustained
#'   decline branch.
#' @param drop_fraction Required fractional decline from the post-activation
#'   running maximum for the sustained branch.
#' @param fast_drop_fraction Optional fractional decline from the post-activation
#'   running maximum required by the one-week fast branch. The validated M1-C
#'   rule uses 0: safety comes from a high passage posterior (>=0.95) plus an
#'   actual immediate decline. Positive values are retained only for controlled
#'   sensitivity experiments.
#' @param min_post_activation Minimum integer observed weeks after activation
#'   before passage can be confirmed.
#' @return A one-row data frame describing the passage state.
m1_v2_passage_decision <- function(passage_history, current_data,
                                   activation_week, high_threshold = 0.95,
                                   low_threshold = 0.10,
                                   drop_fraction = 0.05,
                                   fast_drop_fraction = 0,
                                   min_post_activation = 4L) {
  if (!is.data.frame(passage_history)) stop("`passage_history` must be a data frame.", call. = FALSE)
  req <- c("origin_week", "prob_peak_passed")
  miss <- setdiff(req, names(passage_history))
  if (length(miss)) stop("`passage_history` is missing: ", paste(miss, collapse = ", "), ".", call. = FALSE)
  .check_m1_v2_scalar(activation_week, "activation_week")
  if (!is.numeric(high_threshold) || length(high_threshold) != 1L ||
      !is.finite(high_threshold) || high_threshold < 0.95 || high_threshold > 1) {
    stop("`high_threshold` must be one finite value in [0.95, 1].", call. = FALSE)
  }
  for (nm in c("low_threshold", "drop_fraction", "fast_drop_fraction")) {
    val <- get(nm)
    if (!is.numeric(val) || length(val) != 1L || !is.finite(val) || val < 0 || val > 1) {
      stop("`", nm, "` must be one finite value in [0, 1].", call. = FALSE)
    }
  }
  if (length(min_post_activation) != 1L || !is.finite(min_post_activation) ||
      min_post_activation < 0 || min_post_activation != floor(min_post_activation)) {
    stop("`min_post_activation` must be one non-negative integer.", call. = FALSE)
  }

  h <- passage_history[order(passage_history$origin_week), , drop = FALSE]
  latest <- h[nrow(h), , drop = FALSE]
  origin <- as.numeric(latest$origin_week)
  p_passed <- as.numeric(latest$prob_peak_passed)

  d <- prepare_surveillance_data(current_data)
  seasons <- unique(d$season)
  if (length(seasons) != 1L) stop("`current_data` must contain exactly one season.", call. = FALSE)
  d <- d[d$weekF <= origin & d$weekF >= ceiling(activation_week), , drop = FALSE]
  d <- d[order(d$weekF), , drop = FALSE]

  eligible <- origin >= ceiling(activation_week) + min_post_activation
  immediate_down <- nrow(d) >= 2L &&
    diff(tail(d$weekF, 2L)) == 1 &&
    tail(d$p, 1L) < d$p[nrow(d) - 1L]
  two_down <- nrow(d) >= 3L &&
    all(diff(tail(d$weekF, 3L)) == 1) &&
    all(diff(tail(d$p, 3L)) < 0)
  drop <- if (nrow(d)) 1 - tail(d$p, 1L) / max(d$p, na.rm = TRUE) else NA_real_

  fast <- eligible && is.finite(p_passed) && p_passed >= high_threshold &&
    immediate_down && is.finite(drop) && drop >= fast_drop_fraction
  sustained <- eligible && is.finite(p_passed) && p_passed >= low_threshold &&
    two_down && is.finite(drop) && drop >= drop_fraction
  confirmed <- fast || sustained
  branch <- if (fast) "high_posterior_decline" else if (sustained) "sustained_decline" else NA_character_

  data.frame(
    season = seasons,
    origin_week = origin,
    asof_boundary = origin + 1,
    prob_peak_passed = p_passed,
    immediate_decline = immediate_down,
    sustained_two_week_decline = two_down,
    drop_from_post_activation_max = drop,
    peak_reached_or_passed = confirmed,
    confirmation_branch = branch,
    stringsAsFactors = FALSE
  )
}




.m1_v2_activation_payload <- function(x) {
  req <- c("season", "activation_origin_week", "activation_week_decimal")
  if (!is.data.frame(x) || any(!req %in% names(x))) {
    stop("M1-v2 activation payload is missing required fields.", call. = FALSE)
  }
  z <- data.frame(
    season = as.character(x$season),
    activation_origin_week = as.integer(round(as.numeric(x$activation_origin_week))),
    activation_week_decimal = as.numeric(x$activation_week_decimal),
    stringsAsFactors = FALSE
  )
  z <- z[order(z$season), , drop = FALSE]
  rownames(z) <- NULL
  z
}


#' Construct governed M1-v2 activations from an M0 LOSO result
#'
#' Converts the held-out detections from `loso_M0v2()` into the only activation
#' table accepted by governed M1-v2 training. Fold identities, held-out season
#' names, detection values, and the M0 LOSO context identity are validated and
#' bound into a deterministic provenance ID.
#'
#' @param m0_loso Result returned by `loso_M0v2()`.
#' @return A `page_m1_v2_activation_table` data frame.
m1_v2_activation_table_from_m0_loso <- function(m0_loso) {
  if (!inherits(m0_loso, "page_m0_loso_result") ||
      is.null(m0_loso$folds) || is.null(m0_loso$compare) ||
      is.null(m0_loso$context_id)) {
    stop("`m0_loso` must be a governed `page_m0_loso_result` from `loso_M0v2()`.", call. = FALSE)
  }
  folds <- m0_loso$folds
  fold_names <- names(folds)
  if (is.null(fold_names) || !length(fold_names) || any(!nzchar(fold_names))) {
    stop("M0 LOSO folds must be named by held-out season.", call. = FALSE)
  }
  cmp <- as.data.frame(m0_loso$compare)
  req <- c("season", "iWeek_hat", "iWeek_hatF")
  miss <- setdiff(req, names(cmp))
  if (length(miss)) {
    stop("M0 LOSO compare table is missing: ", paste(miss, collapse = ", "), ".", call. = FALSE)
  }
  cmp$season <- as.character(cmp$season)
  if (anyDuplicated(cmp$season) || !setequal(cmp$season, fold_names)) {
    stop("M0 LOSO fold names and compare seasons do not match exactly.", call. = FALSE)
  }
  cmp <- cmp[match(fold_names, cmp$season), , drop = FALSE]
  if ("detection_failed" %in% names(cmp) && any(cmp$detection_failed %in% TRUE)) {
    stop("M0 LOSO contains failed held-out detections; cannot build M1-v2 activations.", call. = FALSE)
  }
  if (any(!is.finite(cmp$iWeek_hat)) || any(!is.finite(cmp$iWeek_hatF))) {
    stop("M0 LOSO held-out activation coordinates must be finite.", call. = FALSE)
  }
  for (season in fold_names) {
    fold <- folds[[season]]
    if (!is.list(fold) || !identical(as.character(fold$season), season) || is.null(fold$compare)) {
      stop("Malformed M0 LOSO fold for season `", season, "`.", call. = FALSE)
    }
    fc <- as.data.frame(fold$compare)
    fc <- fc[as.character(fc$season) == season, , drop = FALSE]
    if (nrow(fc) != 1L || !all(c("iWeek_hat", "iWeek_hatF") %in% names(fc)) ||
        !isTRUE(all.equal(as.numeric(fc$iWeek_hat), as.numeric(cmp$iWeek_hat[cmp$season == season]))) ||
        !isTRUE(all.equal(as.numeric(fc$iWeek_hatF), as.numeric(cmp$iWeek_hatF[cmp$season == season])))) {
      stop("M0 LOSO fold/aggregate activation mismatch for season `", season, "`.", call. = FALSE)
    }
  }
  provenance_id <- digest::digest(
    list(
      context_id = m0_loso$context_id,
      folds = lapply(folds, function(z) list(
        season = z$season,
        best_params = z$best_params,
        compare = z$compare
      )),
      compare = cmp
    ),
    algo = "sha256"
  )
  out <- data.frame(
    season = cmp$season,
    activation_origin_week = as.integer(round(cmp$iWeek_hat)),
    activation_week_decimal = as.numeric(cmp$iWeek_hatF),
    stringsAsFactors = FALSE
  )
  attr(out, "m0_loso_context_id") <- as.character(m0_loso$context_id)
  attr(out, "activation_provenance_id") <- provenance_id
  attr(out, "activation_payload_hash") <- digest::digest(.m1_v2_activation_payload(out), algo = "sha256")
  class(out) <- c("page_m1_v2_activation_table", class(out))
  out
}

.validate_m1_v2_activation_table <- function(activation_table, training_seasons) {
  if (!inherits(activation_table, "page_m1_v2_activation_table")) {
    stop(
      "`activation_table` must be created by `m1_v2_activation_table_from_m0_loso()`; ",
      "raw activation data frames are not accepted for governed M1-v2 training.",
      call. = FALSE
    )
  }
  req <- c("season", "activation_origin_week", "activation_week_decimal")
  miss <- setdiff(req, names(activation_table))
  if (length(miss)) stop("`activation_table` is missing required fields.", call. = FALSE)
  act <- as.data.frame(activation_table[, req, drop = FALSE])
  act$season <- as.character(act$season)
  if (anyDuplicated(act$season) || !setequal(act$season, training_seasons)) {
    stop("M0 activation seasons must match the M1-v2 training season universe exactly.", call. = FALSE)
  }
  act <- act[match(training_seasons, act$season), , drop = FALSE]
  act$activation_origin_week <- as.numeric(act$activation_origin_week)
  act$activation_week_decimal <- as.numeric(act$activation_week_decimal)
  if (any(!is.finite(act$activation_origin_week)) ||
      any(abs(act$activation_origin_week - round(act$activation_origin_week)) > 1e-8) ||
      any(!is.finite(act$activation_week_decimal))) {
    stop("Historical M0 activation coordinates are invalid.", call. = FALSE)
  }
  provenance_id <- attr(activation_table, "activation_provenance_id", exact = TRUE)
  context_id <- attr(activation_table, "m0_loso_context_id", exact = TRUE)
  payload_hash <- attr(activation_table, "activation_payload_hash", exact = TRUE)
  if (!is.character(provenance_id) || length(provenance_id) != 1L || !nzchar(provenance_id) ||
      !is.character(context_id) || length(context_id) != 1L || !nzchar(context_id) ||
      !is.character(payload_hash) || length(payload_hash) != 1L || !nzchar(payload_hash)) {
    stop("M0 activation provenance is missing.", call. = FALSE)
  }
  current_payload_hash <- digest::digest(
    .m1_v2_activation_payload(activation_table), algo = "sha256"
  )
  if (!identical(payload_hash, current_payload_hash)) {
    stop("M0 activation payload integrity check failed.", call. = FALSE)
  }
  list(data = act, provenance_id = provenance_id, context_id = context_id,
       payload_hash = payload_hash)
}

#' Fit the M1-v2 early-bias calibrator
#'
#' Learns one scalar timing-location correction entirely inside the historical
#' training set. For each historical season, an inner M1-v2 library is trained
#' on all other seasons, predictions are generated at the first few primary
#' post-M0 origins, and the season-balanced early-weighted mean signed error is
#' estimated. The returned offset is the negative of that mean bias.
#'
#' This calibrator is intentionally low dimensional. It does not modify M1-C
#' passage probabilities or the shape of the M1-F posterior.
#'
#' @param library Full historical `page_m1_v2_library` to which the calibrator
#'   will be attached conceptually.
#' @param data The same completed historical surveillance data used to fit
#'   `library`.
#' @param peak_truth The same peak-truth table used to fit `library`.
#' @param activation_table Data frame with one row per training season and
#'   columns `season`, `activation_origin_week`, and `activation_week_decimal`.
#'   Activation values must themselves be cross-fitted/causal historical M0
#'   outputs; this function does not generate M0 values.
#' @param n_origins Number of earliest primary origins per inner season used for
#'   calibration. Default 4 is the frozen exploratory choice.
#' @param candidate_step Candidate peak-time grid spacing for inner predictions.
#' @return A `page_m1_v2_calibrator` object.
fit_m1_v2_bias_calibrator <- function(library, data, peak_truth,
                                      activation_table, n_origins = 4L,
                                      candidate_step = 0.2) {
  .validate_m1_v2_library(library)
  d <- prepare_surveillance_data(data)
  if (digest::digest(d, algo = "sha256") != library$provenance$data_hash) {
    stop("`data` does not match the training data used to fit `library`.", call. = FALSE)
  }
  if (!is.data.frame(peak_truth)) stop("`peak_truth` must be a data frame.", call. = FALSE)
  req_truth <- c("season", "peak_week_decimal")
  miss_truth <- setdiff(req_truth, names(peak_truth))
  if (length(miss_truth)) stop("`peak_truth` is missing: ", paste(miss_truth, collapse = ", "), ".", call. = FALSE)
  pt <- as.data.frame(peak_truth[, req_truth, drop = FALSE])
  pt$season <- as.character(pt$season)
  pt$peak_week_decimal <- as.numeric(pt$peak_week_decimal)
  pt <- pt[match(library$training_seasons, pt$season), , drop = FALSE]
  if (anyNA(pt$season) || digest::digest(pt, algo = "sha256") != library$provenance$truth_hash) {
    stop("`peak_truth` does not match the truth used to fit `library`.", call. = FALSE)
  }

  activation_valid <- .validate_m1_v2_activation_table(
    activation_table, library$training_seasons
  )
  act <- activation_valid$data
  if (length(n_origins) != 1L || !is.finite(n_origins) || n_origins < 1 || n_origins != floor(n_origins)) {
    stop("`n_origins` must be one positive integer.", call. = FALSE)
  }
  .check_m1_v2_scalar(candidate_step, "candidate_step", positive = TRUE)

  rows <- list()
  seasons <- library$training_seasons
  cfg <- library$config
  for (heldout in seasons) {
    inner_seasons <- setdiff(seasons, heldout)
    inner_data <- d[d$season %in% inner_seasons, , drop = FALSE]
    inner_truth <- pt[pt$season %in% inner_seasons, , drop = FALSE]
    inner_library <- fit_m1_v2_library(
      inner_data, inner_truth,
      k = cfg$k, grid_step = cfg$grid_step, tau_step = cfg$tau_step,
      amplitude_grid = cfg$amplitude_grid %||% seq(0.08, 0.44, by = 0.02)
    )
    a <- act[act$season == heldout, , drop = FALSE]
    truth <- pt$peak_week_decimal[pt$season == heldout]
    all_origins <- seq(a$activation_origin_week, round(truth), by = 1)
    origins <- head(all_origins, n_origins)
    heldout_data <- d[d$season == heldout, , drop = FALSE]
    for (origin in origins) {
      fit <- m1_v2_peak_posterior(
        inner_library, heldout_data,
        activation_week = a$activation_week_decimal,
        origin_week = origin,
        candidate_step = candidate_step
      )
      pred <- fit$summary$peak_mean[[1L]]
      rows[[length(rows) + 1L]] <- data.frame(
        season = heldout,
        origin_week = origin,
        activation_origin_week = a$activation_origin_week,
        prediction_peak_mean = pred,
        truth_peak_decimal = truth,
        signed_error = pred - truth,
        weight_early = exp(-(0.1 * (origin - a$activation_origin_week))^2),
        stringsAsFactors = FALSE
      )
    }
  }
  inner <- do.call(rbind, rows)
  inner$weight_season_balanced <- ave(
    inner$weight_early, inner$season,
    FUN = function(v) v / sum(v)
  )
  mean_bias <- sum(inner$weight_season_balanced * inner$signed_error) /
    sum(inner$weight_season_balanced)
  offset <- -mean_bias
  per_season <- do.call(rbind, lapply(split(inner, inner$season), function(z) {
    data.frame(
      season = z$season[[1L]],
      mean_signed_error = sum(z$weight_early * z$signed_error) / sum(z$weight_early),
      n_origins = nrow(z),
      stringsAsFactors = FALSE
    )
  }))

  structure(list(
    version = "m1-v2-early-bias-calibrator-v1",
    library_hash = library$provenance$library_hash,
    training_seasons = seasons,
    mean_signed_bias = mean_bias,
    offset_week = offset,
    n_origins = as.integer(n_origins),
    candidate_step = candidate_step,
    per_season = per_season,
    inner_predictions = inner,
    provenance = list(
      activation_provenance_id = activation_valid$provenance_id,
      activation_payload_hash = activation_valid$payload_hash,
      m0_loso_context_id = activation_valid$context_id,
      calibration_rule = "first-n-primary-origins-season-balanced-early-weighted-mean-bias"
    )
  ), class = "page_m1_v2_calibrator")
}


#' Fit the M1-v2 passage-confirmation policy
#'
#' Selects the hybrid M1-C thresholds using only inner cross-fitted historical
#' passage posteriors from the supplied training seasons. Selection prioritizes
#' false-early confirmations, then their magnitude, misses by peak+2, and delay.
#'
#' @param library Full historical `page_m1_v2_library`.
#' @param data Completed historical surveillance data used by `library`.
#' @param peak_truth Peak truth used by `library`.
#' @param activation_table Cross-fitted historical M0 activation table; same
#'   schema as `fit_m1_v2_bias_calibrator()`.
#' @param candidate_step Candidate peak-time grid spacing in inner passage
#'   replays.
#' @param high_thresholds,low_thresholds,drop_fractions,min_post_activation
#'   Predeclared candidate policy grid.
#' @param fast_drop_fraction Optional extra drop floor for the one-week fast
#'   branch. Default 0 reproduces the validated rule family.
#' @return A `page_m1_v2_passage_policy`.
fit_m1_v2_passage_policy <- function(
    library, data, peak_truth, activation_table,
    candidate_step = 0.2,
    high_thresholds = 0.95,
    low_thresholds = c(0.10, 0.20, 0.30, 0.40),
    drop_fractions = c(0.03, 0.05, 0.08, 0.10),
    fast_drop_fraction = 0,
    min_post_activation = c(3L, 4L)) {
  .validate_m1_v2_library(library)
  d <- prepare_surveillance_data(data)
  if (digest::digest(d, algo = "sha256") != library$provenance$data_hash) {
    stop("`data` does not match the training data used to fit `library`.", call. = FALSE)
  }
  req_truth <- c("season", "peak_week_decimal")
  if (!is.data.frame(peak_truth) || any(!req_truth %in% names(peak_truth))) {
    stop("`peak_truth` must contain `season` and `peak_week_decimal`.", call. = FALSE)
  }
  pt <- as.data.frame(peak_truth[, req_truth, drop = FALSE])
  pt$season <- as.character(pt$season)
  pt$peak_week_decimal <- as.numeric(pt$peak_week_decimal)
  pt <- pt[match(library$training_seasons, pt$season), , drop = FALSE]
  if (anyNA(pt$season) || digest::digest(pt, algo = "sha256") != library$provenance$truth_hash) {
    stop("`peak_truth` does not match the truth used to fit `library`.", call. = FALSE)
  }
  activation_valid <- .validate_m1_v2_activation_table(
    activation_table, library$training_seasons
  )
  act <- activation_valid$data
  .check_m1_v2_scalar(candidate_step, "candidate_step", positive = TRUE)
  if (any(!is.finite(high_thresholds)) || any(high_thresholds < 0.95) || any(high_thresholds > 1)) {
    stop("`high_thresholds` must lie in [0.95, 1].", call. = FALSE)
  }
  if (any(!is.finite(low_thresholds)) || any(low_thresholds < 0) || any(low_thresholds > 1) ||
      any(!is.finite(drop_fractions)) || any(drop_fractions < 0) || any(drop_fractions > 1)) {
    stop("Low thresholds and drop fractions must lie in [0, 1].", call. = FALSE)
  }
  if (!is.numeric(fast_drop_fraction) || length(fast_drop_fraction) != 1L ||
      !is.finite(fast_drop_fraction) || fast_drop_fraction < 0 || fast_drop_fraction > 1) {
    stop("`fast_drop_fraction` must be one finite value in [0, 1].", call. = FALSE)
  }

  history_rows <- list()
  seasons <- library$training_seasons
  cfg <- library$config
  policy_evaluation_late_weeks <- 6L
  for (heldout in seasons) {
    inner_seasons <- setdiff(seasons, heldout)
    inner_library <- fit_m1_v2_library(
      d[d$season %in% inner_seasons, , drop = FALSE],
      pt[pt$season %in% inner_seasons, , drop = FALSE],
      k = cfg$k, grid_step = cfg$grid_step, tau_step = cfg$tau_step,
      amplitude_grid = cfg$amplitude_grid %||% seq(0.08, 0.44, by = 0.02)
    )
    a <- act[act$season == heldout, , drop = FALSE]
    truth <- pt$peak_week_decimal[pt$season == heldout]
    truth_confirm <- ceiling(truth) - 1
    held <- d[d$season == heldout, , drop = FALSE]
    last_origin <- min(max(held$weekF), truth_confirm + policy_evaluation_late_weeks)
    if (a$activation_origin_week > last_origin) next
    for (origin in seq(a$activation_origin_week, last_origin, by = 1)) {
      prefix <- held[held$weekF <= origin, , drop = FALSE]
      pp <- m1_v2_passage_posterior(
        inner_library, prefix,
        activation_week = a$activation_week_decimal,
        origin_week = origin,
        candidate_step = candidate_step
      )
      post_act <- prefix[prefix$weekF >= ceiling(a$activation_week_decimal), , drop = FALSE]
      post_act <- post_act[order(post_act$weekF), , drop = FALSE]
      immediate <- nrow(post_act) >= 2L &&
        diff(tail(post_act$weekF, 2L)) == 1 &&
        tail(post_act$p, 1L) < post_act$p[nrow(post_act) - 1L]
      two_down <- nrow(post_act) >= 3L &&
        all(diff(tail(post_act$weekF, 3L)) == 1) &&
        all(diff(tail(post_act$p, 3L)) < 0)
      drop <- if (nrow(post_act)) 1 - tail(post_act$p, 1L) / max(post_act$p) else NA_real_
      history_rows[[length(history_rows) + 1L]] <- data.frame(
        season = heldout,
        origin_week = origin,
        activation_origin_week = a$activation_origin_week,
        activation_week_decimal = a$activation_week_decimal,
        truth_confirm = truth_confirm,
        prob_peak_passed = pp$prob_peak_passed,
        immediate_decline = immediate,
        sustained_two_week_decline = two_down,
        drop_from_post_activation_max = drop,
        stringsAsFactors = FALSE
      )
    }
  }
  history <- do.call(rbind, history_rows)
  if (is.null(history) || !nrow(history)) stop("No inner passage histories were generated.", call. = FALSE)

  grid <- expand.grid(
    high_threshold = sort(unique(high_thresholds)),
    low_threshold = sort(unique(low_thresholds)),
    drop_fraction = sort(unique(drop_fractions)),
    min_post_activation = sort(unique(as.integer(min_post_activation))),
    KEEP.OUT.ATTRS = FALSE,
    stringsAsFactors = FALSE
  )
  grid$policy_id <- seq_len(nrow(grid))
  eval_rows <- list()
  for (i in seq_len(nrow(grid))) {
    policy <- grid[i, , drop = FALSE]
    for (season in seasons) {
      z <- history[history$season == season, , drop = FALSE]
      z <- z[order(z$origin_week), , drop = FALSE]
      confirm <- NA_real_
      branch <- NA_character_
      for (j in seq_len(nrow(z))) {
        eligible <- z$origin_week[j] >= ceiling(z$activation_week_decimal[j]) +
          policy$min_post_activation
        if (!eligible) next
        fast <- z$prob_peak_passed[j] >= policy$high_threshold &&
          isTRUE(z$immediate_decline[j]) &&
          is.finite(z$drop_from_post_activation_max[j]) &&
          z$drop_from_post_activation_max[j] >= fast_drop_fraction
        sustained <- z$prob_peak_passed[j] >= policy$low_threshold &&
          isTRUE(z$sustained_two_week_decline[j]) &&
          is.finite(z$drop_from_post_activation_max[j]) &&
          z$drop_from_post_activation_max[j] >= policy$drop_fraction
        if (fast || sustained) {
          confirm <- z$origin_week[j]
          branch <- if (fast) "high_posterior_decline" else "sustained_decline"
          break
        }
      }
      tc <- unique(z$truth_confirm)
      eval_rows[[length(eval_rows) + 1L]] <- data.frame(
        policy_id = policy$policy_id,
        season = season,
        confirm_origin = confirm,
        branch = branch,
        truth_confirm = tc,
        false_early = is.finite(confirm) && confirm < tc,
        early_weeks = if (is.finite(confirm)) max(tc - confirm, 0) else 0,
        delay = if (is.finite(confirm)) max(confirm - tc, 0) else NA_real_,
        miss_by_peak2 = !is.finite(confirm) || confirm > tc + 2,
        stringsAsFactors = FALSE
      )
    }
  }
  evaluation <- merge(do.call(rbind, eval_rows), grid, by = "policy_id", sort = FALSE)
  score_rows <- do.call(rbind, lapply(split(evaluation, evaluation$policy_id), function(z) {
    data.frame(
      policy_id = z$policy_id[[1L]],
      n_false_early = sum(z$false_early),
      early_weeks_total = sum(z$early_weeks),
      n_miss_by_peak2 = sum(z$miss_by_peak2),
      mean_delay = mean(ifelse(
        is.finite(z$delay), z$delay, policy_evaluation_late_weeks + 1
      )),
      high_threshold = z$high_threshold[[1L]],
      low_threshold = z$low_threshold[[1L]],
      drop_fraction = z$drop_fraction[[1L]],
      min_post_activation = z$min_post_activation[[1L]],
      fast_drop_fraction = fast_drop_fraction,
      stringsAsFactors = FALSE
    )
  }))
  ord <- order(
    score_rows$n_false_early,
    score_rows$early_weeks_total,
    score_rows$n_miss_by_peak2,
    score_rows$mean_delay,
    -score_rows$high_threshold,
    -score_rows$drop_fraction,
    -score_rows$min_post_activation,
    -score_rows$low_threshold
  )
  selected <- score_rows[ord[1L], , drop = FALSE]

  structure(list(
    version = "m1-v2-passage-policy-v1",
    library_hash = library$provenance$library_hash,
    selected = selected,
    scores = score_rows[ord, , drop = FALSE],
    evaluation = evaluation,
    inner_history = history,
    candidate_step = candidate_step,
    provenance = list(
      activation_provenance_id = activation_valid$provenance_id,
      activation_payload_hash = activation_valid$payload_hash,
      m0_loso_context_id = activation_valid$context_id,
      selection_priority = c(
        "n_false_early", "early_weeks_total", "n_miss_by_peak2", "mean_delay"
      ),
      fast_drop_fraction = fast_drop_fraction
    )
  ), class = "page_m1_v2_passage_policy")
}

#' Apply M1-v2 early-bias calibration to forecast summaries
#'
#' Applies the learned scalar location offset to peak-time summary statistics.
#' The raw posterior and all passage probabilities remain unchanged. This is a
#' reporting calibration, not a second posterior update.
#'
#' @param forecast A `page_m1_v2_forecast`.
#' @param calibrator A `page_m1_v2_calibrator` fitted for the same historical
#'   library as `forecast`.
#' @return A one-row data frame containing raw and calibrated peak summaries.
m1_v2_apply_bias_calibration <- function(forecast, calibrator) {
  if (!inherits(forecast, "page_m1_v2_forecast")) {
    stop("`forecast` must be a `page_m1_v2_forecast`.", call. = FALSE)
  }
  if (!inherits(calibrator, "page_m1_v2_calibrator")) {
    stop("`calibrator` must be a `page_m1_v2_calibrator`.", call. = FALSE)
  }
  if (is.null(forecast$library_hash) || !identical(forecast$library_hash, calibrator$library_hash)) {
    stop("Forecast and calibrator were not fitted from the same historical M1-v2 library.", call. = FALSE)
  }
  s <- forecast$summary[1L, , drop = FALSE]
  off <- calibrator$offset_week
  data.frame(
    season = forecast$season,
    origin_week = forecast$origin_week,
    asof_boundary = forecast$asof_boundary,
    calibration_offset_week = off,
    peak_mean_raw = s$peak_mean,
    peak_mean_calibrated = s$peak_mean + off,
    peak_median_raw = s$peak_median,
    peak_median_calibrated = s$peak_median + off,
    peak_map_raw = s$peak_map,
    peak_map_calibrated = s$peak_map + off,
    peak_q05_raw = s$peak_q05,
    peak_q05_calibrated = s$peak_q05 + off,
    peak_q95_raw = s$peak_q95,
    peak_q95_calibrated = s$peak_q95 + off,
    interval_width_90 = s$interval_width_90,
    calibrated_mean_is_future = (s$peak_mean + off) > forecast$asof_boundary,
    stringsAsFactors = FALSE
  )
}



.m1_v2_recompute_library_hash <- function(library) {
  fitted_hash <- digest::digest(
    list(
      forecast = library$forecast,
      passage = library$passage,
      peak_height = library$peak_height,
      fitted_peak = library$fitted_peak
    ),
    algo = "sha256"
  )
  truth_hash <- digest::digest(library$peak_truth, algo = "sha256")
  digest::digest(
    list(
      version = library$version,
      training_seasons = library$training_seasons,
      config = library$config,
      data_hash = library$provenance$data_hash,
      truth_hash = truth_hash,
      fitted_hash = fitted_hash
    ),
    algo = "sha256"
  )
}

.m1_v2_stage_artifact_id <- function(stage) {
  digest::digest(
    list(
      version = stage$version,
      library_hash = .m1_v2_recompute_library_hash(stage$library),
      calibrator_version = stage$calibrator$version,
      calibration_offset = stage$calibrator$offset_week,
      calibrator_provenance = stage$calibrator$provenance,
      passage_policy_version = stage$passage_policy$version,
      passage_policy_selected = stage$passage_policy$selected,
      passage_policy_provenance = stage$passage_policy$provenance,
      training_seasons = sort(as.character(stage$training_seasons)),
      output_contract = stage$output_contract,
      config = stage$config
    ),
    algo = "sha256"
  )
}


#' Validate the M1-v2 to M2 handoff contract
#'
#' Validates the versioned timing-state object emitted by `run_m1_v2_timing()`.
#' This contract is intentionally independent of the current legacy M2 feature
#' path so the redesigned M2 can adopt it without changing M1 semantics.
#'
#' @param x M1-v2 handoff list.
#' @return `x`, invisibly, if valid.
validate_m1_v2_handoff <- function(x) {
  if (!is.list(x)) stop("M1-v2 handoff must be a list.", call. = FALSE)
  if (!identical(x$version, "m1-v2-to-m2-v1")) {
    stop("Unsupported M1-v2 handoff version.", call. = FALSE)
  }
  states <- c(
    "pre_ignition", "active", "future_only", "passage_only",
    "passage_confirmed", "unavailable"
  )
  if (!is.character(x$state) || length(x$state) != 1L || !x$state %in% states) {
    stop("Invalid M1-v2 handoff state.", call. = FALSE)
  }
  if (identical(x$state, "pre_ignition")) return(invisible(x))

  scalar_finite <- function(name, allow_na = FALSE) {
    value <- x[[name]]
    ok <- is.numeric(value) && length(value) == 1L &&
      ((allow_na && is.na(value)) || is.finite(value))
    if (!ok) stop("Invalid M1-v2 handoff field `", name, "`.", call. = FALSE)
  }
  scalar_finite("origin_week")
  scalar_finite("asof_boundary")
  scalar_finite("activation_week")
  scalar_finite("calibration_offset_week")
  scalar_finite("weeks_elapsed_since_activation")
  if (abs(x$asof_boundary - (x$origin_week + 1)) > 1e-8) {
    stop("M1-v2 handoff release boundary must equal origin_week + 1.", call. = FALSE)
  }
  if (abs(x$weeks_elapsed_since_activation - (x$asof_boundary - x$activation_week)) > 1e-8) {
    stop("M1-v2 handoff elapsed timing must equal asof_boundary - activation_week.", call. = FALSE)
  }
  if (!is.character(x$m1_v2_artifact_id) || length(x$m1_v2_artifact_id) != 1L ||
      is.na(x$m1_v2_artifact_id) || !nzchar(x$m1_v2_artifact_id)) {
    stop("M1-v2 handoff artifact identity is missing.", call. = FALSE)
  }

  future_available <- x$state %in% c("active", "future_only") ||
    (identical(x$state, "passage_confirmed") && is.data.frame(x$raw_peak_posterior))
  passage_available <- x$state %in% c("active", "passage_only", "passage_confirmed")

  if (future_available) {
    for (nm in c("raw_peak_mean", "calibrated_peak_mean",
                 "raw_peak_q05", "raw_peak_q95",
                 "calibrated_peak_q05", "calibrated_peak_q95",
                 "peak_q05", "peak_q95",
                 "interval_width_90", "weeks_to_calibrated_peak")) {
      scalar_finite(nm)
    }
    if (abs(x$weeks_to_calibrated_peak - (x$calibrated_peak_mean - x$asof_boundary)) > 1e-8) {
      stop(
        "M1-v2 handoff remaining timing must equal calibrated_peak_mean - asof_boundary.",
        call. = FALSE
      )
    }
    if (!is.data.frame(x$raw_peak_posterior) ||
        !all(c("peak_week_decimal", "probability") %in% names(x$raw_peak_posterior)) ||
        !nrow(x$raw_peak_posterior) ||
        any(!is.finite(x$raw_peak_posterior$peak_week_decimal)) ||
        any(!is.finite(x$raw_peak_posterior$probability)) ||
        any(x$raw_peak_posterior$probability < 0) ||
        abs(sum(x$raw_peak_posterior$probability) - 1) > 1e-6) {
      stop("M1-v2 handoff raw peak posterior is invalid.", call. = FALSE)
    }
    if (any(x$raw_peak_posterior$peak_week_decimal <= x$asof_boundary)) {
      stop("M1-v2 raw M1-F posterior must be strictly future of the release boundary.", call. = FALSE)
    }
    if (x$raw_peak_q05 > x$raw_peak_q95 ||
        x$calibrated_peak_q05 > x$calibrated_peak_q95 ||
        x$peak_q05 > x$peak_q95 || x$interval_width_90 < 0 ||
        abs((x$raw_peak_q95 - x$raw_peak_q05) - x$interval_width_90) > 1e-8 ||
        abs((x$calibrated_peak_q95 - x$calibrated_peak_q05) - x$interval_width_90) > 1e-8) {
      stop("M1-v2 handoff interval is invalid.", call. = FALSE)
    }
    if (!is.logical(x$calibrated_mean_is_future) ||
        length(x$calibrated_mean_is_future) != 1L ||
        is.na(x$calibrated_mean_is_future)) {
      stop("M1-v2 handoff `calibrated_mean_is_future` must be one logical value.", call. = FALSE)
    }
  } else {
    if (!is.null(x$raw_peak_posterior)) {
      stop("M1-v2 handoff without M1-F availability must not carry a raw future posterior.", call. = FALSE)
    }
    for (nm in c("raw_peak_mean", "calibrated_peak_mean",
                 "raw_peak_q05", "raw_peak_q95",
                 "calibrated_peak_q05", "calibrated_peak_q95",
                 "peak_q05", "peak_q95",
                 "interval_width_90", "weeks_to_calibrated_peak")) {
      scalar_finite(nm, allow_na = TRUE)
    }
    if (!is.logical(x$calibrated_mean_is_future) ||
        length(x$calibrated_mean_is_future) != 1L ||
        !is.na(x$calibrated_mean_is_future)) {
      stop("Unavailable M1-F handoff must set `calibrated_mean_is_future = NA`.", call. = FALSE)
    }
  }

  probs <- c(
    x$prob_peak_passed, x$prob_peak_within_1w,
    x$prob_peak_within_2w, x$prob_peak_within_3w
  )
  if (passage_available) {
    if (length(probs) != 4L || any(!is.finite(probs)) ||
        any(probs < 0) || any(probs > 1)) {
      stop("M1-v2 handoff passage probabilities must lie in [0, 1].", call. = FALSE)
    }
    if (!(x$prob_peak_within_1w <= x$prob_peak_within_2w + 1e-12 &&
          x$prob_peak_within_2w <= x$prob_peak_within_3w + 1e-12)) {
      stop("M1-v2 handoff within-horizon probabilities must be monotone.", call. = FALSE)
    }
  } else {
    if (length(probs) != 4L || any(!is.na(probs))) {
      stop("M1-v2 handoff without M1-C availability must set passage probabilities to NA.", call. = FALSE)
    }
  }

  if (identical(x$state, "passage_confirmed")) {
    scalar_finite("locked_peak_week")
    scalar_finite("locked_at_origin")
  }
  invisible(x)
}


.fit_m1_v2_component <- function(smoothed, peak_height, tau, amplitude_grid) {
  seasons <- names(smoothed)
  X <- matrix(NA_real_, nrow = length(seasons), ncol = length(tau),
              dimnames = list(seasons, NULL))
  for (i in seq_along(seasons)) {
    z <- smoothed[[seasons[[i]]]]
    X[i, ] <- stats::approx(z$tau, z$p_norm, xout = tau, rule = 1)$y
  }
  if (anyNA(X)) stop("Historical seasons do not fully support the requested M1-v2 peak-relative domain.", call. = FALSE)
  pc <- stats::prcomp(X, center = TRUE, scale. = FALSE)
  mean_curve <- pc$center
  loading <- pc$rotation[, 1L]
  scores <- pc$x[, 1L]
  sign_anchor <- which.max(abs(loading))
  if (loading[[sign_anchor]] < 0) {
    loading <- -loading
    scores <- -scores
  }
  recon <- sweep(outer(scores, loading), 2L, mean_curve, "+")
  residual_sd <- pmax(apply(X - recon, 2L, stats::sd), 0.025)
  sd_c <- max(stats::sd(scores), 0.2)
  bounds <- .m1_v2_pc_bounds(tau, mean_curve, loading, sd_c)
  if (anyNA(bounds) || bounds[[1L]] >= bounds[[2L]]) stop("M1-v2 PC1 has no admissible peak-anchored coefficient range.", call. = FALSE)
  list(
    tau = tau,
    mean = mean_curve,
    pc1 = loading,
    residual_sd = residual_sd,
    sd_c = sd_c,
    c_lo = bounds[[1L]],
    c_hi = bounds[[2L]],
    mu_logb = mean(log(peak_height[seasons])),
    sd_logb = max(stats::sd(log(peak_height[seasons])), 0.2),
    amplitude_grid = amplitude_grid,
    pc1_variance_fraction = pc$sdev[[1L]]^2 / sum(pc$sdev^2)
  )
}

.m1_v2_pc_bounds <- function(tau, mean_curve, loading, sd_c,
                             span = 2.5, peak_tolerance = 1e-6) {
  i0 <- which.min(abs(tau))
  grid <- seq(-span * sd_c, span * sd_c, length.out = 4001L)
  admissible <- vapply(grid, function(cc) {
    f <- mean_curve + cc * loading
    all(is.finite(f)) && f[[i0]] >= max(f) - peak_tolerance
  }, logical(1))
  if (!any(admissible)) return(c(NA_real_, NA_real_))
  range(grid[admissible])
}



.m1_v2_trim_obs_for_candidate_support <- function(obs, component, lower_candidate) {
  if (!is.data.frame(obs) || !nrow(obs)) {
    stop("M1-v2 requires at least one observation for candidate support.", call. = FALSE)
  }
  support_floor <- lower_candidate + min(component$tau)
  keep <- obs$weekF >= support_floor - 1e-10
  trimmed <- obs[keep, , drop = FALSE]
  if (!nrow(trimmed)) {
    stop("No observations overlap the M1-v2 candidate/template support.", call. = FALSE)
  }
  trimmed
}


.m1_v2_grid_posterior <- function(obs, candidates, component,
                                  b_grid = NULL, n_c = 17L) {
  if (is.null(b_grid)) b_grid <- component$amplitude_grid %||% seq(0.08, 0.44, by = 0.02)
  c_grid <- seq(component$c_lo, component$c_hi, length.out = n_c)
  log_evidence <- vapply(candidates, function(Tcan) {
    .m1_v2_log_evidence(obs, Tcan, component, b_grid, c_grid)
  }, numeric(1))
  ok <- is.finite(log_evidence)
  if (!any(ok)) stop("All M1-v2 candidate peak times are infeasible.", call. = FALSE)
  log_evidence[!ok] <- -Inf
  w <- exp(log_evidence - max(log_evidence))
  w <- w / sum(w)
  data.frame(
    peak_week_decimal = candidates,
    probability = w,
    log_evidence = log_evidence,
    stringsAsFactors = FALSE
  )
}

.m1_v2_log_evidence <- function(obs, Tcan, component, b_grid, c_grid) {
  tau <- obs$weekF - Tcan
  if (any(tau < min(component$tau) | tau > max(component$tau))) return(-Inf)
  f0 <- stats::approx(component$tau, component$mean, xout = tau)$y
  pcv <- stats::approx(component$tau, component$pc1, xout = tau)$y
  rsd <- stats::approx(component$tau, component$residual_sd, xout = tau)$y
  bc <- expand.grid(b = b_grid, c = c_grid)
  F <- matrix(f0, nrow = nrow(bc), ncol = length(f0), byrow = TRUE) + outer(bc$c, pcv)
  F <- pmax(F, 0.001)
  MU <- F * bc$b
  VV <- (outer(bc$b, rsd))^2 +
    MU * (1 - MU) / matrix(pmax(obs$N, 1), nrow = nrow(bc), ncol = nrow(obs), byrow = TRUE)
  VV <- pmax(VV, 1e-6)
  YY <- matrix(obs$p, nrow = nrow(bc), ncol = nrow(obs), byrow = TRUE)
  score <- rowSums((YY - MU)^2 / VV + log(VV)) +
    ((log(bc$b) - component$mu_logb) / component$sd_logb)^2 +
    2 * log(bc$b) +
    (bc$c / component$sd_c)^2
  m <- min(score)
  -0.5 * m + log(sum(exp(-0.5 * (score - m))))
}

.summarize_m1_v2_posterior <- function(posterior, asof) {
  T <- posterior$peak_week_decimal
  w <- posterior$probability
  cdf <- cumsum(w)
  q <- function(prob) T[which(cdf >= prob)[1L]]
  data.frame(
    peak_mean = sum(T * w),
    peak_median = q(0.5),
    peak_map = T[which.max(w)],
    peak_q05 = q(0.05),
    peak_q95 = q(0.95),
    interval_width_90 = q(0.95) - q(0.05),
    prob_peak_within_1w = sum(w[T > asof & T <= asof + 1]),
    prob_peak_within_2w = sum(w[T > asof & T <= asof + 2]),
    prob_peak_within_3w = sum(w[T > asof & T <= asof + 3]),
    stringsAsFactors = FALSE
  )
}

.prepare_m1_v2_current <- function(library, current_data, origin_week) {
  d <- prepare_surveillance_data(current_data)
  seasons <- unique(d$season)
  if (length(seasons) != 1L) stop("`current_data` must contain exactly one season.", call. = FALSE)
  if (seasons %in% library$training_seasons) {
    stop("Current season is present in the M1-v2 training library; refusing leakage-prone inference.", call. = FALSE)
  }
  d <- d[d$weekF <= origin_week, , drop = FALSE]
  if (!nrow(d)) stop("No observations are available at or before `origin_week`.", call. = FALSE)
  d[order(d$weekF), , drop = FALSE]
}

.validate_m1_v2_library <- function(x) {
  if (!inherits(x, "page_m1_v2_library")) {
    stop("`library` must be a `page_m1_v2_library`.", call. = FALSE)
  }
  required <- c("forecast", "passage", "peak_height", "fitted_peak", "peak_truth",
                "training_seasons", "config", "provenance")
  if (any(!required %in% names(x)) || is.null(x$provenance$library_hash)) {
    stop("M1-v2 library is incomplete.", call. = FALSE)
  }
  expected <- .m1_v2_recompute_library_hash(x)
  if (!identical(x$provenance$library_hash, expected)) {
    stop("M1-v2 library integrity check failed.", call. = FALSE)
  }
  invisible(TRUE)
}

.check_m1_v2_scalar <- function(x, name, positive = FALSE) {
  if (!is.numeric(x) || length(x) != 1L || !is.finite(x) || (positive && x <= 0)) {
    stop("`", name, "` must be one finite ", if (positive) "positive " else "", "number.", call. = FALSE)
  }
}

.check_m1_v2_origin <- function(x) {
  .check_m1_v2_scalar(x, "origin_week")
  if (abs(x - round(x)) > 1e-8) stop("`origin_week` must be an integer observed-week label.", call. = FALSE)
}
