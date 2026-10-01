#!/usr/bin/env Rscript
# Bounded, post-holdout M2 offset/residual prototype for exactly two seasons.
# This script never tunes or refits M0/M1 and never applies online correction.

options(stringsAsFactors = FALSE)

root <- normalizePath(getwd(), mustWork = TRUE)
if (!file.exists(file.path(root, "PAGe", "DESCRIPTION"))) {
  stop("Run this bounded runner from the PAGe repository root.", call. = FALSE)
}

output <- file.path(
  root, "manuscript", "results", "publication-repair-20260908",
  "m2-offset-two-seasons"
)

target_seasons <- c("2014-15", "2016-17")
registry_path <- file.path(root, "results/audit/holdout_reconciliation_principal.csv")
replay_root <- file.path(
  root, "manuscript/results/publication-repair-20260908/replay/20260908T125939/private"
)
input_path <- "/home/yeli/FLU/flu_testing_data.csv"

required_files <- c(
  registry_path,
  input_path,
  file.path(root, "PAGe/R/m2_training.R"),
  file.path(root, "PAGe/R/m2_spec_grid.R"),
  file.path(root, "PAGe/R/pipeline_runtime_helpers.R"),
  file.path(root, "PAGe/R/m2_offset_prototype.R"),
  file.path(replay_root, "2014-15.rds"),
  file.path(replay_root, "2016-17.rds")
)
if (any(!file.exists(required_files))) {
  stop(
    "Missing required input(s): ",
    paste(required_files[!file.exists(required_files)], collapse = ", "),
    call. = FALSE
  )
}

source(file.path(root, "PAGe/R/pipeline_runtime_helpers.R"), local = TRUE)
source(file.path(root, "PAGe/R/m2_training.R"), local = TRUE)
source(file.path(root, "PAGe/R/m2_spec_grid.R"), local = TRUE)
source(file.path(root, "PAGe/R/m2_offset_prototype.R"), local = TRUE)

clip_probability <- function(p) pmin(1 - 1e-6, pmax(1e-6, as.numeric(p)))

sha256 <- function(path) digest::digest(file = path, algo = "sha256")

read_authorized_data <- function(path) {
  raw <- utils::read.csv(path, stringsAsFactors = FALSE)
  needed <- c("season", "week", "seasonstart", "pos_flua", "test_flu")
  missing <- setdiff(needed, names(raw))
  if (length(missing)) {
    stop("Authorized input is missing: ", paste(missing, collapse = ", "))
  }
  n_weeks <- 52L + as.integer(
    MMWRweek::MMWRweek(as.Date(paste0(raw$seasonstart, "-12-31")))$MMWRweek == 53L
  )
  out <- data.frame(
    season = as.character(raw$season),
    weekF = ((as.integer(raw$week) - 27L) %% n_weeks) + 1L,
    y = as.numeric(raw$pos_flua),
    N = as.numeric(raw$test_flu)
  )
  if (anyDuplicated(paste(out$season, out$weekF, sep = ":"))) {
    stop("Authorized input has duplicate season-week rows.")
  }
  if (any(!is.finite(out$y) | !is.finite(out$N) | out$N <= 0 | out$y < 0 | out$y > out$N)) {
    stop("Authorized input has invalid counts.")
  }
  out[order(out$season, out$weekF), , drop = FALSE]
}

registry <- utils::read.csv(registry_path, stringsAsFactors = FALSE)
if (!all(target_seasons %in% registry$season)) {
  stop("Registry is missing one or more requested target seasons.")
}

read_kit <- function(season) {
  row <- registry[registry$season == season, , drop = FALSE]
  if (nrow(row) != 1L || !identical(as.character(row$status), "complete") ||
    !isTRUE(row$exchangeable)) {
    stop("Registry row is not one complete exchangeable row for ", season, ".")
  }
  archive <- sub(
    "/mnt/nfsv4/Users/yeli/PAGe-artifacts",
    "/home/yeli/PAGe-bcc-artifacts",
    row$run_dir,
    fixed = TRUE
  )
  kit_path <- file.path(archive, "artifacts/candidate_pre_holdout.rds")
  if (!file.exists(kit_path)) stop("Frozen kit is missing: ", kit_path)
  replay_path <- file.path(replay_root, paste0(season, ".rds"))
  kit <- readRDS(kit_path)
  replay <- readRDS(replay_path)
  if (!identical(replay$season, season) || !identical(replay$status, "unseen_replay_complete")) {
    stop("Replay is not a completed unseen replay for ", season, ".")
  }
  list(
    season = season,
    row = row,
    kit = kit,
    kit_path = kit_path,
    replay = replay,
    replay_path = replay_path
  )
}

read_target_features <- function(bundle, authorized) {
  season <- bundle$season
  kit <- bundle$kit
  replay <- bundle$replay
  spec <- kit$m2_production$spec
  alpha_state <- as.numeric(spec$alpha_state)
  if (!is.finite(alpha_state) || alpha_state <= 0 || alpha_state >= 1) {
    stop("Invalid alpha_state in frozen kit for ", season)
  }
  obs <- authorized[authorized$season == season, , drop = FALSE]
  if (!nrow(obs)) stop("Authorized input has no target season ", season)
  obs <- obs[order(obs$weekF), , drop = FALSE]
  z_now <- logit_stable(obs$y / obs$N)
  z_ema <- as.numeric(stats::filter(
    alpha_state * z_now,
    filter = 1 - alpha_state,
    method = "recursive",
    init = z_now[1L]
  ))
  z_range <- kit$m2_production$feature_ranges$z_ema
  z_ema_clamped <- if (!is.null(z_range)) {
    pmin(z_range[2L], pmax(z_range[1L], z_ema))
  } else {
    z_ema
  }
  dz_ema <- c(0, diff(z_ema_clamped))
  names(z_ema_clamped) <- as.character(obs$weekF)
  names(dz_ema) <- as.character(obs$weekF)
  names(z_ema) <- as.character(obs$weekF)

  m2 <- as.data.frame(replay$stages$m2_predictions)
  if (!all(c("eval_week", "h", "target_weekF", "m1_p") %in% names(m2))) {
    stop("Replay M2 rows lack the required M1 prediction columns for ", season)
  }
  i_week <- as.integer(replay$ignition_week)
  anchor_week <- as.integer(kit$ref$anchorWeek)
  q <- m2[
    m2$eval_week - i_week >= 0 & m2$eval_week - i_week <= 12 &
      is.finite(m2$m1_p),
    c("eval_week", "h", "target_weekF", "m1_p"),
    drop = FALSE
  ]
  if (!nrow(q)) stop("No requested target origins in replay for ", season)
  q$t_since <- as.numeric(q$eval_week - i_week)
  q$lead <- factor(paste0("h", as.integer(q$h)), levels = c("h1", "h2"))
  q$logit_f_eff <- logit_stable(q$m1_p)
  q$z_ema <- unname(z_ema_clamped[as.character(q$eval_week)])
  q$z_ema_raw <- unname(z_ema[as.character(q$eval_week)])
  q$dz_ema <- unname(dz_ema[as.character(q$eval_week)])
  q$logN_now <- log(obs$N[match(q$eval_week, obs$weekF)])
  q$season <- season
  q$y_lead <- obs$y[match(q$target_weekF, obs$weekF)]
  q$N_lead <- obs$N[match(q$target_weekF, obs$weekF)]
  if (any(!is.finite(q$y_lead) | !is.finite(q$N_lead))) {
    stop("Target outcomes are unavailable for requested replay rows in ", season)
  }

  # Recover the M1 spread from the saved, per-origin forecast curves. The M1
  # p_hat must agree exactly with the replay's M1 value at this key.
  curves <- as.data.frame(replay$stages$m1_curves)
  q$newWeek <- q$target_weekF - i_week + anchor_week
  spread <- vapply(seq_len(nrow(q)), function(i) {
    z <- curves[
      curves$eval_week == q$eval_week[i] & curves$newWeek == q$newWeek[i] &
        curves$kind == "forecast",
      , drop = FALSE
    ]
    if (nrow(z) != 1L) stop("Expected one saved M1 curve row for ", season, " row ", i)
    if (abs(z$p_hat[1L] - q$m1_p[i]) > 1e-10) {
      stop("Saved M1 curve and replay M1 prediction disagree for ", season, " row ", i)
    }
    ifelse(is.finite(z$logit_spread[1L]), z$logit_spread[1L], 0)
  }, numeric(1))
  q$logit_spread <- spread
  q <- q[order(q$eval_week, q$h), , drop = FALSE]
  if (any(!is.finite(q$z_ema) | !is.finite(q$dz_ema) | !is.finite(q$logN_now))) {
    stop("Target prefix feature reconstruction failed for ", season)
  }
  q
}

score_variant <- function(data, column, season, h) {
  x <- data[
    data$season == season & data$h == h &
      data$t_since >= 0 & data$t_since <= 12,
    ,
    drop = FALSE
  ]
  p <- pmin(1 - 1e-12, pmax(1e-12, as.numeric(x[[column]])))
  trials <- sum(x$N_lead)
  data.frame(
    scope = "season",
    season = season,
    horizon = h,
    variant = column,
    rows = nrow(x),
    trials = trials,
    nll = sum(-x$y_lead * log(p) - (x$N_lead - x$y_lead) * log1p(-p)) / trials,
    mae = sum(x$N_lead * abs(p - x$y_lead / x$N_lead)) / trials,
    stringsAsFactors = FALSE
  )
}

run_two_season_prototype <- function() {
if (file.exists(output)) {
  stop("Refusing to overwrite existing output directory: ", output, call. = FALSE)
}
started <- Sys.time()
authorized <- read_authorized_data(input_path)
bundles <- lapply(target_seasons, read_kit)
names(bundles) <- target_seasons

# The two frozen kits intentionally provide their own ten-season M2 training
# sets. They are reused verbatim; the only prohibited rows are the outer
# target season for the corresponding fit.
training_summary <- list()
prediction_rows <- list()
models <- list()
warnings_rows <- list()

for (season in target_seasons) {
  bundle <- bundles[[season]]
  kit <- bundle$kit
  spec <- kit$m2_production$spec
  training_seasons <- as.character(kit$m2_production$training_seasons)
  if (length(training_seasons) != 10L || season %in% training_seasons) {
    stop("Frozen kit training-season contract failed for ", season)
  }
  if (any(training_seasons %in% target_seasons & training_seasons != season)) {
    # The existing kit contract is authoritative: the other requested target
    # can be one of its ten pre-existing training seasons. It is never the
    # current outer target, and no target rows are mixed into this fit.
    message("Using the frozen kit's existing cross-target training season for ", season)
  }

  d_train <- prep_stage2_joint(
    dat = kit$hist_data,
    best_mean_nll = spec,
    template_df = kit$template_df,
    leads = c(1L, 2L),
    alpha_state = as.numeric(spec$alpha_state),
    m1_preds = kit$m1_train_preds,
    feature_ranges = list(z_ema = kit$m2_production$feature_ranges$z_ema),
    verbose = FALSE
  )
  d_train <- d_train[d_train$post_ign %in% TRUE, , drop = FALSE]
  d_train$season <- as.character(d_train$season)
  if (!setequal(unique(d_train$season), training_seasons)) {
    stop("Prepared M2 training seasons differ from the frozen kit for ", season)
  }
  if (any(d_train$season == season)) stop("Outer target entered M2 training rows for ", season)
  if (any(!is.finite(d_train$y_lead) | !is.finite(d_train$N_lead))) {
    stop("Non-finite M2 training response for ", season)
  }

  offset_fit <- fit_m2_offset_correction(d_train, k_z = 2L, k_sp = 0L)
  target <- read_target_features(bundle, authorized)
  offset_pred <- predict_m2_offset_correction(offset_fit, target)

  # Optional identical-row comparator: the saved current M2 GAM, evaluated
  # with its raw link only. No cap, post-peak switch, season RE, or online
  # correction is applied.
  feature_ranges <- kit$m2_production$feature_ranges
  current_raw <- vapply(seq_len(nrow(target)), function(i) {
    logit_m1 <- target$logit_f_eff[i]
    if (!is.null(feature_ranges$logit_f_eff)) {
      logit_m1 <- pmin(feature_ranges$logit_f_eff[2L], pmax(feature_ranges$logit_f_eff[1L], logit_m1))
    }
    pr <- m2_predict_one(
      fit = kit$m2_production$fit,
      ew = target$eval_week[i],
      h = target$h[i],
      iWeek = bundle$replay$ignition_week,
      anchorWeek = kit$ref$anchorWeek,
      logit_f_eff = logit_m1,
      z_ema = target$z_ema[i],
      dz_ema = target$dz_ema[i],
      logit_spread = target$logit_spread[i],
      logN_now = target$logN_now[i],
      ex_terms = spec$exclude_newseason,
      include_season_re = FALSE,
      return_ci = FALSE,
      bias_logit = 0
    )
    if (is.null(pr)) stop("Current raw M2 prediction failed for ", season, " row ", i)
    pr$m2_p
  }, numeric(1))

  target$h <- as.integer(target$h)
  target$m1 <- target$m1_p
  target$offset <- offset_pred$p_hat
  target$current_raw_m2 <- current_raw
  target$offset_correction_logit <- offset_pred$correction_logit
  prediction_rows[[season]] <- target[, c(
    "season", "eval_week", "target_weekF", "h", "t_since", "y_lead", "N_lead",
    "m1", "offset", "current_raw_m2", "offset_correction_logit", "z_ema",
    "logit_spread"
  )]
  models[[season]] <- list(
    target_season = season,
    training_seasons = training_seasons,
    offset_fit = offset_fit,
    formula = paste(deparse(offset_fit$formula), collapse = " "),
    feature_definition = "z_ema is prefix-safe and clamped to the frozen kit range; logit_spread is retained diagnostically but not fitted",
    online_correction = FALSE,
    target_rows = nrow(target)
  )
  warnings_rows[[season]] <- data.frame(
    season = season,
    warning = if (length(offset_fit$warnings)) offset_fit$warnings else NA_character_,
    stringsAsFactors = FALSE
  )
  training_summary[[season]] <- data.frame(
    target_season = season,
    training_seasons = paste(training_seasons, collapse = ";"),
    training_rows = nrow(d_train),
    training_trials = sum(d_train$N_lead),
    target_rows_h1_0_12 = sum(target$h == 1L & target$t_since >= 0 & target$t_since <= 12),
    target_rows_h2_0_12 = sum(target$h == 2L & target$t_since >= 0 & target$t_since <= 12),
    formula = paste(deparse(offset_fit$formula), collapse = " "),
    total_edf = offset_fit$total_edf,
    smooth_edf = paste(names(offset_fit$edf), signif(offset_fit$edf, 8), sep = "=", collapse = ";"),
    converged = offset_fit$converged,
    fit_warnings = paste(offset_fit$warnings, collapse = " | "),
    elapsed_seconds = NA_real_,
    stringsAsFactors = FALSE
  )
  message(season, ": fitted offset correction on ", nrow(d_train), " rows")
}

predictions <- do.call(rbind, prediction_rows)
comparison_rows <- do.call(rbind, lapply(target_seasons, function(s) {
  do.call(rbind, lapply(c(1L, 2L), function(h) {
    do.call(rbind, lapply(c("m1", "offset", "current_raw_m2"), function(v) {
      score_variant(predictions, v, s, h)
    }))
  }))
}))
aggregate_rows <- do.call(rbind, lapply(split(
  comparison_rows[comparison_rows$scope == "season", ],
  comparison_rows[comparison_rows$scope == "season", c("horizon", "variant")],
  drop = TRUE
), function(x) {
  data.frame(
    scope = "equal_season_mean",
    season = "ALL",
    horizon = x$horizon[1L],
    variant = x$variant[1L],
    rows = sum(x$rows),
    trials = sum(x$trials),
    nll = mean(x$nll),
    mae = mean(x$mae),
    stringsAsFactors = FALSE
  )
}))
comparison <- rbind(comparison_rows, aggregate_rows)

if (any(!predictions$season %in% target_seasons)) {
  stop("Prediction output contains a non-requested target season.")
}

dir.create(output, recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(output, "models"), showWarnings = FALSE)
utils::write.csv(predictions, file.path(output, "predictions.csv"), row.names = FALSE)
utils::write.csv(comparison, file.path(output, "comparison.csv"), row.names = FALSE)
utils::write.csv(do.call(rbind, training_summary), file.path(output, "training_summary.csv"), row.names = FALSE)
warnings_df <- do.call(rbind, warnings_rows)
if (is.null(warnings_df) || !nrow(warnings_df)) {
  warnings_df <- data.frame(season = character(), warning = character())
}
utils::write.csv(warnings_df, file.path(output, "fit_warnings.csv"), row.names = FALSE)
for (s in target_seasons) saveRDS(models[[s]], file.path(output, "models", paste0(s, ".rds")))

metadata <- list(
  status = "complete_diagnostic_only",
  purpose = "Post-holdout bounded M2 offset/residual-correction prototype; not prospective confirmation",
  provider = "OpenAI",
  runtime = "native Codex in-session worker",
  permission_envelope = "Level 1; autonomous; may modify files within scope",
  target_seasons = target_seasons,
  training_seasons_by_target = lapply(models, function(x) x$training_seasons),
  target_outcomes_in_training = FALSE,
  target_outcome_check = "Each d_train was built from the frozen kit hist_data and m1_train_preds, then asserted to exclude its outer target season.",
  no_m1_tuning = TRUE,
  no_m1_refit = TRUE,
  no_online_correction_primary = TRUE,
  no_post_peak_switch_primary = TRUE,
  formula = lapply(models, function(x) x$formula),
  formula_contract = "cbind(y_lead, N_lead - y_lead) ~ -1 + lead + offset(logit_f_eff) + horizon-specific regularized s(z_ema, by=lead, bs='ts', k=2)",
  fitted_edf = lapply(models, function(x) list(total_edf = x$offset_fit$total_edf, smooth_edf = x$offset_fit$edf)),
  convergence = lapply(models, function(x) x$offset_fit$converged),
  fit_warnings = lapply(models, function(x) x$offset_fit$warnings),
  score_definition = "Origins with 0 <= t_since <= 12; N-weighted NLL and MAE within each target season; equal-season mean also reported.",
  rows = list(
    predictions = nrow(predictions),
    comparison = nrow(comparison),
    h1_per_target = as.list(table(predictions$season[predictions$h == 1L & predictions$t_since >= 0 & predictions$t_since <= 12])),
    h2_per_target = as.list(table(predictions$season[predictions$h == 2L & predictions$t_since >= 0 & predictions$t_since <= 12]))
  ),
  elapsed_seconds = as.numeric(difftime(Sys.time(), started, units = "secs")),
  input_sha256 = sha256(input_path),
  registry_sha256 = sha256(registry_path),
  source_sha256 = list(
    offset_helper = sha256(file.path(root, "PAGe/R/m2_offset_prototype.R")),
    runner = sha256(file.path(root, "scripts/publication_m2_offset_two_seasons.R"))
  ),
  kit_sha256 = lapply(bundles, function(x) sha256(x$kit_path)),
  replay_sha256 = lapply(bundles, function(x) sha256(x$replay_path)),
  session = capture.output(utils::sessionInfo())
)
jsonlite::write_json(
  metadata,
  file.path(output, "metadata.json"),
  auto_unbox = TRUE,
  pretty = TRUE,
  digits = 16,
  null = "null"
)
message("Wrote bounded M2 offset prototype to ", output)
}

if (sys.nframe() == 0L) run_two_season_prototype()
