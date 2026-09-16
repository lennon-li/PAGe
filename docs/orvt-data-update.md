# ORVT weekly update and historical rebuild

`PAGe::getCurrentD()` is the operational reader for the Public Health Ontario
ORVT lab-testing CSV. With `season = NULL`, it derives the current PAGe season
from the MMWR calendar using week 27 as the season origin. It tries

1. `ORVT_Lab_Testing_Data_<previous-season>_<season>.csv`
2. `ORVT_Lab_Testing_Data_<season>_<next-season>.csv`

under the PHO ORVT directory and records the selected URL, UTC retrieval time,
SHA-256 digest, layout, observed week count, and latest requested-season week
end date. The package default retains the predecessor season for compatibility;
set `include_predecessor = FALSE` for a current-season-only snapshot. A local
file can be supplied with `data =`, and `PAGe.orvt_base_url` or
`PAGe.orvt_file_name` can override default URL resolution. Use `cache_dir =`
for a timestamped raw download archive.

The reader accepts both PHO column layouts (`Surveillance period` and
`Respiratory season`) and maps the PAGe season from the dated week start and
`MMWRweek`, not from that PHO label. This matters because PHO labels currently
start at MMWR week 35 while PAGe seasons start at week 27. The PHO label is
retained in `pho_season` for audit. Rows are validated (`0 <= y <= N`), exact
PHU-week duplicates are removed, and conflicting duplicates stop the read. When
the feed includes the exact `Ontario` public-health-unit row, its provincial
`N` and `y` are used; the separately summed PHU rows must agree exactly
(integer-count tolerance 0), or the read stops. The PHU-only totals and
consistency/source flags are retained in the result. If the exact row is absent
for a week, the PHU sum is used with a warning and
`provincial_value_source = "PHU sum"`; matching names such as `Eastern Ontario
Health Unit` remain PHUs.

For a weekly operational snapshot:

```r
current <- PAGe::getCurrentD(
  include_predecessor = FALSE,
  cache_dir = "/secure/orvt-cache"
)
current <- PAGe::prepare_surveillance_data(current)
```

The historical builder is intentionally separate:

```sh
Rscript scripts/build_flu_hist_orvt.R \
  --input=/home/yeli/FLU/flu_testing_data.csv \
  --orvt=/path/ORVT_Lab_Testing_Data_2024-25_2025-26.csv \
  --orvt=/path/ORVT_Lab_Testing_Data_2025-26_2026-27.csv \
  --dry-run
```

Feed arguments should be supplied oldest to newest. The script validates the
completed 2024-25 overlap with a revision-aware rule: source-label weeks other
than the final 12 require exact `N` and `y`; the final 12 allow relative `N`
drift up to 0.5% and absolute `y` drift up to `max(1, 0.5% of y)`, with those
within-tolerance differences warning only. Any mismatch outside those limits
stops the rebuild. The compared rows are ordered by the feed's `weekS`
source-label index, not by hardcoded calendar week numbers. The builder also
requires 53 unique MMWR weeks for the revised 2025-26 PHO label, checks the
rebuilt canonical counts with `prepare_surveillance_data()`, and refuses to
overwrite an output. Its dry-run prints a per-week 2024-25 comparison table
and the number of 2025-26 weeks that would be written.
Without `--dry-run`, it writes the requested CSV outside the repository and a
same-name `.manifest.json` containing input/feed/output hashes, the comparison
rule, the full per-week agreement table, and per-season row counts. It does not
write to `/home/yeli/FLU` during this task.
