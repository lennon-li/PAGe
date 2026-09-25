# Expert Decimal Timing Labeling Workflow

This workflow is for retrospective annotation of the 11 historical seasons under `page-continuous-week-v1`.

## 1. Prepare canonical surveillance data

The data supplied to the review functions must satisfy the PAGe surveillance contract:

```text
season
weekF
y
N
p
```

`prepare_surveillance_data()` or `prepare_page_data()` can be used upstream.

## 2. Generate one Plotly review per season

```r
reviews <- review_expert_timing_set(hist_data)

reviews[["2022-23"]]$plot
```

The plot shows observed weekly positivity only. It does not infer ignition or peak truth.

For a single season:

```r
review <- review_expert_timing(hist_data, season = "2022-23")
review$plot
```

## 3. Enter expert decimal values explicitly

After visual review, create the annotation numerically:

```r
label_2022_23 <- finalize_expert_timing_review(
  review,
  ignition_week_decimal = 18.4,
  peak_week_decimal = 27.2,
  annotator = "<annotator-id>",
  annotation_version = "labels-v1-pass1",
  positivity_version = "<positivity-version>",
  peak_status = "clear"
)
```

Values are preserved exactly. They are not converted through legacy integer-pair timing labels.

For an uncertain peak:

```r
label <- finalize_expert_timing_review(
  review,
  ignition_week_decimal = 18.4,
  peak_week_decimal = 27.2,
  ignition_interval = c(18.1, 18.8),
  peak_interval = c(26.8, 27.6),
  peak_status = "uncertain",
  annotator = "<annotator-id>",
  annotation_version = "labels-v1-pass1",
  positivity_version = "<positivity-version>"
)
```

For a genuinely unlabelable primary peak, use `peak_status = "unlabelable"`, set the point to `NA_real_`, and document the reason in `comment`.

## 4. Optional blank annotation sheet

```r
sheet <- expert_timing_annotation_sheet(
  hist_data,
  annotator = "<annotator-id>",
  annotation_version = "labels-v1-pass1",
  positivity_version = "<positivity-version>"
)
```

This creates one blank numeric row per season with data snapshot hashes already populated. The sheet is for manual entry only; it does not generate candidate labels.

## 5. Save a versioned release

```r
write_expert_timing_annotations(
  annotations = list(label_2014_15, label_2015_16, label_2022_23),
  path = "annotations/expert-timing-labels-v1-pass1.csv"
)
```

The writer refuses to overwrite an existing release unless `overwrite = TRUE` is supplied explicitly. Prefer a new versioned path rather than overwriting a prior annotation release.

## 6. Second pass

Repeat all 11 seasons later under a distinct version, for example:

```text
labels-v1-pass2
```

Do not display pass-1 values while performing pass 2. Compare passes only after the second pass is complete.

## 7. Do not use these labels at runtime

Expert ignition `I*` and peak `T*` are retrospective truth/evaluation data. They must never be supplied as held-out runtime features.

The deployed M1 activation landmark is causal M0 detection `A`, which will be generated later by season-excluded replay.
