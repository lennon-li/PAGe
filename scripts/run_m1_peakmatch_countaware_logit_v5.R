d <- readRDS('artifacts/expert-ignition-annotation-v2-pass1/campaign_data.rds')
shape <- read.csv('artifacts/m1-peak-aligned-shape-v1/peak_aligned_smoothed_grid.csv', stringsAsFactors=FALSE)
peaks <- read.csv('artifacts/expert-ignition-annotation-v2-pass1/retrospective_peak_truth_v1.csv', stringsAsFactors=FALSE)
m0cmp <- read.csv('artifacts/m0-v2-decimal-loso-baseline-r2/compare.csv', stringsAsFactors=FALSE)
Amap <- setNames(m0cmp$iWeek_hatF, m0cmp$season)
Tmap <- setNames(peaks$peak_week_decimal, peaks$season)
seasons <- intersect(names(Amap), names(Tmap))

logit <- function(p) qlogis(pmin(pmax(p,1e-5),1-1e-5))
shape$eta <- logit(shape$p_smooth)
tau_grid <- seq(-14,1,by=.1)
M <- matrix(NA_real_,nrow=length(tau_grid),ncol=length(seasons),dimnames=list(NULL,seasons))
for(j in seq_along(seasons)){
  z <- shape[shape$season==seasons[j],]
  M[,j] <- approx(z$tau,z$eta,xout=tau_grid,rule=1)$y
}
canon_for <- function(holdout){
  keep <- seasons != holdout
  med <- apply(M[,keep,drop=FALSE],1,median,na.rm=TRUE)
  sd <- apply(M[,keep,drop=FALSE],1,mad,constant=1.4826,na.rm=TRUE)
  data.frame(tau=tau_grid,eta_med=med,eta_sd=pmax(sd,.20))
}
score_candidate <- function(obs,Tcan,canon){
  sc <- 0; n <- 0
  for(i in seq_len(nrow(obs))){
    tau <- obs$weekF[i]-Tcan
    if(tau < -14 || tau > 1) next
    mu <- approx(canon$tau,canon$eta_med,xout=tau)$y
    between_sd <- approx(canon$tau,canon$eta_sd,xout=tau)$y
    # empirical-logit observation with Jeffreys correction; approximate sampling var
    yy <- obs$y[i]; NN <- obs$N[i]
    eta_obs <- log((yy+.5)/(NN-yy+.5))
    samp_var <- 1/(yy+.5) + 1/(NN-yy+.5)
    v <- between_sd^2 + samp_var
    sc <- sc + (eta_obs-mu)^2/v + log(v)
    n <- n+1
  }
  if(n==0) NA_real_ else sc/n
}
windows <- 1:6
res <- list()
for(win in windows){
  for(s in seasons){
    dd<-d[d$season==s,]; dd<-dd[order(dd$weekF),]
    A<-Amap[[s]]; Ttrue<-Tmap[[s]]; canon<-canon_for(s)
    origins<-seq(ceiling(A),floor(Ttrue),by=1)
    for(o in origins){
      avail<-dd[dd$weekF<=o,]
      obs<-tail(avail,win)
      cands<-seq(max(o+.25,A+3),min(o+14,40),by=.1)
      scores<-vapply(cands,function(tc)score_candidate(obs,tc,canon),numeric(1))
      if(all(!is.finite(scores))) next
      That<-cands[which.min(scores)]
      res[[length(res)+1]]<-data.frame(window=win,season=s,A=A,origin=o,true_peak=Ttrue,lead=Ttrue-o,pred=That,err=That-Ttrue,abs_err=abs(That-Ttrue))
    }
  }
}
out<-do.call(rbind,res)
dir.create('artifacts/m1-v2-prototype-countaware-logit-v5',recursive=TRUE,showWarnings=FALSE)
write.csv(out,'artifacts/m1-v2-prototype-countaware-logit-v5/per_origin.csv',row.names=FALSE)
sum<-aggregate(abs_err~window,out,mean)
sum$median<-vapply(sum$window,function(w)median(out$abs_err[out$window==w]),numeric(1))
sum$rmse<-vapply(sum$window,function(w)sqrt(mean(out$err[out$window==w]^2)),numeric(1))
sum<-sum[order(sum$abs_err),]
write.csv(sum,'artifacts/m1-v2-prototype-countaware-logit-v5/summary.csv',row.names=FALSE)
print(sum,row.names=FALSE,digits=4)
bw<-sum$window[1]; z<-out[out$window==bw,]; z$bin<-cut(z$lead,c(-Inf,2,4,6,Inf),labels=c('0-2','2-4','4-6','6+'))
cat('\nBEST WINDOW',bw,'\n'); print(aggregate(abs_err~bin,z,mean),row.names=FALSE,digits=4); print(aggregate(abs_err~season,z,mean),row.names=FALSE,digits=4)
