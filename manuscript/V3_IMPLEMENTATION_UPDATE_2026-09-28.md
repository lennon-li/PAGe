# PAGe v3 manuscript implementation update

Date: 2026-09-28  
Scope: current manuscript-facing evidence and implementation status  
Status: audited shadow release; manuscript update; no promotion

## Canonical release and model decisions

The canonical forecast release is
`5472d08992b5a9da40a9419b75c7427847ff7b1999070041d5e38b0a71da853b`, with
minimum issued origin weekF12 and `production_eligible=FALSE`. The release
identity and component stack are documented in
[`v3-current-canonical-stack-2026-09-28.md`](../docs/v3-current-canonical-stack-2026-09-28.md).
The minimum forecast origin is an operational floor; it is separate from
ignition and timing semantics. The prior experimental weekF3 support policy is
superseded. WeekF12 evidence is support-only, not a promotion or accuracy
claim; see [`v3-week12-lower-bound-migration-2026-09-28.md`](../docs/v3-week12-lower-bound-migration-2026-09-28.md).

- **M0-A:** frozen `m0-v2-wmin12-raw3-se1-decimal-loso-v1`, `w_min=12`,
  raw-3 with one-SE drop tolerance. The small weekF10-to-11 decline remains
  stable. Direct evaluation at predicted positivity near 1.677% would ignite
  M0 at weekF12; this is counterfactual diagnostic evidence, not an observed
  result.
- **M1-A:** frozen M1-v2 timing stage.
- **M2-A:** exact A1 state-only at +1/+2. Governed posterior-C2 gain at +2
  was about 4.04%, below the 5% promotion threshold.
- **B policy:** B activity/timing window 12–40. The 2018–19 season is an
  explicit no-event timing season; 2019–20 is excluded from B timing training
  and scoring. Historical detector behavior is preserved relative to the
  prior 8–40 archive.
- **M1-B v10:** B-specific continuous peak-location posterior; fitted library
  behavior preserves v9. Chronological season-balanced MAE was about 1.6573
  weeks, early-weighted MAE 1.6580 weeks, and mean 90% coverage 0.80. The
  2022–23 season remains weak.
- **M2-B v5:** +1 exact B1; +2 posterior-C2 only when causal timing is
  available, otherwise exact B1 fallback. Governed historical season-balanced
  MAE was 0.514552 pp (B1) and 0.436010 pp (posterior-C2), a descriptive
  15.26% difference; timing-active improvement was 24.91%; worst-season MAE
  changed from 1.172716 to 0.763391 pp. The required lower-bound saturation
  caveat is in
  [`v3-m2-b-final-disposition-2026-09-26.md`](../docs/v3-m2-b-final-disposition-2026-09-26.md):
  interpret this as continuous phase/post-peak correction, not fine-grained
  calibrated peak timing.

## WeekF12 support replay and live-season status

WeekF12 support-only replay MAE was A+1 0.246866 pp (8 seasons), A+2 0.327263
pp (8), B+1 0.154921 pp (7), and B+2 state/fallback 0.154897 pp (7). There
were zero B timing activations at weekF12. These are support checks only.

The 2026–27 weekF8–11 report is diagnostic and pre-issuance. Authoritative
current score-to-date values from the CSV are A+1 0.4121391 pp (n=3), A+2
0.6495239 pp (n=2), B+1 0.02855612 pp (n=3), and B+2 0.04773192 pp (n=2).
They replace stale A+2/B+2 prose in an older end-to-end audit. No observed
weekF12+ result is available at this update. The first eligible shadow run
must retain its as-issued source and panel provenance and be scored only after
its targets are observed.

## Bounded legacy/v2 comparisons

These stage-specific descriptive comparisons use their stated ledgers and do
not support a global v1/v2/v3 ordering.

| Component comparison | Legacy | v2 | Evidence and caveat |
|---|---:|---:|---|
| M1 timing MAE | ~1.375 weeks | ~1.093 weeks | 81 matched rows, 10 seasons, common ledger; M1 timing only |
| M2-A +1 MAE | 8.4087 pp | 1.7757 pp state/growth; 1.5435 pp fixed C2 | 10 matched seasons and identical target counts; training vintages differ |
| M2-A +2 MAE | 9.2056 pp | 2.4124 pp state/growth; 2.1531 pp fixed C2 | Same matched-target and vintage caveat |
| M0 performance | Not established | Not established | No verified common-ledger legacy/v2 metric |

The M1 ledger is
[`common_ledger_vs_legacy_v16_strict_future_release.csv`](../artifacts/m1-v2-lowrank-posterior-v10-release-consistent/common_ledger_vs_legacy_v16_strict_future_release.csv).
The M2-A evidence is recorded in
[`m2-v2-legacy-matched-a-benchmark-2026-09-25.md`](../docs/m2-v2-legacy-matched-a-benchmark-2026-09-25.md).
v3 does not replace M0-A, M1-A, or M2-A. Its incremental evidence is mainly
B-specific timing/routing and governed weekF12 operation. No three-way A table
or global version ranking is appropriate.

## Package and API status

The R package is the primary user-facing product and reproducibility surface.
Package-native workflow is implemented in `PAGe/R/training_workflow.R` and
`PAGe/R/v3_runtime.R`, with frozen artifacts in
`PAGe/inst/models/v3-week12/` and vignettes in `PAGe/vignettes/`.
`page_label_ignitions()` plots seasons and collects expert decimal ignition
labels; `page_train_workflow()` delegates to governed `train_pipeline()` and
does not supply hidden default labels; `page_save_kit()` and `page_load_kit()`
save and restore a kit; `page_v3_forecast()` runs the bundled canonical
artifacts.

Source-tree and clean installed-package v3 tests are 52/52 green and training-workflow tests are 16/16 green. The exact tarball installs into an isolated library and exposes all six new public functions. Package-native weekF12 equivalence to the audited v4 transaction
has maximum forecast absolute difference 4.44e-15 percentage points, exact
route/state equivalence, and identical OLIS versus typed-panel results.
These establish both source-tree and clean installed-package integration/equivalence. The exact built tarball installs successfully, all six new exports are present, and the installed package passes the same 52/52 v3 runtime plus 16/16 training-workflow assertions. The three new vignettes render successfully. A terminal full `R CMD check` summary remains incomplete in this sandbox because long check calls are interrupted after install/load/namespace/static stages; no package error is present in the partial terminal log.

API v4 is an operational monitoring layer for supplement/implementation
detail, not the primary user product. Its core suite was 94/94, HTTP 43/43,
and monitoring 34/34. Independent monitoring semantics audit: APPROVE;
deployment evidence: APPROVE WITH CAVEATS (external-host only); installer
audit: APPROVE. The API remains shadow-only and does not authorize production
serving.

## Manuscript actions and open evidence

The controlling revisions are in [`PLAN.md`](PLAN.md),
[`SKELETON.md`](SKELETON.md), [`METHODS.md`](METHODS.md),
[`RESULTS.md`](RESULTS.md), and [`TODO.md`](TODO.md). Historical prior-cycle
Results remain separate and unchanged. The remaining manuscript gates are:

1. Obtain a terminal full `R CMD check` summary in a stable environment and preserve it.
2. Preserve the already-rendered vignette outputs with the final package evidence.
3. Reconcile all manuscript tables and text to machine-readable current artifacts.
4. Capture the first observed weekF12+ run and later score its forecasts when target observations are available.
5. Complete data-custodian publication authorization and the applicable research-ethics/REB determination before submission.

No commit or push was made as part of this manuscript update.
