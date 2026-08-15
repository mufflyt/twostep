#!/usr/bin/env Rscript
# Syntax gate for EVERY R file in the repo, not just the package.
# R CMD check only ever parses what ships in the tarball; scripts/, tests/,
# tools/ and inst/ are build-excluded, so a syntax error there reaches main
# unnoticed. Zero dependencies, so this runs before anything is installed.
dirs <- c("R", "scripts", "tests", "inst", "tools")
files <- unlist(lapply(dirs, function(d)
  if (dir.exists(d)) list.files(d, pattern = "[.][Rr]$", full.names = TRUE, recursive = TRUE)))
files <- c(files, Filter(file.exists, c("render.R", "render_docx.R", ".Rprofile")))

bad <- character(0)
for (f in files) {
  tryCatch(parse(f), error = function(e)
    bad <<- c(bad, sprintf("  %s\n      %s", f, conditionMessage(e))))
}
cat(sprintf("parsed %d R files across %s\n", length(files), paste(dirs, collapse = "/")))
if (length(bad)) {
  message("FAIL: ", length(bad), " file(s) do not parse:\n", paste(bad, collapse = "\n"))
  quit(status = 1L, save = "no")
}
cat("all files parse\n")

# Non-ASCII outside comments, PACKAGE CODE ONLY. R CMD check enforces this for
# R/ as a portability rule; running it here too fails in seconds instead of after
# a full check. Deliberately NOT applied repo-wide: scripts/ and inst/ print
# Unicode status glyphs to the console, and tests/test-ssot-figure-dashes.R exists
# precisely to assert on non-ASCII dashes, so a repo-wide rule would fight it.
pkg_files <- list.files("R", pattern = "[.][Rr]$", full.names = TRUE, recursive = TRUE)
offenders <- list()
for (f in pkg_files) {
  lines <- readLines(f, warn = FALSE)
  idx <- which(!grepl("^\\s*#", lines) & grepl("[^\x01-\x7F]", lines))
  if (length(idx)) offenders[[f]] <- idx
}
if (length(offenders)) {
  message("FAIL: non-ASCII in package code (use \\uXXXX escapes):")
  for (f in names(offenders))
    message(sprintf("  %s: line(s) %s", f, paste(head(offenders[[f]], 5), collapse = ", ")))
  quit(status = 1L, save = "no")
}
cat(sprintf("no non-ASCII outside comments in %d package files\n", length(pkg_files)))
