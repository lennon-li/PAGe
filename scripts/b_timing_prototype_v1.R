#!/usr/bin/env Rscript

# Compatibility entry point for the reviewed Influenza-B timing prototype.
#
# The first delegated draft used a half-maximum ignition target, the frozen
# Influenza-A amplitude grid, and model-dependent B0/B1 origins. Those choices
# were rejected in review. The authoritative prototype now lives in
# `evaluate_flu_b_timing_baselines_v1.R`, which uses the transferred A-expert
# ignition geometry, B-specific amplitude support, strict LOSO, candidate-
# independent numeric ledgers, and explicit timing-availability sensitivity.

message("Delegating to reviewed Flu-B timing/baseline evaluation")
source("scripts/evaluate_flu_b_timing_baselines_v1.R")
