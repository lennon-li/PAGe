source('PAGe/R/data_contract.R')
source('PAGe/R/expert_timing_annotations.R')
source('PAGe/R/retrospective_peak_truth.R')
source('PAGe/R/m1_v2.R')

campaign <- readRDS('artifacts/expert-ignition-annotation-v2-pass1/campaign_data.rds')
truth <- read.csv('artifacts/expert-ignition-annotation-v2-pass1/retrospective_peak_truth_v1.csv', stringsAsFactors=FALSE)
m0 <- read.csv('artifacts/m0-v2-decimal-loso-baseline-r2/compare.csv', stringsAsFactors=FALSE)
seasons <- as.character(truth$season)

ledger <- do.call(rbind,lapply(seasons,function(s){
  mr<-m0[m0$season==s,]; tr<-truth[truth$season==s,]
  orig<-seq(as.integer(mr$iWeek_hat),round(tr$peak_week_decimal),1)
  data.frame(season=s,origin=orig,m0_integer=as.integer(mr$iWeek_hat),m0_decimal=mr$iWeek_hatF,
             truth=tr$peak_week_decimal,truth_integer=round(tr$peak_week_decimal),
             elapsed=orig-as.integer(mr$iWeek_hat),
             weight=exp(-(0.1*(orig-as.integer(mr$iWeek_hat)))^2))
}))

rows <- list()
for(i in 1:(length(seasons)-1)) for(j in (i+1):length(seasons)){
  a<-seasons[i]; b<-seasons[j]; train<-setdiff(seasons,c(a,b))
  lib<-fit_m1_v2_library(campaign[campaign$season%in%train,],truth[truth$season%in%train,c('season','peak_week_decimal')],k=8L,grid_step=.01,tau_step=.1)
  for(target in c(a,b)){
    outer_for<-if(target==a)b else a
    held<-campaign[campaign$season==target,]
    rr<-ledger[ledger$season==target,]
    for(k in seq_len(nrow(rr))){
      o<-rr$origin[k]
      fit<-m1_v2_peak_posterior(lib,held,rr$m0_decimal[k],o,candidate_step=.2)
      pred<-fit$summary$peak_mean[1]
      rows[[length(rows)+1]]<-data.frame(
        outer_holdout=outer_for,inner_season=target,origin=o,m0_integer=rr$m0_integer[k],
        elapsed=rr$elapsed[k],weight=rr$weight[k],pred=pred,truth=rr$truth[k],
        truth_integer=rr$truth_integer[k],error=pred-rr$truth[k]
      )
    }
  }
}
inner<-do.call(rbind,rows)

outer<-read.csv('artifacts/m1-v2-package-replay-v1-metric/current_11season_extension_per_origin.csv',stringsAsFactors=FALSE)
outer$elapsed<-outer$origin_weekF-outer$m0_integer

fit_intercept<-function(z){z$wbal<-ave(z$weight,z$inner_season,FUN=function(v)v/sum(v));sum(z$wbal*z$error)/sum(z$wbal)}
fit_elapsed<-function(z){z$wbal<-ave(z$weight,z$inner_season,FUN=function(v)v/sum(v));lm(error~elapsed,data=z,weights=wbal)}

pred_rows<-list(); pars<-list()
for(h in seasons){
  z<-inner[inner$outer_holdout==h,]
  te<-outer[outer$season==h,]
  b0<-fit_intercept(z)
  me<-fit_elapsed(z)
  eh<-as.numeric(predict(me,newdata=te))
  ih<-as.numeric(predict(me,newdata=z))
  lo<-quantile(ih,.05); hi<-quantile(ih,.95)
  eh<-pmin(pmax(eh,lo),hi)
  te$pred_intercept<-te$prediction_mean_decimal-b0
  te$pred_intercept_integer<-round(te$pred_intercept)
  te$pred_elapsed<-te$prediction_mean_decimal-eh
  te$pred_elapsed_integer<-round(te$pred_elapsed)
  pred_rows[[h]]<-te
  pars[[h]]<-data.frame(season=h,intercept_bias=b0,elapsed_beta0=coef(me)[1],elapsed_beta1=coef(me)[2],elapsed_errhat_min=lo,elapsed_errhat_max=hi)
}
x<-do.call(rbind,pred_rows); par<-do.call(rbind,pars)
score<-function(pred,truthcol){ss<-sort(unique(x$season));mean(vapply(ss,function(s){z<-x[x$season==s,];sum(z$weight_early*abs(z[[pred]]-z[[truthcol]]))/sum(z$weight_early)},numeric(1)))}
res<-data.frame(
 method=c('uncalibrated','fullwindow_intercept','fullwindow_elapsed'),
 integer_metric=c(score('prediction_integer','truth_peak_integer'),score('pred_intercept_integer','truth_peak_integer'),score('pred_elapsed_integer','truth_peak_integer')),
 native_decimal=c(score('prediction_mean_decimal','truth_peak_decimal'),score('pred_intercept','truth_peak_decimal'),score('pred_elapsed','truth_peak_decimal'))
)
per<-do.call(rbind,lapply(split(x,x$season),function(z)data.frame(season=z$season[1],n=nrow(z),uncal_int=sum(z$weight_early*abs(z$prediction_integer-z$truth_peak_integer))/sum(z$weight_early),int_int=sum(z$weight_early*abs(z$pred_intercept_integer-z$truth_peak_integer))/sum(z$weight_early),elapsed_int=sum(z$weight_early*abs(z$pred_elapsed_integer-z$truth_peak_integer))/sum(z$weight_early),uncal_dec=sum(z$weight_early*abs(z$prediction_mean_decimal-z$truth_peak_decimal))/sum(z$weight_early),int_dec=sum(z$weight_early*abs(z$pred_intercept-z$truth_peak_decimal))/sum(z$weight_early),elapsed_dec=sum(z$weight_early*abs(z$pred_elapsed-z$truth_peak_decimal))/sum(z$weight_early))))

dir.create('artifacts/m1-v2-nested-fullwindow-calibration',recursive=TRUE,showWarnings=FALSE)
write.csv(inner,'artifacts/m1-v2-nested-fullwindow-calibration/inner_predictions.csv',row.names=FALSE)
write.csv(par,'artifacts/m1-v2-nested-fullwindow-calibration/parameters.csv',row.names=FALSE)
write.csv(x,'artifacts/m1-v2-nested-fullwindow-calibration/outer_predictions.csv',row.names=FALSE)
write.csv(res,'artifacts/m1-v2-nested-fullwindow-calibration/summary.csv',row.names=FALSE)
write.csv(per,'artifacts/m1-v2-nested-fullwindow-calibration/per_season.csv',row.names=FALSE)
cat('PARAMETERS\n');print(par,row.names=FALSE,digits=4);cat('\nSUMMARY\n');print(res,row.names=FALSE,digits=5);cat('\nPER SEASON\n');print(per,row.names=FALSE,digits=4)
