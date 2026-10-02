# PAGe Quarto walk-forward report ---------------------------------------------
#
# Builds a cumulative, self-contained Quarto report for a single season. The
# generated `.qmd` is pure Markdown (no render-time R chunks), so it renders
# wherever Quarto is available regardless of how PAGe itself was loaded. All
# surveillance, ignition, timing, and forecast content is precomputed and
# written into the document; trend plots are pre-rendered to PNG assets next to
# the `.qmd` and embedded by Quarto's `embed-resources`.

.page_qmd_walkforward_dirs <- function() {
  opt <- getOption("PAGe.walkforward_dir", NULL)
  candidates <- c(
    opt,
    file.path(Sys.getenv("HOME"), "repos", "IRVRI", "wf_output", "num_test_trend_latest"),
    file.path(Sys.getenv("HOME"), "repos", "IRVRI", "OP")
  )
  unique(candidates[!is.null(candidates) & nzchar(candidates) & dir.exists(candidates)])
}

.page_qmd_latest_hist <- function(dir = NULL) {
  dirs <- if (is.null(dir)) .page_qmd_walkforward_dirs() else dir
  if (!length(dirs)) {
    return(NULL)
  }
  files <- character()
  for (d in dirs) {
    if (dir.exists(d)) {
      found <- list.files(
        d,
        pattern = "^hist.*\\.rdata$",
        ignore.case = TRUE,
        full.names = TRUE
      )
      files <- c(files, found)
    }
  }
  if (!length(files)) {
    return(NULL)
  }
  # Extract date string YYYY[-_]MM[-_]DD from filename if available
  dates <- vapply(basename(files), function(nm) {
    m <- regmatches(nm, regexec("([0-9]{4})[-_]([0-9]{2})[-_]([0-9]{2})", nm))[[1L]]
    if (length(m) == 4L) paste(m[2:4], collapse = "-") else ""
  }, character(1L), USE.NAMES = FALSE)

  mt <- file.info(files)$mtime
  keep <- !is.na(mt)
  files <- files[keep]
  dates <- dates[keep]
  mt <- mt[keep]
  if (!length(files)) {
    return(NULL)
  }
  # Prefer latest date in filename; fall back to file mtime
  files[order(dates, mt, files, decreasing = TRUE)][[1L]]
}

.page_qmd_resolve_data <- function(data) {
  if (is.data.frame(data)) {
    return(list(path = data, source = "typed_panel"))
  }
  if (is.null(data) || (is.character(data) && length(data) == 1L &&
    !is.na(data) && dir.exists(data))) {
    hit <- .page_qmd_latest_hist(data)
    if (!is.null(hit)) {
      return(list(path = hit, source = "hist_rdata"))
    }
    return(list(path = NULL, source = "live_orvt"))
  }
  if (is.character(data) && length(data) == 1L && !is.na(data)) {
    if (!file.exists(data)) {
      stop("Surveillance input does not exist: ", data, call. = FALSE)
    }
    return(list(path = data, source = "path"))
  }
  stop("`data` must be NULL, a directory, a file path, or a typed panel.", call. = FALSE)
}

.page_qmd_infer_season <- function(path) {
  if (!is.character(path) || length(path) != 1L || is.na(path)) {
    return(NULL)
  }
  if (!tolower(tools::file_ext(path)) %in% c("rdata", "rda")) {
    return(NULL)
  }
  env <- new.env(parent = emptyenv())
  load(path, envir = env)
  if (!exists("r", envir = env, inherits = FALSE)) {
    return(NULL)
  }
  r <- get("r", envir = env, inherits = FALSE)
  if (!is.list(r) || !all(c("fluA", "fluB") %in% names(r))) {
    return(NULL)
  }
  a <- .page_v3_aggregate_olis_type(r$fluA)
  b <- .page_v3_aggregate_olis_type(r$fluB)
  common <- intersect(unique(a$season), unique(b$season))
  if (!length(common)) {
    return(NULL)
  }
  common[which.max(.page_v3_season_start(common))]
}

.page_qmd_fmt_pp <- function(x, digits = 3L) {
  if (length(x) != 1L || !is.finite(x)) {
    return("n/a")
  }
  paste0(formatC(x, format = "f", digits = digits), "%")
}

.page_qmd_fmt_num <- function(x, digits = 0L) {
  if (length(x) != 1L || !is.finite(x)) {
    return("n/a")
  }
  formatC(x, format = "f", digits = digits, big.mark = ",")
}

.page_qmd_fmt_week <- function(x, digits = 2L) {
  if (length(x) != 1L || !is.finite(x)) {
    return("not available")
  }
  if (abs(x - round(x)) < 1e-8) {
    return(paste0("Week ", as.integer(round(x))))
  }
  paste0("Week ", formatC(x, format = "f", digits = digits))
}

.page_qmd_fmt_date <- function(x) {
  if (length(x) != 1L || is.na(x) || !nzchar(as.character(x))) {
    return("")
  }
  d <- suppressWarnings(as.Date(x))
  if (is.na(d)) {
    return(as.character(x))
  }
  sub("^0", "", format(d, "%d %b %Y"))
}

.page_qmd_md_table <- function(df) {
  esc <- function(x) gsub("|", "\\|", as.character(x), fixed = TRUE)
  header <- esc(names(df))
  body <- as.data.frame(lapply(df, esc), stringsAsFactors = FALSE)
  lines <- c(
    paste0("| ", paste(header, collapse = " | "), " |"),
    paste0("| ", paste(rep(":---", length(header)), collapse = " | "), " |")
  )
  if (nrow(body)) {
    for (i in seq_len(nrow(body))) {
      lines <- c(lines, paste0(
        "| ",
        paste(unlist(body[i, , drop = TRUE], use.names = FALSE), collapse = " | "),
        " |"
      ))
    }
  }
  lines
}

.page_qmd_m1_summary <- function(m1a) {
  out <- list(
    ignited = FALSE,
    m0_label = "not detected",
    m1_available = FALSE,
    m1_label = "not available",
    peak_mean = NA_real_,
    peak_q05 = NA_real_,
    peak_q95 = NA_real_,
    prob_passed = NA_real_
  )
  if (is.null(m1a) || !isTRUE(m1a$ignited)) {
    return(out)
  }
  out$ignited <- TRUE
  iweek <- NA_real_
  if (is.data.frame(m1a$m0$by_season) && "iWeek_hatF" %in% names(m1a$m0$by_season)) {
    iweek <- suppressWarnings(as.numeric(m1a$m0$by_season$iWeek_hatF[[1L]]))
  }
  out$m0_label <- if (is.finite(iweek)) {
    paste0("detected at ", .page_qmd_fmt_week(iweek))
  } else {
    "detected"
  }
  m1 <- m1a$m1
  if (is.list(m1) && is.data.frame(m1$timing_df) && nrow(m1$timing_df)) {
    tr <- m1$timing_df[nrow(m1$timing_df), , drop = FALSE]
    state <- as.character(tr$state[[1L]])
    sc <- function(nm) {
      if (!nm %in% names(tr)) {
        return(NA_real_)
      }
      suppressWarnings(as.numeric(tr[[nm]][[1L]]))
    }
    if (identical(state, "active")) {
      out$m1_available <- TRUE
      out$peak_mean <- sc("calibrated_peak_mean")
      out$peak_q05 <- sc("calibrated_peak_q05")
      out$peak_q95 <- sc("calibrated_peak_q95")
      out$prob_passed <- sc("prob_peak_passed")
      if (is.finite(out$peak_mean)) {
        out$m1_label <- paste0(
          "peak ", .page_qmd_fmt_week(out$peak_mean),
          if (is.finite(out$peak_q05) && is.finite(out$peak_q95)) {
            paste0(
              " (90% ", formatC(out$peak_q05, format = "f", digits = 2),
              "-", formatC(out$peak_q95, format = "f", digits = 2), ")"
            )
          } else {
            ""
          }
        )
      } else {
        out$m1_label <- "active (peak not available)"
      }
    } else if (length(state) == 1L && !is.na(state) && nzchar(state)) {
      out$m1_label <- paste0("state: ", state)
    }
  }
  out
}

.page_qmd_forecast_table <- function(fc) {
  rows <- list()
  for (tp in c("A", "B")) {
    z <- fc[fc$type == tp, , drop = FALSE]
    if (!nrow(z)) next
    z <- z[order(z$horizon), , drop = FALSE]
    h1 <- z[z$horizon == 1L, , drop = FALSE]
    h2 <- z[z$horizon == 2L, , drop = FALSE]
    rows[[length(rows) + 1L]] <- data.frame(
      Virus = paste0("Influenza ", tp),
      `+1 week` = if (nrow(h1)) {
        paste0(.page_qmd_fmt_pp(h1$forecast_pct[[1L]]), " (Week ", h1$target_weekF[[1L]], ")")
      } else {
        "n/a"
      },
      `+2 weeks` = if (nrow(h2)) {
        paste0(.page_qmd_fmt_pp(h2$forecast_pct[[1L]]), " (Week ", h2$target_weekF[[1L]], ")")
      } else {
        "n/a"
      },
      check.names = FALSE,
      stringsAsFactors = FALSE
    )
  }
  if (!length(rows)) {
    return(character())
  }
  .page_qmd_md_table(do.call(rbind, rows))
}

.page_qmd_panel_dates <- function(panel) {
  n <- nrow(panel)
  if ("week_end_date" %in% names(panel)) {
    d <- as.Date(panel$week_end_date)
    if (any(!is.na(d))) {
      return(d)
    }
  }
  if ("week_start_date" %in% names(panel)) {
    d <- as.Date(panel$week_start_date)
    if (any(!is.na(d))) {
      return(d + 6L)
    }
  }
  rep(as.Date(NA), n)
}

.page_qmd_trend_plot <- function(panel, path) {
  pA <- 100 * panel$p_A
  pB <- 100 * panel$p_B
  d <- .page_qmd_panel_dates(panel)
  use_date <- any(!is.na(d))
  if (use_date) {
    long <- rbind(
      data.frame(x = d, Virus = "Influenza A", positivity = pA, stringsAsFactors = FALSE),
      data.frame(x = d, Virus = "Influenza B", positivity = pB, stringsAsFactors = FALSE)
    )
  } else {
    long <- rbind(
      data.frame(x = panel$weekF, Virus = "Influenza A", positivity = pA, stringsAsFactors = FALSE),
      data.frame(x = panel$weekF, Virus = "Influenza B", positivity = pB, stringsAsFactors = FALSE)
    )
  }
  p <- ggplot2::ggplot(long, ggplot2::aes(x = x, y = positivity)) +
    ggplot2::geom_line(linewidth = 0.8, colour = "#1f5f8b") +
    ggplot2::geom_point(size = 1.8, colour = "#1f5f8b") +
    ggplot2::facet_wrap(~Virus, ncol = 1, scales = "free_y") +
    ggplot2::labs(
      x = if (use_date) "Week ending" else "Season week (weekF)",
      y = "Test positivity (%)"
    ) +
    ggplot2::theme_minimal(base_size = 11)
  if (use_date) {
    p <- p + ggplot2::scale_x_date(date_labels = "%d %b")
  } else {
    p <- p + ggplot2::scale_x_continuous(breaks = panel$weekF)
  }
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  ggplot2::ggsave(path, p, width = 9, height = 5.5, dpi = 120, bg = "white")
  invisible(path)
}

.page_qmd_resolve_quarto <- function() {
  bin <- Sys.which("quarto")
  if (nzchar(bin)) {
    return(unname(bin))
  }
  candidate <- "/home/yeli/.local/bin/quarto"
  if (file.exists(candidate)) {
    return(candidate)
  }
  if (requireNamespace("quarto", quietly = TRUE)) {
    q <- tryCatch(quarto::quarto_path(), error = function(e) "")
    if (is.character(q) && length(q) == 1L && nzchar(q)) {
      return(q)
    }
  }
  ""
}

#' Build a PAGe Quarto walk-forward report (internal engine)
#'
#' Internal engine behind [page_walkforward_qmd()]. Builds a cumulative Quarto
#' (`.qmd`) walk-forward report for one season and, when requested, renders it
#' to a self-contained HTML document. The report contains an executive summary,
#' an observed-surveillance section with a weekly table and Flu A / Flu B trend
#' plots, and a walk-forward as-of review with one tab per origin week from
#' Week 8 through the latest observed week. Each tab replays the surveillance
#' state, M0 ignition status, M1 peak timing, and the M2 forecast available at
#' that origin (or a pre-window notice before Week 12).
#'
#' @param data Surveillance input. One of: `NULL` (default) to use the latest
#'   `hist*.RData` snapshot found in the default IRVRI `OP` directory, falling
#'   back to the live PHO ORVT feed; a directory containing `hist*.RData`
#'   snapshots; a path to an OLIS `.RData`/`.rda` snapshot or ORVT `.csv`; or a
#'   canonical typed A/B panel accepted by [page_v3_forecast()].
#' @param season Optional season label (for example `"2026-27"`). When `NULL`
#'   and an OLIS snapshot is supplied, the latest season present is used.
#' @param output_dir Directory that receives the `.qmd`, any plot assets, and
#'   the rendered `.html`.
#' @param file_name Optional `.qmd` file name. Defaults to
#'   `page_walkforward_<season>_week<origin>.qmd`.
#' @param render When `TRUE` (default), render the `.qmd` to self-contained HTML
#'   using the Quarto CLI.
#' @param ... Reserved for future use.
#'
#' @return Invisibly, a named list with `qmd_path`, `html_path` (or
#'   `NA_character_` when `render = FALSE`), the resolved `data` panel, and the
#'   `forecasts` data frame.
#' @noRd
.page_walkforward_qmd_impl <- function(data = NULL,
                                       season = NULL,
                                       output_dir = "reports",
                                       file_name = NULL,
                                       render = TRUE,
                                       ...) {
  if (!is.logical(render) || length(render) != 1L || is.na(render)) {
    stop("`render` must be TRUE or FALSE.", call. = FALSE)
  }
  if (!is.character(output_dir) || length(output_dir) != 1L || is.na(output_dir) ||
    !nzchar(output_dir)) {
    stop("`output_dir` must be one non-empty directory path.", call. = FALSE)
  }

  resolved <- .page_qmd_resolve_data(data)
  if (is.null(season) && is.character(resolved$path)) {
    season <- .page_qmd_infer_season(resolved$path)
  }
  panel_info <- .page_v3_panel(resolved$path, season = season, strict = TRUE)
  panel <- panel_info$data
  season <- panel_info$season
  current_origin <- max(panel$weekF)
  if (current_origin < 8L) {
    stop("Walk-forward report requires at least Week 8.", call. = FALSE)
  }

  origins <- sort(unique(panel$weekF[panel$weekF >= 8L]))
  models <- page_v3_models()

  forecasts_parts <- list()
  week_blocks <- list()
  for (w in origins) {
    w <- as.integer(w)
    state <- panel[panel$weekF == w, , drop = FALSE][1L, , drop = FALSE]
    m1a <- tryCatch(
      .page_v3_report_m1a(panel, models, w),
      error = function(e) NULL
    )
    m1s <- .page_qmd_m1_summary(m1a)
    fc <- NULL
    if (w >= .PAGE_V3_M2_MIN_ORIGIN) {
      fc <- tryCatch(
        .page_v3_report_diagnostic_forecast(panel, models, w),
        error = function(e) NULL
      )
      if (!is.null(fc) && nrow(fc)) {
        forecasts_parts[[length(forecasts_parts) + 1L]] <- fc
      }
    }

    we <- .page_qmd_fmt_date(if ("week_end_date" %in% names(state)) {
      state$week_end_date[[1L]]
    } else {
      NA_character_
    })
    state_tbl <- data.frame(
      Virus = c("Influenza A", "Influenza B"),
      Positive = c(.page_qmd_fmt_num(state$y_A[[1L]]), .page_qmd_fmt_num(state$y_B[[1L]])),
      Tests = c(.page_qmd_fmt_num(state$N_A[[1L]]), .page_qmd_fmt_num(state$N_B[[1L]])),
      Positivity = c(.page_qmd_fmt_pp(100 * state$p_A[[1L]]), .page_qmd_fmt_pp(100 * state$p_B[[1L]])),
      check.names = FALSE,
      stringsAsFactors = FALSE
    )

    block <- c(
      paste0("### Week ", w),
      "",
      paste0("**Surveillance state**", if (nzchar(we)) paste0(" (week ending ", we, ")") else ""),
      "",
      .page_qmd_md_table(state_tbl),
      "",
      paste0("- **M0 ignition:** ", m1s$m0_label),
      paste0("- **M1 timing:** ", m1s$m1_label),
      "- **M2 forecast:**"
    )
    if (is.null(fc) || !nrow(fc)) {
      block <- c(block, paste0(
        "  - Not issued at Week ", w,
        " (validated M2 window opens at Week ", .PAGE_V3_M2_MIN_ORIGIN, ")."
      ))
    } else {
      block <- c(block, "", .page_qmd_forecast_table(fc))
    }
    block <- c(block, "")
    week_blocks[[length(week_blocks) + 1L]] <- block
  }
  forecasts <- if (length(forecasts_parts)) {
    do.call(rbind, forecasts_parts)
  } else {
    data.frame(
      origin_weekF = integer(), type = character(), horizon = integer(),
      target_weekF = integer(), forecast_pct = numeric(), route = character(),
      stringsAsFactors = FALSE
    )
  }

  if (!is.null(file_name)) {
    if (!is.character(file_name) || length(file_name) != 1L || is.na(file_name) ||
      !nzchar(file_name)) {
      stop("`file_name` must be NULL or one non-empty file name.", call. = FALSE)
    }
    if (!grepl("\\.qmd$", file_name, ignore.case = TRUE)) file_name <- paste0(file_name, ".qmd")
  } else {
    file_name <- sprintf("page_walkforward_%s_week%d.qmd", season, current_origin)
  }
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  qmd_path <- normalizePath(
    file.path(output_dir, file_name),
    winslash = "/", mustWork = FALSE
  )
  assets_dir <- file.path(
    dirname(qmd_path),
    paste0(tools::file_path_sans_ext(basename(qmd_path)), "_assets")
  )
  trend_png <- file.path(assets_dir, "positivity_trend.png")
  .page_qmd_trend_plot(panel, trend_png)
  trend_ref <- file.path(
    basename(assets_dir), basename(trend_png)
  )

  cur <- panel[panel$weekF == current_origin, , drop = FALSE][1L, , drop = FALSE]
  cur_we <- .page_qmd_fmt_date(if ("week_end_date" %in% names(cur)) {
    cur$week_end_date[[1L]]
  } else {
    NA_character_
  })
  cur_m1a <- tryCatch(.page_v3_report_m1a(panel, models, current_origin), error = function(e) NULL)
  cur_m1s <- .page_qmd_m1_summary(cur_m1a)
  cur_fc <- if (current_origin >= .PAGE_V3_M2_MIN_ORIGIN) {
    forecasts[forecasts$origin_weekF == current_origin, , drop = FALSE]
  } else {
    NULL
  }
  m2_summary <- if (is.null(cur_fc) || !nrow(cur_fc)) {
    paste0(
      "Pre-window: no validated M2 forecast is issued before Week ",
      .PAGE_V3_M2_MIN_ORIGIN, "."
    )
  } else {
    paste0(
      "Influenza A ", .page_qmd_fmt_pp(cur_fc$forecast_pct[cur_fc$type == "A" & cur_fc$horizon == 1L][[1L]]),
      " (+1 week) and ", .page_qmd_fmt_pp(cur_fc$forecast_pct[cur_fc$type == "A" & cur_fc$horizon == 2L][[1L]]),
      " (+2 weeks); Influenza B ",
      .page_qmd_fmt_pp(cur_fc$forecast_pct[cur_fc$type == "B" & cur_fc$horizon == 1L][[1L]]),
      " (+1 week) and ", .page_qmd_fmt_pp(cur_fc$forecast_pct[cur_fc$type == "B" & cur_fc$horizon == 2L][[1L]]),
      " (+2 weeks)."
    )
  }

  obs_tbl <- data.frame(
    Week = panel$weekF,
    `Week ending` = vapply(.page_qmd_panel_dates(panel), .page_qmd_fmt_date, character(1L)),
    `Flu A positive` = vapply(panel$y_A, .page_qmd_fmt_num, character(1L)),
    `Flu A tests` = vapply(panel$N_A, .page_qmd_fmt_num, character(1L)),
    `Flu A %` = vapply(100 * panel$p_A, .page_qmd_fmt_pp, character(1L)),
    `Flu B positive` = vapply(panel$y_B, .page_qmd_fmt_num, character(1L)),
    `Flu B tests` = vapply(panel$N_B, .page_qmd_fmt_num, character(1L)),
    `Flu B %` = vapply(100 * panel$p_B, .page_qmd_fmt_pp, character(1L)),
    check.names = FALSE,
    stringsAsFactors = FALSE
  )

  title <- sprintf(
    "PAGe %s Flu Season Walk-Forward Report \u2014 Week %d",
    season, current_origin
  )
  subtitle <- sprintf(
    "Surveillance summary and model diagnostics through %s",
    if (nzchar(cur_we)) cur_we else paste0("Week ", current_origin)
  )

  lines <- c(
    "---",
    paste0('title: "', title, '"'),
    paste0('subtitle: "', subtitle, '"'),
    "format:",
    "  html:",
    "    theme: cosmo",
    "    page-layout: full",
    "    toc: true",
    "    toc-depth: 3",
    "    embed-resources: true",
    "execute:",
    "  echo: false",
    "  warning: false",
    "  message: false",
    "---",
    "",
    "## Executive Summary",
    "",
    paste0(
      "- **Season:** ", season, "; latest observed origin Week ", current_origin,
      if (nzchar(cur_we)) paste0(" (week ending ", cur_we, ")") else "", "."
    ),
    paste0(
      "- **Influenza A positivity:** ", .page_qmd_fmt_pp(100 * cur$p_A[[1L]]),
      " (", .page_qmd_fmt_num(cur$y_A[[1L]]), " positive of ",
      .page_qmd_fmt_num(cur$N_A[[1L]]), " tests)."
    ),
    paste0(
      "- **Influenza B positivity:** ", .page_qmd_fmt_pp(100 * cur$p_B[[1L]]),
      " (", .page_qmd_fmt_num(cur$y_B[[1L]]), " positive of ",
      .page_qmd_fmt_num(cur$N_B[[1L]]), " tests)."
    ),
    paste0("- **M0 ignition:** ", cur_m1s$m0_label, "."),
    paste0("- **M1 timing:** ", cur_m1s$m1_label, "."),
    paste0("- **M2 outlook:** ", m2_summary),
    paste0(
      "- **Walk-forward review:** as-of tabs for Week ",
      min(origins), " through Week ", max(origins), "."
    ),
    "",
    "## Observed Surveillance",
    "",
    "Weekly provincial test counts and positivity for Influenza A and Influenza B.",
    "",
    .page_qmd_md_table(obs_tbl),
    "",
    paste0("![Weekly Influenza A and B test positivity](", trend_ref, ")"),
    "",
    "## Walk-Forward As-Of Review",
    "",
    "Each tab replays the information available at that origin week: the observed",
    "surveillance state, M0 ignition status, M1 peak timing, and the M2 forecast",
    "(or a pre-window notice before Week 12).",
    "",
    "::: {.panel-tabset}",
    ""
  )
  for (blk in week_blocks) lines <- c(lines, blk, "")
  lines <- c(lines, ":::", "")
  writeLines(lines, qmd_path, useBytes = TRUE)

  html_path <- NA_character_
  if (isTRUE(render)) {
    quarto_bin <- .page_qmd_resolve_quarto()
    if (!nzchar(quarto_bin)) {
      stop(
        "Quarto executable not found. Install Quarto or put it on PATH.",
        call. = FALSE
      )
    }
    log <- tempfile(fileext = ".log")
    status <- suppressWarnings(system2(
      quarto_bin,
      c("render", shQuote(qmd_path), "--to", "html"),
      stdout = log, stderr = log
    ))
    if (!identical(as.integer(status), 0L)) {
      msg <- paste(readLines(log, warn = FALSE), collapse = "\n")
      stop("Quarto render failed (status ", status, "):\n", msg, call. = FALSE)
    }
    html_path <- sub("\\.qmd$", ".html", qmd_path)
    if (!file.exists(html_path)) {
      stop("Quarto reported success but no HTML was produced.", call. = FALSE)
    }
    html_path <- normalizePath(html_path, winslash = "/", mustWork = TRUE)
  }

  invisible(list(
    qmd_path = qmd_path,
    html_path = html_path,
    data = panel,
    forecasts = forecasts
  ))
}
