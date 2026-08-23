#!/usr/bin/env Rscript
# Guard: the appendix's stated invariant is that every analysis number is
# COMPUTED from artifacts, not typed. Typed numbers silently go stale when the
# pipeline is re-run -- this has already happened twice.
#
# Rule: in PROSE (outside R chunks, inline `r ...`, and code spans), a decimal
# literal with >= 3 fractional digits is an analysis output and must be live.
# Integers, 1-2 decimal places (years, thresholds, "table 1.2") and anything
# inside the frozen manifest quotation are allowed.
src <- "manuscript/appendix_age_matched_denominators.Rmd"
if (!file.exists(src)) { cat("no appendix; skipped\n"); quit(status = 0) }
x <- readLines(src, warn = FALSE)

in_chunk <- FALSE
bad <- list()
for (i in seq_along(x)) {
  ln <- x[i]
  if (grepl("^```", ln)) { in_chunk <- !in_chunk; next }
  if (in_chunk) next
  ln <- gsub("`[^`]*`", "", ln)                    # inline code and `r ...`
  m <- regmatches(ln, gregexpr("[0-9]+\\.[0-9]{3,}", ln))[[1]]
  if (length(m)) bad[[length(bad) + 1L]] <- sprintf("  %s:%d  %s", src, i, paste(m, collapse = " "))
}
if (length(bad)) {
  cat("FAIL: typed analysis numbers in appendix prose (must be computed in a chunk):\n")
  cat(paste(unlist(bad), collapse = "\n"), "\n")
  quit(status = 1)
}
cat("appendix literal guard: no typed analysis numbers in prose\n")
