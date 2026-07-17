# Migrates user-installed R packages from an old R version to the current (new) R version.

Orchestrates the complete two-step migration (save list from old R, then
install in new R) sequentially in a single execution of a generated
batch file. Includes error logging.

## Usage

``` r
migrate_r_packages(old_r_home = NULL)
```

## Arguments

- old_r_home:

  Optional string. The full path to the root folder of the OLD R
  installation (e.g., "C:/Program Files/R/R-4.2.3"). If missing or
  invalid, a GUI browser will open to select the path.

## Value

Invisible NULL. The function executes the migration externally.
