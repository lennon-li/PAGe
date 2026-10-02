# Interactively review and label seasonal ignition weeks

Presents each requested season using \[review_expert_ignition()\] and
records one decimal ignition week per season. In an interactive R
session, the plot is printed before prompting with \[readline()\]. For
reproducible pipelines, supply a named numeric \`ignition_weeks\` vector
and no prompt is used.

## Usage

``` r
page_label_ignitions(
  data,
  ignition_weeks = NULL,
  seasons = NULL,
  annotator = NULL,
  annotation_version = "expert-ignition-v1",
  positivity_version = "positivity-v1",
  interactive = base::interactive(),
  show_counts = TRUE,
  comments = NULL
)
```

## Arguments

- data:

  Multi-season surveillance data accepted by
  \[prepare_surveillance_data()\].

- ignition_weeks:

  Optional named numeric vector of decimal ignition weekF values. Names
  must be season labels.

- seasons:

  Optional character vector selecting seasons to review. Defaults to
  every season in \`data\`.

- annotator:

  Non-empty annotator identifier. Defaults to the current OS user when
  available.

- annotation_version:

  Version string stored with every expert annotation.

- positivity_version:

  Version string describing the positivity definition.

- interactive:

  Logical. When \`TRUE\` and \`ignition_weeks\` is absent, print each
  review plot and prompt for the decimal ignition week.

- show_counts:

  Include positive/test counts in plot hover text.

- comments:

  Optional named character vector of per-season comments.

## Value

A \`page_ignition_label_set\` containing expert annotations, their flat
table, integer training labels, reviews, and provenance.

## Details

Decimal week coordinates follow PAGe's continuous-week convention:
integer week \`w\` denotes the interval \`\[w, w + 1)\`. The returned
expert annotation preserves the decimal value; \`manual_labels\` uses
\`floor()\` to project that value onto the existing integer M0/M1
training contract.
