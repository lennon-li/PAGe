#!/usr/bin/env Rscript

ab <- read.csv('artifacts/m2-v2-flu-ab-geometry-v1/flu_ab_weekly_v1.csv', stringsAsFactors=FALSE)
shape <- read.csv('artifacts/m2-v2-flu-ab-geometry-v1/peak_aligned_normalized_shape_grid.csv', stringsAsFactors=FALSE)
a_timing <- read.csv('artifacts/m1-v2-governed-nested-m0-replay/per_origin.csv', stringsAsFactors=FALSE)
b_timing <- read.csv('artifacts/m2-v2-b-phase-nested-selected-v1/strict_nested_selected_predictions.csv', stringsAsFactors=FALSE)
seasons <- sort(unique(ab$season))
out_dir <- 'artifacts/m2-v2-ab-curve-ratio-c123-v1'
dir.create(out_dir,recursive=TRUE,showWarnings=FALSE)

logit <- function(p) qlogis(pmin(pmax(p,1e-6),1-1e-6))
stab <- function(y,N,c=.5) (y+c)/(N+2*c)

# Candidate-independent A/B ledger, independent of timing availability.
make_type_ledger <- function(tp){
  ycol<-paste0('y_',tp); ncol<-paste0('N_',tp); pcol<-paste0('p_',tp)
  rows<-list()
  for(s in seasons){
    z<-ab[ab$season==s,]; z<-z[order(z$weekF),]
    y<-z[[ycol]];N<-z[[ncol]];p<-z[[pcol]]
    ps<-stab(y,N); l<-logit(ps);g1<-c(NA,diff(l));g2<-c(NA,NA,(l[3:length(l)]-l[1:(length(l)-2)])/2)
    for(i in seq_len(nrow(z))){
      if(z$weekF[i]<13 || i<3) next
      for(h in 1:2){
        j<-i+h
        if(j>nrow(z) || z$weekF[j]!=z$weekF[i]+h) next
        rows[[length(rows)+1]]<-data.frame(
          season=s,type=tp,origin_week=z$weekF[i],target_week=z$weekF[j],horizon=h,
          y_target=z[[ycol]][j],N_target=z[[ncol]][j],p_target=z[[pcol]][j],
          y_current=y[i],N_current=N[i],p_current=p[i],p_star=ps[i],
          logit_current=l[i],growth1=g1[i],growth2=g2[i],
          denominator_regime=z$denominator_regime[i],stringsAsFactors=FALSE)
      }
    }
  }
  do.call(rbind,rows)
}
ledger<-rbind(make_type_ledger('A'),make_type_ledger('B'));rownames(ledger)<-NULL
ledger$horizon_f<-factor(paste0('h',ledger$horizon),levels=c('h1','h2'))

# Outer-held-out timing features. A uses the governed outer replay; B uses the
# strict nested B timing artifact. Timing-unavailable rows fall back exactly.
a_key <- unique(a_timing[,c('season','origin_week','state','calibrated_peak_mean','locked_peak_week','peak_passed','interval_width_90')])
a_key$timing_peak <- ifelse(a_key$peak_passed & is.finite(a_key$locked_peak_week),a_key$locked_peak_week,a_key$calibrated_peak_mean)
a_key$timing_available <- is.finite(a_key$timing_peak)
a_key$timing_width <- a_key$interval_width_90

a_key <- a_key[,c('season','origin_week','timing_available','timing_peak','timing_width')]
b_key <- unique(b_timing[,c('season','origin_week','timing_available','m1_peak_mean','m1_width')])
names(b_key)[names(b_key)=='m1_peak_mean']<-'timing_peak';names(b_key)[names(b_key)=='m1_width']<-'timing_width'

a_led<-merge(ledger[ledger$type=='A',],a_key,by=c('season','origin_week'),all.x=TRUE,sort=FALSE)
b_led<-merge(ledger[ledger$type=='B',],b_key,by=c('season','origin_week'),all.x=TRUE,sort=FALSE)
for(zname in c('a_led','b_led')){
  z<-get(zname);z$timing_available[is.na(z$timing_available)]<-FALSE;assign(zname,z)
}
ledger<-rbind(a_led,b_led);rownames(ledger)<-NULL
write.csv(ledger,file.path(out_dir,'candidate_independent_ab_ledger.csv'),row.names=FALSE)

# Interpolate one normalized template and return log ratio from current week to target.
template_log_ratio <- function(template_rows,tau,h){
  cur<-approx(template_rows$tau,template_rows$p_norm,xout=tau,rule=1)$y
  fut<-approx(template_rows$tau,template_rows$p_norm,xout=tau+h,rule=1)$y
  if(!is.finite(cur)||!is.finite(fut)) return(NA_real_)
  log(pmax(fut,.01)/pmax(cur,.01))
}

shape_ratio <- function(train_seasons,tp,tau,h,family){
  pooled<-shape[shape$season%in%train_seasons,]
  typed<-pooled[pooled$type==tp,]
  get_median<-function(z){
    ids<-unique(paste(z$season,z$type,sep='|')); vals<-vapply(ids,function(id){
      q<-z[paste(z$season,z$type,sep='|')==id,]
      template_log_ratio(q,tau,h)
    },numeric(1)); stats::median(vals[is.finite(vals)],na.rm=TRUE)
  }
  lp<-get_median(pooled); lt<-get_median(typed)
  if(family=='C1') return(lp)
  if(family=='C3') return(lt)
  # C2: deliberately fixed 50/50 shrinkage of type-specific log drift to pooled.
  # This is a predeclared first-pass partial-pooling candidate, not outer-tuned.
  if(family=='C2') return(.5*lp+.5*lt)
  stop('unknown family')
}

# Blend baseline and shape-ratio forecast on logit scale. eta=.5 deliberately
# keeps local state/growth dominant in this first-pass shape experiment.
blend_shape <- function(p_base,p_current,log_ratio,eta=.5){
  if(!is.finite(log_ratio)) return(p_base)
  p_shape<-pmin(pmax(p_current*exp(log_ratio),1e-6),1-1e-6)
  plogis((1-eta)*logit(p_base)+eta*logit(p_shape))
}

preds<-list()
for(outer in seasons){
  cat('outer',outer,'\n')
  train_seasons<-setdiff(seasons,outer)
  for(tp in c('A','B')){
    tr<-ledger[ledger$season%in%train_seasons & ledger$type==tp,]
    te<-ledger[ledger$season==outer & ledger$type==tp,]
    tr$offset_logit<-tr$logit_current;te$offset_logit<-te$logit_current
    fit<-suppressWarnings(glm(cbind(y_target,N_target-y_target)~horizon_f+growth1+growth2+offset(offset_logit),data=tr,family=quasibinomial()))
    te$pred_base<-as.numeric(predict(fit,newdata=te,type='response'))
    for(fam in c('C1','C2','C3')) te[[paste0('pred_',fam)]]<-te$pred_base
    for(i in seq_len(nrow(te))){
      # Respect the earlier nested B result: no B timing correction at +1.
      use_timing<-isTRUE(te$timing_available[i]) && is.finite(te$timing_peak[i]) && !(tp=='B' && te$horizon[i]==1)
      if(!use_timing) next
      tau<-te$origin_week[i]-te$timing_peak[i]
      for(fam in c('C1','C2','C3')){
        lr<-shape_ratio(train_seasons,tp,tau,te$horizon[i],fam)
        te[[paste0('pred_',fam)]][i]<-blend_shape(te$pred_base[i],te$p_star[i],lr,eta=.5)
      }
    }
    preds[[paste(outer,tp,sep='|')]]<-te
  }
}
pred<-do.call(rbind,preds);rownames(pred)<-NULL
write.csv(pred,file.path(out_dir,'outer_loso_predictions.csv'),row.names=FALSE)

mods<-c('base','C1','C2','C3')
for(m in mods){
 p<-pmin(pmax(pred[[paste0('pred_',m)]],1e-8),1-1e-8)
 pred[[paste0('abs_',m)]]<-abs(p-pred$p_target)
 pred[[paste0('sq_',m)]]<-(p-pred$p_target)^2
 pred[[paste0('nll_',m)]]<--(pred$y_target*log(p)+(pred$N_target-pred$y_target)*log(1-p))/pred$N_target
}

per<-do.call(rbind,lapply(split(pred,list(pred$season,pred$type,pred$horizon),drop=TRUE),function(z){
  out<-data.frame(season=z$season[1],type=z$type[1],horizon=z$horizon[1],n=nrow(z),timing_availability=mean(z$timing_available))
  for(m in mods){
    out[[paste0(m,'_mae_pp')]]<-100*mean(z[[paste0('abs_',m)]])
    out[[paste0(m,'_rmse_pp')]]<-100*sqrt(mean(z[[paste0('sq_',m)]]) )
    out[[paste0(m,'_nll')]]<-mean(z[[paste0('nll_',m)]])
  }
  out
}))
rownames(per)<-NULL
write.csv(per,file.path(out_dir,'per_season_metrics.csv'),row.names=FALSE)

summary<-do.call(rbind,lapply(split(per,list(per$type,per$horizon),drop=TRUE),function(z){
  out<-data.frame(type=z$type[1],horizon=z$horizon[1],n_seasons=nrow(z),mean_timing_availability=mean(z$timing_availability))
  for(m in mods){
    out[[paste0(m,'_mae_pp')]]<-mean(z[[paste0(m,'_mae_pp')]])
    out[[paste0(m,'_rmse_pp')]]<-mean(z[[paste0(m,'_rmse_pp')]])
    out[[paste0(m,'_nll')]]<-mean(z[[paste0(m,'_nll')]])
  }
  for(m in c('C1','C2','C3')){
    out[[paste0(m,'_vs_base_relative_mae_gain')]]<-1-out[[paste0(m,'_mae_pp')]]/out$base_mae_pp
    out[[paste0(m,'_seasons_better')]]<-sum(z[[paste0(m,'_mae_pp')]]<z$base_mae_pp)
  }
  out
}))
rownames(summary)<-NULL
write.csv(summary,file.path(out_dir,'summary.csv'),row.names=FALSE)
cat('\nC1/C2/C3 first-pass outer LOSO\n');print(summary,row.names=FALSE,digits=5)
