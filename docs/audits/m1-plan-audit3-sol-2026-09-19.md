# Final confirmation audit of the M1 retune plan, rev 3

Date: 2026-09-19

## 1. Rev-2 blocking items

1. **NOT CLOSED.** `H`, `rho`, and the peak-side Gate B thresholds are now
   fixed, but the forecast side says only “the same two checks”: it neither
   identifies the two checks nor defines their thresholds or variance
   contribution. Gate B is still not deterministically implementable.

2. **NOT CLOSED.** Ties, gaps, non-finite neighbours, concavity, and large
   label/fallback discrepancies are handled. However, no rule sends an
   *unlabelled* season to the bimodal/shoulder review; “flagged as bimodal by
   the review” presupposes a review for which no trigger is specified.

3. **NOT CLOSED.** The numeric limits are frozen, but the complete passage
   rule is still deferred to later calibration rather than specified. The
   persistence-baseline substitution is prescribed, but it is not a penalty:
   it can improve MAE when persistence happens to beat the candidate, contrary
   to the plan's claim.

4. **CLOSED.** Raw and clamped predictions and clamp activation are stored;
   M1 is scored raw; and M2 receives the clamped logit in fit, evaluation, and
   runtime.

5. **CLOSED.** Each outer split explicitly repeats stage sizing, refinement,
   boundary expansion, and tie-breaking using only its training seasons.

## 2. Frozen constants

Two anchors are wrong under Rev 3's own objective. `peak_incumbent = 0.198`
reproduces exactly only against the old integer raw argmax; using Rev 3's
parabolic fallback gives **0.2194** before any human labels are substituted.
`mae_incumbent = 9.35 pp` is pooled complete-case MAE; the declared
season/horizon-balanced complete-case value is **9.253 pp**, and applying the
stated persistence substitution to the 693 truth-available rows gives about
**8.660 pp**. Moreover, 58/693 truth-available rows lack an M1 forecast, so the
incumbent itself exceeds the 5% rule.

`H = 8` is defensible, but its cited truncation claim is false: under the same
raw peaks used for the reported `0.198`, it truncates 2016-17 (lead 9) as well
as 2017-18 and 2018-19. No material contradiction was found for `kappa = 1`,
`rho = 1`, either utility scale, the two passage limits, or the 1.5-week review
trigger.

## 3. Lead-time non-monotonicity

The table reproduces exactly from the legacy cross-fitted rows **against raw
integer argmax truth**, including bucket sizes 8--22. It is not the Rev 3
truth: with the parabolic fallback, the within-one-week rates are 13.6%,
18.2%, 23.8%, 15.4%, and 0%, with bucket sizes 22, 22, 21, 13, and 12. Thus a
weaker non-monotone pattern remains, but the quoted 4.5%/30.0%/0% contrast does
not survive the plan's own fallback, and human-label results are not yet known.

This does not change the staged recommendation; it reinforces the existing
Stage 1/Stage 3 diagnostics. The rows came from the legacy construction with
`LAMBDA_DELTA = 164672.9` and effectively zero dilation, so the finding is
construction-specific, but no corrected-lambda counterfactual establishes
that the bug caused the non-monotonicity.

## 4. New defects in rev 3

- Both incumbent anchors were frozen from metrics that Rev 3 supersedes.
- The missing-row substitution can reward failure, while target-unavailable
  rows are not separated from spec-caused failures in the 5% denominator.
- The forecast-side Gate B checks and the unlabelled bimodality review are not
  executable as written.
- The new lead-time table is presented without disclosing that it uses the
  rejected raw-argmax truth.

## 5. Verdict

**No. Rev 3 is not fit to hand to an implementer.** Blocking items only:

1. Freeze the complete passage rule, not only its acceptance limits.
2. Finalize the peak truths and recompute both incumbent anchors under the
   exact Rev 3 scoring and missingness rules.
3. Define a non-rewarding failure contribution and a denominator that
   separates structurally missing truth from spec-caused failure.
4. Make the forecast-side Gate B checks and unlabelled bimodality review fully
   deterministic.
