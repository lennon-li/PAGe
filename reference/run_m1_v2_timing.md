# Run the redesigned M1-v2 timing stage

Runs M1-v2 sequentially from the locked M0 activation origin through the
latest observed week. M1-F future timing, calibrated reporting
summaries, M1-C passage probability, and passage confirmation remain
separate. After passage is confirmed, a peak estimate from the
unconditioned passage posterior is locked and carried forward.

## Usage

``` r
run_m1_v2_timing(kit, current_data, m0_result, verbose = TRUE)
```

## Arguments

- kit:

  PAGe deployment kit containing optional \`m1_v2\` artifact.

- current_data:

  Current-season surveillance data.

- m0_result:

  Output of \`run_m0_detection()\`.

- verbose:

  Emit progress messages.

## Value

A list with \`status\`, sequential \`timing_df\`, \`m2_handoff\`, and
the carried \`m0_result\`.

## Details

This stage does not replace the legacy M1 alignment curves currently
used by M2. Instead it emits an explicit \`m2_handoff\` for the
redesigned M2 path.
