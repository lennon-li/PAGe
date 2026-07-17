# Negative log-likelihood for tau/delta alignment

Binomial negative log-likelihood for the time-alignment model \`logit(p)
= a + b \* g(u)\` with \`u = (t - tau) / (1 + delta)\`, with an optional
ridge penalty on \`delta\`. Used as the objective inside the nonlinear
optimiser in \[align_forecast_pipeline_dilate()\].

## Usage

``` r
negloglik_tau_delta(par, t, y, n, gfun, allow_scale = TRUE, lam = 0.1, w = n)
```

## Arguments

- par:

  Numeric vector of parameters. When \`allow_scale = TRUE\`: \`c(tau, a,
  b, delta)\`; otherwise \`c(tau, a, delta)\` with \`b\` fixed to 1.

- t:

  Numeric vector of observation times (\`newWeek\`).

- y:

  Integer vector of weekly positive counts.

- n:

  Integer vector of weekly total tests.

- gfun:

  Reference curve function on the logit scale.

- allow_scale:

  Logical; if \`TRUE\`, estimate slope \`b\` (default \`TRUE\`).

- lam:

  Ridge penalty on \`delta^2\` (default \`0.1\`).

- w:

  Numeric vector of per-observation weights (default \`n\`, i.e. weight
  by total tests).

## Value

A numeric scalar; the penalised binomial negative log-likelihood.
