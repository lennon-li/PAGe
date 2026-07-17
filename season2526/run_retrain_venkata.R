#!/usr/bin/env Rscript
cat("Installing package from source so future workers can find it...\n")
devtools::install("~/repos/PAGe/PAGe", upgrade = FALSE)

cat("Loading package and shared script...\n")
library(PAGe)
source("~/repos/PAGe/scripts/fresh_run/00_shared.R")
library(dplyr)

cat("Setting up multisession...\n")
n_cores = parallel::detectCores() - 1L
future::plan(future::multisession, workers = n_cores)

cat("Loading historical data...\n")
histD <- load_allD(exclude = c(), include_holdout = TRUE)

cat("Pulling 2025-26 from public source via getCurrentD()...\n")
currD <- getCurrentD(season = "2025-26") |>
  dplyr::filter(season == "2025-26")

cat("Combining data and preparing...\n")
histD <- histD |> dplyr::filter(season != "2025-26")
all_raw <- dplyr::bind_rows(histD, currD)
allD <- prepare_surveillance_data(all_raw)

cat("Running full pipeline retune...\n")
retuned <- train_pipeline(allD, mode = "retune")

cat("Saving results...\n")
dir.create("~/repos/PAGe/data", showWarnings = FALSE)
saveRDS(retuned, "~/repos/PAGe/data/retuned_pipeline.rds")
cat("Done.\n")
