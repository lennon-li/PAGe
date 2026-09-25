#!/usr/bin/env Rscript

ab <- read.csv('artifacts/m2-v2-flu-ab-geometry-v1/flu_ab_weekly_v1.csv', stringsAsFactors=FALSE)
shape <- read.csv('artifacts/m2-v2-flu-ab-geometry-v1/peak_aligned_normalized_shape_grid.csv', stringsAsFactors=FALSE)
a_timing <- read.csv('artifacts/m1-v2-governed-nested-m0-replay/per_origin.csv', stringsAsFactors=FALSE)
b_timing <- read.csv('artifacts/m2-v2-b-phase-nested-selected-v1/strict_nested_selected_predictions.csv', stringsAsFactors=FALSE)
seasons <- sort(unique(ab$season))
out_dir <- 'artifacts/m2-v2-ab-curve-ratio-shrinkage-v1'
dir.create(out_dir,recursive=TRUE,showWarnings=FALSE)
alpha_grid <- c(0,.25,.5,.75,1)
eta_shape <- .5

logit <- function(p) qlogis(pmin(pmax(p,1e-6),1-1e-6))
stab <- function(y,N,c=.5) (y+c)/(N+2*c)

make_type_ledger <- function(tp){
 ycol<-paste0('y_',tp);ncol<-paste0('N_',tp);pcol<-paste0('p_',tp);rows<-list()
 for(s in seasons){
  z<-ab[ab$season==s,];z<-z[order(z$weekF),];y<-z[[ycol]];N<-z[[ncol]];p<-z[[pcol]]
  ps<-stab(y,N);l<-logit(ps);g1<-c(NA,diff(l));g2<-c(NA,NA,(l[3:length(l)]-l[1:(length(l)-2)])/2)
  for(i in seq_len(nrow(z))){if(z$weekF[i]<13||i<3)next;for(h in 1:2){j<-i+h;if(j>nrow(z)||z$weekF[j]!=z$weekF[i]+h)next
   rows[[length(rows)+1]]<-data.frame(season=s,type=tp,origin_week=z$weekF[i],target_week=z$weekF[j],horizon=h,
    y_target=z[[ycol]][j],N_target=z[[ncol]][j],p_target=z[[pcol]][j],p_star=ps[i],logit_current=l[i],
    growth1=g1[i],growth2=g2[i],denominator_regime=z$denominator_regime[i],stringsAsFactors=FALSE)}}}
 do.call(rbind,rows)
}
ledger<-rbind(make_type_ledger('A'),make_type_ledger('B'));ledger$horizon_f<-factor(paste0('h',ledger$horizon),levels=c('h1','h2'))

a_key<-unique(a_timing[,c('season','origin_week','calibrated_peak_mean','locked_peak_week','peak_passed','interval_width_90')])
a_key$timing_peak<-ifelse(a_key$peak_passed&is.finite(a_key$locked_peak_week),a_key$locked_peak_week,a_key$calibrated_peak_mean)
a_key$timing_available<-is.finite(a_key$timing_peak);a_key$timing_width<-a_key$interval_width_90
a_key<-a_key[,c('season','origin_week','timing_available','timing_peak','timing_width')]
b_key<-unique(b_timing[,c('season','origin_week','timing_available','m1_peak_mean','m1_width')]);names(b_key)[4:5]<-c('timing_peak','timing_width')
a_led<-merge(ledger[ledger$type=='A',],a_key,by=c('season','origin_week'),all.x=TRUE,sort=FALSE)
b_led<-merge(ledger[ledger$type=='B',],b_key,by=c('season','origin_week'),all.x=TRUE,sort=FALSE)
a_led$timing_available[is.na(a_led$timing_available)]<-FALSE;b_led$timing_available[is.na(b_led$timing_available)]<-FALSE
ledger<-rbind(a_led,b_led);rownames(ledger)<-NULL
write.csv(ledger,file.path(out_dir,'candidate_independent_ab_ledger.csv'),row.names=FALSE)

one_lr<-function(z,tau,h){cur<-approx(z$tau,z$p_norm,xout=tau,rule=1)$y;fut<-approx(z$tau,z$p_norm,xout=tau+h,rule=1)$y;if(!is.finite(cur)||!is.finite(fut))return(NA_real_);log(pmax(fut,.01)/pmax(cur,.01))}
median_lr<-function(train,tp,tau,h){
 pool<-shape[shape$season%in%train,];typed<-pool[pool$type==tp,]
 med<-function(z){ids<-unique(paste(z$season,z$type,sep='|'));v<-vapply(ids,function(id)one_lr(z[paste(z$season,z$type,sep='|')==id,],tau,h),numeric(1));v<-v[is.finite(v)];if(length(v))median(v) else NA_real_}
 c(pooled=med(pool),typed=med(typed))
}
blend<-function(base,current,lr,eta=eta_shape){if(!is.finite(lr))return(base);ps<-pmin(pmax(current*exp(lr),1e-6),1-1e-6);plogis((1-eta)*logit(base)+eta*logit(ps))}

# Inner selection uses only completed training-shape reconstruction, equal weighted
# over validation season x type x horizon. This chooses alpha, not forecast outcome.
selection<-list();inner_scores<-list()
for(outer in seasons){
 tr_outer<-setdiff(seasons,outer);score_alpha<-numeric(length(alpha_grid))
 for(ai in seq_along(alpha_grid)){a<-alpha_grid[ai];cells<-list()
  for(v in tr_outer){lib<-setdiff(tr_outer,v);for(tp in c('A','B'))for(h in 1:2){vz<-shape[shape$season==v&shape$type==tp,];taus<-vz$tau[vz$tau>=-8&vz$tau<=8-h];e<-numeric()
   for(tau in taus){actual<-one_lr(vz,tau,h);lr<-median_lr(lib,tp,tau,h);est<-(1-a)*lr['pooled']+a*lr['typed'];if(is.finite(actual)&&is.finite(est))e<-c(e,est-actual)}
   cells[[length(cells)+1]]<-data.frame(outer=outer,alpha=a,validation=v,type=tp,horizon=h,rmse=sqrt(mean(e^2)),n=length(e))}}
  cc<-do.call(rbind,cells);inner_scores[[paste(outer,a)]]<-cc;score_alpha[ai]<-mean(cc$rmse)
 }
 best<-which(score_alpha==min(score_alpha))[1]
 selection[[outer]]<-data.frame(outer=outer,alpha_selected=alpha_grid[best],inner_rmse=score_alpha[best],
   C1_rmse=score_alpha[1],C2_025_rmse=score_alpha[2],C2_050_rmse=score_alpha[3],C2_075_rmse=score_alpha[4],C3_rmse=score_alpha[5])
}
sel<-do.call(rbind,selection);inner<-do.call(rbind,inner_scores);write.csv(sel,file.path(out_dir,'outer_alpha_selection.csv'),row.names=FALSE);write.csv(inner,file.path(out_dir,'inner_shape_scores.csv'),row.names=FALSE)

preds<-list()
for(outer in seasons){
 train<-setdiff(seasons,outer);alpha<-sel$alpha_selected[sel$outer==outer]
 for(tp in c('A','B')){
  tr<-ledger[ledger$season%in%train&ledger$type==tp,];te<-ledger[ledger$season==outer&ledger$type==tp,]
  tr$offset_logit<-tr$logit_current;te$offset_logit<-te$logit_current
  fit<-suppressWarnings(glm(cbind(y_target,N_target-y_target)~horizon_f+growth1+growth2+offset(offset_logit),data=tr,family=quasibinomial()))
  te$pred_base<-as.numeric(predict(fit,newdata=te,type='response'));te$pred_selected<-te$pred_base;te$alpha_selected<-alpha
  for(i in seq_len(nrow(te))){use<-isTRUE(te$timing_available[i])&&is.finite(te$timing_peak[i])&&!(tp=='B'&&te$horizon[i]==1);if(!use)next
   tau<-te$origin_week[i]-te$timing_peak[i];lr<-median_lr(train,tp,tau,te$horizon[i]);est<-(1-alpha)*lr['pooled']+alpha*lr['typed'];te$pred_selected[i]<-blend(te$pred_base[i],te$p_star[i],est)}
  preds[[paste(outer,tp)]]<-te
 }
}
pred<-do.call(rbind,preds);rownames(pred)<-NULL
for(m in c('base','selected')){p<-pmin(pmax(pred[[paste0('pred_',m)]],1e-8),1-1e-8);pred[[paste0('abs_',m)]]<-abs(p-pred$p_target);pred[[paste0('sq_',m)]]<-(p-pred$p_target)^2;pred[[paste0('nll_',m)]]<--(pred$y_target*log(p)+(pred$N_target-pred$y_target)*log(1-p))/pred$N_target}
write.csv(pred,file.path(out_dir,'outer_selected_predictions.csv'),row.names=FALSE)
per<-do.call(rbind,lapply(split(pred,list(pred$season,pred$type,pred$horizon),drop=TRUE),function(z)data.frame(season=z$season[1],type=z$type[1],horizon=z$horizon[1],alpha=z$alpha_selected[1],timing_availability=mean(z$timing_available),base_mae_pp=100*mean(z$abs_base),selected_mae_pp=100*mean(z$abs_selected),base_rmse_pp=100*sqrt(mean(z$sq_base)),selected_rmse_pp=100*sqrt(mean(z$sq_selected)),base_nll=mean(z$nll_base),selected_nll=mean(z$nll_selected))))
write.csv(per,file.path(out_dir,'per_season_metrics.csv'),row.names=FALSE)
summary<-do.call(rbind,lapply(split(per,list(per$type,per$horizon),drop=TRUE),function(z)data.frame(type=z$type[1],horizon=z$horizon[1],base_mae_pp=mean(z$base_mae_pp),selected_mae_pp=mean(z$selected_mae_pp),relative_mae_gain=1-mean(z$selected_mae_pp)/mean(z$base_mae_pp),base_rmse_pp=mean(z$base_rmse_pp),selected_rmse_pp=mean(z$selected_rmse_pp),base_nll=mean(z$base_nll),selected_nll=mean(z$selected_nll),seasons_better=sum(z$selected_mae_pp<z$base_mae_pp))))
write.csv(summary,file.path(out_dir,'summary.csv'),row.names=FALSE)
cat('Alpha selections\n');print(sel,row.names=FALSE,digits=5);cat('\nOuter metrics\n');print(summary,row.names=FALSE,digits=5)
