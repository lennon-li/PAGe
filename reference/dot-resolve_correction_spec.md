# Resolve the M2 online-bias correction configuration

Internal canonical resolver. Production and frozen LOSO must use this
function so the structural rates and adaptive rule cannot drift apart.

## Usage

``` r
.resolve_correction_spec(
  spec,
  compatibility = c("strict", "legacy"),
  bias_alpha = NULL,
  bias_beta = NULL
)
```
