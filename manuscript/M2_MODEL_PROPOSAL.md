# Proposed simplified M2 model

**Date:** 2026-09-08  
**Status:** proposal only; not implemented or tested.

This proposal records a small, interpretable M2 comparison focused on whether
phase and/or recent growth add information beyond the saved M1 forecast. It is
not a production-model decision. The recent simplified diagnostic found that a
base offset-plus-intercept-plus-`z`-smooth model was competitive for h1, while
the current raw M2 remained a useful h2 comparator; those results were
conditional, post-holdout diagnostics rather than new prospective evidence
(see [the diagnostic report](results/publication-repair-20260908/m2-simplified-20260908-native-02/REPORT.md)).

For season \(s\), origin week \(t\), and horizon \(h\in\{1,2\}\), let

\[
Y_{s,t+h}\mid N_{s,t+h},p_{s,t,h}
  \sim \operatorname{Binomial}(N_{s,t+h},p_{s,t,h}),
\]
\[
\operatorname{logit}(p_{s,t,h})
  = \operatorname{logit}(M1_{s,t,h}^{\mathrm{saved}})
    + a_h + f_h(z_{s,t}) + \text{optional }g_h(u_{s,t})
    \quad\text{or optional }r_h(d_{s,t}).
\]

The saved M1 value is the target-week forecast available at the origin. The
base candidate \(B\) is the tested offset-plus-intercept-plus-`z` smooth. Phase
and growth must first be tested separately: \(P=B+g_h(u)\) and \(G=B+r_h(d)\).
This document does not propose their combination or claim either is a winner.
The comparison is intended to remain small enough that any improvement can be
attributed to one clearly defined feature family.

Define \(q=y/N\) and
\(\ell=\operatorname{logit}(\operatorname{clip}(q,\epsilon,1-\epsilon))\), with
\(\epsilon=10^{-6}\). The level feature is an exponentially smoothed logit,
\(z_t=\alpha\ell_t+(1-\alpha)z_{t-1}\), initialized with the first observed
\(\ell\). The growth feature is \(d_t=z_t-z_{t-1}\), computed only across
adjacent observed weekly data. Missing weeks are explicitly unavailable; they
must not be filled by interpolation from future observations. The phase feature
is \(u_t=t-T_{decl}\), where \(T_{decl}\) is the first M0 ignition declaration
week, locked once and known at \(t\). The same declaration definition must be
used in training and replay. This avoids confusing a declaration with a
retrospective onset estimate or calendar week. Any current label-based
`t_since` training feature must be aligned to the declaration definition before
a new comparison. All added features must be available at the forecast origin.

Use modest by-horizon shrinkage: per-term basis dimensions with \(k=0\) meaning
the term is omitted and positive \(k\) values controlling smooth complexity, ridge-like
regularization on horizon intercepts, and REML. Exclude interactions, season
random effects, residual-history terms, online bias correction, and a post-peak
gate. Retain \(\gamma=1.4\) from the prior test. Inherit \(\alpha\) from the
frozen kit for this controlled comparison; this is not a new tuning claim.

Fit M2 once per outer season and freeze it for weekly replay. Do not retune M1.
Give each training season equal total weight, then compute trial-weighted NLL
and MAE within each season and average those season summaries equally across
the 11 outer seasons. Compare \(B\), \(P\), \(G\), M1 alone, and the raw old M2
benchmark. Select the minimum equal-season training LOSO NLL separately for
each horizon; exact ties choose the simplest model. Lock that rule and model
before outer evaluation.

Residual history and spread are deferred. A mature residual requires matching a
past issued target to the observation subsequently available at the current
origin. The purpose of this comparison is to distinguish a rise/fall signal
from a level or phase signal; it cannot by itself establish a causal mechanism
or prove generalization. Results remain conditional on inherited M0/M1
features, which were not newly cross-fitted; inspected holdouts/development
seasons and 2025–26 are acknowledged limitations, and no hypothesis tests are
proposed.

## Implemented follow-up experiment (2026-09-08)

The initial locked 16-configuration shared-switch experiment was implemented in
`PAGe/R/m2_subset_correction.R` and executed by
`scripts/publication_m2_subsets.R`. It uses the saved M1 logit as a mandatory
offset, declaration-safe `u`, prefix-safe EMA `z`, adjacent-week `d`, k=3
shrinkage smooths, REML, gamma 1.4, equal total trial weight per season, and
inner equal-season NLL selection separately by horizon. It is retained as the
fixed-k baseline for the expanded search. No M0/M1 refitting or
promotion was performed. The all-off candidate is verified to equal saved M1
exactly.

The complete conditional development result, including input/source hashes,
private per-season checkpoints, prior-version matched comparators, integrity
recomputation, and per-season aggregate deltas, is [the M2 subset experiment
report](results/publication-repair-20260908/m2-subsets-20260908-native-01/REPORT.md).
