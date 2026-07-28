#!/usr/bin/env Rscript

# Disclosure-safe, bounded proof of the canonical release chain. The model and
# replay evidence are synthetic fixtures; this script makes no claim about a
# real 2025-26 acceptance decision or deployed artifact.

public_synthetic_release_usage <- function() {
  paste(
    "Usage:",
    "  Rscript scripts/public/synthetic_release_workflow.R --smoke [--output-dir=DIR]",
    "",
    "Runs a small, entirely synthetic acceptance -> fixed refresh -> immutable",
    "promotion -> verified-load workflow. If --output-dir is omitted, temporary",
    "artifacts are removed after the smoke check.",
    sep = "\n"
  )
}

public_synthetic_git_commit <- function() {
  commit <- suppressWarnings(system2(
    "git", c("rev-parse", "--verify", "HEAD"),
    stdout = TRUE, stderr = FALSE
  ))
  if (length(commit) != 1L || !grepl("^[0-9a-f]{7,64}$", commit)) {
    stop("Could not determine the current Git commit.", call. = FALSE)
  }
  commit
}

public_synthetic_data <- function(seed = 2026L) {
  simulated <- PAGe::simulate_flu_seasons(
    S = 3L, weeks = seq_len(16L), seed = seed
  )
  labels <- c("2023-24", "2024-25", "2025-26")
  index <- as.integer(as.character(simulated$season))
  PAGe::prepare_surveillance_data(data.frame(
    season = labels[index],
    weekF = as.integer(simulated$newWeek),
    y = as.integer(simulated$y),
    N = as.integer(simulated$y + simulated$neg),
    stringsAsFactors = FALSE
  ))
}

public_synthetic_gam <- function() {
  if (!requireNamespace("mgcv", quietly = TRUE)) {
    stop("The `mgcv` package is required for the synthetic smoke workflow.",
      call. = FALSE
    )
  }
  model_data <- data.frame(
    logit_f_eff = seq(-2, 2, length.out = 24L),
    z_ema = sin(seq(0, 2 * pi, length.out = 24L)),
    lead = rep(1:2, 12L)
  )
  probability <- stats::plogis(
    -2 + 0.7 * model_data$logit_f_eff +
      0.2 * model_data$z_ema + 0.1 * model_data$lead
  )
  model_data$y <- round(100 * probability)
  model_data$neg <- 100L - model_data$y
  mgcv::gam(
    cbind(y, neg) ~ logit_f_eff + z_ema + lead,
    family = stats::binomial(),
    data = model_data,
    method = "REML"
  )
}

public_synthetic_spec <- function() {
  list(
    delta = 0L, Kr = 1L, k_f = 4L, k_e = 2L, alpha_state = 0.15,
    k_r = 0L, k_de = 0L, k_sp = 0L, bias_alpha = 0.05,
    bias_beta = 0
  )
}

public_synthetic_candidate_kit <- function(training_seasons) {
  spec <- public_synthetic_spec()
  list(
    m0_params = list(p_thresh = 0.005),
    ref = list(anchorWeek = 20),
    hyper = list(),
    manual_labels = c("2023-24" = 20L, "2024-25" = 22L),
    flag_args = list(p_thresh = 0.01, n_consec = 2L),
    M1_PARAMS = list(
      temperature = 0.25, rise_weight = 1, trough_weight = 0.1,
      peak_decay = 0.3, slope_weight = 8, slope_window = 6L,
      dynamic_temp = FALSE, dynamic_temp_pivot = 10L
    ),
    best_spec = spec,
    m2_production = list(
      fit = public_synthetic_gam(),
      best_spec_id = "synthetic-candidate-v1",
      spec = spec,
      training_seasons = training_seasons
    )
  )
}

public_synthetic_incumbent_kit <- function(training_seasons) {
  list(m2_production = list(
    best_spec_id = "synthetic-incumbent-v1",
    spec = public_synthetic_spec(),
    training_seasons = training_seasons
  ))
}

public_synthetic_replay <- function(kit, allD, season) {
  holdout <- allD[as.character(allD$season) == season, , drop = FALSE]
  if (!nrow(holdout)) stop("Synthetic holdout is missing.", call. = FALSE)
  is_candidate <- identical(
    kit$m2_production$best_spec_id, "synthetic-candidate-v1"
  )
  observed <- as.numeric(holdout$p)
  predictions <- data.frame(
    season = season,
    weekF = holdout$weekF,
    lead = rep(1:2, length.out = nrow(holdout)),
    t_since = holdout$weekF - 5,
    p_hat = if (is_candidate) {
      pmin(0.99, pmax(0.01, observed))
    } else {
      rep(0.50, nrow(holdout))
    },
    p_obs = observed,
    y_lead = holdout$y,
    N_lead = holdout$N,
    p_lo = if (is_candidate) pmax(0, observed - 0.03) else 0.25,
    p_hi = if (is_candidate) pmin(1, observed + 0.03) else 0.75,
    stringsAsFactors = FALSE
  )
  list(
    season = season,
    status = "unseen_replay_complete",
    predictions = predictions,
    metrics = PAGe::summarize_forecast_metrics(predictions),
    diagnostics = PAGe::summarize_replay_diagnostics(predictions),
    ignition_week = 5,
    ignition_status = "synthetic_locked",
    eligible_for_refresh = FALSE
  )
}

run_public_synthetic_release <- function(
  output_dir,
  repo_root = getwd(),
  run_id = paste0("synthetic-acceptance-", Sys.getpid()),
  deployment_id = paste0("synthetic-deployment-", Sys.getpid()),
  code_commit = public_synthetic_git_commit(),
  run_timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
) {
  if (!is.character(output_dir) || length(output_dir) != 1L ||
    is.na(output_dir) || !nzchar(output_dir)) {
    stop("`output_dir` must be one non-empty path.", call. = FALSE)
  }
  if (file.exists(output_dir) || dir.exists(output_dir)) {
    stop("Synthetic workflow output already exists; refusing to overwrite it.",
      call. = FALSE
    )
  }
  dependency_paths <- file.path(repo_root, c(
    "scripts/acceptance/acceptance_workflow.R",
    "season2526/refit_helpers.R",
    "scripts/promotion/promotion_workflow.R"
  ))
  if (any(!file.exists(dependency_paths))) {
    stop("Run the synthetic workflow from a PAGe repository checkout.",
      call. = FALSE
    )
  }
  for (path in dependency_paths) source(path, local = environment())

  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  inputs_dir <- file.path(output_dir, "inputs")
  dir.create(inputs_dir, showWarnings = FALSE)
  data_path <- file.path(inputs_dir, "synthetic_surveillance.rds")
  candidate_path <- file.path(inputs_dir, "candidate_kit.rds")
  incumbent_path <- file.path(inputs_dir, "incumbent_kit.rds")

  allD <- public_synthetic_data()
  pre_acceptance_training_seasons <- c("2023-24", "2024-25")
  candidate_kit <- public_synthetic_candidate_kit(
    pre_acceptance_training_seasons
  )
  incumbent_kit <- public_synthetic_incumbent_kit(
    pre_acceptance_training_seasons
  )
  if ("2025-26" %in% candidate_kit$m2_production$training_seasons ||
    "2025-26" %in% incumbent_kit$m2_production$training_seasons) {
    stop("Synthetic setup leaked 2025-26 into pre-acceptance training.",
      call. = FALSE
    )
  }
  saveRDS(allD, data_path)
  saveRDS(candidate_kit, candidate_path)
  saveRDS(incumbent_kit, incumbent_path)

  acceptance <- run_acceptance_replay(
    data_path = data_path,
    candidate_path = candidate_path,
    incumbent_path = incumbent_path,
    private_output_dir = file.path(output_dir, "acceptance-private"),
    audit_output_dir = file.path(output_dir, "acceptance-audit"),
    replay_fun = public_synthetic_replay,
    code_commit = code_commit,
    run_timestamp = run_timestamp,
    run_id = run_id
  )
  if (!isTRUE(acceptance$gate$pass)) {
    stop("Synthetic acceptance gate unexpectedly failed.", call. = FALSE)
  }
  promotion_bundle <- readRDS(acceptance$paths$private_bundle)
  promotion_manifest <- PAGe::read_result_manifest(
    acceptance$paths$manifest
  )

  synthetic_refresh <- function(allD, mode, previous_results,
                                prospective_holdout, promotion, m0_params,
                                m1_params, manual_labels, flag_args,
                                m2_spec_id, ...) {
    stopifnot(
      identical(mode, "refresh"),
      identical(prospective_holdout, "2025-26"),
      inherits(promotion, "page_verified_promotion_evidence"),
      isTRUE(promotion$report$pass),
      identical(previous_results$best_spec, candidate_kit$best_spec),
      identical(m2_spec_id, "synthetic-candidate-v1")
    )
    refreshed_kit <- candidate_kit
    final_seasons <- sort(unique(as.character(allD$season)))
    refreshed_kit$m2_production$training_seasons <- final_seasons
    structure(
      list(
        mode = "refresh",
        holdout = list(status = "released"),
        components = list(
          m0 = list(
            best_params = m0_params,
            manual_labels = manual_labels,
            flag_args = flag_args
          ),
          m1 = list(m1_params = m1_params)
        ),
        kit = refreshed_kit
      ),
      class = c("page_training_result", "list")
    )
  }

  refit <- page_run_post_promotion_refit(
    allD = allD,
    promotion_bundle = promotion_bundle,
    promotion_manifest = promotion_manifest,
    candidate_kit = candidate_kit,
    candidate_path = candidate_path,
    incumbent_path = incumbent_path,
    data_path = data_path,
    promotion_bundle_path = acceptance$paths$private_bundle,
    promotion_manifest_path = acceptance$paths$manifest,
    output_dir = file.path(output_dir, "refit-private"),
    manifest_dir = file.path(output_dir, "refit-audit"),
    train_fn = synthetic_refresh,
    code_commit = code_commit
  )
  final_training_seasons <- refit$manifest$provenance$training_seasons
  if (!"2025-26" %in% final_training_seasons) {
    stop("Synthetic fixed refresh did not release 2025-26.", call. = FALSE)
  }

  promotion <- promote_post_refit(
    data_path = data_path,
    acceptance_bundle_path = acceptance$paths$private_bundle,
    acceptance_manifest_path = acceptance$paths$manifest,
    candidate_path = candidate_path,
    incumbent_path = incumbent_path,
    refit_artifact_path = refit$artifact_path,
    refit_manifest_path = refit$manifest_path,
    registry_dir = file.path(output_dir, "registry"),
    audit_dir = file.path(output_dir, "deployment-audit"),
    deployment_id = deployment_id,
    code_commit = code_commit,
    run_timestamp = run_timestamp
  )
  loaded_kit <- PAGe::load_promoted_kit(
    promotion$promoted_kit_path,
    promotion$manifest_json_path
  )

  structure(
    list(
      acceptance = acceptance,
      refit = refit,
      promotion = promotion,
      loaded_kit = loaded_kit,
      accepted_spec_id = "synthetic-candidate-v1",
      pre_acceptance_training_seasons =
        candidate_kit$m2_production$training_seasons,
      incumbent_training_seasons =
        incumbent_kit$m2_production$training_seasons,
      final_training_seasons = final_training_seasons
    ),
    class = c("page_public_synthetic_release", "list")
  )
}

public_synthetic_release_cli <- function(args = commandArgs(trailingOnly = TRUE)) {
  if (any(args %in% c("--help", "-h"))) {
    writeLines(public_synthetic_release_usage())
    return(invisible(0L))
  }
  known <- args == "--smoke" | startsWith(args, "--output-dir=")
  if (any(!known)) {
    stop("Unknown argument: ", args[which(!known)[1L]], call. = FALSE)
  }
  if (sum(args == "--smoke") != 1L) {
    stop("Supply `--smoke` exactly once.", call. = FALSE)
  }
  output_args <- args[startsWith(args, "--output-dir=")]
  if (length(output_args) > 1L) {
    stop("Supply `--output-dir` at most once.", call. = FALSE)
  }
  temporary <- !length(output_args)
  output_dir <- if (temporary) {
    tempfile("page-public-synthetic-release-")
  } else {
    sub("^--output-dir=", "", output_args[[1L]])
  }
  if (!nzchar(output_dir)) {
    stop("`--output-dir` cannot be empty.", call. = FALSE)
  }
  if (temporary) {
    on.exit(unlink(output_dir, recursive = TRUE, force = TRUE), add = TRUE)
  }
  result <- run_public_synthetic_release(output_dir = output_dir)
  cat("Synthetic release smoke passed.\n")
  cat("  accepted spec: ", result$accepted_spec_id, "\n", sep = "")
  cat(
    "  final training seasons: ",
    paste(result$final_training_seasons, collapse = ", "), "\n",
    sep = ""
  )
  if (temporary) {
    cat("  verified promoted kit: loaded before temporary cleanup\n")
  } else {
    cat(
      "  verified promoted kit: ",
      result$promotion$promoted_kit_path, "\n",
      sep = ""
    )
  }
  invisible(0L)
}

if (sys.nframe() == 0L) {
  status <- tryCatch(
    public_synthetic_release_cli(),
    error = function(error) {
      message("Synthetic release smoke failed: ", conditionMessage(error))
      1L
    }
  )
  quit(save = "no", status = status)
}
