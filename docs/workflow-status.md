# PAGe workflow status map

Last reconciled: 2026-10-02.

This document describes the current canonical source layout and supported user-facing workflow after repository consolidation and public-API cleanup. Historical implementation names and archived research remain available for reproducibility, but they are not part of the supported external package contract.

## Canonical repository and branches

The canonical repository is `/home/yeli/repos/PAGe`.

The active branch topology is:

```text
                         dev/n-history
                        /
master ----------------+
                        \
                         dev/survival-peak
```

- `master` — current supported PAGe R package and operational pipeline.
- `dev/n-history` — test-volume / N-history predictor research.
- `dev/survival-peak` — survival/hazard peak-timing research.

The parallel `PAGe-m1-v2` and `PAGe-m2-a-full` workspaces are no longer canonical source repositories.

## Current production pipeline

The supported production chain is:

```text
official surveillance input / canonical panel
    ↓
M0 ignition
    ↓
M1 timing / peak inference
    ↓
M2 one- and two-week forecasts
    ↓
stratified aggregation when requested
    ↓
immutable release / provenance
    ↓
weekly API and walk-forward report
```

The frozen implementation still carries internal development-generation identifiers where required for artifact identity and reproducibility. Those identifiers are intentionally not exposed in public function names.

## Supported public R API

The package exports a compact stable interface. The complete reference is [`public-api.qmd`](public-api.qmd).

### Data and surveillance

- `page_load_surveillance()`
- `prepare_surveillance_data()`
- `validate_surveillance_data()`
- `validate_season_selection()`
- `page_season_calendar()`

### Forecasting and reporting

- `page_forecast()`
- `page_forecast_now()`
- `page_walkforward_report()`
- `page_models()`
- `plot_forecast()`

### Training and kit lifecycle

- `page_train()`
- `page_save_kit()`
- `page_load_kit()`
- `page_validate_kit()`
- `page_label_ignitions()`
- `season_selection()`

### Stratified aggregation

- `aggregate_strata()`
- `aggregate_strata_draws()`
- `shared_denominator_correlation()`

### Advanced component-level scientific API

- `m0_fit()` / `m0_detect()`
- `m1_fit()` / `m1_predict()`
- `m1_peak_posterior()` / `m1_passage_posterior()`
- `m2_fit()` / `m2_predict()`

### Evaluation and governance

- `evaluate_forecasts()`
- `replay_holdout()`
- `check_promotion()`
- `verify_promotion()`

## Internal implementation interfaces

Low-level tuning, validation, freezing, fold-running, cache, artifact-construction, and historical versioned functions are intentionally internal. Examples include the historical `tune_*`, `freeze_*`, `build_*`, and development-generation runtime functions.

Repository-owned reproduction scripts may use `PAGe:::` to reach those internals when exact historical replay requires it. That does not make those helpers part of the supported external API.

The developer-oriented [`stage-api-map.md`](stage-api-map.md) and [`tuning-playbook.md`](tuning-playbook.md) document those internals.

## Operational source and reproducibility

Current operational tooling includes:

- strict ORVT/source preflight under `2026/`;
- reproducible weekly transaction scripts under `scripts/`;
- API v4 deployment and monitoring tooling;
- corrected `page-weekly-api-v4.service` systemd dependencies;
- source, panel, release, and transaction hashing;
- the R-generated walk-forward report.

The HTML report is a generated artifact. The source of truth is the R package renderer and bundled report template; report HTML should not be hand-maintained.

## Stratified aggregation contract

PAGe supports aggregation across pathogen types, age groups, regions, sites, or other strata.

- Independent strata: analytic variance propagation with zero off-diagonal covariance.
- Shared-denominator mutually exclusive categories: multinomial correlation structure.
- Correlated strata: user-supplied correlation or covariance matrices.
- Joint posterior/simulation draws: preferred when available because dependence and asymmetry are propagated directly.
- Weighted denominator partitions such as age groups: normalized weighted means.

The current Flu A+B walk-forward report sums the separately issued A and B component forecasts and displays a model-mean confidence interval generated through the generic aggregation API. Its current dependence label is `independent_model_mean`; this is distinct from a shared-denominator sampling/predictive interval.

## Research branches

### `dev/n-history`

Contains test-volume / N-history research, including lagged-volume features, EXP-family summaries, acceleration/relative-volume candidates, selection experiments, and related shadow evaluations. Production `master` must not depend on these research features unless they pass a future governed promotion cycle.

### `dev/survival-peak`

Contains survival/hazard peak-timing research, synthetic validation, nested evaluation, and related M1 alternatives. Production `master` continues to use the currently frozen timing implementation until a future governed replacement is accepted.

## Manuscript workspace

All manuscript-specific protocols, drafts, literature review, publication analyses, result tables, and manuscript-only execution scripts live under `manuscript/`.

Production package code remains under `PAGe/`; operational code remains under `2026/` and `scripts/`; manuscript-specific runners live under `manuscript/scripts/`.

The manuscript may call the supported public PAGe API. Historical publication reproductions may use internal functions when exact frozen-analysis reproduction requires them, but those internal calls are not external API commitments.

## Historical and archived workflows

Legacy seasonal runners, superseded training scripts, old fresh-run workflows, and historical model-generation code are retained under `archive/` or dated historical documentation for provenance. They should not be treated as current package or deployment instructions.

Immutable artifact names, schema identifiers, release IDs, and archived filenames may continue to contain `v1`, `v2`, `v3`, or other historical version labels. Those identifiers are part of provenance and should not be renamed merely to match the public API.

## Current validation baseline

Repository consolidation established the current master against package build, focused runtime/report/aggregation tests, Week-12 forecast identity checks, and ORVT/API readiness checks. Subsequent public-API cleanup must preserve those numerical and operational identities; API renaming alone is not authorization to alter frozen forecast behavior.
