#!/usr/bin/env Rscript

# Replay the frozen 2022-23 candidate after the governed retune succeeds.

source_script <- "/home/yeli/repos/PAGe/2018/replay_2018_19.R"
if (!file.exists(source_script)) stop("Replay template not found: ", source_script)
script <- paste(readLines(source_script, warn = FALSE), collapse = "\n")
script <- gsub("2018-19", "2022-23", script, fixed = TRUE)
script <- gsub("2018_19", "2022_23", script, fixed = TRUE)
script <- gsub("2018/replay_2022_23.R", "2022/replay_2022_23.R", script, fixed = TRUE)
eval(parse(text = script), envir = .GlobalEnv)
