source('PAGe/R/data_contract.R')
source('PAGe/R/expert_timing_annotations.R')
source('PAGe/R/retrospective_peak_truth.R')
source('PAGe/R/m1_v2.R')

campaign <- readRDS('artifacts/expert-ignition-annotation-v2-pass1/campaign_data.rds')
truth <- read.csv('artifacts/expert-ignition-annotation-v2-pass1/retrospective_peak_truth_v1.csv', stringsAsFactors=FALSE)
m0 <- read.csv('artifacts/m0-v2-decimal-loso-baseline-r2/compare.csv', stringsAsFactors=FALSE)
seasons <- as.character(truth$season)

ledger <- do.call(rbind,lapply(seasons,function(s){
  mr <- m0[m0$season==s,]; tr <- truth[truth$season==s,]
  orig <- seq(as.integer(mr$iWeek_hat), round(tr$peak_week_decimal), 1)
  data.frame(season=s,origin_weekF=orig,m0_integer=as.integer(mr$iWeek_hat),
             m0_decimal=mr$iWeek_hatF,truth_peak_decimal=tr$peak_week_decimal,
             truth_peak_integer=round(tr$peak_week_decimal))
}))
# Fixed before model comparison: first four primary origins per inner season.
cal_origins <- do.call(rbind,lapply(seasons,function(s) head(ledger[ledger$season==s,],4)))

causal_features <- function(season, origin, m0_decimal, pred_mean, q05, q95){
  z <- campaign[campaign$season==season & campaign$weekF<=origin & campaign$weekF>=ceiling(m0_decimal),]
  z <- z[order(z$weekF),]
  current_p <- tail(z$p,1)
  runmax_p <- max(z$p)
  width <- q95-q05
  skew <- if(is.finite(width) && width>0) (q95+q05-2*pred_mean)/width else 0
  data.frame(
    elapsed = origin-as.integer(m0_decimal),
    width = width,
    skew = skew,
    current_p = current_p,
    runmax_p = runmax_p,
    rel_to_runmax = current_p/pmax(runmax_p,1e-6),
    log_runmax = log(pmax(runmax_p,.002))
  )
}

# Generate pairwise inner predictions: for outer h and inner target s, library
# excludes both h and s. This is the reusable nested calibration dataset.
pair_rows <- list()
for(i in 1:(length(seasons)-1)) for(j in (i+1):length(seasons)){
  a <- seasons[i]; b <- seasons[j]
  train <- setdiff(seasons,c(a,b))
  lib <- fit_m1_v2_library(
    campaign[campaign$season%in%train,],
    truth[truth$season%in%train,c('season','peak_week_decimal')],
    k=8L, grid_step=.01, tau_step=.1
  )
  for(target in c(a,b)){
    outer_for <- if(target==a) b else a
    held <- campaign[campaign$season==target,]
    rr <- cal_origins[cal_origins$season==target,]
    for(k in seq_len(nrow(rr))){
      o <- rr$origin_weekF[k]
      fit <- m1_v2_peak_posterior(lib,held,rr$m0_decimal[k],o,candidate_step=.2)
      s <- fit$summary[1,]
      feat <- causal_features(target,o,rr$m0_decimal[k],s$peak_mean,s$peak_q05,s$peak_q95)
      pair_rows[[length(pair_rows)+1]] <- cbind(data.frame(
        outer_holdout=outer_for, inner_season=target, origin=o,
        m0_integer=rr$m0_integer[k], m0_decimal=rr$m0_decimal[k],
        pred=s$peak_mean, truth=rr$truth_peak_decimal[k],
        truth_integer=rr$truth_peak_integer[k],
        error=s$peak_mean-rr$truth_peak_decimal[k],
        weight=exp(-(0.1*(o-rr$m0_integer[k]))^2),
        stringsAsFactors=FALSE
      ),feat)
    }
  }
}
inner <- do.call(rbind,pair_rows)

# Small, predeclared calibration hierarchy. Outcome is signed timing error.
forms <- list(
  intercept = error ~ 1,
  elapsed = error ~ elapsed,
  width = error ~ width,
  elapsed_width = error ~ elapsed + width,
  elapsed_width_skew = error ~ elapsed + width + skew,
  elapsed_width_runmax = error ~ elapsed + width + log_runmax,
  elapsed_width_skew_runmax = error ~ elapsed + width + skew + log_runmax
)

fit_cal <- function(z, form){
  z$w_bal <- ave(z$weight,z$inner_season,FUN=function(v)v/sum(v))
  lm(form,data=z,weights=w_bal)
}

season_balanced_active <- function(z, pred_col){
  ss <- sort(unique(z$inner_season))
  mean(vapply(ss,function(s){
    q <- z[z$inner_season==s,]
    sum(q$weight*abs(round(q[[pred_col]])-q$truth_integer))/sum(q$weight)
  },numeric(1)))
}

# Outer prediction table from the full package replay; add exactly the same
# causal features used in inner calibration.
outer <- read.csv('artifacts/m1-v2-package-replay-v1-metric/current_11season_extension_per_origin.csv',stringsAsFactors=FALSE)
outer_feat <- do.call(rbind,lapply(seq_len(nrow(outer)),function(i){
  z <- outer[i,]
  causal_features(z$season,z$origin_weekF,z$m0_decimal,z$prediction_mean_decimal,z$q05,z$q95)
}))
outer <- cbind(outer,outer_feat)

selected_rows <- list(); pred_rows <- list(); inner_cv_rows <- list()
for(h in seasons){
  z <- inner[inner$outer_holdout==h,]
  inner_seasons <- sort(unique(z$inner_season))
  cv_scores <- numeric(length(forms)); names(cv_scores) <- names(forms)

  # Inner leave-one-season-out calibration-model selection using the active
  # integer metric. No outer-season outcomes are used here.
  for(fname in names(forms)){
    cv <- list()
    for(v in inner_seasons){
      tr <- z[z$inner_season!=v,]
      te <- z[z$inner_season==v,]
      mdl <- fit_cal(tr,forms[[fname]])
      te$err_hat <- as.numeric(predict(mdl,newdata=te))
      te$pred_cal <- te$pred-te$err_hat
      cv[[v]] <- te
    }
    cvz <- do.call(rbind,cv)
    cv_scores[fname] <- season_balanced_active(cvz,'pred_cal')
    inner_cv_rows[[length(inner_cv_rows)+1]] <- data.frame(outer_holdout=h,model=fname,active_integer=cv_scores[fname])
  }
  best <- names(which.min(cv_scores))
  # Deterministic complexity tie-break: first model in predeclared hierarchy.
  tied <- names(cv_scores)[abs(cv_scores-min(cv_scores))<1e-12]
  best <- names(forms)[match(TRUE,names(forms)%in%tied)]
  mdl <- fit_cal(z,forms[[best]])
  oo <- outer[outer$season==h,]
  oo$model_selected <- best
  oo$error_hat <- as.numeric(predict(mdl,newdata=oo))
  # Avoid pathological extrapolation from tiny inner samples; cap using only
  # the distribution of fitted inner corrections from this outer training fold.
  inner_hat <- as.numeric(predict(mdl,newdata=z))
  cap_lo <- as.numeric(quantile(inner_hat,.05,na.rm=TRUE))
  cap_hi <- as.numeric(quantile(inner_hat,.95,na.rm=TRUE))
  oo$error_hat_capped <- pmin(pmax(oo$error_hat,cap_lo),cap_hi)
  oo$pred_cal <- oo$prediction_mean_decimal-oo$error_hat_capped
  oo$pred_cal_integer <- round(oo$pred_cal)
  pred_rows[[h]] <- oo
  selected_rows[[h]] <- data.frame(
    season=h,model_selected=best,inner_cv_active=min(cv_scores),
    correction_min=cap_lo,correction_max=cap_hi,
    correction_mean=mean(oo$error_hat_capped),
    stringsAsFactors=FALSE
  )
}
cal <- do.call(rbind,pred_rows); rownames(cal)<-NULL
selected <- do.call(rbind,selected_rows); rownames(selected)<-NULL
inner_cv <- do.call(rbind,inner_cv_rows); rownames(inner_cv)<-NULL

score_outer <- function(pred,truthv){
  ss <- sort(unique(cal$season))
  mean(vapply(ss,function(s){
    z <- cal[cal$season==s,]
    sum(z$weight_early*abs(pred[cal$season==s]-truthv[cal$season==s]))/sum(z$weight_early)
  },numeric(1)))
}

# Scalar nested calibration baseline from prior experiment.
scalar <- read.csv('artifacts/m1-v2-nested-bias-calibration-11season/outer_predictions.csv',stringsAsFactors=FALSE)
scalar_score_int <- mean(vapply(sort(unique(scalar$season)),function(s){z<-scalar[scalar$season==s,];sum(z$weight_early*abs(z$pred_cal_integer-z$truth_peak_integer))/sum(z$weight_early)},numeric(1)))
scalar_score_dec <- mean(vapply(sort(unique(scalar$season)),function(s){z<-scalar[scalar$season==s,];sum(z$weight_early*abs(z$pred_cal-z$truth_peak_decimal))/sum(z$weight_early)},numeric(1)))

summary <- data.frame(
  method=c('uncalibrated','nested_scalar_bias','nested_feature_selected'),
  integer_metric=c(
    score_outer(cal$prediction_integer,cal$truth_peak_integer),
    scalar_score_int,
    score_outer(cal$pred_cal_integer,cal$truth_peak_integer)
  ),
  native_decimal_metric=c(
    score_outer(cal$prediction_mean_decimal,cal$truth_peak_decimal),
    scalar_score_dec,
    score_outer(cal$pred_cal,cal$truth_peak_decimal)
  )
)

per_season <- do.call(rbind,lapply(split(cal,cal$season),function(z){
  data.frame(
    season=z$season[1],model=z$model_selected[1],n=nrow(z),
    mean_correction=mean(z$error_hat_capped),
    uncal_int=sum(z$weight_early*abs(z$prediction_integer-z$truth_peak_integer))/sum(z$weight_early),
    cal_int=sum(z$weight_early*abs(z$pred_cal_integer-z$truth_peak_integer))/sum(z$weight_early),
    uncal_dec=sum(z$weight_early*abs(z$prediction_mean_decimal-z$truth_peak_decimal))/sum(z$weight_early),
    cal_dec=sum(z$weight_early*abs(z$pred_cal-z$truth_peak_decimal))/sum(z$weight_early)
  )
}))

dir.create('artifacts/m1-v2-nested-feature-calibration',recursive=TRUE,showWarnings=FALSE)
write.csv(inner,'artifacts/m1-v2-nested-feature-calibration/inner_predictions_features.csv',row.names=FALSE)
write.csv(inner_cv,'artifacts/m1-v2-nested-feature-calibration/inner_cv_model_scores.csv',row.names=FALSE)
write.csv(selected,'artifacts/m1-v2-nested-feature-calibration/selected_models.csv',row.names=FALSE)
write.csv(cal,'artifacts/m1-v2-nested-feature-calibration/outer_predictions.csv',row.names=FALSE)
write.csv(summary,'artifacts/m1-v2-nested-feature-calibration/summary.csv',row.names=FALSE)
write.csv(per_season,'artifacts/m1-v2-nested-feature-calibration/per_season.csv',row.names=FALSE)

cat('SELECTED MODELS\n');print(selected,row.names=FALSE,digits=4)
cat('\nSUMMARY\n');print(summary,row.names=FALSE,digits=5)
cat('\nPER SEASON\n');print(per_season,row.names=FALSE,digits=4)
