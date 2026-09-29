#!/usr/bin/env Rscript

options(stringsAsFactors=FALSE)

source('scripts/v3_shadow_release_helpers_v1.R')
if (!requireNamespace('digest',quietly=TRUE)) stop('Package `digest` is required.',call.=FALSE)

ROOT <- 'artifacts/v3-shadow-release-v2'
dir.create(ROOT,recursive=TRUE,showWarnings=FALSE)

entries <- list()
add <- function(role,path) {
  entries[[length(entries)+1L]] <<- data.frame(role=role,path=path,stringsAsFactors=FALSE)
}

# Normative governance/policy sources.
add('B_season_policy','governance/v3_b_season_policy_v1.csv')
add('runtime_environment','governance/v3_runtime_environment_v1.tsv')
add('canonical_component_inventory_machine','governance/v3_early_origin_component_inventory_v1.csv')
add('early_origin_release_disposition','docs/v3-early-origin-release-disposition-2026-09-28.md')
add('early_origin_runtime_contract','docs/v3-early-origin-runtime-contract-2026-09-28.md')
add('master_v3_plan','docs/v3-joint-ab-modeling-plan-2026-09-25.md')
add('governance_hardening_plan','docs/v3-governance-hardening-plan-2026-09-27.md')
add('governance_hardening_audit','docs/v3-governance-hardening-audit-disposition-2026-09-27.md')
add('artifact_storage_policy','docs/artifact-storage.md')
add('M1_B_final_disposition','docs/v3-m1-b-final-disposition-2026-09-26.md')
add('M2_A_final_disposition','docs/v3-m2-a-final-disposition-2026-09-26.md')
add('M2_B_final_disposition','docs/v3-m2-b-final-disposition-2026-09-26.md')
add('M2_B_prior_runtime_contract','docs/v3-m2-b-shadow-runtime-contract-2026-09-26.md')

# Frozen/growth artifacts used by runtime.
add('M0_A_artifact','artifacts/m0-v2-wmin12-raw3-se1-decimal-loso-v1/loso_result.rds')
add('M1_A_artifact','artifacts/m1-v2-wmin12-raw3-se1-full-history-v1/m1_v2_stage.rds')
add('M2_A_artifact','artifacts/m2-v2-c2-governed-v1/m2_v2_c2_governed_fit.rds')
add('M1_B_artifact','artifacts/m1-b-v3-peak-v9/m1_b_v3_peak_artifact.rds')
add('M1_B_package_manifest','artifacts/m1-b-v3-peak-v9/source_manifest.csv')
add('M2_B_artifact','artifacts/m2-b-v3-shadow-v4/m2_b_v3_shadow_artifact.rds')
add('M2_B_package_manifest','artifacts/m2-b-v3-shadow-v4/source_manifest.csv')

# Deterministic timing/policy outputs.
for (p in c('timing_contract_v3.csv','modeling_eligibility_v3.csv','timing_geometry_v3.csv','season_observation_regimes.csv','contract_metadata.csv','source_manifest.csv')) {
  add(paste0('timing_contract_output_',sub('[.]csv$','',p)),file.path('artifacts/v3-joint-timing-contract-v3',p))
}

# Canonical historical evidence locked by the decisions.
for (pair in list(
  c('M1_B_evidence_summary','artifacts/v3-m1-b0-excluding-pandemic-v1/summary_metrics.csv'),
  c('M1_B_evidence_per_season','artifacts/v3-m1-b0-excluding-pandemic-v1/per_season_metrics.csv'),
  c('M2_A_evidence_verdict','artifacts/v3-m2-a-posterior-c2-chronological-v1/overall_verdict.csv'),
  c('M2_A_evidence_integrity','artifacts/v3-m2-a-posterior-c2-chronological-v1/integrity_checks.csv'),
  c('M2_B_evidence_verdict','artifacts/v3-m2-b-posterior-c2-chronological-v3/overall_verdict.csv'),
  c('M2_B_evidence_summary','artifacts/v3-m2-b-posterior-c2-chronological-v3/summary_metrics.csv'),
  c('M2_B_evidence_acceptance','artifacts/v3-m2-b-posterior-c2-chronological-v3/acceptance_criteria.csv'),
  c('M2_B_evidence_integrity','artifacts/v3-m2-b-posterior-c2-chronological-v3/integrity_checks.csv'),
  c('M2_B_evidence_lower_bound','artifacts/v3-m2-b-posterior-c2-chronological-v3/lower_bound_reset_summary.csv')
)) add(pair[[1]],pair[[2]])
for (pair in list(
  c('M2_A_early_origin_summary','artifacts/v3-m2-a-early-origin-support-v1/summary_metrics.csv'),
  c('M2_A_early_origin_integrity','artifacts/v3-m2-a-early-origin-support-v1-determinism/integrity_checks.csv'),
  c('M2_A_early_origin_predictions','artifacts/v3-m2-a-early-origin-support-v1/per_origin_predictions.csv'),
  c('M2_B_early_origin_summary','artifacts/v3-m2-b-early-origin-support-v1/summary_metrics.csv'),
  c('M2_B_early_origin_integrity','artifacts/v3-m2-b-early-origin-support-v1/integrity_checks.csv'),
  c('M2_B_early_origin_predictions','artifacts/v3-m2-b-early-origin-support-v1/per_origin_predictions.csv'),
  c('M2_A_early_origin_benchmark_script','scripts/v3_benchmark_m2_a_early_origin_support_v1.R'),
  c('M2_B_early_origin_benchmark_script','scripts/v3_benchmark_m2_b_early_origin_support_v1.R')
)) add(pair[[1]],pair[[2]])

# Builders/helpers and authoritative runners.
for (pair in list(
  c('timing_contract_builder','scripts/v3_build_timing_contract_v3.R'),
  c('M1_B_builder','scripts/build_m1_b_v3_peak_artifact_v9.R'),
  c('M1_B_runtime_helper','scripts/v3_m1_b_runtime_helpers_v8.R'),
  c('M2_B_builder','scripts/build_m2_b_v3_shadow_artifact_v4.R'),
  c('M2_B_runtime_helper','scripts/v3_m2_b_runtime_helpers_v4.R'),
  c('ops_helper','scripts/v3_shadow_ops_helpers_v1.R'),
  c('release_helper','scripts/v3_shadow_release_helpers_v1.R'),
  c('release_builder','scripts/build_v3_shadow_release_v2.R'),
  c('v2_runner','2026/run_weekly_shadow_v2.R'),
  c('combined_v3_runner','2026/run_weekly_shadow_v3_early_v1.R'),
  c('standalone_M2_B_runner','2026/run_weekly_m2_b_shadow_v4.R'),
  c('release_launcher','2026/run_weekly_shadow_release_v4.R')
)) add(pair[[1]],pair[[2]])

# Exact dynamic package-source closure. Role is intentionally repeatable.
pkg_sources <- sort(gsub('\\\\','/',list.files('PAGe/R',pattern='[.]R$',full.names=TRUE)))
for (p in pkg_sources) add('runtime_package_source',p)

# Acceptance/regression tests bound into this release.
tests <- c(
  'PAGe/tests/testthat/test-timing-contract-v3-governance.R',
  'PAGe/tests/testthat/test-m1-b-v3-shadow-contract-v9.R',
  'PAGe/tests/testthat/test-m2-b-v3-shadow-contract-v3.R',
  'PAGe/tests/testthat/test-v3-governance-ops-hardening.R',
  'PAGe/tests/testthat/test-weekly-shadow-v2-runner.R',
  'PAGe/tests/testthat/test-weekly-shadow-v3-runner.R',
  'PAGe/tests/testthat/test-weekly-m2-b-v3-runner.R',
  'PAGe/tests/testthat/test-v3-shadow-release-governance.R',
  'PAGe/tests/testthat/test-v3-early-origin-support-contract.R',
  'PAGe/tests/testthat/test-v3-early-origin-release-v2.R'
)
for (p in tests) add('acceptance_test',p)

spec <- do.call(rbind,entries)
missing <- spec$path[!file.exists(spec$path)]
if (length(missing)) stop('Release dependency missing: ',paste(missing,collapse=', '),call.=FALSE)

# Roles that must occur exactly once. Multi-valued roles are runtime_package_source and acceptance_test.
singular <- setdiff(unique(spec$role),c('runtime_package_source','acceptance_test'))
counts <- table(spec$role)
if (any(counts[singular]!=1L)) stop('Release has duplicate/missing singular normative role.',call.=FALSE)

manifest <- .v3_release_manifest_frame(spec$role,spec$path)
release_id <- .v3_release_id_from_manifest(manifest)
final_dir <- file.path(ROOT,release_id)
if (dir.exists(final_dir)) {
  got <- .v3_release_validate(final_dir,expected_id=release_id)
  cat('Release already exists and validates: ',got$release_dir,'\n',sep='')
  cat('release_id: ',release_id,'\n',sep='')
  quit(status=0L)
}

stage <- file.path(ROOT,paste0('.pending-',Sys.getpid(),'-',substr(release_id,1,12)))
if (dir.exists(stage)) stop('Release staging directory already exists: ',stage,call.=FALSE)
dir.create(stage,recursive=TRUE,showWarnings=FALSE)
on.exit(if (dir.exists(stage)) unlink(stage,recursive=TRUE,force=TRUE),add=TRUE)

.v3_release_write_manifest(manifest,file.path(stage,'release_manifest.tsv'))
writeLines(release_id,file.path(stage,'release_id.txt'),useBytes=TRUE)

code_roles <- c('runtime_package_source','timing_contract_builder','M1_B_builder','M1_B_runtime_helper','M2_B_builder','M2_B_runtime_helper','ops_helper','release_helper','release_builder','v2_runner','combined_v3_runner','standalone_M2_B_runner','release_launcher')
code_manifest <- manifest[manifest$role %in% code_roles,,drop=FALSE]
utils::write.csv(code_manifest,file.path(stage,'code_manifest.csv'),row.names=FALSE)

status_txt <- paste(system2('git',c('status','--porcelain'),stdout=TRUE),collapse='\n')
metadata <- data.frame(
  key=c('release_family','release_id','created_utc','git_head','git_dirty','git_status_sha256','identity_authority','artifact_storage_policy','R_version','digest_version','mgcv_version','n_manifest_entries','n_runtime_package_sources','n_acceptance_tests'),
  value=c(
    'v3-shadow-release-v2-early-origin',release_id,format(Sys.time(),'%Y-%m-%dT%H:%M:%SZ',tz='UTC'),
    system2('git',c('rev-parse','HEAD'),stdout=TRUE),ifelse(nzchar(status_txt),'TRUE','FALSE'),
    digest::digest(status_txt,algo='sha256',serialize=FALSE),'content_addressed_release_manifest','docs/artifact-storage.md',
    as.character(getRversion()),as.character(utils::packageVersion('digest')),as.character(utils::packageVersion('mgcv')),
    nrow(manifest),sum(manifest$role=='runtime_package_source'),sum(manifest$role=='acceptance_test')
  ),stringsAsFactors=FALSE)
utils::write.csv(metadata,file.path(stage,'release_metadata.csv'),row.names=FALSE)
utils::write.csv(read.csv('governance/v3_early_origin_component_inventory_v1.csv',check.names=FALSE),file.path(stage,'canonical_component_inventory.csv'),row.names=FALSE)

# Validate staged identity/files using the same runtime validator before publish.
.v3_release_validate(stage,expected_id=release_id)
if (!file.rename(stage,final_dir)) stop('Could not atomically publish v3 shadow release.',call.=FALSE)
# Validate published directory once more.
got <- .v3_release_validate(final_dir,expected_id=release_id)
cat('Built content-addressed v3 shadow release: ',got$release_dir,'\n',sep='')
cat('release_id: ',release_id,'\n',sep='')
cat('manifest entries: ',nrow(manifest),' | PAGe/R sources: ',sum(manifest$role=='runtime_package_source'),' | tests: ',sum(manifest$role=='acceptance_test'),'\n',sep='')
