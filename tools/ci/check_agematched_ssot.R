#!/usr/bin/env Rscript
# =============================================================================
# One artifact: every live age-matched consumer must read the PANEL
# =============================================================================
# artifacts/2sfca/agematched_panel/age_matched_panel.csv is the sole source for
# every age-matched number that reaches the manuscript, the appendix or the SDC
# figure. This fails if a live consumer references the standalone 2020 file
# instead.
#
# Why it is a gate and not a convention: the standalone file and the panel's 2020
# rows are byte-identical today, so a consumer pointed at the wrong one produces
# correct numbers and no symptom. It would stay wrong until the two diverge --
# which is exactly what happened once already, when a locally computed 2020 sat
# at that path while provenance named the EC2 one.
#
# The _precorrection/ copy is exempt BY DESIGN: the appendix documents the
# historical supply-loss defect and needs the contaminated numbers to do it.
# Computing that paragraph from the corrected artifact made it report a 0.000%
# shortfall from 0 lost origins.
if (!file.exists("DESCRIPTION")) { cat("::error::run from the repository root\n"); quit(status=1L) }

PANEL   <- "artifacts/2sfca/agematched_panel/age_matched_panel.csv"
STANDIN <- "artifacts/multiverse/age_matched_results.csv"
CONSUMERS <- c("manuscript/e2sfca_accessibility_manuscript.Rmd",
               "manuscript/appendix_age_matched_denominators.Rmd",
               "tools/multiverse/plot_age_matched.R")

fail <- character(0)
cat("age-matched SSOT\n")
for (f in CONSUMERS) {
  if (!file.exists(f)) { fail <- c(fail, paste0("consumer missing: ", f)); next }
  x <- readLines(f, warn = FALSE)
  # a reference to the standalone path that is NOT the _precorrection copy and
  # NOT inside a comment
  hits <- which(grepl(STANDIN, x, fixed = TRUE) &
                !grepl("_precorrection", x, fixed = TRUE) &
                !grepl("^\\s*#", x))
  if (length(hits))
    fail <- c(fail, sprintf("%s:%s references the standalone 2020 results instead of the panel",
                            f, paste(hits, collapse = ",")))
  # Match by FILENAME, not literal path: the manuscript builds its path from
  # here::here() components, so a literal-string search wrongly reported it as
  # not reading the panel.
  if (!any(grepl("age_matched_panel.csv", x, fixed = TRUE)))
    fail <- c(fail, sprintf("%s never references the panel", f))
  cat("  ", f, ": ", if (any(grepl("age_matched_panel.csv", x, fixed = TRUE))) "reads the panel" else "DOES NOT read the panel", "\n", sep = "")
}
if (!file.exists(PANEL)) fail <- c(fail, paste0("the panel itself is absent: ", PANEL))

cat("\n")
if (length(fail)) {
  message("FAIL: the age-matched chain does not have a single source:")
  for (x in fail) message("  - ", x)
  message("\n  Every live consumer must read ", PANEL, " and must not fall back",
          "\n  to the standalone 2020 file. Fail-open provenance lets the document",
          "\n  and the correction diff cite different artifacts without saying so.")
  quit(status = 1L, save = "no")
}
cat("every live consumer reads the panel, none falls back\n")
