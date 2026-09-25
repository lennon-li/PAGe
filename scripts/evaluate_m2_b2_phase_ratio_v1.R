#!/usr/bin/env Rscript

source('PAGe/R/data_contract.R')
source('PAGe/R/expert_timing_annotations.R')
source('PAGe/R/retrospective_peak_truth.R')
source('PAGe/R/m1_v2.R')

b_path <- 'artifacts/m2-v2-flu-ab-geometry-v1/flu_ab_long_v1.csv'
timing_path <- 'artifacts/m2-v2-flu-b-timing-baselines-v1/b_provisional_timing_truth.csv'
out_dir <- 'artifacts/m2-v2-b2-phase-ratio-v1'
dir.create(out_dir,recursive=TRUE,showWarnings=FALSE)

B <- read.csv(b_path,stringsAsFactors=FALSE)
B <- B[B$type=='B',c('season','weekF','y','N','p','denominator_regime')]
B <- B[order(B$season,B$weekF),]
truth <- read.csv(timing_path,stringsAsFactors=FALSE)
truth <- truth[,c('season','ignition_target_weekF','peak_week_decimal')]
seasons <- sort(unique(B$season))
if(!setequal(seasons,truth$season)) stop('B timing truth and B panel season sets differ.',call.=FALSE)

# Development candidate family frozen from the preceding descriptive timing audit.
# No held-out winner is selected in this script.
candidates <- expand.grid(
  p_threshold=c(.015,.020), count_threshold=40L, lookback_weeks=c(4L,6L),
  KEEP.OUT.ATTRS=FALSE,stringsAsFactors=FALSE
)

peak_truth <- truth[,c('season','peak_week_decimal')]
amplitude_grid <- seq(.005,.25,.005)
libraries <- setNames(vector('list',length(seasons)),seasons)
for(h in seasons) {
  train <- setdiff(seasons,h)
  libraries[[h]] <- fit_m1_v2_library(
    B[B$season%in%train,c('season','weekF','y','N','p')],
    peak_truth[peak_truth$season%in%train,],
    k=8L,grid_step=.01,tau_step=.1,amplitude_grid=amplitude_grid
  )
}

activity_ready <- function(z,p_threshold,count_threshold,window=4L) {
  z <- z[order(z$weekF),]
  for(origin in z$weekF) {
    w <- z[z$weekF<=origin & z$weekF>=origin-window+1L,]
    if(nrow(w)>=window && max(w$p)>=p_threshold && sum(w$y)>=count_threshold) return(as.integer(origin))
  }
  NA_integer_
}

phase_ratio_prediction <- function(lib,prefix,activation,origin,h,current_p) {
  pp <- tryCatch(
    m1_v2_passage_posterior(lib,prefix,activation_week=activation,
                            origin_week=origin,candidate_step=.1,max_future_weeks=12),
    error=function(e) NULL
  )
  if(is.null(pp)) return(list(pred=NA_real_,supported_mass=0,reason='posterior_unavailable'))
  post <- attr(pp,'posterior')
  comp <- lib$passage
  T <- post$peak_week_decimal
  w <- post$probability
  tau0 <- origin-T
  tauh <- origin+h-T
  support <- tau0>=min(comp$tau) & tau0<=max(comp$tau) &
    tauh>=min(comp$tau) & tauh<=max(comp$tau)
  mass <- sum(w[support])
  if(!is.finite(mass) || mass<.80) return(list(pred=NA_real_,supported_mass=mass,reason='insufficient_phase_support'))
  f0 <- stats::approx(comp$tau,comp$mean,xout=tau0[support])$y
  fh <- stats::approx(comp$tau,comp$mean,xout=tauh[support])$y
  ratio <- fh/pmax(f0,.02)
  ratio <- pmin(pmax(ratio,.20),5.0)
  ww <- w[support]/mass
  expected_ratio <- sum(ww*ratio)
  pred <- pmin(pmax(current_p*expected_ratio,0),1)
  list(pred=pred,supported_mass=mass,reason='timing_active')
}

rows <- list()
for(i in seq_len(nrow(candidates))) {
  cand <- candidates[i,]
  candidate_id <- sprintf('p%.3f_c%d_L%d',cand$p_threshold,cand$count_threshold,cand$lookback_weeks)
  for(s in seasons) {
    z <- B[B$season==s,]
    z <- z[order(z$weekF),]
    ready <- activity_ready(z,cand$p_threshold,cand$count_threshold)
    activation <- if(is.finite(ready)) max(min(z$weekF),ready-cand$lookback_weeks) else NA_real_
    I <- truth$ignition_target_weekF[truth$season==s]
    Ttrue <- truth$peak_week_decimal[truth$season==s]
    for(origin in z$weekF) for(h in 1:2) {
      target_week <- origin+h
      target <- z[z$weekF==target_week,]
      if(!nrow(target)) next
      current <- z[z$weekF==origin,]
      pred0 <- current$p
      pred2 <- pred0
      supported_mass <- 0
      status <- 'timing_unavailable'
      if(is.finite(ready) && origin>=ready) {
        prefix <- z[z$weekF<=origin,]
        pr <- phase_ratio_prediction(libraries[[s]],prefix,activation,origin,h,current$p)
        if(is.finite(pr$pred)) pred2 <- pr$pred
        supported_mass <- pr$supported_mass
        status <- pr$reason
      }
      rows[[length(rows)+1L]] <- data.frame(
        candidate_id=candidate_id,p_threshold=cand$p_threshold,
        count_threshold=cand$count_threshold,lookback_weeks=cand$lookback_weeks,
        season=s,origin_week=origin,horizon=h,target_week=target_week,
        ready_origin=ready,activation_week=activation,
        timing_status=status,phase_supported_mass=supported_mass,
        prediction_B0=pred0,prediction_B2=pred2,observed_p=target$p,
        y_target=target$y,N_target=target$N,
        in_provisional_epidemic_ledger=origin>=floor(I) & origin<=ceiling(Ttrue)+2,
        denominator_regime=target$denominator_regime,
        stringsAsFactors=FALSE
      )
    }
  }
}
pred <- do.call(rbind,rows)

clip <- function(p) pmin(pmax(p,1e-6),1-1e-6)
metric <- function(z,col) {
  per <- do.call(rbind,lapply(split(z,z$season),function(q){
    ph <- clip(q[[col]])
    data.frame(
      season=q$season[1],mae_pp=mean(abs(ph-q$observed_p))*100,
      rmse_pp=sqrt(mean((ph-q$observed_p)^2))*100,
      deviance_per_test=mean(-(q$y_target*log(ph)+(q$N_target-q$y_target)*log(1-ph))/q$N_target),
      n=nrow(q),stringsAsFactors=FALSE
    )
  }))
  c(mae_pp=mean(per$mae_pp),rmse_pp=mean(per$rmse_pp),
    deviance_per_test=mean(per$deviance_per_test))
}

summary_rows <- list()
for(cid in unique(pred$candidate_id)) for(scope in c('all','provisional_epidemic')) for(h in c(0,1,2)) {
  z <- pred[pred$candidate_id==cid,]
  if(scope=='provisional_epidemic') z <- z[z$in_provisional_epidemic_ledger,]
  if(h>0) z <- z[z$horizon==h,]
  for(model in c('B0','B2')) {
    m <- metric(z,paste0('prediction_',model))
    summary_rows[[length(summary_rows)+1L]] <- data.frame(
      candidate_id=cid,scope=scope,horizon=if(h==0)'all' else paste0('h',h),model=model,
      n_rows=nrow(z),mae_pp=m['mae_pp'],rmse_pp=m['rmse_pp'],
      deviance_per_test=m['deviance_per_test'],
      timing_active_fraction=mean(z$timing_status=='timing_active'),
      timing_unavailable_fraction=mean(z$timing_status=='timing_unavailable'),
      insufficient_support_fraction=mean(z$timing_status=='insufficient_phase_support'),
      stringsAsFactors=FALSE
    )
  }
}
summary <- do.call(rbind,summary_rows)

write.csv(pred,file.path(out_dir,'per_origin.csv'),row.names=FALSE)
write.csv(summary,file.path(out_dir,'summary.csv'),row.names=FALSE)
write.csv(candidates,file.path(out_dir,'candidate_family.csv'),row.names=FALSE)

cat('B2 phase-ratio development sensitivity (no candidate selected)\n')
for(cid in unique(summary$candidate_id)) {
  cat('\n',cid,'\n',sep='')
  print(summary[summary$candidate_id==cid & summary$scope=='provisional_epidemic',
                c('horizon','model','mae_pp','rmse_pp','deviance_per_test','timing_active_fraction')],
        row.names=FALSE,digits=5)
}
