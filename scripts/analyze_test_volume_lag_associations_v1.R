#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(glmmTMB))

panel_path <- "artifacts/m2-v2-flu-ab-geometry-v1/flu_ab_weekly_v1.csv"
out_dir <- "artifacts/test-volume-lag-association-v1"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

x <- read.csv(panel_path, stringsAsFactors = FALSE)
stopifnot(all(c("season", "weekF", "y_A", "N_A", "p_A", "denominator_regime") %in% names(x)))

clip <- function(p) pmin(pmax(p, 1e-6), 1 - 1e-6)
logit <- function(p) qlogis(clip(p))

ols_slope <- function(v) {
  t <- seq_along(v)
  unname(coef(stats::lm(v ~ t))[2L])
}

rows <- list()
for (s in sort(unique(x$season))) {
  z <- x[x$season == s, , drop = FALSE]
  z <- z[order(z$weekF), , drop = FALSE]
  pstar <- (z$y_A + 0.5) / (z$N_A + 1)
  lgp <- logit(pstar)
  lnN <- log(z$N_A)
  week_to_i <- stats::setNames(seq_len(nrow(z)), z$weekF)
  week8_i <- unname(week_to_i["8"])

  for (i in seq_len(nrow(z))) {
    w <- z$weekF[i]
    if (w < 13L) next
    hist_i <- unname(week_to_i[as.character((w - 4L):w)])
    if (anyNA(hist_i)) next
    i1 <- unname(week_to_i[as.character(w - 1L)])
    i2 <- unname(week_to_i[as.character(w - 2L)])
    if (anyNA(c(i1, i2))) next

    d1 <- lnN[i] - lnN[unname(week_to_i[as.character(w - 1L)])]
    d2 <- lnN[unname(week_to_i[as.character(w - 1L)])] - lnN[unname(week_to_i[as.character(w - 2L)])]
    d3 <- lnN[unname(week_to_i[as.character(w - 2L)])] - lnN[unname(week_to_i[as.character(w - 3L)])]
    d4 <- lnN[unname(week_to_i[as.character(w - 3L)])] - lnN[unname(week_to_i[as.character(w - 4L)])]

    endpoint <- c(
      ep1 = d1,
      ep2 = (lnN[i] - lnN[unname(week_to_i[as.character(w - 2L)])]) / 2,
      ep3 = (lnN[i] - lnN[unname(week_to_i[as.character(w - 3L)])]) / 3,
      ep4 = (lnN[i] - lnN[unname(week_to_i[as.character(w - 4L)])]) / 4
    )
    ols <- c(
      ols3 = ols_slope(lnN[hist_i[3:5]]),
      ols4 = ols_slope(lnN[hist_i[2:5]]),
      ols5 = ols_slope(lnN[hist_i[1:5]])
    )
    raw_ols <- c(
      rawols3 = ols_slope(z$N_A[hist_i[3:5]]) / mean(z$N_A[hist_i[3:5]]),
      rawols4 = ols_slope(z$N_A[hist_i[2:5]]) / mean(z$N_A[hist_i[2:5]]),
      rawols5 = ols_slope(z$N_A[hist_i[1:5]]) / mean(z$N_A[hist_i[1:5]])
    )
    expdl <- function(lambda) {
      ww <- lambda^(0:3)
      sum(c(d1, d2, d3, d4) * ww) / sum(ww)
    }
    dl <- c(
      exp025 = expdl(0.25), exp050 = expdl(0.50),
      exp075 = expdl(0.75), exp100 = expdl(1.00),
      recent2 = mean(c(d1, d2)), older2 = mean(c(d3, d4))
    )
    relative8 <- if (is.na(week8_i)) NA_real_ else lnN[i] - lnN[week8_i]

    for (h in 1:2) {
      j <- unname(week_to_i[as.character(w + h)])
      if (is.na(j)) next
      rows[[length(rows) + 1L]] <- data.frame(
        season = s, origin_week = w, horizon = h,
        y_target = z$y_A[j], N_target = z$N_A[j], p_target = z$p_A[j],
        logit_current = lgp[i], growth1 = lgp[i] - lgp[i1],
        growth2 = (lgp[i] - lgp[i2]) / 2,
        d1 = d1, d2 = d2, d3 = d3, d4 = d4,
        ep1 = endpoint["ep1"], ep2 = endpoint["ep2"], ep3 = endpoint["ep3"], ep4 = endpoint["ep4"],
        ols3 = ols["ols3"], ols4 = ols["ols4"], ols5 = ols["ols5"],
        rawols3 = raw_ols["rawols3"], rawols4 = raw_ols["rawols4"], rawols5 = raw_ols["rawols5"],
        exp025 = dl["exp025"], exp050 = dl["exp050"], exp075 = dl["exp075"], exp100 = dl["exp100"],
        recent2 = dl["recent2"], older2 = dl["older2"], rel8 = relative8,
        denominator_regime = z$denominator_regime[i], stringsAsFactors = FALSE
      )
    }
  }
}

d <- do.call(rbind, rows)
d$season <- factor(d$season)
d$origin_f <- factor(d$origin_week)
write.csv(d, file.path(out_dir, "common_ledger.csv"), row.names = FALSE)

specs <- list(
  OFF = character(),
  EP1 = "ep1", EP2 = "ep2", EP3 = "ep3", EP4 = "ep4",
  OLS3 = "ols3", OLS4 = "ols4", OLS5 = "ols5",
  RAWOLS3 = "rawols3", RAWOLS4 = "rawols4", RAWOLS5 = "rawols5",
  EXP025 = "exp025", EXP050 = "exp050", EXP075 = "exp075", EXP100 = "exp100",
  SPLIT22 = c("recent2", "older2"),
  DL2 = c("d1", "d2"), DL3 = c("d1", "d2", "d3"), DL4 = c("d1", "d2", "d3", "d4"),
  ALMON1 = c("almon0", "almon1"), ALMON2 = c("almon0", "almon1", "almon2"),
  REL8 = "rel8",
  OLS4_X_G1 = c("ols4", "ols4:growth1"),
  EXP050_X_G1 = c("exp050", "exp050:growth1"),
  SPLIT22_X_G1 = c("recent2", "older2", "recent2:growth1")
)

# Almon basis: sum beta_l d_l with beta_l constrained to polynomial in lag index.
d$almon0 <- d$d1 + d$d2 + d$d3 + d$d4
d$almon1 <- 1*d$d1 + 2*d$d2 + 3*d$d3 + 4*d$d4
d$almon2 <- 1*d$d1 + 4*d$d2 + 9*d$d3 + 16*d$d4

make_formula <- function(terms, ar1 = FALSE) {
  rhs <- c("growth1", "growth2", terms, "offset(logit_current)", "(1|season)")
  if (ar1) rhs <- c(rhs, "ar1(origin_f+0|season)")
  stats::as.formula(paste("cbind(y_target, N_target-y_target) ~", paste(rhs, collapse = " + ")))
}

fit_one <- function(z, terms, ar1) {
  suppressWarnings(glmmTMB(
    make_formula(terms, ar1 = ar1), data = z,
    family = betabinomial(link = "logit"), control = glmmTMBControl(optCtrl = list(iter.max = 500, eval.max = 500))
  ))
}

extract_fit <- function(fit, spec, horizon, structure) {
  sm <- summary(fit)$coefficients$cond
  cc <- data.frame(term = rownames(sm), estimate = sm[, "Estimate"], se = sm[, "Std. Error"],
                   z = sm[, "z value"], p_value = sm[, "Pr(>|z|)"], row.names = NULL)
  cc$spec <- spec; cc$horizon <- horizon; cc$structure <- structure
  cc$or_per_0.1 <- exp(0.1 * cc$estimate)
  cc
}

fits <- list(); coefs <- list(); metrics <- list()
# Primary association screen: beta-binomial mixed model with season random intercept.
for (h in 1:2) {
  z <- d[d$horizon == h, , drop = FALSE]
  for (nm in names(specs)) {
    fit <- try(fit_one(z, specs[[nm]], FALSE), silent = TRUE)
    key <- paste(h, nm, "RI", sep = "__")
    if (inherits(fit, "try-error")) {
      metrics[[length(metrics)+1L]] <- data.frame(horizon=h,spec=nm,structure="RI",converged=FALSE,AIC=NA_real_,logLik=NA_real_,npar=NA_integer_)
      next
    }
    fits[[key]] <- fit
    coefs[[length(coefs)+1L]] <- extract_fit(fit,nm,h,"RI")
    metrics[[length(metrics)+1L]] <- data.frame(horizon=h,spec=nm,structure="RI",converged=isTRUE(fit$sdr$pdHess),AIC=AIC(fit),logLik=as.numeric(logLik(fit)),npar=attr(logLik(fit),"df"),stringsAsFactors=FALSE)
  }
}

# AR(1) sensitivity analysis only for OFF plus the strongest RI specifications
# within each horizon and a few representative lag structures.
ri_metric <- do.call(rbind, metrics)
fixed_ar1 <- c("OFF","EP2","OLS4","EXP050","SPLIT22","DL4","ALMON2","OLS4_X_G1")
for (h in 1:2) {
  mh <- ri_metric[ri_metric$horizon==h & ri_metric$structure=="RI" & is.finite(ri_metric$AIC),]
  top <- head(mh$spec[order(mh$AIC)], 6L)
  shortlist <- unique(c(fixed_ar1, top))
  z <- d[d$horizon == h, , drop = FALSE]
  for (nm in shortlist) {
    if (!nm %in% names(specs)) next
    fit <- try(fit_one(z, specs[[nm]], TRUE), silent = TRUE)
    key <- paste(h,nm,"AR1",sep="__")
    if (inherits(fit,"try-error")) {
      metrics[[length(metrics)+1L]] <- data.frame(horizon=h,spec=nm,structure="AR1",converged=FALSE,AIC=NA_real_,logLik=NA_real_,npar=NA_integer_)
      next
    }
    fits[[key]] <- fit
    coefs[[length(coefs)+1L]] <- extract_fit(fit,nm,h,"AR1")
    metrics[[length(metrics)+1L]] <- data.frame(horizon=h,spec=nm,structure="AR1",converged=isTRUE(fit$sdr$pdHess),AIC=AIC(fit),logLik=as.numeric(logLik(fit)),npar=attr(logLik(fit),"df"),stringsAsFactors=FALSE)
  }
}

coef_df <- do.call(rbind, coefs)
metric_df <- do.call(rbind, metrics)
write.csv(coef_df, file.path(out_dir, "coefficients.csv"), row.names = FALSE)
write.csv(metric_df, file.path(out_dir, "fit_metrics.csv"), row.names = FALSE)

# Likelihood-ratio comparisons to the baseline within each horizon/structure.
lrt <- list()
for (h in 1:2) for (structure in c("RI","AR1")) {
  base <- fits[[paste(h,"OFF",structure,sep="__")]]
  if (is.null(base)) next
  for (nm in setdiff(names(specs),"OFF")) {
    alt <- fits[[paste(h,nm,structure,sep="__")]]
    if (is.null(alt)) next
    a <- try(anova(base,alt),silent=TRUE)
    if (inherits(a,"try-error") || nrow(a)<2) next
    lrt[[length(lrt)+1L]] <- data.frame(horizon=h,structure=structure,spec=nm,
      df_added=a$Df[2]-a$Df[1],LR=as.numeric(a$Chisq[2]),p_value=as.numeric(a$`Pr(>Chisq)`[2]),
      AIC_base=AIC(base),AIC_alt=AIC(alt),delta_AIC=AIC(alt)-AIC(base))
  }
}
lrt_df <- do.call(rbind,lrt)
write.csv(lrt_df,file.path(out_dir,"likelihood_ratio_vs_off.csv"),row.names=FALSE)

# Compact N-related term reports.
primary_ri <- coef_df[coef_df$structure=="RI" & !coef_df$term %in% c("(Intercept)","growth1","growth2"),]
primary_ri <- primary_ri[!grepl("^offset",primary_ri$term),]
write.csv(primary_ri,file.path(out_dir,"primary_ri_n_terms.csv"),row.names=FALSE)
primary_ar1 <- coef_df[coef_df$structure=="AR1" & !coef_df$term %in% c("(Intercept)","growth1","growth2"),]
primary_ar1 <- primary_ar1[!grepl("^offset",primary_ar1$term),]
write.csv(primary_ar1,file.path(out_dir,"primary_ar1_n_terms.csv"),row.names=FALSE)

# Correlation among consecutive increments, useful for diagnosing unrestricted DL collinearity.
cor_lags <- cor(d[,c("d1","d2","d3","d4")], use="complete.obs")
write.csv(cor_lags,file.path(out_dir,"lag_correlation.csv"),row.names=TRUE)

cat("common rows:",nrow(d)," seasons:",nlevels(d$season),"\n")
cat("\nAR1 likelihood-ratio comparisons sorted by horizon/p:\n")
print(lrt_df[lrt_df$structure=="AR1",][order(lrt_df[lrt_df$structure=="AR1","horizon"],lrt_df[lrt_df$structure=="AR1","p_value"]),],row.names=FALSE)
cat("\nPrimary RI N-related coefficients:\n")
print(primary_ri[order(primary_ri$horizon,primary_ri$spec,primary_ri$term),],row.names=FALSE)
cat("\nAR1 sensitivity N-related coefficients:\n")
print(primary_ar1[order(primary_ar1$horizon,primary_ar1$spec,primary_ar1$term),],row.names=FALSE)
cat("\nLag correlations:\n"); print(cor_lags)
