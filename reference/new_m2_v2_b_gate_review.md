# Bind a reviewed B timing gate decision document

The JSON decision record must contain \`status = "reviewed_open"\`, the
exact gate policy version, a nonempty \`review_id\`, and \`decision =
"open"\`.

## Usage

``` r
new_m2_v2_b_gate_review(review_path)
```

## Arguments

- review_path:

  Path to the immutable JSON review decision.

## Value

A hash-bound B gate review object.
