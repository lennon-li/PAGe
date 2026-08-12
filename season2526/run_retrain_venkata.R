#!/usr/bin/env Rscript

# Opt-in phase 2 only: refit after a separately saved, passing 2025-26
# promotion decision.  This script never creates promotion evidence itself.

args <- commandArgs(trailingOnly = TRUE)
usage <- paste(
  "Usage:",
  "  run_retrain_venkata.R --data=AUTHORIZED.csv --promotion-bundle=DECISION.rds",
  "    --promotion-manifest=MANIFEST.json --candidate-kit=CANDIDATE.rds",
  "    --incumbent-kit=INCUMBENT.rds",
  "    --output-dir=PRIVATE_DIR --manifest-dir=DISCLOSURE_SAFE_DIR",
  "    [--kit-compatibility=strict|legacy_m2] [--preflight-only]",
  "",
  "Runs only the post-acceptance fixed refresh. `--preflight-only` validates",
  "the private inputs and exits before training.",
  sep = "\n"
)
read_arg <- function(name, env = NULL, default = "") {
  prefix <- paste0("--", name, "=")
  hit <- args[startsWith(args, prefix)]
  if (length(hit) > 1L) stop("Supply `--", name, "` at most once.", call. = FALSE)
  value <- if (length(hit)) sub(prefix, "", hit[1L], fixed = TRUE) else default
  if (!nzchar(value) && !is.null(env)) value <- Sys.getenv(env, default)
  value
}
has_flag <- function(name) paste0("--", name) %in% args
if (any(args %in% c("--help", "-h"))) {
  writeLines(usage)
  quit(save = "no", status = 0L)
}
required_arg <- function(name, env = NULL) {
  value <- read_arg(name, env)
  if (!nzchar(value)) stop("Missing required --", name, " argument.", call. = FALSE)
  value
}
read_data <- function(path) {
  if (grepl("[.]rds$", path, ignore.case = TRUE)) readRDS(path) else utils::read.csv(path)
}
git_commit <- function() {
  out <- suppressWarnings(system2("git", c("rev-parse", "--verify", "HEAD"), stdout = TRUE, stderr = FALSE))
  if (length(out) != 1L || !grepl("^[0-9a-f]{7,64}$", out)) {
    stop("Could not determine the current Git commit for the manifest.", call. = FALSE)
  }
  out
}

data_path <- required_arg("data", "PAGE_FLU_HIST_FILE")
promotion_bundle_path <- required_arg("promotion-bundle")
promotion_manifest_path <- required_arg("promotion-manifest")
candidate_path <- required_arg("candidate-kit")
incumbent_path <- required_arg("incumbent-kit")
output_dir <- required_arg("output-dir", "PAGE_REFIT_PRIVATE_DIR")
manifest_dir <- required_arg("manifest-dir", "PAGE_REFIT_MANIFEST_DIR")
kit_compatibility <- match.arg(
  read_arg("kit-compatibility", default = "strict"),
  c("strict", "legacy_m2")
)

if (!requireNamespace("PAGe", quietly = TRUE)) {
  stop("Install PAGe before running this private refit script.", call. = FALSE)
}
script_arg <- commandArgs(trailingOnly = FALSE)
script_path <- sub("^--file=", "", script_arg[startsWith(script_arg, "--file=")][1L])
source(file.path(dirname(normalizePath(script_path)), "refit_helpers.R"))

promotion_bundle <- readRDS(promotion_bundle_path)
invisible(page_validate_promotion_bundle(promotion_bundle, data_path = data_path))
promotion_manifest <- page_read_promotion_manifest(promotion_manifest_path)
page_validate_promotion_manifest(promotion_manifest, promotion_bundle, promotion_bundle_path)
candidate_kit <- readRDS(candidate_path)
invisible(page_candidate_refit_config(candidate_kit, candidate_path, promotion_bundle, promotion_manifest))
invisible(PAGe::verify_promotion_evidence(
  bundle = promotion_bundle,
  manifest = promotion_manifest,
  data_path = data_path,
  candidate_path = candidate_path,
  incumbent_path = incumbent_path,
  bundle_path = promotion_bundle_path,
  kit_compatibility = kit_compatibility
))
allD <- PAGe::prepare_surveillance_data(read_data(data_path))
if (!"2025-26" %in% as.character(allD$season)) {
  stop("Authorized data does not contain 2025-26; cannot perform the post-promotion refit.", call. = FALSE)
}
if (has_flag("preflight-only")) {
  cat("Preflight passed: canonical passing 2025-26 promotion bundle and manifest accepted. No training run.\n")
  quit(save = "no", status = 0L)
}

result <- page_run_post_promotion_refit(
  allD = allD, promotion_bundle = promotion_bundle, promotion_manifest = promotion_manifest,
  candidate_kit = candidate_kit, candidate_path = candidate_path, data_path = data_path,
  incumbent_path = incumbent_path,
  kit_compatibility = kit_compatibility,
  promotion_bundle_path = promotion_bundle_path, promotion_manifest_path = promotion_manifest_path,
  output_dir = output_dir, manifest_dir = manifest_dir, code_commit = git_commit(), verbose = TRUE
)
cat("Saved private refit: ", result$artifact_path, "\n", sep = "")
cat("Saved disclosure-safe manifest: ", result$manifest_path, "\n", sep = "")
cat("Saved disclosure-safe manifest summary: ", result$manifest_markdown_path, "\n", sep = "")
