#!/usr/bin/env Rscript

# Prepare the governed 11-season expert decimal timing annotation campaign.
#
# Inputs are explicit and never overwritten. The historical prepared snapshot
# supplies the first 10 eligible seasons; the ORVT file supplies the complete
# 2025-26 season, replacing the deliberately partial 2025-26 rows in the
# historical snapshot.

parse_args <- function(args) {
  out <- list()
  for (token in args) {
    if (!grepl("^--[^=]+=", token)) stop("Arguments must use --name=value syntax: ", token, call. = FALSE)
    pieces <- strsplit(sub("^--", "", token), "=", fixed = TRUE)[[1L]]
    out[[pieces[[1L]]]] <- paste(pieces[-1L], collapse = "=")
  }
  out
}

`%||%` <- function(x, y) if (is.null(x)) y else x

opts <- parse_args(commandArgs(trailingOnly = TRUE))
historical_path <- opts$historical %||% stop("Provide --historical=PATH to prepared_data_all_seasons.rds", call. = FALSE)
orvt_path <- opts$orvt %||% stop("Provide --orvt=PATH to complete ORVT lab-testing CSV", call. = FALSE)
output_dir <- opts$output %||% "artifacts/expert-timing-annotation-v1-pass1"
annotator <- opts$annotator %||% "lennon"
annotation_version <- opts$`annotation-version` %||% "labels-v1-pass1"
positivity_version <- opts$`positivity-version` %||% "influenza-a-positivity-v1"

if (!file.exists(historical_path)) stop("Historical snapshot not found: ", historical_path, call. = FALSE)
if (!file.exists(orvt_path)) stop("ORVT source not found: ", orvt_path, call. = FALSE)
if (dir.exists(output_dir) || file.exists(output_dir)) stop("Refusing to overwrite existing output: ", output_dir, call. = FALSE)

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(output_dir, "reviews"), recursive = TRUE, showWarnings = FALSE)

# Source only the small dependency surface needed for campaign preparation.
source("PAGe/R/data_contract.R")
source("PAGe/R/season_calendar.R")
source("PAGe/R/getCurrentD.R")
source("PAGe/R/expert_timing_annotations.R")
source("PAGe/R/expert_timing_workflow.R")
source("PAGe/R/expert_timing_review_set.R")

eligible <- c(
  "2012-13", "2013-14", "2014-15", "2016-17", "2017-18", "2018-19",
  "2019-20", "2022-23", "2023-24", "2024-25", "2025-26"
)

historical <- readRDS(historical_path)
required <- c("season", "weekF", "y", "N", "p")
if (!is.data.frame(historical) || !all(required %in% names(historical))) {
  stop("Historical snapshot does not satisfy required prepared-data columns.", call. = FALSE)
}
historical <- historical[as.character(historical$season) %in% setdiff(eligible, "2025-26"), required, drop = FALSE]

orvt_2025 <- getCurrentD(data = orvt_path, season = "2025-26", include_predecessor = FALSE)
orvt_2025 <- orvt_2025[as.character(orvt_2025$season) == "2025-26", required, drop = FALSE]
if (nrow(orvt_2025) != 53L || !setequal(as.integer(orvt_2025$weekF), 1:53)) {
  stop("Complete 2025-26 annotation source must contain exactly weekF 1:53.", call. = FALSE)
}

campaign <- rbind(historical, orvt_2025)
campaign$season <- as.character(campaign$season)
campaign <- campaign[order(match(campaign$season, eligible), campaign$weekF), , drop = FALSE]
rownames(campaign) <- NULL

seen <- sort(unique(campaign$season))
if (!setequal(seen, eligible)) {
  stop("Campaign season set mismatch. Missing: ", paste(setdiff(eligible, seen), collapse = ", "), call. = FALSE)
}
counts <- table(campaign$season)
expected_counts <- c(
  "2012-13" = 52L, "2013-14" = 52L, "2014-15" = 53L,
  "2016-17" = 52L, "2017-18" = 52L, "2018-19" = 52L,
  "2019-20" = 52L, "2022-23" = 52L, "2023-24" = 52L,
  "2024-25" = 52L, "2025-26" = 53L
)
if (!identical(as.integer(counts[names(expected_counts)]), as.integer(expected_counts))) {
  stop("Campaign row counts do not match expected complete season calendars.", call. = FALSE)
}

campaign_path <- file.path(output_dir, "campaign_data.rds")
saveRDS(campaign, campaign_path, version = 3)
utils::write.csv(campaign, file.path(output_dir, "campaign_data.csv"), row.names = FALSE, na = "")

sheet <- expert_ignition_annotation_sheet(
  campaign,
  annotator = annotator,
  annotation_version = annotation_version,
  positivity_version = positivity_version
)
utils::write.csv(sheet, file.path(output_dir, "annotation_sheet.csv"), row.names = FALSE, na = "")

reviews <- review_expert_ignition_set(campaign, seasons = eligible)
if (!requireNamespace("htmlwidgets", quietly = TRUE)) {
  stop("htmlwidgets is required to save Plotly review files.", call. = FALSE)
}
for (s in eligible) {
  htmlwidgets::saveWidget(
    reviews[[s]]$plot,
    file = file.path(output_dir, "reviews", paste0(s, ".html")),
    selfcontained = FALSE,
    libdir = paste0(s, "_files")
  )
}

summary_rows <- do.call(rbind, lapply(reviews, function(x) x$summary))
utils::write.csv(summary_rows, file.path(output_dir, "season_review_summary.csv"), row.names = FALSE, na = "")

manifest <- list(
  schema = "page_expert_timing_annotation_campaign_v1",
  created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  coordinate_version = .expert_timing_coordinate_version,
  annotation_schema_version = .expert_timing_schema_version,
  annotation_version = annotation_version,
  annotator = annotator,
  positivity_version = positivity_version,
  seasons = eligible,
  historical_source = normalizePath(historical_path, winslash = "/", mustWork = TRUE),
  historical_sha256 = digest::digest(file = historical_path, algo = "sha256", serialize = FALSE),
  orvt_source = normalizePath(orvt_path, winslash = "/", mustWork = TRUE),
  orvt_sha256 = digest::digest(file = orvt_path, algo = "sha256", serialize = FALSE),
  campaign_rds_sha256 = digest::digest(file = campaign_path, algo = "sha256", serialize = FALSE),
  per_season_rows = as.list(as.integer(counts[eligible])),
  notes = c(
    "First ten eligible seasons come unchanged from the governed prepared historical snapshot.",
    "2025-26 is replaced by the complete 53-week archived ORVT series.",
    "Review plots contain observed data only and do not suggest expert labels."
  )
)
names(manifest$per_season_rows) <- eligible
jsonlite::write_json(manifest, file.path(output_dir, "manifest.json"), auto_unbox = TRUE, pretty = TRUE)

cat("Prepared expert timing annotation campaign\n")
cat("output:", normalizePath(output_dir, winslash = "/", mustWork = TRUE), "\n")
cat("seasons:", paste(eligible, collapse = ", "), "\n")
print(summary_rows)
