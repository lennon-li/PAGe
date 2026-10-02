d <- readRDS('artifacts/expert-ignition-annotation-v2-pass1/campaign_data.rds')
shape <- read.csv('artifacts/m1-peak-aligned-shape-v1/peak_aligned_smoothed_grid.csv', stringsAsFactors=FALSE)
peaks <- read.csv('artifacts/expert-ignition-annotation-v2-pass1/retrospective_peak_truth_v1.csv', stringsAsFactors=FALSE)
m0cmp <- read.csv('artifacts/m0-v2-decimal-loso-baseline-r2/compare.csv', stringsAsFactors=FALSE)
Amap <- setNames(m0cmp$iWeek_hatF,m0cmp$season)
Tmap <- setNames(peaks$peak_week_decimal,peaks$season)
seasons <- intersect(names(Amap),names(Tmap))

peak_height <- tapply(shape$p_smooth,shape$season,max,na.rm=TRUE)
shape$p_norm <- shape$p_smooth/peak_height[shape$season]
tau_grid <- seq(-14,0,by=.1)
M <- matrix(NA_real_,nrow=length(seasons),ncol=length(tau_grid),dimnames=list(seasons,NULL))
for(i in seq_along(seasons)){
  z <- shape[shape$season==seasons[i],]
  M[i,] <- approx(z$tau,z$p_norm,xout=tau_grid,rule=1)$y
}

library_for <- function(holdout){
  keep <- seasons != holdout
  X <- M[keep,,drop=FALSE]
  # Training-only one-PC peak-aligned shape model.
  pc <- prcomp(X,center=TRUE,scale.=FALSE)
  mean_curve <- pc$center
  loading <- pc$rotation[,1]
  scores <- pc$x[,1]
  recon <- sweep(outer(scores,loading),2,mean_curve,'+')
  resid <- X-recon
  resid_sd <- pmax(apply(resid,2,sd),.025)
  bh <- peak_height[seasons[keep]]
  list(tau=tau_grid,mean=mean_curve,pc1=loading,resid_sd=resid_sd,
       sd_c=max(sd(scores),.2),mu_logb=mean(log(bh)),sd_logb=max(sd(log(bh)),.2),
       pc1_var=pc$sdev[1]^2/sum(pc$sdev^2))
}

# Return log marginal evidence for one candidate T after integrating b and c.
log_evidence_T <- function(obs,Tcan,lib,bgrid,cgrid){
  tau <- obs$weekF-Tcan
  if(any(tau<min(lib$tau)|tau>max(lib$tau))) return(-Inf)
  f0 <- approx(lib$tau,lib$mean,xout=tau)$y
  pcv <- approx(lib$tau,lib$pc1,xout=tau)$y
  rsd <- approx(lib$tau,lib$resid_sd,xout=tau)$y
  bc <- expand.grid(b=bgrid,c=cgrid)
  F <- matrix(f0,nrow=nrow(bc),ncol=length(f0),byrow=TRUE) + outer(bc$c,pcv)
  F <- pmin(pmax(F,.001),1.30)
  MU <- F * bc$b
  VV <- (outer(bc$b,rsd))^2 + MU*(1-MU)/matrix(pmax(obs$N,1),nrow=nrow(bc),ncol=nrow(obs),byrow=TRUE)
  VV <- pmax(VV,1e-6)
  YY <- matrix(obs$p,nrow=nrow(bc),ncol=nrow(obs),byrow=TRUE)
  data_nll2 <- rowSums((YY-MU)^2/VV + log(VV))
  prior_b <- ((log(bc$b)-lib$mu_logb)/lib$sd_logb)^2 + 2*log(bc$b)
  prior_c <- (bc$c/lib$sd_c)^2
  S <- data_nll2 + prior_b + prior_c
  m <- min(S)
  -.5*m + log(sum(exp(-.5*(S-m))))
}

bgrid <- seq(.08,.44,by=.02)
res <- list()
for(s in seasons){
  dd <- d[d$season==s,]; dd <- dd[order(dd$weekF),]
  A <- Amap[[s]]; Ttrue <- Tmap[[s]]; lib <- library_for(s)
  cgrid <- seq(-2.5*lib$sd_c,2.5*lib$sd_c,length.out=17)
  for(o in seq(ceiling(A),floor(Ttrue),1)){
    obs <- dd[dd$weekF>=ceiling(A) & dd$weekF<=o,]
    cands <- seq(max(o+.05,A+3),min(o+14,40),by=.1)
    le <- vapply(cands,function(tc)log_evidence_T(obs,tc,lib,bgrid,cgrid),numeric(1))
    ok <- is.finite(le)
    if(!any(ok)) next
    le[!ok] <- -Inf
    ww <- exp(le-max(le)); ww <- ww/sum(ww)
    mapT <- cands[which.max(ww)]
    meanT <- sum(cands*ww)
    cdf <- cumsum(ww)
    medianT <- cands[which(cdf>=.5)[1]]
    q05 <- cands[which(cdf>=.05)[1]]; q95 <- cands[which(cdf>=.95)[1]]
    res[[length(res)+1]] <- data.frame(
      season=s,A=A,origin=o,n_obs=nrow(obs),true_peak=Ttrue,lead=Ttrue-o,pc1_train_var=lib$pc1_var,
      map_peak=mapT,mean_peak=meanT,median_peak=medianT,q05=q05,q95=q95,width90=q95-q05,
      covered90=Ttrue>=q05 & Ttrue<=q95,
      err_map=mapT-Ttrue,abs_err_map=abs(mapT-Ttrue),
      err_mean=meanT-Ttrue,abs_err_mean=abs(meanT-Ttrue),
      err_median=medianT-Ttrue,abs_err_median=abs(medianT-Ttrue))
  }
}
out <- do.call(rbind,res)
dir.create('artifacts/m1-v2-lowrank-posterior-v8',recursive=TRUE,showWarnings=FALSE)
write.csv(out,'artifacts/m1-v2-lowrank-posterior-v8/per_origin.csv',row.names=FALSE)
metrics <- data.frame(estimator=c('MAP','mean','median'),MAE=c(mean(out$abs_err_map),mean(out$abs_err_mean),mean(out$abs_err_median)),RMSE=c(sqrt(mean(out$err_map^2)),sqrt(mean(out$err_mean^2)),sqrt(mean(out$err_median^2))))
write.csv(metrics,'artifacts/m1-v2-lowrank-posterior-v8/metrics.csv',row.names=FALSE)
cat('POINT METRICS\n');print(metrics,row.names=FALSE,digits=4)
cat('\nPC1 TRAIN VAR\n');print(summary(out$pc1_train_var))
cat('\nUNCERTAINTY\n');cat('coverage90=',mean(out$covered90),' median_width=',median(out$width90),' mean_width=',mean(out$width90),'\n',sep='')
out$bin<-cut(out$lead,c(-Inf,2,4,6,Inf),labels=c('0-2','2-4','4-6','6+'))
cat('\nMAP BY LEAD\n');print(aggregate(abs_err_map~bin,out,mean),row.names=FALSE,digits=4)
cat('\nCOVERAGE BY LEAD\n');print(aggregate(cbind(covered90,width90)~bin,out,mean),row.names=FALSE,digits=4)
cat('\nMAP BY SEASON\n');print(aggregate(abs_err_map~season,out,mean),row.names=FALSE,digits=4)
