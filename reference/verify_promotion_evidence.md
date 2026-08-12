# Verify Artifact-Bound Holdout Promotion Evidence

Verifies a saved acceptance decision bundle and disclosure-safe manifest
against the authorized data, candidate kit, incumbent kit, and decision
bundle files that they bind by SHA-256. Only a passing promotion report
using PAGe's locked thresholds can produce release evidence.

## Usage

``` r
verify_promotion_evidence(
  bundle,
  manifest,
  data_path,
  candidate_path,
  incumbent_path,
  bundle_path,
  holdout_season = "2025-26",
  kit_compatibility = c("strict", "legacy_m2")
)
```

## Arguments

- bundle:

  Saved `page_holdout_decision_bundle` object.

- manifest:

  Validated disclosure-safe acceptance result manifest.

- data_path:

  Path to the authorized surveillance data artifact.

- candidate_path:

  Path to the evaluated candidate kit artifact.

- incumbent_path:

  Path to the evaluated incumbent kit artifact.

- bundle_path:

  Path to the saved decision bundle artifact.

- holdout_season:

  Expected holdout season.

- kit_compatibility:

  Identity mode for the incumbent kit. The default `"strict"` requires
  `m2_production`; `"legacy_m2"` explicitly permits a legacy `m2` field
  with a warning. The candidate kit must always use the canonical
  identity.

## Value

A `page_verified_promotion_evidence` object accepted by
[`train_pipeline()`](https://lennon-li.github.io/PAGe/reference/train_pipeline.md)
for holdout release.

## Details

The returned S3 class is a transport marker, not a cryptographic
capability: R classes can be forged. The artifact reads and SHA-256
checks performed by this function are the safety boundary. Governed
workflows should construct the object immediately before calling
[`train_pipeline()`](https://lennon-li.github.io/PAGe/reference/train_pipeline.md)
and retain the verified artifacts.
