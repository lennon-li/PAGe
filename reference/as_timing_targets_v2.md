# Extract fractional timing targets from timing-v2 labels

This is the opt-in adapter for the fractional pipeline. Ignition targets
are the midpoint of the normalized pair. Peak targets are the observed
peak week selected during review; the second adjacent peak label is kept
in the returned table for uncertainty and provenance.

## Usage

``` r
as_timing_targets_v2(labels)
```

## Arguments

- labels:

  A timing-v2 label object or list of objects.

## Value

A data frame with one row per season and numeric ignition and peak
targets, normalized pairs, and second-label provenance.
