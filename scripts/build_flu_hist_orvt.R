#!/usr/bin/env Rscript

# Build a new July-start historical input from PHO ORVT vintages. The caller
# must pass --dry-run when validating real/private files; the input is never
# overwritten. The emitted plot and console output are aggregate-only.

`%||%` <- function(x, y) if (is.null(x)) y else x

parse_args <- function(args) {
  out <- list()
  i <- 1L
  while (i <= length(args)) {
    token <- args[[i]]
    if (!grepl("^--", token)) stop("Unexpected argument: ", token, call. = FALSE)
    key_value <- sub("^--", "", token)
    if (grepl("=", key_value, fixed = TRUE)) {
      pieces <- strsplit(key_value, "=", fixed = TRUE)[[1L]]
      key <- pieces[1L]
      value <- paste(pieces[-1L], collapse = "=")
    } else {
      key <- key_value
      value <- TRUE
      if (i < length(args) && !grepl("^--", args[[i + 1L]])) {
        i <- i + 1L
        value <- args[[i]]
      }
    }
    if (key %in% c("orvt", "feed")) out[[key]] <- c(out[[key]], value) else out[[key]] <- value
    i <- i + 1L
  }
  out
}

season_label <- function(start_year) {
  sprintf("%04d-%02d", as.integer(start_year), (as.integer(start_year) + 1L) %% 100L)
}

has_pho_label <- function(x, label) {
  vapply(
    strsplit(as.character(x), ";", fixed = TRUE),
    function(z) label %in% trimws(z), logical(1)
  )
}

read_feed_target <- function(path, season, get_current) {
  mapped <- tryCatch(
    get_current(data = path, season = season, include_predecessor = FALSE),
    error = function(e) {
      if (grepl("no dated rows|No rows remain", conditionMessage(e), ignore.case = TRUE)) {
        return(NULL)
      }
      stop(e)
    }
  )
  if (is.null(mapped)) {
    return(list(data = data.frame(), sha256 = NA_character_))
  }
  rows <- mapped[as.character(mapped$season) == season, , drop = FALSE]
  list(data = rows, sha256 = attr(mapped, "sha256") %||% NA_character_)
}

assemble_target <- function(feed_paths, season, get_current, require_complete = FALSE) {
  selected <- list()
  covered <- integer()
  details <- list()
  for (i in rev(seq_along(feed_paths))) {
    item <- read_feed_target(feed_paths[[i]], season, get_current)
    rows <- item$data
    if (!nrow(rows)) next
    if (anyDuplicated(rows$weekF) || any(!is.finite(rows$weekF))) {
      stop("Each ORVT feed must have unique finite weekF values: ", feed_paths[[i]],
        call. = FALSE
      )
    }
    fresh <- rows[!(rows$weekF %in% covered), , drop = FALSE]
    if (nrow(fresh)) {
      fresh$source_feed <- feed_paths[[i]]
      fresh$source_sha256 <- item$sha256
      selected[[length(selected) + 1L]] <- fresh
      covered <- c(covered, fresh$weekF)
    }
    details[[length(details) + 1L]] <- data.frame(
      source_feed = feed_paths[[i]], source_sha256 = item$sha256,
      available_weeks = nrow(rows), selected_weeks = nrow(fresh),
      stringsAsFactors = FALSE
    )
  }
  result <- if (length(selected)) do.call(rbind, selected) else data.frame()
  if (nrow(result)) result <- result[order(result$weekF), , drop = FALSE]
  expected <- page_season_calendar(
    mmwr_year = as.integer(substr(season, 1L, 4L)),
    week = 27L
  )$nW_true[[1L]]
  if (require_complete && !setequal(covered, seq_len(expected))) {
    stop("ORVT feeds do not cover all ", expected, " weeks of ", season,
      "; found ", length(unique(covered)), ".",
      call. = FALSE
    )
  }
  list(
    data = result,
    source_details = if (length(details)) do.call(rbind, details) else data.frame(),
    expected_weeks = expected, covered_weeks = sort(unique(covered))
  )
}

source_label_rows <- function(path, label, get_current) {
  start_year <- as.integer(substr(label, 1L, 4L))
  result <- get_current(
    data = path, season = season_label(start_year + 1L), include_predecessor = TRUE
  )
  result[has_pho_label(result$pho_season, label), , drop = FALSE]
}

compare_revisions_by_date <- function(existing, source_rows, label, trailing_weeks = 12L) {
  old <- existing[existing$pho_season == label, c(
    "week_start_date", "pos_flua", "test_flu"
  ), drop = FALSE]
  if (!nrow(old) || !nrow(source_rows)) {
    return(list(
      status = "not_available", n_settled = 0L, n_trailing = 0L,
      n_exact = 0L, n_tolerated = 0L, n_rejected = 0L
    ))
  }
  old$date <- as.Date(old$week_start_date)
  old$y_old <- as.numeric(old$pos_flua)
  old$N_old <- as.numeric(old$test_flu)
  source <- source_rows[, c("week_start_date", "y", "N"), drop = FALSE]
  source$date <- as.Date(source$week_start_date)
  source$y_new <- as.numeric(source$y)
  source$N_new <- as.numeric(source$N)
  old <- old[!duplicated(old$date), , drop = FALSE]
  source <- source[!duplicated(source$date), , drop = FALSE]
  agreement <- merge(old[, c("date", "y_old", "N_old")],
    source[, c("date", "y_new", "N_new")],
    by = "date", all = TRUE
  )
  last_old <- max(source$date, na.rm = TRUE)
  agreement$trailing <- agreement$date > last_old - 7L * trailing_weeks
  agreement$dN <- agreement$N_new - agreement$N_old
  agreement$dy <- agreement$y_new - agreement$y_old
  agreement$rel_dN <- abs(agreement$dN) / pmax(abs(agreement$N_new), 1)
  agreement$N_ok <- ifelse(agreement$trailing, agreement$rel_dN <= 0.005,
    is.finite(agreement$dN) & agreement$dN == 0
  )
  agreement$y_ok <- abs(agreement$dy) <= ifelse(agreement$trailing,
    pmax(1, 0.005 * abs(agreement$y_new)), 0
  )
  agreement$ok <- is.finite(agreement$y_old) & is.finite(agreement$N_old) &
    is.finite(agreement$y_new) & is.finite(agreement$N_new) &
    agreement$N_ok & agreement$y_ok
  exact <- agreement$ok & agreement$dN == 0 & agreement$dy == 0
  tolerated <- agreement$ok & agreement$trailing & !exact
  rejected <- !agreement$ok
  list(
    status = if (any(rejected)) "rejected" else "ok",
    n_settled = sum(!agreement$trailing), n_trailing = sum(agreement$trailing),
    n_exact = sum(exact), n_tolerated = sum(tolerated), n_rejected = sum(rejected)
  )
}

bind_union <- function(x, y) {
  fields <- union(names(x), names(y))
  for (field in setdiff(fields, names(x))) x[[field]] <- NA
  for (field in setdiff(fields, names(y))) y[[field]] <- NA
  rbind(x[, fields, drop = FALSE], y[, fields, drop = FALSE])
}

make_source_rows <- function(source, season, partial, template, source_kind) {
  # Blank rows with the template's columns: nothing may be inherited from a
  # historical row (weekF, Influenza B counts, sort keys, ...).
  out <- template[rep(NA_integer_, nrow(source)), , drop = FALSE]
  start_year <- as.integer(substr(season, 1L, 4L))
  set_col <- function(name, value) if (name %in% names(out)) out[[name]] <<- value
  set_col("weekF", as.integer(source$weekF))
  set_col("weekS", as.integer(source$weekS))
  if (!is.null(source$nW_true)) set_col("nW_true", as.integer(source$nW_true))
  set_col("season", season)
  set_col("pho_season", source$pho_season)
  set_col("week", as.integer(source$week))
  set_col("year", as.integer(source$mmwr_year))
  set_col("seasonstart", start_year)
  set_col("seasonend", start_year + 1L)
  set_col("week_start_date", as.character(source$week_start_date))
  set_col("week_end_date", as.character(source$week_end_date))
  set_col("test_flu", as.numeric(source$N))
  set_col("pos_flua", as.numeric(source$y))
  set_col("fluAPercentPositive", 100 * source$p)
  set_col("total_flu_percent_pos", 100 * source$p)
  set_col("charyrsw", sprintf("%d - %02d", source$mmwr_year, source$week))
  set_col("weeksort", as.integer(source$weekF))
  set_col("datasource", "ORVT")
  out$source_feed <- source$source_feed
  out$source_sha256 <- source$source_sha256
  out$season_partial <- isTRUE(partial)
  out$source_kind <- source_kind
  out
}

if (sys.nframe() == 0L) {
  opts <- parse_args(commandArgs(trailingOnly = TRUE))
  dry_run <- isTRUE(opts$`dry-run`) || isTRUE(opts$dry_run)
  input_path <- opts$input %||% "/home/yeli/FLU/flu_testing_data.csv"
  feed_paths <- opts$orvt %||% opts$feed
  if (is.null(feed_paths) || !length(feed_paths)) {
    stop("Supply at least one --orvt=PATH_OR_URL input.", call. = FALSE)
  }
  output_path <- opts$output %||% file.path(
    "/home/yeli/FLU", paste0("flu_testing_data_orvt_", format(Sys.Date(), "%Y%m%d"), ".csv")
  )
  plot_path <- opts$plot %||% paste0(
    "/tmp/claude-1000/-home-yeli-repos-PAGe/f79968cd-322f-4aa1-ad69-dc2dc821bbcc/",
    "scratchpad/datacheck/july_seasons_orvt_would_be_output.png"
  )
  if (file.exists(output_path)) stop("Refusing to overwrite existing output: ", output_path, call. = FALSE)
  if (!file.exists(input_path)) stop("Existing private CSV not found: ", input_path, call. = FALSE)

  if (requireNamespace("PAGe", quietly = TRUE)) {
    get_current <- PAGe::getCurrentD
    cal <- PAGe::page_season_calendar
  } else {
    source("PAGe/R/season_calendar.R", local = TRUE)
    source("PAGe/R/getCurrentD.R", local = TRUE)
    get_current <- getCurrentD
    cal <- page_season_calendar
  }
  page_season_calendar <- cal
  existing <- utils::read.csv(input_path, stringsAsFactors = FALSE, check.names = FALSE)
  required <- c("season", "week", "pos_flua", "test_flu", "week_start_date")
  if (!all(required %in% names(existing))) {
    stop("Existing CSV is missing: ", paste(setdiff(required, names(existing)), collapse = ", "),
      call. = FALSE
    )
  }
  existing$pho_season <- as.character(existing$season)
  existing_calendar <- cal(dates = as.Date(existing$week_start_date), start_week = 27L)
  existing$season <- existing_calendar$season
  existing$week <- existing_calendar$week
  existing$weekF <- existing_calendar$weekF
  existing$weekS <- existing_calendar$weekS
  existing$season_partial <- FALSE
  existing$source_kind <- "historical"

  feed_names <- basename(feed_paths)
  old_i <- which(grepl("2024-25_2025-26", feed_names, fixed = TRUE))[1L]
  if (is.na(old_i)) old_i <- 1L
  target_2025 <- assemble_target(feed_paths, "2025-26", get_current, require_complete = TRUE)
  target_2026 <- assemble_target(feed_paths, "2026-27", get_current, require_complete = FALSE)
  if (!nrow(target_2025$data) || nrow(target_2025$data) != target_2025$expected_weeks) {
    stop("The revised 2025-26 July season must contain exactly 53 weeks.", call. = FALSE)
  }

  old_label_rows <- source_label_rows(feed_paths[[old_i]], "2024-25", get_current)
  revision <- compare_revisions_by_date(existing, old_label_rows, "2024-25")
  if (identical(revision$status, "rejected")) {
    stop("Revision validation rejected one or more settled/date-keyed rows.", call. = FALSE)
  }

  historical <- existing[!existing$season %in% c("2025-26", "2026-27"), , drop = FALSE]
  replacement <- make_source_rows(
    target_2025$data, "2025-26",
    partial = FALSE,
    template = existing[1L, , drop = FALSE], source_kind = "orvt_replacement"
  )
  rebuilt <- bind_union(historical, replacement)
  if (nrow(target_2026$data)) {
    partial <- make_source_rows(
      target_2026$data, "2026-27",
      partial = TRUE,
      template = existing[1L, , drop = FALSE], source_kind = "orvt_partial"
    )
    rebuilt <- bind_union(rebuilt, partial)
  }
  rebuilt <- rebuilt[order(as.character(rebuilt$season), as.integer(rebuilt$weekF)), , drop = FALSE]
  rownames(rebuilt) <- NULL

  if (any(!is.finite(rebuilt$pos_flua)) || any(!is.finite(rebuilt$test_flu)) ||
    any(rebuilt$pos_flua < 0) || any(rebuilt$test_flu < 0) ||
    any(rebuilt$pos_flua > rebuilt$test_flu)) {
    stop("Would-be output violates the historical count contract.", call. = FALSE)
  }

  plot_data <- rebuilt[is.finite(as.numeric(rebuilt$weekF)) & is.finite(as.numeric(rebuilt$pos_flua)) &
    is.finite(as.numeric(rebuilt$test_flu)) & as.numeric(rebuilt$test_flu) > 0, , drop = FALSE]
  plot_data$positivity <- as.numeric(plot_data$pos_flua) / as.numeric(plot_data$test_flu)
  dir.create(dirname(plot_path), recursive = TRUE, showWarnings = FALSE)
  if (!requireNamespace("ggplot2", quietly = TRUE)) stop("ggplot2 is required for the aggregate plot.")
  plot <- ggplot2::ggplot(plot_data, ggplot2::aes(x = weekF, y = positivity)) +
    ggplot2::geom_line(na.rm = TRUE) +
    ggplot2::facet_wrap(~season, scales = "free_y") +
    ggplot2::labs(
      title = "Would-be ORVT output by July-start PAGe season",
      x = "weekF", y = "Influenza A positivity"
    ) +
    ggplot2::theme_minimal()
  ggplot2::ggsave(
    plot_path, plot,
    width = 16, height = 12, units = "in", dpi = 150,
    device = grDevices::png
  )

  counts <- sort(table(rebuilt$season))
  partial_counts <- sort(table(rebuilt$season[rebuilt$season_partial]))
  cat("PAGe ORVT historical rebuild\n")
  cat("mode:", if (dry_run) "dry-run; no CSV/manifest write" else "write new output", "\n")
  cat("2025-26 replacement weeks:", nrow(replacement), "(expected", target_2025$expected_weeks, ")\n")
  cat("2026-27 partial weeks appended:", if (length(partial_counts)) sum(partial_counts) else 0L, "\n")
  cat("revision validation:", revision$status, "settled=", revision$n_settled,
    "trailing=", revision$n_trailing, "exact=", revision$n_exact,
    "tolerated=", revision$n_tolerated, "rejected=", revision$n_rejected, "\n",
    sep = ""
  )
  cat("per-season aggregate row counts:\n")
  print(counts)
  cat("aggregate plot:", normalizePath(plot_path, mustWork = FALSE), "\n")

  feed_manifest <- do.call(rbind, lapply(list(target_2025, target_2026), function(x) x$source_details))
  manifest <- list(
    input_path = normalizePath(input_path, mustWork = FALSE),
    feed_paths = as.list(feed_paths),
    output_path = normalizePath(output_path, mustWork = FALSE),
    dry_run = dry_run,
    season_rule = "MMWR week 27 of start year through week 26 of following year; date-derived",
    replacement_2025_26 = list(
      weeks = nrow(replacement), expected_weeks = target_2025$expected_weeks,
      per_week_source = target_2025$data[, c(
        "weekF", "week", "week_start_date",
        "source_feed", "source_sha256"
      ), drop = FALSE]
    ),
    partial_2026_27_weeks = if (nrow(target_2026$data)) nrow(target_2026$data) else 0L,
    source_details = feed_manifest,
    revision_validation = revision,
    aggregate_plot = normalizePath(plot_path, mustWork = FALSE),
    per_season_row_counts = as.list(as.integer(counts))
  )
  names(manifest$per_season_row_counts) <- names(counts)
  if (!dry_run) {
    parent <- dirname(output_path)
    if (!dir.exists(parent)) dir.create(parent, recursive = TRUE)
    utils::write.csv(rebuilt, output_path, row.names = FALSE, na = "")
    manifest$output_sha256 <- digest::digest(file = output_path, algo = "sha256", serialize = FALSE)
    jsonlite::write_json(manifest, paste0(output_path, ".manifest.json"), auto_unbox = TRUE, pretty = TRUE)
    cat("wrote:", output_path, "\nmanifest:", paste0(output_path, ".manifest.json"), "\n")
  }
}
