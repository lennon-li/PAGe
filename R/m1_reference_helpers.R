#' @export
# Reference function constructors and global accessors (minimal docs)

.flualign_ref_env <- new.env(parent = emptyenv())

#' Create closures for reference link-scale mean g(u) and se{g(u)}
#' @param gam_obj fitted GAM (e.g., gam_fit$gam) on binomial link scale
#' @param grid data.frame with column newWeek over support (e.g., 1:52)
#' @return list(g_ref_fun, g_ref_safe, g_ref_mu_se)
make_reference_functions <- function(gam_obj, grid) {
  stopifnot("newWeek" %in% names(grid))
  # smoother (link scale) for integer weeks
  eta_hat <- drop(predict(gam_obj, newdata = grid, type = "link", se.fit = FALSE))
  spl <- splinefun(grid$newWeek, eta_hat, method = "natural")
  g_ref_fun <- function(u) spl(u)
  g_ref_safe <- function(u) {
    u2 <- pmax(pmin(u, max(grid$newWeek)), min(grid$newWeek))
    spl(u2)
  }
  g_ref_mu_se <- function(u) {
    nd <- data.frame(newWeek = u)
    pr <- predict(gam_obj, newdata = nd, type = "link", se.fit = TRUE)
    list(mu = drop(pr$fit), se = drop(pr$se.fit))
  }
  list(g_ref_fun = g_ref_fun, g_ref_safe = g_ref_safe, g_ref_mu_se = g_ref_mu_se)
}

#' Set reference closures globally for convenience
set_reference <- function(gam_obj, grid) {
  fns <- make_reference_functions(gam_obj, grid)
  .flualign_ref_env$g_ref_fun   <- fns$g_ref_fun
  .flualign_ref_env$g_ref_safe  <- fns$g_ref_safe
  .flualign_ref_env$g_ref_mu_se <- fns$g_ref_mu_se
  invisible(TRUE)
}

#' Get the current reference closures
get_reference <- function() {
  list(
    g_ref_fun   = get("g_ref_fun",   envir = .flualign_ref_env, inherits = FALSE),
    g_ref_safe  = get("g_ref_safe",  envir = .flualign_ref_env, inherits = FALSE),
    g_ref_mu_se = get("g_ref_mu_se", envir = .flualign_ref_env, inherits = FALSE)
  )
}

# Shims exported so user code works
g_ref_fun   <- function(u) get("g_ref_fun",   envir = .flualign_ref_env, inherits = FALSE)(u)
g_ref_safe  <- function(u) get("g_ref_safe",  envir = .flualign_ref_env, inherits = FALSE)(u)
g_ref_mu_se <- function(u) get("g_ref_mu_se", envir = .flualign_ref_env, inherits = FALSE)(u)

# Convenience: fit GAM and set reference in one step
#' Fit reference GAM and set closures
#' @param df data.frame(season, newWeek, y, neg)
#' @param k basis dimension for s(newWeek)
fit_reference_gam <- function(df, k = 12) {
  stopifnot(all(c("newWeek","y","neg","season") %in% names(df)))
  fm <- gamm4::gamm4(cbind(y, neg) ~ s(newWeek, k = k),
                      random = ~(1|season), data = df,
                      family = binomial(), method = "REML")
  grid <- data.frame(newWeek = sort(unique(df$newWeek)))
  set_reference(fm$gam, grid)
  invisible(fm)
}
