# PAGe handoff to the next agent

Date: 2026-09-15 UTC
Project: `/home/yeli/repos/PAGe`
Role requested: take over bounded debugging, efficient M1 implementation, model
training for the incoming season, and manuscript evidence production.

## Objective

Produce a valid, reproducible PAGe model for the next incoming respiratory-virus
season and the evidence needed for the manuscript. The workflow must use the
canonical guarded APIs and preserve the ordered chain:

```text
M0 ignition -> M1 alignment -> M2 forecast -> frozen kit -> prospective replay
```

The final operational deliverable is one frozen model trained on all eligible
historical seasons after the validation decisions are fixed. The manuscript
deliverable is an artifact-backed report of the 11 outer holdouts, not a table
typed from prior notes.

Do not start unrelated experiments or silently substitute legacy scripts for the
current guarded API.

## Non-negotiable analysis rules

- Use the canonical stage lifecycle:
  `validate_season_selection()` -> `tune_*()` -> `validate_*_tuning()` ->
  `fit_*()` -> `freeze_*()` -> `assemble_kit()`.
- Use `train_pipeline()` and `replay_season_holdout()` for the governed
  end-to-end path. Research-only scripts under `scripts/fresh_run/` and old
  versioned nested-LOSO scripts are provenance references, not deployment
  instructions.
- Principal influenza seasons are the fixed 11-season universe:
  `2012-13`, `2013-14`, `2014-15`, `2016-17`, `2017-18`, `2018-19`,
  `2019-20`, `2022-23`, `2023-24`, `2024-25`, and `2025-26`.
- Fixed non-principal exclusions remain `2011-12`, `2015-16`, `2020-21`, and
  `2021-22`. `2015-16` may be used only as a documented diagnostic exclusion.
- For every outer holdout, the other eligible seasons are used for all tuning,
  fitting, scaling, labels, boundary expansion, and stopping decisions. The
  holdout is opened only for the final replay.
- Inner tuning must be season-held-out and walk-forward. Preserve all fold,
  spec, checkpoint, boundary, provenance, and failure artifacts.
- A selected genuinely tuned value must not remain at a boundary. Expand one
  valid adjacent step and retune before freezing. A meaningful null value such
  as an explicitly off term may remain at zero only when the boundary report
  records that interpretation.
- The primary forecast weighting is a parameter, defaulting to a 2:1 ratio:
  equal weeks within each season; target-relative weeks 0 through 12 receive
  weight 2; later eligible weeks receive weight 1; pre-ignition weeks receive
  weight 0; each season receives equal overall weight. Do not replace this with
  test-count weighting without an explicit protocol decision. Keep test counts
  in the binomial likelihood where required, but do not let seasons with more
  tests dominate the primary season summary.
- The primary forecast horizon is two weeks ahead. Horizon one, phase strata,
  ignition error, peak error, calibration, and runtime are secondary outputs.
- No post-holdout model or grid change may be presented as confirmation of that
  holdout. If a change is made after seeing a holdout, start a new development
  cycle and label the old result accordingly.
- Raw surveillance data are private/local. The known authorized path is
  `/home/yeli/FLU/flu_testing_data.csv`; never commit it or copy it into
  `data/`, `results/`, or the repository.

## Current state, with evidence limits

### Asgard 2025-26 ultimate run

Run directory:

```text
results/manuscript/nested-outer-2025-26-ultimate-20260914/
20260914T180000Z-parallel-fixed-r4/
```

The compact status file remains at `training`, with 10 training seasons. The
run log reached M1 spec 25/25 but stopped before writing the final result line,
completion marker, or completed artifact. The tracked launcher session is still
open, but this is not evidence that the R computation is making progress. Treat
the run as **incomplete/stalled until independently verified**.

The old watchdog falsely reported `running` because it trusted a PID that was
PID 2 in the sandbox namespace. That process was the shell, not proof of the R
worker. The false watchdog was stopped. Do not claim this run succeeded or
restart it over the same directory.

Required handling:

1. Make one bounded check of the tracked launcher and run-directory heartbeat.
2. If the launcher has no new output and no artifact progress, preserve the
   directory as an incomplete attempt and capture a short failure packet.
3. Inspect checkpoints and their source/package hashes before considering
   resumption. Resume only if the checkpoint schema, installed package, source
   manifest, and protocol identity match exactly.
4. Otherwise start a fresh run ID after the M1 speedup has been independently
   reviewed. Never mix old-code M1 checkpoints with a changed implementation
   without an explicit compatibility test.

Fix supervision before launching another long run. A watchdog must verify PID
identity using command line and process start time, and must use status/log/
checkpoint/artifact heartbeat evidence. It must classify a live but stale job
only from multiple signals. It must write one compact row per hour and a
terminal packet; it must not invoke an AI model or perform code changes.

### Wei M1 speedup

Wei used OpenCode Go with DeepSeek V4.1 Flash and reported exit code 0. The
reported implementation is in:

```text
PAGe/R/m1_multi_template.R
PAGe/R/m1_loso.R
PAGe/tests/testthat/test-m1-alignment-reuse.R
```

The claimed change caches/reuses alignment preparation across
`slope_weight` values and separates template alignment from the
slope-weight-dependent ensemble step where the formulas permit it. Wei
reported exact equality within `1e-13`, four focused test files passing, and a
small benchmark with three times fewer alignment fits and roughly 2.1 times
lower wall time.

Those claims are delegated evidence, not yet parent-verified. The diff is large
(`m1_loso.R` and `m1_multi_template.R` together showed roughly 961 inserted and
177 deleted lines), so review it carefully for accidental behavior changes.

Next actions:

1. Run `git diff --check` and bounded syntax checks on the three files.
2. Compare the changed functions with the pre-Wei behavior and confirm that
   cache keys include every behavior-affecting input: data/season identity,
   fold, M0 parameters and labels, timing mode/truth, derivative settings,
   `k_ref`, reference method, template shift, and fixed alignment arguments.
3. Obtain an independent read-only review from Liz/Sol or Opus. The reviewer
   must check numerical equivalence, stable spec ordering, checkpoint/resume
   semantics, parallel-worker behavior, and absence of changes to formulas,
   weighting, boundary expansion, min-gain rules, or artifact schemas.
4. Run the focused tests and a small old-versus-new fixture comparison before
   using the speedup in a historical run.
5. Do not commit or push the speedup until the independent review and parent
   checks pass. If a fix is needed, make the smallest patch and repeat review.

The speedup is intended to reduce repeated M1 work. It is not permission to
change the M1 model or tuning grid.

### Venkata jobs and artifacts

The Asgard session cannot currently see `/home/yeli/PAGe-m0-artifacts`; no
Venkata process or artifact directory was visible locally. An earlier report
claimed that a fractional M0 run completed 10/10 holdouts, but that result must
be verified on Venkata before being used as evidence.

Relevant Venkata entry points are:

```text
scripts/launch_m0_outer_holdouts_venkata.sh
scripts/run_m0_outer_holdouts_venkata.R
scripts/launch_outer_holdouts_venkata.sh
scripts/run_outer_holdouts_parallel.R
scripts/watch_outer_holdouts_venkata.sh
```

Before launching anything on Venkata:

1. Check the host, repository revision, installed package library, input path,
   CPU/RAM availability, and whether an old process is still running.
2. Confirm the latest API package is installed from the exact source revision.
   The launcher must record and verify the source hash and package location.
3. Confirm the data preparation directory and protocol RDS are present.
4. Verify that the M0 runner uses fractional timing and the current label
   protocol, rather than the old integer detector.
5. Use a unique output directory and preserve all existing artifacts.
6. Run M0 first if its artifact is missing or unverifiable. Then run the
   complete outer holdouts with M0 -> M1 -> M2 in dependency order. Parallelize
   independent outer seasons only after checking memory and avoiding nested
   oversubscription.

The Venkata launcher currently requires a completed gate directory before the
full outer run. Do not bypass that guard. If the gate is absent, report the
exact blocker and prepare the run rather than launching an invalid job.

For every Venkata run, require:

- one status file per fold and a top-level status file;
- one immutable protocol and source/package manifest;
- M0, M1, and M2 tuning tables including all expanded grid rounds;
- boundary reports and decisions;
- per-fold checkpoints and logs;
- frozen kit identity and strict replay output;
- a compact terminal watchdog record;
- a machine-readable aggregate table linking every metric to its holdout,
  model, horizon, phase, weighting rule, and artifact hash.

### Model for the incoming season

The operational target is one model trained on all eligible historical seasons,
using hyperparameters selected without using the incoming season. The 11 outer
holdouts are used to assess stability and to choose a predeclared final
selection rule; they are not eleven production models.

After the outer analysis is valid:

1. Reconcile the 11 holdout results and verify that every selected M0/M1/M2
   configuration passed boundary and minimum-gain checks.
2. Choose and record the final rule before fitting the all-season model. The
   rule must state how M2 falls back to M1/M0 when its inner gain is absent or
   negative, and must not be chosen from the incoming-season score.
3. Fit and freeze M0, M1, and M2 on the full eligible historical set with the
   selected configuration. Preserve the exact training-season list, label
   vector, protocol, source hash, package hash, and dependency identities.
4. Assemble the kit through `assemble_kit()` and validate it with the strict
   kit validator.
5. Run the incoming season prospectively using the frozen kit. Weekly execution
   may update the declared online state, but must not retune or refit the
   seasonal model.
6. Keep the existing `v16-corrected` kit as the incumbent contextual baseline
   until a governed candidate passes the release gates. The historical 2%
   NLL rule is an operational gate, not a manuscript effect threshold.

Ignition labels currently require special care. The working protocol has
`2025-26 = 19`; the requested sensitivity is to train with both the labelled
week and labelled week + 1, while evaluating the current label for the present
metric unless the frozen protocol explicitly says otherwise. Peak evaluation
uses the observed peak as the evaluation target. Verify the actual API behavior
and label isolation before fitting; do not silently introduce decimal labels or
change the legacy path in this run.

### Manuscript work

Canonical manuscript files include:

```text
manuscript/ANALYSIS_PROTOCOL.md
manuscript/METHODS.md
manuscript/RESULTS.md
manuscript/PLAN.md
manuscript/REPORTING_TEMPLATES.md
manuscript/IGNITION_LABEL_PROTOCOL.md
manuscript/GOVERNANCE_DECISIONS.md
manuscript/REVIEW_LOG.md
```

The current manuscript correctly records that the archived descriptive replay
table is not yet sufficient for the frozen primary comparison. It also records
that the 2025-26 replay has partial coverage and that source/package execution
provenance is incomplete. Do not overwrite those limitations with earlier
historical numbers.

The manuscript workstream should:

1. Populate the reporting templates only from immutable run manifests and
   machine-readable prediction tables.
2. Produce the 11-season M0, M1, and M2 table with the primary 2:1 phase-window
   weighting, equal-season aggregation, horizon and phase diagnostics, and
   explicit missing/failed-row accounting.
3. Compare M1 with new M2 and old M2 using old M2 artifacts only; do not rerun
   old M2 unless an artifact audit proves the old artifact is unavailable.
4. Report the 2025-26 partial-season fold separately from full-season summaries.
5. Add the planned calendar-GAM comparator, ablations, and label sensitivities
   only after the core PAGe evidence passes its gates.
6. Update Methods to describe the three levels of validation clearly:
   outer leave-one-season-out, inner leave-one-season-out tuning, and
   within-season walk-forward replay. State what question each level answers.
7. Record the weekly data resolution, the two-to-one week weighting, equal
   season aggregation, boundary expansion, min-gain rule, model fallback, and
   artifact provenance.
8. Pin the final commit, package version, dependency versions, input checksum,
   protocol checksum, and runtime environment in the analysis manifest.

No superiority claim, confirmation claim, or promotion claim is valid until
the corrected artifacts and paired comparison rows have passed reconciliation.

## Suggested execution order

1. Verify the live Asgard launcher once and classify the current r4 directory;
   preserve it either as complete or as an incomplete attempt with evidence.
2. Parent-check Wei's diff and focused tests.
3. Obtain independent Liz/Sol or Opus review; fix only identified issues.
4. Repair the watchdog so PID reuse and sandbox namespace confusion cannot
   produce a false `running` state.
5. Verify Venkata resources, package revision, raw data, existing M0 artifacts,
   and active jobs.
6. Complete the 2025-26 end-to-end gate run with the reviewed API and exact
   weighting. Do not open the holdout during tuning.
7. Run the remaining ten outer holdouts in parallel only after the single-fold
   run has passed its checks.
8. Reconcile all artifacts and derive the final all-season incoming-season kit.
9. Generate manuscript tables and Methods updates from the immutable evidence.
10. Run a final read-only audit of code, artifacts, labels, weighting,
    holdout isolation, boundary decisions, and manuscript claims.

## Stop conditions

Stop and report a bounded blocker if any of these occur:

- the installed package differs from the source manifest;
- a holdout label appears in training or tuning;
- a selected boundary is unresolved;
- a checkpoint comes from a different code/protocol identity;
- a watchdog cannot distinguish the actual controller from a reused PID;
- Venkata data, package, or artifact paths cannot be verified;
- a fold fails without a preserved error packet;
- manuscript numbers cannot be traced to an immutable artifact.

The next agent should leave the repository and external artifact stores in a
reviewable state and report exact paths, status, checks, failures, and remaining
decisions. Do not report success based only on a delegated agent's message.
