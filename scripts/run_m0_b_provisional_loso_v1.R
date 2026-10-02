source('PAGe/R/data_contract.R')
source('PAGe/R/stage_contracts.R')
source('PAGe/R/timing_pipeline_v2.R')
source('PAGe/R/m0_training.R')
source('PAGe/R/expert_timing_annotations.R')
source('PAGe/R/retrospective_peak_truth.R')
`%||%` <- function(x,y) if(!is.null(x)) x else y

ab <- read.csv('artifacts/m2-v2-flu-ab-geometry-v1/flu_ab_long_v1.csv', stringsAsFactors=FALSE)
b <- ab[ab$type=='B', c('season','weekF','y','N','p','denominator_regime')]
b$season <- as.character(b$season)
b <- b[order(b$season,b$weekF),]
seasons <- sort(unique(b$season))

# Provisional retrospective B ignition truth. The relative excursion fraction
# is inherited from the median baseline-adjusted level at expert A ignition.
# Use the LAST upward crossing before the retrospective B peak to avoid early
# low-level B blips. This is explicitly provisional/evaluation-only.
relative_excursion_fraction <- 0.08888451
truth_rows <- list()
for (s in seasons) {
  z <- b[b$season==s, c('season','weekF','y','N','p')]
  f <- retrospective_gam_peak_truth(z, season=s, k=8L, grid_step=.01)
  g <- f$grid
  pre <- g[g$weekF <= f$peak_week_decimal,]
  base <- as.numeric(stats::quantile(pre$fitted_p,.05,na.rm=TRUE))
  amp <- max(pre$fitted_p,na.rm=TRUE)
  threshold <- base + relative_excursion_fraction*(amp-base)
  above <- pre$fitted_p >= threshold
  crossings <- which(above & c(TRUE,!head(above,-1L)))
  I <- if(length(crossings)) pre$weekF[max(crossings)] else NA_real_
  truth_rows[[s]] <- data.frame(
    season=s, ignition_target_weekF=I, peak_week_decimal=f$peak_week_decimal,
    ignition_to_peak=f$peak_week_decimal-I, baseline_p=base,
    peak_p=amp, threshold_p=threshold, stringsAsFactors=FALSE
  )
}
truth <- do.call(rbind,truth_rows); rownames(truth)<-NULL
if(any(!is.finite(truth$ignition_target_weekF))) stop('Provisional B truth contains missing ignition targets.')

# Classifier phase labels use the same provisional continuous target.
target <- setNames(truth$ignition_target_weekF,truth$season)
b$phase <- as.integer(b$weekF >= target[b$season])

if(!requireNamespace('data.table',quietly=TRUE)) stop('Need data.table')
grid <- data.table::CJ(
  cls_thr=0.26,
  use_cls=FALSE,
  p_thr=c(.0005,.001,.002),
  prev_thr=c(.00025,.0005,.001),
  n_consec=c(4L,5L),
  L=2L,
  eps=0,
  K_sum=5L,
  p_sum_thr=c(.010,.020),
  N_req=4L,
  w_min=18L,
  w_max=40L,
  K_dp=3L,
  dp_thr=.005,
  sorted=FALSE
)

out_dir <- 'artifacts/m0-b-provisional-loso-v1'
dir.create(out_dir,recursive=TRUE,showWarnings=FALSE)
write.csv(truth,file.path(out_dir,'provisional_b_ignition_truth.csv'),row.names=FALSE)
write.csv(as.data.frame(grid),file.path(out_dir,'grid.csv'),row.names=FALSE)

fit <- loso_M0v2(
  dat=b,
  grid=as.data.frame(grid),
  season_col='season',week_col='weekF',phase_col='phase',p_col='p',score_col='p_cls_p',
  fit_args=list(fit_base=TRUE,fit_slope=FALSE,fit_fs=FALSE,event_k=1L,lead=1L,A_pre=6L,B_post=6L,k_week=6L,k_p=8L,k_fs=4L,select=FALSE,verbose=FALSE),
  tune_args=list(miss_penalty=0,lambda=20,kappa=0,gamma=25,gamma_late=0,iWeek=TRUE,ncores=4L,verbose=FALSE,progress_every=200L),
  verbose=TRUE,
  checkpoint_dir=file.path(out_dir,'checkpoint'),
  timing_truth=truth[,c('season','ignition_target_weekF')],
  timing_mode='fractional',
  selection_policy='legacy'
)
saveRDS(fit,file.path(out_dir,'m0_b_loso.rds'))

# Extract one held-out detection per season from fold outputs.
rows <- list()
for(s in names(fit$folds %||% fit$fold_out)) {
  fold <- (fit$folds %||% fit$fold_out)[[s]]
  det <- fold$det %||% fold$detection %||% fold$heldout_detection
  if(is.null(det)) next
  if(is.data.frame(det)) {
    cand <- intersect(c('iWeek_hatF','iWeekF','iWeek','ignition_weekF','weekF'),names(det))
    pred <- if(length(cand)) as.numeric(det[[cand[1]]][1]) else NA_real_
  } else pred <- suppressWarnings(as.numeric(det[1]))
  rows[[s]] <- data.frame(season=s,pred=pred)
}
# Prefer eval_all when it already carries fractional heldout predictions.
ev <- fit$eval_all
write.csv(ev,file.path(out_dir,'eval_all.csv'),row.names=FALSE)
write.csv(fit$eval_tune,file.path(out_dir,'eval_tune.csv'),row.names=FALSE)

cat('truth\n');print(truth,row.names=FALSE,digits=4)
cat('\nEval columns:\n');print(names(ev))
cat('\nEval all:\n');print(ev,row.names=FALSE,digits=4)
