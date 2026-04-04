setwd("C:/Users/lennon.li/Documents/claude/PAGe")
suppressPackageStartupMessages({ library(dplyr); library(mgcv); library(data.table) })
source("R/m0_training.R")
source("R/m2_spec_grid.R")
source("R/m2_training.R")
source("R/pipeline_runtime_helpers.R")
source("R/m0_runtime.R")
source("R/m2_runtime.R")
source("R/pipeline_runtime.R")
load("data/data.RData")

tuned2 <- readRDS("data/stage2_tuning.rds")
spec   <- stage2_spec_from_tuning(tuned2)

cat("=== Best spec ===\n")
cat("delta:", spec$delta, "K:", spec$K, "k_f:", spec$k_f,
    "alpha_state:", spec$alpha_state, "pre_buffer:", spec$pre_buffer, "\n")
cat("k_w:", spec$k_w, "k_s:", spec$k_s, "k_e:", spec$k_e,
    "k_n:", spec$k_n, "k_1:", spec$k_1, "k_2:", spec$k_2, "\n")

# -------------------------------------------------------------------
# Calibration: extract a, b per lead
# -------------------------------------------------------------------
cat("\n=== Calibration coefficients ===\n")
d_calib_oos <- readRDS("data/stage2_calib_loso.rds")

if (requireNamespace("data.table", quietly=TRUE)) {
  cal_off <- train_calib_platt(d_calib_oos)
  cat("a (intercept):\n"); print(cal_off$a)
  cat("b (slope):\n");     print(cal_off$b)

  cat("\nMean p_hat by lead:\n")
  for (h in sort(unique(d_calib_oos$lead))) {
    dh <- d_calib_oos[d_calib_oos$lead == h, ]
    p_obs <- dh$y / dh$N
    cat(sprintf("  lead=%s: n=%d, mean(p_hat)=%.4f, mean(p_obs)=%.4f, mean(logit_phat)=%.3f\n",
                h, nrow(dh), mean(dh$p_hat, na.rm=TRUE),
                mean(p_obs, na.rm=TRUE),
                mean(qlogis(pmax(1e-6, pmin(1-1e-6, dh$p_hat))), na.rm=TRUE)))
  }
}

# -------------------------------------------------------------------
# Retrain model to inspect the newWeek smooth
# -------------------------------------------------------------------
cat("\n=== Retraining model on all seasons ===\n")
alignedD_prosp <- add_prospective_derivs_link(alignedD, k=5L, eps=1e-6, min_obs=4L)

joint_out <- train_stage2_joint(
  dat         = alignedD_prosp,
  template_df = template_df,
  spec        = spec,
  verbose     = TRUE
)

fit <- joint_out$fit
cat("\n--- GAM smooth summary ---\n")
sm <- summary(fit)
print(sm$s.table[, c("edf","Ref.df","F","p-value")])

# Range of key covariates in training
td <- joint_out$train_data
cat("\n--- Training data ranges ---\n")
cat("newWeek:", min(td$newWeek, na.rm=TRUE), "-", max(td$newWeek, na.rm=TRUE), "\n")
cat("z_ema:  ", round(range(td$z_ema, na.rm=TRUE), 3), "\n")
cat("logit_f_eff:", round(range(td$logit_f_eff, na.rm=TRUE), 3), "\n")
cat("t_since:", range(td$t_since, na.rm=TRUE), "\n")

# Check newWeek smooth at end of season for h1 and h2
cat("\n--- Predicted contribution of s(newWeek, by=lead) ---\n")
nw_seq <- 1:52
for (h in c("h1","h2")) {
  nd_nw <- data.frame(
    newWeek    = nw_seq,
    lead       = factor(h, levels = levels(fit$model$lead)),
    logit_f_eff = 0,
    z_ema      = 0,
    logN_now   = log(100),
    d1_now     = 0,
    d2_now     = 0,
    season     = factor(levels(fit$model$season)[1], levels = levels(fit$model$season)),
    season_h   = factor(levels(fit$model$season_h)[1], levels = levels(fit$model$season_h))
  )
  # Predict with only the newWeek smooth active (exclude everything else)
  # Use terms argument
  ex_all_but_nw <- sm$s.names[!grepl("newWeek.*lead", sm$s.names)]
  pr_nw <- predict(fit, newdata=nd_nw, type="terms",
                   exclude=c("s(season)","s(newWeek,season_h)","(Intercept)"))
  # grab the newWeek term column
  nw_col <- grep(paste0("newWeek.*", h), colnames(pr_nw), value=TRUE)
  if (length(nw_col) == 1) {
    cat(sprintf("  %s s(newWeek) at nw=30-52: %s\n", h,
                paste(round(pr_nw[nw_seq >= 30, nw_col], 3), collapse=" ")))
  } else {
    cat("  Term columns found:", paste(colnames(pr_nw), collapse=", "), "\n")
  }
}

# -------------------------------------------------------------------
# Check 2025-26 z_ema vs training distribution
# -------------------------------------------------------------------
cat("\n=== 2025-26 z_ema vs training data ===\n")
source("R/getCurrentD.R")
currentSeason <- tryCatch(getCurrentD(), error = function(e) {
  cat("getCurrentD() failed:", conditionMessage(e), "\n"); NULL
})
if (!is.null(currentSeason)) {
  cat("Current season rows:", nrow(currentSeason),
      " weekF range:", range(currentSeason$weekF), "\n")
  p_cs <- currentSeason$y / pmax(currentSeason$N, 1)
  z_cs <- qlogis(pmax(1e-6, pmin(1-1e-6, p_cs)))
  alpha <- spec$alpha_state
  z_ema_cs <- numeric(length(z_cs)); z_ema_cs[1] <- z_cs[1]
  for (i in seq_along(z_cs)[-1]) z_ema_cs[i] <- alpha*z_cs[i] + (1-alpha)*z_ema_cs[i-1]
  cat("z_ema 2025-26 (last 10 weeks):",
      round(tail(z_ema_cs, 10), 3), "\n")
  cat("Training z_ema range:", round(range(td$z_ema, na.rm=TRUE), 3), "\n")
  cat("Training z_ema mean:", round(mean(td$z_ema, na.rm=TRUE), 3), "\n")
}
