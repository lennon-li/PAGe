\name{verify_promotion_evidence}
\alias{verify_promotion_evidence}
\title{Verify Artifact-Bound Holdout Promotion Evidence}
\usage{
verify_promotion_evidence(
  bundle,
  manifest,
  data_path,
  candidate_path,
  incumbent_path,
  bundle_path,
  holdout_season = "2025-26",
  kit_compatibility = c("strict", "legacy_m2")
)
}
\arguments{
\item{bundle}{Saved \code{page_holdout_decision_bundle} object.}

\item{manifest}{Validated disclosure-safe acceptance result manifest.}

\item{data_path}{Path to the authorized surveillance data artifact.}

\item{candidate_path}{Path to the evaluated candidate kit artifact.}

\item{incumbent_path}{Path to the evaluated incumbent kit artifact.}

\item{bundle_path}{Path to the saved decision bundle artifact.}

\item{holdout_season}{Expected holdout season.}

\item{kit_compatibility}{Identity mode for the incumbent kit. The default
\code{"strict"} requires \code{m2_production}; \code{"legacy_m2"} explicitly
permits a legacy \code{m2} field with a warning. The candidate kit must always
use the canonical identity.}
}
\value{
A \code{page_verified_promotion_evidence} object accepted by
\code{train_pipeline()} for holdout release.
}
\description{
Verifies a saved acceptance decision bundle and disclosure-safe manifest
against the authorized data, candidate kit, incumbent kit, and decision bundle
files that they bind by SHA-256. Only a passing promotion report using PAGe's
locked thresholds can produce release evidence.
}
\details{
The returned S3 class is a transport marker, not a cryptographic capability:
R classes can be forged. The artifact reads and SHA-256 checks performed by
this function are the safety boundary. Governed workflows should construct
the object immediately before calling \code{train_pipeline()} and retain the
verified artifacts.
}
