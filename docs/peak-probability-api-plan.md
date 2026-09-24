# Peak timing probability API plan

## User question

Given a forecast origin and week `X`, answer `P(season peak week < X)` or,
explicitly, `P(season peak week <= X)`. A week is on PAGe's canonical `weekF`
scale, with the applicable season length recorded in the result.

## Contract

- Add the model-agnostic S3 generic `peak_week_distribution(forecast, ...)`.
- A model method returns the existing `page_predictive_distribution` type, with
  `outcome = "season_peak_week"`, `scale = "weekF"`, and origin/season and
  model provenance. A backend can return `status = "unavailable"` if it has no
  defensible peak uncertainty representation.
- Add `probability_peak_before(forecast_or_distribution, week,
  inclusive = FALSE, ...)`. Strict is `< week`; `inclusive = TRUE` means
  `<= week`. Weighted peak probabilities are exact; their `mc_se` and
  `mc_interval` are `NA` because no Monte Carlo approximation is used.
- The first PAGe adapter uses the latest M1 origin in a `page_forecast` by
  default; if that latest origin failed, it returns `unavailable` instead of
  quietly reusing an older successful week. Callers may request a specific
  `origin_week` explicitly.
- The M1 result preserves the valid peak atoms and their **renormalized peak
  weights** (the same subset and weights that generated its weighted peak
  summary), not the all-template softmax weights. The adapter maps each peak to
  `weekF` using that origin's ignition estimate, the stored reference anchor,
  season length, and timing mode. Legacy integer mode applies PAGe's existing
  `round()` rule; fractional mode retains decimal weeks.
- In legacy mode, atoms that round to the same weekF are merged. `n_atoms`
  counts distinct positive-weight weekF values after conversion, and
  `effective_n` is the Kish effective count `1 / sum(w^2)` after merging and
  renormalizing.
- The generic distribution object gains optional normalized atom weights.
  CDF, quantiles, and threshold probabilities use exact weighted empirical
  calculations when weights are supplied. There is no Monte Carlo sampling or
  Monte Carlo error interval for this adapter. Weighted quantiles use the
  left-continuous inverse weighted empirical CDF, so the returned quantile is
  an atom and is consistent with the reported CDF.
- The output is labelled `experimental`: this represents between-template
  spread from ensemble weights tuned for point alignment, not posterior
  probabilities. It is not a calibrated probability for the realized
  surveillance peak, and initially excludes within-template fit uncertainty
  and observation-process uncertainty. `t_peak_ci` endpoints are not treated
  as draws. A later calibrated adapter requires strictly out-of-sample
  peak-week errors evaluated by season. The target for that work is the
  integer weekF of maximum observed positivity, with the earliest week winning
  ties.

## Runtime changes

1. Preserve the valid template peak atoms, template labels, and normalized
   `pk_wts` from the ensemble summary calculation. Do not use raw `res$weights`;
   it includes templates excluded from the peak summary. Compute `wts`
   independently of whether future forecast rows exist, since peak summaries
   are also needed at season end.
2. Carry a separate per-origin peak ensemble table in `page_forecast`, keyed by
   `eval_week`, including `iWeek_hat`, `anchorWeek`, `nW_true`, `timing_mode`,
   status, and fallback reason. Pre-change forecast objects lack this contract
   and return unavailable.
3. Return unavailable for the single-reference fallback and when fewer than
   two positive-weight valid peaks remain or the Kish effective count is below
   2. `n_atoms` counts distinct positive-weight weekF values after conversion;
   `effective_n = 1 / sum(w^2)` is computed after merged weights are
   renormalized.
   Drop out-of-support atoms, renormalize remaining weights, and record dropped
   probability mass; return unavailable if none remain. Document that dropping
   out-of-season mass can bias the conditional probability earlier. Reject
   malformed weights and missing season identity with clear errors/status.
4. A distribution carries the exact atoms and normalized weights. Record
   `target`, season length, atom count, effective atom count, dropped mass,
   origin week, latest input week, timing mode, and rounding rule in metadata.
   Flag threshold weeks at/before the origin as partly observed; the current
   M1 peak atoms do not condition on the observed maximum. Attach the dropped
   mass and partly-observed flag to the threshold probability result as well.
5. The probability wrapper validates `outcome = "season_peak_week"` and a
   declared `target$n_weeks` but permits third-party forecast scales and
   threshold units. The PAGe adapter declares `scale = "weekF"`.

## Validation

- Unit tests cover atom/weight agreement with the existing peak summary,
  weight normalization, weekF coordinate conversion, latest-origin behavior,
  strict versus inclusive thresholds, unavailable or failed M1 rows, support
  filtering and dropped mass, generic outcome validation, and exact weighted
  CDF/quantile/probability results. Compute peak weights independently of
  whether M1 emits future forecast rows, covering origins at season end. For
  weighted results, Monte Carlo error attributes are NA, not binomial intervals.
- Documentation gives a generic third-party model example and a PAGe example,
  and states the experimental scope next to the probability interpretation.
- Do not use the `peak_passed` gate as a peak probability and do not infer a
  distribution from the current CI endpoints.

## Audit questions

1. Is the exact weighted template-peak distribution an honest and useful first
   distribution, given that weights are tuned for point accuracy?
2. Does the API distinguish model-conditional uncertainty from calibration to
   the realized peak week clearly enough?
3. Are origin selection, weekF conversion, support filtering, and threshold
   semantics coherent for prospective and fractional-timing runs? In
   fractional mode the peak atoms are fractional, but strict and inclusive
   thresholds still differ when `X` exactly equals an atom. The experimental
   peak curve is fractional even though the future observed calibration target
   is an integer week.
4. Are the generic API and returned metadata sufficient for other forecast
   engines without coupling them to PAGe internals?
