# Write a PAGe result manifest

Validates and writes a canonical result manifest as JSON or RDS.
Existing files are immutable by default and are never replaced unless
`overwrite = TRUE` is explicit.

## Usage

``` r
write_result_manifest(manifest, path, overwrite = FALSE)
```

## Arguments

- manifest:

  A manifest created by \[new_result_manifest()\].

- path:

  Destination path with a `.json` or `.rds` extension.

- overwrite:

  Whether to replace an existing file. Defaults to `FALSE`.

## Value

Invisibly, the normalized path to the written manifest.
