#!/usr/bin/env Rscript

# Governed 2022-23 exchangeable-season cycle.  The archived M0 settlement is
# reused; M1 is expanded before the dependent M2 stage is allowed to run.

source_runner <- "/home/yeli/PAGe-bcc-artifacts/asgard-archive-20260812/holdouts-and-docs/2024/exchangeable/run_exchangeable_2024_25.R"
if (!file.exists(source_runner)) {
  stop("Maintained exchangeable runner not found: ", source_runner)
}
runner <- paste(readLines(source_runner, warn = FALSE), collapse = "\n")

# The archived source runner was originally stored under a repository-local
# 2024/exchangeable directory.  This checkout keeps those scripts in the
# artifact archive, so anchor its repository calculation explicitly.
old_repo <- 'repo_root <- normalizePath(file.path(dirname(script_file), "../.."), mustWork = TRUE)'
new_repo <- 'repo_root <- normalizePath("/home/yeli/repos/PAGe", mustWork = TRUE)'
if (!grepl(old_repo, runner, fixed = TRUE)) {
  stop("The maintained runner no longer exposes its repository calculation.")
}
runner <- sub(old_repo, new_repo, runner, fixed = TRUE)

old_m2 <- 'readRDS(file.path(repo_root, "2024", "artifacts", "m2_tuning.rds"))'
new_m2 <- 'readRDS(Sys.getenv("PAGE_OLD_M2_TUNING"))'
if (!grepl(old_m2, runner, fixed = TRUE)) {
  stop("The maintained runner no longer exposes its prior M2 artifact path.")
}
runner <- sub(old_m2, new_m2, runner, fixed = TRUE)

old_m1 <- "m1_grid = PAGe::default_m1_grid(),"
new_m1 <- paste0(
  "m1_grid = data.table::CJ(",
  "k_ref = c(15L, 20L, 25L, 30L, 40L, 50L), ",
  "multi_temperature = 0.25, template_shift = 0L, ",
  "align_rise_weight = 1.0, slope_window = 6L, ",
  "slope_weight = c(4.0, 8.0, 12.0, 16.0, 20.0, 30.0), ",
  "sorted = FALSE),"
)
if (!grepl(old_m1, runner, fixed = TRUE)) {
  stop("The maintained runner no longer exposes its default M1 grid.")
}
runner <- sub(old_m1, new_m1, runner, fixed = TRUE)

if (identical(Sys.getenv("PAGE_PREFLIGHT_ONLY"), "1")) {
  parse(text = runner)
  cat("2022-23 runner preflight syntax OK; M1 grid=36 specs\n")
  quit(save = "no", status = 0L)
}

eval(parse(text = runner), envir = .GlobalEnv)
