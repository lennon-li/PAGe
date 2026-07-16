# PAGe: Phase-Aligned Gated Epidemic Forecasting

**PAGe** is an R package for real-time forecasting of seasonal respiratory virus positivity (1–2 weeks ahead) using surveillance data. It combines three-stage modeling with temporal alignment to reference curves and adaptive bias correction for robust predictions.

## Overview

The PAGe pipeline consists of three models:

- **M0 (Ignition Detection)**: Detects when seasonal activity emerges using gating rules trained on historical data
- **M1 (Alignment)**: Aligns partially observed seasons to a learned reference curve using shift (`tau`) and optional dilation (`delta`), generating template-based predictions
- **M2 (Forecast)**: Binomial GAM with M1 covariates, adaptive Holt EMA bias correction, and online season-specific effects for final 1–2 week ahead forecasts

See the [pipeline overview](https://lennon-li.github.io/PAGe/articles/pipeline-overview.html)
for full architecture details.

## Installation

### From GitHub (recommended)
```r
# Install devtools if needed
if (!require("devtools")) install.packages("devtools")

devtools::install_github("lennon-li/PAGe")
library(PAGe)
```

### From source
```r
# Build from the PAGe/ directory
devtools::install("PAGe")
library(PAGe)
```

## Quick Start

The high-level API is organised around **build**, **tune**, **train**,
**assemble**, and **run**. See `vignette("intro", package = "PAGe")`
for a runnable walkthrough.

### 1. Train a kit from historical data
```r
library(PAGe)

# Historical surveillance data shipped with the package.
allD <- load_flu_hist()

# Train the three-stage kit.
m0  <- build_m0(allD)
m1  <- build_m1(allD, m0)
m2  <- train_m2(allD, m0, m1, best_spec = NULL)
kit <- assemble_kit(m0, m1, m2)

# Forecast the current season and plot.
current <- getCurrentD(season = "2025-26")
res <- run_pipeline(kit, current)
plot_forecast(res, history = allD)
```

### 2. Retune hyperparameters (optional)
```r
# Grid search ignition thresholds (M0) and alignment hyperparameters (M1).
m0_tune <- tune_m0(allD)
m1_tune <- tune_m1(allD, m0, m1)

# Production M1 hyperparameters (already baked into build_m1):
# k_ref = 25, temperature = 0.25, slope_weight = 8.0,
# slope_window = 6, dynamic_temp = FALSE
```

### 3. Weekly prospective forecast
```r
# A pre-built kit can be saved to disk and reloaded in production:
saveRDS(kit, "m2_production.rds")
kit <- readRDS("m2_production.rds")

# Each week, produce a 1–2 week ahead forecast:
current <- getCurrentD(season = "2025-26")
res <- run_pipeline(kit, current)
plot_forecast(res, history = allD)
```

## Key Functions

| Task | Function |
|---|---|
| **Data** | `load_flu_hist()`, `getCurrentD()` |
| **Build** | `build_m0()`, `build_m1()`, `build_m2()` |
| **Tune** | `tune_m0()`, `tune_m1()` |
| **Train** | `train_m2()`, `train_stage2_joint()` |
| **Assemble** | `assemble_kit()` |
| **Run** | `run_m0()`, `run_m1()`, `run_m2()`, `run_pipeline()` |
| **Visualisation** | `plot_forecast()`, `plot_alignment_evolution()`, `plotRes()` |

## Documentation

- **[Pipeline overview](https://lennon-li.github.io/PAGe/articles/pipeline-overview.html)** — Full pipeline architecture and data flow
- **[Pipeline walkthrough](https://lennon-li.github.io/PAGe/articles/pipeline-walkthrough.html)** — End-to-end training and deployment example
- **[Source map](https://lennon-li.github.io/PAGe/articles/source-map.html)** — File and function reference

## Development

Built with:
- `mgcv` — GAM fitting and reference curve learning
- `tibble` + `dplyr` + `tidyr` — Tidy data pipelines
- `ggplot2` + `plotly` — Visualization
- `nloptr` — Profile likelihood optimization for alignment parameters

## Citation

If you use PAGe in research, please cite:
```
Li, L., et al. (2026). PAGe: Phase-Aligned Gated Epidemic Forecasting.
```
