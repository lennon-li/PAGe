#!/usr/bin/env bash
set -euo pipefail

root=/home/yeli/PAGe-bcc-artifacts/asgard-archive-20260812
run="$root/2018-final2-expanded-api"
out="$root/replays"
mkdir -p "$out"

# Zero-token OS watcher: finalize only after the detached expansion exits.
while test -f "$run/status.tsv"; do
  last=$(tail -n 1 "$run/status.tsv" | cut -f2)
  case "$last" in
    success) break ;;
    failed) exit 1 ;;
  esac
  sleep 60
done

src="$run/artifacts"
cp -p "$src/holdout_2018_19_replay_api.rds" "$out/replay_2018_19_final2_expanded_api.rds"
cp -p "$src/holdout_2018_19_metrics_api.csv" "$out/metrics_2018_19_final2_expanded_api.csv"
cp -p "$src/holdout_2018_19_predictions_api.csv" "$out/predictions_2018_19_final2_expanded_api.csv"

Rscript - <<'RS'
out <- '/home/yeli/PAGe-bcc-artifacts/asgard-archive-20260812/replays'
root <- '/home/yeli/PAGe-bcc-artifacts/asgard-archive-20260812'
replay_files <- c(
  '2017-18 BCC v2' = file.path(out, 'replay_2017_18_bcc_v2.rds'),
  '2018-19 final2 expanded API' = file.path(out, 'replay_2018_19_final2_expanded_api.rds'),
  '2022-23 API' = file.path(out, 'replay_2022_23_api.rds'),
  '2023-24 exchangeable' = file.path(out, 'replay_2023_24_exchangeable.rds'),
  '2024-25 exchangeable' = file.path(out, 'replay_2024_25_exchangeable.rds')
)
selection_files <- c(
  '2017-18 BCC v2' = file.path(root, 'bcc-2017-18-v2/artifacts/season_selection.rds'),
  '2018-19 final2 expanded API' = file.path(root, '2018-final2-expanded-api/artifacts/season_selection.rds'),
  '2022-23 API' = file.path(root, '2022-final-expanded-v3/m2_tuning_api.rds'),
  '2023-24 exchangeable' = file.path(root, 'holdouts-and-docs/2023/exchangeable/artifacts/m2_tuning.rds'),
  '2024-25 exchangeable' = file.path(root, 'holdouts-and-docs/2024/exchangeable/artifacts/m2_tuning.rds')
)
boundary_files <- c(
  '2017-18 BCC v2' = file.path(root, 'bcc-2017-18-v2/artifacts/m2_tuning.rds'),
  '2018-19 final2 expanded API' = file.path(root, '2018-final2-expanded-api/artifacts/m2_boundary_report_final.csv'),
  '2022-23 API' = file.path(root, '2022-final-expanded-v3/m2_tuning_api.rds'),
  '2023-24 exchangeable' = file.path(root, 'holdouts-and-docs/2023/exchangeable/artifacts/boundary_report.csv'),
  '2024-25 exchangeable' = file.path(root, 'holdouts-and-docs/2024/exchangeable/artifacts/boundary_report.csv')
)
eligible <- function(s, holdout) setdiff(s$data_seasons, c(s$exclude_seasons, holdout))
rows <- lapply(names(replay_files), function(label) {
  x <- readRDS(replay_files[[label]])
  s_obj <- readRDS(selection_files[[label]])
  s <- if (inherits(s_obj, 'page_m2_tuning')) s_obj$selection else s_obj
  s_ok <- setequal(s$training_seasons, eligible(s, x$season)) && length(s$application_seasons) == 0L
  b_path <- boundary_files[[label]]
  b_obj <- if (grepl("\\.csv$", b_path)) read.csv(b_path, stringsAsFactors = FALSE) else readRDS(b_path)
  b <- if (is.data.frame(b_obj)) b_obj else b_obj$boundary_report
  boundary_ok <- !is.null(b) && !any(b$decision == 'expand_required')
  o <- x$metrics$overall; h <- x$metrics$horizon; p <- x$metrics$phase
  data.frame(
    variant = label, holdout = x$season,
    exchangeable = s_ok, interior_non_null = boundary_ok, status = x$status,
    n_predictions = o$n_predictions, bernoulli_nll = o$bernoulli_nll, mae = o$mae,
    lead1_mae = h$mae[match('1', h$lead)], lead2_mae = h$mae[match('2', h$lead)],
    early_mae = p$mae[match('early', p$phase)], late_mae = p$mae[match('late', p$phase)],
    stringsAsFactors = FALSE
  )
})
tab <- do.call(rbind, rows); tab <- tab[order(tab$holdout), ]
write.csv(tab, file.path(out, 'comparison_apples_to_apples.csv'), row.names = FALSE)
fmt <- function(x) sprintf('%.6f', x)
lines <- c(
  '# Apples-to-apples holdout replay comparison', '',
  'Included rows use all eligible seasons exchangeably (the held-out label and permanent exclusions are the only removals) and have no unresolved non-null boundary winner. Explicit null/drop choices at valid domain edges are allowed.', '',
  '| Holdout | Variant | NLL | MAE | Lead 1 MAE | Lead 2 MAE | Predictions |',
  '|---|---|---:|---:|---:|---:|---:|')
for (i in seq_len(nrow(tab))) {
  z <- tab[i,]
  lines <- c(lines, sprintf('| %s | %s | %s | %s | %s | %s | %d |', z$holdout, z$variant, fmt(z$bernoulli_nll), fmt(z$mae), fmt(z$lead1_mae), fmt(z$lead2_mae), z$n_predictions))
}
lines <- c(lines, '', 'Lower NLL and MAE are better. Cross-season differences remain descriptive because the held-out seasons differ; same-season variant comparisons are the strongest comparisons.')
writeLines(lines, file.path(out, 'comparison_apples_to_apples.md'))
RS

find "$out" -maxdepth 1 -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > "$out/SHA256SUMS"
