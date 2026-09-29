# PAGe 0.3.0

- Adds a self-contained canonical v3 weekF12 runtime via `page_v3_models()` and `page_v3_forecast()`, with frozen model artifacts bundled and SHA-256 validated inside the installed package.
- Adds interactive/reproducible expert ignition labeling with `page_label_ignitions()` and the end-to-end `page_train_workflow()` training wrapper.
- Adds validated frozen-kit persistence helpers `page_save_kit()` / `page_load_kit()`.
- Adds training, deployment, and canonical-v3 vignettes.

# PAGe 0.2.0

- Adds independently guarded M0, M1, and M2 lifecycles:
  `validate_season_selection()`, stage tuning validators, `fit_*()`, and
  `freeze_*()`. Downstream stages require frozen, selection-matched upstream
  artifacts with stable identities.
- Extends `assemble_kit()` and `validate_page_kit()` with governed-stage
  provenance and tamper checks while retaining legacy kit compatibility.
- Introduces a coherent public workflow for surveillance-data validation,
  training, holdout replay, promotion, frozen-kit forecasting, and result
  summaries.
- Makes frozen-GAM deployment the default and keeps weekly refitting available
  only as an explicit compatibility option.
- Adds refresh and full-retune training modes with prior-informed adaptive M2
  grids, minimum-NLL, one-standard-error, and Pareto selection, plus optional
  conservative candidate racing.
- Treats 2025-26 as an external holdout by default and requires explicit,
  threshold-based promotion before it may enter the next training cycle.
- Removes private data-path assumptions. Historical surveillance data must be
  supplied explicitly or through `PAGE_FLU_HIST_FILE`.
