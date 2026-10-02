# Pre-verified historical manual ignition labels

Returns the named integer vector of manually-verified ignition weekF
values for historical flu seasons. Pass this to
`flagIgnition(manual_labels = ...)` to bypass algorithmic detection for
known seasons.

## Usage

``` r
page_manual_ignition_labels()
```

## Value

Named integer vector mapping season labels (e.g. `"2015-16"`) to
ignition weekF integer values.

## Details

These labels are retrospective and must never be supplied for a held-out
LOSO test season (use `manual_labels_test = NULL` in LOSO eval paths).

## Examples

``` r
page_manual_ignition_labels()
#> Error in page_manual_ignition_labels(): could not find function "page_manual_ignition_labels"
```
