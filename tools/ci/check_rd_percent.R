#!/usr/bin/env Rscript
# =============================================================================
# `%` in roxygen prose must be escaped -- it is the Rd comment character
# =============================================================================
# In Rd format `%` begins a comment, so an unescaped one discards the rest of
# its line. Inside \arguments{} that swallows the closing brace and the whole
# file becomes unparseable; elsewhere it silently truncates documentation text.
#
# This has now happened TWICE. First from a ported commit ("0.05 (5%)"), which
# produced 2 WARNINGs across every R CMD check platform. Then from me, in the
# very @param documenting the fix for something else -- "observed at 0.786%" --
# two days after fixing the first one. Knowing about a trap is not the same as
# having a gate for it.
#
# roxygen2 escapes % inside \examples{} but NOT in prose, which is why the
# dangerous-looking case is handled and the ordinary one is not.
#
# Usage: Rscript tools/ci/check_rd_percent.R
root <- tryCatch(rprojroot::find_root(rprojroot::has_file("DESCRIPTION")),
                 error = function(e) ".")
setwd(root)
bad <- list()

for (f in list.files("R", pattern = "[.]R$", full.names = TRUE)) {
  ln <- readLines(f, warn = FALSE)
  idx <- grep("^\\s*#'", ln)
  # roxygen2 DOES escape % inside \examples{} -- "%in%" is emitted as "\%in\%" --
  # so example lines must not be flagged here. Only prose is unhandled. Track
  # which roxygen block we are inside; @examples runs until the next @tag.
  in_examples <- FALSE
  for (i in idx) {
    x <- ln[i]
    if (grepl("^\\s*#'\\s*@examples", x)) { in_examples <- TRUE; next }
    if (grepl("^\\s*#'\\s*@[a-zA-Z]+", x)) in_examples <- FALSE
    if (in_examples) next
    if (grepl("^\\s*#'\\s*@(importFrom|import|rawNamespace|export)", x)) next  # tags, not prose
    stripped <- gsub("\\\\%", "", x)          # remove already-escaped
    stripped <- gsub("%[a-zA-Z><=!]+%", "", stripped)  # infix operators: %in% %>% %||%
    stripped <- gsub("%[sdfgex]", "", stripped)        # sprintf placeholders
    stripped <- gsub("%%", "", stripped)
    if (grepl("%", stripped))
      bad[[length(bad) + 1L]] <- sprintf("%s:%d: %s", f, i, trimws(x))
  }
}

# Also check the GENERATED Rd, which is what R actually parses.
for (f in list.files("man", pattern = "[.]Rd$", full.names = TRUE)) {
  ln <- readLines(f, warn = FALSE)
  for (i in seq_along(ln)) {
    x <- ln[i]
    if (startsWith(trimws(x), "%")) next      # a genuine Rd comment line
    if (grepl("%", gsub("\\\\%", "", x)))
      bad[[length(bad) + 1L]] <- sprintf("%s:%d: %s", f, i, trimws(x))
  }
}

cat("Rd percent-escaping audit\n")
cat("  R/ files scanned:   ", length(list.files("R", pattern = "[.]R$")), "\n", sep = "")
cat("  man/ files scanned: ", length(list.files("man", pattern = "[.]Rd$")), "\n", sep = "")
if (length(bad)) {
  message("\nFAIL: ", length(bad), " unescaped '%' in documentation:")
  for (b in bad) message("  - ", b)
  message("\n  In Rd, % starts a comment: everything after it on that line is")
  message("  discarded. Inside \\arguments{} it eats the closing brace and breaks")
  message("  the file; elsewhere it silently truncates the rendered text.")
  message("  Write \\% in the roxygen source, then regenerate with roxygenise().")
  quit(status = 1L, save = "no")
}
cat("every '%' in documentation is escaped\n")
