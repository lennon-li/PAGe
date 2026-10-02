# Convert timing-v2 labels to the M0/M1 training label contract

Extracts the earlier ignition week from one timing-v2 label object or a
list of objects. The normalized pair and peak labels remain available on
the original objects; this adapter supplies only the scalar ignition
vector expected by the existing leakage-safe M0/M1 training functions.

## Usage

``` r
as_manual_labels_v2(labels)
```

## Arguments

- labels:

  A `page_season_timing_v2` or `page_timing_labels_v2` object, or a list
  of those objects.

## Value

A named integer vector mapping season to the earlier ignition week.
