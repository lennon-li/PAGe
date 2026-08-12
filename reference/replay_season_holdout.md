# Replay a season that was unseen by a pre-trained kit

Replay a season that was unseen by a pre-trained kit

## Usage

``` r
replay_season_holdout(
  kit,
  allD,
  season = "2025-26",
  runner = run_prospective_pipeline,
  kit_compatibility = c("strict", "legacy_m2"),
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

- ...:

  Additional runner arguments.

## Value

Replay predictions, standardized metrics, and explicit workflow fields.
The holdout is not eligible to join training until separately compared
with an incumbent using check_promotion().
