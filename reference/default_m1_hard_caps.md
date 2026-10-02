# Return the governed M1 hard-cap defaults

The reference basis cap is an explicit complexity policy, separate from
the 52-week support domain. Callers may override it deliberately, but
all governed entry points use this object when no override is supplied.

## Usage

``` r
default_m1_hard_caps()
```

## Value

A named list of normalized lower/upper bounds.
