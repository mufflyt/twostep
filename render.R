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
cat("\nRendered:", sub("[.]Rmd$", ".html", rmd), "\n")
