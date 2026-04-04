setwd("C:/Users/lennon.li/Documents/claude/PAGe")
suppressPackageStartupMessages(library(dplyr))
suppressPackageStartupMessages(library(mgcv))
suppressPackageStartupMessages(library(data.table))
load("data/data.RData")
source("R/m0_training.R")
source("R/m2_spec_grid.R")
source("R/m2_training.R")   # wins for shared fns

alignedD_prosp <- add_prospective_derivs_link(alignedD, k=5L, eps=1e-6, min_obs=4L)
nc <- min(8L, max(1L, parallel::detectCores() - 1L))

cat("\n=== test_lambda_w.R ===\n")
cat("Seasons:", paste(sort(unique(alignedD$season)), collapse=", "), "\n")
cat("Workers:", nc, "\n\n")

test_seasons <- c("2022-23", "2023-24", "2024-25")

# ============================================================
# PATH 1: tune_stage2_loso_shift_template
# Use a simple spec (no fs term, discrete-safe) for speed
# ============================================================
cat("--- PATH 1: tune_stage2_loso_shift_template ---\n")

# Build simple base spec: no fs (k_s=0), no week smooth (k_w=0) for fast REML
spec_base_simple <- stage2_make_spec(
  delta=0L, K=3L, k_f=6L, alpha_state=0.25,
  pre_buffer=2L, leads=c(1L,2L), T="S",
  k_w=0L, k_s=0L, k_e=6L, k_n=6L, k_1=6L, k_2=0L
)

# Build specs manually to pass to tune_stage2_loso_specs directly
# (bypasses the complex default spec in tune_stage2_loso_shift_template)
make_specs <- function(K_vals, lw_vals, base) {
  specs <- list()
  for (K in K_vals) for (lw in lw_vals) {
    s <- base; s$K <- K; s$lambda_w <- lw
    s$best_row <- data.frame(delta=s$delta, K=K, k_f=s$k_f, alpha_state=s$alpha_state)
    s$formula <- stage2_build_joint_formula(s)
    nm <- paste0("K", K, "_lw", formatC(lw, digits=2, format="f"))
    specs[[nm]] <- s
  }
  specs
}
specs_p1 <- make_specs(c(3L,4L), c(0, 0.1), spec_base_simple)
cat("Specs:", length(specs_p1), "| test seasons:", length(test_seasons), "\n")

t1a <- system.time({
  raw1c <- tune_stage2_loso_specs(
    dat=alignedD_prosp, template_df=template_df,
    specs=specs_p1, testSeason=test_seasons,
    lambda_w=0, eval_window=8L,
    num.cores=1L, verbose=FALSE
  )
})
r1 <- raw1c$results
cat("Single-core:", round(t1a["elapsed"],1), "s | rows:", nrow(r1), "| failed:", sum(!r1$ok), "\n")
if (any(!r1$ok)) cat("  error:", r1$err[!r1$ok][1], "\n")
cat("mean_nll by lambda_w (single-core):\n")
print(aggregate(mean_nll ~ lambda_w, data=r1[r1$ok,], FUN=mean, na.rm=TRUE))

t1b <- system.time({
  rawmc <- tune_stage2_loso_specs(
    dat=alignedD_prosp, template_df=template_df,
    specs=specs_p1, testSeason=test_seasons,
    lambda_w=0, eval_window=8L,
    num.cores=nc, verbose=FALSE
  )
})
rmc <- rawmc$results
cat("Multi-core (", nc, "w):", round(t1b["elapsed"],1), "s | failed:", sum(!rmc$ok), " | speedup:", round(t1a["elapsed"]/max(t1b["elapsed"],0.1),1), "x\n", sep="")
if (any(!rmc$ok)) cat("  error:", rmc$err[!rmc$ok][1], "\n")
cat("mean_nll by lambda_w (multi-core):\n")
print(aggregate(mean_nll ~ lambda_w, data=rmc[rmc$ok,], FUN=mean, na.rm=TRUE))

# Verify single and multi give same results
if (nrow(r1) == nrow(rmc) && !any(!r1$ok) && !any(!rmc$ok)) {
  cat("\nSingle vs multi results match?",
      isTRUE(all.equal(sort(r1$mean_nll), sort(rmc$mean_nll), tolerance=1e-4)), "\n")
}

# ============================================================
# PATH 2: tune_stage2_loso_spec_grid_parallel (m2_spec_grid.R)
# ============================================================
source("R/m2_spec_grid.R")   # restore module versions

cat("\n--- PATH 2: tune_stage2_loso_spec_grid_parallel ---\n")
sg <- expand_grid_specs(
  delta_grid=0L, Kr_grid=c(3L,4L), T_grid="S", k_f_grid=6L,
  alpha_state=0.25, Kb_grid=2L,
  k_w_grid=0L, k_s_grid=0L, k_e_grid=6L, k_n_grid=6L, k_1_grid=6L, k_2_grid=0L,
  verbose=FALSE
)
cat("Base spec_grid rows:", nrow(sg$grid), "\n")

t2 <- system.time({
  tuned_mt <- tune_stage2_loso_spec_grid_parallel(
    alignedD_prosp = alignedD_prosp,
    template_df    = template_df,
    spec_grid      = sg,
    seasons        = test_seasons,
    k_t            = 8L,
    w_early        = 1,
    lambda_w_grid  = c(0, 0.1),
    workers        = nc,
    chunk_size     = 4L,
    nthreads       = 1L,
    verbose        = TRUE
  )
})
cat("PATH 2:", round(t2["elapsed"],1), "s\n")
bsg <- as.data.frame(tuned_mt$by_spec_grid)
cat("by_spec_grid rows:", nrow(bsg), "\n")
keep <- intersect(c("spec_id","lambda_w","Kr","mean_nll"), names(bsg))
cat("Top rows:\n")
print(head(bsg[, keep], 8))
cat("\nmean_nll by lambda_w (PATH 2):\n")
print(aggregate(mean_nll ~ lambda_w, data=bsg, FUN=mean, na.rm=TRUE))

cat("\n=== DONE ===\n")
