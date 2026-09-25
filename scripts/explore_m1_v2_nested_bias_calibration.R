source('PAGe/R/data_contract.R')
source('PAGe/R/expert_timing_annotations.R')
source('PAGe/R/retrospective_peak_truth.R')
source('PAGe/R/m1_v2.R')

campaign<-readRDS('artifacts/expert-ignition-annotation-v2-pass1/campaign_data.rds')
truth<-read.csv('artifacts/expert-ignition-annotation-v2-pass1/retrospective_peak_truth_v1.csv',stringsAsFactors=FALSE)
contract_dir<-'../PAGe/results/benchmark-contracts/m1/v1.0.0'
origin<-read.csv(file.path(contract_dir,'origin_ledger.csv'),stringsAsFactors=FALSE)
m0<-read.csv(file.path(contract_dir,'m0_origin_ledger.csv'),stringsAsFactors=FALSE)
frozen<-read.csv(file.path(contract_dir,'peak_truth_ledger.csv'),stringsAsFactors=FALSE)
seasons<-as.character(frozen$season)
primary<-origin[origin$in_primary_prepeak,]
primary<-merge(primary,m0[,c('season','origin_weekF','m0_locked_weekF')],by=c('season','origin_weekF'),all.x=TRUE,sort=FALSE)
primary<-primary[order(match(primary$season,seasons),primary$origin_weekF),]

# Fixed a priori calibration subset: first four primary origins in each inner season.
cal_origins<-do.call(rbind,lapply(seasons,function(s){z<-primary[primary$season==s,];head(z,4)}))

pair_rows<-list(); pair_meta<-list()
for(i in 1:(length(seasons)-1)) for(j in (i+1):length(seasons)){
  a<-seasons[i];b<-seasons[j];train<-setdiff(seasons,c(a,b))
  lib<-fit_m1_v2_library(campaign[campaign$season%in%train,],truth[truth$season%in%train,c('season','peak_week_decimal')],k=8L,grid_step=.01,tau_step=.1)
  for(target in c(a,b)){
    held<-campaign[campaign$season==target,]; rr<-cal_origins[cal_origins$season==target,]; A<-unique(rr$m0_locked_weekF); T<-truth$peak_week_decimal[truth$season==target]
    outer_for<-if(target==a)b else a
    for(k in seq_len(nrow(rr))){o<-rr$origin_weekF[k];fit<-m1_v2_peak_posterior(lib,held,A,o,candidate_step=.2);pred<-fit$summary$peak_mean[1];pair_rows[[length(pair_rows)+1]]<-data.frame(outer_holdout=outer_for,inner_season=target,origin=o,m0=A,pred=pred,truth=T,error=pred-T,weight=exp(-(0.1*(o-A))^2))}
  }
  pair_meta[[length(pair_meta)+1]]<-data.frame(excluded_a=a,excluded_b=b)
}
inner<-do.call(rbind,pair_rows)

weighted_median<-function(x,w){o<-order(x);x<-x[o];w<-w[o]/sum(w);x[which(cumsum(w)>=.5)[1]]}
offsets<-do.call(rbind,lapply(seasons,function(h){z<-inner[inner$outer_holdout==h,]; # normalize each inner season to equal total mass
  z$w_bal<-ave(z$weight,z$inner_season,FUN=function(v)v/sum(v));
  data.frame(season=h,offset_mean=-sum(z$w_bal*z$error)/sum(z$w_bal),offset_median=-weighted_median(z$error,z$w_bal),inner_bias_mean=sum(z$w_bal*z$error)/sum(z$w_bal),n=nrow(z))}))

outer<-read.csv('artifacts/m1-v2-package-replay-v1-metric/frozen_contract_per_origin.csv',stringsAsFactors=FALSE)
outer<-merge(outer,offsets,by='season',all.x=TRUE,sort=FALSE)
outer$pred_cal_mean<-outer$prediction_mean_decimal+outer$offset_mean
outer$pred_cal_median<-outer$prediction_mean_decimal+outer$offset_median
score<-function(pred,truthv){ss<-sort(unique(outer$season));mean(vapply(ss,function(s){z<-outer[outer$season==s,];sum(z$weight_early*abs(pred[outer$season==s]-truthv[outer$season==s]))/sum(z$weight_early)},numeric(1)))}
res<-data.frame(method=c('uncalibrated_mean','nested_mean_bias','nested_weighted_median_bias'),current_integer=c(score(round(outer$prediction_mean_decimal),outer$current_peak_integer),score(round(outer$pred_cal_mean),outer$current_peak_integer),score(round(outer$pred_cal_median),outer$current_peak_integer)),current_native_decimal=c(score(outer$prediction_mean_decimal,outer$current_peak_decimal),score(outer$pred_cal_mean,outer$current_peak_decimal),score(outer$pred_cal_median,outer$current_peak_decimal)),frozen_integer=c(score(round(outer$prediction_mean_decimal),outer$peak_integer_weekF),score(round(outer$pred_cal_mean),outer$peak_integer_weekF),score(round(outer$pred_cal_median),outer$peak_integer_weekF)))
dir.create('artifacts/m1-v2-nested-bias-calibration',recursive=TRUE,showWarnings=FALSE);write.csv(inner,'artifacts/m1-v2-nested-bias-calibration/inner_predictions.csv',row.names=FALSE);write.csv(offsets,'artifacts/m1-v2-nested-bias-calibration/offsets.csv',row.names=FALSE);write.csv(outer,'artifacts/m1-v2-nested-bias-calibration/outer_predictions.csv',row.names=FALSE);write.csv(res,'artifacts/m1-v2-nested-bias-calibration/summary.csv',row.names=FALSE)
print(offsets,row.names=FALSE,digits=4);cat('\nSCORES\n');print(res,row.names=FALSE,digits=5)
