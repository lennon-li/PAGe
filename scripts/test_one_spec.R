setwd("C:/Users/lennon.li/Documents/claude/PAGe")
library(dplyr)
library(mgcv)
load("data/data.RData")
source("R/m0_training.R")
source("R/m2_spec_grid.R")
source("R/m2_training.R")

alignedD_prosp <- add_prospective_derivs_link(alignedD, k=5L, eps=1e-6, min_obs=4L)

# Build specs the same way tune_stage2_loso_shift_template does
spec_base <- stage2_make_spec(delta=0L, K=3L, k_f=6L, alpha_state=0.25, pre_buffer=2L,
                              leads=c(1L,2L), T="S", k_w=0L, k_s=0L, k_e=6L, k_n=6L, k_1=6L, k_2=6L)
s1 <- spec_base; s1$K <- 3L; s1$lambda_w <- 0.0
s2 <- spec_base; s2$K <- 3L; s2$lambda_w <- 0.1
specs <- list(s0=s1, s01=s2)

# Call tune_stage2_loso_specs directly and inspect raw results
raw <- tune_stage2_loso_specs(
  dat=alignedD_prosp, template_df=template_df, specs=specs,
  testSeason="2024-25",  # just one season for speed
  lambda_w=0, eval_window=NULL,
  num.cores=1L, verbose=TRUE
)
cat("\nRaw results cols:", paste(names(raw$results), collapse=", "), "\n")
cat("Rows:", nrow(raw$results), "\n")
print(raw$results[, intersect(c("ok","spec_id","test_season","delta","K","lambda_w","mean_nll","err"), names(raw$results))])
