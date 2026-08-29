#!/usr/bin/env Rscript
# Guard the manuscript-facing age-matched chain against artifact drift.
#
# The corrected 11-year panel is the only live results source. The archived
# contaminated 2020 file is allowed only for the historical supply-loss example.

panel_path <- paste0(
  "artifacts/2sfca/agematched_panel/",
  "age_matched_panel.csv"
)
legacy_path <- "artifacts/multiverse/age_matched_results.csv"
archive_path <- paste0(
  "artifacts/multiverse/_precorrection/",
  "age_matched_results_CONTAMINATED_2020.csv"
)
panel_hash <- paste0(
  "485df006e8156a5f15add4ad6173e752d320c6d21b2f33f2e1f7e4e4cb025064",
  "  ", panel_path
)

consumer_paths <- c(
  "manuscript/e2sfca_accessibility_manuscript.Rmd",
  "manuscript/appendix_age_matched_denominators.Rmd",
  "tools/multiverse/plot_age_matched.R",
  "tools/ci/render_appendix.sh"
)

failures <- character()
read_text <- function(path) {
  if (!file.exists(path)) {
    failures <<- c(failures, paste("missing file:", path))
    return("")
  }
  paste(readLines(path, warn = FALSE), collapse = "\n")
}

require_text <- function(path, needle, label) {
  txt <- read_text(path)
  if (!grepl(needle, txt, fixed = TRUE)) {
    failures <<- c(
      failures,
      paste0(path, ": missing ", label, ": ", needle)
    )
  }
}

forbid_text <- function(path, needle, label) {
  txt <- read_text(path)
  if (grepl(needle, txt, fixed = TRUE)) {
    failures <<- c(
      failures,
      paste0(path, ": forbidden ", label, ": ", needle)
    )
  }
}

for (path in consumer_paths) {
  require_text(path, panel_path, "corrected-panel SSOT")
  forbid_text(path, legacy_path, "standalone-results fallback")
}

appendix_path <- "manuscript/appendix_age_matched_denominators.Rmd"
require_text(
  appendix_path,
  archive_path,
  "archived contaminated artifact for historical example"
)
require_text(
  appendix_path,
  "100 * (.ref - .got) / .ref",
  "positive historical shortfall calculation"
)
forbid_text(
  appendix_path,
  "affects both regimes equally and cancels in the contrast",
  "supply-loss cancellation overclaim"
)

plot_path <- "tools/multiverse/plot_age_matched.R"
require_text(
  plot_path,
  "B. Disparity contrasts persist\\nunder age matching",
  "corrected disparity-panel title"
)
forbid_text(
  plot_path,
  "B. Disparity contrasts are\\nunchanged by the denominator",
  "literal invariance claim"
)

require_text(
  "SHA256SUMS.txt",
  panel_hash,
  "corrected-panel SHA-256 pin"
)

if (length(failures)) {
  cat("FAIL: age-matched manuscript SSOT guard\n")
  cat(paste0("  - ", failures, collapse = "\n"), "\n")
  quit(status = 1L)
}

cat("age-matched manuscript SSOT guard: PASS\n")
