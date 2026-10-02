# M2-A causal test-volume trend shadow audit — 2026-09-29

## Disposition

**IMPLEMENTED; RETAIN SHADOW-ONLY; DO NOT PROMOTE TO CANONICAL v3.**

The behavioral-feedback hypothesis is plausible and receives meaningful historical support, but the governed audit is mixed. The tuned test-volume trend materially improves LOSO binomial NLL and modestly improves LOSO MAE, yet expanding-history chronological MAE worsens, particularly at +1 week. Only one season is available under the modern type-specific ORVT denominator regime.

Canonical v3 A1 remains unchanged.

## Implementation

Package module:

`PAGe/R/m2_ntrend_shadow.R`

Public API:

- `fit_m2_a_ntrend_shadow()`
- `predict_m2_a_ntrend_shadow()`

Reproducible benchmark:

`scripts/evaluate_m2_a_ntrend_shadow_v1.R`

Evidence directory:

`artifacts/m2-a-ntrend-shadow-v1/`

The causal feature for lookback `w > 0` is:

`(log(N_t) - log(N_{t-w})) / w`

The tuning grid is `w = 0,1,2,3,4`. Window zero is the explicit OFF/null candidate and contains no test-volume term. Tuning uses LOSO mean binomial NLL. If OFF is within `off_tolerance` of the best score, OFF is selected preferentially.

The candidate model retains the A1 state structure:

`cbind(y_target, N_target-y_target) ~ horizon_f + growth1 + growth2 + ntrend + offset(logit_current)`

with `ntrend` omitted exactly when `w=0`.

Runtime prediction truncates observations at the requested origin before feature construction, so future observations cannot affect the result.

## Historical data

Evaluation uses the A weekly panel underlying the governed M2-v2 work:

`artifacts/m2-v2-flu-ab-geometry-v1/flu_ab_weekly_v1.csv`

The audit covers 11 historical seasons in LOSO evaluation. Denominator regimes are imbalanced: most historical rows use the shared influenza-test proxy, while only 2025-26 is fully represented by the modern type-specific ORVT denominator in this panel.

## LOSO tuning result

The tuner selected **2 weeks**.

| Window | Mean binomial NLL | MAE (pp) |
|---:|---:|---:|
| 0 / OFF | 26.91649 | 1.73932 |
| 1 | 24.42010 | 1.68875 |
| **2** | **23.95647** | **1.65486** |
| 3 | 25.52021 | 1.74342 |
| 4 | 25.55839 | 1.73716 |

Selected window 2 versus OFF:

- LOSO MAE relative gain: **4.856%**
- LOSO mean-NLL relative gain: **11.0% approximately**
- +1 MAE: **1.40722 -> 1.34876 pp**
- +2 MAE: **2.08012 -> 1.96897 pp**

The MAE gain is encouraging but falls narrowly below the frozen 5% promotion-style threshold used by the audit.

## Coefficient stability

For window 2, the N-trend coefficient is negative in **11/11** held-out-season fits.

Approximate coefficient range:

- minimum: **-1.2484**
- maximum: **-0.9852**
- mean: **-1.1442**

This is consistent with the proposed surveillance-feedback interpretation: conditional on current positivity and positivity growth, unusually rapid denominator expansion predicts lower future positivity than the A1 trajectory alone would extrapolate.

The coefficient is predictive/associational; it is not interpreted causally as testing reducing infection.

## Season dispersion

Window 2 improves mean LOSO MAE in 7 of 11 seasons and worsens it in 4 of 11.

Large improvements occur in several early seasons and in 2025-26. Modest degradations occur in 2017-18, 2018-19, 2019-20, and 2024-25. The result therefore is not driven by a single season, but it is also not uniformly beneficial.

## Denominator-regime check

Historical shared-denominator proxy:

- OFF MAE: **1.74979 pp**
- window-2 MAE: **1.67477 pp**

Modern ORVT type-specific denominator (2025-26 only):

- OFF MAE: **1.63699 pp**
- window-2 MAE: **1.46029 pp**

The modern result is encouraging, but one modern season is insufficient for promotion evidence.

## Expanding-history chronological audit

This is the main reason for non-promotion.

Across 8 test seasons with at least three strictly prior training seasons:

| Window | Mean binomial NLL | MAE (pp) |
|---:|---:|---:|
| 0 / OFF | 28.87372 | **1.39579** |
| 1 | 27.72364 | 1.45656 |
| **2** | **27.02489** | 1.45277 |
| 3 | 27.35694 | 1.41355 |
| 4 | 27.14245 | 1.43685 |

For selected window 2 versus OFF:

- chronological NLL relative gain: **+6.40%**
- chronological MAE relative gain: **-4.08%** (worse)
- +1 MAE: **0.96268 -> 1.07326 pp** (materially worse)
- +2 MAE: **1.84025 -> 1.84223 pp** (essentially flat/slightly worse)

This pattern suggests that test-volume trend improves probabilistic calibration/count likelihood while not yet improving the point-forecast MAE objective consistently through time. It may also indicate surveillance-regime/nonstationarity effects.

## Formal promotion gate

The integrated audit gate returns `promotion_eligible = FALSE`.

| Check | Result |
|---|---|
| selected nonzero window | PASS |
| LOSO MAE gain >= 5% | **FAIL** |
| chronological NLL improves | PASS |
| chronological MAE non-worse | **FAIL** |
| chronological +1 degradation <= 2% | **FAIL** |
| coefficient sign stable | PASS |
| modern regime non-worse | PASS |
| at least 2 modern denominator seasons | **FAIL** |

No automatic or manual canonical promotion is justified by this evidence.

## Recommended next use

Keep window 2 as a **shadow diagnostic** for 2026-27. Record its +1/+2 forecasts alongside exact A1, but do not route canonical outputs through it.

The most informative future evidence is prospective modern-denominator data. After at least one additional complete modern season, rerun the same fixed grid and promotion gate without changing thresholds based on the observed outcome.

A second research branch may test phase-conditioned use of the same feature (for example post-ignition ascent only), but that should be a new candidate and must retain an explicit OFF state. Do not expand the present candidate with interactions until the simple window-2 effect has prospective support.

## Final package validation

Final N-trend installed-package tests: **14/14 assertions passed**.

Canonical v3 runtime regression suite after adding the shadow module: **62/62 assertions passed**. No canonical v3 forecast route, frozen model bundle, or runtime output was changed by this work.

Final source package build:

`PAGe_0.3.0.tar.gz`

SHA-256:

`e67b5360fc8eedbf2d1ded0af245d98b5c0417e2b962f70e8c877799e28e8578`

`R CMD check --no-manual PAGe_0.3.0.tar.gz` completed with exit code **0** and the full package test suite reported `Running 'testthat.R' ... OK`.

Final status remains **1 WARNING, 2 NOTEs**, attributable to the same pre-existing package Rd/static-analysis and offline-environment issues documented in the v3 package release audit. The new N-trend functions did not introduce an additional check failure.

## Independent-audit limitation

AgentPorter exposes independent reviewer agents, but the `repos` workspace currently prohibits agent dispatch. A second-agent audit could therefore not be executed. This disposition is based on direct code review, causal/future-invariance tests, explicit OFF-selection tests, clean installed-package tests, canonical-v3 regression equivalence, reproducible LOSO/chronological evidence, source/evidence hashing, and full `R CMD check`. No independent-agent approval is claimed.
