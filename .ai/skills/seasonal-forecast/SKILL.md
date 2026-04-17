# Seasonal Forecast Training & Evaluation Skill

Use this skill when training, tuning, evaluating, or deploying the PAGe seasonal respiratory virus forecasting pipeline. Covers the full M0 → M1 → M2 → prospective deployment chain.

---

## Pipeline Overview

```
Raw data (flu_testing_data.csv)
  ↓ M0: Ignition Detection  →  iWeek_hat (season start week)
  ↓ M1: Alignment           →  template fit (tau, delta), logit_spread
  ↓ M2: Forecast GAM        →  p_hat (1–2 week ahead positivity)
  ↓ Prospective             →  weekly walk-forward + Holt EMA bias correction
```

Each stage is sequential within a week. M1 must run before M2 (M2 consumes M1 alignment covariates).

---

## Data Contract

```r
# Raw input columns (flu_testing_data.csv)
# season, week (MMWR), year, seasonstart, week_start_date, pos_flua (y), test_flu (N)

n_weeks_in_start_year <- function(start_year)
  52L + as.integer(MMWRweek::MMWRweek(as.Date(paste0(start_year, "-12-31")))$MMWRweek == 53L)

allD <- read.csv("data/flu_testing_data.csv") |>
  dplyr::mutate(
    neg     = N - y,
    nW_true = n_weeks_in_start_year(start_year),
    weekF   = ((week - 27L) %% nW_true) + 1L,   # flu-season week (startWeek = 27)
    p       = y / N
  )

# Permanent exclusions (missing/unreliable data)
EXCLUDE_PERM <- c("2011-12", "2020-21", "2021-22", "2025-26")
# M1 LOSO also excludes 2015-16 (ignition outlier)
EXCLUDE_M1   <- c(EXCLUDE_PERM, "2015-16")
# Production training keeps 2025-26 (11 seasons)
EXCLUDE_PROD <- c("2011-12", "2015-16", "2020-21", "2021-22")
```

**Manual ignition labels** (canonical, `weekF` space from `startWeek=27`):
```r
manual_labels <- c(
  "2012-13"=18L, "2013-14"=20L, "2014-15"=20L,
  "2015-16"=24L, "2016-17"=19L, "2017-18"=20L,
  "2018-19"=19L, "2019-20"=22L, "2022-23"=15L,
  "2023-24"=20L, "2024-25"=23L
)
```

> **Warning:** `scripts/_extended_tune_m1_v7.R` defines its own `manual_labels_orig - 1L` offset. This is a different coordinate system used only by that script. Do not mix with canonical labels above.

---

## M0 — Ignition Detection

**Purpose:** Detect the week a season ignites (crosses threshold into epidemic phase).

**Script:** `scripts/run_loso.R` (fix Windows `setwd` on line 1 before running on Linux)

**Data prep:**
```r
flag_args <- list(p_thresh=0.01, k1=0.4, k_c=0.01, n_consec=2L,
                  min_window=10L, w_min=21L, w_max=21L, d2_relax=-0.01)

res       <- estimateDerivs(allD, k=10L)
outs      <- res$data |> dplyr::group_by(season) |> dplyr::group_split(.keep=TRUE) |>
  purrr::map(~do.call(flagIgnition, c(list(df=.x, manual_labels=manual_labels), flag_args)))
alignedD  <- alignIgnition(outs)
```

**Grid (36 specs):**
```r
grid_loso <- data.table::CJ(
  cls_thr=0.26, use_cls=FALSE,
  p_thr=c(0.002,0.003,0.004,0.005), prev_thr=c(0.001,0.002,0.003),
  n_consec=5L, L=2L, eps=0, K_sum=5L,
  p_sum_thr=c(0.050,0.055,0.060), N_req=4L, w_min=13L, w_max=26L,
  K_dp=3L, dp_thr=0.01, sorted=FALSE
)
```

**Run:**
```r
tuned <- loso_M0v2(
  dat=alignedD, grid=as.data.frame(grid_loso), score_col="p_cls_p",
  drop_seasons="2015-16",
  fit_args=list(fit_base=TRUE, fit_slope=FALSE, fit_fs=FALSE,
                event_k=1L, lead=1L, A_pre=6L, B_post=6L, k_week=6L, k_p=8L, k_fs=4L,
                select=FALSE, verbose=FALSE),
  tune_args=list(miss_penalty=0, lambda=20, kappa=0, gamma=25, gamma_late=0,
                 iWeek=TRUE, ncores=n_cores, verbose=FALSE, progress_every=50L),
  verbose=TRUE
)
saveRDS(tuned, "data/stage1_tuning.rds")
```

**Scoring:** Lexicographic — minimize `sum_abs` → `max_abs` → `n_miss`.

**Gold standard params:** `cls_thr=0.26, p_thr=0.005, prev_thr=0.001, p_sum_thr=0.06, n_consec=5, L=2, K_sum=5, N_req=4, w_min=13, w_max=26`

**Output:** `tuned$best_params`, `tuned$compare` (per-season ignition week, error).

---

## M1 — Alignment

### Reference Curve

```r
M1_PARAMS <- list(
  k_ref=25L, ref_method="fs", temperature=0.25,
  slope_weight=8.0, slope_window=6L, dynamic_temp=FALSE, dynamic_temp_pivot=10L,
  rise_weight=1.0, trough_weight=0.1, peak_decay=0.3
)

ref   <- estimateRef(alignedD=aligned_train, exSeason=character(0),
                     k=M1_PARAMS$k_ref, n_weeks=52L, method=M1_PARAMS$ref_method)
hyper <- learn_alignment_hyperparams(ref$dat, ref$g_ref_fun)
```

> **Critical:** `ref$anchorWeek` must match between production and LOSO folds. If it differs, all `newWeek` coordinates are wrong and downstream M2 features will be on misaligned scales.

### LOSO Tuning Grid (v7, 20 specs)

**Script:** `scripts/_extended_tune_m1_v7.R`

```r
grid_v7 <- tidyr::crossing(
  k_ref=c(25L,30L,40L,50L), multi_temperature=0.25,
  template_shift=0L, align_rise_weight=1.0,
  slope_window=6L, slope_weight=c(8.0,12.0,16.0,20.0,30.0)
)

tune_v7 <- tune_m1_alignment(
  allD=allD, params=readRDS("data/stage1_tuning.rds")$best_params,
  grid=grid_v7, manual_labels=manual_labels_v7,  # ← uses -1L offset version
  exclude_seasons="2015-16", n_weeks=52L,
  use_multi_template=TRUE, ref_method="fs",
  checkpoint_dir="data/m1_tune_ckpt_v7",  # resumable
  n_cores=n_cores, verbose=TRUE,
  dynamic_temp=FALSE, k_deriv=20L, buffer_weeks=5L,
  curvature_ratio=1.0, align_peak_decay=0.3, align_trough_weight=0.1,
  peak_weight_boost=3, peak_weight_decay=0.3
)
```

**Metric:** Weibull-weighted peak MAE — `w(t) = exp(-(0.1t)²)`.

**Gold standard:** `k_ref=25, slope_weight=8.0` → MAE = **1.275 weeks** (interior on both axes after v7).

**Checkpoint resumption:** Re-run the script; it reads from `checkpoint_dir` and skips completed specs.

### Walk-Forward Predictions

```r
m1_train_preds <- m1_walkforward_multi(
  allD=allD, ref=ref, hyper=hyper, params=params, seasons=train_seas,
  temperature=M1_PARAMS$temperature, slope_weight=M1_PARAMS$slope_weight,
  slope_window=M1_PARAMS$slope_window, dynamic_temp=M1_PARAMS$dynamic_temp,
  ..., parallel=TRUE
)
```

---

## M2 — Forecast GAM

### Tuning Grid (v15, 480 specs)

**Script:** `scripts/run_nested_loso_v15.R`

```r
BIAS_ALPHA <- 0.4  # fixed deployment parameter — NOT a grid dimension
                   # unidentifiable in LOSO (Bernoulli NLL flat 0.1–0.4)

grid_v15 <- tidyr::crossing(
  delta=0L, Kr=1L,
  k_f=c(2L,3L,4L,5L),           # template smooth basis
  k_e=c(2L,3L),                 # EMA state smooth
  alpha_state=c(0.30,0.35,0.40,0.45,0.50),  # EMA decay
  k_r=c(0L,2L,3L),              # residual smooth
  k_de=c(0L,2L),                # dz_ema (growth rate, unit-standardized)
  k_sp=c(0L,2L)                 # logit_spread (M1 alignment uncertainty)
)  # 4×2×5×3×2×2 = 480 specs
```

**Phase structure:**
- **Phase 1** (`nested_loso_v15_phase1.rds`): Build M1 cache per fold (10 folds, ~30 min)
- **Phase 2** (`nested_loso_v15_phase2.rds`): Evaluate 480×10 = 4800 fits; resumable checkpoint
- **Final** (`nested_loso_v15_production.rds`): Assembled results

**Gold standard:** `k_f=4, k_e=2, alpha_state=0.40, k_r=2, k_de=0, k_sp=0` → Bernoulli NLL = **0.406**

**Key functions:**
- `nested_loso_build_fold()` — reference curve + hyperparams per fold
- `nested_loso_m2_train()` — fits GAM for one (fold, spec) combination
- `nested_loso_m2_eval_frozen_bias()` — evaluates with frozen GAM + Holt EMA bias correction

### Production Fit

**Script:** `scripts/_rebuild_m2_production_v15.R`

> **Known gotcha:** Line 31 hardcodes `readRDS('data/stage1_tuning.rds')`. If doing a fresh run, change this to your fresh M0 output path.

```r
joint_out <- train_stage2_joint(
  dat=add_prospective_derivs_link(aligned_train),
  template_df=template_df, spec=best_spec_obj,
  method="REML", m1_preds=m1_train_preds
)
gam_fit        <- joint_out$fit
feature_ranges <- joint_out$feature_ranges  # z_ema, logit_f_eff ranges, dz_ema_sd

saveRDS(list(
  spec=best_spec_obj, fit=gam_fit, feature_ranges=feature_ranges,
  m1_train_preds=m1_train_preds, training_seasons=train_seas,
  spec_version="v15", best_spec_id=best_spec_id
), "data/m2_production.rds")
```

**Production kit schema:**
```r
prod <- readRDS("data/m2_production.rds")
prod$fit              # mgcv::bam() fitted GAM; EDF≈22
prod$feature_ranges   # list(z_ema, logit_f_eff, dz_ema_sd) — clamping bounds
prod$m1_train_preds   # data.frame (season, weekF, m1_p_hat, m1_logit_spread, ...)
prod$spec             # stage2_make_spec object
prod$training_seasons # character vector, 11 seasons
```

---

## Dynamic Post-Hoc Bias Correction (Holt EMA)

The frozen GAM is corrected online each season via a Holt exponential moving average:

```
bias_t = bias_alpha * (y_{t-1} - yhat_{t-1}) + (1 - bias_alpha) * bias_{t-1}
```

- `bias_alpha = 0.4` (level adaptation; faster than 0.2 for short peak windows)
- `bias_beta  = 0.0` (no trend component)

**This is a deployment-time correction, not a structural model parameter.** It is:
- Applied week-by-week after the frozen GAM predicts
- NOT part of the LOSO grid (NLL is flat across 0.1–0.4 → unidentifiable in LOSO)
- Set heuristically: 0.4 chosen for faster peak correction in short seasons (e.g., 2025-26)

**Verification:** During prospective deployment, the `ema_bias` column in the walk-forward output should converge to a nonzero value and track the same sign as the raw residuals. Compare against gold `deploy_wf_cache.rds` by checking same-sign fraction ≥ 0.9.

---

## Prospective Deployment

```r
fresh_kit <- load_prospective_kit(
  ref_path = "data/ref_production.rds",
  m2_path  = "data/m2_production.rds"
)

# Snapshot live data before comparing
currentD <- dplyr::filter(getCurrentD(startWeek=27L), season == "2025-26")
saveRDS(currentD, "data/currentD_snapshot.rds")

wf <- run_prospective_pipeline(
  kit=fresh_kit, current_data=currentD,
  walk_start=5L, mode="frozen", verbose=TRUE
)
saveRDS(wf, "data/deploy_wf_cache.rds")
```

> **Note:** `prospective_deployment.qmd` sources `identifiability.R` and `m1_peak_flags.R` from `PAGe/R/` (not root `R/`). Source these explicitly if running outside the QMD context.

---

## Evaluation Metrics

| Stage | Metric | Target |
|-------|--------|--------|
| M0 | Per-season ignition error (weeks) | 0 for all seasons |
| M1 | Weibull-weighted peak MAE | ≤ 1.275 weeks |
| M2 LOSO | Bernoulli NLL | ≤ 0.406 |
| M2 LOSO | cor(gold, fresh NLL) | ≥ 0.999 |
| Prospective | Max forecast delta | < 0.005 |

### Acceptable fresh-run deltas (vs gold)

| Check | Threshold |
|-------|-----------|
| M0 ignition week per season | = 0 |
| M1 anchorWeek | EXACT (critical) |
| M1 reference curve max delta | < 0.01 (logit) |
| M1 LOSO MAE delta | < +0.02 |
| M2 max NLL delta (per spec) | < 0.002 |
| M2 GAM max coef delta | < 0.05 |
| M2 dz_ema_sd relative delta | < 5% |
| Prospective M2 forecast max delta | < 0.005 |

---

## Runtime Estimates (Asguard, ~20 cores)

| Step | Time |
|------|------|
| M0 LOSO (36 specs) | ~15 min |
| M1 ref curve | ~5 min |
| M1 LOSO (20 specs) | 2–4 hours |
| M2 LOSO Phase 1 | ~30 min |
| M2 LOSO Phase 2 (480 specs) | 4–8 hours |
| M2 production fit | ~10 min |
| Prospective | ~5 min |

**Total: ~8–14 hours.** Run M1 LOSO and M2 LOSO sequentially (both saturate cores internally).

---

## Fresh Validation Scripts

All scripts live in `scripts/fresh_run/`. Each writes to `data/fresh_*` paths and compares against gold at the end.

```
00_shared.R      — shared setup (source at top of each step)
01_m0.R          — M0 LOSO tuning
02_m1_ref.R      — M1 reference curve
03_m1_loso.R     — M1 alignment LOSO
04_m2_loso.R     — M2 nested LOSO (480 specs, resumable)
05_m2_production.R — M2 production GAM fit
06_prospective.R — Prospective walk-forward deployment
07_compare.R     — Consolidated pass/fail comparison report
```

Run in order. Steps 3 and 4 can overlap on separate machines if cores allow.
