# Train the PAGe forecasting system

Stable entry point for governed PAGe training. This wraps the production
training workflow while hiding stage-specific tuning/build/freeze
helpers.

## Usage

``` r
page_train(...)
```

## Arguments

- ...:

  Additional named arguments passed to \[train_pipeline()\].

## Value

A governed PAGe training workflow result.
