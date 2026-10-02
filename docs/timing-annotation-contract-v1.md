# PAGe Expert Timing Annotation Contract v1

Status: governing contract for the M1/M2 redesign expert labels.

This contract is intentionally separate from the legacy `timing_v2` integer-pair labeling API. Legacy timing helpers remain available only for historical reproduction and compatibility. They are not authoritative truth for the redesigned M0/M1/M2 system.

## 1. Continuous season coordinate

The authoritative coordinate is continuous `weekF` time.

For integer week `w`, the associated interval is:

`[w, w + 1)`.

Therefore:

- `27.0` is the start of week 27;
- `27.2` is 20% of the way through week 27;
- `27.5` is halfway through week 27;
- `28.0` is the start of week 28.

This coordinate convention is versioned as:

`page-continuous-week-v1`.

The same convention must be used for expert ignition and expert peak labels.

## 2. Relationship to weekly observations

Observed surveillance values remain weekly aggregates indexed by integer `weekF`.

A decimal expert label is an epidemiological judgment about the latent timing of an event within/between weekly aggregates. It is not a claim that the event was directly observed at sub-week resolution.

The weekly aggregation interval and release/origin time are distinct concepts. Runtime models may only use observations available by the declared origin cutoff.

### 2.1 Runtime release/origin convention

For the redesigned walk-forward system, an origin labelled integer week `w`
means immediately after the completed aggregate indexed by `weekF = w` is
available. The causal prefix is therefore exactly the rows satisfying
`weekF <= w`.

Because observation `w` summarizes interval `[w, w + 1)`, the corresponding
continuous as-of boundary is `w + 1`. This distinction is important when
scoring a continuous latent peak against integer weekly origins.

For a latent peak `T*`:

- the peak is strictly future at origin `w` only when `T* > w + 1`;
- if `T*` lies inside `[w, w + 1)`, the completed observation at origin `w`
  already contains the latent peak interval;
- the first weekly origin at which the latent peak can be considered reached
  under this release convention is `ceiling(T*) - 1`.

This convention is for runtime/evaluation semantics. It does not change the
continuous truth coordinate itself.

## 3. Calendar mapping

When dates are available, each integer week must have an explicit start date and exclusive end date. Date-to-decimal conversion is linear within that actual interval.

Calendars may contain 52 or 53 weeks. Season rollover must be represented by the explicit calendar rather than inferred from arithmetic on week labels.

## 4. Expert events

For each historical season, experts may label:

- latent ignition time `I*`;
- latent primary peak time `T*`.

Both are numeric values on the same continuous coordinate.

For ordinary labelable seasons:

`1 <= I* < T* < n_weeks + 1`.

The annotation process may also retain uncertainty intervals around either point.

## 5. Primary peak semantics

The target is the epidemiologically meaningful primary seasonal peak, not mechanically the maximum reported weekly aggregate.

Annotation status must be one of:

- `clear`: one primary peak can be assigned reasonably precisely;
- `plateau`: the primary peak is a broad plateau and a point label is a summary of a wider plausible interval;
- `multiple_peak`: more than one epidemiologically plausible primary peak exists;
- `uncertain`: a primary peak exists but its timing is materially uncertain;
- `unlabelable`: the season does not support a defensible unique primary-peak point label.

For `plateau`, `multiple_peak`, or `uncertain`, a peak uncertainty interval should normally be recorded.

For `unlabelable`, the peak point may be missing and the reason must be documented.

Secondary later waves do not automatically redefine the primary peak. Any adjudication should be based on epidemiological review of the full historical season, not on a model forecast.

## 6. Ignition semantics

Ignition is the expert-estimated latent start of sustained seasonal epidemic activity.

Expert ignition `I*` is distinct from causal runtime M0 detection origin `A`.

The redesign must retain both quantities:

- `I*` for biological/descriptive evaluation;
- `A` for operational activation and runtime M1 priors.

## 7. Required provenance

Every annotation record must identify:

- season;
- coordinate version;
- annotation schema version;
- annotator;
- annotation version;
- annotation timestamp;
- data snapshot identifier/hash;
- positivity definition/version;
- ignition point and optional interval;
- peak point and optional interval;
- ambiguity status;
- optional comment.

Annotations must be versioned. New adjudication must not silently overwrite raw prior annotations.

## 8. Blinding and repeatability

Experts should label without seeing model predictions.

The initial 11-season reference set should include a repeat labeling pass separated in time. Repeatability should be quantified before interpreting sub-week model errors as meaningful.

## 9. Runtime prohibition

Held-out-season expert truth is evaluation data only. It must never enter runtime M0/M1/M2 features.

M1 runtime activation is based on causal M0 detection `A`, not expert ignition `I*`.

## 10. Legacy compatibility

The following legacy behavior is explicitly non-authoritative for new expert truth:

- integer singleton labels expanded to adjacent week pairs;
- midpoint targets generated automatically from those pairs;
- legacy integer scoring labels.

Legacy functions may remain for reproduction, but new redesign code must consume the expert decimal annotation schema defined here.
