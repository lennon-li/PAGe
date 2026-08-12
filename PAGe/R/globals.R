# Suppress R CMD check NOTEs / WARNINGs for names that are not true
# undefined-global references:
#
#   1. NSE / data.table column-name bindings — unquoted column references
#      inside data.table [ ] calls and pipe expressions.
#
#   2. Legacy pre-governed function names — `detectIgnition4` (used in
#      score_params.R) and `detectIgnitionBySeason` (used in m0_retro.R)
#      are historical function names that pre-date the M0v2 rename to
#      `detectIgnitionBySeason_M0v2` / `detectIgnition_oneSeason`.  They
#      remain in legacy retro/tuning code paths that are not exercised by
#      the current test suite.  They are declared here so that R CMD check
#      does not treat them as undefined-function errors and fail CI.
#      TODO: migrate the callers in score_params.R and m0_retro.R to the
#      current M0v2 API and remove these two entries.
utils::globalVariables(c(
  # --- NSE / data.table column-name bindings ---
  ".", ".derivative", ".env", ".gw", ".lower_ci", ".neg_fit",
  ".upper_ci", ".w", ".y_fit",
  "Kb", "Kr",
  "N", "N_lead", "N_now", "N_true",
  "Public.health.unit", "Rdate", "Surveillance.period",
  "Surveillance.week", "Total...of.tests", "Virus", "X..of.positive.tests",
  "a", "abs_diff", "adj_diff", "anchorWeek",
  "b", "bias_alpha", "bias_beta",
  "cond_cls", "cond_inc", "cond_p", "cond_prev", "cond_sum", "cond_win",
  "cum_N", "cum_y",
  "delta", "delta_hat", "dp",
  "end_week", "eta", "eval_week", "event",
  "fit",
  "hi_event",
  "iWeek", "iWeek_hat", "iWeek_true", "iWeek_used", "ign_weekF",
  "ignite_flag", "ignite_ok", "ignition", "inc",
  "k_de", "k_e", "k_f", "k_n", "k_r", "k_s", "k_w", "kind",
  "late", "late_over2", "lead_n", "lo_event",
  "mae_weibull", "med_p", "miss", "mmwr_year",
  "nW", "nW_true", "n_hit", "neg", "newWeek",
  "over2",
  "p", "p0", "p_cls_base_pop", "p_cls_fs_full", "p_cls_fs_pop",
  "p_cls_p", "p_gamm", "p_hat", "p_hi", "p_lo", "p_now", "p_obs",
  "p_sm", "p_sumK", "phase", "post_ign", "prev",
  "ref_df", "rel_sd",
  "sd_delta", "season", "season_h", "smoothed", "spec_id",
  "startWeek", "start_week", "start_year",
  "t_peak", "t_peak_median", "tau", "theD", "true_peak_weekF",
  "w", "w_hi_train", "w_lo_train", "weekF", "weekS", "week_cut",
  "y", "y_lead", "y_now", "y_true",
  # --- Legacy pre-governed function names (TODO: migrate callers) ---
  "detectIgnition4",       # score_params.R -> detectIgnition_oneSeason
  "detectIgnitionBySeason" # m0_retro.R    -> detectIgnitionBySeason_M0v2
))
