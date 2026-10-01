#!/usr/bin/env Rscript

# Governed 2017-18 holdout cycle.  Reuse the maintained cycle runner while
# changing only the season label; all stage gates and artifact contracts stay
# identical to the 2018-19 workflow.

script_file <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
if (is.null(script_file) || !nzchar(script_file)) {
  script_file <- "2017/run_2017_cycle.R"
}
repo_root <- normalizePath(file.path(dirname(script_file), ".."), mustWork = TRUE)
setwd(repo_root)

runner <- readLines(file.path(repo_root, "2018", "run_2018_cycle.R"), warn = FALSE)
needle <- 'holdout_season <- "2018-19"'
if (!any(grepl(needle, runner, fixed = TRUE))) {
  stop("The maintained 2018 cycle runner no longer exposes its holdout label.")
}
runner <- sub(needle, 'holdout_season <- "2017-18"', runner, fixed = TRUE)
# This BCC run is an installed-package smoke test: do not silently load the
# checkout with devtools::load_all().
runner <- sub(
  'suppressPackageStartupMessages(devtools::load_all("PAGe", quiet = TRUE))',
  'suppressPackageStartupMessages(library(PAGe))',
  runner,
  fixed = TRUE
)
eval(parse(text = runner), envir = .GlobalEnv)
