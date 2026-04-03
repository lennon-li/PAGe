# Extended LOSO tuning for M1 alignment hyperparameters
# Extends the original grid beyond boundary optima
# Reuses existing results; only computes new specs

library(dplyr)
library(tidyr)
library(furrr)
library(MMWRweek)
library(flualign)

wd <- "C:/Users/lennon.li/Documents/claude/PAGe"
source(file.path(wd, "R/estimateRef.R"))
source(file.path(wd, "R/loso_alignment.R"))
source(file.path(wd, "R/utils.R"))
source(file.path(wd, "R/prospective_alignment.R"))
source(file.path(wd, "R/align_multi_template.R"))

# Load existing tuning
tune_old <- readRDS(file.path(wd, "data/m1_alignment_tuning.rds"))
old_grid <- tune_old$grid

message(sprintf("Loaded existing grid: %d specs", nrow(old_grid)))
print(old_grid %>% select(k_ref, multi_temperature, template_shift))

# Create extended grid (boundary exploration)
# Original: k_ref=15,20,25; temp=0.5,1,2; shift=-1,0,1
# Extended: k_ref=20,25,30,35; temp=0.25,0.5,1; shift=-2,-1,0,1
extended_grid <- expand.grid(
  k_ref             = c(20, 25, 30, 35),
  multi_temperature = c(0.25, 0.5, 1.0),
  template_shift    = c(-2L, -1L, 0L, 1L),
  align_rise_weight = 1.0,
  stringsAsFactors  = FALSE
) %>%
  as_tibble()

message(sprintf("Extended grid: %d specs", nrow(extended_grid)))

# Identify which are new (not in old grid)
old_combo <- old_grid %>%
  select(k_ref, multi_temperature, template_shift, align_rise_weight) %>%
  distinct() %>%
  mutate(is_old = TRUE)

new_combos <- anti_join(extended_grid, old_combo,
                         by = c("k_ref", "multi_temperature", "template_shift", "align_rise_weight"))
message(sprintf("New specs to compute: %d (out of %d extended)", nrow(new_combos), nrow(extended_grid)))
print(new_combos)

# Combine: keep old specs + add new ones
# Re-use spec_id numbering for old specs, assign new IDs to new ones
combined_grid <- bind_rows(
  old_grid %>% select(k_ref, multi_temperature, template_shift, align_rise_weight, spec_id),
  new_combos %>%
    mutate(spec_id = sprintf("s%03d", nrow(old_grid) + row_number()))
)

message(sprintf("\nRunning extended tuning with %d total specs", nrow(combined_grid)))
message(sprintf("  %d old (will be skipped from cache)", nrow(old_grid)))
message(sprintf("  %d new (will be computed)", nrow(new_combos)))

# ============================================
# Setup data
# ============================================

allD <- read.csv(file.path(wd, "data/flu_testing_data.csv")) %>%
  select(season, week, year, start_year = seasonstart, date = week_start_date,
         y = pos_flua, N = test_flu) %>%
  mutate(
    neg = N - y,
    date = as.Date(date),
    mmwr_year = ifelse(week >= 35L, start_year, start_year + 1L),
    nW_true = n_weeks_in_start_year(start_year),
    weekF = ((week - 27L) %% nW_true) + 1L,
    p = y / N
  ) %>%
  filter(!season %in% c("2011-12", "2020-21", "2021-22", "2025-26"))

tuned <- readRDS(file.path(wd, "data/stage1_tuning.rds"))
params <- tuned$best_params

manual_labels_orig <- c(
  "2012-13" = 18L, "2013-14" = 20L, "2014-15" = 20L,
  "2015-16" = 24L, "2016-17" = 19L, "2017-18" = 20L,
  "2018-19" = 19L, "2019-20" = 22L, "2022-23" = 15L,
  "2023-24" = 20L, "2024-25" = 23L
)
manual_labels <- manual_labels_orig - 1L

# ============================================
# Run extended tuning
# Checkpoints will skip already-done specs
# ============================================

tune_extended <- tune_m1_alignment(
  allD              = allD,
  params            = params,
  grid              = combined_grid,
  manual_labels     = manual_labels,
  exclude_seasons   = "2015-16",
  n_weeks           = 52L,
  use_multi_template = TRUE,
  ref_method        = "fs",
  checkpoint_dir    = file.path(wd, "data/m1_tune_ckpt_extended"),
  n_cores           = min(parallel::detectCores() - 1L, 8L),
  verbose           = TRUE,
  # Fixed params (passed via ...)
  k_deriv           = 20L,
  buffer_weeks      = 5L,
  curvature_ratio   = 1.0,
  peak_weight_boost = 3,
  peak_weight_decay = 0.3
)

# ============================================
# Results
# ============================================

message("\n=== EXTENDED TUNING RESULTS ===\n")
top_20 <- tune_extended$results %>%
  arrange(mae_weibull) %>%
  head(20)

print(top_20 %>%
  select(k_ref, multi_temperature, template_shift, mae_uniform, mae_exp, mae_weibull))

best_extended <- tune_extended$results %>%
  arrange(mae_weibull) %>%
  slice(1)

message(sprintf("\nBest (extended grid):\n  k_ref=%d, temp=%.2f, shift=%d\n  MAE (Weibull) = %.4f",
                best_extended$k_ref[[1]],
                best_extended$multi_temperature[[1]],
                best_extended$template_shift[[1]],
                best_extended$mae_weibull[[1]]))

# Save extended results
output_file <- file.path(wd, "data/m1_alignment_tuning_extended.rds")
saveRDS(tune_extended, output_file)
message(sprintf("\nSaved: %s", output_file))
