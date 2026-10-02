#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(glmmTMB))

panel_path <- "artifacts/m2-v2-flu-ab-geometry-v1/flu_ab_weekly_v1.csv"
out_dir <- "artifacts/test-volume-lag-association-v2"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

x <- read.csv(panel_path, stringsAsFactors = FALSE)
clip <- function(p) pmin(pmax(p, 1e-6), 1 - 1e-6)
logit <- function(p) qlogis(clip(p))
ols_slope <- function(v) unname(coef(stats::lm(v ~ seq_along(v)))[2L])

rows <- list()
for (s in sort(unique(x$season))) {
  z <- x[x$season == s, , drop = FALSE]
  z <- z[order(z$weekF), , drop = FALSE]
  pstar <- (z$y_A + 0.5) / (z$N_A + 1)
  lgp <- logit(pstar)
  lnN <- log(z$N_A)
  m <- stats::setNames(seq_len(nrow(z)), z$weekF)
  i8 <- unname(m["8"])

  for (i in seq_len(nrow(z))) {
    w <- z$weekF[i]
    if (w < 13L) next
    ih <- unname(m[as.character((w - 4L):w)])
    if (anyNA(ih)) next
    i1 <- unname(m[as.character(w - 1L)])
    i2 <- unname(m[as.character(w - 2L)])
    if (anyNA(c(i1, i2))) next

    lag_i <- unname(m[as.character((w - 4L):w)])
    lv <- lnN[lag_i]
    nv <- z$N_A[lag_i]
    d1 <- lv[5] - lv[4]
    d2 <- lv[4] - lv[3]
    d3 <- lv[3] - lv[2]
    d4 <- lv[2] - lv[1]
    recent2 <- mean(c(d1, d2))
    older2 <- mean(c(d3, d4))
    acceleration <- recent2 - older2
    expdl <- function(lambda) {
      ww <- lambda^(0:3)
      sum(c(d1, d2, d3, d4) * ww) / sum(ww)
    }

    base <- data.frame(
      season = s, origin_week = w,
      logit_current = lgp[i], growth1 = lgp[i] - lgp[i1],
      growth2 = (lgp[i] - lgp[i2]) / 2,
      d1 = d1, d2 = d2, d3 = d3, d4 = d4,
      ep1 = d1,
      ep2 = (lv[5] - lv[3]) / 2,
      ep3 = (lv[5] - lv[2]) / 3,
      ep4 = (lv[5] - lv[1]) / 4,
      ols3 = ols_slope(lv[3:5]), ols4 = ols_slope(lv[2:5]), ols5 = ols_slope(lv),
      rawols3 = ols_slope(nv[3:5]) / mean(nv[3:5]),
      rawols4 = ols_slope(nv[2:5]) / mean(nv[2:5]),
      rawols5 = ols_slope(nv) / mean(nv),
      exp025 = expdl(0.25), exp050 = expdl(0.50), exp075 = expdl(0.75), exp100 = expdl(1.00),
      recent2 = recent2, older2 = older2, accel22 = acceleration,
      rel8 = if (is.na(i8)) NA_real_ else lnN[i] - lnN[i8],
      denominator_regime = z$denominator_regime[i], stringsAsFactors = FALSE
    )
    base$almon0 <- d1 + d2 + d3 + d4
    base$almon1 <- 1*d1 + 2*d2 + 3*d3 + 4*d4
    base$almon2 <- 1*d1 + 4*d2 + 9*d3 + 16*d4

    for (h in 1:2) {
      j <- unname(m[as.character(w + h)])
      if (is.na(j)) next
      r <- base
      r$horizon <- h
      r$y_target <- z$y_A[j]
      r$N_target <- z$N_A[j]
      r$p_target <- z$p_A[j]
      rows[[length(rows) + 1L]] <- r
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
  ACCEL22 = "accel22",
  SPLIT22 = c("recent2", "older2"),
  DL2 = c("d1", "d2"), DL3 = c("d1", "d2", "d3"), DL4 = c("d1", "d2", "d3", "d4"),
  ALMON1 = c("almon0", "almon1"), ALMON2 = c("almon0", "almon1", "almon2"),
  REL8 = "rel8",
  OLS4_X_G1 = c("ols4", "ols4:growth1"),
  EXP050_X_G1 = c("exp050", "exp050:growth1"),
  SPLIT22_X_G1 = c("recent2", "older2", "recent2:growth1")
)

make_formula <- function(terms, ar1 = FALSE) {
  rhs <- c("growth1", "growth2", terms, "offset(logit_current)", "(1|season)")
  if (ar1) rhs <- c(rhs, "ar1(origin_f+0|season)")
  stats::as.formula(paste("cbind(y_target, N_target-y_target) ~", paste(rhs, collapse = " + ")))
}
fit_one <- function(z, terms, ar1 = FALSE) suppressWarnings(glmmTMB(
  make_formula(terms, ar1), data = z, family = betabinomial(link = "logit"),
  control = glmmTMBControl(optCtrl = list(iter.max = 500, eval.max = 500))))
extract <- function(fit, h, nm, structure) {
  sm <- summary(fit)$coefficients$cond
  data.frame(horizon=h, spec=nm, structure=structure, term=rownames(sm),
             estimate=sm[,"Estimate"], se=sm[,"Std. Error"], z=sm[,"z value"],
             p_value=sm[,"Pr(>|z|)"], or_per_0.1=exp(0.1*sm[,"Estimate"]),
             stringsAsFactors=FALSE, row.names=NULL)
}

fits <- list(); coef_rows <- list(); metric_rows <- list()
for (h in 1:2) {
  z <- d[d$horizon == h, , drop = FALSE]
  for (nm in names(specs)) {
    fit <- try(fit_one(z, specs[[nm]], FALSE), silent = TRUE)
    if (inherits(fit, "try-error")) next
    key <- paste(h,nm,"RI",sep="__"); fits[[key]] <- fit
    coef_rows[[length(coef_rows)+1L]] <- extract(fit,h,nm,"RI")
    metric_rows[[length(metric_rows)+1L]] <- data.frame(horizon=h,spec=nm,structure="RI",
      converged=isTRUE(fit$sdr$pdHess),AIC=AIC(fit),logLik=as.numeric(logLik(fit)),df=attr(logLik(fit),"df"))
  }
}

# Refit a fixed representative set with within-season AR1 correlation.
ar1_specs <- c("OFF","EP2","OLS4","EXP050","ACCEL22","DL2","DL4","ALMON2","REL8","EXP050_X_G1")
for (h in 1:2) {
  z <- d[d$horizon == h, , drop = FALSE]
  for (nm in ar1_specs) {
    fit <- try(fit_one(z, specs[[nm]], TRUE), silent = TRUE)
    if (inherits(fit,"try-error")) next
    key <- paste(h,nm,"AR1",sep="__"); fits[[key]] <- fit
    coef_rows[[length(coef_rows)+1L]] <- extract(fit,h,nm,"AR1")
    metric_rows[[length(metric_rows)+1L]] <- data.frame(horizon=h,spec=nm,structure="AR1",
      converged=isTRUE(fit$sdr$pdHess),AIC=AIC(fit),logLik=as.numeric(logLik(fit)),df=attr(logLik(fit),"df"))
  }
}

coef_df <- do.call(rbind,coef_rows)
metrics <- do.call(rbind,metric_rows)
write.csv(coef_df,file.path(out_dir,"coefficients.csv"),row.names=FALSE)
write.csv(metrics,file.path(out_dir,"fit_metrics.csv"),row.names=FALSE)

# Manual LR test against OFF on identical rows.
lrt <- list()
for (h in 1:2) for (structure in c("RI","AR1")) {
  b <- fits[[paste(h,"OFF",structure,sep="__")]]
  if (is.null(b)) next
  candidates <- if (structure=="RI") setdiff(names(specs),"OFF") else setdiff(ar1_specs,"OFF")
  for (nm in candidates) {
    a <- fits[[paste(h,nm,structure,sep="__")]]
    if (is.null(a)) next
    lr <- 2*(as.numeric(logLik(a))-as.numeric(logLik(b)))
    ddf <- attr(logLik(a),"df")-attr(logLik(b),"df")
    lrt[[length(lrt)+1L]] <- data.frame(horizon=h,structure=structure,spec=nm,
      df_added=ddf,LR=lr,p_value=if(ddf>0) pchisq(lr,df=ddf,lower.tail=FALSE) else NA_real_,
      delta_AIC=AIC(a)-AIC(b),stringsAsFactors=FALSE)
  }
}
lrt <- do.call(rbind,lrt)
write.csv(lrt,file.path(out_dir,"likelihood_ratio_vs_off.csv"),row.names=FALSE)
write.csv(cor(d[,c("d1","d2","d3","d4")]),file.path(out_dir,"lag_correlation.csv"))

cat("rows=",nrow(d)," seasons=",nlevels(d$season),"\n",sep="")
for (h in 1:2) {
  cat("\nRI top AIC horizon ",h,"\n",sep="")
  mm <- metrics[metrics$horizon==h & metrics$structure=="RI",]
  print(head(mm[order(mm$AIC),c("spec","AIC","converged")],12),row.names=FALSE)
  cat("\nAR1 representative LRT horizon ",h,"\n",sep="")
  ll <- lrt[lrt$horizon==h & lrt$structure=="AR1",]
  print(ll[order(ll$p_value),],row.names=FALSE)
}
