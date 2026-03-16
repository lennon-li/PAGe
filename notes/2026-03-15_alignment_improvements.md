# Alignment Improvements — 2026-03-15

## Summary of changes made this session

### 1. Delta (dilation) gate — fixed (3 bugs)

Delta was activating 0% of the time. Root causes fixed in sequence:

**Bug 1 — `learn_alignment_hyperparams()` (hyperparams.R)**
`nll_tau_delta` used `weights = n` in the GLM, inflating `LAMBDA_DELTA` ~1000×.
Fix: removed weights so LAMBDA_DELTA is on the same per-observation scale as the curvature check.

**Bug 2 — curvature evaluated at wrong tau**
The curvature gate (`d²NLL/dδ²`) was evaluated at `tau = 0` instead of the profile-optimal `tau_hat`.
At a misspecified tau, the NLL surface is flat in δ regardless of data. Fixed with a quick `optimize()` scan.

**Bug 3 — `cov_tau_delta_from_profile()` always returning NA (fit.R)**
The original implementation used a 961-point grid over ±2.5 tau, fitted a quadratic — but the NLL range (345–3340) was non-convex at that scale, giving a negative-definite Hessian (det = −19M). This triggered a fallback that forced delta_on = FALSE.
Fix: replaced wide grid with a **9-point numerical Hessian** (central differences, h_tau = 0.1, h_del = 0.005):
- `H11 = (nll(τ+h,δ) - 2·nll(τ,δ) + nll(τ-h,δ)) / h²`
- `H12` via 4-point cross-difference
- Solve H for covariance only if det(H) > 1e-12

**Result:** delta_on went from 0% → ~45–52% of aligned eval weeks.

---

### 2. Ignition offset — tried and reverted

Added `offset = -1L` to `run_ignition_weekly()` so `iWeek_hat_locked = raw - 1` (1 week earlier).
**Reverted:** User found it hurt results. Removed entirely from all callers
(`run_ignition_weekly`, `run_alignment_prospective`, `loso_walkforward`).

---

### 3. TAU_SHIFT — tried, made things worse, reverted

**Motivation:** Mean LOSO tau ≈ +2.17. Hypothesis: systematic bias to correct.

**First attempt (wrong direction):**
`eff_anchor = anchorWeek - TAU_SHIFT`
This subtracted ~2 from newWeek, forcing tau → 0. But tau = +2.17 is **real signal** — seasons genuinely peak ~2 weeks after ignition. Forcing tau → 0 made the model predict peak = ignition week. MAE got worse.

**Reverted completely.**
Key lesson: tau ≈ +2.17 reflects that seasons peak ~2 weeks after the ignition detector fires. This is not a bias — it's a real characteristic of the data that the optimizer should be free to capture.

**Final analysis (checked):**
- Mean peak error (hat − true) = **−0.49 weeks** (slightly too early), median = 0
- Mean absolute error = **1.955 weeks** at k_ref=8 (Weibull p=2, λ=0.1)
- Shifting in the OTHER direction (eff_anchor = anchorWeek + TAU_SHIFT) is **self-canceling**: adding to the anchor increases t_peak by the same amount, so peak_weekF is unchanged
- A post-hoc +1 week correction would overshoot — 73% of predictions are already on-target or late
- **Conclusion: no tau shift. Leave as-is.**

---

### 4. LOSO QMD cleanup

- Removed **Peak calibration** section (shrinkage + GAM bias correction)
- Removed **Delta dilation: when is it active?** section
- Simplified k_ref tuning to **single Weibull scheme**: p=2, λ=0.1
  `w(t) = exp(-(0.1·t)²)` — flat for first ~5 weeks, sharp decay after
- Kept weight plot for the single scheme
- Removed weight-viz with all three schemes

---

## Key functions and files

| File | What changed |
|------|-------------|
| `flualign/R/fit.R` | `cov_tau_delta_from_profile()` rewritten with 9-pt numerical Hessian |
| `flualign/R/hyperparams.R` | Removed `weights=n` from `nll_tau_delta`; curvature now at tau_hat |
| `flualign/R/prospective_running.R` | Removed `offset` parameter entirely |
| `flualign/R/prospective_alignment.R` | Removed `offset` and `TAU_SHIFT` logic |
| `flualign/R/loso_alignment.R` | Removed `offset` forwarding |
| `docs/loso_walkforward.qmd` | Removed peak calibration + delta sections; simplified k_ref tuning |

All root-level `R/` files are synced to `flualign/R/`.

---

## Shutdown command (verified working)

```bash
cmd.exe /c shutdown /s /t 60
```

**Do NOT use:** `cmd.exe /c "shutdown /s /t 60"` (quoting the inner command causes issues in some contexts).
**Cancel with:** `cmd.exe /c shutdown /a`
