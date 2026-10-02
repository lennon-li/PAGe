d <- readRDS('artifacts/expert-ignition-annotation-v2-pass1/campaign_data.rds')
shape <- read.csv('artifacts/m1-peak-aligned-shape-v1/peak_aligned_smoothed_grid.csv', stringsAsFactors=FALSE)
peaks <- read.csv('artifacts/expert-ignition-annotation-v2-pass1/retrospective_peak_truth_v1.csv', stringsAsFactors=FALSE)
m0cmp <- read.csv('artifacts/m0-v2-decimal-loso-baseline-r2/compare.csv', stringsAsFactors=FALSE)
Amap <- setNames(m0cmp$iWeek_hatF, m0cmp$season)
Tmap <- setNames(peaks$peak_week_decimal, peaks$season)
seasons <- intersect(names(Amap), names(Tmap))
powers <- c(.20,.30,.40,.50,.60,.75,1.00)
logit <- function(p) qlogis(pmin(pmax(p,1e-5),1-1e-5))
shape$eta <- logit(shape$p_smooth)
tau_grid <- seq(-14,1,by=.1)
M <- matrix(NA_real_, nrow=length(tau_grid), ncol=length(seasons), dimnames=list(NULL,seasons))
for(j in seq_along(seasons)){z<-shape[shape$season==seasons[j],];M[,j]<-approx(z$tau,z$eta,xout=tau_grid,rule=1)$y}
canon_for <- function(holdout){keep<-seasons!=holdout;data.frame(tau=tau_grid,eta_med=apply(M[,keep,drop=FALSE],1,median,na.rm=TRUE),eta_sd=pmax(apply(M[,keep,drop=FALSE],1,mad,constant=1.4826,na.rm=TRUE),.20))}
score_candidate <- function(obs,Tcan,canon){sc<-0;n<-0;for(i in seq_len(nrow(obs))){tau<-obs$weekF[i]-Tcan;if(tau< -14||tau>1)next;mu<-approx(canon$tau,canon$eta_med,xout=tau)$y;bsd<-approx(canon$tau,canon$eta_sd,xout=tau)$y;yy<-obs$y[i];NN<-obs$N[i];eo<-log((yy+.5)/(NN-yy+.5));sv<-1/(yy+.5)+1/(NN-yy+.5);v<-bsd^2+sv;sc<-sc+(eo-mu)^2/v+log(v);n<-n+1};if(n==0)NA_real_ else sc}
wquant <- function(x,w,p)x[which(cumsum(w)>=p)[1L]]
rows<-list()
for(s in seasons){dd<-d[d$season==s,];dd<-dd[order(dd$weekF),];A<-Amap[[s]];Ttrue<-Tmap[[s]];canon<-canon_for(s);for(o in seq(ceiling(A),floor(Ttrue),by=1)){obs<-tail(dd[dd$weekF<=o,],2);cands<-seq(max(o+.25,A+3),min(o+14,40),by=.05);scores<-vapply(cands,function(tc)score_candidate(obs,tc,canon),numeric(1));ok<-is.finite(scores);cands<-cands[ok];scores<-scores[ok];if(!length(scores))next;rel<-scores-min(scores);map<-cands[which.min(scores)];for(power in powers){w<-exp(-.5*power*rel);w<-w/sum(w);q05<-wquant(cands,w,.05);q95<-wquant(cands,w,.95);q10<-wquant(cands,w,.10);q90<-wquant(cands,w,.90);rows[[length(rows)+1]]<-data.frame(season=s,origin=o,true_peak=Ttrue,lead=Ttrue-o,power=power,map_peak=map,abs_err=abs(map-Ttrue),q05=q05,q95=q95,q10=q10,q90=q90,cover90=Ttrue>=q05&Ttrue<=q95,width90=q95-q05,cover80=Ttrue>=q10&Ttrue<=q90,width80=q90-q10)}}}
out<-do.call(rbind,rows)
dir.create('artifacts/m1-v2-prototype-posterior-calibration-v8',recursive=TRUE,showWarnings=FALSE)
write.csv(out,'artifacts/m1-v2-prototype-posterior-calibration-v8/per_origin_power_grid.csv',row.names=FALSE)
cat('GLOBAL POWER GRID (diagnostic only)\n');global<-aggregate(cbind(cover90,width90,cover80,width80)~power,out,mean);print(global,digits=3,row.names=FALSE)
# Season-excluded calibration: pick power whose TRAINING 90% coverage is closest to .90; tie => narrower interval.
sel<-list();held<-list()
for(s in seasons){tr<-out[out$season!=s,];te<-out[out$season==s,];sm<-aggregate(cbind(cover90,width90)~power,tr,mean);sm$gap<-abs(sm$cover90-.90);sm<-sm[order(sm$gap,sm$width90),];pw<-sm$power[1];z<-te[te$power==pw,];sel[[length(sel)+1]]<-data.frame(season=s,power=pw,train_cover90=sm$cover90[1],train_width90=sm$width90[1]);held[[length(held)+1]]<-z}
selection<-do.call(rbind,sel);heldout<-do.call(rbind,held);write.csv(selection,'artifacts/m1-v2-prototype-posterior-calibration-v8/selected_power_by_season.csv',row.names=FALSE);write.csv(heldout,'artifacts/m1-v2-prototype-posterior-calibration-v8/crossfitted_intervals.csv',row.names=FALSE)
cat('\nSELECTED POWER BY HELD-OUT SEASON\n');print(selection,digits=3,row.names=FALSE)
cat('\nCROSSFITTED UNCERTAINTY\n');print(c(cover90=mean(heldout$cover90),width90=mean(heldout$width90),cover80=mean(heldout$cover80),width80=mean(heldout$width80),map_MAE=mean(heldout$abs_err)))
heldout$bin<-cut(heldout$lead,c(-Inf,2,4,6,Inf),labels=c('0-2','2-4','4-6','6+'));cat('\nBY LEAD\n');print(aggregate(cbind(cover90,width90,abs_err)~bin,heldout,mean),digits=3,row.names=FALSE)
