#!/usr/bin/env Rscript
# One-command render of the E2SFCA accessibility manuscript.
# Usage:  Rscript render.R
# Output: manuscript/e2sfca_accessibility_manuscript.html (self-contained)
#
# The manuscript reads only the frozen artifacts shipped in this repo (see
# scripts/manuscript_e2sfca_values.R and artifacts/2sfca/**), so no upstream
# pipeline or network access is required for its own results.
#
# ONE external SSOT dependency: the FPMRS/urogynecology reconciling footnote pulls
# the 2023 URPS workforce count live via mufflyaccess::urps_count() (contract
# 3.0.0), so the mufflyaccess package (>= 0.10.0) must be installed. It is pinned
# in renv.lock + DESCRIPTION Suggests/Remotes, so `renv::restore()` provides it;
# the Rmd setup chunk fails loud if it is missing. No network is needed at render
# time once the package is installed.

if (!requireNamespace("rmarkdown", quietly = TRUE))
  stop("Install rmarkdown: install.packages('rmarkdown')", call. = FALSE)
if (!requireNamespace("mufflyaccess", quietly = TRUE))
  stop("Install mufflyaccess (>= 0.10.0): renv::restore() or ",
       "remotes::install_github('mufflyt/mufflyaccess')", call. = FALSE)

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
