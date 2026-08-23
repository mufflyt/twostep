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

# ---- artifact integrity gate: verify every consumed artifact's sha256 BEFORE
# rendering, so a swapped/corrupted/wrong-source input fails loud rather than
# rendering silently against the wrong data. (Provenance-guard hardening.)
sums <- here::here("SHA256SUMS.txt")
if (file.exists(sums)) {
  chk <- suppressWarnings(system2("shasum", c("-a", "256", "-c", shQuote(sums)),
                                  stdout = TRUE, stderr = TRUE))
  if (!is.null(attr(chk, "status")) && attr(chk, "status") != 0L)
    stop("SHA256SUMS verification FAILED before render; an input artifact does not ",
         "match its recorded checksum:\n", paste(chk, collapse = "\n"), call. = FALSE)
  message("SHA256SUMS: ", sum(grepl(": OK$", chk)), " artifacts verified OK.")
} else {
  warning("SHA256SUMS.txt not found; skipping artifact integrity gate.", call. = FALSE)
}

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

# ---- DOCX, chained rather than left to a separate invocation ----------------
# The two outputs used to be produced by two scripts, and only the release
# workflow ran both. Anyone rendering locally got HTML only, so the DOCX went
# stale silently -- it sat six days behind the HTML while the abstract was
# corrected, meaning the Word copy still asserted a claim the specification
# curve had falsified. Two artifacts of the same paper disagreeing about what
# the paper says is exactly the drift this project gates against everywhere
# else.
#
# The conversion reads the HTML written above, so it cannot be out of date with
# respect to it. Set E2SFCA_SKIP_DOCX=1 to render HTML alone.
if (!nzchar(Sys.getenv("E2SFCA_SKIP_DOCX"))) {
  docx <- here::here("manuscript", "e2sfca_accessibility_manuscript.docx")
  rmarkdown::pandoc_convert(out, to = "docx", output = docx)
  cat("Rendered:", docx, "\n")
  # Belt and braces: assert the DOCX is not older than the HTML it came from.
  if (file.mtime(docx) < file.mtime(out))
    stop("render.R: the DOCX is older than the HTML it was just converted from.",
         call. = FALSE)
}
