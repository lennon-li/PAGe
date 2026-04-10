# PAGe Vault

This folder is structured as an Obsidian vault for the PAGe project. Open `PAGe_Vault` as a vault in Obsidian.

## Scope

PAGe is a three-stage forecasting pipeline:

1. [[M0-Model]]: prospective ignition detection
2. [[M1-Model]]: epidemic curve alignment and peak tracking
3. [[M2-Model]]: short-horizon positivity forecasting

The implementation path is `M0 -> M1 -> M2`, with M2 consuming alignment outputs from M1.

## Main repo references

- Architecture overview: `docs/pipeline_overview.qmd`
- Package source of truth: `flualign/R/`
- Development mirror: `R/`
- Runtime wrapper: `R/pipeline_runtime.R`

## Notes map

- [[M0-Model]]
- [[M0-Implementation]]
- [[M1-Model]]
- [[M1-Implementation]]
- [[M2-Model]]
- [[M2-Implementation]]
