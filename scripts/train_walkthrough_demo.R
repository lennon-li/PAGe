#!/usr/bin/env Rscript
# Pre-computes Stage 1 training artifacts for docs/pipeline_walkthrough.qmd.
# Run once from the repo root: Rscript scripts/train_walkthrough_demo.R
# Runtime: ~1–3 hours depending on hardware (M1 fold building is the bottleneck).
# Results are cached in data/walkthrough/; subsequent renders are instant.

setwd(dirname(dirname(normalizePath(sys.frames()[[1]]$ofile %||% "."))))

suppressPackageStartupMessages({
  library(PAGe)
  library(MMWRweek)
  library(dplyr)
  library(tidyr)
  library(future)
})

`%||%` <- function(x, y) if (is.null(x)) y else x

CACHE_DIR     <- "data/walkthrough"
TRAIN_SEASONS <- c("2012-13", "2014-15", "2017-18", "2019-20", "2023-24")
PROSP_SEASON  <- "2025-26"
START_WEEK    <- 27L

dir.create(CACHE_DIR, showWarnings = FALSE, recursive = TRUE)
cat(sprintf("[%s] Cache directory: %s\n", Sys.time(), CACHE_DIR))

# ── Data loading ────────────────────────────────────────────────────────────
n_weeks_in_start_year <- function(start_year) {
  52L + as.integer(
    MMWRweek::MMWRweek(as.Date(paste0(start_year, "-12-31")))$MMWRweek == 53L
  )
}

load_flu_data <- function(path = "data/flu_testing_data.csv") {
  read.csv(path) |>
    dplyr::select(season, week, start_year = seasonstart,
                  y = pos_flua, N = test_flu) |>
    dplyr::mutate(
      neg   = N - y,
      nW    = n_weeks_in_start_year(start_year),
      weekF = ((week - START_WEEK) %% nW) + 1L,
      p     = y / N
    )
}

allD       <- load_flu_data()
train_allD <- allD |> dplyr::filter(season %in% TRAIN_SEASONS)
cat(sprintf("[%s] Training seasons: %s (%d rows)\n",
            Sys.time(), paste(TRAIN_SEASONS, collapse = ", "), nrow(train_allD)))

# ── M0 ──────────────────────────────────────────────────────────────────────
m0_path <- file.path(CACHE_DIR, "m0.rds")
if (file.exists(m0_path)) {
  cat(sprintf("[%s] M0: loaded from cache.\n", Sys.time()))
  m0 <- readRDS(m0_path)
} else {
  cat(sprintf("[%s] M0: tuning ...\n", Sys.time()))
  m0 <- tune_m0(allD = train_allD, loso_seasons = "all", exclude = character(0))
  saveRDS(m0, m0_path)
  cat(sprintf("[%s] M0: done.\n", Sys.time()))
}

# ── M1 ──────────────────────────────────────────────────────────────────────
m1_path <- file.path(CACHE_DIR, "m1.rds")
if (file.exists(m1_path)) {
  cat(sprintf("[%s] M1: loaded from cache.\n", Sys.time()))
  m1 <- readRDS(m1_path)
} else {
  cat(sprintf("[%s] M1: building reference curve ...\n", Sys.time()))
  m1 <- build_m1(allD = train_allD, m0 = m0, exclude = character(0))
  saveRDS(m1, m1_path)
  cat(sprintf("[%s] M1: done.\n", Sys.time()))
}

# ── M2 LOSO ─────────────────────────────────────────────────────────────────
loso_path <- file.path(CACHE_DIR, "m2_loso.rds")
if (file.exists(loso_path)) {
  cat(sprintf("[%s] M2 LOSO: loaded from cache.\n", Sys.time()))
  loso <- readRDS(loso_path)
} else {
  cat(sprintf("[%s] M2 LOSO: running grid search (this is the slow step) ...\n",
              Sys.time()))
  # 2-spec demo grid. For production use default_m2_grid() (480 specs).
  demo_grid <- tidyr::crossing(
    delta       = 0,
    Kr          = 1,
    k_f         = c(4L, 6L),
    k_e         = 2L,
    alpha_state = 0.15,
    k_r         = 0L,
    k_de        = 0L,
    k_sp        = 6L
  )
  loso <- build_m2(
    allD         = train_allD,
    m0           = m0,
    m1           = m1,
    loso_seasons = "all",
    exclude_seas = character(0),
    grid         = demo_grid,
    verbose      = TRUE
  )
  saveRDS(loso, loso_path)
  cat(sprintf("[%s] M2 LOSO: done. Best NLL=%.4f (%s)\n",
              Sys.time(), loso$summary$bernoulli_nll[1], loso$best_spec_id))
}

# ── M2 final model ────────────────────────────────────────────────────────
model_path <- file.path(CACHE_DIR, "m2_model.rds")
if (file.exists(model_path)) {
  cat(sprintf("[%s] M2 model: loaded from cache.\n", Sys.time()))
  m2_model <- readRDS(model_path)
} else {
  cat(sprintf("[%s] M2 model: training ...\n", Sys.time()))
  m2_model <- train_m2(
    allD      = train_allD,
    m0        = m0,
    m1        = m1,
    best_spec = loso$best_spec,
    exclude   = character(0),
    verbose   = TRUE
  )
  saveRDS(m2_model, model_path)
  cat(sprintf("[%s] M2 model: done (EDF=%.1f).\n",
              Sys.time(), sum(m2_model$fit$edf)))
}

# ── Kit ─────────────────────────────────────────────────────────────────────
kit_path <- file.path(CACHE_DIR, "kit.rds")
if (file.exists(kit_path)) {
  cat(sprintf("[%s] Kit: loaded from cache.\n", Sys.time()))
} else {
  cat(sprintf("[%s] Kit: assembling ...\n", Sys.time()))
  kit <- assemble_kit(m0 = m0, m1 = m1, m2_model = m2_model)
  saveRDS(kit, kit_path)
  cat(sprintf("[%s] Kit: done.\n", Sys.time()))
}

cat(sprintf("[%s] All Stage 1 artifacts written to %s/\n", Sys.time(), CACHE_DIR))
cat("Now render docs/pipeline_walkthrough.qmd — it will load from cache.\n")
