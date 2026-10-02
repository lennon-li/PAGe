# Generate a shadow-only PAGe v3 two-pathogen forecast

Runs the canonical weekF12 PAGe v3 model bundle shipped with the
package. The runtime is self-contained after package installation: no
repository scripts, external model directories, or shell services are
required.

## Usage

``` r
page_v3_forecast(data, season = NULL, origin_weekF = NULL, strict = TRUE)
```

## Arguments

- data:

  Canonical typed A/B panel, OLIS \`.RData\` path containing
  \`r\$fluA\`/\`r\$fluB\`, or a local ORVT CSV path.

- season:

  Optional season label. Required for ORVT CSV paths and when an OLIS
  snapshot spans more than one season.

- origin_weekF:

  Optional forecast origin. Defaults to the latest week.

- strict:

  When \`TRUE\`, supplied positivity columns must agree exactly (within
  numerical tolerance) with the supplied positive/test counts.

## Value

An object of class \`page_v3_forecast\`.
