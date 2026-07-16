#!/usr/bin/env Rscript

# Manual, opt-in real-data acceptance gate. This script is deliberately not
# called by package tests or CI.
args <- commandArgs(trailingOnly = TRUE)
read_arg <- function(name, env = NULL) {
  prefix <- paste0("--", name, "=")
  hit <- args[startsWith(args, prefix)]
  value <- if (length(hit)) sub(prefix, "", hit[1L], fixed = TRUE) else ""
  if (!nzchar(value) && !is.null(env)) value <- Sys.getenv(env, "")
  value
}

data_path <- read_arg("data", "PAGE_FLU_HIST_FILE")
kit_path <- read_arg("kit")
incumbent_path <- read_arg("incumbent-metrics")
if (!nzchar(data_path) || !nzchar(kit_path) || !nzchar(incumbent_path)) {
  stop(
    "Usage: replay_2025_26.R --kit=KIT.rds ",
    "--incumbent-metrics=METRICS.rds --data=FLU.csv\n",
    "`--data` may be replaced by PAGE_FLU_HIST_FILE."
  )
}

if (!requireNamespace("PAGe", quietly = TRUE)) {
  stop("Install PAGe before running the manual acceptance script.")
}
read_data <- function(path) {
  if (grepl("[.]rds$", path, ignore.case = TRUE)) readRDS(path) else utils::read.csv(path)
}

kit <- readRDS(kit_path)
allD <- read_data(data_path)
incumbent <- readRDS(incumbent_path)
replay <- PAGe::replay_season_holdout(kit, allD, season = "2025-26")
gate <- PAGe::check_promotion(replay$metrics, incumbent)

print(gate$gates, row.names = FALSE)
if (length(gate$reasons)) writeLines(paste("-", gate$reasons))
if (!isTRUE(gate$pass)) quit(save = "no", status = 1L)
writeLines("PASS: unseen 2025-26 replay satisfies all promotion gates.")
