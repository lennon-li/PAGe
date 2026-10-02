---
name: seasonal-forecast
description: Train, tune, evaluate, replay, or deploy the PAGe seasonal respiratory virus forecasting pipeline. Covers the M0 → M1 → M2 chain plus the governed acceptance → refresh → promotion release workflow.
---

# Seasonal Forecast Training & Evaluation Skill

Use this skill when training, tuning, evaluating, replaying, or deploying the PAGe seasonal
respiratory virus forecasting pipeline.

---

## Authority and status (read first)

`docs/workflow-status.md` is the governing status map for what is canonical, compatibility,
research-only, superseded, or deprecated. **When this skill and that map disagree, the map wins**
and this skill is stale. `docs/tuning-playbook.md` governs grid design, boundary handling, and
stopping rules. `docs/deployment-workflow.qmd` governs the release chain.

Three rules follow from that map and apply everywhere below:

1. **Canonical for new work** is the guarded stage API (`validate_season_selection()`, `tune_*()`,
   `validate_*_tuning()`, `fit_*()`, `freeze_*()`, `assemble_kit()`) and the high-level wrappers
   (`train_pipeline()`, `run_prospective_pipeline()`, `replay_season_holdout()`,
   `check_promotion()`, `verify_promotion_evidence()`).
2. **Everything under `scripts/fresh_run/` and every versioned `run_nested_loso_v*` script is
   research-only or superseded.** They are preserved for provenance and hypothesis work. They have
   no promotion chain and must not be used as deployment instructions. The stage recipes below are
   documented in that spirit.
3. **No numeric result in this file is current deployment evidence.** Private result artifacts are
   absent from this repository. Historical values are reproduction targets that must be reconciled
   to hashed private artifacts before any current claim.

### Working incumbent

Per `docs/workflow-status.md`, the working incumbent is the private `v16-corrected` frozen kit:

```
alpha_state = 0.20, k_sp = 8, bias_alpha = 0.05
```

The artifact itself is outside version control; the repository records the specification and its
provenance caveat rather than reconstructing it. Older notes citing `alpha_state = 0.15, k_sp = 6`
describe a different v16 research fit and are **not** the incumbent. No completed promotion is
preserved here: the 2025-26 frozen acceptance replay (`boundary-expansion-20260801T150000Z`) failed
the locked NLL gate while horizon and phase gates passed, and no post-promotion refit occurred.

---

## Pipeline Overview

```
Surveillance data (load_flu_hist(path))
  ↓ M0: Ignition Detection  →  iWeek_hat (season start week)
  ↓ M1: Alignment           →  template fit (tau, delta), logit_spread
  ↓ M2: Forecast GAM        →  p_hat (1–2 week ahead positivity)
  ↓ Prospective             →  weekly walk-forward + Holt EMA bias correction
```

Each stage is sequential within a week. M1 must run before M2 (M2 consumes M1 alignment
covariates). Governed retunes stop on unresolved M0 boundary edges before M1, and on unresolved M1
edges before M2.

---

## Data Contract

**Observations are not bundled with the package.** `data/flu_testing_data.csv` was removed in
`715a72e` ("remove generated and private data artifacts"); any code or document still naming that
path — including `load_allD()` in `scripts/fresh_run/00_shared.R` — will fail until you supply
authorized data yourself. Supply it explicitly:

```r
allD <- load_flu_hist(path = "/path/to/authorized/flu_hist.csv")
# or set PAGE_FLU_HIST_FILE and call load_flu_hist()
allD <- prepare_surveillance_data(allD)
```

`load_flu_hist()` resolves in order: explicit `path` → `PAGE_FLU_HIST_FILE` →
`system.file("extdata", "flu_hist.csv", package = "PAGe")`, and errors if none exists. The public
workflow uses synthetic inputs and disclosure-safe outputs (governance decision G-07); authorized
private Ontario rows are supplied by file path and never committed.

```r
# Expected columns after load
# season, week (MMWR), year, seasonstart, week_start_date, pos_flua (y), test_flu (N)

n_weeks_in_start_year <- function(start_year)
  52L + as.integer(MMWRweek::MMWRweek(as.Date(paste0(start_year, "-12-31")))$MMWRweek == 53L)

# derived: neg = N - y, weekF = ((week - 27L) %% nW_true) + 1L, p = y / N   (startWeek = 27)

# Pre-acceptance exclusions (missing/unreliable data plus prospective holdout)
EXCLUDE_PERM <- c("2011-12", "2020-21", "2021-22", "2025-26")
# M1 LOSO also excludes 2015-16 (ignition outlier)
EXCLUDE_M1   <- c(EXCLUDE_PERM, "2015-16")
# A fixed post-acceptance refresh may release 2025-26 after a passing,
# hash-bound decision; these remain the non-holdout exclusions.
EXCLUDE_PROD <- c("2011-12", "2015-16", "2020-21", "2021-22")
```

`train_pipeline()` defaults match `EXCLUDE_PROD` with `prospective_holdout = "2025-26"`.
`load_allD()` in the research scripts fails closed on the holdout unless `include_holdout = TRUE`.

**Manual ignition labels** (canonical, `weekF` space from `startWeek=27`):
```r
manual_labels <- c(
  "2012-13"=18L, "2013-14"=20L, "2014-15"=20L,
  "2015-16"=24L, "2016-17"=19L, "2017-18"=20L,
  "2018-19"=19L, "2019-20"=22L, "2022-23"=15L,
  "2023-24"=20L, "2024-25"=23L
)
```

> **Warning:** `scripts/_extended_tune_m1_v7.R` defines its own `manual_labels_orig - 1L` offset.
> This is a different coordinate system used only by that script. Do not mix with canonical labels.

> **Label isolation:** the canonical `build_m2()` path requires `manual_labels_train` to exclude the
> held-out season and `manual_labels_test = NULL`. Checkpoints built with a held-out label visible to
> evaluation are **not** valid prospective evidence and must be recomputed. Retrospective ignition
> labels are opt-in only.

---

## M0 — Ignition Detection

**Purpose:** Detect the week a season ignites (crosses threshold into epidemic phase).

**Script (research-only):** `scripts/run_loso.R` — historical recipe, preserved for provenance. Fix
the Windows `setwd` on line 1 before running on Linux. For new work call the guarded M0 stage API
via `train_pipeline()`, which applies the boundary gate before M1.

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

**Historical locked parameters:** `cls_thr=0.26, p_thr=0.005, prev_thr=0.001, p_sum_thr=0.06, n_consec=5, L=2, K_sum=5, N_req=4, w_min=13, w_max=26`

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

**Script (research-only):** `scripts/_extended_tune_m1_v7.R` — historical v7 recipe. For new work use
the guarded M1 stage API; unresolved M1 boundary edges stop the run before M2.

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

**Coded locked values:** `k_ref=25, slope_weight=8.0`. Historical sources
report conflicting MAE values, including 1.275, 1.276, and 1.338 weeks; none is
verified here without its private artifact.

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

The M2 search history runs v14 → v15 → v15-postfix → v16 → v17/v18 experiments. **v14 and v15 are
superseded; v16 research and kit-building history is research-only; v17 and v18 are experiments, not
a new incumbent.** The working incumbent remains `v16-corrected` (see *Authority and status*).

### Spec axes

```r
stage2_make_spec(
  delta = 0L, Kr = 1L, T = "S",
  k_f,          # template smooth basis
  k_e,          # EMA state smooth
  alpha_state,  # EMA decay
  k_r,          # residual smooth
  k_de,         # dz_ema (growth rate, unit-standardized)
  k_sp,         # logit_spread (M1 alignment uncertainty)
  k_n = 0L, k_w = 0L, k_s = 0L,
  lambda_w = 0, w_floor = 0.05,
  bias_alpha, bias_beta = 0.0
)
```

**Key functions:**
- `nested_loso_build_fold()` — reference curve + hyperparams per fold
- `nested_loso_m2_train()` — fits GAM for one (fold, spec) combination
- `nested_loso_m2_eval_frozen_bias()` — evaluates with frozen GAM + Holt EMA bias correction

Phase structure is reused across versions: **Phase 1** builds the M1 fold cache (10 folds, ~30 min),
**Phase 2** evaluates specs × folds against that cache with a resumable checkpoint. Later versions
deliberately reuse `data/fresh_nested_loso_v15_phase1.rds` so that only the M2 axes change — except
v18, which rebuilds the cache because it alters `logit_spread` itself.

### Version history

| Version | Status | Grid | What changed |
|---|---|---|---|
| v14 | superseded | — | Do not rebuild a kit from it. Its spec IDs carry a `_ba/_bb` suffix. |
| v15 | superseded | 480 specs: `k_f`×`k_e`×`alpha_state`×`k_r`×`k_de`×`k_sp` | `BIAS_ALPHA = 0.4` fixed, not a grid axis (unidentifiable in LOSO; Bernoulli NLL flat 0.1–0.4). Historical repro target `k_f=4, k_e=2, alpha_state=0.40, k_r=2, k_de=0, k_sp=0`, NLL 0.406. |
| v15-postfix | superseded | 192 specs | Focused grid centred on `k_f=6`/`alpha_state=0.35`. |
| v16 | research-only | 240 specs | **RE-fix:** `estimate_season_re_online()` now uses only post-ignition observations (`weekF >= iWeek_hat`) instead of all current-season obs, preventing pre-ignition low-positivity weeks from producing a spuriously negative season RE that tanked early-season predictions. `bias_alpha` extended to 0.1–1.0 because the RE fix may shift the optimum. |
| v17 | research-only experiment | `k_f`×`k_e`×`alpha_state`×`k_sp` | Tests `bias_alpha` as **adaptive (1/n cumulative mean)** rather than a tuned hyperparameter; the grid's `bias_alpha` column is ignored at eval time. |
| v18 | research-only experiment | 6-spec `k_sp` sweep | Tests whether the improved Phase-2 `logit_spread` (between + within GAM SE) shifts optimal `k_sp`. Rebuilds the M1 fold cache first. |

Neither v17 nor v18 has promoted anything. Treat both as open hypotheses.

### Historical v15 candidate fit (not promotion)

`scripts/_rebuild_m2_production_v15.R` is retired research-only. It requires `--research-only` plus a
unique `--output=...` path, refuses input containing `2025-26`, refuses mutable or existing outputs,
and writes a separate reference sidecar. **It cannot create or replace a promoted kit.**

Historical research-artifact schema, for reading old artifacts only:

```r
prod$fit              # mgcv::bam() fitted GAM; EDF ~ 22
prod$feature_ranges   # list(z_ema, logit_f_eff, dz_ema_sd) — clamping bounds
prod$m1_train_preds   # data.frame (season, weekF, m1_p_hat, m1_logit_spread, ...)
prod$spec             # stage2_make_spec object
prod$training_seasons # historical research training seasons
```

Operational code must instead call `load_promoted_kit()` with the immutable registry path and a
verified deployment manifest.

---

## Current Retuning and Selection

For new development, use `train_pipeline(mode = "retune")`. When compatible `previous_results` are
supplied, `plan_m2_grid()` consolidates finite NLL by stable spec ID and falls back to finite fold
scores when needed. Supplied IDs must be unique and exactly match their parameter-derived canonical
IDs; Bernoulli NLL is preferred to `mean_nll`, and ranking ties use canonical ID. The planner retains
the v16 incumbent and best prior spec, preserves diverse finalists, adds local neighbors, and expands
a winning boundary using adjacent observed spacing. `max_m2_specs` remains a hard cap.

The user must choose one explicit final full-LOSO rule:

- `selection_method = "min_nll"`: lowest NLL, then complexity and spec ID.
- `selection_method = "one_se"`: simplest candidate within one standard error of the best NLL;
  requires finite fold scores.
- `selection_method = "pareto"`: non-dominated on NLL, worst-horizon MAE, and worst-phase MAE, then
  NLL, complexity, and spec ID.

### Boundary discipline

Per `docs/tuning-playbook.md`, a selected value should normally be bracketed by tested values on both
sides. A boundary winner is not automatically a failure — `0` can be a meaningful null model, some
axes have valid limits, a one-SE rule may prefer a simpler boundary, and a flat profile may show
expansion is not identifiable — but the reason must be recorded, never silently promoted. A governed
validation with `check_boundaries = TRUE` warns with class `page_boundary_warning` and stops the
stage. Inspect without stopping:

```r
report <- inspect_tuning_boundaries(m1_tuning, stage = "M1")
subset(report, decision == "expand_required")
```

`expand_tuning_grid()` appends new rows at half the adjacent tested spacing, retaining existing rows
and IDs; the adaptive M2 planner applies the same halving rule automatically.

Retuning must finish before the untouched holdout is examined. **Changing the model or grid after
viewing holdout results starts a new development cycle**; it is not the fixed post-acceptance
refresh.

---

## Dynamic Post-Hoc Bias Correction (Holt EMA)

The frozen GAM is corrected online each season via the canonical correction specification shared by
runtime and frozen LOSO evaluation:

```
bias_t = bias_alpha * (y_{t-1} - yhat_{t-1}) + (1 - bias_alpha) * bias_{t-1}
```

- base `bias_alpha = 0.05` (canonical Holt level EMA base rate, `PAGe/R/m2_spec_grid.R`)
- high `bias_alpha = 0.7` after at least two consecutive same-sign residual transitions
  (the third consecutive same-sign residual)
- `bias_beta = 0.0` (no trend component)

**This is a deployment-time correction, not a structural model parameter.** It is:
- applied week-by-week after the frozen GAM predicts
- resolved from the stored canonical specification in strict mode (`PAGe/R/correction_spec.R`)
- applied identically in frozen LOSO and runtime, including the adaptive transition and post-peak
  override
- available with older values only through an explicit warning-producing compatibility mode

v17 explores replacing the fixed base rate with an adaptive `1/n` cumulative mean. That is an open
experiment and does not change the canonical spec above.

Historical cache comparisons are not current deployment evidence. Verify the registered kit and its
manifest first, then inspect correction-state diagnostics from the governed run.

---

## Prospective Deployment

```r
fresh_kit <- load_promoted_kit(
  kit_path = "/secure/PAGe/deployment-registry/<deployment-id>/promoted_kit.rds",
  deployment_manifest_path =
    "results/deployment-audit/<deployment-id>/deployment_manifest.json"
)

# Snapshot live data before comparing
currentD <- dplyr::filter(getCurrentD(startWeek=27L), season == "2025-26")
saveRDS(currentD, "data/currentD_snapshot.rds")

wf <- run_prospective_pipeline(
  kit=fresh_kit, current_data=currentD,
  walk_start=5L, mode="frozen", verbose=TRUE
)
```

`load_promoted_kit()` checks SHA-256, spec, and training-season binding, and has **no mutable
`current` discovery path**. `mode = "frozen"` is the validated production path; `mode =
"weekly_refit"` and `nested_loso_m2_eval_weekly_refit()` are research-only comparison behavior.

> **Note:** `prospective_deployment.qmd` sources `identifiability.R` and `m1_peak_flags.R` from
> `PAGe/R/` (not root `R/`). Source these explicitly if running outside the QMD context.

---

## Replay, Acceptance, and Promotion

The governed release chain is: **frozen candidate/incumbent acceptance excluding `2025-26` →
immutable decision evidence → fixed-spec refresh including `2025-26` → immutable registry
publication → verified loading.** Operator commands and the private/audit boundary are in
`docs/deployment-workflow.qmd`.

### Season replay

```r
replay <- replay_season_holdout(
  kit, allD, season = "2025-26",
  runner = run_prospective_pipeline,
  kit_compatibility = "strict"   # "legacy_m2" only for a legacy incumbent
)
```

It **stops on holdout leakage** if the season appears in the kit's training seasons, runs
`prepare_surveillance_data()`, and produces a standardized prediction frame plus a forecast ledger.
`summarize_forecast_metrics()` and `summarize_replay_diagnostics()` build the metric and calibration
summaries.

### Promotion gate

```r
report <- check_promotion(
  candidate, incumbent,
  min_nll_improvement    = 0.02,
  max_horizon_degradation = 0.05,
  max_phase_degradation   = 0.10
)
```

The `0.02` relative-NLL threshold is an **operational promotion rule, not a scientific effect
threshold** (governance decision G-06; it entered the code in `feebaa0` on 2026-07-16 with no
recorded clinical or statistical rationale). A bare promotion report cannot release a holdout.

### Chain steps

| Step | Entry point | Notes |
|---|---|---|
| Acceptance replay | `scripts/acceptance/replay_2025_26.R` | Requires authorized data plus candidate and incumbent kits; verifies both exclude `2025-26`. |
| Fixed-spec refresh | `season2526/run_retrain_venkata.R` | Post-acceptance only. Requires the **passing** decision bundle, its manifest, exact kits, authorized data. Run `--preflight-only` first. |
| Evidence verification | `verify_promotion_evidence()` | Validates bundle/manifest/data/candidate/incumbent paths against the holdout season. |
| Promotion | `scripts/promotion/promote_post_refit.R` | Validates the full acceptance-to-refit hash chain; supports `--preflight-only`; refuses destination collisions. |
| Verified load | `load_promoted_kit()` | Immutable kit + deployment manifest only. |

No completed real-data refit or promotion is preserved in this repository. Rendered `docs/*.html`
snapshots are **not** evidence that any private-data run occurred; some predate the audit and retain
retired numbers or weekly-refit language.

---

## Manuscript Analysis (separate from deployment)

`manuscript/` holds the Ontario influenza manuscript analysis, governed by
`manuscript/GOVERNANCE_DECISIONS.md` (v1.1, 2026-09-01),
`manuscript/ANALYSIS_PROTOCOL.md`, and `manuscript/ONTARIO_FLU_SEASON_DECLARATION.md`.

**Do not merge its season doctrine into the deployment pipeline.** The manuscript uses a *rotating*
holdout in which all 11 non-excluded seasons — `2025-26` included — have equal analytical status and
each is held out once (decision G-03). The deployment pipeline keeps `2025-26` as a *prospective*
holdout that fails closed. These are different analyses with different rules.

Other binding manuscript constraints: the season universe may not be expanded by newly retrieved data
(G-04); the four fixed exclusions stay out of the principal exchangeable set, with `2015-16` reportable
only as separately labelled diagnostic evidence (G-02); origin-time vintages are used where
reconstructible, otherwise one consistently applied final-data snapshot with disclosure (G-05).
Data-custodian authorization (G-08) and the ethics/REB determination (G-09) remain **pending external
evidence** and are not inferred from repository access.

---

## Historical Evaluation Targets

The following values are retained for historical reproduction only. They must
be reconciled to hashed private artifacts before use in a current result claim.

| Stage | Metric | Recorded target |
|-------|--------|--------|
| M0 | Per-season ignition error (weeks) | 0 for all seasons |
| M1 | Weibull-weighted peak MAE | ≤ 1.275 weeks |
| M2 LOSO | Bernoulli NLL (v15 gold repro) | ≤ 0.406 |
| M2 LOSO | Bernoulli NLL (v16 historical note) | ≈ 0.4175 |
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

## Runtime Estimates (asgard, ~20 cores)

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

## Fresh-Run Script Inventory (research-only)

All scripts live in `scripts/fresh_run/` and write to `data/fresh_*` paths. Per
`docs/workflow-status.md` the entire family is **research-only**: it loads private local files, has
no promotion chain, and is not a deployment instruction. `00_shared.R` says so itself. Use
`train_pipeline()`, `replay_season_holdout()`, and `check_promotion()` for production work.

### Core sequence

```
00_shared.R        — shared setup; sourced at the top of every step
01_m0.R            — M0 LOSO tuning
02_m1_ref.R        — M1 reference curve
03_m1_loso.R       — M1 alignment LOSO
04_m2_loso.R       — M2 nested LOSO (v15, 480 specs, resumable); builds the Phase-1 M1 fold cache
05_m2_production.R — M2 production GAM fit          [superseded]
06_prospective.R   — prospective walk-forward deployment
07_compare.R       — consolidated pass/fail comparison report
```

### Experiment branches

```
03b_m1_kappa_sweep.R          — M1 kappa sweep
04_m2_loso_postfix.R          — v15-postfix, 192-spec focused grid      [superseded]
04c_m2_loso_expand.R          — v15 grid expansion
04e_m2_loso_v16.R             — v16 RE-fix, 240 specs
04f_m2_loso_v16_expand.R      — v16 boundary expansion
04h_m2_loso_v17_adaptive_ba.R — v17 adaptive bias-alpha experiment
04k_m2_loso_v18_spread.R      — v18 logit_spread ksp sweep (rebuilds M1 cache)
05b_m2_production_v16.R       — v16 kit build
```

Later steps reuse `data/fresh_nested_loso_v15_phase1.rds` as the M1 fold cache rather than rebuilding
it; v18 is the exception. Checkpointed steps resume by re-reading their `*_ckpt.rds`.

> **Data prerequisite:** `load_allD()` in `00_shared.R` still reads `data/flu_testing_data.csv`,
> which is no longer in the repository. Every script in this family will fail at the data load until
> you supply that file locally. See *Data Contract*.

`00_shared.R` locates the repository root by walking up from `getwd()` or the `--file=` argument
looking for `PAGe/DESCRIPTION`, then `setwd()`s there — so these scripts can be run by absolute path
from anywhere, but they will change your working directory.

---

## Historical Fresh-Run FAIL Patterns (recorded 2026-04-16)

When comparing fresh against gold, these FAILs are expected and explained — not regressions:

| FAIL | Cause | Action |
|------|-------|--------|
| M1 ref curve delta > 0.01 | 2025-26 data added to fresh ref (post-peak weeks shift ~0.03 logit) | Expected; passes if gold is also rebuilt with current data |
| M1 LOSO MAE delta > 0.02 | Slope-similarity bug fix (2026-04-10): `t_obs → u_hat` in `align_multi_template` changed alignment scores | Not a regression; gold was pre-fix. Best spec is unchanged (s001) |
| M2 spec_id / coef / NLL mismatch | Gold `nested_loso_v15_production.rds` is actually v14 (has `_ba/bb` suffix in spec IDs) | Strip `_ba[0-9.]+_bb[0-9.]+$` from gold spec IDs before joining |
| Prospective forecast delta > 0.005 | Historical caches used different retired correction settings (`bias_alpha=0.2` versus `0.4`) | Not comparable and not current deployment evidence; use the governed registered-kit workflow instead |

**Critical checks that must PASS even with gold version mismatch:**
- M0 ignition delta = 0 (all seasons)
- M1 anchorWeek exact match
- M2 best NLL ~ 0.406 (fresh: 0.4078)
- Prospective ignition week matches

**Known bugs fixed during fresh run:**
- `run_alignment_prospective_multi()` was not propagating `t_peak_median` to its return list — it was nested under `$peak` internally but not surfaced at the top level. Fixed 2026-04-16. Stale checkpoint files from pre-fix runs must be deleted before re-running M1 LOSO.
- `load_prospective_kit()` uses `data_dir` + filename args, not full paths — use `load_prospective_kit(data_dir="data", ref_file="fresh_ref_production.rds", ...)`.
- `multisession` workers use the installed PAGe package, not local `source()`d overrides — run `R CMD INSTALL PAGe` after any package edits before running LOSO steps.
