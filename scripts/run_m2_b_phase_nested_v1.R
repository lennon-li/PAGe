source('PAGe/R/data_contract.R')
source('PAGe/R/expert_timing_annotations.R')
source('PAGe/R/retrospective_peak_truth.R')
source('PAGe/R/m1_v2.R')

ab <- read.csv('artifacts/m2-v2-flu-ab-geometry-v1/flu_ab_long_v1.csv', stringsAsFactors=FALSE)
b <- ab[ab$type=='B',c('season','weekF','y','N','p','denominator_regime')]
b$season <- as.character(b$season)
b <- b[order(b$season,b$weekF),]
ledger <- read.csv('artifacts/m2-v2-b-baselines-v1/candidate_independent_ledger.csv', stringsAsFactors=FALSE)
geom <- read.csv('artifacts/m2-v2-flu-ab-geometry-v1/type_geometry_k8.csv', stringsAsFactors=FALSE)
truth <- geom[geom$type=='B',c('season','peak_week_decimal','peak_amplitude')]
seasons <- sort(unique(b$season))
out_dir <- 'artifacts/m2-v2-b-phase-nested-v1'
dir.create(out_dir,recursive=TRUE,showWarnings=FALSE)

# Conservative causal timing-availability gate fixed from the independent review:
# a B timing state exists only after epidemic-level B activity is observed.
gate_one <- function(z){
  z<-z[order(z$weekF),]
  sum4<-as.numeric(stats::filter(z$y,rep(1,4),sides=1))
  maxp4<-vapply(seq_len(nrow(z)),function(i)max(z$p[max(1,i-3):i],na.rm=TRUE),numeric(1))
  ok<-which(z$weekF>=18 & is.finite(sum4) & sum4>=40 & maxp4>=.05)
  if(length(ok)) z$weekF[min(ok)] else NA_real_
}
gates <- do.call(rbind,lapply(split(b,b$season),function(z)data.frame(season=z$season[1],gate_week=gate_one(z))))
write.csv(gates,file.path(out_dir,'causal_b_timing_gates.csv'),row.names=FALSE)

summarize_passage <- function(p){
  post <- attr(p,'posterior')
  T <- post$peak_week_decimal; w <- post$probability
  cdf <- cumsum(w)
  q <- function(prob) T[which(cdf>=prob)[1]]
  c(mean=sum(T*w),q05=q(.05),q95=q(.95),width=q(.95)-q(.05),p_passed=p$prob_peak_passed[1])
}

cache_dir <- file.path(out_dir,'feature_cache')
dir.create(cache_dir,recursive=TRUE,showWarnings=FALSE)
make_features <- function(outer_holdout,target_season){
  cache_file <- file.path(cache_dir,paste0('outer_',outer_holdout,'__target_',target_season,'.rds'))
  if(file.exists(cache_file)) return(readRDS(cache_file))
  lib_train <- if(target_season==outer_holdout) setdiff(seasons,outer_holdout) else setdiff(seasons,c(outer_holdout,target_season))
  td <- b[b$season %in% lib_train,]
  tt <- truth[truth$season %in% lib_train,c('season','peak_week_decimal')]
  lib <- fit_m1_v2_library(td,tt,k=8L,grid_step=.01,tau_step=.1,
                           amplitude_grid=seq(.005,.25,by=.005))
  z <- b[b$season==target_season,]
  led <- unique(ledger[ledger$season==target_season,c('season','origin_week')])
  gate <- gates$gate_week[gates$season==target_season]
  rows <- vector('list',nrow(led))
  for(i in seq_len(nrow(led))){
    o <- led$origin_week[i]
    available <- is.finite(gate) && o>=gate
    vals <- c(mean=NA,q05=NA,q95=NA,width=NA,p_passed=NA)
    if(available){
      pp <- tryCatch(m1_v2_passage_posterior(lib,z,activation_week=gate,origin_week=o,
                                              candidate_step=.2,max_future_weeks=12),error=function(e)e)
      if(!inherits(pp,'error')) vals <- summarize_passage(pp) else available <- FALSE
    }
    rows[[i]] <- data.frame(season=target_season,origin_week=o,timing_available=available,
      m1_peak_mean=vals['mean'],m1_q05=vals['q05'],m1_q95=vals['q95'],
      m1_width=vals['width'],m1_p_passed=vals['p_passed'],gate_week=gate,
      outer_holdout=outer_holdout,stringsAsFactors=FALSE)
  }
  out<-do.call(rbind,rows);rownames(out)<-NULL
  saveRDS(out,cache_file)
  out
}

preds <- list(); feature_audit <- list()
for(outer in seasons){
  cat('outer',outer,'\n')
  # Strictly nested upstream features: test season excludes outer; each training
  # season excludes both outer and itself.
  feats <- do.call(rbind,lapply(seasons,function(s){
    if(s==outer || s %in% setdiff(seasons,outer)) make_features(outer,s)
  }))
  feature_audit[[outer]] <- feats
  dat <- merge(ledger,feats,by=c('season','origin_week'),all.x=TRUE,sort=FALSE)
  dat$timing_available[is.na(dat$timing_available)] <- FALSE
  dat$phase_weeks <- ifelse(dat$timing_available,dat$m1_peak_mean-(dat$origin_week+1),0)
  dat$p_passed_feature <- ifelse(dat$timing_available,dat$m1_p_passed,0)
  dat$width_feature <- ifelse(dat$timing_available,dat$m1_width,0)
  dat$horizon_f <- factor(paste0('h',dat$horizon),levels=c('h1','h2'))
  dat$offset_logit <- dat$logit_current
  tr <- dat[dat$season!=outer,]
  te <- dat[dat$season==outer,]

  b1 <- suppressWarnings(glm(
    cbind(y_target,N_target-y_target) ~ horizon_f + growth1 + growth2 + offset(offset_logit),
    data=tr,family=quasibinomial()
  ))
  tr$pred_b1 <- as.numeric(predict(b1,newdata=tr,type='response'))
  te$pred_b0 <- te$p_star
  te$pred_b1 <- as.numeric(predict(b1,newdata=te,type='response'))
  # B2 is a timing-only correction. Inactive rows are IDENTICALLY B1.
  te$pred_b2 <- te$pred_b1
  active_tr <- tr[tr$timing_available & is.finite(tr$phase_weeks) & is.finite(tr$p_passed_feature),]
  active_te <- which(te$timing_available & is.finite(te$phase_weeks) & is.finite(te$p_passed_feature))
  if(nrow(active_tr) >= 20 && length(unique(active_tr$season)) >= 3 && length(active_te)) {
    active_tr$b1_offset <- qlogis(pmin(pmax(active_tr$pred_b1,1e-6),1-1e-6))
    corr <- suppressWarnings(glm(
      cbind(y_target,N_target-y_target) ~ horizon_f + phase_weeks + p_passed_feature +
        offset(b1_offset), data=active_tr, family=quasibinomial()
    ))
    te_active <- te[active_te,]
    te_active$b1_offset <- qlogis(pmin(pmax(te_active$pred_b1,1e-6),1-1e-6))
    te$pred_b2[active_te] <- as.numeric(predict(corr,newdata=te_active,type='response'))
  }
  preds[[outer]] <- te
}
pred <- do.call(rbind,preds);rownames(pred)<-NULL
write.csv(pred,file.path(out_dir,'strict_nested_predictions.csv'),row.names=FALSE)
write.csv(do.call(rbind,feature_audit),file.path(out_dir,'strict_nested_upstream_feature_audit.csv'),row.names=FALSE)

for(m in c('b0','b1','b2')){
  p<-pmin(pmax(pred[[paste0('pred_',m)]],1e-8),1-1e-8)
  pred[[paste0('abs_',m)]]<-abs(p-pred$p_target)
  pred[[paste0('sq_',m)]]<-(p-pred$p_target)^2
  pred[[paste0('nll_',m)]]<--(pred$y_target*log(p)+(pred$N_target-pred$y_target)*log(1-p))/pred$N_target
}
per <- do.call(rbind,lapply(split(pred,list(pred$season,pred$horizon),drop=TRUE),function(z){
  data.frame(season=z$season[1],horizon=z$horizon[1],n=nrow(z),timing_availability=mean(z$timing_available),
    b0_mae_pp=100*mean(z$abs_b0),b1_mae_pp=100*mean(z$abs_b1),b2_mae_pp=100*mean(z$abs_b2),
    b0_nll=mean(z$nll_b0),b1_nll=mean(z$nll_b1),b2_nll=mean(z$nll_b2))
}))
per <- merge(per,truth[,c('season','peak_amplitude')],by='season',all.x=TRUE)
per$signal <- ifelse(per$peak_amplitude>.05,'epidemic_gt5pct','low_signal_le5pct')
write.csv(per,file.path(out_dir,'per_season_metrics.csv'),row.names=FALSE)

summary <- do.call(rbind,lapply(split(per,per$horizon),function(z)data.frame(
 horizon=z$horizon[1],n_seasons=nrow(z),mean_timing_availability=mean(z$timing_availability),
 b0_mae_pp=mean(z$b0_mae_pp),b1_mae_pp=mean(z$b1_mae_pp),b2_mae_pp=mean(z$b2_mae_pp),
 b2_vs_b1_mae_gain_pp=mean(z$b1_mae_pp-z$b2_mae_pp),
 b2_vs_b1_relative_mae_gain=1-mean(z$b2_mae_pp)/mean(z$b1_mae_pp),
 b1_nll=mean(z$b1_nll),b2_nll=mean(z$b2_nll),b2_vs_b1_nll_gain=mean(z$b1_nll-z$b2_nll),
 seasons_b2_better_mae=sum(z$b2_mae_pp<z$b1_mae_pp)
)))
write.csv(summary,file.path(out_dir,'summary.csv'),row.names=FALSE)
strat <- aggregate(cbind(b1_mae_pp,b2_mae_pp,b1_nll,b2_nll,timing_availability)~horizon+signal,per,mean)
write.csv(strat,file.path(out_dir,'signal_stratified_summary.csv'),row.names=FALSE)
cat('\nStrict nested B2 summary\n');print(summary,row.names=FALSE,digits=5)
cat('\nSignal strata\n');print(strat,row.names=FALSE,digits=5)
