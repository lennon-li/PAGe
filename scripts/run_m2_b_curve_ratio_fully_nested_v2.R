#!/usr/bin/env Rscript

source('PAGe/R/data_contract.R')
source('PAGe/R/expert_timing_annotations.R')
source('PAGe/R/retrospective_peak_truth.R')
source('PAGe/R/m1_v2.R')

ab <- read.csv('artifacts/m2-v2-flu-ab-geometry-v1/flu_ab_weekly_v1.csv', stringsAsFactors=FALSE)
long <- read.csv('artifacts/m2-v2-flu-ab-geometry-v1/flu_ab_long_v1.csv', stringsAsFactors=FALSE)
shape <- read.csv('artifacts/m2-v2-flu-ab-geometry-v1/peak_aligned_normalized_shape_grid.csv', stringsAsFactors=FALSE)
geom <- read.csv('artifacts/m2-v2-flu-ab-geometry-v1/type_geometry_k8.csv', stringsAsFactors=FALSE)
ledger <- read.csv('artifacts/m2-v2-b-baselines-v1/candidate_independent_ledger.csv', stringsAsFactors=FALSE)
seasons <- sort(unique(ledger$season))
b <- long[long$type=='B',c('season','weekF','y','N','p','denominator_regime')]
b$season <- as.character(b$season); b <- b[order(b$season,b$weekF),]
truth <- geom[geom$type=='B',c('season','peak_week_decimal')]
out_dir <- 'artifacts/m2-v2-b-curve-ratio-fully-nested-v2'
dir.create(out_dir,recursive=TRUE,showWarnings=FALSE)
cache_dir <- file.path(out_dir,'cache');dir.create(cache_dir,recursive=TRUE,showWarnings=FALSE)
lib_dir <- file.path(cache_dir,'libraries');dir.create(lib_dir,recursive=TRUE,showWarnings=FALSE)
feat_dir <- file.path(cache_dir,'features');dir.create(feat_dir,recursive=TRUE,showWarnings=FALSE)

alpha_grid <- c(0,.25,.5,.75,1)
p_grid <- c(.02,.03,.04,.05)
count_grid <- c(10,20,40)
eta_shape <- .5
week_min <- 18L

# Precompute season-specific retrospective smooths once. M1-v2's historical
# GAMs are season-separable, so exclusion libraries can be rebuilt exactly from
# these cached curves without refitting the same GAM hundreds of times.
.pre_smoothed <- list(); .pre_peak_height <- setNames(numeric(length(seasons)),seasons); .pre_fitted_peak <- .pre_peak_height
for(s in seasons){
  f <- retrospective_gam_peak_truth(b,season=s,k=8L,grid_step=.01)
  tt <- truth$peak_week_decimal[truth$season==s]
  if(abs(f$peak_week_decimal-tt)>.02) stop('Precomputed B smoother does not match frozen peak truth for ',s)
  g<-f$grid;g$tau<-g$weekF-tt;g$p_norm<-g$fitted_p/max(g$fitted_p)
  .pre_smoothed[[s]]<-g[,c('tau','p_norm')];.pre_peak_height[s]<-max(g$fitted_p);.pre_fitted_peak[s]<-f$peak_week_decimal
}
.fast_library <- function(train){
  train<-sort(train); amp<-seq(.005,.25,by=.005); dsub<-prepare_surveillance_data(b[b$season%in%train,]);pt<-truth[match(train,truth$season),c('season','peak_week_decimal'),drop=FALSE]
  fc<-.fit_m1_v2_component(.pre_smoothed[train],.pre_peak_height[train],seq(-14,0,by=.1),amp)
  ps<-.fit_m1_v2_component(.pre_smoothed[train],.pre_peak_height[train],seq(-14,3,by=.1),amp)
  fitted_hash<-digest::digest(list(forecast=fc,passage=ps,peak_height=.pre_peak_height[train],fitted_peak=.pre_fitted_peak[train]),algo='sha256')
  lib<-structure(list(version='m1-v2-lowrank-peak-anchored-v1',training_seasons=train,peak_truth=pt,fitted_peak=.pre_fitted_peak[train],peak_height=.pre_peak_height[train],forecast=fc,passage=ps,config=list(k=8L,grid_step=.01,tau_step=.1,amplitude_grid=amp),provenance=list(coordinate_version='page-continuous-week-v1',data_hash=digest::digest(dsub,algo='sha256'),truth_hash=digest::digest(pt,algo='sha256'),fitted_hash=fitted_hash,library_hash=NULL)),class='page_m1_v2_library')
  lib$provenance$library_hash<-.m1_v2_recompute_library_hash(lib);lib
}

logit <- function(p) qlogis(pmin(pmax(p,1e-6),1-1e-6))
blend <- function(base,current,lr,eta=eta_shape){
 if(!is.finite(lr)) return(base)
 ps<-pmin(pmax(current*exp(lr),1e-6),1-1e-6)
 plogis((1-eta)*logit(base)+eta*logit(ps))
}

# Causal activity summaries independent of candidate gate choice.
gate_stats <- do.call(rbind,lapply(split(b,b$season),function(z){
 z<-z[order(z$weekF),]
 sum4<-as.numeric(stats::filter(z$y,rep(1,4),sides=1))
 maxp4<-vapply(seq_len(nrow(z)),function(i)max(z$p[max(1,i-3):i],na.rm=TRUE),numeric(1))
 data.frame(season=z$season,origin_week=z$weekF,sum4=sum4,maxp4=maxp4)
}))
write.csv(gate_stats,file.path(out_dir,'causal_gate_statistics.csv'),row.names=FALSE)

one_lr <- function(z,tau,h){
 cur<-approx(z$tau,z$p_norm,xout=tau,rule=1)$y
 fut<-approx(z$tau,z$p_norm,xout=tau+h,rule=1)$y
 if(!is.finite(cur)||!is.finite(fut)) return(NA_real_)
 log(pmax(fut,.01)/pmax(cur,.01))
}
median_lr <- function(train_seasons,tp,tau,h){
 pool<-shape[shape$season%in%train_seasons,]
 typed<-pool[pool$type==tp,]
 med<-function(z){
  ids<-unique(paste(z$season,z$type,sep='|'))
  v<-vapply(ids,function(id)one_lr(z[paste(z$season,z$type,sep='|')==id,],tau,h),numeric(1))
  v<-v[is.finite(v)]; if(length(v)) median(v) else NA_real_
 }
 c(pooled=med(pool),typed=med(typed))
}

lib_key <- function(excluded) paste(sort(gsub('-','_',excluded)),collapse='__')
get_library <- function(excluded){
 key<-lib_key(excluded);f<-file.path(lib_dir,paste0(key,'.rds'))
 if(file.exists(f)) return(readRDS(f))
 train<-setdiff(seasons,excluded)
 lib<-.fast_library(train)
 saveRDS(lib,f);lib
}

# Timing is computed from a fixed calendar activation at week 18; candidate gate
# thresholds only determine whether its shape correction is USED. This prevents
# the gate from changing the posterior fit itself and makes gate selection cheap.
make_features <- function(excluded,target){
 key<-paste0(lib_key(excluded),'__target_',gsub('-','_',target));f<-file.path(feat_dir,paste0(key,'.rds'))
 if(file.exists(f)) return(readRDS(f))
 train<-setdiff(seasons,excluded);lib<-get_library(excluded)
 z<-b[b$season==target,]
 led<-unique(ledger[ledger$season==target,c('season','origin_week')])
 rows<-vector('list',nrow(led))
 for(i in seq_len(nrow(led))){
  o<-led$origin_week[i]
  lp1<-lt1<-lp2<-lt2<-NA_real_; ppass<-width<-NA_real_
  gs<-gate_stats[gate_stats$season==target & gate_stats$origin_week==o,]
  potentially_active<-o>=week_min && nrow(gs)==1L && is.finite(gs$sum4) && gs$sum4>=min(count_grid) && is.finite(gs$maxp4) && gs$maxp4>=min(p_grid)
  if(potentially_active){
   pp<-tryCatch(m1_v2_passage_posterior(lib,z,activation_week=week_min,origin_week=o,candidate_step=.2,max_future_weeks=12),error=function(e)e)
   if(!inherits(pp,'error')){
    post<-attr(pp,'posterior');T<-post$peak_week_decimal;w<-post$probability
    calc<-function(h,which){
     vals<-vapply(T,function(tt){lr<-median_lr(train,'B',o-tt,h);lr[[which]]},numeric(1))
     ok<-is.finite(vals)&is.finite(w)
     if(any(ok)) sum(vals[ok]*w[ok])/sum(w[ok]) else NA_real_
    }
    lp1<-calc(1,'pooled');lt1<-calc(1,'typed');lp2<-calc(2,'pooled');lt2<-calc(2,'typed')
    cdf<-cumsum(w);q05<-T[which(cdf>=.05)[1]];q95<-T[which(cdf>=.95)[1]];width<-q95-q05
    ppass<-pp$prob_peak_passed[1]
   }
  }
  rows[[i]]<-data.frame(season=target,origin_week=o,lr_pool_h1=lp1,lr_type_h1=lt1,lr_pool_h2=lp2,lr_type_h2=lt2,
                         p_passed=ppass,timing_width=width,stringsAsFactors=FALSE)
 }
 out<-do.call(rbind,rows);out<-merge(out,gate_stats,by=c('season','origin_week'),all.x=TRUE,sort=FALSE)
 saveRDS(out,f);out
}

fit_b1 <- function(tr){
 tr$horizon_f<-factor(paste0('h',tr$horizon),levels=c('h1','h2'));tr$offset_logit<-tr$logit_current
 suppressWarnings(glm(cbind(y_target,N_target-y_target)~horizon_f+growth1+growth2+offset(offset_logit),data=tr,family=quasibinomial()))
}

candidate_table <- rbind(
 data.frame(candidate='none',p_thr=Inf,count_thr=Inf,alpha=0),
 do.call(rbind,lapply(p_grid,function(p)do.call(rbind,lapply(count_grid,function(n)data.frame(
   candidate=paste0('p',sprintf('%02d',round(100*p)),'_n',n,'_a',alpha_grid),
   p_thr=p,count_thr=n,alpha=alpha_grid
 )))))
)
write.csv(candidate_table,file.path(out_dir,'candidate_grid.csv'),row.names=FALSE)

apply_candidate <- function(z,p_base,cand,h){
 out<-p_base
 if(cand$candidate=='none') return(out)
 active<-z$origin_week>=week_min & is.finite(z$sum4) & z$sum4>=cand$count_thr & is.finite(z$maxp4) & z$maxp4>=cand$p_thr
 lp<-z[[paste0('lr_pool_h',h)]];lt<-z[[paste0('lr_type_h',h)]]
 lr<-(1-cand$alpha)*lp+cand$alpha*lt
 ix<-which(active & is.finite(lr))
 if(length(ix)) out[ix]<-mapply(blend,p_base[ix],z$p_star[ix],lr[ix])
 out
}

outer_preds<-list(); selections<-list(); inner_all<-list()
for(outer in seasons){
 cat('outer',outer,'\n')
 train_outer<-setdiff(seasons,outer)
 # Pair-excluded validation features are independent. Precompute/cache them in
 # parallel; this changes execution only, not the statistical exclusion set.
 invisible(parallel::mclapply(train_outer, function(v) make_features(c(outer,v),v), mc.cores=4L))
 # Inner selection: validation v timing library excludes {outer,v}; B1 fit excludes {outer,v}.
 for(h in 1:2){
  cand_scores<-numeric(nrow(candidate_table))
  for(ci in seq_len(nrow(candidate_table))){
   cnd<-candidate_table[ci,]
   season_mae<-numeric()
   for(v in train_outer){
    tr_seas<-setdiff(train_outer,v);tr<-ledger[ledger$season%in%tr_seas,];va<-ledger[ledger$season==v & ledger$horizon==h,]
    b1<-fit_b1(tr);va$offset_logit<-va$logit_current;va$pred_base<-as.numeric(predict(b1,newdata=va,type='response'))
    feat<-make_features(c(outer,v),v);va<-merge(va,feat,by=c('season','origin_week'),all.x=TRUE,sort=FALSE)
    pv<-apply_candidate(va,va$pred_base,cnd,h)
    season_mae<-c(season_mae,100*mean(abs(pv-va$p_target)))
   }
   cand_scores[ci]<-mean(season_mae)
   inner_all[[paste(outer,h,ci)]]<-data.frame(outer=outer,horizon=h,candidate=cnd$candidate,inner_mae_pp=cand_scores[ci])
  }
  best_ix<-which(cand_scores==min(cand_scores))[1]
  best<-candidate_table[best_ix,]
  selections[[paste(outer,h)]]<-data.frame(outer=outer,horizon=h,candidate=best$candidate,p_thr=best$p_thr,count_thr=best$count_thr,alpha=best$alpha,inner_mae_pp=cand_scores[best_ix])
 }
 # Final outer prediction. Timing library excludes outer only.
 tr<-ledger[ledger$season%in%train_outer,];te<-ledger[ledger$season==outer,]
 b1<-fit_b1(tr);te$offset_logit<-te$logit_current;te$pred_b0<-te$p_star;te$pred_b1<-as.numeric(predict(b1,newdata=te,type='response'));te$pred_v2<-te$pred_b1
 feat<-make_features(outer,outer);te<-merge(te,feat,by=c('season','origin_week'),all.x=TRUE,sort=FALSE)
 for(h in 1:2){sel<-selections[[paste(outer,h)]];cnd<-candidate_table[candidate_table$candidate==sel$candidate,][1,]
  ix<-which(te$horizon==h);te$pred_v2[ix]<-apply_candidate(te[ix,],te$pred_b1[ix],cnd,h);te$selected_candidate[ix]<-sel$candidate}
 outer_preds[[outer]]<-te
}
pred<-do.call(rbind,outer_preds);rownames(pred)<-NULL
sel<-do.call(rbind,selections);rownames(sel)<-NULL
inner<-do.call(rbind,inner_all);rownames(inner)<-NULL
write.csv(pred,file.path(out_dir,'outer_predictions.csv'),row.names=FALSE);write.csv(sel,file.path(out_dir,'outer_selections.csv'),row.names=FALSE);write.csv(inner,file.path(out_dir,'inner_candidate_scores.csv'),row.names=FALSE)

for(m in c('b0','b1','v2')){p<-pmin(pmax(pred[[paste0('pred_',m)]],1e-8),1-1e-8);pred[[paste0('abs_',m)]]<-abs(p-pred$p_target);pred[[paste0('nll_',m)]]<--(pred$y_target*log(p)+(pred$N_target-pred$y_target)*log(1-p))/pred$N_target}
per<-do.call(rbind,lapply(split(pred,list(pred$season,pred$horizon),drop=TRUE),function(z)data.frame(season=z$season[1],horizon=z$horizon[1],candidate=z$selected_candidate[1],b0_mae_pp=100*mean(z$abs_b0),b1_mae_pp=100*mean(z$abs_b1),v2_mae_pp=100*mean(z$abs_v2),b1_nll=mean(z$nll_b1),v2_nll=mean(z$nll_v2),n=nrow(z))))
write.csv(per,file.path(out_dir,'per_season_metrics.csv'),row.names=FALSE)
summary<-do.call(rbind,lapply(split(per,per$horizon),function(z)data.frame(horizon=z$horizon[1],b0_mae_pp=mean(z$b0_mae_pp),b1_mae_pp=mean(z$b1_mae_pp),v2_mae_pp=mean(z$v2_mae_pp),v2_vs_b1_relative_gain=1-mean(z$v2_mae_pp)/mean(z$b1_mae_pp),b1_nll=mean(z$b1_nll),v2_nll=mean(z$v2_nll),v2_vs_b1_nll_gain=mean(z$b1_nll-z$v2_nll),seasons_v2_better=sum(z$v2_mae_pp<z$b1_mae_pp),seasons_v2_worse=sum(z$v2_mae_pp>z$b1_mae_pp))))
write.csv(summary,file.path(out_dir,'summary.csv'),row.names=FALSE)
cat('\nSelections\n');print(sel,row.names=FALSE,digits=4);cat('\nFully nested B curve-ratio summary\n');print(summary,row.names=FALSE,digits=5);cat('\nPer season\n');print(per,row.names=FALSE,digits=4)
