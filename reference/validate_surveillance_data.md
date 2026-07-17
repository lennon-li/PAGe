# Validate canonical PAGe surveillance data

Checks the complete canonical surveillance schema without deriving
missing columns. Use
[`prepare_surveillance_data()`](https://lennon-li.github.io/PAGe/reference/prepare_surveillance_data.md)
first for partial inputs.

## Usage

``` r
validate_surveillance_data(data, tolerance = 1e-08)
```

## Arguments

- data:

  A data frame containing weekly surveillance observations.

- tolerance:

  Numeric tolerance for redundant count and positivity consistency
  checks.

## Value

The validated data frame, unchanged apart from safe canonical type
normalization.
