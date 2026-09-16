# Governed M2 optional-term subset correction family (`offset_subset_v1`).
#
# This opt-in family is production-capable and is kept separate from the
# legacy M2 implementation, with explicit stage and runtime governance. The
# fitted model is a binomial GAM with the saved M1 logit as an offset. The
# M1 logit is the mandatory offset. Optional correction terms are
# controlled by per-term basis dimensions: zero omits a term, while positive
# values create horizon-specific factor-by smooths.

utils::globalVariables(".fit_weight")

m2_subset_component_names <- function() c("intercept", "k_z", "k_u", "k_d", "k_tau", "conf_scale")

m2_subset_term_names <- function() c("z", "u", "d", "tau")

.m2_subset_k <- function(value, name) {
  value <- as.numeric(value[1L])
  if (length(value) != 1L || !is.finite(value) || value != as.integer(value) ||
    value < 0 || (value > 0 && value < 3)) {
    stop("M2 subset `", name, "` must be 0 or an integer >= 3.", call. = FALSE)
  }
  as.integer(value)
}

#' Build the governed M2 offset-subset candidate grid
#'
#' Enumerates the optional-term subset family: an optional horizon intercept
#' crossed with per-term basis sizes for `z`, `u`, and `d`. A basis size of
#' zero turns the term off; positive values must be at least three. The
#' all-off row (`i0_kz0_ku0_kd0`) is always included and reproduces M1
#' exactly.
#'
#' @param k_values Default candidate basis sizes for every term.
#' @param k_z_values,k_u_values,k_d_values Per-term candidate basis sizes.
#' @param k_tau_values Candidate basis sizes for the origin-time peak-relative
#'   term. The stage-A default is the exact existing grid with this term off.
#' @param conf_scale Confidence-scaling values. Stage-A defaults to `"none"`.
#' @param alpha_state EMA decay used to build the `z`/`d` features; one value.
#' @param gamma Smoothness selection multiplier; one value >= 1.
#'
#' @return A data frame with stable `id`, component, and `enabled_count`
#'   columns, ordered from simplest to most complex.
#' @export
m2_subset_grid <- function(k_values = c(0L, 3L, 4L, 5L, 6L, 7L, 8L),
                           k_z_values = k_values, k_u_values = k_values,
                           k_d_values = k_values, k_tau_values = 0L,
                           conf_scale = "none", alpha_state = 0.2,
                           gamma = 1.4) {
  normalize_k_values <- function(values, name) {
    values <- unique(vapply(values, .m2_subset_k, integer(1), name = name))
    if (!length(values)) stop(name, " must contain at least one value.", call. = FALSE)
    values
  }
  k_z_values <- normalize_k_values(k_z_values, "k_z_values")
  k_u_values <- normalize_k_values(k_u_values, "k_u_values")
  k_d_values <- normalize_k_values(k_d_values, "k_d_values")
  k_tau_values <- normalize_k_values(k_tau_values, "k_tau_values")
  conf_scale <- match.arg(conf_scale, c("none", "peak_ci"))
  alpha_state <- as.numeric(alpha_state)
  if (any(!is.finite(alpha_state) | alpha_state <= 0 | alpha_state >= 1)) {
    stop("alpha_state grid values must be in (0, 1).", call. = FALSE)
  }
  gamma <- as.numeric(gamma)
  if (any(!is.finite(gamma) | gamma < 1)) {
    stop("gamma grid values must be >= 1.", call. = FALSE)
  }
  bits <- expand.grid(
    intercept = c(FALSE, TRUE),
    k_z = k_z_values,
    k_u = k_u_values,
    k_d = k_d_values,
    k_tau = k_tau_values,
    conf_scale = conf_scale,
    alpha_state = alpha_state,
    gamma = gamma,
    KEEP.OUT.ATTRS = FALSE,
    stringsAsFactors = FALSE
  )
  bits <- bits[
    order(
      as.integer(bits$intercept) + bits$k_z + bits$k_u + bits$k_d + bits$k_tau,
      sprintf(
        "i%d_kz%d_ku%d_kd%d", bits$intercept,
        bits$k_z, bits$k_u, bits$k_d
      )
    ), ,
    drop = FALSE
  ]
  bits$id <- sprintf(
    "i%d_kz%d_ku%d_kd%d",
    as.integer(bits$intercept), bits$k_z, bits$k_u, bits$k_d
  )
  non_default <- bits$k_tau > 0L | bits$conf_scale != "none"
  bits$id[non_default] <- paste0(
    bits$id[non_default], "_ktau", bits$k_tau[non_default],
    "_cs", bits$conf_scale[non_default]
  )
  bits$enabled_count <- as.integer(bits$intercept) +
    rowSums(bits[c("k_z", "k_u", "k_d", "k_tau")] > 0)
  bits <- bits[, c(
    "id", m2_subset_component_names(), "alpha_state", "gamma",
    "enabled_count"
  ), drop = FALSE]
  rownames(bits) <- NULL
  bits
}

# Stage B is deliberately small: only the two best stage-A base specifications
# are crossed with the predeclared tau/confidence axes. The all-off stage-A rows
# remain in the returned union, so M1 is always a candidate.
.m2_subset_stage_b_grid <- function(stage_a_grid, stage_a_summary) {
  stage_a_grid <- as.data.frame(stage_a_grid)
  if (!nrow(stage_a_grid)) {
    return(stage_a_grid)
  }
  summary <- as.data.frame(stage_a_summary %||% data.frame())
  ids <- character()
  if (nrow(summary) && all(c("spec_id", "bernoulli_nll") %in% names(summary))) {
    agg <- stats::aggregate(
      bernoulli_nll ~ spec_id, summary[is.finite(summary$bernoulli_nll), , drop = FALSE], mean
    )
    complexity <- stage_a_grid$enabled_count[match(agg$spec_id, stage_a_grid$id)]
    ids <- as.character(agg$spec_id[order(agg$bernoulli_nll, complexity, agg$spec_id)][seq_len(min(2L, nrow(agg)))])
  }
  if (!length(ids)) ids <- as.character(utils::head(stage_a_grid$id, 2L))
  base <- stage_a_grid[stage_a_grid$id %in% ids, , drop = FALSE]
  rows <- do.call(rbind, lapply(seq_len(nrow(base)), function(i) {
    do.call(rbind, lapply(c(0L, 3L, 4L, 5L), function(k_tau) {
      do.call(rbind, lapply(c("none", "peak_ci"), function(conf_scale) {
        row <- base[i, , drop = FALSE]
        row$k_tau <- k_tau
        row$conf_scale <- conf_scale
        spec <- m2_subset_spec(row)
        row$id <- spec$id
        row$enabled_count <- spec$enabled_count
        row
      }))
    }))
  }))
  out <- rbind(stage_a_grid, rows)
  out <- out[!duplicated(as.character(out$id)), , drop = FALSE]
  rownames(out) <- NULL
  out
}

m2_subset_spec <- function(spec = NULL, intercept = FALSE,
                           k_z = 0L, k_u = 0L, k_d = 0L, k_tau = 0L,
                           conf_scale = "none", z = NULL, u = NULL, d = NULL,
                           tau = NULL) {
  if (!is.null(spec)) {
    if (is.data.frame(spec)) {
      if (nrow(spec) != 1L) stop("spec data.frame must have one row.", call. = FALSE)
      spec <- as.list(spec[1L, , drop = FALSE])
      spec <- lapply(spec, function(x) if (length(x) == 1L) x else x[[1L]])
    }
    if (!is.list(spec)) stop("spec must be a list or one-row data.frame.", call. = FALSE)
    if (!is.null(spec$intercept)) intercept <- spec$intercept
    if (!is.null(spec$k_tau)) k_tau <- spec$k_tau
    if (!is.null(spec$conf_scale)) conf_scale <- as.character(spec$conf_scale)
    for (nm in m2_subset_term_names()) {
      k_name <- paste0("k_", nm)
      if (!is.null(spec[[k_name]])) {
        if (nm == "z") k_z <- spec[[k_name]]
        if (nm == "u") k_u <- spec[[k_name]]
        if (nm == "d") k_d <- spec[[k_name]]
      } else if (!is.null(spec[[nm]])) {
        legacy <- spec[[nm]]
        if (!is.logical(legacy) || length(legacy) != 1L || is.na(legacy)) {
          stop("Legacy M2 subset switch `", nm, "` must be logical.", call. = FALSE)
        }
        value <- if (legacy) 3L else 0L
        if (nm == "z") k_z <- value
        if (nm == "u") k_u <- value
        if (nm == "d") k_d <- value
      }
    }
  }
  for (legacy_name in c("z", "u", "d")) {
    legacy_value <- get(legacy_name)
    if (!is.null(legacy_value) &&
      (!is.logical(legacy_value) || length(legacy_value) != 1L || is.na(legacy_value))) {
      stop("Legacy M2 subset switch `", legacy_name, "` must be logical.", call. = FALSE)
    }
  }
  if (!is.null(z)) k_z <- if (z) 3L else 0L
  if (!is.null(u)) k_u <- if (u) 3L else 0L
  if (!is.null(d)) k_d <- if (d) 3L else 0L
  if (!is.null(tau)) k_tau <- if (tau) 3L else 0L
  if (!is.logical(intercept) || length(intercept) != 1L || is.na(intercept)) {
    stop("M2 subset intercept must be logical.", call. = FALSE)
  }
  k_z <- .m2_subset_k(k_z, "k_z")
  k_u <- .m2_subset_k(k_u, "k_u")
  k_d <- .m2_subset_k(k_d, "k_d")
  k_tau <- .m2_subset_k(k_tau, "k_tau")
  conf_scale <- match.arg(conf_scale, c("none", "peak_ci"))
  id <- sprintf("i%d_kz%d_ku%d_kd%d", as.integer(intercept), k_z, k_u, k_d)
  if (k_tau > 0L || conf_scale != "none") {
    id <- paste0(id, "_ktau", k_tau, "_cs", conf_scale)
  }
  out <- data.frame(
    id = id, intercept = intercept, k_z = k_z, k_u = k_u, k_d = k_d,
    k_tau = k_tau, conf_scale = conf_scale,
    stringsAsFactors = FALSE
  )
  out$enabled_count <- as.integer(intercept) + sum(c(k_z, k_u, k_d, k_tau) > 0)
  out
}

m2_subset_formula <- function(spec, k = NULL, bs = "ts") {
  spec <- m2_subset_spec(spec)
  if (!is.null(k)) {
    k <- .m2_subset_k(k, "k")
    for (nm in m2_subset_term_names()) {
      k_name <- paste0("k_", nm)
      if (spec[[k_name]] > 0) spec[[k_name]] <- k
    }
  }
  if (!is.character(bs) || length(bs) != 1L || !nzchar(bs)) {
    stop("bs must be one non-empty character value.", call. = FALSE)
  }
  rhs <- c("-1", "offset(m1_logit)")
  # Both confidence modes share this design: `lead` supplies the horizon
  # intercept columns and `s(nm, by=lead)` supplies the centered factor-by
  # smooths. The peak-CI path row-scales the assembled design (and the
  # prediction lpmatrix) by the confidence scale after fit = FALSE.
  if (isTRUE(spec$intercept)) rhs <- c(rhs, "lead")
  for (nm in m2_subset_term_names()) {
    term_k <- spec[[paste0("k_", nm)]]
    if (term_k > 0) {
      rhs <- c(rhs, sprintf("s(%s, by=lead, bs='%s', k=%d)", nm, bs, term_k))
    }
  }
  stats::as.formula(paste(
    "cbind(y_lead, N_lead - y_lead) ~",
    paste(rhs, collapse = " + ")
  ))
}

.m2_subset_scale_design_rows <- function(matrix, scale) {
  scale <- as.numeric(scale)
  if (length(scale) != nrow(matrix)) {
    stop(
      "M2 subset confidence scale must have one value per design row.",
      call. = FALSE
    )
  }
  sweep(matrix, 1L, scale, "*")
}

.m2_subset_fit_scaled_gam <- function(formula, data, family, method, gamma,
                                      weights, para_pen, scale) {
  data$.page_scaled_fit_weight <- as.numeric(weights)
  design <- mgcv::gam(
    formula = formula, data = data, family = family, method = method,
    gamma = gamma, select = TRUE, weights = .page_scaled_fit_weight,
    paraPen = para_pen,
    na.action = stats::na.fail, fit = FALSE
  )
  # The assembled design is row-scaled by the per-row confidence scale before
  # the final fit; the same construction is applied to prediction lpmatrices.
  design$X <- .m2_subset_scale_design_rows(design$X, scale)
  # mgcv does not carry `method`/`gamma` through `fit = FALSE`, so both must be
  # passed explicitly to the final `gam(G = ...)` call or mgcv silently falls
  # back to its GCV/UBRE default.
  mgcv::gam(G = design, method = method, gamma = gamma)
}

.m2_subset_check_fit_method <- function(fit, method) {
  actual <- as.character(fit$method)[1L]
  if (length(actual) != 1L || is.na(actual) ||
    !identical(toupper(actual), toupper(as.character(method)))) {
    stop(
      "M2 subset GAM silently used method '", actual,
      "' instead of the requested '", method, "'.",
      call. = FALSE
    )
  }
  invisible(actual)
}

m2_subset_enabled_features <- function(spec) {
  spec <- m2_subset_spec(spec)
  m2_subset_term_names()[vapply(
    m2_subset_term_names(),
    function(nm) spec[[paste0("k_", nm)]] > 0, logical(1)
  )]
}

m2_subset_validate_data <- function(data, spec, require_season = TRUE) {
  spec <- m2_subset_spec(spec)
  if (!is.data.frame(data)) stop("data must be a data.frame.", call. = FALSE)
  required <- c("y_lead", "N_lead", "lead", "m1_logit")
  required <- c(required, m2_subset_enabled_features(spec))
  if (isTRUE(require_season)) required <- c(required, "season")
  missing <- setdiff(required, names(data))
  if (length(missing)) stop("data is missing: ", paste(missing, collapse = ", "), call. = FALSE)
  if (any(!is.finite(data$y_lead) | !is.finite(data$N_lead) |
    data$N_lead <= 0 | data$y_lead < 0 | data$y_lead > data$N_lead)) {
    stop("Invalid binomial response counts in data.", call. = FALSE)
  }
  if (anyNA(data$lead) || any(!as.character(data$lead) %in% c("h1", "h2"))) {
    stop("lead must contain only h1 and h2.", call. = FALSE)
  }
  if (isTRUE(require_season) && anyNA(data$season)) {
    stop("season must be present and non-missing.", call. = FALSE)
  }
  numeric_columns <- c("y_lead", "N_lead", "m1_logit", m2_subset_enabled_features(spec))
  if (any(!vapply(data[numeric_columns], function(x) all(is.finite(x)), logical(1)))) {
    stop("M2 subset response or enabled predictors must be finite.", call. = FALSE)
  }
  invisible(data)
}

.m2_subset_confidence <- function(data, conf_scale, w_ref = NA_real_) {
  if (identical(conf_scale, "none")) {
    return(list(
      scale = rep(1, nrow(data)),
      missing = rep(FALSE, nrow(data)),
      zero = rep(FALSE, nrow(data))
    ))
  }
  width <- if ("peak_ci_width" %in% names(data)) {
    as.numeric(data$peak_ci_width)
  } else if (all(c("peak_weekF_lo", "peak_weekF_hi") %in% names(data))) {
    as.numeric(data$peak_weekF_hi) - as.numeric(data$peak_weekF_lo)
  } else {
    rep(NA_real_, nrow(data))
  }
  zero <- is.finite(width) & width <= 0
  missing <- !is.finite(width)
  scale <- rep(1, length(width))
  if (is.finite(w_ref) && w_ref > 0) {
    usable <- is.finite(width) & width > 0
    scale[usable] <- pmin(1, width[usable] / w_ref)
  }
  # An exactly zero-width CI carries no confidence: c = 0.  Missing CI falls
  # back to c = 1 and is flagged separately from a measured zero width.
  scale[zero] <- 0
  list(scale = scale, missing = missing, zero = zero)
}

m2_subset_feature_ranges <- function(data, spec) {
  spec <- m2_subset_spec(spec)
  setNames(lapply(m2_subset_enabled_features(spec), function(nm) {
    r <- range(data[[nm]], finite = TRUE)
    if (length(r) != 2L || any(!is.finite(r))) stop("Invalid range for ", nm, call. = FALSE)
    r
  }), m2_subset_enabled_features(spec))
}

m2_subset_is_converged <- function(fit) {
  is.list(fit) && isTRUE(fit$converged) &&
    (is.null(fit$outer.info) ||
      (is.list(fit$outer.info) &&
        identical(as.character(fit$outer.info$conv), "full convergence")))
}

m2_subset_apply_ranges <- function(data, ranges) {
  out <- as.data.frame(data)
  if (length(ranges)) {
    for (nm in names(ranges)) {
      if (!nm %in% names(out)) stop("Prediction data is missing ", nm, call. = FALSE)
      r <- ranges[[nm]]
      out[[nm]] <- pmin(r[2L], pmax(r[1L], as.numeric(out[[nm]])))
    }
  }
  out
}

m2_subset_fit <- function(data, spec, method = "REML", gamma = 1.4,
                          k = NULL, bs = "ts", intercept_sp = -1) {
  spec <- m2_subset_spec(spec)
  m2_subset_validate_data(data, spec)
  dat <- as.data.frame(data)
  dat$lead <- factor(as.character(dat$lead), levels = c("h1", "h2"))
  if (anyNA(dat$lead) || any(table(dat$lead) == 0L)) {
    stop("Both h1 and h2 are required for a shared-horizon fit.", call. = FALSE)
  }
  ranges <- m2_subset_feature_ranges(dat, spec)
  has_correction <- spec$enabled_count > 0L
  w_ref <- if (has_correction && spec$conf_scale == "peak_ci") {
    widths <- if ("peak_ci_width" %in% names(dat)) {
      as.numeric(dat$peak_ci_width)
    } else {
      as.numeric(dat$peak_weekF_hi) - as.numeric(dat$peak_weekF_lo)
    }
    stats::median(widths[is.finite(widths) & widths > 0], na.rm = TRUE)
  } else {
    NA_real_
  }
  conf <- if (has_correction) {
    .m2_subset_confidence(dat, spec$conf_scale, w_ref)
  } else {
    list(
      scale = rep(1, nrow(dat)), missing = rep(FALSE, nrow(dat)),
      zero = rep(FALSE, nrow(dat))
    )
  }
  if (has_correction && spec$conf_scale == "peak_ci" &&
    (!is.finite(w_ref) || w_ref <= 0)) {
    stop("peak_ci confidence scaling requires a positive training-row CI width median.", call. = FALSE)
  }
  # Estimate effect_h(x) * c by row-scaling the assembled factor-by design; the
  # scale is exactly one for the `none` mode, so both modes share one design.
  common <- list(
    spec = spec,
    formula = m2_subset_formula(spec, k = k, bs = bs),
    feature_ranges = ranges,
    training_rows = nrow(dat),
    training_seasons = sort(unique(as.character(dat$season))),
    method = method,
    gamma = gamma,
    basis_k = setNames(vapply(m2_subset_term_names(), function(nm) {
      spec[[paste0("k_", nm)]]
    }, integer(1)), m2_subset_term_names()),
    bs = bs,
    intercept_sp = intercept_sp,
    warnings = character(),
    converged = TRUE,
    total_edf = 0,
    edf = numeric(0),
    season_trial_totals = numeric(0),
    fit_weight_by_season = numeric(0),
    conf_scale = spec$conf_scale, w_ref = w_ref,
    confidence_basis = if (identical(spec$conf_scale, "peak_ci")) {
      "row_scaled_factor_by_design"
    } else {
      "centered_factor_by"
    },
    ci_missing_training = sum(conf$missing),
    ci_zero_training = sum(conf$zero)
  )
  if (identical(spec$enabled_count, 0L)) {
    common$type <- "all_off"
    common$fit <- NULL
    return(common)
  }

  season_totals <- tapply(dat$N_lead, as.character(dat$season), sum)
  if (any(!is.finite(season_totals) | season_totals <= 0)) {
    stop("Season trial totals must be finite and positive.", call. = FALSE)
  }
  dat$.fit_weight <- unname(mean(season_totals) / season_totals[as.character(dat$season)])
  para_pen <- if (isTRUE(spec$intercept)) {
    list(lead = list(diag(2L), sp = intercept_sp))
  } else {
    NULL
  }
  warnings <- character()
  fit <- withCallingHandlers(
    if (identical(spec$conf_scale, "peak_ci")) {
      .m2_subset_fit_scaled_gam(
        formula = common$formula, data = dat,
        family = stats::binomial(), method = method, gamma = gamma,
        weights = dat$.fit_weight, para_pen = para_pen, scale = conf$scale
      )
    } else {
      mgcv::gam(
        formula = common$formula,
        data = dat,
        family = stats::binomial(),
        method = method,
        gamma = gamma,
        select = TRUE,
        weights = .fit_weight,
        paraPen = para_pen,
        na.action = stats::na.fail
      )
    },
    warning = function(w) {
      warnings <<- unique(c(warnings, conditionMessage(w)))
      invokeRestart("muffleWarning")
    }
  )
  if (any(grepl("step\\s*(failed|failure)|failed.*step", warnings,
    ignore.case = TRUE
  ))) {
    stop("M2 subset GAM emitted a step-failure warning.", call. = FALSE)
  }
  if (!m2_subset_is_converged(fit)) {
    diagnostic <- if (is.list(fit$outer.info)) fit$outer.info$conv else NA_character_
    stop(
      "M2 subset GAM did not reach full convergence (outer.info$conv=",
      as.character(diagnostic)[1L], ").",
      call. = FALSE
    )
  }
  # The governed fitting method (and gamma) must be the one actually used; fail
  # loudly rather than recording a method mgcv silently replaced.
  .m2_subset_check_fit_method(fit, method)
  # mgcv records the factor used by a factor-by smooth in `pterms`, even when
  # it has no parametric coefficient.  `nsdf` and the coefficient names are
  # therefore the identifiability check, rather than term labels alone.
  parametric_names <- names(stats::coef(fit))[seq_len(fit$nsdf)]
  has_parametric_lead <- any(grepl("^lead", parametric_names))
  if (!isTRUE(spec$intercept) && (fit$nsdf != 0L || has_parametric_lead)) {
    stop("Disabled horizon intercept entered the model.", call. = FALSE)
  }
  if (isTRUE(spec$intercept) && !has_parametric_lead) {
    stop("Enabled horizon intercept is absent from the model.", call. = FALSE)
  }
  smry <- summary(fit)
  edf <- if (!is.null(smry$s.table) && nrow(smry$s.table)) {
    stats::setNames(as.numeric(smry$s.table[, "edf"]), rownames(smry$s.table))
  } else {
    numeric(0)
  }
  common$type <- "gam"
  common$fit <- fit
  common$warnings <- warnings
  common$converged <- isTRUE(fit$converged)
  common$total_edf <- sum(fit$edf)
  common$edf <- edf
  common$season_trial_totals <- season_totals
  common$fit_weight_by_season <- mean(season_totals) / season_totals
  common
}

m2_subset_predict <- function(fit, newdata) {
  if (!is.list(fit) || is.null(fit$type) || !is.data.frame(newdata)) {
    stop("fit must be an M2 subset fit and newdata a data.frame.", call. = FALSE)
  }
  nd <- as.data.frame(newdata)
  if (!all(c("m1_logit", "lead") %in% names(nd))) {
    stop("Prediction data must contain m1_logit and lead.", call. = FALSE)
  }
  if (any(!is.finite(nd$m1_logit))) stop("Prediction offsets must be finite.", call. = FALSE)
  m1_probability <- if ("m1_p" %in% names(nd)) {
    as.numeric(nd$m1_p)
  } else {
    stats::plogis(nd$m1_logit)
  }
  if (any(!is.finite(m1_probability) | m1_probability < 0 | m1_probability > 1)) {
    stop("Prediction m1_p must be a finite probability.", call. = FALSE)
  }
  nd$lead <- factor(as.character(nd$lead), levels = c("h1", "h2"))
  if (anyNA(nd$lead)) stop("Prediction data contains an unknown horizon.", call. = FALSE)
  nd <- m2_subset_apply_ranges(nd, fit$feature_ranges)
  conf <- .m2_subset_confidence(nd, fit$conf_scale, fit$w_ref)
  if (identical(fit$type, "all_off")) {
    # Preserve the supplied saved M1 probability bit-for-bit.  The link is
    # retained for the correction field, but qlogis/plogis round-tripping is
    # not allowed to perturb the all-off identity contract.
    eta <- stats::qlogis(m1_probability)
    correction <- rep(0, nrow(nd))
  } else {
    required <- m2_subset_enabled_features(fit$spec)
    if (length(setdiff(required, names(nd)))) {
      stop("Prediction data is missing enabled predictors.", call. = FALSE)
    }
    if (any(!vapply(nd[required], function(x) all(is.finite(x)), logical(1)))) {
      stop("Prediction enabled predictors must be finite.", call. = FALSE)
    }
    # The confidence scale row-scales the factor-by prediction design; the
    # unscaled M1 offset is added afterwards.
    if (identical(fit$conf_scale, "peak_ci")) {
      lp <- stats::predict(fit$fit, newdata = nd, type = "lpmatrix")
      lp <- .m2_subset_scale_design_rows(lp, conf$scale)
      eta <- as.numeric(lp %*% stats::coef(fit$fit)) + nd$m1_logit
    } else {
      eta <- as.numeric(stats::predict(fit$fit, newdata = nd, type = "link"))
    }
    correction <- eta - nd$m1_logit
  }
  if (any(!is.finite(eta))) stop("M2 subset prediction is non-finite.", call. = FALSE)
  data.frame(
    m1_p = m1_probability,
    p_hat = if (identical(fit$type, "all_off")) m1_probability else stats::plogis(eta),
    eta = eta,
    correction_logit = correction,
    confidence_scale = if (identical(fit$type, "all_off")) rep(1, nrow(nd)) else conf$scale,
    confidence_scale_missing = if (identical(fit$type, "all_off")) rep(FALSE, nrow(nd)) else conf$missing,
    stringsAsFactors = FALSE
  )
}

m2_subset_observed_features <- function(data, declaration_week, alpha_state) {
  required <- c("season", "weekF", "y", "N")
  if (!is.data.frame(data) || length(setdiff(required, names(data)))) {
    stop("Observed data must contain season, weekF, y, and N.", call. = FALSE)
  }
  alpha_state <- as.numeric(alpha_state[1L])
  declaration_week <- as.numeric(declaration_week[1L])
  if (!is.finite(alpha_state) || alpha_state <= 0 || alpha_state >= 1) {
    stop("alpha_state must be in (0, 1).", call. = FALSE)
  }
  if (!is.finite(declaration_week)) stop("declaration_week must be finite.", call. = FALSE)
  d <- data[order(as.character(data$season), as.integer(data$weekF)), , drop = FALSE]
  if (anyDuplicated(paste(d$season, d$weekF, sep = ":"))) {
    stop("Observed data contains duplicate season-week rows.", call. = FALSE)
  }
  if (any(!is.finite(d$y) | !is.finite(d$N) | d$N <= 0 | d$y < 0 | d$y > d$N)) {
    stop("Observed data contains invalid counts.", call. = FALSE)
  }
  p <- pmin(1 - 1e-6, pmax(1e-6, d$y / d$N))
  logit_now <- stats::qlogis(p)
  z <- as.numeric(stats::filter(alpha_state * logit_now,
    filter = 1 - alpha_state, method = "recursive", init = logit_now[1L]
  ))
  previous_week <- c(NA_integer_, utils::head(as.integer(d$weekF), -1L))
  d_out <- data.frame(
    season = as.character(d$season), weekF = as.integer(d$weekF),
    y = as.numeric(d$y), N = as.numeric(d$N),
    z = z, u = as.numeric(d$weekF) - declaration_week,
    d = ifelse(as.integer(d$weekF) - previous_week == 1L,
      z - c(NA_real_, utils::head(z, -1L)), NA_real_
    ),
    stringsAsFactors = FALSE
  )
  d_out$z_raw <- d_out$z
  d_out$d_raw <- d_out$d
  d_out
}

m2_subset_runtime_feature_row <- function(prefix, origin_week, declaration,
                                          m1_p, h, alpha_state,
                                          observed_features = NULL, tau = NA_real_,
                                          peak_ci_width = NA_real_,
                                          conf_scale = "none", w_ref = NA_real_) {
  if (!is.list(declaration) || !is.finite(declaration$week)) {
    stop("Runtime subset declaration must contain a finite week.", call. = FALSE)
  }
  origin_week <- as.integer(origin_week[1L])
  h <- as.integer(h[1L])
  if (!is.finite(origin_week) || !h %in% c(1L, 2L)) {
    stop("Runtime subset origin and horizon are invalid.", call. = FALSE)
  }
  fs <- observed_features
  if (is.null(fs)) {
    fs <- m2_subset_observed_features(prefix, declaration$week, alpha_state)
  }
  row <- fs[fs$weekF == origin_week, c("z", "u", "d"), drop = FALSE]
  if (nrow(row) != 1L || any(!is.finite(unlist(row)))) {
    stop("Runtime subset features are unavailable at the origin.", call. = FALSE)
  }
  data.frame(
    m1_logit = m2_subset_logit(m1_p), m1_p = as.numeric(m1_p),
    lead = paste0("h", h), z = row$z, u = row$u, d = row$d,
    tau = as.numeric(tau), peak_ci_width = as.numeric(peak_ci_width),
    confidence_scale = .m2_subset_confidence(
      data.frame(peak_ci_width = peak_ci_width), conf_scale, w_ref
    )$scale,
    confidence_scale_missing = .m2_subset_confidence(
      data.frame(peak_ci_width = peak_ci_width), conf_scale, w_ref
    )$missing,
    stringsAsFactors = FALSE
  )
}

m2_subset_prefix_declaration <- function(data, params, origin_week,
                                         detector = run_ignition_weekly,
                                         start_week = 5L,
                                         timing_mode = c("legacy", "fractional")) {
  timing_mode <- match.arg(timing_mode)
  required <- c("season", "weekF", "y", "N")
  if (!is.data.frame(data) || length(setdiff(required, names(data)))) {
    stop("Prefix data must contain season, weekF, y, and N.", call. = FALSE)
  }
  origin_week <- as.numeric(origin_week[1L])
  if (!is.finite(origin_week)) stop("origin_week must be finite.", call. = FALSE)
  prefix <- data[is.finite(data$weekF) & data$weekF <= origin_week, , drop = FALSE]
  if (!nrow(prefix)) stop("No observations are available through origin_week.", call. = FALSE)
  detector_args <- list(prefix, params = params, start_week = start_week)
  detector_formals <- tryCatch(names(formals(detector)), error = function(e) character())
  if ("timing_mode" %in% detector_formals || "..." %in% detector_formals) {
    detector_args$timing_mode <- timing_mode
  }
  out <- do.call(detector, detector_args)
  locked_primary <- if (timing_mode == "fractional") out$ign_week_lockedF else out$ign_week_locked
  locked_alternate <- if (timing_mode == "fractional") out$iWeek_hat_lockedF else out$iWeek_hat_locked
  locked_fallback <- if (length(locked_primary) && is.finite(locked_primary[1L])) {
    locked_primary[1L]
  } else {
    locked_alternate[1L] %||% NA_real_
  }
  # `ign_week_locked` is the first positive gate and can remain NA when a
  # prefix has no detection. Runtime's historical output field still carries
  # w_max in that case, so use it here while retaining the failure flag.
  if (timing_mode == "fractional") {
    declaration <- as.numeric(locked_fallback)
  } else {
    declaration <- as.integer(locked_fallback)
  }
  if (length(declaration) != 1L || !is.finite(declaration)) declaration <- NA_real_
  if (!is.finite(declaration)) declaration <- NA_real_
  detector_df <- if (is.data.frame(out$df)) out$df else data.frame()
  positive_rows <- if ("ignite_ok_now" %in% names(detector_df)) {
    sum(as.logical(detector_df$ignite_ok_now), na.rm = TRUE)
  } else {
    NA_integer_
  }
  list(
    week = declaration,
    origin_week = as.integer(origin_week),
    source = paste0(
      "corresponding outer kit frozen M0; run_ignition_weekly prefix through origin ",
      as.integer(origin_week), "; first locked ignite_ok_now (",
      timing_mode, " timing)"
    ),
    rows_evaluated = nrow(prefix),
    positive_rows = positive_rows,
    detection_failed = isTRUE(out$detection_failed) || is.na(declaration)
  )
}

m2_subset_u_by_origin <- function(origin_week, declarations) {
  vapply(as.character(origin_week), function(w) {
    declaration <- declarations[[w]]
    if (is.null(declaration) || !is.finite(declaration$week)) {
      NA_real_
    } else {
      as.numeric(w) - as.numeric(declaration$week)
    }
  }, numeric(1))
}

# ---------------------------------------------------------------------------
# Governed opt-in family: offset_subset_v1
# ---------------------------------------------------------------------------

m2_subset_family <- function() "offset_subset_v1"

m2_subset_or <- function(x, y) if (is.null(x)) y else x

m2_subset_is_family <- function(x) {
  is.list(x) && identical(x$family, m2_subset_family())
}

#' Build a governed M2 offset-subset configuration
#'
#' @param h1,h2 Selected per-horizon specifications (one-row data frames,
#'   lists, or NULL for the all-off default).
#' @param alpha_state EMA decay used to build the `z`/`d` features, in (0, 1).
#' @param bs Basis type; only `"ts"` is supported.
#' @param method GAM fitting method.
#' @param gamma Smoothness selection multiplier (>= 1).
#' @param intercept_sp Horizon-intercept penalty; -1 estimates it by REML.
#'
#' @return A validated configuration list tagged with the
#'   `offset_subset_v1` family.
#' @export
m2_subset_config <- function(h1 = NULL, h2 = NULL, alpha_state = 0.2,
                             bs = "ts", method = "REML",
                             gamma = 1.4, intercept_sp = -1) {
  if (is.null(h1)) h1 <- m2_subset_spec()
  if (is.null(h2)) h2 <- m2_subset_spec()
  h1 <- m2_subset_spec(h1)
  h2 <- m2_subset_spec(h2)
  alpha_state <- as.numeric(alpha_state[1L])
  if (!is.finite(alpha_state) || alpha_state <= 0 || alpha_state >= 1) {
    stop("alpha_state must be in (0, 1).", call. = FALSE)
  }
  if (!is.character(bs) || length(bs) != 1L || is.na(bs) || !identical(bs, "ts")) {
    stop("M2 subset config supports only `bs = \"ts\"`.", call. = FALSE)
  }
  list(
    family = m2_subset_family(), h1 = h1, h2 = h2,
    alpha_state = alpha_state, bs = bs,
    method = method, gamma = as.numeric(gamma[1L]),
    intercept_sp = as.numeric(intercept_sp[1L])
  )
}

m2_subset_validate_config <- function(config) {
  if (!m2_subset_is_family(config)) {
    stop("M2 subset config must declare family `", m2_subset_family(), "`.",
      call. = FALSE
    )
  }
  if (is.null(config$h1) || is.null(config$h2)) {
    stop("M2 subset config must contain selected h1 and h2 specifications.",
      call. = FALSE
    )
  }
  config <- m2_subset_config(
    h1 = config$h1, h2 = config$h2,
    alpha_state = m2_subset_or(config$alpha_state, 0.2),
    bs = m2_subset_or(config$bs, "ts"),
    method = m2_subset_or(config$method, "REML"), gamma = m2_subset_or(config$gamma, 1.4),
    intercept_sp = m2_subset_or(config$intercept_sp, -1)
  )
  if (!is.finite(config$gamma) || config$gamma < 1) {
    stop("M2 subset config has invalid gamma.", call. = FALSE)
  }
  config
}

m2_subset_grid_config <- function(row, alpha_state = 0.2, ...) {
  row <- as.data.frame(row)
  if (nrow(row) != 1L) stop("M2 subset grid row must have one row.", call. = FALSE)
  m2_subset_config(h1 = row, h2 = row, alpha_state = alpha_state, ...)
}

m2_subset_logit <- function(p, eps = 1e-6) {
  stats::qlogis(pmin(1 - eps, pmax(eps, as.numeric(p))))
}

# Reuse season-wise derivative fits from M1, then refit the same LOSO
# reference/hyperparameter machinery once per excluded set. Recompute the
# anchor from the retained seasons, so even the alignment bounds exclude the
# complete set.
.m1_exclusion_key <- function(excluded_seasons) {
  paste(sort(unique(as.character(excluded_seasons))), collapse = "\r")
}

.m1_heldout_references <- function(m1, seasons, timing_mode = "legacy",
                                   excluded_sets = NULL, params = NULL) {
  aligned <- m1$aligned_train
  required <- c("season", "weekF", "iWeek")
  if (!is.data.frame(aligned) || !all(required %in% names(aligned))) {
    stop("Held-out M1 predictions require aligned_train with season, weekF and iWeek.",
      call. = FALSE
    )
  }
  # The outer M1 configuration may itself have been selected using a season
  # in this inner fold. Exclusion-set caches therefore require explicitly
  # supplied controls; absent that, fixed non-fitted defaults are used.
  p <- params %||%
    (if (is.null(excluded_sets)) {
      m1$m1_params %||% .default_m1_params()
    } else {
      .default_m1_params()
    })
  seasons <- sort(unique(as.character(seasons)))
  legacy_names <- is.null(excluded_sets)
  if (legacy_names) excluded_sets <- lapply(seasons, c)
  excluded_sets <- lapply(excluded_sets, function(x) {
    x <- sort(unique(as.character(x)))
    if (!length(x) || any(!x %in% seasons)) {
      stop("M1 reference exclusion sets must be non-empty subsets of seasons.",
        call. = FALSE
      )
    }
    x
  })
  keys <- vapply(excluded_sets, .m1_exclusion_key, character(1))
  if (anyDuplicated(keys)) {
    keep <- !duplicated(keys)
    excluded_sets <- excluded_sets[keep]
    keys <- keys[keep]
  }
  references <- lapply(seq_along(excluded_sets), function(i) {
    excluded <- excluded_sets[[i]]
    train <- aligned[!as.character(aligned$season) %in% excluded, , drop = FALSE]
    retained <- unique(as.character(train$season))
    if (!length(retained)) {
      stop("Held-out M1 reference requires at least one retained season for ",
        keys[[i]],
        call. = FALSE
      )
    }
    ignition <- unique(train[, c("season", "iWeek"), drop = FALSE])
    if (anyDuplicated(as.character(ignition$season)) || any(!is.finite(ignition$iWeek))) {
      stop("Held-out M1 reference requires one finite ignition per training season.", call. = FALSE)
    }
    anchor <- stats::median(ignition$iWeek)
    if (timing_mode == "legacy") anchor <- as.integer(anchor)
    train$nW_true <- .season_calendar_weeks(train)
    train$newWeek <- .page_shift_week(train$weekF, train$iWeek, anchor)
    .dom <- .page_alignment_domain(train$newWeek, .page_template_weeks())
    train$alignment_in_domain <- .dom$in_domain
    train$alignment_out_of_domain <- .dom$out_of_domain
    attr(train, "anchorWeek") <- anchor
    attr(train, "ignD") <- ignition
    available_k <- length(unique(train$newWeek[
      is.finite(train$newWeek) & train$alignment_in_domain
    ]))
    k_ref <- min(as.integer(p$k_ref %||% 25L), available_k)
    if (k_ref < 1L) {
      stop("Held-out M1 reference has no in-domain support.", call. = FALSE)
    }
    ref <- estimateRef(train,
      exSeason = character(0),
      k = k_ref, n_weeks = .page_template_weeks(),
      method = p$ref_method %||% "fs", timing_mode = timing_mode
    )
    if (any(as.character(ref$dat$season) %in% excluded)) {
      stop("Held-out M1 reference retained an excluded season for ", keys[[i]], ".",
        call. = FALSE
      )
    }
    reference_provenance <- list(
      cache_key = keys[[i]],
      excluded_seasons = excluded,
      training_seasons = retained,
      reference_training_seasons = sort(unique(as.character(ref$dat$season))),
      hyperparameter_source = if (is.null(params)) {
        "fixed governed M1 defaults"
      } else {
        "explicit outer-fold M1 controls"
      },
      anchor_source = "median ignition labels from retained seasons",
      fitted_feature_source = "season-local aligned rows filtered before estimateRef",
      m0_feature_source = "none; nested callers supply label-truth ignition"
    )
    list(
      ref = ref, hyper = learn_alignment_hyperparams(ref$dat, ref$g_ref_fun),
      training_seasons = retained,
      excluded_seasons = excluded,
      excluded_season = if (length(excluded) == 1L) excluded[[1L]] else NULL,
      provenance = reference_provenance
    )
  })
  stats::setNames(references, if (legacy_names) seasons else keys)
}

m2_subset_make_rows <- function(data, m0, m1, m1_train_preds = NULL,
                                seasons = unique(as.character(data$season)),
                                detector = run_ignition_weekly,
                                alpha_state = 0.2,
                                timing_mode = c("legacy", "fractional"),
                                parallel = FALSE,
                                timing_truth = NULL) {
  timing_mode <- match.arg(timing_mode)
  required <- c("season", "weekF", "y", "N")
  missing <- setdiff(required, names(data))
  if (length(missing)) stop("Subset training data is missing: ", paste(missing, collapse = ", "), call. = FALSE)
  if (is.null(m1_train_preds)) {
    if (!exists("m1_walkforward_multi", mode = "function")) {
      stop("M2 subset training requires an M1 walk-forward prediction adapter.", call. = FALSE)
    }
    p <- m2_subset_or(m1$m1_params, .default_m1_params())
    references <- .m1_heldout_references(m1, seasons, timing_mode)
    m1_train_preds <- m1_walkforward_multi(
      allD = data, ref = m1$ref, hyper = m1$hyper,
      season_references = references,
      params = m0$best_params, seasons = seasons,
      temperature = m2_subset_or(p$temperature, 0.25),
      rise_weight = m2_subset_or(p$rise_weight, 1),
      trough_weight = m2_subset_or(p$trough_weight, 0.1),
      peak_decay = m2_subset_or(p$peak_decay, 0.3),
      slope_weight = m2_subset_or(p$slope_weight, 8),
      slope_window = m2_subset_or(p$slope_window, 6L),
      dynamic_temp = isTRUE(p$dynamic_temp),
      dynamic_temp_pivot = m2_subset_or(p$dynamic_temp_pivot, 10L),
      spread_method = m2_subset_or(p$spread_method, "between"),
      parallel = parallel, verbose = FALSE,
      timing_mode = timing_mode
    )
  }
  timing_truth_by_season <- if (is.null(timing_truth)) {
    data.frame()
  } else if (is.numeric(timing_truth) && !is.null(names(timing_truth))) {
    data.frame(
      season = names(timing_truth),
      ignition_target_weekF = as.numeric(timing_truth),
      stringsAsFactors = FALSE
    )
  } else if (is.data.frame(timing_truth) &&
    all(c("season", "ignition_target_weekF") %in% names(timing_truth))) {
    as.data.frame(timing_truth)
  } else {
    stop("timing_truth must be a named numeric vector or a data frame with ",
      "season and ignition_target_weekF.",
      call. = FALSE
    )
  }
  m1_train_preds <- as.data.frame(m1_train_preds)
  original_prediction_names <- names(m1_train_preds)
  needed_preds <- c("season", "eval_weekF", "target_weekF", "h", "m1_p_hat")
  missing <- setdiff(needed_preds, names(m1_train_preds))
  if (length(missing)) stop("M1 predictions are missing: ", paste(missing, collapse = ", "), call. = FALSE)
  pred_season <- as.character(m1_train_preds$season)
  nW_by_season <- stats::setNames(
    vapply(as.character(seasons), function(s) {
      .page_nw_true(data[as.character(data$season) == s, , drop = FALSE])[1L]
    }, numeric(1)), as.character(seasons)
  )
  if (!"forecast_available" %in% names(m1_train_preds)) {
    m1_train_preds$forecast_available <- is.finite(m1_train_preds$m1_p_hat)
  }
  m1_train_preds$forecast_available <- as.logical(m1_train_preds$forecast_available)
  m1_train_preds$forecast_available[is.na(m1_train_preds$forecast_available)] <- FALSE
  if (!"unavailable_reason" %in% names(m1_train_preds)) {
    m1_train_preds$unavailable_reason <- NA_character_
  }
  m1_train_preds$unavailable_reason <- as.character(m1_train_preds$unavailable_reason)
  peak_col <- intersect(c("peak_weekF", "m1_peak_weekF", "peak_weekF_origin"), names(m1_train_preds))[1L]
  if (!is.na(peak_col) && length(peak_col)) {
    m1_train_preds$peak_weekF_origin <- as.numeric(m1_train_preds[[peak_col]])
  } else {
    m1_train_preds$peak_weekF_origin <- NA_real_
  }
  lo_col <- intersect(c("peak_weekF_lo", "m1_peak_weekF_lo"), names(m1_train_preds))[1L]
  hi_col <- intersect(c("peak_weekF_hi", "m1_peak_weekF_hi"), names(m1_train_preds))[1L]
  m1_train_preds$peak_ci_width <- if (!is.na(lo_col) && !is.na(hi_col) &&
    length(lo_col) && length(hi_col)) {
    as.numeric(m1_train_preds[[hi_col]]) - as.numeric(m1_train_preds[[lo_col]])
  } else {
    NA_real_
  }
  missing_reason <- !m1_train_preds$forecast_available &
    (is.na(m1_train_preds$unavailable_reason) | !nzchar(m1_train_preds$unavailable_reason))
  m1_train_preds$unavailable_reason[missing_reason] <- "alignment_prediction_missing"
  if ("target_newWeek" %in% names(m1_train_preds)) {
    for (i in seq_len(nrow(m1_train_preds))) {
      s <- pred_season[i]
      contract <- .page_forecast_availability(
        m1_train_preds$target_weekF[i], m1_train_preds$target_newWeek[i],
        nW_true = nW_by_season[[s]] %||% 52L
      )
      if (!isTRUE(contract$forecast_available[1L])) {
        m1_train_preds$forecast_available[i] <- FALSE
        if (is.na(m1_train_preds$unavailable_reason[i]) ||
          !nzchar(m1_train_preds$unavailable_reason[i]) ||
          identical(m1_train_preds$unavailable_reason[i], "alignment_prediction_missing")) {
          m1_train_preds$unavailable_reason[i] <- contract$unavailable_reason[1L]
        }
      }
    }
  }
  obs <- data[, required, drop = FALSE]
  obs$season <- as.character(obs$season)
  # Seasons are independent. Reuse the parent plan and collect in input order;
  # each worker keeps its origin walk sequential and never installs a plan.
  prepare_season <- function(s) {
    rows <- list()
    declarations <- list()
    os <- obs[obs$season == s, , drop = FALSE]
    mp <- m1_train_preds[as.character(m1_train_preds$season) == s, , drop = FALSE]
    if (!nrow(os) || !nrow(mp)) {
      return(list(rows = rows, declarations = declarations))
    }
    origins <- sort(unique(as.integer(mp$eval_weekF)))
    label_week <- if (nrow(timing_truth_by_season) &&
      s %in% as.character(timing_truth_by_season$season)) {
      as.numeric(timing_truth_by_season$ignition_target_weekF[
        match(s, as.character(timing_truth_by_season$season))
      ])
    } else {
      NULL
    }
    declarations[[s]] <- lapply(origins, function(origin) {
      if (length(label_week) == 1L && is.finite(label_week)) {
        list(
          week = as.numeric(label_week),
          origin_week = as.integer(origin),
          source = "manual M0 ignition label truth; no fitted M0 feature",
          rows_evaluated = sum(os$weekF <= origin),
          positive_rows = NA_integer_,
          detection_failed = FALSE
        )
      } else {
        m2_subset_prefix_declaration(os, m0$best_params,
          origin_week = origin,
          detector = detector,
          timing_mode = timing_mode
        )
      }
    })
    names(declarations[[s]]) <- as.character(origins)
    observed_by_origin <- lapply(origins, function(origin) {
      dec <- declarations[[s]][[as.character(origin)]]
      if (is.null(dec) || !is.finite(dec$week)) {
        return(NULL)
      }
      prefix <- os[os$weekF <= origin, , drop = FALSE]
      tryCatch(
        m2_subset_observed_features(prefix, dec$week, alpha_state),
        error = function(e) NULL
      )
    })
    names(observed_by_origin) <- as.character(origins)
    for (i in seq_len(nrow(mp))) {
      ew <- as.integer(mp$eval_weekF[i])
      target <- as.integer(mp$target_weekF[i])
      h <- as.integer(mp$h[i])
      if (!h %in% c(1L, 2L) || !is.finite(ew) || !is.finite(target) ||
        target != ew + h) {
        next
      }
      ti <- match(target, os$weekF)
      if (is.na(ti)) next
      dec <- declarations[[s]][[as.character(ew)]]
      observed_features <- observed_by_origin[[as.character(ew)]]
      y <- os$y[match(target, os$weekF)]
      n <- os$N[match(target, os$weekF)]
      if (!is.finite(y) || !is.finite(n) || n <= 0 || y < 0 || y > n) next
      available <- isTRUE(mp$forecast_available[i]) && is.finite(mp$m1_p_hat[i])
      reason <- mp$unavailable_reason[i]
      if (is.null(dec) || !is.finite(dec$week)) {
        available <- FALSE
        reason <- "ignition_declaration_unavailable"
      } else if (ew < dec$week) {
        available <- FALSE
        reason <- "prefix_feature_unavailable"
      }
      feature_row <- if (available && !is.null(observed_features)) {
        tryCatch(m2_subset_runtime_feature_row(
          NULL, ew, dec, mp$m1_p_hat[i], h, alpha_state,
          observed_features = observed_features
        ), error = function(e) NULL)
      } else {
        NULL
      }
      if (is.null(feature_row)) {
        available <- FALSE
        if (is.na(reason) || !nzchar(reason)) reason <- "prefix_feature_unavailable"
      }
      rows[[length(rows) + 1L]] <- data.frame(
        season = s, eval_weekF = ew, target_weekF = target, h = h,
        lead = factor(paste0("h", h), levels = c("h1", "h2")),
        m1_p = if (available) as.numeric(mp$m1_p_hat[i]) else NA_real_,
        m1_logit = if (available) feature_row$m1_logit else NA_real_,
        z = if (available) feature_row$z else NA_real_,
        u = if (available) feature_row$u else NA_real_,
        d = if (available) feature_row$d else NA_real_,
        tau = if (available) {
          peak <- as.numeric(mp$peak_weekF_origin[i])
          if (is.finite(peak)) max(-6, min(6, target - peak)) else NA_real_
        } else {
          NA_real_
        },
        peak_weekF_origin = if (available) as.numeric(mp$peak_weekF_origin[i]) else NA_real_,
        peak_ci_width = if (available) as.numeric(mp$peak_ci_width[i]) else NA_real_,
        ignition_weekF = if (nrow(timing_truth_by_season) &&
          s %in% as.character(timing_truth_by_season$season)) {
          as.numeric(timing_truth_by_season$ignition_target_weekF[match(s, as.character(timing_truth_by_season$season))])
        } else {
          as.numeric(dec$week)
        },
        y_lead = y, N_lead = n,
        forecast_available = available,
        unavailable_reason = if (available) NA_character_ else reason,
        stringsAsFactors = FALSE
      )
    }
    list(rows = rows, declarations = declarations)
  }
  prepared <- if (isTRUE(parallel)) {
    furrr::future_map(as.character(seasons), prepare_season,
      .options = furrr::furrr_options(seed = FALSE)
    )
  } else {
    lapply(as.character(seasons), prepare_season)
  }
  rows <- do.call(c, lapply(prepared, `[[`, "rows"))
  declarations <- list()
  for (result in prepared) {
    declarations[names(result$declarations)] <- result$declarations
  }
  if (!length(rows)) stop("M2 subset training produced no eligible M1 forecast rows.", call. = FALSE)
  missing_seasons <- setdiff(as.character(seasons), unique(vapply(
    rows, function(x) as.character(x$season[1L]), character(1)
  )))
  if (length(missing_seasons)) {
    stop("M2 subset training has no eligible rows for season(s): ",
      paste(missing_seasons, collapse = ", "),
      call. = FALSE
    )
  }
  out_data <- do.call(rbind, rows)
  score_meta <- .page_scoring_metadata(data, timing_truth = timing_truth)
  refs <- unique(score_meta[, c("season", "ignition_weekF", "observed_peak_weekF"), drop = FALSE])
  refs <- refs[!duplicated(refs$season), , drop = FALSE]
  reference_ignition <- refs$ignition_weekF[match(out_data$season, refs$season)]
  row_ignition <- as.numeric(out_data$ignition_weekF)
  out_data$ignition_weekF <- ifelse(
    is.finite(reference_ignition), reference_ignition, row_ignition
  )
  out_data$observed_peak_weekF <- refs$observed_peak_weekF[match(out_data$season, refs$season)]
  scored <- page_phase_weights(
    out_data, page_scoring_weights(),
    season_col = "season", target_col = "target_weekF",
    ignition_col = "ignition_weekF", peak_col = "observed_peak_weekF",
    allow_censored = TRUE
  )
  out_data$phase <- scored$phase
  out_data$weight_page_v2 <- scored$weight
  out_data$weight_legacy <- .m2_subset_phase_weights(
    out_data,
    early_weight = 2, early_max_t_since = 12,
    pre_ignition_weight = 0, late_weight = 1
  )
  derived_prediction_names <- setdiff(
    c("peak_weekF_origin", "peak_ci_width"), original_prediction_names
  )
  prediction_output <- m1_train_preds[, setdiff(
    names(m1_train_preds), derived_prediction_names
  ), drop = FALSE]
  list(
    data = out_data, m1_train_preds = prediction_output,
    declarations = declarations,
    declaration_provenance = paste(
      if (nrow(timing_truth_by_season)) {
        paste0(
          "Gate rows use manual M0 ignition label truth for timing; no fitted M0 ",
          "feature enters the gate. Observed z/u/d values use only each season's ",
          "prefix through its M1 origin."
        )
      } else {
        paste0(
          "Frozen M0 parameters applied to each season prefix through each M1 origin;",
          " first locked ignite_ok_now declaration; no future prefix rows used."
        )
      }
    )
  )
}

m2_subset_score <- function(data, prediction, weights = NULL) {
  empty <- c(
    nll = NA_real_, mae = NA_real_,
    nll_test_count = NA_real_, nll_equal_week = NA_real_,
    mae_test_count = NA_real_, mae_equal_week = NA_real_,
    rows = 0, trials = 0, weight_sum = 0
  )
  if (!nrow(data)) {
    return(empty)
  }
  p <- pmin(1 - 1e-12, pmax(1e-12, prediction))
  if (is.null(weights)) weights <- rep(1, nrow(data))
  weights <- as.numeric(weights)
  if (length(weights) != nrow(data) || any(!is.finite(weights)) || any(weights < 0)) {
    stop("Score weights must be finite, non-negative, and one per row.", call. = FALSE)
  }
  trials <- sum(data$N_lead)
  p_obs <- data$y_lead / data$N_lead
  nll_counts <- -data$y_lead * log(p) - (data$N_lead - data$y_lead) * log1p(-p)
  nll_rate <- -(p_obs * log(p) + (1 - p_obs) * log1p(-p))
  abs_err <- abs(p - p_obs)
  wsum <- sum(weights)
  nll_test_count <- sum(weights * nll_counts) / sum(weights * data$N_lead)
  nll_equal_week <- if (wsum > 0) sum(weights * nll_rate) / wsum else NA_real_
  mae_test_count <- sum(weights * data$N_lead * abs_err) / sum(weights * data$N_lead)
  mae_equal_week <- if (wsum > 0) sum(weights * abs_err) / wsum else NA_real_
  c(
    nll = if (wsum > 0) nll_test_count else NA_real_,
    mae = if (wsum > 0) mae_test_count else NA_real_,
    nll_test_count = nll_test_count, nll_equal_week = nll_equal_week,
    mae_test_count = mae_test_count, mae_equal_week = mae_equal_week,
    rows = nrow(data), trials = trials, weight_sum = wsum
  )
}

.m2_subset_phase_weights <- function(data, early_weight, early_max_t_since,
                                     pre_ignition_weight = 0,
                                     late_weight = 1) {
  early_weight <- as.numeric(early_weight[1L])
  early_max_t_since <- as.numeric(early_max_t_since[1L])
  pre_ignition_weight <- as.numeric(pre_ignition_weight[1L])
  late_weight <- as.numeric(late_weight[1L])
  if (!is.finite(early_weight) || early_weight < 0) {
    stop("`early_weight` must be one finite non-negative number.", call. = FALSE)
  }
  if (!is.finite(early_max_t_since) || early_max_t_since < 0) {
    stop("`early_max_t_since` must be one finite non-negative number.", call. = FALSE)
  }
  if (!is.finite(pre_ignition_weight) || pre_ignition_weight < 0) {
    stop("`pre_ignition_weight` must be one finite non-negative number.",
      call. = FALSE
    )
  }
  if (!is.finite(late_weight) || late_weight < 0) {
    stop("`late_weight` must be one finite non-negative number.", call. = FALSE)
  }
  t_since_target <- as.numeric(data$u) + as.numeric(data$h)
  ifelse(
    t_since_target < 0, pre_ignition_weight,
    ifelse(t_since_target <= early_max_t_since, early_weight, late_weight)
  )
}

# Shared M2 selection procedure. This is the single implementation used by the
# outer search (`m2_subset_tune`) and by the fully nested inner gate, so the two
# cannot drift. It takes already-prepared training rows whose M1 features and
# timing are fixed by the caller; it never reads outer scores, grids, or
# rankings.
.m2_subset_select_core <- function(training_data, row_weights, grid,
                                   training_seasons, scored_seasons_by_horizon,
                                   nll_primary, mae_primary,
                                   alpha_state, gamma,
                                   ckpt_dir = NULL, n_cores = 1L,
                                   label = "M2 subset tuning",
                                   evaluation_label = "cross-fitted") {
  grid <- as.data.frame(grid)
  training_seasons <- as.character(training_seasons)
  empty_score <- c(
    nll_test_count = NA_real_, nll_equal_week = NA_real_,
    mae_test_count = NA_real_, mae_equal_week = NA_real_,
    rows = 0, trials = 0, weight_sum = 0
  )
  summary_rows <- list()
  selected <- list()
  evaluate_spec <- function(i) {
    spec <- grid[i, , drop = FALSE]
    spec_id <- as.character(spec$id[1L])
    ckpt_file <- if (!is.null(ckpt_dir)) {
      file.path(ckpt_dir, paste0(spec_id, ".rds"))
    } else {
      NULL
    }
    if (!is.null(ckpt_file) && file.exists(ckpt_file)) {
      cached <- tryCatch(readRDS(ckpt_file), error = function(e) NULL)
      if (is.data.frame(cached) &&
        setequal(as.character(cached$season), training_seasons) &&
        all(c("spec_id", "season", "horizon", "status", "coverage_key") %in% names(cached))) {
        cached$evaluation_label <- evaluation_label
        return(cached)
      }
    }
    spec_rows <- list()
    available_all <- if ("forecast_available" %in% names(training_data)) {
      !is.na(training_data$forecast_available) & training_data$forecast_available
    } else {
      rep(TRUE, nrow(training_data))
    }
    coverage_key_by_h <- setNames(vapply(1:2, function(h) {
      paste(sort(.page_forecast_row_key(
        training_data[training_data$h == h & available_all, , drop = FALSE]
      )), collapse = "\n")
    }, character(1)), as.character(1:2))
    scheduled_by_h <- tabulate(as.integer(training_data$h), nbins = 2L)
    available_by_h <- tabulate(as.integer(training_data$h[available_all]), nbins = 2L)
    for (s in training_seasons) {
      keep_tr <- training_data$season != s
      available <- if ("forecast_available" %in% names(training_data)) {
        !is.na(training_data$forecast_available) & training_data$forecast_available
      } else {
        rep(TRUE, nrow(training_data))
      }
      tr <- training_data[keep_tr & available, , drop = FALSE]
      va_all <- training_data[!keep_tr, , drop = FALSE]
      va <- va_all[available[!keep_tr], , drop = FALSE]
      fit <- tryCatch(m2_subset_fit(tr, spec, gamma = gamma), error = function(e) NULL)
      for (h in 1:2) {
        vh <- va[va$h == h, , drop = FALSE]
        wh <- row_weights[!keep_tr][available[!keep_tr]][va$h == h]
        pr <- if (!is.null(fit) && nrow(vh)) tryCatch(m2_subset_predict(fit, vh)$p_hat, error = function(e) NULL) else NULL
        sc <- if (!is.null(pr)) {
          m2_subset_score(vh, pr, weights = wh)
        } else {
          empty_score
        }
        spec_rows[[length(spec_rows) + 1L]] <- data.frame(
          spec_id = spec_id, season = s, horizon = h,
          bernoulli_nll = sc[[nll_primary]], mae = sc[[mae_primary]],
          bernoulli_nll_test_count = sc[["nll_test_count"]],
          bernoulli_nll_equal_week = sc[["nll_equal_week"]],
          mae_test_count = sc[["mae_test_count"]],
          mae_equal_week = sc[["mae_equal_week"]],
          rows = sc[["rows"]], trials = sc[["trials"]],
          weight_sum = sc[["weight_sum"]],
          scheduled_rows = scheduled_by_h[h],
          available_rows = available_by_h[h],
          unavailable_rows = scheduled_by_h[h] - available_by_h[h],
          coverage_key = coverage_key_by_h[[as.character(h)]],
          status = if (is.null(pr)) {
            "failed"
          } else if (!is.finite(sc[["weight_sum"]]) || sc[["weight_sum"]] <= 0) {
            "unscored"
          } else {
            "ok"
          },
          stringsAsFactors = FALSE
        )
      }
    }
    spec_scores <- do.call(rbind, spec_rows)
    spec_scores$evaluation_label <- evaluation_label
    if (!is.null(ckpt_file)) {
      saveRDS(spec_scores, ckpt_file)
    }
    spec_scores
  }
  score_rows <- if (n_cores > 1L) {
    furrr::future_map(seq_len(nrow(grid)), evaluate_spec,
      .options = furrr::furrr_options(seed = FALSE)
    )
  } else {
    lapply(seq_len(nrow(grid)), evaluate_spec)
  }
  scores <- do.call(rbind, score_rows)
  stage_a_grid <- grid
  stage_a_summary <- if (nrow(scores)) {
    z <- scores[is.finite(scores$bernoulli_nll), , drop = FALSE]
    if (nrow(z)) stats::aggregate(bernoulli_nll ~ spec_id + horizon, z, mean) else data.frame()
  } else {
    data.frame()
  }
  expanded_grid <- .m2_subset_stage_b_grid(stage_a_grid, stage_a_summary)
  if (nrow(expanded_grid) > nrow(stage_a_grid)) {
    old_ids <- as.character(stage_a_grid$id)
    grid <- expanded_grid
    extra <- which(!as.character(grid$id) %in% old_ids)
    extra_scores <- if (n_cores > 1L) {
      furrr::future_map(extra, evaluate_spec,
        .options = furrr::furrr_options(seed = FALSE)
      )
    } else {
      lapply(extra, evaluate_spec)
    }
    scores <- rbind(scores, do.call(rbind, extra_scores))
  }
  coverage_by_horizon <- vector("list", 2L)
  for (h in 1:2) {
    z <- scores[scores$horizon == h, , drop = FALSE]
    coverage_signatures <- unique(as.character(z$coverage_key))
    if (length(coverage_signatures) != 1L) {
      stop(label, " candidate coverage differs between compared specs at h=", h,
        "; refusing to compare models on different denominators.",
        call. = FALSE
      )
    }
    coverage_by_horizon[[h]] <- data.frame(
      horizon = h,
      scheduled_rows = unique(z$scheduled_rows)[1L],
      available_rows = unique(z$available_rows)[1L],
      unavailable_rows = unique(z$unavailable_rows)[1L],
      coverage_key = coverage_signatures[1L], stringsAsFactors = FALSE
    )
    valid <- z[as.character(z$status) == "ok" & is.finite(z$bernoulli_nll), , drop = FALSE]
    counts <- table(valid$spec_id)
    scored_seasons <- scored_seasons_by_horizon[[as.character(h)]]
    complete_ids <- names(counts)[counts == length(scored_seasons)]
    agg <- if (length(complete_ids)) {
      stats::aggregate(
        bernoulli_nll ~ spec_id,
        valid[valid$spec_id %in% complete_ids, , drop = FALSE], mean
      )
    } else {
      data.frame()
    }
    if (!nrow(agg) || any(!is.finite(agg$bernoulli_nll))) {
      stop(label, " has no complete h", h, " candidates.", call. = FALSE)
    }
    enabled <- grid$enabled_count[match(agg$spec_id, grid$id)]
    ord <- order(agg$bernoulli_nll, enabled, agg$spec_id)
    best <- agg[ord[1L], , drop = FALSE]
    selected[[h]] <- grid[match(best$spec_id, grid$id), , drop = FALSE]
    summary_rows[[h]] <- data.frame(
      spec_id = agg$spec_id, horizon = h, bernoulli_nll = agg$bernoulli_nll,
      n_seasons = length(scored_seasons), stringsAsFactors = FALSE
    )
  }
  selected_config <- m2_subset_config(
    h1 = selected[[1L]], h2 = selected[[2L]], alpha_state = alpha_state,
    gamma = gamma
  )
  list(
    grid = grid, scores = scores,
    summary = do.call(rbind, summary_rows),
    selected = selected, selected_config = selected_config,
    coverage = do.call(rbind, coverage_by_horizon),
    best_spec_id = paste0(
      "h1:", selected[[1L]]$id, "|h2:", selected[[2L]]$id
    )
  )
}

m2_subset_tune <- function(data, selection, m0, m1, grid = m2_subset_grid(),
                           alpha_state = NULL, m1_train_preds = NULL,
                           detector = run_ignition_weekly,
                           early_weight = 1, early_max_t_since = 12,
                           pre_ignition_weight = 0, late_weight = 1,
                           score_scale = c("equal_week", "test_count"),
                           scoring = c("page_v2", "legacy_0_12"),
                           checkpoint_dir = NULL,
                           timing_mode = c("legacy", "fractional"),
                           n_cores = 1L, timing_truth = NULL, ...) {
  if (length(n_cores) != 1L || !is.numeric(n_cores) ||
    !is.finite(n_cores) || n_cores < 1 || n_cores > .Machine$integer.max ||
    n_cores != as.integer(n_cores)) {
    stop("`n_cores` must be one positive integer.", call. = FALSE)
  }
  if (n_cores > 1L) {
    old_plan <- .page_set_parallel_plan(n_cores)
    on.exit(future::plan(old_plan), add = TRUE)
  }
  score_scale <- match.arg(score_scale)
  scoring <- match.arg(scoring)
  timing_mode <- match.arg(timing_mode)
  grid <- as.data.frame(grid)
  if (!is.data.frame(grid) || !nrow(grid)) stop("M2 subset grid must be non-empty.", call. = FALSE)
  config_defaults <- m2_subset_config()
  raw_alpha <- if ("alpha_state" %in% names(grid)) {
    grid$alpha_state
  } else {
    config_defaults$alpha_state
  }
  raw_gamma <- if ("gamma" %in% names(grid)) {
    grid$gamma
  } else {
    config_defaults$gamma
  }
  if (!is.null(alpha_state)) raw_alpha <- alpha_state
  if (length(raw_alpha) == 1L) raw_alpha <- rep(raw_alpha, nrow(grid))
  if (length(raw_gamma) == 1L) raw_gamma <- rep(raw_gamma, nrow(grid))
  if (length(raw_alpha) != nrow(grid) || length(raw_gamma) != nrow(grid)) {
    stop("M2 subset alpha_state and gamma grids must match nrow(grid).", call. = FALSE)
  }
  if (any(!is.finite(raw_alpha) | raw_alpha <= 0 | raw_alpha >= 1) ||
    any(!is.finite(raw_gamma) | raw_gamma < 1)) {
    stop("M2 subset grid has invalid alpha_state or gamma values.", call. = FALSE)
  }
  if (length(unique(raw_alpha)) > 1L || length(unique(raw_gamma)) > 1L) {
    stop("M2 subset tuning currently requires shared alpha_state and gamma; use one value of each.", call. = FALSE)
  }
  normalized <- lapply(seq_len(nrow(grid)), function(i) m2_subset_spec(grid[i, , drop = FALSE]))
  grid <- do.call(rbind, normalized)
  grid$alpha_state <- as.numeric(raw_alpha[1L])
  grid$gamma <- as.numeric(raw_gamma[1L])
  grid$enabled_count <- vapply(seq_len(nrow(grid)), function(i) {
    m2_subset_spec(grid[i, , drop = FALSE])$enabled_count
  }, integer(1))
  grid$id <- vapply(seq_len(nrow(grid)), function(i) m2_subset_spec(grid[i, ])$id, character(1))
  if (anyDuplicated(grid$id)) stop("M2 subset grid has duplicate stable IDs.", call. = FALSE)
  alpha_state <- grid$alpha_state[1L]
  gamma <- grid$gamma[1L]
  training <- m2_subset_make_rows(data, m0, m1, m1_train_preds,
    selection$training_seasons,
    detector = detector, alpha_state = alpha_state,
    timing_mode = timing_mode, parallel = n_cores > 1L,
    timing_truth = timing_truth
  )
  data_id <- .stage_training_data_id(data)
  row_weights <- .m2_subset_phase_weights(
    training$data, early_weight, early_max_t_since,
    pre_ignition_weight, late_weight
  )
  row_weights_legacy <- row_weights
  row_weights_page <- as.numeric(training$data$weight_page_v2)
  row_weights <- if (scoring == "page_v2") row_weights_page else row_weights_legacy
  row_weights[!is.finite(row_weights)] <- 0
  # A season with no positively weighted scoring rows (no observed peak, a
  # partial season, or fully censored) is unscored: it is excluded from the
  # candidate completeness requirement rather than aborting tuning.
  scored_seasons_by_horizon <- lapply(1:2, function(h) {
    idx <- as.integer(training$data$h) == h
    w <- row_weights[idx]
    keep <- is.finite(w) & w > 0
    sort(unique(as.character(training$data$season[idx][keep])))
  })
  names(scored_seasons_by_horizon) <- as.character(1:2)
  if (any(lengths(scored_seasons_by_horizon) == 0L)) {
    stop("M2 subset tuning has no scored rows for at least one horizon.",
      call. = FALSE
    )
  }
  nll_primary <- if (score_scale == "equal_week") "nll_equal_week" else "nll_test_count"
  mae_primary <- if (score_scale == "equal_week") "mae_equal_week" else "mae_test_count"
  scoring_hash <- substr(digest::digest(list(
    data_id = data_id,
    m0_id = m0$artifact_id, m1_id = m1$artifact_id,
    alpha_state = alpha_state, gamma = gamma,
    early_weight = as.numeric(early_weight),
    early_max_t_since = as.numeric(early_max_t_since),
    pre_ignition_weight = as.numeric(pre_ignition_weight),
    late_weight = as.numeric(late_weight),
    scoring = scoring,
    page_scoring_weights = page_scoring_weights(),
    score_scale = score_scale,
    timing_mode = timing_mode,
    training_rows = digest::digest(training$data)
  )), 1L, 16L)
  ckpt_dir <- NULL
  if (!is.null(checkpoint_dir) && nzchar(checkpoint_dir)) {
    ckpt_dir <- file.path(checkpoint_dir, scoring_hash)
    dir.create(ckpt_dir, recursive = TRUE, showWarnings = FALSE)
  }
  core <- .m2_subset_select_core(
    training_data = training$data, row_weights = row_weights, grid = grid,
    training_seasons = selection$training_seasons,
    scored_seasons_by_horizon = scored_seasons_by_horizon,
    nll_primary = nll_primary, mae_primary = mae_primary,
    alpha_state = alpha_state, gamma = gamma,
    ckpt_dir = ckpt_dir, n_cores = n_cores,
    evaluation_label = "cross-fitted"
  )
  grid <- core$grid
  scores <- core$scores
  selected <- core$selected
  selected_config <- core$selected_config
  summary_tbl <- core$summary
  out <- list(
    family = m2_subset_family(), grid = grid,
    scores = scores, summary = summary_tbl,
    selected = selected, selected_config = selected_config,
    best_spec_id = core$best_spec_id,
    selection = selection, data_id = data_id,
    training_rows = training$data, m1_train_preds = training$m1_train_preds,
    declaration_provenance = training$declaration_provenance,
    alpha_state = alpha_state,
    coverage = core$coverage,
    evaluation_label = "cross-fitted",
    scoring = list(
      early_weight = as.numeric(early_weight),
      early_max_t_since = as.numeric(early_max_t_since),
      pre_ignition_weight = as.numeric(pre_ignition_weight),
      late_weight = as.numeric(late_weight),
      scoring = scoring,
      weight_columns = c(page_v2 = "weight_page_v2", legacy_0_12 = "weight_legacy"),
      score_scale = score_scale,
      phase_definition = paste0(
        "target t_since = u + h; pre_ignition (t_since < 0) weight ",
        pre_ignition_weight, ";",
        " early (0 <= t_since <= early_max_t_since) weight early_weight;",
        " late (t_since > early_max_t_since) weight ", late_weight
      ),
      coverage = core$coverage,
      scored_seasons = scored_seasons_by_horizon,
      scoring_hash = scoring_hash,
      evaluation_label = "cross-fitted"
    )
  )
  class(out) <- c("page_m2_subset_tuning", "page_m2_tuning", "list")
  out
}

m2_subset_validate_tuning <- function(x) {
  if (!inherits(x, "page_m2_subset_tuning") || !identical(x$family, m2_subset_family())) {
    stop("Invalid M2 subset tuning family.", call. = FALSE)
  }
  if (!is.data.frame(x$grid) || nrow(x$grid) < 1L ||
    !is.data.frame(x$scores) || !is.list(x$selected_config) ||
    !is.list(x$selected) || length(x$selected) != 2L ||
    !all(m2_subset_component_names() %in% names(x$grid)) ||
    !all(c("id", "enabled_count") %in% names(x$grid))) {
    stop("M2 subset tuning is incomplete.", call. = FALSE)
  }
  if (anyDuplicated(as.character(x$grid$id)) || anyNA(x$grid$id) ||
    any(!nzchar(as.character(x$grid$id)))) {
    stop("M2 subset tuning grid has invalid or duplicate IDs.", call. = FALSE)
  }
  grid_ids <- as.character(x$grid$id)
  grid_specs <- lapply(seq_len(nrow(x$grid)), function(i) {
    spec <- tryCatch(m2_subset_spec(x$grid[i, , drop = FALSE]),
      error = function(e) e
    )
    if (inherits(spec, "error")) stop(conditionMessage(spec), call. = FALSE)
    if (!identical(spec$id[1L], grid_ids[i])) {
      stop("M2 subset tuning grid switch identity is inconsistent.", call. = FALSE)
    }
    if (!identical(as.integer(x$grid$enabled_count[i]), spec$enabled_count[1L])) {
      stop("M2 subset tuning grid enabled-count identity is inconsistent.", call. = FALSE)
    }
    spec
  })

  if (!inherits(x$selection, "page_season_selection") ||
    !is.character(x$selection$training_seasons) ||
    !length(x$selection$training_seasons) ||
    anyNA(x$selection$training_seasons) ||
    anyDuplicated(x$selection$training_seasons)) {
    stop("M2 subset tuning is missing a valid season selection.", call. = FALSE)
  }
  seasons <- as.character(x$selection$training_seasons)
  if (!is.character(x$data_id) || length(x$data_id) != 1L ||
    is.na(x$data_id) || !nzchar(x$data_id) ||
    !is.data.frame(x$training_rows) || !nrow(x$training_rows) ||
    !is.data.frame(x$m1_train_preds) || !nrow(x$m1_train_preds) ||
    !is.character(x$declaration_provenance) ||
    length(x$declaration_provenance) != 1L ||
    is.na(x$declaration_provenance) || !nzchar(x$declaration_provenance) ||
    !is.numeric(x$alpha_state) || length(x$alpha_state) != 1L ||
    !is.finite(x$alpha_state) || x$alpha_state <= 0 || x$alpha_state >= 1) {
    stop("M2 subset tuning has incomplete provenance.", call. = FALSE)
  }
  selected_config <- m2_subset_validate_config(x$selected_config)
  for (h in 1:2) {
    name <- paste0("h", h)
    raw_spec <- x$selected_config[[name]]
    normalized_spec <- selected_config[[name]]
    required <- c("id", m2_subset_component_names(), "enabled_count")
    if (!is.data.frame(raw_spec) || nrow(raw_spec) != 1L ||
      !all(required %in% names(raw_spec)) ||
      !identical(as.character(raw_spec$id[1L]), normalized_spec$id[1L]) ||
      !identical(
        as.integer(raw_spec$enabled_count[1L]),
        as.integer(normalized_spec$enabled_count[1L])
      ) ||
      !identical(
        unname(unlist(raw_spec[1L, m2_subset_component_names(), drop = FALSE],
          use.names = FALSE
        )),
        unname(unlist(normalized_spec[1L, m2_subset_component_names(), drop = FALSE],
          use.names = FALSE
        ))
      )) {
      stop("M2 subset tuning selected config ", name,
        " switch identity is inconsistent.",
        call. = FALSE
      )
    }
  }
  training_fields <- c(
    "season", "eval_weekF", "target_weekF", "h", "lead", "m1_p",
    "m1_logit", "z", "u", "d", "y_lead", "N_lead",
    "forecast_available", "unavailable_reason"
  )
  # Older governed tuning artifacts predate the phase-2/3 provenance columns;
  # retain read/validation compatibility while every new tuning result emits
  # the complete scoring and origin-time feature schema.
  pred_fields <- c(
    "season", "eval_weekF", "target_weekF", "h", "m1_p_hat",
    "forecast_available", "unavailable_reason"
  )
  if (!all(training_fields %in% names(x$training_rows)) ||
    !all(pred_fields %in% names(x$m1_train_preds))) {
    stop("M2 subset tuning provenance is missing required training fields.", call. = FALSE)
  }
  training_available <- !is.na(x$training_rows$forecast_available) &
    x$training_rows$forecast_available
  pred_available <- !is.na(x$m1_train_preds$forecast_available) &
    x$m1_train_preds$forecast_available
  if (!setequal(as.character(unique(x$training_rows$season)), seasons) ||
    !setequal(as.character(unique(x$m1_train_preds$season)), seasons) ||
    anyNA(x$training_rows$lead) ||
    any(!is.finite(as.numeric(x$training_rows$eval_weekF))) ||
    any(!is.finite(as.numeric(x$training_rows$target_weekF))) ||
    any(!is.finite(as.numeric(x$training_rows$h))) ||
    any(!is.finite(as.numeric(x$training_rows$m1_p[training_available]))) ||
    any(x$training_rows$m1_p[training_available] < 0 | x$training_rows$m1_p[training_available] > 1) ||
    any(!is.finite(as.numeric(x$training_rows$m1_logit[training_available]))) ||
    any(!is.finite(as.numeric(x$training_rows$y_lead))) ||
    any(!is.finite(as.numeric(x$training_rows$N_lead))) ||
    any(!is.finite(as.numeric(x$m1_train_preds$eval_weekF))) ||
    any(!is.finite(as.numeric(x$m1_train_preds$target_weekF))) ||
    any(!is.finite(as.numeric(x$m1_train_preds$h))) ||
    any(!is.finite(as.numeric(x$m1_train_preds$m1_p_hat[pred_available]))) ||
    any(x$m1_train_preds$m1_p_hat[pred_available] < 0 | x$m1_train_preds$m1_p_hat[pred_available] > 1) ||
    any(as.character(x$training_rows$lead) != paste0("h", x$training_rows$h)) ||
    any(!(as.numeric(x$training_rows$h) %in% c(1, 2))) ||
    any(!(as.numeric(x$m1_train_preds$h) %in% c(1, 2))) ||
    any(as.numeric(x$training_rows$target_weekF) !=
      as.numeric(x$training_rows$eval_weekF) + as.numeric(x$training_rows$h)) ||
    any(as.numeric(x$m1_train_preds$target_weekF) !=
      as.numeric(x$m1_train_preds$eval_weekF) + as.numeric(x$m1_train_preds$h)) ||
    !identical(as.numeric(x$alpha_state), as.numeric(selected_config$alpha_state))) {
    stop("M2 subset tuning provenance is inconsistent with its training rows.", call. = FALSE)
  }
  if (any(!training_available & (is.na(x$training_rows$unavailable_reason) |
    !nzchar(as.character(x$training_rows$unavailable_reason)))) ||
    any(!pred_available & (is.na(x$m1_train_preds$unavailable_reason) |
      !nzchar(as.character(x$m1_train_preds$unavailable_reason))))) {
    stop("M2 subset tuning unavailable rows must document an unavailable reason.", call. = FALSE)
  }

  if (!identical(as.numeric(x$alpha_state), as.numeric(selected_config$alpha_state))) {
    stop("M2 subset tuning alpha_state does not match the selected configuration.", call. = FALSE)
  }
  for (h in 1:2) {
    selected_row <- x$selected[[h]]
    if (!is.data.frame(selected_row) || nrow(selected_row) != 1L) {
      stop("M2 subset tuning selected specification is malformed.", call. = FALSE)
    }
    selected_spec <- m2_subset_spec(selected_row)
    if (!all(c("id", m2_subset_component_names(), "enabled_count") %in%
      names(selected_row)) ||
      !identical(as.character(selected_row$id[1L]), selected_spec$id[1L]) ||
      !identical(
        as.integer(selected_row$enabled_count[1L]),
        as.integer(selected_spec$enabled_count[1L])
      ) ||
      !identical(
        unname(unlist(selected_row[1L, m2_subset_component_names(), drop = FALSE],
          use.names = FALSE
        )),
        unname(unlist(selected_spec[1L, m2_subset_component_names(), drop = FALSE],
          use.names = FALSE
        ))
      )) {
      stop("M2 subset tuning selected specification switch identity is inconsistent.",
        call. = FALSE
      )
    }
    chosen <- selected_config[[paste0("h", h)]]$id
    if (!identical(selected_spec$id[1L], chosen) ||
      !chosen %in% grid_ids ||
      !identical(
        selected_spec[1L, m2_subset_component_names(), drop = FALSE],
        grid_specs[[match(chosen, grid_ids)]][1L, m2_subset_component_names(), drop = FALSE]
      )) {
      stop("M2 subset tuning selected specification identity is invalid.", call. = FALSE)
    }
  }
  if (!is.character(x$best_spec_id) || length(x$best_spec_id) != 1L ||
    !identical(x$best_spec_id, paste0(
      "h1:", selected_config$h1$id, "|h2:", selected_config$h2$id
    ))) {
    stop("M2 subset tuning best specification identity is invalid.", call. = FALSE)
  }

  score_fields <- c(
    "spec_id", "season", "horizon", "bernoulli_nll", "mae",
    "rows", "trials", "status", "scheduled_rows", "available_rows",
    "unavailable_rows", "coverage_key"
  )
  if (!all(score_fields %in% names(x$scores)) ||
    anyNA(x$scores$spec_id) || anyNA(x$scores$season) ||
    anyNA(x$scores$horizon) || anyNA(x$scores$status) || anyDuplicated(paste(
    x$scores$spec_id, x$scores$season, x$scores$horizon,
    sep = "\r"
  ))) {
    stop("M2 subset tuning fold scores are malformed or duplicated.", call. = FALSE)
  }
  expected <- expand.grid(
    spec_id = grid_ids, season = seasons, horizon = 1:2,
    stringsAsFactors = FALSE
  )
  observed <- data.frame(
    spec_id = as.character(x$scores$spec_id),
    season = as.character(x$scores$season),
    horizon = as.integer(x$scores$horizon),
    stringsAsFactors = FALSE
  )
  key <- function(data) paste(data$spec_id, data$season, data$horizon, sep = "\r")
  if (nrow(observed) != nrow(expected) || !setequal(key(observed), key(expected)) ||
    any(!as.character(x$scores$status) %in% c("ok", "failed", "unscored"))) {
    stop("M2 subset tuning fold scores are incomplete or have invalid statuses.", call. = FALSE)
  }
  ok <- as.character(x$scores$status) == "ok"
  if (any(!is.finite(x$scores$bernoulli_nll[ok])) ||
    any(!is.finite(x$scores$mae[ok])) || any(!is.finite(x$scores$rows[ok])) ||
    any(x$scores$rows[ok] <= 0) || any(!is.finite(x$scores$trials[ok])) ||
    any(x$scores$trials[ok] <= 0)) {
    stop("M2 subset tuning successful folds must have finite metrics.", call. = FALSE)
  }
  unscored <- as.character(x$scores$status) == "unscored"
  if (any(x$scores$weight_sum[unscored] > 0, na.rm = TRUE)) {
    stop("M2 subset tuning unscored folds must have no scoring weight.", call. = FALSE)
  }

  if (!is.data.frame(x$summary) || !nrow(x$summary) ||
    !all(c("spec_id", "horizon", "bernoulli_nll", "n_seasons") %in% names(x$summary)) ||
    anyDuplicated(paste(x$summary$spec_id, x$summary$horizon, sep = "\r"))) {
    stop("M2 subset tuning summary is malformed.", call. = FALSE)
  }
  scored_seasons_for <- function(h) {
    ss <- x$scoring$scored_seasons
    if (is.null(ss)) {
      return(seasons)
    }
    value <- ss[[as.character(h)]]
    if (is.null(value)) seasons else as.character(value)
  }
  summary_key <- paste(as.character(x$summary$spec_id), x$summary$horizon, sep = "\r")
  expected_n <- vapply(1:2, function(h) length(scored_seasons_for(h)), integer(1))
  summary_n <- vapply(seq_len(nrow(x$summary)), function(i) {
    expected_n[[as.integer(x$summary$horizon[i])]]
  }, integer(1))
  if (anyNA(x$summary$spec_id) || anyNA(x$summary$horizon) ||
    any(!x$summary$spec_id %in% grid_ids) ||
    any(!is.finite(x$summary$bernoulli_nll)) ||
    anyNA(x$summary$n_seasons) || any(x$summary$n_seasons != summary_n)) {
    stop("M2 subset tuning summary is incomplete or non-finite.", call. = FALSE)
  }
  complete_keys <- character()
  for (spec_id in grid_ids) {
    for (h in 1:2) {
      fold <- x$scores[x$scores$spec_id == spec_id & x$scores$horizon == h, , drop = FALSE]
      scored_here <- as.character(fold$season) %in% scored_seasons_for(h)
      if (nrow(fold) == length(seasons) &&
        all(as.character(fold$status)[scored_here] == "ok") &&
        all(is.finite(fold$bernoulli_nll[scored_here])) &&
        all(as.character(fold$status)[!scored_here] %in% c("unscored", "failed"))) {
        complete_keys <- c(complete_keys, paste(spec_id, h, sep = "\r"))
      }
    }
  }
  if (!setequal(summary_key, complete_keys)) {
    stop("M2 subset tuning summary does not match complete successful fold evidence.", call. = FALSE)
  }
  for (h in 1:2) {
    chosen <- x$selected_config[[paste0("h", h)]]$id
    fold <- x$scores[x$scores$spec_id == chosen & x$scores$horizon == h, , drop = FALSE]
    scored_here <- as.character(fold$season) %in% scored_seasons_for(h)
    selected_summary <- x$summary[x$summary$spec_id == chosen & x$summary$horizon == h, , drop = FALSE]
    if (nrow(fold) != length(seasons) ||
      any(as.character(fold$status)[scored_here] != "ok") ||
      any(!is.finite(fold$bernoulli_nll[scored_here])) || nrow(selected_summary) != 1L ||
      !isTRUE(all.equal(selected_summary$bernoulli_nll[1L],
        mean(fold$bernoulli_nll[scored_here]),
        tolerance = 1e-12
      ))) {
      stop("M2 subset tuning selected candidate lacks complete successful fold evidence.", call. = FALSE)
    }
  }
  invisible(x)
}

m2_subset_train <- function(data, m0, m1, config, m1_train_preds = NULL,
                            detector = run_ignition_weekly,
                            timing_mode = c("legacy", "fractional"),
                            timing_truth = NULL, ...) {
  # `timing_truth` is accepted (so `fit_m2()`/`train_outer_fold()` passing it
  # through `...` doesn't silently vanish) but deliberately NOT forwarded to
  # row construction below. m2_subset_tune() uses truth-ignition rows on
  # purpose, to keep spec selection isolated from M0 detector noise -- but
  # the deployed GAM fit here must be built the same way runtime builds its
  # rows (via the M0 detector, m2_subset_prefix_declaration()), or its s(u)
  # smooth and feature_ranges are calibrated against a timing distribution
  # the model will never see in production. See ANALYSIS_DEVIATIONS for the
  # tune-vs-train asymmetry this intentionally preserves.
  timing_mode <- match.arg(timing_mode)
  config <- m2_subset_validate_config(config)
  training <- m2_subset_make_rows(data, m0, m1, m1_train_preds,
    detector = detector, alpha_state = config$alpha_state,
    timing_mode = timing_mode, timing_truth = NULL
  )
  fit_data <- if ("forecast_available" %in% names(training$data)) {
    training$data[!is.na(training$data$forecast_available) &
      training$data$forecast_available, , drop = FALSE]
  } else {
    training$data
  }
  fits <- list(
    h1 = m2_subset_fit(fit_data, config$h1,
      method = config$method,
      gamma = config$gamma, bs = config$bs, intercept_sp = config$intercept_sp
    ),
    h2 = m2_subset_fit(fit_data, config$h2,
      method = config$method,
      gamma = config$gamma, bs = config$bs, intercept_sp = config$intercept_sp
    )
  )
  list(
    family = m2_subset_family(), fit = fits,
    feature_ranges = lapply(fits, function(x) x$feature_ranges),
    m1_train_preds = training$m1_train_preds,
    spec = config, training_seasons = sort(unique(training$data$season)),
    spec_version = m2_subset_family(), alpha_state = config$alpha_state,
    declaration_provenance = training$declaration_provenance,
    declarations = training$declarations
  )
}

m2_subset_check_tuning_match <- function(fit, tuning) {
  m2_subset_validate_tuning(tuning)
  if (!is.null(tuning$selection)) .check_selection_match(fit$selection, tuning$selection)
  if (!is.null(tuning$data_id) && !identical(fit$data_id, tuning$data_id)) {
    stop("M2 subset fit and tuning training-data identities do not match.", call. = FALSE)
  }
  if (!is.null(tuning$upstream_ids) && !identical(fit$upstream_ids, tuning$upstream_ids)) {
    stop("M2 subset fit and tuning upstream identities do not match.", call. = FALSE)
  }
  if (!identical(fit$config, tuning$selected_config)) {
    stop("M2 subset fit configuration does not match tuning selection.", call. = FALSE)
  }
  invisible(tuning)
}

m2_subset_runtime_prediction <- function(kit, current_data, m1_result,
                                         verbose = TRUE,
                                         timing_mode = c("legacy", "fractional")) {
  timing_mode <- match.arg(timing_mode)
  config <- m2_subset_validate_config(kit$best_spec)
  fits <- kit$m2_production$fit
  alpha <- config$alpha_state
  all_off <- all(vapply(config[c("h1", "h2")], function(x) identical(x$enabled_count, 0L), logical(1)))
  rows <- list()
  required_current <- c("season", "weekF", "y", "N")
  if (!is.data.frame(current_data) || length(setdiff(required_current, names(current_data)))) {
    stop("`current_data` must contain season, weekF, y, and N.", call. = FALSE)
  }
  current_data <- current_data[, required_current, drop = FALSE]
  current_data$season <- as.character(current_data$season)
  nW_current <- .page_nw_true(current_data)[1L]
  if (anyDuplicated(paste(current_data$season, current_data$weekF, sep = ":"))) {
    stop("`current_data` contains duplicate season-week rows.", call. = FALSE)
  }
  if (any(!is.finite(current_data$weekF) | !is.finite(current_data$y) |
    !is.finite(current_data$N) | current_data$N <= 0 |
    current_data$y < 0 | current_data$y > current_data$N)) {
    stop("`current_data` contains invalid observed counts or weekF values.", call. = FALSE)
  }
  for (pw in m1_result$per_week) {
    ew <- as.integer(pw$ew)
    ap <- pw$ap
    if (is.null(ap) || identical(ap$state, "pre_ignition")) next
    alignment_failed <- identical(ap$state, "alignment_failed")
    alignment_reason <- if (alignment_failed) {
      reason <- as.character(ap$fallback_reason)[1L]
      if (is.na(reason) || !nzchar(reason)) "alignment_failed" else reason
    } else {
      NULL
    }
    prefix <- pw$season_to_ew
    if (!is.data.frame(prefix) || length(setdiff(required_current, names(prefix)))) {
      stop("M1 per-week prefix is missing required observed-data columns.", call. = FALSE)
    }
    seasons <- unique(as.character(prefix$season))
    if (length(seasons) != 1L || length(unique(current_data$season)) != 1L ||
      !identical(seasons, unique(current_data$season))) {
      stop("M1 per-week prefix does not match `current_data` season.", call. = FALSE)
    }
    current_prefix <- current_data[current_data$weekF <= ew, required_current, drop = FALSE]
    supplied_prefix <- prefix[, required_current, drop = FALSE]
    current_prefix <- current_prefix[order(current_prefix$weekF), , drop = FALSE]
    supplied_prefix <- supplied_prefix[order(supplied_prefix$weekF), , drop = FALSE]
    if (!isTRUE(all.equal(current_prefix, supplied_prefix, check.attributes = FALSE))) {
      stop("M1 per-week prefix does not match `current_data` through the origin.", call. = FALSE)
    }
    prefix <- current_prefix
    declaration <- if (!all_off) {
      m2_subset_prefix_declaration(
        prefix, kit$m0_params, ew,
        timing_mode = timing_mode
      )
    } else {
      list(week = NA_integer_)
    }
    fs <- if (!all_off && is.finite(declaration$week)) {
      m2_subset_observed_features(prefix, declaration$week, alpha)
    } else {
      NULL
    }
    oi <- if (!is.null(fs)) match(ew, fs$weekF) else NA_integer_
    fdf <- ap$forecast_df
    for (h in c(1L, 2L)) {
      target <- ew + h
      i_week <- as.numeric(ap$iWeek_hatF %||% ap$iWeek_hat)
      target_new <- target - i_week + kit$ref$anchorWeek
      availability <- .page_forecast_availability(
        target, target_new,
        nW_true = nW_current
      )
      if (alignment_failed) {
        availability$forecast_available <- FALSE
        availability$unavailable_reason <- alignment_reason
      }
      m1_p <- if (isTRUE(availability$forecast_available)) {
        if (is.null(fdf)) {
          NA_real_
        } else {
          .approx_unique(fdf$newWeek, fdf$p_hat, target_new, rule = 1)
        }
      } else {
        NA_real_
      }
      if (isTRUE(availability$forecast_available) && !is.finite(m1_p)) {
        availability$forecast_available <- FALSE
        availability$unavailable_reason <- {
          reason <- as.character(ap$fallback_reason)[1L]
          if (is.na(reason) || !nzchar(reason)) {
            "alignment_prediction_missing"
          } else {
            reason
          }
        }
      }
      base <- data.frame(
        eval_week = ew, h = h, target_weekF = target,
        target_newWeek = target_new, nW_true = nW_current,
        forecast_available = availability$forecast_available,
        unavailable_reason = availability$unavailable_reason,
        m1_p = m1_p,
        m1_baseline = m1_p, m2_p = NA_real_, m2_lo = NA_real_,
        m2_hi = NA_real_, correction_logit = NA_real_,
        tau = NA_real_, peak_ci_width = NA_real_, confidence_scale = 1,
        confidence_scale_missing = FALSE,
        family = m2_subset_family(), forecast_action = "failed_m2_explicit",
        failure_reason = NA_character_, stringsAsFactors = FALSE
      )
      if (!isTRUE(base$forecast_available)) {
        base$forecast_action <- "unavailable"
        base$failure_reason <- base$unavailable_reason
      } else if (all_off) {
        base$m2_p <- m1_p
        base$correction_logit <- 0
        base$forecast_action <- "all_off_exact_m1"
      } else if (is.null(fs) || is.na(oi) || !is.finite(fs$z[oi]) || !is.finite(fs$d[oi])) {
        base$m2_p <- m1_p
        base$forecast_action <- "fallback_m1_explicit"
        base$failure_reason <- "prefix_feature_unavailable"
      } else {
        peak_week <- as.numeric(ap$peak_weekF %||% NA_real_)
        tau <- if (is.finite(peak_week)) max(-6, min(6, target - peak_week)) else NA_real_
        peak_width <- as.numeric(ap$peak_weekF_hi %||% NA_real_) -
          as.numeric(ap$peak_weekF_lo %||% NA_real_)
        horizon_fit <- fits[[paste0("h", h)]]
        nd <- m2_subset_runtime_feature_row(
          prefix, ew, declaration, m1_p, h, alpha,
          tau = tau, peak_ci_width = peak_width,
          conf_scale = config[[paste0("h", h)]]$conf_scale,
          w_ref = horizon_fit$w_ref
        )
        pr <- tryCatch(m2_subset_predict(horizon_fit, nd), error = function(e) e)
        if (inherits(pr, "error")) {
          base$m2_p <- m1_p
          base$forecast_action <- "fallback_m1_explicit"
          base$failure_reason <- conditionMessage(pr)
        } else {
          base$m2_p <- pr$p_hat
          base$correction_logit <- pr$correction_logit
          base$tau <- nd$tau
          base$peak_ci_width <- nd$peak_ci_width
          base$confidence_scale <- pr$confidence_scale
          base$confidence_scale_missing <- pr$confidence_scale_missing
          base$forecast_action <- "subset_gam"
        }
      }
      rows[[length(rows) + 1L]] <- base
    }
  }
  out <- if (length(rows)) {
    do.call(rbind, rows)
  } else {
    data.frame(
      eval_week = integer(), h = integer(), target_weekF = integer(),
      target_newWeek = numeric(), nW_true = integer(),
      forecast_available = logical(), unavailable_reason = character(),
      m1_p = numeric(), m1_baseline = numeric(), m2_p = numeric(),
      m2_lo = numeric(), m2_hi = numeric(), correction_logit = numeric(),
      tau = numeric(), peak_ci_width = numeric(), confidence_scale = numeric(),
      confidence_scale_missing = logical(),
      family = character(), forecast_action = character(),
      failure_reason = character(), stringsAsFactors = FALSE
    )
  }
  if (isTRUE(verbose) && nrow(out) && any(out$forecast_action == "fallback_m1_explicit")) {
    message("[run_m2_forecast] offset_subset_v1 used explicit M1 fallback for unavailable rows.")
  }
  list(m2_preds = out)
}

# ---------------------------------------------------------------------------
# Governed boundary audit for offset_subset_v1
# ---------------------------------------------------------------------------

.m2_subset_boundary_axes <- function() c("intercept", "k_z", "k_u", "k_d", "k_tau")

.m2_subset_mean_nll <- function(x, horizon) {
  z <- x$scores[
    x$scores$horizon == horizon &
      as.character(x$scores$status) == "ok" &
      is.finite(x$scores$bernoulli_nll), ,
    drop = FALSE
  ]
  if (!nrow(z)) {
    return(stats::setNames(numeric(0), character(0)))
  }
  tapply(z$bernoulli_nll, as.character(z$spec_id), mean)
}

.m2_subset_matched_gain <- function(x, horizon, axis, sel_row) {
  grid <- as.data.frame(x$grid)
  axes <- c(.m2_subset_boundary_axes(), "conf_scale")
  same_value <- function(left, right) {
    if (is.numeric(left) && is.numeric(right)) {
      isTRUE(all.equal(as.numeric(left), as.numeric(right)))
    } else {
      identical(as.character(left), as.character(right))
    }
  }
  chosen <- as.numeric(sel_row[[axis]][1L])
  tested <- sort(unique(as.numeric(grid[[axis]])))
  inward <- if (chosen >= tested[length(tested)]) {
    tested[tested < chosen]
  } else {
    tested[tested > chosen]
  }
  if (!length(inward)) {
    return(NA_real_)
  }
  inward <- if (chosen >= tested[length(tested)]) max(inward) else min(inward)
  same_other <- vapply(seq_len(nrow(grid)), function(i) {
    all(vapply(setdiff(axes, axis), function(a) {
      same_value(grid[[a]][i], sel_row[[a]][1L])
    }, logical(1))) &&
      same_value(grid[[axis]][i], inward)
  }, logical(1))
  neighbor <- grid[same_other, , drop = FALSE]
  if (nrow(neighbor) != 1L) {
    return(NA_real_)
  }
  nll <- .m2_subset_mean_nll(x, horizon)
  sel_id <- as.character(sel_row$id[1L])
  nbr_id <- as.character(neighbor$id[1L])
  if (!sel_id %in% names(nll) || !nbr_id %in% names(nll)) {
    return(NA_real_)
  }
  unname(nll[[nbr_id]] - nll[[sel_id]])
}

.m2_subset_boundary_report <- function(x, min_nll_gain = NULL, hard_caps = NULL) {
  if (!inherits(x, "page_m2_subset_tuning")) {
    stop("`x` must be a `page_m2_subset_tuning` object.", call. = FALSE)
  }
  grid <- as.data.frame(x$grid)
  caps <- min_nll_gain %||% x$min_nll_gain %||% default_m2_nll_gain_caps()
  rows <- list()
  for (h in 1:2) {
    sel_id <- as.character(x$selected_config[[paste0("h", h)]]$id[1L])
    hit <- which(as.character(grid$id) == sel_id)
    if (!length(hit)) {
      stop("Selected h", h, " specification is absent from the grid.", call. = FALSE)
    }
    sel_row <- grid[hit[1L], , drop = FALSE]
    for (axis in .m2_subset_boundary_axes()) {
      tested <- sort(unique(as.numeric(grid[[axis]])))
      if (length(tested) < 2L) next
      chosen <- as.numeric(sel_row[[axis]][1L])
      edge <- if (isTRUE(all.equal(chosen, tested[1L]))) {
        "lower"
      } else if (isTRUE(all.equal(chosen, tested[length(tested)]))) {
        "upper"
      } else {
        "none"
      }
      cap <- if (axis %in% names(caps)) as.numeric(caps[[axis]]) else NA_real_
      evidence <- NA_real_
      decision <- if (edge == "none") {
        "stop_bracketed"
      } else if (isTRUE(all.equal(chosen, 0))) {
        "accept_null_drop"
      } else if (axis == "intercept") {
        "stop_hard_cap"
      } else {
        "expand_required"
      }
      reason <- switch(decision,
        stop_bracketed = "selected value is bracketed",
        accept_null_drop = "value 0 is the predeclared off/null term",
        stop_hard_cap = "binary axis fully tested; structural cap at 1",
        "selected non-null M2 axis is at a tested edge"
      )
      if (decision == "expand_required" && is.finite(cap)) {
        evidence <- .m2_subset_matched_gain(x, h, axis, sel_row)
        if (is.finite(evidence) && evidence <= cap) {
          decision <- "stop_small_gain"
          reason <- paste0(
            "matched outward NLL gain ", format(evidence, digits = 6),
            " is <= min_nll_gain ", format(cap, digits = 6)
          )
        } else if (!is.finite(evidence)) {
          reason <- paste0(reason, "; no matched adjacent NLL comparison")
        }
      }
      if (!is.null(hard_caps) && axis %in% names(hard_caps) &&
        decision == "expand_required") {
        hc <- suppressWarnings(as.numeric(hard_caps[[axis]]))
        names(hc) <- names(hard_caps[[axis]])
        at_cap <- (is.finite(hc[["upper"]]) && edge == "upper" &&
          chosen == hc[["upper"]] && tested[length(tested)] == hc[["upper"]]) ||
          (is.finite(hc[["lower"]]) && edge == "lower" &&
            chosen == hc[["lower"]] && tested[1L] == hc[["lower"]])
        if (isTRUE(at_cap)) {
          decision <- "stop_hard_cap"
          reason <- "selected value is the declared hard cap"
        }
      }
      rows[[length(rows) + 1L]] <- data.frame(
        stage = "M2", horizon = paste0("h", h), parameter = axis,
        tested_min = tested[1L], tested_max = tested[length(tested)],
        selected_value = chosen, boundary = edge,
        decision = decision, reason = reason,
        min_nll_gain = cap, nll_gain = evidence,
        stringsAsFactors = FALSE
      )
    }
  }
  if (!length(rows)) {
    return(data.frame(
      stage = character(0), horizon = character(0), parameter = character(0),
      tested_min = numeric(0), tested_max = numeric(0),
      selected_value = numeric(0), boundary = character(0),
      decision = character(0), reason = character(0),
      min_nll_gain = numeric(0), nll_gain = numeric(0),
      stringsAsFactors = FALSE
    ))
  }
  do.call(rbind, rows)
}

.m2_subset_expand_grid <- function(x, max_specs = NULL, steps = NULL) {
  report <- .m2_subset_boundary_report(x)
  unresolved <- report[report$decision == "expand_required", , drop = FALSE]
  grid <- as.data.frame(x$grid)
  if (!nrow(unresolved)) {
    return(grid)
  }
  new_rows <- list()
  for (i in seq_len(nrow(unresolved))) {
    axis <- unresolved$parameter[i]
    if (axis == "intercept") {
      stop("Binary `intercept` axis cannot be expanded; declare a hard cap.",
        call. = FALSE
      )
    }
    h <- as.integer(sub("^h", "", unresolved$horizon[i]))
    sel_id <- as.character(x$selected_config[[paste0("h", h)]]$id[1L])
    sel_row <- grid[which(as.character(grid$id) == sel_id)[1L], , drop = FALSE]
    tested <- sort(unique(as.numeric(grid[[axis]])))
    chosen <- as.numeric(sel_row[[axis]][1L])
    explicit <- if (!is.null(steps) && axis %in% names(steps)) {
      as.numeric(steps[[axis]])
    } else {
      NULL
    }
    if (unresolved$boundary[i] == "upper") {
      spacing <- if (length(tested) >= 2L) {
        chosen - max(tested[tested < chosen])
      } else {
        1
      }
      step <- explicit %||% max(1, spacing / 2)
      value <- chosen + step
    } else {
      spacing <- if (any(tested > chosen)) {
        min(tested[tested > chosen]) - chosen
      } else {
        1
      }
      step <- explicit %||% max(1, spacing / 2)
      value <- chosen - step
    }
    value <- as.integer(round(value))
    if (value > 0 && value < 3) value <- 0
    if (isTRUE(all.equal(as.numeric(value), chosen))) {
      stop("Cannot expand M2 subset axis `", axis, "` beyond its valid domain.",
        call. = FALSE
      )
    }
    row <- sel_row
    row[[axis]] <- value
    spec <- m2_subset_spec(row)
    row$id <- spec$id
    row$intercept <- spec$intercept
    row$k_z <- spec$k_z
    row$k_u <- spec$k_u
    row$k_d <- spec$k_d
    row$enabled_count <- spec$enabled_count
    if (!as.character(row$id) %in% as.character(grid$id) &&
      !as.character(row$id) %in% as.character(vapply(
        new_rows, function(r) as.character(r$id), character(1)
      ))) {
      new_rows[[length(new_rows) + 1L]] <- row
    }
  }
  if (length(new_rows)) {
    grid <- rbind(grid, do.call(rbind, new_rows))
  }
  if (anyDuplicated(as.character(grid$id))) {
    stop("Expanded M2 subset grid has duplicate IDs.", call. = FALSE)
  }
  if (!is.null(max_specs) && nrow(grid) > as.integer(max_specs)) {
    stop(
      "Expanded M2 subset grid (", nrow(grid), " specs) exceeds max_specs (",
      as.integer(max_specs), ").",
      call. = FALSE
    )
  }
  grid
}
