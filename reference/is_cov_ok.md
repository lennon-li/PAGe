# Check whether a covariance matrix is valid

Returns `TRUE` only if `V` is a finite, square, positive-definite matrix
with a positive determinant. Used to guard downstream delta-method
calculations.

## Usage

``` r
is_cov_ok(V)
```

## Arguments

- V:

  Object to test.

## Value

Logical scalar.
