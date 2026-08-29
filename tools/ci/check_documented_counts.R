#!/usr/bin/env Rscript
# =============================================================================
# Counts stated in prose must match the thing that produces them
# =============================================================================
# A number in a sentence is a claim about the repository, and it decays the
# moment the repository moves. This file gates the counts that have a live,
# cheap, machine-checkable source.
#
# It exists because of a same-day demonstration. NEWS.md said
#
#     "New tools/ci/check_workflow_syntax.R parses the 114 bash blocks in the
#      workflows"
#
# and within four hours of that sentence being written the number was 126 --
# invalidated by the author's own later commits wiring three new gates into two
# workflows. Nobody edits a NEWS entry from this morning when adding a CI step.
#
# DELIBERATELY NOT GATED HERE, and why, so the omissions are choices rather than
# oversights:
#
#   "231 tract-vector identities"  -- the source is check_denominator_identity.R,
#       which reads eleven ACS vintages and takes minutes. Re-running it to check
#       a sentence would make this gate the slowest in the suite. The number is
#       printed by that tool on every nightly, where it is visible.
#   "4,050 origins", "79,398 rows"  -- the source is mufflyaccess's
#       ssot_sources.json, which is only present when that package is installed.
#       Checked when it is available and skipped when it is not; a gate that
#       fails on a missing optional dependency is a gate people disable.
#   "3,909 origins", "141 missing", "44 physician locations"  -- these describe a
#       directory that no longer exists on any machine. They are history, not
#       claims about the present, and nothing can check them. That is exactly why
#       the hashes were pinned.
#
# Usage: Rscript tools/ci/check_documented_counts.R
if (!file.exists("DESCRIPTION")) { cat("::error::run from the repository root\n"); quit(status = 1L) }

DOCS <- c("README.md", "NEWS.md", "docs/APPENDIX_FROZEN_ISOCHRONE_SSOT.md")
DOCS <- DOCS[file.exists(DOCS)]
fail <- character(0)
bad  <- function(...) fail <<- c(fail, paste0(...))
cat("documented counts\n\n")

# num() tolerates the thousands separators these documents use.
as_int <- function(x) as.integer(gsub("[^0-9]", "", x))

verify <- function(rx, want, label) {
  seen <- 0L
  for (f in DOCS) {
    ln <- readLines(f, warn = FALSE)
    hits <- grep(rx, ln, perl = TRUE)
    for (i in hits) {
      m <- regmatches(ln[i], regexec(rx, ln[i], perl = TRUE))[[1]]
      if (length(m) < 2L) next
      got <- as_int(m[2]); seen <- seen + 1L
      ok <- identical(got, want)
      cat(sprintf("  %-42s %6d  actual %6d  %s\n",
                  paste0(basename(f), ":", i), got, want, if (ok) "ok" else "STALE"))
      if (!ok) bad(f, ":", i, " says ", got, " ", label, "; the repository has ", want)
    }
  }
  if (!seen) cat(sprintf("  %-42s %s\n", "(not stated)", label))
  invisible(seen)
}

# ---- 1. bash blocks in the workflows ----------------------------------------
# Ask the tool that owns the definition rather than re-implementing its parser
# here; two counters that disagree would be worse than none.
out <- tryCatch(system2("Rscript", "tools/ci/check_workflow_syntax.R",
                        stdout = TRUE, stderr = TRUE), error = function(e) character(0))
m <- regmatches(out, regexpr("blocks parsed:[[:space:]]*[0-9]+", out))
if (length(m)) {
  verify("([0-9,]+) bash blocks", as_int(m[1]), "bash blocks")
} else {
  bad("could not read the block count from check_workflow_syntax.R")
}

# ---- 2. cells in the age-matched panel ---------------------------------------
panel <- "artifacts/2sfca/agematched_panel/age_matched_panel.csv"
if (file.exists(panel)) {
  n <- nrow(utils::read.csv(panel, stringsAsFactors = FALSE))
  # "cells" is overloaded: the panel has 154 of them, and the supply-loss
  # narrative says "12 of 14 cells" about something else entirely. Matching both
  # produced six false positives on the first run. A gate that cries wolf is one
  # people learn to skip, so exclude the "N of M cells" form explicitly.
  # Both lookbehinds are load-bearing. Without (?<!of ) this matched "12 of 14
  # cells", a sentence about the supply-loss defect rather than the panel size.
  # Without (?<![0-9,]) the engine simply restarted one digit to the right and
  # matched the "4" of "14" -- the fix for the first false positive silently
  # produced a second, more confusing one that reported "says 4".
  verify("(?<!of )(?<![0-9,])([0-9,]+) cells", n, "cells in the panel")
  prov <- "artifacts/2sfca/agematched_panel/provenance.json"
  if (file.exists(prov) && requireNamespace("jsonlite", quietly = TRUE)) {
    pc <- jsonlite::fromJSON(prov)$n_cells
    cat(sprintf("  %-42s %6d  actual %6d  %s\n", "provenance.json n_cells",
                as.integer(pc), n, if (identical(as.integer(pc), n)) "ok" else "STALE"))
    if (!identical(as.integer(pc), n))
      bad("provenance.json records n_cells=", pc, " but the panel has ", n, " rows")
  }
} else bad("the panel is missing: ", panel)

# ---- 3. SSOT counts, when mufflyaccess is installed --------------------------
src <- tryCatch(system.file("extdata", "ssot", "ssot_sources.json",
                            package = "mufflyaccess"), error = function(e) "")
if (nzchar(src) && file.exists(src) && requireNamespace("jsonlite", quietly = TRUE)) {
  j <- jsonlite::fromJSON(src)
  verify("([0-9,]+) origins(?![^.]*incomplete)", as.integer(j$frozen_isochrones$n_origins),
         "frozen origins")
  verify("([0-9,]+) rows", as.integer(j$abog_refresh$n_rows), "rows in the ABOG registry")
} else {
  cat("  mufflyaccess ssot_sources.json unavailable -- SSOT counts skipped\n")
}

cat("\n")
if (length(fail)) {
  message("FAIL: a count stated in prose no longer matches the repository:")
  for (f in fail) message("  - ", f)
  message("\n  These decay silently. The workflow block count went stale within four",
          "\n  hours of being written, invalidated by the same author's later commits.")
  quit(status = 1L, save = "no")
}
cat("every gated count matches\n")
