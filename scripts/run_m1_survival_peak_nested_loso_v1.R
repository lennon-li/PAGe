#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = TRUE)
output_arg <- match("--output-dir", args)
output_dir <- if (!is.na(output_arg) && output_arg < length(args)) args[[output_arg + 1L]] else NULL
historical_mode <- "--historical" %in% args
authorized <- "--authorize-historical" %in% args
if (historical_mode && !authorized) stop("Historical mode requires explicit --authorize-historical.", call. = FALSE)
if (historical_mode) stop("Historical adapter is hard-disabled in this bounded prototype.", call. = FALSE)
if (!"--synthetic-smoke" %in% args) stop("Only --synthetic-smoke is enabled; historical mode is hard-disabled.", call. = FALSE)
thread_vars <- c("OPENBLAS_NUM_THREADS", "OMP_NUM_THREADS", "MKL_NUM_THREADS", "VECLIB_MAXIMUM_THREADS", "BLIS_NUM_THREADS")
do.call(Sys.setenv, as.list(stats::setNames(rep("1", length(thread_vars)), thread_vars)))
root <- normalizePath(".", mustWork = TRUE)
for (nm in c("protocol", "features", "model", "evaluate", "nested")) {
  path <- file.path(root, "scripts", paste0("m1_survival_peak_", nm, ".R"))
  if (!file.exists(path)) stop("Missing survival source: ", path, call. = FALSE)
  sys.source(path, envir = .GlobalEnv)
}
sp_assert_single_thread_blas <- function() {
  vars <- c("OPENBLAS_NUM_THREADS", "OMP_NUM_THREADS", "MKL_NUM_THREADS", "VECLIB_MAXIMUM_THREADS", "BLIS_NUM_THREADS")
  if (any(Sys.getenv(vars) != "1")) stop("BLAS/OpenMP thread environment must be one thread.", call. = FALSE)
  invisible(TRUE)
}
sp_run_synthetic_executor <- function(output_dir = file.path(root, "artifacts", "m1-survival-peak-v1", "synthetic-run")) {
  sp_assert_single_thread_blas()
  protocol <- sp_protocol("m1-survival-peak-v1-synthetic-full-roles")
  set.seed(protocol$seed); seasons <- protocol$principal_seasons
  W <- setNames(rep(52L, length(seasons)), seasons); W[["2019-20"]] <- 53L
  calendar <- data.frame(season = seasons, W = unname(W), source = "synthetic-protocol-fixture",
    source_hash = vapply(seasons, function(s) paste0("fixture-", s), character(1)), authoritative = TRUE, stringsAsFactors = FALSE)
  cal <- sp_calendar_from_metadata(calendar, seasons)
  weeks <- do.call(rbind, lapply(seq_along(seasons), function(i) {
    w <- 10:13; n <- rep(40L, length(w)); y <- pmin(n, pmax(0L, round(stats::plogis(-2.4 + .12 * w + i / 9 + sin(w / 4) / 3) * n)))
    data.frame(season = seasons[i], weekF = w, y = y, N = n)
  }))
  labels <- data.frame(season = seasons, P = 18 + (seq_along(seasons) %% 5) + .5,
    K = as.integer(floor(18 + (seq_along(seasons) %% 5) + 1)), W = unname(cal[seasons]), mature = TRUE)
  lab <- sp_validate_labels(labels, cal)
  ledger <- sp_build_origin_ledgers(weeks, cal, protocol)
  features <- sp_build_panel(weeks, cal, protocol)
 if (nrow(features) != nrow(ledger$eligible)) stop("Synthetic eligible-origin ledger incomplete.", call. = FALSE)
  fold <- sp_fold_index(protocol)
  candidates <- expand.grid(lambda = 1, link = "logit", stringsAsFactors = FALSE)
  source_files <- file.path(root, "scripts", paste0("m1_survival_peak_", c("protocol", "features", "model", "evaluate", "nested"), ".R"))
  manifest <- list(protocol_id = protocol$protocol_id, source_hashes = as.list(tools::md5sum(source_files)),
    fixture_hashes = list(observations = sp_hash_object(weeks), labels = sp_hash_object(lab), calendar = sp_calendar_hash(calendar)),
    calendar_hash = sp_calendar_hash(calendar), allowed_candidate_grid = candidates, historical = FALSE)
  if (dir.exists(output_dir) && length(list.files(output_dir, all.files = TRUE, no.. = TRUE))) {
    if (!file.exists(file.path(output_dir, "SEALED_COMPLETE.rds"))) stop("Refusing incomplete/corrupt resume directory.", call. = FALSE)
    sp_verify_seal(output_dir, manifest); return(invisible(readRDS(file.path(output_dir, "SEALED_COMPLETE.rds"))))
  }
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(fold, file.path(output_dir, "fold_index.csv"), row.names = FALSE)
  utils::write.csv(ledger$scheduled, file.path(output_dir, "scheduled_ledger.csv"), row.names = FALSE)
  utils::write.csv(ledger$eligible, file.path(output_dir, "eligible_ledger.csv"), row.names = FALSE)
  utils::write.csv(ledger$unavailable, file.path(output_dir, "unavailable_ledger.csv"), row.names = FALSE)
  predictions <- vector("list", nrow(fold))
  fit_cache <- new.env(parent = emptyenv())
  for (i in seq_len(nrow(fold))) predictions[[i]] <- sp_role_predict(fold[i, , drop = FALSE], features, lab, calendar, protocol, candidates, fit_cache)
  pred <- do.call(rbind, predictions)
  if (nrow(pred) != 1221L || anyDuplicated(pred[c("fold_role", "outer_season", "validation_season", "season", "origin")])) stop("Synthetic executor produced incomplete/duplicate fold predictions.", call. = FALSE)
  if (any(c("K", "P", "mature") %in% names(pred))) stop("Truth leaked into prediction artifacts.", call. = FALSE)
  provenance <- unique(pred[c("fold_role", "outer_season", "validation_season", "season", "fitted_seasons", "selection_seasons")])
  utils::write.csv(provenance, file.path(output_dir, "source_selection_sets.csv"), row.names = FALSE)
  utils::write.csv(calendar, file.path(output_dir, "calendar_manifest.csv"), row.names = FALSE)
  saveRDS(manifest, file.path(output_dir, "source_manifest.rds"), version = 3)
  # The seal is written only after all declared roles and truth-free predictions are complete.
  sealed_manifest <- sp_seal_predictions(pred, output_dir, manifest)
  sp_verify_seal(output_dir, manifest)
  sealed_manifest
}
if (sys.nframe() == 0L) {
  tryCatch({
    if (!is.null(output_dir)) {
      if (any(args == "--output-dir") && output_arg == length(args)) stop("--output-dir requires a path.", call. = FALSE)
      result <- sp_run_synthetic_executor(output_dir)
    } else result <- sp_run_synthetic_executor()
    cat(sprintf("PASS: synthetic four-role execution sealed %d truth-free prediction rows; hash=%s\n", result$row_count, result$prediction_hash))
  }, error = function(e) { cat("FAIL: ", conditionMessage(e), "\n", sep = ""); quit(save = "no", status = 2) })
}
