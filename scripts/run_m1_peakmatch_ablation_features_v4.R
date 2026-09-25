d <- readRDS('artifacts/expert-ignition-annotation-v2-pass1/campaign_data.rds')
shape <- read.csv('artifacts/m1-peak-aligned-shape-v1/peak_aligned_smoothed_grid.csv', stringsAsFactors=FALSE)
peaks <- read.csv('artifacts/expert-ignition-annotation-v2-pass1/retrospective_peak_truth_v1.csv', stringsAsFactors=FALSE)
m0cmp <- read.csv('artifacts/m0-v2-decimal-loso-baseline-r2/compare.csv', stringsAsFactors=FALSE)
Amap <- setNames(m0cmp$iWeek_hatF, m0cmp$season)
Tmap <- setNames(peaks$peak_week_decimal, peaks$season)
seasons <- intersect(names(Amap),names(Tmap))

tau_grid <- seq(-14,1,by=.1)
features <- c('p_smooth','auc2','auc3')
mats <- lapply(features,function(f){
  m <- matrix(NA_real_,nrow=length(tau_grid),ncol=length(seasons),dimnames=list(NULL,seasons))
  for(j in seq_along(seasons)){z<-shape[shape$season==seasons[j],];m[,j]<-approx(z$tau,z[[f]],xout=tau_grid,rule=1)$y}
  m
}); names(mats)<-features
canon_for <- function(holdout){
  keep<-seasons!=holdout; med<-function(m)apply(m[,keep,drop=FALSE],1,median,na.rm=TRUE); rsd<-function(m)apply(m[,keep,drop=FALSE],1,mad,constant=1.4826,na.rm=TRUE)
  data.frame(tau=tau_grid,p_med=med(mats$p_smooth),p_sd=pmax(rsd(mats$p_smooth),.01),a2_med=med(mats$auc2),a2_sd=pmax(rsd(mats$auc2),.015),a3_med=med(mats$auc3),a3_sd=pmax(rsd(mats$auc3),.02))
}
interp<-function(x,y,t)approx(x,y,xout=t,rule=2)$y
trapz<-function(x,y)if(length(x)<2)0 else sum(diff(x)*(head(y,-1)+tail(y,-1))/2)
local_auc<-function(dd,t,w){lo<-t-w;if(lo<min(dd$weekF))return(NA_real_);xs<-sort(unique(c(dd$weekF[dd$weekF>=lo&dd$weekF<=t],lo,t)));trapz(xs,interp(dd$weekF,dd$p,xs))}
score<-function(obs,Tcan,canon,use){sc<-0;wt<-0;for(i in seq_len(nrow(obs))){tau<-obs$weekF[i]-Tcan;if(tau< -14||tau>1)next
 if('p'%in%use){mu<-approx(canon$tau,canon$p_med,xout=tau)$y;sd<-approx(canon$tau,canon$p_sd,xout=tau)$y;sc<-sc+((obs$p[i]-mu)/sd)^2+2*log(sd);wt<-wt+1}
 if('a2'%in%use&&is.finite(obs$a2[i])){mu<-approx(canon$tau,canon$a2_med,xout=tau)$y;sd<-approx(canon$tau,canon$a2_sd,xout=tau)$y;sc<-sc+((obs$a2[i]-mu)/sd)^2+2*log(sd);wt<-wt+1}
 if('a3'%in%use&&is.finite(obs$a3[i])){mu<-approx(canon$tau,canon$a3_med,xout=tau)$y;sd<-approx(canon$tau,canon$a3_sd,xout=tau)$y;sc<-sc+((obs$a3[i]-mu)/sd)^2+2*log(sd);wt<-wt+1}}
 if(wt==0)NA_real_ else sc/wt}
configs<-list(p='p',a2='a2',a3='a3',p_a2=c('p','a2'),p_a3=c('p','a3'),a2_a3=c('a2','a3'),all=c('p','a2','a3'))
windows<-3
res<-list()
for(win in windows) for(cfg in names(configs)) for(s in seasons){dd<-d[d$season==s,];dd<-dd[order(dd$weekF),];A<-Amap[[s]];Ttrue<-Tmap[[s]];canon<-canon_for(s);origins<-seq(ceiling(A),floor(Ttrue),1);for(o in origins){avail<-dd[dd$weekF<=o,];obs<-avail[avail$weekF>=o-win,];obs$a2<-vapply(obs$weekF,function(t)local_auc(avail,t,2),numeric(1));obs$a3<-vapply(obs$weekF,function(t)local_auc(avail,t,3),numeric(1));cands<-seq(max(o+.25,A+3),min(o+14,40),by=.1);scores<-vapply(cands,function(tc)score(obs,tc,canon,configs[[cfg]]),numeric(1));if(all(!is.finite(scores)))next;That<-cands[which.min(scores)];res[[length(res)+1]]<-data.frame(window=win,config=cfg,season=s,origin=o,true_peak=Ttrue,lead=Ttrue-o,pred=That,err=That-Ttrue,abs_err=abs(That-Ttrue))}}
out<-do.call(rbind,res);dir.create('artifacts/m1-v2-prototype-ablation-v4',recursive=TRUE,showWarnings=FALSE);write.csv(out,'artifacts/m1-v2-prototype-ablation-v4/per_origin.csv',row.names=FALSE)
sum<-aggregate(abs_err~window+config,out,mean);sum$median<-mapply(function(w,c)median(out$abs_err[out$window==w&out$config==c]),sum$window,sum$config);sum$rmse<-mapply(function(w,c)sqrt(mean(out$err[out$window==w&out$config==c]^2)),sum$window,sum$config);sum<-sum[order(sum$abs_err),];write.csv(sum,'artifacts/m1-v2-prototype-ablation-v4/summary.csv',row.names=FALSE);print(head(sum,20),row.names=FALSE,digits=4)
b<-sum[1,];z<-out[out$window==b$window&out$config==b$config,];z$bin<-cut(z$lead,c(-Inf,2,4,6,Inf),labels=c('0-2','2-4','4-6','6+'));cat('\nBEST:',b$config,'window',b$window,'\n');print(aggregate(abs_err~bin,z,mean),row.names=FALSE,digits=4);print(aggregate(abs_err~season,z,mean),row.names=FALSE,digits=4)
