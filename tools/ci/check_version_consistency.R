#!/usr/bin/env Rscript
# =============================================================================
# One version, seven files
# =============================================================================
# DESCRIPTION is the authority. Six other files restate it, and nothing until now
# checked that they agree:
#
#   DESCRIPTION      Version:
#   CITATION.cff     version:            <- what a citing author copies
#   CITATION.bib     version = {} and note
#   .zenodo.json     version             <- what the DOI records
#   codemeta.json    version
#   README.md        the version badge   <- what a reader sees first
#   NEWS.md          the newest release heading
#
# The failure this prevents is not cosmetic. A tagged release whose CITATION.cff
# still says the previous version means every citation of this work names the
# wrong artifact, and Zenodo mints a DOI against a version string that does not
# match the tag. Nobody notices, because each file is individually plausible.
#
# It is the same hand-maintained-number problem as the audit's gate count and the
# supply-loss figures, and it was found the same way: by bumping 0.1.0 to 0.2.0
# and noticing that seven files needed it and no gate would have said so.
#
# NEWS is checked as "the newest release heading matches", not "some heading
# mentions the version" -- a stale heading for the CURRENT version is exactly the
# thing that looks right.
#
# Usage: Rscript tools/ci/check_version_consistency.R
if (!file.exists("DESCRIPTION")) { cat("::error::run from the repository root\n"); quit(status = 1L) }

want <- unname(read.dcf("DESCRIPTION", fields = "Version")[1, 1])
if (is.na(want)) { cat("::error::DESCRIPTION has no Version field\n"); quit(status = 1L) }
cat("version consistency\n  DESCRIPTION declares ", want, "\n\n", sep = "")

fail <- character(0)
bad  <- function(...) fail <<- c(fail, paste0(...))

check <- function(file, rx, label) {
  if (!file.exists(file)) { bad(file, " is missing"); return(invisible()) }
  txt <- paste(readLines(file, warn = FALSE), collapse = "\n")
  m <- regmatches(txt, regexec(rx, txt, perl = TRUE))[[1]]
  if (length(m) < 2L) {
    bad(file, ": could not find the version (", label,
        "). It was reworded, or the file no longer states one: ", rx)
    return(invisible())
  }
  got <- m[2]
  cat(sprintf("  %-16s %-22s %s\n", basename(file), got,
              if (identical(got, want)) "ok" else "MISMATCH"))
  if (!identical(got, want))
    bad(file, " says ", got, " where DESCRIPTION says ", want, " (", label, ")")
}

V <- "([0-9]+[.-][0-9.-]+)"
check("CITATION.cff",  paste0("(?m)^version:[[:space:]]*", V),            "version:")
check("CITATION.bib",  paste0("version[[:space:]]*=[[:space:]]*\\{", V, "\\}"), "version = {}")
check("CITATION.bib",  paste0("R package version ", V),                   "note field")
check(".zenodo.json",  paste0('"version"[[:space:]]*:[[:space:]]*"', V, '"'), "version")
check("codemeta.json", paste0('"version"[[:space:]]*:[[:space:]]*"', V, '"'), "version")
check("README.md",     paste0("version-", V, "-informational"),           "version badge")

# NEWS: the NEWEST release heading must be this version. Scanning the whole file
# would pass on a stale heading, because the previous release is still in there.
news <- readLines("NEWS.md", warn = FALSE)
fence <- cumsum(grepl("^\\s*```", news)) %% 2L
h1 <- news[grepl("^#[[:space:]]", news) & fence == 0L]
if (!length(h1)) {
  bad("NEWS.md has no level-1 headings")
} else {
  m <- regmatches(h1[1], regexec(paste0("[[:space:]]", V), h1[1], perl = TRUE))[[1]]
  got <- if (length(m) >= 2L) m[2] else "(none)"
  cat(sprintf("  %-16s %-22s %s\n", "NEWS.md", got, if (identical(got, want)) "ok" else "MISMATCH"))
  if (!identical(got, want))
    bad("NEWS.md's newest release heading is \"", h1[1], "\" but DESCRIPTION says ", want)
}

# ---- tag releases: the ref must name the version being released ---------------
# Deliberately NOT checked on ordinary pushes or pull requests, where there is no
# tag and the question is meaningless. This closes the one failure the six file
# checks above cannot see: all seven files agree on 0.2.1 and somebody tags the
# commit v0.2.0 or v0.2.2. Every artifact then says one thing and the immutable
# ref says another, which is the version of this problem that cannot be fixed by
# editing a file afterwards -- a pushed tag is what people cite and archive.
#
# Runs when GITHUB_REF_TYPE=tag (set by GitHub on tag-triggered workflows), or
# locally via --tag=v0.2.0.
tag <- sub("^--tag=", "", grep("^--tag=", commandArgs(trailingOnly = TRUE), value = TRUE))
if (!length(tag) && identical(Sys.getenv("GITHUB_REF_TYPE"), "tag"))
  tag <- Sys.getenv("GITHUB_REF_NAME")

if (length(tag) && nzchar(tag)) {
  expect <- paste0("v", want)
  cat(sprintf("  %-16s %-22s %s\n", "git tag", tag, if (identical(tag, expect)) "ok" else "MISMATCH"))
  if (!identical(tag, expect))
    bad("the tag is ", tag, " but DESCRIPTION says ", want, ", so the release should be ", expect)
} else {
  cat("  git tag          (not a tag build)      skipped\n")
}

cat("\n")
if (length(fail)) {
  message("FAIL: the version is not stated consistently:")
  for (f in fail) message("  - ", f)
  message("\n  DESCRIPTION is the authority. A release whose CITATION.cff names the",
          "\n  previous version makes every citation point at the wrong artifact,",
          "\n  and Zenodo mints a DOI against a string that does not match the tag.")
  quit(status = 1L, save = "no")
}
cat("every file agrees on ", want, "\n", sep = "")
