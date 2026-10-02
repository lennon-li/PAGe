# Detect ignition with an opt-in fractional week estimate

Runs the existing prospective M0 detector and interpolates the first
adjacent classifier-probability crossing of the class threshold. Weekly
observations and the legacy integer estimate are retained; the decimal
estimate is in `iWeek_hatF`.

## Usage

``` r
detectIgnitionBySeason_M0v2_timing(ign_fit, params, ...)
```

## Arguments

- ign_fit:

  Data frame, data.table, or fitIgnition result.

- params:

  M0 detector parameters.

- ...:

  Arguments passed to
  [`detectIgnitionBySeason_M0v2()`](https://lennon-li.github.io/PAGe/reference/detectIgnitionBySeason_M0v2.md).

## Value

The detector result with numeric timing columns and provenance.
