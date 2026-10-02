post <- read.csv('artifacts/m1-c-passage-lowrank-v2/per_origin_posterior.csv', stringsAsFactors=FALSE)
d <- readRDS('artifacts/expert-ignition-annotation-v2-pass1/campaign_data.rds')
peaks <- read.csv('artifacts/expert-ignition-annotation-v2-pass1/retrospective_peak_truth_v1.csv', stringsAsFactors=FALSE)
m0cmp <- read.csv('artifacts/m0-v2-decimal-loso-baseline-r2/compare.csv', stringsAsFactors=FALSE)
Amap <- setNames(m0cmp$iWeek_hatF,m0cmp$season)
Tmap <- setNames(peaks$peak_week_decimal,peaks$season)
seasons <- intersect(names(Amap),names(Tmap))

# Attach raw and pooled two-week causal positivity plus decline diagnostics to posterior rows.
feature_rows <- list()
for(s in seasons){
  z <- d[d$season==s,]; z <- z[order(z$weekF),]
  q2 <- rep(NA_real_,nrow(z))
  for(i in seq_len(nrow(z))){j<-max(1,i-1):i; q2[i]<-sum(z$y[j])/sum(z$N[j])}
  z$q2 <- q2
  z$raw_diff1 <- c(NA,diff(z$p)); z$q2_diff1 <- c(NA,diff(z$q2))
  z$raw_two_down <- c(FALSE,FALSE,head(diff(z$p),-1)<0 & tail(diff(z$p),-1)<0)
  z$q2_two_down <- c(FALSE,FALSE,head(diff(z$q2),-1)<0 & tail(diff(z$q2),-1)<0)
  z$raw_runmax <- cummax(z$p)
  z$q2_runmax <- cummax(z$q2)
  z$raw_drop <- 1-z$p/z$raw_runmax
  z$q2_drop <- 1-z$q2/z$q2_runmax
  p <- post[post$season==s,]
  m <- merge(p,z[,c('weekF','p','q2','raw_diff1','q2_diff1','raw_two_down','q2_two_down','raw_drop','q2_drop')],by.x='origin',by.y='weekF',all.x=TRUE)
  feature_rows[[s]] <- m
}
x <- do.call(rbind,feature_rows); rownames(x)<-NULL
write.csv(x,'artifacts/m1-c-passage-lowrank-v2/per_origin_with_decline_features.csv',row.names=FALSE)

# Two-branch policies:
# fast branch: very high posterior passage probability AND immediate causal decline;
# sustained branch: lower posterior threshold but requires two consecutive declines and drop from running max.
policies <- expand.grid(
  high_thr=c(.8,.9,.95),
  low_thr=c(.1,.2,.3,.4),
  drop_frac=c(.03,.05,.08,.10),
  smooth=c('raw','q2'),
  min_post_A=c(3,4),
  KEEP.OUT.ATTRS=FALSE, stringsAsFactors=FALSE
)
policies$policy_id <- seq_len(nrow(policies))

apply_policy <- function(s,r){
  z <- x[x$season==s,]; z<-z[order(z$origin),]
  confirm <- NA_real_; branch <- NA_character_
  for(i in seq_len(nrow(z))){
    if(z$origin[i] < ceiling(Amap[[s]]) + r$min_post_A) next
    if(r$smooth=='raw'){
      immediate_down <- is.finite(z$raw_diff1[i]) && z$raw_diff1[i] < 0
      two_down <- isTRUE(z$raw_two_down[i])
      drop <- z$raw_drop[i]
    } else {
      immediate_down <- is.finite(z$q2_diff1[i]) && z$q2_diff1[i] < 0
      two_down <- isTRUE(z$q2_two_down[i])
      drop <- z$q2_drop[i]
    }
    fast <- z$p_passed[i] >= r$high_thr && immediate_down
    sustained <- z$p_passed[i] >= r$low_thr && two_down && is.finite(drop) && drop >= r$drop_frac
    if(fast || sustained){
      confirm <- z$origin[i]; branch <- if(fast) 'high_posterior_decline' else 'sustained_decline'; break
    }
  }
  # Origin w includes the completed aggregate for [w,w+1), so T*=w.x has
  # already occurred by release of origin w. First confirmable truth origin=floor(T*).
  tc <- floor(Tmap[[s]])
  data.frame(season=s,policy_id=r$policy_id,confirm_origin=confirm,branch=branch,truth_confirm=tc,
    false_early=is.finite(confirm)&&confirm<tc,
    early_weeks=if(is.finite(confirm))max(tc-confirm,0) else NA_real_,
    delay=if(is.finite(confirm))max(confirm-tc,0) else NA_real_,
    confirmed_by_peak2=is.finite(confirm)&&confirm<=tc+2,
    miss_by_peak2=!is.finite(confirm)||confirm>tc+2)
}

all <- do.call(rbind,lapply(seq_len(nrow(policies)),function(i)do.call(rbind,lapply(seasons,function(s)apply_policy(s,policies[i,])))))
all <- merge(all,policies,by='policy_id',sort=FALSE)
write.csv(all,'artifacts/m1-c-passage-lowrank-v2/hybrid_policy_all_seasons.csv',row.names=FALSE)

# LOSO selection: minimize number and magnitude of early locks first, then misses and delay.
selected <- list()
for(h in seasons){
  tr <- all[all$season!=h,]
  agg <- do.call(rbind,lapply(split(tr,tr$policy_id),function(z)data.frame(
    policy_id=z$policy_id[1], n_false=sum(z$false_early), early_total=sum(z$early_weeks,na.rm=TRUE),
    n_miss=sum(z$miss_by_peak2), mean_delay=if(any(is.finite(z$delay)))mean(z$delay[is.finite(z$delay)]) else Inf,
    high_thr=z$high_thr[1],low_thr=z$low_thr[1],drop_frac=z$drop_frac[1],smooth=z$smooth[1],min_post_A=z$min_post_A[1])))
  ord <- order(agg$n_false,agg$early_total,agg$n_miss,agg$mean_delay,-agg$high_thr,-agg$drop_frac,-agg$min_post_A)
  best <- agg[ord[1],]
  te <- all[all$season==h & all$policy_id==best$policy_id,]
  selected[[h]] <- cbind(te,train_false=best$n_false,train_miss=best$n_miss,train_delay=best$mean_delay)
}
loso <- do.call(rbind,selected);rownames(loso)<-NULL
write.csv(loso,'artifacts/m1-c-passage-lowrank-v2/hybrid_loso_selected.csv',row.names=FALSE)
cat('HYBRID LOSO\n')
print(loso[,c('season','high_thr','low_thr','drop_frac','smooth','min_post_A','truth_confirm','confirm_origin','branch','false_early','delay','miss_by_peak2')],row.names=FALSE,digits=3)
cat('\nSUMMARY\n')
cat('false early=',sum(loso$false_early),'/',nrow(loso),
    ' confirmed by +2=',sum(loso$confirmed_by_peak2),'/',nrow(loso),
    ' misses=',sum(loso$miss_by_peak2),
    ' mean delay=',mean(loso$delay[is.finite(loso$delay)]),
    ' median delay=',median(loso$delay[is.finite(loso$delay)]),'\n',sep='')
