# Validate a PAGe deployment kit

Checks the in-memory artifacts required by the prospective runtime.
Frozen forecasting requires no historical-data files. Weekly refitting
additionally requires historical aligned data and a template data frame.

## Usage

``` r
validate_page_kit(kit, mode = c("frozen", "weekly_refit"))
```

## Arguments

- kit:

  A kit returned by
  [`assemble_kit()`](https://lennon-li.github.io/PAGe/reference/assemble_kit.md)
  or
  [`load_prospective_kit()`](https://lennon-li.github.io/PAGe/reference/load_prospective_kit.md).

- mode:

  Runtime mode: `"frozen"` or `"weekly_refit"`.

## Value

The validated kit.
