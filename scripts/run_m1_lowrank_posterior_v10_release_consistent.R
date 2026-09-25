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

pc1_admissible_bounds <- function(mean_curve,loading,sd_c,k=2.5,eps=.001){
  i0 <- length(mean_curve)
  m0 <- mean_curve[i0]; l0 <- loading[i0]
  lo <- -k*sd_c; hi <- k*sd_c
  # Enforce f(0) >= f(tau) for every tau and f(tau) >= eps.
  for(j in seq_along(mean_curve)){
    if(j==i0) next
    a <- loading[j]-l0
    b <- m0-mean_curve[j]
    if(a>1e-12) hi <- min(hi,b/a)
    if(a< -1e-12) lo <- max(lo,b/a)
    a2 <- loading[j]; b2 <- eps-mean_curve[j]
    if(a2>1e-12) lo <- max(lo,b2/a2)
    if(a2< -1e-12) hi <- min(hi,b2/a2)
  }
  c(lo=lo,hi=hi)
}

library_for <- function(holdout){
  keep <- seasons != holdout
  X <- M[keep,,drop=FALSE]
  pc <- prcomp(X,center=TRUE,scale.=FALSE)
  mean_curve <- pc$center; loading <- pc$rotation[,1]; scores<-pc$x[,1]
  recon <- sweep(outer(scores,loading),2,mean_curve,'+')
  resid <- X-recon
  bh <- peak_height[seasons[keep]]
  sd_c <- max(sd(scores),.2)
  bounds <- pc1_admissible_bounds(mean_curve,loading,sd_c)
  if(bounds['lo']>=bounds['hi']) stop('No admissible PC1 coefficient range for ',holdout)
  list(tau=tau_grid,mean=mean_curve,pc1=loading,resid_sd=pmax(apply(resid,2,sd),.025),
       sd_c=sd_c,c_lo=unname(bounds['lo']),c_hi=unname(bounds['hi']),
       mu_logb=mean(log(bh)),sd_logb=max(sd(log(bh)),.2),pc1_var=pc$sdev[1]^2/sum(pc$sdev^2))
}

log_evidence_T <- function(obs,Tcan,lib,bgrid,cgrid){
  tau <- obs$weekF-Tcan
  if(any(tau<min(lib$tau)|tau>max(lib$tau))) return(-Inf)
  f0<-approx(lib$tau,lib$mean,xout=tau)$y; pcv<-approx(lib$tau,lib$pc1,xout=tau)$y; rsd<-approx(lib$tau,lib$resid_sd,xout=tau)$y
  bc<-expand.grid(b=bgrid,c=cgrid)
  F<-matrix(f0,nrow=nrow(bc),ncol=length(f0),byrow=TRUE)+outer(bc$c,pcv)
  # Admissible c guarantees the full training-grid shape is peak-anchored; clip only numerical tails.
  F<-pmax(F,.001)
  MU<-F*bc$b
  VV<-(outer(bc$b,rsd))^2+MU*(1-MU)/matrix(pmax(obs$N,1),nrow=nrow(bc),ncol=nrow(obs),byrow=TRUE)
  VV<-pmax(VV,1e-6);YY<-matrix(obs$p,nrow=nrow(bc),ncol=nrow(obs),byrow=TRUE)
  S<-rowSums((YY-MU)^2/VV+log(VV))+((log(bc$b)-lib$mu_logb)/lib$sd_logb)^2+2*log(bc$b)+(bc$c/lib$sd_c)^2
  m<-min(S);-.5*m+log(sum(exp(-.5*(S-m))))
}

bgrid<-seq(.08,.44,by=.02);res<-list()
for(s in seasons){
  dd<-d[d$season==s,];dd<-dd[order(dd$weekF),];A<-Amap[[s]];Ttrue<-Tmap[[s]];lib<-library_for(s)
  cgrid<-seq(lib$c_lo,lib$c_hi,length.out=17)
  for(o in seq(ceiling(A),floor(Ttrue),1)){
    obs<-dd[dd$weekF>=ceiling(A)&dd$weekF<=o,]
    cands<-seq(o+1.05,min(o+15,40),by=.1)
    le<-vapply(cands,function(tc)log_evidence_T(obs,tc,lib,bgrid,cgrid),numeric(1));ok<-is.finite(le);if(!any(ok))next
    le[!ok]<- -Inf;ww<-exp(le-max(le));ww<-ww/sum(ww);cdf<-cumsum(ww)
    mapT<-cands[which.max(ww)];meanT<-sum(cands*ww);medT<-cands[which(cdf>=.5)[1]];q05<-cands[which(cdf>=.05)[1]];q95<-cands[which(cdf>=.95)[1]]
    res[[length(res)+1]]<-data.frame(season=s,A=A,origin=o,true_peak=Ttrue,lead=Ttrue-o,pc1_train_var=lib$pc1_var,c_lo=lib$c_lo,c_hi=lib$c_hi,
      map_peak=mapT,mean_peak=meanT,median_peak=medT,q05=q05,q95=q95,width90=q95-q05,covered90=Ttrue>=q05&Ttrue<=q95,
      err_map=mapT-Ttrue,abs_err_map=abs(mapT-Ttrue),err_mean=meanT-Ttrue,abs_err_mean=abs(meanT-Ttrue))
  }
}
out<-do.call(rbind,res);dir.create('artifacts/m1-v2-lowrank-posterior-v10-release-consistent',recursive=TRUE,showWarnings=FALSE);write.csv(out,'artifacts/m1-v2-lowrank-posterior-v10-release-consistent/per_origin.csv',row.names=FALSE)
strict<-out[out$true_peak>(out$origin+1),]
cat('ALL ORIGINS mean MAE=',mean(out$abs_err_mean),' MAP=',mean(out$abs_err_map),' coverage=',mean(out$covered90),'\n',sep='')
cat('STRICT FUTURE n=',nrow(strict),' mean MAE=',mean(strict$abs_err_mean),' RMSE=',sqrt(mean(strict$err_mean^2)),' MAP=',mean(strict$abs_err_map),' coverage=',mean(strict$covered90),'\n',sep='')
cat('\nPC1 BOUNDS BY SEASON\n');print(unique(out[,c('season','c_lo','c_hi','pc1_train_var')]),row.names=FALSE,digits=3)
cat('\nBY SEASON STRICT\n');print(aggregate(abs_err_mean~season,strict,mean),row.names=FALSE,digits=3)
