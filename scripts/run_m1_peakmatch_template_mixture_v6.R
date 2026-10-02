d <- readRDS('artifacts/expert-ignition-annotation-v2-pass1/campaign_data.rds')
shape <- read.csv('artifacts/m1-peak-aligned-shape-v1/peak_aligned_smoothed_grid.csv', stringsAsFactors=FALSE)
peaks <- read.csv('artifacts/expert-ignition-annotation-v2-pass1/retrospective_peak_truth_v1.csv', stringsAsFactors=FALSE)
m0cmp <- read.csv('artifacts/m0-v2-decimal-loso-baseline-r2/compare.csv', stringsAsFactors=FALSE)
Amap <- setNames(m0cmp$iWeek_hatF, m0cmp$season)
Tmap <- setNames(peaks$peak_week_decimal, peaks$season)
seasons <- intersect(names(Amap),names(Tmap))
logit <- function(p) qlogis(pmin(pmax(p,1e-5),1-1e-5))
shape$eta <- logit(shape$p_smooth)

template_score <- function(obs,Tcan,z,eta_floor=.30){
  sc<-0; n<-0
  for(i in seq_len(nrow(obs))){
    tau<-obs$weekF[i]-Tcan
    if(tau<min(z$tau)||tau>max(z$tau))next
    mu<-approx(z$tau,z$eta,xout=tau)$y
    yy<-obs$y[i]; NN<-obs$N[i]
    eta_obs<-log((yy+.5)/(NN-yy+.5))
    samp_var<-1/(yy+.5)+1/(NN-yy+.5)
    v<-eta_floor^2+samp_var
    sc<-sc+(eta_obs-mu)^2/v+log(v);n<-n+1
  }
  if(n==0)NA_real_ else sc
}
logmeanexp <- function(v){m<-max(v);m+log(mean(exp(v-m)))}
score_candidate <- function(obs,Tcan,holdout,mode=c('mixture','best')){
  mode<-match.arg(mode)
  tr<-setdiff(seasons,holdout)
  ss<-vapply(tr,function(s)template_score(obs,Tcan,shape[shape$season==s,]),numeric(1))
  ss<-ss[is.finite(ss)]
  if(!length(ss))return(NA_real_)
  if(mode=='best') return(min(ss))
  -2*logmeanexp(-.5*ss)
}
res<-list()
for(mode in 'mixture') for(win in 2L) for(s in seasons){
  dd<-d[d$season==s,];dd<-dd[order(dd$weekF),]
  A<-Amap[[s]];Ttrue<-Tmap[[s]]
  for(o in seq(ceiling(A),floor(Ttrue),by=1)){
    avail<-dd[dd$weekF<=o,];obs<-tail(avail,win)
    cands<-seq(max(o+.25,A+3),min(o+14,40),by=.1)
    scores<-vapply(cands,function(tc)score_candidate(obs,tc,s,mode),numeric(1))
    if(all(!is.finite(scores)))next
    That<-cands[which.min(scores)]
    res[[length(res)+1]]<-data.frame(mode=mode,window=win,season=s,A=A,origin=o,true_peak=Ttrue,lead=Ttrue-o,pred=That,err=That-Ttrue,abs_err=abs(That-Ttrue))
  }
}
out<-do.call(rbind,res)
dir.create('artifacts/m1-v2-prototype-template-mixture-v6',recursive=TRUE,showWarnings=FALSE)
write.csv(out,'artifacts/m1-v2-prototype-template-mixture-v6/per_origin.csv',row.names=FALSE)
sum<-aggregate(abs_err~mode+window,out,mean)
sum$median<-mapply(function(m,w)median(out$abs_err[out$mode==m&out$window==w]),sum$mode,sum$window)
sum$rmse<-mapply(function(m,w)sqrt(mean(out$err[out$mode==m&out$window==w]^2)),sum$mode,sum$window)
sum<-sum[order(sum$abs_err),]
write.csv(sum,'artifacts/m1-v2-prototype-template-mixture-v6/summary.csv',row.names=FALSE)
print(sum,row.names=FALSE,digits=4)
b<-sum[1,];z<-out[out$mode==b$mode&out$window==b$window,];z$bin<-cut(z$lead,c(-Inf,2,4,6,Inf),labels=c('0-2','2-4','4-6','6+'))
cat('\nBEST',b$mode,'window',b$window,'\n');print(aggregate(abs_err~bin,z,mean),row.names=FALSE,digits=4);print(aggregate(abs_err~season,z,mean),row.names=FALSE,digits=4)
