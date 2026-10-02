d <- readRDS('artifacts/expert-ignition-annotation-v2-pass1/campaign_data.rds')
shape <- read.csv('artifacts/m1-peak-aligned-shape-v1/peak_aligned_smoothed_grid.csv', stringsAsFactors=FALSE)
peaks <- read.csv('artifacts/expert-ignition-annotation-v2-pass1/retrospective_peak_truth_v1.csv', stringsAsFactors=FALSE)
m0cmp <- read.csv('artifacts/m0-v2-decimal-loso-baseline-r2/compare.csv', stringsAsFactors=FALSE)
Amap <- setNames(m0cmp$iWeek_hatF,m0cmp$season)
Tmap <- setNames(peaks$peak_week_decimal,peaks$season)
seasons <- intersect(names(Amap),names(Tmap))

# Peak-normalized historical shape library. Amplitude is handled as a nuisance.
peak_height <- tapply(shape$p_smooth,shape$season,max,na.rm=TRUE)
shape$p_norm <- shape$p_smooth / peak_height[shape$season]
tau_grid <- seq(-14,1,by=.05)
P <- matrix(NA_real_,length(tau_grid),length(seasons),dimnames=list(NULL,seasons))
for(j in seq_along(seasons)){
  z <- shape[shape$season==seasons[j],]
  P[,j] <- approx(z$tau,z$p_norm,xout=tau_grid,rule=1)$y
}
canon_for <- function(s){
  keep <- seasons != s
  bh <- peak_height[seasons[keep]]
  list(
    tau=tau_grid,
    med=apply(P[,keep,drop=FALSE],1,median,na.rm=TRUE),
    sd=pmax(apply(P[,keep,drop=FALSE],1,mad,constant=1.4826,na.rm=TRUE),.05),
    mu_logb=mean(log(bh)),
    sd_logb=max(sd(log(bh)),.20)
  )
}

# -2 log likelihood up to constants. Between-season shape variance and binomial
# sampling variance are both represented. Lognormal amplitude prior enters once.
cell_score <- function(obs,Tcan,b,canon){
  tau <- obs$weekF-Tcan
  if(any(tau<min(canon$tau)|tau>max(canon$tau))) return(Inf)
  f <- approx(canon$tau,canon$med,xout=tau)$y
  fsd <- approx(canon$tau,canon$sd,xout=tau)$y
  mu <- pmin(pmax(b*f,1e-5),.999)
  vv <- pmax((b*fsd)^2 + mu*(1-mu)/pmax(obs$N,1),1e-6)
  data_nll2 <- sum((obs$p-mu)^2/vv + log(vv))
  # Correct lognormal prior on b, on the -2 log scale (constant omitted).
  prior_nll2 <- ((log(b)-canon$mu_logb)/canon$sd_logb)^2 + 2*log(b)
  data_nll2 + prior_nll2
}

bgrid <- seq(.08,.45,by=.01)
res <- list(); post_rows <- list()
for(s in seasons){
  dd <- d[d$season==s,]; dd <- dd[order(dd$weekF),]
  A <- Amap[[s]]; Ttrue <- Tmap[[s]]; canon <- canon_for(s)
  for(o in seq(ceiling(A),floor(Ttrue),1)){
    # All causal observations from M0 activation through current origin.
    obs <- dd[dd$weekF>=ceiling(A) & dd$weekF<=o,]
    cands <- seq(max(o+.05,A+3),min(o+14,40),by=.1)
    S <- matrix(Inf,nrow=length(cands),ncol=length(bgrid))
    for(i in seq_along(cands)) for(j in seq_along(bgrid)) S[i,j] <- cell_score(obs,cands[i],bgrid[j],canon)
    finite <- is.finite(S)
    if(!any(finite)) next
    m <- min(S[finite])
    W <- exp(-.5*(S-m)); W[!finite] <- 0
    # Marginalize nuisance amplitude.
    wt <- rowSums(W); wt <- wt/sum(wt)
    wb <- colSums(W); wb <- wb/sum(wb)
    mapT <- cands[which.max(wt)]
    meanT <- sum(cands*wt)
    cdf <- cumsum(wt)
    medianT <- cands[which(cdf>=.5)[1]]
    q05 <- cands[which(cdf>=.05)[1]]; q95 <- cands[which(cdf>=.95)[1]]
    meanB <- sum(bgrid*wb)
    res[[length(res)+1]] <- data.frame(
      season=s,A=A,origin=o,n_obs=nrow(obs),true_peak=Ttrue,lead=Ttrue-o,
      map_peak=mapT,mean_peak=meanT,median_peak=medianT,
      amplitude_mean=meanB,q05=q05,q95=q95,width90=q95-q05,
      covered90=Ttrue>=q05 & Ttrue<=q95,
      err_map=mapT-Ttrue,abs_err_map=abs(mapT-Ttrue),
      err_mean=meanT-Ttrue,abs_err_mean=abs(meanT-Ttrue),
      err_median=medianT-Ttrue,abs_err_median=abs(medianT-Ttrue)
    )
  }
}
out <- do.call(rbind,res)
dir.create('artifacts/m1-v2-posterior-v7',recursive=TRUE,showWarnings=FALSE)
write.csv(out,'artifacts/m1-v2-posterior-v7/per_origin.csv',row.names=FALSE)
metrics <- data.frame(
  estimator=c('MAP','mean','median'),
  MAE=c(mean(out$abs_err_map),mean(out$abs_err_mean),mean(out$abs_err_median)),
  RMSE=c(sqrt(mean(out$err_map^2)),sqrt(mean(out$err_mean^2)),sqrt(mean(out$err_median^2)))
)
write.csv(metrics,'artifacts/m1-v2-posterior-v7/metrics.csv',row.names=FALSE)
cat('POINT METRICS\n'); print(metrics,row.names=FALSE,digits=4)
cat('\nUNCERTAINTY\n'); cat('90% coverage=',mean(out$covered90),' median width=',median(out$width90),' mean width=',mean(out$width90),'\n',sep='')
out$bin <- cut(out$lead,c(-Inf,2,4,6,Inf),labels=c('0-2','2-4','4-6','6+'))
cat('\nMAP BY LEAD\n'); print(aggregate(abs_err_map~bin,out,mean),row.names=FALSE,digits=4)
cat('\nCOVERAGE BY LEAD\n'); print(aggregate(cbind(covered90,width90)~bin,out,mean),row.names=FALSE,digits=4)
cat('\nMAP BY SEASON\n'); print(aggregate(abs_err_map~season,out,mean),row.names=FALSE,digits=4)
