#!/usr/bin/env Rscript

promotion_usage <- function() {
  cat(
    paste(
      "Promote a passing post-refit PAGe kit into an immutable private registry.",
      "",
      "Usage:",
      "  Rscript scripts/promotion/promote_post_refit.R [options]",
      "",
      "Required options:",
      "  --data PATH",
      "  --acceptance-bundle PATH",
      "  --acceptance-manifest PATH",
      "  --candidate-kit PATH",
      "  --incumbent-kit PATH",
      "  --refit-artifact PATH",
      "  --refit-manifest PATH",
      "  --registry-dir PATH",
      "  --audit-dir PATH",
      "",
      "Optional:",
      "  --deployment-id ID    Immutable directory name; generated if omitted.",
      "  --kit-compatibility MODE",
      "                        strict (default) or legacy_m2 for the incumbent.",
      "  --preflight-only      Validate the chain and write nothing.",
      "  --help                Show this help.",
      "",
      "Both --name=value and --name value forms are accepted.",
      sep = "\n"
    ),
    "\n"
  )
}

promotion_parse_args <- function(args) {
  out <- list()
  i <- 1L
  while (i <= length(args)) {
    arg <- args[[i]]
    if (identical(arg, "--help") || identical(arg, "-h")) {
      out$help <- TRUE
      i <- i + 1L
      next
    }
    if (identical(arg, "--preflight-only")) {
      out$preflight_only <- TRUE
      i <- i + 1L
      next
    }
    if (!grepl("^--[A-Za-z0-9-]+(?:=.*)?$", arg)) {
      stop("Unknown argument: ", arg, call. = FALSE)
    }
    pieces <- strsplit(sub("^--", "", arg), "=", fixed = TRUE)[[1L]]
    key <- gsub("-", "_", pieces[[1L]], fixed = TRUE)
    if (length(pieces) > 1L) {
      value <- paste(pieces[-1L], collapse = "=")
    } else {
      if (i == length(args) || grepl("^--", args[[i + 1L]])) {
        stop("Missing value for option: ", arg, call. = FALSE)
      }
      i <- i + 1L
      value <- args[[i]]
    }
    out[[key]] <- value
    i <- i + 1L
  }
  out
}

promotion_git_commit <- function() {
  commit <- tryCatch(
    system2(
      "git", c("rev-parse", "--verify", "HEAD"),
      stdout = TRUE, stderr = FALSE
    ),
    error = function(error) character(0)
  )
  commit <- tolower(trimws(if (length(commit)) commit[[1L]] else ""))
  if (!grepl("^[0-9a-f]{7,64}$", commit)) {
    stop("Could not determine the current Git commit for promotion.", call. = FALSE)
  }
  commit
}

args <- promotion_parse_args(commandArgs(trailingOnly = TRUE))
if (isTRUE(args$help)) {
  promotion_usage()
  quit(save = "no", status = 0L)
}

required <- c(
  "data", "acceptance_bundle", "acceptance_manifest", "candidate_kit",
  "incumbent_kit", "refit_artifact", "refit_manifest", "registry_dir",
  "audit_dir"
)
missing <- required[!vapply(
  required,
  function(name) is.character(args[[name]]) && nzchar(args[[name]]),
  logical(1)
)]
if (length(missing)) {
  promotion_usage()
  stop(
    "Missing required option(s): ",
    paste(paste0("--", gsub("_", "-", missing)), collapse = ", "),
    call. = FALSE
  )
}
if (!requireNamespace("PAGe", quietly = TRUE)) {
  stop("Install PAGe before running the promotion workflow.", call. = FALSE)
}

invocation <- commandArgs(trailingOnly = FALSE)
script_arg <- grep("^--file=", invocation, value = TRUE)
if (!length(script_arg)) {
  stop("Could not locate the promotion script path.", call. = FALSE)
}
script_path <- normalizePath(sub("^--file=", "", script_arg[[1L]]))
source(file.path(dirname(script_path), "promotion_workflow.R"))

result <- promote_post_refit(
  data_path = args$data,
  acceptance_bundle_path = args$acceptance_bundle,
  acceptance_manifest_path = args$acceptance_manifest,
  candidate_path = args$candidate_kit,
  incumbent_path = args$incumbent_kit,
  refit_artifact_path = args$refit_artifact,
  refit_manifest_path = args$refit_manifest,
  registry_dir = args$registry_dir,
  audit_dir = args$audit_dir,
  deployment_id = args$deployment_id,
  kit_compatibility = if (is.null(args$kit_compatibility)) {
    "strict"
  } else {
    args$kit_compatibility
  },
  preflight_only = isTRUE(args$preflight_only),
  code_commit = promotion_git_commit()
)
if (isTRUE(result$preflight)) {
  cat(
    "Preflight passed: full acceptance-to-refit chain validated for ",
    result$deployment_id,
    ". No promotion outputs were written.\n",
    sep = ""
  )
} else {
  cat("Promoted deployment: ", result$deployment_id, "\n", sep = "")
  cat("Private kit: ", result$promoted_kit_path, "\n", sep = "")
  cat("Audit manifest: ", result$manifest_json_path, "\n", sep = "")
}
