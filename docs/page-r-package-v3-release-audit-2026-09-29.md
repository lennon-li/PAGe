# PAGe R-package v3 release audit — 2026-09-29

## Disposition

**APPROVED for shadow operational use and first real weekF12 execution.**

The canonical v3 forecasting stack is now available as a self-contained R-package workflow. Shell/systemd deployment is optional infrastructure only; model execution, validation, training workflow, ignition review, peak monitoring, and forecast routing live inside `PAGe`.

The canonical pretrained runtime remains shadow-only and production-ineligible.

## Checked package artifact

Package: `PAGe` 0.3.0  
Tarball: `PAGe_0.3.0.tar.gz`  
Tarball SHA-256:

`26bb3b2b1fa0c11d5f8f814cc1c5da4cffaa09216bb2665473d9220372b2947e`

Evidence manifest:

`artifacts/page-r-package-v3-release-2026-09-29/evidence_manifest.csv`

The manifest contains 28 hashed files covering the package-native runtime, training workflow, comparison API, bundled model artifacts, package fixtures, tests, namespace/help entries, and vignettes.

## Canonical release binding

Canonical forecast release:

`5472d08992b5a9da40a9419b75c7427847ff7b1999070041d5e38b0a71da853b`

Bundled model directory:

`PAGe/inst/models/v3-week12/`

Frozen runtime artifacts:

- M0-A SHA-256 `9598486e78eedd8e322da77b0d990db60ca07224c3c6ea6ac61cea9cc6fb611d`
- M1-A SHA-256 `cfeb370305c5b81d66d7eafd7e45ee7e946836ba9f841854f2ec068cf3d43b09`
- M2-A SHA-256 `1efe590c5222f6061af7bef46b0ea19657ec37e070549898569a62ccd4ac65bb`
- M1-B SHA-256 `a98629fc313388487e9b3471ae9934cfae8cbc35cdb707ba371f680162691694`
- M2-B SHA-256 `cae89144c461636662380c19880bf6c5780ce76347edf6b3e30617a614af7226`

`page_v3_models()` validates the bundled manifest and artifact hashes before returning the model bundle and exposes the canonical release ID, manifest, and manifest SHA publicly.

## Package-native runtime

Public entrypoint:

`page_v3_forecast(data, season = NULL, origin_weekF = NULL, strict = TRUE)`

Supported inputs:

- canonical typed A/B weekly panel;
- OLIS `.RData` snapshot containing `r$fluA` and `r$fluB`;
- ORVT CSV path through the package's existing source adapter.

The runtime does not `source()` repository scripts and does not depend on external `artifacts/`, shell scripts, or systemd.

Governed behavior:

- before weekF12: valid result with `issued = FALSE`;
- weekF12+: requires the latest three consecutive observations through the origin;
- M0-A determines ignition;
- M1-A becomes available after ignition and returns peak mean, 90% interval, weeks-to-peak, and passage probabilities;
- M2-A +1/+2 use the frozen governed A1 state route;
- B +1 uses exact B1;
- B +2 uses posterior-C2 only when causal B timing is available, otherwise exact B1 fallback;
- runtime remains `shadow_only`, `production_eligible = FALSE`.

OLIS input now fails closed on invalid dates, non-finite/negative counts, non-positive denominators, or positives exceeding tests. Typed-panel positivity is checked against `y/N` in strict mode.

## Runtime equivalence evidence

`PAGe/tests/testthat/test-v3-package-runtime.R`

Final targeted runtime assertions: **53/53**.

Coverage includes:

- exact bundled artifact hashes;
- pre-weekF12 non-issuance;
- retained weekF12 A-ignition case versus the audited API-v4 child transaction;
- retained weekF12 A-no-ignition case versus the audited API-v4 child transaction;
- typed-panel versus OLIS identity;
- active B posterior-C2 equivalence;
- bundle tamper rejection;
- invalid OLIS count rejection;
- S3 result/print behavior.

## End-to-end user training workflow

Public functions:

- `page_label_ignitions()`
- `page_train_workflow()`
- `page_save_kit()`
- `page_load_kit()`

`page_label_ignitions()` presents each requested season using the existing `review_expert_ignition()` Plotly review and asks the user for a decimal ignition week in interactive mode. A named numeric vector provides the reproducible non-interactive equivalent.

The expert decimal annotation is retained for provenance. The current integer M0/M1 training contract receives `floor(ignition_week_decimal)` explicitly.

`page_train_workflow()` reuses the existing governed `train_pipeline()`; it does not implement a second training engine and does not silently fall back to package-default ignition labels.

Holdout governance was hardened during audit:

- automatic expert review occurs only for trainable seasons after `exclude` and `prospective_holdout` are applied;
- unreleased holdout/excluded seasons are not plotted or requested by the wrapper;
- if a supplied label set contains holdout/excluded labels, they remain attached to provenance but are stripped before `train_pipeline()` is called.

Final training-workflow assertions: **25/25**.

## User vignettes

The following vignettes render successfully from a clean installed package:

- `train-your-own-page.Rmd`
- `deploy-and-forecast.Rmd`
- `canonical-v3-week12.Rmd`
- `model-version-comparison.Rmd`

The training vignette explicitly recommends that an unreleased prospective holdout remain outside fitting, tuning, and expert ignition review.

## v1 / v2 / v3 comparison evidence

Public accessor:

`page_version_metrics()`

Bundled evidence:

`PAGe/inst/extdata/page-version-comparison.csv`

The table deliberately reports only matched or explicitly chronological comparisons. It leaves v3-A metrics `NA` when v3 was not independently scored on the exact legacy/v2 ledger instead of copying inherited metrics by assumption.

Verified comparisons:

### M1-A peak timing — strict matched common ledger

81 matched origin/truth rows across 10 seasons:

- v1/legacy MAE: **1.375185 weeks**
- v2 MAE: **1.092541 weeks**
- relative MAE reduction: **20.55%**

This is a v1/legacy versus v2 result. Canonical v3 preserves the M1-A lineage but is not assigned an independent metric on this exact ledger.

### M2-A +1 / +2 — matched historical targets

10 historical seasons with identical target rows/counts:

+1:

- v1/legacy MAE: **8.408648 pp**
- v2 MAE: **1.775720 pp**
- relative reduction: **78.88%**

+2:

- v1/legacy MAE: **9.205609 pp**
- v2 MAE: **2.412436 pp**
- relative reduction: **73.79%**

Caveat: target rows/counts are matched, but historical training snapshots are not perfectly vintage-matched. Canonical v3 preserves the governed A1 route but is not assigned a v3 score on this exact ledger.

### M2-B +2 — chronological v2 versus v3

Seven-season chronological benchmark:

- v2 B1 MAE: **0.514552 pp**
- v3 posterior-C2 MAE: **0.436010 pp**
- relative reduction: **15.26%**

Timing-active subset, 89 rows / 5 seasons:

- v2 B1 MAE: **0.735688 pp**
- v3 posterior-C2 MAE: **0.552439 pp**
- relative reduction: **24.91%**
- **5/5 timing-active seasons improved**.

Final comparison/accessor assertions: **13/13**.

## Targeted acceptance total

- package-native v3 runtime: **53/53**
- training/annotation workflow: **25/25**
- version-comparison evidence/API: **13/13**

Total: **91/91 targeted assertions**.

## Clean install and R CMD check

A clean `R CMD INSTALL` succeeds and the bundled model/fixture directories are present inside the installed package library.

A fresh `R CMD build PAGe` succeeds and builds all package vignettes.

A fresh check of the exact tarball above:

`R CMD check --no-manual PAGe_0.3.0.tar.gz`

completed with exit code **0**. The full package test suite passed:

`Running 'testthat.R' ... OK`

Final check status:

`Status: 1 WARNING, 2 NOTEs`

The remaining warning/notes are pre-existing package documentation/static-analysis debt outside the new v3 package surface:

- existing undocumented arguments / malformed legacy Rd markup;
- existing visible-binding/import notes in older functions;
- sandbox/offline environment warnings for D-Bus/bspm and unavailable CRAN index.

There is no R CMD check error and no failing package test on the final tarball.

## Audit limitation

AgentPorter workspace policy currently disables subagent dispatch, so a new second-agent read-only audit could not be run for these final package bytes. The release was therefore closed with direct code review, clean installed-package testing, exact retained-run equivalence tests, vignette rebuilds, evidence hashing, and full `R CMD check` rather than claiming a subagent audit that did not occur.

## Next operational step

Run the first complete real 2026-27 weekF12 OLIS vintage through the installed package:

```r
library(PAGe)

result <- page_v3_forecast(
  "/secure/path/hist_olis.RData",
  season = "2026-27"
)

result$monitoring$A$m0
result$monitoring$A$m1
result$monitoring$B$m1
result$forecasts
```

Review the resulting source hash, release ID, M0 ignition state, M1 peak posterior, B timing route, and A/B +1/+2 forecasts before automating weekly execution.

No commit or push was performed during this package release work.
