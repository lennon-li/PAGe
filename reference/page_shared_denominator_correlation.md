# Multinomial correlation for mutually exclusive shared-denominator strata

Constructs the response-scale correlation matrix implied when multiple
mutually exclusive categories are counted out of the same denominator.
For strata \`i != j\`, \`rho_ij = -sqrt(p_i p_j / ((1-p_i)(1-p_j)))\`.

## Usage

``` r
page_shared_denominator_correlation(p, tolerance = 1e-10)
```

## Arguments

- p:

  Named or unnamed vector of category probabilities.

- tolerance:

  Numerical tolerance used to validate that the categories can coexist
  in a multinomial partition (\`sum(p) \<= 1 + tolerance\`).

## Value

A correlation matrix with the same stratum names as \`p\`.
