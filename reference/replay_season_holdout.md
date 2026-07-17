# Replay a season that was unseen by a pre-trained kit

Replay a season that was unseen by a pre-trained kit

## Usage

``` r
replay_season_holdout(
  kit,
  allD,
  season = "2025-26",
  runner = run_prospective_pipeline,
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

- ...:

  Additional runner arguments.

## Value

Replay predictions, standardized metrics, and explicit workflow fields.
The holdout is not eligible to join training until separately compared
with an incumbent using check_promotion().
