#!/usr/bin/env Rscript
# ============================================================
# Nested LOSO M2 — v14: Re-score v13 with Bernoulli NLL
#
# Problem: v13 (and all prior grids) used raw binomial NLL as the tuning
# metric. Binomial NLL = -[y*log(p) + (N-y)*log(1-p)] scales linearly with
# N. Post-COVID test volumes are 5.7x larger than pre-COVID, so post-COVID
# seasons dominate the objective purely due to sample size — not because the
# model is worse on them (per-obs MAE is actually lower post-COVID).
#
# Fix: Bernoulli NLL = -[p_obs*log(p_hat) + (1-p_obs)*log(1-p_hat)]
# This is the per-observation cross-entropy, N-invariant, and the correct
# metric for comparing calibration across seasons with different volumes.
#
# Since v13 already stored full predictions (p_hat, p_obs, y_lead, N_lead)
# for all 960 specs x 10 seasons, we just re-score — no model refitting.
#
# Output: data/nested_loso_v14_production.rds
# ============================================================

cat("=== Nested LOSO M2 v14 — Bernoulli NLL re-scoring of v13 ===\n")
cat("Start:", format(Sys.time()), "\n\n")

suppressPackageStartupMessages({
  library(dplyr)
  library(purrr)
})

# ---- 1. Load v13 results ----
cat("Loading v13 results...\n")
v13 <- readRDS("data/nested_loso_v13_production.rds")
cat("Specs:", length(v13$cv_results), "| Seasons per spec:", 10, "\n\n")

# ---- 2. Bernoulli NLL scoring function ----
bernoulli_nll <- function(p_hat, p_obs, eps = 1e-12) {
  p_hat <- pmin(1 - eps, pmax(eps, p_hat))
  p_obs <- pmin(1 - eps, pmax(eps, p_obs))
  -mean(p_obs * log(p_hat) + (1 - p_obs) * log(1 - p_hat), na.rm = TRUE)
}

# ---- 3. Re-score all specs ----
cat("Re-scoring", length(v13$cv_results), "specs with Bernoulli NLL...\n")

all_scores_v14 <- purrr::imap_dfr(v13$cv_results, function(res, spec_id) {
  purrr::map_dfr(names(res$scores %>% split(seq_len(nrow(res$scores)))),
    function(i) {
      seas <- res$scores$season[as.integer(i)]
      preds_s <- res$predictions %>% filter(season == seas)
      if (nrow(preds_s) == 0) {
        return(tibble::tibble(
          spec_id = spec_id, season = seas, n = NA_integer_,
          bernoulli_nll = NA_real_, brier = NA_real_, rmse_p = NA_real_,
          mean_nll_raw = NA_real_
        ))
      }
      tibble::tibble(
        spec_id       = spec_id,
        season        = seas,
        n             = nrow(preds_s),
        bernoulli_nll = bernoulli_nll(preds_s$p_hat, preds_s$p_obs),
        brier         = mean((preds_s$p_hat - preds_s$p_obs)^2, na.rm = TRUE),
        rmse_p        = sqrt(mean((preds_s$p_hat - preds_s$p_obs)^2, na.rm = TRUE)),
        mean_nll_raw  = res$scores$mean_nll[res$scores$season == seas]
      )
    })
})

cat("Scored", nrow(all_scores_v14), "season-spec rows.\n\n")

# ---- 4. Summarise and rank ----
summary_v14 <- all_scores_v14 |>
  dplyr::group_by(spec_id) |>
  dplyr::summarise(
    n_seasons     = dplyr::n(),
    bernoulli_nll = mean(bernoulli_nll, na.rm = TRUE),
    brier         = mean(brier,         na.rm = TRUE),
    rmse_p        = mean(rmse_p,        na.rm = TRUE),
    mean_nll_raw  = mean(mean_nll_raw,  na.rm = TRUE),
    .groups = "drop"
  ) |>
  dplyr::arrange(bernoulli_nll)

cat("=== Top 20 specs by Bernoulli NLL ===\n")
print(utils::head(summary_v14[, c("spec_id","bernoulli_nll","brier","rmse_p","mean_nll_raw")], 20), n = 20)

best_id_v14   <- summary_v14$spec_id[1]
best_spec_v14 <- v13$cv_results[[best_id_v14]]  # keep for reference

cat("\n=== v13 vs v14 best spec comparison ===\n")
cat("v13 best (raw NLL):       ", v13$best_spec_id, "\n")
cat("v14 best (Bernoulli NLL): ", best_id_v14, "\n")
cat("Same?", v13$best_spec_id == best_id_v14, "\n\n")

# ---- 5. Per-season Bernoulli NLL for best spec ----
cat("=== Per-season Bernoulli NLL (v14 best spec) ===\n")
per_season <- all_scores_v14 |>
  dplyr::filter(spec_id == best_id_v14) |>
  dplyr::mutate(era = ifelse(season >= "2022-23", "post-COVID", "pre-COVID")) |>
  dplyr::select(season, era, n, bernoulli_nll, brier, mean_nll_raw)
print(per_season)
cat("\npre-COVID mean Bernoulli NLL:", round(mean(per_season$bernoulli_nll[per_season$era == "pre-COVID"]), 5), "\n")
cat("post-COVID mean Bernoulli NLL:", round(mean(per_season$bernoulli_nll[per_season$era == "post-COVID"]), 5), "\n\n")

# ---- 6. Show how ranking changed ----
cat("=== Rank correlation: v13 vs v14 ===\n")
merged <- dplyr::inner_join(
  summary_v14 |> dplyr::mutate(rank_v14 = dplyr::row_number()) |>
    dplyr::select(spec_id, rank_v14, bernoulli_nll, mean_nll_raw),
  v13$summary |> dplyr::mutate(rank_v13 = dplyr::row_number()) |>
    dplyr::select(spec_id, rank_v13, mean_nll),
  by = "spec_id"
)
cat("Spearman rank correlation (v13 vs v14 ranking):",
    round(cor(merged$rank_v13, merged$rank_v14, method = "spearman"), 4), "\n")
cat("Top-10 overlap:",
    sum(merged$rank_v14[merged$rank_v13 <= 10] <= 10), "/ 10\n\n")

# ---- 7. alpha_state boundary check under Bernoulli NLL ----
cat("=== Best Bernoulli NLL by alpha_state ===\n")
summary_v14$alpha_state <- as.numeric(
  sub("^.*_as([0-9.]+)_.*$", "\\1", summary_v14$spec_id))
ag <- aggregate(bernoulli_nll ~ alpha_state, data = summary_v14, FUN = min)
print(ag[order(ag$alpha_state), ])

# ---- 8. Save ----
results_v14 <- list(
  scores        = all_scores_v14,
  summary       = summary_v14,
  best_spec_id  = best_id_v14,
  best_spec     = v13$cv_results[[best_id_v14]],
  # carry forward the actual spec object from v13
  best_spec_obj = v13$grid[v13$grid |>
    dplyr::mutate(sid = paste0("d+", delta, "_Kr", Kr,
      "_kf", k_f, "_ke", k_e, "_as", alpha_state,
      "_kr", k_r, "_kde", k_de, "_ba", bias_alpha, "_bb", bias_beta)) |>
    dplyr::pull(sid) == best_id_v14, ],
  v13_ref       = list(best_spec_id = v13$best_spec_id,
                       best_spec    = v13$best_spec)
)
saveRDS(results_v14, "data/nested_loso_v14_production.rds")
cat("Saved data/nested_loso_v14_production.rds\n")
cat("End:", format(Sys.time()), "\n")
