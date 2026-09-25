gov_test_root <- if (file.exists("PAGe/R/m2_v2_c2_governed.R")) "PAGe" else "../.."
source(file.path(gov_test_root, "R", "m2_v2_research.R"), local = TRUE)
source(file.path(gov_test_root, "R", "m2_v2_c2_governed.R"), local = TRUE)

make_governed_c2_fixture <- function() {
  seasons <- paste0(2012:2016, "-", sprintf("%02d", 13:17))
  ledger <- expand.grid(
    season = seasons, type = c("A", "B"), horizon = 1:2,
    KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE
  )
  ledger$N_target <- 1000
  ledger$p_star <- ifelse(ledger$type == "A", .04, .025)
  ledger$logit_current <- qlogis(ledger$p_star)
  ledger$growth1 <- sin(seq_len(nrow(ledger)) / 5) / 10
  ledger$growth2 <- cos(seq_len(nrow(ledger)) / 7) / 12
  ledger$y_target <- round(ledger$N_target * plogis(
    ledger$logit_current + .05 * ledger$growth1 + .03 * ledger$growth2 +
      .02 * (ledger$horizon == 2L)
  ))
  ledger$denominator_regime <- "historical_shared_flu_test_proxy"
  shapes <- expand.grid(
    season = seasons, type = c("A", "B"), tau = -5:5,
    KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE
  )
  shapes$p_norm <- plogis(-2 + .15 * shapes$tau)
  fit <- m2_v2_c2_fit(ledger, shapes, seasons, list(source = paste(rep("a", 64), collapse = "")))
  train_ev <- data.frame(season = seasons, prior_seasons = vapply(seq_along(seasons), function(i) {
    paste(seasons[seq_len(i - 1L)], collapse = ";")
  }, character(1)))
  gov <- new_m2_v2_c2_governed_artifact(
    fit,
    provenance = list(
      source_hashes = list(source = strrep("a", 64)),
      training_data_sha256 = strrep("b", 64), shape_data_sha256 = strrep("c", 64)
    ),
    training_evidence = train_ev
  )
  list(artifact = gov, seasons = seasons)
}

testthat::test_that("governed C2 identity binds fixed shrinkage, provenance, and output contract", {
  fx <- make_governed_c2_fixture()
  a <- fx$artifact
  testthat::expect_match(a$artifact_id, "^m2v2g_[0-9a-f]{64}$")
  testthat::expect_identical(a$contract$shrinkage$version, "c2-fixed-shrinkage-v1")
  testthat::expect_identical(a$contract$b_gate_policy$status, "closed_pending_review")
  testthat::expect_silent(validate_m2_v2_c2_governed_artifact(a))
  bad <- a
  bad$contract$output_contract$version <- "changed"
  testthat::expect_error(validate_m2_v2_c2_governed_artifact(bad), "mutated governed")
})

testthat::test_that("governed C2 rejects chronological timing leakage", {
  fx <- make_governed_c2_fixture()
  ev <- data.frame(season = "2016-17", prior_seasons = "2012-13;2013-14;2014-15;2016-17")
  testthat::expect_error(new_m2_v2_c2_governed_artifact(
    fx$artifact$fit,
    provenance = list(
      source_hashes = list(source = strrep("a", 64)),
      training_data_sha256 = strrep("b", 64), shape_data_sha256 = strrep("c", 64)
    ),
    training_evidence = ev
  ), "target-season leakage")
})

testthat::test_that("governed runtime keeps B +1 exact and B +2 closed until reviewed gate opens", {
  fx <- make_governed_c2_fixture()
  weekly <- data.frame(
    season = "future", weekF = 21:24,
    y_A = c(25, 30, 35, 40), N_A = 1000, p_A = c(.025, .03, .035, .04),
    y_B = c(18, 20, 22, 24), N_B = 400, p_B = c(.045, .05, .055, .06),
    denominator_regime = "orvt_type_specific"
  )
  b <- new_m2_v2_b_soft_timing_handoff("future", 24, 27,
    source_artifact_id = "b-timing-v1"
  )
  closed <- run_m2_v2_c2_governed_runtime(fx$artifact, weekly, 24, b_handoff = b)
  p <- closed$predictions
  b1 <- p$type == "B" & p$horizon == 1L
  b2 <- p$type == "B" & p$horizon == 2L
  testthat::expect_identical(closed$status, "governed_m2_v2_c2_shadow")
  testthat::expect_identical(p$pred_selected[b1], p$pred_baseline[b1])
  testthat::expect_identical(p$pred_selected[b2], p$pred_baseline[b2])
  testthat::expect_identical(p$fallback_reason[b2], "b_gate_closed_pending_review")
  review_path <- tempfile(fileext = ".json")
  jsonlite::write_json(list(
    status = "reviewed_open", decision = "open",
    policy_version = "b-epidemic-gate-5pct-v1",
    review_id = "review-001"
  ), review_path, auto_unbox = TRUE)
  on.exit(unlink(review_path), add = TRUE)
  opened <- new_m2_v2_b_gate_review(review_path)
  active <- run_m2_v2_c2_governed_runtime(fx$artifact, weekly, 24,
    b_handoff = b,
    b_gate_review = opened
  )
  p2 <- active$predictions
  b2 <- p2$type == "B" & p2$horizon == 2L
  testthat::expect_true(p2$c2_applied[b2])
  testthat::expect_identical(p2$b_gate_review_id[b2], "review-001")
})
