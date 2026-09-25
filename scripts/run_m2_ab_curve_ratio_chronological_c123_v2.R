#!/usr/bin/env Rscript

# Parent-reviewed prior-seasons-only chronological replay for M2-v2 C1/C2/C3.
# No exchangeable/future-season upstream timing artifact is consumed.

source('PAGe/R/data_contract.R')
source('PAGe/R/stage_contracts.R')
source('PAGe/R/m0_training.R')
source('PAGe/R/timing_pipeline_v2.R')
source('PAGe/R/expert_timing_annotations.R')
source('PAGe/R/retrospective_peak_truth.R')
source('PAGe/R/m1_v2.R')
source('PAGe/R/pipeline_training.R')
source('PAGe/R/pipeline_runtime.R')

`%||%` <- function(x,y) if(!is.null(x)) x else y

input_dir <- 'artifacts/m2-v2-flu-ab-geometry-v1'
out_dir <- 'artifacts/m2-v2-ab-curve-ratio-chronological-c123-v2'
dir.create(out_dir, recursive=TRUE, showWarnings=FALSE)
dir.create(file.path(out_dir,'cache'), recursive=TRUE, showWarnings=FALSE)
dir.create(file.path(out_dir,'cache','a_prior_m0'), recursive=TRUE, showWarnings=FALSE)
dir.create(file.path(out_dir,'cache','a_target_m0'), recursive=TRUE, showWarnings=FALSE)
dir.create(file.path(out_dir,'cache','a_stage'), recursive=TRUE, showWarnings=FALSE)

ab <- read.csv(file.path(input_dir,'flu_ab_weekly_v1.csv'), stringsAsFactors=FALSE)
long <- read.csv(file.path(input_dir,'flu_ab_long_v1.csv'), stringsAsFactors=FALSE)
shape <- read.csv(file.path(input_dir,'peak_aligned_normalized_shape_grid.csv'), stringsAsFactors=FALSE)
geom <- read.csv(file.path(input_dir,'type_geometry_k8.csv'), stringsAsFactors=FALSE)
campaign <- readRDS('artifacts/expert-ignition-annotation-v2-pass1/campaign_data.rds')
ignition <- read.csv('artifacts/expert-ignition-annotation-v2-pass1/expert_ignition_labels_v2_pass1.csv', stringsAsFactors=FALSE)
peak_truth_A <- read.csv('artifacts/expert-ignition-annotation-v2-pass1/retrospective_peak_truth_v1.csv', stringsAsFactors=FALSE)
m0_grid <- as.data.frame(.default_m0_grid(), stringsAsFactors=FALSE)

for(x in c('ab','long','shape','geom','campaign','ignition','peak_truth_A')) {
  obj <- get(x); if('season' %in% names(obj)) obj$season <- as.character(obj$season); assign(x,obj)
}
seasons <- sort(unique(as.character(ab$season)))
types <- c('A','B'); families <- c('C1','C2','C3')
min_prior_baseline <- 3L
min_prior_family <- 4L
# Governed A stage needs prior-only inner M0 LOSO. Empirically, 3-4 prior
# seasons are rank-deficient; 5 is the first supported history length.
min_prior_governed_A_timing <- 5L

logit <- function(p) qlogis(pmin(pmax(p,1e-6),1-1e-6))
stab <- function(y,N,c=.5) (y+c)/(N+2*c)

# ---------- candidate-independent ledger ----------
make_type_ledger <- function(tp){
  ycol<-paste0('y_',tp);ncol<-paste0('N_',tp);pcol<-paste0('p_',tp);rows<-list()
  for(s in seasons){
    z<-ab[ab$season==s,];z<-z[order(z$weekF),]
    y<-z[[ycol]];N<-z[[ncol]];p<-z[[pcol]];ps<-stab(y,N);l<-logit(ps)
    g1<-c(NA,diff(l));g2<-c(NA,NA,(l[3:length(l)]-l[1:(length(l)-2)])/2)
    for(i in seq_len(nrow(z))){
      if(z$weekF[i]<13 || i<3) next
      for(h in 1:2){
        j<-i+h;if(j>nrow(z)||z$weekF[j]!=z$weekF[i]+h)next
        rows[[length(rows)+1L]]<-data.frame(
          season=s,type=tp,origin_week=z$weekF[i],target_week=z$weekF[j],horizon=h,
          y_target=y[j],N_target=N[j],p_target=p[j],p_star=ps[i],
          logit_current=l[i],growth1=g1[i],growth2=g2[i],
          denominator_regime=z$denominator_regime[i],stringsAsFactors=FALSE)
      }
    }
  }
  do.call(rbind,rows)
}
ledger<-rbind(make_type_ledger('A'),make_type_ledger('B'));rownames(ledger)<-NULL
ledger$horizon_f<-factor(paste0('h',ledger$horizon),levels=c('h1','h2'))
write.csv(ledger,file.path(out_dir,'candidate_independent_ledger.csv'),row.names=FALSE)

fit_state_baseline <- function(tr){
  tr$horizon_f<-factor(paste0('h',tr$horizon),levels=c('h1','h2'));tr$offset_logit<-tr$logit_current
  suppressWarnings(glm(cbind(y_target,N_target-y_target)~horizon_f+growth1+growth2+offset(offset_logit),data=tr,family=quasibinomial()))
}

# ---------- C1/C2/C3 shape family ----------
one_lr<-function(z,tau,h){
  cur<-approx(z$tau,z$p_norm,xout=tau,rule=1)$y;fut<-approx(z$tau,z$p_norm,xout=tau+h,rule=1)$y
  if(!is.finite(cur)||!is.finite(fut))return(NA_real_)
  log(pmax(fut,.01)/pmax(cur,.01))
}
family_lr<-function(train,tp,tau,h,fam){
  pool<-shape[shape$season%in%train,];typed<-pool[pool$type==tp,]
  med<-function(z){
    ids<-unique(paste(z$season,z$type,sep='|'))
    vals<-vapply(ids,function(id)one_lr(z[paste(z$season,z$type,sep='|')==id,],tau,h),numeric(1))
    vals<-vals[is.finite(vals)];if(length(vals))median(vals) else NA_real_
  }
  lp<-med(pool);lt<-med(typed)
  switch(fam,C1=lp,C2=.5*lp+.5*lt,C3=lt)
}
blend_shape<-function(base,current,lr,eta=.5){
  if(!is.finite(lr))return(base)
  ps<-pmin(pmax(current*exp(lr),1e-6),1-1e-6)
  plogis((1-eta)*logit(base)+eta*logit(ps))
}

# Precompute observed shape log-ratios on tau grid for vectorized inner LOPO.
tau_grid <- seq(-8, 8, by=0.25)
lr_cache <- list()
for(s in seasons) for(tp in types) {
  z <- shape[shape$season==s & shape$type==tp,]
  for(h in 1:2) {
    key <- paste(s, tp, h, sep='|')
    lr_cache[[key]] <- vapply(tau_grid, function(tau) one_lr(z, tau, h), numeric(1))
  }
}

select_family_prior_only<-function(prior){
  if(length(prior)<min_prior_family) return(list(selected=NA_character_,C1=NA,C2=NA,C3=NA,reason='fewer_than_four_prior_seasons'))
  scores<-setNames(rep(NA_real_,3),families)
  for(fam in families){
    cells<-numeric()
    for(v in prior){
      train<-setdiff(prior,v)
      if(length(train)<min_prior_baseline) next
      for(tp in types) for(h in 1:2){
        idx <- which(tau_grid >= -8 & tau_grid <= (8 - h))
        taus <- tau_grid[idx]
        actual <- lr_cache[[paste(v, tp, h, sep='|')]][idx]
        pool_keys <- as.vector(outer(train, types, function(s,t) paste(s, t, h, sep='|')))
        typed_keys <- paste(train, tp, h, sep='|')
        pool_mat <- do.call(rbind, lr_cache[pool_keys])
        typed_mat <- do.call(rbind, lr_cache[typed_keys])
        lp <- apply(pool_mat[, idx, drop=FALSE], 2, function(x) { x <- x[is.finite(x)]; if(length(x)) median(x) else NA_real_ })
        lt <- apply(typed_mat[, idx, drop=FALSE], 2, function(x) { x <- x[is.finite(x)]; if(length(x)) median(x) else NA_real_ })
        q <- switch(fam, C1=lp, C2=.5*lp+.5*lt, C3=lt)
        e <- q - actual
        e <- e[is.finite(e)]
        if(length(e)) cells <- c(cells, sqrt(mean(e^2)))
      }
    }
    if(length(cells))scores[fam]<-mean(cells)
  }
  if(!all(is.finite(scores))) return(list(selected=NA_character_,C1=scores['C1'],C2=scores['C2'],C3=scores['C3'],reason='inner_shape_scores_unavailable'))
  # deterministic complexity tie-break C1 < C2 < C3
  best<-families[order(scores,seq_along(families))[1]]
  list(selected=best,C1=scores['C1'],C2=scores['C2'],C3=scores['C3'],reason='prior_only_inner_lopo')
}

# ---------- governed A timing: prior-only M0 -> M1 ----------
make_a_m0_data<-function(season_set){
  d<-campaign[campaign$season%in%season_set,,drop=FALSE]
  tt<-data.frame(season=season_set,ignition_target_weekF=ignition$ignition_week_decimal[match(season_set,ignition$season)],stringsAsFactors=FALSE)
  d<-merge(d,tt,by='season',all.x=TRUE,sort=FALSE);d$phase<-as.integer(d$weekF>=ceiling(d$ignition_target_weekF))
  list(data=d,truth=tt)
}

fit_prior_a_m0_loso<-function(prior){
  key<-paste(gsub('-','_',prior),collapse='__');f<-file.path(out_dir,'cache','a_prior_m0',paste0(key,'.rds'))
  if(file.exists(f))return(readRDS(f))
  md<-make_a_m0_data(prior)
  ans<-tryCatch(loso_M0v2(md$data,m0_grid,timing_truth=md$truth,timing_mode='fractional',selection_policy='legacy',verbose=FALSE,
    tune_args=list(miss_penalty=0,lambda=20,kappa=0,gamma=25,gamma_late=0,iWeek=TRUE,ncores=4L,verbose=FALSE,progress_every=200L)),error=function(e)e)
  saveRDS(ans,f);ans
}

# Fit exactly the target M0 fold from prior seasons only. Target truth/phase is
# present only so the detector can emit retrospective evaluation columns; it is
# never used in classifier fitting or detector threshold tuning.
fit_target_a_m0<-function(prior,target){
  key<-paste(c(gsub('-','_',prior),paste0('target_',gsub('-','_',target))),collapse='__');f<-file.path(out_dir,'cache','a_target_m0',paste0(key,'.rds'))
  if(file.exists(f))return(readRDS(f))
  md_train<-make_a_m0_data(prior);md_target<-make_a_m0_data(target)
  fit_args<-list(fit_base=TRUE,fit_slope=FALSE,fit_fs=FALSE,event_k=1L,lead=1L,A_pre=6L,B_post=6L,k_week=6L,k_p=8L,k_fs=4L,select=FALSE,verbose=FALSE)
  fit_call<-c(list(dat=md_train$data,season_col='season',week_col='weekF',phase_col='phase',p_col='p',timing_truth=md_train$truth),fit_args)
  ans<-tryCatch({
    ign_fit<-do.call(fitIgnition,fit_call)
    gam_base<-ign_fit$fits$base$gam
    target_scored<-md_target$data
    target_scored$p_cls_p<-as.numeric(predict(gam_base,newdata=target_scored,type='response'))
    target_scored$p_cls_base_pop<-target_scored$p_cls_p
    tuned<-tuneIgnitionGrid_M0v2(
      ign_fit=as.data.frame(ign_fit$data),grid=m0_grid,score_col='p_cls_p',week_col='weekF',season_col='season',phase_col='phase',
      truth_col='iWeek',exSeason=NULL,timing_mode='fractional',miss_penalty=0,lambda=20,kappa=0,gamma=25,gamma_late=0,iWeek=TRUE,ncores=4L,verbose=FALSE,progress_every=200L)
    r<-tuned$results;o<-with(r,order(n_over2,n_late_over2,max_abs,n_miss,score));best<-r[o[1],,drop=FALSE]
    pn<-c('cls_thr','p_thr','prev_thr','n_consec','L','eps','K_sum','p_sum_thr','N_req','w_min','w_max','use_cls')
    params<-as.list(best[,intersect(pn,names(best)),drop=FALSE]);params<-lapply(params,function(v)v[[1L]])
    det<-detectIgnitionBySeason_M0v2_timing(ign_fit=target_scored,params=params,score_col='p_cls_p',week_col='weekF',season_col='season',phase_col='phase',verbose=FALSE,iWeek=TRUE,copy_data=TRUE)
    comp<-det$compare[det$compare$season==target,,drop=FALSE]
    if('iWeek_hatF'%in%names(det$by_season))comp$iWeek_hatF<-det$by_season$iWeek_hatF[match(target,det$by_season$season)]
    list(compare=comp,best_params=params,tuning_best=best)
  },error=function(e)e)
  saveRDS(ans,f);ans
}

build_prior_a_stage<-function(prior){
  key<-paste(gsub('-','_',prior),collapse='__');f<-file.path(out_dir,'cache','a_stage',paste0(key,'.rds'))
  if(file.exists(f))return(readRDS(f))
  ans<-tryCatch({
    lo<-fit_prior_a_m0_loso(prior);if(inherits(lo,'error'))stop(conditionMessage(lo))
    acts<-m1_v2_activation_table_from_m0_loso(lo)
    build_m1_v2_timing(campaign[campaign$season%in%prior,,drop=FALSE],
      peak_truth_A[peak_truth_A$season%in%prior,c('season','peak_week_decimal'),drop=FALSE],acts,
      k=8L,grid_step=.01,tau_step=.1,calibration_origins=4L,calibration_candidate_step=.2,passage_candidate_step=.2)
  },error=function(e)e)
  saveRDS(ans,f);ans
}

make_a_timing<-function(prior,target,origins){
  base<-data.frame(season=target,type='A',origin_week=origins,timing_available=FALSE,timing_peak=NA_real_,timing_width=NA_real_,timing_reason='governed_a_timing_unavailable',gate_week=NA_real_,stringsAsFactors=FALSE)
  if(length(prior)<min_prior_governed_A_timing){base$timing_reason<-'fewer_than_five_prior_seasons_for_governed_a_timing';return(list(rows=base,stage_status=base$timing_reason[1],activation=NA_real_,calibration=NA_real_))}
  stage<-build_prior_a_stage(prior);if(inherits(stage,'error')){base$timing_reason<-paste0('a_stage_error:',conditionMessage(stage));return(list(rows=base,stage_status=base$timing_reason[1],activation=NA_real_,calibration=NA_real_))}
  m0<-fit_target_a_m0(prior,target);if(inherits(m0,'error')){base$timing_reason<-paste0('a_target_m0_error:',conditionMessage(m0));return(list(rows=base,stage_status=base$timing_reason[1],activation=NA_real_,calibration=stage$calibrator$offset_week))}
  mr<-m0$compare
  if(nrow(mr)!=1L||!is.finite(mr$iWeek_hat)||!is.finite(mr$iWeek_hatF)){base$timing_reason<-'a_target_m0_unavailable';return(list(rows=base,stage_status=base$timing_reason[1],activation=NA_real_,calibration=stage$calibrator$offset_week))}
  rt<-tryCatch(run_m1_v2_timing(list(m1_v2=stage),campaign[campaign$season==target,,drop=FALSE],list(iWeek_locked=as.integer(mr$iWeek_hat),iWeek_lockedF=mr$iWeek_hatF),verbose=FALSE),error=function(e)e)
  if(inherits(rt,'error')){base$timing_reason<-paste0('a_runtime_error:',conditionMessage(rt));return(list(rows=base,stage_status=base$timing_reason[1],activation=mr$iWeek_hatF,calibration=stage$calibrator$offset_week))}
  z<-rt$timing_df
  rr<-data.frame(season=target,type='A',origin_week=z$origin_week,timing_available=is.finite(z$calibrated_peak_mean),
    timing_peak=ifelse(z$peak_passed & is.finite(z$locked_peak_week),z$locked_peak_week,z$calibrated_peak_mean),
    timing_width=z$interval_width_90,timing_reason=ifelse(is.finite(z$calibrated_peak_mean),'available','runtime_unavailable'),gate_week=NA_real_,stringsAsFactors=FALSE)
  out<-merge(base[,c('season','type','origin_week','gate_week')],rr,by=c('season','type','origin_week','gate_week'),all.x=TRUE,sort=FALSE)
  out$timing_available[is.na(out$timing_available)]<-FALSE;out$timing_reason[is.na(out$timing_reason)]<-'pre_activation'
  list(rows=out,stage_status='available',activation=mr$iWeek_hatF,calibration=stage$calibrator$offset_week)
}

# ---------- B prior-only soft timing ----------
first_b_gate_week<-function(target,origin){
  z<-long[long$season==target & long$type=='B' & long$weekF<=origin,];z<-z[order(z$weekF),]
  if(!nrow(z))return(NA_real_)
  sum4<-as.numeric(stats::filter(z$y,rep(1,4),sides=1))
  maxp4<-vapply(seq_len(nrow(z)),function(i)max(z$p[max(1,i-3):i],na.rm=TRUE),numeric(1))
  ok<-which(z$weekF>=18 & is.finite(sum4) & sum4>=40 & maxp4>=.05)
  if(length(ok))z$weekF[min(ok)] else NA_real_
}
make_b_timing<-function(prior,target,origins){
  base<-data.frame(season=target,type='B',origin_week=origins,timing_available=FALSE,timing_peak=NA_real_,timing_width=NA_real_,timing_reason='b_gate_not_met',gate_week=NA_real_,stringsAsFactors=FALSE)
  train<-long[long$season%in%prior & long$type=='B',c('season','weekF','y','N','p')]
  tt<-geom[geom$type=='B' & geom$season%in%prior,c('season','peak_week_decimal')]
  lib<-tryCatch(fit_m1_v2_library(train,tt,k=8L,grid_step=.01,tau_step=.1,amplitude_grid=seq(.005,.25,by=.005)),error=function(e)e)
  if(inherits(lib,'error')){base$timing_reason<-paste0('b_library_error:',conditionMessage(lib));return(base)}
  zfull<-long[long$season==target & long$type=='B',c('season','weekF','y','N','p')]
  for(i in seq_along(origins)){
    o<-origins[i];gate<-first_b_gate_week(target,o);base$gate_week[i]<-gate
    if(!is.finite(gate))next
    zprefix<-zfull[zfull$weekF<=o,,drop=FALSE]
    pp<-tryCatch(m1_v2_passage_posterior(lib,zprefix,activation_week=gate,origin_week=o,candidate_step=.2,max_future_weeks=12),error=function(e)e)
    if(inherits(pp,'error')){base$timing_reason[i]<-paste0('b_posterior_error:',conditionMessage(pp));next}
    post<-attr(pp,'posterior');w<-post$probability;T<-post$peak_week_decimal;cdf<-cumsum(w)
    base$timing_available[i]<-TRUE;base$timing_peak[i]<-sum(T*w);base$timing_width[i]<-T[which(cdf>=.95)[1]]-T[which(cdf>=.05)[1]];base$timing_reason[i]<-'available'
  }
  base
}

# ---------- chronological outer replay ----------
pred_rows<-list();family_rows<-list();availability_rows<-list();provenance_rows<-list()
for(ixs in seq_along(seasons)){
  target<-seasons[ixs];prior<-if(ixs>1)seasons[seq_len(ixs-1)] else character()
  message('chronological target=',target,' prior=',length(prior))
  if(length(prior)<min_prior_baseline){
    availability_rows[[target]]<-data.frame(season=target,n_prior=length(prior),learned_forecast_available=FALSE,A_timing_availability=NA_real_,B_timing_availability=NA_real_,family_available=FALSE,reason='fewer_than_three_prior_seasons',stringsAsFactors=FALSE)
    family_rows[[target]]<-data.frame(season=target,n_prior=length(prior),selected_family=NA_character_,C1_inner_rmse=NA_real_,C2_inner_rmse=NA_real_,C3_inner_rmse=NA_real_,reason='fewer_than_three_prior_seasons',stringsAsFactors=FALSE)
    provenance_rows[[target]]<-data.frame(season=target,prior_seasons=paste(prior,collapse=';'),selected_family=NA_character_,
      A_stage_status='fewer_than_three_prior_seasons',A_activation_week=NA_real_,A_calibration_offset=NA_real_,
      B_gate_policy='week>=18;trailing4_y>=40;trailing4_max_p>=0.05',stringsAsFactors=FALSE)
    next
  }
  fam<-select_family_prior_only(prior)
  family_rows[[target]]<-data.frame(season=target,n_prior=length(prior),selected_family=fam$selected,C1_inner_rmse=fam$C1,C2_inner_rmse=fam$C2,C3_inner_rmse=fam$C3,reason=fam$reason,stringsAsFactors=FALSE)

  ledA<-ledger[ledger$season==target & ledger$type=='A',];origA<-sort(unique(ledA$origin_week));At<-make_a_timing(prior,target,origA)
  ledB<-ledger[ledger$season==target & ledger$type=='B',];origB<-sort(unique(ledB$origin_week));Bt<-make_b_timing(prior,target,origB)

  for(tp in types){
    tr<-ledger[ledger$season%in%prior & ledger$type==tp,];te<-ledger[ledger$season==target & ledger$type==tp,]
    fit<-fit_state_baseline(tr);te$offset_logit<-te$logit_current;te$pred_base<-as.numeric(predict(fit,newdata=te,type='response'))
    tm<-if(tp=='A')At$rows else Bt
    te<-merge(te,tm,by=c('season','type','origin_week'),all.x=TRUE,sort=FALSE);te$timing_available[is.na(te$timing_available)]<-FALSE
    # `gate_week` is B-specific operational provenance. A carries an NA placeholder.
    if(!'gate_week' %in% names(te)) te$gate_week <- NA_real_
    for(f in families)te[[paste0('pred_',f)]]<-te$pred_base
    if(!is.na(fam$selected)){
      for(i in seq_len(nrow(te))){
        use<-isTRUE(te$timing_available[i]) && is.finite(te$timing_peak[i]) && !(tp=='B' && te$horizon[i]==1)
        if(!use)next
        tau<-te$origin_week[i]-te$timing_peak[i]
        for(f in families){lr<-family_lr(prior,tp,tau,te$horizon[i],f);te[[paste0('pred_',f)]][i]<-blend_shape(te$pred_base[i],te$p_star[i],lr,.5)}
      }
    }
    te$selected_family<-fam$selected;te$pred_selected<-te$pred_base
    if(!is.na(fam$selected))te$pred_selected<-te[[paste0('pred_',fam$selected)]]
    # hard fallback identities
    fallback<-!te$timing_available | (tp=='B' & te$horizon==1) | is.na(fam$selected)
    te$pred_selected[fallback]<-te$pred_base[fallback]
    te$prior_seasons<-paste(prior,collapse=';')
    pred_rows[[paste(target,tp,sep='|')]]<-te
  }
  availability_rows[[target]]<-data.frame(season=target,n_prior=length(prior),learned_forecast_available=TRUE,
    A_timing_availability=mean(At$rows$timing_available),B_timing_availability=mean(Bt$timing_available),family_available=!is.na(fam$selected),reason='available_with_explicit_fallbacks',stringsAsFactors=FALSE)
  provenance_rows[[target]]<-data.frame(season=target,prior_seasons=paste(prior,collapse=';'),selected_family=fam$selected,
    A_stage_status=At$stage_status,A_activation_week=At$activation,A_calibration_offset=At$calibration,
    B_gate_policy='week>=18;trailing4_y>=40;trailing4_max_p>=0.05',stringsAsFactors=FALSE)
}

pred<-do.call(rbind,pred_rows);rownames(pred)<-NULL
for(m in c('base','C1','C2','C3','selected')){
  p<-pmin(pmax(pred[[paste0('pred_',m)]],1e-8),1-1e-8);pred[[paste0('abs_',m)]]<-abs(p-pred$p_target);pred[[paste0('sq_',m)]]<-(p-pred$p_target)^2
  pred[[paste0('err_',m)]]<-p-pred$p_target;pred[[paste0('nll_',m)]]<--(pred$y_target*log(p)+(pred$N_target-pred$y_target)*log(1-p))/pred$N_target
}
write.csv(pred,file.path(out_dir,'predictions.csv'),row.names=FALSE)

per<-do.call(rbind,lapply(split(pred,list(pred$season,pred$type,pred$horizon),drop=TRUE),function(z){
  data.frame(season=z$season[1],type=z$type[1],horizon=z$horizon[1],selected_family=z$selected_family[1],n=nrow(z),timing_availability=mean(z$timing_available),
    base_mae_pp=100*mean(z$abs_base),selected_mae_pp=100*mean(z$abs_selected),base_rmse_pp=100*sqrt(mean(z$sq_base)),selected_rmse_pp=100*sqrt(mean(z$sq_selected)),
    base_bias_pp=100*mean(z$err_base),selected_bias_pp=100*mean(z$err_selected),base_nll=mean(z$nll_base),selected_nll=mean(z$nll_selected),stringsAsFactors=FALSE)
}))
rownames(per)<-NULL;write.csv(per,file.path(out_dir,'per_season_metrics.csv'),row.names=FALSE)
summary<-do.call(rbind,lapply(split(per,list(per$type,per$horizon),drop=TRUE),function(z)data.frame(
  type=z$type[1],horizon=z$horizon[1],n_seasons=nrow(z),base_mae_pp=mean(z$base_mae_pp),selected_mae_pp=mean(z$selected_mae_pp),relative_mae_gain=1-mean(z$selected_mae_pp)/mean(z$base_mae_pp),
  base_rmse_pp=mean(z$base_rmse_pp),selected_rmse_pp=mean(z$selected_rmse_pp),base_bias_pp=mean(z$base_bias_pp),selected_bias_pp=mean(z$selected_bias_pp),
  base_nll=mean(z$base_nll),selected_nll=mean(z$selected_nll),seasons_selected_better=sum(z$selected_mae_pp<z$base_mae_pp),seasons_selected_worse=sum(z$selected_mae_pp>z$base_mae_pp),stringsAsFactors=FALSE)))
rownames(summary)<-NULL;write.csv(summary,file.path(out_dir,'summary.csv'),row.names=FALSE)

# Fixed-C2 research-family evidence. Runtime research packaging freezes C2 and
# does not carry the C1/C2/C3 selector, so report that exact policy separately.
pred$pred_fixed_c2 <- pred$pred_C2
fixed_c2_fallback <- !pred$timing_available | (pred$type=='B' & pred$horizon==1) | is.na(pred$selected_family)
pred$pred_fixed_c2[fixed_c2_fallback] <- pred$pred_base[fixed_c2_fallback]
p_fixed <- pmin(pmax(pred$pred_fixed_c2,1e-8),1-1e-8)
pred$fixed_c2_abs <- abs(p_fixed-pred$p_target)
pred$fixed_c2_sq <- (p_fixed-pred$p_target)^2
pred$fixed_c2_err <- p_fixed-pred$p_target
pred$fixed_c2_nll <- -(pred$y_target*log(p_fixed)+(pred$N_target-pred$y_target)*log(1-p_fixed))/pred$N_target
write.csv(pred,file.path(out_dir,'fixed_c2_predictions.csv'),row.names=FALSE)
fixed_c2_per <- do.call(rbind,lapply(split(pred,list(pred$season,pred$type,pred$horizon),drop=TRUE),function(z){
  data.frame(season=z$season[1],type=z$type[1],horizon=z$horizon[1],n=nrow(z),timing_availability=mean(z$timing_available),
    base_mae_pp=100*mean(z$abs_base),fixed_c2_mae_pp=100*mean(z$fixed_c2_abs),
    base_rmse_pp=100*sqrt(mean(z$sq_base)),fixed_c2_rmse_pp=100*sqrt(mean(z$fixed_c2_sq)),
    base_bias_pp=100*mean(z$err_base),fixed_c2_bias_pp=100*mean(z$fixed_c2_err),
    base_nll=mean(z$nll_base),fixed_c2_nll=mean(z$fixed_c2_nll),stringsAsFactors=FALSE)
}))
rownames(fixed_c2_per)<-NULL
write.csv(fixed_c2_per,file.path(out_dir,'fixed_c2_per_season_metrics.csv'),row.names=FALSE)
fixed_c2_summary <- do.call(rbind,lapply(split(fixed_c2_per,list(fixed_c2_per$type,fixed_c2_per$horizon),drop=TRUE),function(z)data.frame(
  type=z$type[1],horizon=z$horizon[1],n_seasons=nrow(z),
  base_mae_pp=mean(z$base_mae_pp),fixed_c2_mae_pp=mean(z$fixed_c2_mae_pp),relative_mae_gain=1-mean(z$fixed_c2_mae_pp)/mean(z$base_mae_pp),
  base_rmse_pp=mean(z$base_rmse_pp),fixed_c2_rmse_pp=mean(z$fixed_c2_rmse_pp),
  base_bias_pp=mean(z$base_bias_pp),fixed_c2_bias_pp=mean(z$fixed_c2_bias_pp),
  base_nll=mean(z$base_nll),fixed_c2_nll=mean(z$fixed_c2_nll),
  seasons_c2_better=sum(z$fixed_c2_mae_pp<z$base_mae_pp),seasons_c2_worse=sum(z$fixed_c2_mae_pp>z$base_mae_pp),stringsAsFactors=FALSE)))
rownames(fixed_c2_summary)<-NULL
write.csv(fixed_c2_summary,file.path(out_dir,'fixed_c2_summary.csv'),row.names=FALSE)
active_fixed <- pred$timing_available & !is.na(pred$selected_family) & !(pred$type=='B' & pred$horizon==1)
fixed_c2_active_summary <- do.call(rbind,lapply(split(pred[active_fixed,],list(pred$type[active_fixed],pred$horizon[active_fixed]),drop=TRUE),function(z){
  by_season <- do.call(rbind,lapply(split(z,z$season),function(q)data.frame(
    season=q$season[1],n=nrow(q),base_mae_pp=100*mean(q$abs_base),fixed_c2_mae_pp=100*mean(q$fixed_c2_abs))))
  data.frame(type=z$type[1],horizon=z$horizon[1],n_seasons=nrow(by_season),n_rows=sum(by_season$n),
    base_mae_pp=mean(by_season$base_mae_pp),fixed_c2_mae_pp=mean(by_season$fixed_c2_mae_pp),
    relative_mae_gain=1-mean(by_season$fixed_c2_mae_pp)/mean(by_season$base_mae_pp),
    seasons_c2_better=sum(by_season$fixed_c2_mae_pp<by_season$base_mae_pp),
    seasons_c2_worse=sum(by_season$fixed_c2_mae_pp>by_season$base_mae_pp),stringsAsFactors=FALSE)
}))
rownames(fixed_c2_active_summary)<-NULL
write.csv(fixed_c2_active_summary,file.path(out_dir,'fixed_c2_active_summary.csv'),row.names=FALSE)
if(any(abs(pred$pred_fixed_c2[pred$type=='B' & pred$horizon==1]-pred$pred_base[pred$type=='B' & pred$horizon==1])>1e-12))stop('Fixed C2 B +1 fallback identity violated.')
if(any(abs(pred$pred_fixed_c2[!pred$timing_available]-pred$pred_base[!pred$timing_available])>1e-12))stop('Fixed C2 timing-unavailable fallback identity violated.')

family_df<-if(length(family_rows))do.call(rbind,family_rows) else data.frame();write.csv(family_df,file.path(out_dir,'family_selection.csv'),row.names=FALSE)
avail_df<-do.call(rbind,availability_rows);rownames(avail_df)<-NULL;write.csv(avail_df,file.path(out_dir,'availability.csv'),row.names=FALSE)
prov_df<-if(length(provenance_rows))do.call(rbind,provenance_rows) else data.frame();write.csv(prov_df,file.path(out_dir,'provenance.csv'),row.names=FALSE)

# paired differences and hard fallback assertions
paired<-per;paired$mae_diff_pp<-paired$selected_mae_pp-paired$base_mae_pp;paired$rmse_diff_pp<-paired$selected_rmse_pp-paired$base_rmse_pp
write.csv(paired,file.path(out_dir,'paired_differences.csv'),row.names=FALSE)
if(any(abs(pred$pred_selected[pred$type=='B' & pred$horizon==1]-pred$pred_base[pred$type=='B' & pred$horizon==1])>1e-12))stop('B +1 fallback identity violated.')
if(any(abs(pred$pred_selected[!pred$timing_available]-pred$pred_base[!pred$timing_available])>1e-12))stop('Timing-unavailable fallback identity violated.')
if(any(abs(pred$pred_selected[is.na(pred$selected_family)]-pred$pred_base[is.na(pred$selected_family)])>1e-12))stop('Family-unavailable fallback identity violated.')

manifest<-data.frame(
  item=c('script','ab','long','shape','geometry','campaign','ignition','peak_truth_A','m0_grid_source'),
  identity=c(digest::digest(file='scripts/run_m2_ab_curve_ratio_chronological_c123_v2.R',algo='sha256'),digest::digest(ab,algo='sha256'),digest::digest(long,algo='sha256'),digest::digest(shape,algo='sha256'),digest::digest(geom,algo='sha256'),digest::digest(campaign,algo='sha256'),digest::digest(ignition,algo='sha256'),digest::digest(peak_truth_A,algo='sha256'),digest::digest(m0_grid,algo='sha256')),stringsAsFactors=FALSE)
write.csv(manifest,file.path(out_dir,'source_manifest.csv'),row.names=FALSE)
cat('\nPARENT-REVIEWED CHRONOLOGICAL C1/C2/C3 V2\n');print(summary,row.names=FALSE,digits=5)
cat('\nFAMILY\n');print(family_df,row.names=FALSE,digits=5)
cat('\nAVAILABILITY\n');print(avail_df,row.names=FALSE,digits=5)
cat('\nPROVENANCE\n');print(prov_df,row.names=FALSE,digits=5)
