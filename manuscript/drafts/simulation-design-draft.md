> **Status (2026-09-15): reduced for Epidemics supplement**

# PAGe simulation-study design (DRAFT)

- Status: **DRAFT** for project-lead review. No simulation has been run, and no
  numerical result is reported here.
- Draft date: 2026-09-15.
- Scope: a design document for a bounded supplementary simulation that supports
  the *Epidemics* Methodological Manuscript. It is not a main-text section and
  it is not the source of the manuscript's empirical claim. Main-text evidence
  comes from the empirical co-primary blocks of
  [`ANALYSIS_PROTOCOL_v2.0-draft.md`](ANALYSIS_PROTOCOL_v2.0-draft.md) section
  5.3. The simulation is written to be consistent with the current recipe in
  [`ANALYSIS_PROTOCOL_v2.0-draft.md`](ANALYSIS_PROTOCOL_v2.0-draft.md) section 2
  and with the registered empirical protocol
  [`ANALYSIS_PROTOCOL.md`](../ANALYSIS_PROTOCOL.md) sections 2 and 4.
- Reduction (2026-09-15): the eight-stressor program (old U1-U8) is cut to the
  reference DGP plus four decisive unfavourable DGPs. The removed scenarios are
  listed under "Considered and not run" (Section 3.4). The cut follows the
  journal-fit audit item H6 (bounded supplement) and the length/compute budget.
- Relationship to the empirical study: the simulation is a bounded
  generalisation check. Section 5 of the protocol states that simulation
  evidence bounds generalisation claims.
- Every statement that depends on unverified code behaviour is marked
  **ASSUMPTION** with the file it is based on. These must be confirmed against
  the implementation before the protocol is frozen.

---

## 1. Purpose and aims

### 1.1 Claims the simulation is intended to support

The simulation is designed to characterise *when the PAGe decomposition helps
and when it fails*, under data-generating processes (DGPs) whose latent state is
known. It is intended to support the following bounded claims.

1. **Mechanism claim (conditional).** Under a PAGe-compatible epidemic shape
   with between-season timing variation, phase alignment can reduce
   short-horizon forecast loss, and the reduction can be attributed to alignment
   because the no-M1 ablation is evaluated on identical realisations.
2. **Failure-mode claim (conditional).** Under the four retained unfavourable
   conditions-especially template shape mismatch, bimodality, ignition outside
   the training timing range, and low or shifting testing volume with
   overdispersion-phase alignment can be neutral or harmful, and the simulation
   identifies which stage (M0 detection, M1 peak estimation, M2 mapping, or the
   adoption gate) is implicated.
3. **Adoption-gate claim (descriptive).** The prespecified M2-versus-M1
   adoption gate (protocol v2.0 section 2) can be evaluated for how often it
   selects M2, how often that selection is correct given the realised held-out
   scores, and what loss it incurs relative to an oracle that always chooses the
   better of M1 and M2 per season.
4. **Operating-condition map.** The mapping from the retained DGP features
   (onset timing, shape, bimodality, testing volume, dispersion) to the sign and
   approximate magnitude of the component contrasts is summarised as an
   operating-condition map in a supplement figure.

### 1.2 Claims the simulation cannot support

The simulation cannot and must not be used to:

1. **establish empirical performance.** It does not estimate Ontario influenza
   forecast skill, and its numbers do not substitute for the governed replay
   aggregate or for the prospective 2026-27 evaluation.
2. **confirm biological or operational labels.** Simulated ignition and peak are
   latent truths defined by the generator; the empirical study uses operational
   reference labels that are not ground truth. Agreement between simulated and
   empirical label behaviour cannot be claimed as label validity.
3. **validate the production recipe as executed.** Unless the full tuning grids
   and cadence are used, the simulation estimates a reduced recipe (Section 8).
   A reduced-recipe result does not certify the full-grid recipe.
4. **support cross-pathogen or cross-jurisdiction claims.** No other-pathogen or
   other-jurisdiction observation process is simulated here; portability remains
   an empirical question with its own gate. Claims are limited to Ontario
   influenza.
5. **support daily-resolution or age-stratified claims.** The weekly DGP does
   not generate daily counts or age strata, so the daily IRVRI legacy GAM and
   age-stratified comparators are out of scope (Section 4.4).
6. **function as hypothesis testing of the empirical contrast.** The empirical
   analysis is descriptive by protocol; simulation Monte Carlo intervals
   quantify simulation precision, not sampling uncertainty in the Ontario
   seasons.
7. **prove that phase alignment is the cause of any real-world gain.** Only the
   paired ablation structure inside the simulation, and the corresponding
   empirical ablation, can speak to mechanism, and only conditionally.

---

## 2. Existing generator: capabilities and limits

The package currently provides one generator,
`PAGe::simulate_flu_seasons(S, weeks, seed)`
([`PAGe/R/simulate.R`](../../PAGe/R/simulate.R)).

### 2.1 What it can generate

- `S` synthetic seasons on a within-season week index (`weeks`, default
  `1:52`).
- A single symmetric Gaussian bump template on the logit scale,
  `eta_template(t) = -3 + 5 * exp(-0.5 * ((t - 36) / 7)^2)`.
- Per-season intercept `a ~ Normal(0, 0.5)`, amplitude multiplier
  `b ~ LogNormal(meanlog = 0, sdlog = 0.15)`, and timing shift
  `tau ~ Normal(0, 2)`; the logit trajectory is
  `eta = a + b * eta_template(newWeek - tau)`.
- Binomial weekly counts, `y ~ Binomial(n, plogis(eta))`, with
  `n ~ Uniform(600, 1500)` redrawn each week; returns `neg = n - y`.
- A reproducible seed.
- Output columns `season`, `newWeek`, `y`, `neg`
  ([`PAGe/R/simulate.R`](../../PAGe/R/simulate.R)).

### 2.2 What it cannot generate

- **No asymmetric or heavy-tailed template.** Only a symmetric Gaussian bump is
  available, so template shape mismatch cannot be expressed.
- **No multiple waves.** A single bump cannot represent bimodal or prolonged
  seasons.
- **No drift across seasons.** `a`, `b`, and `tau` are independent draws; there
  is no amplitude or baseline trend over the season index.
- **No denominator dynamics.** Weekly `n` is i.i.d. uniform and uncorrelated
  with the epidemic state; there is no trend, regime shift, or low-volume
  period.
- **No overdispersion.** Counts are exactly Binomial; extra-binomial variation
  is unavailable.
- **No missingness, revision, or reporting disruption.** All weeks are present
  and final.
- **No calendar/season labels, ignition labels, or peak labels.** `season` is
  the factor `1:S`, and `newWeek` is not an MMWR-derived `weekF`.
- **No daily or age-stratified observations.**
- **Not directly in the PAGe data contract.** The contract requires
  `season`, `weekF`, `y`, `N`, `neg`, `p`
  ([`METHODS.md`](../METHODS.md) "Surveillance data and data contract").
  `simulate_flu_seasons()` returns `season`, `newWeek`, `y`, `neg`, with no
  explicit `N` or `p`.

**ASSUMPTION** (based on [`PAGe/R/simulate.R`](../../PAGe/R/simulate.R)): the
generator's output is intended for package examples and is not, by itself, a
simulation study engine. The design below therefore assumes a thin wrapper that
draws from an extended DGP family and emits the PAGe contract columns (`weekF`
from `newWeek`, `N = y + neg`, `p = y / N`), plus latent truth
(`true_ignition`, `true_peak`, `true_p`). This wrapper does not exist yet.

---

## 3. Data-generating processes

### 3.1 Common construction

All scenarios share one construction so that methods are compared fairly.

- Latent logit trajectory in within-season week `t`:
  `eta_st = a_s + b_s * g(u_st)`, where `g` is a scenario-specific unit-height
  shape and `u_st` is a scenario-specific timing coordinate (usually
  `t - tau_s`).
- Observation: `y_st ~ Obs(N_st, plogis(eta_st))`, where `Obs` is Binomial in
  the reference and shape/timing scenarios and Beta-binomial in the
  dispersion/volume scenario.
- Latent ignition `= first t with eta_st > eta_ign` (or an equivalent
  phase definition) and latent peak `= argmax_t eta_st`; both are recorded from
  the generator for exact stage scoring.
- Each scenario is a *family*, not a single parameter value. A replicate draws
  its season-universe parameters from the family (Section 7.2).

### 3.2 Reference DGP (PAGe-compatible)

| Item | Specification |
|---|---|
| Shape `g` | Symmetric Gaussian bump, matching `simulate_flu_seasons()` |
| Season effects | `a_s ~ Normal(0, 0.5)`, `b_s ~ LogNormal(0, 0.15)`, `tau_s ~ Normal(0, 2)` |
| Observation | Binomial with weekly `N_st ~ Uniform(600, 1500)`, i.i.d. |
| Latent peak | `36 + tau_s` on the within-season week index |
| Purpose | The favourable condition under which the method is designed |

This is the only scenario currently expressible with the shipped generator; all
others require the extended wrapper of Section 2.2.

### 3.3 Retained unfavourable DGPs

The reduced design keeps exactly four unfavourable conditions. They are chosen
because each breaks a distinct PAGe assumption and each is a plausible
operational failure mode. Parameter levels are design proposals and are marked
`[DECISION]` where the project lead must confirm them. "Stressor" names the
stage or assumption the scenario is intended to break. The ID mapping to the
earlier eight-stressor list is: U1 = old U1, U2 = old U2, U3 = old U3, U4 =
merged old U5 and U6.

| ID | DGP family | Generative description | Parameters and proposed levels | What it stresses |
|---|---|---|---|---|
| U1 | Template shape mismatch | Replace the Gaussian bump with an asymmetric or heavy-tailed epidemic shape (skew-normal / lognormal-shaped rise and decay), so the historical template family cannot represent the target curve | Skew `xi in {-1.0, -0.5, 0, 0.5, 1.0}`; decay-to-rise ratio `in {0.5, 1, 2}` `[DECISION]` | M1 alignment and template weighting; M2 offset quality; the assumption that historical shapes span the target shape |
| U2 | Bimodal / double-peak season | Sum of two bumps with controlled separation and amplitude ratio, optionally unequal widths | Separation `Delta mu in {4, 6, 8}` weeks; amplitude ratio `in {0.25, 0.5, 1.0}`; second-wave width `in {0.5, 1, 1.5}x` `[DECISION]` | Peak-week definition in M1; template locking onto the wrong lobe; post-peak override and bias correction; M0 gating if the first wave is sub-threshold |
| U3 | Shifted / late ignition beyond training range | Draw `tau` from a region not represented in the training seasons (e.g. all training `tau` near 0, target `tau` large positive or negative) | Target offset `in {+3, +5, -3, -5}` weeks beyond the training `tau` support; training support width `in {2, 4}` `[DECISION]` | M0 detection window; M1 template domain and extrapolation; feature-range clamping; no adequate historical analogue |
| U4 | Testing-volume shift with overdispersion | Replace i.i.d. `N_st` with a regime process (step change, smooth trend, or low-volume floor, optionally correlated with epidemic phase) and draw counts from a Beta-binomial with extra-binomial variation while all models remain Binomial | Step multiplier `in {0.5, 2}`; trend over the season; low-volume floor `N_min in {50, 150}`; dispersion `phi in {2, 5, 10}` `[DECISION]` | Denominator-aware objectives; binomial weighting; M2 testing-volume term; identifiability of positivity from counts; likelihood misspecification; calibration; online residual correction |

### 3.4 Considered and not run

The following conditions from the earlier list are not run in this cycle,
because the four retained stressors cover the main failure modes and the
compute budget is bounded (Section 8). Each could be added in a later cycle.

- **Amplitude / baseline drift (old U4).** Monotone trend in `a_s` and/or `b_s`
  over the season index; not run because the retained timing and shape
  stressors already probe the exchangeability assumption.
- **Reporting disruption and missingness (old U7).** Missing or block-missing
  weeks and delayed/backfilled values; not run because the generator has no
  revision model and a simulated version would not represent the real feed.
- **Non-epidemic / flat season (old U8).** A season whose latent trajectory
  stays below the ignition threshold throughout; not run because the retained
  stressors bound the main failure modes and the adoption gate is evaluated on
  seasons that ignite.

The ignition-label perturbation is retained as a stressor applied to a subset
of scenarios (shift the labels supplied to training by `-1` and `+1` week, and
use M0-generated labels) rather than as a separate DGP. This mirrors the
empirical label sensitivities and tests propagation of M0 error into M1 and M2.

**ASSUMPTION** (based on
[`ANALYSIS_PROTOCOL_v2.0-draft.md`](ANALYSIS_PROTOCOL_v2.0-draft.md) section 2
and [`ANALYSIS_PROTOCOL.md`](../ANALYSIS_PROTOCOL.md) section 4): the
implementation supports a fixed-season-start anchor for the no-ignition-gate
ablation and a calendar-week-only M2 for the no-M1 ablation, and the online
correction can be disabled. These are the ablation switches the simulation
relies on; they must be verified in code before freeze.

---

## 4. Methods compared under identical realisations

### 4.1 Core methods

All methods in a replicate see the same realised data and the same origins
(common random numbers). Parameter tuning, where applicable, occurs inside the
outer training seasons only, mirroring
[`ANALYSIS_PROTOCOL.md`](../ANALYSIS_PROTOCOL.md) section 2.2.

| Method | Definition | Inputs | Tuning |
|---|---|---|---|
| Full PAGe | The frozen recipe of [`ANALYSIS_PROTOCOL_v2.0-draft.md`](ANALYSIS_PROTOCOL_v2.0-draft.md) section 2: M0 -> M1 -> M2 with adoption gate and optional online correction | Weekly counts, latent true labels withheld from training | Per protocol; reduced grid in the simulation variant (Section 8) |
| M1 only | M1 aligned point forecast used directly as the predictive positivity; no M2 GAM | Weekly counts | Same M1 grid as full PAGe |
| Persistence | Positivity observed at the origin, carried to both horizons | Weekly counts | None |
| Seasonal naive | Denominator-pooled historical positivity for the corresponding within-season target week, Jeffreys-smoothed | Outer-training counts | None |
| FluSight-style baseline | Median = last observed positivity; predictive quantiles from the empirical distribution of week-to-week positivity changes in the training data at the same horizon, symmetrized | Outer-training counts | None |

### 4.2 Ablations and label arms

Ablations and label perturbations are run on top of the full PAGe recipe on the
same realisations and the same rows.

| Arm | Definition | Tuning |
|---|---|---|
| No ignition gate | Ablation 1 of the protocol: fixed analysis season start replaces M0; M1 and M2 retained | Same as full PAGe |
| No alignment uncertainty | Ablation 3: `logit_spread` and other alignment-uncertainty inputs removed | Same as full PAGe |
| No M1 alignment | Ablation 2: aligned week, template, peak, and spread inputs removed; within-season and time-since-ignition terms used | Same as full PAGe |
| Ignition-label shift `-1` | Training labels shifted one week earlier than the reference | Same as full PAGe |
| Ignition-label shift `+1` | Training labels shifted one week later than the reference | Same as full PAGe |
| M0-generated labels | The labels supplied to training are M0's own estimates rather than the reference labels | Same as full PAGe |

The bias-correction axis is not a separate arm; it is a grid value
([`ANALYSIS_DEVIATIONS_new-cycle-draft.md`](ANALYSIS_DEVIATIONS_new-cycle-draft.md)
D-22).

### 4.3 Contrast structure

- **Primary simulation contrast:** full PAGe minus M1 only on the
  phase-weighted score (Section 6.1), per scenario, averaged over replicates.
  This matches the empirical M2-versus-M1 adoption logic.
- **External benchmark:** full PAGe minus the FluSight-style baseline.
- **Component attribution:** full PAGe minus each ablation, evaluated per
  scenario, to link component benefit or harm to the DGP feature.
- **Floor models:** full PAGe minus persistence and minus seasonal naive.
- **Label sensitivity:** each label arm minus full PAGe on identical rows, to
  trace M0 label error into the forecast score.

### 4.4 Out-of-scope methods

- **IRVRI legacy daily GAM** is out of scope for this simulation because it
  requires daily positive and total counts by age stratum
  ([`ANALYSIS_PROTOCOL_v2.0-draft.md`](ANALYSIS_PROTOCOL_v2.0-draft.md) section
  1.3; [`METHODS.md`](../METHODS.md) "Temporal resolution and legacy
  implementation"). The weekly DGP does not generate daily or age-stratified
  data, so a simulated comparison would not be fair to the legacy model. The
  operational-baseline contrast is estimated empirically (protocol v2.0 section
  5.3, block 1).
- **Calendar-week binomial GAM** is not re-run in the simulation. It remains a
  registered weekly comparator estimated empirically in the 11-fold Workflow A
  analysis ([`ANALYSIS_PROTOCOL_v2.0-draft.md`](ANALYSIS_PROTOCOL_v2.0-draft.md)
  section 4); repeating it in simulation would add compute without changing the
  bounded generalisation claims.
- **IRVRI mvgam** is a weekly statistical comparator that could in principle
  ingest the simulated weekly input, but it is out of scope here because its
  MCMC cost and specification-selection burden are disproportionate for a
  design whose purpose is to characterise PAGe's operating conditions.
- **SIR/SIRS filtering** is excluded for the same reason it is excluded
  empirically: a fair positivity comparison needs a latent-incidence-to-testing
  observation model ([`LITERATURE_REVIEW.md`](../LITERATURE_REVIEW.md) "Models
  not recommended as primary comparators" and
  [`ANALYSIS_PROTOCOL.md`](../ANALYSIS_PROTOCOL.md) section 3).

---

## 5. Design per replicate

### 5.1 Simulated season universe and outer holdout

Each **replicate** draws one synthetic season universe of `S` seasons from the
scenario's DGP. The outer procedure mirrors the empirical protocol
([`ANALYSIS_PROTOCOL.md`](../ANALYSIS_PROTOCOL.md) section 2.1 and
[`METHODS.md`](../METHODS.md) "Seasonal training cadence"):

1. For each target season `s` in the universe, hold `s` out.
2. Tune and freeze exactly one kit per target season using the other `S - 1`
   seasons, with inner leave-one-season-out replay for all non-fixed
   hyperparameters.
3. Replay the frozen kit through `s` week forward, state-updating M0/M1/correction
   only.

Base setting: `S = 12`, fixed by this reduction. Rationale: the empirical
protocol has 11 seasons and `S` must be large enough to retain a meaningful
inner LOSO after the outer holdout and to support template estimation, while
keeping per-replicate cost bounded. One universe size is used; a size
sensitivity is out of scope.

**ASSUMPTION** (based on
[`ANALYSIS_PROTOCOL.md`](../ANALYSIS_PROTOCOL.md) sections 2.1-2.3): one frozen
kit per target season is reused at every origin within that season, and no
current-season observation enters fitting. The simulation inherits this cadence
unchanged.

### 5.2 Origins

- Primary origin window: detected ignition through ignition `+ 12` weeks,
  inclusive, wherever the `h = 1` and `h = 2` target weeks are observed. This
  mirrors the empirical replay window
  ([`METHODS.md`](../METHODS.md) "Validation and replay design").
- Sensitivity: full available post-ignition support.
- If M0 fails to ignite, the replicate's target-season forecast is recorded as
  a pipeline failure with a reason code, exactly as the empirical failure rule
  requires. It is not dropped from the score.

### 5.3 Horizons and scoring rows

- Horizons `h in {1, 2}`, with `h = 2` as the primary contrast, matching the
  empirical primary comparison, and `h = 1` reported as secondary.
- Rows are keyed by `season`, `origin`, `h`, and `target`; all methods in a
  contrast are scored on identical common rows; unavailable forecasts are
  counted with reason codes and never silently dropped.

### 5.4 Latent truths available in simulation

Unlike the empirical study, the simulation knows the generator's `eta`, so it
supplies exact reference ignition and peak weeks. These are used only for
scoring M0 and M1 and for defining evaluation strata; they are never supplied
to any model as inputs. The corresponding empirical operational labels remain
approximate reference labels, not ground truth
([`METHODS.md`](../METHODS.md) "Forecast targets and information boundary").

---

## 6. Estimands and metrics

### 6.1 Forecast loss

Primary forecast estimand per season and method: the phase-weighted Bernoulli
cross-entropy of
[`ANALYSIS_PROTOCOL_v2.0-draft.md`](ANALYSIS_PROTOCOL_v2.0-draft.md) section 5
and [`METHODS.md`](../METHODS.md) "Outcomes and descriptive scoring":

`L_s,m = sum_w [ -q log(p_hat) - (1 - q) log(1 - p_hat) ] / sum_w`,

with `q = y / N` at the target week, predictions clipped to
`[1e-12, 1 - 1e-12]`, and phase weights from protocol v2.0 section 2: zero
pre-ignition, 2 during rise, 3 in the turning window, and 1 during decline (the
exact phase schedule is a `[DECISION]` in the protocol and controls here too).
Within a season, weeks are averaged equally and seasons are then averaged
equally.

The primary simulation contrast per scenario is

`Delta_scenario = mean_s ( L_s,PAGe - L_s,M1only )`,

with negative values favouring full PAGe over M1 only. All comparator, ablation,
and benchmark contrasts use the same rows and the same weights.

### 6.2 M0 ignition error

Scored against the generator's latent ignition week:

- signed ignition-week error (detected minus true);
- absolute ignition-week error;
- miss rate (no ignition detected);
- false-alarm rate, defined during the pre-ignition period of epidemic
  scenarios;
- detection delay relative to true ignition.

### 6.3 M1 peak-week error

Scored against the generator's latent peak week:

- weighted peak-week MAE with weights `exp(-(0.1 d)^2)`, where `d` is weeks
  before the true peak, matching the empirical M1 metric
  ([`METHODS.md`](../METHODS.md) "Outcomes and descriptive scoring");
- unweighted peak-week MAE;
- peak-interval coverage if the implementation emits a peak interval.

For the bimodal scenario (U2), the scoring definition must state which peak is
the reference; this is an open decision (Section 9).

### 6.4 Adoption-gate decision rate and correctness

The adoption gate is the per-season rule that selects M2 only if the
phase-weighted gain clears the floor and variability requirement, and no season
degrades ([`ANALYSIS_PROTOCOL_v2.0-draft.md`](ANALYSIS_PROTOCOL_v2.0-draft.md)
section 2). It is evaluated per simulated target season as follows.

- **Decision rate:** proportion of target seasons in which the gate selects M2.
- **Correctness:** for each season, compare the gate's choice with the realised
  held-out scores on that season's common rows. Define
  `truth = M2 better` when `L_s,M2 < L_s,M1`. Then report the 2x2 table
  (selected M2 vs M1) x (M2 better vs M1 better), and derive:
  - sensitivity = P(select M2 | M2 better);
  - specificity = P(select M1 | M1 better);
  - false-adoption rate = P(select M2 | M1 better);
  - miss rate = P(select M1 | M2 better).
- **Regret:** the gate's realised score minus the score of the per-season oracle
  that always chooses the better of M1 and M2. Regret is reported per scenario
  and as an average, and isolates the cost of gate errors from the cost of the
  underlying stage performance.

Because the simulation knows the realised comparison, this is an
oracle-conditional definition; in the empirical study the true better procedure
is unobservable. The finite-sample binomial standard error of a rate with `R`
replicates is `sqrt(p (1 - p) / R)` and is reported with each rate.

### 6.5 Secondary metrics

Probabilistic scores: weighted interval score (WIS) on the positivity scale with
the same phase weights and aggregation as 6.1, and empirical coverage of the
central 50% and 95% intervals, using the predictive quantiles of protocol v2.0
section 5.1. Also: positivity MAE and RMSE, horizon-specific scores, phase
strata (rise, turning, decline), runtime, and failure rate, matching the
empirical secondary outcome list
([`ANALYSIS_PROTOCOL.md`](../ANALYSIS_PROTOCOL.md) section 6). These are
descriptive and are not the basis for the simulation's main claims.

---

## 7. Monte Carlo design

### 7.1 Replicate count and precision

The primary simulation quantity is the scenario-level mean contrast `Delta`. If
`R` replicate-level values `Delta_r` were available with standard deviation
`SD`, the Monte Carlo standard error of the mean would be

`MCSE = SD / sqrt(R)`.

The design prespecifies a smallest contrast magnitude of interest,
`delta_min`, and chooses `R` so that `MCSE <= delta_min / 4`, giving

`R = (4 SD / delta_min)^2`.

Because `SD` is unknown before the study, the design uses a two-stage
procedure:

1. Run a fixed pilot of `R0 = 25` replicates per scenario [DECISION] under the
   same seeds and reduced recipe;
2. Estimate `SD` from the pilot, compute the required `R`, and run the
   remainder subject to a prespecified cap `R_cap` [PENDING], so a single
   scenario cannot expand without bound;
3. Report the pilot and final values together, and never select seeds or a
   run length after inspecting the direction of the contrast.

The run length is therefore reported as `R = R0 + remainder = [PENDING pilot]`,
with the MCSE target `delta_min / 4` and cap `R_cap` fixed before the pilot is
read. These are planning placeholders; they are not results and must not be
reported as such.

The same MCSE rule applies to each component contrast (ablation, benchmark, and
floor comparisons). Gate rates are reported with the binomial standard error
above.

### 7.2 Seeds

- One master seed per scenario, recorded in the manifest.
- Deterministic derivation of sub-seeds by a documented scheme, with separate
  streams for (a) drawing the season universe, (b) each season's counts,
  (c) the tuner of each method that uses randomness, and (d) any tie-breaking.
  A counter-based or `L'Ecuyer-CMRG` stream scheme is preferred over
  `seed + k` arithmetic because it avoids accidental stream overlap.
- Common random numbers: all methods within a replicate see the same realised
  data, origins, and rows. This is what makes the paired contrasts meaningful.
- The DGP seed and the method-tuning seed must be independent, so that a lucky
  or unlucky data draw does not correlate with a tuner's random path.
- Seeds are frozen in the simulation protocol before results are opened, and
  seed selection is never outcome-driven.

**ASSUMPTION** (based on [`METHODS.md`](../METHODS.md) "Software and
reproducibility"): the project will record master seeds, dependency versions,
platform, and protocol checksum for the simulation as it does for the empirical
analysis.

### 7.3 Reporting of Monte Carlo uncertainty

For every reported scenario-level quantity the supplement reports:

- the number of replicates `R` and the number of seasons per replicate `S`;
- the mean, the between-replicate SD, the MCSE, and a 95% Monte Carlo interval
  `mean +/- 1.96 MCSE` where a normal approximation is suitable;
- the full replicate-level distribution for the primary contrast, shown as a
  boxplot or equivalent in a supplement figure;
- for gate rates, the rate and its binomial standard error;
- the pilot SD and the implied required `R`, so the precision target is
  auditable;
- the seeds and the reduced-recipe configuration used.

Monte Carlo intervals quantify simulation precision only. They are not
confidence intervals for the Ontario empirical effect and are never described
as such.

---

## 8. Compute ceiling and reduced recipe

### 8.1 Total core-hour ceiling

The total compute budget for the simulation is capped at a **total core-hour
ceiling of [PENDING]**. The packet records that one full recipe run (one outer
target season, including its inner tuning) takes approximately **3.3-3.8 h on
14 cores**; this figure is an input to the planning arithmetic and is not
independently verified here. **ASSUMPTION:** the figure refers to a real-data
task-based run and scales roughly with the number of inner folds and the grid
size, not necessarily linearly. A full-recipe simulation across the retained
scenarios at the proposed replicate count would exceed any realistic ceiling,
so the reduced recipe of Section 8.2 is required.

The simulation must be completed before submission. If it is not finished
within the ceiling before the submission deadline, it is dropped from the
manuscript and the absence of simulation evidence is stated as a limitation;
it is not reported late or in partial form as if complete.

### 8.2 Reduced recipe for simulation

The simulation uses an explicitly labelled **reduced recipe**:

- fix the M2 family to the governed `offset_subset_v1` specification rather
  than searching a family;
- reduce the M1 grid to a small set of `k_ref x slope_weight` candidates
  (proposed 3 x 2 or fewer `[DECISION]`) or to a single fixed configuration with
  a small sensitivity;
- reduce the M0 detector grid to a few prespecified configurations;
- reduce or fix the online-correction axis (`bias_alpha` fixed at the frozen
  value, with one off/on level) rather than tuning it;
- reduce inner LOSO folds (for example a fixed subset of inner holdouts) where
  the estimator's precision permits;
- cache and reuse any stage artifact that does not depend on the target season.

The reduced recipe is still the governed M0 -> M1 -> M2 chain with one frozen
kit per target season and identical origins, horizons, and scoring; only the
search extent is reduced. Replicates are embarrassingly parallel across cores
and nodes, which reduces wall-clock time at fixed total core-hours. The exact
reduced grids are confirmed under Section 9 before the pilot.

### 8.3 Trade-off and stated limitation

Reducing the grids and inner folds means the simulation characterises the
**reduced recipe**, not the exact production recipe. Component rankings,
boundary choices, and gate behaviour could differ under the full grid. The
simulation is therefore used to bound *operating conditions and failure modes*
qualitatively and to support the direction of the mechanism and failure-mode
claims, not to reproduce empirical magnitudes or certify the production recipe.
This limitation must be stated in the manuscript and in the simulation
protocol. Any scenario whose conclusion is sensitive to the reduced grid
should be identified by a small full-grid sensitivity run before it is used.

---

## 9. Open decisions for the project lead

1. **Replicate precision and cap.** Confirm the fixed pilot `R0 = 25`, the
   replicate cap `R_cap`, and `delta_min` for the main contrast; `R` remains
   `[PENDING pilot]`.
2. **Retained-DGP parameter levels.** Confirm the proposed levels for shape
   skew, bimodal separation and amplitude, ignition offset, and the
   volume/dispersion combination.
3. **Reduced recipe grids.** Approve the exact M0/M1 candidate counts, the
   inner-fold subset, and the M2/bias configuration used in simulation.
4. **Peak reference in the bimodal scenario (U2).** Decide which peak counts as
   the reference for M1 scoring (first, global, or largest-lobe peak), and
   whether a peak-interval definition is adopted.
5. **Gate correctness definition.** Confirm the oracle-conditional definition of
   "M2 truly better" (per-season common rows) and whether gate behaviour is
   reported overall, at h2, and per phase.
6. **Compute platform and ceiling.** Confirm the total core-hour ceiling
   `[PENDING]`, the scheduler, and the machine-readable run-status reporting to
   be used, consistent with the repository's long-job supervision rules.

---

## Appendix A. Assumptions about code behaviour

| ID | Assumption | Basis file |
|---|---|---|
| A1 | `simulate_flu_seasons()` emits weekly Binomial counts only, with columns `season`, `newWeek`, `y`, `neg`, and no `N`, `p`, daily, age, missingness, overdispersion, trend, or multi-wave support | [`PAGe/R/simulate.R`](../../PAGe/R/simulate.R) |
| A2 | The PAGe data contract requires `season`, `weekF`, `y`, `N`, `neg`, `p`, so a simulation wrapper must add `weekF`, `N`, and `p` | [`METHODS.md`](../METHODS.md) "Surveillance data and data contract" |
| A3 | One frozen kit is trained per target season and reused at all weekly origins; weekly execution is state updating only | [`ANALYSIS_PROTOCOL.md`](../ANALYSIS_PROTOCOL.md) section 2.3; [`METHODS.md`](../METHODS.md) "Seasonal training cadence" |
| A4 | The no-ignition-gate, no-M1, and no-alignment-uncertainty ablations are implemented as switchable configurations; the bias axis is a grid value | [`ANALYSIS_PROTOCOL.md`](../ANALYSIS_PROTOCOL.md) section 4; [`ANALYSIS_DEVIATIONS_new-cycle-draft.md`](ANALYSIS_DEVIATIONS_new-cycle-draft.md) D-22 |
| A5 | The adoption gate uses the floor-and-variability rule and can be observed per season | [`ANALYSIS_PROTOCOL_v2.0-draft.md`](ANALYSIS_PROTOCOL_v2.0-draft.md) section 2 |
| A6 | The forecast score is the clipped phase-weighted Bernoulli cross-entropy with equal-week then equal-season aggregation; WIS and coverage use the protocol's predictive quantiles | [`ANALYSIS_PROTOCOL_v2.0-draft.md`](ANALYSIS_PROTOCOL_v2.0-draft.md) section 5; [`METHODS.md`](../METHODS.md) "Outcomes and descriptive scoring" |
| A7 | The reported ~3.3-3.8 h per full recipe fold on 14 cores is a planning input from the packet and is not verified in this document | Task packet |
| A8 | The M2 family, M1 grid, M0 grid, and bias axis are the tunable surfaces described in protocol v2.0 | [`ANALYSIS_PROTOCOL_v2.0-draft.md`](ANALYSIS_PROTOCOL_v2.0-draft.md) section 2 |
| A9 | The legacy GAM requires daily by-age counts and mvgam is a weekly comparator excluded by scope | [`ANALYSIS_PROTOCOL_v2.0-draft.md`](ANALYSIS_PROTOCOL_v2.0-draft.md) section 1.3; [`ANALYSIS_PROTOCOL.md`](../ANALYSIS_PROTOCOL.md) section 3 |

## Appendix B. Sources read

- [`manuscript/METHODS.md`](../METHODS.md)
- [`manuscript/drafts/ANALYSIS_PROTOCOL_v2.0-draft.md`](ANALYSIS_PROTOCOL_v2.0-draft.md)
- [`manuscript/drafts/ANALYSIS_DEVIATIONS_new-cycle-draft.md`](ANALYSIS_DEVIATIONS_new-cycle-draft.md)
- `/tmp/.../scratchpad/wei/journal_fit_report.md` (journal-fit audit)
- [`manuscript/SKELETON.md`](../SKELETON.md) section 5
- [`manuscript/PLAN.md`](../PLAN.md) phase 5 and section 5
- [`manuscript/ANALYSIS_PROTOCOL.md`](../ANALYSIS_PROTOCOL.md) sections 2 and 4
- [`manuscript/LITERATURE_REVIEW.md`](../LITERATURE_REVIEW.md) "Risks and limitations"
- [`PAGe/R/simulate.R`](../../PAGe/R/simulate.R)
