# Construct a disclosure-safe result manifest

The manifest records aggregate provenance only. It must not contain
row-level predictions or surveillance data.

## Usage

``` r
new_result_manifest(
  artifact_role,
  classification,
  code_commit,
  run_timestamp,
  r_version,
  package_versions,
  input_fingerprint,
  seasons,
  exclusions,
  row_counts,
  spec_id,
  training_seasons,
  source_artifact_hashes,
  fold_ids,
  evaluation_seasons
)
```

## Arguments

- artifact_role:

  Role of the aggregate result artifact.

- classification:

  Disclosure classification; currently must be \`"disclosure_safe"\`.

- code_commit:

  Git commit hash for the code used in the run.

- run_timestamp:

  ISO-8601 run timestamp with timezone.

- r_version:

  R version used for the run.

- package_versions:

  Named package-version vector.

- input_fingerprint:

  SHA-256 fingerprint of the declared input set.

- seasons, exclusions:

  Included seasons and exclusions (\`"none"\` if none).

- row_counts:

  Named aggregate row counts.

- spec_id:

  Model specification identifier.

- training_seasons:

  Training seasons.

- source_artifact_hashes:

  Named SHA-256 hashes of source artifacts.

- fold_ids, evaluation_seasons:

  Fold identifiers and evaluation seasons.

## Value

A validated \`page_result_manifest\` object.
