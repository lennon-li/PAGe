setwd("C:/Users/lennon.li/Documents/claude/PAGe")
suppressPackageStartupMessages({ library(dplyr); library(mgcv); library(data.table) })
source("R/ignitionTraining.R")
source("R/module_training.R")
source("R/prospective_training.R")
source("R/prospective_running.R")
load("data/data.RData")

tuned2 <- readRDS("data/stage2_tuning.rds")
spec   <- stage2_spec_from_tuning(tuned2)
d_calib_oos <- readRDS("data/stage2_calib_loso.rds")
cal_off <- train_calib_platt(d_calib_oos)

cat("=== Calibration a, b ===\n")
cat("a:", round(cal_off$a, 4), "\nb:", round(cal_off$b, 4), "\n")
cat("\nEffect of calibration on raw predictions:\n")
for (p_raw in c(0.03, 0.05, 0.08, 0.12, 0.20)) {
  for (h in c("h1","h2")) {
    lp_cal <- cal_off$a[h] + cal_off$b[h] * qlogis(p_raw)
    p_cal  <- plogis(lp_cal)
    cat(sprintf("  p_raw=%.2f, %s -> p_cal=%.4f (diff=%.4f)\n",
                p_raw, h, p_cal, p_cal - p_raw))
  }
}

# Retrain
alignedD_prosp <- add_prospective_derivs_link(alignedD, k=5L, eps=1e-6, min_obs=4L)
joint_out <- suppressWarnings(train_stage2_joint(
  dat=alignedD_prosp, template_df=template_df, spec=spec, verbose=FALSE
))
fit <- joint_out$fit
td  <- joint_out$train_data

cat("\n=== Training data ranges ===\n")
cat("newWeek:", range(td$newWeek, na.rm=TRUE), "\n")
cat("z_ema:   ", round(range(td$z_ema, na.rm=TRUE), 3), "(mean:", round(mean(td$z_ema, na.rm=TRUE),3),")\n")
cat("logit_f_eff:", round(range(td$logit_f_eff, na.rm=TRUE), 3), "\n")
cat("t_since:", range(td$t_since, na.rm=TRUE), "\n")

sm <- summary(fit)
cat("\n=== Smooth term EDF ===\n")
print(sm$s.table)

# Inspect newWeek smooth contribution at end of season
cat("\n=== newWeek smooth contribution (marginal) at nw=1-52 ===\n")
lev_lead   <- levels(fit$model$lead)
lev_season <- levels(fit$model$season)
lev_sh     <- levels(fit$model$season_h)

for (h in c("h1","h2")) {
  nd <- data.frame(
    newWeek    = 1:52,
    lead       = factor(h, levels=lev_lead),
    logit_f_eff = 0,
    z_ema      = mean(td$z_ema, na.rm=TRUE),
    logN_now   = mean(td$logN_now %||% log(100), na.rm=TRUE),
    d1_now     = 0,
    season     = factor(lev_season[1], levels=lev_season),
    season_h   = factor(lev_sh[1], levels=lev_sh)
  )
  if ("d2_now" %in% names(fit$model)) nd$d2_now <- 0

  pr <- predict(fit, newdata=nd, type="response",
                exclude=c("s(season)","s(newWeek,season_h)"), se.fit=FALSE)
  cat(sprintf("\n%s: mean z_ema=%.3f, nw smooth effect -> p_hat at nw 30-52:\n  %s\n",
              h, mean(td$z_ema, na.rm=TRUE),
              paste(sprintf("%.4f", pr[30:52]), collapse=" ")))
}

# Predicted p at mean covariates vs template
cat("\n=== Model prediction vs template at mean z_ema ===\n")
cat("Template values at nw 19-40:\n")
tpl_sub <- template_df[template_df$newWeek >= 19 & template_df$newWeek <= 40, ]
print(tpl_sub)

# Check 2025-26 z_ema
cat("\n=== Current season z_ema ===\n")
cs <- tryCatch(source("R/getCurrentD.R")$value, error=function(e) NULL)
if (is.null(cs)) {
  # Try loading from data
  cs2526 <- tryCatch({
    getCurrentD()
  }, error=function(e) {
    cat("getCurrentD() failed:", conditionMessage(e), "\n"); NULL
  })
} else {
  cs2526 <- cs
}
if (!is.null(cs2526)) {
  cat("Weeks available:", range(cs2526$weekF), "\n")
  p_cs <- cs2526$y / pmax(cs2526$N, 1)
  z_cs <- qlogis(pmax(1e-6, pmin(1-1e-6, p_cs)))
  alpha <- spec$alpha_state
  z_ema_cs <- numeric(length(z_cs)); z_ema_cs[1] <- z_cs[1]
  for (i in seq_along(z_cs)[-1]) z_ema_cs[i] <- alpha*z_cs[i] + (1-alpha)*z_ema_cs[i-1]
  cat("Current z_ema (last 8):", round(tail(z_ema_cs, 8), 3), "\n")
  cat("Training z_ema quantiles (0.1, 0.25, 0.5, 0.75, 0.9):\n")
  print(quantile(td$z_ema, c(0.1,0.25,0.5,0.75,0.9), na.rm=TRUE))
}
