#!/usr/bin/env Rscript
# Interval-coverage check for the phase-weighted M2 fit (oracle plan 1.4).
#
# Weighting the binomial likelihood by the phase weight inflates the apparent
# sample size, which shifts REML's smoothing choice and shrinks se.fit. The
# earlier diagnostic measured that shrinkage (9% tighter on the link scale)
# but not whether the resulting intervals still cover. Coverage is a
# user-facing output -- m2_lo/m2_hi ship in the weekly forecast -- so it needs
# measuring rather than assuming.
#
# Two intervals are reported because the shipped one is not what its name
# suggests. m2_training.R:171 builds plogis(eta +/- 1.96 * se.fit): a
# CONFIDENCE interval for the mean probability, carrying parameter
# uncertainty only. The thing a reader compares it against -- an observed
# weekly positivity -- also carries binomial sampling noise, which that
# interval does not include. So:
#
#   ci_cov   coverage of the shipped interval, as built today
#   pi_cov   coverage of a predictive interval that adds binomial noise
#
# Nominal is 95% for both. A low ci_cov is expected even for a correct model
# and is a property of the interval's definition, not of the weighting; the
# weighting question is whether arm B is materially WORSE than arm A.

suppressPackageStartupMessages({
  library(PAGe)
  library(mgcv)
})

art <- Sys.getenv(
  "PAGE_EXP_ARTIFACTS",
  "results/final-kit-2026-27/20260918T1520Z-final-2026-27-wmin8-venkata/artifacts"
)
out_dir <- Sys.getenv("PAGE_EXP_OUT", "results/experiments/interval-coverage")
n_sim <- as.integer(Sys.getenv("PAGE_EXP_NSIM", "4000"))
set.seed(20260919L)

tuning <- readRDS(file.path(art, "m2_tuning.rds"))
dat <- as.data.frame(tuning$training_rows)
grid <- as.data.frame(tuning$grid)
avail <- !is.na(dat$forecast_available) & dat$forecast_available
dat <- dat[avail, , drop = FALSE]
seasons <- sort(unique(as.character(dat$season)))

# The grid approved for the re-run: k_z and k_u dropped, k_d/k_tau at a
# single modest basis dimension, conf_scale none. All-off carries no fitted
# object and so has no se.fit; it is excluded here by construction.
keep <- grid$k_z == 0 & grid$k_u == 0 &
  grid$k_d %in% c(0L, 4L) & grid$k_tau %in% c(0L, 4L) &
  grid$conf_scale == "none" & grid$enabled_count > 0L
specs <- grid[keep, , drop = FALSE]
cat("specs under test:", nrow(specs), "\n")
cat("  ", paste(specs$id, collapse = "\n   "), "\n\n")

# Arm B: the phase-weighted fitter, built by patching the single weight line.
src <- deparse(PAGe:::m2_subset_fit)
i <- grep("\\.fit_weight <- unname\\(mean\\(season_totals\\)", src)
stopifnot(length(i) >= 1L)
i <- i[1L]
src[i] <- paste(
  "    dat$.fit_weight <- unname(mean(season_totals) /",
  "season_totals[as.character(dat$season)]) * as.numeric(dat$weight_page_v2)"
)
fit_B <- eval(parse(text = paste(src, collapse = "\n")))
environment(fit_B) <- asNamespace("PAGe")

eval_arm <- function(fitter, spec) {
  rows <- lapply(seasons, function(s) {
    tr <- dat[dat$season != s, , drop = FALSE]
    va <- dat[dat$season == s, , drop = FALSE]
    f <- tryCatch(fitter(tr, spec, gamma = 1.4), error = function(e) NULL)
    if (is.null(f) || is.null(f$fit)) return(NULL)
    nd <- PAGe:::m2_subset_apply_ranges(va, f$feature_ranges)
    nd$lead <- factor(as.character(nd$lead), levels = c("h1", "h2"))
    pr <- tryCatch(
      stats::predict(f$fit, newdata = nd, type = "link", se.fit = TRUE),
      error = function(e) NULL
    )
    if (is.null(pr)) return(NULL)
    eta <- as.numeric(pr$fit)
    se <- as.numeric(pr$se.fit)
    obs <- va$y_lead / va$N_lead

    # Shipped interval: parameter uncertainty only (m2_training.R:171).
    lo <- stats::plogis(eta - 1.96 * se)
    hi <- stats::plogis(eta + 1.96 * se)

    # Predictive interval: draw the mean from its sampling distribution, then
    # draw the count, so binomial noise is included.
    pi_lo <- pi_hi <- numeric(length(eta))
    for (j in seq_along(eta)) {
      p <- stats::plogis(stats::rnorm(n_sim, eta[j], se[j]))
      y <- stats::rbinom(n_sim, size = round(va$N_lead[j]), prob = p)
      q <- stats::quantile(y / round(va$N_lead[j]), c(0.025, 0.975), names = FALSE)
      pi_lo[j] <- q[1L]; pi_hi[j] <- q[2L]
    }
    data.frame(
      season = s, obs = obs, se = se,
      ci_in = obs >= lo & obs <= hi,
      pi_in = obs >= pi_lo & obs <= pi_hi,
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

res <- do.call(rbind, lapply(seq_len(nrow(specs)), function(k) {
  sp <- specs[k, , drop = FALSE]
  a <- eval_arm(PAGe:::m2_subset_fit, sp)
  b <- eval_arm(fit_B, sp)
  if (is.null(a) || is.null(b)) return(NULL)
  data.frame(
    spec_id = as.character(sp$id[1L]),
    n = nrow(a),
    se_A = mean(a$se), se_B = mean(b$se),
    ci_A = mean(a$ci_in), ci_B = mean(b$ci_in),
    pi_A = mean(a$pi_in), pi_B = mean(b$pi_in),
    stringsAsFactors = FALSE
  )
}))

dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
utils::write.csv(res, file.path(out_dir, "coverage_by_spec.csv"), row.names = FALSE)

cat("=== out-of-sample coverage, nominal 0.95 ===\n")
cat("  ci_* = shipped interval (parameter uncertainty only)\n")
cat("  pi_* = predictive interval (adds binomial noise)\n\n")
print(res, row.names = FALSE, digits = 3)

cat("\n=== pooled ===\n")
cat(sprintf("mean se   A %.5f   B %.5f   ratio %.3f\n",
  mean(res$se_A), mean(res$se_B), mean(res$se_B) / mean(res$se_A)))
cat(sprintf("ci cover  A %.3f   B %.3f   change %+.3f\n",
  mean(res$ci_A), mean(res$ci_B), mean(res$ci_B) - mean(res$ci_A)))
cat(sprintf("pi cover  A %.3f   B %.3f   change %+.3f\n",
  mean(res$pi_A), mean(res$pi_B), mean(res$pi_B) - mean(res$pi_A)))
cat("\nwrote:", out_dir, "\n")
