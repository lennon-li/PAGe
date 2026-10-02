# PAGe v3 R-package runtime and training workflow audit

Date: 2026-09-29  
Status: **APPROVE WITH CAVEATS for R-package shadow runtime and training use**.

## Scope

This audit covers the package-native PAGe v3 weekF12 runtime, interactive ignition-label training workflow, frozen-kit persistence, user vignettes, and version-comparison evidence. It does not change the canonical statistical release or promote v3 out of shadow status.

Canonical source release:

`5472d08992b5a9da40a9419b75c7427847ff7b1999070041d5e38b0a71da853b`

Canonical source artifacts remain unchanged outside the package.

## Package-native runtime

Primary interface:

```r
library(PAGe)
result <- page_v3_forecast("hist_olis.RData", season = "2026-27")
```

The installed package requires no repository `source()` calls, external model directory, shell installer, systemd unit, or API service for forecasting.

`page_v3_forecast()` supports:

- typed A/B weekly panels;
- OLIS `.RData` snapshots containing `r$fluA` and `r$fluB`;
- supported ORVT CSV input;
- weekF12 issuance floor;
- M0-A ignition monitoring;
- M1-A peak posterior/interval/passage probabilities;
- M1-B/B activity and timing state;
- A/B +1/+2 forecasts under the frozen v3 routing policy;
- source, package-runtime, model, and input provenance.

The runtime remains `shadow_only` and `production_eligible = FALSE`.

## Runtime-only model projection and privacy

The initial package prototype copied the canonical M2 RDS files byte-for-byte. Distribution review found that fitted M2 objects retained historical `y_target`/`N_target` training frames. That conflicted with PAGe's package policy that surveillance observations are not bundled.

The package therefore ships deterministic runtime-only M2 projections built by:

`scripts/build_v3_package_runtime_bundle.R`

M2-A runtime contains only the frozen A state-model coefficients, training-universe/contract metadata, canonical source artifact ID/SHA-256, and runtime projection identity. Canonical v3 A does not use C2, so historical A shape templates are unnecessary for inference and are omitted.

M2-B runtime contains the frozen B state coefficients, causal activity-detector parameters/hashes, M1-B identity, runtime routing contract, and the learned normalized A/B shape template required for posterior-C2. It omits fitted model training frames, historical target counts, historical-evidence tables, and repository paths.

The package manifest distinguishes:

- canonical `source_sha256` / source artifact ID;
- packaged `runtime_sha256`;
- deterministic `runtime_projection_id` for projected M2 objects.

A recursive distribution check found no `y_target` or `N_target` fields in any packaged v3 RDS. Total packaged model RDS size after projection is 39,773 bytes.

## Numerical equivalence

Installed-package tests compare the package runtime against retained API-v4/canonical-runner fixtures:

- weekF12 A-ignition case;
- weekF12 A-no-ignition case;
- typed-panel versus OLIS identity;
- active B posterior-C2 case;
- pre-weekF12 not-issued behavior;
- tampered-model fail-closed behavior;
- invalid count/positivity fail-closed behavior.

After M2 runtime projection, all runtime/equivalence/privacy tests pass: **62/62**.

## Interactive training workflow

New package functions:

- `page_label_ignitions()`
- `page_train_workflow()`
- `page_save_kit()`
- `page_load_kit()`

The workflow reuses PAGe's existing expert review and `train_pipeline()` implementation. It does not introduce a second statistical trainer.

Interactive usage plots each requested season using the existing expert ignition review and prompts for a decimal ignition week. Reproducible non-interactive use accepts a uniquely named numeric vector.

The decimal expert annotation is retained for provenance. The current M0/M1 training interface is integer-week based, so the workflow explicitly maps the decimal annotation to `floor(ignition_week_decimal)`.

No peak label or forecast truth is fabricated from the ignition annotation.

### Holdout governance

`page_train_workflow()` determines the trainable season set before ignition review.

- `prospective_holdout` and explicitly excluded seasons are not shown by automatic interactive labeling;
- they are not required to have ignition labels;
- if a pre-existing label set contains those seasons, the annotations remain in the returned provenance object but are stripped before `train_pipeline()` is called.

Installed-package training workflow tests pass: **25/25**.

## Vignettes

Four package vignettes build successfully from a clean installed package:

- `train-your-own-page`
- `deploy-and-forecast`
- `canonical-v3-week12`
- `model-version-comparison`

The training vignette explicitly recommends keeping an unreleased prospective holdout out of expert ignition review as well as fitting/tuning.

## Version-comparison evidence

`page_version_metrics()` exposes a packaged comparison table. Missing cells are intentional when a version was not independently scored on the exact same ledger.

### M1-A timing: legacy/v1 versus v2

Strict common ledger: 81 matched origin/truth rows across 10 seasons.

- legacy/v1 MAE: 1.37518518518519 weeks;
- v2 MAE: 1.09254122023805 weeks;
- relative MAE reduction: 20.5531566215263%.

Canonical v3 preserves the M1-A lineage, but the exact ledger is not treated as an independent v3 re-score. The v3 metric cell is therefore `NA`.

### M2-A forecasting: legacy/v1 versus v2

Matched historical target-vintage benchmark across 10 seasons:

- +1: legacy 8.40864843434364 pp versus v2 1.77571970120372 pp; 78.8822220946816% relative reduction; 294 rows;
- +2: legacy 9.20560936375536 pp versus v2 2.41243617024516 pp; 73.7938459593616% relative reduction; 284 rows.

Caveat: target rows/counts are matched, but historical training snapshots are not perfectly vintage-matched. Canonical v3 preserves the governed A1 route but is not assigned a copied v3 metric on this ledger.

### M2-B +2: v2 versus v3

Seven-season chronological benchmark:

- v2 exact B1 MAE: 0.514551588220607 pp;
- v3 posterior-C2 MAE: 0.436010448358419 pp;
- relative MAE reduction: 15.2639971696123%.

Timing-active subset: 89 rows across five seasons.

- v2 B1: 0.735687951168474 pp;
- v3 posterior-C2: 0.552438905138133 pp;
- relative reduction: 24.9085289135551%;
- 5/5 timing-active seasons improved.

No universal pooled v1/v2/v3 score is claimed. There is no verified common-ledger M0 performance comparison, and the historical v1 M2 benchmark is A-only.

## Test and build evidence

Final clean installed-package targeted acceptance after runtime projection:

- package v3 runtime/equivalence/privacy: **62/62**;
- training/holdout workflow: **25/25**;
- version-comparison evidence: **13/13**;
- total targeted: **100/100**.

Four legacy tests that previously sourced repository-relative R files were changed to bind the same unexported functions from the installed PAGe namespace. Their clean-installed-package results are:

- M0 persistence: **24/24**;
- governed C2: **12/12**;
- research C2: **63/63**;
- pipeline shadow: **15/15**.

`R CMD build PAGe` succeeds and builds the package vignettes.

The authoritative final `R CMD check --no-manual` on the sanitized runtime bundle completed with **exit 0**. The full test suite reported **5,687 PASS / 0 FAIL / 97 WARN / 5 SKIP**. Package check status is **1 WARNING, 2 NOTEs**. The check warning and notes are pre-existing package-wide Rd argument-documentation and static-analysis/global-binding debt; the warning output does not identify the new runtime/training/comparison functions.

Final built tarball: `PAGe_0.3.0.tar.gz`

- tarball SHA-256: `be94392b055b37df34f56941b4a45910310432eea7bf847340bee55b0b19a18d`;
- v3 runtime manifest SHA-256: `c03e7eb18032d126f368f73b0908f123b112596caaefd72d95e1bea1e068b6ec`.

## Audit limitations

AgentPorter exposes independent review agents, but the `repos` workspace currently prohibits agent dispatch. Therefore no independent subagent audit is claimed for this package-native change set. Acceptance is based on canonical-fixture equivalence, clean-installed-package tests, distribution/privacy inspection, vignette builds, package build/check, and manual code review.

No commit or push was performed.

## Final disposition

**APPROVE WITH CAVEATS** for R-package shadow operation, training workflow use, and continued 2026-27 prospective evaluation. The package-native runtime reproduces the retained audited canonical fixtures, the M2 distributable objects no longer carry raw historical target-count frames, holdout labels are excluded from training, the version-comparison table avoids unsupported cross-version scores, all targeted installed-package tests pass, all vignettes build, and the full package check completes without ERROR.

Caveats: v3 remains shadow-only; real weekF12+ prospective performance still has to be observed and scored; package-wide legacy Rd/static-analysis debt remains; AgentPorter workspace policy currently prohibits independent subagent dispatch, so no new second-agent package audit is claimed.
