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
alignedD_prosp <- add_prospective_derivs_link(alignedD, k=5L, eps=1e-6, min_obs=4L)

joint_out <- suppressWarnings(train_stage2_joint(
  dat=alignedD_prosp, template_df=template_df, spec=spec, verbose=FALSE
))
td  <- joint_out$train_data
fit <- joint_out$fit

# 1) Rows by newWeek bucket
cat("=== Training rows by newWeek bucket ===\n")
td$nw_bucket <- cut(td$newWeek, breaks=c(0,19,25,30,35,40,45,52), include.lowest=TRUE)
print(table(td$nw_bucket, td$lead))

# 2) Which seasons contribute late-season rows?
late <- td[td$newWeek > 38, ]
cat("\n=== Seasons with late-season rows (nw>38) ===\n")
print(table(as.character(late$season)))
cat("Mean p_obs (late season):", mean(late$y_lead/late$N_lead, na.rm=TRUE), "\n")
cat("Template mean at nw>38:", mean(template_df$fit[template_df$newWeek > 38]), "\n")

# 3) Predicted p_hat at each newWeek with three z_ema levels
cat("\n=== p_hat vs template at different z_ema levels (h1) ===\n")
lev_lead   <- levels(fit$model$lead)
lev_season <- levels(fit$model$season)
lev_sh     <- levels(fit$model$season_h)

# For nw 19-52, compute logit_f_eff properly (using spec delta=1, K=4)
nw_seq <- 19:52
td_pred <- template_df[match(pmin(nw_seq + spec$delta, 52L), template_df$newWeek), "fit"]
omega   <- pmin(1, pmax(0, (nw_seq - min(nw_seq)) / spec$K))
lf_eff  <- omega * qlogis(pmax(1e-6, td_pred))

for (z_val in c(-6.0, -4.0, -3.3, -2.0)) {
  nd <- data.frame(
    newWeek     = nw_seq,
    lead        = factor("h1", levels=lev_lead),
    logit_f_eff = lf_eff,
    z_ema       = z_val,
    logN_now    = log(200),
    d1_now      = 0,
    season      = factor(lev_season[1], levels=lev_season),
    season_h    = factor(lev_sh[1],    levels=lev_sh)
  )
  pr <- predict(fit, newdata=nd, type="response",
                exclude=c("s(season)","s(newWeek,season_h)"), se.fit=FALSE)
  cat(sprintf("\nz_ema=%.1f (p≈%.3f), h1 predictions at nw 19-52:\n",
              z_val, plogis(z_val)))
  df_out <- data.frame(nw=nw_seq, p_hat=round(pr,4),
                       template=round(template_df$fit[match(nw_seq, template_df$newWeek)],4))
  print(df_out, row.names=FALSE)
}
