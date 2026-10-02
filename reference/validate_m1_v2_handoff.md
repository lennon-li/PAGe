# Validate the M1-v2 to M2 handoff contract

Validates the versioned timing-state object emitted by
\`run_m1_v2_timing()\`. This contract is intentionally independent of
the current legacy M2 feature path so the redesigned M2 can adopt it
without changing M1 semantics.

## Usage

``` r
validate_m1_v2_handoff(x)
```

## Arguments

- x:

  M1-v2 handoff list.

## Value

\`x\`, invisibly, if valid.
