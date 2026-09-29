#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE)

source('PAGe/R/data_contract.R')
source('PAGe/R/stage_contracts.R')
source('PAGe/R/m0_training.R')
source('PAGe/R/timing_pipeline_v2.R')
source('PAGe/R/expert_timing_annotations.R')
source('PAGe/R/retrospective_peak_truth.R')
source('PAGe/R/m1_v2.R')

if (!requireNamespace('digest', quietly=TRUE)) stop('Package `digest` is required.')

PANEL_PATH <- 'artifacts/v3-joint-ab-audit-v1/canonical_ab_weekly_v3.csv'
TIMING_PATH <- 'artifacts/v3-joint-timing-contract-v2/timing_contract_v3.csv'
BASE_PATH <- 'artifacts/v3-m1-chronological-baselines-v1/per_origin_predictions.csv'
FOLD_PATH <- 'artifacts/v3-m1-chronological-baselines-v1/fold_ledger.csv'
A_ACT_PATH <- 'artifacts/v3-m1-chronological-baselines-v1/A_frozen_m0_activation.csv'
OUT <- 'artifacts/v3-m1-b1-a-conditioned-v1'

dir.create(OUT, recursive=TRUE, showWarnings=FALSE)

CANDIDATE_STEP <- 0.1
B_MAX_FUTURE <- 16
A_PASSAGE_MAX_FUTURE <- 12
B_AMP_GRID <- seq(.005,.25,by=.005)
H_PRIMARY <- 2.0
EPS_PRIMARY <- 0.10
SENS_H <- c(1,3)
SENS_EPS <- c(.05)

sha256_file <- function(path) digest::digest(file=path,algo='sha256',serialize=FALSE)
season_start <- function(s) as.integer(substr(as.character(s),1,4))

panel <- read.csv(PANEL_PATH,check.names=FALSE)
truth <- read.csv(TIMING_PATH,check.names=FALSE)
base <- read.csv(BASE_PATH,check.names=FALSE)
folds <- read.csv(FOLD_PATH,check.names=FALSE)
A_act <- read.csv(A_ACT_PATH,check.names=FALSE)

A <- data.frame(season=panel$season,weekF=panel$weekF,y=panel$y_A,N=panel$N_A,p=panel$p_A)
B <- data.frame(season=panel$season,weekF=panel$weekF,y=panel$y_B,N=panel$N_B,p=panel$p_B)
A <- A[order(season_start(A$season),A$weekF),]
B <- B[order(season_start(B$season),B$weekF),]

baseB <- base[base$type=='B',]
if (!nrow(baseB)) stop('No B baseline origins found.')

normal_mixture_density <- function(grid, centers, weights=NULL, h=2) {
  centers <- as.numeric(centers)
  if (!length(centers) || any(!is.finite(centers))) stop('Invalid prior centers.')
  if (is.null(weights)) weights <- rep(1/length(centers),length(centers))
  weights <- as.numeric(weights); weights <- weights/sum(weights)
  dens <- vapply(grid,function(x) sum(weights*stats::dnorm(x,mean=centers,sd=h)),numeric(1))
  dens
}

mix_prior_density <- function(grid, structured_density, epsilon) {
  width <- max(grid)-min(grid)+median(diff(grid))
  unif <- rep(1/width,length(grid))
  (1-epsilon)*structured_density + epsilon*unif
}

in_range_mass_normals <- function(lo,hi,centers,weights=NULL,h=2) {
  if (is.null(weights)) weights <- rep(1/length(centers),length(centers))
  weights <- weights/sum(weights)
  sum(weights*(stats::pnorm(hi,centers,h)-stats::pnorm(lo,centers,h)))
}

summarize_from_loge_prior <- function(base_fit, prior_density) {
  post <- base_fit$posterior
  if (length(prior_density)!=nrow(post) || any(!is.finite(prior_density)) || any(prior_density<=0)) stop('Invalid prior density.')
  lp <- post$log_evidence + log(prior_density)
  w <- exp(lp-max(lp)); w <- w/sum(w)
  out <- post
  out$probability <- w
  out$log_prior_density <- log(prior_density)
  out$log_posterior_unnorm <- lp
  list(posterior=out,summary=.summarize_m1_v2_posterior(out,base_fit$asof_boundary))
}

js_divergence <- function(p,q) {
  p <- p/sum(p); q <- q/sum(q); m <- .5*(p+q)
  .5*sum(ifelse(p>0,p*log(p/m),0)) + .5*sum(ifelse(q>0,q*log(q/m),0))
}

discrete_log_score <- function(post,truth_peak) {
  i <- which.min(abs(post$peak_week_decimal-truth_peak))
  log(max(post$probability[i],1e-15))
}

# Sequential causal A state. Once passage is first confirmed, freeze that exact
# passage posterior for all later origins.
build_a_timing_cache <- function(libA, heldA, activation, max_origin) {
  start <- ceiling(activation)
  hist <- NULL
  rows <- list(); first_confirm <- NA_integer_; frozen <- NULL
  for (o in seq.int(start,max_origin)) {
    pp <- tryCatch(m1_v2_passage_posterior(libA,heldA,activation,o,
                                            candidate_step=CANDIDATE_STEP,
                                            max_future_weeks=A_PASSAGE_MAX_FUTURE),
                   error=function(e) NULL)
    if (is.null(pp)) next
    hist <- rbind(hist,pp)
    dec <- m1_v2_passage_decision(hist,heldA,activation)
    current_post <- attr(pp,'posterior')
    if (!is.finite(first_confirm) && isTRUE(dec$peak_reached_or_passed)) {
      first_confirm <- o
      frozen <- current_post
    }
    use_post <- if (is.finite(first_confirm) && o>=first_confirm) frozen else current_post
    s <- .summarize_m1_v2_posterior(use_post,o+1)
    rows[[as.character(o)]] <- list(
      state=if (is.finite(first_confirm) && o>=first_confirm) 'passage_confirmed_frozen' else 'activated_unconfirmed',
      first_confirmation_origin=first_confirm,
      posterior=use_post,
      mean=s$peak_mean,median=s$peak_median,map=s$peak_map,
      passage_prob=pp$prob_peak_passed
    )
  }
  rows
}

get_a_state <- function(cache, origin, activation) {
  if (origin < ceiling(activation)) return(list(state='not_activated',posterior=NULL,first_confirmation_origin=NA_integer_,mean=NA,median=NA,map=NA,passage_prob=NA))
  keys <- as.integer(names(cache)); eligible <- keys[keys<=origin]
  if (!length(eligible)) return(list(state='a_timing_failure',posterior=NULL,first_confirmation_origin=NA_integer_,mean=NA,median=NA,map=NA,passage_prob=NA))
  cache[[as.character(max(eligible))]]
}

make_a_prior <- function(grid,a_state,lags,h,epsilon) {
  if (is.null(a_state$posterior)) return(NULL)
  ap <- a_state$posterior
  centers <- as.vector(outer(ap$peak_week_decimal,lags,'+'))
  weights <- as.vector(outer(ap$probability,rep(1/length(lags),length(lags)),'*'))
  structured <- normal_mixture_density(grid,centers,weights,h)
  mixed <- mix_prior_density(grid,structured,epsilon)
  step <- median(diff(grid)); lo <- min(grid)-step/2; hi <- max(grid)+step/2
  in_mass <- in_range_mass_normals(lo,hi,centers,weights,h)
  list(density=mixed,structured_density=structured,in_range_mass=in_mass,centers=centers,weights=weights)
}

make_cal_prior <- function(grid,b_peaks,h,epsilon) {
  structured <- normal_mixture_density(grid,b_peaks,NULL,h)
  mixed <- mix_prior_density(grid,structured,epsilon)
  step <- median(diff(grid)); lo <- min(grid)-step/2; hi <- max(grid)+step/2
  in_mass <- in_range_mass_normals(lo,hi,b_peaks,NULL,h)
  list(density=mixed,structured_density=structured,in_range_mass=in_mass)
}

pred_rows <- list(); prior_rows <- list(); leak_rows <- list(); sensitivity_rows <- list()

for (test in unique(baseB$season)) {
  fold <- folds[folds$test_season==test,]
  if (nrow(fold)!=1L) stop('Missing fold for ',test)
  prior_seasons <- strsplit(fold$training_seasons,';',fixed=TRUE)[[1]]
  train_timing <- truth[truth$season %in% prior_seasons & is.finite(truth$B_peak_weekF),]
  if (nrow(train_timing)<4L) stop('Insufficient timing-eligible training seasons for ',test)

  trainA <- A[A$season %in% prior_seasons,]
  truthA <- truth[truth$season %in% prior_seasons,c('season','A_peak_weekF')]
  names(truthA)[2] <- 'peak_week_decimal'
  libA <- fit_m1_v2_library(trainA,truthA,k=8L,grid_step=.01,tau_step=.1)

  trainB <- B[B$season %in% train_timing$season,]
  truthB <- train_timing[,c('season','B_peak_weekF')]
  names(truthB)[2] <- 'peak_week_decimal'
  libB <- fit_m1_v2_library(trainB,truthB,k=8L,grid_step=.01,tau_step=.1,amplitude_grid=B_AMP_GRID)

  lags <- train_timing$B_peak_weekF-train_timing$A_peak_weekF
  cor_a_lag <- if (length(lags)>=3 && stats::sd(train_timing$A_peak_weekF)>0 && stats::sd(lags)>0) stats::cor(train_timing$A_peak_weekF,lags) else NA_real_
  cor_ab <- if (length(lags)>=3 && stats::sd(train_timing$A_peak_weekF)>0 && stats::sd(train_timing$B_peak_weekF)>0) stats::cor(train_timing$A_peak_weekF,train_timing$B_peak_weekF) else NA_real_
  prior_rows[[length(prior_rows)+1L]] <- data.frame(
    test_season=test,n_train=nrow(train_timing),training_seasons=paste(train_timing$season,collapse=';'),
    A_peaks=paste(sprintf('%.4f',train_timing$A_peak_weekF),collapse=';'),
    B_peaks=paste(sprintf('%.4f',train_timing$B_peak_weekF),collapse=';'),
    lags=paste(sprintf('%.4f',lags),collapse=';'),cor_Apeak_lag=cor_a_lag,cor_Apeak_Bpeak=cor_ab,
    h=H_PRIMARY,epsilon=EPS_PRIMARY,stringsAsFactors=FALSE)

  heldA <- A[A$season==test,]
  heldB <- B[B$season==test,]
  activationA <- A_act$iWeek_hatF[A_act$season==test]
  if (length(activationA)!=1L || !is.finite(activationA)) stop('Missing A activation for ',test)
  test_origins <- sort(baseB$origin_weekF[baseB$season==test])
  cacheA <- build_a_timing_cache(libA,heldA,activationA,max(test_origins))

  b_activity <- truth$B_activity_weekF[truth$season==test]
  b_truth <- truth$B_peak_weekF[truth$season==test]
  if (!is.finite(b_activity) || !is.finite(b_truth)) stop('B test timing missing for ',test)

  for (o in test_origins) {
    bfit <- m1_v2_peak_posterior(libB,heldB,b_activity,o,candidate_step=CANDIDATE_STEP,max_future_weeks=B_MAX_FUTURE)
    stored <- baseB[baseB$season==test & baseB$origin_weekF==o,]
    if (nrow(stored)!=1L) stop('Stored B0 origin mismatch.')
    if (abs(bfit$summary$peak_mean-stored$pred_peak_mean)>1e-8) stop('Recomputed B0 differs from frozen baseline at ',test,'/',o)

    grid <- bfit$posterior$peak_week_decimal
    b0 <- bfit
    cal_prior <- make_cal_prior(grid,train_timing$B_peak_weekF,H_PRIMARY,EPS_PRIMARY)
    bcal <- summarize_from_loge_prior(bfit,cal_prior$density)

    ast <- get_a_state(cacheA,o,activationA)
    fallback <- FALSE; fallback_reason <- NA_character_
    aprior <- NULL
    if (ast$state %in% c('not_activated','a_timing_failure') || is.null(ast$posterior)) {
      fallback <- TRUE; fallback_reason <- ast$state
      ba <- list(posterior=bfit$posterior,summary=bfit$summary)
      a_in_mass <- NA_real_
    } else {
      aprior <- make_a_prior(grid,ast,lags,H_PRIMARY,EPS_PRIMARY)
      ba <- summarize_from_loge_prior(bfit,aprior$density)
      a_in_mass <- aprior$in_range_mass
    }

    models <- list(B0=list(summary=b0$summary,posterior=b0$posterior,inmass=NA_real_),
                   B1_cal=list(summary=bcal$summary,posterior=bcal$posterior,inmass=cal_prior$in_range_mass),
                   B1_A=list(summary=ba$summary,posterior=ba$posterior,inmass=a_in_mass))
    for (mn in names(models)) {
      mm <- models[[mn]]; s <- mm$summary
      pred_rows[[length(pred_rows)+1L]] <- data.frame(
        season=test,origin_weekF=o,model=mn,truth_peak_weekF=b_truth,
        pred_peak_mean=s$peak_mean,pred_peak_median=s$peak_median,pred_peak_map=s$peak_map,
        q05=s$peak_q05,q95=s$peak_q95,error=s$peak_mean-b_truth,abs_error=abs(s$peak_mean-b_truth),
        covered90=s$peak_q05<=b_truth && s$peak_q95>=b_truth,
        log_score=discrete_log_score(mm$posterior,b_truth),
        structured_prior_in_range_mass=mm$inmass,
        js_from_B0=if(mn=='B0') 0 else js_divergence(b0$posterior$probability,mm$posterior$probability),
        A_state=ast$state,A_activation_weekF=activationA,
        A_first_confirmation_origin=ast$first_confirmation_origin,
        A_peak_mean_used=ast$mean,A_peak_median_used=ast$median,A_peak_map_used=ast$map,
        A_passage_prob_current=ast$passage_prob,
        fallback=fallback && mn=='B1_A',fallback_reason=if(mn=='B1_A') fallback_reason else NA_character_,
        weight_early=stored$weight_early,stringsAsFactors=FALSE)
    }

    # Sensitivities for A-conditioned and calendar controls.
    for (h in c(SENS_H,H_PRIMARY)) for (eps in c(SENS_EPS,EPS_PRIMARY)) {
      if (h==H_PRIMARY && eps==EPS_PRIMARY) next
      cp <- make_cal_prior(grid,train_timing$B_peak_weekF,h,eps)
      cs <- summarize_from_loge_prior(bfit,cp$density)$summary
      sensitivity_rows[[length(sensitivity_rows)+1L]] <- data.frame(season=test,origin_weekF=o,model='B1_cal',h=h,epsilon=eps,pred=cs$peak_mean,abs_error=abs(cs$peak_mean-b_truth))
      if (!fallback) {
        ap <- make_a_prior(grid,ast,lags,h,eps)
        as <- summarize_from_loge_prior(bfit,ap$density)$summary
        sensitivity_rows[[length(sensitivity_rows)+1L]] <- data.frame(season=test,origin_weekF=o,model='B1_A',h=h,epsilon=eps,pred=as$peak_mean,abs_error=abs(as$peak_mean-b_truth))
      }
    }

    # Every-origin future perturbation checks for A and B.
    heldB2 <- heldB; ib <- heldB2$weekF>o
    if (any(ib)) { heldB2$y[ib] <- pmin(heldB2$N[ib],heldB2$y[ib]+7); heldB2$p[ib] <- heldB2$y[ib]/heldB2$N[ib] }
    bfit2 <- m1_v2_peak_posterior(libB,heldB2,b_activity,o,candidate_step=CANDIDATE_STEP,max_future_weeks=B_MAX_FUTURE)
    passB <- max(abs(bfit2$posterior$probability-bfit$posterior$probability))<1e-12

    heldA2 <- heldA; ia <- heldA2$weekF>o
    if (any(ia)) { heldA2$y[ia] <- pmin(heldA2$N[ia],heldA2$y[ia]+7); heldA2$p[ia] <- heldA2$y[ia]/heldA2$N[ia] }
    cacheA2 <- build_a_timing_cache(libA,heldA2,activationA,o)
    ast2 <- get_a_state(cacheA2,o,activationA)
    state_equal <- identical(ast$state,ast2$state) && isTRUE(all.equal(ast$first_confirmation_origin,ast2$first_confirmation_origin))
    post_equal <- if (is.null(ast$posterior) && is.null(ast2$posterior)) TRUE else if (!is.null(ast$posterior) && !is.null(ast2$posterior)) {
      identical(ast$posterior$peak_week_decimal,ast2$posterior$peak_week_decimal) && max(abs(ast$posterior$probability-ast2$posterior$probability))<1e-12
    } else FALSE
    passA <- state_equal && post_equal
    leak_rows[[length(leak_rows)+1L]] <- data.frame(season=test,origin_weekF=o,future_B_invariant=passB,future_A_invariant=passA,stringsAsFactors=FALSE)
    if (!passA || !passB) stop('Future perturbation leakage check failed at ',test,'/',o)
  }
}

pred <- do.call(rbind,pred_rows)
prior_ledger <- do.call(rbind,prior_rows)
leak <- do.call(rbind,leak_rows)
sens <- do.call(rbind,sensitivity_rows)

# Exact pairing contract.
key_counts <- aggregate(model~season+origin_weekF,pred,length)
if (any(key_counts$model!=3L)) stop('B0/B1-cal/B1-A origin pairing failed.')

per_season <- do.call(rbind,lapply(split(pred,list(pred$model,pred$season),drop=TRUE),function(z){
  data.frame(model=z$model[1],season=z$season[1],n_origins=nrow(z),mae=mean(z$abs_error),rmse=sqrt(mean(z$error^2)),bias=mean(z$error),
             early_weighted_mae=sum(z$weight_early*z$abs_error)/sum(z$weight_early),coverage90=mean(z$covered90),mean_log_score=mean(z$log_score),
             stringsAsFactors=FALSE)
}))
per_season <- per_season[order(per_season$model,season_start(per_season$season)),]

summary <- do.call(rbind,lapply(split(per_season,per_season$model),function(z){
  data.frame(model=z$model[1],n_test_seasons=nrow(z),n_origins=sum(z$n_origins),season_balanced_mae=mean(z$mae),
             season_balanced_rmse=mean(z$rmse),season_balanced_bias=mean(z$bias),season_balanced_early_weighted_mae=mean(z$early_weighted_mae),
             mean_coverage90=mean(z$coverage90),mean_log_score=mean(z$mean_log_score),worst_season_mae=max(z$mae),stringsAsFactors=FALSE)
}))

wide <- reshape(per_season[,c('model','season','mae','early_weighted_mae')],idvar='season',timevar='model',direction='wide')
if (all(c('mae.B0','mae.B1_cal','mae.B1_A') %in% names(wide))) {
  wide$delta_A_vs_B0 <- wide$mae.B1_A-wide$mae.B0
  wide$delta_A_vs_cal <- wide$mae.B1_A-wide$mae.B1_cal
  wide$delta_cal_vs_B0 <- wide$mae.B1_cal-wide$mae.B0
  wide$delta_Aew_vs_B0 <- wide$early_weighted_mae.B1_A-wide$early_weighted_mae.B0
  wide$delta_Aew_vs_cal <- wide$early_weighted_mae.B1_A-wide$early_weighted_mae.B1_cal
}

write.csv(pred,file.path(OUT,'per_origin_predictions.csv'),row.names=FALSE)
write.csv(prior_ledger,file.path(OUT,'lag_prior_by_fold.csv'),row.names=FALSE)
write.csv(leak,file.path(OUT,'future_perturbation_checks.csv'),row.names=FALSE)
write.csv(sens,file.path(OUT,'sensitivity_predictions.csv'),row.names=FALSE)
write.csv(per_season,file.path(OUT,'per_season_metrics.csv'),row.names=FALSE)
write.csv(summary,file.path(OUT,'summary_metrics.csv'),row.names=FALSE)
write.csv(wide,file.path(OUT,'paired_b0_b1_deltas.csv'),row.names=FALSE)
write.csv(folds,file.path(OUT,'fold_ledger.csv'),row.names=FALSE)

manifest_paths <- c(PANEL_PATH,TIMING_PATH,BASE_PATH,FOLD_PATH,A_ACT_PATH)
manifest <- data.frame(role=c('canonical_panel','timing_contract','B0_baseline','fold_ledger','A_frozen_m0_activation'),path=manifest_paths,
                       sha256=vapply(manifest_paths,sha256_file,character(1)),stringsAsFactors=FALSE)
write.csv(manifest,file.path(OUT,'source_manifest.csv'),row.names=FALSE)

config <- data.frame(key=c('version','primary_h','primary_epsilon','candidate_step','B_max_future','A_passage_max_future','B_amplitude_grid','A_timing_after_passage','B0_match_required','feasibility_peek_disclosure'),
                     value=c('v3-m1-b1-a-conditioned-v1',H_PRIMARY,EPS_PRIMARY,CANDIDATE_STEP,B_MAX_FUTURE,A_PASSAGE_MAX_FUTURE,'0.005:0.005:0.25','freeze_first_confirmed_passage_posterior','TRUE','held-out timing geometry inspected during design'),stringsAsFactors=FALSE)
write.csv(config,file.path(OUT,'benchmark_config.csv'),row.names=FALSE)

cat('M1-B1 audited implementation complete\n')
print(summary,row.names=FALSE,digits=5)
cat('\nPaired per-season deltas (negative is better for A-conditioned)\n')
print(wide,row.names=FALSE,digits=5)
