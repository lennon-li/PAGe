# Changelog

## PAGe 0.2.0

- Adds independently guarded M0, M1, and M2 lifecycles:
  [`validate_season_selection()`](https://lennon-li.github.io/PAGe/reference/validate_season_selection.md),
  stage tuning validators, `fit_*()`, and `freeze_*()`. Downstream
  stages require frozen, selection-matched upstream artifacts with
  stable identities.
- Extends
  [`assemble_kit()`](https://lennon-li.github.io/PAGe/reference/assemble_kit.md)
  and
  [`validate_page_kit()`](https://lennon-li.github.io/PAGe/reference/validate_page_kit.md)
  with governed-stage provenance and tamper checks while retaining
  legacy kit compatibility.
- Introduces a coherent public workflow for surveillance-data
  validation, training, holdout replay, promotion, frozen-kit
  forecasting, and result summaries.
- Makes frozen-GAM deployment the default and keeps weekly refitting
  available only as an explicit compatibility option.
- Adds refresh and full-retune training modes with prior-informed
  adaptive M2 grids, minimum-NLL, one-standard-error, and Pareto
  selection, plus optional conservative candidate racing.
- Treats 2025-26 as an external holdout by default and requires
  explicit, threshold-based promotion before it may enter the next
  training cycle.
- Removes private data-path assumptions. Historical surveillance data
  must be supplied explicitly or through `PAGE_FLU_HIST_FILE`.
