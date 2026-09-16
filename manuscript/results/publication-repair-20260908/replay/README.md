# Corrected-runtime diagnostic replay

Run `Rscript scripts/publication_replay.R` from the repository root. Each run
creates a unique dated directory; archived kits and results are never modified.
The 11 existing frozen kits are evaluated through the current strict replay API,
without retraining or reselection. This isolates runtime effects, not the effect
of correcting historical tuning. No new seasons or hypothesis tests are added.

Each run records source/input/kit hashes, session details, per-season durations,
full and restricted-window trial-weighted scores, matched prediction changes,
ignition estimates, and emission-status counts. Full replay objects (including
M0, weekly M1 parameters/curves, M2 predictions and the complete forecast ledger)
remain in gitignored `private/` subdirectories. Conditional fitted-mean bands
must not be described as full predictive intervals. Manual-label values are
archive metadata, not independently verified reference-label provenance.

`scripts/publication_watchdog.sh` runs replay then the comparator diagnostic,
with a 12-hour limit per job and zero-token process supervision. Logs, compact
status records and terminal exit codes are in gitignored `jobs/`. A nonzero
exit or failed seasonal result requires review; it must not be counted as a
completed publication analysis.
