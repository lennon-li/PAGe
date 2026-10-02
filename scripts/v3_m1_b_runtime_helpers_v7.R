# Guarded runtime helpers for the frozen pandemic-excluded v3 M1-B shadow artifact.
#
# This governed helper exposes B peak posterior and continuous passage posterior
# only. A binary passage decision is forbidden through this interface. Runtime
# grid/horizon values are pinned here as part of the governed contract.

source('PAGe/R/data_contract.R')
source('PAGe/R/stage_contracts.R')
source('PAGe/R/expert_timing_annotations.R')
source('PAGe/R/retrospective_peak_truth.R')
source('PAGe/R/m1_v2.R')

.M1_B_EXPECTED_TRAINING <- c(
  '2012-13','2013-14','2014-15','2016-17','2017-18',
  '2022-23','2023-24','2024-25','2025-26'
)
.M1_B_EXPECTED_HELPER <- 'scripts/v3_m1_b_runtime_helpers_v7.R'
.M1_B_PEAK_CANDIDATE_STEP <- 0.1
.M1_B_PEAK_MAX_FUTURE_WEEKS <- 16
.M1_B_PASSAGE_CANDIDATE_STEP <- 0.2
.M1_B_PASSAGE_MAX_FUTURE_WEEKS <- 12

.m1_b_same_seasons <- function(x,y) identical(as.character(x),as.character(y))
.m1_b_same_number <- function(x,y) is.numeric(x) && length(x)==1L && is.finite(x) && identical(as.numeric(x),as.numeric(y))

validate_m1_b_v3_artifact <- function(artifact) {
  if (!inherits(artifact,'page_m1_b_v3_peak_artifact')) stop('Not a page_m1_b_v3_peak_artifact.',call.=FALSE)
  if (!identical(artifact$status,'shadow_research_peak_location_only')) stop('M1-B artifact is not shadow peak-location-only.',call.=FALSE)
  if (!identical(artifact$season_policy$excluded_B_season,'2019-20')) stop('M1-B artifact does not carry the frozen 2019-20 exclusion.',call.=FALSE)
  if (!identical(artifact$season_policy$no_event_season,'2018-19')) stop('M1-B artifact does not carry the frozen 2018-19 no-event season.',call.=FALSE)
  if (!inherits(artifact$library,'page_m1_v2_library')) stop('M1-B fitted library is missing or malformed.',call.=FALSE)

  if (!.m1_b_same_seasons(artifact$training_seasons,.M1_B_EXPECTED_TRAINING)) stop('M1-B artifact training seasons differ from the frozen 9-season policy.',call.=FALSE)
  if (!.m1_b_same_seasons(artifact$library$training_seasons,.M1_B_EXPECTED_TRAINING)) stop('M1-B fitted library training seasons differ from the frozen 9-season policy.',call.=FALSE)
  if (!.m1_b_same_seasons(artifact$library$training_seasons,artifact$training_seasons)) stop('M1-B fitted library training seasons do not match artifact training_seasons.',call.=FALSE)
  if ('2019-20' %in% artifact$training_seasons || '2019-20' %in% artifact$library$training_seasons) stop('Excluded 2019-20 entered M1-B training.',call.=FALSE)
  if ('2018-19' %in% artifact$training_seasons || '2018-19' %in% artifact$library$training_seasons) stop('No-event 2018-19 entered M1-B timing training.',call.=FALSE)

  pt_seasons <- as.character(artifact$library$peak_truth$season)
  if (!.m1_b_same_seasons(pt_seasons,.M1_B_EXPECTED_TRAINING)) stop('M1-B peak_truth seasons differ from the frozen training policy.',call.=FALSE)
  if (!.m1_b_same_seasons(names(artifact$library$fitted_peak),.M1_B_EXPECTED_TRAINING)) stop('M1-B fitted_peak seasons differ from the frozen training policy.',call.=FALSE)
  if (!.m1_b_same_seasons(names(artifact$library$peak_height),.M1_B_EXPECTED_TRAINING)) stop('M1-B peak_height seasons differ from the frozen training policy.',call.=FALSE)

  if (!is.list(artifact$calibration) || !identical(artifact$calibration$enabled,FALSE)) stop('M1-B scalar calibration must be explicitly disabled.',call.=FALSE)
  if (!is.list(artifact$joint_A_conditioning) || !identical(artifact$joint_A_conditioning$enabled,FALSE)) stop('M1-B A-conditioning must be explicitly disabled.',call.=FALSE)
  if (!is.list(artifact$passage) || !identical(artifact$passage$hard_gate_eligible,FALSE)) stop('M1-B hard passage eligibility must be explicitly FALSE.',call.=FALSE)
  if (!identical(artifact$passage$historical_threshold_search_closed,TRUE)) stop('M1-B historical passage-search closure is missing.',call.=FALSE)
  if (!identical(artifact$passage$continuous_posterior_shadow_only,TRUE)) stop('M1-B continuous passage posterior is not marked shadow-only.',call.=FALSE)

  rc <- artifact$runtime_contract
  if (!is.list(rc)) stop('M1-B runtime contract is missing.',call.=FALSE)
  if (!identical(rc$allow_peak_posterior,TRUE)) stop('M1-B peak posterior must be explicitly enabled.',call.=FALSE)
  if (!identical(rc$allow_continuous_passage_posterior,TRUE)) stop('M1-B continuous passage posterior must be explicitly enabled.',call.=FALSE)
  if (!identical(rc$allow_passage_decision,FALSE)) stop('M1-B runtime contract does not explicitly disable passage decisions.',call.=FALSE)
  if (!.m1_b_same_number(rc$peak_candidate_step,.M1_B_PEAK_CANDIDATE_STEP)) stop('M1-B peak candidate_step differs from the frozen runtime contract.',call.=FALSE)
  if (!.m1_b_same_number(rc$peak_max_future_weeks,.M1_B_PEAK_MAX_FUTURE_WEEKS)) stop('M1-B peak max_future_weeks differs from the frozen runtime contract.',call.=FALSE)
  if (!.m1_b_same_number(rc$passage_candidate_step,.M1_B_PASSAGE_CANDIDATE_STEP)) stop('M1-B passage candidate_step differs from the frozen runtime contract.',call.=FALSE)
  if (!.m1_b_same_number(rc$passage_max_future_weeks,.M1_B_PASSAGE_MAX_FUTURE_WEEKS)) stop('M1-B passage max_future_weeks differs from the frozen runtime contract.',call.=FALSE)
  if (!identical(rc$required_helper,.M1_B_EXPECTED_HELPER)) stop('M1-B runtime helper path differs from the frozen contract.',call.=FALSE)

  if (!requireNamespace('digest',quietly=TRUE)) stop('Package `digest` is required to validate M1-B runtime provenance.',call.=FALSE)
  helper_path <- rc$required_helper
  if (!file.exists(helper_path)) stop('M1-B required runtime helper is unavailable: ',helper_path,call.=FALSE)
  helper_sha <- digest::digest(file=helper_path,algo='sha256',serialize=FALSE)
  if (!is.character(artifact$provenance$runtime_helper_sha256) || length(artifact$provenance$runtime_helper_sha256)!=1L || !identical(artifact$provenance$runtime_helper_sha256,helper_sha)) stop('M1-B runtime helper provenance hash mismatch.',call.=FALSE)
  if (!identical(artifact$provenance$library_hash,artifact$library$provenance$library_hash)) stop('M1-B artifact/library provenance hash mismatch.',call.=FALSE)
  invisible(TRUE)
}

load_m1_b_v3_artifact <- function(path='artifacts/m1-b-v3-peak-v8/m1_b_v3_peak_artifact.rds') {
  if (!file.exists(path)) stop('M1-B artifact not found: ',path,call.=FALSE)
  z <- readRDS(path)
  validate_m1_b_v3_artifact(z)
  z
}

m1_b_v3_peak_posterior <- function(artifact,current_data,activity_week,origin_week,candidate_step=NULL,max_future_weeks=NULL) {
  validate_m1_b_v3_artifact(artifact)
  if (!is.null(candidate_step) && !identical(as.numeric(candidate_step),.M1_B_PEAK_CANDIDATE_STEP)) stop('M1-B peak candidate_step override violates frozen runtime contract.',call.=FALSE)
  if (!is.null(max_future_weeks) && !identical(as.numeric(max_future_weeks),as.numeric(.M1_B_PEAK_MAX_FUTURE_WEEKS))) stop('M1-B peak max_future_weeks override violates frozen runtime contract.',call.=FALSE)
  m1_v2_peak_posterior(artifact$library,current_data,activation_week=activity_week,origin_week=origin_week,
                       candidate_step=.M1_B_PEAK_CANDIDATE_STEP,max_future_weeks=.M1_B_PEAK_MAX_FUTURE_WEEKS)
}

m1_b_v3_passage_posterior <- function(artifact,current_data,activity_week,origin_week,candidate_step=NULL,max_future_weeks=NULL) {
  validate_m1_b_v3_artifact(artifact)
  if (!identical(artifact$passage$continuous_posterior_shadow_only,TRUE)) stop('Continuous passage posterior is not allowed by this artifact.',call.=FALSE)
  if (!is.null(candidate_step) && !identical(as.numeric(candidate_step),.M1_B_PASSAGE_CANDIDATE_STEP)) stop('M1-B passage candidate_step override violates frozen runtime contract.',call.=FALSE)
  if (!is.null(max_future_weeks) && !identical(as.numeric(max_future_weeks),as.numeric(.M1_B_PASSAGE_MAX_FUTURE_WEEKS))) stop('M1-B passage max_future_weeks override violates frozen runtime contract.',call.=FALSE)
  m1_v2_passage_posterior(artifact$library,current_data,activation_week=activity_week,origin_week=origin_week,
                          candidate_step=.M1_B_PASSAGE_CANDIDATE_STEP,max_future_weeks=.M1_B_PASSAGE_MAX_FUTURE_WEEKS)
}

m1_b_v3_inactive_state <- function() {
  list(state='inactive_no_timing_event',positive_timing_gate=FALSE,peak_posterior=NULL,passage_posterior=NULL)
}

m1_b_v3_passage_decision <- function(...) {
  stop('Hard M1-B passage decisions are forbidden through the governed M1-B helper. Use continuous passage posterior as shadow uncertainty only.',call.=FALSE)
}
