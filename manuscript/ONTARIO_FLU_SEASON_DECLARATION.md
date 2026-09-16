# Ontario influenza season declaration

- Declaration version: 1.1
- Freeze date: 2026-09-01
- Applies to: the new fully nested Ontario influenza manuscript analysis
- Governing record: [`GOVERNANCE_DECISIONS.md`](GOVERNANCE_DECISIONS.md)

## Fixed season universe

The principal analysis uses all 11 seasons remaining after the four fixed
exclusions:

1. `2012-13`
2. `2013-14`
3. `2014-15`
4. `2016-17`
5. `2017-18`
6. `2018-19`
7. `2019-20`
8. `2022-23`
9. `2023-24`
10. `2024-25`
11. `2025-26`

No additional influenza season may enter this protocol version. In particular,
the analysis will not retrieve or append an earlier season, a later season, or
a newly available season to increase precision.

## Declared non-principal seasons

| Season | Declaration | Manuscript use |
|---|---|---|
| `2011-12` | Current data-contract exclusion | Not fitted, tuned, or scored in the principal aggregate |
| `2015-16` | Current workflow exclusion and special ignition/drop-test cycle | Separately labelled diagnostic evidence only; never pooled into the principal aggregate |
| `2020-21` | Pandemic-era data-contract exclusion | Not fitted, tuned, or scored in the principal aggregate |
| `2021-22` | Pandemic-era data-contract exclusion | Not fitted, tuned, or scored in the principal aggregate |

## Outer-replay design

Each of the 11 valid seasons is held out once. For outer fold `F`, the other 10
valid seasons form the only permissible fitting and inner-tuning
universe. The fold season is absent from:

- M0, M1, and M2 fitting and hyperparameter selection;
- reference curves, templates, scaling, imputation, and analogue libraries;
- `manual_labels_train` and any downstream label-derived feature; and
- boundary expansion, stopping, and model-choice decisions.

The held-out fold is replayed prospectively using one frozen fold-specific kit.
Its retrospective reference label is joined only after M0 predictions exist for
scoring.

## Executable declaration

```r
principal_seasons <- c(
  "2012-13", "2013-14", "2014-15", "2016-17", "2017-18",
  "2018-19", "2019-20", "2022-23", "2023-24", "2024-25",
  "2025-26"
)

workflow_exclusions <- c("2011-12", "2015-16", "2020-21", "2021-22")
outer_fold <- "2012-13" # repeat once for each principal season

selection <- validate_season_selection(
  allD,
  training_seasons = setdiff(principal_seasons, outer_fold),
  exclude_seasons = workflow_exclusions,
  holdout_seasons = outer_fold,
  application_seasons = character()
)
```

The analysis runner constructs this selection once for every value of
`outer_fold`. Thus any valid season can be the holdout, and every non-held-out
valid season enters training equally. The earlier `2025-26` acceptance replay
is still reported separately because it used a different lineage; the new
outer-fold score is part of the equal 11-fold retrospective analysis but is not
described as untouched confirmation.

## Preflight assertions

Before fitting, the authorized current influenza input must satisfy all of the
following without importing new observations:

1. every declared season identifier exists exactly once in the normalized
   season set;
2. no undeclared season is automatically admitted to training;
3. the valid and excluded sets are disjoint;
4. every outer fold contains exactly 10 fitting seasons and one unseen replay
   season;
5. the input hash and row counts by season are recorded in the immutable
   analysis manifest; and
6. any mismatch stops the run for disposition instead of changing this list.

The private influenza CSV was not available in the present manuscript-planning
workspace, so this declaration freezes membership from current API defaults and
audited artifact metadata rather than claiming a new row-level data audit.
