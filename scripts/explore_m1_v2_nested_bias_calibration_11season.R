source('PAGe/R/data_contract.R')
source('PAGe/R/expert_timing_annotations.R')
source('PAGe/R/retrospective_peak_truth.R')
source('PAGe/R/m1_v2.R')

campaign<-readRDS('artifacts/expert-ignition-annotation-v2-pass1/campaign_data.rds')
truth<-read.csv('artifacts/expert-ignition-annotation-v2-pass1/retrospective_peak_truth_v1.csv',stringsAsFactors=FALSE)
m0<-read.csv('artifacts/m0-v2-decimal-loso-baseline-r2/compare.csv',stringsAsFactors=FALSE)
seasons<-as.character(truth$season)

ledger<-do.call(rbind,lapply(seasons,function(s){mr<-m0[m0$season==s,];tr<-truth[truth$season==s,];orig<-seq(as.integer(mr$iWeek_hat),round(tr$peak_week_decimal),1);data.frame(season=s,origin_weekF=orig,m0_integer=as.integer(mr$iWeek_hat),m0_decimal=mr$iWeek_hatF,truth_peak_decimal=tr$peak_week_decimal,truth_peak_integer=round(tr$peak_week_decimal))}))
cal_origins<-do.call(rbind,lapply(seasons,function(s){z<-ledger[ledger$season==s,];head(z,4)}))

pair_rows<-list()
for(i in 1:(length(seasons)-1)) for(j in (i+1):length(seasons)){
  a<-seasons[i];b<-seasons[j];train<-setdiff(seasons,c(a,b))
  lib<-fit_m1_v2_library(campaign[campaign$season%in%train,],truth[truth$season%in%train,c('season','peak_week_decimal')],k=8L,grid_step=.01,tau_step=.1)
  for(target in c(a,b)){
    held<-campaign[campaign$season==target,];rr<-cal_origins[cal_origins$season==target,];outer_for<-if(target==a)b else a
    for(k in seq_len(nrow(rr))){o<-rr$origin_weekF[k];fit<-m1_v2_peak_posterior(lib,held,rr$m0_decimal[k],o,candidate_step=.2);pred<-fit$summary$peak_mean[1];pair_rows[[length(pair_rows)+1]]<-data.frame(outer_holdout=outer_for,inner_season=target,origin=o,m0_integer=rr$m0_integer[k],pred=pred,truth=rr$truth_peak_decimal[k],error=pred-rr$truth_peak_decimal[k],weight=exp(-(0.1*(o-rr$m0_integer[k]))^2))}
  }
}
inner<-do.call(rbind,pair_rows)
offsets<-do.call(rbind,lapply(seasons,function(h){z<-inner[inner$outer_holdout==h,];z$w_bal<-ave(z$weight,z$inner_season,FUN=function(v)v/sum(v));data.frame(season=h,offset_mean=-sum(z$w_bal*z$error)/sum(z$w_bal),inner_bias_mean=sum(z$w_bal*z$error)/sum(z$w_bal),n=nrow(z))}))
outer<-read.csv('artifacts/m1-v2-package-replay-v1-metric/current_11season_extension_per_origin.csv',stringsAsFactors=FALSE)
outer<-merge(outer,offsets,by='season',all.x=TRUE,sort=FALSE);outer$pred_cal<-outer$prediction_mean_decimal+outer$offset_mean;outer$pred_cal_integer<-round(outer$pred_cal)
score<-function(pred,truthv){ss<-sort(unique(outer$season));mean(vapply(ss,function(s){z<-outer[outer$season==s,];sum(z$weight_early*abs(pred[outer$season==s]-truthv[outer$season==s]))/sum(z$weight_early)},numeric(1)))}
res<-data.frame(method=c('uncalibrated','nested_mean_bias'),integer_metric=c(score(outer$prediction_integer,outer$truth_peak_integer),score(outer$pred_cal_integer,outer$truth_peak_integer)),native_decimal_metric=c(score(outer$prediction_mean_decimal,outer$truth_peak_decimal),score(outer$pred_cal,outer$truth_peak_decimal)))
per<-do.call(rbind,lapply(split(outer,outer$season),function(z)data.frame(season=z$season[1],offset=z$offset_mean[1],n=nrow(z),uncal_int=sum(z$weight_early*abs(z$prediction_integer-z$truth_peak_integer))/sum(z$weight_early),cal_int=sum(z$weight_early*abs(z$pred_cal_integer-z$truth_peak_integer))/sum(z$weight_early),uncal_dec=sum(z$weight_early*abs(z$prediction_mean_decimal-z$truth_peak_decimal))/sum(z$weight_early),cal_dec=sum(z$weight_early*abs(z$pred_cal-z$truth_peak_decimal))/sum(z$weight_early))))
dir.create('artifacts/m1-v2-nested-bias-calibration-11season',recursive=TRUE,showWarnings=FALSE);write.csv(inner,'artifacts/m1-v2-nested-bias-calibration-11season/inner_predictions.csv',row.names=FALSE);write.csv(offsets,'artifacts/m1-v2-nested-bias-calibration-11season/offsets.csv',row.names=FALSE);write.csv(outer,'artifacts/m1-v2-nested-bias-calibration-11season/outer_predictions.csv',row.names=FALSE);write.csv(res,'artifacts/m1-v2-nested-bias-calibration-11season/summary.csv',row.names=FALSE);write.csv(per,'artifacts/m1-v2-nested-bias-calibration-11season/per_season.csv',row.names=FALSE)
print(offsets,row.names=FALSE,digits=4);cat('\nSCORES\n');print(res,row.names=FALSE,digits=5);cat('\nPER SEASON\n');print(per,row.names=FALSE,digits=4)
