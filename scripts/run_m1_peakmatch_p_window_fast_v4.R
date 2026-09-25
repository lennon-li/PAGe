d <- readRDS('artifacts/expert-ignition-annotation-v2-pass1/campaign_data.rds')
shape <- read.csv('artifacts/m1-peak-aligned-shape-v1/peak_aligned_smoothed_grid.csv', stringsAsFactors=FALSE)
peaks <- read.csv('artifacts/expert-ignition-annotation-v2-pass1/retrospective_peak_truth_v1.csv', stringsAsFactors=FALSE)
m0cmp <- read.csv('artifacts/m0-v2-decimal-loso-baseline-r2/compare.csv', stringsAsFactors=FALSE)
Amap <- setNames(m0cmp$iWeek_hatF, m0cmp$season)
Tmap <- setNames(peaks$peak_week_decimal, peaks$season)
seasons <- intersect(names(Amap), names(Tmap))
tau_grid <- seq(-14,1,by=.05)
P <- matrix(NA_real_,nrow=length(tau_grid),ncol=length(seasons),dimnames=list(NULL,seasons))
for(j in seq_along(seasons)){z<-shape[shape$season==seasons[j],];P[,j]<-approx(z$tau,z$p_smooth,xout=tau_grid,rule=1)$y}
canon_for <- function(s){keep<-seasons!=s; data.frame(tau=tau_grid, med=apply(P[,keep,drop=FALSE],1,median,na.rm=TRUE), sd=pmax(apply(P[,keep,drop=FALSE],1,mad,constant=1.4826,na.rm=TRUE),.01))}
score_candidates <- function(obs,cands,canon){
  tau <- outer(obs$weekF,cands,'-')
  muv <- approx(canon$tau,canon$med,xout=as.vector(tau),rule=1)$y
  sdv <- approx(canon$tau,canon$sd,xout=as.vector(tau),rule=1)$y
  mu <- matrix(muv,nrow=nrow(obs),ncol=length(cands)); sd <- matrix(sdv,nrow=nrow(obs),ncol=length(cands))
  yy <- matrix(obs$p,nrow=nrow(obs),ncol=length(cands))
  val <- ((yy-mu)/sd)^2 + 2*log(sd)
  apply(val,2,function(v) if(all(!is.finite(v))) NA_real_ else mean(v[is.finite(v)]))
}
res <- list()
for(win in c(1,2,3,4,5,6,8)) for(s in seasons){
  dd<-d[d$season==s,];dd<-dd[order(dd$weekF),];A<-Amap[[s]];Ttrue<-Tmap[[s]];canon<-canon_for(s)
  for(o in seq(ceiling(A),floor(Ttrue),1)){
    obs<-dd[dd$weekF<=o & dd$weekF>=o-win,]
    cands<-seq(max(o+.25,A+3),min(o+14,40),by=.05)
    scores<-score_candidates(obs,cands,canon)
    if(all(!is.finite(scores)))next
    pred<-cands[which.min(scores)]
    res[[length(res)+1]]<-data.frame(window=win,season=s,origin=o,true_peak=Ttrue,lead=Ttrue-o,pred=pred,err=pred-Ttrue,abs_err=abs(pred-Ttrue))
  }
}
out<-do.call(rbind,res)
dir.create('artifacts/m1-v2-prototype-p-window-v4',recursive=TRUE,showWarnings=FALSE)
write.csv(out,'artifacts/m1-v2-prototype-p-window-v4/per_origin.csv',row.names=FALSE)
sum<-aggregate(abs_err~window,out,mean);sum$median<-vapply(sum$window,function(w)median(out$abs_err[out$window==w]),numeric(1));sum$rmse<-vapply(sum$window,function(w)sqrt(mean(out$err[out$window==w]^2)),numeric(1));sum<-sum[order(sum$abs_err),];write.csv(sum,'artifacts/m1-v2-prototype-p-window-v4/summary.csv',row.names=FALSE);print(sum,row.names=FALSE,digits=4)
b<-sum$window[1];z<-out[out$window==b,];z$bin<-cut(z$lead,c(-Inf,2,4,6,Inf),labels=c('0-2','2-4','4-6','6+'));cat('\nBEST WINDOW',b,'\n');print(aggregate(abs_err~bin,z,mean),row.names=FALSE,digits=4);cat('\nBY SEASON\n');print(aggregate(abs_err~season,z,mean),row.names=FALSE,digits=4)
