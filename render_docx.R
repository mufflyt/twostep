#!/usr/bin/env Rscript
# Word (.docx) version of the manuscript, converted from the rendered (dash-free)
# HTML. Run `Rscript render.R` first to produce the HTML.
html <- here::here("manuscript", "e2sfca_accessibility_manuscript.html")
docx <- here::here("manuscript", "e2sfca_accessibility_manuscript.docx")
if (!file.exists(html)) stop("Render the HTML first: Rscript render.R", call. = FALSE)
rmarkdown::pandoc_convert(html, to = "docx", output = docx)
cat("Wrote", docx, "\n")
