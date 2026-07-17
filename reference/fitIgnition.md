# Fit ignition classifier scores (Stage-1)

Fits a smooth probabilistic classifier for an "ignition event window"
and appends predicted scores to the full dataset. This function supports
up to three variants:

- **Base** (default): random intercept by season via
  [`gamm4::gamm4()`](https://rdrr.io/pkg/gamm4/man/gamm4.html).

- **Slope** (optional): random intercept + random slope on `week_col`.

- **FS** (optional): season-varying week shape via
  [`mgcv::bam()`](https://rdrr.io/pkg/mgcv/man/bam.html) with `bs="fs"`.

## Usage

``` r
fitIgnition(
  dat,
  season_col = "season",
  week_col = "weekF",
  phase_col = "phase",
  p_col = "p",
  event_k = 1L,
  lead = 1L,
  A_pre = 6L,
  B_post = 6L,
  k_week = 6L,
  k_p = 8L,
  k_fs = 4L,
  fit_base = TRUE,
  fit_slope = FALSE,
  fit_fs = FALSE,
  select = FALSE,
  verbose = TRUE
)
```

## Arguments

- dat:

  data.frame containing at least
  `season_col, week_col, phase_col, p_col`.

- season_col:

  Season identifier column name. Default `"season"`.

- week_col:

  Within-season week column name. Default `"weekF"`.

- phase_col:

  Phase indicator column name. Default `"phase"`.

- p_col:

  Weekly positivity/proportion column name. Default `"p"`.

- event_k:

  Integer \>= 0. Event window width parameter (positives span
  `event_k+1` weeks). Default `1`.

- lead:

  Integer \>= 0. Shifts the event window earlier by `lead` weeks.
  Default `1`.

- A_pre:

  Integer \>= 0. Weeks before `iWeek_true` included in training. Default
  `6`.

- B_post:

  Integer \>= 0. Weeks after `iWeek_true` included in training. Default
  `6`.

- k_week:

  Basis dimension for `s(week)`. Default `6`.

- k_p:

  Basis dimension for `s(p)`. Default `8`.

- k_fs:

  Basis dimension for the factor-smooth deviation
  `s(week,season,bs="fs")`. Default `4`.

- fit_base:

  Logical. Fit the base model. Default `TRUE`.

- fit_slope:

  Logical. Fit the random-slope model. Default `FALSE`.

- fit_fs:

  Logical. Fit the factor-smooth (fs) model. Default `FALSE`.

- select:

  Logical. Passed to `gamm4::gamm4(select=...)`. Default `FALSE`.

- verbose:

  Logical. Print progress messages. Default `TRUE`.

## Value

A list with:

- data:

  Full dataset with added score columns (see below).

- train_data:

  Training subset with `event` label and per-row bounds.

- iWeek_by_season:

  Season-level truth ignition week table.

- fits:

  List of fitted objects for each enabled model.

**Added score columns (in `$data`).**

- `p_cls_p`: base population-level score (gamm4 fixed-effects
  prediction).

- `p_cls_base_pop`: alias of `p_cls_p` for clarity.

- `p_cls_slope_pop`: population-level score for the random-slope model
  (if fitted).

- `p_cls_fs_pop`: population-level score for the fs model (if fitted).

- `p_cls_fs_full`: full fs score including season deviations (if fitted;
  retrospective only).

## Details

**Training window (balanced around ignition).** For each season, the
reference ignition week is `iWeek_true = min(week_col[phase==1])`.
Training data are restricted to a per-season window:
`week in [iWeek_true - A_pre, iWeek_true + B_post]`.

**Event labeling (shifted earlier).** The positive event window is
shifted earlier by `lead` weeks: `event(s,w)=1` if
`iWeek_true - lead - event_k <= week <= iWeek_true - lead`. This
produces an "onset-like" score that can peak before the truth ignition
week.

**Prospective transfer.** The detector should use population-level
predictions (excluding season-specific effects). In this implementation:

- For `gamm4` fits: population-level score is `predict(fit$gam, ...)`
  (random effects excluded).

- For `fs` fit: population-level score is computed by excluding the
  `s(week,season)` smooth.
