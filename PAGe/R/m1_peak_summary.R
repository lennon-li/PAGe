#' @export
peak_summary_from_fit <- function(fit_obj, g_ref_fun, V_ab, V_td, level = 0.95) {
  u_star <- template_peak_u(g_ref_fun)
  t_peak_hat <- fit_obj$tau + (1 + fit_obj$delta) * u_star
  z <- qnorm((1 + level)/2)

  if (is_cov_ok(V_td)) {
    g_vec <- c(1, u_star)
    se_t  <- sqrt(max(drop(t(g_vec) %*% V_td %*% g_vec), 0))
    ci_t  <- t_peak_hat + c(-1, 1) * z * se_t
  } else {
    ci_t  <- c(NA_real_, NA_real_)
  }

  g_star <- g_ref_fun(u_star)
  eta_pk <- fit_obj$a + fit_obj$b * g_star
  p_pk   <- plogis(eta_pk)

  if (is.matrix(V_ab) && nrow(V_ab) == 2) {
    gab <- c(1, g_star); var_eta <- drop(t(gab) %*% V_ab %*% gab)
  } else {
    var_eta <- if (is.matrix(V_ab)) V_ab[1,1] else as.numeric(V_ab[1])
  }
  se_eta <- sqrt(pmax(0, var_eta))
  ci_eta <- eta_pk + c(-1, 1) * z * se_eta
  ci_p   <- plogis(ci_eta)

  list(u_star = u_star, t_peak = t_peak_hat, t_peak_ci = ci_t,
       p_peak = p_pk, p_peak_ci = ci_p)
}
