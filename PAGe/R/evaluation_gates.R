#' Summarize prospective forecast metrics
#'
#' Computes trial-weighted Bernoulli negative log likelihood (NLL) and
#' absolute-error summaries by forecast horizon and epidemic phase. If no
#' explicit phase column is supplied, phase is deterministically defined
#' from t_since: values below 0 are pre-ignition, values from 0 through 3 are
#' early, and values of 4 or greater are late.
#'
#' @param predictions Prediction data frame containing p_hat, observed
#'   probability (p_obs, or y_lead/N_lead), horizon (lead), and phase
#'   information.
#' @param phase_col Optional name of an existing phase column.
#' @param phase_break Non-negative boundary between early and late phases.
#' @param eps Probability clipping value.
#'
#' @return A list with overall, horizon, and phase tables.
#' @export
summarize_forecast_metrics <- function(predictions,
                                       phase_col = NULL,
                                       phase_break = 4,
                                       eps = 1e-12) {
  predictions <- as.data.frame(predictions)
  if (!"p_hat" %in% names(predictions)) {
    stop("`predictions` must contain `p_hat`.")
  }
  if ("p_obs" %in% names(predictions)) {
    p_obs <- as.numeric(predictions$p_obs)
  } else if (all(c("y_lead", "N_lead") %in% names(predictions))) {
    p_obs <- predictions$y_lead / predictions$N_lead
  } else {
    stop("`predictions` must contain `p_obs` or both `y_lead` and `N_lead`.")
  }
  weights <- if ("N_lead" %in% names(predictions)) {
    as.numeric(predictions$N_lead)
  } else {
    rep(1, nrow(predictions))
  }
  if (!"lead" %in% names(predictions)) {
    stop("`predictions` must contain `lead`.")
  }
  if (is.null(phase_col)) {
    if (!"t_since" %in% names(predictions)) {
      stop("`predictions` must contain `t_since` when `phase_col` is NULL.")
    }
    phase <- ifelse(
      predictions$t_since < 0, "pre_ignition",
      ifelse(predictions$t_since < phase_break, "early", "late")
    )
  } else {
    if (!phase_col %in% names(predictions)) {
      stop("Phase column `", phase_col, "` is absent from `predictions`.")
    }
    phase <- as.character(predictions[[phase_col]])
  }

  p_hat <- pmin(1 - eps, pmax(eps, as.numeric(predictions$p_hat)))
  p_obs <- pmin(1 - eps, pmax(eps, p_obs))
  valid <- is.finite(p_hat) & is.finite(p_obs) & is.finite(weights) & weights > 0
  if (!any(valid)) stop("No finite predictions with positive trial weights.")
  loss <- -(p_obs * log(p_hat) + (1 - p_obs) * log(1 - p_hat))
  abs_error <- abs(p_hat - p_obs)
  metric_frame <- data.frame(
    lead = as.character(predictions$lead), phase = phase,
    loss = loss, abs_error = abs_error, weight = weights,
    valid = valid, stringsAsFactors = FALSE
  )
  metric_frame <- metric_frame[metric_frame$valid, , drop = FALSE]

  summarize_group <- function(group) {
    split_rows <- split(metric_frame, metric_frame[[group]], drop = TRUE)
    rows <- lapply(names(split_rows), function(label) {
      x <- split_rows[[label]]
      data.frame(
        label = label,
        mae = stats::weighted.mean(x$abs_error, x$weight),
        n_trials = sum(x$weight), n_predictions = nrow(x),
        stringsAsFactors = FALSE
      )
    })
    out <- do.call(rbind, rows)
    names(out)[1L] <- group
    rownames(out) <- NULL
    out
  }

  overall <- data.frame(
    bernoulli_nll = stats::weighted.mean(metric_frame$loss, metric_frame$weight),
    mae = stats::weighted.mean(metric_frame$abs_error, metric_frame$weight),
    n_trials = sum(metric_frame$weight),
    n_predictions = nrow(metric_frame)
  )
  list(
    overall = overall,
    horizon = summarize_group("lead"),
    phase = summarize_group("phase")
  )
}

.relative_degradation <- function(candidate, incumbent) {
  if (!is.finite(candidate) || !is.finite(incumbent) || incumbent < 0) {
    return(Inf)
  }
  if (incumbent == 0) {
    return(if (candidate <= 0) 0 else Inf)
  }
  (candidate - incumbent) / incumbent
}

.group_gate <- function(candidate, incumbent, key, limit) {
  merged <- merge(
    incumbent[, c(key, "mae"), drop = FALSE],
    candidate[, c(key, "mae"), drop = FALSE],
    by = key, suffixes = c("_incumbent", "_candidate"), all = TRUE
  )
  merged$degradation <- mapply(
    .relative_degradation, merged$mae_candidate, merged$mae_incumbent
  )
  merged$pass <- is.finite(merged$degradation) & merged$degradation <= limit
  list(pass = nrow(merged) > 0L && all(merged$pass), detail = merged)
}

.promotion_schema <- function() "page_promotion_report"

.promotion_schema_version <- function() 1L

.promotion_locked_thresholds <- function() {
  list(
    min_nll_improvement = 0.02,
    max_horizon_degradation = 0.05,
    max_phase_degradation = 0.10
  )
}

.promotion_gate_spec <- function(thresholds) {
  data.frame(
    gate = c("nll", "horizon", "phase"),
    threshold = unname(c(
      thresholds$min_nll_improvement,
      thresholds$max_horizon_degradation,
      thresholds$max_phase_degradation
    )),
    direction = c("at_least", "at_most", "at_most"),
    stringsAsFactors = FALSE
  )
}

.promotion_equal <- function(actual, expected) {
  isTRUE(all.equal(
    unname(actual), unname(expected),
    tolerance = 1e-12, check.attributes = FALSE
  ))
}

.promotion_detail_is_valid <- function(detail, key, threshold, value, pass) {
  required <- c(
    key, "mae_incumbent", "mae_candidate", "degradation", "pass"
  )
  if (!is.data.frame(detail) || !identical(names(detail), required) ||
    !is.numeric(detail$mae_incumbent) ||
    !is.numeric(detail$mae_candidate) ||
    !is.numeric(detail$degradation) ||
    !is.logical(detail$pass) || anyNA(detail$pass)) {
    return(FALSE)
  }
  expected_degradation <- mapply(
    .relative_degradation, detail$mae_candidate, detail$mae_incumbent
  )
  expected_pass <- is.finite(expected_degradation) &
    expected_degradation <= threshold
  expected_value <- if (nrow(detail)) max(expected_degradation) else Inf
  expected_gate_pass <- nrow(detail) > 0L && all(expected_pass)
  .promotion_equal(detail$degradation, expected_degradation) &&
    identical(detail$pass, expected_pass) &&
    .promotion_equal(value, expected_value) &&
    identical(pass, expected_gate_pass)
}

.is_canonical_promotion_report <- function(report, require_locked = FALSE) {
  expected_names <- c(
    "schema", "schema_version", "pass", "gates", "reasons",
    "thresholds", "details"
  )
  if (!inherits(report, "page_promotion_report") || !is.list(report) ||
    !identical(names(report), expected_names) ||
    !identical(report$schema, .promotion_schema()) ||
    !identical(report$schema_version, .promotion_schema_version()) ||
    length(report$pass) != 1L || !is.logical(report$pass) ||
    is.na(report$pass) || !is.character(report$reasons) ||
    !is.list(report$thresholds) || !is.list(report$details)) {
    return(FALSE)
  }
  threshold_names <- names(.promotion_locked_thresholds())
  if (!identical(names(report$thresholds), threshold_names) ||
    !all(vapply(
      report$thresholds,
      function(x) {
        is.numeric(x) && length(x) == 1L &&
          is.finite(x) && x >= 0
      },
      logical(1)
    ))) {
    return(FALSE)
  }
  if (require_locked &&
    !identical(report$thresholds, .promotion_locked_thresholds())) {
    return(FALSE)
  }

  gates <- report$gates
  spec <- .promotion_gate_spec(report$thresholds)
  if (!is.data.frame(gates) ||
    !identical(names(gates), c("gate", "value", "threshold", "direction", "pass")) ||
    !identical(as.character(gates$gate), spec$gate) ||
    !is.numeric(gates$value) || anyNA(gates$value) ||
    !is.numeric(gates$threshold) ||
    !.promotion_equal(gates$threshold, spec$threshold) ||
    !identical(as.character(gates$direction), spec$direction) ||
    !is.logical(gates$pass) || anyNA(gates$pass)) {
    return(FALSE)
  }
  expected_gate_pass <- c(
    is.finite(gates$value[1L]) && gates$value[1L] >= gates$threshold[1L],
    is.finite(gates$value[2L]) && gates$value[2L] <= gates$threshold[2L],
    is.finite(gates$value[3L]) && gates$value[3L] <= gates$threshold[3L]
  )
  if (!identical(gates$pass, expected_gate_pass) ||
    !identical(report$pass, all(expected_gate_pass)) ||
    !identical(names(report$details), c("horizon", "phase")) ||
    !.promotion_detail_is_valid(
      report$details$horizon, "lead", gates$threshold[2L],
      gates$value[2L], gates$pass[2L]
    ) ||
    !.promotion_detail_is_valid(
      report$details$phase, "phase", gates$threshold[3L],
      gates$value[3L], gates$pass[3L]
    )) {
    return(FALSE)
  }
  expected_reasons <- character(0)
  if (!gates$pass[1L]) {
    expected_reasons <- c(expected_reasons, "NLL improvement gate failed.")
  }
  if (!gates$pass[2L]) {
    expected_reasons <- c(
      expected_reasons, "At least one horizon MAE gate failed."
    )
  }
  if (!gates$pass[3L]) {
    expected_reasons <- c(
      expected_reasons, "At least one phase MAE gate failed."
    )
  }
  identical(report$reasons, expected_reasons)
}

#' Check whether a candidate forecast model qualifies for promotion
#'
#' @param candidate,incumbent Metric lists returned by
#'   summarize_forecast_metrics().
#' @param min_nll_improvement Required relative Bernoulli NLL improvement.
#' @param max_horizon_degradation Maximum relative MAE degradation at any lead.
#' @param max_phase_degradation Maximum relative MAE degradation in any phase.
#'
#' @return A versioned \code{page_promotion_report} with canonical schema,
#'   aggregate gates, reasons, thresholds, and per-horizon and per-phase
#'   details. Promotion passes only when every gate passes; zero or missing
#'   incumbent baselines fail safely. The schema supports consistency checks;
#'   it does not provide cryptographic provenance or authenticity.
#' @export
check_promotion <- function(candidate,
                            incumbent,
                            min_nll_improvement = 0.02,
                            max_horizon_degradation = 0.05,
                            max_phase_degradation = 0.10) {
  thresholds <- list(
    min_nll_improvement = min_nll_improvement,
    max_horizon_degradation = max_horizon_degradation,
    max_phase_degradation = max_phase_degradation
  )
  if (!all(vapply(
    thresholds,
    function(x) is.numeric(x) && length(x) == 1L && is.finite(x) && x >= 0,
    logical(1)
  ))) {
    stop("Promotion thresholds must be finite, non-negative numeric scalars.")
  }
  required <- c("overall", "horizon", "phase")
  if (!all(required %in% names(candidate)) || !all(required %in% names(incumbent))) {
    stop("`candidate` and `incumbent` must be forecast metric summaries.")
  }
  inc_nll <- incumbent$overall$bernoulli_nll[1L]
  cand_nll <- candidate$overall$bernoulli_nll[1L]
  nll_improvement <- if (is.finite(inc_nll) && inc_nll > 0 && is.finite(cand_nll)) {
    (inc_nll - cand_nll) / inc_nll
  } else {
    -Inf
  }
  nll_pass <- is.finite(nll_improvement) && nll_improvement >= min_nll_improvement
  horizon <- .group_gate(candidate$horizon, incumbent$horizon, "lead", max_horizon_degradation)
  phase <- .group_gate(candidate$phase, incumbent$phase, "phase", max_phase_degradation)
  gate_spec <- .promotion_gate_spec(thresholds)
  gates <- data.frame(
    gate = gate_spec$gate,
    value = c(
      nll_improvement,
      if (nrow(horizon$detail)) max(horizon$detail$degradation) else Inf,
      if (nrow(phase$detail)) max(phase$detail$degradation) else Inf
    ),
    threshold = gate_spec$threshold,
    direction = gate_spec$direction,
    pass = c(nll_pass, horizon$pass, phase$pass),
    stringsAsFactors = FALSE
  )
  reasons <- character(0)
  if (!nll_pass) reasons <- c(reasons, "NLL improvement gate failed.")
  if (!horizon$pass) reasons <- c(reasons, "At least one horizon MAE gate failed.")
  if (!phase$pass) reasons <- c(reasons, "At least one phase MAE gate failed.")
  structure(
    list(
      schema = .promotion_schema(),
      schema_version = .promotion_schema_version(),
      pass = all(gates$pass),
      gates = gates,
      reasons = reasons,
      thresholds = thresholds,
      details = list(horizon = horizon$detail, phase = phase$detail)
    ),
    class = c("page_promotion_report", "list")
  )
}

.m2_complexity <- function(grid) {
  if ("complexity" %in% names(grid)) {
    return(as.numeric(grid$complexity))
  }
  terms <- intersect(c("k_f", "k_e", "k_r", "k_de", "k_sp", "Kr"), names(grid))
  if (!length(terms)) {
    return(rep(NA_real_, nrow(grid)))
  }
  rowSums(as.data.frame(lapply(grid[terms], as.numeric)), na.rm = TRUE)
}

.selection_metrics <- function(results) {
  if (!is.list(results) || !is.data.frame(results$summary)) {
    stop("`results` must contain a `summary` data frame.")
  }
  tab <- as.data.frame(results$summary)
  if (!"spec_id" %in% names(tab)) stop("`results$summary` must contain `spec_id`.")
  if (!"bernoulli_nll" %in% names(tab)) {
    if ("mean_nll" %in% names(tab)) {
      tab$bernoulli_nll <- tab$mean_nll
    } else {
      stop("Candidate selection requires `bernoulli_nll`.")
    }
  }
  needed <- c("horizon_mae", "phase_mae")
  if (!all(needed %in% names(tab)) && is.list(results$cv_results)) {
    derived <- lapply(names(results$cv_results), function(id) {
      preds <- results$cv_results[[id]]$predictions
      if (is.null(preds) || !nrow(preds)) {
        return(NULL)
      }
      metrics <- summarize_forecast_metrics(preds)
      data.frame(
        spec_id = id,
        horizon_mae = max(metrics$horizon$mae),
        phase_mae = max(metrics$phase$mae)
      )
    })
    derived <- do.call(rbind, derived)
    if (!is.null(derived)) tab <- merge(tab, derived, by = "spec_id", all.x = TRUE)
  }
  grid <- if (is.data.frame(results$grid)) {
    as.data.frame(results$grid)
  } else {
    data.frame(spec_id = tab$spec_id, stringsAsFactors = FALSE)
  }
  grid$complexity <- .m2_complexity(grid)
  merge(tab, grid[, c("spec_id", "complexity"), drop = FALSE], by = "spec_id", all.x = TRUE)
}

.extract_selected_spec <- function(results, spec_id) {
  if (length(results$best_spec_id) == 1L &&
    identical(as.character(results$best_spec_id), spec_id) &&
    is.list(results$best_spec)) {
    return(results$best_spec)
  }
  if (is.list(results$specs) && is.list(results$specs[[spec_id]])) {
    return(results$specs[[spec_id]])
  }
  if (is.data.frame(results$grid) && all(.m2_parameter_names() %in% names(results$grid))) {
    row <- results$grid[as.character(results$grid$spec_id) == spec_id, , drop = FALSE]
    if (nrow(row) == 1L) {
      return(.m2_specs_from_grid(row)$specs[[1L]])
    }
  }
  NULL
}

#' Select an M2 candidate from full nested-LOSO results
#'
#' @param results A build_m2()-like result.
#' @param method Selection rule: minimum NLL (default), one-standard-error, or
#'   Pareto selection on NLL, worst-horizon MAE, and worst-phase MAE.
#'
#' @return Selection metadata including selected_spec_id and selected_spec.
#'   Pareto ties are resolved by NLL, complexity, then
#'   lexicographic specification ID.
#' @export
select_m2_candidate <- function(results,
                                method = c("min_nll", "one_se", "pareto")) {
  method <- match.arg(method)
  tab <- .selection_metrics(results)
  tab <- tab[is.finite(tab$bernoulli_nll), , drop = FALSE]
  if (!nrow(tab)) stop("No candidate has a finite Bernoulli NLL.")
  tab <- tab[order(tab$bernoulli_nll, tab$complexity, tab$spec_id), , drop = FALSE]
  pareto_set <- NULL
  threshold <- NULL

  if (method == "min_nll") {
    selected <- tab[1L, , drop = FALSE]
  } else if (method == "one_se") {
    if (!is.data.frame(results$scores) ||
      !all(c("spec_id", "bernoulli_nll") %in% names(results$scores))) {
      stop("`one_se` selection requires fold-level `scores` with Bernoulli NLL.")
    }
    best_id <- tab$spec_id[1L]
    values <- results$scores$bernoulli_nll[as.character(results$scores$spec_id) == best_id]
    values <- values[is.finite(values)]
    if (length(values) < 2L) stop("`one_se` selection requires at least two finite folds for the best spec.")
    if (!any(is.finite(tab$complexity))) {
      stop("`one_se` selection requires grid complexity columns or `complexity`.")
    }
    threshold <- tab$bernoulli_nll[1L] + stats::sd(values) / sqrt(length(values))
    eligible <- tab[tab$bernoulli_nll <= threshold, , drop = FALSE]
    selected <- eligible[order(eligible$complexity, eligible$bernoulli_nll, eligible$spec_id, na.last = TRUE), , drop = FALSE][1L, , drop = FALSE]
  } else {
    if (!all(c("horizon_mae", "phase_mae") %in% names(tab))) {
      stop("`pareto` selection requires horizon and phase MAE metrics.")
    }
    complete <- is.finite(tab$horizon_mae) & is.finite(tab$phase_mae)
    if (!all(complete)) stop("`pareto` selection requires finite horizon and phase MAE metrics for every candidate.")
    metrics <- as.matrix(tab[, c("bernoulli_nll", "horizon_mae", "phase_mae")])
    dominated <- vapply(seq_len(nrow(tab)), function(i) {
      any(vapply(setdiff(seq_len(nrow(tab)), i), function(j) {
        all(metrics[j, ] <= metrics[i, ]) && any(metrics[j, ] < metrics[i, ])
      }, logical(1)))
    }, logical(1))
    pareto_set <- tab[!dominated, , drop = FALSE]
    selected <- pareto_set[order(pareto_set$bernoulli_nll, pareto_set$complexity, pareto_set$spec_id), , drop = FALSE][1L, , drop = FALSE]
  }
  id <- as.character(selected$spec_id[1L])
  list(
    method = method, selected_spec_id = id,
    selected_spec = .extract_selected_spec(results, id),
    selected = selected, pareto_set = pareto_set,
    one_se_threshold = threshold, candidates = tab
  )
}

#' Conservatively race M2 candidates before full nested LOSO
#'
#' @param grid Candidate grid containing spec_id.
#' @param evaluator Callback evaluator(grid, stage, ...) returning fold-level
#'   spec_id and bernoulli_nll rows for a partial stage.
#' @param stages Increasing deterministic stage sizes passed to evaluator.
#' @param min_survivors Minimum number retained at every stage.
#' @param confidence Confidence level for mean-NLL intervals.
#' @param full_evaluator Required callback run once on final survivors. It must
#'   perform full nested LOSO; partial racing results are never final rankings.
#' @param ... Additional callback arguments.
#'
#' @return Racing history, survivors, and the full evaluator result.
#' @export
race_m2_candidates <- function(grid,
                               evaluator,
                               stages = c(3L, 6L),
                               min_survivors = 3L,
                               confidence = 0.95,
                               full_evaluator,
                               ...) {
  grid <- as.data.frame(grid)
  if (!"spec_id" %in% names(grid) || anyDuplicated(grid$spec_id)) {
    stop("`grid` must contain unique `spec_id` values.")
  }
  if (!is.function(evaluator)) stop("`evaluator` must be a function.")
  if (missing(full_evaluator) || !is.function(full_evaluator)) {
    stop("`full_evaluator` is required so finalists undergo full nested LOSO.")
  }
  stages <- sort(unique(as.integer(stages)))
  if (!length(stages) || any(!is.finite(stages)) || any(stages < 2L)) {
    stop("`stages` must contain integers of at least 2.")
  }
  min_survivors <- max(1L, as.integer(min_survivors))
  survivors <- grid
  history <- vector("list", length(stages))

  for (i in seq_along(stages)) {
    partial <- as.data.frame(evaluator(survivors, stage = stages[i], ...))
    if (!all(c("spec_id", "bernoulli_nll") %in% names(partial))) {
      stop("Racing evaluator must return `spec_id` and `bernoulli_nll`.")
    }
    split_scores <- split(partial$bernoulli_nll, as.character(partial$spec_id))
    intervals <- do.call(rbind, lapply(names(split_scores), function(id) {
      x <- split_scores[[id]][is.finite(split_scores[[id]])]
      if (length(x) < 2L) stop("Each racing candidate needs at least two finite fold scores.")
      se <- stats::sd(x) / sqrt(length(x))
      half <- stats::qt((1 + confidence) / 2, df = length(x) - 1L) * se
      data.frame(spec_id = id, mean = mean(x), lower = mean(x) - half, upper = mean(x) + half)
    }))
    best_upper <- min(intervals$upper)
    keep_ids <- intervals$spec_id[intervals$lower <= best_upper]
    ranked <- intervals$spec_id[order(intervals$mean, intervals$spec_id)]
    keep_ids <- unique(c(keep_ids, utils::head(ranked, min(min_survivors, length(ranked)))))
    survivors <- survivors[as.character(survivors$spec_id) %in% keep_ids, , drop = FALSE]
    survivors <- survivors[match(keep_ids, as.character(survivors$spec_id), nomatch = 0L), , drop = FALSE]
    history[[i]] <- list(stage = stages[i], intervals = intervals, survivors = survivors$spec_id)
  }
  list(
    stages = history, survivors = survivors,
    final = full_evaluator(survivors, ...),
    final_evaluation = "full_nested_loso"
  )
}

#' Replay a season that was unseen by a pre-trained kit
#'
#' @param kit Pre-trained deployment kit.
#' @param allD Multi-season surveillance data.
#' @param season Holdout season to replay.
#' @param runner Injectable prospective runner; defaults to
#'   run_prospective_pipeline() in frozen mode.
#' @param ... Additional runner arguments.
#'
#' @return Replay predictions, standardized metrics, and explicit workflow
#'   fields. The holdout is not eligible to join training until separately
#'   compared with an incumbent using check_promotion().
#' @export
replay_season_holdout <- function(kit,
                                  allD,
                                  season = "2025-26",
                                  runner = run_prospective_pipeline,
                                  ...) {
  m2 <- kit$m2 %||% kit$m2_production %||% kit
  training_seasons <- as.character(m2$training_seasons %||% character(0))
  if (season %in% training_seasons) {
    stop("Holdout leakage: season `", season, "` is present in kit training seasons.")
  }
  allD <- prepare_surveillance_data(allD)
  current_data <- allD[as.character(allD$season) == season, , drop = FALSE]
  if (!nrow(current_data)) stop("Holdout season `", season, "` is absent from `allD`.")
  replay <- runner(kit, current_data, mode = "frozen", verbose = FALSE, ...)
  predictions <- .standardize_replay_predictions(replay, current_data, season)
  list(
    season = season,
    status = "unseen_replay_complete",
    predictions = predictions,
    metrics = summarize_forecast_metrics(predictions),
    eligible_for_refresh = FALSE,
    required_sequence = c(
      "historical_training", "unseen_holdout_replay", "promotion_gates",
      "refresh_including_holdout_for_next_season"
    ),
    next_step = "Compare candidate and incumbent metrics with check_promotion()."
  )
}

.standardize_replay_predictions <- function(replay, current_data, season) {
  standardized <- replay$predictions
  metric_columns <- c("p_hat", "lead", "t_since")
  observed_columns <- c("p_obs", "y_lead", "N_lead")
  if (is.data.frame(standardized) &&
    all(metric_columns %in% names(standardized)) &&
    ("p_obs" %in% names(standardized) ||
      all(c("y_lead", "N_lead") %in% names(standardized)))) {
    return(standardized)
  }

  raw <- replay$m2_preds
  required <- c("eval_week", "h", "target_weekF", "m2_p")
  if (!is.data.frame(raw) || !all(required %in% names(raw))) {
    stop(
      "Replay runner must return standardized `predictions` or prospective ",
      "`m2_preds` with eval_week, h, target_weekF, and m2_p."
    )
  }
  if (!all(c("weekF", "y", "N") %in% names(current_data)) &&
    !all(c("weekF", "p") %in% names(current_data))) {
    stop("Current holdout data need `weekF` plus `y`/`N` or `p` for scoring.")
  }
  target_index <- match(raw$target_weekF, current_data$weekF)
  n_trials <- if ("N" %in% names(current_data)) {
    as.numeric(current_data$N[target_index])
  } else {
    rep(1, nrow(raw))
  }
  positives <- if ("y" %in% names(current_data)) {
    as.numeric(current_data$y[target_index])
  } else {
    as.numeric(current_data$p[target_index]) * n_trials
  }
  p_obs <- if ("p" %in% names(current_data)) {
    as.numeric(current_data$p[target_index])
  } else {
    positives / n_trials
  }
  ignition <- replay$ign_out$ign_week_locked %||%
    replay$ign_out$iWeek_hat_locked %||% NA_integer_
  if (!is.finite(ignition)) {
    stop("Prospective replay did not return a finite locked ignition week.")
  }
  out <- data.frame(
    season = season,
    weekF = as.integer(raw$eval_week),
    lead = raw$h,
    t_since = as.numeric(raw$eval_week) - as.numeric(ignition),
    p_hat = as.numeric(raw$m2_p),
    p_obs = p_obs,
    y_lead = positives,
    N_lead = n_trials
  )
  out[is.finite(out$p_hat) & is.finite(out$p_obs) &
    is.finite(out$N_lead) & out$N_lead > 0, , drop = FALSE]
}
