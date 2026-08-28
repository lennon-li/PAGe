# Compact a complete M0 artifact for the M1 handoff

M1 needs the aligned M0 output, detector parameters, and the label/flag
contract. It does not need the M0 tuning grid, fold scores, or other
provenance payloads. The complete M0 artifact remains available
separately for audit; this projection is safe to pass into the next
stage.

## Usage

``` r
compact_m0_artifact_for_m1(m0)
```

## Arguments

- m0:

  Complete M0 artifact from
  [`build_m0()`](https://lennon-li.github.io/PAGe/reference/build_m0.md),
  [`tune_m0()`](https://lennon-li.github.io/PAGe/reference/tune_m0.md),
  or a governed frozen M0 fit.

## Value

A named list containing the M1-required M0 fields and its optional data
identity. `aligned` may be `NULL` for legacy minimal inputs, in which
case
[`build_m1()`](https://lennon-li.github.io/PAGe/reference/build_m1.md)
rebuilds the alignment rather than silently using an incomplete handoff.
