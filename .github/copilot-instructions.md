# Copilot Instructions: PAGe / flualign

## Project Goal

**PAGe (Phase-Aligned Gated Epidemic Forecasting)** forecasts seasonal respiratory virus % positivity 1–2 weeks ahead using surveillance data. The two deliverables are:
1. A trained, validated forecasting model for 2-week-ahead positivity prediction
2. The **`flualign` R package** — a clean, documented, installable package implementing the pipeline

All design decisions must be justified by forecast accuracy. No data leakage from future seasons — evaluation is always prospective/walk-forward.

## Repository Layout

- `flualign/` — the installable R package (source of truth)
- `R/` — root-level mirror of `flualign/R/` for development convenience. **Keep these in sync** when editing (note: `flagIgnition.R` lives only in `flualign/R/`)
- `docs/` — Quarto (`.qmd`) documentation; `pipeline_overview.qmd` is the authoritative architecture reference
- `scripts/` — pipeline entry points, tuning scripts, diagnostics
- `test/` — standalone LOSO grid-tuning harness (server layout)
- `data/`, `results/` — gitignored input/output directories

## Build & Check Commands

```r
# Inside an R session, from the repo root
devtools::load_all("flualign")         # load package for interactive development
devtools::document("flualign")         # regenerate Roxygen2 docs (RoxygenNote: 7.3.3)
devtools::check("flualign")            # full R CMD check
devtools::install_local("flualign")    # install from source folder
```

```bash
# Pipeline entry points
Rscript scripts/run_loso.R             # leave-one-season-out evaluation
Rscript scripts/run_pipeline.R         # full end-to-end pipeline
Rscript scripts/auto_from_rdata.R --rdata=data/inputs.RData --out=results --mode=all [--verbose]

# Validation scripts (no testthat suite — validation is script-based + LOSO CV)
Rscript scripts/test_one_spec.R        # test a single model specification
Rscript scripts/test_loso_walkforward.R  # walk-forward LOSO validation
```

## Three-Stage Pipeline Architecture

```
M0 (Ignition Detection) → M1 (Alignment) → M2 (Forecast)
                                  ↘ M1→M2 bridge (stacking) ↗
```

Within each week, execution is strictly sequential: M1 runs first to produce alignment outputs, then M2 consumes those outputs to forecast. M2 cannot run before M1 because every covariate it uses is derived from the alignment state M1 just produced.

### M0 — Ignition Detection
**Files:** `ignitionTraining.R`, `flagIgnition.R`, `prospective_running.R`

Detects season "ignition" (onset) using a 4-gate voting system (`cond_sum`, `cond_p`, `cond_prev`, `cond_inc`). Ignition fires when all gates agree simultaneously within an eligible window. Gate thresholds are tuned via LOSO grid search.

- Key functions: `flagIgnition()`, `run_ignition_weekly()`, `detectIgnitionBySeason_M0v2()`, `tuneIgnitionGrid_M0v2()`
- Output: `iWeek` (ignition week), which anchors the alignment
- `flagIgnition()` supports `manual_labels` — a named vector of pre-verified ignition weeks that bypass the algorithm for known seasons

### Reference Curve Estimation
**Files:** `reference.R`, `estimateRef.R`

Before M1 can align, a smooth seasonal template is built from historical data using **known (manually labelled) ignition weeks** — not the prospective detector. `estimateRef()` fits a cyclic GAMM (via `gamm4` with season random intercepts) in aligned `newWeek` space. `learn_alignment_hyperparams()` derives optimizer bounds/penalties (`TAU_BOUNDS`, `DELTA_BOUNDS`, `LAMBDA_DELTA`, `WEEK_THRESHOLD_DELTA`) stored as `hyper`.

The reference curve flexibility `k_ref` is selected by prospective peak MAE across LOSO folds.

### M1 — Curve Alignment
**Files:** `fit.R`, `hyperparams.R`, `loso_alignment.R`, `prospective_alignment.R`

Fits a 4-parameter dilation model against the reference curve on logit scale:
- `tau` — time shift; `delta` — dilation (stretch/compress); `a` — intercept; `b` — amplitude
- Parameters activate progressively: `b` fixed at 1 until sufficient data (`allow_scale`), `delta` fixed at 0 until threshold crossed (`delta_on`)
- Peak estimate: `t_peak = tau + (1+delta) * u*` where `u*` = argmax of reference curve

Three states: `pre_ignition` → `aligning` → `post_peak`. Once peak is passed, alignment freezes.

- Key functions: `run_alignment_prospective()`, `align_forecast_pipeline_dilate()`, `fit_tau_delta()`, `check_scale_identifiability()`
- The same `run_alignment_prospective()` function powers both LOSO evaluation and production deployment

### M1→M2 Bridge (Stacking)
**File:** `m1_m2_bridge.R`

Generates walk-forward M1 predictions as training features for M2. For each evaluation week, runs M1 alignment prospectively and extracts predictions at forecast horizons h=1, h=2.

### M2 — Forecast Model
**Files:** `prospective_training.R`, `module_training.R`, `forecast_post_peak_gam.R`

Joint binomial GAM fitted on stacked leads (h=1 and h=2). Covariates (all derived from M1 outputs):
- **Template backbone** `z(delta, Kr)` — reference curve evaluated in aligned space, linearly ramped in after ignition
- **Global aligned-time smooth** — absorbs residual shift/stretch beyond M1's alignment
- **Season-specific deviation** — per-season shape correction (factor-smooth)
- **EWMA level**, **slope** (`d1`), **curvature** (`d2`) — prospective derivatives (no look-ahead)

Training weights emphasize early post-ignition weeks via exponential decay `exp(-lambda_w * t)`. All hyperparameters (`delta`, `Kr`, `alpha_state`, `lambda_w`) are LOSO-tuned; online, only GAM coefficients update each week.

- Key functions: `stage2_make_spec()`, `prep_stage2_joint()`, `train_stage2_joint()`, `stage2_predict_series()`
- Post-peak handled separately by `forecast_post_peak_gam()`

## Training vs Deployment

| Phase | Steps | Frequency |
|-------|-------|-----------|
| **Offline** | Reference curve + `hyper`, ignition thresholds, LOSO walk-forward → `params_df`, peak detection tuning, M2 hyperparameter tuning, M2 initial fit | Once before season |
| **Online** | M1 alignment → M2 refit → forecast | Weekly during season |

All offline products are frozen objects (`ref`, `hyper`, `params`, `use_ci`, `buffer_weeks`, initial GAM). Online, only GAM coefficients change.

## Core Data Structures

**Input data frame columns** (produced by `alignIgnition()`):
| Column | Meaning |
|---|---|
| `season` | Season label, e.g. `"2024-25"` |
| `week` | MMWR epidemiologic week-of-year |
| `weekF` | Flu-week (starts MMWR week 27) |
| `weekS` | Surveillance-week (starts MMWR week 35) |
| `newWeek` | **Aligned week** — shifted so ignition aligns across seasons |
| `iWeek` | Ignition week for the season |
| `anchorWeek` | Median ignition week (pivot for alignment) |
| `y` | Positive tests |
| `neg` | Negative tests |
| `p` | Observed proportion positive |
| `phase` | `0` = pre-ignition, `1` = post-ignition |

**`align_forecast_pipeline_dilate()` output** (named list):
- `tau`, `delta` — shift and dilation parameters
- `a`, `b` — binomial intercept and slope
- `pred_df` — tibble with `newWeek`, `p_hat`, `p_lo`, `p_hi`, `kind` (`"observed"` / `"forecast"`)
- `peak` — list with `t_peak`, `t_peak_ci`, `p_peak`, `p_peak_ci`
- `fallback_reason` — `NA` if normal, otherwise a string explaining tau-only fallback

## Key Conventions

**Binomial modeling throughout:**
- Link scale is logit (`qlogis`/`plogis`); helper `logit()` clips to `[1e-6, 1-1e-6]`
- Observation weights are binomial sample sizes (`n = y + neg`)

**Function naming:**
- `estimate*` — fits/estimates (e.g., `estimateRef()`)
- `fit*` / `fitIgnition()` — optimization-based fitting
- `flag*` / `detect*` — detection/classification (e.g., `flagPeak()`, `detectIgnitionBySeason_M0v2()`)
- `align*` — alignment operations
- `forecast*` / `stage2_predict*` — prediction functions
- `tune*` / `learn*` — hyperparameter search
- `plot*` / `plotRes()` — visualization

**Parallelism:**
- Always use `future::plan(multisession)` (Windows-safe). Never use `mclapply` or `fork`-based parallelism.

**Global reference state:**
- After calling `fit_reference_gam()`, the reference curve is available globally via `g_ref_fun()`, `g_ref_safe()`, `g_ref_mu_se()` through `.flualign_ref_env`.
- Do not pass raw GAM objects around — use these accessors.

**Optimization fallbacks:**
- When `delta` optimization fails or there is insufficient data, fall back to tau-only alignment. Record reason in `fallback_reason`.
- Use `try(…, silent = TRUE)` for numerical routines; return `1e9` NLL on failure.

**Data files** (gitignored):
- `data/` — input CSVs and RData objects
- `results/` — output from tuning/analysis runs
- `*.RData`, `*.rds` — all ignored at root level

**Quarto docs (`docs/*.qmd`):**
- Do not use h1 (`#`) headings in `.qmd` files — the `title:` field in the YAML front matter renders as h1. Start body content with h2 (`##`).
- `pipeline_overview.qmd` is the authoritative architecture reference; other docs cover individual pipeline stages.

Built-in historical data is in `flualign/inst/extdata/flu_hist.csv` and `flualign/ref_curve.RData`.
