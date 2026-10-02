# Construct governed M1-v2 activations from an M0 LOSO result

Converts the held-out detections from \`loso_M0v2()\` into the only
activation table accepted by governed M1-v2 training. Fold identities,
held-out season names, detection values, and the M0 LOSO context
identity are validated and bound into a deterministic provenance ID.

## Usage

``` r
m1_v2_activation_table_from_m0_loso(m0_loso)
```

## Arguments

- m0_loso:

  Result returned by \`loso_M0v2()\`.

## Value

A \`page_m1_v2_activation_table\` data frame.
