# Test-volume lag association study — 2026-09-29

## Purpose

Exploratory association analysis before nested LOSO. The goal is to understand how recent influenza A testing-volume history is associated with future positivity after controlling for the current PAGe A1 positivity state. This is not a forecasting promotion test and not a causal analysis.

## Data and repeated-measures structure

Source: `artifacts/m2-v2-flu-ab-geometry-v1/flu_ab_weekly_v1.csv`.

A common exact-history ledger was used for every candidate. Each origin requires four exact prior weekly test-volume observations, so candidate comparisons use the same rows.

- 11 historical seasons
- +1 horizon: 431 rows
- +2 horizon: 420 rows
- total: 851 origin/target rows

Primary model: beta-binomial mixed-effects regression with a season random intercept:

`cbind(y_target, N_target-y_target) ~ growth1 + growth2 + N_history + offset(logit_current) + (1|season)`

The beta-binomial accommodates extra-binomial dispersion and reduces the risk that modern high-denominator weeks mechanically dominate a binomial likelihood. Season is the repeated-measures grouping factor.

A within-season AR(1) latent correlation sensitivity model was also fitted for a smaller representative candidate set. The +1 AR(1) models converged. The +2 random-intercept-plus-AR1 models did not have a positive-definite Hessian and are not interpreted.

## Test-volume representations

All lagged changes use natural-log test volume. Let

- `d1 = log(N_t) - log(N_{t-1})`
- `d2 = log(N_{t-1}) - log(N_{t-2})`
- `d3 = log(N_{t-2}) - log(N_{t-3})`
- `d4 = log(N_{t-3}) - log(N_{t-4})`

Candidates include endpoint slopes, trailing OLS slopes, normalized raw-scale slopes, exponentially weighted distributed lags, unrestricted 2/3/4-lag models, Almon polynomial distributed lags, recent-vs-older split lags, testing acceleration, cumulative log-volume rise from week 8, and limited interactions with positivity growth.

## Main association pattern

### Recent two-week test-volume growth

The strongest and most stable simple pattern is a negative association between recent test-volume growth and future positivity conditional on current positivity and its recent growth.

For the unrestricted two-lag model:

+1 week:

- `d1`: beta = -0.3952, p = 4.38e-11
- `d2`: beta = -0.2410, p = 2.33e-05

+2 weeks:

- `d1`: beta = -0.6566, p = 8.22e-14
- `d2`: beta = -0.3716, p = 1.04e-05

Adding the two lags improves AIC versus the A1/OFF model by 43.3 at +1 and 53.0 at +2.

A 0.1 increase in the relevant log-volume increment is roughly a 10.5% increase in testing. The fitted conditional odds multipliers are approximately:

- +1: 0.961 for d1 and 0.976 for d2
- +2: 0.936 for d1 and 0.964 for d2

These are associations, not causal effects of testing.

### Four-lag model

In the random-intercept beta-binomial model, the recent two lags remain strongly negative while older lags are close to null:

+1:

- d1 = -0.3980
- d2 = -0.2277
- d3 = +0.0461, p = 0.32
- d4 = -0.0435, p = 0.35

+2:

- d1 = -0.6591
- d2 = -0.3641
- d3 = +0.0273, p = 0.70
- d4 = -0.0549, p = 0.45

Thus the primary repeated-season model concentrates the association in the most recent two weekly changes.

However, the +1 AR(1) sensitivity fit gives negative estimates for all four lags, including d3 and d4. Therefore the exact lag length is not settled by this association study; nested out-of-season validation remains necessary.

### Recent-versus-older split

Using mean growth over the recent two weeks and the preceding two weeks:

+1:

- recent2 = -0.6265, p = 1.76e-11
- older2 = -0.0147, p = 0.84

+2:

- recent2 = -1.0154, p = 2.93e-13
- older2 = -0.0644, p = 0.58

This is consistent with a short-memory behavioral/surveillance response in the primary model.

### Testing acceleration

Define `accel22 = mean(d1,d2) - mean(d3,d4)`.

- +1 beta = -0.2298, p = 5.06e-05
- +2 beta = -0.3603, p = 2.53e-05

The acceleration-only model improves AIC versus OFF by 14.0 at +1 and 15.1 at +2.

Thus a recent acceleration in testing is associated with lower subsequent positivity than the baseline positivity trajectory alone would imply.

### Exponentially weighted recent growth

With recent lags weighted more heavily (`lambda = 0.5`):

- +1 beta = -0.6772, p = 1.35e-10
- +2 beta = -1.1478, p = 1.84e-13

AIC improves by 36.8 at +1 and 48.0 at +2 versus OFF.

This provides a low-dimensional distributed-lag candidate for later nested LOSO.

### Cumulative rise from week 8

`rel8 = log(N_t) - log(N_week8)` is strongly negatively associated with future positivity:

- +1 beta = -0.2353, p = 2.73e-08
- +2 beta = -0.5252, p = 2.01e-23

It produces the best +2 AIC among the screened random-intercept models, improving AIC by 91.0 versus OFF.

This is statistically striking but potentially more vulnerable to seasonal phase and surveillance-regime confounding than the local lag features. It should not be interpreted as a preferred forecasting predictor without nested LOSO.

### Interaction with positivity growth

For the exponentially weighted recent-volume feature, an interaction with current positivity growth improves +1 fit.

+1:

- volume beta = -0.7926
- `growth1 x volume` beta = +0.6381, p = 0.00051

The positive interaction means the negative volume association is attenuated when positivity itself is rising rapidly. The interaction is not significant at +2 (`p = 0.207`).

This is compatible with, but does not prove, a feedback mechanism in which expansion of testing contains additional surveillance information beyond positivity growth.

## Original versus log scale

The previously completed shape analysis showed that log test volume is generally more linear within the operational season window than raw test volume. In the association models, log-scale short-window forms also generally outperform normalized raw-scale slopes by AIC.

This supports retaining log(N) as the primary transformation for distributed-lag research rather than fitting season-specific Box-Cox powers.

## AR(1) sensitivity

For +1, the beta-binomial model with explicit within-season AR(1) correlation preserves the main conclusions:

- EXP050: beta = -0.5823, p = 3.66e-06
- d1 in DL2: beta = -0.2957, p = 7.13e-06
- d2 in DL2: beta = -0.2017, p = 0.00178
- rel8: beta = -0.4370, p = 3.04e-11
- acceleration: beta = -0.1382, p = 0.0497
- EXP050 x positivity-growth interaction: p = 0.00262

Thus the +1 associations are not removed by explicitly modeling serial correlation.

The analogous +2 AR(1) models fail Hessian/convergence diagnostics under both random-intercept-plus-AR1 and season-fixed-effect-plus-AR1 formulations. Those +2 AR(1) coefficient estimates are not used.

## Interpretation

The association pattern is consistent with the proposed feedback-loop hypothesis:

1. positivity rises;
2. testing demand/clinical testing expands;
3. recent denominator growth carries information not contained in positivity alone;
4. conditional on the current positivity trajectory, rapid test-volume expansion is associated with lower future positivity than A1 would otherwise extrapolate.

The strongest primary-model signal is concentrated in the last one to two weekly volume changes. Testing acceleration is also associated. The cumulative seasonal rise is very strong, especially at +2, but may partly proxy epidemic phase or surveillance era.

## Important limitations

- This is an exploratory association screen over many candidate forms; p-values are descriptive and are not multiplicity-adjusted.
- There are only 11 seasons.
- Denominator measurement regimes differ historically, with limited fully modern type-specific ORVT history.
- Weekly origins within a season overlap heavily; repeated-measures modeling helps but does not convert these results into independent evidence.
- The results are predictive associations, not evidence that increased testing causes a later change in positivity.
- No candidate has been selected or promoted from these association results.

## Implication for nested LOSO

The association study supports carrying the following scientifically distinct families into nested LOSO:

1. OFF / exact A1;
2. two recent unrestricted log-volume lags (`d1 + d2`);
3. exponentially weighted recent log-volume growth (especially lambda around 0.5);
4. recent-vs-older split / acceleration;
5. cumulative relative level from week 8, explicitly treated as a higher-confounding-risk candidate;
6. a limited volume-by-positivity-growth interaction.

The nested LOSO should choose among these inside each outer training set. All candidates must use the same exact-history rows, and OFF must remain the simplest selectable model.
