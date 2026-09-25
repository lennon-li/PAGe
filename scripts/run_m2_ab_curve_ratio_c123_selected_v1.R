#!/usr/bin/env Rscript

shape <- read.csv('artifacts/m2-v2-flu-ab-geometry-v1/peak_aligned_normalized_shape_grid.csv', stringsAsFactors=FALSE)
pred <- read.csv('artifacts/m2-v2-ab-curve-ratio-c123-v1/outer_loso_predictions.csv', stringsAsFactors=FALSE)
seasons <- sort(unique(shape$season))
out_dir <- 'artifacts/m2-v2-ab-curve-ratio-c123-selected-v1'
dir.create(out_dir,recursive=TRUE,showWarnings=FALSE)

families <- c('C1','C2','C3')
complexity_order <- setNames(seq_along(families),families)

one_template_log_ratio <- function(z,tau,h){
 cur<-approx(z$tau,z$p_norm,xout=tau,rule=1)$y
 fut<-approx(z$tau,z$p_norm,xout=tau+h,rule=1)$y
 if(!is.finite(cur)||!is.finite(fut)) return(NA_real_)
 log(pmax(fut,.01)/pmax(cur,.01))
}

family_log_ratio <- function(train_seasons,tp,tau,h,fam){
 pool<-shape[shape$season%in%train_seasons,]
 typed<-pool[pool$type==tp,]
 med<-function(z){
   ids<-unique(paste(z$season,z$type,sep='|'))
   vals<-vapply(ids,function(id){q<-z[paste(z$season,z$type,sep='|')==id,];one_template_log_ratio(q,tau,h)},numeric(1))
   vals<-vals[is.finite(vals)]
   if(!length(vals)) return(NA_real_)
   median(vals)
 }
 lp<-med(pool);lt<-med(typed)
 if(fam=='C1') return(lp)
 if(fam=='C2') return(.5*lp+.5*lt)
 if(fam=='C3') return(lt)
 stop('bad family')
}

# Directly score shape-drift reconstruction, which is the only component that
# differs among C1/C2/C3. This avoids using outer outcomes or runtime timing in
# family selection.
inner_rows<-list(); select_rows<-list()
for(outer in seasons){
 train_outer<-setdiff(seasons,outer)
 for(fam in families){
   val_rows<-list()
   for(v in train_outer){
     lib_seasons<-setdiff(train_outer,v)
     for(tp in c('A','B')) for(h in 1:2){
       vz<-shape[shape$season==v & shape$type==tp,]
       taus<-vz$tau[vz$tau>=-8 & vz$tau<=8-h]
       errs<-numeric()
       for(tau in taus){
         actual<-one_template_log_ratio(vz,tau,h)
         est<-family_log_ratio(lib_seasons,tp,tau,h,fam)
         if(is.finite(actual)&&is.finite(est)) errs<-c(errs,est-actual)
       }
       val_rows[[length(val_rows)+1]]<-data.frame(
         outer=outer,family=fam,validation=v,type=tp,horizon=h,
         rmse_log_ratio=sqrt(mean(errs^2)),mae_log_ratio=mean(abs(errs)),n_tau=length(errs),
         stringsAsFactors=FALSE)
     }
   }
   ir<-do.call(rbind,val_rows)
   inner_rows[[paste(outer,fam)]]<-ir
 }
 ir_all<-do.call(rbind,inner_rows[grepl(paste0('^',outer,' '),names(inner_rows))])
 # Equal weight validation-season x type x horizon cells.
 agg<-aggregate(rmse_log_ratio~family,ir_all,mean)
 best_rmse<-min(agg$rmse_log_ratio)
 tied<-agg$family[abs(agg$rmse_log_ratio-best_rmse)<1e-12]
 best<-tied[which.min(complexity_order[tied])]
 select_rows[[outer]]<-data.frame(
   outer=outer,selected_family=best,
   C1_inner_rmse=agg$rmse_log_ratio[match('C1',agg$family)],
   C2_inner_rmse=agg$rmse_log_ratio[match('C2',agg$family)],
   C3_inner_rmse=agg$rmse_log_ratio[match('C3',agg$family)],
   stringsAsFactors=FALSE)
}
inner<-do.call(rbind,inner_rows);rownames(inner)<-NULL
sel<-do.call(rbind,select_rows);rownames(sel)<-NULL
write.csv(inner,file.path(out_dir,'inner_shape_drift_scores.csv'),row.names=FALSE)
write.csv(sel,file.path(out_dir,'outer_family_selection.csv'),row.names=FALSE)

# Apply the training-only-selected family to the already strict outer predictions.
pred<-merge(pred,sel[,c('outer','selected_family')],by.x='season',by.y='outer',all.x=TRUE,sort=FALSE)
pred$pred_selected<-mapply(function(fam,c1,c2,c3){switch(fam,C1=c1,C2=c2,C3=c3)},pred$selected_family,pred$pred_C1,pred$pred_C2,pred$pred_C3)
pred$pred_selected[!is.finite(pred$pred_selected)]<-pred$pred_base[!is.finite(pred$pred_selected)]
write.csv(pred,file.path(out_dir,'outer_selected_predictions.csv'),row.names=FALSE)

for(m in c('base','selected')){
 p<-pmin(pmax(pred[[paste0('pred_',m)]],1e-8),1-1e-8)
 pred[[paste0('abs_',m)]]<-abs(p-pred$p_target)
 pred[[paste0('sq_',m)]]<-(p-pred$p_target)^2
 pred[[paste0('nll_',m)]]<--(pred$y_target*log(p)+(pred$N_target-pred$y_target)*log(1-p))/pred$N_target
}
per<-do.call(rbind,lapply(split(pred,list(pred$season,pred$type,pred$horizon),drop=TRUE),function(z){
 data.frame(season=z$season[1],type=z$type[1],horizon=z$horizon[1],selected_family=z$selected_family[1],n=nrow(z),
   timing_availability=mean(z$timing_available),
   base_mae_pp=100*mean(z$abs_base),selected_mae_pp=100*mean(z$abs_selected),
   base_rmse_pp=100*sqrt(mean(z$sq_base)),selected_rmse_pp=100*sqrt(mean(z$sq_selected)),
   base_nll=mean(z$nll_base),selected_nll=mean(z$nll_selected))
}))
rownames(per)<-NULL
write.csv(per,file.path(out_dir,'per_season_metrics.csv'),row.names=FALSE)
summary<-do.call(rbind,lapply(split(per,list(per$type,per$horizon),drop=TRUE),function(z)data.frame(
 type=z$type[1],horizon=z$horizon[1],n_seasons=nrow(z),
 base_mae_pp=mean(z$base_mae_pp),selected_mae_pp=mean(z$selected_mae_pp),
 relative_mae_gain=1-mean(z$selected_mae_pp)/mean(z$base_mae_pp),
 base_rmse_pp=mean(z$base_rmse_pp),selected_rmse_pp=mean(z$selected_rmse_pp),
 base_nll=mean(z$base_nll),selected_nll=mean(z$selected_nll),
 seasons_selected_better=sum(z$selected_mae_pp<z$base_mae_pp)
)))
rownames(summary)<-NULL
write.csv(summary,file.path(out_dir,'summary.csv'),row.names=FALSE)
cat('Family selections\n');print(sel,row.names=FALSE,digits=5)
cat('\nSelected family outer metrics\n');print(summary,row.names=FALSE,digits=5)
