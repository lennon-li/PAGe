# .page_scoring_metadata() copies data$ignition_weekF, then (when a
# timing_truth table is supplied) used to unconditionally overwrite the
# whole column with the truth-table lookup -- NA for any season absent from
# `truth`, even when `data` already carried that season's real value. The
# override then filled the erased NA with a substitute, masking the loss
# instead of exposing it. Fixed: only overwrite rows the truth table
# actually covers.

test_that(".page_scoring_metadata keeps a season's real ignition_weekF when truth omits it", {
  data <- data.frame(
    season = c("a", "b"), weekF = c(5, 5),
    ignition_weekF = c(3, 7), stringsAsFactors = FALSE
  )
  truth <- data.frame(
    season = "a", ignition_target_weekF = 2.5,
    stringsAsFactors = FALSE
  )

  meta <- PAGe:::.page_scoring_metadata(data, timing_truth = truth)

  expect_equal(meta$ignition_weekF[meta$season == "a"], 2.5)
  expect_equal(meta$ignition_weekF[meta$season == "b"], 7)
})

test_that(".page_scoring_metadata leaves ignition_weekF alone with no timing_truth", {
  data <- data.frame(
    season = "a", weekF = 5,
    ignition_weekF = 4, stringsAsFactors = FALSE
  )
  meta <- PAGe:::.page_scoring_metadata(data)
  expect_equal(meta$ignition_weekF, 4)
})
