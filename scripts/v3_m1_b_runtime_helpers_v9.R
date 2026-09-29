# Versioned M1-B v10 helper. The posterior implementation remains v8-identical;
# only governed provenance bindings move to timing v4 and the 12-40 detector.
source("scripts/v3_m1_b_runtime_helpers_v8.R", local = TRUE)

.M1_B_EXPECTED_HELPER <- "scripts/v3_m1_b_runtime_helpers_v9.R"
.M1_B_EXPECTED_TIMING <-
  "artifacts/v3-joint-timing-contract-v4/timing_contract_v4.csv"
.M1_B_EXPECTED_ELIG <-
  "artifacts/v3-joint-timing-contract-v4/modeling_eligibility_v4.csv"

load_m1_b_v3_artifact <- function(
    path = "artifacts/m1-b-v3-peak-v10/m1_b_v3_peak_artifact.rds") {
  if (!file.exists(path)) stop("M1-B artifact not found: ", path, call. = FALSE)
  artifact <- readRDS(path)
  validate_m1_b_v3_artifact(artifact)
  artifact
}
