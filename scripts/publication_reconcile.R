#!/usr/bin/env Rscript
# Rebuild a unique comparison table and isolate the historical residual bug.
main <- function() {
  devtools::load_all("PAGe", quiet = TRUE)
  source("scripts/publication_comparator_helpers.R")
  base <- "manuscript/results/publication-repair-20260908"
  replay_dir <- file.path(base, "replay/20260908T125939")
  scores <- utils::read.csv(file.path(base, "comparators/season_scores.csv"))
  scores <- scores[, c("season", "model", "nll", "weighted_mae", "rows", "trials")]
  names(scores)[names(scores) == "weighted_mae"] <- "mae"
  source("scripts/publication_replay.R")
  repaired <- lapply(pc_seasons, function(s) {
    r <- readRDS(file.path(replay_dir, "private", paste0(s, ".rds")))
    m <- replay_metrics(r$predictions)
    m <- m[m$window == "h2_0_12", ]
    data.frame(season = s, model = "PAGe_repaired_runtime", nll = m$nll,
      mae = m$mae, rows = m$n, trials = m$trials)
  })
  scores <- rbind(scores, do.call(rbind, repaired))
  stopifnot(nrow(scores) == 66L,
    !anyDuplicated(paste(scores$season, scores$model)),
    all(table(scores$model) == 11L))
  utils::write.csv(scores, file.path(base, "comparison_h2_0_12.csv"), row.names = FALSE)
  aggregate <- stats::aggregate(cbind(nll, mae) ~ model, scores, mean)
  utils::write.csv(aggregate, file.path(base, "comparison_h2_0_12_aggregate.csv"), row.names = FALSE)

  # Use identical saved M1 curves and fitted kit in both residual variants.
  r <- readRDS(file.path(replay_dir, "private/2014-15.rds"))
  registry <- utils::read.csv("results/audit/holdout_reconciliation_principal.csv")
  entry <- registry[registry$season == "2014-15", ]
  archive <- file.path(sub("/mnt/nfsv4/Users/yeli/PAGe-artifacts",
    "/home/yeli/PAGe-bcc-artifacts", entry$run_dir, fixed = TRUE), "artifacts")
  kit_path <- file.path(archive, "candidate_pre_holdout.rds")
  kit <- readRDS(kit_path)
  input <- "/home/yeli/FLU/flu_testing_data.csv"
  stopifnot(digest::digest(file = input, algo = "sha256") == entry$input_sha256)
  d <- pc_read_data(input)
  names(d)[names(d) == "week"] <- "weekF"
  d <- PAGe::prepare_surveillance_data(d[d$season == "2014-15", ])
  parameters <- r$stages$m1_parameters
  m1 <- list(per_week = lapply(seq_len(nrow(parameters)), function(i) {
    ap <- as.list(parameters[i, ])
    ew <- ap$eval_week
    ap$forecast_df <- r$stages$m1_curves[r$stages$m1_curves$eval_week == ew, ]
    list(ew = ew, ap = ap, season_to_ew = d[d$weekF <= ew, ])
  }))
  ns <- asNamespace("PAGe")
  run <- function(legacy) {
    context <- new.env(parent = ns)
    if (legacy) {
      context$.m2_prediction_log <- function(prediction, target_weekF, h) {
        bl <- get("bl", envir = parent.frame(), inherits = FALSE)
        list(target_weekF = target_weekF, m2_p = prediction$m2_p,
          m2_eta_raw = qlogis(pmin(pmax(prediction$m2_p, 1e-6), 1 - 1e-6)) - bl,
          h = h)
      }
    }
    fn <- get("run_m2_forecast", envir = ns)
    environment(fn) <- context
    fn(kit, d, m1, mode = "frozen", verbose = FALSE)$m2_preds
  }
  corrected <- run(FALSE)
  legacy <- run(TRUE)
  key <- function(x) paste(x$eval_week, x$h, x$target_weekF)
  saved <- r$stages$m2_predictions
  stopifnot(!anyDuplicated(key(saved)), identical(key(corrected), key(legacy)))
  reproduction_error <- max(abs(corrected$m2_p - saved$m2_p[match(key(corrected), key(saved))]))
  stopifnot(reproduction_error < 1e-10)
  delta <- corrected$m2_p - legacy$m2_p
  i <- which.max(abs(delta))
  j <- which(corrected$eval_week == 28 & corrected$h == 1)
  out <- list(season = "2014-15", design = "Identical saved M1 and kit; only residual logging differs",
    corrected_reproduction_max_abs = reproduction_error,
    max_controlled_difference = delta[i], origin = corrected$eval_week[i], horizon = corrected$h[i],
    week28_h1_corrected = corrected$m2_p[j], week28_h1_legacy = legacy$m2_p[j],
    kit_sha256 = digest::digest(file = kit_path, algo = "sha256"),
    script_sha256 = digest::digest(file = "scripts/publication_reconcile.R", algo = "sha256"))
  old <- utils::read.csv(file.path(archive, "holdout_2014_15_predictions.csv"))
  out$archived_week28_h1 <- old$p_hat[old$weekF == 28 & old$lead == 1]
  out$legacy_minus_archive_week28_h1 <- legacy$m2_p[j] - out$archived_week28_h1
  jsonlite::write_json(out, file.path(base, "controlled_residual_comparison.json"),
    pretty = TRUE, auto_unbox = TRUE, digits = 16)
  print(out[c("corrected_reproduction_max_abs", "max_controlled_difference",
    "origin", "horizon", "legacy_minus_archive_week28_h1")])
}
if (sys.nframe() == 0L) main()
