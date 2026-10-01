#!/usr/bin/env Rscript
# Frozen-kit diagnostic only: no training, tuning, promotion or archive writes.
replay_metrics <- function(d) {
  if (any(!is.finite(d$p_hat) | !is.finite(d$p_obs) |
    !is.finite(d$N_lead) | d$N_lead <= 0)) stop("Invalid scorable rows")
  lead <- as.integer(sub("^h", "", d$lead))
  windows <- list(full = rep(TRUE, nrow(d)),
    h2_0_12 = lead == 2 & d$t_since >= 0 & d$t_since <= 12,
    h1_0_12 = lead == 1 & d$t_since >= 0 & d$t_since <= 12,
    h2_full = lead == 2)
  do.call(rbind, lapply(names(windows), function(w) {
    x <- d[which(windows[[w]]), ]
    p <- pmin(1 - 1e-12, pmax(1e-12, x$p_hat))
    avg <- function(v) if (nrow(x)) stats::weighted.mean(v, x$N_lead) else NA_real_
    data.frame(window = w, n = nrow(x), trials = sum(x$N_lead),
      nll = avg(-x$p_obs * log(p) - (1 - x$p_obs) * log1p(-p)),
      mae = avg(abs(x$p_hat - x$p_obs)),
      aggregate_positivity_mse = avg((x$p_hat - x$p_obs)^2),
      bernoulli_brier = avg(x$p_obs * (1 - x$p_hat)^2 +
        (1 - x$p_obs) * x$p_hat^2))
  }))
}

compare_predictions <- function(new, old) {
  key <- function(d) paste(d$season, d$weekF, sub("^h", "", d$lead))
  a <- key(new)
  b <- key(old)
  if (anyDuplicated(a) || anyDuplicated(b)) stop("Duplicate prediction keys")
  j <- match(a, b)
  delta <- new$p_hat - old$p_hat[j]
  good <- is.finite(delta)
  list(summary = data.frame(n_matched = sum(good),
    mean_delta = if (any(good)) mean(delta[good]) else NA_real_,
    max_abs_delta = if (any(good)) max(abs(delta[good])) else NA_real_),
    counts = list(new_only = sum(!a %in% b), old_only = sum(!b %in% a)))
}

validate_ledger <- function(l, d) {
  expected <- expand.grid(weekF = seq.int(min(d$weekF), max(d$weekF)), lead = 1:2)
  key <- function(x) paste(x$weekF, x$lead)
  if (anyDuplicated(key(l)) || !setequal(key(l), key(expected))) stop("Incomplete roster")
  if (any(l$target_weekF != l$weekF + l$lead)) stop("Invalid target")
  invisible(NULL)
}

run_publication_replay <- function() {
  devtools::load_all("PAGe", quiet = TRUE)
  future::plan(future::sequential)
  source("scripts/publication_comparator_helpers.R")
  input <- "/home/yeli/FLU/flu_testing_data.csv"
  hash <- function(f) digest::digest(file = f, algo = "sha256")
  d <- pc_read_data(input)
  names(d)[names(d) == "week"] <- "weekF"
  d <- PAGe::prepare_surveillance_data(d)
  registry <- utils::read.csv("results/audit/holdout_reconciliation_principal.csv")
  stopifnot(nrow(registry) == 11L, setequal(registry$season, pc_seasons))
  base <- "manuscript/results/publication-repair-20260908/replay"
  out <- file.path(base, format(Sys.time(), "%Y%m%dT%H%M%S"))
  if (!dir.create(out, recursive = TRUE)) stop("Output exists")
  dir.create(file.path(out, "private"))
  json <- function(x, name) jsonlite::write_json(x, file.path(out, name),
    auto_unbox = TRUE, pretty = TRUE, digits = 16, null = "null")
  files <- c(list.files("PAGe/R", full.names = TRUE, pattern = "[.]R$"),
    "PAGe/DESCRIPTION", "scripts/publication_replay.R",
    "scripts/publication_comparator_helpers.R")
  hashes <- setNames(vapply(files, hash, character(1)), files)
  json(list(input_sha256 = hash(input), source_sha256 = as.list(hashes),
    purpose = "Repaired runtime with archived frozen fits; not repaired training",
    session = capture.output(utils::sessionInfo())), "manifest.json")
  started <- Sys.time()
  summaries <- list()
  for (s in pc_seasons) {
    json(list(state = "running", season = s, completed = length(summaries)), "status.json")
    clock <- Sys.time()
    warnings <- character()
    result <- tryCatch(withCallingHandlers({
      row <- registry[registry$season == s, ]
      archive <- file.path(sub("/mnt/nfsv4/Users/yeli/PAGe-artifacts",
        "/home/yeli/PAGe-bcc-artifacts", row$run_dir, fixed = TRUE), "artifacts")
      m <- readRDS(file.path(archive, "run_manifest.rds"))
      stopifnot(identical(m$input_sha256, hash(input)),
        setequal(m$training_seasons, setdiff(pc_seasons, s)),
        setequal(m$exclude_seasons, pc_exclusions))
      kit_path <- file.path(archive, "candidate_pre_holdout.rds")
      kit <- readRDS(kit_path)
      r <- PAGe::replay_season_holdout(kit, d, season = s, kit_compatibility = "strict")
      validate_ledger(r$forecast_ledger, d[d$season == s, ])
      saveRDS(r, file.path(out, "private", paste0(s, ".rds")))
      old <- utils::read.csv(file.path(archive,
        paste0("holdout_", gsub("-", "_", s), "_predictions.csv")))
      list(season = s, status = r$status, ignition_week = r$ignition_week,
        reference_ignition = unname(m$manual_labels[s]),
        metrics = replay_metrics(r$predictions),
        comparison = compare_predictions(r$predictions, old),
        ledger = as.list(table(r$forecast_ledger$forecast_status)),
        kit_sha256 = hash(kit_path), archive_run = row$run_id)
    }, warning = function(w) {
      warnings <<- unique(c(warnings, conditionMessage(w)))
      invokeRestart("muffleWarning")
    }), error = function(e) list(season = s, status = "failed", error = conditionMessage(e)))
    result$elapsed_seconds <- as.numeric(difftime(Sys.time(), clock, units = "secs"))
    result$warnings <- warnings
    summaries[[s]] <- result
    json(summaries, "summary.json")
    message(s, ": ", result$status, " (", round(result$elapsed_seconds, 1), "s)")
  }
  unchanged <- identical(hashes, setNames(vapply(files, hash, character(1)), files))
  ok <- unchanged && all(vapply(summaries, function(x)
    identical(x$status, "unseen_replay_complete"), logical(1)))
  json(list(state = if (ok) "complete_diagnostic_only" else "failed",
    source_unchanged = unchanged, completed = length(summaries),
    elapsed_seconds = as.numeric(difftime(Sys.time(), started, units = "secs"))), "status.json")
  if (!ok) stop("Replay failures or source changes; inspect summary.json")
}

if (sys.nframe() == 0L) run_publication_replay()
