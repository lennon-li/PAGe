post <- read.csv('artifacts/m1-v2-lowrank-posterior-v8/per_origin.csv', stringsAsFactors=FALSE)
d <- readRDS('artifacts/expert-ignition-annotation-v2-pass1/campaign_data.rds')
peaks <- read.csv('artifacts/expert-ignition-annotation-v2-pass1/retrospective_peak_truth_v1.csv', stringsAsFactors=FALSE)
m0cmp <- read.csv('artifacts/m0-v2-decimal-loso-baseline-r2/compare.csv', stringsAsFactors=FALSE)
Amap <- setNames(m0cmp$iWeek_hatF,m0cmp$season)
Tmap <- setNames(peaks$peak_week_decimal,peaks$season)
seasons <- intersect(names(Amap),names(Tmap))

# ---- M1-F sequential stability ----
post <- post[order(post$season,post$origin),]
stab_rows <- lapply(split(post,post$season),function(z){
  jump <- c(NA,diff(z$mean_peak))
  width_change <- c(NA,diff(z$width90))
  data.frame(
    season=z$season[1], n_origins=nrow(z),
    mean_abs_jump=mean(abs(jump),na.rm=TRUE),
    median_abs_jump=median(abs(jump),na.rm=TRUE),
    max_abs_jump=max(abs(jump),na.rm=TRUE),
    n_jump_gt1=sum(abs(jump)>1,na.rm=TRUE),
    n_jump_gt2=sum(abs(jump)>2,na.rm=TRUE),
    frac_width_narrows=mean(width_change<0,na.rm=TRUE),
    first_width=z$width90[1], last_width=z$width90[nrow(z)],
    first_abs_err=z$abs_err_mean[1], last_abs_err=z$abs_err_mean[nrow(z)]
  )
})
stability <- do.call(rbind,stab_rows)
dir.create('artifacts/m1-v2-stability-passage-v1',recursive=TRUE,showWarnings=FALSE)
write.csv(stability,'artifacts/m1-v2-stability-passage-v1/sequential_stability_by_season.csv',row.names=FALSE)
cat('SEQUENTIAL STABILITY\n')
print(stability,row.names=FALSE,digits=3)
cat('\nOVERALL\n')
cat('mean abs weekly jump=',mean(stability$mean_abs_jump),
    ' seasons with >1w jump=',sum(stability$n_jump_gt1>0),'/',nrow(stability),
    ' seasons with >2w jump=',sum(stability$n_jump_gt2>0),'/',nrow(stability),
    ' mean first width=',mean(stability$first_width),
    ' mean last width=',mean(stability$last_width),'\n',sep='')

# ---- M1-C causal passage rule candidates ----
# q_t is either raw weekly positivity or a pooled-count trailing 2-week positivity.
make_q <- function(z,smooth_n){
  z <- z[order(z$weekF),]
  q <- rep(NA_real_,nrow(z))
  for(i in seq_len(nrow(z))){
    j <- max(1,i-smooth_n+1):i
    q[i] <- sum(z$y[j])/sum(z$N[j])
  }
  q
}

rule_grid <- expand.grid(
  smooth_n=c(1,2),
  drop_frac=c(0,.05,.10,.15,.20,.25),
  persistence=c(1,2),
  min_post_A=c(2,3,4),
  KEEP.OUT.ATTRS=FALSE,stringsAsFactors=FALSE
)
rule_grid$rule_id <- seq_len(nrow(rule_grid))

apply_rule <- function(season,rule){
  z <- d[d$season==season,]
  z <- z[order(z$weekF),]
  A <- Amap[[season]]; T <- Tmap[[season]]
  q <- make_q(z,rule$smooth_n)
  start <- ceiling(A)
  end <- min(max(z$weekF), ceiling(T)+2)
  eligible <- which(z$weekF>=start & z$weekF<=end)
  confirm <- NA_real_
  for(ii in eligible){
    o <- z$weekF[ii]
    if(o < start + rule$min_post_A) next
    prior_idx <- which(z$weekF>=start & z$weekF<o)
    if(length(prior_idx)<1) next
    running_max <- max(q[prior_idx],na.rm=TRUE)
    drop_ok <- q[ii] <= (1-rule$drop_frac)*running_max
    # persistence means the most recent p consecutive q changes must be negative.
    p <- rule$persistence
    dec_ok <- FALSE
    local_idx <- which(z$weekF<=o & z$weekF>=o-p)
    if(length(local_idx)>=p+1){
      qq <- q[tail(local_idx,p+1)]
      dec_ok <- all(diff(qq)<0)
    }
    if(drop_ok && dec_ok){confirm <- o; break}
  }
  truth_confirm <- ceiling(T)
  data.frame(
    season=season,rule_id=rule$rule_id,confirm_origin=confirm,truth_confirm=truth_confirm,
    false_early=is.finite(confirm) && confirm<truth_confirm,
    delay=if(is.finite(confirm)) max(confirm-truth_confirm,0) else NA_real_,
    confirmed_by_peak2=is.finite(confirm) && confirm<=truth_confirm+2,
    miss_by_peak2=!is.finite(confirm) || confirm>truth_confirm+2
  )
}

all_eval <- do.call(rbind,lapply(seq_len(nrow(rule_grid)),function(i){
  do.call(rbind,lapply(seasons,function(s) apply_rule(s,rule_grid[i,])))
}))
all_eval <- merge(all_eval,rule_grid,by='rule_id',sort=FALSE)
write.csv(all_eval,'artifacts/m1-v2-stability-passage-v1/passage_rule_all_seasons.csv',row.names=FALSE)

# Strict LOSO rule selection. Selection priority:
# 1) number false early; 2) misses by peak+2; 3) mean delay among confirmations;
# 4) stronger drop threshold; 5) smoother/persistent rule as deterministic tie-breakers.
selected <- list()
for(holdout in seasons){
  tr <- all_eval[all_eval$season!=holdout,]
  agg <- do.call(rbind,lapply(split(tr,tr$rule_id),function(x){
    data.frame(rule_id=x$rule_id[1],n_false_early=sum(x$false_early),n_miss=sum(x$miss_by_peak2),
      mean_delay=if(all(!is.finite(x$delay))) Inf else mean(x$delay[is.finite(x$delay)]),
      drop_frac=x$drop_frac[1],smooth_n=x$smooth_n[1],persistence=x$persistence[1],min_post_A=x$min_post_A[1])
  }))
  ord <- order(agg$n_false_early,agg$n_miss,agg$mean_delay,-agg$drop_frac,-agg$smooth_n,-agg$persistence,-agg$min_post_A)
  best <- agg[ord[1],]
  te <- all_eval[all_eval$season==holdout & all_eval$rule_id==best$rule_id,]
  selected[[holdout]] <- cbind(te,best_n_false_early_train=best$n_false_early,best_n_miss_train=best$n_miss,best_mean_delay_train=best$mean_delay)
}
loso <- do.call(rbind,selected)
rownames(loso)<-NULL
write.csv(loso,'artifacts/m1-v2-stability-passage-v1/passage_loso_selected.csv',row.names=FALSE)
cat('\nM1-C LOSO SELECTED\n')
print(loso[,c('season','rule_id','smooth_n','drop_frac','persistence','min_post_A','truth_confirm','confirm_origin','false_early','delay','miss_by_peak2')],row.names=FALSE)
cat('\nM1-C SUMMARY\n')
cat('false early=',sum(loso$false_early),'/',nrow(loso),
    ' confirmed by peak+2=',sum(loso$confirmed_by_peak2),'/',nrow(loso),
    ' misses=',sum(loso$miss_by_peak2),
    ' mean delay=',mean(loso$delay[is.finite(loso$delay)]),
    ' median delay=',median(loso$delay[is.finite(loso$delay)]),'\n',sep='')
