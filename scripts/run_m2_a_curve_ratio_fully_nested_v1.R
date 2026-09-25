#!/usr/bin/env Rscript

source('PAGe/R/data_contract.R')
source('PAGe/R/expert_timing_annotations.R')
source('PAGe/R/retrospective_peak_truth.R')
source('PAGe/R/m1_v2.R')

ab <- read.csv('artifacts/m2-v2-flu-ab-geometry-v1/flu_ab_weekly_v1.csv', stringsAsFactors=FALSE)
shape <- read.csv('artifacts/m2-v2-flu-ab-geometry-v1/peak_aligned_normalized_shape_grid.csv', stringsAsFactors=FALSE)
geom <- read.csv('artifacts/m2-v2-flu-ab-geometry-v1/type_geometry_k8.csv', stringsAsFactors=FALSE)
nested_m0 <- read.csv('artifacts/m1-v2-governed-nested-m0-replay/nested_m0_activations.csv', stringsAsFactors=FALSE)
a_outer <- read.csv('artifacts/m1-v2-governed-nested-m0-replay/per_origin.csv', stringsAsFactors=FALSE)
seasons <- sort(unique(ab$season))
A <- data.frame(season=ab$season,weekF=ab$weekF,y=ab$y_A,N=ab$N_A,p=ab$p_A,stringsAsFactors=FALSE)
truth <- geom[geom$type=='A',c('season','peak_week_decimal')]
out_dir <- 'artifacts/m2-v2-a-curve-ratio-fully-nested-v1'
dir.create(out_dir,recursive=TRUE,showWarnings=FALSE)
cache_dir <- file.path(out_dir,'cache_step04_n9');dir.create(cache_dir,recursive=TRUE,showWarnings=FALSE)
lib_dir <- file.path(cache_dir,'libraries');dir.create(lib_dir,recursive=TRUE,showWarnings=FALSE)
feat_dir <- file.path(cache_dir,'features');dir.create(feat_dir,recursive=TRUE,showWarnings=FALSE)
alpha_grid<-c(0,.25,.5,.75,1);eta_grid<-c(.25,.5,.75)

# Precompute the season-separable retrospective smooths once so pair-exclusion
# libraries do not refit identical GAMs.
.pre_smoothed<-list();.pre_peak_height<-setNames(numeric(length(seasons)),seasons);.pre_fitted_peak<-.pre_peak_height
for(s in seasons){f<-retrospective_gam_peak_truth(A,season=s,k=8L,grid_step=.01);tt<-truth$peak_week_decimal[truth$season==s];if(abs(f$peak_week_decimal-tt)>.02)stop('Precomputed A smoother does not match frozen peak truth for ',s);g<-f$grid;g$tau<-g$weekF-tt;g$p_norm<-g$fitted_p/max(g$fitted_p);.pre_smoothed[[s]]<-g[,c('tau','p_norm')];.pre_peak_height[s]<-max(g$fitted_p);.pre_fitted_peak[s]<-f$peak_week_decimal}
.fast_library<-function(train){train<-sort(train);amp<-seq(.08,.44,by=.02);dsub<-prepare_surveillance_data(A[A$season%in%train,]);pt<-truth[match(train,truth$season),c('season','peak_week_decimal'),drop=FALSE];fc<-.fit_m1_v2_component(.pre_smoothed[train],.pre_peak_height[train],seq(-14,0,by=.1),amp);ps<-.fit_m1_v2_component(.pre_smoothed[train],.pre_peak_height[train],seq(-14,3,by=.1),amp);fh<-digest::digest(list(forecast=fc,passage=ps,peak_height=.pre_peak_height[train],fitted_peak=.pre_fitted_peak[train]),algo='sha256');lib<-structure(list(version='m1-v2-lowrank-peak-anchored-v1',training_seasons=train,peak_truth=pt,fitted_peak=.pre_fitted_peak[train],peak_height=.pre_peak_height[train],forecast=fc,passage=ps,config=list(k=8L,grid_step=.01,tau_step=.1,amplitude_grid=amp),provenance=list(coordinate_version='page-continuous-week-v1',data_hash=digest::digest(dsub,algo='sha256'),truth_hash=digest::digest(pt,algo='sha256'),fitted_hash=fh,library_hash=NULL)),class='page_m1_v2_library');lib$provenance$library_hash<-.m1_v2_recompute_library_hash(lib);lib}

logit<-function(p)qlogis(pmin(pmax(p,1e-6),1-1e-6));stab<-function(y,N,c=.5)(y+c)/(N+2*c)
# A candidate-independent ledger.
rows<-list()
for(s in seasons){z<-ab[ab$season==s,];z<-z[order(z$weekF),];ps<-stab(z$y_A,z$N_A);l<-logit(ps);g1<-c(NA,diff(l));g2<-c(NA,NA,(l[3:length(l)]-l[1:(length(l)-2)])/2)
 for(i in seq_len(nrow(z))){if(z$weekF[i]<13||i<3)next;for(h in 1:2){j<-i+h;if(j>nrow(z)||z$weekF[j]!=z$weekF[i]+h)next;rows[[length(rows)+1]]<-data.frame(season=s,origin_week=z$weekF[i],target_week=z$weekF[j],horizon=h,y_target=z$y_A[j],N_target=z$N_A[j],p_target=z$p_A[j],p_star=ps[i],logit_current=l[i],growth1=g1[i],growth2=g2[i],stringsAsFactors=FALSE)}}}
ledger<-do.call(rbind,rows);ledger$horizon_f<-factor(paste0('h',ledger$horizon),levels=c('h1','h2'))
write.csv(ledger,file.path(out_dir,'candidate_independent_a_ledger.csv'),row.names=FALSE)

# Outer heldout activation coordinates reconstructed from governed replay.
outer_act<-do.call(rbind,lapply(split(a_outer,a_outer$season),function(z)data.frame(season=z$season[1],activation_origin=min(z$origin_week),activation_decimal=unique(z$asof_boundary-z$weeks_elapsed_since_activation)[1])))

one_lr<-function(z,tau,h){cur<-approx(z$tau,z$p_norm,xout=tau,rule=1)$y;fut<-approx(z$tau,z$p_norm,xout=tau+h,rule=1)$y;if(!is.finite(cur)||!is.finite(fut))return(NA_real_);log(pmax(fut,.01)/pmax(cur,.01))}
median_lr<-function(train,tp,tau,h){pool<-shape[shape$season%in%train,];typed<-pool[pool$type==tp,];med<-function(z){ids<-unique(paste(z$season,z$type,sep='|'));v<-vapply(ids,function(id)one_lr(z[paste(z$season,z$type,sep='|')==id,],tau,h),numeric(1));v<-v[is.finite(v)];if(length(v))median(v)else NA_real_};c(pooled=med(pool),typed=med(typed))}

lib_key<-function(excluded)paste(sort(gsub('-','_',excluded)),collapse='__')
get_library<-function(excluded){key<-lib_key(excluded);f<-file.path(lib_dir,paste0(key,'.rds'));if(file.exists(f))return(readRDS(f));train<-setdiff(seasons,excluded);lib<-.fast_library(train);saveRDS(lib,f);lib}
get_activation<-function(excluded,target){
 if(length(excluded)==1 && target==excluded){q<-outer_act[outer_act$season==target,];return(c(origin=q$activation_origin,decimal=q$activation_decimal))}
 # Pair-excluded validation feature: nested M0 row outer=other excluded season, season=target.
 other<-setdiff(excluded,target);q<-nested_m0[nested_m0$outer_holdout==other & nested_m0$season==target,]
 if(nrow(q)!=1) stop('Missing pair-excluded A activation for ',paste(excluded,collapse=','),' target ',target)
 c(origin=q$activation_origin_week,decimal=q$activation_week_decimal)
}
make_features<-function(excluded,target){key<-paste0(lib_key(excluded),'__target_',gsub('-','_',target));f<-file.path(feat_dir,paste0(key,'.rds'));if(file.exists(f))return(readRDS(f));train<-setdiff(seasons,excluded);lib<-get_library(excluded);act<-get_activation(excluded,target);z<-A[A$season==target,];led<-unique(ledger[ledger$season==target,c('season','origin_week')]);rr<-vector('list',nrow(led))
 for(i in seq_len(nrow(led))){o<-led$origin_week[i];lp1<-lt1<-lp2<-lt2<-NA_real_;width<-ppass<-NA_real_;available<-o>=ceiling(act['decimal']) && o<=ceiling(act['decimal'])+14L
  if(available){pp<-tryCatch({
    obs<-prepare_surveillance_data(z);obs<-obs[obs$weekF>=ceiling(act['decimal'])&obs$weekF<=o,];comp<-lib$passage;asof<-o+1;lower<-max(obs$weekF)-max(comp$tau);obs<-.m1_v2_trim_obs_for_candidate_support(obs,comp,lower);upper<-min(asof+12,min(obs$weekF)-min(comp$tau));cand<-seq(lower,upper,by=.4);post<-.m1_v2_grid_posterior(obs,cand,comp,n_c=9L);list(post=post,prob_passed=sum(post$probability[post$peak_week_decimal<=asof]))
   },error=function(e)e);if(!inherits(pp,'error')){post<-pp$post;T<-post$peak_week_decimal;w<-post$probability;calc<-function(h,which){v<-vapply(T,function(tt){x<-median_lr(train,'A',o-tt,h);x[[which]]},numeric(1));ok<-is.finite(v)&is.finite(w);if(any(ok))sum(v[ok]*w[ok])/sum(w[ok])else NA_real_};lp1<-calc(1,'pooled');lt1<-calc(1,'typed');lp2<-calc(2,'pooled');lt2<-calc(2,'typed');cdf<-cumsum(w);q05<-T[which(cdf>=.05)[1]];q95<-T[which(cdf>=.95)[1]];width<-q95-q05;ppass<-pp$prob_passed}else available<-FALSE}
  rr[[i]]<-data.frame(season=target,origin_week=o,timing_available=available,lr_pool_h1=lp1,lr_type_h1=lt1,lr_pool_h2=lp2,lr_type_h2=lt2,timing_width=width,p_passed=ppass,stringsAsFactors=FALSE)}
 out<-do.call(rbind,rr);saveRDS(out,f);out}

fit_base<-function(tr){tr$horizon_f<-factor(paste0('h',tr$horizon),levels=c('h1','h2'));tr$offset_logit<-tr$logit_current;suppressWarnings(glm(cbind(y_target,N_target-y_target)~horizon_f+growth1+growth2+offset(offset_logit),data=tr,family=quasibinomial()))}
blend<-function(base,current,lr,eta){if(!is.finite(lr))return(base);ps<-pmin(pmax(current*exp(lr),1e-6),1-1e-6);plogis((1-eta)*logit(base)+eta*logit(ps))}
cands<-rbind(data.frame(candidate='none',alpha=0,eta=0),do.call(rbind,lapply(alpha_grid,function(a)do.call(rbind,lapply(eta_grid,function(e)data.frame(candidate=paste0('a',a,'_e',e),alpha=a,eta=e))))))
write.csv(cands,file.path(out_dir,'candidate_grid.csv'),row.names=FALSE)
apply_cand<-function(z,pbase,cnd,h){out<-pbase;if(cnd$candidate=='none')return(out);lp<-z[[paste0('lr_pool_h',h)]];lt<-z[[paste0('lr_type_h',h)]];lr<-(1-cnd$alpha)*lp+cnd$alpha*lt;ix<-which(z$timing_available&is.finite(lr));if(length(ix))out[ix]<-mapply(function(b,p,l)blend(b,p,l,cnd$eta),pbase[ix],z$p_star[ix],lr[ix]);out}

preds<-list();sels<-list();inner_all<-list()
for(outer in seasons){cat('outer',outer,'\n');train_outer<-setdiff(seasons,outer)
 invisible(parallel::mclapply(train_outer,function(v) make_features(c(outer,v),v),mc.cores=4L))
 for(h in 1:2){scores<-numeric(nrow(cands));for(ci in seq_len(nrow(cands))){cnd<-cands[ci,];mae<-numeric();for(v in train_outer){train<-setdiff(train_outer,v);tr<-ledger[ledger$season%in%train,];va<-ledger[ledger$season==v&ledger$horizon==h,];fit<-fit_base(tr);va$offset_logit<-va$logit_current;pb<-as.numeric(predict(fit,newdata=va,type='response'));feat<-make_features(c(outer,v),v);va<-merge(va,feat,by=c('season','origin_week'),all.x=TRUE,sort=FALSE);va$timing_available[is.na(va$timing_available)]<-FALSE;pv<-apply_cand(va,pb,cnd,h);mae<-c(mae,100*mean(abs(pv-va$p_target)))};scores[ci]<-mean(mae);inner_all[[paste(outer,h,ci)]]<-data.frame(outer=outer,horizon=h,candidate=cnd$candidate,inner_mae_pp=scores[ci])}
  best<-which(scores==min(scores))[1];cnd<-cands[best,];sels[[paste(outer,h)]]<-data.frame(outer=outer,horizon=h,candidate=cnd$candidate,alpha=cnd$alpha,eta=cnd$eta,inner_mae_pp=scores[best])}
 tr<-ledger[ledger$season%in%train_outer,];te<-ledger[ledger$season==outer,];fit<-fit_base(tr);te$offset_logit<-te$logit_current;te$pred_base<-as.numeric(predict(fit,newdata=te,type='response'));te$pred_v1<-te$pred_base;feat<-make_features(outer,outer);te<-merge(te,feat,by=c('season','origin_week'),all.x=TRUE,sort=FALSE);te$timing_available[is.na(te$timing_available)]<-FALSE
 for(h in 1:2){sel<-sels[[paste(outer,h)]];cnd<-cands[cands$candidate==sel$candidate,][1,];ix<-which(te$horizon==h);te$pred_v1[ix]<-apply_cand(te[ix,],te$pred_base[ix],cnd,h);te$selected_candidate[ix]<-sel$candidate}
 preds[[outer]]<-te}
pred<-do.call(rbind,preds);sel<-do.call(rbind,sels);inner<-do.call(rbind,inner_all);write.csv(pred,file.path(out_dir,'outer_predictions.csv'),row.names=FALSE);write.csv(sel,file.path(out_dir,'outer_selections.csv'),row.names=FALSE);write.csv(inner,file.path(out_dir,'inner_candidate_scores.csv'),row.names=FALSE)
for(m in c('base','v1')){p<-pmin(pmax(pred[[paste0('pred_',m)]],1e-8),1-1e-8);pred[[paste0('abs_',m)]]<-abs(p-pred$p_target);pred[[paste0('nll_',m)]]<--(pred$y_target*log(p)+(pred$N_target-pred$y_target)*log(1-p))/pred$N_target}
per<-do.call(rbind,lapply(split(pred,list(pred$season,pred$horizon),drop=TRUE),function(z)data.frame(season=z$season[1],horizon=z$horizon[1],candidate=z$selected_candidate[1],base_mae_pp=100*mean(z$abs_base),v1_mae_pp=100*mean(z$abs_v1),base_nll=mean(z$nll_base),v1_nll=mean(z$nll_v1),n=nrow(z))))
write.csv(per,file.path(out_dir,'per_season_metrics.csv'),row.names=FALSE);summary<-do.call(rbind,lapply(split(per,per$horizon),function(z)data.frame(horizon=z$horizon[1],base_mae_pp=mean(z$base_mae_pp),v1_mae_pp=mean(z$v1_mae_pp),relative_gain=1-mean(z$v1_mae_pp)/mean(z$base_mae_pp),base_nll=mean(z$base_nll),v1_nll=mean(z$v1_nll),nll_gain=mean(z$base_nll-z$v1_nll),seasons_better=sum(z$v1_mae_pp<z$base_mae_pp),seasons_worse=sum(z$v1_mae_pp>z$base_mae_pp))))
write.csv(summary,file.path(out_dir,'summary.csv'),row.names=FALSE);cat('\nSelections\n');print(sel,row.names=FALSE,digits=4);cat('\nFully nested A curve-ratio summary\n');print(summary,row.names=FALSE,digits=5);cat('\nPer season\n');print(per,row.names=FALSE,digits=4)
