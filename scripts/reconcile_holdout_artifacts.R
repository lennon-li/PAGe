#!/usr/bin/env Rscript

# Reconcile governed 11-season exchangeable holdout artifacts across the archive.
#
# This script is a deterministic, read-only reconciliation tool. It discovers,
# validates, and audits season-local holdout artifacts, ensuring strict exchangeable
# protocol adherence, verification of 10 training seasons and fixed exclusions,
# separation of diagnostic/variant holdouts (such as 2015-16), and emission of
# descriptive comparisons without inferential testing.

VALID_SEASONS <- c(
  "2012-13", "2013-14", "2014-15", "2016-17", "2017-18",
  "2018-19", "2019-20", "2022-23", "2023-24", "2024-25", "2025-26"
)

PERMANENT_EXCLUSIONS <- c("2011-12", "2015-16", "2020-21", "2021-22")

DEFAULT_ARCHIVE_ROOT <- Sys.getenv(
  "PAGE_ARTIFACT_ROOT",
  "/mnt/nfsv4/Users/yeli/PAGe-artifacts/seasonal-archive-20260818"
)

KNOWN_GOVERNED_RUN_PATTERNS <- list(
  "2012-13" = c("2012-13-current-api-20260901", "2012-13-current-api", "2012-13-latest-api"),
  "2013-14" = c("2013-14-current-api-20260901", "2013-14-current-api", "2013-14-latest-api"),
  "2014-15" = c("2014-15-current-api-20260902-r4", "2014-15-current-api-20260902-r3", "2014-15-latest-api-20260818", "2014-15-latest-api"),
  "2016-17" = c("2016-17-current-api-20260902-r4", "2016-17-current-api-20260902-r3", "bcc-2016-17-v5", "bcc-2016-17-v4", "bcc-2016-17-v3", "bcc-2016-17-v2", "bcc-2016-17-v1"),
  "2017-18" = c("2017-18-current-api-20260902-r3", "bcc-2017-18-v2", "bcc-2017-18"),
  "2018-19" = c("2018-19-current-api-20260902-r3", "2018-final2-expanded-api", "2018-final2-expanded", "2018-final2", "bcc-2018-19"),
  "2019-20" = c("2019-20-current-api-20260902-r3", "2019-20-latest-api-20260818-r2", "2019-20-latest-api-20260818", "2019-20-latest-api"),
  "2022-23" = c("2022-23-current-api-20260902-r3", "2022-final-expanded-v3", "2022-final-expanded-v2", "2022-23-api", "exchangeable"),
  "2023-24" = c("2023-24-current-api-20260902-r3", "exchangeable", "2023-24-exchangeable"),
  "2024-25" = c("2024-25-current-api-20260902-r3", "exchangeable", "2024-25-exchangeable"),
  "2025-26" = c("2025-26-current-api-20260902-r3", "2025-capped-api-20260815-r2", "2025-capped-api", "2025-final-api", "2025-compact-handoff-20260816b")
)

`%||%` <- function(x, y) if (!is.null(x) && length(x) > 0L && !all(is.na(x))) x else y

print_usage <- function() {
  cat(
    "Usage: Rscript scripts/reconcile_holdout_artifacts.R [options]\n\n",
    "Options:\n",
    "  --artifact-root PATH    Path to seasonal archive root directory\n",
    "                          (default: $PAGE_ARTIFACT_ROOT or /mnt/nfsv4/Users/yeli/PAGe-artifacts/seasonal-archive-20260818)\n",
    "  --output-prefix PATH    Base path/prefix for generated CSV and Markdown reports\n",
    "                          (e.g., /path/to/reconciliation_report)\n",
    "  --strict                Exit with status 1 if any of the 11 valid seasons is not complete\n",
    "  --no-strict             Exit with status 0 regardless of incomplete runs (default)\n",
    "  -h, --help              Show this help message and exit\n\n",
    "Description:\n",
    "  Discovers and validates season-local holdout artifacts across the 11 exchangeable\n",
    "  seasons (2012-13 through 2025-26, excluding fixed non-exchangeable seasons). Audits\n",
    "  terminal status, 10 training seasons, fixed exclusions, finite NLL/MAE, and\n",
    "  boundary decisions without inferential statistical claims.\n",
    sep = ""
  )
}

parse_cli_args <- function(args) {
  cfg <- list(
    artifact_root = DEFAULT_ARCHIVE_ROOT,
    output_prefix = NULL,
    strict = FALSE
  )
  i <- 1L
  while (i <= length(args)) {
    arg <- args[i]
    if (arg %in% c("-h", "--help")) {
      print_usage()
      quit(save = "no", status = 0L)
    } else if (arg == "--artifact-root") {
      i <- i + 1L
      if (i > length(args)) stop("--artifact-root requires a directory path.")
      cfg$artifact_root <- args[i]
    } else if (grepl("^--artifact-root=", arg)) {
      cfg$artifact_root <- sub("^--artifact-root=", "", arg)
    } else if (arg == "--output-prefix") {
      i <- i + 1L
      if (i > length(args)) stop("--output-prefix requires a path prefix.")
      cfg$output_prefix <- args[i]
    } else if (grepl("^--output-prefix=", arg)) {
      cfg$output_prefix <- sub("^--output-prefix=", "", arg)
    } else if (arg == "--strict") {
      cfg$strict <- TRUE
    } else if (arg == "--no-strict") {
      cfg$strict <- FALSE
    } else {
      stop("Unknown argument: ", arg, "\nRun with --help for usage.")
    }
    i <- i + 1L
  }
  cfg
}

safe_read_rds <- function(path) {
  if (!is.null(path) && file.exists(path)) {
    tryCatch(readRDS(path), error = function(e) NULL)
  } else {
    NULL
  }
}

safe_read_csv <- function(path) {
  if (!is.null(path) && file.exists(path)) {
    tryCatch(utils::read.csv(path, stringsAsFactors = FALSE), error = function(e) NULL)
  } else {
    NULL
  }
}

safe_read_lines <- function(path) {
  if (!is.null(path) && file.exists(path)) {
    tryCatch(readLines(path, warn = FALSE), error = function(e) character(0))
  } else {
    character(0)
  }
}

find_run_directories <- function(root_dir) {
  if (!dir.exists(root_dir)) return(character(0))

  # 1. Exact paths from KNOWN_GOVERNED_RUN_PATTERNS under season, season/runs, root, or root/runs
  governed_paths <- character(0)
  for (s in names(KNOWN_GOVERNED_RUN_PATTERNS)) {
    patterns <- KNOWN_GOVERNED_RUN_PATTERNS[[s]]
    season_candidates <- c(
      file.path(root_dir, s, patterns),
      file.path(root_dir, s, "runs", patterns),
      file.path(root_dir, patterns),
      file.path(root_dir, "runs", patterns)
    )
    existing <- season_candidates[dir.exists(season_candidates)]
    if (length(existing) > 0L) governed_paths <- c(governed_paths, existing[1L])
  }

  # 2. Explicitly named legacy exchangeable paths under season/holdouts-and-docs*/exchangeable
  legacy_exchangeable_paths <- character(0)
  for (s in VALID_SEASONS) {
    year4 <- substr(s, 1L, 4L)
    legacy_exchangeable_paths <- c(
      legacy_exchangeable_paths,
      file.path(root_dir, s, "holdouts-and-docs", "exchangeable"),
      file.path(root_dir, s, paste0("holdouts-and-docs-", year4), "exchangeable"),
      file.path(root_dir, s, paste0("holdouts-and-docs-", s), "exchangeable"),
      file.path(root_dir, "holdouts-and-docs", year4, "exchangeable"),
      file.path(root_dir, "holdouts-and-docs", s, "exchangeable")
    )
  }

  # 3. Explicitly needed 2015-16 holdouts-and-docs diagnostic path
  diagnostic_2015_paths <- c(
    file.path(root_dir, "2015-16", "holdouts-and-docs"),
    file.path(root_dir, "2015-16", "holdouts-and-docs-2015"),
    file.path(root_dir, "2015-16", "holdouts-and-docs-2015-16"),
    file.path(root_dir, "holdouts-and-docs", "2015-16"),
    file.path(root_dir, "holdouts-and-docs", "2015"),
    file.path(root_dir, "2015-16", "runs", "holdouts-and-docs"),
    file.path(root_dir, "2015-16")
  )

  candidate_dirs <- unique(c(governed_paths, legacy_exchangeable_paths, diagnostic_2015_paths))
  candidate_dirs <- candidate_dirs[dir.exists(candidate_dirs)]

  if (length(candidate_dirs) == 0L) return(character(0))

  # Filter out internal/helper non-run subdirectories
  excluded_dir_pattern <- "/(_shared|data|docs|scripts|PAGe|rendered|checkpoints|artifacts|logs|m0_settlement|_backup.*|checkpoints_.*|artifacts_.*)(/|$)"
  candidate_dirs <- candidate_dirs[!grepl(excluded_dir_pattern, candidate_dirs)]

  # A valid run directory must contain at least one run artifact/log/manifest
  run_indicators <- c(
    "status\\.tsv", "status\\.txt", "run\\.log", "run_manifest\\.rds", "launch_manifest\\.txt",
    "run_summary\\.rds", "season_selection\\.rds", "m2_tuning.*\\.rds", "holdout_.*_replay.*\\.rds",
    "page-m2-holdout-replay\\.rds", "candidate_pre_holdout.*\\.rds"
  )
  indicator_pattern <- paste(run_indicators, collapse = "|")

  is_run_dir <- vapply(candidate_dirs, function(d) {
    files <- list.files(d, full.names = FALSE)
    artifact_files <- if (dir.exists(file.path(d, "artifacts"))) list.files(file.path(d, "artifacts"), full.names = FALSE) else character(0)
    any(grepl(indicator_pattern, c(files, artifact_files)))
  }, logical(1L))

  valid_run_dirs <- candidate_dirs[is_run_dir]

  # Exclude container directories if their subdirectories are the actual run directories
  is_parent_container <- vapply(valid_run_dirs, function(d) {
    sub_runs <- setdiff(valid_run_dirs, d)
    any(startsWith(sub_runs, paste0(d, "/")))
  }, logical(1L))

  valid_run_dirs[!is_parent_container]
}

extract_run_status <- function(run_dir) {
  status_tsv <- file.path(run_dir, "status.tsv")
  if (file.exists(status_tsv)) {
    lines <- safe_read_lines(status_tsv)
    if (length(lines) > 1L) {
      last_line <- lines[length(lines)]
      parts <- strsplit(last_line, "\t")[[1L]]
      if (length(parts) >= 2L) {
        return(list(
          status = parts[2L],
          detail = if (length(parts) >= 3L) parts[3L] else "",
          timestamp = parts[1L]
        ))
      }
    }
  }

  status_txt <- file.path(run_dir, "replay_status.txt")
  if (file.exists(status_txt)) {
    txt <- safe_read_lines(status_txt)
    if (length(txt) > 0L) {
      return(list(status = txt[1L], detail = "from replay_status.txt", timestamp = NA_character_))
    }
  }

  list(status = NA_character_, detail = "", timestamp = NA_character_)
}

find_artifact_file <- function(run_dir, patterns) {
  search_dirs <- c(file.path(run_dir, "artifacts"), run_dir)
  for (d in search_dirs) {
    if (dir.exists(d)) {
      for (pat in patterns) {
        matches <- list.files(d, pattern = pat, full.names = TRUE)
        if (length(matches) > 0L) return(matches[1L])
      }
    }
  }
  NULL
}

inspect_run_bundle <- function(run_dir, season_hint = NULL) {
  st <- extract_run_status(run_dir)
  manifest_path <- find_artifact_file(run_dir, c("^run_manifest\\.rds$", "^launch_manifest\\.txt$"))
  summary_path <- find_artifact_file(run_dir, c("^run_summary\\.rds$", "^stage_summaries\\.tsv$"))
  selection_path <- find_artifact_file(run_dir, c("^season_selection\\.rds$"))
  m2_tuning_path <- find_artifact_file(run_dir, c("^m2_tuning.*\\.rds$"))
  candidate_pre_path <- find_artifact_file(run_dir, c("^candidate_pre_holdout.*\\.rds$"))
  replay_path <- find_artifact_file(run_dir, c("^holdout_.*_replay.*\\.rds$", "^page-m2-holdout-replay\\.rds$", "^replay_.*\\.rds$"))
  metrics_path <- find_artifact_file(run_dir, c("^holdout_.*_metrics.*\\.csv$", "^metrics_.*\\.csv$"))
  metrics_rds_path <- find_artifact_file(run_dir, c("^holdout_.*_metrics.*\\.rds$", "^metrics_.*\\.rds$"))
  predictions_path <- find_artifact_file(run_dir, c("^holdout_.*_predictions.*\\.csv$", "^predictions_.*\\.csv$"))
  boundary_path <- find_artifact_file(run_dir, c("boundary_report.*\\.csv$", "^m2_boundary_report.*\\.csv$", "^boundary_report\\.rds$"))

  manifest <- safe_read_rds(manifest_path)
  summary_obj <- safe_read_rds(summary_path)
  selection <- safe_read_rds(selection_path)
  m2_tuning_obj <- safe_read_rds(m2_tuning_path)
  # Candidate pre-holdout bundles can be tens of megabytes; load them only as
  # a last-resort legacy fallback when no smaller identity artifact is present.
  candidate_pre_obj <- NULL
  replay <- safe_read_rds(replay_path)
  if (is.null(manifest) && is.null(selection) && is.null(m2_tuning_obj) && is.null(replay)) {
    candidate_pre_obj <- safe_read_rds(candidate_pre_path)
  }
  metrics_df <- safe_read_csv(metrics_path)
  metrics_rds <- safe_read_rds(metrics_rds_path)

  # Infer season identity
  holdout_season <- if (!is.null(replay$season)) {
    as.character(replay$season)
  } else if (!is.null(manifest$holdout_seasons)) {
    as.character(manifest$holdout_seasons[1L])
  } else if (!is.null(selection$holdout_seasons)) {
    as.character(selection$holdout_seasons[1L])
  } else if (!is.null(m2_tuning_obj$selection$holdout_seasons)) {
    as.character(m2_tuning_obj$selection$holdout_seasons[1L])
  } else if (!is.null(candidate_pre_obj$selection$holdout_seasons)) {
    as.character(candidate_pre_obj$selection$holdout_seasons[1L])
  } else if (!is.null(summary_obj$holdout_season)) {
    as.character(summary_obj$holdout_season)
  } else if (!is.null(season_hint)) {
    season_hint
  } else {
    m <- regmatches(run_dir, regexpr("20[0-9]{2}-[0-9]{2}", run_dir))
    if (length(m) > 0L) m[1L] else NA_character_
  }

  # Commit & Input SHA
  commit <- manifest$repo_commit %||% NA_character_
  if (is.na(commit)) {
    commit_file <- file.path(run_dir, "repo_commit.txt")
    if (file.exists(commit_file)) {
      commit <- trimws(safe_read_lines(commit_file)[1L] %||% NA_character_)
    }
  }

  input_sha <- manifest$input_sha256 %||% NA_character_

  # Training seasons audit
  training_seasons <- if (!is.null(manifest$training_seasons)) {
    as.character(manifest$training_seasons)
  } else if (!is.null(selection$training_seasons)) {
    as.character(selection$training_seasons)
  } else if (!is.null(m2_tuning_obj$selection$training_seasons)) {
    as.character(m2_tuning_obj$selection$training_seasons)
  } else if (!is.null(candidate_pre_obj$selection$training_seasons)) {
    as.character(candidate_pre_obj$selection$training_seasons)
  } else if (!is.null(summary_obj$training_seasons)) {
    as.character(summary_obj$training_seasons)
  } else {
    character(0)
  }

  exclude_seasons <- if (!is.null(manifest$exclude_seasons)) {
    as.character(manifest$exclude_seasons)
  } else if (!is.null(selection$exclude_seasons)) {
    as.character(selection$exclude_seasons)
  } else if (!is.null(m2_tuning_obj$selection$exclude_seasons)) {
    as.character(m2_tuning_obj$selection$exclude_seasons)
  } else if (!is.null(candidate_pre_obj$selection$exclude_seasons)) {
    as.character(candidate_pre_obj$selection$exclude_seasons)
  } else {
    character(0)
  }

  # Metrics extraction
  overall_metrics <- if (!is.null(replay$metrics$overall)) {
    as.data.frame(replay$metrics$overall)
  } else if (!is.null(metrics_df) && nrow(metrics_df) > 0L) {
    metrics_df
  } else if (!is.null(metrics_rds$overall)) {
    as.data.frame(metrics_rds$overall)
  } else if (!is.null(summary_obj$metrics)) {
    as.data.frame(summary_obj$metrics)
  } else {
    NULL
  }

  bernoulli_nll <- if (!is.null(overall_metrics$bernoulli_nll)) as.numeric(overall_metrics$bernoulli_nll[1L]) else NA_real_
  mae <- if (!is.null(overall_metrics$mae)) as.numeric(overall_metrics$mae[1L]) else NA_real_
  n_predictions <- if (!is.null(overall_metrics$n_predictions)) as.integer(overall_metrics$n_predictions[1L]) else NA_integer_
  if (is.na(n_predictions) && !is.null(replay$predictions)) n_predictions <- nrow(replay$predictions)
  if (is.na(n_predictions) && !is.null(predictions_path)) {
    pred_df <- safe_read_csv(predictions_path)
    if (!is.null(pred_df)) n_predictions <- nrow(pred_df)
  }

  lead1_mae <- if (!is.null(replay$metrics$horizon)) {
    h <- replay$metrics$horizon
    h$mae[match("1", as.character(h$lead))] %||% NA_real_
  } else if (!is.null(overall_metrics$lead1_mae)) {
    as.numeric(overall_metrics$lead1_mae[1L])
  } else NA_real_

  lead2_mae <- if (!is.null(replay$metrics$horizon)) {
    h <- replay$metrics$horizon
    h$mae[match("2", as.character(h$lead))] %||% NA_real_
  } else if (!is.null(overall_metrics$lead2_mae)) {
    as.numeric(overall_metrics$lead2_mae[1L])
  } else NA_real_

  early_mae <- if (!is.null(replay$metrics$phase)) {
    p <- replay$metrics$phase
    p$mae[match("early", as.character(p$phase))] %||% NA_real_
  } else if (!is.null(overall_metrics$early_mae)) {
    as.numeric(overall_metrics$early_mae[1L])
  } else NA_real_

  late_mae <- if (!is.null(replay$metrics$phase)) {
    p <- replay$metrics$phase
    p$mae[match("late", as.character(p$phase))] %||% NA_real_
  } else if (!is.null(overall_metrics$late_mae)) {
    as.numeric(overall_metrics$late_mae[1L])
  } else NA_real_

  ignition_week <- if (!is.null(replay$ignition_week)) as.numeric(replay$ignition_week) else NA_real_

  # Boundary assessment
  boundary_obj <- if (!is.null(boundary_path)) {
    if (grepl("\\.csv$", boundary_path)) safe_read_csv(boundary_path) else safe_read_rds(boundary_path)
  } else if (!is.null(m2_tuning_obj$boundary_report)) {
    m2_tuning_obj$boundary_report
  } else NULL
  boundary_report <- if (is.data.frame(boundary_obj)) boundary_obj else if (is.list(boundary_obj)) boundary_obj$boundary_report else NULL

  has_expand_required <- if (!is.null(boundary_report) && "decision" %in% names(boundary_report)) {
    any(boundary_report$decision == "expand_required", na.rm = TRUE)
  } else FALSE

  # Protocol validation checks
  replay_status <- as.character(replay$status %||% NA_character_)
  raw_status <- st$status %||% NA_character_

  is_running <- raw_status %in% c("started", "running", "m0_running", "m0_settled", "m1_running", "m1_settled", "m2_running", "m2_settled", "preflight")
  is_replay_complete <- identical(replay_status, "unseen_replay_complete") || raw_status %in% c("success", "exchangeable_replay_success", "unseen_replay_complete")

  # Audit exchangeable 10 training seasons
  training_count_ok <- length(training_seasons) == 10L
  exclusions_ok <- all(PERMANENT_EXCLUSIONS %in% exclude_seasons) || (!any(PERMANENT_EXCLUSIONS %in% training_seasons) && !is.na(holdout_season) && !holdout_season %in% training_seasons)
  exchangeable <- training_count_ok && exclusions_ok

  finite_metrics <- is.finite(bernoulli_nll) && is.finite(mae)

  # State classification
  classified_state <- if (is_replay_complete && finite_metrics && !is.na(holdout_season)) {
    if (identical(holdout_season, "2015-16")) {
      "diagnostic_complete"
    } else if (exchangeable) {
      "complete"
    } else {
      "invalid"
    }
  } else if (is_running) {
    "pending"
  } else if (identical(raw_status, "failed") && !is_replay_complete) {
    "failed"
  } else if (!is.na(replay_status) && is_replay_complete && finite_metrics) {
    if (identical(holdout_season, "2015-16")) "diagnostic_complete" else "complete"
  } else {
    "incomplete"
  }

  list(
    run_dir = run_dir,
    run_id = basename(run_dir),
    holdout = holdout_season,
    raw_status = raw_status,
    replay_status = replay_status,
    classified_state = classified_state,
    exchangeable = exchangeable,
    training_seasons = training_seasons,
    n_training_seasons = length(training_seasons),
    exclude_seasons = exclude_seasons,
    bernoulli_nll = bernoulli_nll,
    mae = mae,
    lead1_mae = lead1_mae,
    lead2_mae = lead2_mae,
    early_mae = early_mae,
    late_mae = late_mae,
    n_predictions = n_predictions,
    ignition_week = ignition_week,
    has_expand_required = has_expand_required,
    commit = commit,
    input_sha256 = input_sha,
    last_timestamp = st$timestamp,
    artifacts_found = list(
      manifest = !is.null(manifest_path),
      summary = !is.null(summary_path),
      replay = !is.null(replay_path),
      metrics = !is.null(metrics_path) || !is.null(metrics_rds_path),
      predictions = !is.null(predictions_path),
      boundary = !is.null(boundary_path)
    )
  )
}

read_legacy_comparison_table <- function(archive_root) {
  table_paths <- c(
    file.path(archive_root, "_shared", "replays", "comparison_apples_to_apples.csv"),
    file.path(archive_root, "replays", "comparison_apples_to_apples.csv")
  )
  for (p in table_paths) {
    if (file.exists(p)) {
      df <- safe_read_csv(p)
      if (!is.null(df) && nrow(df) > 0L) {
        attr(df, "source_path") <- p
        return(df)
      }
    }
  }
  NULL
}

reconcile_all_seasons <- function(archive_root) {
  run_dirs <- find_run_directories(archive_root)
  inspections <- lapply(run_dirs, inspect_run_bundle)

  # Group inspections by holdout season
  inspections_by_season <- list()
  unmatched_inspections <- list()

  for (insp in inspections) {
    s <- insp$holdout
    if (!is.na(s) && nzchar(s)) {
      inspections_by_season[[s]] <- c(inspections_by_season[[s]], list(insp))
    } else {
      unmatched_inspections <- c(unmatched_inspections, list(insp))
    }
  }

  legacy_comp <- read_legacy_comparison_table(archive_root)

  principal_rows <- list()
  variants_rows <- list()

  for (target_season in VALID_SEASONS) {
    candidates <- inspections_by_season[[target_season]] %||% list()
    known_patterns <- KNOWN_GOVERNED_RUN_PATTERNS[[target_season]] %||% character(0)

    # Rank and pick governed candidate
    governed_candidate <- NULL
    other_candidates <- list()

    if (length(candidates) > 0L) {
      scored <- lapply(candidates, function(cand) {
        score <- 0L
        # Pattern match on governed run IDs
        for (idx in seq_along(known_patterns)) {
          if (cand$run_id == known_patterns[idx]) {
            score <- score + (2000L - idx * 10L)
            break
          } else if (startsWith(cand$run_id, known_patterns[idx])) {
            score <- score + (1000L - idx * 10L)
            break
          }
        }
        if (cand$classified_state == "complete") score <- score + 200L
        if (cand$classified_state == "pending") score <- score + 100L
        if (cand$exchangeable) score <- score + 50L
        score
      })
      scores <- unlist(scored)
      best_idx <- which.max(scores)
      governed_candidate <- candidates[[best_idx]]
      if (length(candidates) > 1L) {
        other_candidates <- candidates[-best_idx]
      }
    }

    # If no candidate was found on disk, attempt fallback lookup in legacy consolidated table
    if (is.null(governed_candidate) && !is.null(legacy_comp) && target_season %in% legacy_comp$holdout) {
      match_rows <- legacy_comp[legacy_comp$holdout == target_season, ]
      if (nrow(match_rows) > 0L) {
        r1 <- match_rows[1L, ]
        governed_candidate <- list(
          run_dir = attr(legacy_comp, "source_path") %||% "consolidated_archive_table",
          run_id = r1$variant %||% paste0(target_season, "-legacy"),
          holdout = target_season,
          raw_status = r1$status %||% "unseen_replay_complete",
          replay_status = r1$status %||% "unseen_replay_complete",
          classified_state = if (identical(as.character(r1$status), "unseen_replay_complete")) "complete" else "incomplete",
          exchangeable = isTRUE(as.logical(r1$exchangeable)),
          n_training_seasons = 10L,
          exclude_seasons = PERMANENT_EXCLUSIONS,
          bernoulli_nll = as.numeric(r1$bernoulli_nll),
          mae = as.numeric(r1$mae),
          lead1_mae = as.numeric(r1$lead1_mae %||% NA_real_),
          lead2_mae = as.numeric(r1$lead2_mae %||% NA_real_),
          early_mae = as.numeric(r1$early_mae %||% NA_real_),
          late_mae = as.numeric(r1$late_mae %||% NA_real_),
          n_predictions = as.integer(r1$n_predictions %||% NA_integer_),
          ignition_week = NA_real_,
          has_expand_required = FALSE,
          commit = NA_character_,
          input_sha256 = NA_character_,
          last_timestamp = NA_character_,
          artifacts_found = list(manifest = FALSE, summary = FALSE, replay = TRUE, metrics = TRUE, predictions = TRUE, boundary = TRUE)
        )
      }
    }

    # Determine status label
    if (is.null(governed_candidate)) {
      status_label <- "missing"
      row_data <- list(
        season = target_season,
        run_id = NA_character_,
        status = status_label,
        exchangeable = NA,
        n_training_seasons = NA_integer_,
        n_predictions = NA_integer_,
        ignition_week = NA_real_,
        bernoulli_nll = NA_real_,
        mae = NA_real_,
        lead1_mae = NA_real_,
        lead2_mae = NA_real_,
        early_mae = NA_real_,
        late_mae = NA_real_,
        commit = NA_character_,
        input_sha256 = NA_character_,
        run_dir = NA_character_
      )
    } else {
      # Evaluate classification
      cand_state <- governed_candidate$classified_state
      status_label <- if (cand_state == "complete") {
        "complete"
      } else if (cand_state == "pending") {
        "pending"
      } else if (cand_state == "failed") {
        # Check special case for 2012-13 / 2013-14 if in progress
        if (target_season %in% c("2012-13", "2013-14") && grepl("running|started|settled", governed_candidate$raw_status)) {
          "pending"
        } else {
          "invalid"
        }
      } else {
        "incomplete"
      }

      row_data <- list(
        season = target_season,
        run_id = governed_candidate$run_id %||% NA_character_,
        status = status_label,
        exchangeable = governed_candidate$exchangeable,
        n_training_seasons = governed_candidate$n_training_seasons,
        n_predictions = governed_candidate$n_predictions,
        ignition_week = governed_candidate$ignition_week,
        bernoulli_nll = governed_candidate$bernoulli_nll,
        mae = governed_candidate$mae,
        lead1_mae = governed_candidate$lead1_mae,
        lead2_mae = governed_candidate$lead2_mae,
        early_mae = governed_candidate$early_mae,
        late_mae = governed_candidate$late_mae,
        commit = governed_candidate$commit %||% NA_character_,
        input_sha256 = governed_candidate$input_sha256 %||% NA_character_,
        run_dir = governed_candidate$run_dir %||% NA_character_
      )
    }

    principal_rows[[target_season]] <- row_data

    # Record secondary candidates as variants
    for (cand in other_candidates) {
      variants_rows[[length(variants_rows) + 1L]] <- list(
        season = target_season,
        variant = cand$run_id,
        classification = "same_season_variant",
        status = cand$classified_state,
        bernoulli_nll = cand$bernoulli_nll,
        mae = cand$mae,
        n_predictions = cand$n_predictions,
        notes = paste0("Secondary candidate directory; raw_status=", cand$raw_status),
        run_dir = cand$run_dir
      )
    }
  }

  # Add 2015-16 diagnostic holdouts to variants
  if ("2015-16" %in% names(inspections_by_season)) {
    for (d_cand in inspections_by_season[["2015-16"]]) {
      variants_rows[[length(variants_rows) + 1L]] <- list(
        season = "2015-16",
        variant = d_cand$run_id,
        classification = "diagnostic_exclusion",
        status = d_cand$classified_state,
        bernoulli_nll = d_cand$bernoulli_nll,
        mae = d_cand$mae,
        n_predictions = d_cand$n_predictions,
        notes = "Permanent exclusion diagnostic drop-test; excluded from principal 11-season table",
        run_dir = d_cand$run_dir
      )
    }
  } else if (!is.null(legacy_comp) && "2015-16" %in% legacy_comp$holdout) {
    match_15 <- legacy_comp[legacy_comp$holdout == "2015-16", ]
    for (idx in seq_len(nrow(match_15))) {
      r <- match_15[idx, ]
      variants_rows[[length(variants_rows) + 1L]] <- list(
        season = "2015-16",
        variant = r$variant,
        classification = "diagnostic_exclusion",
        status = r$status,
        bernoulli_nll = as.numeric(r$bernoulli_nll),
        mae = as.numeric(r$mae),
        n_predictions = as.integer(r$n_predictions),
        notes = "Historical comparison table diagnostic row; excluded from principal 11-season table",
        run_dir = attr(legacy_comp, "source_path") %||% "comparison_apples_to_apples.csv"
      )
    }
  }

  # Build data frames
  principal_df <- do.call(rbind, lapply(principal_rows, as.data.frame, stringsAsFactors = FALSE))
  rownames(principal_df) <- NULL

  variants_df <- if (length(variants_rows) > 0L) {
    v_df <- do.call(rbind, lapply(variants_rows, as.data.frame, stringsAsFactors = FALSE))
    rownames(v_df) <- NULL
    v_df
  } else {
    data.frame(
      season = character(0), variant = character(0), classification = character(0),
      status = character(0), bernoulli_nll = numeric(0), mae = numeric(0),
      n_predictions = integer(0), notes = character(0), run_dir = character(0),
      stringsAsFactors = FALSE
    )
  }

  list(
    principal = principal_df,
    variants = variants_df,
    archive_root = archive_root
  )
}

format_num <- function(val, digits = 6L) {
  if (is.na(val) || !is.numeric(val)) {
    "-"
  } else {
    sprintf(paste0("%.", digits, "f"), val)
  }
}

format_int <- function(val) {
  if (is.na(val) || !is.numeric(val)) "-" else as.character(as.integer(val))
}

generate_markdown_report <- function(reconciliation_result) {
  p_df <- reconciliation_result$principal
  v_df <- reconciliation_result$variants
  root <- reconciliation_result$archive_root

  complete_count <- sum(p_df$status == "complete", na.rm = TRUE)
  pending_count <- sum(p_df$status == "pending", na.rm = TRUE)
  missing_count <- sum(p_df$status == "missing", na.rm = TRUE)
  invalid_count <- sum(!p_df$status %in% c("complete", "pending", "missing"), na.rm = TRUE)

  lines <- c(
    "# PAGe Governed 11-Season Exchangeable Holdout Reconciliation",
    "",
    paste0("- **Archive Root**: `", root, "`"),
    paste0("- **Generated UTC**: `", format(Sys.time(), tz = "UTC", usetz = TRUE), "`"),
    paste0("- **Target Seasons**: 11 valid exchangeable holdouts"),
    paste0("- **Reconciliation Summary**: ", complete_count, " complete, ",
           pending_count, " pending, ", missing_count, " missing, ", invalid_count, " invalid"),
    "",
    "## Principal 11-Season Exchangeable Table",
    "",
    "All rows represent exchangeable nested LOSO evaluations using strictly 10 training seasons and fixed exclusions.",
    "Comparisons are descriptive; lower Bernoulli NLL and MAE indicate superior out-of-sample accuracy.",
    "",
    "| Season | Run ID | Status | Exchangeable | NLL | MAE | Lead 1 MAE | Lead 2 MAE | Predictions | Commit |",
    "|:---|:---|:---|:---:|---:|---:|---:|---:|---:|:---|")

  for (i in seq_len(nrow(p_df))) {
    r <- p_df[i, ]
    commit_short <- if (!is.na(r$commit) && nzchar(r$commit)) substr(r$commit, 1L, 8L) else "-"
    exch_str <- if (isTRUE(r$exchangeable)) "TRUE" else if (identical(r$exchangeable, FALSE)) "FALSE" else "-"
    lines <- c(lines, sprintf(
      "| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |",
      r$season,
      r$run_id %||% "-",
      r$status,
      exch_str,
      format_num(r$bernoulli_nll),
      format_num(r$mae),
      format_num(r$lead1_mae),
      format_num(r$lead2_mae),
      format_int(r$n_predictions),
      commit_short
    ))
  }

  lines <- c(lines, "")

  # Descriptive Metrics for Complete Holdouts
  complete_rows <- p_df[p_df$status == "complete" & is.finite(p_df$bernoulli_nll) & is.finite(p_df$mae), ]
  if (nrow(complete_rows) > 0L) {
    mean_nll <- mean(complete_rows$bernoulli_nll)
    median_nll <- stats::median(complete_rows$bernoulli_nll)
    mean_mae <- mean(complete_rows$mae)
    median_mae <- stats::median(complete_rows$mae)
    total_preds <- sum(complete_rows$n_predictions, na.rm = TRUE)

    lines <- c(
      lines,
      "## Descriptive Aggregate Metrics (Complete Exchangeable Holdouts)",
      "",
      sprintf("- **Evaluated Complete Seasons**: %d / 11", nrow(complete_rows)),
      sprintf("- **Total Predictions**: %d", total_preds),
      sprintf("- **Bernoulli NLL**: Mean = %.6f | Median = %.6f | Range = [%.6f, %.6f]",
              mean_nll, median_nll, min(complete_rows$bernoulli_nll), max(complete_rows$bernoulli_nll)),
      sprintf("- **MAE**: Mean = %.6f | Median = %.6f | Range = [%.6f, %.6f]",
              mean_mae, median_mae, min(complete_rows$mae), max(complete_rows$mae)),
      "",
      "*Note: Cross-season metrics are descriptive. No inferential hypothesis testing or p-values are calculated.*",
      ""
    )
  }

  # Variants and Diagnostic Table
  if (nrow(v_df) > 0L) {
    lines <- c(
      lines,
      "## Holdout Variants & Diagnostic Exclusions",
      "",
      "The following runs are retained for provenance and audit purposes but excluded from the principal 11-season exchangeable table.",
      "",
      "| Season | Variant / Run ID | Classification | Status | NLL | MAE | Predictions | Notes |",
      "|:---|:---|:---|:---|---:|---:|---:|:---|")
    for (i in seq_len(nrow(v_df))) {
      v <- v_df[i, ]
      lines <- c(lines, sprintf(
        "| %s | %s | %s | %s | %s | %s | %s | %s |",
        v$season,
        v$variant %||% "-",
        v$classification %||% "-",
        v$status %||% "-",
        format_num(v$bernoulli_nll),
        format_num(v$mae),
        format_int(v$n_predictions),
        v$notes %||% "-"
      ))
    }
    lines <- c(lines, "")
  }

  lines
}

main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  cfg <- parse_cli_args(args)

  cat("Reconciling holdout artifacts across archive: ", cfg$artifact_root, "\n")
  result <- reconcile_all_seasons(cfg$artifact_root)

  p_df <- result$principal
  v_df <- result$variants

  complete_count <- sum(p_df$status == "complete", na.rm = TRUE)
  pending_count <- sum(p_df$status == "pending", na.rm = TRUE)
  missing_count <- sum(p_df$status == "missing", na.rm = TRUE)
  invalid_count <- sum(!p_df$status %in% c("complete", "pending", "missing"), na.rm = TRUE)

  md_lines <- generate_markdown_report(result)

  # If output prefix specified, write files deterministically
  if (!is.null(cfg$output_prefix) && nzchar(cfg$output_prefix)) {
    out_dir <- dirname(cfg$output_prefix)
    if (!dir.exists(out_dir) && nzchar(out_dir) && out_dir != ".") {
      dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
    }

    principal_csv_path <- paste0(cfg$output_prefix, "_principal.csv")
    comparison_csv_path <- paste0(cfg$output_prefix, ".csv")
    variants_csv_path <- paste0(cfg$output_prefix, "_variants.csv")
    md_path <- paste0(cfg$output_prefix, ".md")

    utils::write.csv(p_df, comparison_csv_path, row.names = FALSE)
    utils::write.csv(p_df, principal_csv_path, row.names = FALSE)
    utils::write.csv(v_df, variants_csv_path, row.names = FALSE)
    writeLines(md_lines, md_path)

    cat("Outputs written:\n")
    cat("  - Principal table: ", comparison_csv_path, "\n")
    cat("  - Variants table:  ", variants_csv_path, "\n")
    cat("  - Markdown report: ", md_path, "\n")
  } else {
    cat("\n", paste(md_lines, collapse = "\n"), "\n", sep = "")
  }

  cat(sprintf("\nStatus summary: %d complete, %d pending, %d missing, %d invalid (Total: 11 seasons)\n",
              complete_count, pending_count, missing_count, invalid_count))

  if (cfg$strict) {
    if (complete_count < length(VALID_SEASONS)) {
      cat("Strict mode check FAILED: Not all 11 seasons are complete.\n")
      quit(save = "no", status = 1L)
    } else {
      cat("Strict mode check PASSED: All 11 seasons verified complete.\n")
      quit(save = "no", status = 0L)
    }
  }

  quit(save = "no", status = 0L)
}

if (!interactive()) {
  main()
}
