# PAGe season calendar and alignment domain

PAGe modelling seasons start at MMWR week 27. For an observation date, the
canonical adapter derives `season`, `start_year`, `week`, `nW_true`, `weekF`,
and `weekS` with `page_season_calendar()`. The source CSV/PHO `season` field is
retained as `pho_season` for audit only and is not used for modelling when a
week-start date is available.

`weekF` is the chronological July-start coordinate: week 1 is MMWR week 27 of
the start year and week `nW_true` is MMWR week 26 of the following year.
`weekS` is the PHO-style week-35 interpretation coordinate only.

Alignment uses the plain shift

```r
newWeek = weekF - iWeek + anchorWeek
```

There is no cyclic wrap or edge clamp. The reference template domain is
`1:52`; shifted rows below 1 or above 52 are retained with
`alignment_out_of_domain = TRUE` for audit, excluded from template fitting,
and yield missing interpolation outside the fitted domain during prediction.
Each reference object records `out_of_domain_by_season` so a run can report
the aggregate count by season without exposing PHU or raw surveillance rows.

The same support rule applies to online alignment. For every candidate
transform, observations whose transformed coordinate is outside `1:52` are
flagged as `alignment_out_of_domain` and excluded from that candidate's
objective. Candidate objectives are means over their admissible rows and
require at least four admissible rows; candidates below that minimum are
infeasible. Template evaluation and prediction never clamp an out-of-domain
coordinate to an endpoint. Forecast targets use a separate availability
contract: a target beyond `nW_true` is `out_of_season`, while an in-season
target outside template support is retained with
`forecast_available = FALSE` and reason
`aligned_week_outside_template_support`.

Walk-forward and replay inputs are prefix-checked at every origin `t`: rows
with `weekF > t` are rejected before M1/M2 computation.
