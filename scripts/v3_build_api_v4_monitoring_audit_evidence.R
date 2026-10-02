#!/usr/bin/env Rscript
options(stringsAsFactors = FALSE)

repo <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
root <- file.path(repo, "artifacts", "v3-api-v4-monitoring-audit-2026-09-28-v2")
if (dir.exists(root)) unlink(root, recursive = TRUE, force = TRUE)
dir.create(root, recursive = TRUE)

source("scripts/v3_weekly_api_helpers_v4.R")
source("scripts/v3_weekly_api_deployment_helpers_v4.R")
source("scripts/build_v3_weekly_api_deployment_v4.R", local = .GlobalEnv)

release_dir <- file.path(repo, "artifacts", "v3-shadow-release-v3", .PAGE_FORECAST_RELEASE_ID)
env <- c(
  PATH = Sys.getenv("PATH"),
  HOME = "/nonexistent/page-api-home",
  R_LIBS_USER = "/nonexistent/page-api-user-library",
  R_LIBS_SITE = "/usr/local/lib/R/site-library:/usr/lib/R/site-library",
  R_PROFILE_USER = "/dev/null",
  R_ENVIRON_USER = "/dev/null",
  TZ = "UTC", LANG = "C.UTF-8", LC_ALL = "C.UTF-8"
)

run_case <- function(name, fixture) {
  case <- file.path(root, name)
  dir.create(case, recursive = TRUE)
  mount <- file.path(case, "mount"); dir.create(mount)
  job <- file.path(mount, "jobs"); dir.create(job)
  out <- file.path(mount, "out"); dir.create(out)
  deps <- file.path(mount, "deployments"); dir.create(deps)

  opt <- list(
    deployment_root = deps, artifact_mount = mount,
    artifact_fs_type = NULL, artifact_mount_source = NULL,
    job_root = job, output_root = out, source_mode = "olis", season = "2026-27",
    bind_host = "127.0.0.1", port = "8089", rscript = Sys.which("Rscript"),
    forecast_release_dir = release_dir,
    olis_fallback = normalizePath(fixture, winslash = "/", mustWork = TRUE),
    max_runtime_seconds = "300", mode = "test"
  )
  dep <- .api_build_deployment(opt, repo)
  writeLines(dep$deployment_id, file.path(case, "deployment_id.txt"))

  pf_path <- file.path(case, "preflight.json")
  pf <- processx::run(
    Sys.which("Rscript"),
    c("--vanilla", "2026/run_page_weekly_api_preflight_v4.R",
      paste0("--deployment-dir=", dep$deployment_dir), paste0("--repo-root=", repo),
      paste0("--release-dir=", release_dir), paste0("--expected-release-id=", .PAGE_FORECAST_RELEASE_ID),
      paste0("--result-path=", pf_path)),
    wd = repo, env = env, timeout = 120, stdout = "|", stderr = "|", error_on_status = FALSE
  )
  writeLines(c(pf$stdout, pf$stderr), file.path(case, "preflight.log"))
  stopifnot(pf$status == 0L)

  cfg <- list(
    repo_root = repo, api_deployment_dir = dep$deployment_dir,
    job_root = job, output_root = out, artifact_mount = mount,
    season = "2026-27", source_mode = "olis",
    forecast_release_id = .PAGE_FORECAST_RELEASE_ID, forecast_release_dir = release_dir,
    rscript = Sys.which("Rscript"), max_runtime_seconds = 300L,
    olis_fallback = normalizePath(fixture, winslash = "/", mustWork = TRUE),
    transaction_schema = file.path(repo, "governance", "v3_weekly_api_transaction_schema_v1.csv"),
    api_environment = file.path(repo, "governance", "v3_weekly_api_environment_v1.tsv")
  )

  rid <- paste0("wr_", digest::digest(name, algo = "md5", serialize = FALSE))
  jd <- .api_job_dir(cfg, rid)
  dir.create(jd, recursive = TRUE)
  .api_atomic_write_json(
    list(run_id = rid, api_contract_version = .PAGE_API_CONTRACT, season = "2026-27",
         expected_release_id = .PAGE_FORECAST_RELEASE_ID, source_mode = "olis",
         created_utc = .api_now(), service_instance_id = "audit"),
    .api_request_path(cfg, rid), TRUE
  )
  .api_atomic_write_json(.api_external_worker_config(cfg), file.path(jd, "worker_config.json"), TRUE)

  wr <- processx::run(
    Sys.which("Rscript"),
    c("--vanilla", "2026/run_page_weekly_api_worker_v4.R", paste0("--job-root=", job), paste0("--run-id=", rid)),
    wd = repo, env = env, timeout = 360000, stdout = "|", stderr = "|", error_on_status = FALSE
  )
  writeLines(c(wr$stdout, wr$stderr), file.path(case, "worker-process.log"))
  receipt <- .api_read_json(.api_worker_result_path(cfg, rid))
  .api_atomic_write_json(receipt, file.path(case, "worker_result.json"))

  for (f in c("result.json", "provenance.json", "transaction_ref.json")) {
    if (file.exists(file.path(jd, f))) file.copy(file.path(jd, f), file.path(case, f))
  }
  sr <- file.path(out, "api-runs", rid, "2026-27")
  if (dir.exists(sr)) {
    txs <- list.dirs(sr, recursive = FALSE, full.names = TRUE)
    txs <- txs[!endsWith(txs, "/.pending") & !endsWith(txs, "/failures")]
    if (length(txs)) {
      for (f in c("source_transaction.tsv", "v2_v3_comparison.csv", "COMPLETED")) {
        if (file.exists(file.path(txs[[1]], f))) file.copy(file.path(txs[[1]], f), file.path(case, f))
      }
    }
  }
  list(deployment_id = dep$deployment_id, run_id = rid, status = receipt$status, case = case)
}

# Real current weekF11: must fail closed because origin < 12.
real <- run_case(
  "real-weekF11",
  file.path(repo, "artifacts", "v3-live-2026-27-week11-deployment-v1", "input", "hist_olis.RData")
)
stopifnot(identical(real$status, "failed"))

# Synthetic weekF12 with A ignition / active M1-A.
dates <- as.Date("2026-07-05") + 7 * (0:11)
fix1 <- file.path(root, "synthetic-weekF12-ignition.RData")
r <- list(
  fluA = data.frame(date = dates, pos = c(2,3,4,5,8,12,18,26,38,62,115,154), tests = rep(4000,12)),
  fluB = data.frame(date = dates, pos = c(0,0,1,0,1,1,1,2,1,2,2,3), tests = rep(4000,12))
)
save(r, file = fix1)
ign <- run_case("synthetic-weekF12-ignition", fix1)
stopifnot(identical(ign$status, "succeeded"))
ri <- jsonlite::fromJSON(file.path(ign$case, "result.json"), simplifyVector = FALSE)
stopifnot(isTRUE(ri$monitoring$A$m0$ignited), isTRUE(ri$monitoring$A$m1$available), length(ri$forecasts) == 4L)

# Synthetic weekF12 with no A ignition: M1-A must remain unavailable without failing the API.
fix2 <- file.path(root, "synthetic-weekF12-no-ignition.RData")
r <- list(
  fluA = data.frame(date = dates, pos = c(0,0,0,1,0,1,0,1,0,1,1,1), tests = rep(4000,12)),
  fluB = data.frame(date = dates, pos = c(0,0,0,0,0,0,0,0,0,0,0,1), tests = rep(4000,12))
)
save(r, file = fix2)
noign <- run_case("synthetic-weekF12-no-ignition", fix2)
stopifnot(identical(noign$status, "succeeded"))
rn <- jsonlite::fromJSON(file.path(noign$case, "result.json"), simplifyVector = FALSE)
stopifnot(identical(rn$monitoring$A$m0$ignited, FALSE), identical(rn$monitoring$A$m1$available, FALSE), length(rn$forecasts) == 4L)

rows <- data.frame(
  case = c("real-weekF11", "synthetic-weekF12-ignition", "synthetic-weekF12-no-ignition"),
  deployment_id = c(real$deployment_id, ign$deployment_id, noign$deployment_id),
  run_id = c(real$run_id, ign$run_id, noign$run_id),
  status = c(real$status, ign$status, noign$status),
  stringsAsFactors = FALSE
)
write.csv(rows, file.path(root, "execution_summary.csv"), row.names = FALSE)
cat("Evidence root: ", root, "\n", sep = "")
print(rows, row.names = FALSE)
