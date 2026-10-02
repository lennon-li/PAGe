#!/usr/bin/env Rscript
source("scripts/m2_nhistory_nested_protocol.R")
source("scripts/m2_nhistory_nested_upstream.R")

Sys.setenv(
  OMP_NUM_THREADS = "1", OPENBLAS_NUM_THREADS = "1", MKL_NUM_THREADS = "1",
  VECLIB_MAXIMUM_THREADS = "1", NUMEXPR_NUM_THREADS = "1"
)

p <- nh_protocol("m2-a-full-ntrend-v2-locked-20260930")
out <- nh_out_dir()
r <- nh_write_gate0(out, p)
if (!identical(as.character(r$status), "PASS")) stop("Gate 0 did not pass.", call. = FALSE)
cat("Gate0 PASS: protocol/input/source manifests locked; zero M2 scientific fits.\n")
