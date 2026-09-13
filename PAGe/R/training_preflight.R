# Read-only preflight support audit for M0/M1/M2.
# Reuses existing validators; does not launch workers or modify state.

#' Preflight support audit for M0/M1/M2
#'
#' A structured, read-only audit that reuses existing per-stage validators to
#' report whether supplied grids and specifications are supportable by the
#' available data. Does not launch workers, fit models, or modify state.
#'
#' @param data Canonical surveillance data frame.
#' @param m0_grid Optional M0 tuning grid (data frame).
#' @param m1_grid Optional M1 tuning grid (data frame).
#' @param m2_grid Optional M2 tuning grid (data frame).
#' @param n_weeks Integer reference-domain size (default 52).
#' @param selection Optional \code{page_season_selection}. When supplied, only
#'   training seasons are used for data-dependent checks.
#' @param aligned Optional aligned M0 output with a \code{newWeek} column. When
#'   supplied, M1 reference-basis support is checked for every requested
#'   \code{k_ref}; otherwise that check is reported as deferred.
#' @param m2_data Optional prepared M2 training data with \code{lead} and
#'   post-ignition covariates. When omitted, M2 grid-domain checks still run,
#'   but basis support is reported as deferred until this handoff exists.
#'
#' @return A \code{page_preflight_audit} list with one entry per requested
#'   stage. Each entry contains \code{valid} (logical), \code{issues} (character
#'   vector of problems), and \code{remediation} (character vector of
#'   suggestions). The audit itself stops on malformed input (e.g., wrong types)
#'   but records per-stage validation failures in the report.
#' @export
preflight_support_audit <- function(data,
                                    m0_grid = NULL,
                                    m1_grid = NULL,
                                    m2_grid = NULL,
                                    n_weeks = 52L,
                                    selection = NULL,
                                    aligned = NULL,
                                    m2_data = NULL) {
  if (!is.data.frame(data)) {
    stop("`data` must be a data frame.", call. = FALSE)
  }
  if (!"season" %in% names(data)) {
    stop("`data` must contain a `season` column.", call. = FALSE)
  }
  if (!is.null(selection) && !inherits(selection, "page_season_selection")) {
    stop("`selection` must be a `page_season_selection` or NULL.", call. = FALSE)
  }
  if (!is.null(aligned) && !is.data.frame(aligned)) {
    stop("`aligned` must be a data frame or NULL.", call. = FALSE)
  }
  if (!is.null(m2_data) && !is.data.frame(m2_data)) {
    stop("`m2_data` must be a data frame or NULL.", call. = FALSE)
  }
  if (!is.null(m0_grid)) {
    if (!is.data.frame(m0_grid)) {
      stop("`m0_grid` must be a data frame or NULL.", call. = FALSE)
    }
  }
  if (!is.null(m1_grid)) {
    if (!is.data.frame(m1_grid)) {
      stop("`m1_grid` must be a data frame or NULL.", call. = FALSE)
    }
  }
  if (!is.null(m2_grid)) {
    if (!is.data.frame(m2_grid)) {
      stop("`m2_grid` must be a data frame or NULL.", call. = FALSE)
    }
  }

  audit_data <- if (!is.null(selection)) {
    data[as.character(data$season) %in% selection$training_seasons, , drop = FALSE]
  } else {
    data
  }

  result <- list()

  if (!is.null(m0_grid)) {
    result$m0 <- .preflight_m0(audit_data, m0_grid)
  }

  if (!is.null(m1_grid)) {
    result$m1 <- .preflight_m1(m1_grid, n_weeks, aligned = aligned)
  }

  if (!is.null(m2_grid)) {
    m2_support_data <- m2_data
    if (is.null(m2_support_data) &&
      all(c("lead", "post_ign") %in% names(audit_data))) {
      m2_support_data <- audit_data
    }
    result$m2 <- .preflight_m2(m2_support_data, m2_grid)
  }

  if (!length(result)) {
    stop(
      "At least one of `m0_grid`, `m1_grid`, or `m2_grid` must be supplied.",
      call. = FALSE
    )
  }

  structure(result, class = "page_preflight_audit")
}

.preflight_m0 <- function(data, grid) {
  issues <- character(0)
  remediation <- character(0)
  valid <- TRUE

  outcome <- tryCatch(
    {
      .validate_m0_grid_support(grid, data = data)
      list(ok = TRUE)
    },
    error = function(e) {
      list(ok = FALSE, message = conditionMessage(e))
    }
  )

  if (!outcome$ok) {
    valid <- FALSE
    issues <- c(issues, outcome$message)
    remediation <- c(remediation, paste0(
      "M0 grid contains unsupported parameter values or exceeds data support. ",
      "Check grid thresholds, integer axes, and window bounds against the ",
      "training data dimensions."
    ))
  }

  list(
    valid = valid, issues = unique(issues), remediation = unique(remediation),
    support_checked = TRUE, deferred = FALSE
  )
}

.preflight_m1 <- function(grid, n_weeks, aligned = NULL) {
  issues <- character(0)
  remediation <- character(0)
  valid <- TRUE

  outcome <- tryCatch(
    {
      .validate_m1_grid_support(grid, n_weeks = n_weeks)
      list(ok = TRUE)
    },
    error = function(e) {
      list(ok = FALSE, message = conditionMessage(e))
    }
  )

  if (!outcome$ok) {
    valid <- FALSE
    issues <- c(issues, outcome$message)
    remediation <- c(remediation, paste0(
      "M1 grid contains integer axis values outside the supported [2, ",
      n_weeks, "] reference domain. Reduce k_ref or slope_window, or increase ",
      "the reference domain size."
    ))
  }

  support_checked <- FALSE
  deferred <- TRUE
  if (valid && !is.null(aligned)) {
    if (!"newWeek" %in% names(aligned)) {
      valid <- FALSE
      issues <- c(issues, "M1 aligned support data must contain `newWeek`.")
      remediation <- c(
        remediation,
        "Pass the complete aligned M0 handoff, including its `newWeek` column."
      )
    } else {
      support_checked <- TRUE
      deferred <- FALSE
      for (k in sort(unique(as.numeric(grid$k_ref)))) {
        check <- tryCatch(
          .validate_m1_reference_support(aligned, k = k, n_weeks = n_weeks),
          error = function(e) conditionMessage(e)
        )
        if (is.character(check)) {
          valid <- FALSE
          issues <- c(issues, check)
          remediation <- c(
            remediation,
            paste0("Reduce `k_ref` to the supported unique aligned-week count (", k, ").")
          )
        }
      }
    }
  }
  list(
    valid = valid, issues = unique(issues), remediation = unique(remediation),
    support_checked = support_checked, deferred = deferred
  )
}

.preflight_m2 <- function(data, grid) {
  issues <- character(0)
  remediation <- character(0)
  valid <- TRUE

  grid_outcome <- tryCatch(
    {
      validated <- .validate_m2_grid(grid)
      list(ok = TRUE, grid = validated)
    },
    error = function(e) {
      list(ok = FALSE, message = conditionMessage(e))
    }
  )

  if (!grid_outcome$ok) {
    valid <- FALSE
    issues <- c(issues, grid_outcome$message)
    remediation <- c(remediation, paste0(
      "M2 grid has invalid parameter values. Check integer bounds, [0, 1] ",
      "ranges for alpha_state/bias_alpha/bias_beta, and k_e != 1."
    ))
    return(list(
      valid = valid, issues = issues, remediation = remediation,
      support_checked = FALSE, deferred = TRUE
    ))
  }

  validated_grid <- grid_outcome$grid
  specs_outcome <- tryCatch(
    {
      .m2_specs_from_grid(validated_grid)
    },
    error = function(e) {
      list(ok = FALSE, message = conditionMessage(e))
    }
  )

  if (!is.list(specs_outcome) || !is.null(specs_outcome$ok)) {
    valid <- FALSE
    issues <- c(issues, specs_outcome$message)
    return(list(
      valid = valid, issues = issues, remediation = remediation,
      support_checked = FALSE, deferred = TRUE
    ))
  }

  specs <- specs_outcome$specs
  if (is.null(data)) {
    return(list(
      valid = valid,
      issues = "M2 basis support deferred: supply `m2_data` after the M1 handoff.",
      remediation = "Run this audit again with the prepared post-ignition M2 training data before launching M2 workers.",
      support_checked = FALSE,
      deferred = TRUE
    ))
  }
  unsupported_specs <- character(0)

  for (spec_id in names(specs)) {
    spec <- specs[[spec_id]]
    spec_outcome <- tryCatch(
      {
        .validate_m2_spec_support(data, spec)
        NULL
      },
      error = function(e) {
        conditionMessage(e)
      }
    )
    if (!is.null(spec_outcome)) {
      unsupported_specs <- c(unsupported_specs, paste0(spec_id, ": ", spec_outcome))
    }
  }

  if (length(unsupported_specs)) {
    valid <- FALSE
    issues <- c(issues, paste0(
      length(unsupported_specs), " M2 spec(s) exceed data support: ",
      paste(utils::head(unsupported_specs, 5L), collapse = "; "),
      if (length(unsupported_specs) > 5L) "..." else ""
    ))
    remediation <- c(remediation, paste0(
      "Reduce basis dimensions (k_f, k_e, k_r, k_de, k_sp, k_n, k_w, k_s) ",
      "for unsupported specifications, or expand the training data."
    ))
  }

  list(
    valid = valid, issues = unique(issues), remediation = unique(remediation),
    support_checked = TRUE, deferred = FALSE
  )
}

#' @export
print.page_preflight_audit <- function(x, ...) {
  stages <- names(x)
  cat("PAGe Preflight Support Audit\n")
  cat("============================\n")
  for (stage in stages) {
    entry <- x[[stage]]
    status <- if (!isTRUE(entry$valid)) {
      "FAIL"
    } else if (isTRUE(entry$deferred)) {
      "DEFERRED"
    } else {
      "PASS"
    }
    cat(sprintf("\n[%s] %s\n", status, toupper(stage)))
    if (length(entry$issues)) {
      cat("  Issues:\n")
      for (issue in entry$issues) {
        cat("    - ", issue, "\n", sep = "")
      }
    }
    if (length(entry$remediation)) {
      cat("  Remediation:\n")
      for (rem in entry$remediation) {
        cat("    - ", rem, "\n", sep = "")
      }
    }
  }
  invisible(x)
}
