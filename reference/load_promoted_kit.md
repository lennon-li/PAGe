# Load a promoted PAGe deployment kit

Loads a deployment kit only after its disclosure-safe promotion
manifest, artifact fingerprint, selected specification, training
seasons, and runtime structure have all been verified.

## Usage

``` r
load_promoted_kit(kit_path, deployment_manifest_path)
```

## Arguments

- kit_path:

  Path to an RDS file containing a PAGe kit or a `page_training_result`
  with a `kit` field.

- deployment_manifest_path:

  Path to the corresponding canonical result manifest.

## Value

A kit validated by \[validate_page_kit()\] in frozen mode.
