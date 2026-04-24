#!/usr/bin/env Rscript
# Step 5b — M2 Production Fit v16 (RE-fix)
#
# Reads best spec from fresh_nested_loso_v16_production.rds (RE-fix results).
# Best spec: kf4/ke2/as0.15/ksp6/ba0.05 | NLL=0.42646
#
# Reads:   data/fresh_m0_tuning.rds
#          data/fresh_nested_loso_v16_production.rds
#          data/fresh_ref_production.rds
# Output:  data/fresh_m2_production.rds   (overwrites v15-postfix kit)
#          data/fresh_ref_production.rds  (updated)
# Compare: data/m2_production.rds

source("scripts/fresh_run/00_shared.R")
cat("=== Step 5b: M2 Production Fit v16 (RE-fix) ===\n")
cat("Start:", format(Sys.time()), "\n\n")

future::plan(future::multisession, workers = n_cores)

# ---- Data (all seasons except permanent, keeps 2025-26) ----
allD_all  <- load_allD(exclude = c())
EXCLUDE_P <- c("2011-12", "2015-16", "2020-21", "2021-22")
allD_prod <- dplyr::filter(allD_all, !season %in% EXCLUDE_P)
train_seas <- sort(unique(allD_prod$season))
cat("Training seasons:", paste(train_seas, collapse = ", "), "\n")
cat("Total:", length(train_seas), "seasons\n\n")

# ---- M0 params (fresh) ----
params <- readRDS("data/fresh_m0_tuning.rds")$best_params
cat("Using fresh M0 best_params:\n"); print(params); cat("\n")

# ---- Align training data ----
cat("M0: estimateDerivs + flagIgnition + alignIgnition...\n")
res_deriv <- estimateDerivs(allD_prod, k = 10L)
train_outs <- res_deriv$data |>
  dplyr::group_by(season) |>
  dplyr::group_split(.keep = TRUE) |>
  purrr::map(function(df)
    do.call(flagIgnition, c(list(df = df, manual_labels = manual_labels), flag_args)))
aligned_train <- alignIgnition(train_outs)
cat("aligned_train:", nrow(aligned_train), "rows\n\n")

# ---- M1 reference curve ----
cat("M1: estimateRef (k_ref =", M1_PARAMS$k_ref, ")...\n")
ref   <- estimateRef(alignedD = aligned_train, exSeason = character(0),
                     k = M1_PARAMS$k_ref, n_weeks = 52L, method = M1_PARAMS$ref_method)
hyper <- learn_alignment_hyperparams(ref$dat, ref$g_ref_fun)
template_df <- ref$pred_df[, c("newWeek", "fit")]
cat("ref built, eta_mat:", nrow(ref$eta_mat), "x", ncol(ref$eta_mat), "\n\n")

# ---- M1 walk-forward training predictions ----
cat("M1: walk-forward predictions (slope_weight=", M1_PARAMS$slope_weight,
    ", slope_window=", M1_PARAMS$slope_window, ")...\n")
m1_train_preds <- m1_walkforward_multi(
  allD = allD_all, ref = ref, hyper = hyper, params = params,
  seasons = train_seas,
  temperature = M1_PARAMS$temperature, rise_weight = M1_PARAMS$rise_weight,
  trough_weight = M1_PARAMS$trough_weight, peak_decay = M1_PARAMS$peak_decay,
  slope_weight = M1_PARAMS$slope_weight, slope_window = M1_PARAMS$slope_window,
  dynamic_temp = M1_PARAMS$dynamic_temp, dynamic_temp_pivot = M1_PARAMS$dynamic_temp_pivot,
  parallel = TRUE, verbose = FALSE
)
cat("m1_train_preds:", nrow(m1_train_preds), "rows\n\n")

# ---- Update fresh_ref_production.rds ----
cat("Updating data/fresh_ref_production.rds...\n")
saveRDS(list(
  ref           = ref,
  hyper         = hyper,
  hist_data     = aligned_train,
  M1_PARAMS     = M1_PARAMS,
  flag_args     = flag_args,
  manual_labels = manual_labels
), "data/fresh_ref_production.rds")
cat("Saved data/fresh_ref_production.rds\n\n")

# ---- M2 best spec (from v16 LOSO results) ----
cat("M2: loading best spec from fresh v16 LOSO...\n")
v16_path <- "data/fresh_nested_loso_v16_production.rds"
if (!file.exists(v16_path)) stop("v16 results not found: ", v16_path)
v16 <- readRDS(v16_path)
best_spec_obj <- v16$best_spec
best_spec_id  <- v16$best_spec_id
spec_version  <- "v16_fresh"
cat("Best spec:", best_spec_id, "\n")
cat("Best NLL:", round(v16$summary$bernoulli_nll[1], 5), "\n")
cat("Spec params: kf=", best_spec_obj$k_f, " ke=", best_spec_obj$k_e,
    " as=", best_spec_obj$alpha_state, " ksp=", best_spec_obj$k_sp,
    " ba=", best_spec_obj$bias_alpha, "\n\n")

# ---- Fit production GAM ----
cat("M2: fitting production GAM...\n")
joint_out <- train_stage2_joint(
  dat         = add_prospective_derivs_link(aligned_train),
  template_df = template_df,
  spec        = best_spec_obj,
  method      = "REML",
  m1_preds    = if (nrow(m1_train_preds) > 0) m1_train_preds else NULL,
  verbose     = FALSE
)
gam_fit        <- joint_out$fit
feature_ranges <- joint_out$feature_ranges
cat("GAM fit. EDF:", round(sum(gam_fit$edf), 2), "\n")
cat("feature_ranges: z_ema [", paste(round(feature_ranges$z_ema, 2), collapse = ", "), "]\n")
cat("                logit_f_eff [", paste(round(feature_ranges$logit_f_eff, 2), collapse = ", "), "]\n")
cat("                dz_ema_sd =", round(feature_ranges$dz_ema_sd, 4), "\n\n")

saveRDS(list(
  spec             = best_spec_obj,
  fit              = gam_fit,
  feature_ranges   = feature_ranges,
  m1_train_preds   = m1_train_preds,
  training_seasons = train_seas,
  spec_version     = spec_version,
  best_spec_id     = best_spec_id
), "data/fresh_m2_production.rds")
cat("Saved: data/fresh_m2_production.rds\n")

# ---- Comparison vs current production kit ----
cat("\n=== Comparison vs current production (data/m2_production.rds) ===\n")
gold_m2  <- readRDS("data/m2_production.rds")
fresh_m2 <- readRDS("data/fresh_m2_production.rds")

cat("Gold spec_id:", gold_m2$best_spec_id, "\n")
cat("Fresh spec_id:", fresh_m2$best_spec_id, "\n")
cat("Gold EDF:", round(sum(gold_m2$fit$edf), 2),
    "| Fresh EDF:", round(sum(fresh_m2$fit$edf), 2), "\n")

if (length(coef(gold_m2$fit)) == length(coef(fresh_m2$fit))) {
  coef_delta <- abs(coef(fresh_m2$fit) - coef(gold_m2$fit))
  cat("Max |coef delta|:", round(max(coef_delta, na.rm = TRUE), 4), "\n")
} else {
  cat("Coef lengths differ (gold:", length(coef(gold_m2$fit)),
      "fresh:", length(coef(fresh_m2$fit)), ") — spec architecture changed\n")
}

cat("Gold dz_ema_sd:", round(gold_m2$feature_ranges$dz_ema_sd, 4),
    "| Fresh dz_ema_sd:", round(fresh_m2$feature_ranges$dz_ema_sd, 4), "\n")

if ("f_eff" %in% names(gold_m2$m1_train_preds) && "f_eff" %in% names(fresh_m2$m1_train_preds)) {
  m1pred_cmp <- dplyr::inner_join(
    gold_m2$m1_train_preds  |> dplyr::select(season, weekF, f_eff_gold  = f_eff),
    fresh_m2$m1_train_preds |> dplyr::select(season, weekF, f_eff_fresh = f_eff),
    by = c("season", "weekF")
  )
  cat("cor(gold f_eff, fresh f_eff):",
      round(cor(m1pred_cmp$f_eff_gold, m1pred_cmp$f_eff_fresh, use = "complete.obs"), 5), "\n")
}

cat("\nEnd:", format(Sys.time()), "\n")
