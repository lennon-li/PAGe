#!/usr/bin/env Rscript
# Step 7 — Comparison Report (fresh run)
# Reads all fresh_* outputs and compares against gold standards.
# Prints a pass/fail summary table.
#
# Reads:   all data/fresh_*.rds outputs from Steps 1–6
# Outputs: printed report only (no new files)

source("scripts/fresh_run/00_shared.R")
cat("=== Step 7: Comparison Report ===\n")
cat("Date:", format(Sys.time()), "\n\n")

results <- list()

check <- function(label, pass, detail = "") {
  status <- if (isTRUE(pass)) "PASS" else if (isFALSE(pass)) "FAIL" else "WARN"
  results[[label]] <<- list(status = status, detail = detail)
  cat(sprintf("[%s] %s%s\n", status, label,
              if (nchar(detail) > 0) paste0(" — ", detail) else ""))
}

# ================================================================
# M0 checks
# ================================================================
cat("\n--- M0 Ignition Detection ---\n")
gold_m0  <- readRDS("data/stage1_tuning.rds")
fresh_m0 <- readRDS("data/fresh_m0_tuning.rds")

params_match <- isTRUE(all.equal(
  as.list(gold_m0$best_params[order(names(gold_m0$best_params))]),
  as.list(fresh_m0$best_params[order(names(fresh_m0$best_params))])
))
check("M0 best_params match", params_match)

if (!is.null(fresh_m0$compare) && !is.null(gold_m0$compare)) {
  cmp <- dplyr::inner_join(
    as.data.frame(gold_m0$compare)  |> dplyr::rename(iWeek_gold  = iWeek_hat),
    as.data.frame(fresh_m0$compare) |> dplyr::rename(iWeek_fresh = iWeek_hat),
    by = "season"
  ) |> dplyr::mutate(delta = iWeek_fresh - iWeek_gold)
  max_delta <- max(abs(cmp$delta), na.rm = TRUE)
  check("M0 per-season ignition delta = 0", max_delta == 0,
        sprintf("max|delta| = %d", max_delta))
}

# ================================================================
# M1 Reference Curve checks
# ================================================================
cat("\n--- M1 Reference Curve ---\n")
gold_ref  <- readRDS("data/ref_production.rds")
fresh_ref <- readRDS("data/fresh_ref_production.rds")

anchor_match <- fresh_ref$ref$anchorWeek == gold_ref$ref$anchorWeek
check("M1 anchorWeek match (CRITICAL)", anchor_match,
      sprintf("gold=%d fresh=%d", gold_ref$ref$anchorWeek, fresh_ref$ref$anchorWeek))

if (!anchor_match) {
  cat("\n!!! CRITICAL: anchorWeek mismatch — all downstream newWeek coords are invalid !!!\n")
  cat("    Cannot continue meaningful comparison. Fix before proceeding.\n\n")
}

pred_cmp  <- dplyr::inner_join(gold_ref$ref$pred_df, fresh_ref$ref$pred_df,
                                by = "newWeek", suffix = c(".gold", ".fresh"))
max_curve <- max(abs(pred_cmp$fit.fresh - pred_cmp$fit.gold), na.rm = TRUE)
check("M1 reference curve max |delta| < 0.01", max_curve < 0.01,
      sprintf("max|delta| = %.5f (logit scale)", max_curve))

# ================================================================
# M1 LOSO checks
# ================================================================
cat("\n--- M1 LOSO Alignment ---\n")
gold_ckpt_path <- "data/m1_tune_ckpt_v7/tune_m1_results.rds"
fresh_ckpt_path <- "data/fresh_m1_tune_ckpt_v7/tune_m1_results.rds"

if (file.exists(gold_ckpt_path) && file.exists(fresh_ckpt_path)) {
  gold_m1  <- readRDS(gold_ckpt_path)
  fresh_m1 <- readRDS(fresh_ckpt_path)
  mae_cmp  <- dplyr::inner_join(
    gold_m1  |> dplyr::rename(mae_gold  = mae_weibull),
    fresh_m1 |> dplyr::rename(mae_fresh = mae_weibull),
    by = "spec_id"
  )
  gold_best_id  <- mae_cmp$spec_id[which.min(mae_cmp$mae_gold)]
  fresh_best_id <- mae_cmp$spec_id[which.min(mae_cmp$mae_fresh)]
  gold_best_mae <- min(mae_cmp$mae_gold, na.rm = TRUE)
  fresh_best_mae <- min(mae_cmp$mae_fresh, na.rm = TRUE)
  check("M1 best spec_id match", gold_best_id == fresh_best_id,
        sprintf("gold=%s fresh=%s", gold_best_id, fresh_best_id))
  check("M1 LOSO MAE <= gold + 0.02", fresh_best_mae <= gold_best_mae + 0.02,
        sprintf("gold=%.4f fresh=%.4f delta=%.4f", gold_best_mae, fresh_best_mae,
                fresh_best_mae - gold_best_mae))
  check("M1 best MAE ~ 1.275", abs(fresh_best_mae - 1.275) < 0.05,
        sprintf("fresh=%.4f (target=1.275)", fresh_best_mae))
} else {
  cat("Skipping M1 LOSO comparison (checkpoint files not found)\n")
}

# ================================================================
# M2 LOSO checks
# ================================================================
cat("\n--- M2 Nested LOSO ---\n")
if (file.exists("data/fresh_nested_loso_v15_production.rds")) {
  gold_v15  <- readRDS("data/nested_loso_v15_production.rds")
  fresh_v15 <- readRDS("data/fresh_nested_loso_v15_production.rds")
  gold_best  <- gold_v15$summary$spec_id[1]
  fresh_best <- fresh_v15$summary$spec_id[1]
  gold_nll   <- gold_v15$summary$bernoulli_nll[1]
  fresh_nll  <- fresh_v15$summary$bernoulli_nll[1]
  check("M2 best spec_id match", gold_best == fresh_best,
        sprintf("gold=%s fresh=%s", gold_best, fresh_best))
  check("M2 Bernoulli NLL <= gold + 0.002", fresh_nll <= gold_nll + 0.002,
        sprintf("gold=%.4f fresh=%.4f delta=%.4f", gold_nll, fresh_nll, fresh_nll - gold_nll))
  check("M2 best NLL ~ 0.406", abs(fresh_nll - 0.406) < 0.005,
        sprintf("fresh=%.4f (target=0.406)", fresh_nll))

  # Normalize gold spec IDs: strip _ba/bb suffix (v14 naming artifact)
  norm_id <- function(x) sub("_ba[0-9.]+_bb[0-9.]+$", "", x)
  gold_sum_norm <- gold_v15$summary |>
    dplyr::mutate(spec_id_norm = norm_id(spec_id)) |>
    dplyr::group_by(spec_id_norm) |>
    dplyr::slice_min(bernoulli_nll, n = 1L, with_ties = FALSE) |>
    dplyr::ungroup()

  score_cmp <- dplyr::inner_join(
    gold_sum_norm  |> dplyr::select(spec_id_norm, nll_gold  = bernoulli_nll),
    fresh_v15$summary |> dplyr::select(spec_id_norm = spec_id, nll_fresh = bernoulli_nll),
    by = "spec_id_norm"
  ) |> dplyr::mutate(delta = nll_fresh - nll_gold)
  if (nrow(score_cmp) > 0) {
    max_nll_delta <- max(abs(score_cmp$delta), na.rm = TRUE)
    check("M2 max |NLL delta| < 0.002", max_nll_delta < 0.002,
          sprintf("max|delta| = %.4f (n=%d matched)", max_nll_delta, nrow(score_cmp)))

    gold_scores_norm <- gold_v15$scores |>
      dplyr::mutate(spec_id_norm = norm_id(spec_id)) |>
      dplyr::group_by(spec_id_norm, season) |>
      dplyr::slice_min(bernoulli_nll, n = 1L, with_ties = FALSE) |>
      dplyr::ungroup()
    merged_nll <- dplyr::inner_join(
      gold_scores_norm  |> dplyr::select(spec_id_norm, season, nll_gold  = bernoulli_nll),
      fresh_v15$scores  |> dplyr::select(spec_id_norm = spec_id, season, nll_fresh = bernoulli_nll),
      by = c("spec_id_norm", "season")
    )
    if (nrow(merged_nll) > 1) {
      nll_cor <- cor(merged_nll$nll_gold, merged_nll$nll_fresh, use = "complete.obs")
      check("M2 cor(gold_nll, fresh_nll) > 0.999", nll_cor > 0.999,
            sprintf("r = %.5f", nll_cor))
    } else {
      check("M2 cor(gold_nll, fresh_nll) > 0.999", NA,
            "insufficient matched rows for correlation")
    }
  } else {
    check("M2 max |NLL delta| < 0.002", NA, "no spec_id matches after normalization (gold uses different naming)")
    check("M2 cor(gold_nll, fresh_nll) > 0.999", NA, "no spec_id matches after normalization")
  }
}

# ================================================================
# M2 Production fit checks
# ================================================================
cat("\n--- M2 Production GAM ---\n")
gold_m2  <- readRDS("data/m2_production.rds")
fresh_m2 <- readRDS("data/fresh_m2_production.rds")

gold_spec_id  <- if (!is.null(gold_m2$best_spec_id) && nchar(gold_m2$best_spec_id) > 0)
  gold_m2$best_spec_id else "(none — gold schema mismatch)"
check("M2 spec_id match", gold_spec_id == fresh_m2$best_spec_id,
      sprintf("gold=%s fresh=%s", gold_spec_id, fresh_m2$best_spec_id))

gold_edf  <- round(sum(gold_m2$fit$edf), 2)
fresh_edf <- round(sum(fresh_m2$fit$edf), 2)
check("M2 EDF within 0.5", abs(fresh_edf - gold_edf) < 0.5,
      sprintf("gold=%.2f fresh=%.2f", gold_edf, fresh_edf))

gold_dz <- gold_m2$feature_ranges$dz_ema_sd
fresh_dz <- fresh_m2$feature_ranges$dz_ema_sd
if (is.numeric(gold_dz) && length(gold_dz) == 1 && is.numeric(fresh_dz)) {
  dz_rel <- abs(fresh_dz - gold_dz) / gold_dz
  check("M2 dz_ema_sd delta < 5%", dz_rel < 0.05,
        sprintf("gold=%.4f fresh=%.4f relative delta = %.1f%%", gold_dz, fresh_dz, dz_rel * 100))
} else {
  check("M2 dz_ema_sd delta < 5%", NA,
        sprintf("gold schema lacks numeric dz_ema_sd (gold version mismatch); fresh=%.4f",
                if (is.numeric(fresh_dz)) fresh_dz else NA_real_))
}

if (length(coef(gold_m2$fit)) == length(coef(fresh_m2$fit))) {
  max_coef <- max(abs(coef(fresh_m2$fit) - coef(gold_m2$fit)), na.rm = TRUE)
  check("M2 max |coef delta| < 0.05", max_coef < 0.05,
        sprintf("max|delta| = %.4f", max_coef))
}

# ================================================================
# Prospective deployment checks
# ================================================================
cat("\n--- Prospective Deployment ---\n")
if (file.exists("data/fresh_deploy_wf_cache.rds")) {
  gold_wf  <- readRDS("data/deploy_wf_cache.rds")
  fresh_wf <- readRDS("data/fresh_deploy_wf_cache.rds")

  gold_ign  <- unique(na.omit(gold_wf$params_df$iWeek_hat))
  fresh_ign <- unique(na.omit(fresh_wf$params_df$iWeek_hat))
  check("Prospective ignition week match", setequal(gold_ign, fresh_ign),
        sprintf("gold=%s fresh=%s", paste(gold_ign, collapse = ","),
                paste(fresh_ign, collapse = ",")))

  common_weeks <- intersect(gold_wf$params_df$eval_week, fresh_wf$params_df$eval_week)
  if (!is.null(gold_wf$m2_preds) && !is.null(fresh_wf$m2_preds)) {
    m2_cmp <- dplyr::inner_join(
      gold_wf$m2_preds  |> dplyr::filter(eval_week %in% common_weeks),
      fresh_wf$m2_preds |> dplyr::filter(eval_week %in% common_weeks),
      by = c("eval_week", "h"), suffix = c(".gold", ".fresh")
    ) |> dplyr::mutate(delta = m2_p.fresh - m2_p.gold)
    max_fc <- max(abs(m2_cmp$delta), na.rm = TRUE)
    check("Prospective M2 forecast max |delta| < 0.005", max_fc < 0.005,
          sprintf("max|delta| = %.4f", max_fc))
  }

  # Holt EMA bias trajectory direction check
  ema_col <- intersect(c("ema_bias", "bias_state"), names(fresh_wf$params_df))
  if (length(ema_col) > 0 && ema_col[1] %in% names(gold_wf$params_df)) {
    gold_bias <- gold_wf$params_df  |> dplyr::filter(eval_week %in% common_weeks) |>
      dplyr::select(eval_week, bias = dplyr::all_of(ema_col[1]))
    fresh_bias <- fresh_wf$params_df |> dplyr::filter(eval_week %in% common_weeks) |>
      dplyr::select(eval_week, bias = dplyr::all_of(ema_col[1]))
    bias_cmp  <- dplyr::inner_join(gold_bias, fresh_bias, by = "eval_week",
                                    suffix = c(".gold", ".fresh"))
    same_sign <- mean(sign(bias_cmp$bias.gold) == sign(bias_cmp$bias.fresh), na.rm = TRUE)
    check("Holt EMA bias same-sign fraction >= 0.9", same_sign >= 0.9,
          sprintf("fraction = %.3f", same_sign))
  }
}

# ================================================================
# Summary
# ================================================================
cat("\n", strrep("=", 60), "\n", sep = "")
cat("SUMMARY\n")
cat(strrep("=", 60), "\n\n")
for (label in names(results)) {
  r <- results[[label]]
  cat(sprintf("  [%s] %s\n", r$status, label))
  if (nchar(r$detail) > 0) cat(sprintf("         %s\n", r$detail))
}

n_pass <- sum(sapply(results, function(r) r$status == "PASS"))
n_fail <- sum(sapply(results, function(r) r$status == "FAIL"))
n_warn <- sum(sapply(results, function(r) r$status == "WARN"))
cat(sprintf("\n  Total: %d PASS | %d FAIL | %d WARN\n", n_pass, n_fail, n_warn))
cat(strrep("=", 60), "\n")
cat("\nEnd:", format(Sys.time()), "\n")
