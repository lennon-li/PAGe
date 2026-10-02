d <- readRDS('artifacts/expert-ignition-annotation-v2-pass1/campaign_data.rds')
shape <- read.csv('artifacts/m1-peak-aligned-shape-v1/peak_aligned_smoothed_grid.csv', stringsAsFactors=FALSE)
peaks <- read.csv('artifacts/expert-ignition-annotation-v2-pass1/retrospective_peak_truth_v1.csv', stringsAsFactors=FALSE)
m0cmp <- read.csv('artifacts/m0-v2-decimal-loso-baseline-r2/compare.csv', stringsAsFactors=FALSE)
Amap <- setNames(m0cmp$iWeek_hatF, m0cmp$season)
Tmap <- setNames(peaks$peak_week_decimal, peaks$season)
seasons <- intersect(names(Amap), names(Tmap))

# Historical amplitude-invariant shape features from retrospective smooths.
shape$q2 <- shape$auc2 / pmax(2 * shape$p_smooth, 1e-6)
shape$q3 <- shape$auc3 / pmax(3 * shape$p_smooth, 1e-6)
shape$rel_slope <- shape$slope / pmax(shape$p_smooth, .005)
# trim pathological ratios in very-low-activity tails
shape$q2 <- pmin(pmax(shape$q2, 0), 3)
shape$q3 <- pmin(pmax(shape$q3, 0), 3)
shape$rel_slope <- pmin(pmax(shape$rel_slope, -1), 1)

tau_grid <- seq(-12, .5, by=.1)
features <- c('q2','q3','rel_slope')
mats <- lapply(features, function(f) {
  m <- matrix(NA_real_, nrow=length(tau_grid), ncol=length(seasons), dimnames=list(NULL,seasons))
  for(j in seq_along(seasons)) {
    z <- shape[shape$season==seasons[j],]
    m[,j] <- approx(z$tau,z[[f]],xout=tau_grid,rule=1)$y
  }
  m
})
names(mats) <- features

canon_for <- function(holdout) {
  keep <- seasons != holdout
  med <- function(m) apply(m[,keep,drop=FALSE],1,median,na.rm=TRUE)
  rsd <- function(m) apply(m[,keep,drop=FALSE],1,mad,constant=1.4826,na.rm=TRUE)
  data.frame(
    tau=tau_grid,
    q2_med=med(mats$q2), q2_sd=pmax(rsd(mats$q2),.08),
    q3_med=med(mats$q3), q3_sd=pmax(rsd(mats$q3),.08),
    rs_med=med(mats$rel_slope), rs_sd=pmax(rsd(mats$rel_slope),.04)
  )
}
interp <- function(x,y,t) approx(x,y,xout=t,rule=2)$y
trapz <- function(x,y) if(length(x)<2) 0 else sum(diff(x)*(head(y,-1)+tail(y,-1))/2)
local_auc_obs <- function(dd,t,w) {
  lo <- t-w
  if(lo < min(dd$weekF)) return(NA_real_)
  xs <- sort(unique(c(dd$weekF[dd$weekF>=lo & dd$weekF<=t],lo,t)))
  trapz(xs,interp(dd$weekF,dd$p,xs))
}
obs_features <- function(avail,t) {
  pt <- interp(avail$weekF,avail$p,t)
  a2 <- local_auc_obs(avail,t,2)
  a3 <- local_auc_obs(avail,t,3)
  pm1 <- interp(avail$weekF,avail$p,t-1)
  pp1 <- if(t+1 <= max(avail$weekF)) interp(avail$weekF,avail$p,t+1) else NA_real_
  # causal one-sided relative slope: 1-week backward difference / current level
  rs <- (pt-pm1)/pmax(pt,.005)
  c(q2=if(is.finite(a2)) a2/pmax(2*pt,1e-6) else NA_real_,
    q3=if(is.finite(a3)) a3/pmax(3*pt,1e-6) else NA_real_,
    rel_slope=pmin(pmax(rs,-1),1))
}
score_candidate <- function(obs,Tcan,canon,use=c('q2','q3','rel_slope')) {
  sc <- 0; wt <- 0
  for(i in seq_len(nrow(obs))) {
    tau <- obs$weekF[i]-Tcan
    if(tau < min(canon$tau) || tau > max(canon$tau)) next
    if('q2' %in% use && is.finite(obs$q2[i])) {
      mu <- approx(canon$tau,canon$q2_med,xout=tau)$y; sd <- approx(canon$tau,canon$q2_sd,xout=tau)$y
      sc <- sc + ((obs$q2[i]-mu)/sd)^2 + 2*log(sd); wt <- wt+1
    }
    if('q3' %in% use && is.finite(obs$q3[i])) {
      mu <- approx(canon$tau,canon$q3_med,xout=tau)$y; sd <- approx(canon$tau,canon$q3_sd,xout=tau)$y
      sc <- sc + ((obs$q3[i]-mu)/sd)^2 + 2*log(sd); wt <- wt+1
    }
    if('rel_slope' %in% use && is.finite(obs$rel_slope[i])) {
      mu <- approx(canon$tau,canon$rs_med,xout=tau)$y; sd <- approx(canon$tau,canon$rs_sd,xout=tau)$y
      sc <- sc + ((obs$rel_slope[i]-mu)/sd)^2 + 2*log(sd); wt <- wt+1
    }
  }
  if(wt==0) NA_real_ else sc/wt
}

configs <- list(q2='q2', q3='q3', q2q3=c('q2','q3'), slope='rel_slope', q2s=c('q2','rel_slope'), q3s=c('q3','rel_slope'), all=c('q2','q3','rel_slope'))
res <- list()
for(cfg in names(configs)) {
  use <- configs[[cfg]]
  for(s in seasons) {
    dd <- d[d$season==s,]; dd <- dd[order(dd$weekF),]
    A <- Amap[[s]]; Ttrue <- Tmap[[s]]; canon <- canon_for(s)
    origins <- seq(ceiling(A),floor(Ttrue),by=1)
    for(o in origins) {
      avail <- dd[dd$weekF<=o,]
      obs <- avail[avail$weekF>=o-2,]
      ff <- t(vapply(obs$weekF,function(t)obs_features(avail,t),numeric(3)))
      obs$q2 <- ff[,'q2']; obs$q3 <- ff[,'q3']; obs$rel_slope <- ff[,'rel_slope']
      cands <- seq(max(o+.25,A+3),min(o+14,40),by=.1)
      scores <- vapply(cands,function(tc)score_candidate(obs,tc,canon,use),numeric(1))
      if(all(!is.finite(scores))) next
      That <- cands[which.min(scores)]
      res[[length(res)+1]] <- data.frame(config=cfg,season=s,A=A,origin=o,true_peak=Ttrue,lead=Ttrue-o,map_peak=That,err=That-Ttrue,abs_err=abs(That-Ttrue))
    }
  }
}
out <- do.call(rbind,res)
dir.create('artifacts/m1-v2-prototype-scale-invariant-v3',recursive=TRUE,showWarnings=FALSE)
write.csv(out,'artifacts/m1-v2-prototype-scale-invariant-v3/per_origin.csv',row.names=FALSE)
summary <- aggregate(abs_err~config,out,mean)
summary$median <- vapply(summary$config,function(z)median(out$abs_err[out$config==z]),numeric(1))
summary$rmse <- vapply(summary$config,function(z)sqrt(mean(out$err[out$config==z]^2)),numeric(1))
summary <- summary[order(summary$abs_err),]
write.csv(summary,'artifacts/m1-v2-prototype-scale-invariant-v3/summary.csv',row.names=FALSE)
print(summary,row.names=FALSE,digits=4)
best <- summary$config[1]
z <- out[out$config==best,]
z$bin <- cut(z$lead,c(-Inf,2,4,6,Inf),labels=c('0-2','2-4','4-6','6+'))
cat('\nBEST BY LEAD\n'); print(aggregate(abs_err~bin,z,mean),row.names=FALSE,digits=4)
cat('\nBEST BY SEASON\n'); print(aggregate(abs_err~season,z,mean),row.names=FALSE,digits=4)
