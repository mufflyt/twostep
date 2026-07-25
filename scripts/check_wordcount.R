#!/usr/bin/env Rscript
# ============================================================================
# Word-count QA for the E2SFCA manuscript.
#
# Counts the RENDERED main text (Introduction through Conclusion) and the
# abstract from the knitted HTML, so the count matches what a journal counts:
# body prose only, excluding the title page, tables, figure captions, code,
# the reference list, and the Supplemental Digital Content appendices.
#
# Usage:
#   Rscript render.R            # produce the HTML first
#   Rscript scripts/check_wordcount.R [path/to/manuscript.html]
#
# Formalized from a session tool so the paper's word count stays auditable.
# ============================================================================
suppressWarnings(suppressMessages(library(xml2)))

args <- commandArgs(trailingOnly = TRUE)
html <- if (length(args) >= 1) args[[1]] else
  here::here("manuscript", "e2sfca_accessibility_manuscript.html")
if (!file.exists(html))
  stop(sprintf("Rendered HTML not found: %s\nRun `Rscript render.R` first.", html),
       call. = FALSE)

h <- read_html(html)
# Drop everything a journal word count excludes.
for (xp in c('//div[@id="TOC"]', '//div[@id="refs"]', '//nav', '//table',
             '//p[contains(@class,"caption")]', '//caption', '//pre', '//code',
             '//style', '//script')) {
  n <- xml_find_all(h, xp); if (length(n)) xml_remove(n)
}
norm <- function(x) trimws(gsub("[[:space:]]+", " ", x))
wc <- function(x) { x <- norm(paste(x, collapse = " "))
  if (!nzchar(x)) 0L else length(strsplit(x, " ")[[1]]) }

# Top-level section = last h1/h2 whose text starts with a KNOWN name; h3 do NOT
# reset it. Everything at/after "Supplemental Digital Content" is supplement.
KNOWN <- c("Title Page", "Abstract", "Introduction", "Materials and Methods",
           "Results", "Discussion", "Conclusion", "Supplemental Digital Content",
           "Reproducibility record", "References")
MAIN  <- c("Introduction", "Materials and Methods", "Results", "Discussion", "Conclusion")

sec <- NA_character_
bucket <- setNames(vector("list", length(KNOWN)), KNOWN)
for (nd in xml_find_all(h, "//h1 | //h2 | //h3 | //p")) {
  nm <- xml_name(nd); tx <- norm(xml_text(nd))
  if (nm %in% c("h1", "h2")) {
    hit <- KNOWN[vapply(KNOWN, function(k) startsWith(tx, k), logical(1))]
    if (length(hit)) sec <- hit[1]
  } else if (nm == "p" && !is.na(sec)) {
    bucket[[sec]] <- c(bucket[[sec]], tx)
  }
}

cat(sprintf("Abstract:                      %s words\n",
            format(wc(bucket[["Abstract"]]), big.mark = ",")))
main_w <- 0L
for (s in MAIN) {
  w <- wc(bucket[[s]]); main_w <- main_w + w
  cat(sprintf("  %-26s %s words\n", paste0(s, ":"), format(w, big.mark = ",")))
}
cat(sprintf("MAIN TEXT (Intro->Conclusion): %s words\n", format(main_w, big.mark = ",")))
cat(sprintf("Supplement (all appendices):   %s words\n",
            format(wc(bucket[["Supplemental Digital Content"]]), big.mark = ",")))
cat("Excluded: title page, tables, figure captions, code, references.\n")
