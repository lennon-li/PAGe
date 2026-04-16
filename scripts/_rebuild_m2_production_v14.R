#!/usr/bin/env Rscript
# Rebuild m2_production.rds with v14 best spec (bias_alpha=0.2, alpha_state=0.40)
cat("=== Rebuild m2_production.rds (v14 spec) ===\n")

suppressPackageStartupMessages({
  library(PAGe); library(dplyr); library(purrr); library(mgcv); library(MMWRweek)
})
for (f in c('R/utils.R','R/m0_retro.R','R/flagIgnition.R',
            'R/m1_reference.R','R/m1_reference_helpers.R','R/m1_multi_template.R',
            'R/m2_spec_grid.R','R/m2_training.R','R/m2_nested_loso.R',
            'R/pipeline_bridge.R','R/pipeline_runtime_helpers.R')) source(f)

n_weeks_in_start_year <- function(sy)
  52L + as.integer(MMWRweek::MMWRweek(as.Date(paste0(sy,'-12-31')))$MMWRweek == 53L)

allD <- read.csv('data/flu_testing_data.csv') |>
  dplyr::select(season, week, year, start_year=seasonstart,
                date=week_start_date, y=pos_flua, N=test_flu) |>
  dplyr::mutate(neg=N-y, date=as.Date(date),
                nW_true=n_weeks_in_start_year(start_year),
                weekF=((week-27L)%%nW_true)+1L, p=y/N)

params        <- readRDS('data/stage1_tuning.rds')$best_params
manual_labels <- c('2012-13'=18L,'2013-14'=20L,'2014-15'=20L,'2015-16'=24L,
                   '2016-17'=19L,'2017-18'=20L,'2018-19'=19L,'2019-20'=22L,
                   '2022-23'=15L,'2023-24'=20L,'2024-25'=23L)
flag_args <- list(p_thresh=0.01,k1=0.4,k_c=0.01,n_consec=2L,
                  min_window=10L,w_min=21L,w_max=21L,d2_relax=-0.01)
EXCLUDE_PERM <- c('2011-12','2015-16','2020-21','2021-22')

train_allD <- allD |> dplyr::filter(!season %in% EXCLUDE_PERM)
train_seas  <- sort(unique(train_allD$season))
cat('Training:', paste(train_seas, collapse=', '), '\n')

cat('M0: estimateDerivs...\n')
res_deriv <- estimateDerivs(train_allD, k=10L)
train_outs <- res_deriv$data |>
  dplyr::group_by(season) |> dplyr::group_split(.keep=TRUE) |>
  purrr::map(function(df) do.call(flagIgnition, c(list(df=df, manual_labels=manual_labels), flag_args)))
aligned_train <- alignIgnition(train_outs)
cat('aligned_train:', nrow(aligned_train), 'rows\n')

cat('M1: estimateRef...\n')
ref   <- estimateRef(alignedD=aligned_train, exSeason=character(0), k=25L, n_weeks=52L, method='fs')
hyper <- learn_alignment_hyperparams(ref$dat, ref$g_ref_fun)
template_df <- ref$pred_df[, c('newWeek','fit')]
cat('ref built, eta_mat:', nrow(ref$eta_mat), 'x', ncol(ref$eta_mat), '\n')

cat('M1: walk-forward predictions...\n')
m1_train_preds <- m1_walkforward_multi(
  allD=allD, ref=ref, hyper=hyper, params=params, seasons=train_seas,
  temperature=0.25, rise_weight=1.0, trough_weight=0.1, peak_decay=0.3,
  slope_weight=0.5, slope_window=4L, dynamic_temp=TRUE, dynamic_temp_pivot=10L,
  parallel=FALSE, verbose=FALSE)
cat('m1_train_preds:', nrow(m1_train_preds), 'rows\n')

spec <- stage2_make_spec(delta=0L, Kr=1L, T='S', k_f=4L, k_e=2L,
  alpha_state=0.40, k_r=2L, k_de=0L, k_n=0L, k_w=0L, k_s=0L,
  lambda_w=0, w_floor=0.05, bias_alpha=0.2, bias_beta=0.0)

cat('M2: fitting production GAM...\n')
joint_out <- train_stage2_joint(
  dat=add_prospective_derivs_link(aligned_train),
  template_df=template_df, spec=spec, method='REML',
  m1_preds=if(nrow(m1_train_preds)>0) m1_train_preds else NULL, verbose=FALSE)
# train_stage2_joint returns a list; unwrap to get the bare GAM and feature_ranges
gam_fit        <- joint_out$fit            # actual bam/gam object
feature_ranges <- joint_out$feature_ranges # list(z_ema=c(lo,hi), logit_f_eff=c(lo,hi))
cat('GAM fit done. EDF:', round(sum(gam_fit$edf),2), '\n')
cat('model[[1]] dim:', paste(dim(gam_fit$model[[1]]), collapse='x'), '\n')
cat('z_ema: [', paste(round(feature_ranges$z_ema,2),collapse=', '), ']\n')
cat('logit_f_eff: [', paste(round(feature_ranges$logit_f_eff,2),collapse=', '), ']\n')

saveRDS(list(spec=spec, fit=gam_fit, feature_ranges=feature_ranges,
             m1_train_preds=m1_train_preds, training_seasons=train_seas,
             spec_version='v14', best_spec_id='kf4_ke2_as0.40_kr2_ba0.2_bb0.0'),
        'data/m2_production.rds')
cat('Saved data/m2_production.rds\n')
cat('Done:', format(Sys.time()), '\n')
