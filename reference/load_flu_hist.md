# Load historical influenza surveillance data

Reads a user-supplied historical surveillance CSV. Resolution order is:
explicit `path`, the `PAGE_FLU_HIST_FILE` environment variable, then a
bundled `inst/extdata/flu_hist.csv` if a future distribution provides
one. PAGe does not currently distribute surveillance observations.

## Usage

``` r
load_flu_hist(path = NULL)
```

## Arguments

- path:

  Optional path to a historical surveillance CSV.

## Value

A data frame containing the CSV fields.

## See also

\[prepare_surveillance_data()\] for normalization and validation.
