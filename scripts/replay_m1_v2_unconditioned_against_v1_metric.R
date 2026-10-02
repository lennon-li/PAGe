source('PAGe/R/data_contract.R')
source('PAGe/R/expert_timing_annotations.R')
source('PAGe/R/retrospective_peak_truth.R')
source('PAGe/R/m1_v2.R')

campaign <- readRDS('artifacts/expert-ignition-annotation-v2-pass1/campaign_data.rds')
current_truth <- read.csv('artifacts/expert-ignition-annotation-v2-pass1/retrospective_peak_truth_v1.csv', stringsAsFactors=FALSE)
contract_dir <- '../PAGe/results/benchmark-contracts/m1/v1.0.0'
benchmark_dir <- '../PAGe/results/benchmark-evaluations/m1-v1.0.0/v16-cache-20260920'
origin <- read.csv(file.path(contract_dir,'origin_ledger.csv'),stringsAsFactors=FALSE)
m0 <- read.csv(file.path(contract_dir,'m0_origin_ledger.csv'),stringsAsFactors=FALSE)
truth <- read.csv(file.path(contract_dir,'peak_truth_ledger.csv'),stringsAsFactors=FALSE)
v1 <- read.csv(file.path(benchmark_dir,'per_origin_scores.csv'),stringsAsFactors=FALSE)
metric <- read.csv(file.path(benchmark_dir,'metric_results.csv'),stringsAsFactors=FALSE)
seasons <- as.character(truth$season)
primary <- origin[origin$in_primary_prepeak,]
primary <- merge(primary,m0[,c('season','origin_weekF','m0_locked_weekF')],by=c('season','origin_weekF'),all.x=TRUE,sort=FALSE)

summarize_post <- function(post){T<-post$peak_week_decimal;w<-post$probability;cdf<-cumsum(w);q<-function(p)T[which(cdf>=p)[1]];c(mean=sum(T*w),median=q(.5),map=T[which.max(w)],q05=q(.05),q95=q(.95))}
rows<-list()
for(h in seasons){
  train<-setdiff(seasons,h)
  lib<-fit_m1_v2_library(campaign[campaign$season%in%train,],current_truth[current_truth$season%in%train,c('season','peak_week_decimal')],k=8L,grid_step=.01,tau_step=.1)
  held<-campaign[campaign$season==h,]
  rr<-primary[primary$season==h,]
  A<-unique(rr$m0_locked_weekF)
  for(i in seq_len(nrow(rr))){
    o<-rr$origin_weekF[i]
    p<-m1_v2_passage_posterior(lib,held,A,o,candidate_step=.1,max_future_weeks=14)
    ps<-summarize_post(attr(p,'posterior'))
    rows[[length(rows)+1]]<-data.frame(season=h,origin_weekF=o,m0_locked_weekF=A,mean=ps['mean'],median=ps['median'],map=ps['map'],q05=ps['q05'],q95=ps['q95'],p_passed=p$prob_peak_passed)
  }
}
x<-do.call(rbind,rows)
x<-merge(x,truth[,c('season','peak_integer_weekF','peak_decimal_weekF')],by='season',all.x=TRUE,sort=FALSE)
x<-merge(x,current_truth[,c('season','peak_week_decimal')],by='season',all.x=TRUE,sort=FALSE)
names(x)[names(x)=='peak_week_decimal']<-'current_peak_decimal'
x$current_peak_integer<-round(x$current_peak_decimal)
x$weight_early<-exp(-(0.1*(x$origin_weekF-x$m0_locked_weekF))^2)
score<-function(pred,truth){ss<-sort(unique(x$season));mean(vapply(ss,function(s){z<-x[x$season==s,];sum(z$weight_early*abs(pred[x$season==s]-truth[x$season==s]))/sum(z$weight_early)},numeric(1)))}
res<-data.frame(estimator=character(),frozen_integer=numeric(),frozen_decimal=numeric(),current_integer=numeric(),current_decimal=numeric(),stringsAsFactors=FALSE)
for(nm in c('mean','median','map')){
  pred<-x[[nm]]
  res<-rbind(res,data.frame(estimator=nm,frozen_integer=score(round(pred),x$peak_integer_weekF),frozen_decimal=score(round(pred),x$peak_decimal_weekF),current_integer=score(round(pred),x$current_peak_integer),current_decimal=score(pred,x$current_peak_decimal)))
}
out_dir<-'artifacts/m1-v2-package-replay-v1-metric-unconditioned';dir.create(out_dir,recursive=TRUE,showWarnings=FALSE)
write.csv(x,file.path(out_dir,'per_origin.csv'),row.names=FALSE);write.csv(res,file.path(out_dir,'metric_summary.csv'),row.names=FALSE)
cat('v1 active benchmark=',metric$value[metric$metric_id=='primary_prepeak_integer_mae_season_balanced_early_weighted'],'\n');print(res,row.names=FALSE,digits=5)
# score v1 against current truth for reference
v<-v1[v1$in_primary_prepeak,];v<-merge(v,current_truth[,c('season','peak_week_decimal')],by='season');v$current_integer<-round(v$peak_week_decimal);v$weight_early<-exp(-(0.1*(v$origin_weekF-v$m0_locked_weekF))^2);ss<-sort(unique(v$season));sv<-mean(vapply(ss,function(s){z<-v[v$season==s,];sum(z$weight_early*abs(z$prediction_peak_weekF-z$current_integer))/sum(z$weight_early)},numeric(1)));cat('v1 active rescored current truth=',sv,'\n')
