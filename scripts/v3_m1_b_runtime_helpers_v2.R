# Guarded runtime helpers for the pandemic-excluded v3 M1-B shadow artifact.
#
# Exposes B peak posterior and continuous passage posterior only. Hard binary
# passage decisions remain forbidden by the frozen M1-B disposition.

source('PAGe/R/data_contract.R')
source('PAGe/R/stage_contracts.R')
source('PAGe/R/expert_timing_annotations.R')
source('PAGe/R/retrospective_peak_truth.R')
source('PAGe/R/m1_v2.R')

validate_m1_b_v3_artifact <- function(artifact) {
  if (!inherits(artifact,'page_m1_b_v3_peak_artifact')) stop('Not a page_m1_b_v3_peak_artifact.',call.=FALSE)
  if (!identical(artifact$status,'shadow_research_peak_location_only')) stop('M1-B artifact is not shadow peak-location-only.',call.=FALSE)
  if (!identical(artifact$season_policy$excluded_B_season,'2019-20')) stop('M1-B artifact does not carry the frozen 2019-20 exclusion.',call.=FALSE)
  if ('2019-20' %in% artifact$training_seasons) stop('Excluded 2019-20 entered M1-B training.',call.=FALSE)
  if ('2018-19' %in% artifact$training_seasons) stop('No-event 2018-19 entered M1-B timing training.',call.=FALSE)
  if (isTRUE(artifact$passage$hard_gate_eligible)) stop('M1-B artifact unexpectedly permits a hard passage gate.',call.=FALSE)
  if (!isTRUE(artifact$passage$historical_threshold_search_closed)) stop('M1-B historical passage-search closure is missing.',call.=FALSE)
  if (!isTRUE(artifact$passage$continuous_posterior_shadow_only)) stop('M1-B continuous passage posterior is not marked shadow-only.',call.=FALSE)
  if (!identical(artifact$runtime_contract$allow_passage_decision,FALSE)) stop('M1-B runtime contract does not explicitly disable passage decisions.',call.=FALSE)
  invisible(TRUE)
}

load_m1_b_v3_artifact <- function(path='artifacts/m1-b-v3-peak-v3/m1_b_v3_peak_artifact.rds') {
  if (!file.exists(path)) stop('M1-B artifact not found: ',path,call.=FALSE)
  z <- readRDS(path)
  validate_m1_b_v3_artifact(z)
  z
}

m1_b_v3_peak_posterior <- function(artifact,current_data,activity_week,origin_week,candidate_step=0.1,max_future_weeks=16) {
  validate_m1_b_v3_artifact(artifact)
  m1_v2_peak_posterior(artifact$library,current_data,activation_week=activity_week,origin_week=origin_week,
                       candidate_step=candidate_step,max_future_weeks=max_future_weeks)
}

m1_b_v3_passage_posterior <- function(artifact,current_data,activity_week,origin_week,candidate_step=0.2,max_future_weeks=12) {
  validate_m1_b_v3_artifact(artifact)
  if (!isTRUE(artifact$passage$continuous_posterior_shadow_only)) stop('Continuous passage posterior is not allowed by this artifact.',call.=FALSE)
  m1_v2_passage_posterior(artifact$library,current_data,activation_week=activity_week,origin_week=origin_week,
                          candidate_step=candidate_step,max_future_weeks=max_future_weeks)
}

m1_b_v3_inactive_state <- function() {
  list(state='inactive_no_timing_event',positive_timing_gate=FALSE,peak_posterior=NULL,passage_posterior=NULL)
}

m1_b_v3_passage_decision <- function(...) {
  stop('Hard M1-B passage decisions are disabled. Use continuous passage posterior as shadow uncertainty only.',call.=FALSE)
}
