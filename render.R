#!/usr/bin/env Rscript
# One-command render of the E2SFCA accessibility manuscript.
# Usage:  Rscript render.R
# Output: manuscript/e2sfca_accessibility_manuscript.html (self-contained)
#
# The manuscript reads only the frozen artifacts shipped in this repo (see
# scripts/manuscript_e2sfca_values.R and artifacts/2sfca/**), so no upstream
# pipeline or network access is required.

if (!requireNamespace("rmarkdown", quietly = TRUE))
  stop("Install rmarkdown: install.packages('rmarkdown')", call. = FALSE)

rmd <- here::here("manuscript", "e2sfca_accessibility_manuscript.Rmd")
rmarkdown::render(
  rmd,
  output_file = "e2sfca_accessibility_manuscript.html",
  quiet = FALSE
)

# No dashes anywhere: the citation style renders page ranges and collapsed
# citation-number ranges with en-dashes regardless of the (hyphenated) bib. Replace
# any en-dash or em-dash in the final HTML with a hyphen so the manuscript contains
# neither. The Rmd prose itself is already dash-free.
out <- here::here("manuscript", "e2sfca_accessibility_manuscript.html")
h <- paste(readLines(out, warn = FALSE), collapse = "\n")
h <- gsub("–", "-", h)   # en-dash
h <- gsub("—", "-", h)   # em-dash (safety; source has none)
writeLines(h, out)

cat("\nRendered:", out, "\n")
