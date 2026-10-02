sp_split <- function(x) if (is.na(x) || !nzchar(x)) character() else strsplit(as.character(x), "|", fixed = TRUE)[[1L]]

sp_fold_index <- function(protocol = sp_protocol()) {
  seasons <- as.character(protocol$principal_seasons); out <- list()
  add <- function(role, outer, validation = NA_character_, evaluated, excluded) {
    allowed <- setdiff(seasons, excluded)
    data.frame(fold_role = role, outer_season = outer, validation_season = validation,
      evaluated_row_season = evaluated, excluded_seasons = paste(sort(unique(excluded)), collapse = "|"),
      allowed_seasons = paste(sort(allowed), collapse = "|"), stringsAsFactors = FALSE)
  }
  for (O in seasons) {
    T <- setdiff(seasons, O); out[[length(out) + 1L]] <- add("outer", O, evaluated = O, excluded = O)
    for (V in T) {
      R <- setdiff(T, V); out[[length(out) + 1L]] <- add("inner_validation", O, V, V, c(O, V))
      for (s in R) out[[length(out) + 1L]] <- add("inner_training_row", O, V, s, c(O, V, s))
    }
    for (s in T) out[[length(out) + 1L]] <- add("outer_training_row", O, evaluated = s, excluded = c(O, s))
  }
  z <- do.call(rbind, out); rownames(z) <- NULL; sp_assert_fold_index(z, protocol); z
}

sp_assert_fold_row <- function(row, protocol = sp_protocol()) {
  z <- as.list(row[1, , drop = FALSE]); O <- as.character(z$outer_season)
  V <- as.character(z$validation_season); s <- as.character(z$evaluated_row_season)
  if (!O %in% protocol$principal_seasons || !s %in% protocol$principal_seasons) stop("Unknown fold season.", call. = FALSE)
  expected <- switch(as.character(z$fold_role), outer = O, inner_validation = c(O, V),
    inner_training_row = c(O, V, s), outer_training_row = c(O, s), stop("Unknown fold role.", call. = FALSE))
  expected <- sort(unique(expected[!is.na(expected) & nzchar(expected)]))
  allowed <- setdiff(as.character(protocol$principal_seasons), expected)
  if (!identical(sort(sp_split(z$excluded_seasons)), expected)) stop("Fold exclusion identity mismatch.", call. = FALSE)
  if (!identical(sort(sp_split(z$allowed_seasons)), sort(allowed))) stop("Fold allowed-set identity mismatch.", call. = FALSE)
  if (length(expected) != switch(z$fold_role, outer = 1L, inner_validation = 2L, inner_training_row = 3L, outer_training_row = 2L))
    stop("Fold role cardinality mismatch.", call. = FALSE)
  invisible(TRUE)
}

sp_assert_fold_index <- function(index, protocol = sp_protocol()) {
  if (!is.data.frame(index) || !all(c("fold_role", "outer_season", "validation_season", "evaluated_row_season", "excluded_seasons", "allowed_seasons") %in% names(index))) stop("Malformed fold index.", call. = FALSE)
  if (nrow(index) != 1221L || anyDuplicated(index[c("fold_role", "outer_season", "validation_season", "evaluated_row_season")])) stop("Fold table is incomplete, duplicated, or has wrong cardinality.", call. = FALSE)
  counts <- table(factor(index$fold_role, levels = c("outer", "inner_validation", "inner_training_row", "outer_training_row")))
  if (!identical(as.integer(counts), c(11L, 110L, 990L, 110L))) stop("Four-role fold counts are incomplete.", call. = FALSE)
  invisible(lapply(seq_len(nrow(index)), function(i) sp_assert_fold_row(index[i, , drop = FALSE], protocol)))
  invisible(TRUE)
}

sp_assert_allowed_labels <- function(labels, allowed) {
  if (!is.data.frame(labels) || !"season" %in% names(labels)) stop("Labels need season identity.", call. = FALSE)
  if (!setequal(unique(as.character(labels$season)), as.character(allowed))) stop("Training labels do not equal allowed set.", call. = FALSE)
  invisible(TRUE)
}

sp_fit_allowed <- function(features, labels, allowed_seasons, protocol = sp_protocol(), candidates = NULL, calendar_metadata = NULL) {
  allowed <- sort(as.character(allowed_seasons)); features <- as.data.frame(features); labels <- as.data.frame(labels)
  if (!setequal(unique(as.character(features$season)), allowed)) stop("Feature seasons do not equal allowed set.", call. = FALSE)
  sp_assert_allowed_labels(labels, allowed)
  if (is.null(candidates)) candidates <- expand.grid(lambda = protocol$lambda, link = protocol$links, stringsAsFactors = FALSE)
  fit <- sp_select_and_fit(features, labels, protocol, candidates, calendar_metadata)
  if (isTRUE(fit$boundary_unresolved)) stop("Selected penalty remains on expanded edge; fail closed.", call. = FALSE)
  fit
}

sp_predict_features <- function(fitted, features, calendar_metadata, protocol = sp_protocol()) {
  cal <- sp_calendar_from_metadata(calendar_metadata)
  p <- as.data.frame(features, stringsAsFactors = FALSE)
  if (!all(c("season", "weekF") %in% names(p)) || any(!p$season %in% names(cal))) stop("Prediction seasons lack independent calendar metadata.", call. = FALSE)
  if (any(p$weekF > unname(cal[as.character(p$season)]))) stop("Prediction origin exceeds calendar metadata.", call. = FALSE)
  scaled <- sp_apply_feature_scaler(p, fitted$scaler, protocol)
  rows <- lapply(seq_len(nrow(scaled)), function(i) {
    s <- as.character(scaled$season[i]); W <- unname(cal[[s]])
    z <- sp_predict_distribution(fitted$fit, scaled[i, , drop = FALSE], W, protocol)
    sp_prediction_fields(z, scaled[i, , drop = FALSE], W)
  })
  do.call(rbind, rows)
}

sp_smoke_fit_predict <- function(observations, labels, calendar_metadata = NULL, protocol = sp_protocol()) {
  lab <- as.data.frame(labels, stringsAsFactors = FALSE)
  if (is.null(calendar_metadata)) stop("Synthetic predictions require independently supplied calendar metadata.", call. = FALSE)
  cal <- sp_calendar_from_metadata(calendar_metadata)
  features <- sp_build_panel(observations, cal, protocol)
  fit <- sp_fit_allowed(features, lab, lab$season, protocol, expand.grid(lambda = 1, link = "logit", stringsAsFactors = FALSE), calendar_metadata)
  pred <- sp_predict_features(fit, features, calendar_metadata, protocol)
  pmf <- do.call(rbind, lapply(pred$pmf, function(x) { z <- numeric(53L); z[as.integer(names(x))] <- x; z }))
  list(fit = fit, predictions = pred, pmf = pmf)
}

sp_crossfit_rows <- function(features, labels, row_seasons, m2_allowed, calendar_metadata, protocol = sp_protocol(), candidates = NULL) {
  if (!all(row_seasons %in% m2_allowed)) stop("Cross-fit rows must be within M2 allowed set.", call. = FALSE)
  rows <- provenance <- list()
  for (s in sort(as.character(row_seasons))) {
    allowed <- setdiff(as.character(m2_allowed), s)
    fit <- sp_fit_allowed(features[features$season %in% allowed, , drop = FALSE], labels[labels$season %in% allowed, , drop = FALSE], allowed, protocol, candidates, calendar_metadata)
    ev <- features[features$season == s, , drop = FALSE]
    rows[[length(rows) + 1L]] <- sp_predict_features(fit, ev, calendar_metadata, protocol)
    provenance[[length(provenance) + 1L]] <- data.frame(row_season = s, fitted_seasons = paste(allowed, collapse = "|"),
      selection_seasons = paste(allowed, collapse = "|"), feature_season = s, truth_join_after_prediction = TRUE, stringsAsFactors = FALSE)
  }
  list(predictions = do.call(rbind, rows), provenance = do.call(rbind, provenance))
}

sp_role_allowed <- function(row) sp_split(row$allowed_seasons)
sp_role_predict <- function(row, features, labels, calendar_metadata, protocol, candidates, fit_cache = NULL) {
  s <- as.character(row$evaluated_row_season); allowed <- sp_role_allowed(row)
  sp_assert_fold_row(row, protocol)
  cache_key <- paste(sort(allowed), collapse = "|")
  fit <- if (!is.null(fit_cache) && exists(cache_key, envir = fit_cache, inherits = FALSE)) {
    get(cache_key, envir = fit_cache, inherits = FALSE)
  } else {
    value <- sp_fit_allowed(features[features$season %in% allowed, , drop = FALSE], labels[labels$season %in% allowed, , drop = FALSE], allowed, protocol, candidates, calendar_metadata)
    if (!is.null(fit_cache)) assign(cache_key, value, envir = fit_cache)
    value
  }
  ev <- features[features$season == s, , drop = FALSE]
  if (!nrow(ev)) stop("Incomplete fold: evaluated feature season has no rows.", call. = FALSE)
  pred <- sp_predict_features(fit, ev, calendar_metadata, protocol)
  pred$fold_role <- row$fold_role; pred$outer_season <- row$outer_season; pred$validation_season <- row$validation_season
  pred$fitted_seasons <- paste(allowed, collapse = "|"); pred$selection_seasons <- paste(allowed, collapse = "|")
  pred
}

sp_hash_file <- function(path) unname(tools::md5sum(path))
sp_hash_object <- function(x) {
  path <- tempfile(); on.exit(unlink(path), add = TRUE); saveRDS(x, path, version = 3); sp_hash_file(path)
}
sp_seal_predictions <- function(predictions, output_dir, source_manifest) {
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  if (any(grepl("(^K$|^P$|truth|target_y|target_N|scoreability)", names(predictions), ignore.case = TRUE))) stop("Truth-derived column present before sealing.", call. = FALSE)
  path <- file.path(output_dir, "sealed_peak_predictions.rds"); saveRDS(predictions, path, version = 3)
  hash <- sp_hash_file(path)
  manifest <- list(status = "SEALED_COMPLETE", row_count = nrow(predictions), prediction_hash = hash,
    source_manifest = source_manifest, sealed_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE))
  saveRDS(manifest, file.path(output_dir, "SEALED_COMPLETE.rds"), version = 3)
  manifest
}

sp_verify_seal <- function(output_dir, expected_source_manifest = NULL) {
  marker <- file.path(output_dir, "SEALED_COMPLETE.rds"); pred <- file.path(output_dir, "sealed_peak_predictions.rds")
  if (!file.exists(marker) || !file.exists(pred)) stop("Incomplete sealed run.", call. = FALSE)
  m <- readRDS(marker)
  if (!identical(m$status, "SEALED_COMPLETE") || !identical(m$prediction_hash, sp_hash_file(pred))) stop("Corrupt sealed prediction artifact.", call. = FALSE)
  if (!is.null(expected_source_manifest) && !identical(m$source_manifest, expected_source_manifest)) stop("Resume source mismatch.", call. = FALSE)
  if (!identical(as.integer(m$row_count), as.integer(nrow(readRDS(pred))))) stop("Sealed row count mismatch.", call. = FALSE)
  invisible(m)
}

sp_score_sealed <- function(output_dir, labels, expected_source_manifest = NULL) {
  sp_verify_seal(output_dir, expected_source_manifest)
  sp_score_predictions(readRDS(file.path(output_dir, "sealed_peak_predictions.rds")), labels)
}

sp_m2_contract <- function(peak_fields_h1, peak_fields_h2, training_rows, m1_offset, common_ledger) {
  required <- c("season", "origin", "peak_weekF_origin", "peak_weekF_lo", "peak_weekF_hi", "peak_ci_width")
  if (!all(required %in% names(peak_fields_h1)) || !all(required %in% names(peak_fields_h2))) stop("M2 peak fields incomplete.", call. = FALSE)
  if (!identical(peak_fields_h1[required], peak_fields_h2[required])) stop("h1/h2 peak fields must be duplicate origin values.", call. = FALSE)
  if (!identical(attr(peak_fields_h1, "ledger_hash"), attr(peak_fields_h2, "ledger_hash")) ||
      !identical(attr(peak_fields_h1, "ledger_hash"), common_ledger)) stop("M2 common-ledger identity mismatch.", call. = FALSE)
  widths <- as.numeric(training_rows$peak_ci_width); pos <- widths[is.finite(widths) & widths > 0]
  if (!length(pos)) stop("Confidence candidates require positive training width support.", call. = FALSE)
  w_ref <- stats::median(pos)
  width_scale <- ifelse(is.na(peak_fields_h1$peak_ci_width), 1,
    ifelse(peak_fields_h1$peak_ci_width <= 0, 0, pmin(1, peak_fields_h1$peak_ci_width / w_ref)))
  list(w_ref = w_ref, width_scale = width_scale, m1_offset = m1_offset, ledger_hash = common_ledger,
       h1_h2_identical = TRUE)
}
