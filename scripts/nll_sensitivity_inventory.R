#!/usr/bin/env Rscript

# Inventory marginal NLL gains across the completed exchangeable holdout runs.
# The inputs are immutable tuning artifacts; this script does not retune models.

`%||%` <- function(x, y) if (!is.null(x)) x else y
script_file <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
script_file <- script_file %||% "scripts/nll_sensitivity_inventory.R"
repo_root <- normalizePath(file.path(dirname(script_file), ".."), mustWork = TRUE)
setwd(repo_root)
suppressPackageStartupMessages(devtools::load_all("PAGe", quiet = TRUE))

artifact_root <- Sys.getenv(
  "PAGE_ARTIFACT_ROOT",
  "/home/yeli/PAGe-bcc-artifacts/asgard-archive-20260812"
)
output_dir <- Sys.getenv(
  "PAGE_NLL_SENSITIVITY_DIR",
  file.path(artifact_root, "nll-sensitivity-20260816")
)
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

inputs <- c(
  `2017-18` = file.path(
    artifact_root, "bcc-2017-18-v2/artifacts/m2_tuning.rds"
  ),
  `2018-19` = file.path(
    artifact_root, "2018-final2-expanded-api/artifacts/m2_tuning_api.rds"
  ),
  `2022-23` = file.path(
    artifact_root, "holdouts-and-docs/2022/exchangeable/artifacts/m2_tuning.rds"
  ),
  `2023-24` = file.path(
    artifact_root, "holdouts-and-docs/2023/exchangeable/artifacts/m2_tuning.rds"
  ),
  `2024-25` = file.path(
    artifact_root, "holdouts-and-docs/2024/exchangeable/artifacts/m2_tuning.rds"
  )
)
missing <- inputs[!file.exists(inputs)]
if (length(missing)) {
  stop(
    "Missing tuning artifact(s): ",
    paste(names(missing), collapse = ", "),
    call. = FALSE
  )
}

tuning <- lapply(inputs, readRDS)
sensitivity <- PAGe::extract_nll_sensitivity(tuning)

write.csv(sensitivity$overall, file.path(output_dir, "nll_by_parameter.csv"), row.names = FALSE)
write.csv(sensitivity$by_season, file.path(output_dir, "nll_by_parameter_season.csv"), row.names = FALSE)
write.csv(sensitivity$gains, file.path(output_dir, "adjacent_nll_gains.csv"), row.names = FALSE)
write.csv(
  sensitivity$matched_gains,
  file.path(output_dir, "matched_adjacent_nll_gains.csv"),
  row.names = FALSE
)
saveRDS(sensitivity, file.path(output_dir, "nll_sensitivity.rds"))

gain_groups <- split(
  sensitivity$gains,
  list(sensitivity$gains$run, sensitivity$gains$parameter),
  drop = TRUE
)
inventory <- do.call(rbind, lapply(gain_groups, function(d) {
  positive <- d$adjacent_gain[is.finite(d$adjacent_gain) & d$adjacent_gain > 0]
  best <- which.min(d$best_metric)
  positive_per_unit <- d$gain_per_unit[
    is.finite(d$gain_per_unit) & d$gain_per_unit > 0
  ]
  data.frame(
    run = d$run[1L], parameter = d$parameter[1L],
    tested_values = nrow(d),
    tested_min = min(d$value), tested_max = max(d$value),
    best_value = d$value[best], best_metric = d$best_metric[best],
    global_best = d$global_best[1L],
    largest_positive_adjacent_gain = if (length(positive)) max(positive) else 0,
    median_positive_adjacent_gain = if (length(positive)) stats::median(positive) else 0,
    largest_positive_gain_per_unit = if (length(positive_per_unit)) {
      max(positive_per_unit)
    } else {
      0
    },
    median_positive_gain_per_unit = if (length(positive_per_unit)) {
      stats::median(positive_per_unit)
    } else {
      0
    },
    last_adjacent_gain = d$adjacent_gain[nrow(d)],
    stringsAsFactors = FALSE
  )
}))
rownames(inventory) <- NULL
write.csv(inventory, file.path(output_dir, "parameter_gain_inventory.csv"), row.names = FALSE)

matched <- sensitivity$matched_gains
matched_groups <- if (nrow(matched)) {
  split(matched, list(matched$run, matched$parameter), drop = TRUE)
} else {
  list()
}
matched_inventory <- if (length(matched_groups)) {
  do.call(rbind, lapply(matched_groups, function(d) {
    positive <- d$adjacent_gain[is.finite(d$adjacent_gain) & d$adjacent_gain > 0]
    positive_per_unit <- d$gain_per_unit[
      is.finite(d$gain_per_unit) & d$gain_per_unit > 0
    ]
    data.frame(
      run = d$run[1L], parameter = d$parameter[1L],
      matched_moves = nrow(d),
      largest_positive_gain = if (length(positive)) max(positive) else 0,
      median_positive_gain = if (length(positive)) stats::median(positive) else 0,
      largest_positive_gain_per_unit = if (length(positive_per_unit)) {
        max(positive_per_unit)
      } else {
        0
      },
      median_positive_gain_per_unit = if (length(positive_per_unit)) {
        stats::median(positive_per_unit)
      } else {
        0
      },
      stringsAsFactors = FALSE
    )
  }))
} else {
  data.frame()
}
if (nrow(matched_inventory)) rownames(matched_inventory) <- NULL
write.csv(
  matched_inventory,
  file.path(output_dir, "matched_parameter_gain_inventory.csv"),
  row.names = FALSE
)

plot_nll <- PAGe::plot_nll_sensitivity(sensitivity, statistic = "best_metric")
plot_gain <- PAGe::plot_nll_sensitivity(sensitivity, statistic = "adjacent_gain")
ggplot2::ggsave(
  file.path(output_dir, "nll_vs_parameter.png"), plot_nll,
  width = 14, height = 10, units = "in", dpi = 160
)
ggplot2::ggsave(
  file.path(output_dir, "adjacent_gain_vs_parameter.png"), plot_gain,
  width = 14, height = 10, units = "in", dpi = 160
)

cat("NLL sensitivity inventory written to:", output_dir, "\n")
cat("Runs:", paste(names(inputs), collapse = ", "), "\n")
cat("Parameters:", paste(sensitivity$parameters, collapse = ", "), "\n")
