d <- readRDS('artifacts/expert-ignition-annotation-v2-pass1/campaign_data.rds')
shape <- read.csv('artifacts/m1-peak-aligned-shape-v1/peak_aligned_smoothed_grid.csv', stringsAsFactors=FALSE)
peaks <- read.csv('artifacts/expert-ignition-annotation-v2-pass1/retrospective_peak_truth_v1.csv', stringsAsFactors=FALSE)
m0cmp <- read.csv('artifacts/m0-v2-decimal-loso-baseline-r2/compare.csv', stringsAsFactors=FALSE)
Amap <- setNames(m0cmp$iWeek_hatF, m0cmp$season)
Tmap <- setNames(peaks$peak_week_decimal, peaks$season)
seasons <- intersect(names(Amap), names(Tmap))

tau_grid <- seq(-14, 1, by=.1)
# Candidate-phase library uses scale-free quantities relative to instantaneous smooth positivity.
shape$r1 <- NA_real_; shape$r2 <- NA_real_; shape$r3 <- NA_real_
for(s in unique(shape$season)) {
  ii <- which(shape$season==s)
  z <- shape[ii,]
  pnow <- pmax(z$p_smooth,1e-4)
  shape$r1[ii] <- z$auc1/pnow
  shape$r2[ii] <- z$auc2/pnow
  shape$r3[ii] <- z$auc3/pnow
}
features <- c('r1','r2','r3')
mats <- lapply(features,function(f){
  m <- matrix(NA_real_,nrow=length(tau_grid),ncol=length(seasons),dimnames=list(NULL,seasons))
  for(j in seq_along(seasons)){
    z <- shape[shape$season==seasons[j],]
    m[,j] <- approx(z$tau,z[[f]],xout=tau_grid,rule=1)$y
  }
  m
}); names(mats)<-features
canon_for <- function(holdout){
  keep <- seasons!=holdout
  med <- function(m) apply(m[,keep,drop=FALSE],1,median,na.rm=TRUE)
  rsd <- function(m) apply(m[,keep,drop=FALSE],1,mad,constant=1.4826,na.rm=TRUE)
  data.frame(tau=tau_grid,
             r1_med=med(mats$r1),r1_sd=pmax(rsd(mats$r1),.08),
             r2_med=med(mats$r2),r2_sd=pmax(rsd(mats$r2),.15),
             r3_med=med(mats$r3),r3_sd=pmax(rsd(mats$r3),.20))
}
interp <- function(x,y,t) approx(x,y,xout=t,rule=2)$y
trapz <- function(x,y) if(length(x)<2) 0 else sum(diff(x)*(head(y,-1)+tail(y,-1))/2)
local_auc <- function(dd,t,w){
  lo <- t-w; if(lo<min(dd$weekF)) return(NA_real_)
  xs <- sort(unique(c(dd$weekF[dd$weekF>=lo & dd$weekF<=t],lo,t)))
  trapz(xs,interp(dd$weekF,dd$p,xs))
}
score_candidate <- function(obs,Tcan,canon){
  # Use only the current origin row's local shape ratios; avoids repeatedly counting overlapping windows.
  z <- obs[nrow(obs),]
  tau <- z$weekF-Tcan
  if(tau < -14 || tau > 1 || !is.finite(z$p) || z$p<=0) return(NA_real_)
  vals <- c(z$a1/z$p,z$a2/z$p,z$a3/z$p)
  meds <- c(approx(canon$tau,canon$r1_med,xout=tau)$y,
            approx(canon$tau,canon$r2_med,xout=tau)$y,
            approx(canon$tau,canon$r3_med,xout=tau)$y)
  sds <- c(approx(canon$tau,canon$r1_sd,xout=tau)$y,
           approx(canon$tau,canon$r2_sd,xout=tau)$y,
           approx(canon$tau,canon$r3_sd,xout=tau)$y)
  ok <- is.finite(vals)&is.finite(meds)&is.finite(sds)&sds>0
  if(sum(ok)<2) return(NA_real_)
  mean(((vals[ok]-meds[ok])/sds[ok])^2 + 2*log(sds[ok]))
}
res<-list()
for(s in seasons){
  dd<-d[d$season==s,]; dd<-dd[order(dd$weekF),]
  A<-Amap[[s]]; Ttrue<-Tmap[[s]]; canon<-canon_for(s)
  for(o in seq(ceiling(A),floor(Ttrue),by=1)){
    avail<-dd[dd$weekF<=o,]; obs<-tail(avail,4)
    obs$a1<-vapply(obs$weekF,function(t)local_auc(avail,t,1),numeric(1))
    obs$a2<-vapply(obs$weekF,function(t)local_auc(avail,t,2),numeric(1))
    obs$a3<-vapply(obs$weekF,function(t)local_auc(avail,t,3),numeric(1))
    cands<-seq(max(o+.25,A+3),min(o+14,40),by=.1)
    scores<-vapply(cands,function(tc)score_candidate(obs,tc,canon),numeric(1))
    if(all(!is.finite(scores))) next
    That<-cands[which.min(scores)]
    res[[length(res)+1]]<-data.frame(season=s,A=A,origin=o,true_peak=Ttrue,lead=Ttrue-o,map_peak=That,err=That-Ttrue,abs_err=abs(That-Ttrue))
  }
}
out<-do.call(rbind,res)
dir.create('artifacts/m1-v2-prototype-shape-ratio-v3',recursive=TRUE,showWarnings=FALSE)
write.csv(out,'artifacts/m1-v2-prototype-shape-ratio-v3/per_origin.csv',row.names=FALSE)
out$bin<-cut(out$lead,c(-Inf,2,4,6,Inf),labels=c('0-2','2-4','4-6','6+'))
print(c(MAE=mean(out$abs_err),RMSE=sqrt(mean(out$err^2)),median=median(out$abs_err),n=nrow(out)))
cat('\nBY LEAD\n'); print(aggregate(abs_err~bin,out,mean))
cat('\nBY SEASON\n'); print(aggregate(abs_err~season,out,mean))
