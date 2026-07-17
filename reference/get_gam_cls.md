# Extract a classifier GAM from various container objects

Convenience helper that accepts either:

- an mgcv `gam`/`bam` object;

- a `gamm4` fit list with component `$gam`;

- a list returned by your
  [`fitIgnition()`](https://lennon-li.github.io/PAGe/reference/fitIgnition.md)
  that contains `$fits$p_only_week_p$gam`.

## Usage

``` r
get_gam_cls(ign_fit_or_gam)
```

## Arguments

- ign_fit_or_gam:

  A trained classifier model or a container holding one.

## Value

An mgcv `gam` or `bam` object.

## Examples

``` r
if (FALSE) { # \dontrun{
gam_cls <- get_gam_cls(ign_fit)                        # fitIgnition() output
gam_cls <- get_gam_cls(ign_fit$fits$p_only_week_p$gam) # direct
} # }
```
