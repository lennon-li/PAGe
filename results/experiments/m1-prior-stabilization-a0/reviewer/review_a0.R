#!/usr/bin/env Rscript
suppressPackageStartupMessages(library(data.table))
root <- normalizePath(getwd(), mustWork = TRUE)
bundle <- file.path(root, "results/experiments/m1-prior-stabilization-a0")
baseline <- file.path(root, "results/experiments/m1-replay-baseline-v1.0.0")
contract <- file.path(root, "results/benchmark-contracts/m1/v1.0.0")
fail <- function(x) stop(x, call. = FALSE)
pred <- fread(file.path(bundle, "outputs/predictions.csv"))
met <- fread(file.path(bundle, "outputs/metrics.csv"))
cmp <- fread(file.path(bundle, "outputs/comparison_to_baseline.csv"))
base <- fread(file.path(baseline, "workers/A/runA/ledgers/peak_ledger.csv"))
origin <- fread(file.path(contract, "origin_ledger.csv"))
if (length(unique(pred$variant_id)) != 4L) fail("Expected four variants")
if (any(pred[, .N, by = variant_id]$N != 334L)) fail("Variant coverage is not 334")
if (any(pred[, sum(in_primary_prepeak), by = variant_id]$V1 != 92L)) fail("Primary coverage is not 92")
if (any(!is.finite(pred$m1_peak_raw))) fail("Non-finite candidate peak")
if (any(pred[variant_id != "baseline", is.na(m1_peak_integer)])) fail("Missing candidate integer peak")
key <- c("origin_id", "season", "origin_weekF")
if (nrow(base) != 334L) fail("Sealed baseline ledger is not 334 rows")
bp <- pred[variant_id == "baseline"]
setkeyv(bp, key); setkeyv(base, key)
if (!identical(bp$origin_id, base$origin_id)) fail("Baseline origin keys differ")
if (any(bp$m1_peak_integer != base$peak_weekF_rounded)) fail("Baseline rounded parity failed")
if (max(abs(bp$m1_peak_raw - (base$t_peak_native - base$anchorWeek + base$iWeek_hat))) > 1e-10) fail("Baseline native parity failed")
if (any(pred[, .N, by = .(variant_id, origin_id)]$N != 1L)) fail("Duplicate variant-origin rows")
if (nrow(origin) != 334L) fail("Contract origin ledger mismatch")
if (any(abs(cmp$primary_integer_mae - 1.156121576654504) > 1e-12)) fail("Candidate integer metric mismatch")
if (any(abs(cmp$primary_decimal_mae - 1.24413030904124) > 1e-12)) fail("Candidate decimal metric mismatch")
if (any(cmp$delta_primary_integer != 0)) fail("Integer delta is non-zero")
if (any(abs(cmp$delta_primary_decimal + 0.000333069185191492) > 1e-12)) fail("Decimal delta mismatch")
if (any(met[variant_id == "baseline", primary_integer_mae] != 1.1561215766545)) fail("Baseline metric mismatch")
if (any(abs(met[variant_id == "baseline", primary_decimal_mae] - 1.24446337822643) > 1e-12)) fail("Baseline decimal metric mismatch")
writeLines(c(
  "A0 independent fresh-process review: PASS",
  "four variants; 334 full origins and 92 primary origins each",
  "baseline rounded and native peak parity checked against sealed ledger",
  "candidate metrics and deltas checked against immutable output tables",
  "no production files were inspected for modification by this reviewer"
), file.path(bundle, "validation/review_a0.txt"))
cat("A0 review PASS\n")
