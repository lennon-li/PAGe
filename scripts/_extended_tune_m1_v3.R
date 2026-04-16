# Further extended LOSO tuning - exploring lower temperatures
# Best from v2: s103 (k_ref=25, temp=0.25, shift=0, MAE=1.169)
# temp=0.25 is at grid edge -> explore temp={0.05, 0.10, 0.15, 0.20}
# Also explore k_ref={20,25,30} x shift={-1,0,1} around the optimum

library(dplyr)
library(tidyr)
library(furrr)
library(MMWRweek)
library(PAGe)

wd <- "C:/Users/lennon.li/Documents/claude/PAGe"
source(file.path(wd, "R/m1_reference.R"))
source(file.path(wd, "R/m1_loso.R"))
source(file.path(wd, "R/utils.R"))
source(file.path(wd, "R/m1_runtime.R"))
source(file.path(wd, "R/m1_multi_template.R"))

# Load existing extended tuning to get grid
tune_prev <- readRDS(file.path(wd, "data/m1_alignment_tuning.rds"))
old_grid <- tune_prev$grid

# New grid: lower temperatures around the optimum
new_grid <- expand.grid(
  k_ref             = c(20L, 25L, 30L),
  multi_temperature = c(0.05, 0.10, 0.15, 0.20),
  template_shift    = c(-1L, 0L, 1L),
  align_rise_weight = 1.0,
  stringsAsFactors  = FALSE
) %>% as_tibble()

message(sprintf("New low-temp grid: %d specs", nrow(new_grid)))
print(new_grid)

# Combined: old 81 + prev extended 36 + new
# We only need to pass old_grid + new_grid since checkpoint will skip old
# But tune_m1_alignment reassigns spec_ids sequentially, so we need full combined grid

# Load prev extended grid structure
ext_prev <- expand.grid(
  k_ref             = c(20, 25, 30, 35),
  multi_temperature = c(0.25, 0.5, 1.0),
  template_shift    = c(-2L, -1L, 0L, 1L),
  align_rise_weight = 1.0,
  stringsAsFactors  = FALSE
) %>% as_tibble()

old_combo <- old_grid %>%
  select(k_ref, multi_temperature, template_shift, align_rise_weight) %>%
  distinct()

prev_new <- anti_join(ext_prev, old_combo,
                       by = c("k_ref", "multi_temperature", "template_shift", "align_rise_weight"))

# Full combined: old(81) + prev_new(36) + new(36) = 153
combined_grid <- bind_rows(
  old_grid %>% select(k_ref, multi_temperature, template_shift, align_rise_weight),
  prev_new,
  new_grid
)

message(sprintf("\nTotal combined grid: %d specs", nrow(combined_grid)))
message(sprintf("  81 original + 36 prev extended + %d new low-temp", nrow(new_grid)))

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
  "2012-13" = 24L, "2013-14" = 22L, "2014-15" = 17L,
  "2015-16" = 19L, "2016-17" = 21L, "2017-18" = 18L,
  "2018-19" = 19L, "2019-20" = 22L, "2022-23" = 15L,
  "2023-24" = 20L, "2024-25" = 23L
)
manual_labels <- manual_labels_orig - 1L

# ============================================
# Run tuning — checkpoint skips old specs
# ============================================

tune_v3 <- tune_m1_alignment(
  allD              = allD,
  params            = params,
  grid              = combined_grid,
  manual_labels     = manual_labels,
  exclude_seasons   = "2015-16",
  n_weeks           = 52L,
  use_multi_template = TRUE,
  ref_method        = "fs",
  checkpoint_dir    = file.path(wd, "data/m1_tune_ckpt_extended2"),
  n_cores           = min(parallel::detectCores() - 1L, 4L),
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

message("\n=== LOW-TEMP TUNING RESULTS ===\n")
top_20 <- tune_v3$results %>%
  arrange(mae_weibull) %>%
  head(20)

print(top_20 %>%
  select(k_ref, multi_temperature, template_shift, mae_uniform, mae_exp, mae_weibull))

best_v3 <- tune_v3$results %>%
  arrange(mae_weibull) %>%
  slice(1)

message(sprintf("\nBest (v3 grid):\n  k_ref=%d, temp=%.2f, shift=%d\n  MAE (Weibull) = %.4f",
                best_v3$k_ref[[1]],
                best_v3$multi_temperature[[1]],
                best_v3$template_shift[[1]],
                best_v3$mae_weibull[[1]]))

# Save
output_file <- file.path(wd, "data/m1_alignment_tuning_v3.rds")
saveRDS(tune_v3, output_file)
message(sprintf("\nSaved: %s", output_file))
