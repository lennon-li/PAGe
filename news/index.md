# Changelog

## PAGe 0.2.0

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
