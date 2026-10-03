# Replay a season that was unseen by a pre-trained kit

The runner must return an independent evaluation schedule in
\`params_df\$eval_week\` (and optionally \`params_df\$h\`). When the
replay emits forecasts, their forecast keys are validated against that
schedule: each origin/horizon pair must be unique, \`target_weekF\` must
equal \`origin + horizon\`, and the emitted set must match the schedule
exactly. Missing, duplicated, unmatched, or inconsistent keys, and any
prediction row from a season other than \`season\`, raise an error
rather than silently scoring a partial replay.

## Usage

``` r
replay_season_holdout(
  kit,
  allD,
  season = "2025-26",
  runner = run_prospective_pipeline,
  kit_compatibility = c("strict", "legacy_m2"),
  timing_mode = c("legacy", "fractional"),
  ...
)
```

## Arguments

- kit:

  Pre-trained deployment kit.

- allD:

  Multi-season surveillance data.

- season:

  Holdout season to replay.

- runner:

  Injectable prospective runner; defaults to run_prospective_pipeline()
  in frozen mode.

- kit_compatibility:

  Identity mode. The default `"strict"` requires canonical
  `m2_production`; `"legacy_m2"` explicitly permits a legacy `m2` field
  with a warning.

- timing_mode:

  Character. `"legacy"` preserves integer ignition and aligned
  coordinates; `"fractional"` preserves numeric coordinates.

- ...:

  Additional runner arguments.

## Value

Replay predictions, standardized metrics, and explicit workflow fields.
The holdout is not eligible to join training until separately compared
with an incumbent using check_promotion(). Also retains a
`forecast_ledger` of expected weekly origins and both horizons,
including missing targets and forecasts, and `stages` with detector
output, M1 parameters/curves and raw M2 predictions. The legacy
`predictions` table contains only scorable rows. A replay with no
scorable rows has status `unseen_replay_failed`, a failure code, and
NULL metrics/diagnostics. Emitted intervals are conditional fitted-mean
bands, not validated full predictive intervals.
