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
cat("\nmanuscript semantic QA passed\n")
