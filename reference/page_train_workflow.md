# Label ignition, train PAGe, and return a deployable frozen kit

This convenience workflow deliberately reuses \[train_pipeline()\]
rather than implementing a separate trainer. If labels are absent, it
first calls \[page_label_ignitions()\]. Only expert ignition timing is
requested; this wrapper does not fabricate peak labels. The current
training pipeline is therefore invoked with its legacy integer timing
interface, while the full decimal expert annotations remain attached for
provenance.

## Usage

``` r
page_train_workflow(
  data,
  labels = NULL,
  ignition_weeks = NULL,
  mode = c("refresh", "retune"),
  annotator = NULL,
  interactive = base::interactive(),
  prospective_holdout = NULL,
  exclude = character(),
  n_cores = max(1L, parallel::detectCores() - 1L),
  checkpoint_dir = NULL,
  verbose = TRUE,
  ...
)
```

## Arguments

- data:

  Multi-season surveillance data.

- labels:

  Optional \`page_ignition_label_set\` or expert annotation list.

- ignition_weeks:

  Optional reproducible named decimal ignition vector used when
  \`labels\` is absent.

- mode:

  Training mode passed to \[train_pipeline()\].

- annotator, interactive:

  Passed to \[page_label_ignitions()\].

- prospective_holdout:

  Optional season kept out of fitting. \`NULL\` trains on all otherwise
  eligible seasons; a prospective holdout is recommended for governed
  model development.

- exclude:

  Seasons excluded from training.

- n_cores, checkpoint_dir, verbose:

  Passed to \[train_pipeline()\].

- ...:

  Additional named arguments passed to \[train_pipeline()\].

## Value

A \`page_training_workflow\` with labels, training result, and frozen
kit.
