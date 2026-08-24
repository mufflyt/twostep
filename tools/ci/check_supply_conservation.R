#!/usr/bin/env Rscript
# =============================================================================
# Supply conservation: no origin may enter E2SFCA without a catchment
# =============================================================================
# The scientific requirement, stated once: for every year x subspecialty cell,
# the supply entering E2SFCA must equal the supply assigned to isochrone origins.
# Zero silently dropped origins.
#
# This exists because it already happened. A local age-matched run used an
# isochrone set that did not cover five of 516 gynecologic-oncology origins.
# Those origins carried 7 of 890 supply units, the runner was configured to DROP
# unmatched supply, and the result came out 0.786% below the frozen analysis --
# a plausible number, reported as success, with the loss visible only in a column
# nobody was comparing.
#
# The engine now fails closed (unmatched_supply_policy = "error") and names the
# offending coord_ids. This is the artifact-level backstop: any results table
# that records origin counts must show them equal.
#
# Usage: Rscript tools/ci/check_supply_conservation.R [results.csv ...]
args <- commandArgs(trailingOnly = TRUE)
if (!file.exists("DESCRIPTION")) { cat("::error::run from the repository root\n"); quit(status=1L) }
files <- if (length(args)) args else c(
  "artifacts/multiverse/age_matched_results.csv",
  Sys.glob("artifacts/multiverse/age_matched_results_*.csv"),
  "artifacts/2sfca/agematched_panel/age_matched_panel.csv")
files <- unique(files[file.exists(files)])
if (!length(files)) { cat("no results artifacts present; nothing to check\n"); quit(status=0L) }

fail <- character(0); cells <- 0L
cat("supply conservation\n")
for (f in files) {
  d <- utils::read.csv(f, stringsAsFactors = FALSE)
  if (!all(c("n_supply_origins", "n_iso_origins") %in% names(d))) {
    cat("  ", basename(f), ": no origin columns, skipped\n", sep = ""); next
  }
  drop <- d$n_supply_origins - d$n_iso_origins
  cells <- cells + nrow(d)
  if (any(drop > 0, na.rm = TRUE)) {
    i <- which(drop > 0)
    lab <- if ("year" %in% names(d)) paste(d$year[i], d$subspec[i]) else d$subspec[i]
    fail <- c(fail, sprintf("%s: %d cell(s) dropped supply -- %s",
      basename(f), length(i),
      paste(sprintf("%s (%d of %d origins, %d lost)", lab, d$n_iso_origins[i],
                    d$n_supply_origins[i], drop[i]), collapse = "; ")))
  }
  if (any(drop < 0, na.rm = TRUE))
    fail <- c(fail, sprintf("%s: more isochrone origins than supply origins", basename(f)))
  cat("  ", basename(f), ": ", nrow(d), " cells, ",
      sum(drop > 0, na.rm = TRUE), " with dropped supply\n", sep = "")
}
cat("\n")
if (length(fail)) {
  message("FAIL: supply entered E2SFCA without a catchment:")
  for (x in fail) message("  - ", x)
  message("\n  Every origin must have a catchment. Supply with no catchment",
          "\n  contributes to nobody's access and silently deflates every mean;",
          "\n  this is the defect that put a local run 0.786% below the frozen analysis.")
  quit(status = 1L, save = "no")
}
cat(cells, " cells checked, no supply dropped\n", sep = "")
