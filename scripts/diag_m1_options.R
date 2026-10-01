#!/usr/bin/env Rscript
# diag_m1_options.R: Quantitative evidence for M1 post-peak fix options.
# Read-only evaluation of recorded Task A/B outputs, M1 predictions, and observed data.
# Run from repo root: Rscript scripts/diag_m1_options.R

suppressPackageStartupMessages({
  library(data.table)
})

a_rows_path <- "results/m1-diagnosis/task_a_rows.csv"
b_seasons_path <- "results/m1-diagnosis/task_b_seasons.csv"
b_trig_path <- "results/m1-diagnosis/task_b_triggers.csv"
kit_preds_path <- file.path(
  "results/final-kit-2026-27",
  "20260918T1520Z-final-2026-27-wmin8-venkata",
  "artifacts/m2_tuning.rds"
)

stopifnot(file.exists(a_rows_path), file.exists(b_seasons_path),
          file.exists(b_trig_path), file.exists(kit_preds_path))

a_rows <- read.csv(a_rows_path, stringsAsFactors = FALSE)
b_seasons <- read.csv(b_seasons_path, stringsAsFactors = FALSE)
b_trig <- read.csv(b_trig_path, stringsAsFactors = FALSE)
m2_obj <- readRDS(kit_preds_path)
preds <- as.data.frame(m2_obj$m1_train_preds)

# Merge datasets
m <- merge(a_rows, preds[, c("season", "eval_weekF", "target_weekF", "h",
                              "m1_tau", "m1_delta", "peak_weekF",
                              "peak_weekF_lo", "peak_weekF_hi")],
           by = c("season", "eval_weekF", "target_weekF", "h"))
m <- merge(m, b_seasons[, c("season", "true_peak_raw", "true_peak_smooth", "first_post_peak")],
           by = "season")
m <- merge(m, b_trig[, c("season", "fire_pp_decl2", "fire_persist2", "fire_decl2")],
           by = "season")

# Forecast available and finite actuals (635 rows)
df <- m[m$m1_forecast_available == TRUE & is.finite(m$actual_p), ]
df$err_m1 <- abs(df$m1_p_hat - df$actual_p) * 100
df$err_gam <- abs(df$gam_no_p_hat - df$actual_p) * 100

cat("=================================================================\n")
cat("TASK C: EMPIRICAL ANALYSIS OF M1 OPTIONS\n")
cat("=================================================================\n\n")

# -----------------------------------------------------------------
# 1. OPTION 1: HARD SWITCH VARIANTS
# -----------------------------------------------------------------
cat("--- 1. OPTION 1: HARD SWITCH (MAEs in percentage points) ---\n")

# 1a. Unlatched baseline (switches when m1_state == 'post_peak')
p_unlatched <- ifelse(df$m1_state == "post_peak", df$gam_no_p_hat, df$m1_p_hat)
err_unlatched <- abs(p_unlatched - df$actual_p) * 100

# 1b. Latched baseline (once first_post_peak reached, stays GAM)
p_latched <- ifelse(df$eval_weekF >= df$first_post_peak, df$gam_no_p_hat, df$m1_p_hat)
err_latched <- abs(p_latched - df$actual_p) * 100

# 1c. Latched persist2 (eval_weekF >= fire_persist2)
p_persist2 <- ifelse(df$eval_weekF >= df$fire_persist2, df$gam_no_p_hat, df$m1_p_hat)
err_persist2 <- abs(p_persist2 - df$actual_p) * 100

# 1d. Latched pp_decl2 (eval_weekF >= fire_pp_decl2)
p_pp_decl2 <- ifelse(df$eval_weekF >= df$fire_pp_decl2, df$gam_no_p_hat, df$m1_p_hat)
err_pp_decl2 <- abs(p_pp_decl2 - df$actual_p) * 100

cat(sprintf("Baseline M1 (n=635):           All = %.2f pp | Pre = %.2f pp | Post = %.2f pp\n",
            mean(df$err_m1), mean(df$err_m1[df$m1_state != "post_peak"]), mean(df$err_m1[df$m1_state == "post_peak"])))
cat(sprintf("Pure GAM no-tpl (n=635):        All = %.2f pp | Pre = %.2f pp | Post = %.2f pp\n",
            mean(df$err_gam), mean(df$err_gam[df$m1_state != "post_peak"]), mean(df$err_gam[df$m1_state == "post_peak"])))
cat(sprintf("Hard Switch (Unlatched pp):     All = %.2f pp | Pre = %.2f pp | Post = %.2f pp\n",
            mean(err_unlatched), mean(err_unlatched[df$m1_state != "post_peak"]), mean(err_unlatched[df$m1_state == "post_peak"])))
cat(sprintf("Hard Switch (Latched pp):       All = %.2f pp | Pre = %.2f pp | Post = %.2f pp\n",
            mean(err_latched), mean(err_latched[df$m1_state != "post_peak"]), mean(err_latched[df$m1_state == "post_peak"])))
cat(sprintf("Hard Switch (Latched persist2): All = %.2f pp | Pre = %.2f pp | Post = %.2f pp\n",
            mean(err_persist2), mean(err_persist2[df$m1_state != "post_peak"]), mean(err_persist2[df$m1_state == "post_peak"])))
cat(sprintf("Hard Switch (Latched pp_decl2): All = %.2f pp | Pre = %.2f pp | Post = %.2f pp\n",
            mean(err_pp_decl2), mean(err_pp_decl2[df$m1_state != "post_peak"]), mean(err_pp_decl2[df$m1_state == "post_peak"])))

# Per-season MAE for Hard Switch Latched vs M1
cat("\nPer-season MAE (Hard Switch Latched vs M1):\n")
s_mae <- do.call(rbind, lapply(split(df, df$season), function(sub) {
  p_l <- ifelse(sub$eval_weekF >= sub$first_post_peak, sub$gam_no_p_hat, sub$m1_p_hat)
  data.frame(
    season = sub$season[1],
    n = nrow(sub),
    m1_all = mean(abs(sub$m1_p_hat - sub$actual_p)) * 100,
    latched_all = mean(abs(p_l - sub$actual_p)) * 100,
    m1_post = mean(abs(sub$m1_p_hat[sub$m1_state == "post_peak"] - sub$actual_p[sub$m1_state == "post_peak"])) * 100,
    latched_post = mean(abs(p_l[sub$m1_state == "post_peak"] - sub$actual_p[sub$m1_state == "post_peak"])) * 100
  )
}))
print(s_mae, row.names = FALSE)

# -----------------------------------------------------------------
# 2. OPTION 2: BLENDED SWITCH & DISCONTINUITY AT SWITCH
# -----------------------------------------------------------------
cat("\n--- 2. OPTION 2: BLENDED SWITCH & DISCONTINUITY ---\n")

# Discrepancy at switch origin (eval_weekF == first_post_peak)
sw <- df[df$eval_weekF == df$first_post_peak, ]
sw$diff_pp <- abs(sw$gam_no_p_hat - sw$m1_p_hat) * 100
cat(sprintf("At switch origin (n=%d): mean |GAM - M1| = %.2f pp, median = %.2f pp, max = %.2f pp (%s h=%d)\n",
            nrow(sw), mean(sw$diff_pp), median(sw$diff_pp), max(sw$diff_pp),
            sw$season[which.max(sw$diff_pp)], sw$h[which.max(sw$diff_pp)]))
cat(sprintf("  h=1: mean = %.2f pp | h=2: mean = %.2f pp\n",
            mean(sw$diff_pp[sw$h == 1]), mean(sw$diff_pp[sw$h == 2])))

# Target-week continuity (eval = first_post_peak - 1 at h=2 vs eval = first_post_peak at h=1)
rev_list <- list()
for (s in unique(df$season)) {
  sub <- df[df$season == s, ]
  fpp <- sub$first_post_peak[1]
  target_wk <- fpp + 1
  row_pre <- sub[sub$eval_weekF == fpp - 1 & sub$target_weekF == target_wk, ]
  row_post <- sub[sub$eval_weekF == fpp & sub$target_weekF == target_wk, ]
  if (nrow(row_pre) == 1 && nrow(row_post) == 1) {
    m1_rev <- (row_post$m1_p_hat - row_pre$m1_p_hat) * 100
    hard_rev <- (row_post$gam_no_p_hat - row_pre$m1_p_hat) * 100
    rev_list[[s]] <- data.frame(season = s, m1_rev = m1_rev, hard_rev = hard_rev)
  }
}
rev_df <- do.call(rbind, rev_list)
cat(sprintf("Target-week revision step across switch (n=%d seasons):\n", nrow(rev_df)))
cat(sprintf("  M1 mean |revision|:          %.2f pp (max %.2f pp in %s)\n",
            mean(abs(rev_df$m1_rev)), max(abs(rev_df$m1_rev)), rev_df$season[which.max(abs(rev_df$m1_rev))]))
cat(sprintf("  Hard Switch mean |revision|: %.2f pp (max %.2f pp in %s)\n",
            mean(abs(rev_df$hard_rev)), max(abs(rev_df$hard_rev)), rev_df$season[which.max(abs(rev_df$hard_rev))]))

# Blended transition performance for W = 1..4 (Latched)
cat("\nBlended switch MAE by window W (Latched transition):\n")
for (W in 1:4) {
  w_gam <- ifelse(df$eval_weekF < df$first_post_peak, 0,
                  pmin(1, (df$eval_weekF - df$first_post_peak + 1) / W))
  p_blend <- (1 - w_gam) * df$m1_p_hat + w_gam * df$gam_no_p_hat
  err_b <- abs(p_blend - df$actual_p) * 100
  cat(sprintf("  W = %d: All MAE = %.2f pp | Post MAE = %.2f pp\n",
              W, mean(err_b), mean(err_b[df$m1_state == "post_peak"])))
}

# -----------------------------------------------------------------
# 3. OPTION 3: ALWAYS-ON ENSEMBLE
# -----------------------------------------------------------------
cat("\n--- 3. OPTION 3: ALWAYS-ON ENSEMBLE ---\n")
ens_res <- list()
for (w in seq(0, 1, by = 0.1)) {
  p_ens <- w * df$m1_p_hat + (1 - w) * df$gam_no_p_hat
  e <- abs(p_ens - df$actual_p) * 100
  ens_res[[length(ens_res) + 1]] <- data.frame(
    w_m1 = w,
    all_mae = mean(e),
    pre_mae = mean(e[df$m1_state != "post_peak"]),
    post_mae = mean(e[df$m1_state == "post_peak"])
  )
}
ens_df <- do.call(rbind, ens_res)
print(ens_df, row.names = FALSE)

# Phase-dependent weights: Pre w_m1 = 0.3, Post w_m1 = 0.0
p_phase_ens <- ifelse(df$m1_state == "post_peak", df$gam_no_p_hat,
                      0.3 * df$m1_p_hat + 0.7 * df$gam_no_p_hat)
err_phase_ens <- abs(p_phase_ens - df$actual_p) * 100
cat(sprintf("\nPhase-dependent ensemble (Pre w_m1=0.3 / Post w_m1=0.0): All MAE = %.2f pp (Pre = %.2f, Post = %.2f)\n",
            mean(err_phase_ens), mean(err_phase_ens[df$m1_state != "post_peak"]), mean(err_phase_ens[df$m1_state == "post_peak"])))

# -----------------------------------------------------------------
# 4. OPTION 4: AMPLITUDE CONSTRAINT ONLY
# -----------------------------------------------------------------
cat("\n--- 4. OPTION 4: AMPLITUDE CONSTRAINT ONLY ---\n")
p_cap40 <- pmin(df$m1_p_hat, 0.40)
p_cap362 <- pmin(df$m1_p_hat, 0.362)
err_cap40 <- abs(p_cap40 - df$actual_p) * 100
err_cap362 <- abs(p_cap362 - df$actual_p) * 100

cat(sprintf("Uncapped M1:   All = %.2f pp | Post = %.2f pp | 2013-14 Post = %.2f pp | rows > 40%% = %d\n",
            mean(df$err_m1), mean(df$err_m1[df$m1_state == "post_peak"]),
            mean(df$err_m1[df$season == "2013-14" & df$m1_state == "post_peak"]), sum(df$m1_p_hat > 0.40)))
cat(sprintf("Capped 40%%:    All = %.2f pp | Post = %.2f pp | 2013-14 Post = %.2f pp | rows > 40%% = %d\n",
            mean(err_cap40), mean(err_cap40[df$m1_state == "post_peak"]),
            mean(err_cap40[df$season == "2013-14" & df$m1_state == "post_peak"]), sum(p_cap40 > 0.40)))
cat(sprintf("Capped 36.2%%:  All = %.2f pp | Post = %.2f pp | 2013-14 Post = %.2f pp | rows > 36.2%% = %d\n",
            mean(err_cap362), mean(err_cap362[df$m1_state == "post_peak"]),
            mean(err_cap362[df$season == "2013-14" & df$m1_state == "post_peak"]), sum(p_cap362 > 0.362)))

# Check 2013-14 eval 33 h=1
w33 <- df[df$season == "2013-14" & df$eval_weekF == 33 & df$h == 1, ]
cat(sprintf("2013-14 eval 33 h=1: M1 = %.1f%% -> Cap40 = %.1f%% vs Actual = %.1f%% (Residual error = %.1f pp)\n",
            w33$m1_p_hat * 100, min(w33$m1_p_hat, 0.40) * 100, w33$actual_p * 100,
            abs(min(w33$m1_p_hat, 0.40) - w33$actual_p) * 100))

# -----------------------------------------------------------------
# 5. OPTION 5: WHY TAU MISFITS
# -----------------------------------------------------------------
cat("\n--- 5. OPTION 5: TAU MISFIT ANALYSIS ---\n")
df$peak_err_raw <- df$peak_weekF - df$true_peak_raw
df$peak_err_smooth <- df$peak_weekF - df$true_peak_smooth

cat(sprintf("Correlation( |peak_err_raw|, m1_err_pp ) on post-peak rows: r = %.3f (p = %.2e)\n",
            cor(abs(df$peak_err_raw[df$m1_state == "post_peak"]), df$err_m1[df$m1_state == "post_peak"]),
            cor.test(abs(df$peak_err_raw[df$m1_state == "post_peak"]), df$err_m1[df$m1_state == "post_peak"])$p.value))

# State non-monotonicity (un-passing)
cat("\nState flips and reversions to aligning after post_peak:\n")
flips_df <- do.call(rbind, lapply(split(df[df$h == 1, ], df$season[df$h == 1]), function(sub) {
  st <- sub$m1_state
  post_idx <- which(st == "post_peak")
  reverts <- if (length(post_idx) > 0) any(which(st == "aligning") > min(post_idx)) else FALSE
  data.frame(
    season = sub$season[1],
    origins = nrow(sub),
    flips = sum(st[-1] != st[-length(st)]),
    reverts_to_aligning = reverts,
    stringsAsFactors = FALSE
  )
}))
print(flips_df, row.names = FALSE)

cat("\n=================================================================\n")
cat("END DIAGNOSTICS\n")
cat("=================================================================\n")
