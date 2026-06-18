# PAGe: Phase-Aligned Gated Epidemic Forecasting

This repository contains the **PAGe R package** for real-time forecasting of seasonal respiratory virus positivity (1–2 weeks ahead) using surveillance data.

## Quick Links

- **[Package Website](http://10.48.50.117/PAGe/)** — pkgdown documentation and function reference
- **[PAGe Package](PAGe/)** — Main installable R package
- **[Documentation](docs/)** — Pipeline overview, walkthrough, and architecture
- **[Scripts](scripts/)** — Tuning, validation, and analysis scripts
- **[Data](data/)** — Input datasets and production model artifacts

## Overview

PAGe combines three models for robust epidemic forecasting:

1. **M0 (Ignition Detection)**: Identifies season start from surveillance signals
2. **M1 (Alignment)**: Aligns partial observations to a learned reference curve via temporal shifting and optional dilation
3. **M2 (Forecast)**: Binomial GAM with M1 covariates and adaptive bias correction for 1–2 week ahead predictions

Prospective (walk-forward) validation ensures no data leakage. All modeling is retrospectively trained on historical seasons, then deployed weekly in real time.

## Installation

```r
# Install from GitHub
devtools::install_github("lennon-li/PAGe")
library(PAGe)

# Or build locally from the PAGe/ subdirectory
devtools::install("PAGe")
```

## Quick Start

```r
library(PAGe)

# Load and train
flu_hist <- load_flu_hist()
fit_reference_gam(flu_hist)
hyper <- learn_alignment_hyperparams(flu_hist, g_ref_fun)

# Forecast one season (first 20 weeks observed)
currentD <- subset(flu_hist, season == "2018-19" & newWeek <= 20, 
                   select = c("newWeek", "y", "neg"))
res <- align_forecast_pipeline_dilate(currentD, g_ref_fun, hyper)
plot_forecast(res, history = flu_hist)
```

See [PAGe/README.md](PAGe/README.md) for complete installation and usage instructions.

## Documentation

| File | Purpose |
|------|---------|
| `docs/pipeline_overview.qmd` | Full architecture and data flow |
| `docs/pipeline_walkthrough.qmd` | End-to-end training and deployment |
| `docs/source_map.qmd` | File structure and function reference |
| `docs/flu_forecasting.qmd` | Method explanation and theory |

## Repository Structure

```
.
├── PAGe/                  # Installable R package (source of truth)
│   ├── R/                 # Package functions
│   ├── man/               # Roxygen2 documentation
│   ├── inst/extdata/      # Built-in data (flu_hist.csv, ref_curve.RData)
│   └── DESCRIPTION        # Package metadata
├── R/                     # Development mirror of PAGe/R/
├── docs/                  # Quarto documentation and walkthroughs
├── scripts/               # Pipeline entry points and diagnostics
├── data/                  # Input/output (gitignored)
├── test/                  # LOSO validation harness
└── PAGe_Vault/           # Project notes (Obsidian vault)
```

## Key Development Files

- `CLAUDE.md` — Project conventions and guidelines
- `scripts/sync-agent-context.R` — Syncs shared agent instructions to `.ai/`
- `.ai/shared/` — Canonical shared context for Claude agents

## Current Status

- ✅ **M0 (Ignition)**: Complete and tuned (LOSO MAE ~0.5 weeks)
- ✅ **M1 (Alignment)**: Complete and tuned (production spec: k_ref=25, slope_weight=8.0, Weibull-weighted peak MAE = 1.275 weeks)
- ✅ **M2 (Forecast)**: Tuned through v15 (production model at `data/m2_production.rds`, Bernoulli NLL = 0.406)

## Citation

If you use PAGe in research, please cite:
```
Li, L., et al. (2026). PAGe: Phase-Aligned Gated Epidemic Forecasting.
Repository: https://github.com/lennon-li/PAGe
```

## License

MIT License — see `PAGe/LICENSE` for details.
