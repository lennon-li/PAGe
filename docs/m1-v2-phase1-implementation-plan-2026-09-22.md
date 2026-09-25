**Amendment (2026-09-22):** Phase 1 expert annotation is ignition-only. Peak truth is programmatic via the frozen retrospective GAM procedure documented in `docs/peak-truth-decision-2026-09-22.md`; earlier peak-annotation deliverables below are superseded.

# M1/M2 Redesign Phase 1 Implementation Plan — Timing and Annotation Contract

## Scope

Phase 1 implements only the authoritative expert-decimal timing contract and its validation/storage primitives.

It does **not** implement:

- a new M0 model;
- an M1 peak model;
- a common-curve model;
- M2 forecasting;
- peak-passage inference;
- LOSO fitting.

The purpose is to make the redesign's truth coordinate and annotation semantics executable before any statistical model is trained.

## Compatibility rule

The existing `timing_v2` integer-pair API is retained for legacy reproduction and existing tests. It is not used as authoritative truth for the redesign.

New redesign code must use the expert-decimal annotation API introduced in this phase.

## Deliverables

### 1. Governing contract

`docs/timing-annotation-contract-v1.md`

Defines:

- continuous coordinate `week w == [w, w+1)`;
- decimal label meaning;
- calendar/date semantics;
- expert ignition `I*` vs runtime detection `A`;
- primary peak semantics;
- ambiguity/unlabelable states;
- provenance and versioning;
- blinding/repeat-label requirements;
- prohibition on runtime use of held-out truth.

### 2. Expert annotation schema

Add an internal R API for one season/annotator record.

Required fields:

- `season`;
- `ignition_week_decimal`;
- `peak_week_decimal`;
- optional ignition interval;
- optional peak interval;
- `peak_status`;
- `annotator`;
- `annotation_version`;
- `annotated_at`;
- `data_snapshot_id`;
- `positivity_version`;
- `coordinate_version`;
- `schema_version`;
- optional `comment`.

### 3. Validation rules

For labelable seasons:

- numeric finite decimal values;
- values within `[1, n_weeks + 1)`;
- ignition strictly before peak;
- intervals contain their point estimates when points are present;
- interval lower <= upper;
- `plateau`, `multiple_peak`, and `uncertain` allow but should encourage nonzero uncertainty intervals;
- `unlabelable` permits missing peak point but requires a comment/reason;
- no silent coercion from old integer-pair labels.

### 4. Compilation/storage primitive

Provide a deterministic conversion from validated annotation objects to a flat data frame suitable for CSV/RDS/versioned release storage.

The compiler must preserve provenance fields and never mutate legacy labels.

### 5. Tests

Tests must cover:

- ordinary decimal ignition/peak;
- sub-week values such as 18.4 and 27.2;
- 52- and 53-week seasons;
- invalid ordering;
- out-of-range decimals;
- interval containment;
- ambiguous/plateau annotations;
- unlabelable peak behavior;
- required provenance;
- deterministic compilation;
- explicit separation from the old `timing_v2` normalization behavior.

## Explicit non-goals

Do not decide yet:

- interpolation algorithms for truth;
- common-curve df;
- likelihood family;
- posterior representation;
- passage thresholds;
- M2 feature set.

## Acceptance criteria

Phase 1 is complete when:

1. the written timing contract is present and internally consistent;
2. valid decimal expert labels can be represented without integer rounding/pair normalization;
3. invalid/ambiguous states fail or encode explicitly rather than silently coercing;
4. 52/53-week bounds are handled correctly;
5. annotations compile deterministically with provenance intact;
6. legacy timing-v2 tests remain unaffected;
7. new focused tests pass in the available R environment, or any environment blocker is documented precisely.

## Next gate

After Phase 1, obtain/review the 11 expert season labels before starting the statistical M1 implementation.
