# Assemble v3 tuning results from cache CSV + grid reconstruction
# Uses base R only to avoid segfault issues with dplyr

wd <- "C:/Users/lennon.li/Documents/claude/PAGe"

# Read the cache CSV
cache <- read.csv(file.path(wd, "data/v3_results_cache.csv"), stringsAsFactors = FALSE)
cat(sprintf("Cache: %d rows\n", nrow(cache)))

# Reconstruct the combined grid (must match _extended_tune_m1_v3.R exactly)

# Original 81 specs: k_ref x temp x shift x rise_weight = 3x3x3x3 = 81
old_grid <- expand.grid(
  k_ref             = c(15L, 20L, 25L),
  multi_temperature = c(0.5, 1.0, 2.0),
  template_shift    = c(-1L, 0L, 1L),
  align_rise_weight = c(1.0, 2.0, 3.0),
  stringsAsFactors  = FALSE
)

# V2 extended: 48 total, minus 12 overlap with old = 36 new
ext_prev <- expand.grid(
  k_ref             = c(20, 25, 30, 35),
  multi_temperature = c(0.25, 0.5, 1.0),
  template_shift    = c(-2L, -1L, 0L, 1L),
  align_rise_weight = 1.0,
  stringsAsFactors  = FALSE
)

# Remove overlaps with old grid
old_key <- paste(old_grid$k_ref, old_grid$multi_temperature,
                 old_grid$template_shift, old_grid$align_rise_weight, sep = "_")
ext_key <- paste(ext_prev$k_ref, ext_prev$multi_temperature,
                 ext_prev$template_shift, ext_prev$align_rise_weight, sep = "_")
prev_new <- ext_prev[!ext_key %in% old_key, ]
cat(sprintf("V2 new specs: %d\n", nrow(prev_new)))

# V3 new: low-temp grid
new_grid <- expand.grid(
  k_ref             = c(20L, 25L, 30L),
  multi_temperature = c(0.05, 0.10, 0.15, 0.20),
  template_shift    = c(-1L, 0L, 1L),
  align_rise_weight = 1.0,
  stringsAsFactors  = FALSE
)
cat(sprintf("V3 new specs: %d\n", nrow(new_grid)))

# Combine
combined <- rbind(
  old_grid[, c("k_ref", "multi_temperature", "template_shift", "align_rise_weight")],
  prev_new[, c("k_ref", "multi_temperature", "template_shift", "align_rise_weight")],
  new_grid[, c("k_ref", "multi_temperature", "template_shift", "align_rise_weight")]
)
combined$spec_id <- sprintf("s%03d", seq_len(nrow(combined)))
cat(sprintf("Combined grid: %d specs\n", nrow(combined)))

# Join
scores <- merge(combined, cache, by = "spec_id", all.x = TRUE)
scores <- scores[order(scores$mae_weibull), ]

cat(sprintf("\nTop 15 specs by MAE (Weibull):\n"))
top15 <- head(scores, 15)
for (i in seq_len(nrow(top15))) {
  r <- top15[i, ]
  cat(sprintf("  %s: k_ref=%2d  temp=%.2f  shift=%2d  rw=%.1f  MAE=%.4f\n",
    r$spec_id, r$k_ref, r$multi_temperature, r$template_shift,
    r$align_rise_weight, r$mae_weibull))
}

best <- scores[1, ]
cat(sprintf("\nBest overall: %s\n  k_ref=%d, temp=%.2f, shift=%d, rise_weight=%.1f\n  MAE (Weibull) = %.4f\n",
  best$spec_id, best$k_ref, best$multi_temperature, best$template_shift,
  best$align_rise_weight, best$mae_weibull))

# Save final results
result <- list(scores = scores, best = best, grid = combined)
saveRDS(result, file.path(wd, "data/m1_alignment_tuning_v3.rds"))
cat(sprintf("\nSaved: %s\n", file.path(wd, "data/m1_alignment_tuning_v3.rds")))
