# Plot classifier scores by season and model

Visualization helper for Stage-1 classifier scores produced by
\[fitIgnition()\]. It will plot any score columns that exist in
`ign_fit$data`; missing score columns are silently dropped (so it works
when only the base model is fitted).

## Usage

``` r
plot_cls_models_by_season(
  ign_fit,
  score_cols = c(base = "p_cls_p", slope = "p_cls_slope_pop", fs = "p_cls_fs_pop"),
  x_col = "weekF",
  x_max = 30L,
  y_max = 0.3,
  lead = 1L,
  thr = NULL,
  use_plotly = TRUE,
  ncol = NULL
)
```

## Arguments

- ign_fit:

  Output from \[fitIgnition()\] (list with `$data`) or a data.frame.

- score_cols:

  Named character vector of score columns to plot (name used as model
  label).

- x_col:

  Week column to plot on x-axis. Default `"weekF"`.

- x_max:

  Plot only weeks `<= x_max`. Default `30`.

- y_max:

  Y-axis maximum. Default `0.3`.

- lead:

  Label shift used in \[fitIgnition()\] (dotted line at
  `iWeek_true - lead`). Default `1`.

- thr:

  Optional numeric vector of horizontal reference lines.

- use_plotly:

  If TRUE returns `plotly::ggplotly(p)`. Default TRUE.

- ncol:

  Optional integer; number of columns in `facet_wrap()`.

## Value

A ggplot object, or plotly object if `use_plotly=TRUE`.

## Details

Each facet corresponds to one `model | season` panel. Two vertical
reference lines are drawn per panel:

- dashed: truth ignition week `iWeek_true = min(weekF[phase==1])`.

- dotted: label endpoint week `iWeek_true - lead` used in classifier
  training.

Horizontal dotted lines can be added via `thr` to visually assess score
thresholds.
