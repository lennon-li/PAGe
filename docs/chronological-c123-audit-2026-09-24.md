# Independent audit of chronological v2 replay
Audit date: 2026-09-24. Reviewer: Argie.

**Verdict: BLOCKED.** The script contains a structural bug (`rbind` column mismatch) that will crash the outer chronological loop before completion. Additionally, the statistical baseline ignores denominator regimes, which may introduce severe bias.

## 1. P0 Must-Fix: Code Bugs
* **`rbind` crash on `pred_rows`:** `At$rows` (from `make_a_timing`) produces an A-path data frame without a `gate_week` column. `Bt` (from `make_b_timing`) includes `gate_week`. When these are merged onto `te`, A rows have 24 columns and B rows have 25. The final `pred <- do.call(rbind, pred_rows)` will fail with "numbers of columns of arguments do not match". **Fix:** Ensure `At$rows` gets an `NA_real_` `gate_week` column, or drop it from `Bt` before the merge.

## 2. P1 Statistical and Causal Findings
* **Denominator-regime interpretation:** `make_type_ledger` explicitly captures `denominator_regime`, but `fit_state_baseline` completely ignores it, fitting `glm(... ~ horizon_f + growth1 + growth2 + offset(offset_logit))` on pooled prior seasons. This implies testing-volume regime shifts are entirely ignored in the baseline trajectory, risking structural bias. **Fix:** Add `denominator_regime` as a factor in the GLM or explicitly subset training if regime invariance cannot be assumed.
* **B gate/timing semantics:** `first_b_gate_week` uses `stats::filter(z$y, rep(1,4))` and a rolling `max` on `z$p`. This calculates over the trailing 4 *available rows*, not exactly 4 calendar weeks. If the time series in `long` is sparse (missing weeks), the gate spans >4 weeks. Ensure `long` is dense or change logic to explicit calendar arithmetic.

## 3. Verification of Requested Checks
* **Prior-season-only M0/M1 A path:** Verified. `build_prior_a_stage` uses an M0 LOSO strictly over the `prior` season set. Target truth is excluded from all shape fitting and model choices.
* **Target truth/phase leakage:** Verified safe. `fit_target_a_m0` uses target `phase` solely for retrospective evaluation (`compare`). The prediction `p_cls_p` uses `predict(gam_base)`, where `gam_base` was strictly trained on prior seasons. Target truth does not influence activation.
* **Small-history fallback:** Verified. The outer chronological loop skips when `length(prior) < 3` (`min_prior_baseline`), and governed A timing falls back to unavailable when `< 5` (`min_prior_governed_A_timing`).
* **Family selection nesting:** Verified. `select_family_prior_only` correctly implements a strictly nested inner LOPO (leave-one-prior-out) over the `prior` set.
* **Exact fallback identities:** Verified. Fallbacks are explicitly enforced via `te$pred_selected[fallback] <- te$pred_base[fallback]`, explicitly passing the `B +1` and `timing-unavailable` assertions.

## 4. Comparison to Previous Audits
* **Claude discrepancy audit (STATUS.md):** The historical Claude discrepancy involved `qlogis(p_hat) - bias` artifacts stemming from soft-capped GAM predictions. This script circumvents the issue entirely by using a simple quasibinomial GLM directly on raw unstabilized logits (`offset_logit`), avoiding bounded GAM links.
* **Selected-v1 architecture audit:**
  * *Candidate-dependent row dropping (P1):* Addressed. The script pre-allocates a `candidate_independent_ledger.csv` and uses explicit fallbacks for unavailable rows, eliminating survival bias.
  * *Selection exclusions (P1):* Addressed via the nested `select_family_prior_only` routine which excludes validation seasons during family selection.
