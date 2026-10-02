#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE)

source('PAGe/R/data_contract.R')
source('PAGe/R/stage_contracts.R')
source('PAGe/R/expert_timing_annotations.R')
source('PAGe/R/retrospective_peak_truth.R')
source('PAGe/R/m1_v2.R')

if (!requireNamespace('digest', quietly=TRUE)) stop('Package `digest` is required.')

PANEL_PATH <- 'artifacts/v3-joint-ab-audit-v1/canonical_ab_weekly_v3.csv'
TIMING_PATH <- 'artifacts/v3-joint-timing-contract-v2/timing_contract_v3.csv'
B_DETECT_PATH <- 'artifacts/v3-a-rule-transfer-to-b-v1/B_window8_40_detection.rds'
B_PARAMS_PATH <- 'artifacts/v3-a-rule-transfer-to-b-v1/A_aggregated_params.rds'
DISPOSITION_PATH <- 'docs/v3-m1-b-final-disposition-2026-09-25.md'
PASSAGE_RESULT_PATH <- 'artifacts/v3-m1-b-passage-robustness-v1/overall_verdict.csv'
SCRIPT_PATH <- 'scripts/build_m1_b_v3_peak_artifact_v2.R'
RUNTIME_HELPER <- 'scripts/v3_m1_b_runtime_helpers.R'
CODE_FILES <- c('PAGe/R/data_contract.R','PAGe/R/stage_contracts.R','PAGe/R/expert_timing_annotations.R','PAGe/R/retrospective_peak_truth.R','PAGe/R/m1_v2.R')
OUT <- 'artifacts/m1-b-v3-peak-v2'
ARTIFACT_PATH <- file.path(OUT,'m1_b_v3_peak_artifact.rds')

if (dir.exists(OUT) && length(list.files(OUT,all.files=TRUE,no..=TRUE))>0L) stop('Refusing to overwrite non-empty ',OUT)
dir.create(OUT,recursive=TRUE,showWarnings=FALSE)

sha256_file <- function(path) digest::digest(file=path,algo='sha256',serialize=FALSE)
season_start <- function(s) as.integer(substr(as.character(s),1,4))

panel <- read.csv(PANEL_PATH,check.names=FALSE)
timing <- read.csv(TIMING_PATH,check.names=FALSE)
passage_verdict <- read.csv(PASSAGE_RESULT_PATH,check.names=FALSE)

if (nrow(passage_verdict)!=1L || isTRUE(passage_verdict$historically_promising_second_look)) stop('Passage verdict no longer matches frozen M1-B disposition.')
if (!identical(as.character(passage_verdict$eligibility),'stop_hard_M1B_passage_gating')) stop('Hard passage gating is not stopped in source verdict.')

B <- data.frame(season=as.character(panel$season),weekF=panel$weekF,y=panel$y_B,N=panel$N_B,p=panel$p_B)
B <- B[order(season_start(B$season),B$weekF),]
meaningful <- as.character(timing$season[is.finite(timing$B_peak_weekF) & timing$B_activity_detected])
meaningful <- meaningful[order(season_start(meaningful))]
if (length(meaningful)!=10L) stop('Expected 10 meaningful B timing seasons; got ',length(meaningful))
if ('2018-19' %in% meaningful) stop('2018-19 must not enter the M1-B timing library.')

trainB <- B[B$season %in% meaningful,]
truthB <- timing[timing$season %in% meaningful,c('season','B_peak_weekF')]
truthB <- truthB[match(meaningful,truthB$season),]
names(truthB)[2] <- 'peak_week_decimal'
if (anyNA(truthB$season) || any(!is.finite(truthB$peak_week_decimal))) stop('Incomplete B peak truth.')

AMP_GRID <- seq(.005,.25,by=.005)
library <- fit_m1_v2_library(trainB,truthB,k=8L,grid_step=.01,tau_step=.1,amplitude_grid=AMP_GRID)
if (!inherits(library,'page_m1_v2_library')) stop('M1-B library fit failed.')
if (!identical(as.character(library$training_seasons),meaningful)) stop('Library training-season order mismatch.')
if (!isTRUE(all.equal(library$config$amplitude_grid,AMP_GRID,tolerance=0))) stop('B amplitude grid mismatch.')

activity_params <- readRDS(B_PARAMS_PATH)
activity_params$w_min <- 8
activity_params$w_max <- 40

artifact <- structure(list(
  version='m1-b-v3-peak-v2',
  status='shadow_research_peak_location_only',
  created_from_disposition_sha256=sha256_file(DISPOSITION_PATH),
  timing_contract_sha256=sha256_file(TIMING_PATH),
  canonical_panel_sha256=sha256_file(PANEL_PATH),
  library=library,
  training_seasons=meaningful,
  peak_target='retrospective-gam-peak-v1-k8',
  amplitude_grid=AMP_GRID,
  activity_marker=list(
    semantics='exploratory_activity_marker_not_gold_ignition',
    window=c(8,40),
    params=activity_params,
    detector_artifact_sha256=sha256_file(B_DETECT_PATH)
  ),
  passage=list(
    hard_gate_eligible=FALSE,
    historical_threshold_search_closed=TRUE,
    continuous_posterior_shadow_only=TRUE,
    source_verdict_sha256=sha256_file(PASSAGE_RESULT_PATH),
    states=c('inactive_no_timing_event','active_unconfirmed','confirmed_shadow_only')
  ),
  runtime_contract=list(
    allow_peak_posterior=TRUE,
    allow_continuous_passage_posterior=TRUE,
    allow_passage_decision=FALSE,
    required_helper=RUNTIME_HELPER
  ),
  calibration=list(enabled=FALSE,reason='scalar_M1B_calibration_failed_primary_chronological_criteria'),
  joint_A_conditioning=list(enabled=FALSE,reason='A_conditioned_M1B_branch_stopped'),
  provenance=list(
    library_hash=library$provenance$library_hash,
    data_hash=library$provenance$data_hash,
    truth_hash=library$provenance$truth_hash,
    coordinate_version=library$provenance$coordinate_version,
    git_head=system2('git',c('rev-parse','HEAD'),stdout=TRUE),
    code_sha256=setNames(vapply(CODE_FILES,sha256_file,character(1)),CODE_FILES),
    runtime_helper_sha256=sha256_file(RUNTIME_HELPER)
  )
),class=c('page_m1_b_v3_peak_artifact','list'))

saveRDS(artifact,ARTIFACT_PATH,version=3)

meta <- data.frame(
  key=c('version','status','n_training_seasons','training_seasons','library_hash','amplitude_grid','activity_window','activity_semantics','scalar_calibration','A_conditioning','hard_passage_gate','continuous_passage_posterior','runtime_passage_decision','runtime_helper','git_head','m1_v2_code_sha256','prospective_confirmation_required','artifact_sha256'),
  value=c(
    artifact$version,artifact$status,length(meaningful),paste(meaningful,collapse=';'),library$provenance$library_hash,
    '0.005:0.005:0.25','8-40',artifact$activity_marker$semantics,'disabled','disabled','disabled','shadow_only','forbidden',RUNTIME_HELPER,artifact$provenance$git_head,artifact$provenance$code_sha256[['PAGe/R/m1_v2.R']],'TRUE',sha256_file(ARTIFACT_PATH)
  ),stringsAsFactors=FALSE)
write.csv(meta,file.path(OUT,'metadata.csv'),row.names=FALSE)
write.csv(data.frame(season=meaningful,peak_week_decimal=truthB$peak_week_decimal,stringsAsFactors=FALSE),file.path(OUT,'training_seasons.csv'),row.names=FALSE)

inputs <- c(PANEL_PATH,TIMING_PATH,B_DETECT_PATH,B_PARAMS_PATH,DISPOSITION_PATH,PASSAGE_RESULT_PATH,SCRIPT_PATH,RUNTIME_HELPER,CODE_FILES)
manifest <- data.frame(role=c('canonical_panel','timing_contract','B_activity_detector','B_activity_params','final_disposition','passage_verdict','builder_script','runtime_helper',rep('frozen_code',length(CODE_FILES))),path=inputs,sha256=vapply(inputs,sha256_file,character(1)),stringsAsFactors=FALSE)
manifest <- rbind(manifest,data.frame(role='serialized_artifact',path=ARTIFACT_PATH,sha256=sha256_file(ARTIFACT_PATH),stringsAsFactors=FALSE))
write.csv(manifest,file.path(OUT,'source_manifest.csv'),row.names=FALSE)

# Round-trip invariants.
z <- readRDS(ARTIFACT_PATH)
stopifnot(inherits(z,'page_m1_b_v3_peak_artifact'))
stopifnot(identical(z$version,'m1-b-v3-peak-v2'))
stopifnot(identical(z$training_seasons,meaningful))
stopifnot(!z$passage$hard_gate_eligible,z$passage$historical_threshold_search_closed,z$passage$continuous_posterior_shadow_only)
stopifnot(identical(z$runtime_contract$allow_passage_decision,FALSE),identical(z$runtime_contract$required_helper,RUNTIME_HELPER))
stopifnot(identical(unname(z$provenance$code_sha256),unname(vapply(CODE_FILES,sha256_file,character(1)))))
stopifnot(!z$calibration$enabled,!z$joint_A_conditioning$enabled)
stopifnot(identical(z$library$provenance$library_hash,library$provenance$library_hash))

cat('Built ',ARTIFACT_PATH,'\n',sep='')
cat('Training seasons: ',paste(meaningful,collapse=', '),'\n',sep='')
cat('Library hash: ',library$provenance$library_hash,'\n',sep='')
cat('Artifact SHA256: ',sha256_file(ARTIFACT_PATH),'\n',sep='')
