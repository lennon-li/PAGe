# Peak truth decision — 2026-09-22

The redesign no longer asks users to provide decimal peak labels.

## Expert input

Experts provide only retrospective decimal ignition `I*`, with an optional plausible interval/comment.

## Peak truth

Retrospective primary peak truth `T*` is derived programmatically from the complete season using a frozen GAM measurement procedure. This truth procedure is separate from runtime M1 and may use the completed historical season because it is an evaluation target, not a runtime feature.

Initial implementation:

- response: weekly influenza-A positive/tested counts;
- model: `mgcv::gam(cbind(y, N-y) ~ s(weekF, bs="cr", k=k), family=quasibinomial(), method="REML")`;
- continuous peak: maximum fitted response over a 0.01-week grid;
- initial robustness audit: compare simple `k` values 5, 6, 8, 10 before freezing the truth specification.

The final `k` and any exceptional-season handling are not frozen yet. They will be chosen only after reviewing peak-location stability across all 11 completed seasons. If modest smoothing choices materially change a season's peak location, that season will be marked as intrinsically ambiguous rather than assigned false precision.

The GAM peak truth must never be generated from partial held-out-season data at runtime and must never be supplied as a held-out runtime feature.
