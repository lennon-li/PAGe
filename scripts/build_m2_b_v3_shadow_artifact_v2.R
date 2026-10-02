#!/usr/bin/env Rscript

options(stringsAsFactors=FALSE)

source('PAGe/R/data_contract.R')
source('PAGe/R/stage_contracts.R')
source('PAGe/R/expert_timing_annotations.R')
source('PAGe/R/retrospective_peak_truth.R')
source('PAGe/R/m1_v2.R')
source('scripts/v3_m1_b_runtime_helpers_v7.R')

if (!requireNamespace('digest',quietly=TRUE)) stop('Package `digest` is required.')

PANEL_PATH <- 'artifacts/v3-joint-ab-audit-v1/canonical_ab_weekly_v3.csv'
TIMING_PATH <- 'artifacts/v3-joint-timing-contract-v2/timing_contract_v3.csv'
ACTIVITY_PARAMS_PATH <- 'artifacts/v3-a-rule-transfer-to-b-v1/A_aggregated_params.rds'
M1B_PATH <- 'artifacts/m1-b-v3-peak-v8/m1_b_v3_peak_artifact.rds'
HISTORICAL_RESULT_PATH <- 'artifacts/v3-m2-b-posterior-c2-chronological-v3/overall_verdict.csv'
HISTORICAL_SUMMARY_PATH <- 'artifacts/v3-m2-b-posterior-c2-chronological-v3/summary_metrics.csv'
HISTORICAL_ACCEPTANCE_PATH <- 'artifacts/v3-m2-b-posterior-c2-chronological-v3/acceptance_criteria.csv'
HISTORICAL_INTEGRITY_PATH <- 'artifacts/v3-m2-b-posterior-c2-chronological-v3/integrity_checks.csv'
HISTORICAL_MANIFEST_PATH <- 'artifacts/v3-m2-b-posterior-c2-chronological-v3/source_manifest.csv'
HISTORICAL_LOWER_BOUND_PATH <- 'artifacts/v3-m2-b-posterior-c2-chronological-v3/lower_bound_reset_summary.csv'
DISPOSITION_PATH <- 'docs/v3-m2-b-final-disposition-2026-09-26.md'
RUNTIME_CONTRACT_PATH <- 'docs/v3-m2-b-shadow-runtime-contract-2026-09-26.md'
RUNTIME_HELPER_PATH <- 'scripts/v3_m2_b_runtime_helpers_v2.R'
SCRIPT_PATH <- 'scripts/build_m2_b_v3_shadow_artifact_v2.R'
OUT <- 'artifacts/m2-b-v3-shadow-v2'
ARTIFACT_PATH <- file.path(OUT,'m2_b_v3_shadow_artifact.rds')

VERSION <- 'm2-b-v3-shadow-v2'
STATUS <- 'shadow_only_prospective_research'
EXCLUDED <- '2019-20'
NO_EVENT <- '2018-19'
STATE_SEASONS <- c('2012-13','2013-14','2014-15','2016-17','2017-18','2018-19','2022-23','2023-24','2024-25','2025-26')
B_SHAPE_SEASONS <- c('2012-13','2013-14','2014-15','2016-17','2017-18','2022-23','2023-24','2024-25','2025-26')
A_SHAPE_SEASONS <- c('2012-13','2013-14','2014-15','2016-17','2017-18','2018-19','2019-20','2022-23','2023-24','2024-25','2025-26')
TAU_GRID <- seq(-8,8,by=.25)

if (dir.exists(OUT) && length(list.files(OUT,all.files=TRUE,no..=TRUE))) stop('Refusing to overwrite non-empty ',OUT,call.=FALSE)
dir.create(OUT,recursive=TRUE,showWarnings=FALSE)

sha256_file <- function(path) digest::digest(file=path,algo='sha256',serialize=FALSE)
season_start <- function(s) as.integer(substr(as.character(s),1,4))
logit <- function(p) qlogis(pmin(pmax(p,1e-6),1-1e-6))
stab <- function(y,N) (y+.5)/(N+1)

required <- c(PANEL_PATH,TIMING_PATH,ACTIVITY_PARAMS_PATH,M1B_PATH,HISTORICAL_RESULT_PATH,HISTORICAL_SUMMARY_PATH,HISTORICAL_ACCEPTANCE_PATH,HISTORICAL_INTEGRITY_PATH,HISTORICAL_MANIFEST_PATH,HISTORICAL_LOWER_BOUND_PATH,DISPOSITION_PATH,RUNTIME_CONTRACT_PATH,RUNTIME_HELPER_PATH)
if (!all(file.exists(required))) stop('Missing required M2-B v3 packaging input.',call.=FALSE)

panel <- read.csv(PANEL_PATH,check.names=FALSE)
timing <- read.csv(TIMING_PATH,check.names=FALSE)
historical_verdict <- read.csv(HISTORICAL_RESULT_PATH,check.names=FALSE)
historical_summary <- read.csv(HISTORICAL_SUMMARY_PATH,check.names=FALSE)
historical_acceptance <- read.csv(HISTORICAL_ACCEPTANCE_PATH,check.names=FALSE)
historical_integrity <- read.csv(HISTORICAL_INTEGRITY_PATH,check.names=FALSE)
historical_lb <- read.csv(HISTORICAL_LOWER_BOUND_PATH,check.names=FALSE)

required_panel <- c('season','weekF','y_A','N_A','p_A','y_B','N_B','p_B','denominator_regime')
if (!all(required_panel %in% names(panel))) stop('Canonical panel schema mismatch.',call.=FALSE)
if (anyDuplicated(panel[c('season','weekF')])) stop('Canonical panel has duplicate season/weekF keys.',call.=FALSE)
panel$season <- as.character(panel$season)
timing$season <- as.character(timing$season)
all_seasons <- unique(panel$season)
all_seasons <- all_seasons[order(season_start(all_seasons))]
if (!identical(all_seasons,A_SHAPE_SEASONS)) stop('Canonical season set/order differs from frozen A shape season policy.',call.=FALSE)
if (!setequal(timing$season,all_seasons)) stop('Timing contract season set mismatch.',call.=FALSE)
if (nrow(historical_verdict)!=1L || !isTRUE(historical_verdict$historically_promising) || !identical(as.character(historical_verdict$decision),'eligible_for_v3_shadow_plus2')) stop('Historical M2-B verdict no longer authorizes shadow packaging.',call.=FALSE)
if (!nrow(historical_acceptance) || !all(historical_acceptance$pass)) stop('Historical M2-B acceptance criteria are not all passing.',call.=FALSE)
if (!nrow(historical_integrity) || !all(historical_integrity$pass)) stop('Historical M2-B integrity checks are not all passing.',call.=FALSE)
if (nrow(historical_lb)!=1L || !is.finite(historical_lb$reset_relative_gain)) stop('Historical M2-B lower-bound diagnostic is missing.',call.=FALSE)

# ---------- full-history B1 state fit ----------
ledger_rows <- list()
for (s in STATE_SEASONS) {
  z <- panel[panel$season==s,,drop=FALSE]
  z <- z[order(z$weekF),]
  if (!nrow(z)) stop('Missing state-training season: ',s,call.=FALSE)
  ps <- stab(z$y_B,z$N_B)
  lg <- logit(ps)
  g1 <- c(NA,diff(lg))
  g2 <- c(NA,NA,(lg[3:length(lg)]-lg[1:(length(lg)-2)])/2)
  for (i in seq_len(nrow(z))) {
    if (z$weekF[i]<13 || i<3L) next
    for (h in 1:2) {
      j <- i+h
      if (j>nrow(z) || z$weekF[j] != z$weekF[i]+h) next
      ledger_rows[[length(ledger_rows)+1L]] <- data.frame(
        season=s,origin_week=z$weekF[i],target_week=z$weekF[j],horizon=h,
        y_target=z$y_B[j],N_target=z$N_B[j],p_target=z$p_B[j],
        p_star=ps[i],logit_current=lg[i],growth1=g1[i],growth2=g2[i],
        stringsAsFactors=FALSE)
    }
  }
}
state_ledger <- do.call(rbind,ledger_rows)
if (!nrow(state_ledger)) stop('No M2-B state training rows.',call.=FALSE)
if (any(state_ledger$season==EXCLUDED)) stop('Excluded 2019-20 entered M2-B state fit.',call.=FALSE)
if (!setequal(unique(state_ledger$season),STATE_SEASONS)) stop('M2-B state training-season coverage mismatch.',call.=FALSE)
state_ledger$horizon_f <- factor(paste0('h',state_ledger$horizon),levels=c('h1','h2'))
state_ledger$offset_logit <- state_ledger$logit_current
state_model <- suppressWarnings(glm(
  cbind(y_target,N_target-y_target) ~ horizon_f + growth1 + growth2 + offset(offset_logit),
  data=state_ledger,family=quasibinomial()))
if (!inherits(state_model,'glm') || !identical(state_model$family$family,'quasibinomial')) stop('M2-B state model fit failed.',call.=FALSE)
if (any(!is.finite(coef(state_model)))) stop('M2-B state model has non-finite coefficients.',call.=FALSE)

# ---------- frozen M1-B reference ----------
m1b <- readRDS(M1B_PATH)
validate_m1_b_v3_artifact(m1b)
if (!identical(m1b$version,'m1-b-v3-peak-v8')) stop('Wrong M1-B artifact version.',call.=FALSE)
if (!identical(as.character(m1b$training_seasons),B_SHAPE_SEASONS)) stop('M1-B training seasons differ from frozen B timing/shape season policy.',call.=FALSE)

# ---------- full-history canonical C2 shape grid ----------
build_shape <- function(season,type) {
  if (type=='B' && !season %in% B_SHAPE_SEASONS) return(NULL)
  peak_col <- if (type=='A') 'A_peak_weekF' else 'B_peak_weekF'
  peak <- timing[[peak_col]][timing$season==season]
  if (length(peak)!=1L || !is.finite(peak)) return(NULL)
  ycol <- paste0('y_',type); ncol <- paste0('N_',type); pcol <- paste0('p_',type)
  z <- panel[panel$season==season,c('season','weekF',ycol,ncol,pcol),drop=FALSE]
  names(z)[3:5] <- c('y','N','p')
  f <- retrospective_gam_peak_truth(z,season=season,k=8L,grid_step=.01)
  peak_diff <- abs(f$peak_week_decimal-peak)
  if (peak_diff>.051) stop('Shape peak mismatch for ',season,' ',type,': ',peak_diff,call.=FALSE)
  amp <- max(f$grid$fitted_p,na.rm=TRUE)
  vals <- approx(f$grid$weekF-peak,f$grid$fitted_p/amp,xout=TAU_GRID,rule=1)$y
  list(
    grid=data.frame(season=season,type=type,tau=TAU_GRID,p_norm=vals,stringsAsFactors=FALSE),
    check=data.frame(season=season,type=type,truth_peak=peak,fitted_peak=f$peak_week_decimal,abs_diff=peak_diff,stringsAsFactors=FALSE))
}
shape_rows <- list(); shape_checks <- list()
for (s in A_SHAPE_SEASONS) for (tp in c('A','B')) {
  q <- build_shape(s,tp)
  if (is.null(q)) next
  shape_rows[[length(shape_rows)+1L]] <- q$grid
  shape_checks[[length(shape_checks)+1L]] <- q$check
}
shape_grid <- do.call(rbind,shape_rows)
shape_check <- do.call(rbind,shape_checks)
actual_A <- unique(as.character(shape_grid$season[shape_grid$type=='A']))
actual_B <- unique(as.character(shape_grid$season[shape_grid$type=='B']))
if (!identical(actual_A,A_SHAPE_SEASONS)) stop('A shape season order/content mismatch.',call.=FALSE)
if (!identical(actual_B,B_SHAPE_SEASONS)) stop('B shape season order/content mismatch.',call.=FALSE)
if (any(c(EXCLUDED,NO_EVENT) %in% actual_B)) stop('Ineligible B shape entered packaged artifact.',call.=FALSE)

# ---------- causal B activity params ----------
activity_params <- readRDS(ACTIVITY_PARAMS_PATH)
activity_params$w_min <- 8L
activity_params$w_max <- 40L

runtime_contract <- list(
  min_origin_week=13L,
  horizons=c(1L,2L),
  plus1_route='exact_B1',
  plus2_route='posterior_C2_if_timing_else_B1',
  allow_hard_passage=FALSE,
  allow_production=FALSE,
  lower_bound_step=.2,
  lower_bound_saturation_threshold=.9,
  lower_bound_definition='sum(probability[peak_week_decimal <= min(peak_week_decimal)+0.2])',
  required_helper=RUNTIME_HELPER_PATH,
  required_m1_helper='scripts/v3_m1_b_runtime_helpers_v7.R'
)

artifact <- structure(list(
  version=VERSION,
  status=STATUS,
  production_eligible=FALSE,
  season_policy=list(
    excluded_B_season=EXCLUDED,
    exclusion_reason='pandemic_transition',
    no_event_B_season=NO_EVENT,
    state_training_seasons=STATE_SEASONS,
    A_shape_seasons=A_SHAPE_SEASONS,
    B_shape_seasons=B_SHAPE_SEASONS
  ),
  state=list(
    model=state_model,
    training_seasons=STATE_SEASONS,
    training_rows=nrow(state_ledger),
    ledger_sha256=digest::digest(state_ledger,algo='sha256')
  ),
  m1_b=list(
    path=M1B_PATH,
    version=m1b$version,
    artifact_sha256=sha256_file(M1B_PATH),
    library_hash=m1b$library$provenance$library_hash
  ),
  activity=list(
    semantics='causal_prefix_operational_activity_marker_not_gold_ignition',
    params=activity_params,
    source_path=ACTIVITY_PARAMS_PATH,
    source_sha256=sha256_file(ACTIVITY_PARAMS_PATH)
  ),
  shape=list(
    grid=shape_grid,
    tau_grid=TAU_GRID,
    A_seasons=A_SHAPE_SEASONS,
    B_seasons=B_SHAPE_SEASONS,
    pooled_weight=.5,
    B_weight=.5,
    eta=.5,
    peak_alignment=shape_check
  ),
  historical_evidence=list(
    benchmark_version='v3-m2-b-posterior-c2-chronological-v3',
    verdict_sha256=sha256_file(HISTORICAL_RESULT_PATH),
    summary_sha256=sha256_file(HISTORICAL_SUMMARY_PATH),
    acceptance_sha256=sha256_file(HISTORICAL_ACCEPTANCE_PATH),
    integrity_sha256=sha256_file(HISTORICAL_INTEGRITY_PATH),
    benchmark_manifest_sha256=sha256_file(HISTORICAL_MANIFEST_PATH),
    lower_bound_diagnostic_sha256=sha256_file(HISTORICAL_LOWER_BOUND_PATH),
    disposition_sha256=sha256_file(DISPOSITION_PATH),
    plus2_historically_promising=TRUE,
    plus1_route='exact_B1',
    lower_bound_monitoring_required=TRUE,
    lower_bound_reset_active_gain=as.numeric(historical_lb$reset_relative_gain[[1]])
  ),
  runtime_contract=runtime_contract,
  prospective=list(
    required=TRUE,
    first_shadow_season='2026-27',
    no_retuning_from_shadow_outcomes=TRUE,
    lower_bound_monitoring_required=TRUE
  ),
  provenance=list(
    canonical_panel_sha256=sha256_file(PANEL_PATH),
    timing_contract_sha256=sha256_file(TIMING_PATH),
    m1_b_artifact_sha256=sha256_file(M1B_PATH),
    runtime_helper_sha256=sha256_file(RUNTIME_HELPER_PATH),
    runtime_contract_sha256=sha256_file(RUNTIME_CONTRACT_PATH),
    disposition_sha256=sha256_file(DISPOSITION_PATH),
    historical_benchmark_manifest_sha256=sha256_file(HISTORICAL_MANIFEST_PATH),
    builder_sha256=sha256_file(SCRIPT_PATH),
    git_head=system2('git',c('rev-parse','HEAD'),stdout=TRUE)
  )
),class=c('page_m2_b_v3_shadow_artifact','list'))

core <- list(
  version=artifact$version,
  status=artifact$status,
  state_coefficients=stats::coef(artifact$state$model),
  state_training=artifact$state$training_seasons,
  m1_library_hash=artifact$m1_b$library_hash,
  shape_grid=artifact$shape$grid,
  shape_A=artifact$shape$A_seasons,shape_B=artifact$shape$B_seasons,
  constants=c(artifact$shape$pooled_weight,artifact$shape$B_weight,artifact$shape$eta,artifact$runtime_contract$lower_bound_step,artifact$runtime_contract$lower_bound_saturation_threshold))
artifact$artifact_id <- digest::digest(core,algo='sha256')

saveRDS(artifact,ARTIFACT_PATH,version=3)

write.csv(state_ledger,file.path(OUT,'state_training_ledger.csv'),row.names=FALSE)
write.csv(shape_grid,file.path(OUT,'shape_grid.csv'),row.names=FALSE)
write.csv(shape_check,file.path(OUT,'shape_peak_alignment.csv'),row.names=FALSE)
write.csv(data.frame(component=c(rep('state_training',length(STATE_SEASONS)),rep('A_shape',length(A_SHAPE_SEASONS)),rep('B_shape',length(B_SHAPE_SEASONS))),season=c(STATE_SEASONS,A_SHAPE_SEASONS,B_SHAPE_SEASONS),stringsAsFactors=FALSE),file.path(OUT,'training_seasons.csv'),row.names=FALSE)

metadata <- data.frame(
  key=c('version','status','production_eligible','artifact_id','artifact_sha256','state_training_n','state_training_seasons','A_shape_seasons','B_shape_seasons','excluded_B_season','no_event_B_season','m1_b_version','m1_b_library_hash','plus1_route','plus2_route','min_origin_week','passage_candidate_step','passage_max_future_weeks','C2_weights','eta','lower_bound_step','lower_bound_saturation_threshold','historical_benchmark_version','lower_bound_reset_active_gain','runtime_helper','runtime_contract'),
  value=c(
    VERSION,STATUS,'FALSE',artifact$artifact_id,sha256_file(ARTIFACT_PATH),length(STATE_SEASONS),paste(STATE_SEASONS,collapse=';'),paste(A_SHAPE_SEASONS,collapse=';'),paste(B_SHAPE_SEASONS,collapse=';'),EXCLUDED,NO_EVENT,m1b$version,m1b$library$provenance$library_hash,'exact_B1','posterior_C2_if_timing_else_B1',13,.M1_B_PASSAGE_CANDIDATE_STEP,.M1_B_PASSAGE_MAX_FUTURE_WEEKS,'0.5 pooled + 0.5 B',.5,.2,.9,'v3-m2-b-posterior-c2-chronological-v3',as.numeric(historical_lb$reset_relative_gain[[1]]),RUNTIME_HELPER_PATH,RUNTIME_CONTRACT_PATH
  ),stringsAsFactors=FALSE)
write.csv(metadata,file.path(OUT,'metadata.csv'),row.names=FALSE)

manifest_paths <- c(PANEL_PATH,TIMING_PATH,ACTIVITY_PARAMS_PATH,M1B_PATH,HISTORICAL_RESULT_PATH,HISTORICAL_SUMMARY_PATH,HISTORICAL_ACCEPTANCE_PATH,HISTORICAL_INTEGRITY_PATH,HISTORICAL_MANIFEST_PATH,HISTORICAL_LOWER_BOUND_PATH,DISPOSITION_PATH,RUNTIME_CONTRACT_PATH,RUNTIME_HELPER_PATH,SCRIPT_PATH)
manifest <- data.frame(
  role=c('canonical_panel','timing_contract','activity_params','m1_b_v8','historical_verdict','historical_summary','historical_acceptance','historical_integrity','historical_source_manifest','historical_lower_bound_diagnostic','historical_disposition','runtime_contract','runtime_helper','builder_script'),
  path=manifest_paths,
  sha256=vapply(manifest_paths,sha256_file,character(1)),stringsAsFactors=FALSE)
manifest <- rbind(manifest,data.frame(role='serialized_artifact',path=ARTIFACT_PATH,sha256=sha256_file(ARTIFACT_PATH),stringsAsFactors=FALSE))
write.csv(manifest,file.path(OUT,'source_manifest.csv'),row.names=FALSE)

# Round-trip through the governed helper. The artifact hashes the already-frozen
# helper and contract, so neither file may change after this point without a new version.
source(RUNTIME_HELPER_PATH)
z <- load_m2_b_v3_shadow_artifact(ARTIFACT_PATH)
stopifnot(identical(z$artifact_id,artifact$artifact_id))
stopifnot(identical(z$state$training_seasons,STATE_SEASONS))
stopifnot(!(EXCLUDED %in% z$state$training_seasons))
stopifnot(!any(c(EXCLUDED,NO_EVENT) %in% z$shape$B_seasons))
stopifnot(identical(z$production_eligible,FALSE))
stopifnot(identical(z$runtime_contract$allow_hard_passage,FALSE))

cat('Built ',ARTIFACT_PATH,'\n',sep='')
cat('Artifact ID: ',artifact$artifact_id,'\n',sep='')
cat('Artifact SHA256: ',sha256_file(ARTIFACT_PATH),'\n',sep='')
cat('State seasons (',length(STATE_SEASONS),'): ',paste(STATE_SEASONS,collapse=', '),'\n',sep='')
cat('B shape seasons (',length(B_SHAPE_SEASONS),'): ',paste(B_SHAPE_SEASONS,collapse=', '),'\n',sep='')
cat('M1-B library hash: ',m1b$library$provenance$library_hash,'\n',sep='')
