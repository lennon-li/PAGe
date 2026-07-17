# Summarise the peak of an aligned seasonal fit

Given a fitted alignment (shift \`tau\`, dilation \`delta\`, intercept
\`a\`, slope \`b\`) and the reference template function, computes the
peak week on the surveillance time axis together with a delta-method
confidence interval, and the peak probability with its interval on the
link scale.

## Usage

``` r
peak_summary_from_fit(fit_obj, g_ref_fun, V_ab, V_td, level = 0.95)
```

## Arguments

- fit_obj:

  List containing numeric scalars \`tau\`, \`delta\`, \`a\`, \`b\`.

- g_ref_fun:

  Reference curve on the logit scale; a function of \`u\`.

- V_ab:

  2x2 covariance matrix for \`(a, b)\`.

- V_td:

  2x2 covariance matrix for \`(tau, delta)\`.

- level:

  Confidence level for the intervals (default \`0.95\`).

## Value

A list with elements \`u_star\`, \`t_peak\`, \`t_peak_ci\`, \`p_peak\`,
\`p_peak_ci\`.
