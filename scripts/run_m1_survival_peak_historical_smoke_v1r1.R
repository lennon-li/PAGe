#!/usr/bin/env Rscript

# Research-only, historical-smoke adapter for the M1 survival-peak v1r1 prototype.
# This deliberately cannot run a full historical LOSO experiment.

sp_m1sm_seasons <- c("2012-13", "2013-14", "2014-15", "2016-17", "2017-18",
  "2018-19", "2019-20", "2022-23", "2023-24", "2024-25", "2025-26")
sp_m1sm_outer <- c("2012-13", "2024-25")
sp_m1sm_origins <- 13:20

sp_m1sm_protocol <- function(run_id = "m1-survival-peak-v1r1-historical-smoke-only") {
  p <- sp_protocol(run_id)
  p$protocol_id <- "research_m1_survival_peak_v1r1"
  p$route <- "research_m1_survival_peak_v1r1"
  p$lambda <- c(3e-5, 1e-4, 3e-4, 1e-3, 3e-3, 1e-2, 3e-2, 1e-1, 3e-1, 1, 3, 10)
  p
}

sp_m1sm_hash_file <- function(path) {
  if (!file.exists(path) || dir.exists(path)) stop("Missing hash input: ", path, call. = FALSE)
  unname(tools::md5sum(path))
}

sp_m1sm_calendar <- function(root = normalizePath(".", mustWork = TRUE)) {
  # Derive season length independently from observed row coverage using the same
  # MMWR-year rule as PAGe's authoritative page_season_calendar().
  if (!requireNamespace("MMWRweek", quietly = TRUE))
    stop("MMWRweek is required for authoritative calendar derivation.", call. = FALSE)
  start_year <- as.integer(substr(sp_m1sm_seasons, 1L, 4L))
  W <- vapply(start_year, function(year) {
    52L + as.integer(MMWRweek::MMWRweek(as.Date(paste0(year, "-12-31")))$MMWRweek == 53L)
  }, integer(1))
  calendar_code <- normalizePath(file.path(root, "../PAGe-m1-v2/PAGe/R/season_calendar.R"), mustWork = TRUE)
  source_hash <- sp_m1sm_hash_file(calendar_code)
  data.frame(season = sp_m1sm_seasons, W = W,
    source = "PAGe page_season_calendar MMWR-year rule",
    source_hash = rep(source_hash, length(W)), authoritative = TRUE, stringsAsFactors = FALSE)
}


sp_m1sm_read_inputs <- function(root = normalizePath(".", mustWork = TRUE)) {
  weekly_path <- normalizePath(file.path(root, "../PAGe-m1-v2/artifacts/v3-joint-ab-audit-v1/canonical_ab_weekly_v3.csv"), mustWork = TRUE)
  timing_path <- normalizePath(file.path(root, "../PAGe-m1-v2/artifacts/v3-joint-timing-contract-v4/timing_contract_v4.csv"), mustWork = TRUE)
  eligibility_path <- normalizePath(file.path(root, "../PAGe-m1-v2/artifacts/v3-joint-timing-contract-v4/modeling_eligibility_v4.csv"), mustWork = TRUE)
  weekly <- utils::read.csv(weekly_path, stringsAsFactors = FALSE, check.names = FALSE)
  timing <- utils::read.csv(timing_path, stringsAsFactors = FALSE, check.names = FALSE)
  eligibility <- utils::read.csv(eligibility_path, stringsAsFactors = FALSE, check.names = FALSE)
  if (!all(c("season", "weekF", "y_A", "N_A") %in% names(weekly))) stop("Canonical weekly source schema mismatch.", call. = FALSE)
  if (!all(c("season", "A_peak_weekF", "A_peak_status") %in% names(timing))) stop("Timing contract source schema mismatch.", call. = FALSE)
  if (!all(c("season", "M1_A_eligible") %in% names(eligibility))) stop("Eligibility preflight schema mismatch.", call. = FALSE)
  weekly <- weekly[weekly$season %in% sp_m1sm_seasons, c("season", "weekF", "y_A", "N_A"), drop = FALSE]
  if (!setequal(unique(as.character(weekly$season)), sp_m1sm_seasons)) stop("Canonical weekly source lacks principal seasons.", call. = FALSE)
  observations <- data.frame(season = as.character(weekly$season), weekF = as.numeric(weekly$weekF),
    y = as.numeric(weekly$y_A), N = as.numeric(weekly$N_A), stringsAsFactors = FALSE)
  missing_counts <- is.na(observations$y) | is.na(observations$N)
  if (any(is.nan(observations$y) | is.nan(observations$N) | is.infinite(observations$y) | is.infinite(observations$N)) ||
      any(!missing_counts & (observations$N <= 0 | observations$y < 0 | observations$y > observations$N)))
    stop("Canonical A counts are invalid.", call. = FALSE)
  attr(observations, "source_hashes") <- list(canonical_ab_weekly_v3 = sp_m1sm_hash_file(weekly_path))
  timing <- timing[timing$season %in% sp_m1sm_seasons, , drop = FALSE]
  if (nrow(timing) != length(sp_m1sm_seasons) || anyDuplicated(timing$season) ||
      !setequal(as.character(timing$season), sp_m1sm_seasons)) stop("Timing source does not map all principal seasons exactly once.", call. = FALSE)
  if (any(as.character(timing$A_peak_status) != "retrospective_peak_truth") || any(!is.finite(timing$A_peak_weekF)))
    stop("All 11 principal A peaks must be finite retrospective_peak_truth labels.", call. = FALSE)
  labels <- data.frame(season = as.character(timing$season), P = as.numeric(timing$A_peak_weekF),
    stringsAsFactors = FALSE)
  attr(labels, "source_hashes") <- list(timing_contract_v4 = sp_m1sm_hash_file(timing_path))
  eligibility <- eligibility[eligibility$season %in% sp_m1sm_seasons, , drop = FALSE]
  if (nrow(eligibility) != length(sp_m1sm_seasons) || anyDuplicated(eligibility$season) ||
      !setequal(as.character(eligibility$season), sp_m1sm_seasons) ||
      anyNA(eligibility$M1_A_eligible) || any(!eligibility$M1_A_eligible))
    stop("M1 eligibility context is incomplete or blocks a principal season.", call. = FALSE)
  list(observations = observations, labels = labels, calendar = sp_m1sm_calendar(root),
    input_paths = c(canonical_ab_weekly_v3 = weekly_path, timing_contract_v4 = timing_path,
      modeling_eligibility_v4 = eligibility_path))
}

sp_m1sm_preflight <- function(root = normalizePath(".", mustWork = TRUE)) {
  protocol <- sp_m1sm_protocol()
  if (!identical(as.character(protocol$principal_seasons), sp_m1sm_seasons))
    stop("M1 v1 principal-season protocol mismatch.", call. = FALSE)
  inputs <- sp_m1sm_read_inputs(root)
  inputs$labels$mature <- TRUE
  inputs$labels <- sp_validate_labels(inputs$labels, sp_calendar_from_metadata(inputs$calendar, sp_m1sm_seasons), TRUE)
  # Exercise the prototype's isolation gate. This adapter is smoke-only even when
  # the delivery directory itself is not a git worktree.
  isolation <- sp_require_isolated_source(root, allow_smoke = TRUE)
  if (!isTRUE(isolation$smoke_only) && (!nzchar(isolation$commit) || !nzchar(isolation$branch)))
    stop("Source identity/isolation check failed.", call. = FALSE)
  inputs$preflight <- sp_preflight_panel(inputs$observations, inputs$labels, inputs$calendar, protocol,
    expected_isolation = is.list(isolation))
  # Restore actual content hashes for the manifest after preflight has exercised the
  # prototype's source-hash pathway.
  inputs$source_hashes <- list(
    canonical_ab_weekly_v3 = sp_m1sm_hash_file(inputs$input_paths[["canonical_ab_weekly_v3"]]),
    timing_contract_v4 = sp_m1sm_hash_file(inputs$input_paths[["timing_contract_v4"]]),
    modeling_eligibility_v4 = sp_m1sm_hash_file(inputs$input_paths[["modeling_eligibility_v4"]]))
  inputs$protocol <- protocol
  inputs$isolation <- isolation
  inputs
}

sp_m1sm_fold_provenance <- function() {
  rows <- list()
  add <- function(role, outer, validation = NA_character_, evaluated, excluded, materialized = FALSE) {
    allowed <- setdiff(sp_m1sm_seasons, excluded)
    data.frame(role = role, outer_season = outer, validation_season = validation,
      evaluated_season = evaluated, excluded_seasons = paste(sort(unique(excluded)), collapse = "|"),
      allowed_seasons = paste(sort(allowed), collapse = "|"), materialized = materialized,
      stringsAsFactors = FALSE)
  }
  for (outer in sp_m1sm_outer) {
    training <- setdiff(sp_m1sm_seasons, outer)
    rows[[length(rows) + 1L]] <- add("outer_prediction", outer, evaluated = outer, excluded = outer, materialized = TRUE)
    for (validation in sort(training)) {
      inner <- setdiff(training, validation)
      rows[[length(rows) + 1L]] <- add("inner_selection", outer, validation, validation, c(outer, validation))
      for (season in sort(inner))
        rows[[length(rows) + 1L]] <- add("inner_training_row", outer, validation, season, c(outer, validation, season))
    }
    for (season in sort(training))
      rows[[length(rows) + 1L]] <- add("outer_training_row", outer, evaluated = season, excluded = c(outer, season))
  }
  out <- do.call(rbind, rows); rownames(out) <- NULL
  for (i in seq_len(nrow(out))) {
    excluded <- strsplit(out$excluded_seasons[i], "|", fixed = TRUE)[[1L]]
    allowed <- strsplit(out$allowed_seasons[i], "|", fixed = TRUE)[[1L]]
    if (!setequal(c(allowed, excluded), sp_m1sm_seasons) || length(intersect(allowed, excluded)))
      stop("Fold exclusion/provenance identity mismatch.", call. = FALSE)
  }
  counts <- table(factor(out$role, levels = c("outer_prediction", "inner_selection", "inner_training_row", "outer_training_row")))
  if (!identical(as.integer(counts), c(2L, 20L, 180L, 20L)) || sum(out$materialized) != 2L)
    stop("Smoke fold table has unexpected roles/cardinality.", call. = FALSE)
  out
}


sp_m1sm_score <- function(predictions, labels, baseline_predictions) {
  detail <- function(pred, model) {
    ix <- match(pred$season, labels$season)
    if (anyNA(ix)) stop("Post-seal scoring truth missing.", call. = FALSE)
    do.call(rbind, lapply(seq_len(nrow(pred)), function(i) {
      pmf <- pred$pmf[[i]]; K <- labels$K[ix[i]]; support <- as.integer(names(pmf))
      q10 <- sp_quantile(pmf, support, .1); q90 <- sp_quantile(pmf, support, .9)
      data.frame(model = model, season = pred$season[i], origin = pred$origin[i], K = K,
        peak_week_log_loss = -log(max(pmf[as.character(K)], 1e-12)),
        median_absolute_error = abs(sp_quantile(pmf, support, .5) - K),
        mean_absolute_error = abs(sum(support * pmf) - K), coverage80 = as.numeric(K >= q10 && K <= q90),
        width80 = q90 - q10, gate_predicted = pred$pi[i], gate_observed = as.numeric(K <= pred$origin[i]),
        stringsAsFactors = FALSE)
    }))
  }
  d <- rbind(detail(predictions, "survival_peak"), detail(baseline_predictions, "empirical_peak_week_pmf"))
  summary <- do.call(rbind, lapply(split(d, d$model), function(x) data.frame(model = x$model[1L], n = nrow(x),
    peak_week_log_loss = mean(x$peak_week_log_loss), median_absolute_error = mean(x$median_absolute_error),
    mean_absolute_error = mean(x$mean_absolute_error), coverage80 = mean(x$coverage80),
    width80 = mean(x$width80), passed_gate_brier = mean((x$gate_predicted - x$gate_observed)^2),
    passed_gate_rate = mean(x$gate_observed), stringsAsFactors = FALSE)))
  hcal <- sp_horizon_cdf_calibration(predictions, labels, horizons = c(1L, 2L, 4L))
  horizon <- aggregate(cbind(predicted, observed) ~ horizon, hcal, mean)
  list(detail = d, summary = summary, horizon_calibration = horizon,
    passed_gate_calibration = sp_passed_calibration(predictions$pi,
      labels$K[match(predictions$season, labels$season)], predictions$origin))
}

sp_m1sm_run <- function(output_dir = file.path("artifacts", "m1-survival-peak-historical-smoke-v1r1"), root = normalizePath(".")) {
  x <- sp_m1sm_preflight(root)
  protocol <- x$protocol; observations <- x$observations; labels <- x$labels; calendar <- x$calendar
  candidates <- expand.grid(lambda = protocol$lambda, link = protocol$links, stringsAsFactors = FALSE)
  source_paths <- file.path(root, "scripts", paste0("m1_survival_peak_", c("protocol", "features", "model", "evaluate", "nested"), ".R"))
  source_paths <- c(source_paths, file.path(root, "scripts", "run_m1_survival_peak_historical_smoke_v1r1.R"))
  amendment_path <- file.path(root, "artifacts", "m1-survival-peak-v1r1", "penalty_grid_amendment.md")
  source_paths <- c(source_paths, amendment_path)
  source_hashes <- as.list(stats::setNames(vapply(source_paths, sp_m1sm_hash_file, character(1)), basename(source_paths)))
  manifest <- list(protocol_id = protocol$protocol_id, run_id = protocol$run_id, research_only = TRUE,
    historical_smoke_only = TRUE, production_decisions = FALSE, outer_seasons = sp_m1sm_outer,
    origins = sp_m1sm_origins, input_hashes = x$source_hashes, source_hashes = source_hashes,
    calendar_hash = sp_calendar_hash(calendar), calendar_source_hashes = as.list(calendar$source_hash),
    allowed_candidate_grid = candidates, prediction_scope = "two outer seasons x origins 13:20")
  if (dir.exists(output_dir) && length(list.files(output_dir, all.files = TRUE, no.. = TRUE))) {
    if (!file.exists(file.path(output_dir, "SEALED_COMPLETE.rds"))) stop("Refusing incomplete/corrupt resume directory.", call. = FALSE)
    sp_verify_seal(output_dir, manifest)
    pred <- readRDS(file.path(output_dir, "sealed_peak_predictions.rds"))
    baseline <- readRDS(file.path(output_dir, "sealed_empirical_baseline.rds"))
    scores <- sp_m1sm_score(pred, labels, baseline)
    utils::write.csv(scores$detail, file.path(output_dir, "post_seal_score_detail.csv"), row.names = FALSE)
    utils::write.csv(scores$summary, file.path(output_dir, "post_seal_score_summary.csv"), row.names = FALSE)
    utils::write.csv(scores$horizon_calibration, file.path(output_dir, "post_seal_horizon_calibration.csv"), row.names = FALSE)
    utils::write.csv(scores$passed_gate_calibration, file.path(output_dir, "post_seal_passed_gate_calibration.csv"), row.names = FALSE)
    return(invisible(list(seal = readRDS(file.path(output_dir, "SEALED_COMPLETE.rds")), scores = scores)))
  }
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(data.frame(input = names(x$input_paths), path = unname(x$input_paths),
    md5 = unlist(x$source_hashes), read_only = TRUE), file.path(output_dir, "read_only_input_hashes.csv"), row.names = FALSE)
  utils::write.csv(data.frame(source = names(source_hashes), md5 = unlist(source_hashes),
    stringsAsFactors = FALSE), file.path(output_dir, "source_hashes.csv"), row.names = FALSE)
  utils::write.csv(calendar, file.path(output_dir, "calendar_manifest.csv"), row.names = FALSE)
  utils::write.csv(sp_m1sm_fold_provenance(), file.path(output_dir, "fold_provenance.csv"), row.names = FALSE)
  utils::write.csv(data.frame(season = sp_m1sm_outer, origins = paste(sp_m1sm_origins, collapse = "|"),
    materialized_predictions = TRUE, stringsAsFactors = FALSE), file.path(output_dir, "prediction_scope.csv"), row.names = FALSE)
  saveRDS(manifest, file.path(output_dir, "source_manifest.rds"), version = 3)
  writeLines(c("RESEARCH-ONLY", "HISTORICAL-SMOKE-ONLY", "NO PRODUCTION DECISIONS"),
    file.path(output_dir, "run_scope.txt"))

  features <- sp_build_panel(observations, x$preflight$calendar, protocol)
  requested <- features[features$season %in% sp_m1sm_outer & features$weekF %in% sp_m1sm_origins, , drop = FALSE]
  expected <- expand.grid(season = sp_m1sm_outer, weekF = sp_m1sm_origins, stringsAsFactors = FALSE)
  if (anyDuplicated(requested[c("season", "weekF")]) ||
      !identical(sort(paste(requested$season, requested$weekF)), sort(paste(expected$season, expected$weekF))))
    stop("Smoke origins are duplicate or missing in canonical observations.", call. = FALSE)
  predictions <- vector("list", length(sp_m1sm_outer)); baseline_predictions <- vector("list", length(sp_m1sm_outer))
  provenance <- list()
  for (i in seq_along(sp_m1sm_outer)) {
    outer <- sp_m1sm_outer[i]; allowed <- setdiff(sp_m1sm_seasons, outer)
    train_features <- features[features$season %in% allowed, , drop = FALSE]
    train_labels <- labels[labels$season %in% allowed, , drop = FALSE]
    sp_assert_allowed_labels(train_labels, allowed)
    fitted <- sp_fit_allowed(train_features, train_labels, allowed, protocol, candidates, calendar)
    if (isTRUE(fitted$boundary_unresolved)) stop("Selected penalty remains on expanded edge; fail closed.", call. = FALSE)
    ev <- requested[requested$season == outer, , drop = FALSE]
    predictions[[i]] <- sp_predict_features(fitted, ev, calendar, protocol)
    predictions[[i]]$outer_season <- outer
    predictions[[i]]$fitted_seasons <- paste(sort(allowed), collapse = "|")
    predictions[[i]]$selection_seasons <- paste(sort(allowed), collapse = "|")
    baseline <- lapply(seq_len(nrow(ev)), function(j) {
      W <- unname(x$preflight$calendar[[outer]])
      pmf <- sp_empirical_pmf(train_labels, W, seq_len(W))
      dist <- list(pmf = pmf, pi = sum(pmf[seq_len(ev$weekF[j])]))
      sp_prediction_fields(dist, ev[j, , drop = FALSE], W)
    })
    baseline_predictions[[i]] <- do.call(rbind, baseline)
    baseline_predictions[[i]]$outer_season <- outer
    baseline_predictions[[i]]$fitted_seasons <- paste(sort(allowed), collapse = "|")
    baseline_predictions[[i]]$selection_seasons <- paste(sort(allowed), collapse = "|")
    provenance[[i]] <- data.frame(outer_season = outer, fitted_seasons = paste(sort(allowed), collapse = "|"),
      selection_seasons = paste(sort(allowed), collapse = "|"), selected_lambda = fitted$selected$lambda,
      selected_link = fitted$selected$link, boundary_expanded = fitted$boundary_expanded,
      boundary_unresolved = fitted$boundary_unresolved, stringsAsFactors = FALSE)
  }
  pred <- do.call(rbind, predictions); baseline <- do.call(rbind, baseline_predictions)
  expected_keys <- expand.grid(season = sp_m1sm_outer, origin = sp_m1sm_origins, stringsAsFactors = FALSE)
  if (nrow(pred) != nrow(expected_keys) || anyDuplicated(pred[c("season", "origin")]) ||
      !identical(sort(paste(pred$season, pred$origin)), sort(paste(expected_keys$season, expected_keys$origin))))
    stop("Sealed prediction key set has duplicate/missing smoke rows.", call. = FALSE)
  if (any(c("K", "P", "mature") %in% names(pred)) || any(!is.finite(vapply(pred$pmf, sum, numeric(1)))))
    stop("Truth leakage or invalid sealed predictions.", call. = FALSE)
  saveRDS(baseline, file.path(output_dir, "sealed_empirical_baseline.rds"), version = 3)
  utils::write.csv(do.call(rbind, provenance), file.path(output_dir, "outer_fit_provenance.csv"), row.names = FALSE)
  sealed <- sp_seal_predictions(pred, output_dir, manifest)
  sp_verify_seal(output_dir, manifest)
  writeLines(c("status=SEALED_COMPLETE", paste0("prediction_md5=", sealed$prediction_hash)),
    file.path(output_dir, "SEALED_COMPLETE"))
  scores <- sp_m1sm_score(readRDS(file.path(output_dir, "sealed_peak_predictions.rds")), labels, baseline)
  utils::write.csv(scores$detail, file.path(output_dir, "post_seal_score_detail.csv"), row.names = FALSE)
  utils::write.csv(scores$summary, file.path(output_dir, "post_seal_score_summary.csv"), row.names = FALSE)
  utils::write.csv(scores$horizon_calibration, file.path(output_dir, "post_seal_horizon_calibration.csv"), row.names = FALSE)
  utils::write.csv(scores$passed_gate_calibration, file.path(output_dir, "post_seal_passed_gate_calibration.csv"), row.names = FALSE)
  invisible(list(seal = sealed, scores = scores))
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  if (any(args %in% c("--full", "--full-loso", "--historical-loso", "--mode=full")))
    stop("Full historical LOSO is refused by this bounded smoke adapter.", call. = FALSE)
  if (!"--authorize-historical-smoke" %in% args)
    stop("Historical smoke requires explicit --authorize-historical-smoke authorization.", call. = FALSE)
  if (any(args %in% c("--historical", "--authorize-historical")))
    stop("Use --authorize-historical-smoke; broad historical authorization is not accepted.", call. = FALSE)
  root <- normalizePath(".", mustWork = TRUE)
  for (nm in c("protocol", "features", "model", "evaluate", "nested")) {
    path <- file.path(root, "scripts", paste0("m1_survival_peak_", nm, ".R"))
    if (!file.exists(path)) stop("Missing survival source: ", path, call. = FALSE)
    sys.source(path, envir = .GlobalEnv)
  }
  out_arg <- match("--output-dir", args)
  output_dir <- if (!is.na(out_arg) && out_arg < length(args)) args[[out_arg + 1L]] else
    file.path("artifacts", "m1-survival-peak-historical-smoke-v1r1")
  if (!is.na(out_arg) && out_arg == length(args)) stop("--output-dir requires a path.", call. = FALSE)
  result <- tryCatch(sp_m1sm_run(output_dir, root), error = function(e) {
    cat("FAIL: ", conditionMessage(e), "\n", sep = ""); quit(save = "no", status = 2L)
  })
  cat(sprintf("PASS: research-only historical smoke sealed %d rows at %s\n", result$seal$row_count,
    normalizePath(output_dir, mustWork = TRUE)))
  print(result$scores$summary, row.names = FALSE)
}
