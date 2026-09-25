source('PAGe/R/data_contract.R')

# Reuse the already generated strict upstream M1-B feature cache from
# run_m2_b_phase_nested_v1.R. If missing, run that script first.
ledger <- read.csv('artifacts/m2-v2-b-baselines-v1/candidate_independent_ledger.csv', stringsAsFactors=FALSE)
geom <- read.csv('artifacts/m2-v2-flu-ab-geometry-v1/type_geometry_k8.csv', stringsAsFactors=FALSE)
truth <- geom[geom$type=='B',c('season','peak_week_decimal','peak_amplitude')]
seasons <- sort(unique(ledger$season))
cache_dir <- 'artifacts/m2-v2-b-phase-nested-v1/feature_cache'
out_dir <- 'artifacts/m2-v2-b-phase-nested-selected-v1'
dir.create(out_dir,recursive=TRUE,showWarnings=FALSE)

fit_b1 <- function(tr){
  tr$horizon_f <- factor(paste0('h',tr$horizon),levels=c('h1','h2'))
  tr$offset_logit <- tr$logit_current
  suppressWarnings(glm(
    cbind(y_target,N_target-y_target) ~ horizon_f + growth1 + growth2 + offset(offset_logit),
    data=tr,family=quasibinomial()
  ))
}

prepare_features <- function(outer){
  feats <- do.call(rbind,lapply(seasons,function(s){
    f <- file.path(cache_dir,paste0('outer_',outer,'__target_',s,'.rds'))
    if(!file.exists(f)) stop('Missing strict upstream feature cache: ',f)
    readRDS(f)
  }))
  dat <- merge(ledger,feats,by=c('season','origin_week'),all.x=TRUE,sort=FALSE)
  dat$timing_available[is.na(dat$timing_available)] <- FALSE
  dat$phase_weeks <- ifelse(dat$timing_available,dat$m1_peak_mean-(dat$origin_week+1),0)
  dat$p_passed_feature <- ifelse(dat$timing_available,dat$m1_p_passed,0)
  dat$width_feature <- ifelse(dat$timing_available,dat$m1_width,0)
  dat$horizon_f <- factor(paste0('h',dat$horizon),levels=c('h1','h2'))
  dat$offset_logit <- dat$logit_current
  dat
}

fit_timing_corr <- function(tr,b1fit,h){
  z <- tr[tr$horizon==h,]
  z$pred_b1 <- as.numeric(predict(b1fit,newdata=z,type='response'))
  z <- z[z$timing_available & is.finite(z$phase_weeks) & is.finite(z$p_passed_feature),]
  if(nrow(z)<12 || length(unique(z$season))<3) return(NULL)
  z$b1_offset <- qlogis(pmin(pmax(z$pred_b1,1e-6),1-1e-6))
  suppressWarnings(glm(
    cbind(y_target,N_target-y_target) ~ phase_weeks + p_passed_feature + offset(b1_offset),
    data=z,family=quasibinomial()
  ))
}

predict_with_corr <- function(test,b1fit,corr,h){
  z <- test[test$horizon==h,]
  pred1 <- as.numeric(predict(b1fit,newdata=z,type='response'))
  pred2 <- pred1
  if(!is.null(corr)){
    ix <- which(z$timing_available & is.finite(z$phase_weeks) & is.finite(z$p_passed_feature))
    if(length(ix)){
      zz <- z[ix,]
      zz$b1_offset <- qlogis(pmin(pmax(pred1[ix],1e-6),1-1e-6))
      pred2[ix] <- as.numeric(predict(corr,newdata=zz,type='response'))
    }
  }
  list(data=z,pred_b1=pred1,pred_b2=pred2)
}

preds <- list(); selections <- list(); inner_scores_all <- list()
for(outer in seasons){
  cat('outer',outer,'\n')
  dat <- prepare_features(outer)
  tr_outer <- dat[dat$season!=outer,]
  te_outer <- dat[dat$season==outer,]
  train_seasons <- setdiff(seasons,outer)
  selected <- setNames(logical(2),c('1','2'))

  # Model choice is inner leave-one-season-out and uses no outer outcomes.
  for(h in 1:2){
    inner_rows <- list()
    for(v in train_seasons){
      tr <- tr_outer[tr_outer$season!=v,]
      va <- tr_outer[tr_outer$season==v,]
      b1 <- fit_b1(tr)
      corr <- fit_timing_corr(tr,b1,h)
      pr <- predict_with_corr(va,b1,corr,h)
      inner_rows[[v]] <- data.frame(
        outer=outer,validation=v,horizon=h,
        b1_mae_pp=100*mean(abs(pr$pred_b1-pr$data$p_target)),
        b2_mae_pp=100*mean(abs(pr$pred_b2-pr$data$p_target)),
        timing_availability=mean(pr$data$timing_available)
      )
    }
    ir <- do.call(rbind,inner_rows); rownames(ir)<-NULL
    inner_scores_all[[paste(outer,h)]] <- ir
    selected[as.character(h)] <- mean(ir$b2_mae_pp) < mean(ir$b1_mae_pp)
    selections[[paste(outer,h)]] <- data.frame(
      outer=outer,horizon=h,select_timing=selected[as.character(h)],
      inner_b1_mae_pp=mean(ir$b1_mae_pp),inner_b2_mae_pp=mean(ir$b2_mae_pp),
      inner_gain_pp=mean(ir$b1_mae_pp-ir$b2_mae_pp)
    )
  }

  b1_final <- fit_b1(tr_outer)
  outer_parts <- list()
  for(h in 1:2){
    corr <- if(selected[as.character(h)]) fit_timing_corr(tr_outer,b1_final,h) else NULL
    pr <- predict_with_corr(te_outer,b1_final,corr,h)
    z <- pr$data
    z$pred_b0 <- z$p_star
    z$pred_b1 <- pr$pred_b1
    z$pred_b2_selected <- pr$pred_b2
    z$timing_selected <- selected[as.character(h)]
    outer_parts[[as.character(h)]] <- z
  }
  preds[[outer]] <- do.call(rbind,outer_parts)
}

pred <- do.call(rbind,preds); rownames(pred)<-NULL
sel <- do.call(rbind,selections); rownames(sel)<-NULL
inner <- do.call(rbind,inner_scores_all); rownames(inner)<-NULL
write.csv(pred,file.path(out_dir,'strict_nested_selected_predictions.csv'),row.names=FALSE)
write.csv(sel,file.path(out_dir,'outer_selection_decisions.csv'),row.names=FALSE)
write.csv(inner,file.path(out_dir,'inner_selection_scores.csv'),row.names=FALSE)

for(m in c('b0','b1','b2_selected')){
  p<-pmin(pmax(pred[[paste0('pred_',m)]],1e-8),1-1e-8)
  pred[[paste0('abs_',m)]]<-abs(p-pred$p_target)
  pred[[paste0('nll_',m)]]<--(pred$y_target*log(p)+(pred$N_target-pred$y_target)*log(1-p))/pred$N_target
}
per <- do.call(rbind,lapply(split(pred,list(pred$season,pred$horizon),drop=TRUE),function(z){
  data.frame(season=z$season[1],horizon=z$horizon[1],n=nrow(z),timing_availability=mean(z$timing_available),
    timing_selected=z$timing_selected[1],
    b0_mae_pp=100*mean(z$abs_b0),b1_mae_pp=100*mean(z$abs_b1),b2_mae_pp=100*mean(z$abs_b2_selected),
    b1_nll=mean(z$nll_b1),b2_nll=mean(z$nll_b2_selected))
}))
per <- merge(per,truth[,c('season','peak_amplitude')],by='season',all.x=TRUE)
per$signal <- ifelse(per$peak_amplitude>.05,'epidemic_gt5pct','low_signal_le5pct')
write.csv(per,file.path(out_dir,'per_season_metrics.csv'),row.names=FALSE)
summary <- do.call(rbind,lapply(split(per,per$horizon),function(z)data.frame(
  horizon=z$horizon[1],n_seasons=nrow(z),timing_selected_folds=sum(z$timing_selected),
  b0_mae_pp=mean(z$b0_mae_pp),b1_mae_pp=mean(z$b1_mae_pp),b2_mae_pp=mean(z$b2_mae_pp),
  b2_vs_b1_gain_pp=mean(z$b1_mae_pp-z$b2_mae_pp),
  b2_vs_b1_relative_gain=1-mean(z$b2_mae_pp)/mean(z$b1_mae_pp),
  b1_nll=mean(z$b1_nll),b2_nll=mean(z$b2_nll),b2_vs_b1_nll_gain=mean(z$b1_nll-z$b2_nll),
  seasons_b2_better=sum(z$b2_mae_pp<z$b1_mae_pp)
)))
write.csv(summary,file.path(out_dir,'summary.csv'),row.names=FALSE)
strat <- aggregate(cbind(b1_mae_pp,b2_mae_pp,b1_nll,b2_nll,timing_availability)~horizon+signal,per,mean)
write.csv(strat,file.path(out_dir,'signal_stratified_summary.csv'),row.names=FALSE)
cat('\nNested selected B2 summary\n');print(summary,row.names=FALSE,digits=5)
cat('\nSelection decisions\n');print(sel,row.names=FALSE,digits=4)
cat('\nSignal strata\n');print(strat,row.names=FALSE,digits=5)
