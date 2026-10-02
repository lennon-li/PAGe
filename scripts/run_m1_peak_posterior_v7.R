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
M <- matrix(NA_real_, nrow=length(tau_grid), ncol=length(seasons), dimnames=list(NULL,seasons))
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
# Return total negative-2-log-likelihood-like score. Do not divide by n:
# additional independent weekly observations should strengthen posterior evidence.
score_candidate <- function(obs,Tcan,canon){
  sc <- 0; n <- 0
  for(i in seq_len(nrow(obs))){
    tau <- obs$weekF[i]-Tcan
    if(tau < -14 || tau > 1) next
    mu <- approx(canon$tau,canon$eta_med,xout=tau)$y
    between_sd <- approx(canon$tau,canon$eta_sd,xout=tau)$y
    yy <- obs$y[i]; NN <- obs$N[i]
    eta_obs <- log((yy+.5)/(NN-yy+.5))
    samp_var <- 1/(yy+.5) + 1/(NN-yy+.5)
    v <- between_sd^2 + samp_var
    sc <- sc + (eta_obs-mu)^2/v + log(v)
    n <- n+1
  }
  if(n==0) NA_real_ else sc
}
wquant <- function(x,w,p){x[which(cumsum(w)>=p)[1L]]}
res <- list()
for(s in seasons){
  dd <- d[d$season==s,]; dd <- dd[order(dd$weekF),]
  A <- Amap[[s]]; Ttrue <- Tmap[[s]]; canon <- canon_for(s)
  for(o in seq(ceiling(A),floor(Ttrue),by=1)){
    obs <- tail(dd[dd$weekF<=o,],2)
    cands <- seq(max(o+.25,A+3),min(o+14,40),by=.05)
    scores <- vapply(cands,function(tc)score_candidate(obs,tc,canon),numeric(1))
    ok <- is.finite(scores)
    cands <- cands[ok]; scores <- scores[ok]
    if(!length(scores)) next
    rel <- scores-min(scores)
    w <- exp(-.5*rel); w <- w/sum(w)
    map <- cands[which.max(w)]
    post_mean <- sum(cands*w)
    med <- wquant(cands,w,.5)
    q05 <- wquant(cands,w,.05); q10 <- wquant(cands,w,.10); q25 <- wquant(cands,w,.25)
    q75 <- wquant(cands,w,.75); q90 <- wquant(cands,w,.90); q95 <- wquant(cands,w,.95)
    res[[length(res)+1]] <- data.frame(season=s,A=A,origin=o,true_peak=Ttrue,lead=Ttrue-o,
      map_peak=map,mean_peak=post_mean,median_peak=med,
      abs_err_map=abs(map-Ttrue),abs_err_mean=abs(post_mean-Ttrue),abs_err_median=abs(med-Ttrue),
      q05=q05,q10=q10,q25=q25,q75=q75,q90=q90,q95=q95,
      width50=q75-q25,width80=q90-q10,width90=q95-q05,
      cover50=Ttrue>=q25&Ttrue<=q75,cover80=Ttrue>=q10&Ttrue<=q90,cover90=Ttrue>=q05&Ttrue<=q95)
  }
}
out <- do.call(rbind,res)
dir.create('artifacts/m1-v2-prototype-posterior-v7',recursive=TRUE,showWarnings=FALSE)
write.csv(out,'artifacts/m1-v2-prototype-posterior-v7/per_origin.csv',row.names=FALSE)
out$bin <- cut(out$lead,c(-Inf,2,4,6,Inf),labels=c('0-2','2-4','4-6','6+'))
cat('POINT ESTIMATES\n')
print(c(map_MAE=mean(out$abs_err_map),mean_MAE=mean(out$abs_err_mean),median_MAE=mean(out$abs_err_median),n=nrow(out)))
cat('\nUNCERTAINTY ALL\n')
print(c(cover50=mean(out$cover50),cover80=mean(out$cover80),cover90=mean(out$cover90),width50=mean(out$width50),width80=mean(out$width80),width90=mean(out$width90)))
cat('\nBY LEAD\n')
print(aggregate(cbind(abs_err_map,cover50,cover80,cover90,width50,width80,width90)~bin,out,mean),digits=3,row.names=FALSE)
cat('\nBY SEASON\n')
print(aggregate(cbind(abs_err_map,cover90,width90)~season,out,mean),digits=3,row.names=FALSE)
