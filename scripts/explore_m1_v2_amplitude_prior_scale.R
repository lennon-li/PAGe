source('PAGe/R/data_contract.R')
source('PAGe/R/expert_timing_annotations.R')
source('PAGe/R/retrospective_peak_truth.R')
source('PAGe/R/m1_v2.R')

campaign <- readRDS('artifacts/expert-ignition-annotation-v2-pass1/campaign_data.rds')
current_truth <- read.csv('artifacts/expert-ignition-annotation-v2-pass1/retrospective_peak_truth_v1.csv', stringsAsFactors=FALSE)
contract_dir <- '../PAGe/results/benchmark-contracts/m1/v1.0.0'
origin <- read.csv(file.path(contract_dir,'origin_ledger.csv'),stringsAsFactors=FALSE)
m0 <- read.csv(file.path(contract_dir,'m0_origin_ledger.csv'),stringsAsFactors=FALSE)
frozen_truth <- read.csv(file.path(contract_dir,'peak_truth_ledger.csv'),stringsAsFactors=FALSE)
seasons <- as.character(frozen_truth$season)
primary <- origin[origin$in_primary_prepeak,]
primary <- merge(primary,m0[,c('season','origin_weekF','m0_locked_weekF')],by=c('season','origin_weekF'),all.x=TRUE,sort=FALSE)
scales <- c(1,1.5,2,3,4)
rows <- list()
for(h in seasons){
  train <- setdiff(seasons,h)
  base <- fit_m1_v2_library(campaign[campaign$season%in%train,], current_truth[current_truth$season%in%train,c('season','peak_week_decimal')], k=8L, grid_step=.01, tau_step=.1)
  rr <- primary[primary$season==h,]
  A <- unique(rr$m0_locked_weekF)
  held <- campaign[campaign$season==h,]
  for(sf in scales){
    lib <- base
    lib$forecast$sd_logb <- base$forecast$sd_logb * sf
    for(i in seq_len(nrow(rr))){
      o <- rr$origin_weekF[i]
      fit <- m1_v2_peak_posterior(lib,held,A,o,candidate_step=.1)
      s <- fit$summary[1,]
      rows[[length(rows)+1]] <- data.frame(scale=sf,season=h,origin=o,m0=A,mean=s$peak_mean,median=s$peak_median,map=s$peak_map)
    }
  }
}
x<-do.call(rbind,rows)
x<-merge(x,frozen_truth[,c('season','peak_integer_weekF','peak_decimal_weekF')],by='season',all.x=TRUE,sort=FALSE)
x<-merge(x,current_truth[,c('season','peak_week_decimal')],by='season',all.x=TRUE,sort=FALSE)
names(x)[names(x)=='peak_week_decimal']<-'current_peak_decimal'
x$current_peak_integer<-round(x$current_peak_decimal)
x$weight<-exp(-(0.1*(x$origin-x$m0))^2)
score<-function(z,pred,truth){ss<-sort(unique(z$season));mean(vapply(ss,function(s){q<-z[z$season==s,];sum(q$weight*abs(q[[pred]]-q[[truth]]))/sum(q$weight)},numeric(1)))}
out<-do.call(rbind,lapply(scales,function(sf){z<-x[x$scale==sf,]; data.frame(scale=sf,
 frozen_mean_integer=score(transform(z,pred=round(mean)),'pred','peak_integer_weekF'),
 current_mean_integer=score(transform(z,pred=round(mean)),'pred','current_peak_integer'),
 current_native_decimal=score(z,'mean','current_peak_decimal'),
 current_median_integer=score(transform(z,pred=round(median)),'pred','current_peak_integer'))}))
dir.create('artifacts/m1-v2-amplitude-prior-scale-exploration',recursive=TRUE,showWarnings=FALSE)
write.csv(x,'artifacts/m1-v2-amplitude-prior-scale-exploration/per_origin.csv',row.names=FALSE)
write.csv(out,'artifacts/m1-v2-amplitude-prior-scale-exploration/summary.csv',row.names=FALSE)
print(out,row.names=FALSE,digits=5)
