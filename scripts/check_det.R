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

cat("Names of det:", paste(names(det), collapse=", "), "\n")
cat("Names of det$data:", paste(names(det$data), collapse=", "), "\n\n")

dt <- det$data
cat("nrow(dt):", nrow(dt), "\n")
cat("Unique seasons:", length(unique(dt$season)), "\n")

## Check how many rows per (season, iWeek)
grp_size <- aggregate(rep(1, nrow(dt)), list(season=dt$season, iWeek=dt$iWeek), sum)
cat("Max rows per (season, iWeek):", max(grp_size$x), "\n")
cat("Rows per (season, iWeek) distribution:\n"); print(table(grp_size$x))

## Check for an 'ignition' or 'detected' column
cat("\nAll column names:\n"); print(names(dt))

## Show 2012-13 rows 1-5
cat("\n2012-13, first 5 rows:\n")
s13 <- dt[dt$season == "2012-13", ]
print(head(s13[order(s13$iWeek),], 5))

## Check what the detection summary looks like
cat("\ndet$detections (or similar):\n")
print(names(det))
if ("detections" %in% names(det)) print(det$detections)
if ("iWeek_hat" %in% names(det)) print(det$iWeek_hat)
if ("summary" %in% names(det)) print(det$summary)
