#!/usr/bin/env Rscript

source('PAGe/R/data_contract.R')
source('PAGe/R/stage_contracts.R')
source('PAGe/R/timing_pipeline_v2.R')
source('PAGe/R/m0_training.R')
source('PAGe/R/pipeline_training.R')
source('PAGe/R/expert_timing_annotations.R')
source('PAGe/R/retrospective_peak_truth.R')
source('PAGe/R/m1_v2.R')

ab_path <- 'artifacts/m2-v2-flu-ab-geometry-v1/flu_ab_long_v1.csv'
a_campaign_path <- 'artifacts/expert-ignition-annotation-v2-pass1/campaign_data.rds'
a_ignition_path <- 'artifacts/expert-ignition-annotation-v2-pass1/expert_ignition_labels_v2_pass1.csv'
out_dir <- 'artifacts/m2-v2-flu-b-timing-baselines-v1'
dir.create(out_dir, recursive=TRUE, showWarnings=FALSE)
dir.create(file.path(out_dir,'m0_loso_checkpoint'), recursive=TRUE, showWarnings=FALSE)

B <- read.csv(ab_path, stringsAsFactors=FALSE)
B <- B[B$type=='B',c('season','weekF','y','N','p','denominator_regime')]
B$season <- as.character(B$season)
B <- B[order(B$season,B$weekF),]
seasons <- sort(unique(B$season))
A <- readRDS(a_campaign_path)
A_ign <- read.csv(a_ignition_path, stringsAsFactors=FALSE)

# -----------------------------------------------------------------------------
# Provisional B ignition target transferred from expert-A ignition geometry.
# This is an exploratory retrospective measurement target, NOT frozen truth.
# We measure where expert A ignition lies between a low prepeak baseline and
# peak amplitude, then use the last upward crossing of the median fraction for B.
# -----------------------------------------------------------------------------
a_frac <- do.call(rbind,lapply(sort(unique(A$season)),function(s){
  z <- A[A$season==s,]
  fit <- retrospective_gam_peak_truth(z, season=s, k=8L, grid_step=.01)
  g <- fit$grid
  pre <- g[g$weekF<=fit$peak_week_decimal,]
  base <- as.numeric(stats::quantile(pre$fitted_p,.05))
  amp <- max(pre$fitted_p)
  I <- A_ign$ignition_week_decimal[A_ign$season==s]
  pI <- stats::approx(g$weekF,g$fitted_p,xout=I)$y
  data.frame(season=s,expert_I=I,baseline=base,peak=amp,
             excursion_fraction=(pI-base)/(amp-base))
}))
transfer_fraction <- stats::median(a_frac$excursion_fraction)

last_upward_crossing <- function(z, k=8L, fraction=transfer_fraction) {
  fit <- retrospective_gam_peak_truth(z, season=unique(z$season), k=k, grid_step=.01)
  g <- fit$grid
  pre <- g[g$weekF<=fit$peak_week_decimal,]
  base <- as.numeric(stats::quantile(pre$fitted_p,.05))
  amp <- max(pre$fitted_p)
  threshold <- base + fraction*(amp-base)
  above <- pre$fitted_p >= threshold
  crossings <- which(above & c(TRUE,!head(above,-1L)))
  I <- if(length(crossings)) pre$weekF[max(crossings)] else NA_real_
  data.frame(
    season=unique(z$season), k=k, ignition_week_decimal=I,
    peak_week_decimal=fit$peak_week_decimal,
    duration=fit$peak_week_decimal-I,
    baseline=base, peak_amplitude=amp, threshold=threshold,
    stringsAsFactors=FALSE
  )
}

# Check transfer rule against A experts.
a_rule <- do.call(rbind,lapply(sort(unique(A$season)),function(s){
  z <- A[A$season==s,]
  r <- last_upward_crossing(z, k=8L)
  r$expert_ignition <- A_ign$ignition_week_decimal[A_ign$season==s]
  r$error_vs_expert <- r$ignition_week_decimal-r$expert_ignition
  r
}))

ks <- c(5L,6L,8L,10L)
b_ign_sensitivity <- do.call(rbind,lapply(seasons,function(s){
  z <- B[B$season==s,c('season','weekF','y','N','p')]
  do.call(rbind,lapply(ks,function(k) last_upward_crossing(z,k=k)))
}))
b_ign_summary <- do.call(rbind,lapply(split(b_ign_sensitivity,b_ign_sensitivity$season),function(z){
  k8 <- z[z$k==8L,]
  data.frame(
    season=z$season[1], ignition_target_weekF=k8$ignition_week_decimal,
    peak_week_decimal=k8$peak_week_decimal,
    duration_k8=k8$duration, peak_amplitude=k8$peak_amplitude,
    ignition_low=min(z$ignition_week_decimal), ignition_high=max(z$ignition_week_decimal),
    ignition_range=max(z$ignition_week_decimal)-min(z$ignition_week_decimal),
    ignition_ambiguous=(max(z$ignition_week_decimal)-min(z$ignition_week_decimal))>1,
    peak_low=min(z$peak_week_decimal),peak_high=max(z$peak_week_decimal),
    peak_range=max(z$peak_week_decimal)-min(z$peak_week_decimal),
    peak_ambiguous=(max(z$peak_week_decimal)-min(z$peak_week_decimal))>1,
    stringsAsFactors=FALSE
  )
}))
b_ign_summary <- b_ign_summary[match(seasons,b_ign_summary$season),]

# -----------------------------------------------------------------------------
# Strict LOSO provisional M0-B using a small B-specific absolute threshold grid.
# The detector family and legacy asymmetric selector are unchanged.
# -----------------------------------------------------------------------------
B_m0 <- merge(B,b_ign_summary[,c('season','ignition_target_weekF')],by='season',all.x=TRUE,sort=FALSE)
B_m0$iWeek <- B_m0$ignition_target_weekF
B_m0$phase <- as.integer(B_m0$weekF>=ceiling(B_m0$iWeek))
m0_truth <- b_ign_summary[,c('season','ignition_target_weekF')]

m0_grid <- expand.grid(
  cls_thr=.26,use_cls=FALSE,
  p_thr=c(.0015,.0025,.004),
  prev_thr=c(.001,.002),
  n_consec=5L,L=2L,eps=0,K_sum=5L,
  p_sum_thr=c(.015,.025,.035),
  N_req=4L,w_min=c(18L,22L),w_max=c(35L,38L),
  K_dp=3L,dp_thr=.01,
  KEEP.OUT.ATTRS=FALSE,stringsAsFactors=FALSE
)
m0_grid <- m0_grid[m0_grid$w_min<m0_grid$w_max,]

m0_loso <- loso_M0v2(
  B_m0, grid=m0_grid,
  timing_truth=m0_truth,timing_mode='fractional',selection_policy='legacy',
  fit_args=list(
    fit_base=TRUE,fit_slope=FALSE,fit_fs=FALSE,event_k=1L,lead=1L,
    A_pre=8L,B_post=6L,k_week=6L,k_p=6L,k_fs=4L,select=FALSE,verbose=FALSE
  ),
  tune_args=list(
    miss_penalty=0,lambda=20,kappa=0,gamma=25,gamma_late=0,
    iWeek=TRUE,ncores=4L,verbose=FALSE,progress_every=200L
  ),
  verbose=FALSE, checkpoint_dir=file.path(out_dir,'m0_loso_checkpoint')
)
m0_compare <- as.data.frame(m0_loso$compare)

# -----------------------------------------------------------------------------
# Candidate-independent +1/+2 B0/B1 numeric baselines.
# B0 = persistence. B1 = season-balanced LOSO linear logit state/growth model.
# No timing features are consumed by either model.
# -----------------------------------------------------------------------------
D <- merge(B,b_ign_summary[,c('season','ignition_target_weekF','peak_week_decimal')],by='season',sort=FALSE)
D <- D[order(D$season,D$weekF),]
D$z <- stats::qlogis((D$y+.5)/(D$N+1))
D$dz <- ave(D$z,D$season,FUN=function(v)c(0,diff(v)))

forecast_rows <- list()
for(s in seasons) {
  z <- D[D$season==s,]
  for(h in 1:2) {
    n <- nrow(z)-h
    if(n<=0) next
    q <- z[seq_len(n),]
    q$lead <- paste0('h',h)
    q$target_week <- z$weekF[seq_len(n)+h]
    q$y_lead <- z$y[seq_len(n)+h]
    q$N_lead <- z$N[seq_len(n)+h]
    q$p_lead <- z$p[seq_len(n)+h]
    q$in_provisional_epidemic_ledger <-
      q$weekF>=floor(q$ignition_target_weekF) & q$weekF<=ceiling(q$peak_week_decimal)+2
    forecast_rows[[length(forecast_rows)+1L]] <- q
  }
}
forecast_data <- do.call(rbind,forecast_rows)
forecast_data$lead <- factor(forecast_data$lead,levels=c('h1','h2'))

forecast_data$z_future <- stats::qlogis((forecast_data$y_lead+.5)/(forecast_data$N_lead+1))
forecast_data$delta_future <- forecast_data$z_future-forecast_data$z

baseline_rows <- list()
for(holdout in seasons) {
  tr <- forecast_data[forecast_data$season!=holdout,]
  te <- forecast_data[forecast_data$season==holdout,]
  tr$season_lead <- interaction(tr$season,tr$lead,drop=TRUE)
  tr$season_balanced_weight <- ave(rep(1,nrow(tr)),tr$season_lead,FUN=function(v)1/length(v))
  # B1 preserves the observed current state and learns only a horizon-specific
  # logit-scale increment from recent growth. It cannot discard persistence.
  fit <- stats::lm(
    delta_future ~ 0 + lead + lead:dz,
    data=tr, weights=season_balanced_weight
  )
  te$prediction_B0 <- te$p
  te$prediction_B1 <- stats::plogis(te$z + stats::predict(fit,newdata=te))
  baseline_rows[[holdout]] <- te
}
baseline_predictions <- do.call(rbind,baseline_rows)

clip_prob <- function(p) pmin(pmax(p,1e-6),1-1e-6)
season_balanced_metrics <- function(df,pred_col) {
  per <- do.call(rbind,lapply(split(df,df$season),function(z){
    ph <- clip_prob(z[[pred_col]])
    data.frame(
      season=z$season[1],
      mae_pp=mean(abs(ph-z$p_lead))*100,
      rmse_pp=sqrt(mean((ph-z$p_lead)^2))*100,
      binomial_deviance_per_test=mean(
        -(z$y_lead*log(ph)+(z$N_lead-z$y_lead)*log(1-ph))/z$N_lead
      ),
      n=nrow(z),stringsAsFactors=FALSE
    )
  }))
  data.frame(
    mae_pp=mean(per$mae_pp),rmse_pp=mean(per$rmse_pp),
    binomial_deviance_per_test=mean(per$binomial_deviance_per_test),
    stringsAsFactors=FALSE
  )
}
metric_rows <- list()
for(scope in c('all','provisional_epidemic')) for(lead in c('all','h1','h2')) for(model in c('B0','B1')) {
  z <- baseline_predictions
  if(scope=='provisional_epidemic') z <- z[z$in_provisional_epidemic_ledger,]
  if(lead!='all') z <- z[as.character(z$lead)==lead,]
  m <- season_balanced_metrics(z,paste0('prediction_',model))
  metric_rows[[length(metric_rows)+1L]] <- cbind(
    data.frame(scope=scope,lead=lead,model=model,n_rows=nrow(z),stringsAsFactors=FALSE),m
  )
}
baseline_metrics <- do.call(rbind,metric_rows)

# -----------------------------------------------------------------------------
# M1-B diagnostics with a B-appropriate amplitude grid.
# 1) oracle activation upper bound;
# 2) causal provisional M0 activation;
# 3) activity-gate sensitivity after M0.
# -----------------------------------------------------------------------------
peak_truth <- b_ign_summary[,c('season','peak_week_decimal')]
b_amp_grid <- seq(.005,.25,.005)

libraries <- setNames(vector('list',length(seasons)),seasons)
for(h in seasons) {
  train <- setdiff(seasons,h)
  libraries[[h]] <- fit_m1_v2_library(
    B[B$season%in%train,c('season','weekF','y','N','p')],
    peak_truth[peak_truth$season%in%train,],
    k=8L,grid_step=.01,tau_step=.1,amplitude_grid=b_amp_grid
  )
}

run_m1_path <- function(holdout, activation, start_origin=NULL) {
  if(!is.finite(activation)) return(NULL)
  T <- peak_truth$peak_week_decimal[peak_truth$season==holdout]
  first <- if(is.null(start_origin)) ceiling(activation) else as.integer(start_origin)
  if(!is.finite(first) || first>floor(T)) return(NULL)
  held <- B[B$season==holdout,c('season','weekF','y','N','p')]
  out <- list()
  for(origin in seq(first,floor(T),by=1L)) {
    fit <- tryCatch(
      m1_v2_peak_posterior(libraries[[holdout]],held,activation,origin,
                           candidate_step=.1,max_future_weeks=16),
      error=function(e) NULL
    )
    if(is.null(fit)) next
    s <- fit$summary[1,]
    out[[length(out)+1L]] <- data.frame(
      season=holdout,origin=origin,activation=activation,true_peak=T,
      peak_mean=s$peak_mean,peak_q05=s$peak_q05,peak_q95=s$peak_q95,
      abs_error=abs(s$peak_mean-T),covered90=T>=s$peak_q05 & T<=s$peak_q95,
      stringsAsFactors=FALSE
    )
  }
  if(length(out)) do.call(rbind,out) else NULL
}

oracle_rows <- lapply(seasons,function(s){
  activation <- b_ign_summary$ignition_target_weekF[b_ign_summary$season==s]
  run_m1_path(s,activation)
})
oracle_m1 <- do.call(rbind,oracle_rows)

causal_rows <- lapply(seasons,function(s){
  mr <- m0_compare[m0_compare$season==s,]
  activation <- if(nrow(mr)==1L) mr$iWeek_hatF else NA_real_
  run_m1_path(s,activation)
})
causal_m1 <- do.call(rbind,causal_rows)

# Fixed evaluation ledger for timing availability: provisional I through floor(T).
ledger <- do.call(rbind,lapply(seasons,function(s){
  I <- b_ign_summary$ignition_target_weekF[b_ign_summary$season==s]
  T <- b_ign_summary$peak_week_decimal[b_ign_summary$season==s]
  data.frame(season=s,origin=seq(ceiling(I),floor(T),by=1L),stringsAsFactors=FALSE)
}))

activity_ready <- function(s,activation,p_threshold,count_threshold,window=4L) {
  if(!is.finite(activation)) return(NA_integer_)
  z <- B[B$season==s,]
  z <- z[order(z$weekF),]
  candidate_origins <- z$weekF[z$weekF>=ceiling(activation)]
  for(origin in candidate_origins) {
    w <- z[z$weekF<=origin & z$weekF>=origin-window+1L,]
    if(nrow(w)>=window && max(w$p)>=p_threshold && sum(w$y)>=count_threshold) return(as.integer(origin))
  }
  NA_integer_
}

gate_grid <- expand.grid(
  p_threshold=c(.010,.015,.020,.025),
  count_threshold=c(20L,40L,60L),
  KEEP.OUT.ATTRS=FALSE,stringsAsFactors=FALSE
)
gate_rows <- list(); gate_predictions <- list()
for(i in seq_len(nrow(gate_grid))) {
  g <- gate_grid[i,]
  ready_table <- do.call(rbind,lapply(seasons,function(s){
    mr <- m0_compare[m0_compare$season==s,]
    Ahat <- if(nrow(mr)==1L) mr$iWeek_hatF else NA_real_
    ready <- activity_ready(s,Ahat,g$p_threshold,g$count_threshold)
    peak_amp <- b_ign_summary$peak_amplitude[b_ign_summary$season==s]
    data.frame(season=s,activation=Ahat,ready_origin=ready,peak_amplitude=peak_amp,
               low_signal=peak_amp<=.05,stringsAsFactors=FALSE)
  }))
  preds <- do.call(rbind,lapply(seq_len(nrow(ready_table)),function(j){
    z <- ready_table[j,]
    if(!is.finite(z$ready_origin)) return(NULL)
    run_m1_path(z$season,z$activation,z$ready_origin)
  }))
  eligible_seasons <- if(!is.null(preds) && nrow(preds)) unique(preds$season) else character(0)
  ledger_ready <- merge(ledger,ready_table[,c('season','ready_origin')],by='season',all.x=TRUE,sort=FALSE)
  available <- is.finite(ledger_ready$ready_origin) & ledger_ready$origin>=ledger_ready$ready_origin
  per_season_mae <- if(!is.null(preds) && nrow(preds)) aggregate(abs_error~season,preds,mean) else data.frame()
  conditional_mae <- if(nrow(per_season_mae)) mean(per_season_mae$abs_error) else NA_real_
  gate_rows[[i]] <- data.frame(
    p_threshold=g$p_threshold,count_threshold=g$count_threshold,
    eligible_seasons=length(eligible_seasons),
    timing_available_origin_fraction=mean(available),
    low_signal_seasons_ready=sum(ready_table$low_signal & is.finite(ready_table$ready_origin)),
    conditional_season_balanced_m1_mae=conditional_mae,
    conditional_origin_mae=if(!is.null(preds) && nrow(preds)) mean(preds$abs_error) else NA_real_,
    stringsAsFactors=FALSE
  )
  if(!is.null(preds) && nrow(preds)) {
    preds$p_threshold <- g$p_threshold
    preds$count_threshold <- g$count_threshold
    gate_predictions[[i]] <- preds
  }
}
gate_sensitivity <- do.call(rbind,gate_rows)
gate_prediction_rows <- if(length(gate_predictions)) do.call(rbind,gate_predictions) else data.frame()

# -----------------------------------------------------------------------------
# Simpler B timing candidate family: no M0-B. A causal activity gate controls
# availability; the M1 likelihood receives only a short lookback preceding the
# gate. This avoids forcing B to have an A-like ignition detector. Candidate
# values are descriptive development candidates only; no winner is selected
# from held-out results here. Future governed selection must be nested.
# -----------------------------------------------------------------------------
activity_ready_no_m0 <- function(s,p_threshold,count_threshold,window=4L) {
  z <- B[B$season==s,]
  z <- z[order(z$weekF),]
  for(origin in z$weekF) {
    w <- z[z$weekF<=origin & z$weekF>=origin-window+1L,]
    if(nrow(w)>=window && max(w$p)>=p_threshold && sum(w$y)>=count_threshold) {
      return(as.integer(origin))
    }
  }
  NA_integer_
}

lookback_grid <- expand.grid(
  p_threshold=c(.015,.020), count_threshold=40L, lookback_weeks=c(4L,6L),
  KEEP.OUT.ATTRS=FALSE, stringsAsFactors=FALSE
)
lookback_rows <- list(); lookback_predictions <- list()
for(i in seq_len(nrow(lookback_grid))) {
  g <- lookback_grid[i,]
  ready_table <- do.call(rbind,lapply(seasons,function(s){
    ready <- activity_ready_no_m0(s,g$p_threshold,g$count_threshold)
    data.frame(season=s,ready_origin=ready,stringsAsFactors=FALSE)
  }))
  preds <- do.call(rbind,lapply(seq_len(nrow(ready_table)),function(j){
    z <- ready_table[j,]
    if(!is.finite(z$ready_origin)) return(NULL)
    activation <- max(min(B$weekF[B$season==z$season]), z$ready_origin-g$lookback_weeks)
    run_m1_path(z$season,activation,z$ready_origin)
  }))
  per <- if(!is.null(preds) && nrow(preds)) aggregate(abs_error~season,preds,mean) else data.frame()
  ledger_ready <- merge(ledger,ready_table,by='season',all.x=TRUE,sort=FALSE)
  available <- is.finite(ledger_ready$ready_origin) & ledger_ready$origin>=ledger_ready$ready_origin
  lookback_rows[[i]] <- data.frame(
    p_threshold=g$p_threshold,count_threshold=g$count_threshold,lookback_weeks=g$lookback_weeks,
    eligible_seasons=if(nrow(per)) nrow(per) else 0L,
    timing_available_origin_fraction=mean(available),
    conditional_season_balanced_m1_mae=if(nrow(per)) mean(per$abs_error) else NA_real_,
    conditional_origin_mae=if(!is.null(preds)&&nrow(preds)) mean(preds$abs_error) else NA_real_,
    stringsAsFactors=FALSE
  )
  if(!is.null(preds)&&nrow(preds)) {
    preds$p_threshold <- g$p_threshold
    preds$count_threshold <- g$count_threshold
    preds$lookback_weeks <- g$lookback_weeks
    lookback_predictions[[i]] <- preds
  }
}
lookback_sensitivity <- do.call(rbind,lookback_rows)
lookback_prediction_rows <- do.call(rbind,lookback_predictions)

# Passage safety diagnostic for the simple reference candidate (2%, 40
# positives, four-week lookback). This does not tune a B passage rule. We test
# the A-style hybrid only as a transfer diagnostic, plus a conservative fast
# branch requiring P(passed)>=0.95 and an immediate consecutive-week decline.
reference_p <- .020; reference_count <- 40L; reference_lookback <- 4L
passage_rows <- list()
for(s in seasons) {
  ready <- activity_ready_no_m0(s,reference_p,reference_count)
  T <- peak_truth$peak_week_decimal[peak_truth$season==s]
  truth_confirm <- ceiling(T)-1L
  if(!is.finite(ready)) {
    passage_rows[[s]] <- data.frame(season=s,ready_origin=NA_integer_,truth_confirm=truth_confirm,
                                    hybrid_confirm=NA_real_,fast_confirm=NA_real_)
    next
  }
  activation <- max(min(B$weekF[B$season==s]),ready-reference_lookback)
  held <- B[B$season==s,c('season','weekF','y','N','p')]
  passage_history <- data.frame()
  hybrid_confirm <- NA_real_; fast_confirm <- NA_real_
  last_origin <- min(max(held$weekF),truth_confirm+4L)
  for(origin in seq(ready,last_origin,by=1L)) {
    prefix <- held[held$weekF<=origin,]
    pp <- m1_v2_passage_posterior(libraries[[s]],prefix,activation,origin,
                                  candidate_step=.1,max_future_weeks=12)
    passage_history <- rbind(passage_history,pp)
    post <- prefix[prefix$weekF>=ceiling(activation),]
    post <- post[order(post$weekF),]
    immediate <- nrow(post)>=2L && diff(tail(post$weekF,2L))==1 &&
      tail(post$p,1L)<post$p[nrow(post)-1L]
    if(!is.finite(fast_confirm) && pp$prob_peak_passed>=.95 && immediate) fast_confirm <- origin
    if(!is.finite(hybrid_confirm)) {
      dec <- m1_v2_passage_decision(
        passage_history,prefix,activation,high_threshold=.95,low_threshold=.10,
        drop_fraction=.05,fast_drop_fraction=0,min_post_activation=4L
      )
      if(dec$peak_reached_or_passed) hybrid_confirm <- origin
    }
  }
  passage_rows[[s]] <- data.frame(season=s,ready_origin=ready,truth_confirm=truth_confirm,
                                  hybrid_confirm=hybrid_confirm,fast_confirm=fast_confirm)
}
passage_reference <- do.call(rbind,passage_rows)
passage_reference$hybrid_false_early <- is.finite(passage_reference$hybrid_confirm) &
  passage_reference$hybrid_confirm<passage_reference$truth_confirm
passage_reference$fast_false_early <- is.finite(passage_reference$fast_confirm) &
  passage_reference$fast_confirm<passage_reference$truth_confirm
passage_reference$hybrid_by_peak2 <- is.finite(passage_reference$hybrid_confirm) &
  passage_reference$hybrid_confirm<=passage_reference$truth_confirm+2L
passage_reference$fast_by_peak2 <- is.finite(passage_reference$fast_confirm) &
  passage_reference$fast_confirm<=passage_reference$truth_confirm+2L

# Median ignition-to-peak duration comparator, leave-one-season-out.
duration_baseline <- do.call(rbind,lapply(seasons,function(s){
  train <- b_ign_summary[b_ign_summary$season!=s,]
  I <- b_ign_summary$ignition_target_weekF[b_ign_summary$season==s]
  T <- b_ign_summary$peak_week_decimal[b_ign_summary$season==s]
  pred <- I + stats::median(train$peak_week_decimal-train$ignition_target_weekF)
  data.frame(season=s,prediction=pred,true_peak=T,abs_error=abs(pred-T),stringsAsFactors=FALSE)
}))

summary_metrics <- data.frame(
  metric=c(
    'A_transfer_fraction_median','A_transfer_rule_MAE_vs_expert','A_transfer_rule_bias_vs_expert',
    'B_provisional_ignition_ambiguous_n','B_peak_ambiguous_n',
    'M0_B_mean_abs_error','M0_B_median_abs_error','M0_B_max_abs_error','M0_B_misses',
    'M1_B_oracle_activation_origin_MAE','M1_B_oracle_activation_season_balanced_MAE',
    'M1_B_causal_M0_origin_MAE','M1_B_causal_M0_season_balanced_MAE',
    'B_duration_baseline_LOSO_MAE'
  ),
  value=c(
    transfer_fraction,mean(abs(a_rule$error_vs_expert)),mean(a_rule$error_vs_expert),
    sum(b_ign_summary$ignition_ambiguous),sum(b_ign_summary$peak_ambiguous),
    m0_loso$summary$mean_abs,m0_loso$summary$median_abs,m0_loso$summary$max_abs,m0_loso$summary$n_miss,
    mean(oracle_m1$abs_error),mean(aggregate(abs_error~season,oracle_m1,mean)$abs_error),
    mean(causal_m1$abs_error),mean(aggregate(abs_error~season,causal_m1,mean)$abs_error),
    mean(duration_baseline$abs_error)
  ),stringsAsFactors=FALSE
)

write.csv(a_frac,file.path(out_dir,'a_expert_ignition_excursion_fraction.csv'),row.names=FALSE)
write.csv(a_rule,file.path(out_dir,'a_transferred_rule_validation.csv'),row.names=FALSE)
write.csv(b_ign_sensitivity,file.path(out_dir,'b_provisional_ignition_sensitivity.csv'),row.names=FALSE)
write.csv(b_ign_summary,file.path(out_dir,'b_provisional_timing_truth.csv'),row.names=FALSE)
saveRDS(m0_loso,file.path(out_dir,'m0_b_loso_result.rds'))
write.csv(m0_compare,file.path(out_dir,'m0_b_compare.csv'),row.names=FALSE)
write.csv(baseline_predictions,file.path(out_dir,'m2_b0_b1_per_origin.csv'),row.names=FALSE)
write.csv(baseline_metrics,file.path(out_dir,'m2_b0_b1_metrics.csv'),row.names=FALSE)
write.csv(oracle_m1,file.path(out_dir,'m1_b_oracle_activation_per_origin.csv'),row.names=FALSE)
write.csv(causal_m1,file.path(out_dir,'m1_b_causal_m0_per_origin.csv'),row.names=FALSE)
write.csv(duration_baseline,file.path(out_dir,'m1_b_duration_baseline.csv'),row.names=FALSE)
write.csv(gate_sensitivity,file.path(out_dir,'m1_b_activity_gate_sensitivity.csv'),row.names=FALSE)
write.csv(gate_prediction_rows,file.path(out_dir,'m1_b_activity_gate_predictions.csv'),row.names=FALSE)
write.csv(lookback_sensitivity,file.path(out_dir,'m1_b_activity_lookback_sensitivity.csv'),row.names=FALSE)
write.csv(lookback_prediction_rows,file.path(out_dir,'m1_b_activity_lookback_predictions.csv'),row.names=FALSE)
write.csv(passage_reference,file.path(out_dir,'m1_b_passage_reference_diagnostic.csv'),row.names=FALSE)
write.csv(summary_metrics,file.path(out_dir,'summary_metrics.csv'),row.names=FALSE)

manifest <- data.frame(
  item=c('script','flu_ab_long','a_campaign','a_expert_ignition'),
  path=c('scripts/evaluate_flu_b_timing_baselines_v1.R',ab_path,a_campaign_path,a_ignition_path),
  sha256=c(
    digest::digest(file='scripts/evaluate_flu_b_timing_baselines_v1.R',algo='sha256',serialize=FALSE),
    digest::digest(file=ab_path,algo='sha256',serialize=FALSE),
    digest::digest(file=a_campaign_path,algo='sha256',serialize=FALSE),
    digest::digest(file=a_ignition_path,algo='sha256',serialize=FALSE)
  ),
  stringsAsFactors=FALSE
)
write.csv(manifest,file.path(out_dir,'source_manifest.csv'),row.names=FALSE)

cat('B provisional timing / baseline evaluation complete\n')
print(summary_metrics,row.names=FALSE,digits=5)
cat('\nB0/B1 metrics\n'); print(baseline_metrics,row.names=FALSE,digits=5)
cat('\nActivity gate sensitivity after provisional M0 (descriptive only)\n'); print(gate_sensitivity,row.names=FALSE,digits=5)
cat('\nActivity gate + short-lookback sensitivity, no M0 (descriptive only)\n'); print(lookback_sensitivity,row.names=FALSE,digits=5)
cat('\nReference B-passage safety diagnostic\n'); print(passage_reference,row.names=FALSE)
