#!/usr/bin/env Rscript
suppressPackageStartupMessages(library(glmmTMB))
out_dir <- "artifacts/test-volume-lag-association-v2"
d <- read.csv(file.path(out_dir, "common_ledger.csv"), stringsAsFactors = FALSE)
d$season <- factor(d$season)
specs <- list(
  OFF=character(), EP1="ep1", EP2="ep2", EP3="ep3", EP4="ep4",
  OLS3="ols3", OLS4="ols4", OLS5="ols5",
  RAWOLS3="rawols3", RAWOLS4="rawols4", RAWOLS5="rawols5",
  EXP025="exp025", EXP050="exp050", EXP075="exp075", EXP100="exp100",
  ACCEL22="accel22", SPLIT22=c("recent2","older2"),
  DL2=c("d1","d2"), DL3=c("d1","d2","d3"), DL4=c("d1","d2","d3","d4"),
  ALMON1=c("almon0","almon1"), ALMON2=c("almon0","almon1","almon2"), REL8="rel8",
  OLS4_X_G1=c("ols4","ols4:growth1"), EXP050_X_G1=c("exp050","exp050:growth1"),
  SPLIT22_X_G1=c("recent2","older2","recent2:growth1")
)
mkf <- function(tt) as.formula(paste(
  "cbind(y_target,N_target-y_target) ~",
  paste(c("growth1","growth2",tt,"offset(logit_current)","(1|season)"), collapse=" + ")
))
fits <- list(); cr <- list(); mr <- list(); lr <- list()
for (h in 1:2) {
  z <- d[d$horizon == h, , drop=FALSE]
  for (nm in names(specs)) {
    f <- suppressWarnings(glmmTMB(mkf(specs[[nm]]), data=z, family=betabinomial(link="logit"),
      control=glmmTMBControl(optCtrl=list(iter.max=500, eval.max=500))))
    fits[[paste(h,nm,sep="__")]] <- f
    sm <- summary(f)$coefficients$cond
    cr[[length(cr)+1L]] <- data.frame(horizon=h,spec=nm,term=rownames(sm),estimate=sm[,"Estimate"],
      se=sm[,"Std. Error"],z=sm[,"z value"],p_value=sm[,"Pr(>|z|)"],or_per_0.1=exp(0.1*sm[,"Estimate"]),row.names=NULL)
    mr[[length(mr)+1L]] <- data.frame(horizon=h,spec=nm,AIC=AIC(f),logLik=as.numeric(logLik(f)),
      df=attr(logLik(f),"df"),converged=isTRUE(f$sdr$pdHess))
  }
  b <- fits[[paste(h,"OFF",sep="__")]]
  for (nm in setdiff(names(specs),"OFF")) {
    a <- fits[[paste(h,nm,sep="__")]]
    lrv <- 2*(as.numeric(logLik(a))-as.numeric(logLik(b)))
    ddf <- attr(logLik(a),"df")-attr(logLik(b),"df")
    lr[[length(lr)+1L]] <- data.frame(horizon=h,spec=nm,df_added=ddf,LR=lrv,
      p_value=pchisq(lrv,ddf,lower.tail=FALSE),delta_AIC=AIC(a)-AIC(b))
  }
}
cr <- do.call(rbind,cr); mr <- do.call(rbind,mr); lr <- do.call(rbind,lr)
write.csv(cr,file.path(out_dir,"ri_coefficients.csv"),row.names=FALSE)
write.csv(mr,file.path(out_dir,"ri_fit_metrics.csv"),row.names=FALSE)
write.csv(lr,file.path(out_dir,"ri_lrt_vs_off.csv"),row.names=FALSE)
cat("rows=",nrow(d)," seasons=",nlevels(d$season),"\n",sep="")
for (h in 1:2) {
  cat("\nH",h," top AIC\n",sep="")
  z <- mr[mr$horizon==h,]
  print(head(z[order(z$AIC),],12),row.names=FALSE)
  cat("\nH",h," top LRT\n",sep="")
  q <- lr[lr$horizon==h,]
  print(head(q[order(q$p_value),],15),row.names=FALSE)
}
