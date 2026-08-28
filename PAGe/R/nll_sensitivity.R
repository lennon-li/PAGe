# Utilities for inspecting the marginal effect of each tuning-grid axis.

.nll_sensitivity_is_tuning <- function(x) {
  is.list(x) && !is.null(x$grid) && is.data.frame(x$grid)
}

.nll_sensitivity_results <- function(x) {
  if (.nll_sensitivity_is_tuning(x)) {
    return(list(result = x))
  }
  if (!is.list(x) || !length(x)) {
    stop(
      "`x` must be a tuning result or a non-empty list of tuning results.",
      call. = FALSE
    )
  }
  if (!all(vapply(x, .nll_sensitivity_is_tuning, logical(1)))) {
    stop(
      "Every element of a tuning-result collection must contain a data-frame `grid`.",
      call. = FALSE
    )
  }
  x
}

.nll_sensitivity_metric <- function(result, metric) {
  if (is.null(metric)) {
    metric <- if ("bernoulli_nll" %in% names(result$summary %||% list())) {
      "bernoulli_nll"
    } else if ("mean_nll" %in% names(result$summary %||% list())) {
      "mean_nll"
    } else {
      stop(
        "`metric` is required when the tuning summary has no NLL column.",
        call. = FALSE
      )
    }
  }
  if (!is.character(metric) || length(metric) != 1L ||
    is.na(metric) || !nzchar(metric)) {
    stop("`metric` must be one non-empty column name.", call. = FALSE)
  }
  metric
}

.nll_sensitivity_summary <- function(result, metric) {
  grid <- as.data.frame(result$grid, stringsAsFactors = FALSE)
  if (!"spec_id" %in% names(grid)) {
    grid$spec_id <- paste0("spec_", seq_len(nrow(grid)))
  }
  if (anyDuplicated(as.character(grid$spec_id))) {
    stop("Tuning grid `spec_id` values must be unique.", call. = FALSE)
  }

  summary <- result$summary
  if (!is.data.frame(summary) || !all(c("spec_id", metric) %in% names(summary))) {
    scores <- result$scores
    if (!is.data.frame(scores) || !all(c("spec_id", metric) %in% names(scores))) {
      stop(
        "Tuning result does not contain the requested metric `", metric,
        "` in `summary` or `scores`.",
        call. = FALSE
      )
    }
    summary <- stats::aggregate(
      scores[[metric]],
      by = list(spec_id = as.character(scores$spec_id)),
      FUN = function(z) mean(z[is.finite(z)], na.rm = TRUE)
    )
    names(summary)[2L] <- metric
  } else {
    summary <- as.data.frame(summary, stringsAsFactors = FALSE)
  }
  summary$spec_id <- as.character(summary$spec_id)
  if (anyDuplicated(summary$spec_id)) {
    stop("Tuning summary `spec_id` values must be unique.", call. = FALSE)
  }
  summary[[metric]] <- suppressWarnings(as.numeric(summary[[metric]]))
  summary <- summary[is.finite(summary[[metric]]), c("spec_id", metric), drop = FALSE]
  if (!nrow(summary)) {
    stop("Tuning result has no finite values for metric `", metric, "`.", call. = FALSE)
  }
  merge(summary, grid, by = "spec_id", all.x = FALSE, sort = FALSE)
}

.nll_sensitivity_parameters <- function(grid,
                                        parameters = NULL,
                                        exclude = c("spec_id", "provenance", "run", "season")) {
  excluded <- unique(exclude)
  if (is.null(parameters)) {
    parameters <- names(grid)[vapply(grid, function(z) {
      values <- suppressWarnings(as.numeric(z))
      is.numeric(z) && any(is.finite(values)) &&
        length(unique(values[is.finite(values)])) >= 2L
    }, logical(1))]
    parameters <- setdiff(parameters, excluded)
  } else {
    if (!is.character(parameters) || !length(parameters) ||
      anyNA(parameters) || any(!nzchar(parameters))) {
      stop("`parameters` must be non-empty column names.", call. = FALSE)
    }
    missing <- setdiff(parameters, names(grid))
    if (length(missing)) {
      stop(
        "No requested parameter was found in the tuning grid: ",
        paste(missing, collapse = ", "),
        call. = FALSE
      )
    }
  }
  if (!length(parameters)) {
    stop("The tuning grid has no numeric parameter with at least two values.", call. = FALSE)
  }
  bad <- parameters[!vapply(grid[parameters], is.numeric, logical(1))]
  if (length(bad)) {
    stop("Requested parameters must be numeric: ", paste(bad, collapse = ", "), call. = FALSE)
  }
  parameters
}

.nll_sensitivity_axis <- function(data, parameter, metric, run) {
  values <- suppressWarnings(as.numeric(data[[parameter]]))
  metric_values <- data[[metric]]
  keep <- is.finite(values) & is.finite(metric_values)
  data <- data[keep, c("spec_id", metric), drop = FALSE]
  data$value <- values[keep]
  if (!nrow(data)) {
    return(NULL)
  }
  levels <- sort(unique(data$value))
  rows <- lapply(levels, function(value) {
    d <- data[data$value == value, , drop = FALSE]
    best <- which.min(d[[metric]])
    vals <- d[[metric]]
    data.frame(
      run = run, parameter = parameter, value = value,
      n_specs = length(unique(d$spec_id)),
      n_values = nrow(d),
      mean_metric = mean(vals),
      sd_metric = if (length(vals) > 1L) stats::sd(vals) else NA_real_,
      best_metric = vals[best],
      best_spec_id = as.character(d$spec_id[best]),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

.nll_sensitivity_gains <- function(axis_data, metric) {
  if (is.null(axis_data) || !nrow(axis_data)) {
    return(axis_data)
  }
  split_data <- split(axis_data, list(axis_data$run, axis_data$parameter), drop = TRUE)
  rows <- lapply(split_data, function(d) {
    d <- d[order(d$value), , drop = FALSE]
    d$previous_value <- c(NA_real_, head(d$value, -1L))
    d$previous_best_metric <- c(NA_real_, head(d$best_metric, -1L))
    d$step <- d$value - d$previous_value
    # Positive gain means that moving upward on the axis reduced the metric.
    d$adjacent_gain <- d$previous_best_metric - d$best_metric
    d$gain_per_unit <- d$adjacent_gain / abs(d$step)
    d$global_best <- min(d$best_metric, na.rm = TRUE)
    d$delta_to_global_best <- d$best_metric - d$global_best
    d$metric <- metric
    d
  })
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

.nll_sensitivity_matched <- function(data, metric, parameters, run) {
  rows <- list()
  row_index <- 0L
  for (parameter in parameters) {
    other <- setdiff(parameters, parameter)
    values <- suppressWarnings(as.numeric(data[[parameter]]))
    keep <- is.finite(values) & is.finite(data[[metric]])
    d <- data[keep, , drop = FALSE]
    d$value <- values[keep]
    if (!nrow(d)) next
    if (length(other)) {
      group_key <- do.call(
        paste,
        c(lapply(d[other], function(z) {
          z <- as.character(z)
          z[is.na(z)] <- "<NA>"
          z
        }), sep = "\r")
      )
    } else {
      group_key <- rep("all", nrow(d))
    }
    for (key in unique(group_key)) {
      group <- d[group_key == key, , drop = FALSE]
      levels <- sort(unique(group$value))
      if (length(levels) < 2L) next
      for (j in seq_len(length(levels) - 1L)) {
        from <- group[group$value == levels[j], , drop = FALSE]
        to <- group[group$value == levels[j + 1L], , drop = FALSE]
        from <- from[which.min(from[[metric]]), , drop = FALSE]
        to <- to[which.min(to[[metric]]), , drop = FALSE]
        row_index <- row_index + 1L
        rows[[row_index]] <- data.frame(
          run = run, parameter = parameter,
          from_value = levels[j], to_value = levels[j + 1L],
          step = levels[j + 1L] - levels[j],
          from_spec_id = as.character(from$spec_id[1L]),
          to_spec_id = as.character(to$spec_id[1L]),
          from_metric = from[[metric]][1L], to_metric = to[[metric]][1L],
          adjacent_gain = from[[metric]][1L] - to[[metric]][1L],
          gain_per_unit = (from[[metric]][1L] - to[[metric]][1L]) /
            abs(levels[j + 1L] - levels[j]),
          metric = metric, stringsAsFactors = FALSE
        )
      }
    }
  }
  if (!length(rows)) {
    return(data.frame(
      run = character(), parameter = character(), from_value = numeric(),
      to_value = numeric(), step = numeric(), from_spec_id = character(),
      to_spec_id = character(), from_metric = numeric(), to_metric = numeric(),
      adjacent_gain = numeric(), gain_per_unit = numeric(), metric = character(),
      stringsAsFactors = FALSE
    ))
  }
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

.nll_sensitivity_by_season <- function(result, metric, parameters, run) {
  scores <- result$scores
  if (!is.data.frame(scores) ||
    !all(c("spec_id", "season", metric) %in% names(scores))) {
    return(data.frame())
  }
  grid <- as.data.frame(result$grid, stringsAsFactors = FALSE)
  if (!"spec_id" %in% names(grid)) {
    grid$spec_id <- paste0("spec_", seq_len(nrow(grid)))
  }
  scores <- merge(
    scores[c("spec_id", "season", metric)],
    grid[c("spec_id", parameters)],
    by = "spec_id", all.x = FALSE, sort = FALSE
  )
  scores$season <- as.character(scores$season)
  pieces <- lapply(parameters, function(parameter) {
    seasons <- sort(unique(scores$season))
    out <- lapply(seasons, function(season) {
      d <- scores[scores$season == season, , drop = FALSE]
      axis <- .nll_sensitivity_axis(d, parameter, metric, run)
      if (is.null(axis)) {
        return(NULL)
      }
      axis$season <- season
      axis
    })
    do.call(rbind, out)
  })
  out <- do.call(rbind, pieces)
  if (is.null(out) || !nrow(out)) {
    return(data.frame())
  }
  rownames(out) <- NULL
  out
}

#' Extract metric sensitivity across tuning-grid parameters
#'
#' For every numeric grid axis, this function reports the mean and best
#' cross-validation metric at each tested value, the best specification, and
#' the adjacent improvement when moving upward through the tested values.
#' The default metric is Bernoulli NLL. A named list of tuning results can be
#' supplied to compare independent holdout cycles.
#'
#' @param x A tuning result, or a named list of tuning results.
#' @param metric Character scalar metric column. Defaults to
#'   \code{"bernoulli_nll"}; pass another metric for M0/M1 analyses.
#' @param parameters Optional numeric grid columns to inspect. By default all
#'   numeric columns with at least two finite values are included.
#' @return An object with \code{overall}, \code{by_season}, \code{gains}, and
#'   \code{matched_gains} data frames. The matched table compares specifications
#'   that differ only in the named parameter, which is the preferred estimate
#'   for a parameter-specific gain cap. Positive \code{adjacent_gain} means the
#'   newer value reduced the metric; \code{gain_per_unit} divides that change by
#'   the parameter step. The object has class \code{page_nll_sensitivity}.
#' @export
extract_nll_sensitivity <- function(x,
                                    metric = "bernoulli_nll",
                                    parameters = NULL) {
  results <- .nll_sensitivity_results(x)
  run_names <- names(results)
  if (is.null(run_names) || any(!nzchar(run_names))) {
    run_names <- paste0("run", seq_along(results))
  }

  overall <- list()
  by_season <- list()
  matched_gains <- list()
  for (i in seq_along(results)) {
    result <- results[[i]]
    this_metric <- .nll_sensitivity_metric(result, metric)
    summary <- .nll_sensitivity_summary(result, this_metric)
    this_parameters <- .nll_sensitivity_parameters(
      summary, parameters,
      exclude = c("spec_id", "provenance", "run", "season", this_metric)
    )
    overall[[i]] <- do.call(rbind, lapply(this_parameters, function(parameter) {
      .nll_sensitivity_axis(summary, parameter, this_metric, run_names[i])
    }))
    matched_gains[[i]] <- .nll_sensitivity_matched(
      summary, this_metric, this_parameters, run_names[i]
    )
    by_season[[i]] <- .nll_sensitivity_by_season(
      result, this_metric, this_parameters, run_names[i]
    )
  }
  overall <- do.call(rbind, overall)
  rownames(overall) <- NULL
  gains <- .nll_sensitivity_gains(overall, metric)
  by_season <- by_season[!vapply(by_season, is.null, logical(1))]
  by_season <- if (length(by_season)) do.call(rbind, by_season) else data.frame()
  if (nrow(by_season)) rownames(by_season) <- NULL
  matched_gains <- do.call(rbind, matched_gains)
  rownames(matched_gains) <- NULL
  structure(
    list(
      overall = overall,
      by_season = by_season,
      gains = gains,
      matched_gains = matched_gains,
      metric = metric,
      parameters = unique(overall$parameter)
    ),
    class = c("page_nll_sensitivity", "list")
  )
}

#' Plot metric sensitivity across tuning-grid parameters
#'
#' @param x A tuning result, a named tuning-result list, or a
#'   \code{page_nll_sensitivity} object from \code{extract_nll_sensitivity()}.
#' @param metric Metric column when \code{x} is a raw tuning result.
#' @param parameters Optional parameters to plot.
#' @param run Optional run names to retain.
#' @param season Optional season. When supplied, plots season-specific values
#'   from \code{by_season}; otherwise plots overall values.
#' @param statistic Either \code{"best_metric"} (default),
#'   \code{"mean_metric"}, or \code{"adjacent_gain"}.
#' @param facet_scales Passed to \code{ggplot2::facet_wrap()}.
#' @return A \code{ggplot} object.
#' @export
plot_nll_sensitivity <- function(x,
                                 metric = "bernoulli_nll",
                                 parameters = NULL,
                                 run = NULL,
                                 season = NULL,
                                 statistic = c("best_metric", "mean_metric", "adjacent_gain"),
                                 facet_scales = "free_x") {
  statistic <- match.arg(statistic)
  analysis <- if (inherits(x, "page_nll_sensitivity")) {
    x
  } else {
    extract_nll_sensitivity(x, metric = metric, parameters = parameters)
  }
  if (!is.null(season) && statistic == "adjacent_gain") {
    stop("`adjacent_gain` is available only for overall sensitivity data.", call. = FALSE)
  }
  data <- if (!is.null(season)) {
    analysis$by_season
  } else if (statistic == "adjacent_gain") {
    analysis$gains
  } else {
    analysis$overall
  }
  if (!is.null(season) && nrow(data)) {
    data <- data[data$season %in% as.character(season), , drop = FALSE]
  }
  if (!is.null(run) && nrow(data)) {
    data <- data[data$run %in% as.character(run), , drop = FALSE]
  }
  if (!is.null(parameters) && nrow(data)) {
    data <- data[data$parameter %in% parameters, , drop = FALSE]
  }
  if (!nrow(data)) {
    stop("No sensitivity observations remain after the requested filters.", call. = FALSE)
  }
  plot_data <- data[
    is.finite(data$value) & is.finite(data[[statistic]]), ,
    drop = FALSE
  ]
  if (!nrow(plot_data)) {
    stop("No finite sensitivity observations remain to plot.", call. = FALSE)
  }
  group_key <- interaction(plot_data$run, plot_data$parameter, drop = TRUE)
  line_data <- plot_data[duplicated(group_key) | duplicated(group_key, fromLast = TRUE), , drop = FALSE]
  ggplot2::ggplot(
    plot_data,
    ggplot2::aes(
      x = .data$value, y = .data[[statistic]],
      colour = .data$run, group = interaction(.data$run, .data$parameter)
    )
  ) +
    ggplot2::geom_line(data = line_data, na.rm = TRUE) +
    ggplot2::geom_point(na.rm = TRUE) +
    ggplot2::facet_wrap(~parameter, scales = facet_scales) +
    ggplot2::labs(
      x = "Grid value", y = paste0(statistic, " (", analysis$metric, ")"),
      colour = "Run"
    ) +
    ggplot2::theme_bw()
}
