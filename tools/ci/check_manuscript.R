#!/usr/bin/env Rscript
# =============================================================================
# Manuscript semantic QA. Does the rendered paper actually say something valid?
# =============================================================================
# rmarkdown::render() exiting 0 means the code ran, not that the paper is
# correct. A manuscript can render perfectly and still print "NA" where an
# estimate belongs, carry an unresolved citation, or embed a developer's home
# directory. Nothing in this repository checked the rendered artifact until now.
#
# The file is a ~10MB SELF-CONTAINED html: almost all of it is base64-embedded
# fonts and figures. Grepping it raw would drown in false positives, so the
# embedded assets, scripts and styles are stripped first and only the visible
# prose is scanned.
#
# Usage: Rscript tools/ci/check_manuscript.R [path-to-html]

args <- commandArgs(trailingOnly = TRUE)
html_path <- if (length(args)) args[1] else
  file.path("manuscript", "e2sfca_accessibility_manuscript.html")

fails <- character(0)
bad <- function(...) fails <<- c(fails, paste0(...))

if (!file.exists(html_path)) {
  message("FAIL: no rendered manuscript at ", html_path,
          "\n  Run: Rscript render.R")
  quit(status = 1L, save = "no")
}

size_mb <- file.size(html_path) / 1024^2
cat(sprintf("rendered manuscript: %s (%.1f MB)\n", html_path, size_mb))
# A render that silently produced a stub is worse than one that failed.
if (file.size(html_path) < 200 * 1024)
  bad(sprintf("rendered file is only %.0f KB -- suspiciously small for this manuscript",
              file.size(html_path) / 1024))

raw <- paste(readLines(html_path, warn = FALSE), collapse = "\n")

# --- strip everything that is not visible prose ------------------------------
txt <- raw
txt <- gsub("data:[^;\"')]+;base64,[A-Za-z0-9+/=\\s]+", " ", txt, perl = TRUE)
txt <- gsub("(?s)<script.*?</script>", " ", txt, perl = TRUE)
txt <- gsub("(?s)<style.*?</style>",  " ", txt, perl = TRUE)
txt <- gsub("(?s)<!--.*?-->",         " ", txt, perl = TRUE)
txt <- gsub("<[^>]*>", " ", txt, perl = TRUE)          # drop tags
txt <- gsub("&[a-zA-Z#0-9]+;", " ", txt, perl = TRUE)  # entities
cat(sprintf("visible prose: %.0f KB of %.0f KB total\n",
            nchar(txt) / 1024, nchar(raw) / 1024))

lines <- unlist(strsplit(txt, "\n", fixed = TRUE))
report <- function(label, pattern, perl = TRUE, limit = 4) {
  hit <- grep(pattern, lines, perl = perl, value = TRUE)
  hit <- trimws(gsub("\\s+", " ", hit))
  hit <- hit[nzchar(hit)]
  if (length(hit)) {
    bad(sprintf("%s -- %d occurrence(s)", label, length(hit)))
    for (h in utils::head(hit, limit))
      message("      ", substr(h, 1, 150))
  }
  length(hit)
}

cat("\nscanning visible prose:\n")
checks <- c(
  # A bare NA/NaN/Inf where a number belongs is the classic silent failure.
  "missing values (NA)"        = report("missing value NA in prose", "(?<![A-Za-z0-9_])NA(?![A-Za-z0-9_])"),
  "not-a-number (NaN)"         = report("NaN in prose", "(?<![A-Za-z0-9_])NaN(?![A-Za-z0-9_])"),
  "infinity (Inf)"             = report("Inf in prose", "(?<![A-Za-z0-9_.])-?Inf(?![A-Za-z0-9_])"),
  # Evaluation errors that knitr rendered rather than raised.
  "R errors"                   = report("R error text in prose",
                                        "Error in |object '[^']*' not found|could not find function|subscript out of bounds"),
  # Someone's machine leaking into the paper.
  "absolute paths"             = report("absolute local path", "(/Users/[A-Za-z0-9._-]+|/home/[a-z][A-Za-z0-9._-]*|[A-Z]:\\\\\\\\)"),
  # Citation and cross-reference machinery that did not resolve.
  "unresolved citations"       = report("unresolved citation", "\\[@[A-Za-z0-9_:-]+\\]|\\(\\?\\?\\?\\)|\\\\@ref\\("),
  "unrendered chunk options"   = report("unrendered knitr option", "```\\{r|\\{r [a-z]")
)

# --- year-consistency gates --------------------------------------------------
plain <- trimws(gsub("\\s+", " ", txt))
capture_year <- function(label, pattern) {
  m <- regexec(pattern, plain, perl = TRUE)
  hit <- regmatches(plain, m)[[1]]
  if (!length(hit)) {
    bad("could not find ", label, " year in rendered prose")
    return(NA_integer_)
  }
  as.integer(hit[2])
}

fig1_year <- capture_year(
  "Figure 1",
  "Figure 1\\. Potential spatial accessibility to each obstetrics-gynecology subspecialty, ([0-9]{4}),")
table1_year <- capture_year(
  "Table 1",
  "Table 1\\. Active Workforce and Standardized Supply per Population by Obstetrics-Gynecology Subspecialty, ([0-9]{4})")
if (!is.na(fig1_year) && !is.na(table1_year) && fig1_year != table1_year) {
  bad(sprintf("Figure 1 year (%d) and Table 1 year (%d) disagree",
              fig1_year, table1_year))
}

# --- structural sanity -------------------------------------------------------
cat("\nstructure:\n")
n_img <- lengths(regmatches(raw, gregexpr("<img ", raw, fixed = TRUE)))
n_tab <- lengths(regmatches(raw, gregexpr("<table", raw, fixed = TRUE)))
n_b64 <- lengths(regmatches(raw, gregexpr("base64,", raw, fixed = TRUE)))
cat(sprintf("  images: %d   tables: %d   embedded assets: %d\n", n_img, n_tab, n_b64))
if (n_img == 0L) bad("no images in the rendered manuscript")
if (n_tab == 0L) bad("no tables in the rendered manuscript")

# An <img> with no src, or one still pointing at a local file rather than being
# embedded, means a figure silently did not make it in.
broken <- lengths(regmatches(raw, gregexpr('<img[^>]*src="(?!data:)[^"]*"', raw, perl = TRUE)))
if (broken > 0L) bad(sprintf("%d image(s) not embedded (src is not a data: URI)", broken))

if (length(fails)) {
  message("\nFAIL: manuscript semantic QA found ", length(fails), " problem(s):")
  for (f in fails) message("  - ", f)
  quit(status = 1L, save = "no")
}
# ---- the DOCX must not lag the HTML -----------------------------------------
# They are two renderings of ONE paper. When they disagree, the reader who
# opened Word gets a different manuscript from the reader who opened the
# browser -- and has no way to know. Observed: the DOCX sat six days behind
# while the abstract was corrected, so it still asserted "Disparities held
# across all sensitivity specifications", a claim the specification curve had
# falsified.
#
# Compared by mtime rather than content because the two formats legitimately
# differ byte-for-byte; what must hold is that the DOCX was produced from the
# CURRENT HTML.
.docx <- sub("[.]html$", ".docx", html_path)
if (file.exists(.docx)) {
  .lag <- as.numeric(difftime(file.mtime(html_path), file.mtime(.docx), units = "secs"))
  cat("\ndocx freshness:\n")
  cat("  html:", format(file.mtime(html_path), "%Y-%m-%d %H:%M:%S"), "\n")
  cat("  docx:", format(file.mtime(.docx), "%Y-%m-%d %H:%M:%S"), "\n")
  if (.lag > 1) {
    message("FAIL: the DOCX is ", round(.lag / 3600, 1), " hours older than the HTML.")
    message("  Two renderings of one paper that disagree is a reader-facing defect.")
    message("  Fix: Rscript render.R  (which now produces both).")
    quit(status = 1L, save = "no")
  }
  cat("  docx is current with the html\n")
} else {
  cat("\ndocx freshness: no DOCX present (skipped)\n")
}

cat("\nmanuscript semantic QA passed\n")
