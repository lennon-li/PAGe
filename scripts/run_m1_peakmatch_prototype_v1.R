prior_weight <- as.numeric(Sys.getenv('M1_PRIOR_WEIGHT','0'))
out_dir <- paste0('artifacts/m1-v2-prototype-peakmatch-v1-pw',gsub('\\.','_',format(prior_weight,trim=TRUE)))
d <- readRDS('artifacts/expert-ignition-annotation-v2-pass1/campaign_data.rds')
shape <- read.csv('artifacts/m1-peak-aligned-shape-v1/peak_aligned_smoothed_grid.csv', stringsAsFactors=FALSE)
peaks <- read.csv('artifacts/expert-ignition-annotation-v2-pass1/retrospective_peak_truth_v1.csv', stringsAsFactors=FALSE)
m0cmp <- read.csv('artifacts/m0-v2-decimal-loso-baseline-r2/compare.csv', stringsAsFactors=FALSE)
Amap <- setNames(m0cmp$iWeek_hatF, m0cmp$season)
Tmap <- setNames(peaks$peak_week_decimal, peaks$season)
seasons <- intersect(names(Amap), names(Tmap))

tau_grid <- seq(-14, 1, by=.1)
features <- c('p_smooth','auc2','auc3')
# Precompute feature matrices: rows=tau, cols=season.
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
  robust_sd <- function(m) apply(m[,keep,drop=FALSE],1,mad,constant=1.4826,na.rm=TRUE)
  data.frame(
    tau=tau_grid,
    p_med=med(mats$p_smooth), p_sd=pmax(robust_sd(mats$p_smooth),.01),
    a2_med=med(mats$auc2), a2_sd=pmax(robust_sd(mats$auc2),.015),
    a3_med=med(mats$auc3), a3_sd=pmax(robust_sd(mats$auc3),.02)
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
score_candidate <- function(obs,Tcan,canon,A,prior_med,prior_sd) {
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
  if(wt==0) return(NA_real_)
  data_score <- sc/wt
  d <- Tcan-A
  prior_score <- ((d-prior_med)/prior_sd)^2 + 2*log(prior_sd)
  data_score + prior_weight*prior_score
}

res <- list()
for(s in seasons) {
  dd <- d[d$season==s,]; dd <- dd[order(dd$weekF),]
  A <- Amap[[s]]; Ttrue <- Tmap[[s]]; canon <- canon_for(s)
  train_s <- setdiff(seasons,s)
  train_d <- unname(Tmap[train_s]-Amap[train_s])
  prior_med <- median(train_d)
  prior_sd <- max(mad(train_d,constant=1.4826),1.5)
  origins <- seq(ceiling(A),floor(Ttrue),by=1)
  for(o in origins) {
    avail <- dd[dd$weekF<=o,]
    obs <- avail[avail$weekF>=o-3,]
    obs$a2 <- vapply(obs$weekF,function(t)local_auc_obs(avail,t,2),numeric(1))
    obs$a3 <- vapply(obs$weekF,function(t)local_auc_obs(avail,t,3),numeric(1))
    cands <- seq(max(o+.25,A+3),min(o+14,40),by=.1)
    scores <- vapply(cands,function(tc)score_candidate(obs,tc,canon,A,prior_med,prior_sd),numeric(1))
    if(all(!is.finite(scores))) next
    j <- which.min(scores); That <- cands[j]
    z <- scores-min(scores,na.rm=TRUE); w <- exp(-.5*z); w[!is.finite(w)] <- 0; w <- w/sum(w)
    cdf <- cumsum(w)
    q05 <- cands[which(cdf>=.05)[1]]; q95 <- cands[which(cdf>=.95)[1]]
    res[[length(res)+1]] <- data.frame(season=s,A=A,origin=o,true_peak=Ttrue,lead=Ttrue-o,prior_med=prior_med,prior_sd=prior_sd,map_peak=That,
      mean_peak=sum(cands*w),err_map=That-Ttrue,abs_err_map=abs(That-Ttrue),q05=q05,q95=q95,width90=q95-q05)
  }
}
out <- do.call(rbind,res)
dir.create(out_dir,recursive=TRUE,showWarnings=FALSE)
write.csv(out,file.path(out_dir,'per_origin.csv'),row.names=FALSE)
out$bin <- cut(out$lead,c(-Inf,2,4,6,Inf),labels=c('0-2','2-4','4-6','6+'))
by_lead <- aggregate(abs_err_map~bin,out,mean)
by_season <- aggregate(abs_err_map~season,out,mean)
ee <- do.call(rbind,lapply(split(out,out$season),function(z)z[which.min(z$origin),]))
write.csv(by_lead,file.path(out_dir,'by_lead.csv'),row.names=FALSE)
write.csv(by_season,file.path(out_dir,'by_season.csv'),row.names=FALSE)
write.csv(ee,file.path(out_dir,'earliest_origin.csv'),row.names=FALSE)
cat('ALL ORIGINS\n'); print(c(MAE=mean(out$abs_err_map),RMSE=sqrt(mean(out$err_map^2)),median=median(out$abs_err_map),n=nrow(out)))
cat('\nBY LEAD BIN\n'); print(by_lead)
cat('\nBY SEASON\n'); print(by_season)
cat('\nEARLIEST ORIGIN EACH SEASON\n'); print(ee[,c('season','A','origin','true_peak','map_peak','abs_err_map','width90')],row.names=FALSE,digits=3)
