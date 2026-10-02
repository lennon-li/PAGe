d <- readRDS('artifacts/expert-ignition-annotation-v2-pass1/campaign_data.rds')
shape <- read.csv('artifacts/m1-peak-aligned-shape-v1/peak_aligned_smoothed_grid.csv', stringsAsFactors=FALSE)
peaks <- read.csv('artifacts/expert-ignition-annotation-v2-pass1/retrospective_peak_truth_v1.csv', stringsAsFactors=FALSE)
m0cmp <- read.csv('artifacts/m0-v2-decimal-loso-baseline-r2/compare.csv', stringsAsFactors=FALSE)
meta <- read.csv('artifacts/m1-subtype-hypothesis-v1/season_subtype_metadata.csv', stringsAsFactors=FALSE)
Amap <- setNames(m0cmp$iWeek_hatF, m0cmp$season)
Tmap <- setNames(peaks$peak_week_decimal, peaks$season)
submap <- setNames(meta$dominant_A_subtype, meta$season)
seasons <- intersect(intersect(names(Amap), names(Tmap)), names(submap))

tau_grid <- seq(-14, 1, by=.1)
features <- c('p_smooth','auc2','auc3')
mats <- lapply(features, function(f) {
  m <- matrix(NA_real_, nrow=length(tau_grid), ncol=length(seasons), dimnames=list(NULL,seasons))
  for(j in seq_along(seasons)) {
    z <- shape[shape$season==seasons[j],]
    m[,j] <- approx(z$tau,z[[f]],xout=tau_grid,rule=1)$y
  }
  m
})
names(mats) <- features

canon_for <- function(holdout, mode=c('pooled','subtype')) {
  mode <- match.arg(mode)
  keep <- seasons != holdout
  if(mode=='subtype') keep <- keep & submap[seasons] == submap[[holdout]]
  med <- function(m) apply(m[,keep,drop=FALSE],1,median,na.rm=TRUE)
  robust_sd <- function(m) apply(m[,keep,drop=FALSE],1,mad,constant=1.4826,na.rm=TRUE)
  data.frame(
    tau=tau_grid,
    p_med=med(mats$p_smooth), p_sd=pmax(robust_sd(mats$p_smooth),.01),
    a2_med=med(mats$auc2), a2_sd=pmax(robust_sd(mats$auc2),.015),
    a3_med=med(mats$auc3), a3_sd=pmax(robust_sd(mats$auc3),.02),
    n_train=sum(keep)
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
score_candidate <- function(obs,Tcan,canon) {
  sc <- 0; wt <- 0
  for(i in seq_len(nrow(obs))) {
    tau <- obs$weekF[i]-Tcan
    if(tau < -14 || tau > 1) next
    pm <- approx(canon$tau,canon$p_med,xout=tau)$y
    ps <- approx(canon$tau,canon$p_sd,xout=tau)$y
    sc <- sc + ((obs$p[i]-pm)/ps)^2 + 2*log(ps); wt <- wt+1
    if(is.finite(obs$a2[i])) {
      am <- approx(canon$tau,canon$a2_med,xout=tau)$y; as <- approx(canon$tau,canon$a2_sd,xout=tau)$y
      sc <- sc + .5*(((obs$a2[i]-am)/as)^2+2*log(as)); wt <- wt+.5
    }
    if(is.finite(obs$a3[i])) {
      am <- approx(canon$tau,canon$a3_med,xout=tau)$y; as <- approx(canon$tau,canon$a3_sd,xout=tau)$y
      sc <- sc + .5*(((obs$a3[i]-am)/as)^2+2*log(as)); wt <- wt+.5
    }
  }
  if(wt==0) NA_real_ else sc/wt
}

res <- list()
for(mode in c('pooled','subtype')) {
  for(s in seasons) {
    dd <- d[d$season==s,]; dd <- dd[order(dd$weekF),]
    A <- Amap[[s]]; Ttrue <- Tmap[[s]]; canon <- canon_for(s,mode)
    origins <- seq(ceiling(A),floor(Ttrue),by=1)
    for(o in origins) {
      avail <- dd[dd$weekF<=o,]
      obs <- avail[avail$weekF>=o-3,]
      obs$a2 <- vapply(obs$weekF,function(t)local_auc_obs(avail,t,2),numeric(1))
      obs$a3 <- vapply(obs$weekF,function(t)local_auc_obs(avail,t,3),numeric(1))
      cands <- seq(max(o+.25,A+3),min(o+14,40),by=.1)
      scores <- vapply(cands,function(tc)score_candidate(obs,tc,canon),numeric(1))
      if(all(!is.finite(scores))) next
      That <- cands[which.min(scores)]
      res[[length(res)+1]] <- data.frame(mode=mode,season=s,subtype=submap[[s]],n_train=canon$n_train[1],A=A,origin=o,true_peak=Ttrue,lead=Ttrue-o,map_peak=That,err=That-Ttrue,abs_err=abs(That-Ttrue))
    }
  }
}
out <- do.call(rbind,res)
dir.create('artifacts/m1-subtype-hypothesis-v1',recursive=TRUE,showWarnings=FALSE)
write.csv(out,'artifacts/m1-subtype-hypothesis-v1/per_origin_pooled_vs_oracle_subtype.csv',row.names=FALSE)
cat('OVERALL\n'); print(aggregate(abs_err~mode,out,mean))
cat('\nBY SUBTYPE\n'); print(aggregate(abs_err~mode+subtype,out,mean))
cat('\nBY SEASON\n'); print(aggregate(abs_err~mode+season+subtype,out,mean))
cat('\nEARLY LEAD > 6\n'); print(aggregate(abs_err~mode+subtype,out[out$lead>6,],mean))
cat('\nMID 3-6\n'); print(aggregate(abs_err~mode+subtype,out[out$lead>3 & out$lead<=6,],mean))
cat('\nLATE <=3\n'); print(aggregate(abs_err~mode+subtype,out[out$lead<=3,],mean))
