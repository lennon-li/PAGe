m1v2_pipeline_test_truth <- function(data, k = 6L, grid_step = .05) {
  seasons <- sort(unique(data$season))
  do.call(rbind, lapply(seasons, function(s) {
    fit <- retrospective_gam_peak_truth(data, season = s, k = k, grid_step = grid_step)
    data.frame(season = s, peak_week_decimal = fit$peak_week_decimal)
  }))
}

m1v2_pipeline_make_season <- function(season, peak, amp = .22) {
  w <- 1:34
  p <- amp * exp(-0.5 * ((w - peak) / 3)^2)
  N <- rep(1800L, length(w))
  data.frame(season = season, weekF = w, y = round(N * p), N = N)
}

m1v2_pipeline_activation_table <- function(seasons, origin = 10, decimal = 9.6) {
  cmp <- data.frame(
    season = seasons, iWeek_hat = origin, iWeek_hatF = decimal,
    detection_failed = FALSE, stringsAsFactors = FALSE
  )
  folds <- setNames(lapply(seasons, function(ss) list(
    season = ss, best_params = list(),
    compare = cmp[cmp$season == ss, c("season", "iWeek_hat", "iWeek_hatF"), drop = FALSE]
  )), seasons)
  m1_v2_activation_table_from_m0_loso(structure(list(
    folds = folds, compare = cmp, context_id = paste0("test-", paste(seasons, collapse = "-"))
  ), class = c("page_m0_loso_result", "list")))
}

test_that("build_m1_v2_timing returns governed timing artifact", {
  hist <- rbind(
    m1v2_pipeline_make_season("s1",16,.20),
    m1v2_pipeline_make_season("s2",17,.24),
    m1v2_pipeline_make_season("s3",18,.18),
    m1v2_pipeline_make_season("s4",16.5,.26),
    m1v2_pipeline_make_season("s5",17.5,.21)
  )
  truth <- m1v2_pipeline_test_truth(hist)
  activation <- m1v2_pipeline_activation_table(truth$season)
  stage <- build_m1_v2_timing(
    hist, truth, activation,
    k = 6L, grid_step = .05, tau_step = .2,
    calibration_origins = 2L, calibration_candidate_step = .4,
    passage_candidate_step = .4
  )
  expect_s3_class(stage, "page_m1_v2_stage")
  expect_s3_class(stage$library, "page_m1_v2_library")
  expect_s3_class(stage$calibrator, "page_m1_v2_calibrator")
  expect_s3_class(stage$passage_policy, "page_m1_v2_passage_policy")
  expect_true(stage$passage_policy$selected$high_threshold >= .95)
  expect_true(is.character(stage$artifact_id) && nzchar(stage$artifact_id))
  expect_identical(stage$output_contract$m2_handoff_version, "m1-v2-to-m2-v1")

  m0_legacy <- list(
    best_params = list(cls_thr=.2,p_thr=.01,prev_thr=.01,n_consec=3L,L=2L,eps=0,
                       K_sum=4L,p_sum_thr=.04,N_req=3L,w_min=13L,w_max=30L),
    manual_labels = setNames(rep(10L,length(truth$season)),truth$season),
    flag_args = list(p_thresh=.01)
  )
  m1_legacy <- list(
    ref = list(anchorWeek=20L,pred_df=data.frame(newWeek=1:52,fit=0)),
    hyper = list(), aligned_train = hist,
    m1_params = .default_m1_params(), seasons_used = truth$season
  )
  m2_legacy <- list(
    fit = structure(list(model=data.frame(logit_f_eff=0,z_ema=0,lead=factor("h1"))),class="gam"),
    spec = list(k_f=4L,k_n=0L,k_de=0L,k_r=0L,k_sp=0L,bias_alpha=.05,bias_beta=0),
    feature_ranges=list(),m1_train_preds=data.frame(),training_seasons=truth$season
  )
  kit <- assemble_kit(m0_legacy,m1_legacy,m2_legacy,m1_v2=stage)
  expect_identical(kit$m1_v2,stage)
  expect_identical(kit$m1_train_preds,m2_legacy$m1_train_preds)
})


test_that("custom M1-v2 amplitude grid propagates through nested calibration and passage fits", {
  hist <- rbind(
    m1v2_pipeline_make_season("b1",17,.025),
    m1v2_pipeline_make_season("b2",18,.040),
    m1v2_pipeline_make_season("b3",16,.055),
    m1v2_pipeline_make_season("b4",17.5,.070),
    m1v2_pipeline_make_season("b5",18.5,.090)
  )
  truth <- m1v2_pipeline_test_truth(hist)
  activation <- m1v2_pipeline_activation_table(truth$season, origin = 11, decimal = 10.6)
  grid <- seq(.005,.12,by=.005)
  stage <- build_m1_v2_timing(
    hist, truth, activation,
    k=6L, grid_step=.05, tau_step=.2, amplitude_grid=rev(grid),
    calibration_origins=1L, calibration_candidate_step=.4,
    passage_candidate_step=.4
  )
  expect_equal(stage$config$amplitude_grid, grid)
  expect_equal(stage$library$config$amplitude_grid, grid)

  cal_row <- stage$calibrator$inner_predictions[1,]
  heldout <- cal_row$season[[1]]
  inner_seasons <- setdiff(truth$season, heldout)
  inner_lib <- fit_m1_v2_library(
    hist[hist$season %in% inner_seasons,],
    truth[truth$season %in% inner_seasons,],
    k=6L,grid_step=.05,tau_step=.2,amplitude_grid=grid
  )
  held <- hist[hist$season==heldout,]
  cal_fit <- m1_v2_peak_posterior(
    inner_lib,held,activation_week=10.6,
    origin_week=cal_row$origin_week[[1]],candidate_step=.4
  )
  expect_equal(cal_row$prediction_peak_mean, cal_fit$summary$peak_mean[[1]], tolerance=1e-12)

  pass_row <- stage$passage_policy$inner_history[1,]
  expect_identical(pass_row$season[[1]], heldout)
  pass_fit <- m1_v2_passage_posterior(
    inner_lib,held,activation_week=10.6,
    origin_week=pass_row$origin_week[[1]],candidate_step=.4
  )
  expect_equal(pass_row$prob_peak_passed, pass_fit$prob_peak_passed[[1]], tolerance=1e-12)
})

test_that("run_m1_v2_timing emits sequential timing and M2 handoff", {
  hist <- rbind(
    m1v2_pipeline_make_season("s1",16,.20),
    m1v2_pipeline_make_season("s2",17,.24),
    m1v2_pipeline_make_season("s3",18,.18),
    m1v2_pipeline_make_season("s4",16.5,.26),
    m1v2_pipeline_make_season("s5",17.5,.21)
  )
  truth <- m1v2_pipeline_test_truth(hist)
  activation <- m1v2_pipeline_activation_table(truth$season)
  stage <- build_m1_v2_timing(
    hist, truth, activation,
    k = 6L, grid_step = .05, tau_step = .2,
    calibration_origins = 2L, calibration_candidate_step = .4,
    passage_candidate_step = .4
  )
  current <- m1v2_pipeline_make_season("heldout",17,.23)
  current <- current[current$weekF <= 18,]
  m0 <- list(iWeek_locked = 10L, iWeek_lockedF = 9.6)
  out <- run_m1_v2_timing(list(m1_v2 = stage), current, m0, verbose = FALSE)

  expect_true(nrow(out$timing_df) > 0)
  expect_identical(out$m2_handoff$version, "m1-v2-to-m2-v1")
  expect_identical(out$m2_handoff$m1_v2_artifact_id, stage$artifact_id)
  expect_true(out$m2_handoff$state %in% c("active", "future_only", "passage_only", "passage_confirmed", "unavailable"))
  expect_true(all(c(
    "raw_peak_posterior", "raw_peak_mean", "calibrated_peak_mean", "calibrated_mean_is_future", "peak_q05", "peak_q95",
    "prob_peak_passed", "prob_peak_within_1w", "prob_peak_within_2w",
    "prob_peak_within_3w", "locked_peak_week"
  ) %in% names(out$m2_handoff)))
})

test_that("run_m1_v2_timing emits elapsed/remaining timing quantities", {
  hist <- rbind(
    m1v2_pipeline_make_season("s1",16,.20),
    m1v2_pipeline_make_season("s2",17,.24),
    m1v2_pipeline_make_season("s3",18,.18),
    m1v2_pipeline_make_season("s4",16.5,.26),
    m1v2_pipeline_make_season("s5",17.5,.21)
  )
  truth <- m1v2_pipeline_test_truth(hist)
  activation <- m1v2_pipeline_activation_table(truth$season)
  stage <- build_m1_v2_timing(
    hist, truth, activation,
    k = 6L, grid_step = .05, tau_step = .2,
    calibration_origins = 2L, calibration_candidate_step = .4,
    passage_candidate_step = .4
  )
  current <- m1v2_pipeline_make_season("heldout",17,.23)
  current <- current[current$weekF <= 18,]
  m0 <- list(iWeek_locked = 10L, iWeek_lockedF = 9.6)
  out <- run_m1_v2_timing(list(m1_v2 = stage), current, m0, verbose = FALSE)

  expect_true(all(c(
    "weeks_elapsed_since_activation", "weeks_to_calibrated_peak"
  ) %in% names(out$timing_df)))
  expect_true(all(c(
    "weeks_elapsed_since_activation", "weeks_to_calibrated_peak"
  ) %in% names(out$m2_handoff)))

  handoff <- out$m2_handoff
  expect_equal(
    handoff$weeks_elapsed_since_activation,
    handoff$asof_boundary - handoff$activation_week
  )
  if (!is.na(handoff$calibrated_peak_mean)) {
    expect_equal(
      handoff$weeks_to_calibrated_peak,
      handoff$calibrated_peak_mean - handoff$asof_boundary
    )
  } else {
    expect_true(is.na(handoff$weeks_to_calibrated_peak))
  }

  # Elapsed timing is monotone nondecreasing across the sequential walk.
  expect_true(all(diff(out$timing_df$weeks_elapsed_since_activation) >= -1e-8))

  validate_m1_v2_handoff(handoff)
})

test_that("run_m1_v2_timing is backward compatible when kit has no M1-v2", {
  out <- run_m1_v2_timing(
    list(),
    m1v2_pipeline_make_season("heldout",17,.23),
    list(iWeek_locked = 10L, iWeek_lockedF = 9.6),
    verbose = FALSE
  )
  expect_identical(out$status, "unavailable")
  expect_identical(out$reason, "kit_missing_m1_v2")
  expect_null(out$m2_handoff)
})


test_that("run_m1_v2_timing fails hard when current season is in training artifact", {
  hist <- rbind(
    m1v2_pipeline_make_season("s1",16,.20),
    m1v2_pipeline_make_season("s2",17,.24),
    m1v2_pipeline_make_season("s3",18,.18),
    m1v2_pipeline_make_season("s4",16.5,.26),
    m1v2_pipeline_make_season("s5",17.5,.21)
  )
  truth <- m1v2_pipeline_test_truth(hist)
  activation <- m1v2_pipeline_activation_table(truth$season)
  stage <- build_m1_v2_timing(
    hist, truth, activation,
    k = 6L, grid_step = .05, tau_step = .2,
    calibration_origins = 2L, calibration_candidate_step = .4,
    passage_candidate_step = .4
  )
  expect_error(
    run_m1_v2_timing(
      list(m1_v2 = stage),
      hist[hist$season == "s1" & hist$weekF <= 18, ],
      list(iWeek_locked = 10L, iWeek_lockedF = 9.6),
      verbose = FALSE
    ),
    "present in the M1-v2 training artifact"
  )
})


test_that("run_m1_v2_timing verifies governed kit identity on direct calls", {
  hist <- rbind(
    m1v2_pipeline_make_season("s1",16,.20),
    m1v2_pipeline_make_season("s2",17,.24),
    m1v2_pipeline_make_season("s3",18,.18),
    m1v2_pipeline_make_season("s4",16.5,.26),
    m1v2_pipeline_make_season("s5",17.5,.21)
  )
  truth <- m1v2_pipeline_test_truth(hist)
  activation <- m1v2_pipeline_activation_table(truth$season)
  stage <- build_m1_v2_timing(hist,truth,activation,k=6L,grid_step=.05,tau_step=.2,
                              calibration_origins=2L,calibration_candidate_step=.4,
                              passage_candidate_step=.4)
  badkit <- list(m1_v2=stage,governance_id="base",m1_v2_governance_id="wrong")
  current <- m1v2_pipeline_make_season("heldout",17,.23)
  expect_error(
    run_m1_v2_timing(badkit,current[current$weekF<=18,],
                     list(iWeek_locked=10L,iWeek_lockedF=9.6),verbose=FALSE),
    "governance identity integrity check failed"
  )
})


test_that("M1-v2 stage artifact identity binds training metadata and handoff contract", {
  hist <- rbind(
    m1v2_pipeline_make_season("s1",16,.20),
    m1v2_pipeline_make_season("s2",17,.24),
    m1v2_pipeline_make_season("s3",18,.18),
    m1v2_pipeline_make_season("s4",16.5,.26),
    m1v2_pipeline_make_season("s5",17.5,.21)
  )
  truth <- m1v2_pipeline_test_truth(hist)
  activation <- m1v2_pipeline_activation_table(truth$season)
  stage <- build_m1_v2_timing(hist,truth,activation,k=6L,grid_step=.05,tau_step=.2,
                              calibration_origins=2L,calibration_candidate_step=.4,
                              passage_candidate_step=.4)
  bad <- stage
  bad$output_contract$m2_handoff_version <- "tampered"
  expect_false(identical(stage$artifact_id,.m1_v2_stage_artifact_id(bad)))
  bad2 <- stage
  bad2$training_seasons <- rev(bad2$training_seasons)
  # Training-season identity is canonicalized by sort, so ordering alone is benign.
  expect_identical(stage$artifact_id,.m1_v2_stage_artifact_id(bad2))
  bad3 <- stage
  bad3$training_seasons <- bad3$training_seasons[-1]
  expect_false(identical(stage$artifact_id,.m1_v2_stage_artifact_id(bad3)))
})
