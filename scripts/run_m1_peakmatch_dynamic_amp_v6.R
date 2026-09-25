d <- readRDS('artifacts/expert-ignition-annotation-v2-pass1/campaign_data.rds')
shape <- read.csv('artifacts/m1-peak-aligned-shape-v1/peak_aligned_smoothed_grid.csv', stringsAsFactors=FALSE)
peaks <- read.csv('artifacts/expert-ignition-annotation-v2-pass1/retrospective_peak_truth_v1.csv', stringsAsFactors=FALSE)
m0cmp <- read.csv('artifacts/m0-v2-decimal-loso-baseline-r2/compare.csv', stringsAsFactors=FALSE)
Amap <- setNames(m0cmp$iWeek_hatF,m0cmp$season); Tmap <- setNames(peaks$peak_week_decimal,peaks$season)
seasons <- intersect(names(Amap),names(Tmap))
peak_height <- tapply(shape$p_smooth,shape$season,max,na.rm=TRUE)
shape$p_norm <- shape$p_smooth/peak_height[shape$season]
tau_grid <- seq(-14,1,by=.05)
P <- matrix(NA_real_,length(tau_grid),length(seasons),dimnames=list(NULL,seasons))
for(j in seq_along(seasons)){z<-shape[shape$season==seasons[j],];P[,j]<-approx(z$tau,z$p_norm,xout=tau_grid,rule=1)$y}
canon_for <- function(s){keep<-seasons!=s; bh<-peak_height[seasons[keep]]; data.frame(tau=tau_grid,med=apply(P[,keep,drop=FALSE],1,median,na.rm=TRUE),sd=pmax(apply(P[,keep,drop=FALSE],1,mad,constant=1.4826,na.rm=TRUE),.05),mu_logb=mean(log(bh)),sd_logb=max(sd(log(bh)),.20))}

score_tc <- function(obs,Tcan,canon,prior_weight){
  tau<-obs$weekF-Tcan
  if(any(tau<min(canon$tau)|tau>max(canon$tau))) return(c(score=NA_real_,b=NA_real_))
  f<-approx(canon$tau,canon$med,xout=tau)$y; fsd<-approx(canon$tau,canon$sd,xout=tau)$y
  # Dense but bounded peak-amplitude grid; no future held-out information.
  bgrid<-seq(.10,.40,by=.01)
  scores<-vapply(bgrid,function(b){mu<-pmin(pmax(b*f,1e-5),.999); shape_var<-(b*fsd)^2; sample_var<-mu*(1-mu)/pmax(obs$N,1); vv<-pmax(shape_var+sample_var,1e-6); ll<-sum((obs$p-mu)^2/vv+log(vv)); prior<-((log(b)-canon$mu_logb[1])/canon$sd_logb[1])^2; ll+prior_weight*prior},numeric(1))
  j<-which.min(scores);c(score=scores[j],b=bgrid[j])
}
schedules <- c('const8','fast_decay','slow_decay','reciprocal')
res <- list()
for(schedule in schedules) for(s in seasons){
  dd<-d[d$season==s,]; dd<-dd[order(dd$weekF),]; A<-Amap[[s]]; Ttrue<-Tmap[[s]]; canon<-canon_for(s)
  for(o in seq(ceiling(A),floor(Ttrue),1)){
    elapsed <- o-ceiling(A)
    pw <- switch(schedule,
      const8=8,
      fast_decay=max(1,8*exp(-elapsed/3)),
      slow_decay=max(1,8*exp(-elapsed/6)),
      reciprocal=max(1,8/(1+elapsed/3)))
    obs<-dd[dd$weekF<=o & dd$weekF>=o-1,]
    cands<-seq(max(o+.25,A+3),min(o+14,40),by=.1)
    sm<-vapply(cands,function(tc)score_tc(obs,tc,canon,pw),numeric(2)); scores<-sm['score',]
    if(all(!is.finite(scores)))next
    j<-which.min(scores); pred<-cands[j]
    res[[length(res)+1]]<-data.frame(schedule=schedule,prior_weight=pw,season=s,origin=o,true_peak=Ttrue,lead=Ttrue-o,pred=pred,bhat=sm['b',j],err=pred-Ttrue,abs_err=abs(pred-Ttrue))
  }
}
out<-do.call(rbind,res)
dir.create('artifacts/m1-v2-prototype-dynamic-amp-v6',recursive=TRUE,showWarnings=FALSE)
write.csv(out,'artifacts/m1-v2-prototype-dynamic-amp-v6/per_origin.csv',row.names=FALSE)
su<-aggregate(abs_err~schedule,out,mean)
su$median<-vapply(su$schedule,function(w)median(out$abs_err[out$schedule==w]),numeric(1))
su$rmse<-vapply(su$schedule,function(w)sqrt(mean(out$err[out$schedule==w]^2)),numeric(1))
su<-su[order(su$abs_err),]
write.csv(su,'artifacts/m1-v2-prototype-dynamic-amp-v6/summary.csv',row.names=FALSE)
print(su,row.names=FALSE,digits=4)
bw<-su$schedule[1]; z<-out[out$schedule==bw,]; z$bin<-cut(z$lead,c(-Inf,2,4,6,Inf),labels=c('0-2','2-4','4-6','6+'))
cat('\nBEST',bw,'\n');print(aggregate(abs_err~bin,z,mean),row.names=FALSE,digits=4);cat('\nBY SEASON\n');print(aggregate(abs_err~season,z,mean),row.names=FALSE,digits=4)
