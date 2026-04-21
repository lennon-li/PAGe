#!/usr/bin/env Rscript
# Rebuild production kit with v15-postfix best spec and LOCKED M1 params
# - Loads best spec from data/nested_loso_v15_postfix_production.rds
# - Stores M1_PARAMS in ref_production.rds (so load_prospective_kit uses them)
# - Regenerates m1_train_preds with slope_weight=8, slope_window=6
# - Fits production GAM with v15-postfix best spec (corrected eval loop B1-B4)
# - Stamps spec_version = "v15-postfix" in saved kit
# - Saves to data/m2_production.rds (backup must already exist)
cat("=== Rebuild production kit (v15-postfix spec, corrected eval loop, locked M1) ===\n")

suppressPackageStartupMessages({
  library(PAGe); library(dplyr); library(purrr); library(mgcv); library(MMWRweek)
  library(future); library(furrr)
})
n_cores <- max(1L, parallel::detectCores() - 1L)
future::plan(future::multisession, workers = n_cores)
cat("Parallel plan: multisession with", n_cores, "workers\n")
for (f in c('R/utils.R', 'R/m0_retro.R', 'R/flagIgnition.R',
            'R/m1_reference.R', 'R/m1_reference_helpers.R', 'R/m1_multi_template.R',
            'R/m2_spec_grid.R', 'R/m2_training.R', 'R/m2_nested_loso.R',
            'R/pipeline_bridge.R', 'R/pipeline_runtime_helpers.R')) source(f)

n_weeks_in_start_year <- function(sy)
  52L + as.integer(MMWRweek::MMWRweek(as.Date(paste0(sy, '-12-31')))$MMWRweek == 53L)

# ---- Data ----
allD <- read.csv('data/flu_testing_data.csv') |>
  dplyr::select(season, week, year, start_year = seasonstart,
                date = week_start_date, y = pos_flua, N = test_flu) |>
  dplyr::mutate(neg = N - y, date = as.Date(date),
                nW_true = n_weeks_in_start_year(start_year),
                weekF = ((week - 27L) %% nW_true) + 1L, p = y / N)

params        <- readRDS('data/stage1_tuning.rds')$best_params
manual_labels <- c('2012-13' = 18L, '2013-14' = 20L, '2014-15' = 20L,
                   '2015-16' = 24L, '2016-17' = 19L, '2017-18' = 20L,
                   '2018-19' = 19L, '2019-20' = 22L, '2022-23' = 15L,
                   '2023-24' = 20L, '2024-25' = 23L)
flag_args <- list(p_thresh = 0.01, k1 = 0.4, k_c = 0.01, n_consec = 2L,
                  min_window = 10L, w_min = 21L, w_max = 21L, d2_relax = -0.01)
EXCLUDE_PERM <- c('2011-12', '2015-16', '2020-21', '2021-22')

# ---- LOCKED M1 PARAMS (v5-v7 LOSO grid, Weibull MAE = 1.275) ----
M1_PARAMS <- list(
  k_ref              = 25L,
  ref_method         = "fs",
  temperature        = 0.25,
  rise_weight        = 1.0,
  trough_weight      = 0.1,
  peak_decay         = 0.3,
  slope_weight       = 8.0,   # ← LOCKED
  slope_window       = 6L,    # ← LOCKED
  dynamic_temp       = FALSE,
  dynamic_temp_pivot = 10L
)
cat('M1 params: slope_weight =', M1_PARAMS$slope_weight,
    '| slope_window =', M1_PARAMS$slope_window, '\n\n')

train_allD <- allD |> dplyr::filter(!season %in% EXCLUDE_PERM)
train_seas  <- sort(unique(train_allD$season))
cat('Training seasons:', paste(train_seas, collapse = ', '), '\n\n')

# ---- M0 ----
cat('M0: estimateDerivs...\n')
res_deriv    <- estimateDerivs(train_allD, k = 10L)
train_outs   <- res_deriv$data |>
  dplyr::group_by(season) |> dplyr::group_split(.keep = TRUE) |>
  purrr::map(function(df)
    do.call(flagIgnition, c(list(df = df, manual_labels = manual_labels), flag_args)))
aligned_train <- alignIgnition(train_outs)
cat('aligned_train:', nrow(aligned_train), 'rows\n\n')

# ---- M1: reference curve ----
cat('M1: estimateRef (k_ref =', M1_PARAMS$k_ref, ')...\n')
ref   <- estimateRef(alignedD = aligned_train, exSeason = character(0),
                     k = M1_PARAMS$k_ref, n_weeks = 52L, method = M1_PARAMS$ref_method)
hyper <- learn_alignment_hyperparams(ref$dat, ref$g_ref_fun)
template_df <- ref$pred_df[, c('newWeek', 'fit')]
cat('ref built, eta_mat:', nrow(ref$eta_mat), 'x', ncol(ref$eta_mat), '\n\n')

# ---- M1: walk-forward training predictions (locked params) ----
cat('M1: walk-forward predictions (slope_weight=', M1_PARAMS$slope_weight,
    ', slope_window=', M1_PARAMS$slope_window, ')...\n')
m1_train_preds <- m1_walkforward_multi(
  allD         = allD,
  ref          = ref,
  hyper        = hyper,
  params       = params,
  seasons      = train_seas,
  temperature  = M1_PARAMS$temperature,
  rise_weight  = M1_PARAMS$rise_weight,
  trough_weight = M1_PARAMS$trough_weight,
  peak_decay   = M1_PARAMS$peak_decay,
  slope_weight = M1_PARAMS$slope_weight,
  slope_window = M1_PARAMS$slope_window,
  dynamic_temp = M1_PARAMS$dynamic_temp,
  dynamic_temp_pivot = M1_PARAMS$dynamic_temp_pivot,
  parallel     = TRUE,
  verbose      = FALSE
)
cat('m1_train_preds:', nrow(m1_train_preds), 'rows\n\n')

# ---- Save ref_production.rds with M1_PARAMS ----
cat('Saving ref_production.rds (with M1_PARAMS)...\n')
ref_cache_old <- readRDS('data/ref_production.rds')
saveRDS(list(
  ref          = ref,
  hyper        = hyper,
  hist_data    = ref_cache_old$hist_data,
  M1_PARAMS    = M1_PARAMS,
  flag_args    = flag_args,
  manual_labels = manual_labels
), 'data/ref_production.rds')
cat('Saved ref_production.rds\n\n')

# ---- M2 SPEC — load from v15-postfix LOSO results ----
cat('M2: loading best spec from v15-postfix results...\n')
v15pf_path <- 'data/nested_loso_v15_postfix_production.rds'
if (!file.exists(v15pf_path)) {
  stop("v15-postfix results not found at: ", v15pf_path,
       "\nRun scripts/run_nested_loso_v15_postfix.R first.")
}
v15pf <- readRDS(v15pf_path)
best_spec_obj <- v15pf$best_spec
best_spec_id  <- v15pf$best_spec_id
spec_version  <- 'v15-postfix'
cat('Using v15-postfix best spec:', best_spec_id, '\n')
cat('  bias_alpha:', best_spec_obj$bias_alpha, '\n')
cat('  bias_beta: ', best_spec_obj$bias_beta,  '\n')

# ---- M2: fit production GAM ----
cat('M2: fitting production GAM...\n')
joint_out <- train_stage2_joint(
  dat         = add_prospective_derivs_link(aligned_train),
  template_df = template_df,
  spec        = best_spec_obj,
  method      = 'REML',
  m1_preds    = if (nrow(m1_train_preds) > 0) m1_train_preds else NULL,
  verbose     = FALSE
)
gam_fit        <- joint_out$fit
feature_ranges <- joint_out$feature_ranges
cat('GAM fit. EDF:', round(sum(gam_fit$edf), 2), '\n')
cat('feature_ranges: z_ema [', paste(round(feature_ranges$z_ema, 2), collapse = ', '), ']\n')
cat('              logit_f_eff [', paste(round(feature_ranges$logit_f_eff, 2), collapse = ', '), ']\n')
cat('              dz_ema_sd =', round(feature_ranges$dz_ema_sd, 4), '\n\n')

saveRDS(list(
  spec             = best_spec_obj,
  fit              = gam_fit,
  feature_ranges   = feature_ranges,
  m1_train_preds   = m1_train_preds,
  training_seasons = train_seas,
  spec_version     = spec_version,
  best_spec_id     = best_spec_id
), 'data/m2_production.rds')
cat('Saved data/m2_production.rds\n')
cat('Done:', format(Sys.time()), '\n')
