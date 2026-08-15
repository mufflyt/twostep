#!/usr/bin/env Rscript
# Documentation freshness. Regenerates with roxygen2 and fails if anything moves.
#
# This is the guard for the ORIGINAL bug in this repo: NAMESPACE was maintained
# by hand, drifted from the @export tags, and three tagged exports silently never
# shipped. Committed man/ and NAMESPACE must be exactly what the sources produce.
if (!requireNamespace("roxygen2", quietly = TRUE))
  stop("check_docs_fresh.R needs roxygen2", call. = FALSE)

before <- system2("git", c("status", "--porcelain", "man", "NAMESPACE"), stdout = TRUE)
if (length(before))
  message("NOTE: man/ or NAMESPACE was already dirty before regeneration:\n",
          paste(before, collapse = "\n"))

roxygen2::roxygenise(".")

diff <- system2("git", c("status", "--porcelain", "man", "NAMESPACE"), stdout = TRUE)
if (length(diff)) {
  message("FAIL: regenerating docs changed committed files. Run:\n",
          "  Rscript -e 'roxygen2::roxygenise()'\nand commit the result.\n")
  message(paste(diff, collapse = "\n"))
  system2("git", c("--no-pager", "diff", "--", "man", "NAMESPACE"))
  quit(status = 1L, save = "no")
}
cat("man/ and NAMESPACE are in sync with the sources\n")
