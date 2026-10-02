# Build the manuscript per-row export from the scheduled replay ledger

Retains every scheduled origin/horizon, including rows whose forecast
was unavailable, and carries
\`forecast_available\`/\`unavailable_reason\` so the missing-forecast
accounting is not lost. Returns \`NULL\` when the replay has no ledger
(synthetic callers), so callers fall back to matched rows.

## Usage

``` r
.nested_ledger_export(replay, data, timing_labels = NULL)
```
