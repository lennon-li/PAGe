# Save versioned expert ignition annotations

Save versioned expert ignition annotations

## Usage

``` r
write_expert_ignition_annotations(annotations, path, overwrite = FALSE)
```

## Arguments

- annotations:

  One or more `page_expert_ignition_annotation_v2` objects.

- path:

  Output CSV path.

- overwrite:

  Logical; when `FALSE` (default), refuse to replace an existing
  annotation release.

## Value

Invisibly, the normalized output path.
