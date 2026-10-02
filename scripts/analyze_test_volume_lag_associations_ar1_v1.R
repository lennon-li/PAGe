#!/usr/bin/env Rscript
suppressPackageStartupMessages(library(glmmTMB))
out_dir <- "artifacts/test-volume-lag-association-v2"
d <- read.csv(file.path(out_dir,"common_ledger.csv"),stringsAsFactors=FALSE)
d$season <- factor(d$season); d$origin_f <- factor(d$origin_week)
specs <- list(
  OFF=character(), DL2=c("d1","d2"), EXP050="exp050", ACCEL22="accel22",
  REL8="rel8", EXP050_X_G1=c("exp050","exp050:growth1"), DL4=c("d1","d2","d3","d4")
)
mkf <- function(tt) as.formula(paste(
  "cbind(y_target,N_target-y_target) ~",
  paste(c("growth1","growth2",tt,"offset(logit_current)","(1|season)","ar1(origin_f+0|season)"),collapse=" + ")
))
fits<-list(); cr<-list(); mr<-list(); lr<-list()
for(h in 1:2){
 z<-d[d$horizon==h,]
 for(nm in names(specs)){
  f<-suppressWarnings(glmmTMB(mkf(specs[[nm]]),data=z,family=betabinomial(link="logit"),control=glmmTMBControl(optCtrl=list(iter.max=700,eval.max=700))))
  fits[[paste(h,nm,sep="__")]]<-f
  sm<-summary(f)$coefficients$cond
  cr[[length(cr)+1L]]<-data.frame(horizon=h,spec=nm,term=rownames(sm),estimate=sm[,"Estimate"],se=sm[,"Std. Error"],z=sm[,"z value"],p_value=sm[,"Pr(>|z|)"],or_per_0.1=exp(.1*sm[,"Estimate"]),row.names=NULL)
  mr[[length(mr)+1L]]<-data.frame(horizon=h,spec=nm,AIC=AIC(f),logLik=as.numeric(logLik(f)),df=attr(logLik(f),"df"),converged=isTRUE(f$sdr$pdHess))
 }
 b<-fits[[paste(h,"OFF",sep="__")]]
 for(nm in setdiff(names(specs),"OFF")){
  a<-fits[[paste(h,nm,sep="__")]]; lrv<-2*(as.numeric(logLik(a))-as.numeric(logLik(b))); ddf<-attr(logLik(a),"df")-attr(logLik(b),"df")
  lr[[length(lr)+1L]]<-data.frame(horizon=h,spec=nm,df_added=ddf,LR=lrv,p_value=pchisq(lrv,ddf,lower.tail=FALSE),delta_AIC=AIC(a)-AIC(b))
 }
}
cr<-do.call(rbind,cr); mr<-do.call(rbind,mr); lr<-do.call(rbind,lr)
write.csv(cr,file.path(out_dir,"ar1_coefficients.csv"),row.names=FALSE)
write.csv(mr,file.path(out_dir,"ar1_fit_metrics.csv"),row.names=FALSE)
write.csv(lr,file.path(out_dir,"ar1_lrt_vs_off.csv"),row.names=FALSE)
print(mr[order(mr$horizon,mr$AIC),],row.names=FALSE)
print(lr[order(lr$horizon,lr$p_value),],row.names=FALSE)
