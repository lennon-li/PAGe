#!/usr/bin/env Rscript
# Phase-weighted M2 subset development run.
#
# This wraps the existing all-season subset runner without overwriting its
# artifacts. It changes only the inner/outer primary score to a full
# post-ignition, target-phase-weighted weekly score: target t_since 0:12 gets
# weight 2 and later targets get weight 1. A post-run sensitivity table retains
# the corresponding test-count-weighted scores.

options(stringsAsFactors = FALSE)

root <- normalizePath(getwd(), mustWork = TRUE)
source_path <- file.path(root, "scripts", "publication_m2_subsets.R")
output <- Sys.getenv(
  "PAGE_M2_PHASE_WEIGHTED_OUTPUT",
  file.path(root, "manuscript/results/publication-repair-20260910/m2-phase-weighted-01")
)

if (!file.exists(source_path)) {
  stop("Missing source runner: ", source_path, call. = FALSE)
}

runner_env <- new.env(parent = globalenv())
sys.source(source_path, envir = runner_env)
runner_env$output <- output

phase_weight <- function(data) {
  t_target <- as.numeric(data$u) + as.numeric(data$h)
  ifelse(is.finite(t_target) & t_target >= 0 & t_target <= 12, 2, 1)
}

score_vector <- function(data, p, horizon, scheme = "phase_equal_week") {
  keep <- data$h == horizon & data$u >= 0 & is.finite(p)
  x <- data[keep, , drop = FALSE]
  p <- runner_env$clip_probability(p[keep])
  if (!nrow(x)) {
    return(data.frame(rows = 0L, trials = 0, nll = NA_real_, mae = NA_real_))
  }
  q_obs <- x$y_lead / x$N_lead
  loss <- -(q_obs * log(p) + (1 - q_obs) * log1p(-p))
  abs_error <- abs(p - q_obs)
  q_phase <- phase_weight(x)
  weights <- if (identical(scheme, "phase_test")) q_phase * x$N_lead else q_phase
  data.frame(
    rows = nrow(x), trials = sum(x$N_lead),
    nll = sum(weights * loss) / sum(weights),
    mae = sum(weights * abs_error) / sum(weights)
  )
}

# The original runner resolves score_vector in its source environment. Replace
# it before launching so all 11 outer folds and their inner folds use the new
# primary development score.
runner_env$score_vector <- score_vector
runner_env$run_experiment()

if (!file.exists(file.path(output, "status.json"))) {
  stop("Weighted run did not write status.json.", call. = FALSE)
}

# Rescore every retained outer prediction under both proposed weighting rules.
private_dir <- file.path(output, "private")
private_files <- sort(list.files(private_dir, pattern = "\\.rds$", full.names = TRUE))
if (!length(private_files)) stop("No per-season private artifacts were produced.", call. = FALSE)

score_prediction <- function(data, p, horizon, scheme) {
  keep <- data$h == horizon & data$u >= 0 & is.finite(p)
  x <- data[keep, , drop = FALSE]
  p <- runner_env$clip_probability(p[keep])
  if (!nrow(x)) return(NULL)
  q_obs <- x$y_lead / x$N_lead
  loss <- -(q_obs * log(p) + (1 - q_obs) * log1p(-p))
  abs_error <- abs(p - q_obs)
  q_phase <- phase_weight(x)
  weights <- if (identical(scheme, "phase_test")) q_phase * x$N_lead else q_phase
  data.frame(
    nll = sum(weights * loss) / sum(weights),
    mae = sum(weights * abs_error) / sum(weights),
    rows = nrow(x), trials = sum(x$N_lead),
    stringsAsFactors = FALSE
  )
}

metric_rows <- list()
for (path in private_files) {
  artifact <- readRDS(path)
  pred <- artifact$predictions
  season <- as.character(artifact$target_season)
  variants <- grep("^cfg_", names(pred), value = TRUE)
  variants <- c("m1", variants, "selected_grid")
  for (variant in variants) {
    p <- if (identical(variant, "m1")) pred$m1_p else pred[[variant]]
    if (is.null(p)) next
    for (h in 1:2) {
      for (scheme in c("phase_equal_week", "phase_test")) {
        sc <- score_prediction(pred, p, h, scheme)
        if (is.null(sc)) next
        metric_rows[[length(metric_rows) + 1L]] <- data.frame(
          season = season, horizon = h, variant = variant,
          weighting = scheme, sc, stringsAsFactors = FALSE
        )
      }
    }
  }
}

metrics <- do.call(rbind, metric_rows)
metrics$delta_m1_nll <- NA_real_
metrics$delta_m1_mae <- NA_real_
for (key in unique(paste(metrics$season, metrics$horizon, metrics$weighting, sep = "\r"))) {
  bits <- strsplit(key, "\r", fixed = TRUE)[[1L]]
  hit <- metrics$season == bits[1L] & metrics$horizon == as.integer(bits[2L]) &
    metrics$weighting == bits[3L]
  base <- metrics[hit & metrics$variant == "m1", , drop = FALSE]
  if (nrow(base) != 1L) next
  metrics$delta_m1_nll[hit] <- metrics$nll[hit] - base$nll[1L]
  metrics$delta_m1_mae[hit] <- metrics$mae[hit] - base$mae[1L]
}

aggregate_metrics <- do.call(rbind, lapply(
  split(metrics, list(metrics$horizon, metrics$variant, metrics$weighting), drop = TRUE),
  function(x) {
    data.frame(
      horizon = x$horizon[1L], variant = x$variant[1L], weighting = x$weighting[1L],
      equal_season_nll = mean(x$nll, na.rm = TRUE),
      equal_season_mae = mean(x$mae, na.rm = TRUE),
      mean_delta_m1_nll = mean(x$delta_m1_nll, na.rm = TRUE),
      mean_delta_m1_mae = mean(x$delta_m1_mae, na.rm = TRUE),
      seasons = sum(is.finite(x$nll)), stringsAsFactors = FALSE
    )
  }
))

utils::write.csv(metrics, file.path(output, "weighted_outer_metrics.csv"), row.names = FALSE)
utils::write.csv(aggregate_metrics, file.path(output, "weighted_outer_aggregate.csv"), row.names = FALSE)

protocol_path <- file.path(output, "weighted_protocol.txt")
writeLines(c(
  "M2 phase-weighted development run",
  "",
  "Primary development score: equal-season mean of equal-week Bernoulli cross-entropy.",
  "Within each season, target weeks with 0 <= target t_since <= 12 receive weight 2;",
  "later post-ignition target weeks receive weight 1. Both horizons are scored,",
  "with h2 retained as the primary reporting horizon and h1 secondary.",
  "",
  "Sensitivity: the same phase weights multiplied by target test count N_lead.",
  "The all-off candidate is the exact M1 offset and is retained in every fold.",
  "Existing unweighted/test-weighted artifacts were not overwritten.",
  "These are development and sensitivity results after prior outcome access;",
  "they do not replace the frozen confirmatory protocol retrospectively."
), protocol_path)

status <- jsonlite::read_json(file.path(output, "status.json"), simplifyVector = FALSE)
status$weighted_metrics_path <- file.path(output, "weighted_outer_metrics.csv")
status$weighted_aggregate_path <- file.path(output, "weighted_outer_aggregate.csv")
jsonlite::write_json(status, file.path(output, "status.json"), auto_unbox = TRUE, pretty = TRUE)

cat("Weighted phase run complete: ", output, "\n", sep = "")
