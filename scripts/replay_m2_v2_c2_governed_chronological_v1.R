#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE)

source("PAGe/R/m1_v2.R")
source("PAGe/R/m2_v2_research.R")
source("PAGe/R/m2_v2_c2_governed.R")

if (!requireNamespace("digest", quietly = TRUE) ||
    !requireNamespace("jsonlite", quietly = TRUE)) {
  stop("digest and jsonlite are required.")
}

out_dir <- "artifacts/m2-v2-c2-governed-chronological-v1"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

ledger_path <- "artifacts/m2-v2-ab-curve-ratio-chronological-c123-v2/candidate_independent_ledger.csv"
reference_path <- "artifacts/m2-v2-ab-curve-ratio-chronological-c123-v2/fixed_c2_predictions.csv"
shape_path <- "artifacts/m2-v2-flu-ab-geometry-v1/peak_aligned_normalized_shape_grid.csv"
long_path <- "artifacts/m2-v2-flu-ab-geometry-v1/flu_ab_long_v1.csv"
for (p in c(ledger_path, reference_path, shape_path, long_path)) {
  if (!file.exists(p)) stop("Missing replay input: ", p)
}

ledger <- read.csv(ledger_path, stringsAsFactors = FALSE)
ref <- read.csv(reference_path, stringsAsFactors = FALSE)
shape <- read.csv(shape_path, stringsAsFactors = FALSE)
long <- read.csv(long_path, stringsAsFactors = FALSE)

target_seasons <- unique(as.character(ref$season))

split_prior <- function(x) {
  if (is.na(x) || !nzchar(x)) return(character())
  strsplit(x, ";", fixed = TRUE)[[1L]]
}

make_weekly_panel <- function(season) {
  z <- long[long$season == season, , drop = FALSE]
  a <- z[z$type == "A", c("season", "weekF", "y", "N", "p", "denominator_regime")]
  b <- z[z$type == "B", c("season", "weekF", "y", "N", "p", "denominator_regime")]
  names(a)[3:6] <- c("y_A", "N_A", "p_A", "regime_A")
  names(b)[3:6] <- c("y_B", "N_B", "p_B", "regime_B")
  out <- merge(a, b, by = c("season", "weekF"), all = FALSE, sort = TRUE)
  if (!nrow(out) || any(out$regime_A != out$regime_B)) {
    stop("Typed denominator regime mismatch for season ", season)
  }
  out$denominator_regime <- out$regime_A
  out <- out[, c("season", "weekF", "y_A", "N_A", "p_A",
                 "y_B", "N_B", "p_B", "denominator_regime")]
  out[order(out$weekF), , drop = FALSE]
}

make_a_handoff <- function(season, origin_week, timing_available, timing_peak) {
  if (!isTRUE(timing_available) || !is.finite(timing_peak)) return(NULL)
  origin_week <- as.numeric(origin_week)
  timing_peak <- as.numeric(timing_peak)
  asof <- origin_week + 1
  activation <- max(1, min(origin_week, floor(timing_peak) - 1))
  common <- list(
    version = "m1-v2-to-m2-v1",
    season = as.character(season),
    origin_week = origin_week,
    asof_boundary = asof,
    activation_week = as.numeric(activation),
    calibration_offset_week = 0,
    weeks_elapsed_since_activation = asof - activation,
    m1_v2_artifact_id = paste0("chronological-a-replay-", season)
  )
  if (timing_peak > asof) {
    c(common, list(
      state = "future_only",
      raw_peak_mean = timing_peak,
      calibrated_peak_mean = timing_peak,
      raw_peak_q05 = timing_peak,
      raw_peak_q95 = timing_peak,
      calibrated_peak_q05 = timing_peak,
      calibrated_peak_q95 = timing_peak,
      peak_q05 = timing_peak,
      peak_q95 = timing_peak,
      interval_width_90 = 0,
      weeks_to_calibrated_peak = timing_peak - asof,
      calibrated_mean_is_future = TRUE,
      raw_peak_posterior = data.frame(
        peak_week_decimal = timing_peak,
        probability = 1
      ),
      prob_peak_passed = NA_real_,
      prob_peak_within_1w = NA_real_,
      prob_peak_within_2w = NA_real_,
      prob_peak_within_3w = NA_real_,
      locked_peak_week = NA_real_,
      locked_at_origin = NA_real_
    ))
  } else {
    c(common, list(
      state = "passage_confirmed",
      raw_peak_mean = NA_real_,
      calibrated_peak_mean = NA_real_,
      raw_peak_q05 = NA_real_,
      raw_peak_q95 = NA_real_,
      calibrated_peak_q05 = NA_real_,
      calibrated_peak_q95 = NA_real_,
      peak_q05 = NA_real_,
      peak_q95 = NA_real_,
      interval_width_90 = NA_real_,
      weeks_to_calibrated_peak = NA_real_,
      calibrated_mean_is_future = NA,
      raw_peak_posterior = NULL,
      prob_peak_passed = 1,
      prob_peak_within_1w = 1,
      prob_peak_within_2w = 1,
      prob_peak_within_3w = 1,
      locked_peak_week = timing_peak,
      locked_at_origin = origin_week
    ))
  }
}

make_b_handoff <- function(season, origin_week, timing_available, timing_peak, timing_width) {
  new_m2_v2_b_soft_timing_handoff(
    season = season,
    origin_week = origin_week,
    peak_mean = if (isTRUE(timing_available) && is.finite(timing_peak)) timing_peak else NA_real_,
    timing_available = isTRUE(timing_available) && is.finite(timing_peak),
    source_artifact_id = if (isTRUE(timing_available) && is.finite(timing_peak)) {
      paste0("chronological-b-replay-", season)
    } else {
      NA_character_
    },
    interval_width_90 = if (is.finite(timing_width)) timing_width else NA_real_
  )
}

# Temporary, evaluation-only gate opening. This is deliberately not persisted as
# an operational governance decision; it exists only while this replay runs.
review_file <- tempfile(fileext = ".json")
jsonlite::write_json(list(
  status = "reviewed_open",
  decision = "open",
  policy_version = "b-epidemic-gate-5pct-v1",
  review_id = "retrospective-evaluation-only-governed-replay-v1",
  scope = "retrospective_evaluation_only_not_operational_authorization"
), review_file, auto_unbox = TRUE, pretty = TRUE)
eval_review <- new_m2_v2_b_gate_review(review_file)
on.exit(unlink(review_file), add = TRUE)

source_hashes <- list(
  candidate_ledger = digest::digest(file = ledger_path, algo = "sha256"),
  fixed_c2_reference = digest::digest(file = reference_path, algo = "sha256"),
  shape_grid = digest::digest(file = shape_path, algo = "sha256"),
  typed_weekly = digest::digest(file = long_path, algo = "sha256")
)

all_rows <- list()
fold_rows <- list()

for (season in target_seasons) {
  rz <- ref[ref$season == season, , drop = FALSE]
  prior_strings <- unique(as.character(rz$prior_seasons))
  if (length(prior_strings) != 1L) stop("Non-unique prior set for ", season)
  priors <- split_prior(prior_strings)
  if (length(priors) < 3L) next

  train_ledger <- ledger[ledger$season %in% priors, , drop = FALSE]
  if (!nrow(train_ledger)) stop("No prior training ledger for ", season)
  fit <- m2_v2_c2_fit(
    training_ledger = train_ledger,
    shape_grid = shape,
    training_seasons = priors,
    source_hashes = c(source_hashes, list(target_season = season, prior_seasons = priors))
  )
  evidence <- data.frame(
    season = season,
    prior_seasons = paste(priors, collapse = ";"),
    stringsAsFactors = FALSE
  )
  gov <- new_m2_v2_c2_governed_artifact(
    fit,
    provenance = list(
      source_hashes = source_hashes,
      training_data_sha256 = digest::digest(train_ledger, algo = "sha256"),
      shape_data_sha256 = digest::digest(
        shape[shape$season %in% priors, , drop = FALSE], algo = "sha256"
      ),
      replay_scope = "strict_prior_seasons_only"
    ),
    training_evidence = evidence
  )
  weekly <- make_weekly_panel(season)
  origins <- sort(unique(rz$origin_week))

  for (origin in origins) {
    origin_rows <- rz[rz$origin_week == origin, , drop = FALSE]
    ar <- origin_rows[origin_rows$type == "A", , drop = FALSE]
    br <- origin_rows[origin_rows$type == "B", , drop = FALSE]
    if (!nrow(ar) || !nrow(br)) stop("Missing A/B reference rows at ", season, " week ", origin)

    family_available <- any(!is.na(origin_rows$selected_family) & nzchar(origin_rows$selected_family))
    a_handoff <- make_a_handoff(
      season, origin,
      timing_available = family_available && isTRUE(ar$timing_available[1L]),
      timing_peak = ar$timing_peak[1L]
    )
    b_handoff <- make_b_handoff(
      season, origin,
      timing_available = family_available && isTRUE(br$timing_available[1L]),
      timing_peak = br$timing_peak[1L],
      timing_width = br$timing_width[1L]
    )

    closed <- run_m2_v2_c2_governed_runtime(
      gov, weekly, origin,
      a_handoff = a_handoff,
      b_handoff = b_handoff,
      b_gate_review = NULL
    )
    open <- run_m2_v2_c2_governed_runtime(
      gov, weekly, origin,
      a_handoff = a_handoff,
      b_handoff = b_handoff,
      b_gate_review = eval_review
    )

    pp_closed <- closed$predictions
    pp_open <- open$predictions
    for (i in seq_len(nrow(pp_open))) {
      tp <- pp_open$type[i]
      h <- pp_open$horizon[i]
      rr <- origin_rows[origin_rows$type == tp & origin_rows$horizon == h, , drop = FALSE]
      if (!nrow(rr)) next
      if (nrow(rr) != 1L) stop("Non-unique reference row at ", season, " ", origin, " ", tp, " +", h)
      j <- which(pp_closed$type == tp & pp_closed$horizon == h)
      all_rows[[length(all_rows) + 1L]] <- data.frame(
        season = season,
        prior_seasons = paste(priors, collapse = ";"),
        origin_week = origin,
        type = tp,
        horizon = h,
        y_target = rr$y_target,
        N_target = rr$N_target,
        p_target = rr$p_target,
        reference_pred_base = rr$pred_base,
        reference_pred_fixed_c2 = rr$pred_fixed_c2,
        runtime_pred_base = pp_open$pred_baseline[i],
        governed_closed_pred = pp_closed$pred_selected[j],
        evaluation_open_pred = pp_open$pred_selected[i],
        c2_applied_open = pp_open$c2_applied[i],
        timing_used_open = pp_open$timing_used[i],
        fallback_reason_closed = pp_closed$fallback_reason[j],
        fallback_reason_open = pp_open$fallback_reason[i],
        b_gate_status = pp_open$b_gate_status[i],
        b_gate_active = if (tp == "B") isTRUE(open$b_gate$active) else NA,
        b_gate_activation_week = if (tp == "B") open$b_gate$activation_week else NA_integer_,
        timing_available_reference = rr$timing_available,
        family_available_reference = family_available,
        timing_peak_reference = rr$timing_peak,
        governed_artifact_id = gov$artifact_id,
        stringsAsFactors = FALSE
      )
    }
  }
  fold_rows[[length(fold_rows) + 1L]] <- data.frame(
    season = season,
    prior_seasons = paste(priors, collapse = ";"),
    n_prior = length(priors),
    governed_artifact_id = gov$artifact_id,
    research_fit_artifact_id = fit$artifact_id,
    stringsAsFactors = FALSE
  )
}

pred <- do.call(rbind, all_rows)
folds <- do.call(rbind, fold_rows)

pred$abs_base <- abs(pred$runtime_pred_base - pred$p_target)
pred$abs_closed <- abs(pred$governed_closed_pred - pred$p_target)
pred$abs_open <- abs(pred$evaluation_open_pred - pred$p_target)
pred$sq_base <- (pred$runtime_pred_base - pred$p_target)^2
pred$sq_closed <- (pred$governed_closed_pred - pred$p_target)^2
pred$sq_open <- (pred$evaluation_open_pred - pred$p_target)^2
pred$err_base <- pred$runtime_pred_base - pred$p_target
pred$err_closed <- pred$governed_closed_pred - pred$p_target
pred$err_open <- pred$evaluation_open_pred - pred$p_target
pred$runtime_minus_reference_base <- pred$runtime_pred_base - pred$reference_pred_base
pred$open_minus_reference_c2 <- pred$evaluation_open_pred - pred$reference_pred_fixed_c2

season_metric <- function(d) {
  data.frame(
    n = nrow(d),
    base_mae_pp = 100 * mean(d$abs_base),
    closed_mae_pp = 100 * mean(d$abs_closed),
    open_mae_pp = 100 * mean(d$abs_open),
    base_rmse_pp = 100 * sqrt(mean(d$sq_base)),
    closed_rmse_pp = 100 * sqrt(mean(d$sq_closed)),
    open_rmse_pp = 100 * sqrt(mean(d$sq_open)),
    base_bias_pp = 100 * mean(d$err_base),
    closed_bias_pp = 100 * mean(d$err_closed),
    open_bias_pp = 100 * mean(d$err_open),
    c2_applied_rate_open = mean(d$c2_applied_open),
    timing_used_rate_open = mean(d$timing_used_open),
    stringsAsFactors = FALSE
  )
}

keys <- unique(pred[, c("season", "type", "horizon")])
per_season <- do.call(rbind, lapply(seq_len(nrow(keys)), function(i) {
  k <- keys[i, ]
  d <- pred[pred$season == k$season & pred$type == k$type & pred$horizon == k$horizon, ]
  cbind(k, season_metric(d))
}))

summary_rows <- list()
for (tp in c("A", "B")) for (h in 1:2) {
  z <- per_season[per_season$type == tp & per_season$horizon == h, ]
  summary_rows[[length(summary_rows) + 1L]] <- data.frame(
    type = tp,
    horizon = h,
    n_seasons = nrow(z),
    base_mae_pp = mean(z$base_mae_pp),
    governed_closed_mae_pp = mean(z$closed_mae_pp),
    evaluation_open_mae_pp = mean(z$open_mae_pp),
    closed_relative_mae_gain = 1 - mean(z$closed_mae_pp) / mean(z$base_mae_pp),
    open_relative_mae_gain = 1 - mean(z$open_mae_pp) / mean(z$base_mae_pp),
    base_rmse_pp = mean(z$base_rmse_pp),
    governed_closed_rmse_pp = mean(z$closed_rmse_pp),
    evaluation_open_rmse_pp = mean(z$open_rmse_pp),
    base_bias_pp = mean(z$base_bias_pp),
    governed_closed_bias_pp = mean(z$closed_bias_pp),
    evaluation_open_bias_pp = mean(z$open_bias_pp),
    seasons_open_better = sum(z$open_mae_pp < z$base_mae_pp - 1e-12),
    seasons_open_worse = sum(z$open_mae_pp > z$base_mae_pp + 1e-12),
    stringsAsFactors = FALSE
  )
}
summary <- do.call(rbind, summary_rows)

b2 <- pred[pred$type == "B" & pred$horizon == 2L, ]
if (nrow(b2)) {
  gate_split <- do.call(rbind, lapply(c(FALSE, TRUE), function(active) {
    z <- b2[b2$b_gate_active %in% active, ]
    if (!nrow(z)) return(NULL)
    data.frame(
      b_gate_active = active,
      n = nrow(z),
      n_seasons = length(unique(z$season)),
      base_mae_pp = 100 * mean(z$abs_base),
      open_mae_pp = 100 * mean(z$abs_open),
      relative_mae_gain = 1 - mean(z$abs_open) / mean(z$abs_base),
      stringsAsFactors = FALSE
    )
  }))
} else gate_split <- data.frame()

invariants <- data.frame(
  check = c(
    "runtime_baseline_matches_frozen_reference",
    "evaluation_open_matches_frozen_fixed_c2",
    "b_h1_closed_exact_baseline",
    "b_h1_open_exact_baseline",
    "b2_closed_exact_baseline",
    "timing_unavailable_open_exact_baseline"
  ),
  max_abs_diff = c(
    max(abs(pred$runtime_minus_reference_base)),
    max(abs(pred$open_minus_reference_c2)),
    max(abs(pred$governed_closed_pred[pred$type == "B" & pred$horizon == 1L] -
            pred$runtime_pred_base[pred$type == "B" & pred$horizon == 1L])),
    max(abs(pred$evaluation_open_pred[pred$type == "B" & pred$horizon == 1L] -
            pred$runtime_pred_base[pred$type == "B" & pred$horizon == 1L])),
    max(abs(pred$governed_closed_pred[pred$type == "B" & pred$horizon == 2L] -
            pred$runtime_pred_base[pred$type == "B" & pred$horizon == 2L])),
    max(abs(pred$evaluation_open_pred[!pred$timing_available_reference | !pred$family_available_reference] -
            pred$runtime_pred_base[!pred$timing_available_reference | !pred$family_available_reference]))
  ),
  stringsAsFactors = FALSE
)
invariants$pass_1e10 <- invariants$max_abs_diff < 1e-10

write.csv(pred, file.path(out_dir, "predictions.csv"), row.names = FALSE)
write.csv(folds, file.path(out_dir, "fold_artifacts.csv"), row.names = FALSE)
write.csv(per_season, file.path(out_dir, "per_season_metrics.csv"), row.names = FALSE)
write.csv(summary, file.path(out_dir, "summary.csv"), row.names = FALSE)
write.csv(gate_split, file.path(out_dir, "b2_gate_split.csv"), row.names = FALSE)
write.csv(invariants, file.path(out_dir, "invariants.csv"), row.names = FALSE)

provenance <- data.frame(
  key = c("ledger_sha256", "reference_sha256", "shape_sha256", "typed_weekly_sha256",
          "governed_contract", "b_gate_evaluation_scope"),
  value = c(source_hashes$candidate_ledger, source_hashes$fixed_c2_reference,
            source_hashes$shape_grid, source_hashes$typed_weekly,
            m2_v2_c2_governed_contract()$model_version,
            "retrospective_evaluation_only_not_operational_authorization"),
  stringsAsFactors = FALSE
)
write.csv(provenance, file.path(out_dir, "provenance.csv"), row.names = FALSE)

cat("\nGoverned chronological replay summary\n")
print(summary, row.names = FALSE, digits = 5)
cat("\nB+2 gate split (evaluation-only open policy)\n")
print(gate_split, row.names = FALSE, digits = 5)
cat("\nInvariants\n")
print(invariants, row.names = FALSE, digits = 6)

if (!all(invariants$pass_1e10)) {
  stop("Governed chronological replay failed frozen-reference invariants.")
}
