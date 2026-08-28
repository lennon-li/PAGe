# Flag influenza ignition week (4-rule minimal version)

Rules: 1) Core run (no w_min gating): fit\>=p_thresh & d1\>k1 for
n_consec weeks (OR 1-week if d2 \> d2_relax and core holds that week) 2)
Slow-start (fallback only, gated by w_min): cum_p_fit \> k_c & d1 \> k1
(single-week) 3) Relaxed run (fallback only, gated by w_min):
fit\>=p_thresh & d1 \> k1 for n_consec (OR 1-week if d2 \> d2_relax) 4)
Minimal run (fallback only, gated by w_min AND weekF \> w_max):
fit\>=p_thresh & d1 \> 0 for n_consec (OR 1-week if d2 \> d2_relax)

## Usage

``` r
flagIgnition(
  df,
  p_thresh = 0.01,
  k1,
  k_c = 0.01,
  n_consec = 2L,
  current_week = NULL,
  min_window = 10L,
  w_min = 20L,
  w_max = 21L,
  d2_relax = -0.01,
  manual_labels = NULL
)
```

## Arguments

- df:

  data.frame for a single season. Must include weekF, fit, d1, d1_low.
  If d2 is missing, the 1-week d2-relaxation is skipped. If y and N are
  present, cum_p_obs/cum_p_fit are computed (cum_p_fit weighted by N).

- p_thresh:

  response-scale positivity threshold for rules 1/3/4.

- k1:

  logit-scale slope threshold.

- k_c:

  threshold for cumulative fitted positivity (rule 2).

- n_consec:

  run length for run-based rules (default 2).

- current_week:

  optional integer; if provided, only consider weekF \<= current_week.

- min_window:

  exclude early/late weeks by requiring weekF in \[min_window,
  52-min_window\].

- w_min:

  fallback start week: rules 2-4 are only considered at weekF \>= w_min
  (and only if rule 1 fails).

- w_max:

  enable rule 4 only if weekF \> w_max (default 21).

- d2_relax:

  threshold for optional 1-week relaxation when d2 exists.

- manual_labels:

  named integer vector mapping season labels (e.g. "2015-16") to
  manually-verified ignition weekF values. When a season is found in
  this vector, the algorithmic detection is bypassed and the specified
  week is used directly. Defaults to `NULL` (algorithmic detection
  only). Pass
  [`page_manual_ignition_labels()`](https://lennon-li.github.io/PAGe/reference/page_manual_ignition_labels.md)
  to restore the pre-verified historical labels (retrospective; never
  use for held-out LOSO test seasons).

## Value

list(data=augmented df, ignition=1-row summary)

## Details

Window gate (all rules): weekF in \[min_window, 52-min_window\], and \<=
current_week if provided. Fallback gate (rules 2-4 only): weekF \>=
w_min, and only evaluated if rule 1 fails. Extra gate (rule 4 only):
weekF \> w_max.

## Examples

``` r
# Algorithmic detection only (default; safe for prospective / LOSO use)
# out <- flagIgnition(season_df, p_thresh = 0.01, k1 = 0.05)

# Opt into retrospective manual labels for known seasons
# out <- flagIgnition(season_df, p_thresh = 0.01, k1 = 0.05,
#                     manual_labels = page_manual_ignition_labels())
```
