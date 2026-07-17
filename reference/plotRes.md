# Plot alignment results against history and reference curve

Produces two plotly panels for a fitted alignment: one overlaying
historical-season curves with the current fit, and one overlaying the
reference curve on the current-season date axis. Intended for
interactive inspection of a single-season result.

## Usage

``` r
plotRes(res, seasonIndex = NULL, peakInfo = NULL, currentSeason = NULL)
```

## Arguments

- res:

  List returned by the alignment pipeline; must contain \`pred_df\`,
  \`last_obs\`, \`peak\`, \`tau\`, and \`delta\`.

- seasonIndex:

  Optional integer length-2 vector giving the start and end \`newWeek\`
  of the in-season window to annotate.

- peakInfo:

  Optional list with a \`flag_week\` element; currently unused (retained
  for API parity).

- currentSeason:

  Data frame for the current season with columns \`date\`, \`weekF\`,
  \`newWeek\`, and \`p\` (observed positivity).

## Value

A named list with \`hist\`, \`ref\` (both plotly objects), and \`data\`
(the joined data frame used to draw them).
