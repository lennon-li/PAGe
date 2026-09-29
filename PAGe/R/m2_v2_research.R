# M2-v2 C2 research interface. This file is deliberately parallel to the
# legacy M2 runtime and is not called by run_prospective_pipeline().

m2_v2_c2_artifact_spec <- function() {
  list(
    artifact_schema = "page-m2-v2-c2-research-v1",
    model_version = "m2-v2-c2-research-v1",
    family = "C2",
    type_pool_weight = 0.5,
    curve_blend_weight = 0.5,
    horizons = c(1L, 2L),
    types = c("A", "B"),
    denominator_regimes = c(
      "historical_shared_flu_test_proxy",
      "orvt_type_specific"
    ),
    timing_contracts = list(
      A = "m1-v2-to-m2-v1",
      B = "m1-v2-b-soft-timing-provisional-v1"
    ),
    b_gate_policy = list(
      version = "b-epidemic-gate-5pct-v1",
      semantics = "causal_latch_after_first_qualifying_trailing_window",
      min_origin_week = 18L,
      trailing_weeks = 4L,
      min_trailing_positive_count = 40L,
      min_trailing_max_positivity = 0.05,
      status = "provisional_research"
    ),
    baseline_template = list(
      formula = "cbind(y_target, N_target-y_target) ~ horizon_f + growth1 + growth2 + offset(offset_logit)",
      family = "quasibinomial",
      offset = "logit_current",
      training_scope = "explicit_training_seasons_only",
      coefficients = "fit and retain per type from supplied training rows"
    ),
    routing = list(
      A = "C2 at +1/+2 only with valid governed A timing",
      B_h1 = "exact B1 baseline",
      B_h2 = "C2 only with valid B soft timing and active reviewed B gate",
      unavailable_or_invalid_timing = "exact type-specific baseline",
      cross_type_timing = "hard error"
    )
  )
}

.m2_v2_c2_require_digest <- function() {
  if (!requireNamespace("digest", quietly = TRUE)) {
    stop("M2-v2 research identity requires package `digest`.", call. = FALSE)
  }
}

.m2_v2_c2_training_data_id <- function(ledger) {
  .m2_v2_c2_require_digest()
  keep <- c(
    "season", "type", "horizon", "y_target", "N_target", "p_star",
    "logit_current", "growth1", "growth2", "denominator_regime"
  )
  x <- ledger[, keep, drop = FALSE]
  x$season <- as.character(x$season)
  x$type <- as.character(x$type)
  x <- x[order(x$season, x$type, x$horizon, x$y_target, x$N_target, x$p_star,
               x$logit_current, x$growth1, x$growth2, x$denominator_regime), , drop = FALSE]
  rownames(x) <- NULL
  digest::digest(x, algo = "sha256")
}

.m2_v2_c2_shape_id <- function(shapes) {
  .m2_v2_c2_require_digest()
  x <- shapes[, c("season", "type", "tau", "p_norm"), drop = FALSE]
  x$season <- as.character(x$season)
  x$type <- as.character(x$type)
  x <- x[order(x$season, x$type, x$tau), , drop = FALSE]
  rownames(x) <- NULL
  digest::digest(x, algo = "sha256")
}

.m2_v2_c2_artifact_id <- function(model) {
  .m2_v2_c2_require_digest()
  payload <- list(
    artifact_schema = model$spec$artifact_schema,
    model_version = model$spec$model_version,
    family = model$spec$family,
    type_pool_weight = model$spec$type_pool_weight,
    curve_blend_weight = model$spec$curve_blend_weight,
    timing_contracts = model$spec$timing_contracts,
    b_gate_policy = model$spec$b_gate_policy,
    routing = model$spec$routing,
    training_seasons = sort(as.character(model$training_seasons)),
    baseline_coefficients = model$baseline_coefficients,
    fitted_baseline_coefficients = lapply(model$baseline_fits, stats::coef),
    denominator_regime_metadata = model$denominator_regime_metadata,
    data_id = model$data_id,
    shape_id = model$shape_id,
    source_hashes = model$source_hashes
  )
  paste0("m2v2_", digest::digest(payload, algo = "sha256"))
}

validate_m2_v2_c2_research_fit <- function(model) {
  if (!inherits(model, "page_m2_v2_c2_research")) {
    stop("model is not an M2-v2 C2 research fit.", call. = FALSE)
  }
  req <- c("spec", "training_seasons", "baseline_fits", "baseline_coefficients",
           "shape_templates", "denominator_regime_metadata", "source_hashes",
           "data_id", "shape_id", "artifact_id")
  if (!all(req %in% names(model))) {
    stop("M2-v2 research fit is missing identity or fitted-payload fields.", call. = FALSE)
  }
  if (!identical(model$spec$family, "C2") ||
      !identical(model$spec$timing_contracts$A, "m1-v2-to-m2-v1")) {
    stop("M2-v2 research fit has an unsupported family/timing contract.", call. = FALSE)
  }
  fitted_coef <- lapply(model$baseline_fits, stats::coef)
  if (!identical(model$baseline_coefficients, fitted_coef)) {
    stop("M2-v2 research baseline coefficient payload mismatch.", call. = FALSE)
  }
  expected <- .m2_v2_c2_artifact_id(model)
  if (!identical(model$artifact_id, expected)) {
    stop("M2-v2 research artifact identity mismatch.", call. = FALSE)
  }
  invisible(model)
}

m2_v2_c2_fit <- function(training_ledger, shape_grid, training_seasons,
                         source_hashes = list()) {
  req <- c("season", "type", "horizon", "y_target", "N_target", "p_star",
           "logit_current", "growth1", "growth2", "denominator_regime")
  if (!is.data.frame(training_ledger) || !all(req %in% names(training_ledger))) {
    stop("training_ledger is missing required M2-v2 columns.", call. = FALSE)
  }
  if (!all(c("season", "type", "tau", "p_norm") %in% names(shape_grid))) {
    stop("shape_grid must contain season, type, tau, and p_norm.", call. = FALSE)
  }
  training_seasons <- sort(unique(as.character(training_seasons)))
  if (!length(training_seasons) || anyNA(training_seasons)) {
    stop("training_seasons must explicitly name at least one training season.", call. = FALSE)
  }
  ledger <- training_ledger
  ledger$season <- as.character(ledger$season)
  ledger$type <- as.character(ledger$type)
  if (any(!ledger$season %in% training_seasons)) {
    stop("training_ledger contains a season outside training_seasons.", call. = FALSE)
  }
  if (!all(training_seasons %in% unique(ledger$season))) {
    stop("training_seasons contains a season absent from training_ledger.", call. = FALSE)
  }
  if (any(!ledger$type %in% c("A", "B")) || any(!ledger$horizon %in% 1:2)) {
    stop("training ledger type or horizon is outside the v1 contract.", call. = FALSE)
  }
  if (anyNA(ledger$denominator_regime) || any(!nzchar(ledger$denominator_regime))) {
    stop("denominator_regime must be retained for every training row.", call. = FALSE)
  }
  allowed_regimes <- m2_v2_c2_artifact_spec()$denominator_regimes
  unknown_regimes <- setdiff(unique(as.character(ledger$denominator_regime)), allowed_regimes)
  if (length(unknown_regimes)) {
    stop("training_ledger contains an unsupported denominator regime: ",
         paste(unknown_regimes, collapse = ", "), call. = FALSE)
  }
  if (any(!is.finite(ledger$y_target)) || any(!is.finite(ledger$N_target)) ||
      any(ledger$y_target < 0 | ledger$N_target < ledger$y_target)) {
    stop("training outcome counts are invalid.", call. = FALSE)
  }
  ledger <- ledger[order(ledger$season, ledger$type, ledger$horizon, ledger$y_target,
                         ledger$N_target, ledger$p_star, ledger$logit_current,
                         ledger$growth1, ledger$growth2, ledger$denominator_regime), , drop = FALSE]
  rownames(ledger) <- NULL
  shapes <- shape_grid[as.character(shape_grid$season) %in% training_seasons, , drop = FALSE]
  shapes$season <- as.character(shapes$season)
  shapes$type <- as.character(shapes$type)
  if (!nrow(shapes) || any(!shapes$type %in% c("A", "B"))) {
    stop("shape_grid has no valid training-season A/B shape rows.", call. = FALSE)
  }
  if (!all(training_seasons %in% unique(shapes$season))) {
    stop("shape_grid is missing one or more training seasons.", call. = FALSE)
  }
  shapes <- shapes[is.finite(shapes$tau) & is.finite(shapes$p_norm), , drop = FALSE]
  shapes$p_norm <- pmin(pmax(shapes$p_norm, 0.01), 1)
  shapes <- shapes[order(shapes$season, shapes$type, shapes$tau), , drop = FALSE]
  rownames(shapes) <- NULL

  fits <- lapply(c("A", "B"), function(tp) {
    d <- ledger[ledger$type == tp, , drop = FALSE]
    if (!nrow(d)) stop("No training baseline rows for type ", tp, ".", call. = FALSE)
    d$horizon_f <- factor(paste0("h", d$horizon), levels = c("h1", "h2"))
    d$offset_logit <- d$logit_current
    suppressWarnings(stats::glm(
      cbind(y_target, N_target - y_target) ~ horizon_f + growth1 + growth2 +
        offset(offset_logit), data = d, family = stats::quasibinomial()
    ))
  })
  names(fits) <- c("A", "B")
  spec <- m2_v2_c2_artifact_spec()
  out <- structure(list(
    spec = spec,
    training_seasons = training_seasons,
    baseline_fits = fits,
    baseline_coefficients = lapply(fits, stats::coef),
    shape_templates = shapes,
    denominator_regime_metadata = list(
      levels = sort(unique(as.character(ledger$denominator_regime))),
      by_type = stats::setNames(lapply(c("A", "B"), function(tp) {
        sort(unique(as.character(ledger$denominator_regime[ledger$type == tp])))
      }), c("A", "B")),
      observations = "retained as measurement-regime metadata; never silently harmonized",
      likelihood_status = "research_quasibinomial_not_finalized_for_production"
    ),
    source_hashes = source_hashes,
    data_id = .m2_v2_c2_training_data_id(ledger),
    shape_id = .m2_v2_c2_shape_id(shapes),
    artifact_id = NA_character_
  ), class = "page_m2_v2_c2_research")
  out$artifact_id <- .m2_v2_c2_artifact_id(out)
  validate_m2_v2_c2_research_fit(out)
  out
}

m2_v2_c2_curve_log_ratio <- function(model, type, tau, horizon) {
  validate_m2_v2_c2_research_fit(model)
  if (!type %in% c("A", "B") || !horizon %in% 1:2) return(NA_real_)
  shapes <- model$shape_templates
  one <- function(d) {
    d <- d[order(d$tau), , drop = FALSE]
    if (nrow(d) < 2L || tau < min(d$tau) || tau + horizon > max(d$tau)) return(NA_real_)
    cur <- stats::approx(d$tau, d$p_norm, xout = tau, rule = 1)$y
    fut <- stats::approx(d$tau, d$p_norm, xout = tau + horizon, rule = 1)$y
    if (!is.finite(cur) || !is.finite(fut)) NA_real_ else log(fut / cur)
  }
  ids <- unique(paste(shapes$season, shapes$type, sep = "|"))
  ratios <- vapply(ids, function(id) {
    bits <- strsplit(id, "|", fixed = TRUE)[[1L]]
    one(shapes[shapes$season == bits[1L] & shapes$type == bits[2L], , drop = FALSE])
  }, numeric(1))
  pooled_values <- ratios[is.finite(ratios)]
  if (!length(pooled_values)) return(NA_real_)
  pooled <- stats::median(pooled_values)
  type_ids <- ids[vapply(strsplit(ids, "|", fixed = TRUE), `[[`, character(1), 2L) == type]
  type_ratios <- vapply(type_ids, function(id) {
    bits <- strsplit(id, "|", fixed = TRUE)[[1L]]
    one(shapes[shapes$season == bits[1L] & shapes$type == bits[2L], , drop = FALSE])
  }, numeric(1))
  type_values <- type_ratios[is.finite(type_ratios)]
  if (!length(type_values)) return(NA_real_)
  typed <- stats::median(type_values)
  w <- model$spec$type_pool_weight
  (1 - w) * pooled + w * typed
}

m2_v2_c2_predict <- function(model, newdata) {
  validate_m2_v2_c2_research_fit(model)
  req <- c("type", "horizon", "p_star", "logit_current", "growth1", "growth2",
           "origin_week", "timing_type", "timing_contract_version", "timing_available", "timing_peak")
  if (!is.data.frame(newdata) || !all(req %in% names(newdata))) {
    stop("newdata is missing required forecast/timing contract columns.", call. = FALSE)
  }
  d <- newdata
  d$type <- as.character(d$type)
  d$timing_type <- as.character(d$timing_type)
  if (any(!d$type %in% c("A", "B")) || any(!d$horizon %in% 1:2)) stop("Invalid type or horizon.", call. = FALSE)
  if (anyNA(d$timing_type) || any(d$timing_type != d$type)) {
    stop("Timing type must match forecast type; cross-type timing substitution is forbidden.", call. = FALSE)
  }
  expected_contract <- unname(vapply(d$type, function(tp) model$spec$timing_contracts[[tp]], character(1)))
  contract_ok <- !is.na(d$timing_contract_version) & d$timing_contract_version == expected_contract
  available_flag <- !is.na(d$timing_available) & d$timing_available
  peak_ok <- is.finite(d$timing_peak)
  failed <- if ("timing_failed" %in% names(d)) {
    is.na(d$timing_failed) | d$timing_failed
  } else {
    rep(FALSE, nrow(d))
  }
  if (!"timing_gate_active" %in% names(d)) d$timing_gate_active <- FALSE
  gate_active <- !is.na(d$timing_gate_active) & d$timing_gate_active
  available <- available_flag & contract_ok & peak_ok & !failed

  baseline <- rep(NA_real_, nrow(d))
  for (tp in c("A", "B")) {
    i <- which(d$type == tp)
    if (!length(i)) next
    nd <- d[i, , drop = FALSE]
    nd$horizon_f <- factor(paste0("h", nd$horizon), levels = c("h1", "h2"))
    nd$offset_logit <- nd$logit_current
    baseline[i] <- as.numeric(stats::predict(model$baseline_fits[[tp]], newdata = nd, type = "response"))
  }
  selected <- baseline
  applied <- rep(FALSE, nrow(d))
  fallback_reason <- rep(NA_character_, nrow(d))
  for (i in seq_len(nrow(d))) {
    if (d$type[i] == "B" && d$horizon[i] == 1L) {
      fallback_reason[i] <- "policy_b_h1_baseline"
      next
    }
    if (failed[i]) {
      fallback_reason[i] <- "type_timing_failed"
      next
    }
    if (!available_flag[i]) {
      fallback_reason[i] <- "type_timing_unavailable"
      next
    }
    if (!contract_ok[i]) {
      fallback_reason[i] <- "upstream_identity_mismatch"
      next
    }
    if (!peak_ok[i]) {
      fallback_reason[i] <- "type_timing_unavailable"
      next
    }
    if (d$type[i] == "B" && !gate_active[i]) {
      fallback_reason[i] <- "b_timing_gate_inactive"
      next
    }
    lr <- m2_v2_c2_curve_log_ratio(model, d$type[i], d$origin_week[i] - d$timing_peak[i], d$horizon[i])
    if (!is.finite(lr)) {
      fallback_reason[i] <- "curve_support_unavailable"
      next
    }
    curve <- pmin(pmax(d$p_star[i] * exp(lr), 1e-6), 1 - 1e-6)
    bw <- model$spec$curve_blend_weight
    selected[i] <- stats::plogis(
      (1 - bw) * stats::qlogis(pmin(pmax(baseline[i], 1e-8), 1 - 1e-8)) +
        bw * stats::qlogis(pmin(pmax(curve, 1e-8), 1 - 1e-8))
    )
    applied[i] <- TRUE
  }
  fallback_reason[applied] <- NA_character_
  d$pred_baseline <- baseline
  d$pred_c2 <- ifelse(applied, selected, baseline)
  d$pred_selected <- d$pred_c2
  d$c2_applied <- applied
  d$timing_contract_valid <- contract_ok
  d$timing_used <- applied
  d$fallback_reason <- fallback_reason
  d$model_artifact_id <- model$artifact_id
  d
}


.m2_v2_or <- function(x, y) if (!is.null(x)) x else y

# -------------------------------------------------------------------------
# Research-only runtime adapter. This is intentionally not wired into the
# production pipeline. It converts a typed A/B weekly panel plus explicit
# timing handoffs into the exact feature contract consumed by m2_v2_c2_predict().

#' Build a provisional type-B soft-timing handoff for M2-v2
#'
#' @param season Single season identifier.
#' @param origin_week Current integer origin week.
#' @param peak_mean Soft posterior mean B peak week; may be `NA`.
#' @param timing_available Logical flag indicating whether B timing is available.
#' @param source_artifact_id Nonempty upstream B timing artifact identity when available.
#' @param interval_width_90 Optional 90 percent timing interval width.
#' @param prob_peak_passed Optional posterior probability that the B peak has passed.
#' @return A validated provisional type-B timing handoff list.
#' @export
new_m2_v2_b_soft_timing_handoff <- function(season, origin_week,
                                             peak_mean = NA_real_,
                                             timing_available = is.finite(peak_mean),
                                             source_artifact_id = NA_character_,
                                             interval_width_90 = NA_real_,
                                             prob_peak_passed = NA_real_) {
  out <- list(
    version = "m1-v2-b-soft-timing-provisional-v1",
    type = "B",
    season = as.character(season),
    origin_week = as.numeric(origin_week),
    timing_available = isTRUE(timing_available),
    peak_mean = as.numeric(peak_mean),
    interval_width_90 = as.numeric(interval_width_90),
    prob_peak_passed = as.numeric(prob_peak_passed),
    source_artifact_id = as.character(source_artifact_id)
  )
  validate_m2_v2_b_soft_timing_handoff(out)
  out
}

validate_m2_v2_b_soft_timing_handoff <- function(x) {
  if (!is.list(x)) stop("B soft-timing handoff must be a list.", call. = FALSE)
  req <- c("version", "type", "season", "origin_week", "timing_available", "peak_mean",
           "interval_width_90", "prob_peak_passed", "source_artifact_id")
  if (!all(req %in% names(x))) stop("B soft-timing handoff is missing required fields.", call. = FALSE)
  if (!identical(x$version, "m1-v2-b-soft-timing-provisional-v1")) {
    stop("Unsupported B soft-timing handoff version.", call. = FALSE)
  }
  if (!identical(x$type, "B")) stop("B soft-timing handoff type must be B.", call. = FALSE)
  if (!is.character(x$season) || length(x$season) != 1L || is.na(x$season) || !nzchar(x$season)) {
    stop("B soft-timing handoff season is invalid.", call. = FALSE)
  }
  if (!is.numeric(x$origin_week) || length(x$origin_week) != 1L || !is.finite(x$origin_week)) {
    stop("B soft-timing handoff origin_week is invalid.", call. = FALSE)
  }
  if (!is.logical(x$timing_available) || length(x$timing_available) != 1L || is.na(x$timing_available)) {
    stop("B soft-timing handoff timing_available must be one logical value.", call. = FALSE)
  }
  if (isTRUE(x$timing_available)) {
    if (!is.numeric(x$peak_mean) || length(x$peak_mean) != 1L || !is.finite(x$peak_mean)) {
      stop("Available B soft timing requires a finite peak_mean.", call. = FALSE)
    }
    if (!is.character(x$source_artifact_id) || length(x$source_artifact_id) != 1L ||
        is.na(x$source_artifact_id) || !nzchar(x$source_artifact_id)) {
      stop("Available B soft timing requires a source_artifact_id.", call. = FALSE)
    }
  }
  if (!is.numeric(x$interval_width_90) || length(x$interval_width_90) != 1L ||
      !is.numeric(x$prob_peak_passed) || length(x$prob_peak_passed) != 1L ||
      !is.character(x$source_artifact_id) || length(x$source_artifact_id) != 1L) {
    stop("B soft-timing scalar metadata fields are invalid.", call. = FALSE)
  }
  if (is.finite(x$interval_width_90) && x$interval_width_90 < 0) {
    stop("B soft-timing interval_width_90 cannot be negative.", call. = FALSE)
  }
  if (is.finite(x$prob_peak_passed) && (x$prob_peak_passed < 0 || x$prob_peak_passed > 1)) {
    stop("B soft-timing prob_peak_passed must lie in [0, 1].", call. = FALSE)
  }
  invisible(x)
}

.m2_v2_runtime_stabilized_p <- function(y, N, c = 0.5) {
  if (!is.finite(y) || !is.finite(N) || y < 0 || N <= 0 || y > N) return(NA_real_)
  (y + c) / (N + 2 * c)
}

.m2_v2_runtime_gate_b <- function(weekly_data, origin_week, spec) {
  origin_week <- as.integer(origin_week)
  semantics <- if (!is.null(spec$semantics)) spec$semantics else NA_character_
  if (!identical(semantics, "causal_latch_after_first_qualifying_trailing_window")) {
    stop("Unsupported B timing-gate semantics.", call. = FALSE)
  }
  d <- weekly_data[weekly_data$weekF <= origin_week, , drop = FALSE]
  d <- d[order(d$weekF), , drop = FALSE]
  candidate_weeks <- d$weekF[d$weekF >= spec$min_origin_week]
  if (!length(candidate_weeks)) {
    return(list(active = FALSE, status = "insufficient_gate_history",
                activation_week = NA_integer_, trailing_positive_count = NA_real_,
                trailing_max_positivity = NA_real_))
  }
  last_count <- NA_real_
  last_max_p <- NA_real_
  for (w in candidate_weeks) {
    wanted <- seq(as.integer(w) - spec$trailing_weeks + 1L, as.integer(w), by = 1L)
    z <- d[d$weekF %in% wanted, , drop = FALSE]
    z <- z[order(z$weekF), , drop = FALSE]
    exact <- nrow(z) == length(wanted) && identical(as.integer(z$weekF), wanted)
    if (!exact) next
    fallback_p <- as.numeric(z$y_B / z$N_B)
    p_obs <- if ("p_B" %in% names(z)) as.numeric(z$p_B) else fallback_p
    p_obs[!is.finite(p_obs)] <- fallback_p[!is.finite(p_obs)]
    if (any(!is.finite(p_obs)) || any(!is.finite(z$y_B))) next
    count <- sum(as.numeric(z$y_B))
    max_p <- max(p_obs)
    last_count <- count
    last_max_p <- max_p
    if (count >= spec$min_trailing_positive_count &&
        max_p >= spec$min_trailing_max_positivity) {
      return(list(active = TRUE, status = "active_latched",
                  activation_week = as.integer(w), trailing_positive_count = count,
                  trailing_max_positivity = max_p))
    }
  }
  list(active = FALSE,
       status = if (is.finite(last_count)) "inactive" else "insufficient_gate_history",
       activation_week = NA_integer_, trailing_positive_count = last_count,
       trailing_max_positivity = last_max_p)
}


.m2_v2_runtime_a_timing <- function(a_handoff, season, origin_week) {
  out <- list(
    timing_type = "A", timing_contract_version = "m1-v2-to-m2-v1",
    timing_available = FALSE, timing_peak = NA_real_, timing_failed = FALSE,
    timing_source_artifact_id = NA_character_, timing_state = "missing"
  )
  if (is.null(a_handoff)) return(out)
  out$timing_contract_version <- as.character(.m2_v2_or(a_handoff$version, NA_character_))
  out$timing_source_artifact_id <- as.character(.m2_v2_or(a_handoff$m1_v2_artifact_id, NA_character_))
  out$timing_state <- as.character(.m2_v2_or(a_handoff$state, "invalid"))
  valid <- tryCatch({
    if (!exists("validate_m1_v2_handoff", mode = "function")) {
      stop("validate_m1_v2_handoff() is unavailable.")
    }
    validate_m1_v2_handoff(a_handoff)
    TRUE
  }, error = function(e) FALSE)
  same_origin <- is.numeric(a_handoff$origin_week) && length(a_handoff$origin_week) == 1L &&
    is.finite(a_handoff$origin_week) && abs(a_handoff$origin_week - origin_week) < 1e-8
  same_season <- is.character(a_handoff$season) && length(a_handoff$season) == 1L &&
    identical(as.character(a_handoff$season), as.character(season))
  if (!valid || !same_origin || !same_season) {
    out$timing_failed <- TRUE
    return(out)
  }
  if (identical(a_handoff$state, "passage_confirmed") && is.finite(a_handoff$locked_peak_week)) {
    out$timing_peak <- as.numeric(a_handoff$locked_peak_week)
    out$timing_available <- TRUE
  } else if (a_handoff$state %in% c("active", "future_only") &&
             is.finite(a_handoff$calibrated_peak_mean)) {
    out$timing_peak <- as.numeric(a_handoff$calibrated_peak_mean)
    out$timing_available <- TRUE
  }
  out
}

.m2_v2_runtime_b_timing <- function(b_handoff, season, origin_week) {
  out <- list(
    timing_type = "B", timing_contract_version = "m1-v2-b-soft-timing-provisional-v1",
    timing_available = FALSE, timing_peak = NA_real_, timing_failed = FALSE,
    timing_source_artifact_id = NA_character_, timing_state = "missing"
  )
  if (is.null(b_handoff)) return(out)
  if (!is.null(b_handoff$type) && !identical(b_handoff$type, "B")) {
    stop("B runtime handoff must be type B; cross-type timing substitution is forbidden.", call. = FALSE)
  }
  out$timing_contract_version <- as.character(.m2_v2_or(b_handoff$version, NA_character_))
  out$timing_source_artifact_id <- as.character(.m2_v2_or(b_handoff$source_artifact_id, NA_character_))
  out$timing_state <- if (isTRUE(b_handoff$timing_available)) "available" else "unavailable"
  valid <- tryCatch({ validate_m2_v2_b_soft_timing_handoff(b_handoff); TRUE }, error = function(e) FALSE)
  same_origin <- is.numeric(b_handoff$origin_week) && length(b_handoff$origin_week) == 1L &&
    is.finite(b_handoff$origin_week) && abs(b_handoff$origin_week - origin_week) < 1e-8
  same_season <- is.character(b_handoff$season) && length(b_handoff$season) == 1L &&
    identical(as.character(b_handoff$season), as.character(season))
  if (!valid || !same_origin || !same_season) {
    out$timing_failed <- TRUE
    return(out)
  }
  if (isTRUE(b_handoff$timing_available) && is.finite(b_handoff$peak_mean)) {
    out$timing_available <- TRUE
    out$timing_peak <- as.numeric(b_handoff$peak_mean)
  }
  out
}

m2_v2_c2_runtime_features <- function(weekly_data, origin_week) {
  required <- c("season", "weekF", "y_A", "N_A", "y_B", "N_B", "denominator_regime")
  if (!is.data.frame(weekly_data) || !all(required %in% names(weekly_data))) {
    stop("weekly_data is missing required typed A/B surveillance columns.", call. = FALSE)
  }
  seasons <- unique(as.character(weekly_data$season))
  if (length(seasons) != 1L || is.na(seasons) || !nzchar(seasons)) {
    stop("weekly_data must contain exactly one season.", call. = FALSE)
  }
  origin_week <- as.integer(origin_week)
  wanted <- origin_week - 2:0
  z <- weekly_data[weekly_data$weekF %in% wanted, , drop = FALSE]
  z <- z[order(z$weekF), , drop = FALSE]
  if (nrow(z) != 3L || !identical(as.integer(z$weekF), as.integer(wanted))) {
    stop("M2-v2 runtime requires exact origin, origin-1, and origin-2 weekly observations.", call. = FALSE)
  }
  regime <- as.character(z$denominator_regime[3L])
  if (is.na(regime) || !nzchar(regime)) {
    stop("M2-v2 runtime denominator_regime is missing at the origin.", call. = FALSE)
  }
  rows <- list()
  for (tp in c("A", "B")) {
    y <- as.numeric(z[[paste0("y_", tp)]])
    N <- as.numeric(z[[paste0("N_", tp)]])
    ps <- vapply(seq_along(y), function(i) .m2_v2_runtime_stabilized_p(y[i], N[i]), numeric(1))
    if (any(!is.finite(ps))) stop("Invalid typed counts in M2-v2 runtime prefix.", call. = FALSE)
    lg <- stats::qlogis(ps)
    for (h in 1:2) {
      rows[[length(rows) + 1L]] <- data.frame(
        season = seasons, type = tp, horizon = h, origin_week = origin_week,
        p_star = ps[3L], logit_current = lg[3L],
        growth1 = lg[3L] - lg[2L], growth2 = (lg[3L] - lg[1L]) / 2,
        denominator_regime = regime,
        stringsAsFactors = FALSE
      )
    }
  }
  do.call(rbind, rows)
}

run_m2_v2_c2_research_runtime <- function(model, weekly_data, origin_week,
                                           a_handoff = NULL, b_handoff = NULL) {
  validate_m2_v2_c2_research_fit(model)
  features <- m2_v2_c2_runtime_features(weekly_data, origin_week)
  season <- unique(features$season)
  if (season %in% model$training_seasons) {
    stop("Current season is present in the M2-v2 research training artifact; refusing leakage-prone inference.", call. = FALSE)
  }
  unknown_regimes <- setdiff(unique(features$denominator_regime), model$spec$denominator_regimes)
  if (length(unknown_regimes)) {
    stop("M2-v2 research runtime encountered an unsupported denominator regime: ",
         paste(unknown_regimes, collapse = ", "), call. = FALSE)
  }
  a <- .m2_v2_runtime_a_timing(a_handoff, season, origin_week)
  b <- .m2_v2_runtime_b_timing(b_handoff, season, origin_week)
  gate <- .m2_v2_runtime_gate_b(weekly_data, origin_week, model$spec$b_gate_policy)

  features$timing_type <- features$type
  features$timing_contract_version <- ifelse(
    features$type == "A", a$timing_contract_version, b$timing_contract_version
  )
  features$timing_available <- ifelse(features$type == "A", a$timing_available, b$timing_available)
  features$timing_peak <- ifelse(features$type == "A", a$timing_peak, b$timing_peak)
  features$timing_failed <- ifelse(features$type == "A", a$timing_failed, b$timing_failed)
  features$timing_gate_active <- ifelse(features$type == "B", gate$active, FALSE)
  pred <- m2_v2_c2_predict(model, features)
  pred$timing_source_artifact_id <- ifelse(
    pred$type == "A", a$timing_source_artifact_id, b$timing_source_artifact_id
  )
  pred$timing_state <- ifelse(pred$type == "A", a$timing_state, b$timing_state)
  pred$b_gate_status <- ifelse(pred$type == "B", gate$status, NA_character_)
  pred$b_gate_trailing_positive_count <- ifelse(pred$type == "B", gate$trailing_positive_count, NA_real_)
  pred$b_gate_trailing_max_positivity <- ifelse(pred$type == "B", gate$trailing_max_positivity, NA_real_)
  list(
    status = "research_shadow_only",
    model_artifact_id = model$artifact_id,
    season = season,
    origin_week = as.integer(origin_week),
    predictions = pred,
    a_timing = a,
    b_timing = b,
    b_gate = gate
  )
}
