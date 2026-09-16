# Archived-pair comparator diagnostic

Run from the repository root:

```sh
OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 Rscript --vanilla scripts/publication_comparators.R
```

This independent sidecar fits persistence, seasonal naive, calendar GAM and
historical-analogue continuation against the existing eleven holdout archives.
It does not generate PAGe predictions or invoke the package under repair.
All four exclusions remain excluded; each outer target is physically removed
before comparator tuning/fitting. Within-season scoring weights target trials;
the primary aggregate weights seasons equally. Every model uses the same 138
h2 rows: ignition offsets 0–12 in ten seasons and 0–7 in 2025–26.

Calendar fits use both horizons and all complete exact-week origin/lag/target
training pairs. Inner LOSO selection scores only the archived h2 windows using
trial-weighted season NLL, then equal-season mean and the one-SE rule. The SE is
the sample SD of the minimizing candidate's inner-season scores divided by the
square root of the number of inner seasons. Complexity is the nominal count
of smooth basis coefficients; canonical configuration IDs break ties.
Calendar smooths are separate by horizon, with a horizon intercept, REML
binomial fitting, and fixed cyclic knots at 0.5 and 53.5. The current signal is
clipped logit positivity; change is the difference from the exact previous
week. No lag imputation or aligned/M0/M1 features are used.

Analogue distance is unweighted mean squared logit difference at the same
within-season weeks over the full trailing window. Candidates lacking a
history or continuation are unavailable, not imputed; insufficient neighbours
stops the run. Ties use season ID. Continuations pool counts without smoothing;
seasonal naive alone uses the specified Jeffreys smoothing. For the analogue
one-SE rule, more neighbours means lower complexity, then shorter window.
These formula/support/complexity choices are explicit interpretations where
the protocol did not fully specify implementation.

One frozen configuration and calendar coefficient fit is stored per target,
before prediction. Parameters are never refitted to current-season data.
Forecast timings are batch latency divided by origins, not an operational
weekly latency benchmark. Source, archive and script hashes, warning/failure
records, runtime, selected configurations and inner-season scores are retained.
CSV prediction rows and RDS fitted objects are gitignored; JSON files contain
aggregate scores and audit/configuration metadata, not private weekly rows.

## Interpretation limits

This is a **final-data retrospective diagnostic**, not the repaired fully
nested publication analysis. PAGe points and ignition windows are pre-repair
archives. In particular, an inner season's archived M0 window may have been
derived using the current outer target; reusing it is not a newly nested M0
experiment. Archived global manual-label metadata is reported, not taken as
proof that historical fitting excluded every forbidden label. No new claim
about the PAGe lineage is made. The source observations are final revisions,
not vintage snapshots. No uncertainty intervals or hypothesis tests are run.

The protocol grids remain fixed for this bounded diagnostic. Boundary winners
are flagged rather than silently declared resolved; no publication-ready
freeze or promotion is asserted. Elastic net, boosted tree, repaired PAGe and
the broader manuscript sensitivity analyses are not part of this sidecar.
