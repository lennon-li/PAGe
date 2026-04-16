#!/usr/bin/env Rscript
# Diagnostic: compare fixed-alpha (old cache) vs adaptive-alpha M2 on
# 2025-26 AND historical seasons.
# Does NOT refit the GAM; only the bias correction loop changes.
cat("=== Adaptive-alpha M2 diagnostic ===\n")

suppressPackageStartupMessages({
  library(PAGe); library(dplyr); library(MMWRweek); library(future); library(furrr)
})
for (f in c('R/utils.R', 'R/m0_retro.R', 'R/flagIgnition.R',
            'R/m1_reference.R', 'R/m1_reference_helpers.R', 'R/m1_multi_template.R',
            'R/m2_spec_grid.R', 'R/m2_training.R', 'R/m2_nested_loso.R',
            'R/pipeline_bridge.R', 'R/pipeline_runtime_helpers.R',
            'R/pipeline_runtime.R')) source(f)

n_weeks_in_start_year <- function(sy)
  52L + as.integer(MMWRweek::MMWRweek(as.Date(paste0(sy, '-12-31')))$MMWRweek == 53L)

DATA_DIR <- "data"
n_cores  <- max(1L, parallel::detectCores() - 1L)
future::plan(future::multisession, workers = n_cores)

# ---- Load kit ----
kit <- load_prospective_kit(DATA_DIR)
cat(sprintf("Kit: spec=%s  bias_alpha=%.2f\n",
            kit$m2_production$best_spec_id,
            as.numeric(kit$best_spec$bias_alpha %||% 0.2)))

# ---- Load all data ----
allD <- read.csv(file.path(DATA_DIR, "flu_testing_data.csv")) |>
  dplyr::select(season, week, year, start_year = seasonstart,
                date = week_start_date, y = pos_flua, N = test_flu) |>
  dplyr::mutate(neg = N - y, date = as.Date(date),
                nW_true = n_weeks_in_start_year(start_year),
                weekF = ((week - 27L) %% nW_true) + 1L, p = y / N)

# LOSO test seasons (same as v13/v14/v15 runs)
LOSO_SEASONS  <- c("2012-13","2013-14","2014-15","2016-17","2017-18",
                   "2018-19","2019-20","2022-23","2023-24","2024-25")
ALL_SEASONS   <- c(LOSO_SEASONS, "2025-26")

# ---- Helper: run pipeline on one season ----
run_one <- function(seas) {
  d <- dplyr::filter(allD, season == seas)
  tryCatch(
    run_prospective_pipeline(kit = kit, current_data = d,
                             walk_start = 5L, manual_ign_week = NA_integer_,
                             mode = "frozen", verbose = FALSE),
    error = function(e) { message("  FAILED: ", seas, " — ", conditionMessage(e)); NULL }
  )
}

# ---- Load old baseline (pre-adaptive-alpha deploy cache) ----
old_cache_file <- file.path(DATA_DIR, "deploy_wf_cache.rds")
m2_old_2526    <- NULL
if (file.exists(old_cache_file)) {
  old_wf <- readRDS(old_cache_file)
  if (!is.null(old_wf$m2_preds)) {
    m2_old_2526 <- old_wf$m2_preds
    cat(sprintf("Old cache loaded: %d M2 prediction rows for 2025-26\n", nrow(m2_old_2526)))
  }
}

# ================================================================
# 1. RUN 2025-26
# ================================================================
cat("\n--- 1. Running 2025-26 (adaptive alpha) ---\n")
t0     <- proc.time()
wf_new <- run_one("2025-26")
cat(sprintf("Done in %.1f sec\n", (proc.time() - t0)[["elapsed"]]))

m2_new_2526 <- wf_new$m2_preds
cat(sprintf("New M2 rows: %d\n", nrow(m2_new_2526)))

# Compare h=1 only
if (!is.null(m2_old_2526) && nrow(m2_new_2526) > 0) {
  cmp <- dplyr::inner_join(
    dplyr::select(m2_new_2526, eval_week, h, m2_p_new = m2_p),
    dplyr::select(m2_old_2526, eval_week, h, m2_p_old = m2_p),
    by = c("eval_week", "h")
  ) |> dplyr::mutate(delta_pp = (m2_p_new - m2_p_old) * 100)

  cat("\n2025-26 change summary (adaptive − fixed, pp):\n")
  cat(sprintf("  h=1: mean=%+.3f pp  max=%+.3f pp\n",
              mean(cmp$delta_pp[cmp$h==1]), max(cmp$delta_pp[cmp$h==1])))
  cat(sprintf("  h=2: mean=%+.3f pp  max=%+.3f pp\n",
              mean(cmp$delta_pp[cmp$h==2]), max(cmp$delta_pp[cmp$h==2])))

  cat("\nPer-week (h=1):\n")
  cmp_h1 <- dplyr::filter(cmp, h==1) |> dplyr::arrange(eval_week) |>
    dplyr::mutate(across(c(m2_p_new, m2_p_old), ~round(.x*100,2)),
                  delta_pp = round(delta_pp, 3))
  print(cmp_h1[, c("eval_week","m2_p_old","m2_p_new","delta_pp")])
} else {
  cat("\n2025-26 predictions (h=1):\n")
  print(dplyr::filter(m2_new_2526, h==1) |>
        dplyr::mutate(across(c(m2_p, m2_lo, m2_hi), ~round(.x*100,2))) |>
        dplyr::select(eval_week, m2_p, m2_lo, m2_hi))
}

# Save updated 2025-26 cache
attr(wf_new, "cache_hash") <- unname(tools::md5sum(c(
  file.path(DATA_DIR, "ref_production.rds"),
  file.path(DATA_DIR, "m2_production.rds")
)))
attr(wf_new, "m2_mode") <- "frozen"
saveRDS(wf_new, old_cache_file)
cat(sprintf("\nSaved updated 2025-26 cache -> %s\n", old_cache_file))

# ================================================================
# 2. RETRODICTION ON HISTORICAL SEASONS
# ================================================================
cat("\n--- 2. Retrodiction on historical seasons (adaptive alpha) ---\n")
cat("Note: production GAM trained on all seasons — this is in-sample retrodiction,\n")
cat("not LOSO. Purpose: verify adaptive alpha fires and measure correction magnitude.\n\n")

retro_results <- vector("list", length(LOSO_SEASONS))
names(retro_results) <- LOSO_SEASONS

for (seas in LOSO_SEASONS) {
  cat(sprintf("  %s ...", seas))
  t0 <- proc.time()
  wf <- run_one(seas)
  elapsed <- (proc.time() - t0)[["elapsed"]]
  if (is.null(wf) || is.null(wf$m2_preds) || nrow(wf$m2_preds) == 0) {
    cat(sprintf(" SKIPPED\n")); next
  }
  retro_results[[seas]] <- wf$m2_preds
  cat(sprintf(" %d rows (%.1fs)\n", nrow(wf$m2_preds), elapsed))
}

retro_all <- dplyr::bind_rows(lapply(names(retro_results), function(s) {
  df <- retro_results[[s]]
  if (is.null(df)) return(NULL)
  dplyr::mutate(df, season = s)
}))

if (nrow(retro_all) > 0) {
  # Compute RMSE vs observed per season for h=1
  # Need observed p per target_weekF
  obs_lookup <- allD |>
    dplyr::mutate(p_obs = y / pmax(N, 1L)) |>
    dplyr::select(season, weekF, p_obs)

  retro_scored <- retro_all |>
    dplyr::filter(h == 1L) |>
    dplyr::left_join(obs_lookup, by = c("season", "target_weekF" = "weekF")) |>
    dplyr::filter(!is.na(p_obs), !is.na(m2_p))

  season_summary <- retro_scored |>
    dplyr::group_by(season) |>
    dplyr::summarise(
      n      = dplyr::n(),
      rmse   = sqrt(mean((m2_p - p_obs)^2)) * 100,
      bias   = mean(m2_p - p_obs) * 100,
      peak_p = max(p_obs, na.rm=TRUE) * 100,
      .groups = "drop"
    ) |>
    dplyr::arrange(season)

  cat("\nRetrodiction summary (h=1, pp = percentage points):\n")
  print(season_summary, n = 20)

  cat(sprintf("\nOverall RMSE (h=1): %.3f pp\n",
              sqrt(mean((retro_scored$m2_p - retro_scored$p_obs)^2)) * 100))
  cat(sprintf("Overall bias (h=1): %+.3f pp\n",
              mean(retro_scored$m2_p - retro_scored$p_obs) * 100))

  saveRDS(retro_all, file.path(DATA_DIR, "m2_retro_adaptive_alpha.rds"))
  cat(sprintf("\nRetrodiction results saved -> %s\n",
              file.path(DATA_DIR, "m2_retro_adaptive_alpha.rds")))
}

cat("\nDone.\n")
