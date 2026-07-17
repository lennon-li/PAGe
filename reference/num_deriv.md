# Numerical central-difference derivative

Approximates the derivative of `f` at `x` using a symmetric two-point
central-difference formula.

## Usage

``` r
num_deriv(x, f, eps = 0.001)
```

## Arguments

- x:

  Numeric scalar at which to evaluate the derivative.

- f:

  A function of a single numeric argument.

- eps:

  Numeric step size (default `1e-3`).

## Value

A numeric scalar approximating the derivative of f at x.
