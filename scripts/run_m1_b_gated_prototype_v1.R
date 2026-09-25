source('PAGe/R/data_contract.R')
source('PAGe/R/expert_timing_annotations.R')
source('PAGe/R/retrospective_peak_truth.R')
source('PAGe/R/m1_v2.R')

ab <- read.csv('artifacts/m2-v2-flu-ab-geometry-v1/flu_ab_long_v1.csv', stringsAsFactors=FALSE)
b <- ab[ab$type=='B', c('season','weekF','y','N','p')]
b$season <- as.character(b$season)
b <- b[order(b$season,b$weekF),]
seasons <- sort(unique(b$season))
geom <- read.csv('artifacts/m2-v2-flu-ab-geometry-v1/type_geometry_k8.csv', stringsAsFactors=FALSE)
truth <- geom[geom$type=='B',c('season','peak_week_decimal','peak_amplitude')]
m0 <- readRDS('artifacts/m0-b-provisional-loso-v1/m0_b_loso.rds')$compare
ign <- read.csv('artifacts/m0-b-provisional-loso-v1/provisional_b_ignition_truth.csv', stringsAsFactors=FALSE)

gate_p <- as.numeric(Sys.getenv('PAGE_B_TIMING_GATE_P', unset='0.05'))
if(!is.finite(gate_p) || gate_p <= 0 || gate_p >= 1) stop('Invalid PAGE_B_TIMING_GATE_P')
# Causal B timing-availability gate: at least 40 B positives in trailing 4 weeks
# and trailing 4-week max positivity >= gate_p. The reviewed default is 5%.
gate_one <- function(z){
 z<-z[order(z$weekF),]
 sum4<-as.numeric(stats::filter(z$y,rep(1,4),sides=1))
 maxp4<-vapply(seq_len(nrow(z)),function(i)max(z$p[max(1,i-3):i],na.rm=TRUE),numeric(1))
 ok<-which(z$weekF>=18 & is.finite(sum4) & sum4>=40 & maxp4>=gate_p)
 if(length(ok)) z$weekF[min(ok)] else NA_real_
}
gates <- do.call(rbind,lapply(split(b,b$season),function(z)data.frame(season=z$season[1],gate_week=gate_one(z))))
activation <- Reduce(function(x,y)merge(x,y,by='season'),list(
  m0[,c('season','iWeek_hatF')],gates,ign[,c('season','ignition_target_weekF')],truth
))
activation$activation_week <- ifelse(is.finite(activation$gate_week),pmax(activation$iWeek_hatF,activation$gate_week),NA_real_)
activation$timing_available <- is.finite(activation$activation_week) & activation$activation_week < activation$peak_week_decimal

gate_tag <- sprintf('%dpct',round(100*gate_p))
out_dir <- file.path('artifacts',paste0('m1-b-gated-',gate_tag,'-prototype-v1'))
dir.create(out_dir,recursive=TRUE,showWarnings=FALSE)
write.csv(activation,file.path(out_dir,'activation_table.csv'),row.names=FALSE)
writeLines(sprintf('gate_p=%0.6f',gate_p),file.path(out_dir,'gate_config.txt'))

rows<-list(); libmeta<-list()
for(hold in seasons){
 train<-setdiff(seasons,hold)
 td<-b[b$season%in%train,]
 tt<-truth[truth$season%in%train,c('season','peak_week_decimal')]
 lib<-fit_m1_v2_library(td,tt,k=8L,grid_step=.01,tau_step=.1,
                        amplitude_grid=seq(.005,.25,by=.005))
 libmeta[[hold]]<-data.frame(season=hold,pc1_var=lib$forecast$pc1_variance_fraction,
                             min_train_peak=min(lib$peak_height),max_train_peak=max(lib$peak_height))
 z<-b[b$season==hold,]
 a<-activation[activation$season==hold,]
 Itruth<-a$ignition_target_weekF; Ttruth<-a$peak_week_decimal
 # Candidate-independent truth ledger: every integer origin from ceil(I*) until
 # the last release boundary strictly before T*. Model availability is separate.
 origins<-seq(ceiling(Itruth),floor(Ttruth-1e-8),by=1)
 for(o in origins){
   available<-isTRUE(a$timing_available) && o>=ceiling(a$activation_week) && (o+1)<Ttruth
   pred<-q05<-q95<-NA_real_; err<-NA_real_
   if(available){
     f<-tryCatch(m1_v2_peak_posterior(lib,z,activation_week=a$activation_week,
                                     origin_week=o,candidate_step=.1,max_future_weeks=14),
                 error=function(e)e)
     if(!inherits(f,'error')){
       pred<-f$summary$peak_mean[1];q05<-f$summary$peak_q05[1];q95<-f$summary$peak_q95[1];err<-pred-Ttruth
     } else available<-FALSE
   }
   rows[[length(rows)+1]]<-data.frame(season=hold,origin=o,Itruth=Itruth,Ttruth=Ttruth,
      m0_hat=a$iWeek_hatF,gate_week=a$gate_week,activation_week=a$activation_week,
      timing_available=available,pred_peak=pred,q05=q05,q95=q95,error=err,
      peak_amplitude=a$peak_amplitude,stringsAsFactors=FALSE)
 }
}
x<-do.call(rbind,rows);meta<-do.call(rbind,libmeta)
write.csv(x,file.path(out_dir,'per_origin.csv'),row.names=FALSE)
write.csv(meta,file.path(out_dir,'library_meta.csv'),row.names=FALSE)

per<-do.call(rbind,lapply(split(x,x$season),function(z){
 ok<-is.finite(z$pred_peak)
 data.frame(season=z$season[1],n_ledger=nrow(z),n_available=sum(ok),availability=mean(ok),
   mae=if(any(ok))mean(abs(z$error[ok])) else NA_real_,
   rmse=if(any(ok))sqrt(mean(z$error[ok]^2)) else NA_real_,
   bias=if(any(ok))mean(z$error[ok]) else NA_real_,
   coverage90=if(any(ok))mean(z$q05[ok]<=z$Ttruth[ok]&z$q95[ok]>=z$Ttruth[ok]) else NA_real_,
   peak_amplitude=z$peak_amplitude[1])
}))
write.csv(per,file.path(out_dir,'per_season.csv'),row.names=FALSE)
ok<-is.finite(per$mae)
summary<-data.frame(
 n_seasons=nrow(per),n_timing_seasons=sum(ok),overall_ledger_availability=sum(per$n_available)/sum(per$n_ledger),
 season_balanced_conditional_mae=mean(per$mae[ok]),
 season_balanced_conditional_rmse=mean(per$rmse[ok]),
 season_balanced_conditional_coverage90=mean(per$coverage90[ok]),
 low_signal_timing_seasons=sum(ok & per$peak_amplitude<=.05),
 epidemic_timing_seasons=sum(ok & per$peak_amplitude>.05)
)
write.csv(summary,file.path(out_dir,'summary.csv'),row.names=FALSE)
cat('B gated M1 prototype\n');print(summary,row.names=FALSE,digits=5);cat('\nPer season\n');print(per,row.names=FALSE,digits=4)
