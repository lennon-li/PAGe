#!/usr/bin/env Rscript

# Manual, opt-in real-data acceptance gate. It preserves candidate-versus-
# incumbent replay evidence before reporting a failing promotion decision.

args <- commandArgs(trailingOnly = TRUE)
usage <- paste(
  "Usage:",
  "  replay_2025_26.R --data=AUTHORIZED.csv --candidate-kit=CANDIDATE.rds",
  "    --incumbent-kit=INCUMBENT.rds --private-output=PRIVATE_DIR",
  "    --audit-output=results/audit [--season=2025-26] [--run-id=ID]",
  "    [--kit-compatibility=strict|legacy_m2]",
  "",
  "`--data` may be replaced by PAGE_FLU_HIST_FILE. Private replay objects and",
  "the decision bundle are written only under --private-output; --audit-output",
  "receives aggregate CSV/Markdown/JSON evidence only. Existing run IDs fail",
  "rather than overwrite a decision. No refit or promotion is performed.",
  sep = "\n"
)

read_arg <- function(name, env = NULL) {
  prefix <- paste0("--", name, "=")
  hit <- args[startsWith(args, prefix)]
  if (length(hit) > 1L) stop("Supply `--", name, "` at most once.", call. = FALSE)
  value <- if (length(hit)) sub(prefix, "", hit[[1L]], fixed = TRUE) else ""
  if (!nzchar(value) && !is.null(env)) value <- Sys.getenv(env, "")
  value
}

if (any(args %in% c("--help", "-h"))) {
  writeLines(usage)
  quit(save = "no", status = 0L)
}

data_path <- read_arg("data", "PAGE_FLU_HIST_FILE")
candidate_path <- read_arg("candidate-kit")
incumbent_path <- read_arg("incumbent-kit")
private_output_dir <- read_arg("private-output")
audit_output_dir <- read_arg("audit-output")
season <- read_arg("season")
run_id <- read_arg("run-id")
if (!nzchar(season)) season <- "2025-26"
if (!all(nzchar(c(data_path, candidate_path, incumbent_path, private_output_dir, audit_output_dir)))) {
  stop(usage, call. = FALSE)
}
if (!requireNamespace("PAGe", quietly = TRUE)) {
  stop("Install PAGe before running the manual acceptance script.", call. = FALSE)
}

script_file <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[1L])
if (is.na(script_file) || !nzchar(script_file)) script_file <- "scripts/acceptance/replay_2025_26.R"
source(file.path(dirname(normalizePath(script_file)), "acceptance_workflow.R"))

run_args <- list(
  data_path = data_path,
  candidate_path = candidate_path,
  incumbent_path = incumbent_path,
  private_output_dir = private_output_dir,
  audit_output_dir = audit_output_dir,
  season = season,
  kit_compatibility = match.arg(
    read_arg("kit-compatibility"),
    c("", "strict", "legacy_m2")
  )
)
if (!nzchar(run_args$kit_compatibility)) run_args$kit_compatibility <- "strict"
if (nzchar(run_id)) run_args$run_id <- run_id
result <- do.call(run_acceptance_replay, run_args)
writeLines(c(
  paste0("PASS: private decision bundle saved at `", result$paths$private_bundle, "`."),
  paste0("PASS: disclosure-safe audit evidence saved at `", result$paths$audit_dir, "`.")
))
