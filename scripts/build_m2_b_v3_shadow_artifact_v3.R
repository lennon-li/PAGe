#!/usr/bin/env Rscript

options(stringsAsFactors=FALSE)

source('scripts/v3_m2_b_runtime_helpers_v3.R')
if (!requireNamespace('digest',quietly=TRUE)) stop('Package `digest` is required.',call.=FALSE)

V2_PATH <- 'artifacts/m2-b-v3-shadow-v2/m2_b_v3_shadow_artifact.rds'
M1_PATH <- 'artifacts/m1-b-v3-peak-v9/m1_b_v3_peak_artifact.rds'
TIMING_PATH <- 'artifacts/v3-joint-timing-contract-v3/timing_contract_v3.csv'
ELIG_PATH <- 'artifacts/v3-joint-timing-contract-v3/modeling_eligibility_v3.csv'
POLICY_PATH <- 'governance/v3_b_season_policy_v1.csv'
HELPER_PATH <- 'scripts/v3_m2_b_runtime_helpers_v3.R'
M1_HELPER_PATH <- 'scripts/v3_m1_b_runtime_helpers_v8.R'
BUILDER_PATH <- 'scripts/build_m2_b_v3_shadow_artifact_v3.R'
DISPOSITION_PATH <- 'docs/v3-m2-b-final-disposition-2026-09-26.md'
CONTRACT_PATH <- 'docs/v3-m2-b-shadow-runtime-contract-2026-09-26.md'
OUT <- 'artifacts/m2-b-v3-shadow-v3'
ARTIFACT_PATH <- file.path(OUT,'m2_b_v3_shadow_artifact.rds')

sha256_file <- function(path) digest::digest(file=path,algo='sha256',serialize=FALSE)
required <- c(V2_PATH,M1_PATH,TIMING_PATH,ELIG_PATH,POLICY_PATH,HELPER_PATH,M1_HELPER_PATH,BUILDER_PATH,DISPOSITION_PATH,CONTRACT_PATH)
if (!all(file.exists(required))) stop('Missing M2-B shadow-v3 packaging dependency.',call.=FALSE)
if (dir.exists(OUT) && length(list.files(OUT,all.files=TRUE,no..=TRUE))) stop('Refusing to overwrite non-empty ',OUT,call.=FALSE)
dir.create(OUT,recursive=TRUE,showWarnings=FALSE)

v2 <- readRDS(V2_PATH)
if (!inherits(v2,'page_m2_b_v3_shadow_artifact') || !identical(v2$version,'m2-b-v3-shadow-v2')) stop('Accepted shadow-v2 source artifact is malformed.',call.=FALSE)
m1 <- readRDS(M1_PATH)
validate_m1_b_v3_artifact(m1)
if (!identical(m1$version,'m1-b-v3-peak-v9')) stop('M1-B v9 dependency mismatch.',call.=FALSE)

# Copy the accepted behavioral payload exactly. Only governance/provenance bindings change.
a <- v2
a$version <- .M2_B_V3_VERSION
a$status <- .M2_B_V3_STATUS
a$production_eligible <- FALSE
a$m1_b$path <- M1_PATH
a$m1_b$version <- m1$version
a$m1_b$artifact_sha256 <- sha256_file(M1_PATH)
a$m1_b$library_hash <- m1$library$provenance$library_hash
a$runtime_contract$required_helper <- HELPER_PATH
a$runtime_contract$required_m1_helper <- M1_HELPER_PATH
a$provenance$m1_b_artifact_sha256 <- sha256_file(M1_PATH)
a$provenance$timing_contract_sha256 <- sha256_file(TIMING_PATH)
a$provenance$modeling_eligibility_sha256 <- sha256_file(ELIG_PATH)
a$provenance$season_policy_sha256 <- sha256_file(POLICY_PATH)
a$provenance$runtime_helper_sha256 <- sha256_file(HELPER_PATH)
a$provenance$m1_runtime_helper_sha256 <- sha256_file(M1_HELPER_PATH)
a$provenance$runtime_contract_sha256 <- sha256_file(CONTRACT_PATH)
a$provenance$disposition_sha256 <- sha256_file(DISPOSITION_PATH)
a$provenance$builder_sha256 <- sha256_file(BUILDER_PATH)
a$provenance$rebased_from_shadow_v2_sha256 <- sha256_file(V2_PATH)
a$provenance$git_head <- system2('git',c('rev-parse','HEAD'),stdout=TRUE)
a$historical_evidence$disposition_sha256 <- sha256_file(DISPOSITION_PATH)
a$artifact_id <- digest::digest(.m2b_v3_core(a),algo='sha256')

# Behavior-preservation assertions: model/shape/constants/routes are copied exactly.
stopifnot(identical(stats::coef(a$state$model),stats::coef(v2$state$model)))
stopifnot(identical(a$state$model,v2$state$model))
stopifnot(identical(a$state$training_seasons,v2$state$training_seasons))
stopifnot(identical(a$shape$grid,v2$shape$grid))
stopifnot(identical(a$shape$tau_grid,v2$shape$tau_grid))
stopifnot(identical(a$shape$A_seasons,v2$shape$A_seasons),identical(a$shape$B_seasons,v2$shape$B_seasons))
stopifnot(identical(a$shape$pooled_weight,v2$shape$pooled_weight),identical(a$shape$B_weight,v2$shape$B_weight),identical(a$shape$eta,v2$shape$eta))
for (nm in c('min_origin_week','horizons','plus1_route','plus2_route','allow_hard_passage','allow_production','lower_bound_step','lower_bound_saturation_threshold','lower_bound_definition')) {
  stopifnot(identical(a$runtime_contract[[nm]],v2$runtime_contract[[nm]]))
}
stopifnot(identical(a$activity$params,v2$activity$params),identical(a$activity$semantics,v2$activity$semantics))

saveRDS(a,ARTIFACT_PATH,version=3)
validate_m2_b_v3_shadow_artifact(readRDS(ARTIFACT_PATH))

metadata <- data.frame(
  key=c('version','status','production_eligible','artifact_id','artifact_sha256','rebased_from_shadow_v2_sha256','m1_b_version','m1_b_artifact_id','m1_b_library_hash','timing_contract_sha256','modeling_eligibility_sha256','season_policy_sha256','plus1_route','plus2_route'),
  value=c(a$version,a$status,'FALSE',a$artifact_id,sha256_file(ARTIFACT_PATH),sha256_file(V2_PATH),m1$version,m1$artifact_id,m1$library$provenance$library_hash,sha256_file(TIMING_PATH),sha256_file(ELIG_PATH),sha256_file(POLICY_PATH),a$runtime_contract$plus1_route,a$runtime_contract$plus2_route),
  stringsAsFactors=FALSE)
write.csv(metadata,file.path(OUT,'metadata.csv'),row.names=FALSE)

# Retain the accepted shadow-v2 behavioral source explicitly, plus all current bindings.
v2_manifest <- read.csv(file.path(dirname(V2_PATH),'source_manifest.csv'),check.names=FALSE,stringsAsFactors=FALSE)
keep_roles <- c('canonical_panel','activity_params','historical_verdict','historical_summary','historical_acceptance','historical_integrity','historical_source_manifest','historical_lower_bound_diagnostic')
manifest <- v2_manifest[v2_manifest$role %in% keep_roles,c('role','path','sha256'),drop=FALSE]
current <- data.frame(
  role=c('behavioral_source_shadow_v2','timing_contract_v3','modeling_eligibility_v3','B_season_policy_source','m1_b_v9','m1_b_runtime_helper_v8','historical_disposition','runtime_contract','runtime_helper_v3','builder_script'),
  path=c(V2_PATH,TIMING_PATH,ELIG_PATH,POLICY_PATH,M1_PATH,M1_HELPER_PATH,DISPOSITION_PATH,CONTRACT_PATH,HELPER_PATH,BUILDER_PATH),
  stringsAsFactors=FALSE)
current$sha256 <- vapply(current$path,sha256_file,character(1))
manifest <- rbind(manifest,current)
manifest <- rbind(manifest,data.frame(role='serialized_artifact',path=ARTIFACT_PATH,sha256=sha256_file(ARTIFACT_PATH),stringsAsFactors=FALSE))
write.csv(manifest,file.path(OUT,'source_manifest.csv'),row.names=FALSE)

cat('Built ',ARTIFACT_PATH,'\n',sep='')
cat('Artifact ID: ',a$artifact_id,'\n',sep='')
cat('Artifact SHA256: ',sha256_file(ARTIFACT_PATH),'\n',sep='')
cat('Rebased from shadow-v2 with identical behavioral payload.\n')
