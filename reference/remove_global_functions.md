# Remove all functions from the global environment

Lists every object in `.GlobalEnv` and removes any that are functions.
Intended for sourced-script cleanup. Calls
[`gc()`](https://rdrr.io/r/base/gc.html) before returning.

## Usage

``` r
remove_global_functions()
```

## Value

`invisible(NULL)`.
