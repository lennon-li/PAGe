#!/usr/bin/env Rscript

source("scripts/publication_stage_report.R")
checks <- stage_report_run_synthetic_checks()
if (!all(checks$pass)) stop("Stage-report synthetic checks failed")
cat("Stage-report synthetic checks passed:", nrow(checks), "checks\n")
