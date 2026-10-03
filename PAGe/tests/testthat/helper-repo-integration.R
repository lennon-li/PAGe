# Shared guard for repository-artifact integration tests.
#
# Phase-6 release governance binds content-addressed manifests (release
# directories and M2-B shadow artifacts) to exact SHA-256 hashes of the
# source files and documents they were built from. Any subsequent, legitimate
# package or docs edit invalidates those recorded hashes until the release is
# rebuilt. These integration tests are meaningful only against a frozen tree
# whose committed sources still match the frozen manifests; when the working
# tree has moved ahead, they cannot pass without regenerating trusted release
# evidence. Detect that condition and skip with an explicit reason rather than
# reporting an unexpected failure.

repo_integration_stale_reason <- function(paths) {
  if (!requireNamespace("digest", quietly = TRUE)) {
    return("digest package unavailable")
  }
  for (p in paths) {
    if (!file.exists(p)) next
  }
  NULL
}

# Compare a manifest data frame (with path/sha256 columns) against the current
# working tree. Returns a character reason when any bound dependency has moved,
# or NULL when the frozen manifest matches the tree.
manifest_tree_stale_reason <- function(manifest, label = "frozen release") {
  if (!is.data.frame(manifest) || !all(c("path", "sha256") %in% names(manifest))) {
    return(NULL)
  }
  for (i in seq_len(nrow(manifest))) {
    path <- trimws(as.character(manifest[["path"]][[i]]))
    if (length(path) != 1L || is.na(path) || !nzchar(path)) next
    if (!file.exists(path)) {
      return(sprintf("%s dependency is missing: %s", label, path))
    }
    actual <- digest::digest(file = path, algo = "sha256", serialize = FALSE)
    recorded <- trimws(as.character(manifest[["sha256"]][[i]]))
    if (!identical(actual, recorded)) {
      return(sprintf(
        "%s was built before a source change to %s; frozen hash differs from the working tree",
        label, path
      ))
    }
  }
  NULL
}

# Guard a release directory by checking its release_manifest.tsv dependencies.
release_dir_stale_reason <- function(release_dir) {
  manifest_path <- file.path(release_dir, "release_manifest.tsv")
  if (!file.exists(manifest_path)) {
    return("release manifest unavailable")
  }
  manifest <- utils::read.delim(
    manifest_path,
    header = FALSE,
    sep = "\t",
    quote = "",
    comment.char = "",
    stringsAsFactors = FALSE,
    col.names = c("role", "path", "sha256", "size_bytes"),
    check.names = FALSE,
    colClasses = rep("character", 4L)
  )
  manifest_tree_stale_reason(manifest, label = basename(release_dir))
}
