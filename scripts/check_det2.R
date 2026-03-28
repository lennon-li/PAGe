setwd("C:/Users/lennon.li/Documents/claude/PAGe")
load("data/data.RData")
source("R/ignitionTraining.R")

ign_fit <- fitIgnition(
  dat=alignedD, event_k=1L, lead=1L,
  A_pre=6L, B_post=6L, k_week=6L, k_p=8L, k_fs=4L,
  fit_base=TRUE, verbose=FALSE
)

tuned <- readRDS("data/stage1_tuning.rds")
bp    <- tuned$best_params

det <- detectIgnitionBySeason_M0v2(ign_fit, params = bp)

cat("by_season structure:\n")
print(det$by_season)

cat("\n--- 2012-13 data: weekF vs gate states ---\n")
s13 <- det$data[det$data$season == "2012-13", ]
cat("unique(iWeek):", unique(s13$iWeek), "\n")
cat("unique(iWeek_hat):", unique(s13$iWeek_hat), "\n")
cat("weekF range:", range(s13$weekF), "\n")
cat("newWeek range:", range(s13$newWeek), "\n")
cat("ignite_flag at which weekF?", s13$weekF[which(s13$ignite_flag==TRUE)], "\n")
cat("n_hit > 0 at which weekF?", s13$weekF[which(!is.na(s13$n_hit) & s13$n_hit >= 3)], "\n")
cat("\nGate columns around detection:\n")
cols <- c("weekF","newWeek","p_sm","n_hit","cond_sum","cond_p","cond_prev","cond_inc","cond_dp","ignite_flag","ignite_ok")
print(s13[s13$weekF >= 28 & s13$weekF <= 42, cols])

cat("\n--- n_hit == N_req structure ---\n")
dt <- det$data
cat("n_hit range:", range(dt$n_hit, na.rm=TRUE), "\n")
cat("ignite_flag count:", sum(dt$ignite_flag, na.rm=TRUE), "\n")
