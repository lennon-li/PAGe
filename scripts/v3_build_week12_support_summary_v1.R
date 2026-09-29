#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE)
options(digits = 17)
a_path <- "artifacts/v3-m2-a-early-origin-support-v1/per_origin_predictions.csv"
b_path <- "artifacts/v3-m2-b-early-origin-support-v1/per_origin_predictions.csv"
out_path <- "governance/v3_week12_support_summary_v1.csv"
if (!all(file.exists(c(a_path, b_path)))) stop("Missing early-origin evidence.")

a <- read.csv(a_path, check.names = FALSE)
b <- read.csv(b_path, check.names = FALSE)
a <- a[a$origin_week == 12L, ]
b <- b[b$origin_week == 12L, ]
rows <- rbind(
  data.frame(component = "A", horizon = 1L,
    n_seasons = sum(a$horizon == 1L),
    mae_pp = 100 * mean(a$abs_A1[a$horizon == 1L]),
    timing_activations = sum(a$timing_available[a$horizon == 1L])),
  data.frame(component = "A", horizon = 2L,
    n_seasons = sum(a$horizon == 2L),
    mae_pp = 100 * mean(a$abs_A1[a$horizon == 2L]),
    timing_activations = sum(a$timing_available[a$horizon == 2L])),
  data.frame(component = "B", horizon = 1L,
    n_seasons = sum(b$horizon == 1L),
    mae_pp = 100 * mean(b$abs_B1[b$horizon == 1L]),
    timing_activations = sum(b$timing_available[b$horizon == 1L])),
  data.frame(component = "B", horizon = 2L,
    n_seasons = sum(b$horizon == 2L),
    mae_pp = 100 * mean(b$abs_B1[b$horizon == 2L]),
    timing_activations = sum(b$timing_available[b$horizon == 2L]))
)
rows$origin_weekF <- 12L
rows$forecast_route <- "state_baseline_support_check"
rows$claim_scope <- "support_only_not_promotion_or_accuracy_claim"
rows$source_path <- ifelse(rows$component == "A", a_path, b_path)
write.csv(rows, out_path, row.names = FALSE)
cat("Built ", out_path, "\n", sep = "")
