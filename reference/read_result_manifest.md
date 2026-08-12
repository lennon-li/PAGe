# Read a PAGe result manifest

Reads a canonical disclosure-safe result manifest from JSON or RDS and
validates its schema before returning it.

## Usage

``` r
read_result_manifest(path)
```

## Arguments

- path:

  Path to a manifest with a `.json` or `.rds` extension.

## Value

A validated `page_result_manifest` object.
