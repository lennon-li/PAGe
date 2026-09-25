d <- readRDS('artifacts/expert-ignition-annotation-v2-pass1/campaign_data.rds')
shape <- read.csv('artifacts/m1-peak-aligned-shape-v1/peak_aligned_smoothed_grid.csv', stringsAsFactors=FALSE)
peaks <- read.csv('artifacts/expert-ignition-annotation-v2-pass1/retrospective_peak_truth_v1.csv', stringsAsFactors=FALSE)
m0cmp <- read.csv('artifacts/m0-v2-decimal-loso-baseline-r2/compare.csv', stringsAsFactors=FALSE)
Amap <- setNames(m0cmp$iWeek_hatF, m0cmp$season)
Tmap <- setNames(peaks$peak_week_decimal, peaks$season)
seasons <- intersect(names(Amap),names(Tmap))

step <- .05
tau_grid <- seq(-14,1,by=step)
logit <- function(p) qlogis(pmin(pmax(p,1e-5),1-1e-5))
M <- matrix(NA_real_,nrow=length(tau_grid),ncol=length(seasons),dimnames=list(NULL,seasons))
for(j in seq_along(seasons)){
  z <- shape[shape$season==seasons[j],]
  M[,j] <- approx(z$tau,logit(z$p_smooth),xout=tau_grid,rule=1)$y
}
row_logmeanexp <- function(X){
  m <- apply(X,1,max)
  m + log(rowMeans(exp(X-m)))
}
mixture_scores <- function(obs,cands,holdout,eta_floor=.30){
  keep <- seasons!=holdout
  S <- matrix(0,nrow=length(cands),ncol=sum(keep))
  valid <- rep(TRUE,length(cands))
  for(i in seq_len(nrow(obs))){
    tau <- obs$weekF[i]-cands
    idx <- round((tau-min(tau_grid))/step)+1L
    ok <- idx>=1L & idx<=nrow(M)
    valid <- valid & ok
    idx2 <- pmin(pmax(idx,1L),nrow(M))
    MU <- M[idx2,keep,drop=FALSE]
    yy <- obs$y[i]; NN <- obs$N[i]
    eo <- log((yy+.5)/(NN-yy+.5))
    v <- eta_floor^2 + 1/(yy+.5) + 1/(NN-yy+.5)
    S <- S + (eo-MU)^2/v + log(v)
  }
  out <- rep(NA_real_,length(cands))
  out[valid] <- -2*row_logmeanexp(-.5*S[valid,,drop=FALSE])
  out
}
res<-list()
for(win in 2:4){
  for(s in seasons){
    dd<-d[d$season==s,];dd<-dd[order(dd$weekF),]
    A<-Amap[[s]];Ttrue<-Tmap[[s]]
    for(o in seq(ceiling(A),floor(Ttrue),by=1)){
      obs<-tail(dd[dd$weekF<=o,],win)
      cands<-seq(max(o+.25,A+3),min(o+14,40),by=step)
      scores<-mixture_scores(obs,cands,s)
      if(all(!is.finite(scores))) next
      pred<-cands[which.min(scores)]
      res[[length(res)+1]]<-data.frame(window=win,season=s,A=A,origin=o,true_peak=Ttrue,lead=Ttrue-o,pred=pred,err=pred-Ttrue,abs_err=abs(pred-Ttrue))
    }
  }
}
out<-do.call(rbind,res)
dir.create('artifacts/m1-v2-prototype-template-mixture-fast-v6',recursive=TRUE,showWarnings=FALSE)
write.csv(out,'artifacts/m1-v2-prototype-template-mixture-fast-v6/per_origin.csv',row.names=FALSE)
sum<-aggregate(abs_err~window,out,mean)
sum$median<-vapply(sum$window,function(w)median(out$abs_err[out$window==w]),numeric(1))
sum$rmse<-vapply(sum$window,function(w)sqrt(mean(out$err[out$window==w]^2)),numeric(1))
sum<-sum[order(sum$abs_err),]
write.csv(sum,'artifacts/m1-v2-prototype-template-mixture-fast-v6/summary.csv',row.names=FALSE)
print(sum,digits=4,row.names=FALSE)
bw<-sum$window[1];z<-out[out$window==bw,];z$bin<-cut(z$lead,c(-Inf,2,4,6,Inf),labels=c('0-2','2-4','4-6','6+'))
cat('\nBEST WINDOW',bw,'\n');print(aggregate(abs_err~bin,z,mean),digits=4,row.names=FALSE);print(aggregate(abs_err~season,z,mean),digits=4,row.names=FALSE)
