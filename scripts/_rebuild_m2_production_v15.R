#!/usr/bin/env Rscript
# RESEARCH-ONLY ARCHIVE: rebuild the historical v15 fit with locked M1 params.
# This is not a promotion path and must never replace mutable production files.
# - Stores M1_PARAMS in a unique research reference sidecar
# - Regenerates m1_train_preds with slope_weight=8, slope_window=6
# - Fits the historical v15 GAM (update SPEC section below after v15 grid completes)
cli_args <- commandArgs(trailingOnly = TRUE)
output_arg <- grep("^--output=", cli_args, value = TRUE)
if (!"--research-only" %in% cli_args || length(output_arg) != 1L) {
  stop(
    "Research-only archive. Re-run with --research-only and exactly one ",
    "--output=/path/to/unique-v15-artifact.rds.",
    call. = FALSE
  )
}
OUTPUT_PATH <- sub("^--output=", "", output_arg)
if (!grepl("[.]rds$", OUTPUT_PATH, ignore.case = TRUE) ||
    !dir.exists(dirname(OUTPUT_PATH))) {
  stop("`--output` must be a new .rds path in an existing directory.", call. = FALSE)
}
REF_OUTPUT_PATH <- file.path(
  dirname(OUTPUT_PATH),
  paste0(tools::file_path_sans_ext(basename(OUTPUT_PATH)), "_ref.rds")
)
mutable_paths <- normalizePath(
  c("data/m2_production.rds", "data/ref_production.rds"),
  mustWork = FALSE
)
requested_paths <- normalizePath(c(OUTPUT_PATH, REF_OUTPUT_PATH), mustWork = FALSE)
if (tolower(basename(OUTPUT_PATH)) %in%
    c("m2_production.rds", "ref_production.rds") ||
    any(requested_paths %in% mutable_paths) ||
    any(file.exists(c(OUTPUT_PATH, REF_OUTPUT_PATH)))) {
  stop(
    "Refusing mutable or existing output; choose a unique research artifact path.",
    call. = FALSE
  )
}
cat("=== Research-only v15 rebuild (locked M1) ===\n")

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
if ("2025-26" %in% as.character(allD$season)) {
  stop(
    "Historical v15 rebuild refuses data containing the 2025-26 holdout.",
    call. = FALSE
  )
}

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
  slope_weight       = 8.0,   # <- LOCKED
  slope_window       = 6L,    # <- LOCKED
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

# ---- Save a research-only reference sidecar with M1_PARAMS ----
cat('Saving research reference sidecar (with M1_PARAMS)...\n')
ref_cache_old <- readRDS('data/ref_production.rds')
saveRDS(list(
  ref          = ref,
  hyper        = hyper,
  hist_data    = ref_cache_old$hist_data,
  M1_PARAMS    = M1_PARAMS,
  flag_args    = flag_args,
  manual_labels = manual_labels
), REF_OUTPUT_PATH)
cat('Saved research reference sidecar:', REF_OUTPUT_PATH, '\n\n')

# ---- M2 SPEC -- update after v15 LOSO completes ----
# Placeholder: uses v14 spec until v15 grid is complete.
# After run_nested_loso_v15.R finishes, update k_f, k_e, k_sp, k_de below.
cat('M2: loading best spec...\n')
v15_path <- 'data/nested_loso_v15_production.rds'
if (file.exists(v15_path)) {
  v15 <- readRDS(v15_path)
  best_spec_obj <- v15$best_spec
  best_spec_id  <- v15$best_spec_id
  spec_version  <- 'v15'
  cat('Using v15 best spec:', best_spec_id, '\n')
} else {
  cat('v15 not ready -- using v14 spec as placeholder\n')
  best_spec_obj <- stage2_make_spec(
    delta = 0L, Kr = 1L, T = 'S',
    k_f = 4L, k_e = 2L, alpha_state = 0.40,
    k_r = 2L, k_de = 0L, k_sp = 0L,
    k_n = 0L, k_w = 0L, k_s = 0L,
    lambda_w = 0, w_floor = 0.05,
    bias_alpha = 0.2, bias_beta = 0.0
  )
  best_spec_id <- 'v14_placeholder'
  spec_version <- 'v15_placeholder'
}

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
), OUTPUT_PATH)
cat('Saved research artifact:', OUTPUT_PATH, '\n')
cat('Done:', format(Sys.time()), '\n')
