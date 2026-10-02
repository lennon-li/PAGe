amp_prior_weight <- as.numeric(Sys.getenv('M1_AMP_PRIOR_WEIGHT','1'))
d <- readRDS('artifacts/expert-ignition-annotation-v2-pass1/campaign_data.rds')
shape <- read.csv('artifacts/m1-peak-aligned-shape-v1/peak_aligned_smoothed_grid.csv', stringsAsFactors=FALSE)
peaks <- read.csv('artifacts/expert-ignition-annotation-v2-pass1/retrospective_peak_truth_v1.csv', stringsAsFactors=FALSE)
m0cmp <- read.csv('artifacts/m0-v2-decimal-loso-baseline-r2/compare.csv', stringsAsFactors=FALSE)
Amap <- setNames(m0cmp$iWeek_hatF, m0cmp$season)
Tmap <- setNames(peaks$peak_week_decimal, peaks$season)
seasons <- intersect(names(Amap), names(Tmap))
peak_height <- tapply(shape$p_smooth, shape$season, max, na.rm=TRUE)
shape$p_norm <- shape$p_smooth / peak_height[shape$season]
shape$auc2_norm <- shape$auc2 / peak_height[shape$season]
shape$auc3_norm <- shape$auc3 / peak_height[shape$season]

tau_grid <- seq(-14,1,by=.1)
features <- c('p_norm','auc2_norm','auc3_norm')
mats <- lapply(features,function(f){
  m<-matrix(NA_real_,nrow=length(tau_grid),ncol=length(seasons),dimnames=list(NULL,seasons))
  for(j in seq_along(seasons)){
    z<-shape[shape$season==seasons[j],]
    m[,j]<-approx(z$tau,z[[f]],xout=tau_grid,rule=1)$y
  }
  m
}); names(mats)<-features
canon_for <- function(holdout){
  keep<-seasons!=holdout
  med<-function(m)apply(m[,keep,drop=FALSE],1,median,na.rm=TRUE)
  rsd<-function(m)apply(m[,keep,drop=FALSE],1,mad,constant=1.4826,na.rm=TRUE)
  ph<-unname(peak_height[seasons[keep]])
  list(curve=data.frame(tau=tau_grid,
      p_med=med(mats$p_norm),p_sd=pmax(rsd(mats$p_norm),.05),
      a2_med=med(mats$auc2_norm),a2_sd=pmax(rsd(mats$auc2_norm),.08),
      a3_med=med(mats$auc3_norm),a3_sd=pmax(rsd(mats$auc3_norm),.12)),
    log_amp_med=median(log(ph)),
    log_amp_sd=max(mad(log(ph),constant=1.4826),.20),
    amp_low=min(ph), amp_high=max(ph))
}
interp<-function(x,y,t)approx(x,y,xout=t,rule=2)$y
trapz<-function(x,y)if(length(x)<2)0 else sum(diff(x)*(head(y,-1)+tail(y,-1))/2)
local_auc<-function(dd,t,w){lo<-t-w;if(lo<min(dd$weekF))return(NA_real_);xs<-sort(unique(c(dd$weekF[dd$weekF>=lo & dd$weekF<=t],lo,t)));trapz(xs,interp(dd$weekF,dd$p,xs))}
score_candidate<-function(obs,Tcan,canon){
  c<-canon$curve
  xs<-ys<-ws<-numeric(0)
  for(i in seq_len(nrow(obs))){
    tau<-obs$weekF[i]-Tcan
    if(tau < -14 || tau > 1) next
    pm<-approx(c$tau,c$p_med,xout=tau)$y; ps<-approx(c$tau,c$p_sd,xout=tau)$y
    xs<-c(xs,pm);ys<-c(ys,obs$p[i]);ws<-c(ws,1/(ps^2))
    if(is.finite(obs$a2[i])){am<-approx(c$tau,c$a2_med,xout=tau)$y;as<-approx(c$tau,c$a2_sd,xout=tau)$y;xs<-c(xs,am);ys<-c(ys,obs$a2[i]);ws<-c(ws,.5/(as^2))}
    if(is.finite(obs$a3[i])){am<-approx(c$tau,c$a3_med,xout=tau)$y;as<-approx(c$tau,c$a3_sd,xout=tau)$y;xs<-c(xs,am);ys<-c(ys,obs$a3[i]);ws<-c(ws,.5/(as^2))}
  }
  ok<-is.finite(xs)&is.finite(ys)&is.finite(ws)&xs>=0&ws>0
  xs<-xs[ok];ys<-ys[ok];ws<-ws[ok]
  if(length(xs)<2||sum(ws*xs^2)<=0)return(c(score=NA_real_,amp=NA_real_))
  # weighted data-optimal amplitude, clipped to plausible held-out historical range
  b<-sum(ws*xs*ys)/sum(ws*xs^2)
  b<-min(max(b,canon$amp_low),canon$amp_high)
  data_score<-0;wt<-0
  for(i in seq_len(nrow(obs))){
    tau<-obs$weekF[i]-Tcan
    if(tau < -14 || tau > 1) next
    pm<-approx(c$tau,c$p_med,xout=tau)$y;ps<-max(b*approx(c$tau,c$p_sd,xout=tau)$y,.005)
    data_score<-data_score+((obs$p[i]-b*pm)/ps)^2+2*log(ps);wt<-wt+1
    if(is.finite(obs$a2[i])){am<-approx(c$tau,c$a2_med,xout=tau)$y;as<-max(b*approx(c$tau,c$a2_sd,xout=tau)$y,.008);data_score<-data_score+.5*(((obs$a2[i]-b*am)/as)^2+2*log(as));wt<-wt+.5}
    if(is.finite(obs$a3[i])){am<-approx(c$tau,c$a3_med,xout=tau)$y;as<-max(b*approx(c$tau,c$a3_sd,xout=tau)$y,.012);data_score<-data_score+.5*(((obs$a3[i]-b*am)/as)^2+2*log(as));wt<-wt+.5}
  }
  prior_score<-((log(b)-canon$log_amp_med)/canon$log_amp_sd)^2 + 2*log(canon$log_amp_sd)
  c(score=data_score/wt + amp_prior_weight*prior_score,amp=b)
}
res<-list()
for(s in seasons){
  dd<-d[d$season==s,];dd<-dd[order(dd$weekF),]
  A<-Amap[[s]];Ttrue<-Tmap[[s]];canon<-canon_for(s)
  for(o in seq(ceiling(A),floor(Ttrue),by=1)){
    avail<-dd[dd$weekF<=o,];obs<-tail(avail,4)
    obs$a2<-vapply(obs$weekF,function(t)local_auc(avail,t,2),numeric(1))
    obs$a3<-vapply(obs$weekF,function(t)local_auc(avail,t,3),numeric(1))
    cands<-seq(max(o+.25,A+3),min(o+14,40),by=.1)
    sm<-vapply(cands,function(tc)score_candidate(obs,tc,canon),numeric(2))
    scores<-sm['score',];if(all(!is.finite(scores)))next
    j<-which.min(scores);That<-cands[j]
    res[[length(res)+1]]<-data.frame(season=s,A=A,origin=o,true_peak=Ttrue,lead=Ttrue-o,map_peak=That,amplitude_hat=sm['amp',j],err=That-Ttrue,abs_err=abs(That-Ttrue))
  }
}
out<-do.call(rbind,res)
out$bin<-cut(out$lead,c(-Inf,2,4,6,Inf),labels=c('0-2','2-4','4-6','6+'))
out_dir<-paste0('artifacts/m1-v2-prototype-amp-prior-v4-w',gsub('\\.','_',format(amp_prior_weight,trim=TRUE)))
dir.create(out_dir,recursive=TRUE,showWarnings=FALSE)
write.csv(out,file.path(out_dir,'per_origin.csv'),row.names=FALSE)
cat('weight=',amp_prior_weight,' MAE=',mean(out$abs_err),' RMSE=',sqrt(mean(out$err^2)),' median=',median(out$abs_err),' n=',nrow(out),'\n',sep='')
print(aggregate(abs_err~bin,out,mean))
