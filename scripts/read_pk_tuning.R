pk <- readRDS("data/peak_det_tuning.rds")
pk <- pk[order(pk$use_ci, pk$buffer_weeks), ]
print(pk)

cat("\n--- No-FP candidates (fp_rate == 0) ---\n")
nofp <- pk[pk$fp_rate == 0, ]
nofp <- nofp[order(nofp$mean_delay), ]
print(nofp)

cat("\n--- Best: fp=0, min mean_delay ---\n")
print(nofp[1, ])
