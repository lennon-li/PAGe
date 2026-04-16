# PAGe: Phase-Aligned Gated Epidemic Forecasting

**PAGe** is an R package for real-time forecasting of seasonal respiratory virus positivity (1–2 weeks ahead) using surveillance data. It combines three-stage modeling with temporal alignment to reference curves and adaptive bias correction for robust predictions.

## Overview

The PAGe pipeline consists of three models:

- **M0 (Ignition Detection)**: Detects when seasonal activity emerges using gating rules trained on historical data
- **M1 (Alignment)**: Aligns partially observed seasons to a learned reference curve using shift (`tau`) and optional dilation (`delta`), generating template-based predictions
- **M2 (Forecast)**: Binomial GAM with M1 covariates, adaptive Holt EMA bias correction, and online season-specific effects for final 1–2 week ahead forecasts

See [pipeline_overview.qmd](docs/pipeline_overview.qmd) for full architecture details.

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

### 1. Load data and train reference
```r
library(PAGe)

# Load historical flu surveillance data
flu_hist <- load_flu_hist()

# Fit reference curve (sets global reference functions)
fit_reference_gam(flu_hist)
```

### 2. Tune alignment hyperparameters
```r
# Learn M1 alignment hyperparameters via LOSO cross-validation
hyper <- learn_alignment_hyperparams(flu_hist, g_ref_fun)

# Production hyperparameters (pre-tuned):
# k_ref=25, temperature=0.25, slope_weight=8.0, slope_window=6, dynamic_temp=FALSE
```

### 3. Demo: Forecast one season
```r
# Pick a season and take only early weeks (simulating prospective setting)
set.seed(1)
season <- sample(levels(flu_hist$season), 1)
currentD <- subset(flu_hist, season == season & newWeek <= 20, 
                   select = c("newWeek", "y", "neg"))

# Run M0 (ignition detection) → M1 (alignment) → forecast
res <- align_forecast_pipeline_dilate(
  currentD, 
  g_ref_fun = g_ref_fun, 
  hyper = hyper, 
  level = 0.95
)

# Visualize
plot_forecast(res, history = flu_hist)
```

### 4. Real-time deployment
For weekly prospective forecasting (loading pre-trained models):
```r
kit <- load_prospective_kit("data/m2_production.rds")

# Each week, call:
weekly_forecast <- run_prospective_pipeline(
  currentD = flu_hist[flu_hist$season == "2025-26" & flu_hist$weekF <= 5, ],
  kit = kit,
  forecast_weeks = c(1, 2)
)
```

## Key Functions

| Task | Function |
|---|---|
| **Data** | `load_flu_hist()` |
| **M0 (Ignition)** | `run_ignition_weekly()`, `fitIgnition()` |
| **M1 (Alignment)** | `run_alignment_prospective()`, `learn_alignment_hyperparams()` |
| **M2 (Forecast)** | `train_stage2_joint()`, `refit_stage2_weekly()` |
| **Pipeline** | `align_forecast_pipeline_dilate()`, `run_prospective_pipeline()` |
| **Visualization** | `plot_forecast()`, `plot_alignment_evolution()` |

## Documentation

- **[pipeline_overview.qmd](docs/pipeline_overview.qmd)** — Full pipeline architecture and data flow
- **[pipeline_walkthrough.qmd](docs/pipeline_walkthrough.qmd)** — End-to-end training and deployment example
- **[source_map.qmd](docs/source_map.qmd)** — File and function reference

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
