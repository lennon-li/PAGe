#!/usr/bin/env Rscript
# EXPERIMENT (diagnostic, not a selection step).
#
# Question: should the M2 GAM's fitting weights include the phase weight
# (weight_page_v2) that selection and the adoption gate score on, or only the
# season trial-count balance they use today (m2_subset_correction.R:444)?
#
# This is deliberately NOT a "run both and keep the winner" comparison. Doing
# that would select a fitting procedure on the same evidence the gate judges,
# which is the circularity the analysis protocol forbids. The adoption
# argument is decision-theoretic and made in advance: optimise the loss you
# are graded on. This run exists to check for a SURPRISE -- specifically the
# known risk that utility-weighting a binomial likelihood inflates apparent
# sample size, which shifts REML's smoothing choice and can make predictive
# uncertainty optimistic.
#
# Design notes that make the result mean anything:
#   * Out-of-sample only. In-sample, arm B necessarily wins on the weighted
#     score because it is directly maximising it -- that comparison is
#     near-tautological and is not reported.
#   * Leave-one-season-out: every season is scored by a fit that never saw it.
#   * Every spec in the grid, not a chosen one, so nothing is cherry-picked.
#   * Paired by (spec, season) so between-season spread -- which dominates at
#     n=11 -- cancels in the comparison.
#   * Direction-of-effect across seasons is the headline, not the pooled mean.
#     At this n a small mean difference is not resolvable; a consistent sign is.

suppressPackageStartupMessages({
  library(PAGe)
  library(mgcv)
})

art <- Sys.getenv(
  "PAGE_EXP_ARTIFACTS",
  "results/final-kit-2026-27/20260918T1520Z-final-2026-27-wmin8-venkata/artifacts"
)
out_dir <- Sys.getenv("PAGE_EXP_OUT", "results/experiments/phase-fit-weight")
n_cores <- as.integer(Sys.getenv("PAGE_N_CORES", "10"))

tuning <- readRDS(file.path(art, "m2_tuning.rds"))
dat <- as.data.frame(tuning$training_rows)
grid <- as.data.frame(tuning$grid)

# Mirror the real tuner: rows whose forecast was never available carry
# non-finite features and are excluded from both fitting and scoring
# (.m2_subset_select_core does the same before every fit). Without this the
# fitter refuses the frame outright.
avail <- if ("forecast_available" %in% names(dat)) {
  !is.na(dat$forecast_available) & dat$forecast_available
} else {
  rep(TRUE, nrow(dat))
}
cat("rows dropped as unavailable:", sum(!avail), "of", nrow(dat), "\n")
dat <- dat[avail, , drop = FALSE]
seasons <- sort(unique(as.character(dat$season)))

cat("== phase-fit-weight experiment ==\n")
cat("training rows :", nrow(dat), "\n")
cat("seasons       :", length(seasons), "\n")
cat("specs         :", nrow(grid), "\n")
cat("source        :", art, "\n\n")

# ---- Build arm B by patching exactly one line of the real fitter -----------
# Both arms therefore run byte-identical code apart from the weight itself:
# same formula, same paraPen, same feature ranges, same REML call. Arm A is
# the stock function, untouched.
src <- deparse(PAGe:::m2_subset_fit)
target <- grep("\\.fit_weight <- unname\\(mean\\(season_totals\\)", src)
stopifnot(length(target) == 1L)
cat("patching line:\n  ", trimws(src[target]), "\n")
src[target] <- paste(
  "    dat$.fit_weight <- unname(mean(season_totals) /",
  "season_totals[as.character(dat$season)]) * as.numeric(dat$weight_page_v2)"
)
cat("          ->\n  ", trimws(src[target]), "\n\n")
m2_fit_phase <- eval(parse(text = paste(src, collapse = "\n")))
environment(m2_fit_phase) <- asNamespace("PAGe")

# ---- Metrics ---------------------------------------------------------------
nll_rows <- function(y, N, p) {
  p <- pmin(1 - 1e-12, pmax(1e-12, p))
  -(y * log(p) + (N - y) * log(1 - p)) / N
}

score_fold <- function(fit, va) {
  pr <- PAGe:::m2_subset_predict(fit, va)
  nll <- nll_rows(va$y_lead, va$N_lead, pr$p_hat)
  w <- as.numeric(va$weight_page_v2)
  # Mean predictive SE on the link scale: the optimism probe. If arm B buys
  # no out-of-sample accuracy but reports systematically tighter uncertainty,
  # that is the inflated-sample-size effect showing up.
  se <- NA_real_
  if (!is.null(fit$fit)) {
    se <- tryCatch({
      nd <- PAGe:::m2_subset_apply_ranges(va, fit$feature_ranges)
      nd$lead <- factor(as.character(nd$lead), levels = c("h1", "h2"))
      mean(stats::predict(fit$fit, newdata = nd, type = "link", se.fit = TRUE)$se.fit)
    }, error = function(e) NA_real_)
  }
  c(
    wnll = sum(w * nll) / sum(w),
    unll = mean(nll),
    se_link = se
  )
}

run_spec <- function(i) {
  spec <- grid[i, , drop = FALSE]
  out <- lapply(seasons, function(s) {
    tr <- dat[dat$season != s, , drop = FALSE]
    va <- dat[dat$season == s, , drop = FALSE]
    if (!nrow(va)) return(NULL)
    fa <- tryCatch(PAGe:::m2_subset_fit(tr, spec, gamma = 1.4), error = function(e) NULL)
    fb <- tryCatch(m2_fit_phase(tr, spec, gamma = 1.4), error = function(e) NULL)
    if (is.null(fa) || is.null(fb)) return(NULL)
    sa <- tryCatch(score_fold(fa, va), error = function(e) NULL)
    sb <- tryCatch(score_fold(fb, va), error = function(e) NULL)
    if (is.null(sa) || is.null(sb)) return(NULL)
    data.frame(
      spec_id = as.character(spec$id[1L]),
      enabled_count = spec$enabled_count[1L],
      season = s,
      wnll_A = sa[["wnll"]], wnll_B = sb[["wnll"]],
      unll_A = sa[["unll"]], unll_B = sb[["unll"]],
      se_A = sa[["se_link"]], se_B = sb[["se_link"]],
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, out)
}

idx <- seq_len(nrow(grid))
res <- if (n_cores > 1L && requireNamespace("parallel", quietly = TRUE)) {
  do.call(rbind, parallel::mclapply(idx, run_spec, mc.cores = n_cores))
} else {
  do.call(rbind, lapply(idx, run_spec))
}

dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
utils::write.csv(res, file.path(out_dir, "per_spec_season.csv"), row.names = FALSE)

# ---- Report ----------------------------------------------------------------
res$d_wnll <- res$wnll_B - res$wnll_A # negative => arm B better
corr <- res[res$enabled_count > 0L, , drop = FALSE]

cat("\n=== all-off sanity (must be identical in both arms) ===\n")
off <- res[res$enabled_count == 0L, , drop = FALSE]
cat("max |wnll_B - wnll_A| on all-off:", format(max(abs(off$d_wnll)), digits = 3), "\n")

cat("\n=== out-of-sample weighted NLL, corrected specs only ===\n")
cat("spec x season comparisons:", nrow(corr), "\n")
cat("arm A (season balance only) mean:", round(mean(corr$wnll_A), 6), "\n")
cat("arm B (+ phase weight)      mean:", round(mean(corr$wnll_B), 6), "\n")
cat("mean paired difference (B-A)    :", round(mean(corr$d_wnll), 6), "\n")
cat("B better in", sum(corr$d_wnll < 0), "of", nrow(corr),
  sprintf("(%.1f%%)\n", 100 * mean(corr$d_wnll < 0)))

cat("\n=== direction by season (the headline at n=11) ===\n")
by_season <- do.call(rbind, lapply(split(corr, corr$season), function(z) {
  data.frame(
    season = z$season[1L], n_specs = nrow(z),
    mean_d = mean(z$d_wnll), B_better_pct = 100 * mean(z$d_wnll < 0)
  )
}))
by_season <- by_season[order(by_season$season), ]
print(by_season, row.names = FALSE, digits = 4)
cat("\nseasons where B is better on average:",
  sum(by_season$mean_d < 0), "of", nrow(by_season), "\n")

cat("\n=== uncertainty probe (mean predictive SE, link scale) ===\n")
ok <- is.finite(corr$se_A) & is.finite(corr$se_B)
cat("arm A mean SE:", round(mean(corr$se_A[ok]), 5), "\n")
cat("arm B mean SE:", round(mean(corr$se_B[ok]), 5), "\n")
cat("B/A SE ratio :", round(mean(corr$se_B[ok]) / mean(corr$se_A[ok]), 4),
  " (<1 means B reports tighter uncertainty)\n")

saveRDS(list(res = res, by_season = by_season), file.path(out_dir, "summary.rds"))
cat("\nwrote:", out_dir, "\n")
